import Foundation

struct Console: Identifiable, Hashable, Sendable {
    let id: UUID
    var host: String
    var port: UInt16
    var name: String?
    var status: Status

    enum Status: Sendable, Hashable {
        case idle
        case connecting
        case sending
        case completed
        case failed(String)
    }

    init(id: UUID = UUID(), host: String, port: UInt16 = 5000, name: String? = nil, status: Status = .idle) {
        self.id = id
        self.host = host
        self.port = port
        self.name = name
        self.status = status
    }

    var displayName: String { name ?? host }
}
