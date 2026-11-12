'use strict';
/* global Day, Fmt, TimeOfDay, Zones, Color, PALETTE, TodayStyle, Tags, PRESETS, Presets, MAX_WINDOW_DAYS, uuid,
   starterContent, makeTask, exampleContent, Hierarchy, DataFile, KINDS, storedKind, isTimed, displayed, LINK_TYPES,
   linkType, LINK_SIDES, isVerticalSide, exitSide, entrySide, LINK_DEFAULT_WIDTH */

// One workspace: its groups, tasks, milestones, arrows, categories and tags, and every change to
// them. Mirrors the Mac app's Store. Each workspace (tab) has its own Store and its own undo history.

class Store {
  /** `zones` gives the time zone everything is shown in (the computer's, or one chosen in Settings). */
  constructor(bridge, clock, prefs, workspacePath, zones) {
    this.bridge = bridge;
    this.clock = clock;
    this.zones = zones;
    this.workspacePath = workspacePath;
    this.listeners = new Set();
    this.content = starterContent();
    this.window = null;
    this.viewZone = zones.current();
    const now = clock.nowIn(this.viewZone);
    this.today = now.day;
    this.nowMinute = now.minutes;
    this.collapsed = new Set();
    this.hiddenCategories = new Set();
    this.selectedTagKeys = new Set();
    this.showingArchive = false; // showing the Archive (completed items) instead of the main list
    this.selectedTaskID = null;
    this.selectedLinkID = null;
    this.titleFocusID = null;
    this.saveError = null;
    this.notice = null;
    this.undoStack = [];
    this.redoStack = [];
    this.coalescing = null;
    this.scrollRequest = null;
    this.dataPath = '';
    this.lastText = null;
    this.firstWeekday = [0, 1, 6].includes(prefs.firstWeekday) ? prefs.firstWeekday : 0;
    this.todayColorHex = Color.normalizedHex(prefs.todayColor || '') || TodayStyle.defaultHex;
    this.saving = Promise.resolve();
  }

  get workspaceName() { return this.workspacePath.split(/[\\/]/).filter(Boolean).pop() || this.workspacePath; }

  // ---------------------------------------------------------------- Loading & saving
  async load() {
    const r = await this.bridge.workspaceLoad(this.workspacePath);
    this.dataPath = r.path || '';
    if (r.status === 'loaded') {
      try {
        this.adopt(DataFile.decode(r.text), true);
        this.lastText = r.text;
        this.bridge.log(`Loaded ${this.content.tasks.length} items from ${r.path}`);
      } catch (e) {
        await this.bridge.workspaceQuarantine(this.workspacePath);
        this.saveError = `The data file could not be read and was set aside: ${e.message}`;
        this.content = starterContent();
      }
    } else if (r.status === 'unreadable') {
      this.saveError = `The data file could not be read: ${r.error}`;
    } else if (r.status === 'missing-folder') {
      this.saveError = `The workspace folder isn't there any more: ${this.workspacePath}`;
    } else {
      this.bridge.log(`New workspace at ${r.path}`);
    }
    if (!this.content.categories.length) this.content.categories = starterContent().categories;
    this.normalize();
    if (r.status !== 'missing-folder' && r.status !== 'unreadable') this.persist();
  }

  /** Takes a decoded file, upgrading one from version 2.0 (parents become groups). */
  adopt(d, announce) {
    this.content = d.content;
    this.window = d.window;
    this.collapsed = new Set(d.collapsed);
    this.hiddenCategories = new Set(d.hiddenCategories);
    if (d.version < DataFile.CURRENT_VERSION) {
      if (announce) this.bridge.workspaceKeepCopy(this.workspacePath, `dayspindle-data.v${d.version}-backup.json`);
      const [groups, added] = Hierarchy.migrateParentsToGroups(this.content);
      Hierarchy.assignTimeZone(this.content, this.zones.system());
      if (groups && announce) {
        this.notice = `Upgraded for DaySpindle 2.1: ${groups === 1 ? '1 task with subtasks is now a group' : `${groups} tasks with subtasks are now groups`}`
          + (added ? `, and ${added === 1 ? 'its own dates are' : 'their own dates are'} kept as ${added === 1 ? 'a task' : 'tasks'} of the same name inside.` : '.');
      }
      this.bridge.log(`Upgraded data from version ${d.version}: ${groups} groups, ${added} tasks added for their own dates`);
    }
  }

  normalize() {
    Hierarchy.repair(this.content);
    const taskIDs = new Set(this.content.tasks.map((t) => t.id));
    this.collapsed = new Set([...this.collapsed].filter((id) => taskIDs.has(id)));
    const catIDs = new Set(this.content.categories.map((c) => c.id));
    this.hiddenCategories = new Set([...this.hiddenCategories].filter((id) => catIDs.has(id)));
    if (!this.window) this.window = Store.windowAround(this.today);
    if (this.window.end < this.window.start) this.window.end = this.window.start;
    if (this.window.end - this.window.start + 1 > MAX_WINDOW_DAYS) this.window.end = this.window.start + MAX_WINDOW_DAYS - 1;
  }

  /** The default window: 14 days with today near the start. */
  static windowAround(today, days = 14) {
    const start = today - Math.floor((days - 1) / 4);
    return { start, end: start + days - 1 };
  }

  fileText() {
    return DataFile.encode({ content: this.content, window: this.window, collapsed: this.collapsed, hiddenCategories: this.hiddenCategories });
  }

  persist() {
    const text = this.fileText();
    if (text === this.lastText) return;
    this.lastText = text;
    this.saving = this.bridge.workspaceSave(this.workspacePath, text).then((err) => {
      const was = this.saveError;
      if (err) this.saveError = `Could not save to ${this.dataPath}: ${err}`;
      else if (was && was.startsWith('Could not save')) this.saveError = null;
      if (was !== this.saveError) this.emit();
    });
  }

  /** Reads the file again when another program or computer (through OneDrive or iCloud, say)
   * changed it since this app last read or saved it. */
  async reloadIfChanged() {
    const r = await this.bridge.workspaceLoad(this.workspacePath, true);
    if (r.status !== 'loaded' || r.text === this.lastText) return;
    try {
      const d = DataFile.decode(r.text);
      this.adopt(d, false);
      this.lastText = r.text;
      this.normalize();
      this.undoStack = [];
      this.redoStack = [];
      this.notice = 'This workspace changed on disk and was loaded again.';
      this.pruneSelection();
      this.emit();
    } catch { /* keep what's open */ }
  }

  /** Replaces everything with an imported data file (the main process keeps a copy of the old one). */
  replaceAll(decoded, source) {
    this.adopt(decoded, false);
    if (!this.window) this.window = Store.windowAround(this.today);
    this.selectedTagKeys = new Set();
    this.selectedTaskID = null;
    this.selectedLinkID = null;
    this.undoStack = [];
    this.redoStack = [];
    this.saveError = null;
    this.notice = `Imported ${Fmt.itemCount(decoded.content.tasks.length)} from ${source}.`;
    this.normalize();
    this.persist();
    this.emit();
  }

  dismissNotice() { if (this.notice) { this.notice = null; this.emit(); } }

  // ---------------------------------------------------------------- Change notification
  subscribe(fn) { this.listeners.add(fn); return () => this.listeners.delete(fn); }
  emit() { for (const fn of this.listeners) fn(this); }

  // ---------------------------------------------------------------- Lookups
  get categories() { return this.content.categories; }
  get tags() { return this.content.tags; }
  get tasks() { return this.content.tasks; }
  get dependencies() { return this.content.dependencies; }
  category(id) { return this.content.categories.find((c) => c.id === id) || null; }
  /** The item as stored. */
  task(id) { return this.content.tasks.find((t) => t.id === id) || null; }
  /** The item as shown: a timed item's dates and times converted to the time zone being viewed. */
  shown(id) { const t = this.task(id); return t ? displayed(t, this.viewZone) : null; }
  kind(id) { const t = this.task(id); return t ? Hierarchy.effectiveKind(this.content, t) : 'task'; }
  isMark(id) { const t = this.task(id); return !!t && Hierarchy.isMark(this.content, t); }
  hasSubtasks(id) { return Hierarchy.hasStructuralChildren(this.content, id); }
  /** The item's bar color: its own color if set, otherwise its category's. */
  colorHex(task) { return task.colorHex || this.category(task.categoryID)?.colorHex || '#8B8D98'; }
  taskCountForCategory(id) { return this.content.tasks.filter((t) => t.categoryID === id).length; }
  taskCountForTag(tag) { const k = tag.toLowerCase(); return this.content.tasks.filter((t) => t.tags.some((x) => x.toLowerCase() === k)).length; }

  /** First and last day as shown; a group spans everything inside it; an empty group has none. */
  displayDates(id) {
    const t = this.task(id);
    if (!t) return null;
    if (Hierarchy.effectiveKind(this.content, t) !== 'group') { const s = displayed(t, this.viewZone); return { start: s.start, end: s.end }; }
    const inside = [...Hierarchy.descendants(this.content, id)].map((x) => this.task(x))
      .filter((x) => x && Hierarchy.effectiveKind(this.content, x) !== 'group').map((x) => displayed(x, this.viewZone));
    if (!inside.length) return null;
    return { start: Math.min(...inside.map((x) => x.start)), end: Math.max(...inside.map((x) => x.end)) };
  }
  /** Milestones attached to a task, in date order (as shown). */
  marks(id) {
    if (this.kind(id) !== 'task') return [];
    return this.content.tasks.filter((t) => t.parentID === id && storedKind(t) === 'milestone')
      .map((t) => displayed(t, this.viewZone))
      .sort((a, b) => a.start - b.start || String(a.startTime || '').localeCompare(String(b.startTime || '')));
  }
  children(id) { return this.content.tasks.filter((t) => t.parentID === id); }

  // ---------------------------------------------------------------- Filters
  get filtersActive() { return this.hiddenCategories.size > 0 || this.selectedTagKeys.size > 0; }

  // ---------------------------------------------------------------- Archive
  /** Items in the Archive: completed items and everything inside them. A milestone drawn on a task's bar
   * stays with its task (on the bar), so it's in the Archive only when its task is. */
  get archivedIDs() {
    const byID = new Map(this.content.tasks.map((t) => [t.id, t]));
    const memo = new Map();
    const completedHereOrAbove = (id, hops) => {
      const t = id && hops < 10000 ? byID.get(id) : null;
      if (!t) return false;
      if (memo.has(id)) return memo.get(id);
      const r = !!t.completed || completedHereOrAbove(t.parentID, hops + 1);
      memo.set(id, r);
      return r;
    };
    const out = new Set();
    for (const t of this.content.tasks) {
      const archived = Hierarchy.isMark(this.content, t) ? completedHereOrAbove(t.parentID, 0) : completedHereOrAbove(t.id, 0);
      if (archived) out.add(t.id);
    }
    return out;
  }
  /** How many items (not counting milestones on bars) are in the Archive, and outside it. */
  get archiveCount() { const a = this.archivedIDs; return this.content.tasks.filter((t) => a.has(t.id) && !Hierarchy.isMark(this.content, t)).length; }
  get mainCount() { const a = this.archivedIDs; return this.content.tasks.filter((t) => !a.has(t.id) && !Hierarchy.isMark(this.content, t)).length; }
  /** Shows the Archive (completed items) or the main list. */
  showArchive(on) {
    if (!!this.showingArchive === !!on) return;
    this.showingArchive = !!on;
    this.selectedTaskID = null;
    this.emit();
  }
  /** Shows the list (main or Archive) that an item is in. */
  showListFor(id) {
    const t = this.task(id);
    if (!t) return;
    const a = this.archivedIDs;
    const inArchive = Hierarchy.isMark(this.content, t) ? a.has(t.parentID) : a.has(id);
    if (inArchive !== !!this.showingArchive) { this.showingArchive = inArchive; this.emit(); }
  }
  isCategoryShown(id) { return !this.hiddenCategories.has(id); }
  get shownCategories() { return this.content.categories.filter((c) => this.isCategoryShown(c.id)); }

  /** An item shows when its category is checked and it has every selected tag. */
  matchesFilters(t) {
    if (this.hiddenCategories.has(t.categoryID)) return false;
    if (this.selectedTagKeys.size) {
      const keys = new Set(t.tags.map((x) => x.toLowerCase()));
      for (const k of this.selectedTagKeys) if (!keys.has(k)) return false;
    }
    return true;
  }
  get visibleTasks() { return this.content.tasks.filter((t) => this.matchesFilters(t)); }

  clearFilters() {
    this.selectedTagKeys = new Set();
    this.setHiddenCategories(new Set());
    this.showingArchive = false;
    this.emit();
  }
  toggleCategory(id) {
    const h = new Set(this.hiddenCategories);
    if (h.has(id)) h.delete(id); else h.add(id);
    this.setHiddenCategories(h);
    this.emit();
  }
  showOnlyCategory(id) {
    const others = new Set(this.content.categories.map((c) => c.id).filter((x) => x !== id));
    const same = others.size === this.hiddenCategories.size && [...others].every((x) => this.hiddenCategories.has(x));
    this.setHiddenCategories(same ? new Set() : others);
    this.emit();
  }
  showAllCategories() { this.setHiddenCategories(new Set()); this.emit(); }
  setHiddenCategories(h) {
    const same = h.size === this.hiddenCategories.size && [...h].every((x) => this.hiddenCategories.has(x));
    if (same) return;
    this.hiddenCategories = h;
    const sel = this.selectedTaskID && this.task(this.selectedTaskID);
    if (sel && h.has(sel.categoryID)) this.selectedTaskID = null;
    this.persist();
  }
  selectTag(tag, additive) {
    const k = tag.toLowerCase();
    const s = new Set(this.selectedTagKeys);
    if (additive) { if (s.has(k)) s.delete(k); else s.add(k); }
    else if (s.size === 1 && s.has(k)) s.clear();
    else { s.clear(); s.add(k); }
    this.selectedTagKeys = s;
    this.emit();
  }
  removeTagFilter(tag) { this.selectedTagKeys.delete(tag.toLowerCase()); this.emit(); }

  // ---------------------------------------------------------------- Visible range
  get currentPreset() { return Presets.matching(this.window); }
  get windowDays() { return this.window.end - this.window.start + 1; }
  setWindow(w) {
    const n = { start: w.start, end: Math.max(w.end, w.start) };
    if (n.end - n.start + 1 > MAX_WINDOW_DAYS) n.end = n.start + MAX_WINDOW_DAYS - 1;
    if (n.start === this.window.start && n.end === this.window.end) return;
    this.window = n;
    this.persist();
    this.emit();
  }
  setWindowStart(d) {
    if (d > this.window.end) { const k = this.window.end - this.window.start; this.setWindow({ start: d, end: d + k }); }
    else this.setWindow({ start: d, end: this.window.end });
  }
  setWindowEnd(d) { this.setWindow({ start: this.window.start, end: Math.max(d, this.window.start) }); }
  applyPreset(p) { this.setWindow(Presets.windowFor(p, this.window.start)); }
  shiftWindow(dir) {
    const p = this.currentPreset;
    if (p && p.months) { this.setWindow(Presets.windowFor(p, Day.addMonths(this.window.start, p.months * dir))); return; }
    const n = this.windowDays * dir;
    this.setWindow({ start: this.window.start + n, end: this.window.end + n });
  }
  shiftWindowDays(days) {
    if (!days) return;
    const p = this.currentPreset;
    if (p) this.setWindow(Presets.windowFor(p, this.window.start + days));
    else this.setWindow({ start: this.window.start + days, end: this.window.end + days });
  }
  goToToday() {
    this.refreshToday();
    const n = this.windowDays;
    const start = this.today - Math.floor((n - 1) / 4);
    const p = this.currentPreset;
    this.setWindow(p ? Presets.windowFor(p, start) : { start, end: start + n - 1 });
    this.requestScroll(this.today);
    this.emit();
  }
  /** Shifts the window (same length) so an item outside it becomes visible. */
  reveal(id) {
    this.showListFor(id);
    const d = this.displayDates(id);
    this.selectedTaskID = id;
    this.selectedLinkID = null;
    if (d) {
      if (d.end < this.window.start || d.start > this.window.end) {
        const n = this.windowDays;
        const start = d.start - Math.min(2, Math.floor((n - 1) / 4));
        this.setWindow({ start, end: start + n - 1 });
      }
      this.requestScroll(Math.max(d.start, this.window.start));
    }
    this.emit();
  }
  requestScroll(day) { this.scrollRequest = { token: (this.scrollRequest?.token || 0) + 1, day }; }

  // ---------------------------------------------------------------- Today and time zone
  refreshToday() {
    const zone = this.zones.current();
    let changed = false;
    if (zone !== this.viewZone) { this.viewZone = zone; changed = true; this.bridge.log(`Showing times in ${zone}`); }
    const now = this.clock.nowIn(zone);
    if (now.day !== this.today) { this.today = now.day; changed = true; this.bridge.log(`Day changed to ${Day.iso(now.day)}`); }
    if (now.minutes !== this.nowMinute) { this.nowMinute = now.minutes; changed = true; }
    if (changed) this.emit();
  }

  // ---------------------------------------------------------------- Undo
  /** Applies one change as one undo step. Changes with the same `coalesceKey` within two seconds
   * (dragging a color, say) become one step. */
  mutate(actionName, change, coalesceKey = null) {
    const before = this.content;
    const next = structuredClone(this.content);
    change(next);
    Hierarchy.repair(next);
    if (JSON.stringify(next) === JSON.stringify(before)) return false;
    const now = Date.now();
    if (coalesceKey && this.coalescing && this.coalescing.key === coalesceKey && now - this.coalescing.time < 2000) {
      this.coalescing.time = now;
      this.applyContent(next);
      return true;
    }
    this.undoStack.push({ name: actionName, content: before });
    if (this.undoStack.length > 200) this.undoStack.shift();
    this.redoStack = [];
    this.coalescing = coalesceKey ? { key: coalesceKey, time: now } : null;
    this.applyContent(next);
    return true;
  }
  applyContent(next) {
    this.content = next;
    const catIDs = new Set(next.categories.map((c) => c.id));
    this.hiddenCategories = new Set([...this.hiddenCategories].filter((id) => catIDs.has(id)));
    const tagKeys = new Set(next.tags.map((t) => t.toLowerCase()));
    this.selectedTagKeys = new Set([...this.selectedTagKeys].filter((k) => tagKeys.has(k)));
    const taskIDs = new Set(next.tasks.map((t) => t.id));
    this.collapsed = new Set([...this.collapsed].filter((id) => taskIDs.has(id)));
    this.pruneSelection();
    this.persist();
    this.emit();
  }
  pruneSelection() {
    if (this.selectedTaskID && !this.task(this.selectedTaskID)) this.selectedTaskID = null;
    if (this.selectedLinkID && !this.dependency(this.selectedLinkID)) this.selectedLinkID = null;
  }
  get canUndo() { return this.undoStack.length > 0; }
  get canRedo() { return this.redoStack.length > 0; }
  get undoName() { return this.undoStack[this.undoStack.length - 1]?.name || ''; }
  get redoName() { return this.redoStack[this.redoStack.length - 1]?.name || ''; }
  undo() {
    const step = this.undoStack.pop();
    if (!step) return;
    this.coalescing = null;
    this.redoStack.push({ name: step.name, content: this.content });
    this.applyContent(step.content);
  }
  redo() {
    const step = this.redoStack.pop();
    if (!step) return;
    this.coalescing = null;
    this.undoStack.push({ name: step.name, content: this.content });
    this.applyContent(step.content);
  }

  // ---------------------------------------------------------------- Tags
  canonicalTag(name, content) { return content.tags.find((t) => t.toLowerCase() === name.toLowerCase()) || name; }
  registerTags(tags, content) {
    const result = [];
    for (const raw of tags) {
      const n = Tags.normalize(raw);
      if (!n) continue;
      const c = this.canonicalTag(n, content);
      if (!content.tags.includes(c)) content.tags.push(c);
      if (!result.some((r) => r.toLowerCase() === c.toLowerCase())) result.push(c);
    }
    Tags.sort(content.tags);
    return result;
  }
  renameTag(original, newRaw) {
    const newName = Tags.normalize(newRaw);
    if (!newName) return 'Enter a tag name.';
    const oldKey = original.toLowerCase();
    this.mutate('Rename Tag', (c) => {
      const target = c.tags.find((t) => t.toLowerCase() === newName.toLowerCase() && t.toLowerCase() !== oldKey) || newName;
      c.tags = c.tags.filter((t) => t.toLowerCase() !== oldKey && t.toLowerCase() !== target.toLowerCase());
      c.tags.push(target);
      Tags.sort(c.tags);
      for (const t of c.tasks) {
        const seen = new Set();
        t.tags = t.tags.map((x) => (x.toLowerCase() === oldKey ? target : x))
          .filter((x) => { const k = x.toLowerCase(); if (seen.has(k)) return false; seen.add(k); return true; });
      }
    });
    if (this.selectedTagKeys.delete(oldKey)) { this.selectedTagKeys.add(newName.toLowerCase()); this.emit(); }
    return null;
  }
  deleteTag(tag) {
    const k = tag.toLowerCase();
    this.mutate('Delete Tag', (c) => {
      c.tags = c.tags.filter((t) => t.toLowerCase() !== k);
      for (const t of c.tasks) t.tags = t.tags.filter((x) => x.toLowerCase() !== k);
    });
  }

  // ---------------------------------------------------------------- Selection
  select(id) {
    if (this.selectedTaskID === id && (!id || !this.selectedLinkID)) return;
    this.selectedTaskID = id;
    if (id) this.selectedLinkID = null;
    this.emit();
  }
  selectLink(id) {
    if (this.selectedLinkID === id) return;
    this.selectedLinkID = id;
    if (id) this.selectedTaskID = null;
    this.emit();
  }

  // ---------------------------------------------------------------- Creating items
  /** Creates a group, task or milestone, selects it and asks for the details pane with its title
   * ready to type. A milestone created inside a task marks a key moment of that task. */
  newItem(kind, parentID = null, start = null, title = null) {
    // New items aren't completed: show the main list, unless it goes inside an archived item.
    if (this.showingArchive && !(parentID && this.archivedIDs.has(parentID))) this.showingArchive = false;
    let parent = parentID ? this.task(parentID) : null;
    while (parent && storedKind(parent) === 'milestone') parent = parent.parentID ? this.task(parent.parentID) : null;
    const fallback = this.today >= this.window.start && this.today <= this.window.end ? this.today : this.window.start;
    const pd = parent ? this.displayDates(parent.id) : null;
    let s, e;
    if (kind === 'milestone') { s = start ?? pd?.end ?? fallback; e = s; }
    else { s = start ?? pd?.start ?? fallback; e = start == null ? (pd?.end ?? s) : s; }
    const categoryID = parent?.categoryID || this.shownCategories[0]?.id || this.content.categories[0].id;
    const tags = this.content.tags.filter((t) => this.selectedTagKeys.has(t.toLowerCase()));
    const name = kind === 'task' ? (parent ? 'New Subtask' : 'New Task') : `New ${KINDS[kind]}`;
    const item = makeTask({ title: title || name, start: s, end: e, categoryID, tags, parentID: parent?.id || null, kind });
    this.mutate(kind === 'task' && parent ? 'New Subtask' : `New ${KINDS[kind]}`, (c) => { c.tasks.push(item); });
    this.expandAncestors(item.id);
    this.selectedTaskID = item.id;
    this.selectedLinkID = null;
    this.titleFocusID = item.id;
    this.wantsInspector = true;
    this.reveal(item.id);
    return item.id;
  }

  /** Items `taskID` may be placed under: groups and tasks (never milestones), except itself and
   * anything inside it, in outline order. */
  parentCandidates(taskID) {
    const excluded = taskID ? new Set([taskID, ...Hierarchy.descendants(this.content, taskID)]) : new Set();
    return Hierarchy.outline(this.content).filter((o) => !excluded.has(o.task.id) && storedKind(o.task) !== 'milestone');
  }

  /** Checks typed times. Blank means 00:00 on the first day and 24:00 on the last day. */
  parseTimes(startText, endText, start, end, milestone) {
    let startTime = null, endTime = null;
    if (String(startText || '').trim()) {
      startTime = TimeOfDay.normalize(startText);
      if (!startTime) return { error: 'Enter the time like 9:30 or 14:00.' };
    }
    if (milestone) return { startTime, endTime: null };
    if (String(endText || '').trim()) {
      endTime = TimeOfDay.normalize(endText, true);
      if (!endTime) return { error: 'Enter the end time like 17:00, 5pm or 24:00.' };
    }
    if (start === end && (endTime || TimeOfDay.defaultEnd) < (startTime || TimeOfDay.defaultStart)) {
      return { error: "On a one-day task the end time can't be before the start time." };
    }
    return { startTime, endTime };
  }

  /** Keeps an item consistent after an edit made in time zone `zone`. */
  static normalizeItem(t, zone) {
    if (storedKind(t) === 'milestone') { t.end = t.start; t.endTime = null; }
    if (t.end < t.start) t.end = t.start;
    t.timeZone = isTimed(t) ? zone : null;
  }

  /** Creates or replaces a whole item (used by Import and the self-check). Returns an error or null. */
  saveTaskDraft(d) {
    const title = String(d.title || '').trim();
    if (!title) return 'Enter a title.';
    if (d.end < d.start) return "The end date can't be before the start date.";
    if (!this.category(d.categoryID)) return 'Choose a category.';
    let customColor = null;
    if (String(d.colorHex || '').trim()) {
      customColor = Color.normalizedHex(d.colorHex);
      if (!customColor) return 'Enter the color as a hex value, like #2F6FEB.';
    }
    const kind = d.kind || 'task';
    const times = this.parseTimes(d.startTime, d.endTime, d.start, d.end, kind === 'milestone');
    if (times.error) return times.error;
    if (d.parentID && !this.task(d.parentID)) return 'The parent no longer exists.';
    const zone = this.viewZone;
    const savedID = d.taskID || uuid();
    this.mutate(d.taskID ? `Edit ${KINDS[kind]}` : `New ${KINDS[kind]}`, (c) => {
      const tags = this.registerTags(d.tags || [], c);
      const t = makeTask({ id: savedID, title, start: d.start, end: d.end, categoryID: d.categoryID, tags, parentID: d.parentID || null,
        colorHex: customColor, notes: String(d.notes || '').trim() || null, location: String(d.location || '').trim() || null,
        startTime: times.startTime, endTime: times.endTime, kind });
      Store.normalizeItem(t, zone);
      const i = c.tasks.findIndex((x) => x.id === savedID);
      if (i >= 0) c.tasks[i] = t; else c.tasks.push(t);
    });
    this.expandAncestors(savedID);
    this.selectedTaskID = savedID;
    this.emit();
    return null;
  }

  // ---------------------------------------------------------------- Editing items (the details pane)
  /** Applies one edit. A timed item is first expressed in the time zone being viewed, so what you see
   * is what you change (and its moment in time stays right). */
  updateItem(id, action, change, coalesce = null) {
    const zone = this.viewZone;
    return this.mutate(action, (c) => {
      const i = c.tasks.findIndex((x) => x.id === id);
      if (i < 0) return;
      const before = { ...displayed(c.tasks[i], zone) };
      Store.normalizeItem(before, zone);
      const t = { ...before, tags: before.tags.slice() };
      change(t);
      Store.normalizeItem(t, zone);
      if (JSON.stringify(t) === JSON.stringify(before)) return;
      c.tasks[i] = t;
    }, coalesce ? `${coalesce}:${id}` : null);
  }
  setTitle(id, text) {
    const title = String(text || '').trim();
    if (!title) return 'Enter a title.';
    this.updateItem(id, 'Rename', (t) => { t.title = title; });
    return null;
  }
  /** Changes what an item is. An item with subtasks is always a group. */
  setKind(id, kind) {
    const t = this.task(id);
    if (!t) return null;
    if (this.hasSubtasks(id) && kind !== 'group') return 'An item with subtasks is always a group.';
    const zone = this.viewZone;
    const span = this.displayDates(id);
    this.mutate(`Change to ${KINDS[kind]}`, (c) => {
      const i = c.tasks.findIndex((x) => x.id === id);
      if (i < 0) return;
      const item = { ...displayed(c.tasks[i], zone) };
      if (kind === 'group' && span) { item.start = span.start; item.end = span.end; }
      item.kind = kind;
      if (kind === 'milestone') {
        item.end = item.start; item.endTime = null;
        for (const x of c.tasks) if (x.parentID === id) x.parentID = item.parentID || null;
      }
      Store.normalizeItem(item, zone);
      c.tasks[i] = item;
    });
    return null;
  }
  /** New first and last day (as shown). For a milestone, `end` is ignored. */
  setDates(id, start, end) {
    const t = this.task(id);
    if (!t) return null;
    if (Hierarchy.effectiveKind(this.content, t) === 'group') return "A group's dates come from what's inside it.";
    const ms = storedKind(t) === 'milestone';
    if (!ms && end < start) return "The end date can't be before the start date.";
    const sh = this.shown(id);
    if (!ms && start === end && (sh.endTime || TimeOfDay.defaultEnd) < (sh.startTime || TimeOfDay.defaultStart)) {
      return "On a one-day task the end time can't be before the start time.";
    }
    this.updateItem(id, 'Change Dates', (x) => { x.start = start; x.end = ms ? start : end; });
    return null;
  }
  setTimes(id, startText, endText) {
    const t = this.shown(id);
    if (!t) return null;
    const r = this.parseTimes(startText, endText, t.start, t.end, storedKind(t) === 'milestone');
    if (r.error) return r.error;
    this.updateItem(id, 'Change Time', (x) => { x.startTime = r.startTime; x.endTime = r.endTime; });
    return null;
  }
  setParent(id, parentID) {
    if (parentID) {
      const p = this.task(parentID);
      if (!p) return 'That item no longer exists.';
      if (storedKind(p) === 'milestone') return 'Nothing can go inside a milestone.';
      if (parentID === id || Hierarchy.descendants(this.content, id).has(parentID)) return "An item can't go inside itself or one of its own subtasks.";
    }
    this.mutate('Move Into Group', (c) => {
      const x = c.tasks.find((y) => y.id === id);
      if (x) x.parentID = parentID || null;
      c.dependencies = c.dependencies.filter((d) => !Hierarchy.related(c, d.from, d.to));
    });
    this.expandAncestors(id);
    this.emit();
    return null;
  }
  setCategory(id, categoryID) { if (this.category(categoryID)) this.updateItem(id, 'Change Category', (t) => { t.categoryID = categoryID; }); }
  setColor(id, hex) {
    const h = hex ? Color.normalizedHex(hex) : null;
    this.updateItem(id, 'Change Color', (t) => { t.colorHex = h; }, 'color');
  }
  setLocation(id, text) { this.updateItem(id, 'Change Location', (t) => { t.location = String(text || '').trim() || null; }); }
  setNotes(id, text) { this.updateItem(id, 'Change Notes', (t) => { t.notes = String(text || '').trim() || null; }); }
  setTags(id, tags) {
    const zone = this.viewZone;
    this.mutate('Change Tags', (c) => {
      const reg = this.registerTags(tags, c);
      const i = c.tasks.findIndex((x) => x.id === id);
      if (i < 0) return;
      const t = { ...displayed(c.tasks[i], zone), tags: reg };
      Store.normalizeItem(t, zone);
      c.tasks[i] = t;
    });
  }

  /** Saves new dates from a timeline drag (as shown). Dragging a group moves everything in it;
   * moving a task takes its milestones along. */
  updateDates(id, start, end) {
    const t = this.task(id);
    if (!t || end < start) return;
    const k = Hierarchy.effectiveKind(this.content, t);
    if (k === 'group') {
      const span = this.displayDates(id);
      if (!span) return;
      this.shift(new Set([id, ...Hierarchy.descendants(this.content, id)]), start - span.start, 'Move Group');
    } else if (k === 'milestone') {
      this.updateItem(id, 'Move Milestone', (x) => { x.start = start; x.end = start; });
    } else {
      const s = displayed(t, this.viewZone);
      if (s.end - s.start === end - start) {
        const marks = this.content.tasks.filter((x) => x.parentID === id && storedKind(x) === 'milestone').map((x) => x.id);
        this.shift(new Set([id, ...marks]), start - s.start, 'Move Task');
      } else {
        this.updateItem(id, 'Resize Task', (x) => { x.start = start; x.end = end; });
      }
    }
  }
  shift(ids, days, action) {
    if (!days) return;
    const zone = this.viewZone;
    this.mutate(action, (c) => {
      c.tasks = c.tasks.map((x) => {
        if (!ids.has(x.id)) return x;
        const t = { ...displayed(x, zone) };
        t.start += days; t.end += days;
        Store.normalizeItem(t, zone);
        return t;
      });
    });
  }

  deleteMessage(id) {
    const t = this.task(id);
    const kind = this.kind(id);
    const parts = [];
    const marks = this.content.tasks.filter((x) => x.parentID === id && storedKind(x) === 'milestone').length;
    const inside = this.children(id).length;
    if (kind === 'task' && marks) parts.push(marks === 1 ? 'Its milestone is deleted too.' : `Its ${marks} milestones are deleted too.`);
    else if (inside) {
      const parent = t.parentID && this.task(t.parentID);
      parts.push(`${inside === 1 ? 'The item inside it moves' : `The ${inside} items inside it move`} ${parent ? `into “${parent.title}”` : 'to the top level'}.`);
    }
    const links = this.content.dependencies.filter((d) => d.from === id || d.to === id).length;
    if (links) parts.push(links === 1 ? 'Its arrow is removed.' : `Its ${links} arrows are removed.`);
    parts.push('You can undo this with Edit › Undo (Ctrl+Z).');
    return parts.join(' ');
  }
  /** Deletes an item. A task's milestones go with it; anything else inside moves up one level. */
  deleteTask(id) {
    const t = this.task(id);
    if (!t) return;
    const kind = this.kind(id);
    this.mutate(`Delete ${KINDS[kind]}`, (c) => {
      const removed = new Set([id]);
      if (kind === 'task') for (const x of c.tasks) if (x.parentID === id && storedKind(x) === 'milestone') removed.add(x.id);
      for (const x of c.tasks) if (x.parentID === id && !removed.has(x.id)) x.parentID = t.parentID || null;
      c.tasks = c.tasks.filter((x) => !removed.has(x.id));
      c.dependencies = c.dependencies.filter((d) => !removed.has(d.from) && !removed.has(d.to));
    });
    if (this.selectedTaskID === id) { this.selectedTaskID = null; this.emit(); }
  }
  moveOutOfParent(id) {
    const t = this.task(id);
    if (!t || !t.parentID) return;
    const grand = this.task(t.parentID)?.parentID || null;
    this.mutate('Move Out of Group', (c) => { const x = c.tasks.find((y) => y.id === id); if (x) x.parentID = grand; });
    this.selectedTaskID = id;
    this.emit();
  }

  addExampleTasks() {
    this.mutate('Add Example Tasks', (c) => {
      const ex = exampleContent(this.today, c.categories);
      c.categories = ex.categories;
      c.tasks.push(...ex.tasks);
      for (const t of ex.tags) if (!c.tags.some((x) => x.toLowerCase() === t.toLowerCase())) c.tags.push(t);
      Tags.sort(c.tags);
    });
  }

  // ---------------------------------------------------------------- Dependencies
  dependency(id) { return this.content.dependencies.find((d) => d.id === id) || null; }
  predecessors(id) { return this.content.dependencies.filter((d) => d.to === id); }
  successors(id) { return this.content.dependencies.filter((d) => d.from === id); }
  /** Why an arrow from a to b isn't possible, or null when it is. */
  linkProblem(a, b) {
    if (!this.task(a) || !this.task(b)) return 'That item no longer exists.';
    if (a === b) return 'An arrow needs two different items.';
    if (Hierarchy.related(this.content, a, b)) return "A group and an item inside it can't be joined by an arrow.";
    if (this.content.dependencies.some((d) => (d.from === a && d.to === b) || (d.from === b && d.to === a))) return 'These two items are already joined by an arrow.';
    return null;
  }
  /** Adds an arrow (and selects it). Of the sides, only top and bottom are kept: left and right follow the type. */
  addDependency(a, b, type = 'FS', select = true, fromSide = null, toSide = null) {
    if (this.linkProblem(a, b)) return null;
    const d = { id: uuid(), from: a, to: b, type: LINK_TYPES[type] ? type : 'FS', colorHex: null, width: null,
      fromSide: isVerticalSide(fromSide) ? fromSide : null, toSide: isVerticalSide(toSide) ? toSide : null };
    this.mutate('Add Arrow', (c) => { c.dependencies.push(d); });
    if (select) this.selectLink(d.id);
    return d.id;
  }
  updateDependency(id, action, change, coalesce = null) {
    this.mutate(action, (c) => { const d = c.dependencies.find((x) => x.id === id); if (d) change(d); }, coalesce ? `${coalesce}:${id}` : null);
  }
  setDependencyType(id, type) { if (LINK_TYPES[type]) this.updateDependency(id, 'Change Arrow', (d) => { d.type = type; }); }
  /** Moves one end of an arrow to a side of its item. Left and right also set which end of the item the
   * arrow joins (its start or its end); top and bottom keep that. */
  setDependencySide(id, exit, side) {
    if (!LINK_SIDES[side]) return;
    this.updateDependency(id, 'Change Arrow Side', (d) => {
      const t = LINK_TYPES[d.type] || LINK_TYPES.FS;
      if (exit) {
        d.fromSide = isVerticalSide(side) ? side : null;
        if (!isVerticalSide(side)) d.type = linkType(side === 'right', t.toEnd);
      } else {
        d.toSide = isVerticalSide(side) ? side : null;
        if (!isVerticalSide(side)) d.type = linkType(t.fromEnd, side === 'right');
      }
    });
  }
  setDependencyColor(id, hex) {
    const h = hex ? Color.normalizedHex(hex) : null;
    this.updateDependency(id, 'Change Arrow Color', (d) => { d.colorHex = h; }, 'linkcolor');
  }
  setDependencyWidth(id, w) {
    const v = w == null ? null : Math.min(Math.max(+w, 0.25), 8);
    this.updateDependency(id, 'Change Arrow Thickness', (d) => { d.width = v === LINK_DEFAULT_WIDTH ? null : v; }, 'linkwidth');
  }
  reverseDependency(id) {
    this.updateDependency(id, 'Reverse Arrow', (d) => {
      [d.from, d.to] = [d.to, d.from];
      d.type = linkType(LINK_TYPES[d.type].toEnd, LINK_TYPES[d.type].fromEnd);
      [d.fromSide, d.toSide] = [d.toSide || null, d.fromSide || null];
    });
  }
  deleteDependency(id) {
    this.mutate('Delete Arrow', (c) => { c.dependencies = c.dependencies.filter((d) => d.id !== id); });
    if (this.selectedLinkID === id) { this.selectedLinkID = null; this.emit(); }
  }

  // ---------------------------------------------------------------- Order
  moveTask(id, beforeID) {
    const t = this.task(id);
    if (!t || beforeID === id) return;
    if (beforeID && (this.task(beforeID)?.parentID || null) !== (t.parentID || null)) return;
    this.mutate('Reorder', (c) => {
      const from = c.tasks.findIndex((x) => x.id === id);
      if (from < 0) return;
      const [item] = c.tasks.splice(from, 1);
      const to = beforeID ? c.tasks.findIndex((x) => x.id === beforeID) : -1;
      if (to >= 0) c.tasks.splice(to, 0, item);
      else {
        let last = -1;
        c.tasks.forEach((x, i) => { if ((x.parentID || null) === (item.parentID || null)) last = i; });
        if (last >= 0) c.tasks.splice(last + 1, 0, item); else c.tasks.push(item);
      }
    });
    this.selectedTaskID = id;
    this.emit();
  }
  /** Siblings that have their own rows (not milestones drawn on a task's bar), among those listed with it:
   * the unfinished ones, or the completed ones (which are listed after them). */
  siblings(id) {
    const t = this.task(id);
    if (!t) return [];
    return this.content.tasks.filter((x) => (x.parentID || null) === (t.parentID || null) && !Hierarchy.isMark(this.content, x)
      && !!x.completed === !!t.completed);
  }
  /** The first sibling (in stored order) after the last of these, if any. */
  firstListedAfter(sibs) {
    const last = sibs[sibs.length - 1];
    const i = last ? this.content.tasks.findIndex((x) => x.id === last.id) : -1;
    if (i < 0) return null;
    return this.content.tasks.slice(i + 1).find((x) => (x.parentID || null) === (last.parentID || null) && !Hierarchy.isMark(this.content, x))?.id || null;
  }
  /** Marks an item as completed (or not). A completed item moves to the Archive (with everything inside it);
   * its place in the order is kept, so unmarking it returns it to where it was. */
  setCompleted(id, done) {
    const t = this.task(id);
    if (!t || !!t.completed === !!done) return;
    this.mutate(done ? 'Mark as Completed' : 'Mark as Not Completed', (c) => {
      const x = c.tasks.find((y) => y.id === id);
      if (x) x.completed = done ? true : null;
    });
    this.selectedTaskID = id;
    this.emit();
  }
  toggleCompleted(id) { const t = this.task(id); if (t) this.setCompleted(id, !t.completed); }
  canMoveTask(id, offset) {
    const sibs = this.siblings(id);
    const i = sibs.findIndex((x) => x.id === id);
    return i >= 0 && i + offset >= 0 && i + offset < sibs.length;
  }
  moveTaskBy(id, offset) {
    const sibs = this.siblings(id);
    const i = sibs.findIndex((x) => x.id === id);
    if (i < 0 || i + offset < 0 || i + offset >= sibs.length) return;
    if (offset < 0) this.moveTask(id, sibs[i + offset].id);
    else {
      // Before the next one in the list, or (at the end) before the first item listed after this part.
      const after = i + offset + 1;
      this.moveTask(id, after < sibs.length ? sibs[after].id : this.firstListedAfter(sibs));
    }
  }
  moveCategory(id, index) {
    const from = this.content.categories.findIndex((c) => c.id === id);
    if (from < 0) return;
    const to = Math.min(Math.max(index, 0), this.content.categories.length - 1);
    if (to === from) return;
    this.mutate('Reorder Categories', (c) => {
      const [item] = c.categories.splice(from, 1);
      c.categories.splice(to, 0, item);
    });
  }

  // ---------------------------------------------------------------- Preferences
  setFirstWeekday(d) {
    if (![0, 1, 6].includes(d) || d === this.firstWeekday) return;
    this.firstWeekday = d;
    this.bridge.setPref('firstWeekday', d);
    this.emit();
  }
  setTodayColor(hex) {
    const h = Color.normalizedHex(hex);
    if (!h || h === this.todayColorHex) return;
    this.todayColorHex = h;
    this.bridge.setPref('todayColor', h);
    this.emit();
  }

  // ---------------------------------------------------------------- Collapsing groups
  isCollapsed(id) { return this.collapsed.has(id); }
  setCollapsed(id, on) {
    if (on === this.collapsed.has(id)) return;
    if (on) {
      this.collapsed.add(id);
      if (this.selectedTaskID && Hierarchy.ancestors(this.content, this.selectedTaskID).includes(id)) this.selectedTaskID = id;
    } else this.collapsed.delete(id);
    this.persist();
    this.emit();
  }
  toggleCollapsed(id) { this.setCollapsed(id, !this.collapsed.has(id)); }
  expandAll() { if (this.collapsed.size) { this.collapsed = new Set(); this.persist(); this.emit(); } }
  collapseAll() {
    const parents = new Set(this.content.tasks.filter((t) => this.hasSubtasks(t.id)).map((t) => t.id));
    if (parents.size === this.collapsed.size && [...parents].every((x) => this.collapsed.has(x))) return;
    this.collapsed = parents;
    if (this.selectedTaskID) { const a = Hierarchy.ancestors(this.content, this.selectedTaskID); if (a.length) this.selectedTaskID = a[a.length - 1]; }
    this.persist();
    this.emit();
  }
  get hasGroups() { return this.content.tasks.some((t) => this.hasSubtasks(t.id)); }
  expandAncestors(id) {
    const a = Hierarchy.ancestors(this.content, id);
    if (a.some((x) => this.collapsed.has(x))) { for (const x of a) this.collapsed.delete(x); this.persist(); }
  }

  // ---------------------------------------------------------------- Categories
  newCategoryDraft() {
    const used = new Set(this.content.categories.map((c) => c.colorHex.toUpperCase()));
    const hex = (PALETTE.find(([, h]) => !used.has(h)) || PALETTE[0])[1];
    return { categoryID: null, name: '', colorHex: hex, notes: '' };
  }
  editCategoryDraft(id) {
    const c = this.category(id);
    return c ? { categoryID: id, name: c.name, colorHex: c.colorHex, notes: c.notes || '' } : null;
  }
  saveCategoryDraft(d) {
    const name = d.name.trim();
    if (!name) return 'Enter a category name.';
    const hex = Color.normalizedHex(d.colorHex);
    if (!hex) return 'Type a hex color such as #2F6FEB.';
    if (this.content.categories.some((c) => c.name.toLowerCase() === name.toLowerCase() && c.id !== d.categoryID)) {
      return `A category named “${name}” already exists.`;
    }
    const note = String(d.notes || '').trim() || null;
    this.mutate(d.categoryID ? 'Edit Category' : 'New Category', (c) => {
      const x = d.categoryID && c.categories.find((y) => y.id === d.categoryID);
      if (x) { x.name = name; x.colorHex = hex; x.notes = note; }
      else c.categories.push({ id: uuid(), name, colorHex: hex, notes: note });
    });
    return null;
  }
  saveCategoryNote(id, text) {
    const note = String(text || '').trim();
    this.mutate(note ? 'Edit Category Note' : 'Remove Category Note', (c) => {
      const x = c.categories.find((y) => y.id === id);
      if (x) x.notes = note || null;
    });
  }
  categoryFallback(id) { return this.content.categories.find((c) => c.id !== id) || null; }
  deleteCategory(id) {
    const fb = this.categoryFallback(id);
    if (!fb) return;
    this.mutate('Delete Category', (c) => {
      c.categories = c.categories.filter((x) => x.id !== id);
      for (const t of c.tasks) if (t.categoryID === id) t.categoryID = fb.id;
    });
  }

  // ---------------------------------------------------------------- Chart model
  /** Rows in outline order. An item matching the filters appears under its nearest ancestor that also
   * matches (or at the top level); collapsed groups hide what's inside them. Milestones attached to a
   * task are drawn on that task's row instead of their own. */
  chartModel() {
    const zone = this.viewZone;
    const colorByID = new Map(this.content.categories.map((c) => [c.id, c.colorHex]));
    const shownByID = new Map(this.content.tasks.map((t) => [t.id, displayed(t, zone)]));
    const childrenOf = new Map();
    for (const t of this.content.tasks) if (t.parentID) { if (!childrenOf.has(t.parentID)) childrenOf.set(t.parentID, []); childrenOf.get(t.parentID).push(t); }
    const kind = (t) => {
      if (storedKind(t) === 'milestone') return 'milestone';
      if (storedKind(t) === 'group' || (childrenOf.get(t.id) || []).some((c) => storedKind(c) !== 'milestone')) return 'group';
      return 'task';
    };
    const spanCache = new Map();
    const span = (t, depth = 0) => {
      if (spanCache.has(t.id)) return spanCache.get(t.id);
      let r = null;
      if (kind(t) !== 'group' || depth > 100) { const s = shownByID.get(t.id); r = [s.start, s.end]; }
      else for (const c of childrenOf.get(t.id) || []) {
        const cs = span(c, depth + 1);
        if (cs) r = r ? [Math.min(r[0], cs[0]), Math.max(r[1], cs[1])] : cs;
      }
      spanCache.set(t.id, r);
      return r;
    };
    const color = (t) => t.colorHex || colorByID.get(t.categoryID) || '#8B8D98';
    const byIdAll = new Map(this.content.tasks.map((t) => [t.id, t]));
    const markIDs = new Set(this.content.tasks.filter((t) => storedKind(t) === 'milestone' && t.parentID
      && byIdAll.has(t.parentID) && kind(byIdAll.get(t.parentID)) === 'task').map((t) => t.id));

    // The main list or the Archive (completed items and what's inside them).
    const archived = this.archivedIDs, inList = (t) => archived.has(t.id) === !!this.showingArchive;
    const matched = this.content.tasks.filter((t) => !markIDs.has(t.id) && this.matchesFilters(t) && inList(t));
    const matchedIDs = new Set(matched.map((t) => t.id));
    const parentByID = new Map(this.content.tasks.map((t) => [t.id, t.parentID || null]));
    const byParent = new Map();
    for (const t of matched) {
      let p = t.parentID || null, hops = 0;
      while (p && !matchedIDs.has(p) && hops < 10000) { p = parentByID.get(p) || null; hops++; }
      if (!byParent.has(p)) byParent.set(p, []);
      byParent.get(p).push(t);
    }
    const rows = [], visited = new Set();
    const visit = (p, depth) => {
      // Completed items come after the others at the same level, each part in its own order.
      const items = byParent.get(p) || [];
      for (const t of [...items.filter((x) => !x.completed), ...items.filter((x) => x.completed)]) {
        if (visited.has(t.id)) continue;
        visited.add(t.id);
        const s = shownByID.get(t.id), k = kind(t);
        const hasChildren = (byParent.get(t.id) || []).length > 0;
        const collapsed = hasChildren && this.collapsed.has(t.id);
        const dates = span(t);
        const marks = k === 'task'
          ? (childrenOf.get(t.id) || []).filter((m) => markIDs.has(m.id) && this.matchesFilters(m) && inList(m)).map((m) => {
            const ms = shownByID.get(m.id);
            return { id: m.id, day: ms.start, minute: TimeOfDay.minutes(ms.startTime || ''), title: m.title, colorHex: color(m),
              detail: [ms.startTime, ms.location].filter(Boolean).join(' · '), completed: !!m.completed };
          }).sort((a, b) => a.day - b.day || (a.minute ?? 0) - (b.minute ?? 0))
          : [];
        const detail = [];
        if (k === 'group') { const n = (childrenOf.get(t.id) || []).length; detail.push(n === 1 ? '1 item' : `${n} items`); }
        else if (k === 'milestone') { if (s.startTime) detail.push(s.startTime); }
        else { const tt = TimeOfDay.range(s.startTime, s.endTime); if (tt) detail.push(tt); }
        if (s.location) detail.push(s.location);
        rows.push({ id: t.id, title: t.title, start: dates ? dates[0] : s.start, end: dates ? dates[1] : s.end,
          colorHex: color(t), tags: t.tags, depth, hasChildren, collapsed, parentID: t.parentID || null,
          detail: detail.join(' · '), notes: t.notes || null, kind: k, hasDates: !!dates,
          minute: k === 'milestone' ? TimeOfDay.minutes(s.startTime || '') : null, marks, completed: !!t.completed });
        if (!collapsed) visit(t.id, depth + 1);
      }
    };
    visit(null, 0);

    // Where each item is drawn: its own row, its task's row (a milestone mark), or the row of the
    // group it's folded into.
    const rowIDs = new Set(rows.map((r) => r.id));
    const anchorRow = {};
    for (const t of this.content.tasks) {
      let cur = t.id, hops = 0;
      while (cur && !rowIDs.has(cur) && hops++ < 10000) cur = parentByID.get(cur) || null;
      if (cur) anchorRow[t.id] = cur;
    }
    const links = this.content.dependencies.map((d) => ({ id: d.id, from: d.from, to: d.to, type: d.type, colorHex: d.colorHex,
      width: d.width ?? LINK_DEFAULT_WIDTH, exitSide: exitSide(d), entrySide: entrySide(d) }));
    let empty = null;
    if (!rows.length && this.showingArchive) {
      empty = this.filtersActive && this.archiveCount ? 'Nothing in the Archive matches the current filters.'
        : 'The Archive is empty. Mark an item as completed (Ctrl+Shift+C) and it moves here; unmark it to return it to its place.';
    } else if (!rows.length) empty = this.content.tasks.length ? 'Nothing matches the current filters.' : 'Nothing here yet. Click New Task, or double-click the timeline to add a task.';
    return { rows, window: this.window, today: this.today, selectedID: this.selectedTaskID, emptyMessage: empty,
      taskCount: matched.length, firstWeekday: this.firstWeekday, todayHex: this.todayColorHex,
      links, anchorRow, selectedLinkID: this.selectedLinkID, nowMinute: this.nowMinute, archive: !!this.showingArchive };
  }
}

/** Hover text: dates, times, location, milestones and notes. */
function rowToolTip(row, today) {
  if (!row.notes && !row.detail && !(row.marks || []).length && row.kind === 'task') return null;
  const lines = [row.title];
  if (row.hasDates === false) lines.push('Empty group');
  else lines.push((row.kind === 'milestone' ? Fmt.medium(row.start) : Fmt.range(row.start, row.end, Day.year(today))) + (row.detail ? ' · ' + row.detail : ''));
  for (const m of row.marks || []) lines.push(`◆ ${m.title}: ${Fmt.short(m.day)}${m.detail ? ' · ' + m.detail : ''}`);
  if (row.notes) lines.push('', row.notes);
  return lines.join('\n');
}

/** "Now"; `simulated` (yyyy-MM-ddTHH:mm:ss, local time) starts the clock there. */
class Clock {
  constructor(simulated) {
    this.offset = 0;
    if (simulated) {
      const m = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})$/.exec(simulated);
      if (m) this.offset = new Date(+m[1], +m[2] - 1, +m[3], +m[4], +m[5], +m[6]).getTime() - Date.now();
    }
  }
  get isSimulated() { return this.offset !== 0; }
  now() { return new Date(Date.now() + this.offset); }
  /** Today's day and the minutes since midnight in a time zone. */
  nowIn(zone) { return Zones.now(zone, Date.now() + this.offset); }
  today() { return Day.fromDate(this.now()); }
}

if (typeof module !== 'undefined') module.exports = { Store, Clock, rowToolTip };
