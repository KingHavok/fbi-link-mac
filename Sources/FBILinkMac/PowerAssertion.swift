import Foundation
import IOKit.pwr_mgt

/// Prevents idle sleep while a transfer is in progress. Wraps
/// `IOPMAssertionCreateWithName` so the Mac stays awake long enough for the
/// 3DS to finish pulling files over HTTP.
final class PowerAssertion {
    private var assertionID: IOPMAssertionID = 0
    private var held = false

    func acquire(reason: String) {
        guard !held else { return }
        let rc = IOPMAssertionCreateWithName(
            kIOPMAssertionTypeNoIdleSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &assertionID
        )
        held = (rc == kIOReturnSuccess)
    }

    func release() {
        guard held else { return }
        IOPMAssertionRelease(assertionID)
        held = false
        assertionID = 0
    }

    deinit { release() }
}
