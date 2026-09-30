'use strict';
/* ==========================================================================
   dp-doorlock – narzędzia wspólne: DOM, komunikacja z Lua, ikony, toasty
   ========================================================================== */
const DL = (window.DL = {
  isFiveM: typeof window.GetParentResourceName === 'function',
  cfg: { keys: { use: 'E', menu: 'G' }, keypad: { min: 4, max: 8 }, showNames: true },
});

DL.$ = (s, r = document) => r.querySelector(s);
DL.$$ = (s, r = document) => Array.from(r.querySelectorAll(s));

/** h('div.a.b', {attr}, ...children) – mały kreator elementów */
DL.h = (tag, attrs, ...kids) => {
  const [head, ...cls] = tag.split('.');
  const [name, id] = head.split('#');
  const el = document.createElement(name || 'div');
  if (id) el.id = id;
  if (cls.length) el.className = cls.join(' ');
  if (attrs) {
    for (const k in attrs) {
      const v = attrs[k];
      if (v == null || v === false) continue;
      if (k === 'html') el.innerHTML = v;
      else if (k === 'text') el.textContent = v;
      else if (k.startsWith('on')) el.addEventListener(k.slice(2), v);
      else if (k === 'style' && typeof v === 'object') Object.assign(el.style, v);
      else el.setAttribute(k, v === true ? '' : v);
    }
  }
  for (const k of kids.flat()) if (k != null && k !== false) el.append(k.nodeType ? k : document.createTextNode(k));
  return el;
};

DL.esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
DL.clamp = (v, a, b) => (v < a ? a : v > b ? b : v);
DL.lerp = (a, b, t) => a + (b - a) * t;

/** deterministyczny PRNG (mulberry32) – minigry z seedem z serwera */
DL.rng = seed => () => {
  seed |= 0; seed = (seed + 0x6d2b79f5) | 0;
  let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
  t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
  return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
};

/** POST do Lua (albo mock w przeglądarce) */
DL.post = (name, data = {}) => {
  if (!DL.isFiveM) return Promise.resolve(DL.mock ? DL.mock(name, data) : { ok: true });
  return fetch(`https://${GetParentResourceName()}/${name}`, {
    method: 'POST', headers: { 'Content-Type': 'application/json; charset=UTF-8' }, body: JSON.stringify(data),
  }).then(r => r.json()).catch(() => ({ ok: false }));
};

DL.fmtTime = ts => {
  const d = new Date(ts * 1000);
  const p = n => String(n).padStart(2, '0');
  return `${p(d.getDate())}.${p(d.getMonth() + 1)} ${p(d.getHours())}:${p(d.getMinutes())}`;
};
DL.initials = s => String(s || '?').trim().split(/\s+/).slice(0, 2).map(w => w[0]).join('').toUpperCase();

/* ---------------- ikony (linia 1.8, 24×24) ---------------- */
const P = {
  lock: '<rect x="4.5" y="10.5" width="15" height="10" rx="2.5"/><path d="M8 10.5V7.5a4 4 0 0 1 8 0v3"/><circle cx="12" cy="15.5" r="1.4"/>',
  unlock: '<rect x="4.5" y="10.5" width="15" height="10" rx="2.5"/><path d="M8 10.5V7.5a4 4 0 0 1 7.6-1.7"/><circle cx="12" cy="15.5" r="1.4"/>',
  keypad: '<rect x="5" y="2.5" width="14" height="19" rx="2.5"/><rect x="8" y="5.5" width="8" height="3" rx="1"/><path d="M8.5 12h.01M12 12h.01M15.5 12h.01M8.5 15h.01M12 15h.01M15.5 15h.01M12 18h.01"/>',
  card: '<rect x="2.5" y="5.5" width="19" height="13" rx="2.5"/><path d="M2.5 9.5h19"/><rect x="5.5" y="12.5" width="4" height="3" rx=".8"/>',
  finger: '<path d="M7 11a5 5 0 0 1 10 0v1.5"/><path d="M4.5 9a8 8 0 0 1 15 0"/><path d="M12 11v4.5c0 2 1 3.5 2.5 4.5"/><path d="M9 12.5V15c0 2.2.6 4 2 5.5"/><path d="M15 14.5c0 1.6.4 2.8 1.2 3.8"/><path d="M6.3 13.5c.2 2.5 1 4.5 2.4 6"/>',
  knock: '<path d="M8 13V6.5a1.5 1.5 0 0 1 3 0V12"/><path d="M11 11V5a1.5 1.5 0 0 1 3 0v6"/><path d="M14 11V6.5a1.5 1.5 0 0 1 3 0V14a6 6 0 0 1-6 6h-.5A5.5 5.5 0 0 1 5 14.5V11a1.5 1.5 0 0 1 3 0v2"/><path d="M20 4l1.5-1.5M20.5 7.5H22"/>',
  bell: '<path d="M6 16V11a6 6 0 0 1 12 0v5l1.5 2h-15z"/><path d="M10 20.5a2 2 0 0 0 4 0"/>',
  pick: '<path d="M3 21l7.5-7.5"/><path d="M10.5 13.5l6-6 2 1 2.5-2.5"/><path d="M14.5 4.5l5 5"/><path d="M7 21h6"/>',
  chip: '<rect x="6.5" y="6.5" width="11" height="11" rx="1.8"/><rect x="9.5" y="9.5" width="5" height="5" rx=".8"/><path d="M9.5 3v3.5M14.5 3v3.5M9.5 17.5V21M14.5 17.5V21M3 9.5h3.5M3 14.5h3.5M17.5 9.5H21M17.5 14.5H21"/>',
  fire: '<path d="M12 21c-3.9 0-6.5-2.6-6.5-6.2 0-3.7 3-5.6 3.5-9.3 2.2 1.3 3.2 3.3 3.2 5 1-.7 1.6-2 1.7-3.3 2.3 1.8 4.6 4.6 4.6 7.6 0 3.6-2.6 6.2-6.5 6.2z"/><path d="M12 21c-1.5 0-2.7-1.1-2.7-2.7 0-1.8 1.6-2.6 2.1-4.3 1.9 1 3.3 2.5 3.3 4.3 0 1.6-1.2 2.7-2.7 2.7z"/>',
  ram: '<path d="M14 3.5l6.5 6.5-3 3L11 6.5z"/><path d="M12.5 8L4 16.5a2.1 2.1 0 0 0 3 3L15.5 11"/>',
  wrench: '<path d="M14.7 6.3a4 4 0 0 0 5 5L21 10a5.5 5.5 0 0 1-7.2 5.3L7 22l-3-3 6.7-6.8A5.5 5.5 0 0 1 16 5z"/>',
  shield: '<path d="M12 2.8l7.5 3v5.7c0 4.6-3.2 8.3-7.5 9.7-4.3-1.4-7.5-5.1-7.5-9.7V5.8z"/><path d="M9 12l2.2 2.2L15.5 10"/>',
  keys: '<circle cx="8" cy="15" r="4"/><path d="M10.8 12.2L20 3M16 7l2.5 2.5M18 5l2 2"/>',
  hash: '<path d="M5 9h14M5 15h14M10 4L8.5 20M15.5 4L14 20"/>',
  edit: '<path d="M4 20h4L19 9l-4-4L4 16z"/><path d="M13.5 6.5l4 4"/>',
  door: '<path d="M5 21V4.5A1.5 1.5 0 0 1 6.5 3h11A1.5 1.5 0 0 1 19 4.5V21"/><path d="M3 21h18"/><circle cx="15" cy="12.5" r="1"/>',
  double: '<path d="M3.5 21V4.5A1.5 1.5 0 0 1 5 3h14a1.5 1.5 0 0 1 1.5 1.5V21"/><path d="M12 3v18M2 21h20"/><path d="M9.5 12.5h.01M14.5 12.5h.01"/>',
  sliding: '<path d="M2 21h20M3 5h18"/><path d="M4 5v16M20 5v16"/><path d="M8 5v16M12 5v16M16 5v16"/><path d="M13.5 13h5M16.5 11l2 2-2 2"/>',
  garage: '<path d="M3 21V9l9-5.5L21 9v12"/><path d="M6.5 21v-8.5h11V21M6.5 15.5h11M6.5 18.5h11"/>',
  alarm: '<path d="M12 3a7 7 0 0 1 7 7v5l2 3H3l2-3v-5a7 7 0 0 1 7-7z"/><path d="M12 7.5v4.5M12 15h.01"/>',
  bolt: '<path d="M13.5 2.5L5 13.5h6l-1 8 8.5-11h-6z"/>',
  clock: '<circle cx="12" cy="12" r="8.5"/><path d="M12 7.5V12l3 2"/>',
  user: '<circle cx="12" cy="8" r="4"/><path d="M4.5 21a7.5 7.5 0 0 1 15 0"/>',
  users: '<circle cx="9" cy="8" r="3.5"/><path d="M2.5 20a6.5 6.5 0 0 1 13 0"/><path d="M16 4.6a3.5 3.5 0 0 1 0 6.8M18.5 14a6.5 6.5 0 0 1 3 6"/>',
  search: '<circle cx="11" cy="11" r="6.5"/><path d="M20 20l-4.3-4.3"/>',
  plus: '<path d="M12 5v14M5 12h14"/>',
  trash: '<path d="M4 7h16M9.5 7V4.5h5V7M6.5 7l1 13h9l1-13"/><path d="M10 11v5.5M14 11v5.5"/>',
  x: '<path d="M6 6l12 12M18 6L6 18"/>',
  check: '<path d="M4.5 12.5l4.5 4.5L19.5 6.5"/>',
  pin: '<path d="M12 21s-6.5-6-6.5-11a6.5 6.5 0 0 1 13 0c0 5-6.5 11-6.5 11z"/><circle cx="12" cy="10" r="2.3"/>',
  eyeoff: '<path d="M3 3l18 18"/><path d="M10.6 5.1A10 10 0 0 1 12 5c5.5 0 9 5.5 9.5 7-.3.8-1.2 2.4-2.7 3.9M6.6 6.6C4.4 8 3 10.3 2.5 12c.5 1.5 4 7 9.5 7 1.6 0 3-.4 4.3-1.1"/><path d="M9.9 9.9a3 3 0 0 0 4.2 4.2"/>',
  list: '<path d="M8 6h13M8 12h13M8 18h13M3.5 6h.01M3.5 12h.01M3.5 18h.01"/>',
  log: '<path d="M6 3h9l4 4v14H6z"/><path d="M15 3v4h4M9 11h7M9 14.5h7M9 18h4"/>',
  target: '<circle cx="12" cy="12" r="8"/><circle cx="12" cy="12" r="3"/><path d="M12 1.5v4M12 18.5v4M1.5 12h4M18.5 12h4"/>',
  timer: '<circle cx="12" cy="13.5" r="7.5"/><path d="M12 9.5v4l2.5 1.5M9.5 2.5h5M19 6l1.5-1.5"/>',
  cog: '<circle cx="12" cy="12" r="3"/><path d="M12 2.5v2.2M12 19.3v2.2M4.7 4.7l1.6 1.6M17.7 17.7l1.6 1.6M2.5 12h2.2M19.3 12h2.2M4.7 19.3l1.6-1.6M17.7 6.3l1.6-1.6"/>',
  wave: '<path d="M2 12c2.5-6 4.5-6 7 0s4.5 6 7 0 4.5-6 6 0"/>',
  info: '<circle cx="12" cy="12" r="9"/><path d="M12 11v5.5M12 7.5h.01"/>',
  warn: '<path d="M12 3.5l9.5 16.5h-19z"/><path d="M12 10v4.5M12 17.5h.01"/>',
  spark: '<path d="M12 2.5l1.8 6.2 6.2 1.8-6.2 1.8L12 18.5l-1.8-6.2L4 10.5l6.2-1.8z"/><path d="M19 17l.7 2.3L22 20l-2.3.7L19 23l-.7-2.3L16 20l2.3-.7z"/>',
  layers: '<path d="M12 3l9.5 5-9.5 5-9.5-5z"/><path d="M2.5 12.5l9.5 5 9.5-5M2.5 16.5l9.5 5 9.5-5"/>',
  back: '<path d="M15 5l-7 7 7 7"/>',
};
DL.icon = (name, cls = '') =>
  `<svg class="ic ${cls}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${P[name] || P.door}</svg>`;
DL.iconEl = (name, cls) => { const s = document.createElement('span'); s.className = 'icw'; s.innerHTML = DL.icon(name, cls); return s.firstChild; };

/** Animowana kłódka – kabłąk podnosi się i odchyla przy otwarciu (klasa .open na rodzicu) */
DL.padlock = () => `
<svg class="padlock" viewBox="0 0 40 40" aria-hidden="true">
  <path class="pl-shackle" d="M13.5 19v-5.2a6.5 6.5 0 0 1 13 0V19" fill="none" stroke-width="3.2" stroke-linecap="round"/>
  <rect class="pl-body" x="9.5" y="18" width="21" height="15" rx="4"/>
  <rect x="9.5" y="26" width="21" height="7" rx="3.5" fill="#000" opacity=".16"/>
  <rect x="11" y="19.2" width="18" height="2.6" rx="1.3" fill="#fff" opacity=".22"/>
  <path d="M20 23.2a2 2 0 0 1 1.1 3.7l.5 2.6h-3.2l.5-2.6a2 2 0 0 1 1.1-3.7z" fill="rgba(0,0,0,.5)"/>
</svg>`;

/* ---------------- toasty ---------------- */
const toastIcon = { success: 'check', error: 'x', warn: 'warn', info: 'info', alarm: 'alarm' };
DL.toast = (text, kind = 'info', time = 4500) => {
  const box = DL.$('#toasts');
  const t = DL.h('div.toast.' + kind, { style: { '--t': time + 'ms' } });
  t.innerHTML = `<div class="t-ic">${DL.icon(toastIcon[kind] || 'info')}</div><div class="t-txt">${DL.esc(text)}</div><i class="t-bar"></i>`;
  box.append(t);
  while (box.children.length > 5) box.firstChild.remove();
  requestAnimationFrame(() => t.classList.add('in'));
  setTimeout(() => { t.classList.remove('in'); t.classList.add('out'); setTimeout(() => t.remove(), 400); }, time);
  if (kind === 'alarm') DL.Audio?.play('alarm', 0.6);
};

/* ---------------- warstwa modalna (jedna naraz) ---------------- */
DL.layer = {
  cur: null,
  open(name, el, onClose) {
    this.close(true);
    const root = DL.$('#layer');
    root.innerHTML = '';
    root.append(el);
    root.className = 'show l-' + name;
    this.cur = { name, onClose };
  },
  close(silent) {
    const c = this.cur;
    if (!c) return;
    this.cur = null;
    const root = DL.$('#layer');
    root.className = '';
    root.innerHTML = '';
    if (c.onClose) c.onClose();
    if (!silent) DL.post('close');
  },
};

/** Dopasowanie skali okna minigry do rozdzielczości */
DL.fitGame = box => {
  const s = Math.min(1, (window.innerWidth * 0.94) / 1000, (window.innerHeight * 0.9) / 540);
  box.style.setProperty('--gs', s.toFixed(3));
};
