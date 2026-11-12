'use strict';
/* global Day, Fmt, Weeks, Color, TodayStyle, Theme, rowToolTip, LINK_TYPES, LINK_SIDES, linkTypeForSides */

// The Gantt chart: a fixed corner, a header that follows horizontal scrolling, a task list that
// follows vertical scrolling (never horizontal), and the scrollable timeline. Everything is drawn
// on canvases sized to what is visible, like the Mac app's layer-drawn views.

const CH = {
  headerHeight: 82, monthRowHeight: 24, weekRowHeight: 20, rowHeight: 40, barHeight: 24, minDayWidth: 32,
  groupBarTop: 10, groupBarHeight: 15, milestoneSize: 18, markSize: 13,
  defaultTaskListWidth: 300, minTaskListWidth: 180, maxTaskListWidth: 640, minTimelineWidth: 260, indentStep: 16,
  get dayRowsTop() { return this.monthRowHeight + this.weekRowHeight; },
  chevronX(depth) { return 8 + Math.min(depth, 10) * this.indentStep; },
  titleX(depth) { return this.chevronX(depth) + 34; },
};

// ---------------------------------------------------------------- Drawing helpers
const Draw = {
  setup(canvas, w, h) {
    const dpr = window.devicePixelRatio || 1;
    const pw = Math.max(1, Math.round(w * dpr)), ph = Math.max(1, Math.round(h * dpr));
    if (canvas.width !== pw || canvas.height !== ph) { canvas.width = pw; canvas.height = ph; }
    canvas.style.width = `${w}px`;
    canvas.style.height = `${h}px`;
    const ctx = canvas.getContext('2d');
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    return ctx;
  },
  px(x) { const d = window.devicePixelRatio || 1; return Math.round(x * d) / d; },
  hair() { return 1 / (window.devicePixelRatio || 1); },
  width(ctx, text, font) { ctx.font = font; return ctx.measureText(text).width; },
  /** Text vertically centered in a box, truncated with "…" to the width. */
  text(ctx, text, font, color, x, y, w, h, align = 'left') {
    if (w <= 4) return;
    ctx.font = font;
    let s = text;
    if (ctx.measureText(s).width > w) {
      let lo = 0, hi = s.length;
      while (lo < hi) {
        const mid = (lo + hi + 1) >> 1;
        if (ctx.measureText(s.slice(0, mid) + '…').width <= w) lo = mid; else hi = mid - 1;
      }
      s = s.slice(0, lo).trimEnd() + '…';
    }
    ctx.fillStyle = color;
    ctx.textBaseline = 'middle';
    ctx.textAlign = align;
    const tx = align === 'center' ? x + w / 2 : align === 'right' ? x + w : x;
    ctx.fillText(s, tx, y + h / 2 + 0.5);
    ctx.textAlign = 'left';
  },
  roundRect(ctx, x, y, w, h, r, roundLeft = true, roundRight = true) {
    const rl = roundLeft ? Math.min(r, h / 2, w / 2) : 0, rr = roundRight ? Math.min(r, h / 2, w / 2) : 0;
    ctx.beginPath();
    ctx.moveTo(x + rl, y);
    ctx.lineTo(x + w - rr, y);
    if (rr) ctx.arcTo(x + w, y, x + w, y + rr, rr); else ctx.lineTo(x + w, y);
    ctx.lineTo(x + w, y + h - rr);
    if (rr) ctx.arcTo(x + w, y + h, x + w - rr, y + h, rr); else ctx.lineTo(x + w, y + h);
    ctx.lineTo(x + rl, y + h);
    if (rl) ctx.arcTo(x, y + h, x, y + h - rl, rl); else ctx.lineTo(x, y + h);
    ctx.lineTo(x, y + rl);
    if (rl) ctx.arcTo(x, y, x + rl, y, rl); else ctx.lineTo(x, y);
    ctx.closePath();
  },
  /** The fill and text colors of a completed item: a pale version of its color. */
  completedColors(hex) {
    return Theme.dark ? { fill: Color.mix(hex, '#000000', 0.55), text: Color.mix(hex, '#FFFFFF', 0.55) }
      : { fill: Color.mix(hex, '#FFFFFF', 0.62), text: Color.mix(hex, '#000000', 0.45) };
  },
  /** A check mark drawn with lines, `size` px wide. */
  check(ctx, cx, cy, size, color) {
    ctx.beginPath();
    ctx.moveTo(cx - size * 0.5, cy);
    ctx.lineTo(cx - size * 0.12, cy + size * 0.38);
    ctx.lineTo(cx + size * 0.5, cy - size * 0.4);
    ctx.lineWidth = Math.max(1.3, size * 0.2); ctx.lineCap = 'round'; ctx.lineJoin = 'round';
    ctx.strokeStyle = color;
    ctx.stroke();
  },
  diamond(ctx, cx, cy, size) {
    const h = size / 2;
    ctx.beginPath();
    ctx.moveTo(cx, cy - h); ctx.lineTo(cx + h, cy); ctx.lineTo(cx, cy + h); ctx.lineTo(cx - h, cy);
    ctx.closePath();
  },
  /** A polyline with softly rounded corners. */
  polyline(ctx, pts, radius) {
    ctx.beginPath();
    ctx.moveTo(pts[0].x, pts[0].y);
    for (let k = 1; k < pts.length - 1; k++) {
      const a = pts[k - 1], b = pts[k], c = pts[k + 1];
      const r = Math.min(radius, Math.hypot(b.x - a.x, b.y - a.y) / 2, Math.hypot(c.x - b.x, c.y - b.y) / 2);
      if (r > 0.5) ctx.arcTo(b.x, b.y, c.x, c.y, r); else ctx.lineTo(b.x, b.y);
    }
    ctx.lineTo(pts[pts.length - 1].x, pts[pts.length - 1].y);
  },
  /** A filled arrowhead whose tip is at `tip`, pointing away from `from`. */
  arrowhead(ctx, tip, from, lineWidth) {
    const a = Math.atan2(tip.y - from.y, tip.x - from.x);
    const len = 6 + lineWidth * 1.6, half = 3.2 + lineWidth * 0.9;
    const bx = tip.x - Math.cos(a) * len, by = tip.y - Math.sin(a) * len;
    ctx.beginPath();
    ctx.moveTo(tip.x, tip.y);
    ctx.lineTo(bx + Math.sin(a) * half, by - Math.cos(a) * half);
    ctx.lineTo(bx - Math.sin(a) * half, by + Math.cos(a) * half);
    ctx.closePath();
    ctx.fill();
  },
  chevron(ctx, x, y, left, color) {
    const dx = left ? 2.5 : -2.5;
    ctx.beginPath();
    ctx.moveTo(x + dx, y - 4);
    ctx.lineTo(x - dx, y);
    ctx.lineTo(x + dx, y + 4);
    ctx.strokeStyle = color;
    ctx.lineWidth = 1.5;
    ctx.lineCap = 'round';
    ctx.lineJoin = 'round';
    ctx.stroke();
  },
};

class GanttChart {
  constructor(root, cb) {
    this.root = root;
    this.cb = cb;
    this.model = { rows: [], window: { start: 0, end: 13 }, today: 0, selectedID: null, emptyMessage: null, taskCount: 0, firstWeekday: 0,
      todayHex: TodayStyle.defaultHex, links: [], anchorRow: {}, selectedLinkID: null, nowMinute: null };
    this.dayWidth = 40;
    this.drag = null;      // a bar being moved or resized
    this.linkDraft = null; // an arrow being drawn from a connector handle
    this.hoverItem = null; // the item whose connector handles are shown
    this.hoveredLinkID = null;
    this.reorder = null;   // a row being dragged to a new position
    this.hoveredRowID = null;
    this.timeScrollRemainder = 0;
    this.lastScrollToken = 0;
    this.didInitialScroll = false;
    this.preferredTaskListWidth = CH.defaultTaskListWidth;
    this.taskListWidth = CH.defaultTaskListWidth;
    this.debug = { monthLabels: [], weekLabels: [], weekdayLabels: [] };

    const el = (tag, cls, parent = root) => { const e = document.createElement(tag); e.className = cls; parent.appendChild(e); return e; };
    this.corner = el('canvas', 'pane corner');
    this.header = el('canvas', 'pane header');
    this.left = el('canvas', 'pane left');
    this.body = el('div', 'pane body');
    this.scroller = el('div', 'scroller', this.body);
    this.scroller.tabIndex = 0;
    this.scroller.setAttribute('aria-label', 'Timeline');
    this.spacer = el('div', 'spacer', this.scroller);
    this.timeline = el('canvas', 'timeline', this.body);
    this.handle = el('div', 'resize-handle chart-handle');
    this.handle.title = 'Drag to resize the task list. Double-click to reset.';

    this.scroller.addEventListener('scroll', () => { this.requestDraw(); });
    new ResizeObserver(() => this.layout()).observe(root);
    this.installTimelineEvents();
    this.installLeftEvents();
    this.installHeaderEvents();
    this.installHandle();
  }

  // ---------------------------------------------------------------- Model & layout
  setModel(m) {
    const old = this.model;
    this.model = m;
    if (this.drag && !m.rows.some((r) => r.id === this.drag.id || (r.marks || []).some((k) => k.id === this.drag.id))) this.drag = null;
    if (this.hoverItem && (this.hoverItem.row >= m.rows.length || (!this.hoverItem.markID && m.rows[this.hoverItem.row].id !== this.hoverItem.itemID))) this.hoverItem = null;
    if (old.window.start !== m.window.start || old.window.end !== m.window.end || old.rows.length !== m.rows.length) this.layout();
    else this.requestDraw();
  }

  setTaskListWidth(w, save) {
    this.preferredTaskListWidth = Math.min(Math.max(Math.round(w), CH.minTaskListWidth), CH.maxTaskListWidth);
    if (save) this.cb.onTaskListWidth?.(this.preferredTaskListWidth);
    this.layout();
  }

  layout() {
    const W = this.root.clientWidth, H = this.root.clientHeight;
    if (!W || !H) return;
    const available = Math.max(CH.minTaskListWidth, W - CH.minTimelineWidth);
    this.taskListWidth = Math.min(Math.max(this.preferredTaskListWidth, CH.minTaskListWidth), available);
    const lw = this.taskListWidth, hh = CH.headerHeight, gap = 1;
    const place = (e, x, y, w, h) => Object.assign(e.style, { left: `${x}px`, top: `${y}px`, width: `${Math.max(0, w)}px`, height: `${Math.max(0, h)}px` });
    place(this.corner, 0, 0, lw, hh);
    place(this.header, lw + gap, 0, W - lw - gap, hh);
    place(this.left, 0, hh + gap, lw, H - hh - gap);
    place(this.body, lw + gap, hh + gap, W - lw - gap, H - hh - gap);
    place(this.handle, lw - 4, 0, 9, H);
    this.headerW = Math.max(0, W - lw - gap);
    this.leftH = Math.max(1, H - hh - gap);
    this.updateDocumentSize();
    if (!this.didInitialScroll && this.scroller.clientWidth > 0) {
      this.didInitialScroll = true;
      requestAnimationFrame(() => {
        const w = this.model.window;
        if (this.model.today >= w.start && this.model.today <= w.end) this.scrollToDay(this.model.today, true);
      });
    }
  }

  updateDocumentSize() {
    const cw = this.scroller.clientWidth, chh = this.scroller.clientHeight;
    const days = Math.max(this.model.window.end - this.model.window.start + 1, 1);
    this.dayWidth = Math.max(CH.minDayWidth, cw / days);
    const full = days * this.dayWidth;
    const width = full <= cw + 0.5 ? cw : full;
    const height = Math.max(this.model.rows.length * CH.rowHeight, chh);
    this.spacer.style.width = `${width}px`;
    this.spacer.style.height = `${height}px`;
    this.docWidth = width;
    this.drawNow();
  }

  get scrollX() { return this.scroller.scrollLeft; }
  get scrollY() { return this.scroller.scrollTop; }
  get viewW() { return this.scroller.clientWidth; }
  get viewH() { return this.scroller.clientHeight; }

  requestDraw() {
    if (this.drawPending) return;
    this.drawPending = true;
    requestAnimationFrame(() => { this.drawPending = false; this.drawNow(); });
  }

  drawNow() {
    Theme.dark = window.matchMedia('(prefers-color-scheme: dark)').matches;
    this.root.style.background = Theme.c('divider');
    this.drawCorner();
    this.drawHeader();
    this.drawLeft();
    this.drawTimeline();
  }

  // ---------------------------------------------------------------- Geometry
  dates(row) {
    const d = this.drag;
    if (d) {
      if (d.id === row.id) return [d.start, d.end];
      if (d.shifted?.has(row.id)) { const k = d.start - d.originalStart; return [row.start + k, row.end + k]; }
    }
    return [row.start, row.end];
  }
  /** A milestone mark's day, following a drag in progress. */
  markDay(mark) {
    const d = this.drag;
    if (d) {
      if (d.id === mark.id) return d.start;
      if (d.shifted?.has(mark.id)) return mark.day + (d.start - d.originalStart);
    }
    return mark.day;
  }
  dayX(day) { return (day - this.model.window.start) * this.dayWidth; }
  /** Where in its day a milestone sits: at its time, or in the middle of the day. */
  milestoneX(day, minute) { return this.dayX(day) + this.dayWidth * (minute == null ? 0.5 : Math.min(Math.max(minute, 0), 1440) / 1440); }
  milestoneCenter(i, row) { const [s] = this.dates(row); return { x: this.milestoneX(s, row.minute), y: i * CH.rowHeight + CH.rowHeight / 2 }; }
  markCenter(i, mark) { return { x: this.milestoneX(this.markDay(mark), mark.minute), y: i * CH.rowHeight + CH.rowHeight / 2 }; }
  /** A task's or group's whole bar, even the part outside the visible range. */
  fullBarRect(i, row) {
    const [s, e] = this.dates(row);
    const x0 = this.dayX(s) + 3, x1 = this.dayX(e + 1) - 3;
    if (row.kind === 'group') return { x: x0, y: i * CH.rowHeight + CH.groupBarTop, w: Math.max(x1 - x0, 4), h: CH.groupBarHeight };
    return { x: x0, y: i * CH.rowHeight + (CH.rowHeight - CH.barHeight) / 2, w: Math.max(x1 - x0, 4), h: CH.barHeight };
  }
  rowIndexOf(id) { return this.model.rows.findIndex((r) => r.id === id); }
  /** The box an arrow joins on an item: its whole bar, or the square around a diamond (document coordinates). */
  itemFrame(id) {
    const rowID = this.model.anchorRow?.[id];
    const i = rowID ? this.rowIndexOf(rowID) : -1;
    if (i < 0) return null;
    const row = this.model.rows[i];
    const square = (c, size) => ({ x: c.x - size / 2, y: c.y - size / 2, w: size, h: size });
    if (id !== rowID) {
      const mark = (row.marks || []).find((m) => m.id === id);
      if (mark) return square(this.markCenter(i, mark), CH.markSize);
    }
    if (row.kind === 'milestone') return square(this.milestoneCenter(i, row), CH.milestoneSize);
    if (row.hasDates === false) return null;
    return this.fullBarRect(i, row);
  }
  static sidePoint(r, side) {
    if (side === 'left') return { x: r.x, y: r.y + r.h / 2 };
    if (side === 'right') return { x: r.x + r.w, y: r.y + r.h / 2 };
    if (side === 'top') return { x: r.x + r.w / 2, y: r.y };
    return { x: r.x + r.w / 2, y: r.y + r.h };
  }
  /** Where an arrow leaves or arrives at an item: the middle of one of its four sides (left is its start,
   * right its end), in document coordinates. */
  anchor(id, side) {
    const r = this.itemFrame(id);
    return r ? GanttChart.sidePoint(r, side) : null;
  }
  /** The arrow's route: out of the predecessor, along the rows, into the successor, with right-angle turns. */
  linkPoints(link) {
    const ra = this.itemFrame(link.from), rb = this.itemFrame(link.to);
    if (!ra || !rb) return null;
    const rowA = this.model.anchorRow[link.from];
    if (rowA && rowA === this.model.anchorRow[link.to]) {
      const row = this.model.rows[this.rowIndexOf(rowA)];
      const shown = (id) => id === rowA || (row?.marks || []).some((m) => m.id === id);
      if (!shown(link.from) && !shown(link.to)) return null; // both folded into the same group
    }
    return this.bestRoute(ra, link.exitSide || 'right', rb, link.entrySide || 'left');
  }
  /** Of the right-angled routes that fit the sides, the one crossing the fewest other bars and diamonds
   * (the simplest one when they tie). */
  bestRoute(ra, s1, rb, s2) {
    const candidates = GanttChart.routes(ra, s1, rb, s2);
    const rows = this.model.rows;
    if (candidates.length < 2 || !rows.length) return candidates[0];
    const lo = Math.min(ra.y, rb.y) - CH.rowHeight, hi = Math.max(ra.y + ra.h, rb.y + rb.h) + CH.rowHeight;
    const first = Math.max(0, Math.floor(lo / CH.rowHeight)), last = Math.min(rows.length - 1, Math.floor(hi / CH.rowHeight));
    const obstacles = [];
    for (let i = first; i <= last; i++) {
      const row = rows[i];
      if (row.kind === 'milestone') {
        const c = this.milestoneCenter(i, row), h = CH.milestoneSize / 2;
        obstacles.push({ x: c.x - h, y: c.y - h, w: 2 * h, h: 2 * h });
      } else if (row.hasDates !== false) obstacles.push(this.fullBarRect(i, row));
    }
    const crossings = (pts) => {
      let n = 0;
      for (let k = 1; k < pts.length; k++) for (const r of obstacles) if (GanttChart.crosses(pts[k - 1], pts[k], r)) n++;
      return n;
    };
    let best = 0, bestScore = Infinity;
    candidates.forEach((c, k) => { const n = crossings(c); if (n < bestScore) { best = k; bestScore = n; } });
    return candidates[best];
  }
  /** Whether a horizontal or vertical segment passes through the inside of a box (1 pt in from its edges). */
  static crosses(a, b, r) {
    const x0 = r.x + 1, x1 = r.x + r.w - 1, y0 = r.y + 1, y1 = r.y + r.h - 1;
    if (Math.abs(a.y - b.y) < 0.01) return a.y > y0 && a.y < y1 && Math.max(a.x, b.x) > x0 && Math.min(a.x, b.x) < x1;
    return a.x > x0 && a.x < x1 && Math.max(a.y, b.y) > y0 && Math.min(a.y, b.y) < y1;
  }
  /** Right-angled routes that leave box `ra` through side `s1` and enter box `rb` through `s2`, simplest
   * first. Left and right ends take a short step sideways first; top and bottom ends a short step up or
   * down, so lines run in the gaps between rows. */
  static routes(ra, s1, rb, s2) {
    const a = GanttChart.sidePoint(ra, s1), b = GanttChart.sidePoint(rb, s2);
    const S1 = LINK_SIDES[s1], S2 = LINK_SIDES[s2];
    const v1 = S1.dy !== 0, v2 = S2.dy !== 0;
    const gapH = 10, gapV = 8;
    const out = [];
    const add = (middle) => out.push(GanttChart.simplified([a, ...middle, b]));
    const P = (x, y) => ({ x, y });
    if (!v1 && !v2) {
      const o = S1.dx, into = -S2.dx; // direction leaving the predecessor / of travel entering the successor
      const e0 = a.x + o * gapH, e1 = b.x - into * gapH;
      if (Math.abs(a.y - b.y) < 0.5 && (b.x - a.x) * into > gapH && o === into) add([]);
      else if (o === into) {
        if ((e1 - e0) * o >= 0) add([P(e0, a.y), P(e0, b.y)]);
        else {
          const yMid = a.y + (b.y >= a.y ? 1 : -1) * CH.rowHeight / 2;
          add([P(e0, a.y), P(e0, yMid), P(e1, yMid), P(e1, b.y)]);
        }
      } else {
        const xv = o > 0 ? Math.max(e0, e1) : Math.min(e0, e1);
        add([P(xv, a.y), P(xv, b.y)]);
      }
    } else if (v1 && v2) {
      const o = S1.dy, into = -S2.dy;
      const e0 = a.y + o * gapV, e1 = b.y - into * gapV;
      if (Math.abs(a.x - b.x) < 0.5 && (b.y - a.y) * into > gapV && o === into) add([]);
      else if (o === into) {
        if ((e1 - e0) * o >= 0) {
          // Along the gap next to the successor, or the one next to the predecessor.
          add([P(a.x, e1), P(b.x, e1)]);
          add([P(a.x, e0), P(b.x, e0)]);
        } else {
          // The successor is the wrong way: go round beside both items.
          const left = Math.min(ra.x, rb.x) - gapH, right = Math.max(ra.x + ra.w, rb.x + rb.w) + gapH;
          const near = Math.abs(a.x - left) + Math.abs(b.x - left) <= Math.abs(a.x - right) + Math.abs(b.x - right);
          for (const x of near ? [left, right] : [right, left]) add([P(a.x, e0), P(x, e0), P(x, e1), P(b.x, e1)]);
        }
      } else {
        const yv = o > 0 ? Math.max(e0, e1) : Math.min(e0, e1);
        add([P(a.x, yv), P(b.x, yv)]);
      }
    } else if (!v1 && v2) {
      const o = S1.dx, into = -S2.dy;
      if ((b.x - a.x) * o >= gapH && (b.y - a.y) * into >= gapV) add([P(b.x, a.y)]); // one turn
      const x0 = a.x + o * gapH, y1 = b.y - into * gapV;
      add([P(x0, a.y), P(x0, y1), P(b.x, y1)]);
    } else {
      const o = S1.dy, into = -S2.dx;
      if ((b.y - a.y) * o >= gapV && (b.x - a.x) * into >= gapH) add([P(a.x, b.y)]); // one turn
      const y0 = a.y + o * gapV, x1 = b.x - into * gapH;
      add([P(a.x, y0), P(x1, y0), P(x1, b.y)]);
    }
    return out;
  }
  /** Drops repeated points and points in the middle of a straight run. */
  static simplified(pts) {
    const out = [];
    for (const p of pts) {
      const last = out[out.length - 1];
      if (last && Math.abs(last.x - p.x) < 0.01 && Math.abs(last.y - p.y) < 0.01) continue;
      if (out.length >= 2) {
        const a = out[out.length - 2], b = last;
        const cross = (b.x - a.x) * (p.y - b.y) - (b.y - a.y) * (p.x - b.x);
        const dot = (b.x - a.x) * (p.x - b.x) + (b.y - a.y) * (p.y - b.y);
        if (Math.abs(cross) < 0.01 && dot >= 0) out.pop();
      }
      out.push(p);
    }
    return out;
  }
  static segDist(p, a, b) {
    const dx = b.x - a.x, dy = b.y - a.y, l2 = dx * dx + dy * dy;
    if (!l2) return Math.hypot(p.x - a.x, p.y - a.y);
    const t = Math.max(0, Math.min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / l2));
    return Math.hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy));
  }
  /** The arrow under a document point, if any. */
  linkAt(p) {
    let best = null;
    for (const l of this.model.links || []) {
      const pts = this.linkPoints(l);
      if (!pts) continue;
      const tol = Math.max(4, l.width / 2 + 3);
      for (let k = 1; k < pts.length; k++) {
        const d = GanttChart.segDist(p, pts[k - 1], pts[k]);
        if (d <= tol && (!best || d < best.d)) best = { id: l.id, d };
      }
    }
    return best?.id || null;
  }
  /** The item under a point when drawing an arrow, and the side of it nearest the point. */
  linkTarget(p, fromID) {
    const i = this.rowIndexAtY(p.y);
    if (i == null) return null;
    const row = this.model.rows[i];
    let found = null;
    for (const m of row.marks || []) {
      if (m.id === fromID) continue;
      const c = this.markCenter(i, m);
      if (Math.abs(p.x - c.x) <= CH.markSize / 2 + 5) found = m.id;
    }
    if (!found && row.id !== fromID) {
      if (row.kind === 'milestone') {
        const c = this.milestoneCenter(i, row);
        if (Math.abs(p.x - c.x) <= CH.milestoneSize / 2 + 6) found = row.id;
      } else if (row.hasDates !== false) {
        const r = this.fullBarRect(i, row);
        if (p.x >= r.x - 6 && p.x <= r.x + r.w + 6 && p.y >= r.y - 8 && p.y <= r.y + r.h + 8) found = row.id;
      }
    }
    if (!found || (this.cb.canLink && !this.cb.canLink(fromID, found))) return null;
    const frame = this.itemFrame(found);
    if (!frame) return null;
    let side = 'left', best = Infinity;
    for (const k of Object.keys(LINK_SIDES)) {
      const q = GanttChart.sidePoint(frame, k), d = Math.hypot(p.x - q.x, p.y - q.y);
      if (d < best) { best = d; side = k; }
    }
    return { id: found, side, point: GanttChart.sidePoint(frame, side) };
  }
  /** Connector handles of the hovered item: just outside the middle of each of its four sides. */
  handles(h) {
    const out = [];
    for (const [side, S] of Object.entries(LINK_SIDES)) {
      const a = this.anchor(h.itemID, side);
      if (!a) continue;
      const d = S.dy ? 9 : 11;
      const c = { x: a.x + S.dx * d, y: a.y + S.dy * d };
      if (!(c.x > this.scrollX + 2 && c.x < this.scrollX + this.viewW - 2)) continue;
      // Keep the top and bottom handles fully in view.
      c.y = Math.min(Math.max(c.y, this.scrollY + 7), this.scrollY + this.viewH - 7);
      out.push({ side, center: c });
    }
    return out;
  }
  /** What moves along when an item is dragged: everything below a group, a task's milestones. */
  shiftedIDs(index) {
    const rows = this.model.rows, row = rows[index];
    const ids = new Set((row.marks || []).map((m) => m.id));
    if (row.kind !== 'group') return ids;
    for (let k = index + 1; k < rows.length && rows[k].depth > row.depth; k++) {
      ids.add(rows[k].id);
      for (const m of rows[k].marks || []) ids.add(m.id);
    }
    return ids;
  }
  dayAtX(x) { return this.model.window.start + Math.floor(x / this.dayWidth); }
  rowIndexAtY(y) { const i = Math.floor(y / CH.rowHeight); return y >= 0 && i < this.model.rows.length ? i : null; }

  /** The visible part of a bar, in document coordinates, plus whether the window cuts it off. */
  barRect(index, start, end) {
    const w = this.model.window;
    const s = Math.max(start, w.start), e = Math.min(end, w.end);
    if (s > e) return null;
    const inset = 3;
    const x0 = (s - w.start) * this.dayWidth + (start >= w.start ? inset : 0);
    const x1 = (e - w.start + 1) * this.dayWidth - (end <= w.end ? inset : 0);
    const y = index * CH.rowHeight + (CH.rowHeight - CH.barHeight) / 2;
    return { x: x0, y, w: Math.max(x1 - x0, 4), h: CH.barHeight, clippedLeft: start < w.start, clippedRight: end > w.end };
  }

  /** A "‹ Oct 12 – Oct 14" pill for an item entirely outside the window, pinned to the visible edge. */
  hintRect(index, row) {
    if (row.hasDates === false) return null;
    const w = this.model.window;
    const before = row.end < w.start, after = row.start > w.end;
    if (!before && !after) return null;
    const range = row.kind === 'milestone' ? `◆ ${Fmt.short(row.start)}` : Fmt.range(row.start, row.end, Day.year(this.model.today));
    const text = before ? `‹  ${range}` : `${range}  ›`;
    const ctx = this.timeline.getContext('2d');
    const width = Draw.width(ctx, text, Theme.font(11)) + 16;
    const y = index * CH.rowHeight + (CH.rowHeight - 20) / 2;
    const x = before ? this.scrollX + 6 : this.scrollX + this.viewW - width - 6;
    return { x, y, w: width, h: 20, text };
  }

  hit(p) {
    // Connector handles of the hovered item come first: they sit just outside it.
    if (this.hoverItem && !this.drag) {
      for (const hd of this.handles(this.hoverItem)) {
        if (Math.hypot(p.x - hd.center.x, p.y - hd.center.y) <= 8) {
          return { kind: 'handle', id: this.hoverItem.itemID, side: hd.side, point: this.anchor(this.hoverItem.itemID, hd.side) || hd.center };
        }
      }
    }
    const i = this.rowIndexAtY(p.y);
    if (i == null) { const l = this.linkAt(p); return l ? { kind: 'link', id: l } : { kind: 'empty' }; }
    const row = this.model.rows[i];
    for (const m of (row.marks || []).slice().reverse()) {
      const c = this.markCenter(i, m);
      if (Math.abs(p.x - c.x) + Math.abs(p.y - c.y) <= CH.markSize / 2 + 4) return { kind: 'mark', index: i, id: m.id };
    }
    const [s, e] = this.dates(row);
    if (row.kind === 'milestone') {
      const c = this.milestoneCenter(i, row);
      if (s >= this.model.window.start && s <= this.model.window.end && Math.abs(p.x - c.x) + Math.abs(p.y - c.y) <= CH.milestoneSize / 2 + 4) {
        return { kind: 'bar', index: i, mode: 'move' };
      }
    } else if (row.kind === 'group') {
      const r = row.hasDates === false ? null : this.barRect(i, s, e);
      if (r && p.x >= r.x - 3 && p.x <= r.x + r.w + 3 && p.y >= i * CH.rowHeight + CH.groupBarTop - 4 && p.y <= i * CH.rowHeight + CH.groupBarTop + CH.groupBarHeight + 10) {
        return { kind: 'bar', index: i, mode: 'move' };
      }
    } else {
      const r = this.barRect(i, s, e);
      if (r && p.x >= r.x - 3 && p.x <= r.x + r.w + 3 && p.y >= r.y - 3 && p.y <= r.y + r.h + 3) {
        const edge = Math.min(8, Math.max(4, r.w / 4));
        if (!r.clippedLeft && p.x <= r.x + edge) return { kind: 'bar', index: i, mode: 'resizeStart' };
        if (!r.clippedRight && p.x >= r.x + r.w - edge) return { kind: 'bar', index: i, mode: 'resizeEnd' };
        return { kind: 'bar', index: i, mode: 'move' };
      }
    }
    const l = this.linkAt(p);
    if (l) return { kind: 'link', id: l };
    const h = this.hintRect(i, row);
    if (h && p.x >= h.x && p.x <= h.x + h.w && p.y >= h.y && p.y <= h.y + h.h) return { kind: 'hint', index: i };
    return { kind: 'row', index: i };
  }

  /** Scrolls horizontally so `day` is centered (when the timeline is wider than the view). */
  scrollToDay(day, onlyIfHidden = false) {
    this.updateDocumentSize();
    const w = this.model.window;
    const clamped = Math.min(Math.max(day, w.start), w.end);
    const dayX = (clamped - w.start) * this.dayWidth;
    if (onlyIfHidden && dayX >= this.scrollX && dayX + this.dayWidth <= this.scrollX + this.viewW) return;
    const x = Math.max(0, Math.min(dayX + this.dayWidth / 2 - this.viewW / 2, this.docWidth - this.viewW));
    this.scroller.scrollLeft = x;
    this.requestDraw();
  }

  handleScrollRequest(req) {
    if (req && req.token !== this.lastScrollToken) {
      this.lastScrollToken = req.token;
      requestAnimationFrame(() => this.scrollToDay(req.day));
    }
  }

  /** Horizontal scrolling: first within the visible range; past either end it keeps going by
   * moving the range itself, a day at a time. `dx` > 0 moves later in time. */
  scrollTime(dx) {
    const maxX = Math.max(0, this.docWidth - this.viewW);
    const x = this.scrollX, wanted = x + dx;
    const newX = Math.min(Math.max(wanted, 0), maxX);
    if (Math.abs(newX - x) > 0.01) this.scroller.scrollLeft = newX;
    const overflow = wanted - newX;
    if (overflow === 0 || (overflow > 0) !== (this.timeScrollRemainder > 0)) this.timeScrollRemainder = 0;
    this.timeScrollRemainder += overflow;
    const days = Math.trunc(this.timeScrollRemainder / this.dayWidth);
    if (days !== 0) {
      this.timeScrollRemainder -= days * this.dayWidth;
      this.cb.onShiftDays?.(days);
    }
  }

  /** Wheel handling shared by the panes: sideways goes through time, up/down scrolls the rows. */
  wheel(e) {
    let dx = e.deltaX, dy = e.deltaY;
    const unit = e.deltaMode === 1 ? 40 : e.deltaMode === 2 ? this.viewW : 1;
    dx *= unit; dy *= unit;
    if (e.shiftKey && dx === 0) { dx = dy; dy = 0; }
    if (Math.abs(dx) > Math.abs(dy)) { e.preventDefault(); this.scrollTime(dx); return true; }
    return false;
  }

  select(id) {
    this.model.selectedID = id;
    if (id) this.model.selectedLinkID = null;
    this.cb.onSelect?.(id);
    this.requestDraw();
  }
  selectLink(id) {
    this.model.selectedLinkID = id;
    if (id) this.model.selectedID = null;
    this.cb.onSelectLink?.(id);
    this.requestDraw();
  }

  selectNeighbor(offset) {
    const rows = this.model.rows;
    if (!rows.length) return;
    let index = 0;
    const i = rows.findIndex((r) => r.id === this.model.selectedID);
    if (i >= 0) index = Math.min(Math.max(i + offset, 0), rows.length - 1);
    else if (offset < 0) index = rows.length - 1;
    this.select(rows[index].id);
    const top = index * CH.rowHeight;
    if (top < this.scrollY) this.scroller.scrollTop = top;
    else if (top + CH.rowHeight > this.scrollY + this.viewH) this.scroller.scrollTop = top + CH.rowHeight - this.viewH;
  }

  /** ← collapses the selected parent or moves to its parent; → expands it or moves to its first subtask. */
  outlineKey(right) {
    const rows = this.model.rows;
    const i = rows.findIndex((r) => r.id === this.model.selectedID);
    if (i < 0) return;
    const row = rows[i];
    if (right) {
      if (row.hasChildren && row.collapsed) this.cb.onToggle?.(row.id);
      else if (row.hasChildren) this.selectNeighbor(1);
    } else if (row.hasChildren && !row.collapsed) this.cb.onToggle?.(row.id);
    else if (row.parentID) {
      const pi = rows.findIndex((r) => r.id === row.parentID);
      if (pi >= 0) this.selectNeighbor(pi - i);
    }
  }

  // ---------------------------------------------------------------- Reordering in the task list
  /** Starts dragging a task: it may only land among its siblings (same parent, same level). */
  beginReorder(id) {
    const rows = this.model.rows;
    const i = rows.findIndex((r) => r.id === id);
    if (i < 0) return;
    const row = rows[i], rh = CH.rowHeight;
    // Among the siblings listed with it: unfinished items, or completed ones (listed after them).
    const sibs = rows.map((r, k) => [r, k]).filter(([r]) => r.parentID === row.parentID && r.depth === row.depth && !!r.completed === !!row.completed);
    const slots = sibs.map(([r, k]) => ({ y: k * rh, beforeID: r.id, depth: row.depth }));
    if (sibs.length) {
      let end = sibs[sibs.length - 1][1] + 1;
      while (end < rows.length && rows[end].depth > row.depth) end++;
      slots.push({ y: end * rh, beforeID: null, depth: row.depth });
    }
    this.reorder = { id, slots, current: null };
    this.requestDraw();
  }
  updateReorder(docY) {
    const r = this.reorder;
    if (!r || !r.slots.length) return;
    let best = 0;
    r.slots.forEach((s, k) => { if (Math.abs(s.y - docY) < Math.abs(r.slots[best].y - docY)) best = k; });
    if (best !== r.current) { r.current = best; this.requestDraw(); }
  }
  endReorder(commit) {
    const r = this.reorder;
    if (!r) return;
    this.reorder = null;
    this.requestDraw();
    if (commit && r.current != null) this.cb.onReorder?.(r.id, r.slots[r.current].beforeID);
  }

  // ---------------------------------------------------------------- Menus
  rowMenu(index) {
    const row = this.model.rows[index];
    this.select(row.id);
    const w = this.model.window;
    const inView = (row.start >= w.start && row.start <= w.end) || (row.end >= w.start && row.end <= w.end) || (row.start < w.start && row.end > w.end);
    const items = [{ label: 'Show Details', id: 'edit' }, { label: row.completed ? 'Return from Archive' : 'Mark as Completed', id: 'complete' }];
    if (row.kind !== 'milestone') {
      items.push({ label: 'Add Subtask', id: 'subtask' }, { label: row.kind === 'task' ? 'Add Milestone to This Task' : 'Add Milestone', id: 'milestone' });
    }
    if (row.hasChildren) items.push({ label: row.collapsed ? 'Expand Group' : 'Collapse Group', id: 'toggle' });
    if (row.parentID) {
      const t = this.cb.parentTitle?.(row.parentID);
      items.push({ label: t ? `Move Out of “${t}”` : 'Move Up a Level', id: 'moveOut' });
    }
    items.push({ label: 'Move Up', id: 'up', enabled: !!this.cb.canMoveBy?.(row.id, -1) });
    items.push({ label: 'Move Down', id: 'down', enabled: !!this.cb.canMoveBy?.(row.id, 1) });
    if (!inView) items.push({ label: 'Show in Timeline', id: 'reveal' });
    items.push({ type: 'separator' }, { label: `Delete ${{ task: 'Task', group: 'Group', milestone: 'Milestone' }[row.kind] || 'Task'}…`, id: 'delete' });
    window.bridge.popup(items).then((id) => {
      const act = { edit: () => this.cb.onOpen?.(row.id), subtask: () => this.cb.onNewSubtask?.(row.id), toggle: () => this.cb.onToggle?.(row.id),
        complete: () => this.cb.onComplete?.(row.id, !row.completed),
        milestone: () => this.cb.onAddMilestone?.(row.id),
        moveOut: () => this.cb.onMoveOut?.(row.id), up: () => this.cb.onMoveBy?.(row.id, -1), down: () => this.cb.onMoveBy?.(row.id, 1),
        reveal: () => this.cb.onReveal?.(row.id), delete: () => this.cb.onDelete?.(row.id) }[id];
      act?.();
    });
  }

  emptyMenu(day) {
    window.bridge.popup([{ label: `New Task on ${Fmt.short(day)}`, id: 'new' }]).then((id) => { if (id) this.cb.onCreate?.(day); });
  }

  /** Right-click on a milestone shown on a task's bar. */
  markMenu(id) {
    this.select(id);
    const mark = this.model.rows.flatMap((r) => r.marks || []).find((m) => m.id === id);
    window.bridge.popup([{ label: 'Show Details', id: 'edit' }, { label: mark?.completed ? 'Mark as Not Completed' : 'Mark as Completed', id: 'complete' },
      { type: 'separator' }, { label: 'Delete Milestone…', id: 'delete' }]).then((r) => {
      if (r === 'edit') this.cb.onOpen?.(id); else if (r === 'delete') this.cb.onDelete?.(id);
      else if (r === 'complete') this.cb.onComplete?.(id, !mark?.completed);
    });
  }

  /** Right-click on an arrow. */
  linkMenu(id) {
    this.selectLink(id);
    const link = (this.model.links || []).find((l) => l.id === id);
    const cur = link?.type;
    const sides = (exit) => Object.entries(LINK_SIDES).map(([k, t]) =>
      ({ label: t.title, id: `${exit ? 'exit' : 'entry'}:${k}`, checked: (exit ? link?.exitSide : link?.entrySide) === k, radio: true }));
    window.bridge.popup([
      { label: 'Show Details', id: 'open' },
      { label: 'Connect', submenu: Object.entries(LINK_TYPES).map(([k, t]) => ({ label: t.title, id: `type:${k}`, checked: cur === k, radio: true })) },
      { label: 'Leaves From', submenu: sides(true) },
      { label: 'Arrives At', submenu: sides(false) },
      { type: 'separator' },
      { label: 'Delete Arrow', id: 'delete' },
    ]).then((r) => {
      if (r === 'open') this.cb.onOpenLink?.(id);
      else if (r === 'delete') this.cb.onDeleteLink?.(id);
      else if (r && r.startsWith('type:')) this.cb.onLinkType?.(id, r.slice(5));
      else if (r && r.startsWith('exit:')) this.cb.onLinkSide?.(id, true, r.slice(5));
      else if (r && r.startsWith('entry:')) this.cb.onLinkSide?.(id, false, r.slice(6));
    });
  }

  /** Right-click on the header: the Today spindle's color (on today's column) and the first day of the week. */
  headerMenu(onToday) {
    const m = this.model;
    const colors = TodayStyle.choices.map(([name, hex]) => ({ label: name, id: `color:${hex}`, checked: m.todayHex === hex, radio: true, swatch: hex }));
    const isCustom = !TodayStyle.choices.some(([, hex]) => hex === m.todayHex);
    colors.push({ label: isCustom ? `Custom (${m.todayHex})…` : 'Custom Color…', id: 'custom', checked: isCustom ? true : undefined, radio: true, swatch: isCustom ? m.todayHex : undefined });
    const items = onToday
      ? [{ label: 'Today Color', id: 'title', enabled: false }, ...colors]
      : [{ label: 'Today Color', submenu: colors }];
    items.push({ type: 'separator' }, {
      label: 'First Day of Week',
      submenu: [0, 1, 6].map((d) => ({ label: Fmt.weekdayLong[d], id: `week:${d}`, checked: m.firstWeekday === d, radio: true })),
    });
    window.bridge.popup(items).then((id) => {
      if (!id) return;
      if (id.startsWith('color:')) this.cb.onTodayColor?.(id.slice(6));
      else if (id === 'custom') this.cb.onCustomTodayColor?.();
      else if (id.startsWith('week:')) this.cb.onFirstWeekday?.(+id.slice(5));
    });
  }

  // ---------------------------------------------------------------- Timeline events
  docPoint(e) {
    const r = this.scroller.getBoundingClientRect();
    return { x: e.clientX - r.left + this.scrollX, y: e.clientY - r.top + this.scrollY, vx: e.clientX - r.left, vy: e.clientY - r.top };
  }

  cursorFor(h) {
    if (h.kind === 'bar') return h.mode === 'move' ? 'grab' : 'ew-resize';
    if (h.kind === 'mark') return 'grab';
    if (h.kind === 'handle') return 'crosshair';
    if (h.kind === 'hint' || h.kind === 'link') return 'pointer';
    return 'default';
  }

  installTimelineEvents() {
    const sc = this.scroller;
    sc.addEventListener('wheel', (e) => this.wheel(e), { passive: false });
    sc.addEventListener('mousemove', (e) => {
      if (this.drag || this.linkDraft || e.buttons) return;
      const p = this.docPoint(e);
      if (p.vx > this.viewW || p.vy > this.viewH) { this.setHover(null); this.setHoverItem(null); sc.style.cursor = 'default'; return; }
      const h = this.hit(p);
      sc.style.cursor = this.cursorFor(h);
      if (h.kind === 'bar') this.setHoverItem({ row: h.index, markID: null, itemID: this.model.rows[h.index].id });
      else if (h.kind === 'mark') this.setHoverItem({ row: h.index, markID: h.id, itemID: h.id });
      else if (h.kind !== 'handle') this.setHoverItem(null);
      const id = h.index != null ? this.model.rows[h.index].id : null;
      if (h.kind !== 'handle') this.setHover(id);
      const linkID = h.kind === 'link' ? h.id : null;
      if (linkID !== this.hoveredLinkID) { this.hoveredLinkID = linkID; this.requestDraw(); }
      let tip = null;
      if (h.kind === 'mark') {
        const m = this.model.rows[h.index].marks.find((x) => x.id === h.id);
        tip = m ? `◆ ${m.title}\n${Fmt.medium(m.day)}${m.detail ? ' · ' + m.detail : ''}` : null;
      } else if (h.kind === 'bar' || h.kind === 'hint') tip = rowToolTip(this.model.rows[h.index], this.model.today);
      if ((sc.title || '') !== (tip || '')) sc.title = tip || '';
    });
    sc.addEventListener('mouseleave', () => {
      if (this.drag || this.linkDraft) return;
      this.setHover(null);
      this.setHoverItem(null);
      if (this.hoveredLinkID) { this.hoveredLinkID = null; this.requestDraw(); }
    });
    sc.addEventListener('mousedown', (e) => {
      if (e.button !== 0) return;
      const p = this.docPoint(e);
      if (p.vx > this.viewW || p.vy > this.viewH) return; // the scroll bars
      sc.focus({ preventScroll: true });
      e.preventDefault();
      const h = this.hit(p);
      if (h.kind === 'handle') {
        this.linkDraft = { fromID: h.id, fromSide: h.side, origin: h.point, current: p, target: null };
        sc.style.cursor = 'crosshair';
        this.trackLinkDraft();
      } else if (h.kind === 'bar') {
        const row = this.model.rows[h.index];
        this.select(row.id);
        if (e.detail >= 2) { this.cb.onOpen?.(row.id); return; }
        const [s0, e0] = this.dates(row);
        this.drag = { id: row.id, mode: h.mode, anchorX: p.x, originalStart: s0, originalEnd: e0, start: s0, end: e0, shifted: this.shiftedIDs(h.index) };
        sc.style.cursor = h.mode === 'move' ? 'grabbing' : 'ew-resize';
        this.trackDrag(e);
      } else if (h.kind === 'mark') {
        this.select(h.id);
        if (e.detail >= 2) { this.cb.onOpen?.(h.id); return; }
        const m = this.model.rows[h.index].marks.find((x) => x.id === h.id);
        this.drag = { id: h.id, mode: 'move', anchorX: p.x, originalStart: m.day, originalEnd: m.day, start: m.day, end: m.day, shifted: new Set() };
        sc.style.cursor = 'grabbing';
        this.trackDrag(e);
      } else if (h.kind === 'link') {
        this.selectLink(h.id);
        if (e.detail >= 2) this.cb.onOpenLink?.(h.id);
      } else if (h.kind === 'hint') {
        this.cb.onReveal?.(this.model.rows[h.index].id);
      } else if (h.kind === 'row') {
        this.select(this.model.rows[h.index].id);
        if (e.detail === 2) this.cb.onCreate?.(this.dayAtX(p.x));
      } else {
        this.select(null);
        this.selectLink(null);
        if (e.detail === 2) this.cb.onCreate?.(this.dayAtX(p.x));
      }
    });
    sc.addEventListener('contextmenu', (e) => {
      e.preventDefault();
      const p = this.docPoint(e);
      const h = this.hit(p);
      if (h.kind === 'empty') this.emptyMenu(this.dayAtX(p.x));
      else if (h.kind === 'mark') this.markMenu(h.id);
      else if (h.kind === 'link') this.linkMenu(h.id);
      else if (h.kind === 'handle') { const i = this.rowIndexOf(this.model.anchorRow[h.id]); if (i >= 0) this.rowMenu(i); }
      else this.rowMenu(h.index);
    });
    sc.addEventListener('keydown', (e) => this.keyDown(e));
  }

  setHover(id) {
    if (this.hoveredRowID !== id) { this.hoveredRowID = id; this.requestDraw(); }
  }
  setHoverItem(h) {
    const same = (a, b) => (!a && !b) || (a && b && a.row === b.row && a.itemID === b.itemID);
    if (!same(this.hoverItem, h)) { this.hoverItem = h; this.requestDraw(); }
  }

  /** Drawing an arrow: follows the pointer; letting go over another item joins them. */
  trackLinkDraft() {
    const move = (e) => {
      const d = this.linkDraft;
      if (!d) return;
      const r = this.scroller.getBoundingClientRect();
      if (e.clientX < r.left + 20) this.scroller.scrollLeft -= 12;
      else if (e.clientX > r.left + this.viewW - 20) this.scroller.scrollLeft += 12;
      const p = this.docPoint(e);
      d.current = p;
      d.target = this.linkTarget(p, d.fromID);
      this.drawNow();
    };
    const up = () => {
      window.removeEventListener('mousemove', move, true);
      window.removeEventListener('mouseup', up, true);
      const d = this.linkDraft;
      this.linkDraft = null;
      this.scroller.style.cursor = 'default';
      if (d && d.target) this.cb.onLink?.(d.fromID, d.fromSide, d.target.id, d.target.side);
      this.requestDraw();
    };
    window.addEventListener('mousemove', move, true);
    window.addEventListener('mouseup', up, true);
  }

  trackDrag(downEvent) {
    const move = (e) => {
      const d = this.drag;
      if (!d) return;
      const r = this.scroller.getBoundingClientRect();
      // Scroll when dragging near the left or right edge.
      if (e.clientX < r.left + 20) this.scroller.scrollLeft -= 12;
      else if (e.clientX > r.left + this.viewW - 20) this.scroller.scrollLeft += 12;
      const p = this.docPoint(e);
      const delta = Math.round((p.x - d.anchorX) / this.dayWidth);
      let s = d.start, en = d.end;
      if (d.mode === 'move') { s = d.originalStart + delta; en = d.originalEnd + delta; }
      else if (d.mode === 'resizeStart') { s = Math.min(d.originalStart + delta, d.originalEnd); en = d.originalEnd; }
      else { s = d.originalStart; en = Math.max(d.originalEnd + delta, d.originalStart); }
      if (s !== d.start || en !== d.end) { d.start = s; d.end = en; this.drawNow(); }
    };
    const up = () => {
      window.removeEventListener('mousemove', move, true);
      window.removeEventListener('mouseup', up, true);
      const d = this.drag;
      this.drag = null;
      this.scroller.style.cursor = 'default';
      if (d && (d.start !== d.originalStart || d.end !== d.originalEnd)) {
        const k = d.start - d.originalStart;
        for (const row of this.model.rows) {
          if (row.id === d.id) { row.start = d.start; row.end = d.end; }
          else if (d.shifted?.has(row.id)) { row.start += k; row.end += k; }
          for (const m of row.marks || []) {
            if (m.id === d.id) m.day = d.start; else if (d.shifted?.has(m.id)) m.day += k;
          }
        }
        this.cb.onCommit?.(d.id, d.start, d.end);
      }
      this.requestDraw();
    };
    window.addEventListener('mousemove', move, true);
    window.addEventListener('mouseup', up, true);
    move(downEvent);
  }

  keyDown(e) {
    const id = this.model.selectedID;
    const k = e.key;
    if (e.ctrlKey || e.metaKey) return;
    const link = this.model.selectedLinkID;
    if (k === 'Delete' || k === 'Backspace') { if (link) this.cb.onDeleteLink?.(link); else if (id) this.cb.onDelete?.(id); }
    else if (k === 'Enter') { if (link) this.cb.onOpenLink?.(link); else if (id) this.cb.onOpen?.(id); }
    else if (e.altKey && (k === 'ArrowUp' || k === 'ArrowDown')) { if (id) this.cb.onMoveBy?.(id, k === 'ArrowUp' ? -1 : 1); }
    else if (e.altKey) return;
    else if (k === 'ArrowDown') this.selectNeighbor(1);
    else if (k === 'ArrowUp') this.selectNeighbor(-1);
    else if (k === 'ArrowLeft') this.outlineKey(false);
    else if (k === 'ArrowRight') this.outlineKey(true);
    else if (k === 'Escape') {
      if (this.linkDraft) { this.linkDraft = null; this.requestDraw(); }
      else if (this.reorder) this.endReorder(false);
      else if (this.drag) { this.drag = null; this.requestDraw(); }
      else { this.select(null); this.selectLink(null); }
    } else return;
    e.preventDefault();
    e.stopPropagation();
  }

  // ---------------------------------------------------------------- Task list events
  leftPoint(e) {
    const r = this.left.getBoundingClientRect();
    return { x: e.clientX - r.left, y: e.clientY - r.top, docY: e.clientY - r.top + this.scrollY };
  }

  chevronHit(index, p) {
    const row = this.model.rows[index];
    if (!row?.hasChildren) return false;
    const x = CH.chevronX(row.depth) - 4;
    return p.x >= x && p.x <= x + 22;
  }

  installLeftEvents() {
    const L = this.left;
    L.addEventListener('wheel', (e) => {
      if (this.wheel(e)) return;
      e.preventDefault();
      this.scroller.scrollTop += e.deltaY * (e.deltaMode === 1 ? 40 : 1);
    }, { passive: false });
    L.addEventListener('mousemove', (e) => {
      if (e.buttons) return;
      const p = this.leftPoint(e);
      const i = this.rowIndexAtY(p.docY);
      this.setHover(i == null ? null : this.model.rows[i].id);
      L.style.cursor = i != null && this.chevronHit(i, p) ? 'pointer' : 'default';
      const tip = i == null ? null : rowToolTip(this.model.rows[i], this.model.today);
      if ((L.title || '') !== (tip || '')) L.title = tip || '';
    });
    L.addEventListener('mouseleave', () => this.setHover(null));
    L.addEventListener('mousedown', (e) => {
      if (e.button !== 0) return;
      e.preventDefault();
      this.scroller.focus({ preventScroll: true });
      const p = this.leftPoint(e);
      const i = this.rowIndexAtY(p.docY);
      if (i == null) { this.select(null); return; }
      const id = this.model.rows[i].id;
      if (this.chevronHit(i, p)) { this.cb.onToggle?.(id); return; }
      this.select(id);
      if (e.detail === 2) { this.cb.onOpen?.(id); return; }
      // Dragging a row moves the task up or down among its siblings (never to another level).
      const start = { x: e.clientX, y: e.clientY };
      const move = (ev) => {
        if (!this.reorder) {
          if (Math.hypot(ev.clientX - start.x, ev.clientY - start.y) <= 4) return;
          this.beginReorder(id);
          document.body.style.cursor = 'grabbing';
        }
        const r = L.getBoundingClientRect();
        if (ev.clientY < r.top + 16) this.scroller.scrollTop -= 10;
        else if (ev.clientY > r.bottom - 16) this.scroller.scrollTop += 10;
        this.updateReorder(this.leftPoint(ev).docY);
      };
      const up = () => {
        window.removeEventListener('mousemove', move, true);
        window.removeEventListener('mouseup', up, true);
        document.body.style.cursor = '';
        if (this.reorder) this.endReorder(true);
      };
      window.addEventListener('mousemove', move, true);
      window.addEventListener('mouseup', up, true);
    });
    L.addEventListener('contextmenu', (e) => {
      e.preventDefault();
      const i = this.rowIndexAtY(this.leftPoint(e).docY);
      if (i != null) this.rowMenu(i);
    });
  }

  installHeaderEvents() {
    this.header.addEventListener('wheel', (e) => { if (!this.wheel(e)) e.preventDefault(); }, { passive: false });
    this.header.addEventListener('contextmenu', (e) => {
      e.preventDefault();
      const r = this.header.getBoundingClientRect();
      const i = Math.floor((e.clientX - r.left + this.scrollX) / this.dayWidth);
      this.headerMenu(this.model.window.start + i === this.model.today);
    });
  }

  installHandle() {
    const h = this.handle;
    h.addEventListener('dblclick', () => this.setTaskListWidth(CH.defaultTaskListWidth, true));
    h.addEventListener('mousedown', (e) => {
      if (e.button !== 0 || e.detail > 1) return;
      e.preventDefault();
      const x0 = e.clientX, w0 = this.taskListWidth;
      document.body.classList.add('resizing');
      const move = (ev) => this.setTaskListWidth(w0 + ev.clientX - x0, false);
      const up = () => {
        window.removeEventListener('mousemove', move, true);
        window.removeEventListener('mouseup', up, true);
        document.body.classList.remove('resizing');
        this.setTaskListWidth(this.taskListWidth, true);
      };
      window.addEventListener('mousemove', move, true);
      window.addEventListener('mouseup', up, true);
    });
  }

  // ---------------------------------------------------------------- Drawing: corner
  drawCorner() {
    const w = this.taskListWidth, h = CH.headerHeight;
    const ctx = Draw.setup(this.corner, w, h);
    ctx.fillStyle = Theme.c('canvas');
    ctx.fillRect(0, 0, w, h);
    const x = CH.titleX(0);
    Draw.text(ctx, (this.model.archive ? 'Archive · ' : '') + Fmt.itemCount(this.model.taskCount), Theme.font(11), Theme.c('tertiaryText'), x, 7, w - x - 8, 14);
    Draw.text(ctx, 'Group / Task / Milestone', Theme.font(12), Theme.c('secondaryText'), x, h - 26, w - x - 8, 16);
  }

  // ---------------------------------------------------------------- Drawing: header
  drawHeader() {
    const W = Math.max(this.headerW || 0, 1), H = CH.headerHeight;
    const ctx = Draw.setup(this.header, W, H);
    const m = this.model, win = m.window, dw = this.dayWidth, ox = this.scrollX;
    const dark = Theme.dark;
    const hair = Draw.hair();
    ctx.fillStyle = Theme.c('canvas');
    ctx.fillRect(0, 0, W, H);
    const monthBottom = CH.monthRowHeight, top = CH.dayRowsTop;
    const days = win.end - win.start + 1;
    const first = Math.max(0, Math.floor(ox / dw));
    const last = Math.min(days - 1, Math.ceil((ox + W) / dw));
    this.debug = { monthLabels: [], weekLabels: [], weekdayLabels: [], todayColumn: null };
    if (first > last) return;
    const todayFill = TodayStyle.fill(m.todayHex, dark), todayAccent = TodayStyle.accent(m.todayHex, dark);

    // Column backgrounds in the weekday/date rows; the tint never reaches the month or week bars.
    for (let i = first; i <= last; i++) {
      const day = win.start + i, x = i * dw - ox;
      if (day === m.today) { ctx.fillStyle = todayFill; ctx.fillRect(x, top, dw, H - top); this.debug.todayColumn = { x, w: dw }; }
      else if (Day.isWeekend(day)) { ctx.fillStyle = Theme.c('weekend'); ctx.fillRect(x, top, dw, H - top); }
    }
    ctx.fillStyle = Theme.c('gridLine');
    for (let i = first; i <= last + 1; i++) ctx.fillRect(Draw.px(i * dw - ox), top + 6, hair, H - top - 6);
    ctx.fillRect(0, monthBottom, W, hair);
    ctx.fillRect(0, top, W, hair);

    // Month labels ("Nov 2026", sticky to the left edge) and month boundary lines.
    const monthFont = Theme.font(12);
    let ms = Day.firstOfMonth(win.start + first);
    while (ms <= win.start + last) {
      const next = Day.addMonths(ms, 1);
      const si = Math.max(ms - win.start, 0), ei = Math.min(next - win.start - 1, days - 1);
      const sx = si * dw - ox, ex = (ei + 1) * dw - ox;
      if (ms > win.start) { ctx.fillStyle = Theme.c('monthLine'); ctx.fillRect(Draw.px(sx), 0, hair, monthBottom); }
      const long = Fmt.monthYear(ms), short = Fmt.monthShort[Day.month(ms) - 1];
      const label = ex - Math.max(sx, 0) >= Draw.width(ctx, long, monthFont) + 16 ? long : short;
      const lw = Draw.width(ctx, label, monthFont);
      const lx = Math.min(Math.max(sx, 0) + 8, ex - lw - 8);
      if (lx + lw <= ex - 4 && ex - Math.max(sx, 0) > lw + 8) {
        Draw.text(ctx, label, monthFont, Theme.c('headerText'), lx, 5, lw + 2, 16);
        this.debug.monthLabels.push(label);
      }
      ms = next;
    }

    // Week bar: "Week 46" over each week's columns (sticky), with week boundary lines.
    const weekFont = Theme.font(11);
    let ws = Weeks.start(win.start + first, m.firstWeekday);
    while (ws <= win.start + last) {
      const si = Math.max(ws - win.start, 0), ei = Math.min(ws + 6 - win.start, days - 1);
      const sx = si * dw - ox, ex = (ei + 1) * dw - ox;
      if (ws > win.start) { ctx.fillStyle = Theme.c('monthLine'); ctx.fillRect(Draw.px(sx), monthBottom, hair, CH.weekRowHeight); }
      const n = Weeks.number(ws, m.firstWeekday);
      const room = ex - Math.max(sx, 0) - 12;
      const label = [`Week ${n}`, `W${n}`, `${n}`].find((t) => Draw.width(ctx, t, weekFont) <= room);
      if (label) {
        const lw = Draw.width(ctx, label, weekFont);
        const lx = Math.min(Math.max(sx, 0) + 6, ex - lw - 6);
        Draw.text(ctx, label, weekFont, Theme.c('secondaryText'), lx, monthBottom + 3, lw + 2, 14);
        this.debug.weekLabels.push({ label, first: Day.iso(Math.max(ws, win.start)), last: Day.iso(Math.min(ws + 6, win.end)) });
      }
      ws += 7;
    }

    // Weekday + day number; today is marked by color alone (weekday and date circle in the Today color).
    const circleText = Color.prefersLightText(m.todayHex) ? '#FFFFFF' : Theme.c('barDarkText');
    for (let i = first; i <= last; i++) {
      const day = win.start + i, x = i * dw - ox, isToday = day === m.today, wd = Day.weekday(day);
      const weekday = dw >= 42 ? Fmt.weekdayShort[wd] : Fmt.weekdayLetter[wd];
      Draw.text(ctx, weekday, Theme.font(10), isToday ? todayAccent : (Day.isWeekend(day) ? Theme.c('tertiaryText') : Theme.c('secondaryText')), x, top + 3, dw, 13, 'center');
      this.debug.weekdayLabels.push(weekday);
      const num = String(Day.dayOfMonth(day));
      if (isToday) {
        const d = 22, cx = x + dw / 2, cy = top + 15 + d / 2;
        ctx.fillStyle = todayAccent;
        ctx.beginPath(); ctx.arc(cx, cy, d / 2, 0, Math.PI * 2); ctx.fill();
        Draw.text(ctx, num, Theme.font(13), circleText, x, top + 15, dw, d, 'center');
      } else {
        Draw.text(ctx, num, Theme.font(13), Day.isWeekend(day) ? Theme.c('secondaryText') : Theme.c('text'), x, top + 19, dw, 16, 'center');
      }
    }
  }

  // ---------------------------------------------------------------- Drawing: task list
  drawLeft() {
    const w = this.taskListWidth, h = this.leftH || 1;
    const ctx = Draw.setup(this.left, w, h);
    ctx.fillStyle = Theme.c('canvas');
    ctx.fillRect(0, 0, w, h);
    const m = this.model, rh = CH.rowHeight, oy = this.scrollY, hair = Draw.hair();
    if (!m.rows.length) return;
    const first = Math.max(0, Math.floor(oy / rh)), last = Math.min(m.rows.length - 1, Math.floor((oy + h) / rh));
    for (let i = first; i <= last; i++) {
      const row = m.rows[i], y = i * rh - oy;
      if (row.id === m.selectedID) { ctx.fillStyle = Theme.c('selection'); ctx.fillRect(0, y, w, rh); }
      else if (row.id === this.hoveredRowID) { ctx.fillStyle = Theme.c('hover'); ctx.fillRect(0, y, w, rh); }

      // Disclosure chevron for parents: › collapsed, ⌄ expanded.
      if (row.hasChildren) {
        const cx = CH.chevronX(row.depth) + 7, cy = y + 13.5;
        ctx.beginPath();
        if (row.collapsed) { ctx.moveTo(cx - 2, cy - 4.5); ctx.lineTo(cx + 2.5, cy); ctx.lineTo(cx - 2, cy + 4.5); }
        else { ctx.moveTo(cx - 4.5, cy - 2); ctx.lineTo(cx, cy + 2.5); ctx.lineTo(cx + 4.5, cy - 2); }
        ctx.lineWidth = 1.6; ctx.lineCap = 'round'; ctx.lineJoin = 'round';
        ctx.strokeStyle = Theme.c('chevron');
        ctx.stroke();
      }
      // Kind marker in the item's color: dot (task), diamond (milestone), square (group).
      // A completed item's marker is a check in a circle.
      ctx.fillStyle = row.colorHex;
      const mx = CH.chevronX(row.depth) + 18 + 4.5, my = y + 9 + 4.5;
      if (row.completed) { ctx.beginPath(); ctx.arc(mx, my, 6, 0, Math.PI * 2); ctx.fill(); Draw.check(ctx, mx, my, 6.6, '#FFFFFF'); }
      else if (row.kind === 'milestone') { Draw.diamond(ctx, mx, my, 11); ctx.fill(); }
      else if (row.kind === 'group') { Draw.roundRect(ctx, mx - 5, my - 5, 10, 10, 2); ctx.fill(); }
      else { ctx.beginPath(); ctx.arc(mx, my, 4.5, 0, Math.PI * 2); ctx.fill(); }

      // Bold title, then the tags inline in bold gray. A note icon marks tasks with notes.
      const tx = CH.titleX(row.depth);
      const width = Math.max(w - tx - 10, 10);
      const titleWidth = row.notes ? Math.max(width - 20, 10) : width;
      if (row.notes) this.drawNoteIcon(ctx, w - 22, y + 6);
      const titleFont = Theme.font(13, true), tagFont = Theme.font(12, true);
      const titleW = Draw.width(ctx, row.title, titleFont);
      Draw.text(ctx, row.title, titleFont, row.completed ? Theme.c('secondaryText') : Theme.c('text'), tx, y + 5, titleWidth, 17);
      if (row.completed) { // struck through
        ctx.fillStyle = Theme.c('secondaryText');
        ctx.fillRect(tx, y + 13.5, Math.min(titleW, titleWidth), 1.2);
      }
      if (row.tags.length && titleW + 12 < titleWidth) {
        const tags = '  ' + row.tags.map((t) => `#${t}`).join(' ');
        Draw.text(ctx, tags, tagFont, Theme.c('tagText'), tx + titleW, y + 5, titleWidth - titleW, 17);
      }
      // Dates (regular). While dragging, the preview dates show in the accent color.
      const [s, e] = this.dates(row);
      let dateText;
      if (row.kind === 'milestone') dateText = Fmt.weekdayDate(s) + (Day.year(s) !== Day.year(m.today) ? `, ${Day.year(s)}` : '');
      else if (row.hasDates === false) dateText = 'Empty group';
      else dateText = `${Fmt.range(s, e, Day.year(m.today))} · ${Fmt.dayCount(e - s + 1)}`;
      if (row.detail) dateText += ' · ' + row.detail;
      if (row.completed) dateText = 'Completed · ' + dateText;
      if (row.marks?.length) {
        dateText += ` · ◆ ${row.marks[0].title} ${Fmt.short(this.markDay(row.marks[0]))}`;
        if (row.marks.length > 1) dateText += ` +${row.marks.length - 1}`;
      }
      const moving = this.drag && (this.drag.id === row.id || this.drag.shifted?.has(row.id));
      Draw.text(ctx, dateText, Theme.font(11), moving ? Theme.c('accent') : Theme.c('secondaryText'), tx, y + 22, width, 14);
      ctx.fillStyle = Theme.c('rowLine');
      ctx.fillRect(0, y + rh - hair, w, hair);
    }
    // The insertion line while a task is dragged to a new position.
    if (this.reorder && this.reorder.current != null) {
      const slot = this.reorder.slots[this.reorder.current];
      const y = slot.y - oy, x0 = CH.titleX(slot.depth) - 8;
      ctx.fillStyle = Theme.c('accent');
      ctx.fillRect(x0, y - 1, w - x0, 2);
      ctx.beginPath(); ctx.arc(x0 - 3, y, 3.5, 0, Math.PI * 2);
      ctx.lineWidth = 2; ctx.strokeStyle = Theme.c('accent'); ctx.stroke();
    }
  }

  /** A small page-with-lines icon. */
  drawNoteIcon(ctx, x, y) {
    ctx.strokeStyle = Theme.c('chevron');
    ctx.lineWidth = 1.1;
    Draw.roundRect(ctx, x + 0.5, y + 0.5, 11, 13, 2);
    ctx.stroke();
    ctx.fillStyle = Theme.c('chevron');
    for (let k = 0; k < 3; k++) ctx.fillRect(x + 3, y + 3.5 + k * 2.8, k === 2 ? 4 : 6, 1.1);
  }

  // ---------------------------------------------------------------- Drawing: timeline
  drawTimeline() {
    const W = this.viewW, H = this.viewH;
    if (!W || !H) return;
    const ctx = Draw.setup(this.timeline, W, H);
    const m = this.model, win = m.window, dw = this.dayWidth, rh = CH.rowHeight, dark = Theme.dark, hair = Draw.hair();
    const ox = this.scrollX, oy = this.scrollY;
    ctx.fillStyle = Theme.c('canvas');
    ctx.fillRect(0, 0, W, H);
    ctx.save();
    ctx.translate(-ox, -oy);
    const days = win.end - win.start + 1;
    const first = Math.max(0, Math.floor(ox / dw)), last = Math.min(days - 1, Math.floor((ox + W) / dw));
    const firstRow = Math.max(0, Math.floor(oy / rh)), lastRow = Math.min(m.rows.length - 1, Math.floor((oy + H) / rh));

    // Weekend shading and the full-height Today column.
    const todayFill = TodayStyle.fill(m.todayHex, dark);
    for (let i = first; i <= last; i++) {
      const day = win.start + i;
      if (day === m.today) { ctx.fillStyle = todayFill; ctx.fillRect(i * dw, oy, dw, H); }
      else if (Day.isWeekend(day)) { ctx.fillStyle = Theme.c('weekend'); ctx.fillRect(i * dw, oy, dw, H); }
    }
    // Selected / hovered row bands.
    for (let r = firstRow; r <= lastRow; r++) {
      const id = m.rows[r].id;
      if (id === m.selectedID) { ctx.fillStyle = Theme.c('selection'); ctx.fillRect(ox, r * rh, W, rh); }
      else if (id === this.hoveredRowID) { ctx.fillStyle = Theme.c('hover'); ctx.fillRect(ox, r * rh, W, rh); }
    }
    // Day grid lines (month boundaries slightly darker).
    for (let i = first; i <= last + 1; i++) {
      const day = win.start + i;
      ctx.fillStyle = Day.dayOfMonth(day) === 1 && i > 0 ? Theme.c('monthLine') : Theme.c('gridLine');
      ctx.fillRect(Draw.px(i * dw), oy, hair, H);
    }
    if (m.emptyMessage) {
      const f = Theme.font(13);
      const tw = Math.min(Draw.width(ctx, m.emptyMessage, f) + 4, W - 20);
      Draw.text(ctx, m.emptyMessage, f, Theme.c('secondaryText'), ox + W / 2 - tw / 2, oy + 80, tw, 18, 'center');
    }
    if (firstRow <= lastRow) {
      ctx.fillStyle = Theme.c('rowLine');
      for (let r = firstRow; r <= lastRow; r++) ctx.fillRect(ox, (r + 1) * rh - hair, W, hair);
      // Items (opaque, so the Today column never tints them) and off-window hints.
      for (let r = firstRow; r <= lastRow; r++) {
        const row = m.rows[r];
        const [s, e] = this.dates(row);
        const selected = row.id === m.selectedID, hovered = row.id === this.hoveredRowID;
        const dragging = !!this.drag && (this.drag.id === row.id || !!this.drag.shifted?.has(row.id));
        let drawn = false;
        if (row.kind === 'milestone') {
          if (s >= win.start && s <= win.end) { this.drawMilestone(ctx, row, this.milestoneCenter(r, row), selected, dragging, hovered); drawn = true; }
        } else if (row.kind === 'group') {
          if (row.hasDates === false) drawn = true;
          else { const bar = this.barRect(r, s, e); if (bar) { this.drawGroupBar(ctx, row, bar, r, selected, dragging, hovered); drawn = true; } }
        } else {
          const bar = this.barRect(r, s, e);
          if (bar) { this.drawBar(ctx, row, bar, selected, dragging, hovered); drawn = true; }
        }
        if (!drawn) {
          const h = this.hintRect(r, row);
          if (h) {
            ctx.fillStyle = Theme.c('chipFill');
            Draw.roundRect(ctx, h.x, h.y, h.w, h.h, 10); ctx.fill();
            Draw.text(ctx, h.text, Theme.font(11), Theme.c('secondaryText'), h.x + 8, h.y + 3, h.w - 12, 14);
          }
        }
        for (const mk of row.marks || []) {
          const day = this.markDay(mk);
          if (day >= win.start && day <= win.end) this.drawMark(ctx, mk, this.markCenter(r, mk), row.colorHex, mk.id === m.selectedID, this.drag?.id === mk.id);
        }
      }
    }
    this.drawLinks(ctx);
    this.drawNowLine(ctx);
    if (this.hoverItem && !this.drag) this.drawHandles(ctx, this.hoverItem);
    if (this.linkDraft) this.drawLinkDraft(ctx, this.linkDraft);
    if (this.drag) {
      const r = m.rows.findIndex((x) => x.id === this.drag.id || (x.marks || []).some((k) => k.id === this.drag.id));
      if (r >= 0) this.drawDragBubble(ctx, r);
    }
    if (this.reorder && this.reorder.current != null) {
      ctx.fillStyle = Theme.c('accent');
      ctx.fillRect(ox, this.reorder.slots[this.reorder.current].y - 1, W, 2);
    }
    ctx.restore();
  }

  drawBar(ctx, row, r, selected, dragging, hovered) {
    const base = Color.parse(row.colorHex) ? row.colorHex : '#808080';
    const done = row.completed ? Draw.completedColors(base) : null;
    const fill = done ? done.fill : base;
    const light = done ? Color.prefersLightText(done.fill) : Color.prefersLightText(fill);
    const textColor = done ? done.text : light ? '#FFFFFF' : '#1D1D1F';
    ctx.save();
    if (dragging || hovered) {
      ctx.shadowColor = `rgba(0,0,0,${dragging ? 0.28 : 0.16})`;
      ctx.shadowBlur = dragging ? 6 : 3;
      ctx.shadowOffsetY = dragging ? 2 : 1;
    }
    ctx.fillStyle = fill;
    Draw.roundRect(ctx, r.x, r.y, r.w, r.h, 6, !r.clippedLeft, !r.clippedRight);
    ctx.fill();
    ctx.restore();
    if (selected) {
      const dark = Theme.dark;
      ctx.strokeStyle = Color.mix(fill, dark ? '#FFFFFF' : '#000000', dark ? 0.45 : 0.35);
      ctx.lineWidth = 1.5;
      Draw.roundRect(ctx, r.x - 2, r.y - 2, r.w + 4, r.h + 4, 8, !r.clippedLeft, !r.clippedRight);
      ctx.stroke();
    }
    let minX = r.x + 8, maxX = r.x + r.w - 8;
    const chevColor = light ? 'rgba(255,255,255,0.85)' : 'rgba(29,29,31,0.85)';
    if (r.clippedLeft) { Draw.chevron(ctx, r.x + 7, r.y + r.h / 2, true, chevColor); minX = r.x + 15; }
    if (r.clippedRight) { Draw.chevron(ctx, r.x + r.w - 7, r.y + r.h / 2, false, chevColor); maxX = r.x + r.w - 15; }
    // Bold title inside the bar, or just to its right when the bar is too short.
    const font = Theme.font(12, true);
    const title = row.completed ? '✓ ' + row.title : row.title;
    const titleW = Draw.width(ctx, title, font);
    const available = maxX - minX, outsideRoom = this.docWidth - (r.x + r.w) - 12;
    if (available < Math.min(titleW, 64) && !r.clippedRight && outsideRoom > 40) {
      Draw.text(ctx, title, font, row.completed ? Theme.c('secondaryText') : Theme.c('text'), r.x + r.w + 6, r.y + 4, Math.min(titleW + 1, outsideRoom), 16);
    } else if (available > 12) {
      Draw.text(ctx, title, font, textColor, minX, r.y + 4, available, 16);
    }
  }

  /** A group: a slim bar spanning everything inside it, with tabs pointing down at both ends. */
  drawGroupBar(ctx, row, r, index, selected, dragging, hovered) {
    const dark = Theme.dark;
    const base = Color.parse(row.colorHex) ? row.colorHex : '#808080';
    const done = row.completed ? Draw.completedColors(base) : null;
    const fill = done ? done.fill : Color.mix(base, dark ? '#FFFFFF' : '#000000', dark ? 0.08 : 0.12);
    const top = index * CH.rowHeight + CH.groupBarTop, h = CH.groupBarHeight, tab = 7;
    const x0 = r.x, x1 = r.x + r.w;
    ctx.save();
    if (dragging || hovered) { ctx.shadowColor = `rgba(0,0,0,${dragging ? 0.28 : 0.16})`; ctx.shadowBlur = dragging ? 6 : 3; ctx.shadowOffsetY = dragging ? 2 : 1; }
    ctx.beginPath();
    ctx.moveTo(x0, top + 3);
    ctx.arcTo(x0, top, x0 + 3, top, 3);
    ctx.lineTo(x1 - 3, top);
    ctx.arcTo(x1, top, x1, top + 3, 3);
    if (r.clippedRight) ctx.lineTo(x1, top + h); else { ctx.lineTo(x1, top + h + tab); ctx.lineTo(x1 - tab, top + h); }
    if (r.clippedLeft) ctx.lineTo(x0, top + h); else { ctx.lineTo(x0 + tab, top + h); ctx.lineTo(x0, top + h + tab); }
    ctx.closePath();
    ctx.fillStyle = fill;
    ctx.fill();
    ctx.restore();
    if (selected) {
      ctx.strokeStyle = Color.mix(base, dark ? '#FFFFFF' : '#000000', dark ? 0.5 : 0.4);
      ctx.lineWidth = 1.5;
      Draw.roundRect(ctx, x0 - 2.5, top - 2.5, r.w + 5, h + 5, 5);
      ctx.stroke();
    }
    const textColor = done ? done.text : Color.prefersLightText(base) ? '#FFFFFF' : '#1D1D1F';
    const font = Theme.font(11, true);
    const title = row.completed ? '✓ ' + row.title : row.title;
    const titleW = Draw.width(ctx, title, font);
    const inner = r.w - 2 * (tab + 3), outsideRoom = this.docWidth - x1 - 12;
    if (inner >= Math.min(titleW, 60)) Draw.text(ctx, title, font, textColor, x0 + tab + 3, top + 0.5, inner, 14);
    else if (!r.clippedRight && outsideRoom > 40) Draw.text(ctx, title, font, row.completed ? Theme.c('secondaryText') : Theme.c('text'), x1 + 8, top + 0.5, Math.min(titleW + 1, outsideRoom), 14);
  }

  /** A milestone with its own row: a diamond at its date (and time), its title beside it. */
  drawMilestone(ctx, row, c, selected, dragging, hovered) {
    const fill = Color.parse(row.colorHex) ? row.colorHex : '#808080', size = CH.milestoneSize;
    ctx.save();
    if (dragging || hovered) { ctx.shadowColor = `rgba(0,0,0,${dragging ? 0.28 : 0.16})`; ctx.shadowBlur = dragging ? 6 : 3; ctx.shadowOffsetY = dragging ? 2 : 1; }
    ctx.fillStyle = row.completed ? Draw.completedColors(fill).fill : fill;
    Draw.diamond(ctx, c.x, c.y, size); ctx.fill();
    ctx.restore();
    if (row.completed) Draw.check(ctx, c.x, c.y, 7, Draw.completedColors(fill).text);
    if (selected) {
      ctx.strokeStyle = Color.mix(fill, Theme.dark ? '#FFFFFF' : '#000000', Theme.dark ? 0.45 : 0.35);
      ctx.lineWidth = 1.5;
      Draw.diamond(ctx, c.x, c.y, size + 7); ctx.stroke();
    }
    const font = Theme.font(12, true), room = this.docWidth - c.x - size;
    const title = row.completed ? '✓ ' + row.title : row.title;
    if (room > 30) Draw.text(ctx, title, font, row.completed ? Theme.c('secondaryText') : Theme.c('text'), c.x + size / 2 + 6, c.y - 8, Math.min(Draw.width(ctx, title, font) + 1, room), 16);
  }

  /** A milestone on its task's bar: a small diamond with a light outline. */
  drawMark(ctx, mark, c, barHex, selected, dragging) {
    let fill = Color.parse(mark.colorHex) ? mark.colorHex : '#808080';
    if (fill.toUpperCase() === String(barHex).toUpperCase()) fill = Color.mix(fill, '#000000', 0.35);
    const size = CH.markSize;
    ctx.fillStyle = Theme.c('canvas');
    Draw.diamond(ctx, c.x, c.y, size + 4); ctx.fill();
    ctx.save();
    if (dragging) { ctx.shadowColor = 'rgba(0,0,0,0.3)'; ctx.shadowBlur = 5; ctx.shadowOffsetY = 2; }
    ctx.fillStyle = mark.completed ? Draw.completedColors(fill).fill : fill;
    Draw.diamond(ctx, c.x, c.y, size); ctx.fill();
    ctx.restore();
    if (mark.completed) Draw.check(ctx, c.x, c.y, 5.5, Draw.completedColors(fill).text);
    if (selected) { ctx.strokeStyle = Theme.c('accent'); ctx.lineWidth = 1.5; Draw.diamond(ctx, c.x, c.y, size + 9); ctx.stroke(); }
  }

  /** Dependency arrows: thin right-angled lines with an arrowhead at the successor. */
  drawLinks(ctx) {
    for (const l of this.model.links || []) {
      const pts = this.linkPoints(l);
      if (!pts || pts.length < 2) continue;
      const selected = l.id === this.model.selectedLinkID, hovered = l.id === this.hoveredLinkID;
      const color = l.colorHex || Theme.c('linkLine');
      const w = Math.max(0.25, l.width || 1.25);
      ctx.lineCap = 'round'; ctx.lineJoin = 'round';
      if (selected || hovered) {
        Draw.polyline(ctx, pts, 5);
        ctx.lineWidth = w + (selected ? 5 : 3.5);
        ctx.strokeStyle = Theme.dark ? `rgba(76,141,255,${selected ? 0.45 : 0.18})` : `rgba(47,111,235,${selected ? 0.3 : 0.16})`;
        ctx.stroke();
      }
      const tip = pts[pts.length - 1], prev = pts[pts.length - 2];
      const len = Math.hypot(tip.x - prev.x, tip.y - prev.y) || 1, back = Math.min(len, 4 + w);
      const base = { x: tip.x - ((tip.x - prev.x) / len) * back, y: tip.y - ((tip.y - prev.y) / len) * back };
      Draw.polyline(ctx, [...pts.slice(0, -1), base], 5);
      ctx.lineCap = 'butt';
      ctx.lineWidth = w;
      ctx.strokeStyle = color;
      ctx.stroke();
      ctx.fillStyle = color;
      Draw.arrowhead(ctx, tip, prev, w);
    }
  }

  /** Small round handles just outside the hovered item: drag one to another item to add an arrow. */
  drawHandles(ctx, h) {
    for (const hd of this.handles(h)) {
      const c = hd.center, S = LINK_SIDES[hd.side];
      // along = away from the item, across = sideways.
      const at = (along, across) => [c.x + along * S.dx - across * S.dy, c.y + along * S.dy + across * S.dx];
      ctx.fillStyle = Theme.c('canvas');
      ctx.beginPath(); ctx.arc(c.x, c.y, 7.5, 0, Math.PI * 2); ctx.fill();
      ctx.fillStyle = Theme.c('accent');
      ctx.beginPath(); ctx.arc(c.x, c.y, 6, 0, Math.PI * 2); ctx.fill();
      ctx.strokeStyle = '#FFFFFF'; ctx.lineWidth = 1.4; ctx.lineCap = 'round'; ctx.lineJoin = 'round';
      ctx.beginPath();
      ctx.moveTo(...at(-2.8, 0)); ctx.lineTo(...at(2.6, 0));
      ctx.moveTo(...at(0.2, -2.6)); ctx.lineTo(...at(2.8, 0)); ctx.lineTo(...at(0.2, 2.6));
      ctx.stroke();
    }
  }

  /** The arrow being drawn: dashed from the handle to the pointer, and the route it will take once it's
   * over an item it can join. */
  drawLinkDraft(ctx, d) {
    const accent = Theme.c('accent');
    ctx.strokeStyle = accent; ctx.fillStyle = accent; ctx.lineWidth = 1.5;
    const ra = this.itemFrame(d.fromID), rb = d.target && this.itemFrame(d.target.id);
    if (ra && rb) {
      const pts = this.bestRoute(ra, d.fromSide, rb, d.target.side);
      const tip = pts[pts.length - 1], prev = pts[pts.length - 2];
      const len = Math.hypot(tip.x - prev.x, tip.y - prev.y) || 1, back = Math.min(len, 5.5);
      Draw.polyline(ctx, [...pts.slice(0, -1), { x: tip.x - ((tip.x - prev.x) / len) * back, y: tip.y - ((tip.y - prev.y) / len) * back }], 5);
      ctx.lineCap = 'butt'; ctx.lineJoin = 'round';
      ctx.stroke();
      Draw.arrowhead(ctx, tip, prev, 1.5);
    } else {
      ctx.setLineDash([4, 3]);
      ctx.beginPath(); ctx.moveTo(d.origin.x, d.origin.y); ctx.lineTo(d.current.x, d.current.y); ctx.stroke();
      ctx.setLineDash([]);
      Draw.arrowhead(ctx, d.current, d.origin, 1.5);
    }
    if (!d.target) return;
    const i = this.rowIndexOf(this.model.anchorRow[d.target.id]);
    if (i < 0) return;
    const row = this.model.rows[i];
    const mark = (row.marks || []).find((k) => k.id === d.target.id);
    ctx.lineWidth = 2; ctx.strokeStyle = accent;
    if (mark) { const c = this.markCenter(i, mark); Draw.diamond(ctx, c.x, c.y, CH.markSize + 9); ctx.stroke(); }
    else if (row.kind === 'milestone') { const c = this.milestoneCenter(i, row); Draw.diamond(ctx, c.x, c.y, CH.milestoneSize + 8); ctx.stroke(); }
    else { const r = this.fullBarRect(i, row); Draw.roundRect(ctx, r.x - 3, r.y - 3, r.w + 6, r.h + 6, 7); ctx.stroke(); }
    const label = `${LINK_TYPES[linkTypeForSides(d.fromSide, d.target.side)].title} · into its ${LINK_SIDES[d.target.side].word}`;
    const font = Theme.font(11), w = Draw.width(ctx, label, font) + 16;
    const bx = d.target.point.x - w / 2, by = d.target.point.y - 36;
    ctx.fillStyle = Theme.c('bubbleFill');
    Draw.roundRect(ctx, bx, by, w, 20, 6); ctx.fill();
    Draw.text(ctx, label, font, Theme.c('bubbleText'), bx + 8, by + 3, w - 16, 14);
  }

  /** A thin line at the current time in the Today column. */
  drawNowLine(ctx) {
    const m = this.model;
    if (m.nowMinute == null || m.today < m.window.start || m.today > m.window.end) return;
    const x = this.milestoneX(m.today, m.nowMinute);
    const accent = TodayStyle.accent(m.todayHex, Theme.dark);
    ctx.fillStyle = accent;
    ctx.fillRect(x - 0.75, this.scrollY, 1.5, this.viewH);
  }

  drawDragBubble(ctx, rowIndex) {
    const d = this.drag;
    const row = this.model.rows[rowIndex];
    let bar;
    const mark = (row.marks || []).find((k) => k.id === d.id);
    if (mark) { const c = this.markCenter(rowIndex, mark); bar = { x: c.x - 8, y: c.y - 8, w: 16, h: 16 }; }
    else if (row.kind === 'milestone') { const c = this.milestoneCenter(rowIndex, row); bar = { x: c.x - 10, y: c.y - 10, w: 20, h: 20 }; }
    else bar = this.barRect(rowIndex, d.start, d.end);
    if (!bar) return;
    const single = d.start === d.end && (row.kind === 'milestone' || !!mark);
    const text = single ? Fmt.weekdayDate(d.start) : `${Fmt.range(d.start, d.end, Day.year(this.model.today))} · ${Fmt.dayCount(d.end - d.start + 1)}`;
    const font = Theme.font(11);
    const w = Draw.width(ctx, text, font) + 16, h = 20;
    let x = bar.x + bar.w / 2 - w / 2;
    x = Math.max(this.scrollX + 4, Math.min(x, this.scrollX + this.viewW - w - 4));
    let y = bar.y - h - 4;
    if (y < this.scrollY + 2) y = bar.y + bar.h + 4;
    ctx.fillStyle = Theme.c('bubbleFill');
    Draw.roundRect(ctx, x, y, w, h, 6); ctx.fill();
    Draw.text(ctx, text, font, Theme.c('bubbleText'), x + 8, y + 3, w - 16, 14);
  }

  // ---------------------------------------------------------------- Points for the self-check
  /** Window (client) coordinates of a row's bar, task list row and chevron. */
  /** Window (client) coordinates of a document point. */
  clientPoint(p) {
    const sr = this.scroller.getBoundingClientRect();
    return { x: sr.left + p.x - this.scrollX, y: sr.top + p.y - this.scrollY };
  }
  /** For the self-check: a point on an item (away from milestone diamonds), and its anchors. */
  itemPoint(id) {
    const rowID = this.model.anchorRow?.[id];
    const i = rowID ? this.rowIndexOf(rowID) : -1;
    if (i < 0) return null;
    const row = this.model.rows[i];
    let p;
    const mark = id !== rowID ? (row.marks || []).find((m) => m.id === id) : null;
    if (mark) p = this.markCenter(i, mark);
    else if (row.kind === 'milestone') p = this.milestoneCenter(i, row);
    else {
      const r = this.fullBarRect(i, row);
      const marks = (row.marks || []).map((m) => this.markCenter(i, m).x);
      let x = r.x + r.w / 2;
      for (let cx = r.x + 10; cx <= r.x + r.w - 10; cx += 3) if (marks.every((mx) => Math.abs(mx - cx) > 16)) { x = cx; break; }
      p = { x, y: r.y + r.h / 2 };
    }
    const side = (k) => this.anchor(id, k) && this.clientPoint(this.anchor(id, k));
    return { item: this.clientPoint(p), start: side('left'), end: side('right'), left: side('left'), right: side('right'),
      top: side('top'), bottom: side('bottom') };
  }
  pointsFor(id) {
    const i = this.model.rows.findIndex((r) => r.id === id);
    if (i < 0) return null;
    const row = this.model.rows[i];
    const sr = this.scroller.getBoundingClientRect(), lr = this.left.getBoundingClientRect();
    const bar = this.barRect(i, row.start, row.end);
    const y = i * CH.rowHeight - this.scrollY;
    return {
      index: i,
      bar: bar && { x: sr.left + bar.x - this.scrollX, y: sr.top + bar.y - this.scrollY, w: bar.w, h: bar.h },
      row: { x: lr.left + CH.titleX(row.depth) + 20, y: lr.top + y + CH.rowHeight / 2 },
      chevron: row.hasChildren ? { x: lr.left + CH.chevronX(row.depth) + 7, y: lr.top + y + 13.5 } : null,
      rowTop: lr.top + y,
    };
  }
  dayCenterX(day) {
    const sr = this.scroller.getBoundingClientRect();
    return sr.left + (day - this.model.window.start + 0.5) * this.dayWidth - this.scrollX;
  }
}
