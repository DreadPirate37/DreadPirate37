'use strict';
/* ==========================================================================
   dp-dziupla – narzędzia wspólne NUI (matematyka, RNG, wejście, komunikacja)
   ========================================================================== */
const W = (window.W = window.W || {});

W.isFiveM = typeof window.GetParentResourceName === 'function';
W.resName = W.isFiveM ? window.GetParentResourceName() : 'dp-dziupla';

W.clamp = (v, a, b) => (v < a ? a : v > b ? b : v);
W.lerp = (a, b, t) => a + (b - a) * t;
W.dist = (ax, ay, bx, by) => Math.hypot(ax - bx, ay - by);
W.$ = id => document.getElementById(id);

/* Deterministyczny RNG (mulberry32) */
W.rng = seed => {
  let a = seed >>> 0 || 1;
  const r = () => {
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
  r.range = (lo, hi) => lo + r() * (hi - lo);
  r.int = (lo, hi) => Math.floor(lo + r() * (hi - lo + 1));
  r.pick = arr => arr[Math.floor(r() * arr.length)];
  return r;
};

/* Płótno dopasowane do okna (z uwzględnieniem DPR) */
W.fitCanvas = cv => {
  const dpr = Math.min(2, window.devicePixelRatio || 1);
  const w = window.innerWidth, h = window.innerHeight;
  if (cv.width !== Math.round(w * dpr) || cv.height !== Math.round(h * dpr)) {
    cv.width = Math.round(w * dpr);
    cv.height = Math.round(h * dpr);
  }
  const g = cv.getContext('2d');
  g.setTransform(dpr, 0, 0, dpr, 0, 0);
  return { g, w, h };
};

/* --------------------------------------------------------------------------
   Wejście w pikselach okna (overlay i minigry). Prędkość myszy jest wygładzana.
   -------------------------------------------------------------------------- */
W.Input = {
  x: 0, y: 0, vx: 0, vy: 0, speed: 0, down: false, rdown: false, wheel: 0,
  keys: new Set(), pressed: new Set(), clicked: false, released: false, rclicked: false,
  _lx: 0, _ly: 0, _lt: 0,
  init() {
    window.addEventListener('mousemove', e => {
      const now = performance.now();
      const dt = Math.max(14, now - this._lt) / 1000; // min. ~1 klatka – bez skoków prędkości
      const vx = (e.clientX - this._lx) / dt, vy = (e.clientY - this._ly) / dt;
      this.vx = this.vx * 0.6 + vx * 0.4;
      this.vy = this.vy * 0.6 + vy * 0.4;
      this.x = e.clientX;
      this.y = e.clientY;
      this._lx = e.clientX;
      this._ly = e.clientY;
      this._lt = now;
    });
    window.addEventListener('mousedown', e => {
      W.Audio.unlock();
      if (e.target.closest && e.target.closest('button, input, .no-game')) return;
      if (e.button === 0) { this.down = true; this.clicked = true; }
      if (e.button === 2) { this.rdown = true; this.rclicked = true; }
    });
    window.addEventListener('mouseup', e => {
      if (e.button === 0) { if (this.down) this.released = true; this.down = false; }
      if (e.button === 2) this.rdown = false;
    });
    window.addEventListener('wheel', e => { this.wheel += e.deltaY < 0 ? 1 : -1; }, { passive: true });
    window.addEventListener('contextmenu', e => e.preventDefault());
    window.addEventListener('keydown', e => {
      if (e.target && e.target.tagName === 'INPUT') return;
      if (!this.keys.has(e.code)) this.pressed.add(e.code);
      this.keys.add(e.code);
      if (['Space', 'Tab'].includes(e.code)) e.preventDefault();
    });
    window.addEventListener('keyup', e => this.keys.delete(e.code));
    window.addEventListener('blur', () => { this.keys.clear(); this.down = false; this.rdown = false; });
  },
  key(c) { return this.keys.has(c); },
  hit(c) { return this.pressed.has(c); },
  /* wywołać raz na klatkę; prędkość wygasa, gdy mysz stoi */
  tick(dt) {
    if (performance.now() - this._lt > 60) {
      this.vx *= Math.pow(0.001, dt);
      this.vy *= Math.pow(0.001, dt);
    }
    this.speed = Math.hypot(this.vx, this.vy);
  },
  endFrame() {
    this.pressed.clear();
    this.clicked = false;
    this.released = false;
    this.rclicked = false;
    this.wheel = 0;
  },
};

/* --------------------------------------------------------------------------
   Komunikacja z Lua
   -------------------------------------------------------------------------- */
W.post = async (name, data = {}) => {
  if (!W.isFiveM) return W.mock ? W.mock(name, data) : { ok: true };
  try {
    const r = await fetch(`https://${W.resName}/${name}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json; charset=UTF-8' },
      body: JSON.stringify(data),
    });
    return await r.json();
  } catch (e) {
    return null;
  }
};

W.fmtMoney = v => '$' + Math.round(v || 0).toLocaleString('pl-PL');
W.esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
W.fmtTime = s => `${Math.floor(s / 60)}:${String(Math.floor(s % 60)).padStart(2, '0')}`;

W.toast = (text, kind = 'info', time = 4500) => {
  const box = W.$('toasts');
  const el = document.createElement('div');
  el.className = 'toast ' + kind;
  el.innerHTML = `<i></i><span>${W.esc(text)}</span>`;
  box.appendChild(el);
  requestAnimationFrame(() => el.classList.add('in'));
  setTimeout(() => {
    el.classList.remove('in');
    setTimeout(() => el.remove(), 350);
  }, time);
};

/* Kolor stanu części 0..100 */
W.condColor = c => (c >= 75 ? 'var(--good)' : c >= 45 ? 'var(--acc)' : 'var(--bad)');

/* Proste cząsteczki w pikselach ekranu */
W.Particles = class {
  constructor() { this.list = []; }
  add(p) { if (this.list.length < 600) this.list.push(p); }
  update(dt) {
    const L = this.list;
    for (let i = L.length - 1; i >= 0; i--) {
      const p = L[i];
      p.life -= dt;
      if (p.life <= 0) { L.splice(i, 1); continue; }
      p.vy += (p.g ?? 900) * dt;
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      if (p.rot != null) p.rot += (p.vr || 0) * dt;
    }
  }
  draw(g) {
    for (const p of this.list) {
      const a = W.clamp(p.life / (p.max || 1), 0, 1);
      g.globalAlpha = a;
      if (p.kind === 'spark') {
        g.strokeStyle = p.c || '#ffcf6b';
        g.lineWidth = 2;
        g.beginPath();
        g.moveTo(p.x, p.y);
        g.lineTo(p.x - p.vx * 0.02, p.y - p.vy * 0.02);
        g.stroke();
      } else if (p.kind === 'hex') {
        g.save();
        g.translate(p.x, p.y);
        g.rotate(p.rot || 0);
        W.hex(g, 0, 0, p.r, '#9aa3ab', '#5d656c');
        g.restore();
      } else {
        g.fillStyle = p.c || '#fff';
        g.beginPath();
        g.arc(p.x, p.y, p.r || 2, 0, Math.PI * 2);
        g.fill();
      }
    }
    g.globalAlpha = 1;
  }
  clear() { this.list.length = 0; }
};

/* Sześciokątny łeb śruby */
W.hex = (g, x, y, r, fill, stroke, rot = 0) => {
  g.beginPath();
  for (let i = 0; i < 6; i++) {
    const a = rot + (i / 6) * Math.PI * 2;
    const px = x + Math.cos(a) * r, py = y + Math.sin(a) * r;
    if (i === 0) g.moveTo(px, py);
    else g.lineTo(px, py);
  }
  g.closePath();
  g.fillStyle = fill;
  g.fill();
  if (stroke) {
    g.strokeStyle = stroke;
    g.lineWidth = Math.max(1, r * 0.12);
    g.stroke();
  }
};

W.roundRect = (g, x, y, w, h, r) => {
  g.beginPath();
  g.moveTo(x + r, y);
  g.arcTo(x + w, y, x + w, y + h, r);
  g.arcTo(x + w, y + h, x, y + h, r);
  g.arcTo(x, y + h, x, y, r);
  g.arcTo(x, y, x + w, y, r);
  g.closePath();
};
