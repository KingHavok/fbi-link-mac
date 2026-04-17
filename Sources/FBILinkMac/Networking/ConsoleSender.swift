import Foundation
@preconcurrency import Network

/// Connects to a 3DS running FBI's "Receive URLs over the network" on port 5000,
/// sends the wire-protocol URL list, waits for the one-byte done marker, and closes.
actor ConsoleSender {
    enum Event: Sendable {
        case connecting(consoleID: UUID)
        case connected(consoleID: UUID)
        case finished(consoleID: UUID)
        case failed(consoleID: UUID, message: String)
    }

    private let queue = DispatchQueue(label: "ConsoleSender")
    private let (stream, continuation) = AsyncStream<Event>.makeStream()
    private var connections: [UUID: NWConnection] = [:]

    var events: AsyncStream<Event> { stream }

    func send(to console: Console, urls: [URL]) {
        let payload = WireProtocol.encodeURLList(urls)
        let host = NWEndpoint.Host(console.host)
        let port = NWEndpoint.Port(rawValue: console.port) ?? .init(integerLiteral: 5000)
        let params = NWParameters.tcp
        if let tcp = params.defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options {
            tcp.noDelay = true
        }
        let conn = NWConnection(host: host, port: port, using: params)
        connections[console.id] = conn
        continuation.yield(.connecting(consoleID: console.id))
        conn.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            Task { await self.handle(state: state, console: console, connection: conn, payload: payload) }
        }
        conn.start(queue: queue)
    }

    func cancelAll() {
        for (_, conn) in connections { conn.cancel() }
        connections.removeAll()
    }

    func finish() {
        continuation.finish()
    }

    // MARK: - Private

    private func handle(state: NWConnection.State, console: Console, connection: NWConnection, payload: Data) {
        switch state {
        case .ready:
            continuation.yield(.connected(consoleID: console.id))
            connection.send(content: payload, completion: .contentProcessed { [weak self] err in
                guard let self else { return }
                if let err {
                    Task { await self.fail(console: console, message: "Send failed: \(err.localizedDescription)") }
                    return
                }
                self.awaitDone(connection: connection, console: console)
            })
        case .failed(let err):
            continuation.yield(.failed(consoleID: console.id, message: err.localizedDescription))
            connection.cancel()
            connections[console.id] = nil
        case .cancelled:
            connections[console.id] = nil
        default:
            break
        }
    }

    nonisolated private func awaitDone(connection: NWConnection, console: Console) {
        connection.receive(minimumIncompleteLength: WireProtocol.doneByteLength,
                           maximumLength: WireProtocol.doneByteLength) { [weak self] _, _, _, error in
            guard let self else { return }
            if let error {
                Task { await self.fail(console: console, message: "Done-byte read failed: \(error.localizedDescription)") }
                return
            }
            Task { await self.complete(console: console, connection: connection) }
        }
    }

    private func fail(console: Console, message: String) {
        continuation.yield(.failed(consoleID: console.id, message: message))
        connections[console.id]?.cancel()
        connections[console.id] = nil
    }

    private func complete(console: Console, connection: NWConnection) {
        continuation.yield(.finished(consoleID: console.id))
        connection.cancel()
        connections[console.id] = nil
    }
}
