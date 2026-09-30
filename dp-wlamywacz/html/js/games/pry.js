/* WEJ-06 – podważanie łomem: trzymasz LPM, żeby napierać. Rama puszcza, gdy nacisk jest
   w pulsującym oknie („pompowanie”). Za mocno = łom się ześlizguje z hukiem (70). */
'use strict';
Games.pry = {
  title: () => 'Łom',
  help: () => 'Przytrzymaj <kbd>LPM</kbd> albo <kbd>Spację</kbd>, żeby napierać, puść, żeby odpuścić. Trzymaj nacisk w jasnym oknie, które pulsuje.',
  create(p, api) {
    const diff = p.diff || 1;
    const width = diff >= 2 ? 0.12 : 0.18;
    const g = {
      press: 0, prog: 0, slips: 0, holding: false, t: 0, creakT: 0, done: false,
      partial() { return {}; },
      band() { const c = 0.55 + Math.sin(this.t * (1.6 + diff * 0.5)) * 0.2; return [c - width / 2, c + width / 2]; },
      update(dt) {
        if (this.done) return;
        this.t += dt;
        this.press = clamp(this.press + (this.holding ? 0.9 : -1.4) * dt, 0, 1.1);
        const [a, b] = this.band();
        if (this.press >= a && this.press <= b) {
          this.prog += dt * (0.32 / diff);
          if ((this.creakT -= dt) <= 0) { Snd.creak(0.12); this.creakT = 0.25; }
        }
        if (this.press > 1.0) {
          this.slips++; this.press = 0.2; this.prog = Math.max(0, this.prog - 0.3);
          Snd.metal(); api.noise(70, 'łom');
          if (this.slips >= 3) { this.done = true; setTimeout(() => api.finish({ ok: false }), 350); }
        }
        if (this.prog >= 1) { this.done = true; Snd.noise(0.25, 700, 1, 0.8, 'lowpass'); api.noise(45, 'łom'); setTimeout(() => api.finish({ ok: true }), 450); }
      },
      down() { this.holding = true; },
      up() { this.holding = false; },
      key(e, down) { if (e.key === ' ') { this.holding = down; return true; } return false; },
      draw(c) {
        let gr = c.createLinearGradient(0, 0, 800, 0); gr.addColorStop(0, '#1b140d'); gr.addColorStop(1, '#241a11');
        c.fillStyle = gr; c.fillRect(0, 0, 800, 600);
        c.fillStyle = '#3a2a1b'; c.fillRect(380, 0, 40, 600);
        const gap = 4 + this.prog * 22;
        c.fillStyle = '#060708'; c.fillRect(400 - gap / 2, 0, gap, 600);
        c.save(); c.translate(400, 300); c.rotate(-0.5 + this.press * 0.35);
        c.fillStyle = '#7a1f1a'; rr(c, 0, -8, 300, 16, 6); c.fill();
        c.fillStyle = '#aab5bd'; rr(c, -26, -6, 34, 12, 4); c.fill();
        c.restore();
        // wskaźnik nacisku i okno
        const [a, b] = this.band();
        c.fillStyle = 'rgba(255,255,255,.07)'; rr(c, 110, 120, 22, 360, 4); c.fill();
        c.fillStyle = 'rgba(120,211,154,.35)'; c.fillRect(110, 480 - 360 * b, 22, 360 * (b - a));
        c.fillStyle = this.press > 0.95 ? COL.bad : COL.brass; c.fillRect(110, 480 - 360 * Math.min(1, this.press), 22, 360 * Math.min(1, this.press));
        c.fillStyle = 'rgba(255,255,255,.07)'; rr(c, 250, 540, 300, 10, 5); c.fill();
        c.fillStyle = COL.ok; rr(c, 250, 540, 300 * this.prog, 10, 5); c.fill();
        c.font = `500 12px ${FM}`; c.fillStyle = COL.muted; c.textAlign = 'center';
        c.fillText(`NACISK`, 121, 500); c.fillText(`rama puszcza ${Math.round(this.prog * 100)}% · ześlizgnięcia ${this.slips}/3`, 400, 530);
      },
    };
    return g;
  },
};
