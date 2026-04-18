# FBI Link

A native Mac app for installing CIA/TIK files onto a Nintendo 3DS running [FBI](https://github.com/Steveice10/FBI) — a modern replacement for the old [3DS-FBI-Link](https://github.com/smartperson/3DS-FBI-Link) that still uses FBI's original wire protocol but is built from scratch for current macOS.

![FBI Link screenshot](docs/screenshot.png)

## What you can do with it

- **Auto-discover 3DS consoles** on your local network.
- **Queue CIA or TIK files** by dragging them onto the window, picking with the file browser, or pointing at a whole folder.
- **Queue remote URLs** — the 3DS downloads them directly from the origin.
- **Pick a target 3DS and hit Send.** The Mac starts a small HTTP server, hands FBI the URL list, and streams files over.
- **Watch live progress** — per-file bars with speed and ETA, plus a per-device bar on each 3DS in the sidebar.
- **Keep your Mac awake** automatically for the duration of a transfer.
- **Stop a transfer cleanly** at any time from the sidebar; the 3DS sees the stream drop immediately.

## Requirements

- macOS 14 Sonoma or later (universal binary; Intel and Apple Silicon).
- A Nintendo 3DS running FBI, on the same Wi-Fi network as your Mac.
- FBI's **Receive URLs over the network** screen open on the 3DS when you click Send.

## Install

1. Go to the [Releases page](https://github.com/KingHavok/fbi-link-mac/releases) and download the latest `FBILinkMac-v1.0.0.zip` (or the latest non-prerelease).
2. Unzip it. Drag **FBI Link.app** into your **Applications** folder.

## First launch

FBI Link is ad-hoc signed, not notarised with Apple. macOS Sequoia and Sonoma will block it on the first double-click. The fix only takes a few seconds:

1. Double-click **FBI Link** in Applications. A dialog will say *"Apple could not verify FBI Link is free of malware…"* — click **Done**. Do **not** click *Move to Bin*.
2. Open **System Settings → Privacy & Security** and scroll to the bottom.
3. You'll see a message like *"FBI Link was blocked to protect your Mac."* Click **Open Anyway** next to it and authenticate with your password or Touch ID.
4. Launch FBI Link again. A second *"Are you sure?"* dialog appears — click **Open**. The app starts.

macOS will also ask for **Local Network** permission the first time you click Discover or Send. Grant it — the app can't reach your 3DS without it. If you ever need to change this later, it's under **System Settings → Privacy & Security → Local Network**.

> If you'd rather do it from the Terminal: `xattr -dr com.apple.quarantine /Applications/FBI\ Link.app` strips the quarantine flag and skips the Open Anyway dance.

## Using it

1. On your 3DS, open **FBI → Remote Install → Receive URLs over the network**. The screen shows your 3DS's IP address.
2. In FBI Link on your Mac, click **Discover 3DS** (the radio icon in the toolbar). It should find your console automatically and list it in the sidebar. If not, use **Add 3DS** to type its IP in manually.
3. Click the 3DS in the sidebar to select it.
4. Add some files: drag CIAs onto the window, or use the toolbar's **Add Files** / **Add URL** buttons. Folders work too — all `.cia` and `.tik` files inside are picked up.
5. Click **Send** on the 3DS row. The 3DS will ask you to confirm — tap Yes, and the transfer starts.
6. Progress bars update live. When everything turns green, you're done.

Stop at any time by clicking **Stop** where Send used to be.

## Known limitations

- **Remote URLs have no progress bar.** When you use Add URL, FBI on the 3DS downloads directly from the origin server — the Mac is out of the loop, so byte-level progress isn't visible. The row shows *"Fetched by 3DS — progress not tracked"* instead of a misleading 0%.
- **Single 3DS at a time.** The UI shows per-device progress because that's where it's heading, but right now one Send goes to one 3DS. If you select a different 3DS while a transfer is running, the current one has to finish or be stopped first.
- **Ad-hoc signed.** See the first-launch section. Until I get a paid Apple Developer account and set up notarisation in CI, macOS will always make you jump through the Privacy & Security hoop on the first launch of each new build.

## Found a bug?

Open an issue at [github.com/KingHavok/fbi-link-mac/issues](https://github.com/KingHavok/fbi-link-mac/issues). The log pane at the bottom of the app is selectable and has a **Copy All** option in its right-click menu — pasting that into the issue makes it dramatically easier to diagnose.

## For contributors

Everything about the architecture, the wire protocol, the build process, and how this project got to 1.0 lives in [DEVLOG.md](DEVLOG.md).

## Credits

- [Steveice10/FBI](https://github.com/Steveice10/FBI) — the on-device installer this app talks to.
- [smartperson/3DS-FBI-Link](https://github.com/smartperson/3DS-FBI-Link) — the prior Mac client whose wire protocol is preserved here.
- [miltoncandelero/Boop](https://github.com/miltoncandelero/Boop) — inspiration for the auto-discovery approach.

## License

MIT. See [LICENSE](LICENSE).
