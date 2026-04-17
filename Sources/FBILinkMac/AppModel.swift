import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class AppModel {
    var consoles: [Console] = []
    var files: [TransferFile] = []
    var isServing = false
    var logLines: [String] = []
    var serverPort: UInt16?
    var lanAddress: String?
    var aggregateStats: TransferStats = .zero
    var perFileStats: [TransferFile.ID: TransferStats] = [:]

    private let server = FileServer()
    private let sender = ConsoleSender()
    private var pumpTasks: [Task<Void, Never>] = []
    private var aggregateTracker = SpeedTracker()
    private var perFileTrackers: [TransferFile.ID: SpeedTracker] = [:]
    private let powerAssertion = PowerAssertion()
    // Under App Sandbox, reading files granted via .fileImporter / drag-drop
    // requires holding their security scope. We start the scope when the URL
    // is added and rely on process exit to release it.
    private var scopedURLs: [URL] = []

    init() {
        self.lanAddress = LANAddress.primaryIPv4()
    }

    // MARK: - File input

    func addFiles(_ urls: [URL]) {
        for url in urls where url.startAccessingSecurityScopedResource() {
            scopedURLs.append(url)
        }
        let expanded = expandDirectories(urls)
        for url in expanded {
            guard let file = TransferFile.fromLocal(url) else { continue }
            files.append(file)
        }
    }

    func addRemoteURL(_ url: URL) {
        files.append(.fromRemote(url))
    }

    func removeFile(_ id: TransferFile.ID) {
        files.removeAll { $0.id == id }
    }

    func clearFiles() { files.removeAll() }

    private func expandDirectories(_ urls: [URL]) -> [URL] {
        let fm = FileManager.default
        let exts: Set<String> = ["cia", "tik"]
        var out: [URL] = []
        for url in urls {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { continue }
                for case let child as URL in enumerator where exts.contains(child.pathExtension.lowercased()) {
                    out.append(child)
                }
            } else {
                out.append(url)
            }
        }
        return out
    }

    // MARK: - Consoles

    func addConsole(host: String, port: UInt16 = 5000, name: String? = nil) {
        consoles.append(Console(host: host, port: port, name: name))
    }

    func removeConsole(_ id: Console.ID) {
        consoles.removeAll { $0.id == id }
    }

    // MARK: - Serving

    func start() {
        guard !isServing else { return }
        guard !files.isEmpty else { log("Add a CIA or URL first."); return }
        guard !consoles.isEmpty else { log("Add a 3DS by IP first."); return }

        isServing = true
        powerAssertion.acquire(reason: "FBILinkMac is transferring files to a 3DS")
        aggregateTracker.reset()
        perFileTrackers.removeAll()
        perFileStats.removeAll()
        aggregateStats = .zero
        for idx in files.indices { files[idx].bytesSent = 0 }
        pumpTasks.forEach { $0.cancel() }
        pumpTasks.removeAll()

        let filesSnapshot = files
        Task { @MainActor in
            do {
                try await server.setFiles(filesSnapshot)
                _ = try await server.start()
            } catch {
                log("Server start failed: \(error.localizedDescription)")
                isServing = false
            }
        }
        pumpTasks.append(Task { @MainActor in await self.pumpServerEvents() })
        pumpTasks.append(Task { @MainActor in await self.pumpSenderEvents() })
    }

    func stop() {
        Task { @MainActor in
            await server.stop()
            await sender.cancelAll()
        }
        isServing = false
        serverPort = nil
        powerAssertion.release()
    }

    // MARK: - Event pumps

    private func pumpServerEvents() async {
        let stream = await server.events
        for await event in stream {
            switch event {
            case .started(let port):
                serverPort = port
                log("Server listening on port \(port).")
                await dispatchConsoles(port: port)
            case .requestStarted(_, let host):
                log("Serving request from \(host).")
            case .progress(let id, let sent, let total):
                if let idx = files.firstIndex(where: { $0.id == id }) {
                    files[idx].bytesSent = sent
                    if files[idx].byteCount == 0 { files[idx].byteCount = total }
                }
                updateStats(fileID: id, bytesSent: sent, total: total)
            case .requestFinished(let id):
                if let f = files.first(where: { $0.id == id }) {
                    log("Finished serving \(f.displayName).")
                }
                markFileFinished(id)
            case .log(let message):
                log(message)
            case .error(let message):
                log("Error: \(message)")
            }
        }
    }

    private func pumpSenderEvents() async {
        let stream = await sender.events
        for await event in stream {
            switch event {
            case .connecting(let id):
                updateConsole(id) { $0.status = .connecting }
            case .connected(let id):
                updateConsole(id) { $0.status = .sending }
                if let c = consoles.first(where: { $0.id == id }) { log("Connected to \(c.displayName).") }
            case .finished(let id):
                updateConsole(id) { $0.status = .completed }
                if let c = consoles.first(where: { $0.id == id }) { log("\(c.displayName) finished installing.") }
                checkAllDone()
            case .failed(let id, let message):
                updateConsole(id) { $0.status = .failed(message) }
                log("Send to console failed: \(message)")
                checkAllDone()
            }
        }
    }

    private func updateConsole(_ id: Console.ID, _ mutate: (inout Console) -> Void) {
        guard let idx = consoles.firstIndex(where: { $0.id == id }) else { return }
        mutate(&consoles[idx])
    }

    // MARK: - Stats

    private func updateStats(fileID: TransferFile.ID, bytesSent: Int64, total: Int64) {
        var tracker = perFileTrackers[fileID] ?? SpeedTracker()
        tracker.record(totalBytes: bytesSent)
        perFileTrackers[fileID] = tracker
        perFileStats[fileID] = TransferStats(
            bytesSent: bytesSent,
            totalBytes: total,
            bytesPerSecond: tracker.bytesPerSecond,
            isActive: bytesSent < total
        )
        recomputeAggregate()
    }

    private func markFileFinished(_ id: TransferFile.ID) {
        if var stats = perFileStats[id] {
            stats.isActive = false
            stats.bytesPerSecond = 0
            perFileStats[id] = stats
        }
        perFileTrackers[id]?.reset()
        recomputeAggregate()
    }

    private func recomputeAggregate() {
        let totalSent = files.reduce(Int64(0)) { $0 + $1.bytesSent }
        let totalBytes = files.reduce(Int64(0)) { $0 + max($1.byteCount, $1.bytesSent) }
        aggregateTracker.record(totalBytes: totalSent)
        let anyActive = perFileStats.values.contains { $0.isActive }
        aggregateStats = TransferStats(
            bytesSent: totalSent,
            totalBytes: totalBytes,
            bytesPerSecond: anyActive ? aggregateTracker.bytesPerSecond : 0,
            isActive: anyActive
        )
    }

    // MARK: - Discovery

    func discoverConsoles() {
        Task { await performDiscovery() }
    }

    private func performDiscovery() async {
        if let ip = lanAddress {
            log("Scanning local subnet to warm ARP cache…")
            await Task.detached(priority: .utility) {
                await SubnetSweep.sweep(from: ip)
            }.value
        }
        let found = ARPDiscovery.findNintendoConsoles()
        let existing = Set(consoles.map(\.host))
        var added = 0
        for entry in found where !existing.contains(entry.ip) {
            addConsole(host: entry.ip, name: "3DS at \(entry.ip)")
            log("Auto-detected 3DS at \(entry.ip) (MAC \(entry.mac)).")
            added += 1
        }
        if found.isEmpty {
            log("No 3DS found in ARP table. Open FBI's Receive URLs screen on your 3DS and try again.")
        } else if added == 0 {
            log("Auto-discovery found \(found.count) 3DS, all already in your console list.")
        }
    }

    private func dispatchConsoles(port: UInt16) async {
        guard let hostIP = lanAddress else {
            log("Could not determine this Mac's LAN address.")
            stop(); return
        }
        let urls: [URL] = files.compactMap { file in
            switch file.source {
            case .localFile:
                // servedPath is already percent-encoded; join textually to avoid double encoding.
                return URL(string: "http://\(hostIP):\(port)\(file.servedPath)")
            case .remoteURL(let url):
                return url
            }
        }
        for console in consoles {
            await sender.send(to: console, urls: urls)
        }
    }

    private func checkAllDone() {
        let unfinished = consoles.contains { console in
            switch console.status {
            case .idle, .connecting, .sending: return true
            case .completed, .failed: return false
            }
        }
        if !unfinished { stop() }
    }

    func log(_ message: String) {
        let stamp = Date().formatted(date: .omitted, time: .standard)
        logLines.append("[\(stamp)] \(message)")
        if logLines.count > 500 { logLines.removeFirst(logLines.count - 500) }
    }
}
