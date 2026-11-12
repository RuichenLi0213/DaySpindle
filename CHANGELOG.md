# What changed

## 2.1, compared with 2.0

### New

- **Groups, tasks and milestones.** A task with subtasks becomes a group that spans everything inside it. A milestone can have its own row, or sit on a task's bar.
- **Dependency arrows** between items: Finish → Start, Start → Start, Finish → Finish and Start → Finish. They can leave from and arrive at any of an item's four sides, with their own color and thickness.
- **A details pane on the right** in place of the task editing window. Double-click an item or an arrow to edit it.
- **Completed and the Archive.** Completed items move to the Archive in the sidebar, and return to their place when unmarked (⇧⌘C on a Mac, Ctrl+Shift+C on Windows).
- **Time zones,** like Calendar: an item with a time keeps the moment it was entered in.
- **Workspaces and tabs.** Your items are saved in folders you choose, and several workspaces can be open at once, in tabs along the top of the window.
- **Tips** at the bottom left of the sidebar, folded by default.

### Changed

- **Where your data is saved:** in each workspace's folder (`dayspindle-data.json`), no longer in one file in your user folder. **File › Import Tasks from DaySpindle 2.0…** brings your 2.0 tasks into a workspace and leaves the 2.0 file as it was. See [Upgrading from 2.0](README.md#upgrading-from-20).
- **Moving between a Mac and a PC:** open the same workspace folder on both, instead of exporting and importing a file.
- **Examples:** an `Example Workspace` folder comes with each version and opens by itself the first time. 2.0 added example tasks tagged `#example` to your own list instead.
- **Installing on Windows:** double-click `Start DaySpindle.cmd`. It joins the parts, checks them and unpacks the app by itself; in 2.0 you ran `join-parts.cmd` and unzipped the result yourself. The app is now 8 parts of 20 MB in `Windows/package`, in place of 16 parts of 10 MB.
- **Installing on a Mac:** `DaySpindle-2.1-macOS.zip` unzips straight to `DaySpindle.app`.
- **Layout:** the workspace tabs are the top row of the window, above the dates and the time scale. The date range reads **FROM … TO**, and the Today line is a plain line.
- **Source code:** each version's folder now includes its source code and the script that builds it.

### Removed from this repository

These 2.0 files are replaced by the 2.1 files above: `Windows/join-parts.cmd`, `Windows/DaySpindle-2.0-Windows-x64.zip.001` to `.016`, and `macOS/DaySpindle-2.0-macOS.zip`.
