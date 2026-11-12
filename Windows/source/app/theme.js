'use strict';
// Colors (light and dark, the same values as the Mac app) and line icons.

const ThemeColors = {
  canvas: ['#FFFFFF', '#1E1E20'],
  divider: ['#E1E1E4', '#3A3A3D'],
  text: ['#1D1D1F', '#F2F2F5'],
  secondaryText: ['#6E6E73', '#A3A3AA'],
  tertiaryText: ['#A1A1A6', '#6F6F76'],
  tagText: ['#8A8A90', '#8E8E96'],
  headerText: ['#3A3A3C', '#D6D6DB'],
  accent: ['#2F6FEB', '#4C8DFF'],
  gridLine: ['#ECECEF', '#2D2D30'],
  rowLine: ['#F1F1F3', '#29292C'],
  monthLine: ['#D6D6DB', '#4A4A4E'],
  weekend: ['#FAFAFB', '#222224'],
  selection: ['rgba(47,111,235,0.08)', 'rgba(76,141,255,0.20)'],
  hover: ['rgba(0,0,0,0.025)', 'rgba(255,255,255,0.035)'],
  chipFill: ['#F0F0F3', '#303033'],
  chevron: ['#8A8A90', '#8E8E96'],
  bubbleFill: ['rgba(29,29,31,0.9)', 'rgba(236,236,241,0.96)'],
  bubbleText: ['#FFFFFF', '#1D1D1F'],
  barDarkText: ['#1D1D1F', '#1D1D1F'],
  linkLine: ['#6E6E78', '#A0A0AA'],
};

const Theme = {
  dark: false,
  c(name) { return ThemeColors[name][this.dark ? 1 : 0]; },
  font(size, bold = false) { return `${bold ? 'bold ' : ''}${size}px Helvetica, Arial, sans-serif`; },
};

/** Line icons drawn at 16 × 16 in the current text color. */
const Icons = {
  svg(body, size = 16, extra = '') {
    return `<svg width="${size}" height="${size}" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.3" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" ${extra}>${body}</svg>`;
  },
  plus: (s) => Icons.svg('<path d="M8 3v10M3 8h10"/>', s),
  chevronLeft: (s) => Icons.svg('<path d="M10 3.5 5.5 8l4.5 4.5"/>', s),
  chevronRight: (s) => Icons.svg('<path d="M6 3.5 10.5 8 6 12.5"/>', s),
  chevronDown: (s) => Icons.svg('<path d="M4 6l4 4 4-4"/>', s),
  sun: (s) => Icons.svg('<circle cx="8" cy="8" r="2.8"/><path d="M8 1.5v1.6M8 12.9v1.6M1.5 8h1.6M12.9 8h1.6M3.4 3.4l1.1 1.1M11.5 11.5l1.1 1.1M3.4 12.6l1.1-1.1M11.5 4.5l1.1-1.1"/>', s),
  moon: (s) => Icons.svg('<path d="M13.2 10.1A5.6 5.6 0 0 1 5.9 2.8a5.6 5.6 0 1 0 7.3 7.3Z"/>', s),
  desktop: (s) => Icons.svg('<rect x="1.8" y="2.6" width="12.4" height="8.6" rx="1.3"/><path d="M6 13.8h4M8 11.2v2.6"/>', s),
  archive: (s) => Icons.svg('<rect x="2" y="2.8" width="12" height="3.4" rx="0.8"/><path d="M3 6.2v6.3a1 1 0 0 0 1 1h8a1 1 0 0 0 1-1V6.2"/><path d="M6.3 9h3.4"/>', s),
  tray: (s) => Icons.svg('<path d="M2 9.2 3.6 3.4a1 1 0 0 1 1-.7h6.8a1 1 0 0 1 1 .7L14 9.2v3.1a1 1 0 0 1-1 1H3a1 1 0 0 1-1-1Z"/><path d="M2 9.2h3.3l.9 1.6h3.6l.9-1.6H14"/>', s),
  pencil: (s) => Icons.svg('<path d="M10.8 2.7a1.5 1.5 0 0 1 2.1 2.1l-7.7 7.7-2.9.8.8-2.9Z"/>', s),
  note: (s) => Icons.svg('<rect x="3" y="2" width="10" height="12" rx="1.8"/><path d="M5.6 5.6h4.8M5.6 8h4.8M5.6 10.4h2.8"/>', s),
  calendar: (s) => Icons.svg('<rect x="2" y="3" width="12" height="11" rx="1.6"/><path d="M2 6.4h12M5.2 1.8v2.4M10.8 1.8v2.4"/>', s),
  check: (s) => Icons.svg('<path d="M3.5 8.4 6.6 11.4 12.5 4.8"/>', s),
  xmark: (s) => Icons.svg('<path d="M4.5 4.5l7 7M11.5 4.5l-7 7"/>', s),
  filter: (s) => Icons.svg('<circle cx="8" cy="8" r="6.2"/><path d="M5 6.3h6M6 8.3h4M7 10.3h2"/>', s),
  folder: (s) => Icons.svg('<path d="M1.8 4.2a1 1 0 0 1 1-1h3.4l1.4 1.6h5.6a1 1 0 0 1 1 1v6.6a1 1 0 0 1-1 1H2.8a1 1 0 0 1-1-1Z"/>', s),
  folderPlus: (s) => Icons.svg('<path d="M1.8 4.2a1 1 0 0 1 1-1h3.4l1.4 1.6h5.6a1 1 0 0 1 1 1v6.6a1 1 0 0 1-1 1H2.8a1 1 0 0 1-1-1Z"/><path d="M8 7.4v3.8M6.1 9.3h3.8"/>', s),
  warning: (s) => Icons.svg('<path d="M8 2.2 14.3 13H1.7Z"/><path d="M8 6.4v3M8 11.1v.2"/>', s),
  globe: (s) => Icons.svg('<circle cx="8" cy="8" r="6.2"/><path d="M1.8 8h12.4M8 1.8c1.8 1.8 2.6 3.9 2.6 6.2S9.8 12.4 8 14.2C6.2 12.4 5.4 10.3 5.4 8S6.2 3.6 8 1.8Z"/>', s),
  sidebarRight: (s) => Icons.svg('<rect x="1.8" y="2.6" width="12.4" height="10.8" rx="1.6"/><path d="M10 2.6v10.8"/>', s),
  sliders: (s) => Icons.svg('<path d="M2.5 5h11M2.5 11h11"/><circle cx="6" cy="5" r="1.6" fill="currentColor"/><circle cx="10.5" cy="11" r="1.6" fill="currentColor"/>', s),
  arrowIn: (s) => Icons.svg('<path d="M2 8h9M8 5l3 3-3 3M13.5 3.5v9"/>', s),
  arrowOut: (s) => Icons.svg('<path d="M5 8h9M11 5l3 3-3 3M2.5 3.5v9"/>', s),
  info: (s) => Icons.svg('<circle cx="8" cy="8" r="6.2"/><path d="M8 7.2v4M8 4.9v.2"/>', s),
  link: (s) => Icons.svg('<path d="M3 4h4v8h6M10.5 9.5 13 12l-2.5 2.5"/>', s),
};
