# FBI Link — devlog

Notes on why this project exists, how it's built, and the story of getting it to 1.0. For the end-user version, see [README.md](README.md).

## Origin

A modern macOS client for pushing CIA/TIK files to [FBI](https://github.com/Steveice10/FBI) running on a Nintendo 3DS. The pre-existing Mac option — [smartperson/3DS-FBI-Link](https://github.com/smartperson/3DS-FBI-Link) — still works but is pre-SwiftUI, pre-Network.framework, and doesn't fit cleanly onto recent macOS releases. This project is a clean-sheet rewrite that preserves FBI's wire protocol so it still talks to stock FBI on-device, but is built on Swift 6, SwiftUI, and Network.framework under Apple's current concurrency and sandboxing models.

## Architecture

- **SwiftUI + `@Observable`.** Single `AppModel` on the main actor holds all UI state (consoles, files, per-file and per-console transfer stats, log lines). Views read it via `@Environment`.
- **Network.framework.** `NWListener` powers the ad-hoc HTTP/1.1 file server; `NWConnection` opens the outbound session to FBI on port 5000 and feeds it the wire-protocol URL list. No subprocesses, no raw sockets in the hot path.
- **Swift 6 strict concurrency.** `FileServer` is an actor. Per-request work runs in a `RequestHandler` reference type that sits behind the server's serial `DispatchQueue`, marked `@unchecked Sendable` so Network.framework's `@Sendable` callbacks compile under the new checker.
- **App Sandbox + Hardened Runtime.** Entitlements are limited to `network.client`, `network.server`, `files.user-selected.read-only`, and the sandbox itself. Drag-and-drop / file-importer URLs are held via `startAccessingSecurityScopedResource` so reads keep working under the sandbox.

## Wire protocol

Preserved from the original for FBI compatibility:

1. Mac opens TCP to `3DS:5000`.
2. Mac sends `[UInt32 big-endian length][urls joined by \n, UTF-8]`.
3. 3DS HTTP-GETs each URL from the Mac's local file server (or remote URLs directly).
4. 3DS sends a single byte back when done (regardless of whether the user accepted or dismissed the prompt).
5. Both sides close.

## Build locally

```sh
brew install xcodegen
xcodegen generate
open FBILinkMac.xcodeproj
```

For quick iteration without Xcode:

```sh
swift run FBILinkMac
```

## Ship history

Things worth remembering, roughly chronological.

**Initial scaffold.** SwiftUI app with a sidebar of consoles and a right-pane file list. Wire-protocol encode/decode, an `NWListener` HTTP/1.1 file server with streaming and per-chunk progress callbacks, an `NWConnection` sender that waits on FBI's done-byte, `.fileImporter` + drag-drop for CIAs.

**Per-file and aggregate progress.** Rolling-window `SpeedTracker` computes bytes/sec as linear regression across retained samples. Initial UI had a single top-of-pane aggregate bar plus per-file progress in the table.

**Manual console add.** Form sheet for typing an IP when discovery isn't an option.

**ARP discovery.** Reads the kernel ARP cache in-process via `sysctl(CTL_NET, PF_ROUTE, 0, AF_INET, NET_RT_FLAGS, RTF_LLINFO)`, filters to Nintendo OUI prefixes. No subprocess, no `/usr/sbin/arp`, sandbox-clean.

**Subnet sweep.** On Discover, before reading ARP, fire a UDP datagram at every host on the local /24 so the 3DS's entry exists in the ARP cache on first try. Sleeps briefly so the kernel can populate.

**Idle-sleep prevention.** While a transfer is in progress, hold `kIOPMAssertionTypeNoIdleSleep` so the Mac doesn't nap mid-CIA.

**App icon + Hardened Runtime + App Sandbox opt-in.** Shipped entitlements (`network.client`, `network.server`, `files.user-selected.read-only`), and the asset catalog with 16/32/64/128/256/512/1024 rasterizations. Notarisation is the one hardening step left, and needs a paid Apple Developer account.

**The ARP use-after-free.** Discovery worked in debug builds and on the command line but returned zero entries in Release builds once the app was packaged. After progressively narrower diagnostics, the cause was a lifetime bug: `inet_ntop` returns a pointer into the buffer you hand it, and the IP string was being constructed *after* `withUnsafeMutableBufferPointer` had returned. Debug keeps the backing array alive long enough by accident; Release doesn't. Fix: move the `String(cString:)` call inside the pointer closure. See commit [`489b3eb`](https://github.com/KingHavok/fbi-link-mac/commit/489b3eb).

**Console selection + server allowlist + real Stop.** Up to that point, Send broadcast to every known console and Stop only cancelled the `NWListener`, leaving in-flight HTTP responses streaming. Sidebar now has a single-select binding so the target is explicit; `FileServer` carries an allowlist of permitted client IPs (seeded with the selected 3DS) and returns 403 to anyone else; Stop tracks every accepted `NWConnection` and cancels them all so the 3DS actually sees the stream drop.

**Quit behaviour.** `NSApplicationDelegateAdaptor` wires up `applicationShouldTerminateAfterLastWindowClosed = true` (so clicking the red button actually quits this single-window utility) and `applicationShouldTerminate` that prompts for confirmation if a transfer is still running.

**UI reshape.** Send/Stop moved off the toolbar onto the selected 3DS row so the target is unambiguous. The top aggregate bar was replaced with per-console progress inline in each sidebar row — keyed by the active transfer, already shaped for multi-device fan-out before the backend supports it. The target is also exposed as a "Sending to:" picker above the file list so the destination is visible and switchable from the right pane. The log flipped to newest-first with text selection and a Copy All / Clear context menu for bug-report friendliness.

**Interrupted vs completed.** Frozen progress bars now tint red when a transfer was stopped, declined, or otherwise cut off below 100%, and green when it finished. Declines (user presses No on FBI's prompt) are detected by tracking which files actually had HTTP GETs issued — an empty set at done-byte time means the user dismissed the prompt.

**Re-Send after completion.** Originally each Send cancelled the server/sender pump tasks and spawned fresh ones, which broke on the second attempt because `AsyncStream` is single-consumer and the new iterators couldn't see events from the existing streams. The pump loops are now started once in `init` and live for the process lifetime.

**Sender diagnostics.** `.waiting` NWConnection states now surface as a user-facing log line with the OS's actual error string, so a silent hang is no longer indistinguishable from "nothing happened". Combined with clearer guidance in the release notes (System Settings → Privacy & Security → Local Network — Sequoia re-prompts per ad-hoc signing identity), the "Send does nothing" failure mode is now self-explanatory.

**Ad-hoc release workflow.** GitHub Actions builds a universal Release binary, ad-hoc signs it, zips with `ditto --sequesterRsrc --keepParent`, and publishes to GitHub Releases. Main-branch pushes produce `build-N` prereleases; pushing a `v*` tag produces a non-prerelease marked "latest". The release notes include the Sequoia first-launch flow (double-click → Done → System Settings → Privacy & Security → Open Anyway).

## What's not done

- **Notarisation.** Requires a paid Apple Developer account. Without it, macOS will always nag about blocked apps and users need to run the Open Anyway dance.
- **Fan-out to multiple 3DS simultaneously.** The UI is shaped for it, but `AppModel.start` and `ConsoleSender.send` are still single-target.
- **Progress for remote URLs.** Add URL items are fetched directly by FBI from their origin host — the Mac never sees the bytes. A proxy that downloads and re-serves locally would fix this but is a bigger change.

## Credits

- [Steveice10/FBI](https://github.com/Steveice10/FBI) — the tool this talks to.
- [smartperson/3DS-FBI-Link](https://github.com/smartperson/3DS-FBI-Link) — prior Mac app whose wire protocol is preserved here.
- [miltoncandelero/Boop](https://github.com/miltoncandelero/Boop) — auto-detection idea.
- Built collaboratively with Claude (Anthropic) via Claude Code.

## License

MIT. See [LICENSE](LICENSE).
