# SnapSort

SnapSort is a minimal macOS menu bar app (Swift + SwiftUI) that watches your active screenshot save folder and automatically sorts new screenshots into date-based subfolders.

## Behavior

- Detects screenshot location from `com.apple.screencapture location`.
- Falls back to Desktop if no custom location is set.
- Watches for newly created files in that base folder.
- Ignores non-screenshot files.
- Moves matching screenshots without renaming.
- Auto-creates destination date folders for confirmed screenshots (daily/monthly) before moving.
- Applies a current-time window guard before moving: daily mode only moves screenshots from today, monthly mode only moves screenshots from this month (local time).
- Handles collisions by appending deterministic suffixes: ` (1)`, ` (2)`, etc.

## Sort Modes

When folder sorting is ON:

- Monthly: `<BaseFolder>/<FolderName>/YYYY-MM/`
- Daily: `<BaseFolder>/<FolderName>/YYYY-MM-DD/`

`FolderName` is either:

- Default `Screenshots` (recommended), or
- A custom value from the menu UI.

## Build and Run

1. Open `/Users/kyeongsucho/Documents/SnapSort/SnapSort.xcodeproj` in Xcode.
2. Select the `SnapSort` target.
3. Build and run (`Cmd+R`).
4. The app appears as a single menu bar icon.

## Menu Controls

- `Folder sorting` toggle (default ON)
- `Sort mode`: Monthly (default) or Daily
- `Use default folder name (Screenshots)` checkbox (default checked)
- Custom folder name text input when default name is unchecked

## Notes

- This is an `LSUIElement` menu bar app, so it does not appear in the Dock.
- Screenshot detection is locale-agnostic and metadata-based: files are only auto-sorted when Spotlight marks them as screenshots (`kMDItemIsScreenCapture` or `kMDItemImageIsScreenshot`).
