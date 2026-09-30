/* WYT-09 – shim do taniej kłódki: wsuwasz blaszkę w szczelinę przy pałąku, trzymając kąt
   w wąskim, pływającym oknie. Poza oknem blaszka się gnie; trzy zgięcia = porażka. */
'use strict';
Games.shim = {
  title: () => 'Shim do kłódki',
  help: () => 'Przytrzymaj <kbd>LPM</kbd> i przeciągaj w dół, żeby wsuwać shim. Ruchem w bok trzymaj kąt w zielonym oknie.',
  create(p, api) {
    const rng = api.rng;
    const g = {
      depth: 0, angle: 0, bend: 0, bends: 0, pressing: false, sy: 0, sx: 0, t: rng() * 10, done: false, guide: 0,
      partial() { return {}; },
      update(dt) {
        if (this.done) return;
        this.t += dt;
        this.guide = Math.sin(this.t * 1.3) * 14 + Math.sin(this.t * 3.1 + 1) * 6;
        const off = Math.abs(this.angle - this.guide) > 7;
        if (this.pressing && off) {
          this.bend += dt * 1.4;
          if (Math.random() < 0.2) Snd.scrape();
          if (this.bend >= 1) {
            this.bends++; this.bend = 0; this.depth = 0; Snd.metal(); api.noise(12, 'shim');
            if (this.bends >= 3) { this.done = true; setTimeout(() => api.finish({ ok: false }), 350); }
          }
        } else this.bend = Math.max(0, this.bend - dt * 0.5);
      },
      down(pt) { this.pressing = true; this.sy = pt.y; this.sx = pt.x; this.d0 = this.depth; },
      move(pt) {
        if (!this.pressing || this.done) return;
        this.angle = clamp((pt.x - this.sx) * 0.25, -30, 30);
        const off = Math.abs(this.angle - this.guide) > 7;
        if (!off) {
          this.depth = clamp(this.d0 + (pt.y - this.sy) / 220, this.depth, 1);
          if (this.depth >= 1) { this.done = true; Snd.open(); api.noise(5, 'shim'); setTimeout(() => api.finish({ ok: true }), 450); }
        } else { this.sy = pt.y - (this.depth - this.d0) * 220; }
      },
      up() { this.pressing = false; },
      draw(c) {
        c.fillStyle = '#10151a'; c.fillRect(0, 0, 800, 600);
        // pałąk i korpus kłódki
        c.strokeStyle = this.done && this.depth >= 1 ? '#aab5bd' : '#c3ccd2'; c.lineWidth = 22;
        const lift = this.done && this.depth >= 1 ? 30 : 0;
        c.beginPath(); c.moveTo(330, 300 - lift); c.lineTo(330, 190 - lift); c.arc(400, 190 - lift, 70, Math.PI, 0); c.lineTo(470, 300); c.stroke();
        const gr = c.createLinearGradient(290, 280, 510, 480); gr.addColorStop(0, '#e7c170'); gr.addColorStop(1, '#8a6a2c');
        c.fillStyle = gr; rr(c, 280, 280, 240, 200, 18); c.fill();
        c.fillStyle = '#3b2c10'; rr(c, 390, 380, 20, 40, 6); c.fill();
        // okno kąta
        c.save(); c.translate(330, 250);
        c.fillStyle = 'rgba(120,211,154,.25)';
        c.beginPath(); c.moveTo(0, 0); c.arc(0, 0, 90, (90 + this.guide - 7) * DEG, (90 + this.guide + 7) * DEG); c.closePath(); c.fill();
        c.rotate(this.angle * DEG);
        c.fillStyle = this.bend > 0.5 ? COL.bad : '#dfe5e9';
        rr(c, -3, -120 + this.depth * 130, 6, 110, 2); c.fill();
        c.restore();
        c.font = `500 12px ${FM}`; c.fillStyle = COL.muted; c.textAlign = 'center';
        c.fillText(`głębokość ${Math.round(this.depth * 100)}% · zgięcia ${this.bends}/3`, 400, 540);
      },
    };
    return g;
  },
};
