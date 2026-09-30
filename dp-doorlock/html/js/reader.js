'use strict';
/* ==========================================================================
   Czytniki: karta magnetyczna (przeciągnięcie przez szczelinę z oceną
   tempa) oraz skaner linii papilarnych (przytrzymanie palca).
   ========================================================================== */
DL.Reader = (() => {
  let cur = null;

  const result = async () => {
    const res = await DL.post('reader', { id: cur.id });
    if (!cur) return null;
    return res || { ok: false };
  };

  /* ---------------- karta ---------------- */
  const openCard = d => {
    const box = DL.h('div.device.reader');
    box.innerHTML = `
      <i class="screw tl"></i><i class="screw tr"></i><i class="screw bl"></i><i class="screw br"></i>
      <button class="dev-close">${DL.icon('x')}</button>
      <div class="dev-head"><div class="t"><b>${DL.esc(d.name)}</b><span>${DL.esc(d.group || 'Czytnik kart')}</span></div><i class="led red"></i></div>
      <div class="rd-body">
        <div class="rd-screen"><span class="s1">PRZECIĄGNIJ KARTĘ</span><span class="s2">POZ. ${d.level || 1}+</span></div>
        <div class="rd-slot"></div>
      </div>
      <div class="rd-track">
        <div class="guide"><span>start</span><i></i>${DL.icon('card')}<i></i><span>koniec</span></div>
        <div class="kcard"><div class="stripe"></div><div class="chipx"></div><div class="logo">${DL.icon('shield')}</div><div class="lbl">KARTA DOSTĘPU</div><div class="lvl">ID</div></div>
      </div>
      <div class="rd-msg">Chwyć kartę i przeciągnij ją płynnie w prawo</div>`;
    const card = DL.$('.kcard', box), track = DL.$('.rd-track', box), msg = DL.$('.rd-msg', box);
    const screen = DL.$('.rd-screen', box), s1 = DL.$('.s1', box), slot = DL.$('.rd-slot', box), led = DL.$('.led', box);
    DL.$('.dev-close', box).onclick = () => DL.layer.close();
    cur = { id: d.id, busy: false };

    let drag = null, x = 0;
    const maxX = () => track.clientWidth - card.offsetWidth;
    const place = (v, anim) => {
      x = v;
      card.style.transition = anim ? 'transform .45s cubic-bezier(.34,1.56,.64,1)' : 'none';
      card.style.transform = `translateX(${v}px) rotate(${(v / maxX() - 0.5) * 4}deg)`;
    };
    const say = (t, cls = '') => { msg.textContent = t; msg.className = 'rd-msg ' + cls; };

    card.addEventListener('pointerdown', e => {
      if (cur.busy) return;
      card.setPointerCapture(e.pointerId);
      drag = { sx: e.clientX - x, t0: 0, lastX: x, ok: true, back: false };
    });
    card.addEventListener('pointermove', e => {
      if (!drag) return;
      const v = DL.clamp(e.clientX - drag.sx, 0, maxX());
      if (v < drag.lastX - 12) drag.back = true;          // cofanie karty psuje odczyt
      if (!drag.t0 && v > 12) { drag.t0 = performance.now(); DL.Audio.play('swipe', 0.6); }
      drag.lastX = v;
      place(v);
    });
    const release = async () => {
      if (!drag) return;
      const dt = drag.t0 ? performance.now() - drag.t0 : 0, full = x >= maxX() - 4, back = drag.back;
      drag = null;
      if (!full) { say('Przeciągnij kartę do końca', 'err'); return place(0, true); }
      if (back) { say('Karta cofnięta – spróbuj jednym ruchem', 'err'); return place(0, true); }
      if (dt < 140) { say('Za szybko!', 'err'); DL.Audio.play('error', 0.5); return place(0, true); }
      if (dt > 1100) { say('Za wolno…', 'err'); DL.Audio.play('error', 0.5); return place(0, true); }
      cur.busy = true;
      s1.textContent = 'ODCZYT…';
      led.className = 'led amber';
      const res = await result();
      if (!res) return;
      if (res.ok) {
        slot.className = 'rd-slot ok'; led.className = 'led green'; screen.className = 'rd-screen';
        s1.textContent = res.locked ? 'ZAMKNIĘTO' : 'DOSTĘP PRZYZNANY';
        say('Karta zaakceptowana', 'ok');
        DL.Audio.play('ok');
        setTimeout(() => DL.layer.close(), 1000);
      } else {
        slot.className = 'rd-slot err'; led.className = 'led red'; screen.className = 'rd-screen err';
        s1.textContent = res.reason === 'lockdown' ? 'BLOKADA BUDYNKU' : 'ODMOWA DOSTĘPU';
        say(res.msg || 'Karta odrzucona', 'err');
        DL.Audio.play('deny');
        setTimeout(() => {
          if (!cur) return;
          cur.busy = false; slot.className = 'rd-slot'; screen.className = 'rd-screen'; s1.textContent = 'PRZECIĄGNIJ KARTĘ';
          place(0, true);
        }, 1500);
      }
    };
    card.addEventListener('pointerup', release);
    card.addEventListener('pointercancel', release);
    DL.layer.open('reader', box, () => { cur = null; });
    DL.Audio.play('open');
  };

  /* ---------------- biometria ---------------- */
  const fingerprint = () => {
    const cx = 67, cy = 100, rnd = DL.rng(7);
    let base = '', lit = '';
    for (let k = 1; k <= 11; k++) {
      const rx = 5 + k * 5.6, ry = 7 + k * 8;
      const segs = k < 3 ? 1 : 2;
      for (let s = 0; s < segs; s++) {
        const span = segs === 1 ? Math.PI * 1.7 : Math.PI * (0.55 + rnd() * 0.35);
        const a0 = segs === 1 ? Math.PI * 0.65 : (s === 0 ? Math.PI * (0.85 + rnd() * 0.15) : Math.PI * (1.75 + rnd() * 0.1) - span / 2 + Math.PI * 0.3);
        const a1 = a0 + span;
        const p = a => [cx + rx * Math.cos(a), cy - 10 + ry * Math.sin(a) * (a > Math.PI * 1.9 || a < Math.PI * 0.1 ? 1 : 1)];
        const [x1, y1] = p(a0), [x2, y2] = p(a1);
        const d = `M${x1.toFixed(1)} ${y1.toFixed(1)}A${rx} ${ry} 0 ${span > Math.PI ? 1 : 0} 1 ${x2.toFixed(1)} ${y2.toFixed(1)}`;
        base += `<path class="ridge" d="${d}"/>`;
        lit += `<path class="lit" pathLength="400" d="${d}"/>`;
      }
    }
    return `<svg viewBox="0 0 134 194">${base}${lit}</svg>`;
  };

  const openBio = d => {
    const box = DL.h('div.device.bio');
    box.innerHTML = `
      <i class="screw tl"></i><i class="screw tr"></i><i class="screw bl"></i><i class="screw br"></i>
      <button class="dev-close">${DL.icon('x')}</button>
      <div class="dev-head"><div class="t"><b>${DL.esc(d.name)}</b><span>${DL.esc(d.group || 'Skaner biometryczny')}</span></div><i class="led red"></i></div>
      <div class="bio-pad">${fingerprint()}<i class="beam"></i><i class="ring"></i></div>
      <div class="bio-pct">PRZYŁÓŻ PALEC</div>
      <div class="rd-msg">Przytrzymaj lewy przycisk myszy na czytniku</div>`;
    const pad = DL.$('.bio-pad', box), pct = DL.$('.bio-pct', box), msg = DL.$('.rd-msg', box), led = DL.$('.led', box);
    DL.$('.dev-close', box).onclick = () => DL.layer.close();
    const DUR = 1400;
    cur = { id: d.id, busy: false };
    let t = 0, raf = 0, t0 = 0;
    pad.style.setProperty('--dur', DUR + 'ms');

    const stop = () => { clearTimeout(t); cancelAnimationFrame(raf); };
    const counter = () => {
      const p = Math.min(100, Math.round(((performance.now() - t0) / DUR) * 100));
      pct.textContent = `SKANOWANIE ${String(p).padStart(3, ' ')}%`;
      if (p < 100) raf = requestAnimationFrame(counter);
    };
    pad.addEventListener('pointerdown', () => {
      if (cur.busy) return;
      pad.className = 'bio-pad scan';
      led.className = 'led amber';
      msg.className = 'rd-msg'; msg.textContent = 'Nie odrywaj palca…';
      DL.Audio.play('scan', 0.8);
      t0 = performance.now();
      counter();
      t = setTimeout(async () => {
        cancelAnimationFrame(raf);
        cur.busy = true;
        pct.textContent = 'ANALIZA…';
        const res = await result();
        if (!res) return;
        if (res.ok) {
          pad.className = 'bio-pad ok'; led.className = 'led green';
          pct.textContent = 'TOŻSAMOŚĆ POTWIERDZONA';
          msg.className = 'rd-msg ok'; msg.textContent = res.locked ? 'Drzwi zamknięte' : 'Drzwi odblokowane';
          DL.Audio.play('ok');
          setTimeout(() => DL.layer.close(), 1100);
        } else {
          pad.className = 'bio-pad err'; led.className = 'led red';
          pct.textContent = 'NIEZNANY ODCISK';
          msg.className = 'rd-msg err'; msg.textContent = res.msg || 'Brak dostępu';
          DL.Audio.play('deny');
          setTimeout(() => { if (cur) { cur.busy = false; pad.className = 'bio-pad'; pct.textContent = 'PRZYŁÓŻ PALEC'; } }, 1600);
        }
      }, DUR);
    });
    const cancel = () => {
      if (!cur || cur.busy || !pad.classList.contains('scan')) return;
      stop();
      pad.className = 'bio-pad'; led.className = 'led red';
      pct.textContent = 'PRZERWANO';
      msg.className = 'rd-msg err'; msg.textContent = 'Przytrzymaj palec do końca skanu';
      DL.Audio.play('error', 0.4);
    };
    pad.addEventListener('pointerup', cancel);
    pad.addEventListener('pointerleave', cancel);
    DL.layer.open('reader', box, () => { stop(); cur = null; });
    DL.Audio.play('open');
  };

  return { open: d => (d.kind === 'bio' ? openBio(d) : openCard(d)) };
})();
