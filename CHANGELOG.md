# Changelog

## 0.3.1

### What's improved

- **Lower idle overhead.** Tilty now pauses tracking while paused, when displays sleep, and when another user session is active. It also avoids repeated accessibility queries and unnecessary toolbar updates. In an idle VS Code measurement, CPU time fell from about 80 ms to 25 ms per 30 seconds; results vary by app and Mac.
- **Smoother tracking.** Window-drag notifications are coalesced, and Tilty ignores geometry changes caused by its own animations. Window checks speed up while things are changing and back off after a few quiet seconds.
- **Less background work.** Settings and the menu bar icon are reused, repeated app-event subscriptions are avoided, and failed subscriptions are retried less often.

### Fixes

- Closing a layout picker can no longer dismiss a newly opened picker because of a delayed click or Escape event.

### Note

Most apps report window changes immediately. For apps that do not, or changes such as hiding a toolbar that do not move the window, the backup check now runs less often after a quiet period; the toolbar may take up to about 1.4 seconds to catch up.

### Updating

Quit Tilty, replace it in Applications with the new one and open it. macOS may ask you to allow Accessibility access again after the update.

## 0.3.0

### What's new

- **Smooth window moves.** Fill, Left, Right, the layout grid and the window picker now slide the window into place instead of jumping. Apps that can't redraw fast enough snap straight there, so a move never stutters.
- **Animate Window Moves** switch in the menu bar. On by default. Turn it off if you'd rather windows snap. Tilty also snaps when **Reduce Motion** is on in macOS.

### Updating

Quit Tilty, replace it in Applications with the new one and open it. If the buttons don't show up, open **System Settings > Privacy & Security > Accessibility**, remove Tilty with the **minus** button, then open Tilty again and allow it.

## 0.2.1

### What's new

- **About Tilty** in the menu bar. It shows the version, with links to the website, the GitHub repo, the release notes and a place to report a problem.
- **Check for Updates** in the menu bar opens the latest release, so you can see if there's a newer version.

### Updating

Quit Tilty, replace it in Applications with the new one and open it. If the buttons don't show up, open **System Settings > Privacy & Security > Accessibility**, remove Tilty with the **minus** button, then open Tilty again and allow it.

## 0.2.0

More layouts, like Windows 11 snap layouts, but one click instead of a hover.

### What's new

- **Layout grid.** A small chevron at the end of the toolbar opens a grid of six layouts: halves, two-thirds and one-third, one-third and two-thirds, three columns, one tall window with two stacked, and quarters.
- **Pick a zone.** Click the part of a layout where the current window should go and it snaps there.
- **Fill the rest.** After you place a window, your other open windows show up in the empty zones. Click one to drop it in. Press Esc or click anywhere else to skip.
- **Optional suggestions after Left or Right.** Turn on **Suggest Windows After Left or Right** in the menu bar to get the same window picker for the other side. Off by default, so the quick buttons stay click and done.
- **Stage Manager warning.** Stage Manager shows one app at a time, so it hides windows you lay out side by side. When it's on, the layout grid, the window picker and the menu bar tell you, with a button to turn it off in Settings.

### Updating from 0.1.0

Quit Tilty, replace it in Applications with the new one and open it. Each version counts as a new app to macOS, so if the buttons don't show up, open **System Settings > Privacy & Security > Accessibility**, remove Tilty with the **minus** button, then open Tilty again and allow it.

## 0.1.0

The first release of Tilty. Big one-click buttons in the title bar for tiling windows.

### What's in it

- **Fill, Left Half and Right Half** buttons right after the traffic lights of the window you're using. One click and the window moves.
- **Click again to restore.** Click the same button twice and the window goes back to where it was.
- **Follows you around.** The buttons move to whichever window is active, hide while you drag, and stay out of the way in full screen, dialogs and minimized windows.
- **Chrome friendly.** In Chrome, Edge, Brave and other Chromium browsers the buttons sit at the right end of the tab strip so they never cover a tab. You can change this per app from the menu bar.
- **Menu bar icon** with Pause, per-app button placement, Launch at Login and Quit.
- **Multiple displays.** A window stays on the screen it's already on.
- Works on Apple Silicon and Intel Macs with macOS 13 or later.

### Install

1. Download **Tilty.dmg** below and open it.
2. Drag **Tilty** into the **Applications** folder.
3. Open Tilty. macOS says it can't verify the app, because Tilty isn't from the App Store. Click **Done**.
4. Open **System Settings > Privacy & Security**, scroll down and click **Open Anyway** next to Tilty. Confirm with **Open Anyway** again.
5. When Tilty asks for Accessibility access, click **Open System Settings** and turn on **Tilty**. That's it.

### Updating from an older version

Quit Tilty, replace it in Applications with the new one and open it. If the buttons don't show up, open **System Settings > Privacy & Security > Accessibility**, select Tilty, remove it with the **minus** button, then open Tilty again and allow it.
