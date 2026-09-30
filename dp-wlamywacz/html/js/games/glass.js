/* WEJ-05 – wycinanie szyby: prowadzisz nóż po okręgu. Zbyt duże odchylenie = pęknięcie
   (hałas 30); trzy pęknięcia i szyba idzie w drobny mak. Pełen okrąg + przyssawka = otwarte. */
'use strict';
Games.glass = {
  title: () => 'Nóż do szkła',
  help: () => 'Przytrzymaj <kbd>LPM</kbd> na przerywanej linii i prowadź nóż po okręgu. Po pełnym okręgu kliknij środek, żeby wyjąć szybę przyssawką.',
  create(p, api) {
    const R = 120, cx = 400, cy = 290;
    const g = {
      drawing: false, lastA: null, travel: 0, cracks: 0, path: [], cut: false, done: false, err: 0,
      partial() { return {}; },
      update() {},
      angleOf(pt) { return Math.atan2(pt.y - cy, pt.x - cx); },
      down(pt) {
        if (this.cut) {
          if (Math.hypot(pt.x - cx, pt.y - cy) < R * 0.7 && !this.done) { this.done = true; Snd.thunk(0.3); api.noise(8, 'szkło'); setTimeout(() => api.finish({ ok: true }), 400); }
          return;
        }
        this.drawing = true; this.lastA = this.angleOf(pt);
      },
      move(pt) {
        if (!this.drawing || this.cut || this.done) return;
        const dist = Math.hypot(pt.x - cx, pt.y - cy);
        const e = Math.abs(dist - R);
        this.err = e;
        if (e > 38) {
          this.cracks++; this.drawing = false; Snd.glass(); api.noise(30, 'szkło');
          if (this.cracks >= 3) { this.done = true; setTimeout(() => api.finish({ ok: false }), 450); }
          return;
        }
        const a = this.angleOf(pt);
        let da = a - this.lastA;
        if (da > Math.PI) da -= TAU; if (da < -Math.PI) da += TAU;
        this.travel += Math.abs(da);
        this.lastA = a;
        this.path.push([pt.x, pt.y]);
        if (Math.random() < 0.3) Snd.noise(0.03, 6000, 4, 0.05);
        if (this.travel >= TAU) { this.cut = true; this.drawing = false; Snd.tick(0.2); }
      },
      up() { this.drawing = false; },
      draw(c) {
        c.fillStyle = '#0c1216'; c.fillRect(0, 0, 800, 600);
        const gr = c.createLinearGradient(160, 60, 640, 520); gr.addColorStop(0, 'rgba(160,200,220,.18)'); gr.addColorStop(1, 'rgba(90,120,140,.08)');
        c.fillStyle = gr; c.fillRect(160, 60, 480, 460);
        c.strokeStyle = '#3b2a1c'; c.lineWidth = 16; c.strokeRect(160, 60, 480, 460);
        c.setLineDash([8, 8]); c.strokeStyle = 'rgba(236,229,212,.35)'; c.lineWidth = 2; circle(c, cx, cy, R); c.stroke(); c.setLineDash([]);
        c.strokeStyle = 'rgba(255,255,255,.75)'; c.lineWidth = 1.5; c.beginPath();
        this.path.forEach(([x, y], i) => (i ? c.lineTo(x, y) : c.moveTo(x, y))); c.stroke();
        for (let i = 0; i < this.cracks; i++) {
          c.strokeStyle = 'rgba(255,255,255,.5)'; c.beginPath();
          const a = i * 2.1 + 0.4; c.moveTo(cx + Math.cos(a) * R, cy + Math.sin(a) * R);
          for (let k = 1; k < 6; k++) c.lineTo(cx + Math.cos(a + k * 0.07) * (R + k * 22), cy + Math.sin(a + k * 0.05) * (R + k * 22));
          c.stroke();
        }
        if (this.cut) { c.fillStyle = 'rgba(167,125,255,.18)'; circle(c, cx, cy, R * 0.6); c.fill(); c.fillStyle = COL.paper; c.font = `600 14px ${FM}`; c.textAlign = 'center'; c.fillText('KLIKNIJ – PRZYSSAWKA', cx, cy + 5); }
        c.font = `500 12px ${FM}`; c.fillStyle = COL.muted; c.textAlign = 'center';
        c.fillText(`okrąg ${Math.min(100, Math.round(this.travel / TAU * 100))}% · pęknięcia ${this.cracks}/3`, 400, 560);
      },
    };
    return g;
  },
};
