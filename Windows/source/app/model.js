'use strict';
// Data model of the Windows edition (DaySpindle 2.1). Reads and writes the same file format as the Mac app:
// days are "yyyy-MM-dd", ids are upper-case UUID strings, optional fields are left out when empty.

// ---------------------------------------------------------------- Days
// A day is an integer: days since 1970-01-01 in the proleptic Gregorian calendar,
// so day arithmetic never depends on time zones or daylight saving time.
const Day = {
  fromCivil(y, m, d) { // Howard Hinnant's algorithm
    y = m <= 2 ? y - 1 : y;
    const era = Math.floor((y >= 0 ? y : y - 399) / 400);
    const yoe = y - era * 400;
    const mp = m > 2 ? m - 3 : m + 9;
    const doy = Math.floor((153 * mp + 2) / 5) + d - 1;
    const doe = yoe * 365 + Math.floor(yoe / 4) - Math.floor(yoe / 100) + doy;
    return era * 146097 + doe - 719468;
  },
  toCivil(n) {
    const z = n + 719468;
    const era = Math.floor((z >= 0 ? z : z - 146096) / 146097);
    const doe = z - era * 146097;
    const yoe = Math.floor((doe - Math.floor(doe / 1460) + Math.floor(doe / 36524) - Math.floor(doe / 146096)) / 365);
    const doy = doe - (365 * yoe + Math.floor(yoe / 4) - Math.floor(yoe / 100));
    const mp = Math.floor((5 * doy + 2) / 153);
    const d = doy - Math.floor((153 * mp + 2) / 5) + 1;
    const m = mp < 10 ? mp + 3 : mp - 9;
    return { y: yoe + era * 400 + (m <= 2 ? 1 : 0), m, d };
  },
  daysInMonth(y, m) {
    if ([1, 3, 5, 7, 8, 10, 12].includes(m)) return 31;
    if ([4, 6, 9, 11].includes(m)) return 30;
    return (y % 4 === 0 && y % 100 !== 0) || y % 400 === 0 ? 29 : 28;
  },
  iso(n) {
    const c = Day.toCivil(n);
    return `${String(c.y).padStart(4, '0')}-${String(c.m).padStart(2, '0')}-${String(c.d).padStart(2, '0')}`;
  },
  parse(s) {
    if (typeof s !== 'string') return null;
    const m = /^(\d{4})-(\d{1,2})-(\d{1,2})$/.exec(s.trim());
    if (!m) return null;
    const y = +m[1], mo = +m[2], d = +m[3];
    if (mo < 1 || mo > 12 || d < 1 || d > Day.daysInMonth(y, mo)) return null;
    return Day.fromCivil(y, mo, d);
  },
  /** The local calendar day of a Date, in this computer's time zone. */
  fromDate(date) { return Day.fromCivil(date.getFullYear(), date.getMonth() + 1, date.getDate()); },
  weekday(n) { const w = (n + 4) % 7; return w < 0 ? w + 7 : w; }, // 0 = Sunday (1970-01-01 was a Thursday)
  isWeekend(n) { const w = Day.weekday(n); return w === 0 || w === 6; },
  year(n) { return Day.toCivil(n).y; },
  month(n) { return Day.toCivil(n).m; },
  dayOfMonth(n) { return Day.toCivil(n).d; },
  firstOfMonth(n) { const c = Day.toCivil(n); return Day.fromCivil(c.y, c.m, 1); },
  /** Adds calendar months, clamping the day to the target month's length. */
  addMonths(n, k) {
    const c = Day.toCivil(n);
    let total = c.y * 12 + (c.m - 1) + k;
    if (total < 0) total = 0;
    const y = Math.floor(total / 12), m = (total % 12) + 1;
    return Day.fromCivil(y, m, Math.min(c.d, Day.daysInMonth(y, m)));
  },
};

// ---------------------------------------------------------------- English formatting
const Fmt = {
  monthShort: ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'],
  monthLong: ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'],
  weekdayShort: ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'],
  weekdayLong: ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'],
  weekdayLetter: ['S', 'M', 'T', 'W', 'T', 'F', 'S'],
  /** "Nov 9" */
  short(n) { const c = Day.toCivil(n); return `${Fmt.monthShort[c.m - 1]} ${c.d}`; },
  /** "Nov 9, 2026" */
  medium(n) { const c = Day.toCivil(n); return `${Fmt.monthShort[c.m - 1]} ${c.d}, ${c.y}`; },
  /** "Nov 2026" (month names are always three letters). */
  monthYear(n) { const c = Day.toCivil(n); return `${Fmt.monthShort[c.m - 1]} ${c.y}`; },
  /** "Mon, Nov 9" */
  weekdayDate(n) { return `${Fmt.weekdayShort[Day.weekday(n)]}, ${Fmt.short(n)}`; },
  /** "Nov 9 – Nov 12", "Nov 9", or with years when the range is not within `refYear`. */
  range(s, e, refYear) {
    const showYear = Day.year(s) !== Day.year(e) || (refYear != null && Day.year(s) !== refYear);
    const f = showYear ? Fmt.medium : Fmt.short;
    return s === e ? f(s) : `${f(s)} – ${f(e)}`;
  },
  dayCount(k) { return k === 1 ? '1 day' : `${k} days`; },
  taskCount(k) { return k === 1 ? '1 task' : `${k} tasks`; },
  itemCount(k) { return k === 1 ? '1 item' : `${k} items`; },
};

// ---------------------------------------------------------------- Times of day
const TimeOfDay = {
  // Without a start time a task starts at 00:00 on its first day; without an end time it
  // ends at 24:00 on its last day.
  defaultStart: '00:00',
  defaultEnd: '24:00',

  /** Reads "9", "0930", "9:30", "9.30", "21:05", "9pm", "9:30 am" … as "HH:mm" (24-hour).
   * "24:00" (end of the day) is accepted only when `allowEndOfDay` is set. Returns null otherwise. */
  normalize(text, allowEndOfDay = false) {
    const compact = String(text ?? '').replace(/\s+/g, '');
    if (allowEndOfDay && ['24', '24:00', '2400', '24.00'].includes(compact)) return TimeOfDay.defaultEnd;
    let s = compact.toLowerCase();
    let pm = false, am = false;
    if (s.endsWith('pm') || s.endsWith('p')) { pm = true; s = s.slice(0, s.endsWith('pm') ? -2 : -1); }
    else if (s.endsWith('am') || s.endsWith('a')) { am = true; s = s.slice(0, s.endsWith('am') ? -2 : -1); }
    s = s.replace(/\./g, ':');
    let h = null, m = null;
    if (s.includes(':')) {
      const parts = s.split(':');
      if (parts.length !== 2 || parts[0].length < 1 || parts[0].length > 2 || parts[1].length !== 2) return null;
      if (!/^\d+$/.test(parts[0]) || !/^\d+$/.test(parts[1])) return null;
      h = +parts[0]; m = +parts[1];
    } else if (/^\d+$/.test(s)) {
      if (s.length <= 2) { h = +s; m = 0; }
      else if (s.length <= 4) { h = +s.slice(0, s.length - 2); m = +s.slice(-2); }
      else return null;
    }
    if (h == null || m == null || m < 0 || m > 59) return null;
    if (pm || am) {
      if (h < 1 || h > 12) return null;
      if (pm && h < 12) h += 12;
      if (am && h === 12) h = 0;
    }
    if (h < 0 || h > 23) return null;
    return `${String(h).padStart(2, '0')}:${String(m).padStart(2, '0')}`;
  },
  /** "09:30–17:00"; with one time set, the other is its default. Null when neither is set. */
  range(start, end) {
    if (!start && !end) return null;
    return `${start || TimeOfDay.defaultStart}–${end || TimeOfDay.defaultEnd}`;
  },
  /** "09:30" → 570; "24:00" → 1440. */
  minutes(hhmm) {
    const m = /^(\d{1,2}):(\d{2})$/.exec(String(hhmm || ''));
    if (!m) return null;
    const h = +m[1], mi = +m[2];
    return h <= 24 && mi <= 59 ? h * 60 + mi : null;
  },
  /** 570 → "09:30"; 1440 → "24:00". */
  text(minutes) { return `${String(Math.floor(minutes / 60)).padStart(2, '0')}:${String(minutes % 60).padStart(2, '0')}`; },
};

// ---------------------------------------------------------------- Time zones
// Like Apple Calendar: an item with a time keeps its moment in time and is shown in the time zone
// being viewed (normally this computer's, so 10:00 entered in Tokyo shows as 02:00 in Berlin);
// an item without any time keeps its dates in every time zone. Zones are IANA names ("Asia/Tokyo"),
// the same as on the Mac.
const Zones = {
  formatters: new Map(),
  fmt(zone) {
    let f = Zones.formatters.get(zone);
    if (!f) {
      f = new Intl.DateTimeFormat('en-US', { timeZone: zone, hourCycle: 'h23', year: 'numeric', month: 'numeric',
        day: 'numeric', hour: 'numeric', minute: 'numeric', second: 'numeric' });
      Zones.formatters.set(zone, f);
    }
    return f;
  },
  valid(zone) {
    if (!zone || typeof zone !== 'string') return false;
    try { Zones.fmt(zone); return true; } catch { return false; }
  },
  /** This computer's time zone. */
  system() { return Intl.DateTimeFormat().resolvedOptions().timeZone || 'UTC'; },
  all() { try { return Intl.supportedValuesOf('timeZone'); } catch { return [Zones.system(), 'UTC']; } },
  /** Wall-clock parts of a moment (ms) in a zone. */
  parts(zone, ms) {
    const o = {};
    for (const p of Zones.fmt(zone).formatToParts(new Date(ms))) if (p.type !== 'literal') o[p.type] = +p.value;
    if (o.hour === 24) o.hour = 0;
    return o;
  },
  /** Minutes the zone is ahead of UTC at a moment. */
  offset(zone, ms) {
    const p = Zones.parts(zone, ms);
    const asUTC = Date.UTC(p.year, p.month - 1, p.day, p.hour, p.minute, p.second);
    return Math.round((asUTC - Math.floor(ms / 1000) * 1000) / 60000);
  },
  /** The moment (ms) of a wall-clock day and minute in a zone. */
  moment(zone, day, minutes) {
    const c = Day.toCivil(day);
    const guess = Date.UTC(c.y, c.m - 1, c.d) + minutes * 60000;
    let ms = guess - Zones.offset(zone, guess) * 60000;
    ms = guess - Zones.offset(zone, ms) * 60000;
    return ms;
  },
  /** The same moment as a day and minutes after midnight in another zone. */
  convert(day, minutes, from, to) {
    if (from === to) return { day, minutes };
    const p = Zones.parts(to, Zones.moment(from, day, minutes));
    return { day: Day.fromCivil(p.year, p.month, p.day), minutes: p.hour * 60 + p.minute };
  },
  /** The day and minutes now in a zone. */
  now(zone, ms) {
    const p = Zones.parts(zone, ms);
    return { day: Day.fromCivil(p.year, p.month, p.day), minutes: p.hour * 60 + p.minute };
  },
  /** "GMT+9", "GMT-3:30", "GMT". */
  offsetText(zone, ms = Date.now()) {
    const m = Zones.offset(zone, ms);
    if (m === 0) return 'GMT';
    const a = Math.abs(m);
    return `GMT${m < 0 ? '-' : '+'}${Math.floor(a / 60)}${a % 60 ? ':' + String(a % 60).padStart(2, '0') : ''}`;
  },
  /** "Tokyo" for "Asia/Tokyo". */
  city(zone) {
    const parts = zone.split('/');
    return (parts.length > 1 ? parts.slice(1).join('/') : zone).replace(/_/g, ' ');
  },
  /** "Asia/Tokyo (GMT+9)". */
  label(zone) { return `${zone.replace(/_/g, ' ')} (${Zones.offsetText(zone)})`; },
};

// ---------------------------------------------------------------- Week numbers
// Sunday or Saturday first: week 1 is the week that contains January 1 (US style).
// Monday first: ISO 8601, where week 1 is the week that contains January 4.
const Weeks = {
  /** firstWeekday: 0 = Sunday … 6 = Saturday. */
  start(d, firstWeekday) { return d - ((Day.weekday(d) - firstWeekday + 7) % 7); },
  minimumDaysInFirstWeek(firstWeekday) { return firstWeekday === 1 ? 4 : 1; },
  number(d, firstWeekday) {
    const ws = Weeks.start(d, firstWeekday);
    const m = Weeks.minimumDaysInFirstWeek(firstWeekday);
    const year = Day.year(ws + (7 - m));
    const week1 = Weeks.start(Day.fromCivil(year, 1, m), firstWeekday);
    return Math.floor((ws - week1) / 7) + 1;
  },
};

// ---------------------------------------------------------------- Colors
const Color = {
  parse(hex) {
    let s = String(hex || '').trim();
    if (s.startsWith('#')) s = s.slice(1);
    if (!/^[0-9a-fA-F]{6}$/.test(s)) return null;
    const v = parseInt(s, 16);
    return { r: ((v >> 16) & 255) / 255, g: ((v >> 8) & 255) / 255, b: (v & 255) / 255 };
  },
  hex(c) {
    const f = (x) => Math.round(Math.min(Math.max(x, 0), 1) * 255).toString(16).padStart(2, '0').toUpperCase();
    return `#${f(c.r)}${f(c.g)}${f(c.b)}`;
  },
  /** Accepts "#2F6FEB", "2f6feb", "#2F6" or "2F6" (spaces ignored) and returns "#2F6FEB", or null. */
  normalizedHex(text) {
    let s = String(text ?? '').replace(/\s+/g, '').toUpperCase();
    if (s.startsWith('#')) s = s.slice(1);
    if (!/^[0-9A-F]*$/.test(s)) return null;
    if (s.length === 3) s = s.split('').map((c) => c + c).join('');
    if (s.length !== 6) return null;
    return '#' + s;
  },
  luminance(c) {
    const lin = (x) => (x <= 0.03928 ? x / 12.92 : Math.pow((x + 0.055) / 1.055, 2.4));
    return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b);
  },
  /** White text unless the fill is light enough that dark text reads better. */
  prefersLightText(hex) {
    const c = Color.parse(hex) || { r: 0.5, g: 0.5, b: 0.5 };
    return 1.05 / (Color.luminance(c) + 0.05) >= 2.4;
  },
  mix(hex, otherHex, t) {
    const a = Color.parse(hex), b = Color.parse(otherHex);
    if (!a || !b) return hex;
    return Color.hex({ r: a.r + (b.r - a.r) * t, g: a.g + (b.g - a.g) * t, b: a.b + (b.b - a.b) * t });
  },
};

const PALETTE = [
  ['Red', '#E5484D'], ['Orange', '#F2811D'], ['Yellow', '#F5C518'], ['Green', '#30A46C'],
  ['Mint', '#12A594'], ['Teal', '#0E9FC2'], ['Blue', '#2F6FEB'], ['Indigo', '#5B5BD6'],
  ['Purple', '#8E4EC6'], ['Pink', '#D6409F'], ['Brown', '#A07553'], ['Gray', '#8B8D98'],
];

/** The Today spindle's color: the weekday label, the date circle and the column tint. */
const TodayStyle = {
  defaultHex: '#E5484D',
  choices: [
    ['Red', '#E5484D'], ['Orange', '#F2811D'], ['Yellow', '#F5C518'], ['Green', '#30A46C'],
    ['Teal', '#0E9FC2'], ['Blue', '#2F6FEB'], ['Indigo', '#5B5BD6'], ['Purple', '#8E4EC6'],
    ['Pink', '#D6409F'], ['Gray', '#8B8D98'],
  ],
  accent(hex, dark) {
    if (hex === TodayStyle.defaultHex) return dark ? '#FF5A5F' : '#E5484D';
    return dark ? Color.mix(hex, '#FFFFFF', 0.12) : hex;
  },
  fill(hex, dark) {
    if (hex === TodayStyle.defaultHex) return dark ? '#3B2624' : '#FFEFEC';
    return dark ? Color.mix(hex, '#1E1E20', 0.80) : Color.mix(hex, '#FFFFFF', 0.89);
  },
};

// ---------------------------------------------------------------- Tags
const Tags = {
  /** "#Follow up" → "Follow-up". Returns null for empty input. */
  normalize(raw) {
    let s = String(raw || '').trim();
    while (s.startsWith('#')) s = s.slice(1);
    s = s.split(/\s+/).filter(Boolean).join('-');
    s = s.replace(/^[,;#]+|[,;#]+$/g, '');
    if (!s) return null;
    return Array.from(s).slice(0, 40).join('');
  },
  parse(text) { return String(text || '').split(/[,; \n\t]+/).map(Tags.normalize).filter(Boolean); },
  sort(list) { return list.sort((a, b) => a.localeCompare(b, 'en', { sensitivity: 'base' })); },
};

// ---------------------------------------------------------------- Time scale presets
const PRESETS = [
  { title: '1 Week', weeks: 1 }, { title: '2 Weeks', weeks: 2 }, { title: '3 Weeks', weeks: 3 },
  { title: '1 Month', months: 1 }, { title: '2 Months', months: 2 }, { title: '3 Months', months: 3 },
  { title: '6 Months', months: 6 }, { title: '1 Year', months: 12 },
];
const Presets = {
  windowFor(p, start) {
    return p.weeks ? { start, end: start + 7 * p.weeks - 1 } : { start, end: Day.addMonths(start, p.months) - 1 };
  },
  /** The preset that produces exactly this window, if any. */
  matching(w) {
    return PRESETS.find((p) => Presets.windowFor(p, w.start).end === w.end) || null;
  },
};
const MAX_WINDOW_DAYS = 732;

// ---------------------------------------------------------------- Content
function uuid() {
  const c = typeof crypto !== 'undefined' ? crypto : require('crypto');
  return c.randomUUID().toUpperCase();
}

function starterContent() {
  return {
    categories: [
      { id: uuid(), name: 'Work', colorHex: '#2F6FEB', notes: null },
      { id: uuid(), name: 'Personal', colorHex: '#30A46C', notes: null },
    ],
    tags: [],
    tasks: [],
    dependencies: [],
  };
}

/** An item (task, milestone or group) with every optional field present (null when unset).
 * `kind` null means a task (as in files from version 2.0); `timeZone` is the zone its times were
 * entered in, null when it has no times. */
function makeTask(fields) {
  return {
    id: fields.id || uuid(), title: fields.title, start: fields.start, end: fields.end,
    categoryID: fields.categoryID, tags: fields.tags || [], parentID: fields.parentID || null,
    colorHex: fields.colorHex || null, notes: fields.notes || null, location: fields.location || null,
    startTime: fields.startTime || null, endTime: fields.endTime || null,
    kind: ['task', 'milestone', 'group'].includes(fields.kind) ? fields.kind : null,
    timeZone: fields.timeZone || null,
    // Marked as completed (whenever it was finished; its dates stay). Listed after the unfinished items
    // at its level; its place in the order is kept, so unmarking it puts it back where it was.
    completed: fields.completed === true ? true : null,
  };
}

const KINDS = { task: 'Task', milestone: 'Milestone', group: 'Group' };
const storedKind = (t) => t.kind || 'task';
const isTimed = (t) => !!(t.startTime || t.endTime);

/** An item as seen from the time zone `view`: a timed item's dates and times are converted from the
 * zone they were entered in; an item without times is returned unchanged. */
function displayed(t, view) {
  if (!isTimed(t) || !t.timeZone || t.timeZone === view || !Zones.valid(t.timeZone)) return t;
  const x = { ...t };
  const s = Zones.convert(t.start, TimeOfDay.minutes(t.startTime || TimeOfDay.defaultStart) ?? 0, t.timeZone, view);
  if (storedKind(t) === 'milestone') {
    x.start = s.day; x.end = s.day; x.startTime = TimeOfDay.text(s.minutes); x.endTime = null;
  } else {
    let e = Zones.convert(t.end, TimeOfDay.minutes(t.endTime || TimeOfDay.defaultEnd) ?? 1440, t.timeZone, view);
    if (e.minutes === 0 && e.day - 1 >= s.day) e = { day: e.day - 1, minutes: 1440 }; // midnight = 24:00 the day before
    x.start = s.day; x.startTime = TimeOfDay.text(s.minutes);
    x.end = Math.max(e.day, s.day); x.endTime = TimeOfDay.text(e.minutes);
  }
  x.timeZone = view;
  return x;
}

/** Arrow types: which ends of the two items an arrow joins. */
const LINK_TYPES = {
  FS: { title: 'Finish → Start', fromEnd: true, toEnd: false },
  SS: { title: 'Start → Start', fromEnd: false, toEnd: false },
  FF: { title: 'Finish → Finish', fromEnd: true, toEnd: true },
  SF: { title: 'Start → Finish', fromEnd: false, toEnd: true },
};
const linkType = (fromEnd, toEnd) => (fromEnd ? (toEnd ? 'FF' : 'FS') : (toEnd ? 'SF' : 'SS'));
/** The sides of an item an arrow can leave from or arrive at. Left is the item's start and right its
 * end; top and bottom are the middle of its upper and lower edge. dx/dy point out of the item. */
const LINK_SIDES = {
  left: { title: 'Left', word: 'start', arrow: '←', dx: -1, dy: 0 },
  right: { title: 'Right', word: 'end', arrow: '→', dx: 1, dy: 0 },
  top: { title: 'Top', word: 'top', arrow: '↑', dx: 0, dy: -1 },
  bottom: { title: 'Bottom', word: 'bottom', arrow: '↓', dx: 0, dy: 1 },
};
const isVerticalSide = (s) => s === 'top' || s === 'bottom';
/** The side an arrow actually leaves its first item from / arrives at its second. Only top and
 * bottom are stored; left and right follow the type (left = start, right = end). */
const exitSide = (d) => (isVerticalSide(d.fromSide) ? d.fromSide : ((LINK_TYPES[d.type] || LINK_TYPES.FS).fromEnd ? 'right' : 'left'));
const entrySide = (d) => (isVerticalSide(d.toSide) ? d.toSide : ((LINK_TYPES[d.type] || LINK_TYPES.FS).toEnd ? 'right' : 'left'));
/** The type an arrow drawn between these sides gets: top and bottom keep Finish → Start for that end. */
const linkTypeForSides = (exit, entry) => linkType(exit !== 'left', entry === 'right');
const LINK_DEFAULT_WIDTH = 1.25;
const LINK_WIDTHS = [0.5, 0.75, 1, 1.25, 1.5, 2, 2.5, 3, 4];

/** Sample tasks for the very first launch, placed around `today`, all tagged #example.
 * Reuses categories with the same names when they exist. */
function exampleContent(today, existing) {
  const categories = existing.map((c) => ({ ...c }));
  const category = (name, hex) => {
    const found = categories.find((c) => c.name.toLowerCase() === name.toLowerCase());
    if (found) return found.id;
    const c = { id: uuid(), name, colorHex: hex, notes: null };
    categories.push(c);
    return c.id;
  };
  const work = category('Work', '#2F6FEB');
  const personal = category('Personal', '#30A46C');
  const home = category('Home', '#F2811D');
  const task = (title, s, e, cat, tags, o = {}) => makeTask({
    title, start: today + s, end: today + e, categoryID: cat, tags: [...tags, 'example'],
    parentID: o.parent, colorHex: o.color, notes: o.notes, location: o.location, startTime: o.startTime, endTime: o.endTime,
  });
  const launch = task('Launch website', -2, 12, work, ['web'],
    { notes: 'A parent task: click the chevron to hide or show its subtasks.' });
  const tasks = [
    launch,
    task('Write copy', -2, 1, work, ['writing'], { parent: launch.id }),
    task('Design mockups', 0, 4, work, ['design'], { parent: launch.id,
      notes: 'Two options for the home page. Drag the bar to move it, or drag an end to change the dates.' }),
    task('Publish site', 10, 12, work, ['web'], { parent: launch.id, location: 'Online', startTime: '10:00' }),
    task('Team meeting', 1, 1, work, ['meeting'], { notes: 'Agenda: progress, risks, next steps.',
      location: 'Room 204', startTime: '09:30', endTime: '10:30' }),
    task('Quarterly report', -4, 3, work, ['follow-up']),
    task('Dentist', 3, 3, personal, ['health'], { location: 'City Dental', startTime: '14:00', endTime: '15:00' }),
    task('Plan trip', 5, 9, personal, ['travel', 'follow-up'], { notes: 'Book train tickets and a hotel.' }),
    task('Garden cleanup', 6, 7, home, ['outdoor'], { notes: 'This bar has its own color, set in the editor under Bar Color.',
      color: '#A07553' }),
  ];
  const tags = Tags.sort([...new Set(tasks.flatMap((t) => t.tags))]);
  return { categories, tags, tasks, dependencies: [] };
}

const Hierarchy = {
  /** Clears parent links to missing tasks, to the task itself, or that form a cycle; keeps
   * milestones on one day with nothing inside them; drops arrows that can't be. */
  repair(content) {
    const ids = new Set(content.tasks.map((t) => t.id));
    for (const t of content.tasks) {
      if (t.parentID && (t.parentID === t.id || !ids.has(t.parentID))) t.parentID = null;
    }
    const milestoneParent = new Map(content.tasks.filter((t) => storedKind(t) === 'milestone').map((t) => [t.id, t.parentID || null]));
    for (const t of content.tasks) {
      let hops = 0;
      while (t.parentID && milestoneParent.has(t.parentID) && hops++ < 100) t.parentID = milestoneParent.get(t.parentID);
      if (storedKind(t) === 'milestone') { t.end = t.start; t.endTime = null; }
    }
    if (!Array.isArray(content.dependencies)) content.dependencies = [];
    const seen = new Set();
    content.dependencies = content.dependencies.filter((d) => {
      const key = `${d.from}>${d.to}`;
      if (d.from === d.to || !ids.has(d.from) || !ids.has(d.to) || seen.has(key)) return false;
      seen.add(key);
      return true;
    });
    const parentOf = new Map(content.tasks.filter((t) => t.parentID).map((t) => [t.id, t.parentID]));
    for (const t of content.tasks) {
      const seen = new Set([t.id]);
      let cur = parentOf.get(t.id);
      while (cur) {
        if (cur === t.id) { t.parentID = null; parentOf.delete(t.id); break; }
        if (seen.has(cur)) break;
        seen.add(cur);
        cur = parentOf.get(cur);
      }
    }
  },
  children(content, id) { return content.tasks.filter((t) => (t.parentID || null) === id); },
  /** Every subtask below `id`, at any depth. */
  descendants(content, id) {
    const result = new Set();
    const frontier = [id];
    while (frontier.length) {
      const next = frontier.pop();
      for (const t of content.tasks) if (t.parentID === next && !result.has(t.id)) { result.add(t.id); frontier.push(t.id); }
    }
    return result;
  },
  /** Parent, grandparent, … of `id`, nearest first. */
  ancestors(content, id) {
    const byId = new Map(content.tasks.map((t) => [t.id, t]));
    const result = [];
    let cur = byId.get(id)?.parentID;
    while (cur && !result.includes(cur)) { result.push(cur); cur = byId.get(cur)?.parentID; }
    return result;
  },
  /** All tasks in outline order (each parent followed by its subtasks), with their depth. */
  outline(content) {
    const byParent = new Map();
    for (const t of content.tasks) {
      const k = t.parentID || null;
      if (!byParent.has(k)) byParent.set(k, []);
      byParent.get(k).push(t);
    }
    const out = [], visited = new Set();
    const visit = (p, depth) => {
      for (const t of byParent.get(p) || []) {
        if (visited.has(t.id)) continue;
        visited.add(t.id);
        out.push({ task: t, depth });
        visit(t.id, depth + 1);
      }
    };
    visit(null, 0);
    return out;
  },
  /** Has subtasks or subgroups (milestones attached to a task don't count). */
  hasStructuralChildren(content, id) { return content.tasks.some((t) => t.parentID === id && storedKind(t) !== 'milestone'); },
  /** What an item is shown as: a task with subtasks becomes a group on its own. */
  effectiveKind(content, t) {
    if (storedKind(t) === 'milestone') return 'milestone';
    if (storedKind(t) === 'group' || Hierarchy.hasStructuralChildren(content, t.id)) return 'group';
    return 'task';
  },
  /** A milestone attached to a task: drawn as a diamond on that task's row. */
  isMark(content, t) {
    if (storedKind(t) !== 'milestone' || !t.parentID) return false;
    const p = content.tasks.find((x) => x.id === t.parentID);
    return !!p && Hierarchy.effectiveKind(content, p) === 'task';
  },
  /** Whether a is an ancestor or a descendant of b. */
  related(content, a, b) {
    return Hierarchy.ancestors(content, a).includes(b) || Hierarchy.ancestors(content, b).includes(a);
  },
  /** Version 2 → 3: each task with subtasks becomes a group spanning them. When its own dates differ
   * from that span, they're kept as a task of the same name, first inside the group. Returns
   * [groups, tasks added]. */
  migrateParentsToGroups(content) {
    let groups = 0, added = 0;
    const inserts = [];
    for (const p of content.tasks) {
      if (storedKind(p) === 'milestone' || !Hierarchy.hasStructuralChildren(content, p.id)) continue;
      const below = [...Hierarchy.descendants(content, p.id)].map((id) => content.tasks.find((t) => t.id === id)).filter(Boolean);
      if (!below.length) continue;
      const s = Math.min(...below.map((t) => t.start)), e = Math.max(...below.map((t) => t.end));
      if (p.start !== s || p.end !== e) {
        inserts.push([p.id, makeTask({ title: p.title, start: p.start, end: p.end, categoryID: p.categoryID, tags: p.tags.slice(),
          parentID: p.id, colorHex: p.colorHex, location: p.location, startTime: p.startTime, endTime: p.endTime,
          kind: 'task', timeZone: p.timeZone })]);
        p.location = null; p.startTime = null; p.endTime = null; p.timeZone = null;
        added++;
      }
      p.kind = 'group';
      groups++;
    }
    for (const [after, t] of inserts) {
      const i = content.tasks.findIndex((x) => x.id === after);
      content.tasks.splice(i + 1, 0, t);
    }
    return [groups, added];
  },
  /** Timed tasks from before time zones were stored were entered in this computer's time zone. */
  assignTimeZone(content, zone) {
    for (const t of content.tasks) if (isTimed(t) && !t.timeZone) t.timeZone = zone;
  },
};

// ---------------------------------------------------------------- File format
const DataFile = {
  /** 3: groups, milestones, arrows and time zones (DaySpindle 2.1). */
  CURRENT_VERSION: 3,

  /** Parses the JSON text of a data file (from the Mac or Windows app). Throws with a readable message. */
  decode(text) {
    let raw;
    try { raw = JSON.parse(String(text).replace(/^﻿/, '')); } catch (e) { throw new Error(`Not valid JSON (${e.message})`); }
    const fail = (what) => { throw new Error(`Not a DaySpindle data file: ${what}`); };
    if (!raw || typeof raw !== 'object') fail('the file is empty');
    const c = raw.content;
    if (!c || !Array.isArray(c.categories) || !Array.isArray(c.tasks)) fail('missing tasks or categories');
    const str = (v) => (typeof v === 'string' && v.trim() !== '' ? v : null);
    const categories = c.categories.map((x, i) => {
      if (typeof x?.id !== 'string' || typeof x?.name !== 'string' || !Color.parse(x?.colorHex)) fail(`category ${i + 1} is incomplete`);
      return { id: x.id.toUpperCase(), name: x.name, colorHex: Color.hex(Color.parse(x.colorHex)), notes: str(x.notes) };
    });
    if (!categories.length) fail('it has no categories');
    const tasks = c.tasks.map((x, i) => {
      const start = Day.parse(x?.start), end = Day.parse(x?.end);
      if (typeof x?.id !== 'string' || typeof x?.title !== 'string' || start == null || end == null || typeof x?.categoryID !== 'string') {
        fail(`task ${i + 1} is incomplete`);
      }
      return makeTask({
        id: x.id.toUpperCase(), title: x.title, start, end: Math.max(end, start),
        categoryID: x.categoryID.toUpperCase(),
        tags: Array.isArray(x.tags) ? x.tags.filter((t) => typeof t === 'string') : [],
        parentID: typeof x.parentID === 'string' ? x.parentID.toUpperCase() : null,
        colorHex: Color.normalizedHex(x.colorHex || ''),
        notes: str(x.notes), location: str(x.location),
        startTime: TimeOfDay.normalize(x.startTime || ''), endTime: TimeOfDay.normalize(x.endTime || '', true),
        kind: x.kind, timeZone: Zones.valid(x.timeZone) ? x.timeZone : null, completed: x.completed === true,
      });
    });
    const catIDs = new Set(categories.map((x) => x.id));
    for (const t of tasks) if (!catIDs.has(t.categoryID)) t.categoryID = categories[0].id;
    const tags = Array.isArray(c.tags) ? c.tags.filter((t) => typeof t === 'string') : [];
    for (const t of tasks) for (const tag of t.tags) if (!tags.some((x) => x.toLowerCase() === tag.toLowerCase())) tags.push(tag);
    const ws = Day.parse(raw.window?.start), we = Day.parse(raw.window?.end);
    const window = ws != null && we != null ? { start: ws, end: Math.max(we, ws) } : null;
    const upper = (a) => (Array.isArray(a) ? a.filter((x) => typeof x === 'string').map((x) => x.toUpperCase()) : []);
    const dependencies = (Array.isArray(c.dependencies) ? c.dependencies : []).filter((d) => d && typeof d.id === 'string'
      && typeof d.from === 'string' && typeof d.to === 'string').map((d) => ({
      id: d.id.toUpperCase(), from: d.from.toUpperCase(), to: d.to.toUpperCase(),
      type: LINK_TYPES[d.type] ? d.type : 'FS',
      colorHex: Color.normalizedHex(d.colorHex || '') || null,
      width: typeof d.width === 'number' && Number.isFinite(d.width) ? Math.min(Math.max(d.width, 0.25), 8) : null,
      fromSide: isVerticalSide(d.fromSide) ? d.fromSide : null,
      toSide: isVerticalSide(d.toSide) ? d.toSide : null,
    }));
    const version = typeof raw.version === 'number' ? raw.version : 1;
    return { version, content: { categories, tags, tasks, dependencies }, window, collapsed: upper(raw.collapsed),
      hiddenCategories: upper(raw.hiddenCategories) };
  },

  /** The JSON text, in the format the Mac app reads (keys sorted, empty optional fields left out). */
  encode({ content, window, collapsed, hiddenCategories }) {
    const sortKeys = (v) => {
      if (Array.isArray(v)) return v.map(sortKeys);
      if (v && typeof v === 'object') return Object.fromEntries(Object.keys(v).sort().map((k) => [k, sortKeys(v[k])]));
      return v;
    };
    const data = {
      version: DataFile.CURRENT_VERSION,
      content: {
        categories: content.categories.map((c) => {
          const o = { id: c.id, name: c.name, colorHex: c.colorHex };
          if (c.notes) o.notes = c.notes;
          return o;
        }),
        tags: content.tags.slice(),
        tasks: content.tasks.map((t) => {
          const o = { id: t.id, title: t.title, start: Day.iso(t.start), end: Day.iso(t.end), categoryID: t.categoryID, tags: t.tags.slice() };
          for (const k of ['parentID', 'colorHex', 'notes', 'location', 'startTime', 'endTime', 'kind', 'timeZone']) if (t[k]) o[k] = t[k];
          if (t.completed === true) o.completed = true;
          return o;
        }),
        dependencies: (content.dependencies || []).map((d) => {
          const o = { id: d.id, from: d.from, to: d.to, type: d.type };
          if (d.colorHex) o.colorHex = d.colorHex;
          if (d.width != null) o.width = d.width;
          if (isVerticalSide(d.fromSide)) o.fromSide = d.fromSide;
          if (isVerticalSide(d.toSide)) o.toSide = d.toSide;
          return o;
        }),
      },
      window: { start: Day.iso(window.start), end: Day.iso(window.end) },
      collapsed: content.tasks.map((t) => t.id).filter((id) => collapsed.has(id)),
      hiddenCategories: content.categories.map((c) => c.id).filter((id) => hiddenCategories.has(id)),
    };
    return JSON.stringify(sortKeys(data), null, 2) + '\n';
  },
};

if (typeof module !== 'undefined') {
  module.exports = {
    Day, Fmt, TimeOfDay, Zones, Weeks, Color, PALETTE, TodayStyle, Tags, PRESETS, Presets, MAX_WINDOW_DAYS,
    uuid, starterContent, makeTask, exampleContent, Hierarchy, DataFile, KINDS, storedKind, isTimed, displayed,
    LINK_TYPES, linkType, LINK_SIDES, isVerticalSide, exitSide, entrySide, linkTypeForSides, LINK_DEFAULT_WIDTH, LINK_WIDTHS,
  };
}
