'use strict';
/* ==========================================================================
   Etap 4 – SPAWANIE (serce minigry)

   Gracz prowadzi palnik po złączu i jednocześnie pilnuje:
   • długości łuku (kółko myszy) – łuk dryfuje, elektroda MMA się skraca,
   • prędkości posuwu – za wolno = przegrzanie/przepalenie, za szybko = brak przetopu,
   • ciepła – lokalnego (jeziorko) i całego detalu (temp. międzyściegowa),
   • drżenia ręki (SHIFT stabilizuje, ale męczy),
   • materiałów: wymiana elektrody / czyszczenie dyszy / dodawanie spoiwa TIG,
   • zdarzeń losowych: podmuch wiatru, dym, przywarcie elektrody.
   Ściegi wypełniające i licowe wymagają ZAKOSÓW (ruch wahadłowy), bo liczy się
   pokrycie całej szerokości rowka.
   ========================================================================== */
W.Stages.weld = (game, arg) => {
  const passIdx = Number(arg) || 0;
  const t = game.task, path = game.piece.path, rand = game.rand, noise = game.noise;
  const P = game.P, M = game.M, POS = game.POS, S = game.setup;
  const proc = t.process, diff = t.difficulty;
  const passes = t.passes;
  const isCap = passes > 1 && passIdx === passes - 1;
  const isFill = passIdx > 0 && !isCap;
  const B = isCap ? 20 : isFill ? 13 : 0;
  const BINS = B > 0 ? 5 : 1;
  const st = {};

  const vIdeal = P.v * M.speed * (B > 0 ? 0.6 : 1);
  const poolR = P.poolR * (S.poolMul || 1);
  const latR = B > 0 ? poolR * 0.75 : poolR * 1.25;
  const CELL = 10;
  const N = Math.max(8, Math.ceil(path.len / CELL));
  const fillNeed = 1 + (1 - (game.fitup ?? 1)) * 0.35;
  const R1 = (vIdeal / poolR) * 1.12;
  const RB = ((vIdeal * 2 * B) / (poolR * latR)) * 1.1;
  const binC = new Float32Array(BINS);
  for (let b = 0; b < BINS; b++) binC[b] = BINS === 1 ? 0 : -0.75 * B + (1.5 * B * b) / (BINS - 1);

  const fill = new Float32Array(N * BINS);
  const heat = new Float32Array(N), maxHeat = new Float32Array(N);
  const aw = new Float32Array(N), alat = new Float32Array(N), aspd = new Float32Array(N), aarc = new Float32Array(N);
  const burn = new Uint8Array(N), poro = new Uint8Array(N), incl = new Uint8Array(N), sag = new Uint8Array(N);
  const dirt = new Float32Array(N);
  for (let c = 0; c < N; c++) {
    const i = path.idx((c + 0.5) * CELL);
    dirt[c] = W.clamp(game.dirtAt(path.x[i], path.y[i]), 0, 1.5);
  }
  if (game.pendingIncl) {
    for (const c of game.pendingIncl) if (c < N) incl[c] = 1;
    game.pendingIncl = null;
  }

  const ampF = S.ampF, heatIn = 1.15 * Math.pow(ampF, 1.6) * M.heat * POS.heat * P.heat * (B > 0 ? 0.62 : 1);
  const burnT = M.burn - (t.position === 'overhead' ? 0.05 : 0);
  const coolK = 0.38 * M.cool;
  const interpassC = M.interpass;
  const tempC = () => Math.round(20 + game.partT * 650);
  const bead = game.layers.bead.getContext('2d');
  const cols = M.bead;
  const visR = 200 - diff * 14;
  const limitTime = (path.len / vIdeal) * 2.6 + 25;

  /* stan */
  const T = { x: W.Input.x, y: W.Input.y, ex: 0, ey: 0 };
  let arcOn = false, needRelease = false, L = 0.5, Lv = 0, stamina = 1, locked = false;
  let electrode = 1, clog = 0, filler = 0.6, tungDirty = false, stuck = false, stuckHits = 0;
  let busy = 0, busyKind = '', vEma = 0, lastS = null, lastDep = null, passTime = 0, arcTime = 0;
  let strayT = 0, strayMarked = false, finished = false, idleDone = 0, enterArm = 0;
  let evt = null, evtT = 0, nextEvt = 7 + rand() * 6, nt = rand() * 100, fillerCd = 0, flick = 1;
  let started = false, rhythm = '', rhythmT = 0;
  const burnRate = 1 / Math.max(6, (0.45 * path.len) / vIdeal);

  const passName = W.PASS_NAMES[passes === 1 ? 0 : isCap ? 2 : passIdx === 0 ? 0 : 1];
  game.title(`Spawanie – ścieg ${passName.toLowerCase()} (${passIdx + 1}/${passes})`, B > 0 ? 'Prowadź zakosami – pokryj całą szerokość rowka' : 'Prowadź dokładnie po linii złącza');

  const keyList = [['LPM', 'łuk'], ['KÓŁKO', 'długość łuku'], ['SHIFT', 'stabilizacja']];
  if (proc === 'MMA') keyList.push(['R', 'nowa elektroda'], ['SPACJA', 'odrywanie']);
  if (proc === 'MAG') keyList.push(['R', 'czyść dyszę']);
  if (proc === 'TIG') keyList.push(['SPACJA', 'dodaj spoiwo'], ['R', 'ostrz wolfram']);
  keyList.push(['C', 'chłodzenie'], ['ENTER', 'zakończ ścieg']);
  game.keys(keyList);

  const introLines = [
    `Metoda: <b>${P.name}</b>. Idealny posuw: zielone pole na wskaźniku prędkości.`,
    '<b>Kółkiem myszy</b> trzymaj długość łuku w zielonym polu. Za krótki = przywieranie, za długi = pory i odpryski, zgaśnięcie.',
    'Za wolno = <b>przegrzanie i przepalenie</b>. Za szybko = <b>brak przetopu</b>. Pod przyłbicą widać tylko okolicę jeziorka!',
  ];
  if (B > 0) introLines.push('<b>Ścieg z zakosami:</b> prowadź ruchem wahadłowym od krawędzi do krawędzi rowka (przerywane linie). Nie pokryte brzegi = <b>podtopienia</b>.');
  if (proc === 'MMA') introLines.push('Elektroda się <b>skraca</b> – łuk sam się wydłuża, dociskaj kółkiem. Gdy się skończy: <b>R</b>. Przywarła? Stukaj <b>SPACJĘ</b>.');
  if (proc === 'MAG') introLines.push('Odpryski zapychają <b>dyszę</b> – przy czerwonym pasku wyczyść ją klawiszem <b>R</b>, inaczej pory.');
  if (proc === 'TIG') introLines.push('Rytmicznie <b>dodawaj spoiwo (SPACJA)</b>, trzymając poziom w zielonym polu. Za krótki łuk = brudny wolfram (<b>R</b>).');
  if (passIdx > 0) introLines.push(`Temperatura międzyściegowa max <b>${interpassC}°C</b> – w razie potrzeby schłodź detal (<b>C</b>).`);
  game.intro(st, `Ścieg ${passName.toLowerCase()} ${passIdx + 1}/${passes}`, introLines, keyList.slice(0, 5));

  /* ---------------- HUD ---------------- */
  const left = document.getElementById('hud-left');
  const right = document.getElementById('hud-right');
  left.innerHTML = `
    <div class="gauge v" id="gArc"><div class="band" style="top:38%;height:24%"></div><div class="needle"></div><label>ŁUK</label><small>dł.</small></div>
    <div class="gauge v" id="gHeat"><div class="bar"></div><div class="mark" style="bottom:${(0.8 / 1.2) * 100}%"></div><div class="mark red" style="bottom:${(burnT / 1.2) * 100}%"></div><label>JEZIORKO</label></div>
    <div class="readout"><small>DETAL</small><b id="rTemp">20°C</b><small id="rTempMax">max ${interpassC}°C</small></div>`;
  const spdBand = [0.5 + Math.log(1 / 1.45) / Math.log(4) / 2, 0.5 + Math.log(1.45) / Math.log(4) / 2];
  let consHtml = '';
  if (proc === 'MMA') consHtml = '<div class="meter" id="mCons"><label>ELEKTRODA <b>R</b></label><div><i></i></div></div>';
  if (proc === 'MAG') consHtml = '<div class="meter" id="mCons"><label>DYSZA (zapchanie) <b>R</b></label><div><i></i></div></div>';
  if (proc === 'TIG') consHtml = '<div class="meter band" id="mCons"><label>SPOIWO <b>SPACJA</b> <em id="rhythm"></em></label><div><span style="left:25%;width:50%"></span><i></i></div></div>';
  right.innerHTML = `
    <div class="gauge h" id="gSpd"><div class="band" style="left:${spdBand[0] * 100}%;width:${(spdBand[1] - spdBand[0]) * 100}%"></div><div class="needle"></div><label>PRĘDKOŚĆ POSUWU</label><small class="l">wolno</small><small class="r">szybko</small></div>
    ${consHtml}
    <div class="meter" id="mSteady"><label>STABILIZACJA <b>SHIFT</b></label><div><i></i></div></div>
    <div class="meter" id="mCov"><label>POKRYCIE ZŁĄCZA</label><div><i></i></div></div>`;
  const q = s => document.querySelector(s);
  const H = {
    arc: q('#gArc .needle'), heat: q('#gHeat .bar'), temp: q('#rTemp'), spd: q('#gSpd .needle'),
    cons: q('#mCons i'), steady: q('#mSteady i'), cov: q('#mCov i'), rhythm: q('#rhythm'),
  };

  const post = on => W.post('arc', { on, proc });

  const cellFill = c => {
    if (BINS === 1) return fill[c];
    let s = 0;
    for (let b = 0; b < BINS; b++) s += Math.min(fill[c * BINS + b], 1.8);
    return s / BINS;
  };
  const coverage = () => {
    let k = 0;
    for (let c = 0; c < N; c++) if (cellFill(c) >= 0.72) k++;
    return k / N;
  };

  const addSpatter = (x, y) => {
    if (game.spatter.length > 160) return;
    const a = rand() * Math.PI * 2, d = 14 + rand() * 55;
    game.spatter.push({ x: x + Math.cos(a) * d, y: y + Math.sin(a) * d, r: 1.2 + rand() * 1.8, gone: false });
    game.def.spatter++;
  };

  const startBusy = (kind, dur, msg) => {
    busy = dur;
    busyKind = kind;
    game.flash(msg, 'info', dur * 1000);
    W.Audio.click();
  };

  /* ---------------- zakończenie ściegu ---------------- */
  const finishPass = () => {
    if (finished) return;
    finished = true;
    if (arcOn) { arcOn = false; post(false); }
    W.Audio.arc(false, proc);
    let sum = 0, lofRun = false, ucRun = false, poroRun = false;
    const cellQ = new Float32Array(N);
    const fusion = ampF < 0.85 ? W.lerp(0.7, 1, W.clamp((ampF - 0.6) / 0.25, 0, 1)) : 1;
    for (let c = 0; c < N; c++) {
      const f = cellFill(c);
      const w = aw[c] || 1e-6;
      const lat = alat[c] / w, spd = aspd[c] / w, arcE = aarc[c] / w;
      let fillS = f < 0.75 ? W.smooth(0.2, 0.75, f) : f > 1.7 ? 1 - W.smooth(1.7, 2.8, f) * 0.6 : 1;
      const accS = 1 - W.clamp(lat, 0, 1);
      const spdS = aw[c] > 0 ? W.gauss(spd, 0.45) : 0;
      const arcS = 1 - W.clamp(arcE, 0, 1);
      const heatS = burn[c] ? 0 : maxHeat[c] > 0.8 ? 0.75 : 1;
      let s = 0.35 * fillS + 0.2 * accS + 0.2 * spdS + 0.15 * arcS + 0.1 * heatS;
      let undercut = false;
      if (BINS > 1) {
        const edge = Math.min(fill[c * BINS], fill[c * BINS + BINS - 1]);
        if (edge < 0.28) { s -= 0.2; undercut = true; }
      }
      if (poro[c]) s -= 0.25;
      if (incl[c]) s -= 0.35;
      if (sag[c]) s -= 0.2;
      if (f < 0.3) s = 0.05;
      s = W.clamp(s * fusion, 0, 1);
      cellQ[c] = s;
      sum += s;
      /* zliczanie wad (ciągi komórek = jedna wada) */
      if (f < 0.3 && !lofRun) game.def.lof++;
      lofRun = f < 0.3;
      if (undercut && !ucRun) game.def.undercut++;
      ucRun = undercut;
      if (poro[c] && !poroRun) game.def.poro++;
      poroRun = !!poro[c];
      if (incl[c]) game.def.incl += 0.34;
      if (sag[c]) game.def.sag++;
      if (burn[c]) game.def.burn++;
    }
    game.def.incl = Math.round(game.def.incl * 100) / 100;
    const score = (sum / N) * 100;

    /* dane do RTG i czyszczenia */
    game.cells = game.cells || [];
    const fills = new Float32Array(N);
    for (let c = 0; c < N; c++) fills[c] = cellFill(c);
    game.cells.push({ N, CELL, B, fills, burn, poro, incl, sag, cellQ, maxHeat });

    /* żużel (MMA) */
    game.slag = [];
    if (P.slag) {
      for (let c = 0; c < N; c += 2) {
        if (fills[c] < 0.3) continue;
        const i = path.idx((c + 1) * CELL);
        game.slag.push({ c, x: path.x[i], y: path.y[i], ang: path.ang[i], w: B > 0 ? B + 6 : poolR * 0.9, hits: 0, gone: false, seed: rand() });
      }
    }
    /* przebarwienia / naloty do szczotkowania */
    game.tintZones = [];
    for (let c = 0; c < N; c += 5) {
      let mh = 0;
      for (let k = c; k < Math.min(N, c + 5); k++) mh = Math.max(mh, maxHeat[k]);
      if (mh < 0.35 && !(proc === 'MAG' && c % 10 === 0)) continue;
      const i = path.idx((c + 2.5) * CELL);
      game.tintZones.push({ x: path.x[i], y: path.y[i], ang: path.ang[i], r: (B || poolR) + 14, t: 0, heat: mh, gone: false });
    }
    /* trwałe przebarwienia na obrazie */
    if (M.tint || proc !== 'TIG') {
      for (const z of game.tintZones) {
        const gr = bead.createRadialGradient(z.x, z.y, 4, z.x, z.y, z.r);
        const a = W.clamp(z.heat, 0, 1) * 0.35;
        gr.addColorStop(0, M.tint ? `rgba(60,70,160,${a})` : `rgba(20,20,20,${a})`);
        gr.addColorStop(0.6, M.tint ? `rgba(190,150,60,${a})` : `rgba(40,35,30,${a * 0.6})`);
        gr.addColorStop(1, 'rgba(0,0,0,0)');
        bead.fillStyle = gr;
        bead.beginPath();
        bead.arc(z.x, z.y, z.r, 0, Math.PI * 2);
        bead.fill();
      }
    }
    const cov = coverage();
    game.done('weld', score, {
      msg: score >= 85 ? 'Piękny ścieg!' : score >= 65 ? 'Ścieg poprawny' : cov < 0.8 ? 'Niepełny ścieg – duże braki' : 'Ścieg z wadami',
      cls: score >= 65 ? 'good' : 'bad',
      delay: 1100,
    });
  };

  /* ---------------- aktualizacja ---------------- */
  st.onStart = () => {
    T.x = W.Input.x;
    T.y = W.Input.y;
  };

  st.update = dt => {
    if (finished) return;
    const I = W.Input;
    passTime += dt;
    nt += dt;

    /* chłodzenie sprężonym powietrzem */
    const air = I.key('KeyC') && !arcOn;
    W.Audio.hiss(air, 0.1);
    game.partT = Math.max(0, game.partT - dt * (arcOn ? 0.004 : 0.012) * M.cool - (air ? dt * 0.06 : 0));
    const tooHot = !started && passIdx > 0 && tempC() > interpassC;

    /* stabilizacja */
    const wantSteady = I.key('ShiftLeft') || I.key('ShiftRight');
    if (wantSteady && !locked) stamina -= dt * 0.3;
    else stamina += dt * 0.14;
    if (stamina <= 0) { stamina = 0; locked = true; }
    if (locked && stamina > 0.3) locked = false;
    stamina = Math.min(1, stamina);
    const steady = wantSteady && !locked;

    /* drżenie ręki */
    const fatigue = Math.min(3, arcTime * 0.06);
    const tr = (2 + diff * 1.1 + POS.tremor + fatigue) * (steady ? 0.3 : 1) * (evt === 'gust' ? 1.3 : 1);
    T.x += (I.x - T.x) * Math.min(1, dt * 16);
    T.y += (I.y - T.y) * Math.min(1, dt * 16);
    T.ex = T.x + (noise(nt * 1.7) + noise(nt * 4.3 + 50) * 0.5) * tr;
    T.ey = T.y + (noise(nt * 1.9 + 20) + noise(nt * 3.9 + 80) * 0.5) * tr;

    /* długość łuku */
    L += I.wheel * 0.055;
    const drift = P.arcDrift * (evt === 'gust' ? 3 : 1) * (S.polOk ? 1 : 1.8) * (1 + diff * 0.12);
    Lv += (rand() - 0.5) * drift * dt * 8;
    Lv *= Math.pow(0.35, dt);
    L += Lv * dt + (arcOn ? P.creep * dt : 0);
    if (proc === 'MAG' && S.secF > 1.12 && arcOn) L -= dt * 0.06 * (S.secF - 1) * 5;
    L = W.clamp(L, 0, 1);

    /* czynności serwisowe (R) */
    if (busy > 0) {
      busy -= dt;
      if (busy <= 0) {
        busy = 0;
        if (busyKind === 'electrode') electrode = 1;
        if (busyKind === 'nozzle') clog = 0;
        if (busyKind === 'tungsten') tungDirty = false;
        W.Audio.good();
        L = 0.5;
      }
    } else if (I.hit('KeyR') && !arcOn) {
      if (proc === 'MMA' && electrode < 0.98) startBusy('electrode', 0.9, 'Zakładasz nową elektrodę…');
      else if (proc === 'MAG' && clog > 0.05) startBusy('nozzle', 1.1, 'Czyścisz dyszę…');
      else if (proc === 'TIG' && tungDirty) startBusy('tungsten', 1.5, 'Ostrzysz wolfram…');
    }

    /* przywarcie elektrody */
    if (stuck) {
      if (I.hit('Space')) {
        stuckHits++;
        W.Audio.thud(0.4, 700);
        T.x += (rand() - 0.5) * 12;
        if (stuckHits >= 4) {
          stuck = false;
          L = 0.45;
          needRelease = true;
          game.flash('Oderwana!', 'good', 600);
        }
      }
    }

    /* spoiwo TIG */
    fillerCd -= dt;
    rhythmT -= dt;
    if (proc === 'TIG' && I.hit('Space') && fillerCd <= 0 && !stuck) {
      const before = filler;
      filler = Math.min(1.5, filler + 0.38);
      fillerCd = 0.1;
      W.Audio.blip(1200, 0.03, 'triangle', 0.06);
      rhythm = before < 0.25 ? 'SPÓŹNIONE' : before > 0.8 ? 'ZA CZĘSTO' : before < 0.45 ? 'IDEALNIE' : 'OK';
      rhythmT = 0.6;
    }

    /* zajarzanie łuku */
    if (!I.down) needRelease = false;
    const canArc = !busy && !stuck && !tungDirty && !needRelease && !tooHot && (proc !== 'MMA' || electrode > 0);
    const want = I.down && canArc;
    if (I.clicked && tooHot) game.flash(`Detal za gorący (${tempC()}°C) – schłodź do ${interpassC}°C (C)`, 'warn', 1200);
    if (I.clicked && proc === 'MMA' && electrode <= 0) game.flash('Elektroda zużyta – R', 'warn', 900);
    if (I.clicked && tungDirty) game.flash('Brudny wolfram – naostrz (R)', 'warn', 900);
    if (want && !arcOn) {
      arcOn = true;
      started = true;
      lastS = null;
      lastDep = null;
      post(true);
    } else if (!want && arcOn) {
      arcOn = false;
      post(false);
      W.Audio.arc(false, proc);
    }

    /* zdarzenia losowe */
    if (evt) {
      evtT -= dt;
      if (evtT <= 0) evt = null;
    } else if (diff >= 2 && arcOn) {
      nextEvt -= dt;
      if (nextEvt <= 0) {
        evt = rand() < 0.55 ? 'gust' : 'smoke';
        evtT = 3 + rand() * 1.5;
        nextEvt = 11 - diff + rand() * 8;
        game.flash(evt === 'gust' ? 'Podmuch wiatru! Łuk szarpie' : 'Gęsty dym – słaba widoczność', 'warn', 1500);
        W.Audio.warn();
      }
    }

    /* chłodzenie komórek */
    const baseH = game.partT * 0.55;
    const kd = Math.exp(-coolK * dt);
    for (let c = 0; c < N; c++) heat[c] = baseH + (heat[c] - baseH) * kd;

    let curHeat = 0;
    if (arcOn) {
      arcTime += dt;
      const nr = path.nearest(T.ex, T.ey);
      let ds = lastS == null ? 0 : path.ds(lastS, nr.s);
      if (Math.abs(ds) > 40) ds = 0;
      lastS = nr.s;
      vEma += (Math.abs(ds) / dt - vEma) * Math.min(1, dt * 4);
      const latAbs = Math.abs(nr.lat);
      const arcErr = Math.max(0, Math.abs(L - 0.5) - 0.12) / 0.3;
      const spdErr = Math.abs(Math.log(Math.max(vEma, 1) / vIdeal));
      const onJoint = B > 0 ? latAbs <= B + latR : latAbs <= latR * 1.6;
      let fF = 1;
      if (proc === 'TIG') fF = filler < 0.2 ? 0.3 : filler > 1.15 ? 1.25 : 1;
      else if (proc === 'MAG') fF = W.clamp(S.secF, 0.7, 1.3);
      else fF = W.clamp(S.poolMul, 0.8, 1.25);
      const arcF = L > 0.85 ? 0.6 : 1;
      const lh = heatIn * (S.polOk ? 1 : 1.1);

      /* ryzyko porów – na sekundę */
      let poroRisk = arcErr * 2.5 + (S.polOk ? 0 : 0.4);
      if (proc === 'MAG' && clog > 0.7) poroRisk += 1.6;
      if (proc === 'TIG' && !S.secOk) poroRisk += 0.9;
      if (evt === 'gust' && proc !== 'MMA') poroRisk += 1.2;

      if (onJoint) {
        strayT = 0;
        strayMarked = false;
        const cLo = Math.floor((nr.s - poolR) / CELL), cHi = Math.floor((nr.s + poolR) / CELL);
        for (let cr = cLo; cr <= cHi; cr++) {
          let c = cr;
          if (path.closed) c = ((c % N) + N) % N;
          else if (c < 0 || c >= N) continue;
          const delta = Math.abs(path.ds(nr.s, (c + 0.5) * CELL));
          if (delta >= poolR) continue;
          const wa = 1 - delta / poolR;
          heat[c] += dt * lh * wa;
          if (heat[c] > maxHeat[c]) maxHeat[c] = heat[c];
          for (let b = 0; b < BINS; b++) {
            let wl;
            if (BINS === 1) wl = Math.max(0, 1 - Math.pow(latAbs / latR, 2));
            else wl = Math.max(0, 1 - Math.abs(nr.lat - binC[b]) / latR);
            fill[c * BINS + b] += (dt * (BINS === 1 ? R1 : RB) * wa * wl * fF * arcF) / fillNeed;
          }
          aw[c] += dt * wa;
          alat[c] += dt * wa * (B > 0 ? Math.max(0, latAbs - B) / latR : latAbs / latR);
          aspd[c] += dt * wa * spdErr;
          aarc[c] += dt * wa * arcErr;
          const risk = poroRisk + dirt[c] * 3;
          if (!poro[c] && rand() < risk * dt * wa * 0.6) {
            poro[c] = 1;
            const pi = path.idx((c + 0.5) * CELL);
            for (let k = 0; k < 3; k++) {
              bead.fillStyle = 'rgba(15,15,15,0.8)';
              bead.beginPath();
              bead.arc(path.x[pi] + (rand() - 0.5) * 8, path.y[pi] + (rand() - 0.5) * 8, 0.8 + rand() * 1.2, 0, Math.PI * 2);
              bead.fill();
            }
          }
          if (heat[c] > burnT && !burn[c]) {
            burn[c] = 1;
            heat[c] = 0.7;
            const pi = path.idx((c + 0.5) * CELL);
            W.hole(bead, path.x[pi], path.y[pi], 5 + rand() * 3);
            game.flash('PRZEPALENIE! Szybciej lub mniej prądu', 'bad', 1300);
            W.Audio.bad();
            game.particles.burst(path.x[pi], path.y[pi], 40, 300, 4, 0.8, 1.2, Math.PI / 2, 1.2);
          }
          if (heat[c] > POS.drip && !sag[c] && rand() < dt * 3) {
            sag[c] = 1;
            game.flash('Jeziorko spływa – za gorąco w tej pozycji!', 'warn', 1000);
            game.particles.emit(T.ex, T.ey + 4, (rand() - 0.5) * 40, 60, 1.2, 4, 1.4);
          }
          curHeat = Math.max(curHeat, heat[c]);
        }
      } else {
        strayT += dt;
        if (strayT > 0.25 && !strayMarked) {
          strayMarked = true;
          game.def.stray++;
          game.flash('Łuk poza rowkiem!', 'bad', 800);
        }
      }

      game.partT += dt * 0.011 * ampF * (B > 0 ? 1.15 : 1);

      /* materiały eksploatacyjne i przywieranie */
      if (proc === 'MMA') {
        electrode -= dt * burnRate * (S.poolMul > 1 ? 0.85 : 1);
        if (electrode <= 0) {
          electrode = 0;
          arcOn = false;
          post(false);
          game.flash('Elektroda się skończyła – R', 'warn', 1200);
        }
        if (L < 0.1 && arcOn) {
          stuck = true;
          stuckHits = 0;
          arcOn = false;
          post(false);
          const c = W.clamp(Math.floor(nr.s / CELL), 0, N - 1);
          incl[c] = 1;
          game.flash('Elektroda przywarła! Stukaj SPACJĘ', 'bad', 1500);
          W.Audio.thud(0.5, 400);
        }
      } else if (proc === 'MAG') {
        clog = Math.min(1, clog + dt * (0.025 + arcErr * 0.25 + (S.polOk ? 0 : 0.1)));
        if (L < 0.1) {
          L = 0.32;
          game.flash('Drut stuka – za krótki łuk', 'warn', 700);
          for (let k = 0; k < 4; k++) addSpatter(T.ex, T.ey);
          W.Audio.thud(0.3, 1500);
        }
      } else {
        filler = Math.max(0, filler - dt * 0.9);
        if (L < 0.1 && arcOn) {
          tungDirty = true;
          arcOn = false;
          post(false);
          const c = W.clamp(Math.floor(nr.s / CELL), 0, N - 1);
          incl[c] = 1;
          game.flash('Wolfram zanurzony w jeziorku! Ostrz (R)', 'bad', 1400);
        }
      }
      if (L > 0.97 && arcOn) {
        arcOn = false;
        needRelease = true;
        post(false);
        game.flash('Łuk zgasł – za długi!', 'warn', 900);
      }

      /* odpryski */
      let sp = proc === 'TIG' ? 0 : proc === 'MMA' ? 0.6 : 1.0;
      sp += arcErr * 12 + (S.polOk ? 0 : 5) + (proc === 'MAG' && clog > 0.7 ? 5 : 0) + (proc === 'MAG' && !S.secOk ? 4 : 0);
      if (rand() < sp * dt) addSpatter(T.ex, T.ey);

      /* lico spoiny */
      if (!lastDep || W.dist(lastDep.x, lastDep.y, T.ex, T.ey) >= 2 || passTime - lastDep.t > 0.06) {
        const ang = path.ang[nr.i];
        if (onJoint && B > 0) {
          /* ścieg z zakosami: szerokie łuski na osi, szerokość = pokryta część rowka */
          const c = W.clamp(Math.floor(nr.s / CELL), 0, N - 1);
          let covd = 0;
          for (let b = 0; b < BINS; b++) if (fill[c * BINS + b] > 0.3) covd++;
          const w = B * (0.45 + 0.55 * (covd / BINS)) + 3;
          const off = W.clamp(nr.lat, -B, B) * 0.25;
          W.ripple(bead, path.x[nr.i] + path.nx[nr.i] * off, path.y[nr.i] + path.ny[nr.i] * off, ang, w, cols, arcErr > 0.5 ? 0.6 : 0.85);
        } else if (onJoint) {
          const w = W.clamp(poolR * 0.62 * Math.sqrt(W.clamp(vIdeal / Math.max(vEma, 15), 0.5, 2.2)) * fF, 4, 14);
          const px = path.x[nr.i] + path.nx[nr.i] * W.clamp(nr.lat, -latR, latR) * 0.8;
          const py = path.y[nr.i] + path.ny[nr.i] * W.clamp(nr.lat, -latR, latR) * 0.8;
          W.ripple(bead, px, py, ang, w, cols, arcErr > 0.5 ? 0.7 : 1);
        } else {
          W.ripple(bead, T.ex, T.ey, ang, 5, ['#9a9a9a', '#555', 'rgba(40,40,40,0.6)'], 0.8);
        }
        lastDep = { x: T.ex, y: T.ey, t: passTime };
      }

      /* iskry i dźwięk */
      const n = P.sparks * (1 + arcErr * 2 + (S.polOk ? 0 : 1)) * dt;
      for (let k = 0; k < n + (rand() < n % 1 ? 1 : 0); k++) {
        const a = -Math.PI / 2 + (rand() - 0.5) * 2.6;
        const s = 180 + rand() * 420;
        game.particles.emit(T.ex, T.ey, Math.cos(a) * s, Math.sin(a) * s, 0.3 + rand() * 0.5, 0, 0.9);
      }
      if (rand() < dt * 4) game.particles.emit(T.ex, T.ey - 10, (rand() - 0.5) * 20, -30, 2, 5, 1);
      W.Audio.arc(true, proc, arcErr + (S.polOk ? 0 : 0.5));
      flick = 0.85 + rand() * 0.3;
    } else {
      vEma *= Math.pow(0.1, dt);
    }

    /* HUD */
    H.arc.style.top = ((1 - L) * 100).toFixed(1) + '%';
    H.arc.parentElement.classList.toggle('bad', Math.abs(L - 0.5) > 0.12);
    H.heat.style.height = (W.clamp(curHeat / 1.2, 0, 1) * 100).toFixed(1) + '%';
    H.heat.style.background = curHeat > 0.8 ? '#ff4d3d' : curHeat > 0.5 ? '#ffb020' : '#4ecdc4';
    H.temp.textContent = tempC() + '°C';
    H.temp.classList.toggle('bad', tempC() > interpassC);
    const sp = W.clamp(0.5 + Math.log(Math.max(vEma, 1) / vIdeal) / Math.log(4) / 2, 0, 1);
    H.spd.style.left = (arcOn ? sp * 100 : 0).toFixed(1) + '%';
    if (H.cons) {
      const v = proc === 'MMA' ? electrode : proc === 'MAG' ? clog : filler / 1.5;
      H.cons.style.width = (v * 100).toFixed(1) + '%';
      H.cons.parentElement.parentElement.classList.toggle('bad', proc === 'MMA' ? electrode < 0.15 : proc === 'MAG' ? clog > 0.7 : filler < 0.3 || filler > 1.15);
      if (proc === 'TIG') H.cons.style.left = '0';
    }
    if (H.rhythm) H.rhythm.textContent = rhythmT > 0 ? rhythm : '';
    H.steady.style.width = (stamina * 100).toFixed(1) + '%';
    H.steady.parentElement.parentElement.classList.toggle('bad', locked);
    const cov = coverage();
    H.cov.style.width = (cov * 100).toFixed(1) + '%';
    game.progress(cov);
    game.timer(limitTime - passTime, 10);

    /* koniec ściegu */
    if (cov >= 0.97 && !arcOn) {
      idleDone += dt;
      if (idleDone > 0.6) finishPass();
    } else idleDone = 0;
    enterArm -= dt;
    if (I.hit('Enter')) {
      if (cov > 0.9 || enterArm > 0) finishPass();
      else {
        enterArm = 1.5;
        game.flash(`Pokrycie tylko ${(cov * 100).toFixed(0)}% – ENTER ponownie, by zakończyć`, 'warn', 1500);
      }
    }
    if (passTime > limitTime) {
      game.flash('Koniec czasu na ścieg', 'warn', 1000);
      finishPass();
    }
  };

  /* ---------------- rysowanie ---------------- */
  st.render = g => {
    game.drawWork(g);
    game.drawSpatter(g);

    /* żarzenie się świeżej spoiny */
    g.save();
    g.globalCompositeOperation = 'lighter';
    for (let c = 0; c < N; c++) {
      const h = heat[c] - 0.18;
      if (h <= 0 || cellFill(c) < 0.1) continue;
      const i = path.idx((c + 0.5) * CELL);
      g.fillStyle = W.heatColor(h * 1.3) + W.clamp(h * 1.4, 0, 0.85) + ')';
      g.beginPath();
      g.arc(path.x[i], path.y[i], (B || poolR * 0.6) + 3, 0, Math.PI * 2);
      g.fill();
    }
    g.restore();

    const I = W.Input;
    /* prowadnice rowka i podpowiedzi (widoczne bez przyłbicy) */
    if (!arcOn) {
      g.save();
      if (B > 0) {
        g.setLineDash([6, 6]);
        g.strokeStyle = 'rgba(255,200,60,0.5)';
        g.lineWidth = 1.2;
        path.strokeOffset(g, B);
        path.strokeOffset(g, -B);
      }
      if (diff <= 2 || !started) {
        g.fillStyle = 'rgba(255,90,60,0.55)';
        for (let c = 0; c < N; c += 1) {
          if (cellFill(c) >= 0.72) continue;
          const i = path.idx((c + 0.5) * CELL);
          g.fillRect(path.x[i] - 1.5, path.y[i] - 1.5, 3, 3);
        }
      }
      if (!started) {
        const i0 = 0;
        g.fillStyle = '#3ddc84';
        g.font = 'bold 15px Rajdhani, sans-serif';
        g.fillText('START', path.x[i0] - 20, path.y[i0] - 18);
        g.beginPath();
        g.arc(path.x[i0], path.y[i0], 6, 0, Math.PI * 2);
        g.fill();
      }
      g.restore();
    }

    if (arcOn) {
      /* jeziorko + łuk */
      g.save();
      g.globalCompositeOperation = 'lighter';
      const r = (B > 0 ? latR : poolR) * 1.1 * flick;
      let gr = g.createRadialGradient(T.ex, T.ey, 0, T.ex, T.ey, r * 2.4);
      gr.addColorStop(0, 'rgba(255,255,255,1)');
      gr.addColorStop(0.25, 'rgba(255,240,190,0.9)');
      gr.addColorStop(0.6, 'rgba(255,150,40,0.35)');
      gr.addColorStop(1, 'rgba(255,90,20,0)');
      g.fillStyle = gr;
      g.beginPath();
      g.arc(T.ex, T.ey, r * 2.4, 0, Math.PI * 2);
      g.fill();
      const tint = proc === 'TIG' ? '170,200,255' : '200,220,255';
      gr = g.createRadialGradient(T.ex, T.ey, 0, T.ex, T.ey, 90 * flick);
      gr.addColorStop(0, `rgba(${tint},0.5)`);
      gr.addColorStop(1, `rgba(${tint},0)`);
      g.fillStyle = gr;
      g.beginPath();
      g.arc(T.ex, T.ey, 90, 0, Math.PI * 2);
      g.fill();
      g.restore();
    }

    game.particles.render(g);

    /* przyłbica samościemniająca */
    if (arcOn) {
      const gr = g.createRadialGradient(T.ex, T.ey, 30, T.ex, T.ey, visR * (evt === 'smoke' ? 0.55 : 1));
      gr.addColorStop(0, 'rgba(8,22,10,0)');
      gr.addColorStop(0.6, 'rgba(6,18,8,0.55)');
      gr.addColorStop(1, 'rgba(3,10,4,0.94)');
      g.fillStyle = gr;
      g.fillRect(0, 0, W.VW, W.VH);
    }
    if (evt === 'smoke') {
      g.fillStyle = 'rgba(120,120,115,0.28)';
      g.fillRect(0, 0, W.VW, W.VH);
    }

    /* palnik i celownik */
    const extra = proc === 'MMA' ? electrode : filler;
    W.drawTorch(g, T.ex, T.ey, proc, filler, extra);
    g.strokeStyle = 'rgba(255,255,255,0.5)';
    g.lineWidth = 1;
    g.beginPath();
    g.arc(I.x, I.y, 3, 0, Math.PI * 2);
    g.stroke();

    if (busy > 0) {
      g.strokeStyle = '#ffb020';
      g.lineWidth = 4;
      g.beginPath();
      g.arc(T.ex, T.ey, 26, -Math.PI / 2, -Math.PI / 2 + (1 - busy / (busyKind === 'tungsten' ? 1.5 : busyKind === 'nozzle' ? 1.1 : 0.9)) * Math.PI * 2);
      g.stroke();
    }
    if (stuck) {
      g.fillStyle = '#ff4d3d';
      g.font = 'bold 20px Rajdhani, sans-serif';
      g.textAlign = 'center';
      g.fillText(`SPACJA ×${4 - stuckHits}`, T.ex, T.ey - 40);
      g.textAlign = 'left';
    }
  };

  /* podgląd stanu (debug / testy automatyczne) */
  st.dbg = () => ({ L, electrode, clog, filler, arcOn, stuck, busy, tungDirty, cov: coverage(), v: vEma, vIdeal, B, temp: tempC() });

  st.destroy = () => {
    if (arcOn) post(false);
    W.Audio.arc(false, proc);
    W.Audio.hiss(false);
  };
  return st;
};
