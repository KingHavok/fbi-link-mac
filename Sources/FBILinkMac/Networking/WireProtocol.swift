import Foundation

/// Matches the control protocol used by stock FBI's "Receive URLs over the network":
/// `[UInt32 big-endian byteCount][urls joined by "\n", UTF-8]`. FBI then HTTP-GETs
/// each URL and sends a single byte back when done.
enum WireProtocol {
    static let defaultFBIPort: UInt16 = 5000
    static let doneByteLength = 1

    static func encodeURLList(_ urls: [URL]) -> Data {
        let joined = urls.map(\.absoluteString).joined(separator: "\n")
        let body = Data(joined.utf8)
        var lengthBE = UInt32(body.count).bigEndian
        var payload = Data(capacity: 4 + body.count)
        withUnsafeBytes(of: &lengthBE) { payload.append(contentsOf: $0) }
        payload.append(body)
        return payload
    }
}
