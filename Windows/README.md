# DaySpindle for Windows

Version 2.0. Developed by Ruichen Li. Released under the [MIT License](../LICENSE).

[Main page](../README.md) · [macOS version](../macOS/README.md)

DaySpindle is a Gantt chart task manager. Plan tasks and subtasks on a day-by-day timeline, color them by category, tag them, and drag their bars to reschedule. It runs entirely on your PC: no account, no cloud service, no network access. Nothing has to be installed.

**Needs:** Windows 10 or Windows 11, 64-bit. Windows 11 on Arm also runs it, through emulation.


## What's in this folder

The app is one zip, `DaySpindle-2.0-Windows-x64.zip` (158 MB). GitHub accepts files of at most 25 MB through its web page, so the zip is split into 16 parts of 10 MB each (the last one is 7.8 MB):

- [`DaySpindle-2.0-Windows-x64.zip.001`](DaySpindle-2.0-Windows-x64.zip.001)
- [`DaySpindle-2.0-Windows-x64.zip.002`](DaySpindle-2.0-Windows-x64.zip.002)
- [`DaySpindle-2.0-Windows-x64.zip.003`](DaySpindle-2.0-Windows-x64.zip.003)
- [`DaySpindle-2.0-Windows-x64.zip.004`](DaySpindle-2.0-Windows-x64.zip.004)
- [`DaySpindle-2.0-Windows-x64.zip.005`](DaySpindle-2.0-Windows-x64.zip.005)
- [`DaySpindle-2.0-Windows-x64.zip.006`](DaySpindle-2.0-Windows-x64.zip.006)
- [`DaySpindle-2.0-Windows-x64.zip.007`](DaySpindle-2.0-Windows-x64.zip.007)
- [`DaySpindle-2.0-Windows-x64.zip.008`](DaySpindle-2.0-Windows-x64.zip.008)
- [`DaySpindle-2.0-Windows-x64.zip.009`](DaySpindle-2.0-Windows-x64.zip.009)
- [`DaySpindle-2.0-Windows-x64.zip.010`](DaySpindle-2.0-Windows-x64.zip.010)
- [`DaySpindle-2.0-Windows-x64.zip.011`](DaySpindle-2.0-Windows-x64.zip.011)
- [`DaySpindle-2.0-Windows-x64.zip.012`](DaySpindle-2.0-Windows-x64.zip.012)
- [`DaySpindle-2.0-Windows-x64.zip.013`](DaySpindle-2.0-Windows-x64.zip.013)
- [`DaySpindle-2.0-Windows-x64.zip.014`](DaySpindle-2.0-Windows-x64.zip.014)
- [`DaySpindle-2.0-Windows-x64.zip.015`](DaySpindle-2.0-Windows-x64.zip.015)
- [`DaySpindle-2.0-Windows-x64.zip.016`](DaySpindle-2.0-Windows-x64.zip.016)
- [`join-parts.cmd`](join-parts.cmd): joins the 16 parts back into `DaySpindle-2.0-Windows-x64.zip`, using only the `copy` and `certutil` commands built into Windows, and checks that the result is complete.
- `README.md`: this page.


## Download

- **Everything at once (easiest):** on the [repository's main page](../), click the green **Code** button and choose **Download ZIP**. Unzip it and open its `Windows` folder.
- **Only this folder:** click each of the 17 files above (the 16 parts and `join-parts.cmd`), then the download button (**Download raw file**) at the top right of its page. Save all of them in one folder.


## Getting started

- [ ] **1. Join the parts.** In the folder with the 16 parts, double-click `join-parts.cmd`.

  If Windows warns about a file from the internet, click **More info**, then **Run anyway** (or **Run**). The script joins the parts, checks the result, and says **Done**. You now have `DaySpindle-2.0-Windows-x64.zip`, and you can delete the parts. If it reports a problem, download the parts again.

  Have 7-Zip? Instead of the script, you can open `DaySpindle-2.0-Windows-x64.zip.001` in 7-Zip (with all 16 parts in the same folder) and extract it directly, then continue with step 3.

- [ ] **2. Unzip it.** Right-click `DaySpindle-2.0-Windows-x64.zip` and choose **Properties**. If you see **Unblock**, tick it and click **OK**. Then right-click the zip, choose **Extract All**, and click **Extract**. Don't open the app from inside the zip.

- [ ] **3. Put the `DaySpindle-2.0-Windows-x64` folder where it can stay,** for example `C:\Users\<your name>\DaySpindle`. You can rename the folder. Don't run DaySpindle from a USB stick, and avoid `C:\Program Files` (copying there needs an administrator).

- [ ] **4. Open the `DaySpindle for Windows` folder and double-click `DaySpindle.exe`.**

  The first time, Windows may say "Windows protected your PC", because the app isn't signed by a publisher. Click **More info**, then **Run anyway**. Windows asks only once.

- [ ] **5. Look around.** The first start shows a few example tasks around today's date, all tagged **#example**, so you can see how DaySpindle works. Delete them when you're ready. **Help › Add Example Tasks** brings them back.

- [ ] **6. Optional: make it easy to open.**
  - While DaySpindle is open, right-click its icon in the taskbar and choose **Pin to taskbar**.
  - Or right-click `DaySpindle.exe` and choose **Pin to Start**.
  - Or right-click `DaySpindle.exe` and choose **Show more options › Send to › Desktop (create shortcut)**.

To check the joined zip by hand, its SHA-256 checksum is `A5D5160303DCB51F063E55D4AD183779F9D5681DE4C5EE7C166FDA37A81DE3F4`. In Command Prompt, in the folder with the zip, run:

```bat
certutil -hashfile DaySpindle-2.0-Windows-x64.zip SHA256
```


## What's in the unzipped folder

- `DaySpindle for Windows\`: the app, `DaySpindle.exe`, and the files it needs (about 360 MB). Keep these files together, and don't move `DaySpindle.exe` out on its own.
- `README.md`: the full instructions, for reading offline.
- `LICENSE.txt`: the license.
- `dayspindle.cmd`: optional. Opens DaySpindle from Command Prompt: `cd` to this folder, then type `dayspindle`.


## Bringing your tasks from a Mac

If you also use the [macOS version](../macOS/README.md), you can take your tasks with you. On the Mac, choose **DaySpindle › Show Data File in Finder**, and copy `dayspindle-data.json` to the PC, by USB stick, OneDrive, Google Drive, Dropbox, iCloud Drive or a network share.

- **Before DaySpindle's first start on the PC:** put `dayspindle-data.json` in the `DaySpindle-2.0-Windows-x64` folder, next to its `README.md`. `DaySpindle.exe` imports it the first time it starts, and shows a note at the top saying so. Click **Dismiss**.
- **If DaySpindle has been used on this PC already:** choose **File › Import Data…** and pick `dayspindle-data.json`. The app asks first, and keeps a copy of the data it replaces. Set the Today color and the rest in **File › Settings**.


## Your data and privacy

DaySpindle doesn't connect to the internet, and it doesn't collect or send any data. Everything stays on your PC:

- **Your tasks:** `%APPDATA%\DaySpindle\dayspindle-data.json`
- **Your settings:** `%APPDATA%\DaySpindle\settings.json`
- **Caches:** `%LOCALAPPDATA%\DaySpindle`

**File › Show Data File** opens that folder. Or paste `%APPDATA%\DaySpindle` into the File Explorer address bar. The data file has the same format as on the Mac. Every change is saved at once. To keep a backup, copy the file somewhere safe. Your tasks are kept outside the app's folder, so replacing the app with a newer version keeps them.


## Moving changes between a Mac and a PC

The Mac and the PC don't sync with each other. Use one at a time, and move the data across when you switch.

- **Mac to PC:** on the Mac, choose **DaySpindle › Show Data File in Finder** and copy the latest `dayspindle-data.json` to the PC. In DaySpindle on the PC, choose **File › Import Data…** and pick it.
- **PC to Mac:** on the PC, choose **File › Export Data…** and copy that file to the Mac. On the Mac, quit DaySpindle, then put the file in `~/Library/Application Support/org.dayspindle.DaySpindle/` as `dayspindle-data.json`, replacing the one there.


## Using DaySpindle on Windows

It works like the Mac version, with these differences:

- Ctrl takes the place of Cmd, and Alt the place of Option. For example: Ctrl+N for a new task, Ctrl+Z to undo, Ctrl+Y to redo, Ctrl+T for today, and Alt+Left / Alt+Right for the previous or next period.
- The menus are in the menu bar at the top of the window.
- Settings is in the **File** menu (Ctrl+,).


## If something isn't right

- **`join-parts.cmd` says a part is missing or the zip is incomplete.** All 16 parts and `join-parts.cmd` must be in the same folder, with their names unchanged. Download any missing or damaged part again, then run `join-parts.cmd` again.
- **You see example tasks instead of the tasks you brought from a Mac.** `dayspindle-data.json` wasn't in the folder when DaySpindle first started, or DaySpindle had already been used on this PC. Choose **File › Import Data…** and pick the file.
- **Nothing seems to happen when you double-click `DaySpindle.exe`.** DaySpindle is probably already open: only one window runs at a time. Look in the taskbar.
- **Your antivirus removed or blocked `DaySpindle.exe`.** Allow it in the antivirus, or unzip the folder again. The app isn't signed by a publisher, which some antivirus programs dislike.


## Removing DaySpindle from the PC

Delete the DaySpindle folder. To remove your tasks and settings too, also delete `%APPDATA%\DaySpindle` and `%LOCALAPPDATA%\DaySpindle`.


## Developer, license and disclaimer

- **Developer:** DaySpindle is developed by Ruichen Li.
- **License:** [MIT License](../LICENSE). The same text comes with the app as `LICENSE.txt`. Anyone may use, copy, change and share DaySpindle for free, for any purpose. When you share it, or a version you've changed, keep the copyright notice "Copyright (c) 2026 Ruichen Li" and the license text with it.
- **No warranty:** DaySpindle is provided "as is", without warranty of any kind. The developer isn't liable for any loss or damage from using it, including lost tasks. Keep your own backup of anything important.
- **Third-party software:** DaySpindle for Windows is built with Electron, which includes Chromium, Node.js and other open-source software under their own licenses. Their license texts come with the app, in the `DaySpindle for Windows` folder, as `LICENSE` (Electron) and `LICENSES.chromium.html` (Chromium and the rest). Keep them with the app when you share it.
- **Trademarks:** Windows is a trademark of Microsoft Corporation. Mac and macOS are trademarks of Apple Inc. DaySpindle isn't affiliated with or endorsed by Microsoft or Apple.
