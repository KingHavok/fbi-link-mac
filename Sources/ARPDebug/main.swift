import Foundation
import Darwin

// Tiny diagnostic for the sysctl(NET_RT_FLAGS) ARP read used by ARPDiscovery.
// Run from terminal:  swift run ARPDebug

func hex(_ b: UInt8) -> String { String(format: "%02x", b) }

var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, AF_INET, NET_RT_FLAGS, RTF_LLINFO]
let mibCount = u_int(mib.count)
var needed: size_t = 0

let sizeRC = mib.withUnsafeMutableBufferPointer { ptr in
    sysctl(ptr.baseAddress, mibCount, nil, &needed, nil, 0)
}
print("sysctl(size) rc=\(sizeRC) errno=\(errno) needed=\(needed)")

if needed == 0 {
    print("No bytes reported. Trying again with RTF_LLINFO=0 (all route entries)…")
    mib[5] = 0
    needed = 0
    let rc2 = mib.withUnsafeMutableBufferPointer { ptr in
        sysctl(ptr.baseAddress, mibCount, nil, &needed, nil, 0)
    }
    print("sysctl(size, no filter) rc=\(rc2) errno=\(errno) needed=\(needed)")
}

guard needed > 0 else { print("Nothing to read. Exiting."); exit(1) }

var buffer = [UInt8](repeating: 0, count: needed)
let rc = buffer.withUnsafeMutableBufferPointer { bufPtr in
    mib.withUnsafeMutableBufferPointer { mibPtr in
        sysctl(mibPtr.baseAddress, mibCount, bufPtr.baseAddress, &needed, nil, 0)
    }
}
print("sysctl(read) rc=\(rc) errno=\(errno) bytes=\(needed)")
guard rc >= 0 else { exit(1) }

var offset = 0
var msgCount = 0
buffer.withUnsafeBytes { raw in
    guard let base = raw.baseAddress else { return }
    while offset < needed {
        let rtm = base.load(fromByteOffset: offset, as: rt_msghdr.self)
        let msgLen = Int(rtm.rtm_msglen)
        msgCount += 1
        print("#\(msgCount) offset=\(offset) msglen=\(msgLen) type=\(rtm.rtm_type) flags=0x\(String(rtm.rtm_flags, radix: 16)) addrs=0x\(String(rtm.rtm_addrs, radix: 16))")
        if msgLen <= 0 || offset + msgLen > needed { print("  (stopping, bad msglen)"); break }

        let sinOffset = offset + MemoryLayout<rt_msghdr>.stride
        let sin = base.load(fromByteOffset: sinOffset, as: sockaddr_in.self)
        var addr = sin.sin_addr
        var ipBuf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        let ip = ipBuf.withUnsafeMutableBufferPointer { ptr -> String in
            if inet_ntop(AF_INET, &addr, ptr.baseAddress, socklen_t(INET_ADDRSTRLEN)) != nil {
                return String(cString: ptr.baseAddress!)
            }
            return ""
        }
        let sinLen = Int(sin.sin_len)
        let sinPadded = (sinLen + 3) & ~3
        let sdlOffset = sinOffset + sinPadded
        print("  sin.sa_family=\(sin.sin_family) sin_len=\(sinLen) ip=\(ip) sdlOffset=\(sdlOffset)")

        if sdlOffset + MemoryLayout<sockaddr_dl>.stride <= offset + msgLen {
            let sdl = base.load(fromByteOffset: sdlOffset, as: sockaddr_dl.self)
            print("  sdl.sa_family=\(sdl.sdl_family) sdl_len=\(sdl.sdl_len) nlen=\(sdl.sdl_nlen) alen=\(sdl.sdl_alen)")
            if sdl.sdl_alen == 6 {
                let dataBase = sdlOffset + 8
                var mac = [UInt8](repeating: 0, count: 6)
                for i in 0..<6 {
                    mac[i] = base.load(fromByteOffset: dataBase + Int(sdl.sdl_nlen) + i, as: UInt8.self)
                }
                print("  MAC=\(mac.map(hex).joined(separator: ":"))")
            }
        } else {
            print("  (no room for sockaddr_dl)")
        }

        offset += msgLen
    }
}
print("Total messages parsed: \(msgCount)")
