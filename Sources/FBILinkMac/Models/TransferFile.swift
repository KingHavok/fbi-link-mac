import Foundation

struct TransferFile: Identifiable, Hashable, Sendable {
    enum Source: Hashable, Sendable {
        case localFile(URL)
        case remoteURL(URL)
    }

    let id: UUID
    var source: Source
    var displayName: String
    var byteCount: Int64
    var bytesSent: Int64

    init(id: UUID = UUID(), source: Source, displayName: String, byteCount: Int64, bytesSent: Int64 = 0) {
        self.id = id
        self.source = source
        self.displayName = displayName
        self.byteCount = byteCount
        self.bytesSent = bytesSent
    }

    var progress: Double {
        guard byteCount > 0 else { return 0 }
        return min(1.0, Double(bytesSent) / Double(byteCount))
    }

    var isLocal: Bool {
        if case .localFile = source { return true }
        return false
    }

    var servedPath: String {
        switch source {
        case .localFile(let url):
            let name = url.lastPathComponent
            return "/" + (name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name)
        case .remoteURL(let url):
            return url.absoluteString
        }
    }
}

extension TransferFile {
    static func fromLocal(_ url: URL) -> TransferFile? {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .nameKey])
        let size = Int64(values?.fileSize ?? 0)
        let name = values?.name ?? url.lastPathComponent
        return TransferFile(source: .localFile(url), displayName: name, byteCount: size)
    }

    static func fromRemote(_ url: URL) -> TransferFile {
        TransferFile(source: .remoteURL(url), displayName: url.lastPathComponent, byteCount: 0)
    }
}
