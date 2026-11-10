# DaySpindle for macOS

Version 2.0. Developed by Ruichen Li. Released under the [MIT License](../LICENSE).

[Main page](../README.md) · [Windows version](../Windows/README.md)

DaySpindle is a Gantt chart task manager. Plan tasks and subtasks on a day-by-day timeline, color them by category, tag them, and drag their bars to reschedule. It runs entirely on your Mac: no account, no cloud service, no network access.

**Needs:** macOS 14 Sonoma or later, on a Mac with Apple silicon or an Intel processor.


## What's in this folder

- [`DaySpindle-2.0-macOS.zip`](DaySpindle-2.0-macOS.zip) (2.2 MB): the app. Unzipped, it's a `DaySpindle-2.0-macOS` folder holding:
  - `DaySpindle.app`: the app
  - `README.md`: these instructions
  - `LICENSE.txt`: the license
- `README.md`: this page.


## Download

Click [`DaySpindle-2.0-macOS.zip`](DaySpindle-2.0-macOS.zip), then the download button (**Download raw file**) at the top right of that page.

Or download both versions at once: on the [repository's main page](../), click the green **Code** button and choose **Download ZIP**.


## Installing

1. Double-click `DaySpindle-2.0-macOS.zip` to unzip it. Open the `DaySpindle-2.0-macOS` folder it makes, and drag `DaySpindle.app` into your **Applications** folder.
2. Open it. macOS blocks it the first time, because the app isn't signed by an Apple-registered developer or notarized by Apple.
   - **macOS 15 or later:** click **Done**. Open **System Settings › Privacy & Security**, scroll down, click **Open Anyway** next to the message about DaySpindle, and confirm.
   - **macOS 14:** right-click the app, choose **Open**, then click **Open**.

   macOS remembers your choice, so you do this only once.
3. The first start shows a few example tasks around today's date, all tagged **#example**, so you can see how DaySpindle works. Delete them when you're ready. **Help › Add Example Tasks** brings them back.


## Getting around

- **New task:** ⌘N. **New subtask:** ⌥⌘N. **New category:** ⇧⌘N.
- **Edit a task:** double-click it, press Return, or press ⌘E. Here you set its dates, optional times, location, notes and tags.
- **Reschedule:** drag a bar to move a task, or drag its ends to change its dates. Drag rows to reorder tasks and categories.
- **Filter:** tick or untick categories in the sidebar, and click tags to show only their tasks. ⌘K clears the filters.
- **Today:** ⌘T. **Previous / next period:** ⌥⌘← / ⌥⌘→.
- **Undo / Redo:** ⌘Z / ⇧⌘Z.
- **Settings:** ⌘, for the appearance (System, Light or Dark), the Today color and the first day of the week.


## Your data and privacy

DaySpindle doesn't connect to the internet, and it doesn't collect or send any data. Everything stays on your Mac:

- **Your tasks:** `~/Library/Application Support/org.dayspindle.DaySpindle/dayspindle-data.json`
- **The copy from your previous session:** `dayspindle-data.previous.json`, in the same folder
- **Your settings:** the app's preferences, `org.dayspindle.DaySpindle`

Every change is saved straight away. **DaySpindle › Show Data File in Finder** shows the file. To keep a backup, copy that file somewhere safe. Your tasks are kept outside the app, so replacing the app with a newer version keeps them.


## Moving your tasks to Windows

The [Windows version](../Windows/README.md) uses the same file format.

1. On the Mac, choose **DaySpindle › Show Data File in Finder**, and copy `dayspindle-data.json` to the PC.
2. On the PC, in DaySpindle, choose **File › Import Data…** and pick the file. The app asks before it replaces anything.

   Before DaySpindle's first start on a PC, you can instead put `dayspindle-data.json` in the `DaySpindle-2.0-Windows-x64` folder, next to its README. `DaySpindle.exe` then imports it on its own.

To bring changes back, choose **File › Export Data…** on the PC. On the Mac, quit DaySpindle, put the file in `~/Library/Application Support/org.dayspindle.DaySpindle/` as `dayspindle-data.json`, replacing the one there, and open DaySpindle again.

The Mac and the PC don't sync with each other. Use one at a time, and move the file when you switch.


## Removing DaySpindle

1. Quit DaySpindle and move `DaySpindle.app` to the Trash.
2. To remove your tasks and settings too, delete the folder `~/Library/Application Support/org.dayspindle.DaySpindle`. Then run this in Terminal:

   ```bash
   defaults delete org.dayspindle.DaySpindle
   ```


## Developer, license and disclaimer

- **Developer:** DaySpindle is developed by Ruichen Li.
- **License:** [MIT License](../LICENSE). The same text comes with the app as `LICENSE.txt`. Anyone may use, copy, change and share DaySpindle for free, for any purpose. When you share it, or a version you've changed, keep the copyright notice "Copyright (c) 2026 Ruichen Li" and the license text with it.
- **No warranty:** DaySpindle is provided "as is", without warranty of any kind. The developer isn't liable for any loss or damage from using it, including lost tasks. Keep your own backup of anything important.
- **Third-party software:** the Mac version uses only Apple's system frameworks. It includes no third-party code.
- **Trademarks:** Mac and macOS are trademarks of Apple Inc. DaySpindle isn't affiliated with or endorsed by Apple.
