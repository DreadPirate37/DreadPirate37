'use strict';
/* ==========================================================================
   Etap 3a (pęknięcie) – Penetrant + otwory zatrzymujące pęknięcie
   Penetrant ujawnia prawdziwą długość pęknięcia. Trzeba nawiercić otwór
   tuż ZA końcem rysy, bo inaczej pęknięcie „pójdzie” dalej pod spoiną.
   ========================================================================== */
W.Stages.drill = game => {
  const t = game.task, piece = game.piece, path = piece.path, rand = game.rand;
  const st = {};
  const TIME = 20 - t.difficulty;
  const holes = piece.tips.map(tp => ({ tx: tp.x + tp.dx * 4, ty: tp.y + tp.dy * 4, done: false, score: 0 }));
  let cur = 0, reveal = 0, time = TIME, finished = false;
  let prog = 0, sumD = 0, sumT = 0, restarts = 0, stamina = 1, locked = false;
  const wander = { x: 0, y: 0, vx: 0, vy: 0 };
  const D = { x: 640, y: 360 };
  const base = piece.base.getContext('2d');

  game.title('Badanie penetracyjne i otwory', 'Znajdź prawdziwe końce pęknięcia i zatrzymaj je otworami');
  game.keys([['LPM (przytrzymaj)', 'wierć'], ['SHIFT', 'stabilizuj rękę'], ['ENTER', 'pomiń']]);
  game.intro(st, 'Otwory zatrzymujące pęknięcie', [
    'Czerwony penetrant pokaże <b>pełną długość rysy</b> – jest dłuższa niż widać gołym okiem!',
    'Nawierć otwór <b>tuż za końcem</b> pęknięcia, po obu stronach.',
    'Wiertarka „ucieka” – kontruj myszą. <b>SHIFT</b> stabilizuje, ale męczy rękę.',
    'Puszczenie LPM w trakcie = zaczynasz otwór od nowa.',
  ], [['LPM', 'wierć'], ['SHIFT', 'stabilizacja']]);

  const finish = () => {
    if (finished) return;
    finished = true;
    W.Audio.drill(false);
    const avg = holes.reduce((a, h) => a + h.score, 0) / holes.length;
    game.done('prep2', avg * 100 - restarts * 5, { msg: avg > 0.8 ? 'Pęknięcie zatrzymane' : 'Otwory niedokładne…', cls: avg > 0.8 ? 'good' : 'warn' });
  };

  st.update = dt => {
    if (finished) return;
    const I = W.Input;
    if (reveal < 1) {
      reveal = Math.min(1, reveal + dt / 1.3);
      W.Audio.hiss(reveal < 1, 0.08);
      return;
    }
    time -= dt;
    game.timer(time);
    const h = holes[cur];
    const steady = I.key('ShiftLeft') || I.key('ShiftRight');
    if (steady && !locked) stamina -= dt * 0.35;
    else stamina += dt * 0.2;
    if (stamina <= 0) { stamina = 0; locked = true; }
    if (locked && stamina > 0.35) locked = false;
    stamina = Math.min(1, stamina);
    const useSteady = steady && !locked;

    if (I.down) {
      const k = (6 + t.difficulty * 3) * (useSteady ? 0.3 : 1);
      wander.vx += (rand() - 0.5) * k * 60 * dt;
      wander.vy += (rand() - 0.5) * k * 60 * dt;
      wander.vx *= 0.96;
      wander.vy *= 0.96;
      wander.x = W.clamp(wander.x + wander.vx * dt, -30, 30);
      wander.y = W.clamp(wander.y + wander.vy * dt, -30, 30);
      if (prog === 0) { wander.x = wander.y = wander.vx = wander.vy = 0; sumD = sumT = 0; }
      D.x = I.x + wander.x;
      D.y = I.y + wander.y;
      prog += dt / 1.7;
      sumD += W.dist(D.x, D.y, h.tx, h.ty) * dt;
      sumT += dt;
      W.Audio.drill(true, prog);
      if (rand() < dt * 30) game.particles.emit(D.x, D.y, (rand() - 0.5) * 120, -rand() * 80, 0.5, 1, 1);
      if (prog >= 1) {
        const avgD = sumD / sumT;
        h.score = W.gauss(avgD, 11);
        h.done = true;
        W.hole(base, D.x, D.y, 4.5);
        base.strokeStyle = 'rgba(210,215,220,0.8)';
        base.lineWidth = 1.2;
        base.beginPath();
        base.arc(D.x, D.y, 5.5, 0, Math.PI * 2);
        base.stroke();
        W.Audio.drill(false);
        W.Audio[h.score > 0.7 ? 'good' : 'bad']();
        game.flash(h.score > 0.85 ? 'Idealnie za końcem rysy!' : h.score > 0.5 ? 'Otwór OK' : 'Za daleko od końca pęknięcia', h.score > 0.5 ? 'good' : 'bad', 900);
        prog = 0;
        cur++;
        if (cur >= holes.length) finish();
      }
    } else {
      if (prog > 0.15) {
        restarts++;
        game.flash('Wiertło zeszło – zaczynasz od nowa', 'warn', 800);
      }
      prog = 0;
      D.x = I.x;
      D.y = I.y;
      W.Audio.drill(false);
    }
    game.progress((cur + prog) / holes.length);
    if (time <= 0 || I.hit('Enter')) finish();
  };

  st.render = g => {
    game.drawWork(g);
    /* penetrant – czerwona rysa na białym wywoływaczu */
    g.save();
    g.fillStyle = `rgba(245,245,240,${0.55 * Math.min(1, reveal * 2)})`;
    g.fillRect(0, 0, W.VW, W.VH);
    const upto = Math.floor(path.n * reveal);
    g.strokeStyle = 'rgba(200,10,20,0.85)';
    g.lineWidth = 2.2;
    g.shadowColor = 'rgba(255,0,0,0.6)';
    g.shadowBlur = 6;
    g.beginPath();
    for (let i = 0; i < upto; i++) {
      const j = Math.sin(i * 12.9898) * 0.6;
      if (i === 0) g.moveTo(path.x[i] + j, path.y[i] + j);
      else g.lineTo(path.x[i] + j, path.y[i] + j);
    }
    g.stroke();
    g.restore();
    game.particles.render(g);
    if (reveal < 1 || finished) return;
    const h = holes[cur];
    const I = W.Input;
    /* wiertarka */
    const x = I.down ? D.x : I.x, y = I.down ? D.y : I.y;
    g.save();
    g.strokeStyle = 'rgba(20,20,20,0.9)';
    g.lineWidth = 2;
    g.beginPath();
    g.arc(x, y, 5, 0, Math.PI * 2);
    g.stroke();
    if (prog > 0) {
      g.strokeStyle = '#ffb020';
      g.lineWidth = 4;
      g.beginPath();
      g.arc(x, y, 14, -Math.PI / 2, -Math.PI / 2 + prog * Math.PI * 2);
      g.stroke();
    }
    g.translate(x, y);
    g.rotate(0.5);
    g.fillStyle = '#9da3a8';
    g.fillRect(-1.5, -26, 3, 22);
    g.fillStyle = '#1f5fa8';
    g.fillRect(-10, -90, 20, 64);
    g.fillStyle = '#111';
    g.fillRect(-7, -130, 14, 42);
    g.restore();
    /* pasek stabilizacji */
    g.fillStyle = 'rgba(0,0,0,0.5)';
    g.fillRect(20, 680, 200, 10);
    g.fillStyle = locked ? '#c33' : '#4ecdc4';
    g.fillRect(20, 680, 200 * stamina, 10);
    g.fillStyle = '#ddd';
    g.font = '13px Rajdhani, sans-serif';
    g.fillText('STABILIZACJA (SHIFT)', 20, 674);
    void h;
  };

  st.destroy = () => {
    W.Audio.drill(false);
    W.Audio.hiss(false);
  };
  return st;
};
