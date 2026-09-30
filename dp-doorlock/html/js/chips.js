'use strict';
/* ==========================================================================
   Znaczniki drzwi w świecie. Elementy DOM są tworzone raz na drzwi i
   używane ponownie; ruch = wyłącznie transform (warstwa kompozytora).
   Odliczanie autozamka to przejście CSS – zero pracy JS na klatkę.
   ========================================================================== */
DL.Chips = (() => {
  const root = () => DL.$('#chips');
  const els = new Map();       // id → { el, meta, f, st }
  const meta = new Map();      // id → { name, group, security, type, st }
  let W = window.innerWidth, H = window.innerHeight;
  window.addEventListener('resize', () => { W = window.innerWidth; H = window.innerHeight; });

  const SEC = { standard: null, keypad: 'keypad', card: 'card', bio: 'finger' };
  const SEC_LABEL = { standard: 'Klucz', keypad: 'PIN', card: 'Karta', bio: 'Biometria' };
  const RING = 169.6;

  const stateName = st => (st.d ? 'lockdown' : st.b ? 'broken' : st.l ? 'locked' : 'open');
  const stateLabel = { locked: 'Zamknięte', open: 'Otwarte', broken: 'Wyłamane', lockdown: 'Blokada' };
  const useLabel = (m, st) => {
    if (st.b) return null;
    if (m.security === 'keypad') return 'Klawiatura';
    if (m.security === 'card') return 'Przyłóż kartę';
    if (m.security === 'bio') return 'Skanuj palec';
    return st.l ? 'Otwórz' : 'Zamknij';
  };

  const build = (id, m) => {
    const el = DL.h('div.chip');
    el.innerHTML = `
      <div class="chip-ico">
        ${DL.padlock()}
        <svg class="chip-ring" viewBox="0 0 58 58"><circle cx="29" cy="29" r="27"/></svg>
        <div class="chip-sec">${SEC[m.security] ? DL.icon(SEC[m.security]) : ''}</div>
      </div>
      <div class="chip-card">
        <div class="chip-name"></div>
        <div class="chip-sub"><i class="dot"></i><b></b><span class="grp"></span></div>
        <div class="chip-keys"></div>
      </div>`;
    root().append(el);
    const rec = { el, f: false, ring: el.querySelector('.chip-ring circle'), name: el.querySelector('.chip-name'),
      stTxt: el.querySelector('.chip-sub b'), grp: el.querySelector('.chip-sub .grp'), keys: el.querySelector('.chip-keys'),
      hideT: 0, autoT: 0 };
    els.set(id, rec);
    fill(id);
    return rec;
  };

  /** Wypełnia treść i klasy stanu (wołane tylko przy zmianie meta/stanu) */
  const fill = id => {
    const rec = els.get(id), m = meta.get(id);
    if (!rec || !m) return;
    const st = m.st || { l: true };
    const s = stateName(st);
    rec.el.className = `chip s-${s}${st.a ? ' alarm' : ''}${rec.f ? ' f' : ''}${rec.el.classList.contains('vis') ? ' vis' : ''}`;
    rec.name.textContent = DL.cfg.showNames ? m.name : 'Drzwi';
    rec.stTxt.textContent = stateLabel[s];
    rec.grp.textContent = [m.group, SEC_LABEL[m.security]].filter(Boolean).join(' · ');
    const use = useLabel(m, st);
    rec.keys.innerHTML =
      (use ? `<span><kbd>${DL.esc(DL.cfg.keys.use)}</kbd>${use}</span>` : '') +
      `<span><kbd>${DL.esc(DL.cfg.keys.menu)}</kbd>Więcej</span>` +
      (st.t ? '<span class="chip-auto"></span>' : '');
    ring(rec, st);
  };

  /** Odliczanie autozamka: stan początkowy + jedno przejście CSS */
  const ring = (rec, st) => {
    clearInterval(rec.autoT);
    const c = rec.ring;
    if (!st.t || !st.T) { rec.el.classList.remove('auto'); c.style.transition = 'none'; return; }
    rec.el.classList.add('auto');
    const frac = DL.clamp(st.t / st.T, 0, 1);
    c.style.transition = 'none';
    c.style.strokeDashoffset = String(RING * (1 - frac));
    c.getBoundingClientRect();                     // wymuszenie stylu przed przejściem
    c.style.transition = `stroke-dashoffset ${st.t}ms linear`;
    c.style.strokeDashoffset = String(RING);
    const auto = rec.el.querySelector('.chip-auto');
    if (auto) {
      const end = performance.now() + st.t;
      const tick = () => { auto.innerHTML = `${Math.max(0, Math.ceil((end - performance.now()) / 1000))}s`; };
      tick();
      rec.autoT = setInterval(() => { tick(); if (performance.now() >= end) clearInterval(rec.autoT); }, 1000);
    }
  };

  const api = {
    meta(list) {
      for (const d of list) {
        meta.set(d.id, d);
        if (els.has(d.id)) fill(d.id);
      }
    },
    state(id, st) {
      const m = meta.get(id);
      if (!m) return;
      m.st = st;
      fill(id);
    },
    /** lista pozycji z Lua: [{ id, x, y, s, f }] (x, y ∈ 0..1) */
    update(list) {
      const seen = new Set();
      for (const c of list) {
        if (!meta.has(c.id)) continue;
        seen.add(c.id);
        const rec = els.get(c.id) || build(c.id, meta.get(c.id));
        clearTimeout(rec.hideT);
        rec.hideT = 0;
        rec.el.style.transform = `translate3d(${(c.x * W).toFixed(1)}px,${(c.y * H).toFixed(1)}px,0) scale(${c.s.toFixed(3)})`;
        if (!rec.el.classList.contains('vis')) rec.el.classList.add('vis');
        if (rec.f !== c.f) {
          rec.f = c.f;
          rec.el.classList.toggle('f', c.f);
          if (c.f) DL.Audio.play('tick', 0.5);
        }
      }
      for (const [id, rec] of els) {
        if (seen.has(id) || rec.hideT) continue;
        rec.el.classList.remove('vis');
        rec.hideT = setTimeout(() => { clearInterval(rec.autoT); rec.el.remove(); els.delete(id); }, 4000);
      }
    },
    fx(id, fx) {
      const rec = els.get(id);
      if (!rec) return;
      const cls = 'fx-' + fx;
      rec.el.classList.remove(cls);
      void rec.el.offsetWidth;
      rec.el.classList.add(cls);
      setTimeout(() => rec.el.classList.remove(cls), 800);
    },
    clear() { for (const [, r] of els) { clearInterval(r.autoT); r.el.remove(); } els.clear(); },
  };
  return api;
})();
