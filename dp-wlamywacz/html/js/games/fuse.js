/* ZAB-18 – skrzynka z bezpiecznikami: odkręcasz 4 śruby pokrywy (przytrzymaj na każdej)
   i zrzucasz wyłącznik główny. Dom traci prąd: światła, kamery przewodowe i alarm bez akumulatora. */
'use strict';
Games.fuse = {
  title: () => 'Bezpieczniki',
  help: () => 'Przytrzymaj <kbd>LPM</kbd> na każdej śrubie, żeby ją wykręcić, potem kliknij wyłącznik główny.',
  create(p, api) {
    const screws = [[250, 130], [550, 130], [250, 470], [550, 470]].map(([x, y]) => ({ x, y, t: 0, out: false }));
    const labels = ['Kuchnia', 'Salon', 'Sypialnia', 'Łazienka', 'Garaż', 'Gniazdka', 'Oświetlenie', 'Alarm'];
    const g = {
      hold: null, cover: false, main: false, done: false,
      partial() { return {}; },
      update(dt) {
        if (this.hold && !this.hold.out) {
          this.hold.t += dt / 0.8;
          if (Math.random() < 0.25) Snd.tick(0.05);
          if (this.hold.t >= 1) { this.hold.out = true; this.hold = null; Snd.click(0.2); if (screws.every((s) => s.out)) { this.cover = true; Snd.metal(); } }
        }
      },
      down(pt) {
        if (this.done) return;
        if (!this.cover) { this.hold = screws.find((s) => !s.out && Math.hypot(pt.x - s.x, pt.y - s.y) < 22) || null; return; }
        if (pt.x > 360 && pt.x < 440 && pt.y > 180 && pt.y < 260) {
          this.main = true; this.done = true; Snd.thunk(0.6); api.noise(12, 'bezpieczniki');
          setTimeout(() => api.finish({ ok: true }), 600);
        }
      },
      up() { this.hold = null; },
      draw(c) {
        c.fillStyle = '#1c2227'; c.fillRect(0, 0, 800, 600);
        const gr = c.createLinearGradient(220, 100, 580, 500); gr.addColorStop(0, '#5a646b'); gr.addColorStop(1, '#2f373d');
        c.fillStyle = gr; rr(c, 220, 100, 360, 400, 10); c.fill();
        if (!this.cover) {
          c.fillStyle = 'rgba(0,0,0,.2)'; rr(c, 236, 116, 328, 368, 8); c.fill();
          c.font = `700 22px ${FD}`; c.fillStyle = COL.warn; c.textAlign = 'center'; c.fillText('UWAGA – 230 V', 400, 300);
          for (const s of screws) {
            if (!s.out) screw(c, s.x, s.y, s.t * 6);
            if (s.t > 0 && !s.out) { c.strokeStyle = COL.brass; c.lineWidth = 3; c.beginPath(); c.arc(s.x, s.y, 14, -Math.PI / 2, -Math.PI / 2 + TAU * s.t); c.stroke(); }
          }
        } else {
          c.fillStyle = '#15191c'; rr(c, 236, 116, 328, 368, 8); c.fill();
          c.fillStyle = this.main ? '#3a4046' : COL.bad; rr(c, 370, 180, 60, 80, 6); c.fill();
          c.font = `600 12px ${FM}`; c.fillStyle = COL.paper; c.textAlign = 'center'; c.fillText(this.main ? 'OFF' : 'GŁÓWNY', 400, 276);
          labels.forEach((l, i) => {
            const x = 262 + (i % 4) * 76, y = 310 + Math.floor(i / 4) * 80;
            c.fillStyle = this.main ? '#3a4046' : '#cfd6db'; rr(c, x, y, 34, 50, 4); c.fill();
            c.fillStyle = COL.muted; c.font = `500 10px ${FM}`; c.fillText(l, x + 17, y + 66);
          });
        }
      },
    };
    return g;
  },
};
