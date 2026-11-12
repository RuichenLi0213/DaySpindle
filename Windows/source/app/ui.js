'use strict';
/* global Day, Fmt, TimeOfDay, Zones, Weeks, Color, PALETTE, TodayStyle, Tags, PRESETS, Hierarchy, DataFile, KINDS,
   storedKind, LINK_TYPES, linkType, LINK_SIDES, exitSide, entrySide, linkTypeForSides, LINK_DEFAULT_WIDTH, LINK_WIDTHS, Store, Clock, Theme, Icons, GanttChart, CH */

// The window: workspace tabs, sidebar, toolbar, filter bar, chart, the details pane on the right,
// sheets (category, tag, Today color, settings, confirmations), popovers and shortcuts.

const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const $ = (sel, root = document) => root.querySelector(sel);
const $$ = (sel, root = document) => [...root.querySelectorAll(sel)];
function h(html) { const t = document.createElement('template'); t.innerHTML = html.trim(); return t.content.firstElementChild; }
const clamp = (v, lo, hi) => Math.min(Math.max(v, lo), hi);

const INSTRUCTIONS = [
  'Mark an item as completed (Ctrl+Shift+C or in its details) to move it to the Archive in the sidebar. Unmark it there to return it to its place.',
  'Check a category to show it; Ctrl-click shows only it.',
  'Click a tag to filter; Ctrl-click adds more tags.',
  'Drag categories or rows to reorder them. A subtask stays inside its group.',
  'Drag a bar to move it; drag its ends to change dates. Dragging a group moves everything in it.',
  'Point at a bar, then drag one of the round handles on its four sides onto another item to draw an arrow.',
  'Double-click an item or arrow to see and edit it on the right.',
  'Right-click the Today header for its color and the first day of the week.',
];
const EXAMPLE_WORKSPACE = 'Example Workspace';
const EXAMPLE_NOTE = 'Done with the examples? Close this tab (× on the tab), then delete the “Example Workspace” folder in File Explorer. File > New Workspace… starts your own.';
const APPEARANCES = { system: ['System', 'desktop', 'light'], light: ['Light', 'sun', 'dark'], dark: ['Dark', 'moon', 'system'] };
const SIDEBAR = { def: 232, min: 180, max: 420, minContent: 640 };
const INSPECTOR = { def: 340, min: 280, max: 560 };

/** The marker for an item's kind, in its color: dot (task), diamond (milestone), square (group). */
const kindIcon = (kind, hex, size = 10) =>
  `<span class="kind-icon ${kind}" style="width:${size}px;height:${size}px;background:${esc(hex)}"></span>`;

class App {
  async start() {
    this.config = await window.bridge.config();
    this.isMac = this.config.platform === 'darwin';
    this.clock = new Clock(this.config.simulatedNow);
    const prefs = this.config.prefs;
    this.prefs = prefs;
    this.timeZone = Zones.valid(prefs.timeZone) ? prefs.timeZone : null;
    this.zones = { current: () => this.timeZone || this.systemZone(), system: () => this.systemZone() };
    this.appearance = prefs.appearance || 'system';
    this.sidebarWidth = prefs.sidebarWidth || SIDEBAR.def;
    this.inspectorWidth = prefs.inspectorWidth || INSPECTOR.def;
    this.inspectorVisible = prefs.inspectorVisible !== false;
    this.stores = new Map();
    this.store = null;
    this.tabs = this.config.tabs;
    this.sheet = null;
    this.popover = null;
    this.keys = {};

    const s = () => this.store;
    this.chart = new GanttChart($('#chart'), {
      onSelect: (id) => s()?.select(id),
      onOpen: (id) => this.openInspector(id),
      onDelete: (id) => this.requestDeleteTask(id),
      onCommit: (id, a, b) => s()?.updateDates(id, a, b),
      onReveal: (id) => s()?.reveal(id),
      onCreate: (day) => this.newItem('task', null, day),
      onToggle: (id) => s()?.toggleCollapsed(id),
      onNewSubtask: (id) => this.newItem('task', id),
      onAddMilestone: (id) => this.newItem('milestone', id),
      onMoveOut: (id) => s()?.moveOutOfParent(id),
      parentTitle: (id) => s()?.task(id)?.title,
      onReorder: (id, before) => s()?.moveTask(id, before),
      onMoveBy: (id, off) => s()?.moveTaskBy(id, off),
      onComplete: (id, done) => s()?.setCompleted(id, done),
      canMoveBy: (id, off) => !!s()?.canMoveTask(id, off),
      onTodayColor: (hex) => s()?.setTodayColor(hex),
      onCustomTodayColor: () => this.openTodayColor(),
      onFirstWeekday: (d) => s()?.setFirstWeekday(d),
      onShiftDays: (n) => s()?.shiftWindowDays(n),
      onTaskListWidth: (w) => window.bridge.setPref('taskListWidth', w),
      onLink: (a, as, b, bs) => { if (!s()?.addDependency(a, b, linkTypeForSides(as, bs), true, as, bs)) window.bridge.log('Arrow refused'); },
      canLink: (a, b) => !s()?.linkProblem(a, b),
      onSelectLink: (id) => s()?.selectLink(id),
      onOpenLink: (id) => { s()?.selectLink(id); this.setInspectorVisible(true); },
      onDeleteLink: (id) => s()?.deleteDependency(id),
      onLinkType: (id, t) => s()?.setDependencyType(id, t),
      onLinkSide: (id, exit, side) => s()?.setDependencySide(id, exit, side),
    });
    this.chart.setTaskListWidth(prefs.taskListWidth || CH.defaultTaskListWidth, false);

    this.installSidebar();
    this.installSidebarHandle();
    this.installInspectorHandle();
    this.installToolbar();
    this.installTabBar();
    this.installFilterBar();
    this.installInspector();
    this.installKeyboard();
    window.bridge.onCommand((c, v) => this.command(c, v));
    window.bridge.onTabsChanged((t) => this.setTabs(t));
    window.bridge.onRefreshToday(() => this.store?.refreshToday());
    window.bridge.onAppFocus(() => this.appFocused());
    window.bridge.onAppearanceChanged((mode) => { this.appearance = mode; this.keys = {}; this.render(); });
    window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', () => { this.chart.drawNow(); this.keys = {}; this.render(); });
    window.addEventListener('resize', () => { this.applySidebarWidth(); this.applyInspector(); });
    document.addEventListener('visibilitychange', () => { if (!document.hidden) this.store?.refreshToday(); });
    setInterval(() => { this.store?.refreshToday(); this.renderTimeZone(); }, this.clock.isSimulated ? 1000 : 15000);

    this.applySidebarWidth();
    await this.setTabs(this.tabs);
    window.app = this;
  }

  systemZone() {
    const sim = this.config.simulatedTimeZone;
    return sim && Zones.valid(sim) ? sim : Zones.system();
  }

  // ---------------------------------------------------------------- Workspaces
  async setTabs(t) {
    this.tabs = t;
    for (const p of [...this.stores.keys()]) if (!t.list.some((e) => e.path === p)) this.stores.delete(p);
    await this.activate(t.active);
  }

  async activate(path) {
    const entry = this.tabs.list.find((e) => e.path === path);
    const prev = this.store;
    if (!entry || !entry.exists) {
      this.store = null;
      this.keys = {};
      this.render();
      return;
    }
    let s = this.stores.get(path);
    if (!s) {
      s = new Store(window.bridge, this.clock, { firstWeekday: prev?.firstWeekday ?? this.prefs.firstWeekday,
        todayColor: prev?.todayColorHex ?? this.prefs.todayColor }, path, this.zones);
      await s.load();
      if (this.tabs.found === path) s.notice = `Opened the workspace next to DaySpindle: ${path}.${s.notice ? ' ' + s.notice : ''}`;
      s.subscribe(() => { if (this.store === s) this.render(); });
      this.stores.set(path, s);
    } else {
      await s.reloadIfChanged();
    }
    if (prev && prev !== s) { s.firstWeekday = prev.firstWeekday; s.todayColorHex = prev.todayColorHex; }
    this.store = s;
    s.refreshToday();
    this.keys = {};
    this.chart.didInitialScroll = false;
    this.chart.lastScrollToken = -1;
    this.chart.hoverItem = null;
    this.chart.drag = null;
    this.chart.linkDraft = null;
    this.render();
    this.chart.layout();
  }

  selectTab(path) {
    if (!this.tabs.list.some((e) => e.path === path) || this.tabs.active === path) return;
    this.tabs.active = path;
    window.bridge.selectTab(path);
    this.activate(path);
  }

  stepTab(offset) {
    const list = this.tabs.list;
    const i = list.findIndex((e) => e.path === this.tabs.active);
    if (list.length < 2 || i < 0) return;
    this.selectTab(list[(i + offset + list.length) % list.length].path);
  }

  async appFocused() {
    const t = await window.bridge.tabs();
    const changed = JSON.stringify(t.list) !== JSON.stringify(this.tabs.list);
    if (changed) { await this.setTabs(t); return; }
    await this.store?.reloadIfChanged();
    this.store?.refreshToday();
  }

  // ---------------------------------------------------------------- Rendering
  render() {
    const s = this.store;
    this.renderTabBar();
    this.renderTimeZone();
    this.renderWelcome();
    if (!s) {
      $('#sidebar-scroll').innerHTML = '';
      $('#sidebar-clear').innerHTML = '';
      $('#toolbar').innerHTML = '';
      $('#filterbar').innerHTML = '';
      $('#messages').innerHTML = '';
      this.keys = { welcome: this.keys.welcome, tabs: this.keys.tabs, tz: this.keys.tz };
      $('#chart').style.display = 'none';
      this.applyInspector();
      window.bridge.menuState({ hasWorkspace: false, sheetOpen: !!this.sheet });
      return;
    }
    $('#chart').style.display = '';
    this.renderSidebar();
    this.renderToolbar();
    this.renderFilterBar();
    this.renderMessages();
    this.chart.setModel(s.chartModel());
    this.chart.handleScrollRequest(s.scrollRequest);
    this.applyInspector();
    this.renderInspector();
    const sel = s.selectedTaskID;
    window.bridge.menuState({
      hasWorkspace: true,
      canUndo: s.canUndo, undoName: s.undoName, canRedo: s.canRedo, redoName: s.redoName,
      hasSelection: !!sel, selectionKind: sel ? s.kind(sel) : null, selectionCompleted: !!(sel && s.task(sel)?.completed), selectionIsMark: !!(sel && s.isMark(sel)),
      canMoveUp: !!sel && s.canMoveTask(sel, -1), canMoveDown: !!sel && s.canMoveTask(sel, 1),
      preset: s.currentPreset?.title || null, firstWeekday: s.firstWeekday, sheetOpen: !!this.sheet,
      hasGroups: s.hasGroups, filtersActive: s.filtersActive, inspectorVisible: this.inspectorVisible,
    });
  }

  changed(name, key) {
    if (this.keys[name] === key) return false;
    this.keys[name] = key;
    return true;
  }

  // ---------------------------------------------------------------- Sidebar
  applySidebarWidth() {
    const upper = Math.max(SIDEBAR.min, Math.min(SIDEBAR.max, window.innerWidth - 1 - SIDEBAR.minContent));
    const w = clamp(this.sidebarWidth, SIDEBAR.min, upper);
    $('#sidebar').style.width = `${w}px`;
    $('#sidebar-handle').style.left = `${w - 4}px`;
  }

  installSidebarHandle() {
    const hd = $('#sidebar-handle');
    hd.title = 'Drag to resize the sidebar. Double-click to reset.';
    hd.addEventListener('dblclick', () => { this.sidebarWidth = SIDEBAR.def; this.applySidebarWidth(); this.applyInspector(); window.bridge.setPref('sidebarWidth', SIDEBAR.def); });
    hd.addEventListener('mousedown', (e) => {
      if (e.button !== 0 || e.detail > 1) return;
      e.preventDefault();
      const x0 = e.clientX, w0 = $('#sidebar').offsetWidth;
      document.body.classList.add('resizing');
      const move = (ev) => { this.sidebarWidth = clamp(Math.round(w0 + ev.clientX - x0), SIDEBAR.min, SIDEBAR.max); this.applySidebarWidth(); this.applyInspector(); };
      const up = () => {
        window.removeEventListener('mousemove', move, true);
        window.removeEventListener('mouseup', up, true);
        document.body.classList.remove('resizing');
        window.bridge.setPref('sidebarWidth', this.sidebarWidth);
      };
      window.addEventListener('mousemove', move, true);
      window.addEventListener('mouseup', up, true);
    });
  }

  renderSidebar() {
    const s = this.store;
    const key = JSON.stringify([s.workspacePath, s.categories, s.tags, [...s.hiddenCategories], [...s.selectedTagKeys], s.tasks.length,
      s.tasks.map((t) => [t.categoryID, t.tags, t.parentID, !!t.completed]), !!s.showingArchive, Theme.dark]);
    if (!this.changed('sidebar', key)) return;
    const check = `<span class="check">${Icons.check(11)}</span>`;
    const rows = [];
    const allSelected = !s.filtersActive && !s.showingArchive;
    rows.push(`<div class="side-row ${allSelected ? 'selected' : ''}" data-act="all" data-ctl="All Tasks">
      <span class="icon">${Icons.tray(15)}</span><span class="name"><span>All Items</span></span>
      <span class="count">${s.mainCount}</span>${allSelected ? check : ''}</div>`);
    // Completed items, out of the main list. Unmark one to return it to its place.
    rows.push(`<div class="side-row ${s.showingArchive ? 'selected' : ''}" data-act="archive" data-ctl="Archive"
        title="Completed items. Select one and unmark it to return it to its place.">
      <span class="icon">${Icons.archive(15)}</span><span class="name"><span>Archive</span></span>
      <span class="count">${s.archiveCount}</span>${s.showingArchive ? check : ''}</div>`);
    rows.push(`<div class="section-header">Categories<span class="grow"></span>
      <span class="add" data-act="newCategory" title="New Category">${Icons.plus(12)}</span></div>`);
    s.categories.forEach((c, i) => {
      const shown = s.isCategoryShown(c.id);
      const mark = Color.prefersLightText(c.colorHex) ? '#FFFFFF' : '#1D1D1F';
      rows.push(`<div class="side-row cat ${shown ? '' : 'hidden-cat'}" data-cat="${c.id}" data-index="${i}" data-ctl="Category ${esc(c.name)}" title="${esc(c.notes || '')}">
        <span class="icon"><span class="checkbox" style="border-color:${c.colorHex};background:${shown ? c.colorHex : 'transparent'};color:${mark}">${shown ? Icons.svg('<path d="M3.5 8.4 6.6 11.4 12.5 4.8"/>', 10, 'stroke-width="2.4"') : ''}</span></span>
        <span class="name"><span>${esc(c.name)}</span>${c.notes ? `<span class="note-icon" data-ctl="Note icon ${esc(c.name)}">${Icons.note(12)}</span>` : ''}</span>
        <span class="count hideable">${s.taskCountForCategory(c.id)}</span>
        <span class="edit" data-edit-cat="${c.id}" title="Edit">${Icons.pencil(12)}</span></div>`);
    });
    rows.push('<div class="section-header">Tags</div>');
    if (!s.tags.length) rows.push('<div class="side-hint">Add #tags to an item and they’ll appear here.</div>');
    for (const tag of s.tags) {
      const sel = s.selectedTagKeys.has(tag.toLowerCase());
      rows.push(`<div class="side-row tag ${sel ? 'selected' : ''}" data-tag="${esc(tag)}" data-ctl="Tag ${esc(tag)}">
        <span class="icon" style="font-size:14px">#</span><span class="name"><span>${esc(tag)}</span></span>
        <span class="count hideable">${s.taskCountForTag(tag)}</span>${sel ? check : ''}
        <span class="edit" data-edit-tag="${esc(tag)}" title="Edit">${Icons.pencil(12)}</span></div>`);
    }
    $('#sidebar-scroll').innerHTML = rows.join('');
    $('#sidebar-clear').innerHTML = s.filtersActive
      ? `<button class="pill" data-act="clear" data-ctl="Sidebar Clear Filters">${Icons.filter(13)}<span>Clear Filters</span></button>` : '';
    this.renderInstructions();
  }

  /** The tips at the bottom of the sidebar, folded under "Tips" (click to unfold; remembered). In the
   * Example Workspace, a note above them says how to remove it. */
  renderInstructions() {
    const example = this.store?.workspaceName === EXAMPLE_WORKSPACE;
    const open = !!this.prefs.tipsExpanded;
    $('#instructions').innerHTML = (example ? `<div class="example-note" data-ctl="Example workspace note"><span>ⓘ</span><span>${esc(EXAMPLE_NOTE)}</span></div>` : '')
      + `<button class="tips-toggle ${open ? 'open' : ''}" data-ctl="Tips" title="${open ? 'Fold the tips' : 'Show tips on using DaySpindle'}">
          <span class="chev">${Icons.chevronRight(9)}</span><span>Tips</span></button>`
      + (open ? INSTRUCTIONS.map((l) => `<div class="tip"><span>•</span><span>${esc(l)}</span></div>`).join('') : '');
  }

  installSidebar() {
    $('#instructions').addEventListener('click', (e) => {
      if (!e.target.closest('.tips-toggle')) return;
      this.prefs.tipsExpanded = !this.prefs.tipsExpanded;
      window.bridge.setPref('tipsExpanded', this.prefs.tipsExpanded);
      this.renderInstructions();
    });
    const root = $('#sidebar-scroll');
    $('#sidebar-clear').addEventListener('click', () => this.store?.clearFilters());
    root.addEventListener('mousedown', (e) => {
      if (e.button !== 0) return;
      if (e.target.closest('.edit')) { e.stopPropagation(); return; }
      const cat = e.target.closest('.side-row.cat');
      if (!cat) return;
      e.preventDefault();
      this.trackCategoryDrag(cat, e);
    });
    root.addEventListener('click', (e) => {
      const s = this.store;
      if (!s) return;
      const edit = e.target.closest('.edit');
      if (edit) {
        if (edit.dataset.editCat) this.openCategoryEditor(s.editCategoryDraft(edit.dataset.editCat));
        else this.openTagEditor(edit.dataset.editTag);
        return;
      }
      const act = e.target.closest('[data-act]')?.dataset.act;
      if (act === 'all') s.clearFilters();
      else if (act === 'archive') s.showArchive(true);
      else if (act === 'newCategory') this.openCategoryEditor(s.newCategoryDraft());
      const tag = e.target.closest('.side-row.tag');
      if (tag) s.selectTag(tag.dataset.tag, e.ctrlKey || e.metaKey);
    });
    root.addEventListener('contextmenu', (e) => {
      const cat = e.target.closest('.side-row.cat');
      const tag = e.target.closest('.side-row.tag');
      if (cat) { e.preventDefault(); this.categoryMenu(cat.dataset.cat); }
      else if (tag) { e.preventDefault(); this.tagMenu(tag.dataset.tag); }
    });
    $('#timezone').addEventListener('click', (e) => {
      const b = e.target.closest('.tz');
      if (b) this.openTimeZonePicker(b);
    });
  }

  trackCategoryDrag(rowEl, down) {
    const s = this.store;
    const id = rowEl.dataset.cat, from = +rowEl.dataset.index;
    const rowsEls = $$('.side-row.cat', $('#sidebar-scroll'));
    const pitch = rowsEls.length > 1 ? rowsEls[1].offsetTop - rowsEls[0].offsetTop : rowEl.offsetHeight + 1;
    const n = s.categories.length;
    let dragging = false, offset = 0;
    const target = () => clamp(from + Math.round(offset / pitch), 0, Math.max(n - 1, 0));
    const move = (e) => {
      offset = e.clientY - down.clientY;
      if (!dragging) {
        if (Math.abs(offset) <= 4) return;
        dragging = true;
        rowEl.classList.add('dragging');
        rowsEls.forEach((r) => { if (r !== rowEl) r.classList.add('shifting'); });
      }
      const to = target();
      rowEl.style.transform = `translateY(${offset}px)`;
      rowsEls.forEach((r, i) => {
        if (r === rowEl) return;
        let dy = 0;
        if (from < to && i > from && i <= to) dy = -pitch;
        if (to < from && i >= to && i < from) dy = pitch;
        r.style.transform = dy ? `translateY(${dy}px)` : '';
      });
    };
    const up = (e) => {
      window.removeEventListener('mousemove', move, true);
      window.removeEventListener('mouseup', up, true);
      if (dragging) {
        rowsEls.forEach((r) => { r.style.transform = ''; r.classList.remove('shifting', 'dragging'); });
        this.keys.sidebar = null;
        if (target() !== from) s.moveCategory(id, target()); else this.renderSidebar();
      } else if (e.ctrlKey || e.metaKey) s.showOnlyCategory(id);
      else s.toggleCategory(id);
    };
    window.addEventListener('mousemove', move, true);
    window.addEventListener('mouseup', up, true);
  }

  categoryMenu(id) {
    const s = this.store, c = s.category(id);
    if (!c) return;
    window.bridge.popup([
      { label: `Show Only “${c.name}”`, id: 'only' },
      { label: 'Show All Categories', id: 'all', enabled: s.hiddenCategories.size > 0 },
      { type: 'separator' },
      { label: c.notes ? 'Edit Note…' : 'Add Note…', id: 'note' },
      { label: 'Edit Category…', id: 'edit' },
      { label: 'Delete Category…', id: 'delete' },
    ]).then((r) => {
      if (r === 'only') s.showOnlyCategory(id);
      else if (r === 'all') s.showAllCategories();
      else if (r === 'note') this.openCategoryNote(id);
      else if (r === 'edit') this.openCategoryEditor(s.editCategoryDraft(id));
      else if (r === 'delete') this.requestDeleteCategory(id);
    });
  }

  tagMenu(tag) {
    window.bridge.popup([{ label: 'Rename Tag…', id: 'rename' }, { label: 'Delete Tag…', id: 'delete' }]).then((r) => {
      if (r === 'rename') this.openTagEditor(tag);
      else if (r === 'delete') this.requestDeleteTag(tag);
    });
  }

  // ---------------------------------------------------------------- Time zone
  renderTimeZone() {
    const zone = this.zones.current();
    const key = JSON.stringify([zone, !!this.timeZone, Zones.offsetText(zone)]);
    if (!this.changed('tz', key)) return;
    $('#timezone').innerHTML = `<div class="tz" data-ctl="Time Zone" title="Time zone for times and for “today”. Timed items keep their moment in time, like Apple Calendar.">
      <span class="icon">${Icons.globe(13)}</span><span><div class="city">${esc(Zones.city(zone))}</div>
      <div class="sub">${Zones.offsetText(zone)} · ${this.timeZone ? 'chosen time zone' : "this computer's time zone"}</div></span></div>`;
  }

  setTimeZone(zone) {
    this.timeZone = zone && Zones.valid(zone) ? zone : null;
    window.bridge.setPref('timeZone', this.timeZone);
    for (const st of this.stores.values()) st.refreshToday();
    this.keys.tz = null;
    this.render();
  }

  /** Chooses the time zone times are shown in: this computer's (it follows you when you travel) or a fixed one. */
  openTimeZonePicker(anchor) {
    if (this.popover?.anchor === anchor) { this.closePopover(); return; }
    const el = h(`<div class="popover tz-list" data-ctl="Time zone list">
      <div class="caption">Show times in</div>
      <input class="input" data-ctl="Time zone search" placeholder="Search, e.g. Tokyo or Berlin" spellcheck="false">
      <div class="rows"></div></div>`);
    const input = $('input', el), rows = $('.rows', el);
    const all = Zones.all();
    const render = () => {
      const q = input.value.trim().toLowerCase().replace(/ /g, '_');
      const list = q ? all.filter((z) => z.toLowerCase().includes(q) || Zones.offsetText(z).toLowerCase().includes(q)) : all;
      const ck = (on) => (on ? `<span class="ck">${Icons.check(11)}</span>` : '');
      const out = [];
      if (!q) {
        out.push(`<div class="row" data-zone="" data-ctl="Time zone System"><span><div class="t">This computer's time zone</div>
          <div class="d">${esc(Zones.label(this.systemZone()))}, follows you when you travel</div></span><span class="grow"></span>${ck(!this.timeZone)}</div>`);
      }
      for (const z of list.slice(0, 600)) {
        out.push(`<div class="row" data-zone="${esc(z)}" data-ctl="Time zone ${esc(z)}"><span><div class="t">${esc(z.replace(/_/g, ' '))}</div>
          <div class="d">${Zones.offsetText(z)}</div></span><span class="grow"></span>${ck(this.timeZone === z)}</div>`);
      }
      rows.innerHTML = out.join('');
    };
    input.addEventListener('input', render);
    rows.addEventListener('click', (e) => {
      const r = e.target.closest('[data-zone]');
      if (!r) return;
      this.closePopover();
      this.setTimeZone(r.dataset.zone || null);
    });
    render();
    this.showPopover(el, anchor);
    input.focus();
  }

  // ---------------------------------------------------------------- Tabs
  renderTabBar() {
    const t = this.tabs;
    const key = JSON.stringify([t, Theme.dark]);
    if (!this.changed('tabs', key)) return;
    const counts = new Map();
    for (const e of t.list) counts.set(e.name, (counts.get(e.name) || 0) + 1);
    const title = (e) => (counts.get(e.name) > 1 ? `${e.name} — ${e.path.split(/[\\/]/).slice(-2, -1)[0] || ''}` : e.name);
    $('#tabbar').innerHTML = `<div class="tabs">${t.list.map((e) => `
      <span class="ws-tab ${e.path === t.active ? 'selected' : ''} ${e.exists ? '' : 'missing'}" data-path="${esc(e.path)}" title="${esc(e.path)}" data-ctl="Workspace tab ${esc(e.name)}">
        <span class="folder">${e.exists ? Icons.folder(13) : Icons.warning(13)}</span><span>${esc(title(e))}</span>
        <span class="x" data-close="${esc(e.path)}" title="Close this tab (the folder is kept)">${Icons.xmark(9)}</span></span>`).join('')}</div>
      <button class="pill plain icon small" data-act="addWorkspace" data-ctl="Add Workspace" title="New or open a workspace">${Icons.plus(12)}</button>`;
  }

  installTabBar() {
    const bar = $('#tabbar');
    bar.addEventListener('click', (e) => {
      const x = e.target.closest('[data-close]');
      if (x) { e.stopPropagation(); window.bridge.closeTab(x.dataset.close); return; }
      const tab = e.target.closest('.ws-tab');
      if (tab) { this.selectTab(tab.dataset.path); return; }
      const add = e.target.closest('[data-act="addWorkspace"]');
      if (add) this.workspaceMenu(add);
    });
    bar.addEventListener('contextmenu', (e) => {
      const tab = e.target.closest('.ws-tab');
      if (!tab) return;
      e.preventDefault();
      const p = tab.dataset.path, entry = this.tabs.list.find((x) => x.path === p);
      window.bridge.popup([
        { label: this.isMac ? 'Show in Finder' : 'Show in File Explorer', id: 'reveal' },
        ...(entry && !entry.exists ? [{ label: 'Locate Folder…', id: 'locate' }] : []),
        { type: 'separator' },
        { label: 'Move Tab Left', id: 'left' }, { label: 'Move Tab Right', id: 'right' },
        { type: 'separator' },
        { label: 'Close Tab', id: 'close' },
      ]).then((r) => {
        if (r === 'reveal') window.bridge.revealTab(p);
        else if (r === 'locate') window.bridge.locateTab(p);
        else if (r === 'left') window.bridge.moveTab(p, -1);
        else if (r === 'right') window.bridge.moveTab(p, 1);
        else if (r === 'close') window.bridge.closeTab(p);
      });
    });
  }

  workspaceMenu(anchor) {
    const r = anchor.getBoundingClientRect();
    window.bridge.popup([
      { label: 'New Workspace…', id: 'new' },
      { label: 'Open Workspace…', id: 'open' },
      ...(this.tabs.legacy ? [{ label: 'Import Tasks from DaySpindle 2.0…', id: 'import' }] : []),
    ], { x: r.left, y: r.bottom + 4 }).then((id) => {
      if (id === 'new') window.bridge.newWorkspace();
      else if (id === 'open') window.bridge.openWorkspace();
      else if (id === 'import') window.bridge.importLegacy();
    });
  }

  /** Welcome (no workspace open) or "Can't find the workspace folder". */
  renderWelcome() {
    const t = this.tabs, s = this.store;
    const entry = t.list.find((e) => e.path === t.active);
    const key = JSON.stringify([!!s, entry, t.legacy]);
    if (!this.changed('welcome', key)) return;
    const w = $('#welcome');
    if (s) { w.classList.remove('open'); w.innerHTML = ''; return; }
    w.classList.add('open');
    if (entry && !entry.exists) {
      w.innerHTML = `<div class="muted">${Icons.warning(30)}</div><h1>Can't find the workspace folder</h1>
        <div class="path">${esc(entry.path)}</div>
        <p>It may have been moved, renamed or deleted, or it's on a drive that isn't connected.</p>
        <div class="buttons"><button class="pill prominent" data-act="locate">Locate Folder…</button><button class="pill" data-act="close">Close Tab</button></div>`;
    } else {
      w.innerHTML = `<div style="color:var(--accent)">${Icons.folderPlus(34)}</div><h1>Welcome to DaySpindle 2.1</h1>
        <p>Your groups, tasks and milestones live in a workspace: a folder you choose, on this PC, in OneDrive or on a USB stick. Move or copy the folder to another computer and open it there to carry on.</p>
        <div class="buttons"><button class="pill prominent" data-act="new" data-ctl="Welcome New Workspace">New Workspace…</button>
        <button class="pill" data-act="open" data-ctl="Welcome Open Workspace">Open Workspace…</button></div>
        ${t.legacy ? '<button class="pill plain" data-act="import">Import My Tasks from DaySpindle 2.0…</button>' : ''}`;
    }
    w.onclick = (e) => {
      const a = e.target.closest('[data-act]')?.dataset.act;
      if (a === 'new') window.bridge.newWorkspace();
      else if (a === 'open') window.bridge.openWorkspace();
      else if (a === 'import') window.bridge.importLegacy();
      else if (a === 'locate') window.bridge.locateTab(entry.path);
      else if (a === 'close') window.bridge.closeTab(entry.path);
    };
  }

  // ---------------------------------------------------------------- Toolbar
  renderToolbar() {
    const s = this.store;
    const w = s.window, p = s.currentPreset;
    const [title, icon, next] = APPEARANCES[this.appearance] || APPEARANCES.system;
    const key = JSON.stringify([w, p?.title, this.appearance, s.today, this.inspectorVisible]);
    if (!this.changed('toolbar', key)) return;
    $('#toolbar').innerHTML = `
      <span style="display:flex;align-items:center">
        <button class="pill" data-ctl="New Task" title="New Task (Ctrl+N)">${Icons.plus(13)}<span class="new-label">New Task</span></button>
        <button class="pill plain icon" data-ctl="New menu" title="New group, task or milestone">${Icons.chevronDown(10)}</button>
      </span>
      <span class="spacer"></span>
      <span class="range">
        <span class="label">FROM</span>
        <button class="pill" data-ctl="First visible day" title="First visible day"><span class="date-icon muted">${Icons.calendar(13)}</span><span>${Fmt.medium(w.start)}</span></button>
        <span class="label">TO</span>
        <button class="pill" data-ctl="Last visible day" title="Last visible day"><span class="date-icon muted">${Icons.calendar(13)}</span><span>${Fmt.medium(w.end)}</span></button>
      </span>
      <button class="pill" data-ctl="Time scale" title="Time scale"><span>${p ? p.title : Fmt.dayCount(s.windowDays)}</span><span class="muted">${Icons.chevronDown(10)}</span></button>
      <span class="spacer"></span>
      <span class="segmented">
        <button class="pill icon" data-ctl="Previous period" title="Previous period (Alt+Left)">${Icons.chevronLeft(12)}</button>
        <span class="sep"></span>
        <button class="pill" data-ctl="Today" title="Bring today into view (Ctrl+T)">Today</button>
        <span class="sep"></span>
        <button class="pill icon" data-ctl="Next period" title="Next period (Alt+Right)">${Icons.chevronRight(12)}</button>
      </span>
      <button class="pill icon" data-ctl="Appearance" data-mode="${this.appearance}" title="Appearance: ${title}. Click for ${APPEARANCES[next][0]}. Right-click to choose.">${Icons[icon](15)}</button>
      <button class="pill icon ${this.inspectorVisible ? '' : 'plain'}" data-ctl="Details" title="${this.inspectorVisible ? 'Hide' : 'Show'} Details (Ctrl+I)">${Icons.sidebarRight(15)}</button>`;
  }

  installToolbar() {
    const tb = $('#toolbar');
    tb.addEventListener('click', (e) => {
      const s = this.store;
      const b = e.target.closest('button');
      if (!b || !s) return;
      switch (b.dataset.ctl) {
        case 'New Task': this.newItem('task'); break;
        case 'New menu': this.newMenu(b); break;
        case 'First visible day': this.openDayPicker(b, { day: s.window.start, onPick: (d) => s.setWindowStart(d) }); break;
        case 'Last visible day': this.openDayPicker(b, { day: s.window.end, minDay: s.window.start, onPick: (d) => s.setWindowEnd(d) }); break;
        case 'Time scale': this.timeScaleMenu(b); break;
        case 'Previous period': s.shiftWindow(-1); break;
        case 'Today': s.goToToday(); break;
        case 'Next period': s.shiftWindow(1); break;
        case 'Appearance': this.setAppearance(APPEARANCES[this.appearance][2]); break;
        case 'Details': this.setInspectorVisible(!this.inspectorVisible); break;
        default:
      }
      b.blur();
    });
    tb.addEventListener('contextmenu', (e) => {
      const b = e.target.closest('[data-ctl="Appearance"]');
      if (!b) return;
      e.preventDefault();
      window.bridge.popup(Object.entries(APPEARANCES).map(([mode, [t]]) => ({ label: t, id: mode, checked: this.appearance === mode, radio: true })))
        .then((m) => { if (m) this.setAppearance(m); });
    });
  }

  /** "+ New ▾": a group, task or milestone, or one inside the selected item. */
  newMenu(anchor) {
    if (this.popover?.anchor === anchor) { this.closePopover(); return; }
    const s = this.store, sel = s.selectedTaskID, selKind = sel ? s.kind(sel) : null;
    const items = [['group', 'New Group', 'Ctrl+Shift+G', null], ['task', 'New Task', 'Ctrl+N', null], ['milestone', 'New Milestone', 'Ctrl+Shift+M', null]];
    if (sel && selKind !== 'milestone') {
      items.push(null, ['task', 'New Subtask Inside', 'Ctrl+Alt+N', sel], ['milestone', selKind === 'task' ? 'Milestone for This Task' : 'Milestone Inside', '', sel]);
    }
    const el = h(`<div class="popover newmenu" data-ctl="New items">${items.map((it, i) => (it
      ? `<div class="it" data-i="${i}" data-ctl="${esc(it[1])}">${kindIcon(it[0], '#2F6FEB', 9)}<span>${esc(it[1])}</span><span class="k">${esc(it[2])}</span></div>`
      : '<div class="sep"></div>')).join('')}</div>`);
    el.addEventListener('click', (e) => {
      const it = e.target.closest('[data-i]');
      if (!it) return;
      const [kind, , , parent] = items[+it.dataset.i];
      this.closePopover();
      this.newItem(kind, parent);
    });
    this.showPopover(el, anchor);
  }

  setAppearance(mode) {
    this.appearance = mode;
    window.bridge.setPref('appearance', mode);
    this.keys.toolbar = null;
    this.render();
  }

  timeScaleMenu(anchor) {
    const s = this.store, p = s.currentPreset;
    const items = [{ label: 'Time Scale', id: 'title', enabled: false },
      ...PRESETS.map((x, i) => ({ label: x.title, id: String(i), checked: p === x, radio: true }))];
    if (!p) items.push({ type: 'separator' }, { label: `Custom: ${Fmt.range(s.window.start, s.window.end, Day.year(s.today))}`, id: 'custom', enabled: false });
    const r = anchor.getBoundingClientRect();
    window.bridge.popup(items, { x: r.left, y: r.bottom + 4 }).then((id) => { if (id != null && PRESETS[+id]) s.applyPreset(PRESETS[+id]); });
  }

  // ---------------------------------------------------------------- Filter bar & messages
  renderFilterBar() {
    const s = this.store;
    const key = JSON.stringify([s.workspacePath, s.filtersActive, [...s.hiddenCategories], [...s.selectedTagKeys], s.categories, s.tags, s.visibleTasks.length, s.tasks.length]);
    if (!this.changed('filter', key)) return;
    const fb = $('#filterbar');
    if (!s.filtersActive) { fb.innerHTML = ''; return; }
    const parts = ['<span class="muted">Showing</span>'];
    if (s.hiddenCategories.size) {
      const shown = s.shownCategories;
      if (!shown.length) parts.push('<span class="muted">no categories</span>');
      for (const c of shown) parts.push(`<span class="chip"><span class="dot" style="background:${c.colorHex}"></span>${esc(c.name)}</span>`);
    }
    for (const t of s.tags.filter((x) => s.selectedTagKeys.has(x.toLowerCase()))) {
      parts.push(`<span class="chip removable">#${esc(t)}<span class="x" data-remove-tag="${esc(t)}" title="Remove this filter">${Icons.xmark(9)}</span></span>`);
    }
    parts.push(`<span class="spacer"></span><span class="muted" data-ctl="Filter count">${s.visibleTasks.length} of ${s.tasks.length} items</span>`);
    parts.push('<button class="pill small" data-ctl="Clear Filters" title="Show all categories and clear the tag filter (Ctrl+K)">Clear Filters</button>');
    fb.innerHTML = parts.join('');
  }

  installFilterBar() {
    $('#filterbar').addEventListener('click', (e) => {
      const x = e.target.closest('[data-remove-tag]');
      if (x) this.store?.removeTagFilter(x.dataset.removeTag);
      else if (e.target.closest('[data-ctl="Clear Filters"]')) this.store?.clearFilters();
    });
    $('#messages').addEventListener('click', (e) => { if (e.target.closest('[data-act="dismiss"]')) this.store?.dismissNotice(); });
  }

  renderMessages() {
    const s = this.store;
    const key = JSON.stringify([s.workspacePath, s.saveError, s.notice]);
    if (!this.changed('messages', key)) return;
    const out = [];
    if (s.saveError) out.push(`<div class="message error" data-ctl="Save error"><span class="grow">${esc(s.saveError)}</span></div>`);
    if (s.notice) out.push(`<div class="message notice" data-ctl="Notice"><span>${Icons.info(13)}</span><span class="grow">${esc(s.notice)}</span><button class="pill small plain" data-act="dismiss">Dismiss</button></div>`);
    $('#messages').innerHTML = out.join('');
    requestAnimationFrame(() => this.chart.layout());
  }

  // ---------------------------------------------------------------- Creating items
  newItem(kind, parentID = null, day = null) {
    const s = this.store;
    if (!s) return;
    s.newItem(kind, parentID, day);
    this.setInspectorVisible(true);
  }

  openInspector(id) {
    this.store?.showListFor(id);
    this.store?.select(id);
    this.setInspectorVisible(true);
  }

  // ---------------------------------------------------------------- Details pane
  setInspectorVisible(on) {
    if (this.inspectorVisible === on) { this.render(); return; }
    this.inspectorVisible = on;
    window.bridge.setPref('inspectorVisible', on);
    this.keys.toolbar = null;
    this.keys.inspector = null;
    this.render();
  }

  applyInspector() {
    const on = !!this.store && this.inspectorVisible;
    const sw = $('#sidebar').offsetWidth || this.sidebarWidth;
    const upper = Math.max(240, Math.min(INSPECTOR.max, window.innerWidth - sw - 2 - 440));
    const w = Math.min(Math.max(this.inspectorWidth, Math.min(INSPECTOR.min, upper)), upper);
    const insp = $('#inspector'), hd = $('#inspector-handle');
    insp.classList.toggle('open', on);
    hd.classList.toggle('open', on);
    insp.style.width = `${w}px`;
    hd.style.left = `${window.innerWidth - w - 5}px`;
  }

  installInspectorHandle() {
    const hd = $('#inspector-handle');
    hd.title = 'Drag to resize the details. Double-click to reset.';
    hd.addEventListener('dblclick', () => { this.inspectorWidth = INSPECTOR.def; this.applyInspector(); window.bridge.setPref('inspectorWidth', INSPECTOR.def); });
    hd.addEventListener('mousedown', (e) => {
      if (e.button !== 0 || e.detail > 1) return;
      e.preventDefault();
      const x0 = e.clientX, w0 = $('#inspector').offsetWidth;
      document.body.classList.add('resizing');
      const move = (ev) => { this.inspectorWidth = clamp(Math.round(w0 - (ev.clientX - x0)), INSPECTOR.min, INSPECTOR.max); this.applyInspector(); };
      const up = () => {
        window.removeEventListener('mousemove', move, true);
        window.removeEventListener('mouseup', up, true);
        document.body.classList.remove('resizing');
        window.bridge.setPref('inspectorWidth', this.inspectorWidth);
      };
      window.addEventListener('mousemove', move, true);
      window.addEventListener('mouseup', up, true);
    });
  }

  renderInspector() {
    const s = this.store;
    if (!s || !this.inspectorVisible) return;
    const link = s.selectedLinkID && s.dependency(s.selectedLinkID);
    const id = !link && s.selectedTaskID && s.task(s.selectedTaskID) ? s.selectedTaskID : null;
    let key;
    if (link) {
      key = JSON.stringify(['link', link, s.task(link.from)?.title, s.task(link.to)?.title, s.kind(link.from), s.kind(link.to), Theme.dark]);
    } else if (id) {
      const t = s.shown(id);
      const deps = [...s.predecessors(id), ...s.successors(id)].map((d) => [d, s.task(d.from)?.title, s.task(d.to)?.title]);
      key = JSON.stringify(['item', t, s.kind(id), s.isMark(id), s.hasSubtasks(id), s.displayDates(id), s.marks(id).map((m) => [m.id, m.title, m.start, m.startTime]),
        s.children(id).map((c) => [c.id, c.title, s.kind(c.id), s.displayDates(c.id)]), deps, s.categories, s.tags,
        t.parentID && s.task(t.parentID)?.title, s.viewZone, s.task(id).timeZone, s.today, s.titleFocusID === id, Theme.dark, this.inspectorError]);
    } else key = JSON.stringify(['none', Theme.dark]);
    if (!this.changed('inspector', key)) return;
    const head = `<div class="head"><span>Details</span><span class="grow"></span>
      <button class="iconbtn" data-act="hideInspector" title="Hide the details (Ctrl+I)" data-ctl="Hide Details">${Icons.xmark(10)}</button></div>`;
    let body;
    if (link) body = this.linkInspectorHTML(link);
    else if (id) body = this.itemInspectorHTML(id);
    else {
      body = `<div class="empty"><div class="t">Nothing selected</div>
        <div class="s">Double-click a group, task or milestone (or an arrow) to see and edit its details here.</div></div>`;
    }
    const insp = $('#inspector');
    const scroll = $('.scroll', insp)?.scrollTop || 0;
    const sameItem = this.inspectorShowing === (link ? link.id : id);
    insp.innerHTML = `${head}<div class="scroll">${body}</div>`;
    this.inspectorShowing = link ? link.id : id;
    if (sameItem) $('.scroll', insp).scrollTop = scroll;
    if (id) this.mountItemInspector(id);
    if (link) this.mountLinkInspector(link.id);
    if (id && s.titleFocusID === id) {
      s.titleFocusID = null;
      requestAnimationFrame(() => { const t = $('[data-field="title"]', insp); t?.focus(); t?.select(); });
    }
  }

  itemInspectorHTML(id) {
    const s = this.store, t = s.shown(id), kind = s.kind(id), mark = s.isMark(id), stored = s.task(id);
    const zone = s.viewZone;
    const color = s.colorHex(t);
    const cap = (text) => `<div class="caption">${esc(text)}</div>`;
    const out = [];
    out.push(`<div class="kind">${kindIcon(kind, color, 11)}<span>${mark ? 'Milestone of a task' : KINDS[kind]}</span></div>`);
    out.push(`<input class="input title" data-field="title" data-ctl="Title" value="${esc(t.title)}" placeholder="Title">`);
    // A milestone on a task's bar stays on the bar (with a check) instead of moving to the Archive.
    const done = !!stored.completed;
    const tip = done ? (mark ? 'Click to mark it as not completed (Ctrl+Shift+C)' : 'Click to return it from the Archive (Ctrl+Shift+C)')
      : (mark ? 'Mark it as passed: its diamond gets a check (Ctrl+Shift+C)' : 'Mark it as finished, whenever it was done: it moves to the Archive (Ctrl+Shift+C)');
    out.push(`<div><button class="pill completed-btn ${done ? 'done' : ''}" data-act="toggleCompleted" data-ctl="${done ? 'Completed' : 'Mark as Completed'}" title="${tip}">
        <span class="mark">${done ? Icons.check(9) : ''}</span><span>${done ? (mark ? 'Completed' : 'Completed · in the Archive') : 'Mark as Completed'}</span></button>
      ${done && !mark ? cap('Click it again to return it from the Archive to its place in the list.') : ''}</div>`);
    out.push(`<div><div class="field-label">Type</div><div class="seg">${Object.entries(KINDS).map(([k, label]) =>
      `<button class="pill ${kind === k ? 'selected' : ''}" data-kind="${k}" data-ctl="Type ${label}" ${s.hasSubtasks(id) && k !== 'group' ? 'disabled' : ''}>${label}</button>`).join('')}</div>
      ${s.hasSubtasks(id) ? cap("It has subtasks, so it's a group. Its dates come from what's inside it.") : ''}</div>`);
    // Dates
    const zoneCaption = () => {
      if (!stored.startTime && !stored.endTime) return cap('No time set: the same dates in every time zone.');
      let c = cap(`Times in ${Zones.label(zone)}.`);
      if (stored.timeZone && stored.timeZone !== zone) {
        const when = storedKind(stored) === 'milestone'
          ? `${Fmt.medium(stored.start)} ${stored.startTime || ''}`
          : `${Fmt.short(stored.start)} ${stored.startTime || TimeOfDay.defaultStart} – ${Fmt.short(stored.end)} ${stored.endTime || TimeOfDay.defaultEnd}`;
        c += cap(`Entered in ${Zones.label(stored.timeZone)}: ${when}.`);
      }
      return c;
    };
    if (kind === 'group') {
      const d = s.displayDates(id);
      out.push(`<div><div class="field-label">Dates</div>${d
        ? `<div>${Fmt.range(d.start, d.end, Day.year(s.today))} · ${Fmt.dayCount(d.end - d.start + 1)}</div>${cap("From the first to the last item inside it. Drag the group's bar to move everything in it.")}`
        : `<div class="muted" style="color:var(--secondary-text)">Empty group</div>${cap('Add subtasks or milestones; the group then spans them.')}`}</div>`);
    } else if (kind === 'milestone') {
      out.push(`<div><div class="field-label">Date</div><div class="row" style="gap:6px">${this.dayButton(t.start, 'Milestone date')}
        <input class="input time" data-field="startTime" data-ctl="Milestone time" placeholder="Time" value="${esc(t.startTime || '')}"
          title="A time of day, e.g. 9:30, 14:00 or 5pm. Leave it empty for the whole day."></div>${zoneCaption()}</div>`);
    } else {
      out.push(`<div><div class="field-label">Starts</div><div class="row" style="gap:6px">${this.dayButton(t.start, 'Start date')}
        <input class="input time" data-field="startTime" data-ctl="Start time" placeholder="${TimeOfDay.defaultStart}" value="${esc(t.startTime || '')}"></div></div>
        <div class="row"><div><div class="field-label">Ends</div><div class="row" style="gap:6px">${this.dayButton(t.end, 'End date')}
        <input class="input time" data-field="endTime" data-ctl="End time" placeholder="${TimeOfDay.defaultEnd}" value="${esc(t.endTime || '')}"></div></div>
        <div><div class="field-label">Duration</div><div style="height:28px;display:flex;align-items:center;color:var(--secondary-text)">${Fmt.dayCount(t.end - t.start + 1)}</div></div></div>
        ${zoneCaption()}`);
    }
    // Inside
    const p = t.parentID && s.task(t.parentID);
    out.push(`<div><div class="field-label">${mark ? 'Task' : 'Inside'}</div><button class="pill" data-act="parent" data-ctl="Inside" style="max-width:100%">${p
      ? `${kindIcon(s.kind(p.id), s.colorHex(p), 9)}<b style="overflow:hidden;text-overflow:ellipsis">${esc(p.title)}</b>`
      : '<span class="muted">None (top level)</span>'}<span class="muted">${Icons.chevronDown(10)}</span></button></div>`);
    // Category
    out.push(`<div><div class="field-label">Category</div><div class="chips">${s.categories.map((c) => {
      const sel = c.id === t.categoryID;
      return `<span class="cat-chip ${sel ? 'selected' : ''}" data-cid="${c.id}" data-ctl="Category chip ${esc(c.name)}"
        style="${sel ? `border-color:${c.colorHex};background:${c.colorHex}22` : ''}"><span class="dot" style="background:${c.colorHex}"></span>${esc(c.name)}</span>`;
    }).join('')}</div></div>`);
    // Color
    const catHex = s.category(t.categoryID)?.colorHex || '#8B8D98';
    out.push(`<div><div class="field-label">Color</div><div style="display:flex;align-items:center;gap:8px;flex-wrap:wrap">
      <span class="cat-chip ${t.colorHex ? '' : 'selected'}" data-act="categoryColor" data-ctl="Use category color" style="${t.colorHex ? '' : `border-color:${catHex};background:${catHex}22`}"><span class="dot" style="background:${catHex}"></span>Category</span>
      <span class="muted" style="font-size:12px;color:var(--secondary-text)">or</span><span data-slot="hex"></span></div></div>`);
    // Location
    out.push(`<div><div class="field-label">Location</div><input class="input" data-field="location" data-ctl="Location" placeholder="Optional, e.g. Room 204" value="${esc(t.location || '')}"></div>`);
    // Tags
    const sugg = s.tags.filter((x) => !t.tags.some((y) => y.toLowerCase() === x.toLowerCase()));
    out.push(`<div><div class="field-label">Tags</div><div class="tagbox">${t.tags.map((x) =>
      `<span class="chip removable">#${esc(x)}<span class="x" data-untag="${esc(x)}" title="Remove">${Icons.xmark(8)}</span></span>`).join('')}
      <input data-field="tag" data-ctl="Tag input" spellcheck="false" placeholder="${t.tags.length ? 'Add tag' : 'Add tags'}" style="width:120px"></div>
      ${sugg.length ? `<div class="suggestions">${sugg.map((x) => `<button class="pill plain small" data-addtag="${esc(x)}">#${esc(x)}</button>`).join('')}</div>` : ''}</div>`);
    // Milestones / contents
    if (kind === 'task') {
      const marks = s.marks(id);
      out.push(`<div><div class="field-label">Milestones</div>${marks.length ? '' : cap("Key moments of this task, such as a mid-term review or the deadline. They're drawn as diamonds on its bar.")}
        <div class="list">${marks.map((m) => this.itemRowHTML(m, 'milestone')).join('')}</div>
        <button class="add" data-act="addMilestone" data-ctl="Add Milestone">${Icons.plus(11)}Add Milestone</button></div>`);
    }
    if (kind === 'group') {
      out.push(`<div><div class="field-label">Inside this group</div><div class="list">${s.children(id).map((c) =>
        this.itemRowHTML(s.shown(c.id), s.kind(c.id))).join('')}</div>
        <button class="add" data-act="addSubtask" data-ctl="Add Subtask">${Icons.plus(11)}Add Subtask</button>
        <button class="add" data-act="addMilestone" data-ctl="Add Milestone">${Icons.plus(11)}Add Milestone</button></div>`);
    }
    // Arrows
    const before = s.predecessors(id), after = s.successors(id);
    out.push(`<div><div class="field-label">Arrows</div>${before.length || after.length ? ''
      : cap('None yet. On the timeline, point at this item, then drag one of the small round handles on its four sides onto another item.')}
      <div style="display:flex;flex-direction:column;gap:6px">${[...before.map((d) => this.depRowHTML(d, d.from, true)), ...after.map((d) => this.depRowHTML(d, d.to, false))].join('')}</div>
      <button class="add" data-act="addArrow" data-ctl="Add Arrow">${Icons.plus(11)}Add Arrow</button></div>`);
    out.push(`<div><div class="field-label">Notes</div><textarea class="input" data-field="notes" data-ctl="Notes" placeholder="Optional: details, links, people…">${esc(t.notes || '')}</textarea></div>`);
    if (this.inspectorError) out.push(`<div class="error" data-ctl="Details error">${esc(this.inspectorError)}</div>`);
    out.push(`<div><button class="pill destructive" data-act="delete" data-ctl="Delete item">Delete ${KINDS[kind]}…</button></div>`);
    return out.join('');
  }

  itemRowHTML(t, kind) {
    const s = this.store;
    let d;
    if (kind === 'milestone') d = Fmt.short(t.start) + (t.startTime ? ` ${t.startTime}` : '');
    else if (kind === 'group') { const x = s.displayDates(t.id); d = x ? Fmt.range(x.start, x.end, Day.year(s.today)) : 'Empty'; }
    else d = Fmt.range(t.start, t.end, Day.year(s.today));
    return `<div class="it" data-open="${t.id}" title="Show “${esc(t.title)}”" data-ctl="Row ${esc(t.title)}">${kindIcon(kind, s.colorHex(t), 9)}
      <span class="t">${esc(t.title)}</span><span class="d">${esc(d)}</span></div>`;
  }

  depRowHTML(d, otherID, incoming) {
    const s = this.store, other = s.task(otherID);
    const w = d.width ?? LINK_DEFAULT_WIDTH;
    const widthText = (x) => `${+x.toFixed(2)} pt`;
    return `<div class="dep ${s.selectedLinkID === d.id ? 'selected' : ''}" data-dep="${d.id}">
      <div class="top"><span title="${incoming ? 'Comes after this item' : 'This item comes after it'}">${incoming ? Icons.arrowIn(11) : Icons.arrowOut(11)}</span>
        <span>${incoming ? 'After' : 'Before'}</span>
        <span class="other" data-open="${otherID}" title="Show this item">${other ? kindIcon(s.kind(otherID), s.colorHex(other), 8) : ''} ${esc(other?.title || '?')}</span>
        <span class="grow"></span>
        <button class="iconbtn" data-act="openLink" title="Arrow settings">${Icons.sliders(11)}</button>
        <button class="iconbtn" data-act="deleteLink" title="Delete this arrow" data-ctl="Delete arrow">${Icons.xmark(9)}</button></div>
      <div class="controls">
        <select data-dfield="type" title="Which ends the arrow joins" data-ctl="Arrow type">${Object.entries(LINK_TYPES).map(([k, t]) =>
          `<option value="${k}" ${d.type === k ? 'selected' : ''}>${t.title}</option>`).join('')}</select>
        <select data-dfield="width" title="Line thickness" data-ctl="Arrow thickness">${[...new Set([...LINK_WIDTHS, w])].sort((a, b) => a - b).map((x) =>
          `<option value="${x}" ${x === w ? 'selected' : ''}>${widthText(x)}${x === LINK_DEFAULT_WIDTH ? ' (default)' : ''}</option>`).join('')}</select>
        <input type="color" data-dfield="color" title="Line color" value="${(d.colorHex || '#6E6E78').toLowerCase()}">
        ${d.colorHex ? '<button class="pill plain small" data-act="defaultColor">Default</button>' : ''}
      </div></div>`;
  }

  /** Wires the details pane's fields to the store (once per render). */
  mountItemInspector(id) {
    const s = this.store, insp = $('#inspector');
    const t = s.shown(id);
    const catHex = s.category(t.categoryID)?.colorHex || '#8B8D98';
    const hex = this.hexField({ value: t.colorHex || '', placeholder: catHex, allowEmpty: true, ctl: 'Item hex',
      onChange: () => { if (!hex.invalid && hex.value && hex.normalized !== s.task(id)?.colorHex) s.setColor(id, hex.normalized); } });
    $('[data-slot="hex"]', insp)?.appendChild(hex.el);
  }

  linkInspectorHTML(link) {
    const s = this.store;
    const endpoint = (id) => {
      const t = s.task(id);
      return `<button class="pill endpoint" data-open="${id}" data-ctl="Endpoint ${esc(t?.title || '')}">${t ? kindIcon(s.kind(id), s.colorHex(t), 9) : ''}
        <span class="t">${esc(t?.title || '?')}</span><span style="flex:1"></span><span class="muted">${Icons.chevronRight(10)}</span></button>`;
    };
    const a = s.task(link.from)?.title || 'the first item', b = s.task(link.to)?.title || 'the second item';
    const explain = { FS: `“${b}” starts after “${a}” finishes.`, SS: `“${b}” starts when “${a}” starts.`,
      FF: `“${b}” finishes when “${a}” finishes.`, SF: `“${b}” finishes when “${a}” starts.` }[link.type];
    const w = link.width ?? LINK_DEFAULT_WIDTH;
    const colors = ['#6E6E78', ...PALETTE.map(([, x]) => x)];
    const cur = (link.colorHex || '#6E6E78').toUpperCase();
    return `<div class="kind">${Icons.link(12)}<span>Arrow</span></div>
      <div><div class="field-label">From</div>${endpoint(link.from)}</div>
      <div><div class="field-label">To</div>${endpoint(link.to)}</div>
      <div><div class="field-label">Connects</div><div class="typelist">${Object.entries(LINK_TYPES).map(([k, t]) =>
        `<div class="it" data-type="${k}" data-ctl="Connect ${k}">${t.title}${link.type === k ? `<span class="ck">${Icons.check(11)}</span>` : ''}</div>`).join('')}</div>
        <div class="caption">${esc(explain)}</div></div>
      <div><div class="field-label">Sides</div>${[true, false].map((exit) => {
        const cur = exit ? exitSide(link) : entrySide(link), name = exit ? a : b;
        return `<div class="sides-label">${exit ? `Leaves “${esc(name)}” from its` : `Arrives at “${esc(name)}” on its`}</div>
          <div class="sides">${Object.entries(LINK_SIDES).map(([k, t]) =>
            `<button class="pill small ${cur === k ? 'prominent' : ''}" data-side="${exit ? 'exit' : 'entry'}:${k}" data-ctl="${exit ? 'Exit' : 'Entry'} side ${k}"
              title="${k === 'top' || k === 'bottom' ? `The middle of its ${t.word} edge` : `Its ${t.word} (${k} side)`}">${t.arrow} ${t.title}</button>`).join('')}</div>`;
      }).join('')}
        <div class="caption">Left is an item’s start and right its end. Top and bottom join the middle of its upper or lower edge.</div></div>
      <div><div class="field-label">Thickness</div><div class="row" style="align-items:center;gap:10px">
        <input type="range" min="0.25" max="6" step="0.25" value="${w}" data-lfield="width" data-ctl="Thickness slider">
        <span data-slot="w" style="width:52px;text-align:right">${+w.toFixed(2)} pt</span></div></div>
      <div><div class="field-label">Color</div><div class="swatches" style="grid-template-columns:repeat(7,30px)">${colors.map((x) =>
        `<span class="swatch-btn ${cur === x ? 'selected' : ''}" data-color="${x}" title="${x === '#6E6E78' ? 'Default gray' : x}" style="color:${x}"><span style="background:${x}"></span></span>`).join('')}</div>
        <div style="display:flex;align-items:center;gap:8px;margin-top:8px"><span style="font-size:12px;color:var(--secondary-text)">Hex</span><span data-slot="lhex"></span></div></div>
      <div class="row"><button class="pill" data-act="reverse" data-ctl="Reverse" title="Swap which item comes first">Reverse</button><span style="flex:1"></span>
        <button class="pill destructive" data-act="deleteLink" data-ctl="Delete Arrow">Delete Arrow</button></div>`;
  }

  mountLinkInspector(linkID) {
    const s = this.store, l = s.dependency(linkID);
    const hex = this.hexField({ value: l.colorHex || '', placeholder: '#6E6E78', allowEmpty: true, ctl: 'Arrow hex',
      onChange: () => { if (!hex.invalid && hex.value && hex.normalized !== s.dependency(linkID)?.colorHex) s.setDependencyColor(linkID, hex.normalized); } });
    $('[data-slot="lhex"]', $('#inspector'))?.appendChild(hex.el);
  }

  installInspector() {
    const insp = $('#inspector');
    const itemID = () => this.inspectorShowing && this.store?.task(this.inspectorShowing) ? this.inspectorShowing : null;
    const linkID = () => this.inspectorShowing && this.store?.dependency(this.inspectorShowing) ? this.inspectorShowing : null;
    const report = (err) => { if ((err || null) !== (this.inspectorError || null)) { this.inspectorError = err || null; this.keys.inspector = null; this.render(); } };
    insp.addEventListener('click', (e) => {
      const s = this.store;
      if (!s) return;
      const act = e.target.closest('[data-act]')?.dataset.act;
      if (act === 'hideInspector') { this.setInspectorVisible(false); return; }
      const open = e.target.closest('[data-open]');
      if (open && !e.target.closest('[data-act]')) { this.inspectorError = null; s.reveal(open.dataset.open); return; }
      const id = itemID(), lid = linkID();
      if (id) {
        const kindBtn = e.target.closest('[data-kind]');
        if (kindBtn && !kindBtn.disabled) { report(s.setKind(id, kindBtn.dataset.kind)); return; }
        const cat = e.target.closest('[data-cid]');
        if (cat) { s.setCategory(id, cat.dataset.cid); return; }
        const untag = e.target.closest('[data-untag]');
        if (untag) { s.setTags(id, s.task(id).tags.filter((x) => x !== untag.dataset.untag)); return; }
        const addtag = e.target.closest('[data-addtag]');
        if (addtag) { s.setTags(id, [...s.task(id).tags, addtag.dataset.addtag]); return; }
        const dayBtn = e.target.closest('button[data-ctl="Start date"], button[data-ctl="End date"], button[data-ctl="Milestone date"]');
        if (dayBtn) {
          const t = s.shown(id);
          if (dayBtn.dataset.ctl === 'Start date') this.openDayPicker(dayBtn, { day: t.start, onPick: (d) => report(s.setDates(id, d, Math.max(s.shown(id).end, d))) });
          else if (dayBtn.dataset.ctl === 'End date') this.openDayPicker(dayBtn, { day: t.end, minDay: t.start, onPick: (d) => report(s.setDates(id, s.shown(id).start, d)) });
          else this.openDayPicker(dayBtn, { day: t.start, onPick: (d) => report(s.setDates(id, d, d)) });
          return;
        }
        const dep = e.target.closest('[data-dep]');
        if (act === 'toggleCompleted') { s.toggleCompleted(id); return; }
        if (act === 'categoryColor') s.setColor(id, null);
        else if (act === 'parent') this.parentPicker(e.target.closest('button'), id);
        else if (act === 'addMilestone') this.newItem('milestone', id);
        else if (act === 'addSubtask') this.newItem('task', id);
        else if (act === 'addArrow') this.addArrowPicker(e.target.closest('button'), id);
        else if (act === 'delete') this.requestDeleteTask(id);
        else if (act === 'openLink' && dep) { s.selectLink(dep.dataset.dep); }
        else if (act === 'deleteLink' && dep) s.deleteDependency(dep.dataset.dep);
        else if (act === 'defaultColor' && dep) s.setDependencyColor(dep.dataset.dep, null);
      } else if (lid) {
        const type = e.target.closest('[data-type]');
        if (type) { s.setDependencyType(lid, type.dataset.type); return; }
        const side = e.target.closest('[data-side]');
        if (side) { const [end, k] = side.dataset.side.split(':'); s.setDependencySide(lid, end === 'exit', k); return; }
        const sw = e.target.closest('[data-color]');
        if (sw) { s.setDependencyColor(lid, sw.dataset.color === '#6E6E78' ? null : sw.dataset.color); return; }
        if (act === 'reverse') s.reverseDependency(lid);
        else if (act === 'deleteLink') s.deleteDependency(lid);
      }
    });
    // Text fields save when you press Enter or leave them ("change"), so each edit is one Undo step.
    insp.addEventListener('change', (e) => {
      const s = this.store;
      if (!s) return;
      const f = e.target.dataset.field, df = e.target.dataset.dfield, lf = e.target.dataset.lfield;
      const id = itemID(), lid = linkID();
      if (id && f) {
        const v = e.target.value;
        if (f === 'title') report(s.setTitle(id, v));
        else if (f === 'startTime') { const t = s.shown(id); report(s.setTimes(id, v, storedKind(t) === 'milestone' ? '' : (t.endTime || ''))); }
        else if (f === 'endTime') report(s.setTimes(id, s.shown(id).startTime || '', v));
        else if (f === 'location') s.setLocation(id, v);
        else if (f === 'notes') s.setNotes(id, v);
        else if (f === 'tag') { const add = Tags.parse(v); e.target.value = ''; if (add.length) s.setTags(id, [...s.task(id).tags, ...add]); }
      }
      const dep = e.target.closest('[data-dep]');
      if (dep && df) {
        if (df === 'type') s.setDependencyType(dep.dataset.dep, e.target.value);
        else if (df === 'width') s.setDependencyWidth(dep.dataset.dep, +e.target.value);
        else if (df === 'color') s.setDependencyColor(dep.dataset.dep, e.target.value);
      }
      if (lid && lf === 'width') s.setDependencyWidth(lid, +e.target.value);
    });
    insp.addEventListener('input', (e) => {
      const s = this.store, lid = linkID();
      if (lid && e.target.dataset.lfield === 'width') {
        const v = +e.target.value;
        const lbl = $('[data-slot="w"]', insp);
        if (lbl) lbl.textContent = `${+v.toFixed(2)} pt`;
        s.setDependencyWidth(lid, v);
      }
      if (e.target.dataset.field === 'tag' && /[,; ]/.test(e.target.value)) e.target.dispatchEvent(new Event('change', { bubbles: true }));
    });
    insp.addEventListener('keydown', (e) => {
      if (e.key === 'Enter' && e.target.dataset?.field === 'tag') { e.preventDefault(); e.target.dispatchEvent(new Event('change', { bubbles: true })); return; }
      // Enter saves a one-line field (leaving it fires "change").
      if (e.key === 'Enter' && e.target.tagName === 'INPUT' && e.target.type === 'text' && !e.isComposing) { e.preventDefault(); e.target.blur(); return; }
      if (e.key === 'Escape' && e.target.matches('input, textarea')) { e.target.blur(); this.chart.scroller.focus({ preventScroll: true }); }
    });
  }

  /** Chooses the group or task an item belongs under. */
  parentPicker(anchor, id) {
    if (this.popover?.anchor === anchor) { this.closePopover(); return; }
    const s = this.store, cur = s.task(id)?.parentID || null;
    const list = h('<div class="popover parent-list" data-ctl="Parent list"></div>');
    const items = [`<div class="item" data-pid=""><span class="muted">None (top level)</span><span class="grow"></span>${cur ? '' : `<span class="ck">${Icons.check(11)}</span>`}</div>`];
    for (const c of s.parentCandidates(id)) {
      const d = s.displayDates(c.task.id);
      items.push(`<div class="item" data-pid="${c.task.id}" data-ctl="Parent ${esc(c.task.title)}" style="padding-left:${8 + Math.min(c.depth, 8) * 14}px">
        ${kindIcon(s.kind(c.task.id), s.colorHex(c.task), 8)}<span class="t">${esc(c.task.title)}</span>
        <span class="d">${d ? Fmt.range(d.start, d.end, Day.year(s.today)) : ''}</span><span class="grow"></span>
        ${cur === c.task.id ? `<span class="ck">${Icons.check(11)}</span>` : ''}</div>`);
    }
    list.innerHTML = items.join('');
    list.addEventListener('click', (ev) => {
      const it = ev.target.closest('[data-pid]');
      if (!it) return;
      this.closePopover();
      const err = s.setParent(id, it.dataset.pid || null);
      if (err) { this.inspectorError = err; this.keys.inspector = null; this.render(); }
    });
    this.showPopover(list, anchor);
  }

  /** Adds an arrow from or to the item shown, chosen from a list. */
  addArrowPicker(anchor, id) {
    if (this.popover?.anchor === anchor) { this.closePopover(); return; }
    const s = this.store;
    const el = h(`<div class="popover linkpick" data-ctl="Add arrow list">
      <select data-ctl="Arrow direction"><option value="out">This → other</option><option value="in">Other → this</option></select>
      <select data-ctl="New arrow type">${Object.entries(LINK_TYPES).map(([k, t]) => `<option value="${k}">${t.title}</option>`).join('')}</select>
      <div class="rows"></div></div>`);
    const [dir, type] = $$('select', el), rows = $('.rows', el);
    const render = () => {
      const out = dir.value === 'out';
      const cands = Hierarchy.outline(s.content).filter((c) => !(out ? s.linkProblem(id, c.task.id) : s.linkProblem(c.task.id, id)));
      rows.innerHTML = cands.length ? cands.map((c) => `<div class="it" data-target="${c.task.id}" data-ctl="Link target ${esc(c.task.title)}" style="padding-left:${6 + Math.min(c.depth, 8) * 12}px">
        ${kindIcon(s.kind(c.task.id), s.colorHex(c.task), 8)}<span class="t">${esc(c.task.title)}</span></div>`).join('')
        : '<div style="color:var(--secondary-text);font-size:12px;padding:4px">No other items can be joined to this one.</div>';
    };
    dir.addEventListener('change', render);
    rows.addEventListener('click', (e) => {
      const it = e.target.closest('[data-target]');
      if (!it) return;
      this.closePopover();
      if (dir.value === 'out') s.addDependency(id, it.dataset.target, type.value, false);
      else s.addDependency(it.dataset.target, id, type.value, false);
    });
    render();
    this.showPopover(el, anchor);
  }

  // ---------------------------------------------------------------- Popovers
  closePopover() {
    if (!this.popover) return;
    this.popover.el.remove();
    window.removeEventListener('mousedown', this.popover.outside, true);
    this.popover = null;
  }

  showPopover(el, anchor) {
    this.closePopover();
    document.body.appendChild(el);
    const r = anchor.getBoundingClientRect(), pw = el.offsetWidth, ph = el.offsetHeight;
    const left = clamp(r.left + r.width / 2 - pw / 2, 8, window.innerWidth - pw - 8);
    let top = r.bottom + 6;
    if (top + ph > window.innerHeight - 8) top = Math.max(8, r.top - ph - 6);
    el.style.left = `${left}px`;
    el.style.top = `${top}px`;
    const outside = (e) => { if (!el.contains(e.target) && !anchor.contains(e.target)) this.closePopover(); };
    window.addEventListener('mousedown', outside, true);
    this.popover = { el, anchor, outside };
  }

  /** A month calendar under a date button. Days before `minDay` can't be picked. */
  openDayPicker(anchor, { day, minDay, onPick }) {
    if (this.popover?.anchor === anchor) { this.closePopover(); return; }
    const s = this.store;
    let month = Day.firstOfMonth(day);
    const el = h('<div class="popover calendar" data-ctl="Calendar"></div>');
    const render = () => {
      const fw = s.firstWeekday;
      const first = Weeks.start(month, fw);
      const dim = Day.daysInMonth(Day.year(month), Day.month(month));
      const rows = Math.ceil((month - first + dim) / 7);
      const cells = [];
      for (let k = 0; k < 7; k++) cells.push(`<div class="wd">${Fmt.weekdayLetter[(fw + k) % 7]}</div>`);
      for (let k = 0; k < rows * 7; k++) {
        const d = first + k;
        const cls = ['d', Day.month(d) !== Day.month(month) ? 'other' : '', d === s.today ? 'today' : '', d === day ? 'selected' : '',
          minDay != null && d < minDay ? 'disabled' : ''].join(' ');
        cells.push(`<div class="${cls}" data-day="${d}" data-iso="${Day.iso(d)}">${Day.dayOfMonth(d)}</div>`);
      }
      el.innerHTML = `<div class="head"><span class="title">${Fmt.monthYear(month)}</span>
        <button class="pill plain icon small" data-nav="-1" title="Previous month">${Icons.chevronLeft(11)}</button>
        <button class="pill plain small" data-nav="0">Today</button>
        <button class="pill plain icon small" data-nav="1" title="Next month">${Icons.chevronRight(11)}</button></div>
        <div class="grid">${cells.join('')}</div>`;
    };
    render();
    el.addEventListener('click', (e) => {
      const nav = e.target.closest('[data-nav]');
      if (nav) { month = +nav.dataset.nav === 0 ? Day.firstOfMonth(s.today) : Day.addMonths(month, +nav.dataset.nav); render(); return; }
      const c = e.target.closest('[data-day]');
      if (c && !c.classList.contains('disabled')) { this.closePopover(); onPick(+c.dataset.day); }
    });
    this.showPopover(el, anchor);
  }

  // ---------------------------------------------------------------- Sheets
  openSheet(el, { onCancel, onDefault } = {}) {
    this.closePopover();
    const ov = $('#overlay');
    ov.innerHTML = '';
    ov.appendChild(el);
    ov.classList.add('open');
    this.sheet = { el, onCancel: onCancel || (() => this.closeSheet()), onDefault };
    this.render();
    requestAnimationFrame(() => (el.querySelector('[autofocus]') || el.querySelector('input, textarea, button.prominent'))?.focus());
  }

  closeSheet() {
    this.closePopover();
    const ov = $('#overlay');
    ov.classList.remove('open');
    ov.innerHTML = '';
    this.sheet = null;
    this.render();
    this.chart.scroller.focus({ preventScroll: true });
  }

  sheetKey(e) {
    if (!this.sheet) return;
    if (e.key === 'Escape') {
      e.preventDefault();
      if (this.popover) this.closePopover(); else this.sheet.onCancel();
      return;
    }
    if (e.key !== 'Enter' || e.isComposing) return;
    const t = e.target;
    if (t.tagName === 'TEXTAREA' && !(e.ctrlKey || e.metaKey)) return;
    if (t.tagName === 'BUTTON' && !t.classList.contains('prominent')) return;
    e.preventDefault();
    this.sheet.onDefault?.();
  }

  /** A hex color field: swatch, text ("#2F6FEB", "2f6", …) and a color picker. */
  hexField({ value, placeholder, allowEmpty = false, ctl, onChange }) {
    const el = h(`<span class="hexfield"><span class="swatch"></span>
      <input type="text" spellcheck="false" maxlength="9" placeholder="${esc(placeholder || '#2F6FEB')}" data-ctl="${esc(ctl)}">
      <input type="color" title="Pick a color" tabindex="-1"></span>`);
    const text = el.querySelector('input[type=text]'), picker = el.querySelector('input[type=color]'), sw = el.querySelector('.swatch');
    const api = {
      el,
      get value() { return text.value.trim(); },
      get normalized() { return Color.normalizedHex(text.value); },
      get invalid() { return text.value.trim() ? !Color.normalizedHex(text.value) : !allowEmpty; },
      set placeholder(p) { placeholder = p; text.placeholder = p; update(); },
      set(v) { text.value = v || ''; update(); },
    };
    const update = () => {
      const shown = Color.normalizedHex(text.value) || placeholder || '#2F6FEB';
      sw.style.background = shown;
      picker.value = shown.toLowerCase();
      el.classList.toggle('bad', api.invalid && !!text.value.trim());
    };
    text.value = value || '';
    text.addEventListener('input', () => { update(); });
    text.addEventListener('change', () => { const n = Color.normalizedHex(text.value); if (n) text.value = n; update(); onChange?.(); });
    picker.addEventListener('input', () => { text.value = picker.value.toUpperCase(); update(); onChange?.(); });
    update();
    return api;
  }

  dayButton(day, ctl) {
    return `<button class="pill" data-ctl="${ctl}" title="${ctl}"><span class="muted">${Icons.calendar(13)}</span><span>${Fmt.medium(day)}</span></button>`;
  }

  // ---------------------------------------------------------------- Category editor & note
  openCategoryEditor(draft) {
    if (!draft) return;
    const s = this.store;
    const d = { ...draft };
    const isNew = !d.categoryID;
    const el = h(`<div class="sheet" style="width:420px" role="dialog" data-sheet="category">
      <h2>${isNew ? 'New Category' : 'Edit Category'}</h2>
      <div class="field"><div class="field-label">Name</div><input class="input" data-ctl="Category name" placeholder="e.g. Work" autofocus style="height:30px;font-size:14px"></div>
      <div class="field"><div class="field-label">Color</div><div class="swatches" data-slot="swatches"></div>
        <div style="display:flex;align-items:center;gap:8px;margin-top:10px"><span class="muted" style="font-size:12px;color:var(--secondary-text)">Hex</span><span data-slot="hex"></span></div>
        <div class="hint bad" data-slot="hexHint"></div></div>
      <div class="field"><div class="field-label">Note</div><textarea class="input" data-ctl="Category editor note" style="height:70px" placeholder="Optional: shown when you hover over the category"></textarea></div>
      <div class="error" data-slot="error"></div>
      <div class="buttons">${isNew ? '' : '<button class="pill destructive" data-act="delete">Delete Category…</button>'}
        <span class="grow"></span><button class="pill" data-act="cancel">Cancel</button>
        <button class="pill prominent" data-act="save" data-ctl="Save category">${isNew ? 'Add Category' : 'Save'}</button></div></div>`);
    const name = el.querySelector('[data-ctl="Category name"]');
    const note = el.querySelector('textarea');
    name.value = d.name;
    note.value = d.notes || '';
    const hex = this.hexField({ value: d.colorHex, ctl: 'Category hex', onChange: () => { renderSwatches(); validate(); } });
    el.querySelector('[data-slot="hex"]').appendChild(hex.el);
    const renderSwatches = () => {
      const cur = hex.normalized;
      el.querySelector('[data-slot="swatches"]').innerHTML = PALETTE.map(([n, x]) =>
        `<span class="swatch-btn ${cur === x ? 'selected' : ''}" data-hex="${x}" title="${n}" style="color:${x}"><span style="background:${x}"></span></span>`).join('');
    };
    el.querySelector('[data-slot="swatches"]').addEventListener('click', (e) => {
      const b = e.target.closest('[data-hex]');
      if (b) { hex.set(b.dataset.hex); renderSwatches(); validate(); }
    });
    const saveBtn = el.querySelector('[data-act="save"]');
    const validate = () => {
      el.querySelector('[data-slot="hexHint"]').textContent = hex.invalid ? 'Type a hex color such as #2F6FEB.' : '';
      saveBtn.disabled = !name.value.trim() || hex.invalid;
    };
    name.addEventListener('input', validate);
    el.querySelector('input[type=text][data-ctl="Category hex"]').addEventListener('input', validate);
    const save = () => {
      if (saveBtn.disabled) return;
      const err = s.saveCategoryDraft({ ...d, name: name.value, colorHex: hex.value, notes: note.value });
      if (err) { el.querySelector('[data-slot="error"]').textContent = err; return; }
      this.closeSheet();
    };
    saveBtn.addEventListener('click', save);
    el.querySelector('[data-act="cancel"]').addEventListener('click', () => this.closeSheet());
    el.querySelector('[data-act="delete"]')?.addEventListener('click', () => this.requestDeleteCategory(d.categoryID));
    renderSwatches();
    validate();
    this.openSheet(el, { onDefault: save });
  }

  openCategoryNote(id) {
    const s = this.store, c = s.category(id);
    if (!c) return;
    const had = !!c.notes;
    const el = h(`<div class="sheet" style="width:440px" role="dialog" data-sheet="categoryNote">
      <h2><span class="dot" style="width:10px;height:10px;background:${c.colorHex}"></span>Note for “${esc(c.name)}”</h2>
      <textarea class="input" data-ctl="Category note" style="height:130px" placeholder="Write a note about this category" autofocus></textarea>
      <div class="hint" style="margin-top:-6px">Shown when you hover over the category in the sidebar. Enter starts a new line; Ctrl+Enter saves.</div>
      <div class="buttons">${had ? '<button class="pill destructive" data-act="remove">Remove Note</button>' : ''}<span class="grow"></span>
        <button class="pill" data-act="cancel">Cancel</button><button class="pill prominent" data-act="save" data-ctl="Save note">Save</button></div></div>`);
    const ta = el.querySelector('textarea');
    ta.value = c.notes || '';
    const save = () => { s.saveCategoryNote(id, ta.value); this.closeSheet(); };
    el.querySelector('[data-act="save"]').addEventListener('click', save);
    el.querySelector('[data-act="cancel"]').addEventListener('click', () => this.closeSheet());
    el.querySelector('[data-act="remove"]')?.addEventListener('click', () => { s.saveCategoryNote(id, ''); this.closeSheet(); });
    this.openSheet(el, { onDefault: save });
  }

  openTagEditor(tag) {
    const s = this.store;
    const el = h(`<div class="sheet" style="width:380px" role="dialog" data-sheet="tag">
      <h2>Edit Tag</h2>
      <div style="display:flex;align-items:center;gap:6px"><span style="font-size:14px;color:var(--secondary-text)">#</span>
        <input class="input" data-ctl="Tag name" autofocus></div>
      <div class="message-text" style="font-size:12px">Used by ${Fmt.itemCount(s.taskCountForTag(tag))}. Renaming to an existing tag merges them.</div>
      <div class="error" data-slot="error"></div>
      <div class="buttons"><button class="pill destructive" data-act="delete">Delete Tag…</button><span class="grow"></span>
        <button class="pill" data-act="cancel">Cancel</button><button class="pill prominent" data-act="save">Save</button></div></div>`);
    const input = el.querySelector('input');
    input.value = tag;
    const save = () => {
      const err = s.renameTag(tag, input.value);
      if (err) { el.querySelector('[data-slot="error"]').textContent = err; return; }
      this.closeSheet();
    };
    el.querySelector('[data-act="save"]').addEventListener('click', save);
    el.querySelector('[data-act="cancel"]').addEventListener('click', () => this.closeSheet());
    el.querySelector('[data-act="delete"]').addEventListener('click', () => this.requestDeleteTag(tag));
    this.openSheet(el, { onDefault: save });
  }

  // ---------------------------------------------------------------- Confirmations
  confirm({ title, emphasis, message, confirmTitle, onConfirm, destructive = true }) {
    let titleHTML = esc(title);
    if (emphasis && title.includes(emphasis)) {
      const i = title.indexOf(emphasis);
      titleHTML = `${esc(title.slice(0, i))}<b>${esc(emphasis)}</b>${esc(title.slice(i + emphasis.length))}`;
    }
    const el = h(`<div class="sheet" style="width:380px" role="alertdialog" data-sheet="confirm">
      <div style="font-size:15px;line-height:1.35" data-ctl="Confirm title">${titleHTML}</div>
      <div class="message-text">${esc(message)}</div>
      <div class="buttons"><span class="grow"></span>${confirmTitle
        ? `<button class="pill" data-act="cancel">Cancel</button><button class="pill prominent" data-act="ok" data-ctl="Confirm" ${destructive ? 'style="background:var(--destructive);border-color:var(--destructive)"' : ''}>${esc(confirmTitle)}</button>`
        : '<button class="pill prominent" data-act="cancel" data-ctl="OK">OK</button>'}</div></div>`);
    const ok = () => { this.closeSheet(); onConfirm?.(); };
    el.querySelector('[data-act="ok"]')?.addEventListener('click', ok);
    el.querySelector('[data-act="cancel"]').addEventListener('click', () => this.closeSheet());
    this.openSheet(el, { onDefault: confirmTitle ? ok : () => this.closeSheet() });
  }

  requestDeleteTask(id) {
    const s = this.store, t = s?.task(id);
    if (!t) return;
    this.confirm({ title: `Delete “${t.title}”?`, emphasis: t.title, message: s.deleteMessage(id), confirmTitle: `Delete ${KINDS[s.kind(id)]}`,
      onConfirm: () => s.deleteTask(id) });
  }

  requestDeleteCategory(id) {
    const s = this.store, c = s.category(id);
    if (!c) return;
    const fb = s.categoryFallback(id);
    if (!fb) {
      this.confirm({ title: `Can't delete “${c.name}”`, message: 'Every item needs a category, so at least one category must remain.', confirmTitle: '' });
      return;
    }
    const n = s.taskCountForCategory(id);
    this.confirm({ title: `Delete the category “${c.name}”?`, confirmTitle: 'Delete Category',
      message: n === 0 ? 'No items use this category.' : `${n === 1 ? 'Its 1 item' : `Its ${n} items`} will move to “${fb.name}”.`,
      onConfirm: () => s.deleteCategory(id) });
  }

  requestDeleteTag(tag) {
    const n = this.store.taskCountForTag(tag);
    this.confirm({ title: `Delete the tag #${tag}?`, confirmTitle: 'Delete Tag',
      message: n === 0 ? 'No items use this tag.' : `The tag will be removed from ${Fmt.itemCount(n)}. The items themselves are kept.`,
      onConfirm: () => this.store.deleteTag(tag) });
  }

  // ---------------------------------------------------------------- Today color & settings
  openTodayColor() {
    const s = this.store;
    if (!s) return;
    const el = h(`<div class="sheet" style="width:400px" role="dialog" data-sheet="todayColor">
      <h2>Today Color</h2>
      <div style="display:flex;gap:16px;align-items:flex-start">
        <div style="flex:1;display:flex;flex-direction:column;gap:12px">
          <div class="swatches" style="grid-template-columns:repeat(5,30px)" data-slot="swatches"></div>
          <div style="display:flex;align-items:center;gap:8px"><span style="font-size:12px;color:var(--secondary-text)">Hex</span><span data-slot="hex"></span></div>
          <div class="hint bad" data-slot="hint" style="margin:0"></div>
        </div>
        <div class="today-preview" data-slot="preview"><span data-slot="wd" style="font-size:10px"></span><span class="circle" data-slot="circle"></span></div>
      </div>
      <div class="buttons"><button class="pill" data-act="red">Use Red</button><span class="grow"></span>
        <button class="pill" data-act="cancel">Cancel</button><button class="pill prominent" data-act="save" data-ctl="Save today color">Save</button></div></div>`);
    const hex = this.hexField({ value: s.todayColorHex, placeholder: TodayStyle.defaultHex, ctl: 'Today hex', onChange: () => update() });
    el.querySelector('[data-slot="hex"]').appendChild(hex.el);
    el.querySelector('input[type=text][data-ctl="Today hex"]').addEventListener('input', () => update());
    const saveBtn = el.querySelector('[data-act="save"]');
    const update = () => {
      const cur = hex.normalized;
      el.querySelector('[data-slot="swatches"]').innerHTML = TodayStyle.choices.map(([n, x]) =>
        `<span class="swatch-btn ${cur === x ? 'selected' : ''}" data-hex="${x}" title="${n}" style="color:${x}"><span style="background:${x}"></span></span>`).join('');
      const dark = window.matchMedia('(prefers-color-scheme: dark)').matches;
      const c = cur || TodayStyle.defaultHex;
      el.querySelector('[data-slot="preview"]').style.background = TodayStyle.fill(c, dark);
      const wd = el.querySelector('[data-slot="wd"]');
      wd.textContent = Fmt.weekdayShort[Day.weekday(s.today)];
      wd.style.color = TodayStyle.accent(c, dark);
      const circle = el.querySelector('[data-slot="circle"]');
      circle.textContent = String(Day.dayOfMonth(s.today));
      circle.style.background = TodayStyle.accent(c, dark);
      circle.style.color = Color.prefersLightText(c) ? '#FFFFFF' : '#1D1D1F';
      el.querySelector('[data-slot="hint"]').textContent = hex.invalid ? 'Type a hex color such as #E5484D.' : '';
      saveBtn.disabled = hex.invalid;
    };
    el.querySelector('[data-slot="swatches"]').addEventListener('click', (e) => {
      const b = e.target.closest('[data-hex]');
      if (b) { hex.set(b.dataset.hex); update(); }
    });
    const save = () => { if (saveBtn.disabled) return; s.setTodayColor(hex.normalized); this.closeSheet(); };
    saveBtn.addEventListener('click', save);
    el.querySelector('[data-act="red"]').addEventListener('click', () => { hex.set(TodayStyle.defaultHex); update(); });
    el.querySelector('[data-act="cancel"]').addEventListener('click', () => this.closeSheet());
    update();
    this.openSheet(el, { onDefault: save });
  }

  openSettings() {
    const el = h(`<div class="sheet" style="width:440px" role="dialog" data-sheet="settings">
      <h2>Settings</h2>
      <div class="settings-section"><div>Appearance</div><div class="segmented" data-slot="appearance"></div><div class="caption" data-slot="caption"></div></div>
      <div class="settings-section"><div>First Day of Week</div><div class="segmented" data-slot="week"></div></div>
      <div class="settings-section"><div>Today Color</div><div><button class="pill" data-act="today"><span class="dot" data-slot="todayDot"></span>Choose…</button></div></div>
      <div class="settings-section"><div>Time Zone</div><div><button class="pill" data-act="tz" data-ctl="Settings time zone">${Icons.globe(13)}<span data-slot="tz"></span></button></div>
        <div class="caption">Times are shown in this time zone, as in Apple Calendar: a task at 10:00 in Tokyo shows at 02:00 in Berlin. Items without a time keep their dates everywhere. Unless you choose one, it's this computer's time zone and follows you when you travel.</div></div>
      <div class="settings-section"><div>Workspace</div><div class="path" data-slot="ws"></div>
        <div><button class="pill" data-act="show">${this.isMac ? 'Show in Finder' : 'Show in File Explorer'}</button></div></div>
      <div class="buttons"><span class="grow"></span><button class="pill prominent" data-act="done">Done</button></div></div>`);
    const captions = { system: 'DaySpindle follows Windows (Settings › Personalization › Colors) and switches when it does.',
      light: 'DaySpindle always uses its light look.', dark: 'DaySpindle always uses its dark look.' };
    const render = () => {
      const s = this.store;
      el.querySelector('[data-slot="appearance"]').innerHTML = Object.entries(APPEARANCES).map(([m, [t]]) =>
        `<button class="pill ${this.appearance === m ? 'selected' : ''}" style="min-width:110px" data-mode="${m}">${t}</button>`).join('');
      el.querySelector('[data-slot="caption"]').textContent = captions[this.appearance];
      const fw = s ? s.firstWeekday : this.prefs.firstWeekday;
      el.querySelector('[data-slot="week"]').innerHTML = [0, 1, 6].map((d) =>
        `<button class="pill ${fw === d ? 'selected' : ''}" style="min-width:110px" data-week="${d}">${Fmt.weekdayLong[d]}</button>`).join('');
      el.querySelector('[data-slot="todayDot"]').style.background = s ? s.todayColorHex : this.prefs.todayColor;
      const z = this.zones.current();
      el.querySelector('[data-slot="tz"]').textContent = `${Zones.label(z)}${this.timeZone ? '' : " · this computer's"}`;
      el.querySelector('[data-slot="ws"]').textContent = s ? s.dataPath : 'No workspace open';
    };
    el.addEventListener('click', (e) => {
      const s = this.store;
      const m = e.target.closest('[data-mode]'), w = e.target.closest('[data-week]'), a = e.target.closest('[data-act]')?.dataset.act;
      if (m) this.setAppearance(m.dataset.mode);
      else if (w) { for (const st of this.stores.values()) st.setFirstWeekday(+w.dataset.week); }
      else if (a === 'today') { if (s) this.openTodayColor(); return; }
      else if (a === 'tz') { this.openTimeZonePicker(e.target.closest('button')); return; }
      else if (a === 'show') { if (this.tabs.active) window.bridge.revealTab(this.tabs.active); }
      else if (a === 'done') { this.closeSheet(); return; }
      render();
    });
    this.settingsRender = render;
    render();
    this.openSheet(el, { onDefault: () => this.closeSheet() });
  }

  // ---------------------------------------------------------------- Import & export
  async importData() {
    const r = await window.bridge.chooseImport();
    if (!r) return;
    const name = r.path.split(/[\\/]/).pop();
    if (r.error) { this.confirm({ title: `Can't open “${name}”`, message: r.error, confirmTitle: '' }); return; }
    let decoded;
    try { decoded = DataFile.decode(r.text); }
    catch (e) { this.confirm({ title: `Can't import “${name}”`, message: e.message, confirmTitle: '' }); return; }
    const s = this.store;
    this.confirm({
      title: `Replace this workspace with “${name}”?`, emphasis: name, confirmTitle: 'Replace',
      message: `The ${Fmt.itemCount(s.tasks.length)} in “${s.workspaceName}” will be replaced by the ${Fmt.itemCount(decoded.content.tasks.length)} in this file. A copy of the current data is kept in the workspace folder.`,
      onConfirm: async () => {
        const err = await window.bridge.backupBeforeImport(s.workspacePath);
        if (err) { this.confirm({ title: 'Import stopped', message: `The current data could not be backed up: ${err}`, confirmTitle: '' }); return; }
        s.replaceAll(decoded, name);
      },
    });
  }

  async exportData() {
    const r = await window.bridge.exportData(this.store.fileText());
    if (r.canceled) return;
    if (r.error) { this.confirm({ title: 'Export failed', message: r.error, confirmTitle: '' }); return; }
    this.store.notice = `Exported to ${r.path}. To move a whole workspace instead, copy its folder.`;
    this.store.emit();
  }

  // ---------------------------------------------------------------- Commands & keyboard
  command(name, value) {
    const s = this.store, sel = s?.selectedTaskID;
    if (this.sheet) {
      if (name === 'undo' || name === 'redo') document.execCommand(name);
      return;
    }
    const typing = document.activeElement?.matches?.('input, textarea');
    if ((name === 'undo' || name === 'redo') && typing) { document.execCommand(name); return; }
    switch (name) {
      case 'settings': this.openSettings(); return;
      case 'nextTab': this.stepTab(1); return;
      case 'previousTab': this.stepTab(-1); return;
      case 'newWorkspace': window.bridge.newWorkspace(); return;
      case 'openWorkspace': window.bridge.openWorkspace(); return;
      case 'closeTab': if (this.tabs.active) window.bridge.closeTab(this.tabs.active); return;
      default:
    }
    if (!s) return;
    switch (name) {
      case 'newTask': this.newItem('task'); break;
      case 'newSubtask': if (sel && s.kind(sel) !== 'milestone') this.newItem('task', sel); break;
      case 'newMilestone': this.newItem('milestone', sel && s.kind(sel) !== 'milestone' ? sel : null); break;
      case 'newGroup': this.newItem('group'); break;
      case 'newCategory': this.openCategoryEditor(s.newCategoryDraft()); break;
      case 'editTask': if (sel) this.openInspector(sel); break;
      case 'toggleInspector': this.setInspectorVisible(!this.inspectorVisible); break;
      case 'deleteTask': if (sel) this.requestDeleteTask(sel); break;
      case 'toggleCompleted': if (sel) s.toggleCompleted(sel); break;
      case 'moveUp': if (sel) s.moveTaskBy(sel, -1); break;
      case 'moveDown': if (sel) s.moveTaskBy(sel, 1); break;
      case 'importData': this.importData(); break;
      case 'exportData': this.exportData(); break;
      case 'undo': s.undo(); break;
      case 'redo': s.redo(); break;
      case 'allTasks': case 'clearFilters': s.clearFilters(); break;
      case 'expandAll': s.expandAll(); break;
      case 'collapseAll': s.collapseAll(); break;
      case 'today': s.goToToday(); break;
      case 'previous': s.shiftWindow(-1); break;
      case 'next': s.shiftWindow(1); break;
      case 'preset': if (PRESETS[value]) s.applyPreset(PRESETS[value]); break;
      case 'firstWeekday': for (const st of this.stores.values()) st.setFirstWeekday(value); break;
      case 'todayColor': this.openTodayColor(); break;
      case 'addExamples': s.addExampleTasks(); break;
      default:
    }
  }

  installKeyboard() {
    window.addEventListener('keydown', (e) => {
      if (this.sheet) { this.sheetKey(e); return; }
      if (this.popover && e.key === 'Escape') { e.preventDefault(); this.closePopover(); return; }
      const ctrl = e.ctrlKey || (this.isMac && e.metaKey);
      const is = (ch) => e.code === `Key${ch}` || (!e.code && (e.key || '').toUpperCase() === ch);
      // While typing in a field, editing keys belong to the field.
      const typing = e.target.closest?.('input, textarea, select');
      if (typing && (!ctrl || ['Z', 'Y', 'A', 'C', 'V', 'X'].some(is))) return;
      let cmd = null;
      if (ctrl && e.key === 'Tab') cmd = e.shiftKey ? 'previousTab' : 'nextTab';
      else if (ctrl && e.altKey && e.shiftKey && is('N')) cmd = 'newWorkspace';
      else if (ctrl && !e.altKey && !e.shiftKey && is('N')) cmd = 'newTask';
      else if (ctrl && e.altKey && is('N')) cmd = 'newSubtask';
      else if (ctrl && e.shiftKey && is('N')) cmd = 'newCategory';
      else if (ctrl && e.shiftKey && is('M')) cmd = 'newMilestone';
      else if (ctrl && e.shiftKey && is('G')) cmd = 'newGroup';
      else if (ctrl && e.shiftKey && is('C')) cmd = 'toggleCompleted';
      else if (ctrl && is('E')) cmd = 'editTask';
      else if (ctrl && is('I')) cmd = 'toggleInspector';
      else if (ctrl && is('O')) cmd = 'openWorkspace';
      else if (ctrl && is('W')) cmd = 'closeTab';
      else if (ctrl && !e.shiftKey && is('Z')) cmd = 'undo';
      else if (ctrl && ((e.shiftKey && is('Z')) || is('Y'))) cmd = 'redo';
      else if (ctrl && (e.code === 'Digit1' || e.key === '1')) cmd = 'allTasks';
      else if (ctrl && is('K')) cmd = 'clearFilters';
      else if (ctrl && is('T')) cmd = 'today';
      else if (ctrl && e.key === ',') cmd = 'settings';
      else if (!ctrl && e.altKey && e.key === 'ArrowUp') cmd = 'moveUp';
      else if (!ctrl && e.altKey && e.key === 'ArrowDown') cmd = 'moveDown';
      else if (!ctrl && e.altKey && e.key === 'ArrowLeft') cmd = 'previous';
      else if (!ctrl && e.altKey && e.key === 'ArrowRight') cmd = 'next';
      else if (!ctrl && !e.altKey && (e.key === 'Delete' || e.key === 'Backspace') && (this.store?.selectedTaskID || this.store?.selectedLinkID)) {
        if (this.store.selectedLinkID) { e.preventDefault(); this.store.deleteDependency(this.store.selectedLinkID); return; }
        cmd = 'deleteTask';
      } else if (!ctrl && !e.altKey && e.key === 'Enter' && this.store?.selectedTaskID && !e.target.closest?.('button')) cmd = 'editTask';
      else if (this.store && !ctrl && !e.altKey && ['ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight'].includes(e.key) && document.activeElement !== this.chart.scroller) {
        this.chart.scroller.focus({ preventScroll: true });
        this.chart.keyDown(e);
        return;
      }
      if (!cmd) return;
      e.preventDefault();
      this.command(cmd);
    });
    $('#overlay').addEventListener('mousedown', (e) => { if (e.target.id === 'overlay') e.preventDefault(); });
  }
}

new App().start().catch((e) => {
  window.bridge.log(`Startup failed: ${e.stack || e}`);
  document.body.innerHTML = `<pre style="padding:20px;white-space:pre-wrap">DaySpindle could not start:\n${esc(e.stack || e)}</pre>`;
});
