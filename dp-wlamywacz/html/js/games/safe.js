/* ZAM-10 – sejf z tarczą na stetoskop. Kolejno ↻ ↺ ↻; zapadkę słychać tylko przy obrocie
   we właściwą stronę. Szum otoczenia (pralka) utrudnia słuchanie; wykres stetoskopu pomaga
   graczom bez dźwięku (dostępność). */
'use strict';
Games.safe = {
  title: (p) => `Sejf · klasa ${p.cls}`,
  help: () => 'Kręć tarczą przeciągając po niej, kółkiem albo <kbd>←</kbd>/<kbd>→</kbd> (<kbd>Shift</kbd> – precyzyjnie). <kbd>Enter</kbd> zapisuje liczbę, <kbd>E</kbd> ciągnie klamkę.',
  create(p, api) {
    const P = { A: { tol: 1, vol: 1, fake: 0, bg: 0.1 }, B: { tol: 0, vol: 0.7, fake: 1, bg: 0.3 }, C: { tol: 0, vol: 0.45, fake: 3, bg: 0.5 } }[p.cls] || { tol: 0, vol: 0.7, fake: 1, bg: 0.3 };
    const rng = api.rng;
    const combo = (p.combo || [11, 52, 87]).map(Number);
    const fakes = [];
    while (fakes.length < P.fake) { const n = Math.floor(rng() * 100); if (combo.every((c) => circ100(c, n) > 4) && !fakes.includes(n)) fakes.push(n); }
    const DIRS = [-1, 1, -1];
    const CX = 400, CY = 236;
    const g = {
      num: Math.floor(rng() * 100), step: 0, marks: [], vib: 0, osc: new Float32Array(240), oscI: 0, spike: 0, dragA: null, keyDir: 0, fine: false, lastTick: 0, open: 0, done: false,
      partial() { return {}; },
      turn(d) {
        if (!d || this.done) return;
        const from = this.num;
        this.num = ((from + d) % 100 + 100) % 100;
        if (Math.abs(d) > 50) return;
        if (d > 0) { for (let m = Math.floor(from) + 1; m <= from + d; m++) this.cross(((m % 100) + 100) % 100, 1); }
        else { for (let m = Math.ceil(from) - 1; m >= from + d; m--) this.cross(((m % 100) + 100) % 100, -1); }
      },
      cross(m, s) {
        const now = performance.now();
        if (now - this.lastTick > 22) { Snd.tick(0.02 + 0.04 * P.vol); this.lastTick = now; }
        this.spike = Math.max(this.spike, 0.12);
        if (this.step < 3 && s === DIRS[this.step] && circ100(m, combo[this.step]) <= P.tol) { Snd.thunk(0.4 * P.vol, -0.4); this.vib = 1; this.spike = 1; }
        else if (fakes.includes(m)) { Snd.thunk(0.26 * P.vol, -0.4); this.spike = Math.max(this.spike, 0.62); }
      },
      mark() {
        if (this.done || this.step >= 3) return;
        this.marks.push(Math.round(this.num) % 100); this.step++; Snd.click(0.25);
      },
      pull() {
        if (this.done) return;
        if (this.marks.length < 3) return;
        const ok = this.marks.every((m, i) => circ100(m, combo[i]) <= P.tol);
        if (ok) { this.done = true; Snd.open(); setTimeout(() => api.finish({ ok: true, combo: this.marks }), 700); }
        else { Snd.thunk(0.7); api.noise(15, 'klamka'); this.marks = []; this.step = 0; }
      },
      update(dt) {
        if (this.keyDir) this.turn(this.keyDir * (this.fine ? 3 : 12) * dt);
        this.vib *= Math.pow(0.02, dt);
        for (let k = 0; k < 2; k++) {
          const v = P.bg * (Math.random() * 2 - 1) * 0.4 + this.spike * (Math.random() < 0.5 ? 1 : -1) * (0.7 + Math.random() * 0.3);
          this.osc[this.oscI] = v; this.oscI = (this.oscI + 1) % this.osc.length; this.spike *= 0.55;
        }
        if (this.done) this.open = Math.min(1, this.open + dt * 1.5);
      },
      down(pt) { const dx = pt.x - CX, dy = pt.y - CY; if (dx * dx + dy * dy < 175 * 175) this.dragA = Math.atan2(dy, dx); },
      move(pt) {
        if (this.dragA === null) return;
        const a = Math.atan2(pt.y - CY, pt.x - CX);
        let da = a - this.dragA; if (da > Math.PI) da -= TAU; if (da < -Math.PI) da += TAU;
        this.dragA = a; this.turn(-da / (3.6 * DEG));
      },
      up() { this.dragA = null; },
      wheel(dy) { this.turn(dy > 0 ? -1 : 1); },
      key(e, down) {
        const k = e.key.toLowerCase();
        if (k === 'arrowright' || k === 'd') { this.keyDir = down ? -1 : (this.keyDir === -1 ? 0 : this.keyDir); return true; }
        if (k === 'arrowleft' || k === 'a') { this.keyDir = down ? 1 : (this.keyDir === 1 ? 0 : this.keyDir); return true; }
        if (k === 'shift') { this.fine = down; return true; }
        if (down && !e.repeat && k === 'enter') { this.mark(); return true; }
        if (down && !e.repeat && k === 'e') { this.pull(); return true; }
        return false;
      },
      draw(c) {
        c.fillStyle = '#1a2025'; c.fillRect(0, 0, 800, 600);
        const g2 = c.createLinearGradient(150, 30, 650, 570); g2.addColorStop(0, '#56626b'); g2.addColorStop(0.5, '#3a444c'); g2.addColorStop(1, '#262d33');
        c.fillStyle = g2; rr(c, 150, 30, 500, 540, 16); c.fill();
        for (let x = 176; x <= 624; x += 56) { screw(c, x, 50, x * 0.03); screw(c, x, 550, x * 0.05); }
        c.fillStyle = '#20262b'; circle(c, CX, CY, 152); c.fill();
        const cy = CY + (this.vib > 0.05 ? (Math.random() - 0.5) * 3 * this.vib : 0);
        c.save(); c.translate(CX, cy); c.rotate(-this.num * 3.6 * DEG);
        let gr = c.createRadialGradient(-30, -40, 10, 0, 0, 140); gr.addColorStop(0, '#3a4248'); gr.addColorStop(1, '#151a1e');
        c.fillStyle = gr; circle(c, 0, 0, 140); c.fill();
        for (let m = 0; m < 100; m++) {
          const a = m * 3.6 * DEG, s = Math.sin(a), co = -Math.cos(a);
          const len = m % 10 === 0 ? 16 : m % 5 === 0 ? 11 : 6;
          c.strokeStyle = m % 10 === 0 ? '#f0ece2' : 'rgba(220,226,230,.7)'; c.lineWidth = m % 5 === 0 ? 2 : 1;
          c.beginPath(); c.moveTo(s * 136, co * 136); c.lineTo(s * (136 - len), co * (136 - len)); c.stroke();
          if (m % 10 === 0) { c.save(); c.translate(s * 108, co * 108); c.rotate(a); c.fillStyle = '#f0ece2'; c.font = `600 18px ${FM}`; c.textAlign = 'center'; c.textBaseline = 'middle'; c.fillText(String(m), 0, 0); c.restore(); }
        }
        gr = c.createRadialGradient(-18, -22, 4, 0, 0, 62); gr.addColorStop(0, '#d5dde2'); gr.addColorStop(0.6, '#7b8790'); gr.addColorStop(1, '#3a444b');
        c.fillStyle = gr; circle(c, 0, 0, 60); c.fill();
        c.restore(); c.textBaseline = 'alphabetic';
        c.fillStyle = COL.brass; c.beginPath(); c.moveTo(CX - 9, CY - 156); c.lineTo(CX + 9, CY - 156); c.lineTo(CX, CY - 142); c.closePath(); c.fill();
        c.font = `500 14px ${FM}`; c.textAlign = 'center'; c.fillStyle = COL.paper; c.fillText(pad2(Math.round(this.num) % 100), CX, CY - 164);
        c.save(); c.translate(598, 236); c.rotate(-this.open * 55 * DEG); c.fillStyle = '#9aa6ae'; rr(c, -10, -10, 26, 110, 10); c.fill(); c.fillStyle = '#5a656d'; circle(c, 0, 0, 22); c.fill(); c.restore();
        c.textAlign = 'left'; c.font = `600 15px ${FD}`; c.fillStyle = COL.brass;
        c.fillText(this.step < 3 ? `KROK ${this.step + 1}/3 · ${DIRS[this.step] < 0 ? '↻ W PRAWO' : '↺ W LEWO'} · zapisane: ${this.marks.map(pad2).join('-') || '—'}` : 'POCIĄGNIJ KLAMKĘ (E)', 184, 410);
        c.save(); rr(c, 176, 432, 448, 104, 8); c.clip();
        c.fillStyle = '#07090b'; c.fillRect(176, 432, 448, 104);
        c.strokeStyle = COL.warn; c.lineWidth = 1.6; c.beginPath();
        const n = this.osc.length;
        for (let k = 0; k < n; k++) { const v = this.osc[(this.oscI + k) % n]; const x = 184 + (k / (n - 1)) * 432, y = 490 - clamp(v, -1, 1) * 38; if (k) c.lineTo(x, y); else c.moveTo(x, y); }
        c.stroke(); c.restore();
        c.font = `500 11px ${FM}`; c.fillStyle = COL.muted; c.fillText('STETOSKOP', 184, 426);
      },
    };
    return g;
  },
};
