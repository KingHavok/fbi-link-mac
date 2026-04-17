import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Picks a non-loopback IPv4 address for this host so we can construct URLs the
/// 3DS on the same LAN can actually reach.
enum LANAddress {
    static func primaryIPv4() -> String? {
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0, let first = ifaddrPtr else { return nil }
        defer { freeifaddrs(ifaddrPtr) }

        var candidates: [(iface: String, addr: String)] = []
        var node: UnsafeMutablePointer<ifaddrs>? = first
        while let cur = node {
            defer { node = cur.pointee.ifa_next }
            let flags = Int32(cur.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0,
                  let addrPtr = cur.pointee.ifa_addr, addrPtr.pointee.sa_family == sa_family_t(AF_INET) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let rc = getnameinfo(addrPtr, socklen_t(addrPtr.pointee.sa_len),
                                 &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
            guard rc == 0 else { continue }
            let name = String(cString: cur.pointee.ifa_name)
            let addr = String(cString: host)
            candidates.append((name, addr))
        }
        // Prefer en0 (Wi-Fi / primary Ethernet on macOS), then any en*, then anything else.
        if let hit = candidates.first(where: { $0.iface == "en0" }) { return hit.addr }
        if let hit = candidates.first(where: { $0.iface.hasPrefix("en") }) { return hit.addr }
        return candidates.first?.addr
    }
}
