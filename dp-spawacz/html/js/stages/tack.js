'use strict';
/* ==========================================================================
   Etap 3b (złącza / łata) – Sczepianie
   Sczepy w kolejności „na krzyż” (przeciwdziała odkształceniom). Każdy sczep:
   najedź na punkt i kliknij, gdy zwężający się pierścień trafi w znacznik.
   Złe sczepy = odkształcenie detalu = szersza szczelina do wypełnienia.
   ========================================================================== */
W.Stages.tack = game => {
  const t = game.task, path = game.piece.path;
  const st = {};
  const bead = game.layers.bead.getContext('2d');
  const fr = path.closed
    ? [0, 0.5, 0.25, 0.75, 0.125, 0.625].slice(0, 4 + Math.min(2, Math.floor(t.difficulty / 2)))
    : [0.04, 0.96, 0.5, 0.27, 0.73].slice(0, t.type === 'fillet' ? 4 : 4 + (t.difficulty >= 3 ? 1 : 0));
  const pts = fr.map(f => {
    const i = path.idx(f * path.len);
    return { i, x: path.x[i], y: path.y[i], q: null };
  });
  const DUR = 1.35 - t.difficulty * 0.1;
  const R0 = 70, RT = 14;
  let cur = 0, ringT = 0, pause = 0.5, finished = false, distort = 0;

  game.title('Sczepianie', 'Sczepy w kolejności – trafiaj w rytm pierścienia');
  game.keys([['LPM', 'sczep'], ['ENTER', 'pomiń']]);
  game.intro(st, 'Sczepianie elementów', [
    'Sczepy zakłada się <b>naprzemiennie</b> – numeracja pokazuje kolejność.',
    'Najedź celownikiem na punkt i <b>kliknij</b>, gdy pierścień zrówna się ze znacznikiem.',
    'Za wcześnie / za późno / obok punktu = <b>odkształcenie</b> detalu i trudniejsze spawanie.',
  ], [['LPM', 'sczep']]);

  const place = q => {
    const p = pts[cur];
    p.q = q;
    distort += (1 - q) * 3;
    const cols = game.M.bead;
    for (let k = -4; k <= 4; k++) {
      const i = path.idx((p.i + k * 1.2) * path.sp);
      W.ripple(bead, path.x[i], path.y[i], path.ang[i], 6.5, cols);
    }
    game.particles.burst(p.x, p.y, 25, 380, 0, 0.5);
    W.Audio.arc(true, t.process, 0.5);
    setTimeout(() => W.Audio.arc(false, t.process), 180);
    W.post('arc', { on: true });
    setTimeout(() => W.post('arc', { on: false }), 250);
    game.flash(q > 0.85 ? 'Idealny sczep!' : q > 0.55 ? 'Dobry sczep' : q > 0.25 ? 'Słaby sczep' : 'Nieudany sczep', q > 0.55 ? 'good' : 'bad', 700);
    cur++;
    ringT = 0;
    pause = 0.45;
    game.progress(cur / pts.length);
    if (cur >= pts.length) finish();
  };

  const finish = () => {
    if (finished) return;
    finished = true;
    const qs = pts.map(p => p.q ?? 0);
    const avg = qs.reduce((a, b) => a + b, 0) / qs.length;
    game.fitup = W.clamp(avg, 0.2, 1);
    game.done('prep2', avg * 100, { msg: avg > 0.75 ? 'Elementy sczepione równo' : 'Detal lekko się odkształcił', cls: avg > 0.75 ? 'good' : 'warn' });
  };

  st.update = dt => {
    if (finished) return;
    const I = W.Input;
    if (I.hit('Enter')) {
      finish();
      return;
    }
    if (pause > 0) {
      pause -= dt;
      return;
    }
    ringT += dt;
    const r = R0 * (1 - ringT / DUR);
    const p = pts[cur];
    if (I.clicked) {
      const posErr = W.dist(I.x, I.y, p.x, p.y) / RT;
      const timeErr = Math.abs(r - RT) / RT;
      let q = W.clamp(1 - 0.65 * timeErr - 0.45 * Math.max(0, posErr - 0.25), 0, 1);
      if (posErr > 2.5) q = 0.05;
      place(q);
    } else if (r <= 0) {
      place(0.05);
    }
  };

  st.render = g => {
    game.drawWork(g);
    g.save();
    /* lekkie „rozjechanie” szczeliny po złych sczepach */
    if (distort > 0) {
      g.strokeStyle = 'rgba(0,0,0,0.55)';
      g.lineWidth = 1 + distort * 0.6;
      path.stroke(g);
    }
    pts.forEach((p, k) => {
      const active = k === cur && !finished;
      g.fillStyle = p.q != null ? (p.q > 0.55 ? '#3ddc84' : '#ff5c5c') : active ? '#ffb020' : 'rgba(255,255,255,0.5)';
      g.font = 'bold 18px Rajdhani, sans-serif';
      g.textAlign = 'center';
      g.fillText(String(k + 1), p.x + path.nx[p.i] * -34, p.y + path.ny[p.i] * -34 + 6);
      if (!active) return;
      g.strokeStyle = '#ffb020';
      g.lineWidth = 2;
      g.beginPath();
      g.arc(p.x, p.y, RT, 0, Math.PI * 2);
      g.stroke();
      if (pause <= 0) {
        const r = Math.max(0, R0 * (1 - ringT / DUR));
        const good = Math.abs(r - RT) < 5;
        g.strokeStyle = good ? '#3ddc84' : 'rgba(255,255,255,0.85)';
        g.lineWidth = good ? 4 : 2.5;
        g.beginPath();
        g.arc(p.x, p.y, r, 0, Math.PI * 2);
        g.stroke();
      }
    });
    game.particles.render(g);
    const I = W.Input;
    g.strokeStyle = '#fff';
    g.lineWidth = 1.5;
    g.beginPath();
    g.moveTo(I.x - 10, I.y); g.lineTo(I.x - 3, I.y);
    g.moveTo(I.x + 3, I.y); g.lineTo(I.x + 10, I.y);
    g.moveTo(I.x, I.y - 10); g.lineTo(I.x, I.y - 3);
    g.moveTo(I.x, I.y + 3); g.lineTo(I.x, I.y + 10);
    g.stroke();
    g.restore();
    W.drawTorch(g, I.x, I.y, t.process, 0, 0.8);
  };

  st.dbg = () => {
    const p = pts[cur];
    return p ? { x: p.x, y: p.y, r: pause > 0 ? -1 : R0 * (1 - ringT / DUR), cur } : null;
  };

  st.destroy = () => W.Audio.arc(false, t.process);
  return st;
};
