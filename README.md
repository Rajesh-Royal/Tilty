# <img src="docs/icon.svg" width="40" align="top" alt=""> Tilty

Tilty puts three big buttons in the title bar of whatever window you're using: **Fill**, **Left Half** and **Right Half**. One click and the window moves. No hovering, no waiting, no menus.

<p align="center">
  <img src="docs/demo.svg" alt="Tilty demo: one click on Fill, Left Half and Right Half, then click again to restore" width="720">
</p>

## Why I built this

If I had a keyboard and a mouse, I would not have built this.

I use a laptop only, and I use the trackpad only. My fingers are big and the macOS window buttons are small. Keyboard shortcuts are hard to remember. To make a window bigger without going full screen, I had to hover over the green button, wait for the menu to show up, and then pick Fill. If I clicked the green button by mistake, the window went full screen and I had to back out of it.

I don't want to wait even a second. It should be click and done. That's it.

Tilty is a personal tool built for exactly that.

## What it does

- Shows a small toolbar right after the traffic lights of the active window.
- **Fill** makes the window as big as the screen without going full screen. The menu bar and Dock stay visible.
- **Left Half** and **Right Half** snap the window to that side of the screen.
- Click the same button again to put the window back where it was.
- The toolbar follows you as you switch apps and windows. It hides while you drag a window and comes back when you let go.
- It stays out of the way for full screen windows, dialogs, sheets and minimized windows.
- Works with multiple displays. The window stays on the screen it's already on.

### Chrome and other Chromium browsers

Chrome puts its tabs right after the traffic lights, so there the toolbar sits at the right end of the tab strip instead. You can change this for any app from the menu bar: **Icons in <App>** then **After the Traffic Lights** or **At the Right End**.

### Menu bar

The Tilty icon in the menu bar has:

- **Pause Tilty** to hide the toolbar for a while.
- **Icons in <App>** to pick where the toolbar sits for the current app.
- **Launch at Login**.
- **Quit Tilty**.

If the icon shows a warning triangle, Tilty is still waiting for Accessibility access.

## Install

**[Download Tilty.dmg](https://github.com/Rajesh-Royal/Tilty/releases/latest/download/Tilty.dmg)** (macOS 13 or later, Apple Silicon and Intel)

1. Open the DMG and drag **Tilty** into **Applications**.
2. Open Tilty. macOS says it can't verify the app, because Tilty isn't from the App Store. Click **Done**.
3. Open **System Settings > Privacy & Security**, scroll down and click **Open Anyway** next to Tilty.
4. When Tilty asks for Accessibility access, click **Open System Settings** and turn on **Tilty**.

That's it. Click into any window and the buttons are next to the traffic lights. If they don't show up after a few seconds, quit Tilty from the menu bar and open it again.

What changed in each version is in the [release notes](https://github.com/Rajesh-Royal/Tilty/releases) and in [CHANGELOG.md](CHANGELOG.md).

### Updating

Quit Tilty, replace it in Applications with the new version and open it. Each version counts as a new app to macOS, so if the buttons don't show up, open **Privacy & Security > Accessibility**, remove Tilty with the **minus** button, then open Tilty again and allow it.

## Build from source

Needs Xcode.

```bash
scripts/build-app.sh --install
```

This builds `Tilty.app`, copies it to `/Applications`, clears the old Accessibility grant and opens it. Without `--install` the app lands in `build/Tilty.app`. Add `--universal` for an Apple Silicon and Intel build.

The app is signed locally (ad hoc), so macOS treats each build as a new app. If you built without `--install`, reset the old grant with:

```bash
tccutil reset Accessibility app.tilty.Tilty
```

### Releasing a new version

1. Put the new version number in `VERSION`.
2. Add a `## <version>` section to `CHANGELOG.md`. It becomes the release notes.
3. Commit, then run `scripts/release.sh`. It builds a universal app, packs `Tilty.dmg`, tags the commit and publishes the GitHub release.

Run `scripts/release.sh --dry-run` to build the DMG without publishing.

## Development

```bash
swift build      # debug build
swift test       # unit tests for the geometry and restore logic
```

If `xcode-select -p` points at Command Line Tools, prefix commands with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. The build script does this for you.

Layout:

- `Sources/TiltyCore` holds the pure logic. It covers coordinate flipping, tile frames, screen choice, toolbar placement and the restore memory. It has no AppKit or Accessibility code, so it's easy to test.
- `Sources/Tilty` is the app. It has the menu bar item, the floating toolbar panel, window tracking through `AXObserver` and the window mover.
- `Tests/TiltyCoreTests` has tests for the core.

To change the README animation, edit `scripts/make-demo-svg.py` and run `python3 scripts/make-demo-svg.py`. It writes `docs/demo.svg`. Then run `node scripts/make-demo-anim.mjs` to refresh `docs/demo.webp` and `docs/demo.gif` from it.

`Tilty --preview` (run the binary inside the app) draws the toolbar on the frontmost window without needing Accessibility access. It's handy for checking the look.

## Not in scope

- Drag to the screen edge to snap. macOS already does this (System Settings > Desktop & Dock > "Drag windows to screen edges to tile").
- Keyboard shortcuts. The whole point is one click on the trackpad.

## License

Tilty is free for personal and other noncommercial use. You can use it, share it and change it. You can't use it or sell it for commercial purposes.

It's licensed under the [PolyForm Noncommercial License 1.0.0](LICENSE.md).
