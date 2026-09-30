/* WYT-01 – wytrych „punkt” jak w Thief Simulatorze (ZAM-01 klasy A/B/C, D = meblowy).
   Obracasz wytrych, napinacz obraca bęben tym dalej, im bliżej jesteś punktu. Daleko od punktu
   wytrych drży i traci wytrzymałość (WYT-05). Kolejne etapy = kolejne punkty. */
'use strict';
Games.lockpick = {
  title: (p) => `Zamek klasy ${p.cls === 'D' ? 'meblowej' : p.cls}`,
  sub: (p) => `${p.pick || 'wytrych'} · zapas: ${Math.max(0, (p.picks || 1) - 1)}`,
  help: () => 'Mysz obraca wytrych. Przytrzymaj <kbd>LPM</kbd> albo <kbd>Spację</kbd>, żeby napiąć. <kbd>A</kbd>/<kbd>D</kbd> – obrót z klawiatury, z <kbd>Shift</kbd> precyzyjnie. Gdy bęben staje i wytrych drży – puść i przesuń.',
  create(p, api) {
    const rng = api.rng;
    const stages = p.stages || 1;
    const tol = Math.max(2, (p.tol || 10) * (1 + (p.precision || 0)));
    const fall = p.fall || 45;
    const sweet = [];
    for (let i = 0; i < stages; i++) sweet.push(Math.round(16 + rng() * 148));
    const g = {
      stage: 0, rot: 0, angle: 90, hp: p.hp || 100, maxHp: p.hp || 100, spare: Math.max(0, (p.picks || 1) - 1), broken: 0,
      shake: 0, jit: 0, bindT: 0, creakT: 0, keyDir: 0, fine: false, keyT: false, ptrT: false, done: false, open: 0,
      allowed() { const d = Math.abs(this.angle - sweet[Math.min(this.stage, stages - 1)]); return clamp(1 - Math.max(0, d - tol) / fall, 0, 1); },
      partial() { return { broken: this.broken }; },
      update(dt) {
        if (this.done) { this.open = Math.min(1, this.open + dt * 2); return; }
        if (this.keyDir) this.angle = clamp(this.angle + this.keyDir * (this.fine ? 22 : 75) * dt, 0, 180);
        const a = this.allowed();
        if (this.keyT || this.ptrT) {
          if (this.rot < a - 0.002) {
            this.rot = Math.min(a, this.rot + dt * 1.5); this.shake *= 0.85;
            if ((this.creakT -= dt) <= 0) { Snd.creak(0.04 + 0.08 * a); this.creakT = 0.12; }
          } else if (a >= 0.999) {
            this.stage++; this.rot = 0; Snd.pinSet(); api.noise(10, 'hak');
            if (this.stage >= stages) { this.done = true; Snd.open(); setTimeout(() => api.finish({ ok: true, broken: this.broken }), 500); }
          } else {
            this.rot = Math.max(a, this.rot - dt * 0.8);
            this.shake = Math.min(1, this.shake + dt * 5);
            this.hp -= (p.dmg || 25) * dt * (0.5 + 0.5 * (1 - a));
            if ((this.bindT -= dt) <= 0) { Snd.rattle(); this.bindT = 0.08; }
            if (this.hp <= 0) this.breakPick();
          }
        } else { this.rot = Math.max(0, this.rot - dt * 3.2); this.shake *= 0.8; }
        this.jit = (Math.random() - 0.5) * this.shake * 5;
      },
      breakPick() {
        Snd.snap(); api.noise(20, 'pęknięcie');
        this.broken++; this.rot = 0; this.shake = 0; this.keyT = this.ptrT = false;
        if (this.spare > 0) { this.spare--; this.hp = this.maxHp; }
        else { this.hp = 0; this.done = true; setTimeout(() => api.finish({ ok: false, broken: this.broken }), 400); }
      },
      aim(pt) { let a = Math.atan2(290 - pt.y, pt.x - 400) / DEG; if (a < 0) a = pt.x >= 400 ? 0 : 180; this.angle = clamp(a, 0, 180); },
      down(pt, e) { this.aim(pt); this.ptrT = true; },
      move(pt, e) { if (e.pointerType === 'mouse' || e.buttons) this.aim(pt); },
      up() { this.ptrT = false; },
      wheel(dy) { this.angle = clamp(this.angle + (dy > 0 ? -2 : 2), 0, 180); },
      key(e, down) {
        const k = e.key.toLowerCase();
        if (k === ' ') { this.keyT = down; return true; }
        if (k === 'a' || k === 'arrowleft') { this.keyDir = down ? 1 : (this.keyDir === 1 ? 0 : this.keyDir); return true; }
        if (k === 'd' || k === 'arrowright') { this.keyDir = down ? -1 : (this.keyDir === -1 ? 0 : this.keyDir); return true; }
        if (k === 'shift') { this.fine = down; return true; }
        return false;
      },
      draw(c) {
        const cx = 400, cy = 290;
        // drzwi i szyld
        let gr = c.createLinearGradient(0, 0, 800, 0);
        gr.addColorStop(0, '#16110c'); gr.addColorStop(0.5, '#231a12'); gr.addColorStop(1, '#140f0a');
        c.fillStyle = gr; c.fillRect(0, 0, 800, 600);
        gr = c.createLinearGradient(220, 0, 580, 0);
        gr.addColorStop(0, '#343d44'); gr.addColorStop(0.45, '#68737c'); gr.addColorStop(1, '#2b3238');
        c.fillStyle = gr; rr(c, 222, 76, 356, 440, 22); c.fill();
        screw(c, 400, 100, 0.4); screw(c, 400, 508, 1.1);
        c.fillStyle = 'rgba(20,24,28,.75)'; c.font = `500 12px ${FM}`; c.textAlign = 'center';
        c.fillText(p.cls === 'D' ? 'ZAMEK MEBLOWY' : `DP-SECURE · KL. ${p.cls}`, cx, 488);
        // obudowa i bęben
        gr = c.createRadialGradient(cx - 40, cy - 50, 20, cx, cy, 150);
        gr.addColorStop(0, '#cdd5db'); gr.addColorStop(0.55, '#7c8891'); gr.addColorStop(1, '#353f47');
        c.fillStyle = gr; circle(c, cx, cy, 150); c.fill();
        c.fillStyle = '#20262b'; circle(c, cx, cy, 113); c.fill();
        const plugA = ((Math.min(this.stage, stages) + this.rot) / stages) * 90 * DEG + this.open * 0;
        gr = c.createRadialGradient(cx - 35, cy - 40, 8, cx, cy, 110);
        gr.addColorStop(0, '#f6d992'); gr.addColorStop(0.6, COL.brass); gr.addColorStop(1, '#7c5c22');
        c.fillStyle = gr; circle(c, cx, cy, 106); c.fill();
        c.save(); c.translate(cx, cy); c.rotate(plugA);
        c.fillStyle = '#5f4516'; c.beginPath(); c.moveTo(-6, -104); c.lineTo(6, -104); c.lineTo(0, -92); c.closePath(); c.fill();
        c.fillStyle = '#0b0d0f'; c.beginPath();
        c.moveTo(-7, -64); c.lineTo(7, -64); c.lineTo(7, -30); c.lineTo(13, -18); c.lineTo(5, -4); c.lineTo(9, 18); c.lineTo(3, 30); c.lineTo(8, 64);
        c.lineTo(-8, 64); c.lineTo(-8, 34); c.lineTo(-13, 22); c.lineTo(-5, 6); c.lineTo(-10, -14); c.lineTo(-4, -28); c.lineTo(-7, -40); c.closePath(); c.fill();
        c.fillStyle = (this.keyT || this.ptrT) ? '#e6ebee' : '#9aa6ae';
        rr(c, -4, 46, 8, 150, 2); c.fill(); rr(c, -4, 188, 122, 10, 3); c.fill();
        c.restore();
        // wytrych
        const th = (this.angle + this.jit) * DEG;
        c.save(); c.translate(cx, cy); c.rotate(-th);
        c.fillStyle = this.hp > 0 ? '#d7dee3' : '#7a3a34'; rr(c, -2, -2.5, 252, 5, 2.5); c.fill();
        c.beginPath(); c.moveTo(-4, -2.5); c.quadraticCurveTo(-9, -11, -1, -12); c.lineTo(3, -2.5); c.closePath(); c.fill();
        c.fillStyle = '#2a3036'; rr(c, 196, -10, 110, 20, 7); c.fill();
        c.restore();
        // etapy i wytrzymałość
        c.font = `500 11px ${FM}`; c.fillStyle = COL.muted; c.textAlign = 'center'; c.fillText('ETAPY', cx, 46);
        for (let i = 0; i < stages; i++) {
          const x = cx - (stages - 1) * 17 + i * 34;
          circle(c, x, 66, 8);
          if (i < this.stage) { c.fillStyle = COL.brass; c.fill(); } else { c.strokeStyle = COL.muted; c.lineWidth = 1.5; c.stroke(); }
        }
        c.fillStyle = 'rgba(255,255,255,.08)'; rr(c, 300, 556, 200, 8, 4); c.fill();
        c.fillStyle = this.hp / this.maxHp < 0.3 ? COL.bad : COL.brass; rr(c, 300, 556, 200 * Math.max(0, this.hp / this.maxHp), 8, 4); c.fill();
        c.fillStyle = COL.muted; c.fillText(`wytrych · zapas ${this.spare}`, cx, 548);
      },
    };
    return g;
  },
};
