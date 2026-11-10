<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/icon-dark.png">
    <img src="docs/icon.png" width="128" height="128" alt="DaySpindle app icon">
  </picture>
</p>

# DaySpindle

A Gantt chart task manager for macOS and Windows. Plan tasks and subtasks on a day-by-day timeline, color them by category, tag them, and drag their bars to reschedule.

It runs entirely on your computer: no account, no cloud service, no network access. Your tasks live in one readable JSON file, and the Mac and Windows versions use the same file format, so you can move your tasks between them.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/screenshot-dark.png">
  <img src="docs/screenshot.png" alt="DaySpindle on macOS, showing the example tasks">
</picture>

Version 2.0. Developed by Ruichen Li. Free for everyone to use under the [MIT License](#developer-license-and-disclaimer). If you share it, keep the author's name with it.

## Which version do I need?

This repository holds both versions, ready to use. Nothing has to be built or installed.

| | macOS | Windows |
|---|---|---|
| **Folder** | [`DaySpindle-2.0-macOS`](DaySpindle-2.0-macOS) | [`DaySpindle-2.0-Windows-x64`](DaySpindle-2.0-Windows-x64) |
| **Needs** | macOS 14 Sonoma or later, on Apple silicon or Intel | Windows 10 or 11, 64-bit (Windows 11 on Arm runs it through emulation) |
| **Size** | about 7 MB | about 360 MB |
| **Made with** | Swift (AppKit and SwiftUI), a native Mac app | Electron |
| **Full instructions** | [macOS README](DaySpindle-2.0-macOS/README.md) | [Windows README](DaySpindle-2.0-Windows-x64/README.md) |

The two versions look and work the same way. Each folder also has its own `README.md` and `LICENSE.txt`.

## Features

- A timeline with a month bar, week numbers and weekdays. Choose the range with From/TO dates or a time scale from 1 Week to 1 Year, and scroll sideways through time.
- Tasks with start and end dates, optional start and end times, location and notes. Subtasks nest under their parents and can be collapsed.
- Categories with colors and notes, each with a checkbox to show or hide its tasks. Tags work as filters, and they combine with categories.
- Drag a bar to move a task, drag its ends to change its dates, and drag rows to reorder tasks and categories.
- Light, Dark or System appearance, a Today color you choose, and Sunday, Monday or Saturday as the first day of the week.
- Undo and redo for every change. Each change is saved straight away.

## Download

1. Click the green **Code** button at the top of this page and choose **Download ZIP**.
2. Unzip it, and keep the folder for your system: `DaySpindle-2.0-macOS` or `DaySpindle-2.0-Windows-x64`.

If you use Git: install [Git LFS](https://git-lfs.com) first, then clone the repository as usual. The Windows app's largest file, `DaySpindle.exe`, is stored with Git LFS.

## Install on a Mac

1. Open the `DaySpindle-2.0-macOS` folder and drag `DaySpindle.app` into **Applications**.
2. Open it. The app isn't signed by an Apple-registered developer or notarized by Apple, so macOS blocks it the first time:
   - **macOS 15 or later:** click **Done**. Open **System Settings › Privacy & Security**, scroll down, click **Open Anyway** next to the message about DaySpindle, and confirm.
   - **macOS 14:** right-click the app, choose **Open**, then click **Open**.

   macOS remembers your choice, so you do this only once.
3. The first start shows a few example tasks around today's date, all tagged **#example**. Delete them when you're ready. **Help › Add Example Tasks** brings them back.

More in the [macOS README](DaySpindle-2.0-macOS/README.md).

## Install on Windows

1. Before you unzip: right-click the downloaded zip and choose **Properties**. If you see **Unblock**, tick it and click **OK**. Then right-click the zip and choose **Extract All**.
2. Put the `DaySpindle-2.0-Windows-x64` folder where it can stay, for example `C:\Users\<your name>\DaySpindle`. You can rename it. Don't run the app from inside the zip or from a USB stick, and avoid `C:\Program Files`.
3. Open the `DaySpindle for Windows` folder and double-click `DaySpindle.exe`. The app isn't signed by a publisher, so Windows may say "Windows protected your PC". Click **More info**, then **Run anyway**. Windows asks only once.
4. The first start shows the same example tasks as on the Mac.

To open it more easily, right-click its taskbar icon while it runs and choose **Pin to taskbar**. More in the [Windows README](DaySpindle-2.0-Windows-x64/README.md).

## Where your tasks are stored

| | macOS | Windows |
|---|---|---|
| **Your tasks** | `~/Library/Application Support/org.dayspindle.DaySpindle/dayspindle-data.json` | `%APPDATA%\DaySpindle\dayspindle-data.json` |
| **Copy from the previous session** | `dayspindle-data.previous.json`, in the same folder | `dayspindle-data.previous.json`, in the same folder |
| **Your settings** | the app's preferences, `org.dayspindle.DaySpindle` | `%APPDATA%\DaySpindle\settings.json` |
| **Show the file** | **DaySpindle › Show Data File in Finder** | **File › Show Data File** |

Your tasks are kept outside the app's folder, so replacing the app with a newer version keeps them. To back them up, copy `dayspindle-data.json` somewhere safe.

## Moving your tasks between a Mac and a PC

The two versions don't sync with each other. Use one at a time, and move the file when you switch.

- **Mac to PC:** on the Mac, choose **DaySpindle › Show Data File in Finder** and copy `dayspindle-data.json` to the PC. In DaySpindle on the PC, choose **File › Import Data…** and pick it. The app asks first, and keeps a copy of the data it replaces.

  On a PC where DaySpindle has never run, you can instead put the file in the `DaySpindle-2.0-Windows-x64` folder, next to its README, before the first start. `DaySpindle.exe` imports it on its own.
- **PC to Mac:** on the PC, choose **File › Export Data…** and copy the file to the Mac. On the Mac, quit DaySpindle, then put the file in `~/Library/Application Support/org.dayspindle.DaySpindle/` as `dayspindle-data.json`, replacing the one there.

## Keyboard shortcuts

| Action | Mac | Windows |
|---|---|---|
| New task / new subtask / new category | ⌘N / ⌥⌘N / ⇧⌘N | Ctrl+N / Ctrl+Alt+N / Ctrl+Shift+N |
| Edit selected task | ⌘E or Return | Ctrl+E, Enter, or double-click |
| Delete selected task | Delete | Delete |
| Move selected task up / down | ⌥⌘↑ / ⌥⌘↓ | Alt+↑ / Alt+↓ |
| Collapse / expand selected parent | ← / → | ← / → |
| Today | ⌘T | Ctrl+T |
| Previous / next period | ⌥⌘← / ⌥⌘→ | Alt+← / Alt+→ |
| All Tasks / Clear Filters | ⌘1 / ⌘K | Ctrl+1 / Ctrl+K |
| Settings | ⌘, | Ctrl+, |
| Undo / Redo | ⌘Z / ⇧⌘Z | Ctrl+Z / Ctrl+Y |

On Windows the menus are in the window's menu bar, and **Settings…** is in the **File** menu.

## Removing DaySpindle

- **macOS:** quit DaySpindle and move `DaySpindle.app` to the Trash. To remove your tasks and settings too, delete `~/Library/Application Support/org.dayspindle.DaySpindle` and run `defaults delete org.dayspindle.DaySpindle` in Terminal.
- **Windows:** delete the DaySpindle folder. To remove your tasks and settings too, also delete `%APPDATA%\DaySpindle` and `%LOCALAPPDATA%\DaySpindle`.

## Privacy

DaySpindle has no account and doesn't connect to the internet. It doesn't collect, track or send any data. Everything you enter stays in the files listed above, on your own computer.

## What's in this repository

```
├── README.md                      this file
├── LICENSE                        MIT License
├── docs/                          the icon and screenshots shown above
├── DaySpindle-2.0-macOS/
│   ├── DaySpindle.app             the Mac app
│   ├── README.md                  install and use on a Mac
│   └── LICENSE.txt
└── DaySpindle-2.0-Windows-x64/
    ├── DaySpindle for Windows/    the Windows app: DaySpindle.exe and the files it needs
    ├── README.md                  install and use on Windows
    ├── LICENSE.txt
    └── dayspindle.cmd             optional: opens DaySpindle from Command Prompt
```

## Developer, license and disclaimer

- **Developer:** DaySpindle is developed by Ruichen Li.
- **License:** MIT License. The full text is in [`LICENSE`](LICENSE). In short:
  - **Everyone can use it** for free, for any purpose, including at work and in their own projects. You may also copy, change and share it.
  - **When you share it**, whether the original or a version you've changed, keep the line "Copyright (c) 2026 Ruichen Li" and the license text with it. Including the `LICENSE` file is the simplest way. This is how others know the app was developed by Ruichen Li.
  - If you mention DaySpindle somewhere or build on it, a credit such as "DaySpindle by Ruichen Li" with a link to this repository is appreciated.

  The `LICENSE` file is the binding text. This summary is only a guide to it.
- **No warranty:** DaySpindle is provided "as is", without warranty of any kind. The developer isn't liable for any loss or damage from using it, including lost tasks. Keep your own backup of anything important.
- **Third-party software:** the Mac version uses only Apple's system frameworks. The Windows version is built with Electron, which includes Chromium, Node.js and other open-source software under their own licenses. Their license texts are in `DaySpindle-2.0-Windows-x64/DaySpindle for Windows/`, as `LICENSE` (Electron) and `LICENSES.chromium.html` (Chromium and the rest).
- **Unsigned apps:** neither app is signed by an Apple-registered developer or a Windows publisher. That is why macOS and Windows ask for confirmation the first time.
- **Trademarks:** Mac and macOS are trademarks of Apple Inc. Windows is a trademark of Microsoft Corporation. DaySpindle isn't affiliated with or endorsed by Apple or Microsoft.
