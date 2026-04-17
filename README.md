# fbi-link-mac

A modern macOS app to push CIA files to [FBI](https://github.com/Steveice10/FBI) running on a Nintendo 3DS.

Clean-sheet SwiftUI rewrite of [smartperson/3DS-FBI-Link](https://github.com/smartperson/3DS-FBI-Link). Same wire protocol so it works with stock FBI, but built on Network.framework + Swift 6 + SwiftUI.

## Status

**Early scaffold.** Protocol + file server + console sender are implemented. UI is minimal. See [Roadmap](#roadmap).

## Requirements

- macOS 14 Sonoma or later (Intel or Apple Silicon, universal binary)
- Xcode 16 to build
- Nintendo 3DS running FBI with **Receive URLs over the network** open

## Build

```sh
brew install xcodegen
xcodegen generate
open FBILinkMac.xcodeproj
```

Or for quick iteration without Xcode project generation:

```sh
swift run FBILinkMac
```

## Wire protocol

Preserved from the original for FBI compatibility:

1. Mac opens TCP to `3DS:5000`.
2. Mac sends `[UInt32 big-endian length][urls joined by \n, UTF-8]`.
3. 3DS HTTP-GETs each URL from the Mac's local file server.
4. 3DS sends a single byte back when done.
5. Both sides close.

## Roadmap

- [x] Wire protocol encode/decode
- [x] `NWListener`-based HTTP file server with streaming + progress callbacks
- [x] `NWConnection`-based sender
- [x] Manual console add by IP
- [ ] Per-file progress bars + aggregate progress + transfer speed / ETA
- [ ] Drag-and-drop + `.fileImporter` for CIAs
- [ ] Auto-discover 3DS on LAN (ARP + `NSLocalNetworkUsageDescription`)
- [ ] Hardened Runtime + notarisation in CI
- [ ] App Sandbox opt-in

## Credits

- [Steveice10/FBI](https://github.com/Steveice10/FBI) — the tool this talks to.
- [smartperson/3DS-FBI-Link](https://github.com/smartperson/3DS-FBI-Link) — prior Mac app whose wire protocol is preserved here.
- [miltoncandelero/Boop](https://github.com/miltoncandelero/Boop) — auto-detection idea.

## License

MIT. See [LICENSE](LICENSE).
