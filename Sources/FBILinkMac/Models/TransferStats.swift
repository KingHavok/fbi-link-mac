import Foundation

/// Rolling-window byte-rate sampler. Keeps samples within `windowSeconds` and
/// computes bytes/second as linear regression across the retained window edges.
struct SpeedTracker: Sendable {
    private(set) var samples: [(time: Date, bytes: Int64)] = []
    var windowSeconds: TimeInterval = 2.0

    mutating func record(totalBytes: Int64, now: Date = .init()) {
        if let last = samples.last, now.timeIntervalSince(last.time) < 0.05 {
            samples[samples.count - 1] = (now, totalBytes)
        } else {
            samples.append((now, totalBytes))
        }
        let cutoff = now.addingTimeInterval(-windowSeconds)
        if let keepFrom = samples.firstIndex(where: { $0.time >= cutoff }), keepFrom > 0 {
            samples.removeFirst(keepFrom - 1)
        }
    }

    mutating func reset() { samples.removeAll() }

    var bytesPerSecond: Double {
        guard let first = samples.first, let last = samples.last else { return 0 }
        let dt = last.time.timeIntervalSince(first.time)
        guard dt > 0.05 else { return 0 }
        return max(0, Double(last.bytes - first.bytes) / dt)
    }
}

struct TransferStats: Sendable, Equatable {
    var bytesSent: Int64
    var totalBytes: Int64
    var bytesPerSecond: Double
    var isActive: Bool

    var progress: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1.0, Double(bytesSent) / Double(totalBytes))
    }

    var etaSeconds: Double? {
        guard isActive, bytesPerSecond > 0, totalBytes > bytesSent else { return nil }
        return Double(totalBytes - bytesSent) / bytesPerSecond
    }

    static let zero = TransferStats(bytesSent: 0, totalBytes: 0, bytesPerSecond: 0, isActive: false)
}

enum TransferFormat {
    static func bytes(_ n: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
    }

    static func rate(_ bps: Double) -> String {
        guard bps > 0 else { return "—" }
        return ByteCountFormatter.string(fromByteCount: Int64(bps), countStyle: .file) + "/s"
    }

    static func duration(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "—" }
        let total = Int(seconds.rounded())
        if total < 60 { return "\(total)s" }
        let m = total / 60, s = total % 60
        if m < 60 { return String(format: "%dm %02ds", m, s) }
        let h = m / 60, mm = m % 60
        return String(format: "%dh %02dm", h, mm)
    }
}
