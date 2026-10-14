/* ══ GitDuo 2.0 原型 · 02 · SVG 图标表与构造器（I / svg / pillOf） ══ */
/* ============================================================ icons */
const I = {
  home:'<path d="M3 10.5 12 3l9 7.5"/><path d="M5 9.5V21h14V9.5"/>',
  folder:'<path d="M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/>',
  compass:'<circle cx="12" cy="12" r="9"/><path d="m15.5 8.5-2 5-5 2 2-5z"/>',
  bell:'<path d="M18 8a6 6 0 1 0-12 0c0 7-3 8-3 8h18s-3-1-3-8"/><path d="M10 20a2.2 2.2 0 0 0 4 0"/>',
  user:'<circle cx="12" cy="8" r="4"/><path d="M4 21c1.5-4 5-5.5 8-5.5s6.5 1.5 8 5.5"/>',
  people:'<circle cx="9.5" cy="8" r="3.6"/><path d="M3 20.2c1.3-3.7 4-5.4 6.5-5.4s5.2 1.7 6.5 5.4"/><path d="M16.6 5.4a3.4 3.4 0 0 1 0 6.4"/><path d="M18.6 20.2c-.5-1.7-1.2-3.1-2.2-4.2"/>',
  back:'<path d="M15 18 9 12l6-6"/>',
  chev:'<path d="m9 6 6 6-6 6"/>',
  chevD:'<path d="m6 9 6 6 6-6"/>',
  bm:'<path d="M19 21l-7-5-7 5V5a2 2 0 0 1 2-2h10a2 2 0 0 1 2 2z"/>',
  repo:'<path d="M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/>',
  star:'<path d="m12 3 2.7 5.7 6.3.8-4.6 4.3 1.2 6.2L12 17l-5.6 3 1.2-6.2L3 9.5l6.3-.8z"/>',
  fork:'<circle cx="6" cy="6" r="2.4"/><circle cx="18" cy="6" r="2.4"/><circle cx="12" cy="18" r="2.4"/><path d="M6 8.4V11a2 2 0 0 0 2 2h8a2 2 0 0 0 2-2V8.4M12 13v2.6"/>',
  eye:'<path d="M2 12s3.5-6.5 10-6.5S22 12 22 12s-3.5 6.5-10 6.5S2 12 2 12z"/><circle cx="12" cy="12" r="2.8"/>',
  issueO:'<circle cx="12" cy="12" r="8.5"/><circle cx="12" cy="12" r="2.4" fill="currentColor" stroke="none"/>',
  issueC:'<circle cx="12" cy="12" r="8.5"/><path d="m8.5 12 2.4 2.4 4.6-4.8" stroke="#fff" stroke-width="1.8"/>',
  pr:'<circle cx="6.5" cy="6.5" r="2.4"/><circle cx="6.5" cy="17.5" r="2.4"/><path d="M6.5 9v6"/><circle cx="17.5" cy="17.5" r="2.4"/><path d="M17.5 15V9a3 3 0 0 0-3-3h-2"/><path d="m14.5 3.8-2.4 2.2 2.4 2.2"/>',
  merge:'<circle cx="6.5" cy="6.5" r="2.4"/><circle cx="6.5" cy="17.5" r="2.4"/><path d="M6.5 9v6M6.5 9c0 4 3 6 8 6"/>',
  commit:'<circle cx="12" cy="12" r="3.5"/><path d="M3 12h5.5M15.5 12H21"/>',
  tag:'<path d="m3 12 9-9h7a2 2 0 0 1 2 2v7l-9 9z"/><circle cx="16.5" cy="7.5" r="1.3"/>',
  file:'<path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z"/><path d="M14 3v5h5"/>',
  dir:'<path d="M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/>',
  gear:'<circle cx="12" cy="12" r="3"/><path d="M19 12a7 7 0 0 0-.15-1.4l2-1.55-2-3.45-2.35.95A7 7 0 0 0 14.1 5.1L13.7 2.6h-3.4l-.4 2.5a7 7 0 0 0-2.4 1.45L5.15 5.6l-2 3.45 2 1.55a7 7 0 0 0 0 2.8l-2 1.55 2 3.45 2.35-.95a7 7 0 0 0 2.4 1.45l.4 2.5h3.4l.4-2.5a7 7 0 0 0 2.4-1.45l2.35.95 2-3.45-2-1.55c.1-.45.15-.92.15-1.4z"/>',
  plus:'<path d="M12 5v14M5 12h14"/>',
  /* 导航栏右上角那颗「⋯」（App 侧 `GitHubIcon.ellipsis`）。
     ⚠️ 三个实心点 —— 表里其余图标都是描边（`fill:none` 由外层样式给），
        所以每个圆点上要显式写 `fill="currentColor" stroke="none"`（同 `issueO` 那个内点）。 */
  dots:'<circle cx="5" cy="12" r="1.7" fill="currentColor" stroke="none"/><circle cx="12" cy="12" r="1.7" fill="currentColor" stroke="none"/><circle cx="19" cy="12" r="1.7" fill="currentColor" stroke="none"/>',
  search:'<circle cx="11" cy="11" r="7"/><path d="m20 20-3.8-3.8"/>',
  clock:'<circle cx="12" cy="12" r="9"/><path d="M12 7.5V12l3 2"/>',
  x:'<path d="M6 6l12 12M18 6 6 18"/>',
  pencil:'<path d="M4 20h4L18.5 9.5a2.12 2.12 0 0 0-3-3L5 17z"/><path d="m14.5 6.5 3 3"/>',
  trash:'<path d="M4 7h16"/><path d="M9.5 7V5.4A1.4 1.4 0 0 1 10.9 4h2.2a1.4 1.4 0 0 1 1.4 1.4V7"/><path d="m6.5 7 .9 12.1a2 2 0 0 0 2 1.9h5.2a2 2 0 0 0 2-1.9L17.5 7"/>',
  check:'<path d="m4.5 12.5 5 5L19.5 7"/>',
  lock:'<rect x="4" y="10.5" width="16" height="10" rx="2.4"/><path d="M8 10.5V7.6a4 4 0 0 1 8 0v2.9"/>',
};
/* GitHub mark（官方 Octocat 轮廓，纯 fill） */
const GH_MARK = '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 2C6.48 2 2 6.48 2 12c0 4.42 2.87 8.17 6.84 9.5.5.09.66-.22.66-.48v-1.7c-2.78.6-3.37-1.34-3.37-1.34-.45-1.16-1.1-1.47-1.1-1.47-.9-.62.07-.6.07-.6 1 .07 1.53 1.03 1.53 1.03.88 1.52 2.34 1.08 2.9.83.09-.65.35-1.09.63-1.34-2.22-.25-4.55-1.11-4.55-4.94 0-1.09.39-1.98 1.03-2.68-.1-.25-.45-1.27.1-2.64 0 0 .84-.27 2.75 1.02a9.6 9.6 0 0 1 5 0c1.91-1.29 2.75-1.02 2.75-1.02.55 1.37.2 2.39.1 2.64.64.7 1.03 1.59 1.03 2.68 0 3.84-2.34 4.69-4.57 4.93.36.31.68.92.68 1.85v2.74c0 .27.16.58.67.48A10 10 0 0 0 22 12c0-5.52-4.48-10-10-10z"/></svg>';
const svg = (p,cls='') => `<svg class="${cls}" viewBox="0 0 24 24">${p}</svg>`;
const pillOf = s => ({
  'open':'<span class="pill open">● Open</span>',
  'closed-i':'<span class="pill closed-i">● Closed</span>',
  'closed-p':'<span class="pill closed-p">● Closed</span>',
  'merged':'<span class="pill merged">⇿ Merged</span>',
}[s] || '');
