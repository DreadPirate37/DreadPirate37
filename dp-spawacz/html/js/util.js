'use strict';
/* ==========================================================================
   dp-spawacz – narzędzia wspólne (matematyka, RNG, ścieżki, wejście, NUI)
   ========================================================================== */
const W = (window.W = window.W || {});

W.VW = 1280;
W.VH = 720;
W.isFiveM = typeof window.GetParentResourceName === 'function';
W.resName = W.isFiveM ? window.GetParentResourceName() : 'dp-spawacz';

W.clamp = (v, a, b) => (v < a ? a : v > b ? b : v);
W.lerp = (a, b, t) => a + (b - a) * t;
W.smooth = (e0, e1, x) => {
  const t = W.clamp((x - e0) / (e1 - e0), 0, 1);
  return t * t * (3 - 2 * t);
};
W.gauss = (x, s) => Math.exp(-((x / s) * (x / s)));
W.dist = (ax, ay, bx, by) => Math.hypot(ax - bx, ay - by);

/* Deterministyczny RNG (mulberry32) – ten sam seed = ten sam detal */
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

/* Szum 1D (value noise) – drżenie ręki, dryf łuku */
W.makeNoise = rand => {
  const p = new Float32Array(512);
  for (let i = 0; i < 512; i++) p[i] = rand() * 2 - 1;
  return x => {
    const i = Math.floor(x);
    const f = x - i;
    const t = f * f * (3 - 2 * f);
    const a = p[i & 511];
    const b = p[(i + 1) & 511];
    return a + (b - a) * t;
  };
};

W.canvas = (w = W.VW, h = W.VH) => {
  const c = document.createElement('canvas');
  c.width = w;
  c.height = h;
  return c;
};

/* --------------------------------------------------------------------------
   Ścieżka spoiny – wygładzona (Catmull-Rom) i równomiernie próbkowana
   -------------------------------------------------------------------------- */
function catmull(pts, closed, steps) {
  const out = [];
  const n = pts.length;
  const get = i => (closed ? pts[(i + n) % n] : pts[W.clamp(i, 0, n - 1)]);
  const segs = closed ? n : n - 1;
  for (let i = 0; i < segs; i++) {
    const p0 = get(i - 1), p1 = get(i), p2 = get(i + 1), p3 = get(i + 2);
    for (let s = 0; s < steps; s++) {
      const t = s / steps, t2 = t * t, t3 = t2 * t;
      out.push([
        0.5 * (2 * p1[0] + (-p0[0] + p2[0]) * t + (2 * p0[0] - 5 * p1[0] + 4 * p2[0] - p3[0]) * t2 + (-p0[0] + 3 * p1[0] - 3 * p2[0] + p3[0]) * t3),
        0.5 * (2 * p1[1] + (-p0[1] + p2[1]) * t + (2 * p0[1] - 5 * p1[1] + 4 * p2[1] - p3[1]) * t2 + (-p0[1] + 3 * p1[1] - 3 * p2[1] + p3[1]) * t3),
      ]);
    }
  }
  if (!closed) out.push(pts[n - 1]);
  return out;
}

function resample(pts, closed, sp) {
  const P = closed ? pts.concat([pts[0]]) : pts;
  const out = [P[0].slice()];
  let carry = 0;
  for (let k = 1; k < P.length; k++) {
    const ax = P[k - 1][0], ay = P[k - 1][1], bx = P[k][0], by = P[k][1];
    const L = Math.hypot(bx - ax, by - ay);
    if (L < 1e-6) continue;
    let pos = sp - carry;
    while (pos <= L) {
      out.push([ax + ((bx - ax) * pos) / L, ay + ((by - ay) * pos) / L]);
      pos += sp;
    }
    carry = L - (pos - sp);
  }
  if (closed && out.length > 2) {
    const f = out[0], l = out[out.length - 1];
    if (Math.hypot(f[0] - l[0], f[1] - l[1]) < sp * 0.5) out.pop();
  } else if (!closed) {
    const last = P[P.length - 1];
    const l = out[out.length - 1];
    if (Math.hypot(last[0] - l[0], last[1] - l[1]) > sp * 0.35) out.push(last.slice());
  }
  return out;
}

W.Path = class {
  constructor(ctrl, { closed = false, spacing = 3, smooth = true, steps = 14 } = {}) {
    const pts = resample(smooth ? catmull(ctrl, closed, steps) : ctrl, closed, spacing);
    const n = pts.length;
    this.closed = closed;
    this.sp = spacing;
    this.n = n;
    this.x = new Float32Array(n);
    this.y = new Float32Array(n);
    this.nx = new Float32Array(n);
    this.ny = new Float32Array(n);
    this.ang = new Float32Array(n);
    for (let i = 0; i < n; i++) {
      this.x[i] = pts[i][0];
      this.y[i] = pts[i][1];
    }
    for (let i = 0; i < n; i++) {
      const a = closed ? (i - 1 + n) % n : Math.max(0, i - 1);
      const b = closed ? (i + 1) % n : Math.min(n - 1, i + 1);
      let tx = this.x[b] - this.x[a], ty = this.y[b] - this.y[a];
      const l = Math.hypot(tx, ty) || 1;
      tx /= l;
      ty /= l;
      this.nx[i] = -ty;
      this.ny[i] = tx;
      this.ang[i] = Math.atan2(ty, tx);
    }
    this.len = closed ? n * spacing : (n - 1) * spacing;
  }

  /* najbliższy punkt: indeks, odległość, przesunięcie boczne (ze znakiem) */
  nearest(px, py) {
    let best = 0, bd = 1e12;
    const X = this.x, Y = this.y;
    for (let i = 0; i < this.n; i++) {
      const dx = X[i] - px, dy = Y[i] - py;
      const d = dx * dx + dy * dy;
      if (d < bd) {
        bd = d;
        best = i;
      }
    }
    const lat = (px - X[best]) * this.nx[best] + (py - Y[best]) * this.ny[best];
    return { i: best, s: best * this.sp, d: Math.sqrt(bd), lat };
  }

  idx(s) {
    const i = Math.round(s / this.sp);
    return this.closed ? ((i % this.n) + this.n) % this.n : W.clamp(i, 0, this.n - 1);
  }

  /* różnica długości łuku z uwzględnieniem ścieżek zamkniętych */
  ds(a, b) {
    let d = b - a;
    if (this.closed) {
      if (d > this.len / 2) d -= this.len;
      else if (d < -this.len / 2) d += this.len;
    }
    return d;
  }

  stroke(g) {
    g.beginPath();
    g.moveTo(this.x[0], this.y[0]);
    for (let i = 1; i < this.n; i++) g.lineTo(this.x[i], this.y[i]);
    if (this.closed) g.closePath();
    g.stroke();
  }

  strokeOffset(g, off) {
    g.beginPath();
    for (let i = 0; i < this.n; i++) {
      const x = this.x[i] + this.nx[i] * off, y = this.y[i] + this.ny[i] * off;
      if (i === 0) g.moveTo(x, y);
      else g.lineTo(x, y);
    }
    if (this.closed) g.closePath();
    g.stroke();
  }
};

/* --------------------------------------------------------------------------
   Wejście (mysz / klawiatura) w logicznych współrzędnych 1280x720
   -------------------------------------------------------------------------- */
W.Input = {
  x: 640, y: 360, down: false, rdown: false, wheel: 0,
  keys: new Set(), pressed: new Set(),
  clicked: false, clicks: 0, rclicked: false, released: false,
  el: null,
  attach(el) {
    this.el = el;
    const pos = e => {
      const r = el.getBoundingClientRect();
      this.x = ((e.clientX - r.left) / r.width) * W.VW;
      this.y = ((e.clientY - r.top) / r.height) * W.VH;
    };
    window.addEventListener('mousemove', pos);
    window.addEventListener('mousedown', e => {
      pos(e);
      W.Audio.unlock();
      if (e.button === 0) { this.down = true; this.clicked = true; this.clicks++; }
      if (e.button === 2) { this.rdown = true; this.rclicked = true; }
    });
    window.addEventListener('mouseup', e => {
      if (e.button === 0) { this.down = false; this.released = true; }
      if (e.button === 2) this.rdown = false;
    });
    window.addEventListener('wheel', e => { this.wheel += e.deltaY < 0 ? 1 : -1; }, { passive: true });
    window.addEventListener('contextmenu', e => e.preventDefault());
    window.addEventListener('keydown', e => {
      if (!this.keys.has(e.code)) this.pressed.add(e.code);
      this.keys.add(e.code);
      if (['Space', 'Tab'].includes(e.code)) e.preventDefault();
    });
    window.addEventListener('keyup', e => this.keys.delete(e.code));
    window.addEventListener('blur', () => { this.keys.clear(); this.down = false; this.rdown = false; });
  },
  key(c) { return this.keys.has(c); },
  hit(c) { return this.pressed.has(c); },
  endFrame() {
    this.pressed.clear();
    this.clicked = false;
    this.clicks = 0;
    this.rclicked = false;
    this.released = false;
    this.wheel = 0;
  },
};

/* --------------------------------------------------------------------------
   Komunikacja z Lua
   -------------------------------------------------------------------------- */
W.post = async (name, data = {}) => {
  if (!W.isFiveM) return W.mock ? W.mock(name, data) : null;
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

W.fmtMoney = v => '$' + Math.round(v).toLocaleString('pl-PL');
W.esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

W.toast = (text, kind = 'info', time = 4500) => {
  const box = document.getElementById('toasts');
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
