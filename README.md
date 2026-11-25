# Reading Stash

A macOS menu bar app for links and documents you want to read later. Drag a link or file toward the lower-right corner and release on **Drop to Stash**. Click the stack in the menu bar to open your reading list, or rest the pointer in the corner for half a second.

In Firefox, drag the site icon beside the address. Dragging the tab itself can leave the app without a URL. If Quick Note gets in the way, turn off its lower-right shortcut in System Settings → Desktop & Dock → Hot Corners.

The list is newest first. Search by title, URL, or filename. Click an item to open it and tick the box when you're done. Saving the same link again moves it to the top of Unread.

## Build

Requires macOS 14 or later and the Xcode Command Line Tools.

```sh
./build.sh
open "build/Reading Stash.app"
```

Run `./check.sh` in a macOS desktop session. The checks use temporary libraries and test pasteboards.

## Storage

The library lives in `~/Library/Application Support/Reading Stash/`. Links are bookmarks. Files are copied into the library, so you can move or delete the originals. Back up the whole folder to keep both the index and the files.
