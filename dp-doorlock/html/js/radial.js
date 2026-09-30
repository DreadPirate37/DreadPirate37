'use strict';
/* ==========================================================================
   Menu radialne akcji drzwi – wybór kątem myszy (jak koło broni w GTA),
   klawisze 1–9, ESC zamyka. Segmenty to ścieżki SVG liczone raz.
   ========================================================================== */
DL.Radial = (() => {
  const C = 240, R1 = 112, R2 = 228, GAP = 1.6;
  let cur = null;

  const polar = (r, a) => [C + r * Math.cos(a), C + r * Math.sin(a)];
  const arc = (a0, a1) => {
    const g0 = (GAP / R2), g1 = (GAP / R1);
    const [x1, y1] = polar(R2, a0 + g0), [x2, y2] = polar(R2, a1 - g0);
    const [x3, y3] = polar(R1, a1 - g1), [x4, y4] = polar(R1, a0 + g1);
    const large = a1 - a0 > Math.PI ? 1 : 0;
    return `M${x1} ${y1}A${R2} ${R2} 0 ${large} 1 ${x2} ${y2}L${x3} ${y3}A${R1} ${R1} 0 ${large} 0 ${x4} ${y4}Z`;
  };
  const outer = (a0, a1) => {
    const [x1, y1] = polar(R2 - 1, a0 + 0.02), [x2, y2] = polar(R2 - 1, a1 - 0.02);
    return `M${x1} ${y1}A${R2 - 1} ${R2 - 1} 0 ${a1 - a0 > Math.PI ? 1 : 0} 1 ${x2} ${y2}`;
  };

  const stateCls = st => (st.d ? 's-lockdown' : st.b ? 's-broken' : st.l ? 's-locked' : 's-open');

  const open = d => {
    const opts = d.options || [];
    const n = Math.max(opts.length, 1);
    const step = (Math.PI * 2) / n;
    const start = -Math.PI / 2 - step / 2;
    const wrap = DL.h('div.radial');
    let svg = `<svg class="wheel" viewBox="0 0 480 480"><defs>
      <radialGradient id="rsHot" cx="240" cy="240" r="228" gradientUnits="userSpaceOnUse">
        <stop offset=".45" stop-color="rgba(${getComputedStyle(document.body).getPropertyValue('--acc-rgb')},.08)"/>
        <stop offset="1" stop-color="rgba(${getComputedStyle(document.body).getPropertyValue('--acc2-rgb')},.32)"/>
      </radialGradient></defs>`;
    opts.forEach((o, i) => {
      const a0 = start + i * step, a1 = a0 + step;
      svg += `<g class="rseg${o.disabled ? ' dis' : ''} tone-${o.tone || 'n'}" data-i="${i}"><path d="${arc(a0, a1)}"/><path class="rs-glow" d="${outer(a0, a1)}"/></g>`;
    });
    wrap.innerHTML = svg + '</svg>';
    opts.forEach((o, i) => {
      const a = start + (i + 0.5) * step;
      const [x, y] = polar((R1 + R2) / 2, a);
      const ic = DL.h('div.r-ic' + (o.disabled ? '.dis' : '') + (o.tone ? '.tone-' + o.tone : ''), { style: { left: x + 'px', top: y + 'px' } });
      ic.innerHTML = `${DL.icon(o.icon)}<small>${DL.esc(o.label)}</small>${i < 9 ? `<span class="num">${i + 1}</span>` : ''}`;
      wrap.append(ic);
    });
    const center = DL.h('div.r-center.' + stateCls(d.st || {}));
    center.innerHTML = `${DL.padlock()}<div class="rc-name">${DL.esc(d.name)}</div><div class="rc-grp">${DL.esc(d.group || '—')}</div><div class="rc-opt"></div>`;
    wrap.append(center);
    wrap.append(DL.h('div.r-hint', { html: '<span><kbd>LPM</kbd>wybierz</span><span><kbd>1–9</kbd>skrót</span><span><kbd>ESC</kbd>zamknij</span>' }));

    const segs = DL.$$('.rseg', wrap), icons = DL.$$('.r-ic', wrap), optEl = DL.$('.rc-opt', center);
    cur = { d, opts, hot: -1, wrap, step, start };

    const setHot = i => {
      if (i === cur.hot) return;
      if (cur.hot >= 0) { segs[cur.hot].classList.remove('hot'); icons[cur.hot].classList.remove('hot'); }
      cur.hot = i;
      if (i < 0) { optEl.innerHTML = ''; return; }
      segs[i].classList.add('hot');
      icons[i].classList.add('hot');
      const o = opts[i];
      optEl.className = 'rc-opt' + (o.disabled ? ' dis' : '');
      optEl.innerHTML = `${DL.esc(o.label)}${o.desc ? `<small>${DL.esc(o.desc)}</small>` : ''}`;
      DL.Audio.play('tick', 0.7);
    };
    cur.setHot = setHot;

    cur.move = e => {
      const r = wrap.getBoundingClientRect();
      const dx = e.clientX - (r.left + r.width / 2), dy = e.clientY - (r.top + r.height / 2);
      if (dx * dx + dy * dy < 60 * 60) return setHot(-1);
      let a = Math.atan2(dy, dx) - start;
      a = ((a % (Math.PI * 2)) + Math.PI * 2) % (Math.PI * 2);
      setHot(Math.floor(a / step) % opts.length);
    };
    cur.click = e => { if (e.button === 0 && cur.hot >= 0) choose(cur.hot); else if (e.button === 2) DL.layer.close(); };
    window.addEventListener('mousemove', cur.move);
    window.addEventListener('mousedown', cur.click);
    DL.layer.open('radial', wrap, () => {
      window.removeEventListener('mousemove', cur.move);
      window.removeEventListener('mousedown', cur.click);
      cur = null;
    });
    DL.Audio.play('open', 0.8);
  };

  const choose = i => {
    const o = cur && cur.opts[i];
    if (!o) return;
    if (o.disabled) { DL.Audio.play('deny', 0.5); cur.wrap.animate([{ transform: 'translateX(-6px)' }, { transform: 'translateX(5px)' }, { transform: 'none' }], 250); return; }
    const id = cur.d.id;
    DL.Audio.play('beep', 0.8);
    DL.layer.close(true);
    DL.post('radial', { id, option: o.id });
  };

  const key = e => {
    if (!cur) return false;
    const n = Number(e.key);
    if (n >= 1 && n <= 9 && n <= cur.opts.length) { cur.setHot(n - 1); choose(n - 1); return true; }
    if (e.key === 'Enter' && cur.hot >= 0) { choose(cur.hot); return true; }
    return false;
  };

  return { open, key };
})();
