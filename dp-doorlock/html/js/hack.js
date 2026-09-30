'use strict';
/* ==========================================================================
   Minigra: hakowanie czytnika – synchronizacja sygnału.
   Dopasuj swoją falę (fiolet) do sygnału czytnika (turkus) trzema
   pokrętłami: częstotliwość, amplituda, faza. Zgodność ≥ 94% utrzymana
   przez 1 s zatrzaskuje etap. Na wyższych poziomach sygnał dryfuje i szumi.
   ========================================================================== */
DL.Hack = (() => {
  const VW = 1000, VH = 540;
  const SX = 40, SY = 100, SW = 700, SH = 360;   // ekran oscyloskopu
  const SAMPLES = 140, NEED = 0.94, HOLD = 1.0;
  let g = null;

  const PARAMS = [
    { k: 'f', label: 'Częstotliwość', keys: 'A / D', min: 1, max: 6, step: 0.03, fmt: v => v.toFixed(2) + ' Hz' },
    { k: 'a', label: 'Amplituda', keys: 'S / W', min: 0.15, max: 1, step: 0.008, fmt: v => Math.round(v * 100) + '%' },
    { k: 'p', label: 'Faza', keys: 'Q / E', min: 0, max: Math.PI * 2, step: 0.035, wrap: true, fmt: v => Math.round((v * 180) / Math.PI) + '°' },
  ];
  const KEYMAP = { a: ['f', -1], d: ['f', 1], s: ['a', -1], w: ['a', 1], q: ['p', -1], e: ['p', 1] };

  const wave = (x, w, t = 0) => w.a * Math.sin(x * Math.PI * 2 * w.f + w.p + t);

  const newTarget = () => {
    const r = g.rnd;
    g.target = { f: 1.4 + r() * 4.2, a: 0.3 + r() * 0.65, p: r() * Math.PI * 2 };
    g.me = { f: g.target.f > 3.5 ? 1.2 + r() : 4.5 + r(), a: g.target.a > 0.6 ? 0.25 : 0.95, p: (g.target.p + Math.PI * (0.6 + r() * 0.8)) % (Math.PI * 2) };
    g.hold = 0;
    renderKnobs();
  };

  const match = () => {
    let err = 0;
    const drift = g.drift * g.time;
    for (let i = 0; i < SAMPLES; i++) {
      const x = i / (SAMPLES - 1);
      err += Math.abs(wave(x, g.me) - wave(x, g.target, drift));
    }
    return DL.clamp(1 - err / SAMPLES / 1.1, 0, 1);
  };

  const renderKnobs = () => {
    PARAMS.forEach((P, i) => {
      const v = g.me[P.k];
      const frac = (v - P.min) / (P.max - P.min);
      g.ui.knobs[i].dial.style.transform = `rotate(${-135 + frac * 270}deg)`;
      g.ui.knobs[i].val.textContent = P.fmt(v);
    });
  };

  const adjust = (k, dir, mult = 1) => {
    const P = PARAMS.find(p => p.k === k);
    let v = g.me[k] + P.step * dir * mult;
    if (P.wrap) v = ((v % P.max) + P.max) % P.max;
    else v = DL.clamp(v, P.min, P.max);
    g.me[k] = v;
    g.dirty = true;
  };

  const msg = (text, cls) => {
    const m = g.ui.msg;
    m.textContent = text;
    m.className = 'g-msg show ' + cls;
    clearTimeout(g.msgT);
    g.msgT = setTimeout(() => (m.className = 'g-msg ' + cls), 1200);
  };

  /* ---------------- rysowanie ---------------- */
  const draw = t => {
    const c = g.ctx;
    c.fillStyle = '#05070c'; c.fillRect(0, 0, VW, VH);
    // ekran CRT
    const scr = c.createRadialGradient(SX + SW / 2, SY + SH / 2, 40, SX + SW / 2, SY + SH / 2, SW * 0.7);
    scr.addColorStop(0, '#0b1f24'); scr.addColorStop(1, '#040a0d');
    c.fillStyle = scr;
    c.beginPath(); c.roundRect ? c.roundRect(SX, SY, SW, SH, 16) : c.rect(SX, SY, SW, SH); c.fill();
    c.save();
    c.beginPath(); c.roundRect ? c.roundRect(SX, SY, SW, SH, 16) : c.rect(SX, SY, SW, SH); c.clip();
    // siatka
    c.strokeStyle = 'rgba(61,214,245,.07)'; c.lineWidth = 1;
    for (let x = SX; x <= SX + SW; x += SW / 14) { c.beginPath(); c.moveTo(x, SY); c.lineTo(x, SY + SH); c.stroke(); }
    for (let y = SY; y <= SY + SH; y += SH / 8) { c.beginPath(); c.moveTo(SX, y); c.lineTo(SX + SW, y); c.stroke(); }
    c.strokeStyle = 'rgba(61,214,245,.18)';
    c.beginPath(); c.moveTo(SX, SY + SH / 2); c.lineTo(SX + SW, SY + SH / 2); c.stroke();

    const mid = SY + SH / 2, amp = SH * 0.42;
    const drift = g.drift * g.time;
    const line = (fn, color, width, blur, dash) => {
      c.save();
      c.strokeStyle = color; c.lineWidth = width; c.shadowColor = color; c.shadowBlur = blur;
      if (dash) c.setLineDash(dash);
      c.beginPath();
      for (let i = 0; i <= 240; i++) {
        const x = i / 240;
        const y = mid - fn(x) * amp;
        i ? c.lineTo(SX + x * SW, y) : c.moveTo(SX + x * SW, y);
      }
      c.stroke();
      c.restore();
    };
    const noise = g.noise;
    line(x => wave(x, g.target, drift) + (noise ? Math.sin(x * 97 + t / 60) * noise * 0.06 : 0), '#3dd6f5', 3, 16, [2, 0]);
    line(x => wave(x, g.me), g.m >= NEED ? '#2fe3a4' : '#a28bff', 2.5, 14);

    // przemiatająca plamka
    const sx = ((t / 1600) % 1);
    const sg = c.createLinearGradient(SX + sx * SW - 80, 0, SX + sx * SW, 0);
    sg.addColorStop(0, 'rgba(61,214,245,0)'); sg.addColorStop(1, 'rgba(61,214,245,.08)');
    c.fillStyle = sg; c.fillRect(SX + sx * SW - 80, SY, 80, SH);
    // linie skanowania
    c.fillStyle = 'rgba(0,0,0,.18)';
    for (let y = SY; y < SY + SH; y += 3) c.fillRect(SX, y, SW, 1);
    // zakłócenie przy etapie
    if (g.glitch > 0) {
      c.fillStyle = `rgba(162,139,255,${g.glitch * 0.25})`;
      for (let k = 0; k < 6; k++) c.fillRect(SX, SY + Math.random() * SH, SW, 2 + Math.random() * 8);
    }
    c.restore();
    // ramka ekranu
    c.strokeStyle = 'rgba(61,214,245,.25)'; c.lineWidth = 1.5;
    c.beginPath(); c.roundRect ? c.roundRect(SX, SY, SW, SH, 16) : c.rect(SX, SY, SW, SH); c.stroke();

    // etykiety
    c.font = '600 11px "JetBrains Mono", monospace';
    c.fillStyle = '#3dd6f5'; c.fillText('● SYGNAŁ CZYTNIKA', SX + 16, SY + 24);
    c.fillStyle = '#a28bff'; c.fillText('● TWÓJ NADAJNIK', SX + 170, SY + 24);
    c.fillStyle = 'rgba(255,255,255,.35)';
    c.fillText(g.hex, SX + 16, SY + SH - 14);
  };

  /* ---------------- logika ---------------- */
  const loop = t => {
    if (!g) return;
    const dt = Math.min(0.05, (t - (g.last || t)) / 1000);
    g.last = t;
    if (!g.over) {
      g.time += dt;
      for (const key in g.down) if (g.down[key] && KEYMAP[key]) adjust(KEYMAP[key][0], KEYMAP[key][1], g.fine ? 0.35 : 1);
      if (g.dirty) { renderKnobs(); g.dirty = false; }
      g.m = match();
      if (g.m >= NEED) {
        g.hold += dt;
        if (g.hold >= HOLD) stageDone();
      } else g.hold = Math.max(0, g.hold - dt * 2);
      g.ui.pct.textContent = Math.round(g.m * 100) + '%';
      g.ui.pct.classList.toggle('hi', g.m >= NEED);
      g.ui.bar.style.transform = `scaleX(${g.m})`;
      g.ui.hold.style.transform = `scaleX(${Math.min(1, g.hold / HOLD)})`;
      if ((g.hexT += dt) > 0.12) { g.hexT = 0; g.hex = Array.from({ length: 12 }, () => Math.floor(Math.random() * 256).toString(16).padStart(2, '0')).join(' ').toUpperCase(); }
    }
    g.glitch = Math.max(0, g.glitch - dt * 2);
    draw(t);
    g.raf = requestAnimationFrame(loop);
  };

  const stageDone = () => {
    g.stage++;
    g.ui.stages.forEach((s, i) => s.classList.toggle('on', i < g.stage));
    g.glitch = 1;
    DL.Audio.play('lockin');
    if (g.stage >= g.stages) return finish(true);
    msg(`Etap ${g.stage}/${g.stages} zsynchronizowany`, 'good');
    DL.Audio.play('glitch');
    newTarget();
  };

  const finish = win => {
    if (g.over) return;
    g.over = true;
    const end = DL.h('div.g-end.' + (win ? 'win' : 'lose'));
    end.innerHTML = `<div class="box"><div class="big">${DL.icon(win ? 'chip' : 'x')}</div><b>${win ? 'Dostęp uzyskany' : 'Połączenie zerwane'}</b><span>${win ? 'Czytnik przejęty – zamek zwolniony' : 'Czytnik zablokował sesję'}</span></div>`;
    g.box.append(end);
    DL.Audio.play(win ? 'ok' : 'error');
    setTimeout(() => close(win), 1700);
  };

  const close = win => {
    if (!g) return;
    const done = g;
    g = null;
    cancelAnimationFrame(done.raf);
    clearInterval(done.iv);
    DL.layer.close(true);
    DL.post('gameDone', { success: !!win });
  };

  const open = d => {
    const diff = d.difficulty || 2, stages = d.stages || 2;
    const box = DL.h('div.game.hack');
    box.innerHTML = `
      <canvas></canvas>
      <div class="g-top">
        <div class="ttl"><div class="bdg">${DL.icon('chip')}</div><div><b>Włamanie do czytnika</b><span>Synchronizacja sygnału · trudność ${diff}/5</span></div></div>
        <div class="g-stat">
          <div class="st"><small>Etapy</small><div class="pins">${'<i></i>'.repeat(stages)}</div></div>
          <div class="g-time"></div>
        </div>
      </div>
      <div class="g-msg"></div>
      <div class="hk-side"></div>
      <div class="g-foot"><span><kbd>A</kbd><kbd>D</kbd>częstotliwość</span><span><kbd>S</kbd><kbd>W</kbd>amplituda</span><span><kbd>Q</kbd><kbd>E</kbd>faza</span><span><kbd>SHIFT</kbd>precyzja</span><span><kbd>ESC</kbd>rozłącz</span></div>`;
    const cv = DL.$('canvas', box);
    const dpr = Math.min(2, window.devicePixelRatio || 1);
    cv.width = VW * dpr; cv.height = VH * dpr;
    const ctx = cv.getContext('2d');
    ctx.scale(dpr, dpr);

    const side = DL.$('.hk-side', box);
    const knobs = PARAMS.map(P => {
      const el = DL.h('div.knob');
      el.innerHTML = `<div class="dial"><i></i></div><div class="kv"><b>${P.label}</b><em></em><small>${P.keys} · kółko myszy</small></div>`;
      side.append(el);
      el.addEventListener('wheel', e => { e.preventDefault(); adjust(P.k, e.deltaY < 0 ? 1 : -1, e.shiftKey ? 1 : 3); DL.Audio.play('tick', 0.3); }, { passive: false });
      el.addEventListener('pointerdown', e => {
        el.setPointerCapture(e.pointerId);
        let y = e.clientY;
        el.classList.add('hot');
        const mv = ev => { const dy = y - ev.clientY; y = ev.clientY; adjust(P.k, Math.sign(dy), Math.abs(dy) * 0.6); };
        const up = () => { el.classList.remove('hot'); el.removeEventListener('pointermove', mv); el.removeEventListener('pointerup', up); };
        el.addEventListener('pointermove', mv);
        el.addEventListener('pointerup', up);
      });
      return { el, dial: DL.$('.dial i', el), val: DL.$('em', el) };
    });
    const sync = DL.h('div.sync', { html: '<small>Zgodność sygnału</small><div class="pct">0%</div><div class="bar"><i></i></div><div class="hold"><i></i></div>' });
    side.append(sync);

    g = {
      box, ctx, rnd: DL.rng(d.seed || 1), stage: 0, stages, time: 0, over: false, m: 0, hold: 0, glitch: 0, hex: '', hexT: 0,
      drift: diff >= 3 ? 0.35 + (diff - 3) * 0.25 : 0, noise: diff >= 4 ? (diff - 3) : 0, down: {}, fine: false,
      ui: { knobs, msg: DL.$('.g-msg', box), time: DL.$('.g-time', box), stages: DL.$$('.pins i', box),
        pct: DL.$('.pct', sync), bar: DL.$('.bar i', sync), hold: DL.$('.hold i', sync) },
    };
    newTarget();
    const endAt = performance.now() + (d.time || 45) * 1000;
    const tick = () => {
      if (!g || g.over) return;
      const s = Math.max(0, Math.ceil((endAt - performance.now()) / 1000));
      g.ui.time.textContent = `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`;
      g.ui.time.classList.toggle('warn', s <= 10);
      if (s <= 0) finish(false);
    };
    g.iv = setInterval(tick, 250);
    tick();
    DL.layer.open('game', box, () => { if (g) { cancelAnimationFrame(g.raf); clearInterval(g.iv); g = null; } });
    DL.fitGame(box);
    g.raf = requestAnimationFrame(loop);
    DL.Audio.play('glitch');
  };

  const key = (e, down) => {
    if (!g) return false;
    if (e.key === 'Escape' && down) { if (!g.over) { g.over = true; close(false); } return true; }
    if (e.key === 'Shift') { g.fine = down; return true; }
    const k = e.key.toLowerCase();
    if (KEYMAP[k]) { g.down[k] = down; return true; }
    return false;
  };

  return { open, key };
})();
