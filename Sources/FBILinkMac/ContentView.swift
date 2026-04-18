import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @State private var showAddConsole = false
    @State private var showAddURL = false
    @State private var showFileImporter = false

    private static let projectURL = URL(string: "https://github.com/KingHavok/fbi-link-mac")!

    var body: some View {
        NavigationSplitView {
            ConsoleSidebar()
                .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        } detail: {
            VStack(spacing: 0) {
                TargetBar()
                Divider()
                FileList()
                Divider()
                LogPane()
                    .frame(height: 140)
            }
            .toolbar { toolbar }
        }
        .sheet(isPresented: $showAddConsole) { AddConsoleSheet() }
        .sheet(isPresented: $showAddURL) { AddURLSheet() }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: ContentView.importerTypes,
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls): model.addFiles(urls)
            case .failure(let err): model.log("File import cancelled: \(err.localizedDescription)")
            }
        }
    }

    static var importerTypes: [UTType] {
        var types: [UTType] = [.folder]
        if let cia = UTType(filenameExtension: "cia") { types.append(cia) }
        if let tik = UTType(filenameExtension: "tik") { types.append(tik) }
        return types
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button { model.discoverConsoles() } label: { Label("Discover 3DS", systemImage: "sensor.tag.radiowaves.forward") }
                .help("Sweep the local subnet and scan the ARP table for Nintendo MAC prefixes")
            Button { showAddConsole = true } label: { Label("Add 3DS", systemImage: "plus.app") }
                .help("Manually add a 3DS by IP address")
            Button { showAddURL = true } label: { Label("Add URL", systemImage: "link.badge.plus") }
                .help("Queue a remote URL for the 3DS to download directly")
            Button { showFileImporter = true } label: { Label("Add Files", systemImage: "doc.badge.plus") }
                .help("Pick CIA/TIK files or a folder to serve to the 3DS")
            Spacer()
            Button { openURL(ContentView.projectURL) } label: { Label("Project on GitHub", systemImage: "chevron.left.forwardslash.chevron.right") }
                .help("Open the FBILinkMac project page on GitHub to file bugs or check for updates")
        }
    }
}

// MARK: - Target bar

private struct TargetBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var bindable = model
        HStack(spacing: 12) {
            if model.consoles.isEmpty {
                Text("Add a 3DS to begin")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Picker("Sending to:", selection: $bindable.selectedConsoleID) {
                    ForEach(model.consoles) { console in
                        Text(console.displayName).tag(Optional(console.id))
                    }
                }
                .pickerStyle(.menu)
                .fixedSize()
                .disabled(model.isServing)
                .help(model.isServing
                      ? "Stop the current transfer before switching 3DS"
                      : "Pick which 3DS receives the queued files")
            }
            Spacer()
            if !model.files.isEmpty {
                Text(fileSummary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.background.secondary)
    }

    private var fileSummary: String {
        let count = model.files.count
        let total = model.files.reduce(Int64(0)) { $0 + max($1.byteCount, $1.bytesSent) }
        let noun = count == 1 ? "file" : "files"
        guard total > 0 else { return "\(count) \(noun) queued" }
        return "\(count) \(noun) · \(TransferFormat.bytes(total))"
    }
}

// MARK: - Console sidebar

private struct ConsoleSidebar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var bindable = model
        List(selection: $bindable.selectedConsoleID) {
            Section("3DS Consoles") {
                if model.consoles.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("No 3DS added yet.").foregroundStyle(.secondary)
                        Text("Click **Discover 3DS** or **Add 3DS** in the toolbar.")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                } else {
                    ForEach(model.consoles) { console in
                        ConsoleRow(console: console, isSelected: console.id == model.selectedConsoleID)
                            .tag(console.id)
                            .contextMenu {
                                Button("Remove", role: .destructive) { model.removeConsole(console.id) }
                            }
                    }
                }
            }
            if let lan = model.lanAddress {
                Section("This Mac") {
                    LabeledContent("LAN IP", value: lan)
                    if let port = model.serverPort {
                        LabeledContent("Serving on", value: "\(port)")
                    }
                }
                .font(.callout)
            }
        }
        .listStyle(.sidebar)
    }
}

private struct ConsoleRow: View {
    @Environment(AppModel.self) private var model
    let console: Console
    let isSelected: Bool

    var body: some View {
        let stats = model.perConsoleStats[console.id]
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(console.displayName).font(.body)
                Text(statusLabel).font(.caption).foregroundStyle(.secondary)
                if let stats, stats.totalBytes > 0 {
                    ProgressView(value: stats.progress)
                        .progressViewStyle(.linear)
                        .tint(progressTint)
                    Text(progressFooter(stats))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if isSelected {
                Button(model.isServing ? "Stop" : "Send") {
                    if model.isServing { model.stop() } else { model.start() }
                }
                .controlSize(.small)
                .keyboardShortcut(.defaultAction)
                .disabled(!model.isServing && model.files.isEmpty)
                .help(model.isServing
                      ? "Stop the transfer and shut down the file server"
                      : "Start the file server and tell this 3DS to fetch the queued files")
            }
        }
    }

    private func progressFooter(_ s: TransferStats) -> String {
        let pct = Int((s.progress * 100).rounded())
        let size = "\(TransferFormat.bytes(s.bytesSent)) of \(TransferFormat.bytes(s.totalBytes)) (\(pct)%)"
        guard s.isActive, s.bytesPerSecond > 0 else { return size }
        var extras: [String] = [TransferFormat.rate(s.bytesPerSecond)]
        if let eta = s.etaSeconds { extras.append("ETA \(TransferFormat.duration(eta))") }
        return size + " · " + extras.joined(separator: " · ")
    }

    private var statusLabel: String {
        switch console.status {
        case .idle: "Idle"
        case .connecting: "Connecting…"
        case .sending: "Sending…"
        case .completed: "Done"
        case .failed(let message): "Failed: \(message)"
        }
    }

    private var symbol: String {
        switch console.status {
        case .completed: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        case .sending, .connecting: "arrow.up.circle"
        case .idle: "gamecontroller"
        }
    }

    private var color: Color {
        switch console.status {
        case .completed: .green
        case .failed: .red
        case .sending, .connecting: .accentColor
        case .idle: .secondary
        }
    }

    private var progressTint: Color {
        switch console.status {
        case .failed: .red
        case .completed: .green
        case .sending, .connecting, .idle: .accentColor
        }
    }
}

// MARK: - File list

private struct FileList: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if model.files.isEmpty {
                DropTarget()
            } else {
                Table(model.files) {
                    TableColumn("Name") { file in
                        HStack {
                            Image(systemName: file.isLocal ? "doc.fill" : "link")
                                .foregroundStyle(.secondary)
                            Text(file.displayName)
                                .lineLimit(1).truncationMode(.middle)
                        }
                    }
                    TableColumn("Progress") { file in
                        FileProgressCell(file: file)
                    }
                    TableColumn("Size") { file in
                        Text(file.byteCount > 0 ? TransferFormat.bytes(file.byteCount) : "—")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            let accepted = urls.filter { $0.isFileURL }
            if !accepted.isEmpty { model.addFiles(accepted) }
            return !accepted.isEmpty
        }
    }
}

private struct FileProgressCell: View {
    @Environment(AppModel.self) private var model
    let file: TransferFile

    var body: some View {
        if !file.isLocal {
            Text("Fetched by 3DS — progress not tracked")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .help("The 3DS downloads this URL directly from the remote host, so the Mac can't see byte-level progress.")
        } else {
            let stats = model.perFileStats[file.id]
            VStack(alignment: .leading, spacing: 2) {
                if file.byteCount > 0 {
                    ProgressView(value: file.progress)
                        .tint(tint(for: stats, file: file))
                } else {
                    ProgressView().controlSize(.small)
                }
                if let stats, stats.isActive, stats.bytesPerSecond > 0 {
                    Text(rowFooter(stats))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                } else if let stats, !stats.isActive, stats.bytesSent > 0, file.progress < 1.0 {
                    Text("Interrupted at \(TransferFormat.bytes(stats.bytesSent))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private func tint(for stats: TransferStats?, file: TransferFile) -> Color {
        if file.progress >= 1.0 { return .green }
        if let stats, stats.isActive { return .accentColor }
        if case .failed = model.selectedConsole?.status { return .red }
        if let stats, stats.bytesSent > 0 { return .red }
        return .accentColor
    }

    private func rowFooter(_ s: TransferStats) -> String {
        var bits = [TransferFormat.rate(s.bytesPerSecond)]
        if let eta = s.etaSeconds { bits.append("ETA \(TransferFormat.duration(eta))") }
        return bits.joined(separator: " · ")
    }
}

private struct DropTarget: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.and.arrow.down.on.square")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("Drop CIA files here").font(.headline)
            Text("Or use the toolbar to add files, folders, or URLs.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// MARK: - Log pane

private struct LogPane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(model.logLines.enumerated().reversed()), id: \.offset) { idx, line in
                        Text(line).font(.system(.caption, design: .monospaced)).id(idx)
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            }
            .onChange(of: model.logLines.count) { _, new in
                guard new > 0 else { return }
                proxy.scrollTo(new - 1, anchor: .top)
            }
        }
        .background(.background.secondary)
        .contextMenu {
            Button("Copy All") { copyAll() }
                .disabled(model.logLines.isEmpty)
            Button("Clear") { model.logLines.removeAll() }
                .disabled(model.logLines.isEmpty)
        }
    }

    private func copyAll() {
        let text = model.logLines.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

// MARK: - Sheets

private struct AddConsoleSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var host = ""
    @State private var port: String = "5000"
    @State private var name = ""

    var body: some View {
        Form {
            TextField("IP address", text: $host).textContentType(.URL)
            TextField("Port", text: $port)
            TextField("Name (optional)", text: $name)
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 360)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Add") {
                    let p = UInt16(port) ?? 5000
                    model.addConsole(host: host, port: p, name: name.isEmpty ? nil : name)
                    dismiss()
                }.disabled(host.isEmpty)
            }
        }
    }
}

private struct AddURLSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var urlString = "https://"

    var body: some View {
        Form {
            TextField("URL", text: $urlString)
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 440)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Add") {
                    if let url = URL(string: urlString) { model.addRemoteURL(url) }
                    dismiss()
                }.disabled(URL(string: urlString) == nil)
            }
        }
    }
}
