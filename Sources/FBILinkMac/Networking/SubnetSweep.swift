import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Warms the kernel's ARP cache by firing a single UDP datagram at every host
/// on the local /24. We don't care whether anyone listens — the act of sending
/// forces the kernel to run ARP resolution, which is what populates the table
/// that ``ARPDiscovery`` later reads.
enum SubnetSweep {
    /// Sweeps the /24 containing `hostIP`, skipping the local address itself.
    /// Returns after a short settle delay so the ARP cache has time to register
    /// replies before the caller re-reads it.
    static func sweep(from hostIP: String) async {
        let parts = hostIP.split(separator: ".")
        guard parts.count == 4,
              let selfLast = Int(parts[3]) else { return }
        let base = parts[0..<3].joined(separator: ".")

        for i in 1...254 where i != selfLast {
            ping("\(base).\(i)")
        }
        try? await Task.sleep(for: .milliseconds(800))
    }

    private static func ping(_ ip: String) {
        let fd = socket(AF_INET, SOCK_DGRAM, 0)
        guard fd >= 0 else { return }
        defer { close(fd) }

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(9).bigEndian  // discard
        guard inet_pton(AF_INET, ip, &addr.sin_addr) == 1 else { return }

        let payload: UInt8 = 0
        withUnsafePointer(to: &addr) { addrPtr in
            addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { saPtr in
                withUnsafePointer(to: payload) { bytePtr in
                    _ = sendto(fd, bytePtr, 1, 0, saPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
    }
}
