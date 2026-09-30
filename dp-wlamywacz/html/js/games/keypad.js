/* ZAM-06 / ZAB-11 – klawiatura panelu alarmu (albo sejfu meblowego, ZAM-12).
   Latarka (F) pokazuje starte klawisze – cyfry kodu bez kolejności. Kod sprawdza serwer,
   więc gra oddaje tylko wpisane cyfry. Przy alarmie widać odliczanie opóźnienia wejścia. */
'use strict';
Games.keypad = {
  title: (p) => (p.furniture ? 'Sejf meblowy' : 'Panel alarmu'),
  sub: (p) => (p.siren ? 'SYRENA WYJE' : p.delay > 0 ? `opóźnienie wejścia: ${Math.ceil(p.delay)} s` : ''),
  help: () => 'Klikaj klawisze albo pisz cyfry, <kbd>Enter</kbd> zatwierdza, <kbd>Backspace</kbd> czyści. <kbd>F</kbd> – poświeć latarką na klawiaturę.',
  create(p, api) {
    const KEYS = ['1', '2', '3', '4', '5', '6', '7', '8', '9', 'C', '0', 'OK'];
    const rng = api.rng;
    const smudge = {};
    for (const ch of String(p.smudge || '')) smudge[ch] = { a: 0.6 + rng() * 0.3, rot: rng() * TAU, seed: Math.floor(rng() * 1e6) };
    smudge.OK = { a: 0.9, rot: rng() * TAU, seed: Math.floor(rng() * 1e6) };
    const rect = (i) => { const col = i % 3, row = Math.floor(i / 3); return { x: 281 + col * 84, y: 196 + row * 76, w: 70, h: 62 }; };
    const g = {
      entry: '', left: p.delay || 0, light: false, lx: 400, ly: 330, pressed: -1, pressT: 0, beepT: 0, done: false,
      partial() { return {}; },
      update(dt) {
        this.pressT = Math.max(0, this.pressT - dt);
        if (this.left > 0 && !this.done) {
          this.left -= dt; this.beepT -= dt;
          if (this.beepT <= 0) { Snd.beep(this.left < 10 ? 1900 : 1500, 0.05, 0.06); this.beepT = this.left < 10 ? 0.5 : 1; }
          if (this.left <= 0) { this.done = true; api.finish({ ok: false, timeout: true }); }
        }
      },
      press(k) {
        if (this.done) return;
        Snd.beep(1250, 0.06, 0.09);
        this.pressed = KEYS.indexOf(k); this.pressT = 0.12;
        if (k === 'C') this.entry = '';
        else if (k === 'OK') {
          if (this.entry.length < (p.len || 4)) { Snd.beep(600, 0.15, 0.09); return; }
          this.done = true;
          api.finish({ ok: true, code: this.entry });
        } else if (this.entry.length < (p.len || 4)) this.entry += k;
      },
      hit(pt) { for (let i = 0; i < 12; i++) { const r = rect(i); if (pt.x >= r.x && pt.x <= r.x + r.w && pt.y >= r.y && pt.y <= r.y + r.h) return KEYS[i]; } return null; },
      down(pt) { const k = this.hit(pt); if (k) this.press(k); },
      move(pt) { this.lx = pt.x; this.ly = pt.y; },
      key(e, down) {
        if (!down || e.repeat) return false;
        if (/^[0-9]$/.test(e.key)) { this.press(e.key); return true; }
        if (e.key === 'Enter') { this.press('OK'); return true; }
        if (e.key === 'Backspace' || e.key === 'Delete') { this.press('C'); return true; }
        if (e.key.toLowerCase() === 'f') { this.light = !this.light; Snd.click(0.15); return true; }
        return false;
      },
      draw(c) {
        c.fillStyle = '#2a3035'; c.fillRect(0, 0, 800, 600);
        c.fillStyle = 'rgba(0,0,0,.4)'; rr(c, 262, 64, 288, 492, 18); c.fill();
        const pg = c.createLinearGradient(250, 50, 550, 550); pg.addColorStop(0, '#eeeeea'); pg.addColorStop(1, '#bdbfb9');
        c.fillStyle = pg; rr(c, 252, 54, 296, 490, 18); c.fill();
        c.font = `600 12px ${FM}`; c.fillStyle = '#6b6f6a'; c.textAlign = 'left'; c.fillText(p.furniture ? 'SAFE-BOX' : 'SECURIX 3000', 276, 82);
        c.fillStyle = '#231d0d'; rr(c, 278, 92, 244, 76, 6); c.fill();
        c.fillStyle = '#f0c35a'; c.font = `500 15px ${FM}`;
        c.fillText(p.siren ? 'ALARM!' : this.left > 0 ? `UZBROJONY  00:${pad2(Math.ceil(this.left))}` : (p.furniture ? 'PODAJ KOD' : 'UZBROJONY'), 292, 124);
        c.font = `500 20px ${FM}`;
        c.fillText(('*'.repeat(this.entry.length) + '_'.repeat((p.len || 4) - this.entry.length)).split('').join(' '), 292, 154);
        c.fillStyle = (this.left > 0 && (performance.now() / 500 | 0) % 2) || p.siren ? COL.bad : '#5a1d17'; circle(c, 500, 78, 6); c.fill();
        for (let i = 0; i < 12; i++) {
          const r = rect(i), k = KEYS[i], pr = i === this.pressed && this.pressT > 0;
          c.fillStyle = pr ? '#aeb4ae' : '#d7dad3'; rr(c, r.x, r.y + (pr ? 2 : 0), r.w, r.h, 8); c.fill();
          c.strokeStyle = 'rgba(0,0,0,.35)'; c.lineWidth = 1.5; c.stroke();
          c.fillStyle = k === 'OK' ? '#2f6b45' : k === 'C' ? '#8d3a33' : '#23282c';
          c.font = `600 ${k.length > 1 ? 18 : 24}px ${FM}`; c.textAlign = 'center'; c.textBaseline = 'middle';
          c.fillText(k === 'OK' ? '✓' : k, r.x + r.w / 2, r.y + r.h / 2 + (pr ? 2 : 0));
          c.textBaseline = 'alphabetic';
        }
        // latarka: starte klawisze widać w świetle pod kątem
        if (this.light) {
          const gl = c.createRadialGradient(this.lx, this.ly, 10, this.lx, this.ly, 150);
          gl.addColorStop(0, 'rgba(255,245,220,.18)'); gl.addColorStop(1, 'rgba(0,0,0,0)');
          c.fillStyle = gl; c.fillRect(0, 0, 800, 600);
          for (let i = 0; i < 12; i++) {
            const s = smudge[KEYS[i]]; if (!s) continue;
            const r = rect(i), x = r.x + r.w / 2, y = r.y + r.h / 2;
            const vis = s.a * clamp(1 - Math.hypot(x - this.lx, y - this.ly) / 160, 0, 1) * 0.8;
            if (vis < 0.03) continue;
            c.save(); c.translate(x, y); c.rotate(s.rot);
            c.strokeStyle = `rgba(90,80,60,${vis})`; c.lineWidth = 1.2;
            const rr2 = mulberry32(s.seed);
            for (let k = 3; k <= 20; k += 3) { const st = rr2() * TAU; c.beginPath(); c.ellipse(0, 0, k * 1.05, k * 0.8, 0, st, st + 1.5 + rr2() * 2.5); c.stroke(); }
            c.restore();
          }
        }
        c.font = `500 12px ${FM}`; c.fillStyle = COL.muted; c.textAlign = 'center';
        c.fillText(this.light ? 'latarka: przesuń mysz nad klawiszami' : 'F – poświeć latarką', 400, 580);
      },
    };
    return g;
  },
};
