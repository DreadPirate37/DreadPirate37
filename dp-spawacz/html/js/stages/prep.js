'use strict';
/* ==========================================================================
   Etap 2 – Przygotowanie powierzchni
   Szlifierka (LPM) zbiera rdzę i farbę, odtłuszczacz (PPM) zmywa olej.
   Szlifowanie po oleju go rozmazuje, zbyt długie szlifowanie czystej blachy
   robi podcięcia. Brud zostawiony w strefie spawania = pory w spoinie.
   ========================================================================== */
W.Stages.prep = game => {
  const t = game.task, path = game.piece.path, rand = game.rand, zone = game.piece.zone;
  const GS = 8, COLS = W.VW / GS, ROWS = W.VH / GS, NC = COLS * ROWS;
  const rust = new Float32Array(NC), oil = new Float32Array(NC), hard = new Float32Array(NC).fill(1);
  const inZone = new Uint8Array(NC), ground = new Float32Array(NC), gouged = new Uint8Array(NC);
  const rustCv = W.canvas(), oilCv = W.canvas();
  const rg = rustCv.getContext('2d'), og = oilCv.getContext('2d');
  const marks = game.layers.marks.getContext('2d');
  const diff = t.difficulty;
  const st = {};
  const TIME = 26 - diff * 1.5;

  /* strefa spawania */
  const zc = Math.ceil(zone / GS);
  for (let i = 0; i < path.n; i += 2) {
    const cx = Math.floor(path.x[i] / GS), cy = Math.floor(path.y[i] / GS);
    for (let y = cy - zc; y <= cy + zc; y++) {
      for (let x = cx - zc; x <= cx + zc; x++) {
        if (x < 0 || y < 0 || x >= COLS || y >= ROWS) continue;
        if (W.dist((x + 0.5) * GS, (y + 0.5) * GS, path.x[i], path.y[i]) <= zone) inZone[y * COLS + x] = 1;
      }
    }
  }

  /* zabrudzenia */
  const paintCol = rand.pick(['#2f5f8f', '#8f2f2a', '#3f6f3a', '#b88a1f']);
  const blobs = 9 + diff * 2 + (t.type === 'patch' ? 3 : 0);
  for (let b = 0; b < blobs; b++) {
    const i = rand.int(0, path.n - 1);
    const off = rand.range(-zone * 0.8, zone * 0.8);
    const bx = path.x[i] + path.nx[i] * off, by = path.y[i] + path.ny[i] * off;
    const r = rand.range(18, 44);
    const roll = rand();
    const type = roll < 0.58 ? 'rust' : roll < 0.82 ? 'paint' : 'oil';
    const x0 = Math.max(0, Math.floor((bx - r) / GS)), x1 = Math.min(COLS - 1, Math.floor((bx + r) / GS));
    const y0 = Math.max(0, Math.floor((by - r) / GS)), y1 = Math.min(ROWS - 1, Math.floor((by + r) / GS));
    for (let y = y0; y <= y1; y++) {
      for (let x = x0; x <= x1; x++) {
        const d = W.dist((x + 0.5) * GS, (y + 0.5) * GS, bx, by) / r;
        if (d > 1) continue;
        const a = W.clamp((1 - d * d) * (0.7 + rand() * 0.6), 0, 1);
        const c = y * COLS + x;
        if (type === 'oil') oil[c] = Math.min(1, oil[c] + a);
        else {
          rust[c] = Math.min(1, rust[c] + a);
          if (type === 'paint') hard[c] = 1.7;
        }
      }
    }
    /* wygląd */
    if (type === 'oil') {
      const gr = og.createRadialGradient(bx, by, 2, bx, by, r);
      gr.addColorStop(0, 'rgba(20,16,10,0.6)');
      gr.addColorStop(0.7, 'rgba(40,30,60,0.32)');
      gr.addColorStop(1, 'rgba(30,60,40,0)');
      og.fillStyle = gr;
      og.beginPath();
      og.arc(bx, by, r, 0, Math.PI * 2);
      og.fill();
    } else {
      for (let k = 0; k < r * 9; k++) {
        const a = rand() * Math.PI * 2, d = Math.sqrt(rand()) * r;
        const x = bx + Math.cos(a) * d, y = by + Math.sin(a) * d;
        if (type === 'rust') {
          rg.fillStyle = `rgba(${120 + rand() * 70},${50 + rand() * 40},${15 + rand() * 20},${0.35 + rand() * 0.5})`;
          rg.beginPath();
          rg.arc(x, y, 1 + rand() * 3.5 * (1 - d / r), 0, Math.PI * 2);
          rg.fill();
        } else {
          rg.fillStyle = paintCol;
          rg.globalAlpha = 0.85;
          rg.fillRect(x, y, 2 + rand() * 5, 2 + rand() * 5);
          rg.globalAlpha = 1;
        }
      }
    }
  }

  let initial = 0;
  for (let c = 0; c < NC; c++) if (inZone[c]) initial += rust[c] + oil[c];
  initial = Math.max(initial, 1);

  const G = { x: 640, y: 360, rpm: 0, ang: 0 };
  let time = TIME, remaining = 1, doneT = 0, finished = false;

  game.title('Przygotowanie powierzchni', 'Oczyść strefę spawania (przerywane linie) do czystego metalu');
  game.keys([['LPM', 'szlifierka – rdza i farba'], ['PPM', 'odtłuszczacz – olej'], ['ENTER', 'zakończ']]);
  game.intro(st, 'Przygotowanie powierzchni', [
    'Rdza, farba i olej w strefie spawania powodują <b>pory</b> w spoinie.',
    '<b>Szlifierka (LPM)</b> zdziera rdzę i farbę. Farba schodzi wolniej.',
    '<b>Nie szlifuj oleju</b> – tarcza go rozmazuje. Najpierw <b>odtłuszczacz (PPM)</b>.',
    'Nie trzymaj tarczy za długo w jednym miejscu czystej blachy – zrobisz <b>podcięcie</b>.',
    `Masz <b>${TIME.toFixed(0)} s</b>. Szybciej = premia czasowa.`,
  ]);

  const cellsIn = (x, y, r, fn) => {
    const x0 = Math.max(0, Math.floor((x - r) / GS)), x1 = Math.min(COLS - 1, Math.floor((x + r) / GS));
    const y0 = Math.max(0, Math.floor((y - r) / GS)), y1 = Math.min(ROWS - 1, Math.floor((y + r) / GS));
    for (let cy = y0; cy <= y1; cy++) {
      for (let cx = x0; cx <= x1; cx++) {
        const d = W.dist((cx + 0.5) * GS, (cy + 0.5) * GS, x, y);
        if (d <= r) fn(cy * COLS + cx, cx, cy, d);
      }
    }
  };

  const finish = () => {
    if (finished) return;
    finished = true;
    W.Audio.grinder(0);
    W.Audio.hiss(false);
    const clean = 1 - remaining;
    let gouges = 0;
    for (let c = 0; c < NC; c++) gouges += gouged[c];
    game.def.gouge += gouges;
    const score = 100 * Math.pow(W.clamp(clean, 0, 1), 1.4) - gouges * 3.5 + (time / TIME) * 12;
    game.dirtAt = (x, y) => {
      const cx = Math.floor(x / GS), cy = Math.floor(y / GS);
      if (cx < 0 || cy < 0 || cx >= COLS || cy >= ROWS) return 0;
      const c = cy * COLS + cx;
      return rust[c] + oil[c];
    };
    /* resztki brudu zostają na obrazie detalu */
    const bg = game.piece.base.getContext('2d');
    bg.drawImage(rustCv, 0, 0);
    bg.drawImage(oilCv, 0, 0);
    game.done('prep', W.clamp(score, 0, 100), {
      msg: clean > 0.95 ? 'Czysto jak w aptece!' : clean > 0.8 ? 'Powierzchnia przygotowana' : 'Zostało sporo brudu…',
      cls: clean > 0.8 ? 'good' : 'warn',
    });
  };

  st.update = dt => {
    if (finished) return;
    const I = W.Input;
    time -= dt;
    game.timer(time);
    G.x += (I.x - G.x) * Math.min(1, dt * 11);
    G.y += (I.y - G.y) * Math.min(1, dt * 11);
    const grinding = I.down;
    G.rpm = W.clamp(G.rpm + (grinding ? dt / 0.35 : -dt / 0.6), 0, 1);
    G.ang += G.rpm * dt * 60;
    W.Audio.grinder(G.rpm);
    const R = 22;

    if (G.rpm > 0.2) {
      let onMetal = false, onOil = false;
      cellsIn(G.x, G.y, R, c => {
        if (oil[c] > 0.08) {
          onOil = true;
          /* rozmazywanie oleju */
          if (rand() < dt * 4) {
            const a = rand() * Math.PI * 2, d = R + rand() * 20;
            const nx = G.x + Math.cos(a) * d, ny = G.y + Math.sin(a) * d;
            /* olej jest przenoszony, nie tworzony */
            const moved = Math.min(oil[c], 0.3);
            oil[c] -= moved;
            let k = 0;
            cellsIn(nx, ny, 10, () => k++);
            cellsIn(nx, ny, 10, c2 => (oil[c2] = Math.min(1, oil[c2] + moved / Math.max(1, k))));
            const gr = og.createRadialGradient(nx, ny, 1, nx, ny, 12);
            gr.addColorStop(0, 'rgba(20,16,10,0.3)');
            gr.addColorStop(1, 'rgba(20,16,10,0)');
            og.fillStyle = gr;
            og.beginPath();
            og.arc(nx, ny, 12, 0, Math.PI * 2);
            og.fill();
          }
        }
        if (rust[c] > 0) {
          rust[c] = Math.max(0, rust[c] - (dt * 4.2 * G.rpm) / hard[c] * (oil[c] > 0.1 ? 0.45 : 1));
        } else if (inZone[c]) {
          onMetal = true;
          ground[c] += dt * G.rpm;
          if (ground[c] > 0.9 && !gouged[c]) {
            gouged[c] = 1;
            const cx = (c % COLS + 0.5) * GS, cy = (Math.floor(c / COLS) + 0.5) * GS;
            marks.fillStyle = 'rgba(15,15,18,0.35)';
            marks.beginPath();
            marks.ellipse(cx, cy, 7, 3, rand() * 3, 0, Math.PI * 2);
            marks.fill();
            W.Audio.thud(0.15, 2500);
          }
        }
      });
      /* obraz: ścieranie rdzy/farby */
      rg.save();
      rg.globalCompositeOperation = 'destination-out';
      rg.globalAlpha = Math.min(1, dt * 5.5 * G.rpm);
      rg.beginPath();
      rg.arc(G.x, G.y, R, 0, Math.PI * 2);
      rg.fill();
      rg.restore();
      /* połysk szlifu */
      for (let k = 0; k < (onMetal ? 1 : 0); k++) {
        marks.strokeStyle = `rgba(235,240,245,${0.025 + rand() * 0.03})`;
        marks.lineWidth = 1;
        marks.beginPath();
        marks.arc(G.x + (rand() - 0.5) * 16, G.y + (rand() - 0.5) * 16, 10 + rand() * 14, rand() * 6, rand() * 6 + 1.2);
        marks.stroke();
      }
      const n = Math.floor(dt * 220 * G.rpm);
      for (let k = 0; k < n; k++) {
        const a = -0.4 + (rand() - 0.5) * 0.9;
        const s = 350 + rand() * 450;
        game.particles.emit(G.x + R * 0.7, G.y + 6, Math.cos(a) * s, Math.sin(a) * s * 0.6, 0.25 + rand() * 0.35, 0, onMetal ? 1 : 0.7);
      }
      if (onOil && rand() < dt * 3) game.flash('Rozmazujesz olej! Najpierw odtłuszczacz (PPM)', 'warn', 900);
    }

    const spraying = I.rdown;
    W.Audio.hiss(spraying);
    if (spraying) {
      cellsIn(I.x, I.y, 34, c => (oil[c] = Math.max(0, oil[c] - dt * 3.2)));
      og.save();
      og.globalCompositeOperation = 'destination-out';
      og.globalAlpha = Math.min(1, dt * 5.5);
      og.beginPath();
      og.arc(I.x, I.y, 34, 0, Math.PI * 2);
      og.fill();
      og.restore();
      for (let k = 0; k < 3; k++) game.particles.emit(I.x + (rand() - 0.5) * 40, I.y + (rand() - 0.5) * 40, (rand() - 0.5) * 30, (rand() - 0.5) * 30, 0.6, 2, 1.5);
    }

    let cur = 0;
    for (let c = 0; c < NC; c++) if (inZone[c]) cur += rust[c] + oil[c];
    remaining = W.clamp(cur / initial, 0, 1);
    game.progress(1 - remaining);

    if (remaining < 0.03) {
      doneT += dt;
      if (doneT > 0.4) finish();
    }
    if (time <= 0 || I.hit('Enter')) finish();
  };

  st.render = g => {
    game.drawWork(g);
    g.drawImage(rustCv, 0, 0);
    g.drawImage(oilCv, 0, 0);
    /* strefa */
    g.save();
    g.setLineDash([10, 8]);
    g.lineWidth = 1.5;
    g.strokeStyle = 'rgba(255,190,40,0.55)';
    path.strokeOffset(g, zone);
    path.strokeOffset(g, -zone);
    g.restore();
    game.particles.render(g);
    /* szlifierka */
    const I = W.Input;
    g.save();
    g.translate(G.x, G.y);
    g.fillStyle = '#5a5f63';
    g.beginPath();
    g.arc(0, 0, 22, 0, Math.PI * 2);
    g.fill();
    g.strokeStyle = 'rgba(255,255,255,0.35)';
    g.lineWidth = 1;
    for (let k = 0; k < 6; k++) {
      const a = G.ang + (k * Math.PI) / 3;
      g.beginPath();
      g.moveTo(Math.cos(a) * 5, Math.sin(a) * 5);
      g.lineTo(Math.cos(a) * 20, Math.sin(a) * 20);
      g.stroke();
    }
    g.fillStyle = '#26292c';
    g.beginPath();
    g.arc(0, 0, 25, Math.PI * 0.95, Math.PI * 2.05);
    g.fill();
    g.fillStyle = '#e8a317';
    g.fillRect(-12, -70, 24, 44);
    g.fillStyle = '#222';
    g.fillRect(-9, -140, 18, 72);
    g.restore();
    if (I.rdown) {
      g.strokeStyle = 'rgba(160,210,255,0.6)';
      g.setLineDash([4, 4]);
      g.beginPath();
      g.arc(I.x, I.y, 34, 0, Math.PI * 2);
      g.stroke();
      g.setLineDash([]);
    }
  };

  st.destroy = () => {
    W.Audio.grinder(0);
    W.Audio.hiss(false);
  };
  return st;
};
