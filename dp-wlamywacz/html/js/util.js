/* dp-wlamywacz – narzędzia NUI */
'use strict';
const RES = typeof GetParentResourceName === 'function' ? GetParentResourceName() : null;
const DEMO = !RES;

// wiadomość do Lua (w podglądzie przeglądarki – do konsoli)
async function post(name, data) {
  if (DEMO) { console.log('[→ lua]', name, data); return (window.demoReply && window.demoReply(name, data)) || { ok: true }; }
  try {
    const r = await fetch(`https://${RES}/${name}`, { method: 'POST', headers: { 'Content-Type': 'application/json; charset=UTF-8' }, body: JSON.stringify(data || {}) });
    return await r.json();
  } catch (e) { return { ok: false }; }
}

const $ = (s, root) => (root || document).querySelector(s);
const clamp = (v, a, b) => (v < a ? a : v > b ? b : v);
const lerp = (a, b, t) => a + (b - a) * t;
const TAU = Math.PI * 2, DEG = Math.PI / 180;
const pad2 = (n) => String(n).padStart(2, '0');
const circ100 = (a, b) => { const d = Math.abs(a - b) % 100; return Math.min(d, 100 - d); };

function mulberry32(a) { return function () { a |= 0; a = a + 0x6D2B79F5 | 0; let t = Math.imul(a ^ a >>> 15, 1 | a); t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t; return ((t ^ t >>> 14) >>> 0) / 4294967296; }; }
// seed z Lua przepuszczony przez hash, żeby uniknąć korelacji bliskich seedów
function rngFrom(seed) { let h = 2166136261; const s = String(seed); for (let i = 0; i < s.length; i++) { h ^= s.charCodeAt(i); h = Math.imul(h, 16777619); } return mulberry32(h >>> 0); }

function el(tag, attrs, ...kids) {
  const e = document.createElement(tag);
  if (attrs) for (const k in attrs) {
    if (k === 'class') e.className = attrs[k];
    else if (k === 'text') e.textContent = attrs[k];
    else if (k.startsWith('on')) e.addEventListener(k.slice(2), attrs[k]);
    else if (attrs[k] !== undefined && attrs[k] !== null && attrs[k] !== false) e.setAttribute(k, attrs[k]);
  }
  for (const k of kids.flat(Infinity)) if (k !== null && k !== undefined && k !== false) e.append(k.nodeType ? k : document.createTextNode(String(k)));
  return e;
}

function rr(c, x, y, w, h, r) { c.beginPath(); c.moveTo(x + r, y); c.arcTo(x + w, y, x + w, y + h, r); c.arcTo(x + w, y + h, x, y + h, r); c.arcTo(x, y + h, x, y, r); c.arcTo(x, y, x + w, y, r); c.closePath(); }
function circle(c, x, y, r) { c.beginPath(); c.arc(x, y, r, 0, TAU); }

const css = getComputedStyle(document.documentElement);
const tok = (n, f) => css.getPropertyValue(n).trim() || f;
const COL = {
  brass: tok('--brass', '#d9aa4f'), ok: tok('--ok', '#78d39a'), bad: tok('--bad', '#ec6a5f'), warn: tok('--warn', '#eab94c'),
  paper: tok('--paper', '#ece5d4'), muted: tok('--muted', '#8f9ea8'), steel: tok('--steel', '#b9c4cc'), uv: tok('--uv', '#a77dff'),
};
const FD = '"Big Shoulders Display","Arial Narrow",Impact,sans-serif';
const FM = '"IBM Plex Mono",ui-monospace,Menlo,Consolas,monospace';

function screw(c, x, y, a) {
  const g = c.createRadialGradient(x - 2, y - 2, 1, x, y, 8);
  g.addColorStop(0, '#c3ccd2'); g.addColorStop(1, '#4b555c');
  c.fillStyle = g; circle(c, x, y, 7.5); c.fill();
  c.strokeStyle = 'rgba(0,0,0,.65)'; c.lineWidth = 1.6;
  c.beginPath(); c.moveTo(x - 5 * Math.cos(a), y - 5 * Math.sin(a)); c.lineTo(x + 5 * Math.cos(a), y + 5 * Math.sin(a)); c.stroke();
}
function vignette(c, W, H) {
  const g = c.createRadialGradient(W / 2, H / 2, 180, W / 2, H / 2, 520);
  g.addColorStop(0, 'rgba(0,0,0,0)'); g.addColorStop(1, 'rgba(0,0,0,.6)');
  c.fillStyle = g; c.fillRect(0, 0, W, H);
}
