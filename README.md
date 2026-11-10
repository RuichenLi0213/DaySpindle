<p align="center">
  <img src="docs/icon.png" width="128" height="128" alt="DaySpindle app icon">
</p>

# DaySpindle

A Gantt chart task manager for macOS and Windows. Plan tasks and subtasks on a day-by-day timeline, color them by category, tag them, and drag their bars to reschedule.

It runs entirely on your computer: no account, no cloud service, no network access. Your tasks live in one readable JSON file, and the Mac and Windows versions use the same file format, so you can move your tasks between them.

![DaySpindle on macOS, showing the example tasks](docs/screenshot.png)

**Version 2.0.** Developed by **Ruichen Li**. Free for everyone to use under the [MIT License](LICENSE). If you share it, keep the author's name with it.


## Choose your version

| | macOS | Windows |
|---|---|---|
| **Download** | [`DaySpindle-2.0-macOS.zip`](macOS/DaySpindle-2.0-macOS.zip) (2.2 MB) | the [`Windows`](Windows) folder: one zip in 7 parts, plus `join-parts.cmd` (158 MB in all) |
| **Needs** | macOS 14 Sonoma or later, on Apple silicon or Intel | Windows 10 or 11, 64-bit (Windows 11 on Arm runs it through emulation) |
| **Size once unpacked** | about 7 MB | about 360 MB |
| **Made with** | Swift (AppKit and SwiftUI), a native Mac app | Electron |
| **Full instructions** | [macOS README](macOS/README.md) | [Windows README](Windows/README.md) |

The two versions look and work the same way. Nothing has to be built or installed: unzip and open.

GitHub accepts files of at most 25 MB through its web page, so the Windows zip is split into 7 parts. [`join-parts.cmd`](Windows/join-parts.cmd) joins them back together on Windows without any extra software. See [Install on Windows](#install-on-windows).


## Features

- A timeline with a month bar, week numbers and weekdays. Choose the range with From/TO dates or a time scale from 1 Week to 1 Year, and scroll sideways through time.
- Tasks with start and end dates, optional start and end times, location and notes. Subtasks nest under their parents and can be collapsed.
- Categories with colors and notes, each with a checkbox to show or hide its tasks. Tags work as filters, and they combine with categories.
- Drag a bar to move a task, drag its ends to change its dates, and drag rows to reorder tasks and categories.
- Light, Dark or System appearance, a Today color you choose, and Sunday, Monday or Saturday as the first day of the week.
- Undo and redo for every change. Each change is saved straight away.


## Download

- **Both versions at once:** click the green **Code** button at the top of this page, choose **Download ZIP** (about 160 MB), and unzip it. The Mac version is in its `macOS` folder, the Windows version in its `Windows` folder.
- **Only the Mac version:** open [`macOS/DaySpindle-2.0-macOS.zip`](macOS/DaySpindle-2.0-macOS.zip) and click the download button (**Download raw file**) at the top right.
- **Only the Windows version:** open the [`Windows`](Windows) folder and download its 7 parts (`DaySpindle-2.0-Windows-x64.zip.001` to `.007`) and `join-parts.cmd` the same way, into one folder.


## Install on a Mac

1. Double-click `DaySpindle-2.0-macOS.zip` to unzip it. Open the `DaySpindle-2.0-macOS` folder it makes, and drag `DaySpindle.app` into **Applications**.
2. Open it. The app isn't signed by an Apple-registered developer or notarized by Apple, so macOS blocks it the first time:
   - **macOS 15 or later:** click **Done**. Open **System Settings › Privacy & Security**, scroll down, click **Open Anyway** next to the message about DaySpindle, and confirm.
   - **macOS 14:** right-click the app, choose **Open**, then click **Open**.

   macOS remembers your choice, so you do this only once.
3. The first start shows a few example tasks around today's date, all tagged **#example**. Delete them when you're ready. **Help › Add Example Tasks** brings them back.

All the details, including where your tasks are kept and how to remove the app, are in the [macOS README](macOS/README.md).


## Install on Windows

1. **Join the parts.** Put the 7 parts and `join-parts.cmd` in one folder, then double-click `join-parts.cmd`. If Windows warns about a file from the internet, click **More info**, then **Run anyway** (or **Run**). It joins the parts into `DaySpindle-2.0-Windows-x64.zip`, checks that the zip is complete, and says **Done**.
2. **Unzip it.** Right-click `DaySpindle-2.0-Windows-x64.zip` and choose **Properties**. If you see **Unblock**, tick it and click **OK**. Then right-click the zip and choose **Extract All**.
3. **Put the `DaySpindle-2.0-Windows-x64` folder where it can stay,** for example `C:\Users\<your name>\DaySpindle`. Don't run the app from inside the zip or from a USB stick, and avoid `C:\Program Files`.
4. **Open the `DaySpindle for Windows` folder and double-click `DaySpindle.exe`.** The app isn't signed by a publisher, so Windows may say "Windows protected your PC". Click **More info**, then **Run anyway**. Windows asks only once.
5. The first start shows the same example tasks as on the Mac.

All the details, including the 7-Zip alternative to step 1, the checksum and troubleshooting, are in the [Windows README](Windows/README.md).


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

  On a PC where DaySpindle has never run, you can instead put the file in the `DaySpindle-2.0-Windows-x64` folder, next to its `README.md`, before the first start. `DaySpindle.exe` imports it on its own.
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

DaySpindle has no account and doesn't connect to the internet. It doesn't collect, track or send any data. Everything you enter stays in the files listed under [Where your tasks are stored](#where-your-tasks-are-stored), on your own computer.


## What's in this repository

| File or folder | What it is |
|---|---|
| [`README.md`](README.md) | this page |
| [`LICENSE`](LICENSE) | the MIT License |
| [`docs`](docs) | the [icon](docs/icon.png) and the [screenshot](docs/screenshot.png) shown on this page |
| [`macOS`](macOS) | the Mac version, [`DaySpindle-2.0-macOS.zip`](macOS/DaySpindle-2.0-macOS.zip), and its [README](macOS/README.md) |
| [`Windows`](Windows) | the Windows version as one zip in 7 parts, [`join-parts.cmd`](Windows/join-parts.cmd), and its [README](Windows/README.md) |

Unzipped, the two versions contain:

```
DaySpindle-2.0-macOS/
├── DaySpindle.app                 the Mac app
├── README.md                      install and use on a Mac
└── LICENSE.txt

DaySpindle-2.0-Windows-x64/
├── DaySpindle for Windows/        the Windows app: DaySpindle.exe and the files it needs
├── README.md                      install and use on Windows
├── LICENSE.txt
└── dayspindle.cmd                 optional: opens DaySpindle from Command Prompt
```


## Developer, license and disclaimer

- **Developer:** DaySpindle is developed by Ruichen Li.
- **License:** [MIT License](LICENSE). In short:
  - **Everyone can use it** for free, for any purpose, including at work and in their own projects. You may also copy, change and share it.
  - **When you share it**, whether the original or a version you've changed, keep the line "Copyright (c) 2026 Ruichen Li" and the license text with it. Including the [`LICENSE`](LICENSE) file is the simplest way. This is how others know the app was developed by Ruichen Li.
  - If you mention DaySpindle somewhere or build on it, a credit such as "DaySpindle by Ruichen Li" with a link to this repository is appreciated.

  The [`LICENSE`](LICENSE) file is the binding text. This summary is only a guide to it.
- **No warranty:** DaySpindle is provided "as is", without warranty of any kind. The developer isn't liable for any loss or damage from using it, including lost tasks. Keep your own backup of anything important.
- **Third-party software:** the Mac version uses only Apple's system frameworks. The Windows version is built with Electron, which includes Chromium, Node.js and other open-source software under their own licenses. Their license texts come with the Windows version, in its `DaySpindle for Windows` folder, as `LICENSE` (Electron) and `LICENSES.chromium.html` (Chromium and the rest).
- **Unsigned apps:** neither app is signed by an Apple-registered developer or a Windows publisher. That is why macOS and Windows ask for confirmation the first time.
- **Trademarks:** Mac and macOS are trademarks of Apple Inc. Windows is a trademark of Microsoft Corporation. DaySpindle isn't affiliated with or endorsed by Apple or Microsoft.
