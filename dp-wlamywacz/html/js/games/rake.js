/* WYT-03 – grabie: trzymasz napięcie w zielonej strefie i szarpiesz wytrychem w poziomie.
   Każde szarpnięcie ma szansę ustawić kolejny pin. Szybkie na klasie A, rzadkie na B. Głośne (25). */
'use strict';
Games.rake = {
  title: (p) => `Grabie · klasa ${p.cls}`,
  help: () => 'Kółko myszy albo <kbd>W</kbd>/<kbd>S</kbd> ustawia napięcie – trzymaj je w jasnej strefie. Przytrzymaj <kbd>LPM</kbd> i szarp myszą w lewo i w prawo.',
  create(p, api) {
    const pins = p.cls === 'A' ? 3 : p.cls === 'D' ? 2 : 5;
    const chance = p.chance || 0.3;
    const g = {
      t: 0.2, set: 0, time: 25, pressing: false, lastX: 400, dir: 0, amp: 0, pinX: 400, noiseT: 0, jig: new Array(pins).fill(0), done: false, tUp: false, tDown: false,
      partial() { return {}; },
      update(dt) {
        if (this.done) return;
        this.time -= dt;
        if (this.tUp) this.t = clamp(this.t + dt * 0.5, 0, 1);
        if (this.tDown) this.t = clamp(this.t - dt * 0.5, 0, 1);
        this.t = clamp(this.t + (Math.random() - 0.5) * dt * 0.08, 0, 1);  // napięcie lekko pływa
        this.noiseT -= dt;
        for (let i = 0; i < pins; i++) this.jig[i] *= 0.85;
        if (this.time <= 0) { this.done = true; Snd.thunk(0.3); setTimeout(() => api.finish({ ok: false }), 300); }
      },
      stroke() {
        if (this.noiseT <= 0) { api.noise(25, 'grabie'); this.noiseT = 0.4; }
        Snd.rattle();
        for (let i = this.set; i < pins; i++) this.jig[i] = 6 + Math.random() * 14;
        const inZone = this.t > 0.35 && this.t < 0.65;
        if (!inZone) { if (this.t > 0.8 && this.set > 0 && Math.random() < 0.3) { this.set--; Snd.tick(0.1); } return; }
        const q = 1 - Math.abs(this.t - 0.5) * 3;
        if (Math.random() < chance * q) {
          this.set++; Snd.pinSet();
          if (this.set >= pins) { this.done = true; Snd.open(); setTimeout(() => api.finish({ ok: true }), 450); }
        }
      },
      down(pt) { this.pressing = true; this.lastX = pt.x; this.dir = 0; this.amp = 0; },
      move(pt) {
        this.pinX = clamp(pt.x, 220, 580);
        if (!this.pressing || this.done) return;
        const dx = pt.x - this.lastX;
        const d = Math.sign(dx);
        if (d !== 0) {
          if (d !== this.dir) { if (this.amp > 60) this.stroke(); this.dir = d; this.amp = 0; }
          this.amp += Math.abs(dx);
        }
        this.lastX = pt.x;
      },
      up() { this.pressing = false; },
      wheel(dy) { this.t = clamp(this.t + (dy > 0 ? -0.04 : 0.04), 0, 1); },
      key(e, down) { const k = e.key.toLowerCase(); if (k === 'w') { this.tUp = down; return true; } if (k === 's') { this.tDown = down; return true; } return false; },
      draw(c) {
        c.fillStyle = '#0b1014'; c.fillRect(0, 0, 800, 600);
        // przekrój uproszczony
        let gr = c.createLinearGradient(0, 180, 0, 300); gr.addColorStop(0, '#7a868f'); gr.addColorStop(1, '#46515a');
        c.fillStyle = gr; c.fillRect(200, 180, 400, 120);
        gr = c.createLinearGradient(0, 300, 0, 400); gr.addColorStop(0, '#e7c170'); gr.addColorStop(1, '#8a6a2c');
        c.fillStyle = gr; c.fillRect(200, 300, 400, 100);
        c.fillStyle = '#0a0d10'; c.fillRect(200, 360, 420, 28);
        for (let i = 0; i < pins; i++) {
          const x = 240 + i * (320 / Math.max(1, pins - 1));
          const set = i < this.set;
          const lift = set ? 0 : this.jig[i];
          c.fillStyle = '#20262b'; c.fillRect(x - 12, 186, 24, 114);
          c.fillStyle = set ? COL.brass : '#d7dde2'; rr(c, x - 10, set ? 262 : 270 - lift, 20, 30, 3); c.fill();
          c.fillStyle = '#c8843a'; rr(c, x - 10, 302 - lift, 20, 50, 3); c.fill();
        }
        c.setLineDash([6, 5]); c.strokeStyle = 'rgba(246,217,146,.55)'; c.beginPath(); c.moveTo(200, 300); c.lineTo(600, 300); c.stroke(); c.setLineDash([]);
        // grabie
        const x = this.pinX;
        c.fillStyle = '#dfe5e9'; c.beginPath(); c.moveTo(800, 372); c.lineTo(x + 8, 372);
        for (let k = 0; k < 3; k++) { const x0 = x - k * 26; c.quadraticCurveTo(x0 - 4, this.pressing ? 352 : 358, x0 - 13, 370); c.quadraticCurveTo(x0 - 20, this.pressing ? 352 : 358, x0 - 26, 370); }
        c.lineTo(x - 80, 376); c.lineTo(800, 376); c.closePath(); c.fill();
        // napięcie
        c.fillStyle = 'rgba(255,255,255,.07)'; rr(c, 120, 180, 18, 220, 4); c.fill();
        c.fillStyle = 'rgba(120,211,154,.28)'; c.fillRect(120, 400 - 220 * 0.65, 18, 220 * 0.3);
        c.fillStyle = COL.brass; c.fillRect(120, 400 - 220 * this.t, 18, 220 * this.t);
        c.font = `500 11px ${FM}`; c.fillStyle = COL.muted; c.textAlign = 'center';
        c.fillText('NAPIĘCIE', 129, 420);
        c.fillText(`piny ${this.set}/${pins} · czas ${Math.max(0, Math.ceil(this.time))} s`, 400, 470);
      },
    };
    return g;
  },
};
