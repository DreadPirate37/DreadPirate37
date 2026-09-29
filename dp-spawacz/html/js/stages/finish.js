'use strict';
/* ==========================================================================
   Etap 5 – Czyszczenie spoiny
   1 Młotek (żużel, 3 uderzenia) · 2 Skrobak (odpryski) · 3 Szczotka (naloty)
   Po ściegu pośrednim MMA: zostawiony żużel = wtrącenia w kolejnym ściegu!
   ========================================================================== */
W.Stages.finish = (game, arg) => {
  const mid = arg === 'mid';
  const rand = game.rand;
  const st = {};
  const TOOLS = [
    { key: 'hammer', label: 'Młotek', hint: 'żużel' },
    { key: 'scraper', label: 'Skrobak', hint: 'odpryski' },
    { key: 'brush', label: 'Szczotka', hint: 'naloty / przebarwienia' },
  ];
  let tool = 0;

  const slag = game.slag.filter(s => !s.gone);
  const spatter = mid ? [] : game.spatter.filter(s => !s.gone);
  const zones = mid ? [] : game.tintZones.filter(z => !z.gone);
  const total = slag.length * 1 + spatter.length * 0.35 + zones.length * 0.8;
  const TIME = Math.min(32, 6 + slag.length * 0.45 + spatter.length * 0.28 + zones.length * 0.6);
  let time = TIME, wrong = 0, finished = false;
  const cleanLayer = W.canvas();
  const cg = cleanLayer.getContext('2d');

  if (total <= 0) {
    st.update = () => {};
    st.render = g => game.drawWork(g);
    setTimeout(() => game.done('finish', 100, { msg: 'Nic do czyszczenia – czysta robota!', delay: 700 }), 50);
    return st;
  }

  game.title(mid ? 'Usuwanie żużla między ściegami' : 'Czyszczenie spoiny', mid ? 'Każdy kawałek żużla zostawiony = wtrącenie w następnym ściegu' : 'Odpowiednie narzędzie do każdego zabrudzenia');
  game.keys([['1 / 2 / 3', 'narzędzie'], ['KÓŁKO', 'zmiana narzędzia'], ['LPM', 'użyj'], ['ENTER', 'zakończ']]);
  const lines = [];
  if (slag.length) lines.push('<b>Młotek (1)</b> – odbij żużel: 3 uderzenia w każdy kawałek.');
  if (spatter.length) lines.push(`<b>Skrobak (2)</b> – zeskrob odpryski (${spatter.length} szt. – efekt Twojego łuku!).`);
  if (zones.length) lines.push(`<b>Szczotka (3)</b> – przytrzymaj LPM na ${game.M.tint ? 'przebarwieniach' : 'nalotach'} przy spoinie.`);
  lines.push('Złe narzędzie = strata czasu i punktów.');
  game.intro(st, mid ? 'Żużel między ściegami' : 'Czyszczenie', lines, [['1', 'młotek'], ['2', 'skrobak'], ['3', 'szczotka']]);

  const right = document.getElementById('hud-right');
  right.innerHTML = `<div class="tools">${TOOLS.map((tl, i) => `<div class="tool" data-i="${i}"><b>${i + 1}</b>${tl.label}<small>${tl.hint}</small></div>`).join('')}</div>`;
  const toolEls = [...right.querySelectorAll('.tool')];
  const setTool = i => {
    tool = (i + 3) % 3;
    toolEls.forEach((e, k) => e.classList.toggle('on', k === tool));
    W.Audio.click();
  };
  setTool(slag.length ? 0 : spatter.length ? 1 : 2);

  const remainingW = () =>
    slag.filter(s => !s.gone).length + spatter.filter(s => !s.gone).length * 0.35 + zones.filter(z => !z.gone).length * 0.8;

  const finish = () => {
    if (finished) return;
    finished = true;
    W.Audio.brush(false);
    const left = slag.filter(s => !s.gone);
    if (mid && left.length) game.pendingIncl = left.map(s => s.c);
    const removed = 1 - remainingW() / total;
    const score = removed * 100 - wrong * 1.5 + (time / TIME) * 8;
    /* wyczyszczony obraz zostaje */
    game.layers.bead.getContext('2d').drawImage(cleanLayer, 0, 0);
    game.done('finish', W.clamp(score, 0, 100), {
      msg: removed > 0.95 ? 'Wyczyszczone na błysk' : removed > 0.7 ? 'Wyczyszczone' : 'Zostało sporo brudu',
      cls: removed > 0.7 ? 'good' : 'warn',
    });
  };

  const wrongTool = need => {
    wrong++;
    time -= 0.4;
    game.flash(`Tu potrzebny: ${TOOLS[need].label} (${need + 1})`, 'warn', 700);
    W.Audio.bad();
  };

  st.update = dt => {
    if (finished) return;
    const I = W.Input;
    time -= dt;
    game.timer(time);
    if (I.hit('Digit1')) setTool(0);
    if (I.hit('Digit2')) setTool(1);
    if (I.hit('Digit3')) setTool(2);
    if (I.wheel) setTool(tool - I.wheel);

    if (I.clicked) {
      const s = slag.find(s => !s.gone && W.dist(I.x, I.y, s.x, s.y) < s.w + 6);
      const sp = spatter.find(s => !s.gone && W.dist(I.x, I.y, s.x, s.y) < 9);
      if (s) {
        if (tool !== 0) wrongTool(0);
        else {
          s.hits += Math.min(3, I.clicks || 1);
          W.Audio.thud(0.45, 1100 + rand() * 400);
          game.particles.burst(s.x, s.y, 5, 160, 3, 0.7, 0.8);
          if (s.hits >= 3) {
            s.gone = true;
            game.particles.burst(s.x, s.y, 10, 260, 3, 0.9, 1.1);
          }
        }
      } else if (sp) {
        if (tool !== 1) wrongTool(1);
        else {
          sp.gone = true;
          W.Audio.thud(0.2, 3000);
          game.particles.burst(sp.x, sp.y, 3, 90, 1, 0.4, 0.8);
        }
      }
    }
    let brushing = false;
    if (I.down && tool === 2) {
      for (const z of zones) {
        if (z.gone || W.dist(I.x, I.y, z.x, z.y) > z.r + 6) continue;
        const blocked = slag.some(s => !s.gone && W.dist(s.x, s.y, z.x, z.y) < z.r);
        if (blocked) {
          if (rand() < dt * 2) game.flash('Najpierw odbij żużel', 'warn', 600);
          continue;
        }
        brushing = true;
        z.t += dt;
        cg.save();
        cg.globalAlpha = 0.08;
        cg.strokeStyle = '#e9eef2';
        for (let k = 0; k < 3; k++) {
          cg.beginPath();
          cg.moveTo(I.x - 10 + rand() * 20, I.y - 8 + rand() * 16);
          cg.lineTo(I.x - 10 + rand() * 20, I.y - 8 + rand() * 16);
          cg.stroke();
        }
        cg.restore();
        if (z.t > 0.55) {
          z.gone = true;
          W.Audio.tick();
        }
      }
    } else if (I.down && tool !== 2) {
      const z = zones.find(z => !z.gone && W.dist(I.x, I.y, z.x, z.y) < z.r);
      const hitSomething = slag.some(s => !s.gone && W.dist(I.x, I.y, s.x, s.y) < s.w + 6) || spatter.some(s => !s.gone && W.dist(I.x, I.y, s.x, s.y) < 9);
      if (z && I.clicked && !hitSomething) wrongTool(2);
    }
    W.Audio.brush(brushing);
    const rem = remainingW();
    game.progress(1 - rem / total);
    if (rem <= 0.001 || time <= 0 || I.hit('Enter')) finish();
  };

  st.render = g => {
    game.drawWork(g);
    g.drawImage(cleanLayer, 0, 0);
    /* naloty */
    for (const z of zones) {
      if (z.gone) continue;
      const a = W.clamp(1 - z.t / 0.55, 0, 1);
      const gr = g.createRadialGradient(z.x, z.y, 2, z.x, z.y, z.r);
      gr.addColorStop(0, game.M.tint ? `rgba(70,60,150,${0.5 * a})` : `rgba(25,22,20,${0.55 * a})`);
      gr.addColorStop(0.7, game.M.tint ? `rgba(200,150,50,${0.35 * a})` : `rgba(40,35,30,${0.3 * a})`);
      gr.addColorStop(1, 'rgba(0,0,0,0)');
      g.fillStyle = gr;
      g.beginPath();
      g.arc(z.x, z.y, z.r, 0, Math.PI * 2);
      g.fill();
    }
    game.drawSpatter(g);
    /* żużel */
    for (const s of slag) {
      if (s.gone) continue;
      g.save();
      g.translate(s.x + (s.hits ? (Math.random() - 0.5) * s.hits : 0), s.y);
      g.rotate(s.ang);
      const gr = g.createLinearGradient(0, -s.w, 0, s.w);
      gr.addColorStop(0, '#5a4a36');
      gr.addColorStop(0.5, '#2c241c');
      gr.addColorStop(1, '#4a3d2e');
      g.fillStyle = gr;
      g.beginPath();
      const rr = W.rng(Math.floor(s.seed * 1e9));
      for (let k = 0; k < 7; k++) {
        const a = (k / 7) * Math.PI * 2;
        const rx = 11 * (0.75 + rr() * 0.4), ry = s.w * (0.8 + rr() * 0.3);
        const px = Math.cos(a) * rx, py = Math.sin(a) * ry;
        if (k === 0) g.moveTo(px, py);
        else g.lineTo(px, py);
      }
      g.closePath();
      g.fill();
      g.strokeStyle = 'rgba(255,230,180,0.18)';
      g.stroke();
      if (s.hits) {
        g.strokeStyle = 'rgba(0,0,0,0.7)';
        g.beginPath();
        g.moveTo(-6, -s.w * 0.5);
        g.lineTo(3, s.w * 0.4);
        g.stroke();
      }
      g.restore();
    }
    game.particles.render(g);
    /* kursor-narzędzie */
    const I = W.Input;
    g.save();
    g.translate(I.x, I.y);
    if (tool === 0) {
      g.rotate(I.down ? -0.2 : -0.7);
      g.fillStyle = '#8a5a2b';
      g.fillRect(-3, 0, 6, 70);
      g.fillStyle = '#6d7277';
      g.fillRect(-16, -8, 32, 12);
    } else if (tool === 1) {
      g.rotate(-0.6);
      g.fillStyle = '#b8bec3';
      g.fillRect(-7, -2, 14, 22);
      g.fillStyle = '#c1121f';
      g.fillRect(-5, 20, 10, 55);
    } else {
      g.rotate(-0.5);
      g.fillStyle = '#9b7a4d';
      g.fillRect(-18, 10, 36, 10);
      g.fillRect(-4, 20, 8, 60);
      g.fillStyle = '#c9cdd1';
      for (let k = -16; k <= 16; k += 3) g.fillRect(k, 0, 1.2, 10);
    }
    g.restore();
  };

  st.destroy = () => W.Audio.brush(false);
  return st;
};
