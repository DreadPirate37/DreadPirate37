'use strict';
/* ==========================================================================
   Etap 6 – Odbiór: badanie RTG, protokół, ocena, wypłata (liczona przez serwer)
   ========================================================================== */
W.Stages.report = game => {
  const st = { ready: true };
  const sum = game.summary();
  const path = game.piece.path;
  const el = document.getElementById('report');
  let view = 'photo';
  let result = null;

  game.title('Odbiór techniczny', 'Inspektor sprawdza spoinę');
  game.keys([['TAB', 'zdjęcie / RTG']]);
  game.timer(null);
  game.progress(1);

  /* film RTG */
  const film = W.canvas();
  (() => {
    const f = film.getContext('2d');
    f.fillStyle = '#10161c';
    f.fillRect(0, 0, W.VW, W.VH);
    for (let i = 0; i < 4000; i++) {
      f.fillStyle = `rgba(255,255,255,${Math.random() * 0.03})`;
      f.fillRect(Math.random() * W.VW, Math.random() * W.VH, 2, 2);
    }
    f.fillStyle = 'rgba(160,185,205,0.18)';
    f.fillRect(0, 0, W.VW, W.VH);
    const passes = game.cells || [];
    const last = passes[passes.length - 1];
    if (!last) return;
    const { N, CELL } = last;
    for (let c = 0; c < N; c++) {
      /* gęstość spoiny = jaśniej; braki = ciemno */
      let fillAvg = 0, lof = false, por = false, inc = false, br = false;
      for (const p of passes) {
        const cc = Math.min(c, p.N - 1);
        fillAvg += Math.min(p.fills[cc], 1.6);
        if (p.fills[cc] < 0.3) lof = true;
        por = por || p.poro[cc];
        inc = inc || p.incl[cc];
        br = br || p.burn[cc];
      }
      fillAvg /= passes.length;
      const i = path.idx((c + 0.5) * CELL);
      const x = path.x[i], y = path.y[i];
      const w = (last.B || 8) + 6;
      const lum = Math.round(W.clamp(90 + fillAvg * 90, 60, 230));
      f.fillStyle = `rgba(${lum},${lum + 8},${lum + 14},0.85)`;
      f.beginPath();
      f.arc(x, y, w, 0, Math.PI * 2);
      f.fill();
      if (lof) {
        f.strokeStyle = 'rgba(10,12,16,0.9)';
        f.lineWidth = 2.5;
        f.beginPath();
        f.moveTo(x - Math.cos(path.ang[i]) * 6, y - Math.sin(path.ang[i]) * 6);
        f.lineTo(x + Math.cos(path.ang[i]) * 6, y + Math.sin(path.ang[i]) * 6);
        f.stroke();
      }
      if (por) {
        for (let k = 0; k < 4; k++) {
          f.fillStyle = 'rgba(8,10,14,0.85)';
          f.beginPath();
          f.arc(x + (Math.random() - 0.5) * w, y + (Math.random() - 0.5) * w, 1 + Math.random() * 2, 0, Math.PI * 2);
          f.fill();
        }
      }
      if (inc) {
        f.fillStyle = 'rgba(20,20,26,0.85)';
        f.fillRect(x - 4, y - 1.5, 8 + Math.random() * 4, 3);
      }
      if (br) W.hole(f, x, y, 7);
    }
    f.fillStyle = 'rgba(200,220,235,0.7)';
    f.font = '14px "Share Tech Mono", monospace';
    f.fillText(`RT · ${W.TYPES[game.task.type]} · ${game.task.thickness} mm · ${game.P.label}`, 220, 640);
  })();

  const bar = (label, v) => `
    <div class="sbar"><span>${label}</span><div><i style="width:${W.clamp(v, 0, 100).toFixed(0)}%" class="${v >= 80 ? 'g' : v >= 55 ? 'y' : 'r'}"></i></div><b>${v.toFixed(0)}</b></div>`;
  const defs = Object.entries(sum.defects)
    .filter(([, v]) => v > 0)
    .map(([k, v]) => `<li><span>${W.DEFECTS[k]}</span><b>${Math.ceil(v)}</b></li>`)
    .join('');

  el.innerHTML = `
    <div class="rep">
      <h2>PROTOKÓŁ ODBIORU</h2>
      ${bar('Ustawienia WPS', sum.scores.setup)}
      ${bar('Przygotowanie', sum.scores.prep)}
      ${bar(game.task.type === 'crack' ? 'Otwory zatrzymujące' : 'Sczepianie', sum.scores.prep2)}
      ${bar('Spawanie', sum.scores.weld)}
      ${bar('Czyszczenie', sum.scores.finish)}
      <h3>Wykryte niezgodności</h3>
      <ul class="defs">${defs || '<li class="none">Brak – spoina bez zastrzeżeń</li>'}</ul>
      <div class="total"><span>Jakość</span><b>${sum.quality.toFixed(1)}%</b></div>
      <div class="pay" id="payBox"><span class="spin"></span> Inspektor wystawia ocenę…</div>
      <button class="btn primary" id="repClose" disabled>Zamknij</button>
    </div>
    <div class="stamp g-${sum.grade}" id="stamp">${sum.grade}</div>`;
  el.classList.remove('hidden');
  const closeBtn = el.querySelector('#repClose');
  closeBtn.onclick = () => game.close(false);

  setTimeout(() => {
    el.querySelector('#stamp').classList.add('in');
    W.Audio.stamp();
  }, 700);

  /* wynik do serwera – serwer liczy wypłatę i XP niezależnie */
  (async () => {
    const payload = {
      token: game.task.token,
      scores: sum.scores,
      defects: sum.defects,
      quality: sum.quality,
      seconds: sum.seconds,
      stageTimes: sum.stageTimes,
    };
    const res = await W.post('finish', payload);
    result = res || { ok: false, msg: 'Brak odpowiedzi serwera' };
    const box = el.querySelector('#payBox');
    if (result.ok) {
      const lines = [];
      if (result.failed) {
        lines.push(`<div class="fail">Spoina odrzucona przez inspektora.</div>`);
        lines.push(result.attemptsLeft > 0 ? `<small>Pozostałe podejścia: ${result.attemptsLeft}</small>` : '<small>Brak kolejnych podejść – zadanie przepadło.</small>');
      } else {
        lines.push(`<div class="money">${W.fmtMoney(result.pay)}</div>`);
        if (result.bonus) lines.push(`<small>w tym premia za ocenę ${W.esc(result.grade)}: ${W.fmtMoney(result.bonus)}</small>`);
      }
      lines.push(`<small>+${result.xp} XP${result.levelUp ? ` · <b class="lvl">AWANS: ${W.esc(result.levelLabel)}!</b>` : ''}</small>`);
      box.innerHTML = lines.join('');
      if (result.grade && result.grade !== sum.grade) {
        const s = el.querySelector('#stamp');
        s.textContent = result.grade;
        s.className = `stamp in g-${result.grade}`;
      }
      W.Audio[result.failed ? 'bad' : 'good']();
    } else {
      box.innerHTML = `<div class="fail">${W.esc(result.msg || 'Błąd')}</div>`;
    }
    closeBtn.disabled = false;
  })();

  st.update = dt => {

    if (W.Input.hit('Tab')) view = view === 'photo' ? 'rt' : 'photo';
    if (W.Input.hit('Enter') && !closeBtn.disabled) game.close(false);
  };
  st.render = g => {
    g.fillStyle = '#0b0d0f';
    g.fillRect(0, 0, W.VW, W.VH);
    g.save();
    g.translate(-200, 0);
    if (view === 'rt') g.drawImage(film, 0, 0);
    else {
      game.drawWork(g);
      game.drawSpatter(g);
    }
    g.restore();
    g.fillStyle = 'rgba(0,0,0,0.25)';
    g.fillRect(0, 0, W.VW, W.VH);
    g.fillStyle = '#ffb020';
    g.font = 'bold 16px Rajdhani, sans-serif';
    g.fillText(view === 'rt' ? '◉ RADIOGRAM (TAB – zdjęcie)' : '◉ ZDJĘCIE (TAB – radiogram)', 24, 100);
  };
  st.destroy = () => (el.innerHTML = '');
  return st;
};
