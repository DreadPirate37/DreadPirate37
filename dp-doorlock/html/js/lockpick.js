'use strict';
/* ==========================================================================
   Minigra: wytrych (zamek bębenkowy w przekroju)
   • ruch myszy w poziomie – wybór zapadki,
   • LPM – unoszenie zapadki; puść, gdy szczelina między bolcami zrówna się
     z linią ścinania (złota linia),
   • tylko jedna zapadka naraz „wiąże” – unosi się wolniej i lekko drga,
   • przestawienie (za wysoko) nadwyręża wytrych.
   Pętla rAF działa tylko, gdy gra jest otwarta.
   ========================================================================== */
DL.Lockpick = (() => {
  const VW = 1000, VH = 540;
  const SHEAR = 262, PLUG_BOTTOM = 408, CH_TOP = 124;
  let g = null;

  const msg = (text, cls) => {
    const m = g.ui.msg;
    m.textContent = text;
    m.className = 'g-msg show ' + cls;
    clearTimeout(g.msgT);
    g.msgT = setTimeout(() => (m.className = 'g-msg ' + cls), 1100);
  };

  const hud = () => {
    g.ui.pins.forEach((p, i) => p.classList.toggle('on', i < g.set));
    g.ui.hp.style.transform = `scaleX(${g.hp / 100})`;
    g.ui.hpv.textContent = Math.round(g.hp) + '%';
  };

  const finish = win => {
    if (g.over) return;
    g.over = true;
    const end = DL.h('div.g-end.' + (win ? 'win' : 'lose'));
    end.innerHTML = `<div class="box"><div class="big">${DL.icon(win ? 'unlock' : 'x')}</div><b>${win ? 'Zamek otwarty' : g.hp <= 0 ? 'Wytrych pękł' : 'Czas minął'}</b><span>${win ? 'Bębenek obrócony' : 'Spróbuj ponownie'}</span></div>`;
    setTimeout(() => { if (g) { g.box.append(end); } }, win ? 700 : 150);
    if (win) DL.Audio.play('turn'); else DL.Audio.play('snap');
    setTimeout(() => close(win), win ? 2000 : 1500);
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

  /* ---------------- rysowanie ---------------- */
  const pinX = i => g.x0 + i * g.gap;

  const drawBg = c => {
    const bg = c.createRadialGradient(VW / 2, VH / 2, 60, VW / 2, VH / 2, 620);
    bg.addColorStop(0, '#1a2033'); bg.addColorStop(1, '#07080d');
    c.fillStyle = bg; c.fillRect(0, 0, VW, VH);
    c.strokeStyle = 'rgba(255,255,255,.025)'; c.lineWidth = 1;
    for (let x = 0; x < VW; x += 40) { c.beginPath(); c.moveTo(x, 0); c.lineTo(x, VH); c.stroke(); }
    for (let y = 0; y < VH; y += 40) { c.beginPath(); c.moveTo(0, y); c.lineTo(VW, y); c.stroke(); }
  };

  const rr = (c, x, y, w, h, r) => { c.beginPath(); c.moveTo(x + r, y); c.arcTo(x + w, y, x + w, y + h, r); c.arcTo(x + w, y + h, x, y + h, r); c.arcTo(x, y + h, x, y, r); c.arcTo(x, y, x + w, y, r); c.closePath(); };

  const brass = (c, y0, y1, light) => {
    const gr = c.createLinearGradient(0, y0, 0, y1);
    if (light) { gr.addColorStop(0, '#f3d58a'); gr.addColorStop(.45, '#c99a3e'); gr.addColorStop(1, '#7d5a1c'); }
    else { gr.addColorStop(0, '#b88a36'); gr.addColorStop(.5, '#8a6424'); gr.addColorStop(1, '#5b3f12'); }
    return gr;
  };

  const draw = t => {
    const c = g.ctx;
    drawBg(c);
    const L = g.x0 - 70, R = pinX(g.n - 1) + 90;
    const jitter = g.lifting && g.sel === g.order[g.set] ? Math.sin(t / 18) * 0.8 : 0;

    // obudowa
    c.save();
    c.shadowColor = 'rgba(0,0,0,.6)'; c.shadowBlur = 40; c.shadowOffsetY = 18;
    rr(c, L, CH_TOP - 24, R - L, PLUG_BOTTOM - CH_TOP + 48, 28);
    c.fillStyle = brass(c, CH_TOP - 24, PLUG_BOTTOM + 24, false); c.fill();
    c.restore();
    c.strokeStyle = 'rgba(255,230,160,.25)'; c.lineWidth = 1.5; rr(c, L, CH_TOP - 24, R - L, PLUG_BOTTOM - CH_TOP + 48, 28); c.stroke();

    // bębenek (obraca się lekko wraz z postępem)
    c.save();
    const rot = g.turn;
    c.translate(0, rot * 6 + jitter);
    rr(c, L + 20, SHEAR, R - L - 40, PLUG_BOTTOM - SHEAR, 18);
    c.fillStyle = brass(c, SHEAR, PLUG_BOTTOM, true); c.fill();
    c.fillStyle = 'rgba(255,255,255,.18)'; c.fillRect(L + 34, SHEAR + 6, R - L - 68, 3);
    // kanał klucza
    c.fillStyle = '#0d0a05';
    rr(c, L + 20, PLUG_BOTTOM - 44, R - L - 60, 26, 10); c.fill();
    c.restore();

    // linia ścinania
    c.save();
    c.setLineDash([10, 8]); c.lineDashOffset = -t / 40;
    c.strokeStyle = 'rgba(255, 214, 120, .9)'; c.lineWidth = 2;
    c.shadowColor = '#ffd678'; c.shadowBlur = 12;
    c.beginPath(); c.moveTo(L + 10, SHEAR); c.lineTo(R - 10, SHEAR); c.stroke();
    c.restore();

    // komory i zapadki
    for (let i = 0; i < g.n; i++) {
      const x = pinX(i), p = g.pins[i];
      const h = p.set ? 0 : p.h;
      // komora
      c.fillStyle = '#120d05';
      rr(c, x - 21, CH_TOP, 42, PLUG_BOTTOM - 44 - CH_TOP, 8); c.fill();
      const keyTop = PLUG_BOTTOM - 44 - p.len - h;
      const drvBottom = p.set ? SHEAR : keyTop;
      const drvTop = drvBottom - p.drv;
      // sprężyna
      c.strokeStyle = '#9aa3b8'; c.lineWidth = 2.2; c.beginPath();
      const coils = 7, sTop = CH_TOP + 6, sLen = drvTop - sTop;
      for (let k = 0; k <= coils * 2; k++) {
        const yy = sTop + (sLen * k) / (coils * 2);
        const xx = x + (k % 2 ? 12 : -12);
        k ? c.lineTo(xx, yy) : c.moveTo(x, yy);
      }
      c.stroke();
      // bolec górny (stal)
      const st = c.createLinearGradient(x - 16, 0, x + 16, 0);
      st.addColorStop(0, '#6d7488'); st.addColorStop(.4, '#e3e7f0'); st.addColorStop(1, '#5b6173');
      c.fillStyle = st; rr(c, x - 16, drvTop, 32, p.drv, 5); c.fill();
      // bolec dolny (mosiądz, zaostrzony)
      const bk = c.createLinearGradient(x - 16, 0, x + 16, 0);
      bk.addColorStop(0, '#8a6424'); bk.addColorStop(.45, '#ffe3a0'); bk.addColorStop(1, '#7a5519');
      c.fillStyle = bk;
      const kt = p.set ? PLUG_BOTTOM - 44 - p.len : keyTop;
      c.beginPath();
      c.moveTo(x - 16, kt + 4); c.quadraticCurveTo(x - 16, kt, x - 12, kt);
      c.lineTo(x + 12, kt); c.quadraticCurveTo(x + 16, kt, x + 16, kt + 4);
      c.lineTo(x + 16, kt + p.len - 10); c.lineTo(x, kt + p.len); c.lineTo(x - 16, kt + p.len - 10); c.closePath(); c.fill();
      // podświetlenie wybranej / ustawionej
      if (p.set) {
        c.save(); c.shadowColor = '#2fe3a4'; c.shadowBlur = 18; c.strokeStyle = 'rgba(47,227,164,.9)'; c.lineWidth = 2;
        rr(c, x - 17, drvTop - 1, 34, p.drv + 2, 6); c.stroke(); c.restore();
      } else if (i === g.sel) {
        c.save(); c.shadowColor = 'rgba(61,214,245,.9)'; c.shadowBlur = 14; c.strokeStyle = 'rgba(61,214,245,.7)'; c.lineWidth = 1.5;
        rr(c, x - 21, CH_TOP, 42, PLUG_BOTTOM - 44 - CH_TOP, 8); c.stroke(); c.restore();
      }
    }

    // napinacz (dół, lewa strona)
    c.save();
    c.translate(L + 36, PLUG_BOTTOM - 26);
    c.rotate(-0.06 - g.turn * 0.25);
    c.fillStyle = '#c9cfdd';
    rr(c, -120, -6, 130, 12, 4); c.fill();
    rr(c, -2, -6, 12, 34, 4); c.fill();
    c.restore();

    // wytrych: trzon leży w kanale klucza, unosi się tylko haczyk
    const tipX = g.pickX, sel = g.pins[g.sel];
    const lift = g.lifting && sel && !sel.set ? sel.h : 0;
    const keyway = PLUG_BOTTOM - 31;
    const tipY = PLUG_BOTTOM - 44 - lift + (g.lifting ? jitter : 0);
    c.save();
    c.shadowColor = 'rgba(0,0,0,.6)'; c.shadowBlur = 8; c.shadowOffsetY = 3;
    c.lineCap = 'round'; c.lineJoin = 'round';
    const steel = c.createLinearGradient(0, keyway - 5, 0, keyway + 5);
    steel.addColorStop(0, '#f2f4f8'); steel.addColorStop(1, '#8a91a6');
    c.strokeStyle = steel; c.lineWidth = 7;
    c.beginPath();
    c.moveTo(L - 60, keyway);
    c.lineTo(tipX - 22, keyway);
    c.quadraticCurveTo(tipX - 2, keyway, tipX, tipY + 4);
    c.stroke();
    c.fillStyle = '#eef1f7';
    c.beginPath(); c.arc(tipX, tipY + 3, 4.5, 0, Math.PI * 2); c.fill();
    c.restore();
    // rękojeść
    const hd = c.createLinearGradient(0, keyway - 11, 0, keyway + 11);
    hd.addColorStop(0, '#3a4262'); hd.addColorStop(1, '#161a2a');
    c.fillStyle = hd; rr(c, L - 190, keyway - 11, 140, 22, 11); c.fill();
    c.fillStyle = 'rgba(255,255,255,.08)'; rr(c, L - 180, keyway - 8, 120, 4, 2); c.fill();
  };

  /* ---------------- logika ---------------- */
  const loop = t => {
    if (!g) return;
    const dt = Math.min(0.05, (t - (g.last || t)) / 1000);
    g.last = t;
    g.pickX = DL.lerp(g.pickX, pinX(g.sel), Math.min(1, dt * 14));
    const p = g.pins[g.sel];
    const binding = g.sel === g.order[g.set];
    if (!g.over) {
      if (g.lifting && p && !p.set) {
        const speed = binding ? g.slow : 210;
        p.h = Math.min(g.hMax, p.h + speed * dt);
        if (binding && (g.clickAcc += dt) > 0.12) { g.clickAcc = 0; DL.Audio.play('pin', 0.35); }
        if (!binding && p.h >= g.hMax && !p.maxed) { p.maxed = true; g.hp -= 2 * g.dmg; hud(); DL.Audio.play('pin', 0.6); }
      }
      for (let i = 0; i < g.n; i++) {
        const q = g.pins[i];
        if (!q.set && !(g.lifting && i === g.sel) && q.h > 0) q.h = Math.max(0, q.h - 420 * dt);
      }
      if (g.set === g.n) g.turn = Math.min(1, g.turn + dt * 2.2);
      else g.turn = DL.lerp(g.turn, (g.set / g.n) * 0.25, dt * 6);
      if (g.hp <= 0) finish(false);
    }
    draw(t);
    g.raf = requestAnimationFrame(loop);
  };

  const release = () => {
    if (!g || !g.lifting) return;
    g.lifting = false;
    const p = g.pins[g.sel];
    if (!p || p.set || g.over) return;
    p.maxed = false;
    const binding = g.sel === g.order[g.set];
    if (!binding) { if (p.h > 10) DL.Audio.play('pin', 0.4); return; }
    const d = p.h - p.target;
    if (Math.abs(d) <= g.tol) {
      p.set = true; p.h = 0; g.set++;
      DL.Audio.play('set');
      msg(g.set === g.n ? 'Wszystkie zapadki!' : 'Zapadka ustawiona', 'good');
      hud();
      if (g.set === g.n) finish(true);
    } else if (d > g.tol) {
      g.hp -= 20 * g.dmg;
      DL.Audio.play('snap', 0.4);
      msg('Przestawiona – za wysoko!', 'bad');
      hud();
    } else if (p.h > 8) {
      msg('Za nisko…', 'warn');
    }
  };

  const open = d => {
    const rnd = DL.rng(d.seed || 1);
    const n = d.pins || 4, diff = d.difficulty || 2;
    const box = DL.h('div.game.lockpick');
    box.innerHTML = `
      <canvas width="${VW}" height="${VH}"></canvas>
      <div class="g-top">
        <div class="ttl"><div class="bdg">${DL.icon('pick')}</div><div><b>${d.advanced ? 'Zaawansowany wytrych' : 'Wytrych'}</b><span>Zamek bębenkowy · trudność ${diff}/5</span></div></div>
        <div class="g-stat">
          <div class="st"><small>Zapadki</small><div class="pins">${'<i></i>'.repeat(n)}</div></div>
          <div class="st"><small>Wytrych <em class="hpv">100%</em></small><div class="bar hp"><i></i></div></div>
          <div class="g-time"></div>
        </div>
      </div>
      <div class="g-msg"></div>
      <div class="g-foot"><span><kbd>MYSZ</kbd>wybór zapadki</span><span><kbd>LPM</kbd>przytrzymaj – unieś</span><span>Puść, gdy szczelina trafi w <b style="color:#ffd678">złotą linię</b></span><span><kbd>ESC</kbd>poddaj się</span></div>`;
    const cv = DL.$('canvas', box);
    const dpr = Math.min(2, window.devicePixelRatio || 1);
    cv.width = VW * dpr; cv.height = VH * dpr;
    const ctx = cv.getContext('2d');
    ctx.scale(dpr, dpr);

    const gap = Math.min(96, 560 / Math.max(1, n - 1));
    const x0 = VW / 2 - (gap * (n - 1)) / 2;
    const pins = [];
    for (let i = 0; i < n; i++) {
      const len = 30 + Math.round(rnd() * 48);
      pins.push({ len, drv: 34 + Math.round(rnd() * 12), h: 0, set: false, target: PLUG_BOTTOM - 44 - len - SHEAR, maxed: false });
    }
    const order = pins.map((_, i) => i);
    for (let i = order.length - 1; i > 0; i--) { const j = Math.floor(rnd() * (i + 1)); [order[i], order[j]] = [order[j], order[i]]; }

    g = {
      box, ctx, n, pins, order, x0, gap, set: 0, sel: 0, pickX: x0, lifting: false, over: false, turn: 0, clickAcc: 0,
      hp: 100, dmg: d.advanced ? 0.6 : 1, tol: [10, 8, 6.5, 5.5, 4.5][diff - 1] || 6, slow: [70, 64, 58, 54, 50][diff - 1] || 60,
      hMax: 105, time: d.time || 60,
      ui: { pins: DL.$$('.pins i', box), hp: DL.$('.bar.hp i', box), hpv: DL.$('.hpv', box), msg: DL.$('.g-msg', box), time: DL.$('.g-time', box) },
    };
    const endAt = performance.now() + g.time * 1000;
    const tick = () => {
      if (!g || g.over) return;
      const s = Math.max(0, Math.ceil((endAt - performance.now()) / 1000));
      g.ui.time.textContent = `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`;
      g.ui.time.classList.toggle('warn', s <= 10);
      if (s <= 0) finish(false);
    };
    g.iv = setInterval(tick, 250);
    tick();

    cv.addEventListener('mousemove', e => {
      if (!g || g.lifting) return;
      const r = cv.getBoundingClientRect();
      const x = ((e.clientX - r.left) / r.width) * VW;
      const i = DL.clamp(Math.round((x - g.x0) / g.gap), 0, g.n - 1);
      if (i !== g.sel) { g.sel = i; DL.Audio.play('tick', 0.4); }
    });
    cv.addEventListener('mousedown', e => { if (e.button === 0 && g && !g.over && !g.pins[g.sel].set) { g.lifting = true; g.clickAcc = 0; } });
    window.addEventListener('mouseup', release);
    DL.layer.open('game', box, () => { window.removeEventListener('mouseup', release); if (g) { cancelAnimationFrame(g.raf); clearInterval(g.iv); g = null; } });
    DL.fitGame(box);
    hud();
    g.raf = requestAnimationFrame(loop);
    DL.Audio.play('open');
  };

  const key = e => {
    if (!g) return false;
    if (e.key === 'Escape') { if (!g.over) { g.over = true; close(false); } return true; }
    return false;
  };

  return { open, key };
})();

/** Dopasowanie skali okna minigry do rozdzielczości */
DL.fitGame = box => {
  const s = Math.min(1, (window.innerWidth * 0.94) / 1000, (window.innerHeight * 0.9) / 540);
  box.style.setProperty('--gs', s.toFixed(3));
};
