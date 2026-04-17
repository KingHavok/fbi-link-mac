import Foundation
#if canImport(Darwin)
import Darwin
#endif

struct ARPEntry: Hashable, Sendable {
    let ip: String
    let mac: String
    var macPrefix: [UInt8] { Array(macBytes.prefix(3)) }

    var macBytes: [UInt8] {
        mac.split(separator: ":").compactMap { UInt8($0, radix: 16) }
    }
}

/// Reads the kernel ARP cache in-process via `sysctl(NET_RT_FLAGS)`. No
/// subprocess, no `/usr/sbin/arp`, which keeps us compatible with tighter
/// sandboxing on newer macOS versions.
enum ARPDiscovery {
    /// OUI prefixes assigned to Nintendo, preserved from the original
    /// 3DS-FBI-Link Mac app. Stored as `[UInt8]` so MAC normalisation
    /// (leading zeros) is unambiguous.
    static let nintendoPrefixes: Set<[UInt8]> = Set([
        "e8:4e:ce", "e0:e7:51", "e0:0c:7f", "d8:6b:f7", "cc:fb:65", "cc:9e:00",
        "b8:ae:6e", "a4:c0:e1", "a4:5c:27", "9c:e6:35", "98:b6:e9", "8c:cd:e8",
        "8c:56:c5", "7c:bb:8a", "78:a2:a0", "58:bd:a3", "40:f4:07", "40:d2:8a",
        "34:af:2c", "2c:10:c1", "18:2a:7b", "00:27:09", "00:26:59", "00:25:a0",
        "00:24:f3", "00:24:44", "00:24:1e", "00:23:cc", "00:23:31", "00:22:d7",
        "00:22:aa", "00:22:4c", "00:21:bd", "00:21:47", "00:1f:c5", "00:1f:32",
        "00:1e:a9", "00:1e:35", "00:1d:bc", "00:1c:be", "00:1b:ea", "00:1b:7a",
        "00:1a:e9", "00:19:fd", "00:19:1d", "00:17:ab", "00:16:56", "00:09:bf",
    ].map { str in
        str.split(separator: ":").compactMap { UInt8($0, radix: 16) }
    })

    static func readARPTable() -> [ARPEntry] {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, AF_INET, NET_RT_FLAGS, RTF_LLINFO]
        let mibCount = u_int(mib.count)
        var needed: size_t = 0
        let sizeRC = mib.withUnsafeMutableBufferPointer { ptr in
            sysctl(ptr.baseAddress, mibCount, nil, &needed, nil, 0)
        }
        guard sizeRC >= 0, needed > 0 else { return [] }

        var buffer = [UInt8](repeating: 0, count: needed)
        let rc = buffer.withUnsafeMutableBufferPointer { bufPtr in
            mib.withUnsafeMutableBufferPointer { mibPtr in
                sysctl(mibPtr.baseAddress, mibCount, bufPtr.baseAddress, &needed, nil, 0)
            }
        }
        guard rc >= 0 else { return [] }

        var entries: [ARPEntry] = []
        return buffer.withUnsafeBytes { raw -> [ARPEntry] in
            guard let base = raw.baseAddress else { return [] }
            var offset = 0
            while offset < needed {
                let rtm = base.load(fromByteOffset: offset, as: rt_msghdr.self)
                let msgLen = Int(rtm.rtm_msglen)
                guard msgLen > 0, offset + msgLen <= needed else { break }
                let sinOffset = offset + MemoryLayout<rt_msghdr>.stride
                if sinOffset + MemoryLayout<sockaddr_in>.stride <= offset + msgLen {
                    let sin = base.load(fromByteOffset: sinOffset, as: sockaddr_in.self)
                    var addr = sin.sin_addr
                    var ipBuf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                    let ipPtr = ipBuf.withUnsafeMutableBufferPointer { ptr -> UnsafePointer<CChar>? in
                        inet_ntop(AF_INET, &addr, ptr.baseAddress, socklen_t(INET_ADDRSTRLEN))
                    }
                    let ip = ipPtr.map { String(cString: $0) } ?? ""
                    let sinLen = Int(sin.sin_len)
                    let padded = (sinLen + 3) & ~3
                    let sdlOffset = sinOffset + padded
                    if sdlOffset + MemoryLayout<sockaddr_dl>.stride <= offset + msgLen, !ip.isEmpty {
                        let sdl = base.load(fromByteOffset: sdlOffset, as: sockaddr_dl.self)
                        let nameLen = Int(sdl.sdl_nlen)
                        let macLen = Int(sdl.sdl_alen)
                        if macLen == 6 {
                            // sdl_data starts at offset 8 in sockaddr_dl (sdl_len, sdl_family,
                            // sdl_index, sdl_type, sdl_nlen, sdl_alen, sdl_slen).
                            let dataBase = sdlOffset + 8
                            var macBytes = [UInt8](repeating: 0, count: 6)
                            for i in 0..<6 {
                                macBytes[i] = base.load(fromByteOffset: dataBase + nameLen + i, as: UInt8.self)
                            }
                            let mac = macBytes.map { String(format: "%02x", $0) }.joined(separator: ":")
                            entries.append(ARPEntry(ip: ip, mac: mac))
                        }
                    }
                }
                offset += msgLen
            }
            return entries
        }
    }

    static func findNintendoConsoles() -> [ARPEntry] {
        readARPTable().filter { nintendoPrefixes.contains($0.macPrefix) }
    }
}
