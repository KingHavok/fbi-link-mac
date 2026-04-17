import Foundation
@preconcurrency import Network
import OSLog

/// Minimal HTTP/1.1 server built on `NWListener`. Serves a bounded set of files
/// registered via ``setFiles(_:)`` and emits byte-level progress updates through
/// the ``events`` async stream.
actor FileServer {
    enum Event: Sendable {
        case started(port: UInt16)
        case requestStarted(fileID: UUID, clientHost: String)
        case progress(fileID: UUID, bytesSent: Int64, totalBytes: Int64)
        case requestFinished(fileID: UUID)
        case log(String)
        case error(String)
    }

    private let logger = Logger(subsystem: "com.kinghavok.FBILinkMac", category: "FileServer")
    private let queue = DispatchQueue(label: "FileServer")
    private var listener: NWListener?
    private var files: [String: TransferFile] = [:]   // keyed by servedPath
    private let (stream, continuation) = AsyncStream<Event>.makeStream()

    var events: AsyncStream<Event> { stream }

    func setFiles(_ files: [TransferFile]) {
        self.files = files.reduce(into: [:]) { $0[$1.servedPath] = $1 }
    }

    func start() throws -> UInt16 {
        if let listener { return listener.port?.rawValue ?? 0 }
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        let listener = try NWListener(using: params, on: .any)
        self.listener = listener
        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            Task { await self.handleListenerState(state) }
        }
        listener.newConnectionHandler = { [weak self] conn in
            guard let self else { return }
            Task { await self.accept(conn) }
        }
        listener.start(queue: queue)
        // NWListener.port is populated synchronously on .ready; surface via .started event instead.
        return listener.port?.rawValue ?? 0
    }

    func stop() {
        listener?.cancel()
        listener = nil
        continuation.yield(.log("Server stopped."))
    }

    func finish() {
        continuation.finish()
    }

    // MARK: - Private

    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            if let port = listener?.port?.rawValue {
                continuation.yield(.started(port: port))
            }
        case .failed(let err):
            continuation.yield(.error("Listener failed: \(err.localizedDescription)"))
        case .cancelled:
            continuation.yield(.log("Listener cancelled."))
        default:
            break
        }
    }

    private func accept(_ conn: NWConnection) async {
        let handler = RequestHandler(connection: conn, queue: queue, server: self)
        await handler.start()
    }

    fileprivate func lookup(path: String) -> TransferFile? {
        files[path]
    }

    fileprivate func emit(_ event: Event) {
        continuation.yield(event)
    }

    fileprivate func indexHTML() -> String {
        let rows = files.values.map { f in
            "<tr><td><a href=\"\(f.servedPath)\">\(f.displayName)</a></td><td>\(f.byteCount)</td></tr>"
        }.joined()
        return """
        <!doctype html><html><body>
        <h1>fbi-link-mac</h1>
        <table border="1" cellpadding="4"><tr><th>File</th><th>Size</th></tr>\(rows)</table>
        </body></html>
        """
    }
}

// MARK: - Connection handling

private final class RequestHandler {
    private let connection: NWConnection
    private let queue: DispatchQueue
    private weak var server: FileServer?
    private var buffer = Data()

    init(connection: NWConnection, queue: DispatchQueue, server: FileServer) {
        self.connection = connection
        self.queue = queue
        self.server = server
    }

    func start() async {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready: self.readRequest()
            case .failed(let err):
                Task { [server] in await server?.emit(.error("Connection failed: \(err.localizedDescription)")) }
                self.connection.cancel()
            case .cancelled: break
            default: break
            }
        }
        connection.start(queue: queue)
    }

    private var clientHost: String {
        if case let .hostPort(host, _) = connection.endpoint {
            return "\(host)"
        }
        return "unknown"
    }

    private func readRequest() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8_192) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let error {
                Task { [server] in await server?.emit(.error("Read error: \(error.localizedDescription)")) }
                self.connection.cancel()
                return
            }
            if let data, !data.isEmpty {
                self.buffer.append(data)
                if let headerEnd = self.buffer.range(of: Data("\r\n\r\n".utf8)) {
                    let header = self.buffer.subdata(in: 0..<headerEnd.lowerBound)
                    self.handleHeaders(header)
                    return
                }
            }
            if isComplete {
                self.connection.cancel()
            } else {
                self.readRequest()
            }
        }
    }

    private func handleHeaders(_ header: Data) {
        guard let headerStr = String(data: header, encoding: .utf8) else {
            sendStatus(400, body: "Bad request"); return
        }
        let requestLine = headerStr.split(separator: "\r\n").first.map(String.init) ?? ""
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { sendStatus(400, body: "Bad request"); return }
        let method = String(parts[0])
        let rawPath = String(parts[1])
        let path = rawPath.removingPercentEncoding ?? rawPath
        guard method == "GET" else { sendStatus(405, body: "Method not allowed"); return }
        Task { await self.route(decodedPath: path, rawPath: rawPath) }
    }

    private func route(decodedPath: String, rawPath: String) async {
        guard let server else { connection.cancel(); return }
        if decodedPath == "/" || decodedPath.isEmpty {
            let html = await server.indexHTML()
            sendStatus(200, contentType: "text/html; charset=utf-8", body: html); return
        }
        if let file = await server.lookup(path: rawPath) ?? server.lookup(path: decodedPath) {
            if case .localFile(let url) = file.source {
                await server.emit(.requestStarted(fileID: file.id, clientHost: clientHost))
                streamFile(at: url, file: file); return
            }
        }
        sendStatus(404, body: "Not found")
    }

    private func sendStatus(_ code: Int, contentType: String = "text/plain; charset=utf-8", body: String) {
        let reason = httpReason(code)
        let bodyData = Data(body.utf8)
        let header = "HTTP/1.1 \(code) \(reason)\r\nContent-Type: \(contentType)\r\nContent-Length: \(bodyData.count)\r\nConnection: close\r\n\r\n"
        var out = Data(header.utf8); out.append(bodyData)
        connection.send(content: out, completion: .contentProcessed { [weak self] _ in
            self?.connection.cancel()
        })
    }

    private func httpReason(_ code: Int) -> String {
        switch code {
        case 200: "OK"; case 400: "Bad Request"; case 404: "Not Found"
        case 405: "Method Not Allowed"; default: "OK"
        }
    }

    private func streamFile(at url: URL, file: TransferFile) {
        let handle: FileHandle
        do { handle = try FileHandle(forReadingFrom: url) } catch {
            sendStatus(500, body: "Cannot open file"); return
        }
        let total = file.byteCount
        let header = "HTTP/1.1 200 OK\r\nContent-Type: application/octet-stream\r\nContent-Length: \(total)\r\nAccept-Ranges: bytes\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(header.utf8), completion: .contentProcessed { [weak self] err in
            guard let self else { try? handle.close(); return }
            if let err {
                Task { [server] in await server?.emit(.error("Header send failed: \(err.localizedDescription)")) }
                self.connection.cancel(); try? handle.close(); return
            }
            self.pumpChunks(handle: handle, file: file, sent: 0, total: total)
        })
    }

    private func pumpChunks(handle: FileHandle, file: TransferFile, sent: Int64, total: Int64) {
        let chunkSize = 64 * 1024
        let chunk: Data
        do { chunk = try handle.read(upToCount: chunkSize) ?? Data() }
        catch {
            Task { [server] in await server?.emit(.error("Read failed: \(error.localizedDescription)")) }
            try? handle.close(); connection.cancel(); return
        }
        if chunk.isEmpty {
            try? handle.close()
            let fileID = file.id
            Task { [server] in
                await server?.emit(.progress(fileID: fileID, bytesSent: total, totalBytes: total))
                await server?.emit(.requestFinished(fileID: fileID))
            }
            connection.send(content: nil, isComplete: true, completion: .contentProcessed { [weak self] _ in
                self?.connection.cancel()
            })
            return
        }
        connection.send(content: chunk, completion: .contentProcessed { [weak self] err in
            guard let self else { try? handle.close(); return }
            if let err {
                Task { [server] in await server?.emit(.error("Chunk send failed: \(err.localizedDescription)")) }
                try? handle.close(); self.connection.cancel(); return
            }
            let newSent = sent + Int64(chunk.count)
            let fileID = file.id
            Task { [server] in
                await server?.emit(.progress(fileID: fileID, bytesSent: newSent, totalBytes: total))
            }
            self.pumpChunks(handle: handle, file: file, sent: newSent, total: total)
        })
    }
}
