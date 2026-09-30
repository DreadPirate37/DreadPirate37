'use strict';
/* ==========================================================================
   Minigra: otwieranie zamków – trzy narzędzia, trzy mechaniki
   (przebieg i układ jak w symulatorach włamywacza, grafika własna):

   • diy      – SPINKA + ŚRUBOKRĘT (proste zamki). Mysz ustawia kąt spinki,
                D / LPM przekręca śrubokrętem. Im bliżej właściwego kąta, tym
                dalej obraca się bębenek. Każde zablokowanie = nietrafiona
                próba; po kilku spinka pęka.
   • standard – WYTRYCH (zamki z zapadkami). Przekrój wkładki, zapadki jak
                pastylki. A/D – wybór zapadki, S / PPM / kółko – stuknięcie
                w dół (sprężyna odbija, czasem trzeba kilka razy). Na dnie
                zapadka na chwilę staje – wtedy LPM / SPACJA ją blokuje.
                Kliknięcie w złym momencie = błąd; po 4 błędach wytrych pęka.
   • round    – WYTRYCH OKRĄGŁY (zamki okrągłe / tubowe). Zapadki w kole,
                ta sama zasada: stuknij, poczekaj aż stanie, zablokuj.

   Wyjście klawiszem ESC nic nie kosztuje (licznik błędów się zeruje).
   Tło płótna jest przezroczyste – w grze pod spodem widać drzwi z kamery
   zbliżeniowej. Statyczne części zamka renderowane raz do bufora.
   ========================================================================== */
DL.Lockpick = (() => {
  const VW = 1280, VH = 720;
  const CX = 640, CY = 410;
  const PLUG_R = 33, HOUSE_R = 47;
  const OPEN = Math.PI / 2;
  let g = null;

  const MODELS = { euro: 'Wkładka w szyldzie', rim: 'Wkładka w rozecie', padlock: 'Kłódka', round: 'Zamek okrągły' };
  const TOOLS = { diy: 'Spinka i śrubokręt', standard: 'Wytrych', round: 'Wytrych okrągły' };
  /* ---------------- pomocnicze rysowanie ---------------- */
  const rr = (c, x, y, w, h, r) => { c.beginPath(); c.moveTo(x + r, y); c.arcTo(x + w, y, x + w, y + h, r); c.arcTo(x + w, y + h, x, y + h, r); c.arcTo(x, y + h, x, y, r); c.arcTo(x, y, x + w, y, r); c.closePath(); };
  const lin = (c, x0, y0, x1, y1, stops) => { const gr = c.createLinearGradient(x0, y0, x1, y1); stops.forEach(([o, col]) => gr.addColorStop(o, col)); return gr; };
  const rad = (c, x, y, r0, r1, stops, fx = x, fy = y) => { const gr = c.createRadialGradient(fx, fy, r0, x, y, r1); stops.forEach(([o, col]) => gr.addColorStop(o, col)); return gr; };

  const noise = (w, h, alpha, rnd) => {
    const n = document.createElement('canvas');
    n.width = w; n.height = h;
    const x = n.getContext('2d'), img = x.createImageData(w, h);
    for (let i = 0; i < img.data.length; i += 4) {
      const v = rnd() * 255;
      img.data[i] = img.data[i + 1] = img.data[i + 2] = v;
      img.data[i + 3] = alpha;
    }
    x.putImageData(img, 0, 0);
    return n;
  };

  /** szczotkowana stal – poziome rysy */
  const brushed = (c, x, y, w, h, rnd, dark) => {
    c.save();
    c.clip();
    c.fillStyle = lin(c, x, y, x + w, y, dark
      ? [[0, '#4c525e'], [0.3, '#7d8594'], [0.5, '#a3abb9'], [0.7, '#6d7482'], [1, '#434955']]
      : [[0, '#8d95a3'], [0.25, '#d6dbe4'], [0.45, '#f4f6fa'], [0.6, '#b9c0cc'], [0.85, '#e3e7ee'], [1, '#8a919f']]);
    c.fillRect(x, y, w, h);
    for (let i = 0; i < h * 1.4; i++) {
      c.fillStyle = `rgba(${rnd() > 0.5 ? '255,255,255' : '0,0,0'},${rnd() * 0.06})`;
      c.fillRect(x + rnd() * w * 0.3, y + rnd() * h, w * (0.3 + rnd() * 0.7), 1);
    }
    c.restore();
  };

  const screw = (c, x, y, r, rot) => {
    c.save();
    c.shadowColor = 'rgba(0,0,0,.5)'; c.shadowBlur = 4; c.shadowOffsetY = 1.5;
    c.fillStyle = rad(c, x, y, 0, r, [[0, '#f3f5f9'], [0.6, '#aab1be'], [1, '#5d6472']], x - r * 0.35, y - r * 0.35);
    c.beginPath(); c.arc(x, y, r, 0, Math.PI * 2); c.fill();
    c.restore();
    c.save(); c.translate(x, y); c.rotate(rot);
    c.strokeStyle = 'rgba(20,22,28,.75)'; c.lineWidth = r * 0.28; c.lineCap = 'round';
    c.beginPath(); c.moveTo(-r * 0.6, 0); c.lineTo(r * 0.6, 0); c.stroke();
    c.restore();
  };

  /* ---------------- modele zamków (statyczne części) ---------------- */
  const cylinderHousing = (c, rnd, round) => {
    // obudowa wkładki (profil europejski lub okrągły), mosiądz
    c.save();
    c.shadowColor = 'rgba(0,0,0,.6)'; c.shadowBlur = 10; c.shadowOffsetY = 3;
    c.beginPath();
    if (round) c.arc(CX, CY, HOUSE_R, 0, Math.PI * 2);
    else { c.arc(CX, CY, HOUSE_R, Math.PI * 0.82, Math.PI * 0.18); c.lineTo(CX + 19, CY + 88); c.arcTo(CX + 19, CY + 102, CX, CY + 102, 16); c.arcTo(CX - 19, CY + 102, CX - 19, CY + 88, 16); c.closePath(); }
    c.fillStyle = lin(c, CX - 50, CY - 50, CX + 50, CY + 100, [[0, '#f6dd98'], [0.35, '#c9a24e'], [0.7, '#9c7428'], [1, '#6a4b14']]);
    c.fill();
    c.restore();
    // wewnętrzny cień na styku bębenka
    c.fillStyle = rad(c, CX, CY, PLUG_R - 2, PLUG_R + 6, [[0, 'rgba(0,0,0,.85)'], [1, 'rgba(0,0,0,0)']]);
    c.beginPath(); c.arc(CX, CY, PLUG_R + 6, 0, Math.PI * 2); c.fill();
    // rysy na mosiądzu
    c.save(); c.beginPath(); c.arc(CX, CY, HOUSE_R, 0, 7); c.clip();
    for (let i = 0; i < 50; i++) { c.strokeStyle = `rgba(60,40,10,${rnd() * 0.25})`; c.lineWidth = 0.6; const a = rnd() * 7; c.beginPath(); c.arc(CX, CY, PLUG_R + 3 + rnd() * 10, a, a + rnd() * 0.6); c.stroke(); }
    c.restore();
  };

  const escutcheonEuro = (c, rnd) => {
    const x = CX - 70, y = CY - 286, w = 140, h = 470;
    c.save();
    c.shadowColor = 'rgba(0,0,0,.65)'; c.shadowBlur = 26; c.shadowOffsetX = 6; c.shadowOffsetY = 12;
    rr(c, x, y, w, h, 70); c.fillStyle = '#9ba2ae'; c.fill();
    c.restore();
    rr(c, x, y, w, h, 70); brushed(c, x, y, w, h, rnd);
    // faza krawędzi
    c.lineWidth = 3;
    c.strokeStyle = 'rgba(255,255,255,.55)'; rr(c, x + 2, y + 2, w - 4, h - 4, 68); c.stroke();
    c.strokeStyle = 'rgba(0,0,0,.35)'; c.lineWidth = 2; rr(c, x, y, w, h, 70); c.stroke();
    screw(c, CX, y + 34, 9, 0.6);
    screw(c, CX, y + h - 34, 9, 2.1);
    // klamka: rozeta + dźwignia
    const hy = CY - 172;
    c.save(); c.shadowColor = 'rgba(0,0,0,.6)'; c.shadowBlur = 16; c.shadowOffsetY = 8;
    c.fillStyle = rad(c, CX, hy, 5, 42, [[0, '#ffffff'], [0.5, '#c6ccd6'], [1, '#6c7380']], CX - 14, hy - 14);
    c.beginPath(); c.arc(CX, hy, 40, 0, 7); c.fill();
    c.restore();
    c.save(); c.shadowColor = 'rgba(0,0,0,.55)'; c.shadowBlur = 22; c.shadowOffsetX = 10; c.shadowOffsetY = 16;
    c.beginPath();
    c.moveTo(CX - 6, hy - 22); c.bezierCurveTo(CX + 80, hy - 26, CX + 200, hy - 24, CX + 330, hy - 8);
    c.arcTo(CX + 352, hy - 4, CX + 350, hy + 18, 20);
    c.bezierCurveTo(CX + 200, hy + 26, CX + 80, hy + 26, CX - 6, hy + 22);
    c.closePath();
    c.fillStyle = lin(c, 0, hy - 26, 0, hy + 26, [[0, '#f7f9fc'], [0.35, '#d4d9e2'], [0.55, '#8b93a1'], [0.8, '#c3c9d3'], [1, '#6a7180']]);
    c.fill();
    c.restore();
    c.strokeStyle = 'rgba(255,255,255,.7)'; c.lineWidth = 2;
    c.beginPath(); c.moveTo(CX + 10, hy - 18); c.bezierCurveTo(CX + 90, hy - 21, CX + 200, hy - 19, CX + 320, hy - 5); c.stroke();
    c.fillStyle = rad(c, CX, hy, 2, 22, [[0, '#ffffff'], [1, '#9aa2af']], CX - 6, hy - 6);
    c.beginPath(); c.arc(CX, hy, 20, 0, 7); c.fill();
    cylinderHousing(c, rnd, false);
  };

  const escutcheonRim = (c, rnd) => {
    // okrągła rozeta chromowana
    c.save(); c.shadowColor = 'rgba(0,0,0,.6)'; c.shadowBlur = 24; c.shadowOffsetY = 12;
    c.fillStyle = '#8f96a2'; c.beginPath(); c.arc(CX, CY, 104, 0, 7); c.fill(); c.restore();
    c.fillStyle = rad(c, CX, CY, 20, 110, [[0, '#f5f7fb'], [0.55, '#c5cbd5'], [0.85, '#7f8795'], [1, '#e9edf3']], CX - 40, CY - 50);
    c.beginPath(); c.arc(CX, CY, 104, 0, 7); c.fill();
    c.strokeStyle = 'rgba(0,0,0,.25)'; c.lineWidth = 1.5;
    for (const r of [96, 78]) { c.beginPath(); c.arc(CX, CY, r, 0, 7); c.stroke(); }
    c.strokeStyle = 'rgba(255,255,255,.7)'; c.lineWidth = 3; c.beginPath(); c.arc(CX, CY, 101, Math.PI * 1.05, Math.PI * 1.6); c.stroke();
    screw(c, CX - 62, CY - 62, 7, 0.3);
    screw(c, CX + 62, CY + 62, 7, 1.9);
    cylinderHousing(c, rnd, true);
  };

  const padlockBody = (c, rnd, shackle) => {
    const x = CX - 125, y = CY - 115, w = 250, h = 225;
    // kabłąk rysowany osobno (animuje się przy otwarciu)
    if (shackle !== false) drawShackle(c, 0);
    c.save(); c.shadowColor = 'rgba(0,0,0,.7)'; c.shadowBlur = 30; c.shadowOffsetX = 8; c.shadowOffsetY = 16;
    rr(c, x, y, w, h, 26); c.fillStyle = '#6a717d'; c.fill(); c.restore();
    // laminowane płytki stali
    c.save(); rr(c, x, y, w, h, 26); c.clip();
    c.fillStyle = lin(c, x, 0, x + w, 0, [[0, '#4a505b'], [0.2, '#9aa1ad'], [0.45, '#d8dde5'], [0.7, '#8d94a0'], [1, '#474c56']]);
    c.fillRect(x, y, w, h);
    for (let yy = y + 12; yy < y + h; yy += 13) {
      c.fillStyle = 'rgba(0,0,0,.28)'; c.fillRect(x, yy, w, 1.5);
      c.fillStyle = 'rgba(255,255,255,.18)'; c.fillRect(x, yy + 1.5, w, 1);
    }
    for (let i = 0; i < 120; i++) { c.fillStyle = `rgba(120,70,30,${rnd() * 0.12})`; c.beginPath(); c.arc(x + rnd() * w, y + rnd() * h, rnd() * 4, 0, 7); c.fill(); }
    c.restore();
    // nity
    for (const [rx, ry] of [[x + 20, y + 20], [x + w - 20, y + 20], [x + 20, y + h - 20], [x + w - 20, y + h - 20]]) {
      c.fillStyle = rad(c, rx, ry, 0, 7, [[0, '#f0f2f6'], [1, '#6e7480']], rx - 2, ry - 2);
      c.beginPath(); c.arc(rx, ry, 6, 0, 7); c.fill();
    }
    // tłoczenie marki
    c.font = '700 13px "Sora", sans-serif'; c.textAlign = 'center';
    c.fillStyle = 'rgba(0,0,0,.35)'; c.fillText('DP · SECURITY', CX, y + 42);
    c.fillStyle = 'rgba(255,255,255,.35)'; c.fillText('DP · SECURITY', CX, y + 41);
    cylinderHousing(c, rnd, true);
  };

  /** kabłąk kłódki; lift > 0 – kabłąk wyskakuje (krótsze ramię wychodzi z korpusu) */
  const drawShackle = (c, lift) => {
    const top = CY - 250 - lift, x0 = CX - 78, x1 = CX + 78, yb = CY - 100;
    c.save();
    c.shadowColor = 'rgba(0,0,0,.6)'; c.shadowBlur = 16; c.shadowOffsetX = 6; c.shadowOffsetY = 10;
    c.lineCap = 'butt'; c.lineWidth = 32;
    c.strokeStyle = lin(c, x0 - 16, 0, x1 + 16, 0, [[0, '#5a616d'], [0.12, '#f4f6fa'], [0.22, '#9aa1ad'], [0.5, '#6d7481'], [0.78, '#9aa1ad'], [0.88, '#f4f6fa'], [1, '#5a616d']]);
    c.beginPath();
    c.moveTo(x0, yb);
    c.lineTo(x0, top + 78);
    c.arc(CX, top + 78, 78, Math.PI, 0);
    c.lineTo(x1, yb - lift * 1.1);
    c.stroke();
    c.restore();
    c.strokeStyle = 'rgba(255,255,255,.5)'; c.lineWidth = 3;
    c.beginPath(); c.arc(CX, top + 78, 70, Math.PI * 1.1, Math.PI * 1.45); c.stroke();
  };

  const keyway = c => {
    // kanał klucza w profilu paracentrycznym (zygzak)
    c.beginPath();
    c.moveTo(-3, -24); c.lineTo(3, -24); c.lineTo(3, -14); c.lineTo(6, -9); c.lineTo(1, -3); c.lineTo(4, 3);
    c.lineTo(1, 9); c.lineTo(5, 14); c.lineTo(5, 22); c.quadraticCurveTo(0, 27, -5, 22); c.lineTo(-5, 12);
    c.lineTo(-1, 7); c.lineTo(-5, 1); c.lineTo(-2, -5); c.lineTo(-6, -11); c.lineTo(-3, -16); c.closePath();
  };


  /* ==========================================================================
     WSPÓLNE: płótno pełnoekranowe, bufor statyczny, winieta, podpowiedzi
     ========================================================================== */
  const layer = draw => {
    const cv = document.createElement('canvas');
    cv.width = VW * 2; cv.height = VH * 2;
    const c = cv.getContext('2d');
    c.scale(2, 2);
    draw(c);
    return cv;
  };

  const fit = () => {
    if (!g) return;
    const dpr = Math.min(2, window.devicePixelRatio || 1);
    const W = window.innerWidth, H = window.innerHeight;
    g.cv.width = W * dpr; g.cv.height = H * dpr;
    g.cv.style.width = W + 'px'; g.cv.style.height = H + 'px';
    const s = Math.min(W / VW, H / VH);
    g.view = { dpr, W, H, s, ox: (W - VW * s) / 2, oy: (H - VH * s) / 2 };
  };

  const begin = () => {
    const c = g.ctx, v = g.view;
    c.setTransform(v.dpr, 0, 0, v.dpr, 0, 0);
    c.clearRect(0, 0, v.W, v.H);
    // winieta skupiająca wzrok na zamku (gra widoczna na brzegach)
    const gr = c.createRadialGradient(v.W / 2, v.H * 0.55, v.H * 0.15, v.W / 2, v.H * 0.55, Math.max(v.W, v.H) * 0.75);
    gr.addColorStop(0, 'rgba(0,0,0,.25)'); gr.addColorStop(1, 'rgba(0,0,0,.82)');
    c.fillStyle = gr; c.fillRect(0, 0, v.W, v.H);
    c.setTransform(v.dpr * v.s, 0, 0, v.dpr * v.s, v.ox * v.dpr, v.oy * v.dpr);
  };

  const prompts = list => {
    g.ui.keys.innerHTML = list.map(([k, t]) => `<div class="lp-k">${k.split('|').map(x => `<kbd>${x}</kbd>`).join('')}<span>${t}</span></div>`).join('');
  };

  const status = () => {
    const left = g.maxFails - g.fails;
    g.ui.cond.innerHTML = Array.from({ length: g.maxFails }, (_, i) => `<i class="${i < left ? 'on' : ''}"></i>`).join('');
    if (g.ui.pins) g.ui.pins.innerHTML = g.pins ? g.pins.map((p, i) => `<i class="${p.set ? 'on' : ''}${i === g.sel ? ' sel' : ''}"></i>`).join('') : '';
  };

  const note = (text, cls = '') => {
    const n = g.ui.note;
    n.textContent = text;
    n.className = 'lp-note show ' + cls;
    clearTimeout(g.noteT);
    g.noteT = setTimeout(() => (n.className = 'lp-note ' + cls), 1000);
  };

  const fail = () => {
    g.fails++;
    status();
    if (g.fails >= g.maxFails) return snap();
    DL.Audio.play('error', 0.35);
    note(`Nietrafione – zostało ${g.maxFails - g.fails}`, 'bad');
  };

  const snap = () => {
    g.over = true;
    g.broken = true;
    g.fall = { x: 0, y: 0, vy: -140, r: 0 };
    DL.Audio.play('snap');
    note(g.mode === 'diy' ? 'Spinka pękła!' : 'Wytrych pękł!', 'bad');
    setTimeout(() => close(false, true), 1300);
  };

  const win = () => {
    g.over = true;
    g.opening = 0.0001;
    DL.Audio.play('turn');
    setTimeout(() => DL.Audio.play('unlock'), 380);
    note('Otwarte', 'good');
    setTimeout(() => close(true, false), 1250);
  };

  const close = (ok, broken) => {
    if (!g) return;
    const done = g;
    g = null;
    cancelAnimationFrame(done.raf);
    window.removeEventListener('resize', fit);
    DL.layer.close(true);
    DL.post('gameDone', { success: !!ok, broke: !!broken });
  };

  /* ==========================================================================
     TRYB DIY: spinka + śrubokręt płaski
     ========================================================================== */
  const TH_MIN = Math.PI * 1.08, TH_MAX = Math.PI * 1.92;     // spinka w górnej połowie

  const drawPlugDiy = (c, rot, shake) => {
    c.save();
    c.translate(CX + shake.x, CY + shake.y);
    c.rotate(rot);
    c.fillStyle = rad(c, 0, 0, 2, PLUG_R, [[0, '#f9e4a6'], [0.55, '#d2ab58'], [0.9, '#9d7529'], [1, '#6f5117']], -10, -12);
    c.beginPath(); c.arc(0, 0, PLUG_R, 0, 7); c.fill();
    c.strokeStyle = 'rgba(90,60,15,.25)'; c.lineWidth = 0.7;
    for (let r = 8; r < PLUG_R; r += 4) { c.beginPath(); c.arc(0, 0, r, 0, 7); c.stroke(); }
    c.strokeStyle = 'rgba(255,250,225,.55)'; c.lineWidth = 2.5;
    c.beginPath(); c.arc(0, 0, PLUG_R - 3, Math.PI * 1.1, Math.PI * 1.55); c.stroke();
    keyway(c); c.fillStyle = '#0b0805'; c.fill();
    c.strokeStyle = 'rgba(70,45,10,.9)'; c.lineWidth = 1.2; keyway(c); c.stroke();
    // śrubokręt płaski: grot w dolnej części kanału, rękojeść do kamery (w dół, w prawo)
    const dir = Math.atan2(1, 0.42);
    c.save();
    c.shadowColor = 'rgba(0,0,0,.6)'; c.shadowBlur = 14; c.shadowOffsetX = 6; c.shadowOffsetY = 10;
    c.rotate(dir - Math.PI / 2);
    c.fillStyle = lin(c, -4, 0, 4, 0, [[0, '#7c8391'], [0.5, '#f3f5f9'], [1, '#6a717e']]);
    c.fillRect(-3.5, 6, 7, 120);                                   // trzon
    c.fillStyle = '#c9ced8'; c.fillRect(-4.5, 4, 9, 6);           // grot
    // rękojeść: przezroczysty żółty plastik z czarnym ogumowaniem (perspektywa)
    c.beginPath();
    c.moveTo(-13, 126); c.lineTo(13, 126); c.lineTo(24, 300); c.quadraticCurveTo(0, 318, -24, 300); c.closePath();
    c.fillStyle = lin(c, -24, 0, 24, 0, [[0, '#8a6a00'], [0.35, '#f5c518'], [0.55, '#ffe27a'], [1, '#9c7700']]);
    c.fill();
    c.shadowColor = 'transparent';
    c.fillStyle = 'rgba(20,20,22,.92)';
    c.beginPath(); c.moveTo(-17, 190); c.lineTo(17, 190); c.lineTo(22, 270); c.lineTo(-22, 270); c.closePath(); c.fill();
    c.strokeStyle = 'rgba(255,255,255,.08)'; c.lineWidth = 2;
    for (let y = 198; y < 266; y += 8) { const w = 17 + (y - 190) / 80 * 5; c.beginPath(); c.moveTo(-w, y); c.lineTo(w, y); c.stroke(); }
    c.fillStyle = 'rgba(255,255,255,.35)'; c.fillRect(-8, 132, 3, 52);
    c.restore();
    c.restore();
  };

  /** spinka do włosów: dwa ramiona (proste i faliste), końcówki z plastikowymi kulkami */
  const drawBobbyPin = (c, th, bend, shake, broken, fall) => {
    const tx = CX + shake.x, ty = CY + shake.y - 10;
    const dx = Math.cos(th), dy = Math.sin(th), px = -dy, py = dx;
    const L = broken ? 70 : 250, b = bend * 22;
    c.save();
    c.shadowColor = 'rgba(0,0,0,.55)'; c.shadowBlur = 10; c.shadowOffsetX = 5; c.shadowOffsetY = 8;
    c.lineCap = 'round'; c.lineJoin = 'round';
    c.strokeStyle = '#2a211c'; c.lineWidth = 3.4;
    // ramię proste (wchodzi w kanał, zagięty koniec)
    c.beginPath();
    c.moveTo(tx - px * 4 - dx * 6, ty - py * 4 - dy * 6);
    c.lineTo(tx, ty);
    c.quadraticCurveTo(tx + dx * L * 0.5 + px * b, ty + dy * L * 0.5 + py * b, tx + dx * L, ty + dy * L);
    c.stroke();
    if (!broken) {
      // zagięcie „U” i ramię faliste
      const ex = tx + dx * L, ey = ty + dy * L;
      c.beginPath();
      c.moveTo(ex, ey);
      c.quadraticCurveTo(ex + dx * 14 + px * 7, ey + dy * 14 + py * 7, ex + px * 12, ey + py * 12);
      for (let t = 1; t >= 0.28; t -= 0.04) {
        const w = Math.sin(t * 38) * 3.2;
        c.lineTo(tx + dx * L * t + px * (12 + w) + px * b * 0.6 * Math.sin(t * Math.PI), ty + dy * L * t + py * (12 + w) + py * b * 0.6 * Math.sin(t * Math.PI));
      }
      c.stroke();
      // połysk lakieru
      c.shadowColor = 'transparent';
      c.strokeStyle = 'rgba(255,230,210,.25)'; c.lineWidth = 1;
      c.beginPath(); c.moveTo(tx + dx * 30 - px, ty + dy * 30 - py); c.lineTo(tx + dx * (L - 20) - px, ty + dy * (L - 20) - py); c.stroke();
      // plastikowa kulka na końcu ramienia falistego
      const kx = tx + dx * L * 0.28 + px * 12, ky = ty + dy * L * 0.28 + py * 12;
      c.fillStyle = rad(c, kx, ky, 0, 4, [[0, '#6b5a50'], [1, '#1c1512']], kx - 1, ky - 1);
      c.beginPath(); c.arc(kx, ky, 3.6, 0, 7); c.fill();
    }
    c.restore();
    if (broken && fall) {
      c.save();
      c.translate(tx + dx * 150 + fall.x, ty + dy * 150 + fall.y);
      c.rotate(th + fall.r);
      c.strokeStyle = '#2a211c'; c.lineWidth = 3.4; c.lineCap = 'round';
      c.beginPath(); c.moveTo(-80, 0); c.lineTo(100, 0); c.quadraticCurveTo(116, 6, 100, 12); c.lineTo(-40, 12); c.stroke();
      c.restore();
    }
  };

  const diyLoop = dt => {
    if (!g.over) {
      g.th = DL.lerp(g.th, g.thWant, Math.min(1, dt * 16));
      const d = Math.abs(g.th - g.sweet);
      const allow = d <= g.tol ? 1 : DL.clamp(1 - (d - g.tol) / g.zone, 0, 1);
      const limit = OPEN * allow * (allow < 1 ? 0.9 : 1);
      g.binding = false;
      if (g.turning) {
        if (g.rot < limit) g.rot = Math.min(limit, g.rot + 1.7 * dt);
        if (allow >= 1 && g.rot >= OPEN - 0.002) return win();
        if (g.rot >= limit - 0.01) {
          g.binding = true;
          g.bindT += dt;
          g.bend = DL.lerp(g.bend, 0.5 + (1 - allow) * 0.6, dt * 8);
          if ((g.creakT -= dt) <= 0) { g.creakT = 0.3; DL.Audio.play('creak', 0.3 + (1 - allow) * 0.4); }
          // zablokowanie trwające chwilę = jedna nietrafiona próba (raz na przekręcenie)
          if (g.bindT > 0.35 && !g.counted) { g.counted = true; fail(); }
        }
      } else {
        g.rot = Math.max(0, g.rot - 3 * dt);
        g.bend = DL.lerp(g.bend, 0, dt * 10);
        g.bindT = 0;
        g.counted = false;
      }
    }
    if (g.opening) g.rot = Math.min(OPEN, g.rot + dt * 3);
    const amp = g.binding ? 1.2 + g.bend * 1.6 : 0;
    const sh = { x: (Math.random() - 0.5) * amp, y: (Math.random() - 0.5) * amp };
    const c = g.ctx;
    if (g.model === 'padlock') drawShackle(c, g.opening ? Math.min(60, (g.shk = (g.shk || 0) + dt * 220)) : 0);
    c.drawImage(g.static, 0, 0, VW, VH);
    drawPlugDiy(c, g.rot, sh);
    drawBobbyPin(c, g.th, g.bend, sh, g.broken, g.fall);
    if (g.fall) { g.fall.vy += 1600 * dt; g.fall.y += g.fall.vy * dt; g.fall.r += dt * 3; }
  };

  /* ==========================================================================
     ZAPADKI – wspólna logika dla wytrycha i wytrycha okrągłego
     ========================================================================== */
  const makePins = (n, d) => Array.from({ length: n }, () => ({
    p: 0, set: false, stall: 0, fall: 0,
    k: 1 + Math.floor(g.rnd() * (d.knockMax || 2)),          // ile stuknięć potrzeba (sprężyna odbija)
  }));

  const pinsUpdate = dt => {
    for (const q of g.pins) {
      if (q.set) continue;
      if (q.stall > 0) {
        q.stall -= dt;
        if (q.stall <= 0) { q.fall = 1; DL.Audio.play('pin', 0.4); }
      } else if (q.fall > 0) {
        q.p = Math.max(0, q.p - dt * 5);
        if (q.p <= 0) q.fall = 0;
      } else if (q.p > 0) {
        q.p = Math.max(0, q.p - g.spring * dt);       // sprężyna powoli wypycha zapadkę
      }
    }
    g.dip = Math.max(0, g.dip - dt * 7);
  };

  const knock = () => {
    if (g.over || g.knockCd > 0) return;
    g.knockCd = 0.13;
    g.dip = 1;
    const q = g.pins[g.sel];
    if (q.set || q.stall > 0 || q.fall > 0) return DL.Audio.play('pin', 0.3);
    q.p = Math.min(1, q.p + (1 / q.k) * (0.92 + g.rnd() * 0.16));
    if (q.p >= 0.985) {
      q.p = 1;
      q.stall = g.stallT;
      DL.Audio.play('set', 0.45);
    } else DL.Audio.play('pin', 0.7);
  };

  const secure = () => {
    if (g.over) return;
    const q = g.pins[g.sel];
    if (q.set) return;
    if (q.stall > 0) {
      q.set = true;
      q.stall = 0;
      DL.Audio.play('set');
      status();
      if (g.pins.every(x => x.set)) return win();
      note(`Zapadka zablokowana (${g.pins.filter(x => x.set).length}/${g.pins.length})`, 'good');
    } else fail();
  };

  const select = dir => {
    if (g.over) return;
    const n = g.pins.length;
    g.sel = g.mode === 'round' ? (g.sel + dir + n) % n : DL.clamp(g.sel + dir, 0, n - 1);
    DL.Audio.play('tick', 0.5);
    status();
  };

  /* ==========================================================================
     TRYB STANDARD: przekrój wkładki
     ========================================================================== */
  const ST = { x0: 300, x1: 980, top: 250, key: 300, chTop: 318, chBot: 560, travel: 118, pinH: 64 };

  const standardStatic = c => {
    const { x0, x1, top, chBot } = ST;
    // korpus wkładki (przecięty)
    c.save(); c.shadowColor = 'rgba(0,0,0,.7)'; c.shadowBlur = 40; c.shadowOffsetY = 20;
    rr(c, x0, top - 70, x1 - x0, chBot - top + 110, 34);
    c.fillStyle = lin(c, 0, top - 70, 0, chBot + 40, [[0, '#e9c877'], [0.3, '#b98d39'], [0.7, '#8f6a25'], [1, '#5c4213']]);
    c.fill(); c.restore();
    // powierzchnia przekroju (piaskowana)
    c.save(); rr(c, x0, top - 70, x1 - x0, chBot - top + 110, 34); c.clip();
    for (let i = 0; i < 1800; i++) { c.fillStyle = `rgba(${g.rnd() > 0.5 ? '255,240,200' : '60,40,10'},${g.rnd() * 0.08})`; c.fillRect(x0 + g.rnd() * (x1 - x0), top - 70 + g.rnd() * 500, 1.5, 1.5); }
    c.restore();
    // bębenek (cylinder) – pasmo z kanałem klucza
    c.fillStyle = lin(c, 0, top - 28, 0, ST.chTop, [[0, '#f6dd9a'], [0.5, '#d9b262'], [1, '#a57b2e']]);
    rr(c, x0 + 26, top - 28, x1 - x0 - 52, ST.chTop - top + 28, 14); c.fill();
    c.fillStyle = '#0c0905';
    rr(c, x0 + 26, ST.key - 26, x1 - x0 - 40, 26, 8); c.fill();                   // kanał klucza
    c.fillStyle = 'rgba(255,220,150,.12)'; c.fillRect(x0 + 30, ST.key - 26, x1 - x0 - 50, 3);
    // linia podziału bębenek / korpus
    c.strokeStyle = 'rgba(60,40,10,.8)'; c.lineWidth = 2;
    c.beginPath(); c.moveTo(x0 + 20, ST.chTop); c.lineTo(x1 - 20, ST.chTop); c.stroke();
    // komory zapadek
    for (let i = 0; i < g.pins.length; i++) {
      const x = pinX(i);
      c.fillStyle = '#130e06';
      rr(c, x - 22, ST.key - 2, 44, chBot - ST.key, 10); c.fill();
      c.fillStyle = 'rgba(0,0,0,.5)'; c.fillRect(x - 22, ST.key - 2, 44, 6);
      // znacznik dna komory
      const bot = ST.key + ST.travel + ST.pinH;
      c.strokeStyle = 'rgba(255,215,130,.35)'; c.lineWidth = 1; c.setLineDash([4, 4]);
      c.beginPath(); c.moveTo(x - 20, bot); c.lineTo(x + 20, bot); c.stroke(); c.setLineDash([]);
    }
  };

  const pinX = i => { const n = g.pins.length, span = 520; return 640 - span / 2 + (span / (n - 1)) * i; };

  const drawSpring = (c, x, y0, y1, coils = 9) => {
    c.strokeStyle = lin(c, x - 14, 0, x + 14, 0, [[0, '#6e7584'], [0.5, '#e6e9f0'], [1, '#6e7584']]);
    c.lineWidth = 2.6;
    c.beginPath();
    for (let k = 0; k <= coils * 2; k++) {
      const y = y0 + ((y1 - y0) * k) / (coils * 2);
      const xx = x + (k % 2 ? 13 : -13);
      k ? c.lineTo(xx, y) : c.moveTo(x, y);
    }
    c.stroke();
  };

  const pill = (c, x, y, w, h, set, glow) => {
    c.save();
    if (glow) { c.shadowColor = glow; c.shadowBlur = 18; }
    c.fillStyle = set
      ? lin(c, x - w / 2, 0, x + w / 2, 0, [[0, '#2f7a57'], [0.45, '#8ff0c1'], [1, '#246146']])
      : lin(c, x - w / 2, 0, x + w / 2, 0, [[0, '#7a5519'], [0.4, '#ffe6a3'], [0.6, '#e2b75e'], [1, '#6f4c14']]);
    rr(c, x - w / 2, y, w, h, w / 2); c.fill();
    c.restore();
    c.fillStyle = 'rgba(255,255,255,.35)'; rr(c, x - w / 2 + 6, y + 6, 4, h - 12, 2); c.fill();
  };

  const standardDraw = dt => {
    const c = g.ctx;
    c.drawImage(g.static, 0, 0, VW, VH);
    const bot = ST.key + ST.travel + ST.pinH;
    g.pins.forEach((q, i) => {
      const x = pinX(i);
      const tremble = q.stall > 0 ? (Math.random() - 0.5) * 1.4 : 0;
      const y = ST.key + q.p * ST.travel + tremble;
      drawSpring(c, x, y + ST.pinH, ST.chBot - 6, 7 + Math.round((1 - q.p) * 2));
      pill(c, x, y, 34, ST.pinH, q.set, q.set ? 'rgba(47,227,164,.8)' : q.stall > 0 ? 'rgba(255,214,120,.7)' : null);
      if (i === g.sel && !g.over) {
        c.strokeStyle = 'rgba(255,255,255,.55)'; c.lineWidth = 1.5;
        rr(c, x - 24, ST.key - 4, 48, ST.chBot - ST.key + 4, 12); c.stroke();
      }
    });
    // obrót po otwarciu – przesunięcie bębenka
    // wytrych: wchodzi kanałem z prawej, haczyk nad wybraną zapadką
    g.pickX = DL.lerp(g.pickX, pinX(g.sel), Math.min(1, dt * 16));
    const tipY = ST.key - 8 + g.dip * 10;
    drawPick(c, g.pickX, tipY, g.broken, g.fall);
    if (g.opening) { c.fillStyle = `rgba(47,227,164,${Math.min(0.18, g.opening)})`; c.fillRect(ST.x0, ST.top - 70, ST.x1 - ST.x0, bot); g.opening += dt; }
  };

  /** wytrych haczykowy wchodzący kanałem klucza z prawej strony */
  const drawPick = (c, tipX, tipY, broken, fall) => {
    const endX = broken ? tipX + 90 : VW + 40;
    c.save();
    c.shadowColor = 'rgba(0,0,0,.6)'; c.shadowBlur = 10; c.shadowOffsetY = 6;
    c.lineCap = 'round'; c.lineJoin = 'round';
    c.strokeStyle = lin(c, 0, tipY - 4, 0, tipY + 4, [[0, '#ffffff'], [0.5, '#b7bfcc'], [1, '#606878']]);
    c.lineWidth = 5;
    c.beginPath();
    c.moveTo(tipX - 3, tipY + 14);
    c.quadraticCurveTo(tipX - 4, tipY - 2, tipX + 12, tipY - 3);   // haczyk
    c.lineTo(endX, tipY - 3);
    c.stroke();
    if (!broken) {
      // rękojeść poza zamkiem
      const hx = ST.x1 + 40;
      c.fillStyle = lin(c, 0, tipY - 18, 0, tipY + 14, [[0, '#454c5c'], [0.4, '#1d212a'], [1, '#0b0d12']]);
      rr(c, hx, tipY - 17, VW - hx + 60, 30, 12); c.fill();
      c.shadowColor = 'transparent';
      c.strokeStyle = 'rgba(255,255,255,.06)'; c.lineWidth = 2;
      for (let x = hx + 14; x < VW; x += 12) { c.beginPath(); c.moveTo(x, tipY - 14); c.lineTo(x, tipY + 10); c.stroke(); }
    }
    c.restore();
    if (broken && fall) {
      c.save();
      c.translate(tipX + 260 + fall.x, tipY + fall.y);
      c.rotate(fall.r * 0.5);
      c.fillStyle = '#1d212a'; rr(c, 0, -15, 330, 30, 12); c.fill();
      c.fillStyle = '#b7bfcc'; c.fillRect(-150, -5, 152, 5);
      c.restore();
    }
  };

  /* ==========================================================================
     TRYB ROUND: zamek okrągły (tubowy) – zapadki w kole + podgląd przekroju
     ========================================================================== */
  const RD = { r: 84, hole: 15 };

  const roundStatic = c => {
    // rozeta chromowana
    c.save(); c.shadowColor = 'rgba(0,0,0,.7)'; c.shadowBlur = 40; c.shadowOffsetY = 18;
    c.fillStyle = '#8f96a2'; c.beginPath(); c.arc(CX, CY, 190, 0, 7); c.fill(); c.restore();
    c.fillStyle = rad(c, CX, CY, 30, 200, [[0, '#f5f7fb'], [0.55, '#c5cbd5'], [0.85, '#7f8795'], [1, '#e9edf3']], CX - 60, CY - 80);
    c.beginPath(); c.arc(CX, CY, 190, 0, 7); c.fill();
    c.strokeStyle = 'rgba(255,255,255,.7)'; c.lineWidth = 4; c.beginPath(); c.arc(CX, CY, 186, Math.PI * 1.05, Math.PI * 1.6); c.stroke();
    // cylinder mosiężny
    c.fillStyle = lin(c, CX - 130, CY - 130, CX + 130, CY + 130, [[0, '#f6dd98'], [0.4, '#c9a24e'], [1, '#6a4b14']]);
    c.beginPath(); c.arc(CX, CY, 132, 0, 7); c.fill();
    c.strokeStyle = 'rgba(60,40,10,.6)'; c.lineWidth = 2; c.beginPath(); c.arc(CX, CY, 118, 0, 7); c.stroke();
    // pierścieniowy kanał klucza
    c.fillStyle = '#0b0805';
    c.beginPath(); c.arc(CX, CY, 106, 0, 7); c.arc(CX, CY, 58, 0, 7, true); c.fill('evenodd');
    // otwory zapadek
    for (let i = 0; i < g.pins.length; i++) {
      const [x, y] = holeXY(i);
      c.fillStyle = '#050403'; c.beginPath(); c.arc(x, y, RD.hole + 2, 0, 7); c.fill();
    }
    // tłoczenie
    c.font = '700 12px "Sora", sans-serif'; c.textAlign = 'center';
    c.fillStyle = 'rgba(0,0,0,.35)'; c.fillText('DP · TUBULAR', CX, CY + 162);
  };

  const holeXY = i => { const a = -Math.PI / 2 + (i / g.pins.length) * Math.PI * 2; return [CX + Math.cos(a) * RD.r, CY + Math.sin(a) * RD.r, a]; };

  const roundDraw = dt => {
    const c = g.ctx;
    c.drawImage(g.static, 0, 0, VW, VH);
    // środek (rdzeń) – obraca się po otwarciu
    const rot = g.opening ? Math.min(OPEN, g.opening * 3) : 0;
    if (g.opening) g.opening += dt;
    c.save(); c.translate(CX, CY); c.rotate(rot);
    c.fillStyle = rad(c, 0, 0, 4, 56, [[0, '#f9e4a6'], [0.6, '#cfa653'], [1, '#7a5a1c']], -12, -14);
    c.beginPath(); c.arc(0, 0, 56, 0, 7); c.fill();
    c.fillStyle = '#0b0805'; c.fillRect(-5, -58, 10, 16);            // wycięcie prowadzące
    c.restore();
    // zapadki: im głębiej, tym mniejsze i ciemniejsze (perspektywa w głąb otworu)
    g.pins.forEach((q, i) => {
      const [x, y] = holeXY(i);
      const tr = q.stall > 0 ? (Math.random() - 0.5) * 1.2 : 0;
      const depth = q.set ? 1 : q.p;
      const r = RD.hole * (1 - depth * 0.45);
      c.save();
      if (q.set) { c.shadowColor = 'rgba(47,227,164,.9)'; c.shadowBlur = 14; }
      else if (q.stall > 0) { c.shadowColor = 'rgba(255,214,120,.9)'; c.shadowBlur = 14; }
      const light = 1 - depth * 0.6;
      c.fillStyle = q.set
        ? rad(c, x + tr, y, 0, r, [[0, '#9ff5cc'], [1, '#1f6b4b']], x - 3, y - 3)
        : rad(c, x + tr, y, 0, r, [[0, `rgba(${255 * light | 0},${230 * light | 0},${160 * light | 0},1)`], [1, `rgba(${120 * light | 0},${80 * light | 0},${20 * light | 0},1)`]], x - 3, y - 3);
      c.beginPath(); c.arc(x + tr, y, r, 0, 7); c.fill();
      c.restore();
      if (i === g.sel && !g.over) {
        c.strokeStyle = 'rgba(255,255,255,.75)'; c.lineWidth = 2;
        c.beginPath(); c.arc(x, y, RD.hole + 7, 0, 7); c.stroke();
      }
    });
    // wytrych okrągły: tuleja z czujnikami, wskazówka na wybraną zapadkę
    const [sx, sy, a] = holeXY(g.sel);
    g.pickA = g.pickA == null ? a : lerpAngle(g.pickA, a, Math.min(1, dt * 14));
    c.save();
    c.translate(CX, CY); c.rotate(g.pickA + Math.PI / 2);
    c.shadowColor = 'rgba(0,0,0,.6)'; c.shadowBlur = 12; c.shadowOffsetY = 6;
    c.strokeStyle = lin(c, -60, 0, 60, 0, [[0, '#6c7380'], [0.5, '#eef1f6'], [1, '#6c7380']]);
    c.lineWidth = 9; c.beginPath(); c.arc(0, 0, 70, 0, 7); c.stroke();          // tuleja
    if (!g.broken) {
      c.fillStyle = '#e8ebf1'; rr(c, -4, -RD.r - 6 + g.dip * 6, 8, 24, 3); c.fill();   // czujnik
      c.fillStyle = '#1c2029'; c.beginPath(); c.arc(0, 0, 40, 0, 7); c.fill();         // rękojeść (widok od czoła)
      c.fillStyle = 'rgba(255,255,255,.08)'; c.beginPath(); c.arc(-8, -10, 22, 0, 7); c.fill();
    }
    c.restore();
    // podgląd przekroju wybranej zapadki
    const q = g.pins[g.sel], ix = 1020, iy = 250;
    c.fillStyle = 'rgba(10,12,18,.75)'; rr(c, ix - 60, iy - 40, 120, 290, 14); c.fill();
    c.strokeStyle = 'rgba(255,255,255,.12)'; c.lineWidth = 1; rr(c, ix - 60, iy - 40, 120, 290, 14); c.stroke();
    c.font = '600 11px "JetBrains Mono", monospace'; c.fillStyle = 'rgba(255,255,255,.5)'; c.textAlign = 'center';
    c.fillText(`ZAPADKA ${g.sel + 1}`, ix, iy - 18);
    c.fillStyle = '#130e06'; rr(c, ix - 20, iy, 40, 220, 8); c.fill();
    c.strokeStyle = 'rgba(255,215,130,.4)'; c.setLineDash([4, 4]); c.beginPath(); c.moveTo(ix - 20, iy + 150); c.lineTo(ix + 20, iy + 150); c.stroke(); c.setLineDash([]);
    const py = iy + 4 + (q.set ? 1 : q.p) * 90 + (q.stall > 0 ? (Math.random() - 0.5) * 1.4 : 0);
    drawSpring(c, ix, py + 56, iy + 216, 6);
    pill(c, ix, py, 28, 56, q.set, q.stall > 0 ? 'rgba(255,214,120,.7)' : null);
  };

  const lerpAngle = (a, b, t) => { let d = ((b - a + Math.PI * 3) % (Math.PI * 2)) - Math.PI; return a + d * t; };

  /* ==========================================================================
     PĘTLA, WEJŚCIE, OTWARCIE
     ========================================================================== */
  const loop = t => {
    if (!g) return;
    const dt = Math.min(0.05, (t - (g.last || t)) / 1000);
    g.last = t;
    g.knockCd = Math.max(0, (g.knockCd || 0) - dt);
    begin();
    if (g.mode === 'diy') diyLoop(dt);
    else {
      if (!g.over) pinsUpdate(dt);
      if (g.fall) { g.fall.vy += 1600 * dt; g.fall.y += g.fall.vy * dt; g.fall.r += dt * 3; }
      if (g.mode === 'standard') standardDraw(dt); else roundDraw(dt);
    }
    if (g) g.raf = requestAnimationFrame(loop);
  };

  const open = d => {
    const mode = TOOLS[d.mode] ? d.mode : 'diy';
    const model = MODELS[d.model] ? d.model : (mode === 'round' ? 'round' : 'euro');
    const diff = DL.clamp(d.difficulty || 2, 1, 5);
    const box = DL.h('div.lp-full');
    box.innerHTML = `
      <canvas></canvas>
      <div class="lp-tl"><b>${TOOLS[mode]}</b><span>${MODELS[model]} · poziom ${diff}</span><div class="lp-cond"></div>${mode !== 'diy' ? '<div class="lp-pins"></div>' : ''}</div>
      <div class="lp-note"></div>
      <div class="lp-keys"></div>`;
    const cv = DL.$('canvas', box);
    g = {
      box, cv, ctx: cv.getContext('2d'), mode, model, diff, rnd: DL.rng(d.seed || 1),
      over: false, broken: false, fails: 0, maxFails: d.maxFails || 4, opening: 0,
      ui: { keys: DL.$('.lp-keys', box), cond: DL.$('.lp-cond', box), pins: DL.$('.lp-pins', box), note: DL.$('.lp-note', box) },
    };

    if (mode === 'diy') {
      Object.assign(g, {
        rot: 0, th: Math.PI * 1.5, thWant: Math.PI * 1.5, bend: 0, bindT: 0, creakT: 0, counted: false, turning: false,
        tol: (d.tol || [0.07, 0.055, 0.045, 0.038, 0.032][diff - 1]) * Math.PI, zone: 0.9,
      });
      g.sweet = TH_MIN + 0.1 + g.rnd() * (TH_MAX - TH_MIN - 0.2);
      g.static = layer(c => {
        if (model === 'rim') escutcheonRim(c, g.rnd);
        else if (model === 'padlock') padlockBody(c, g.rnd, false);
        else escutcheonEuro(c, g.rnd);
      });
      prompts([['MYSZ', 'Kąt spinki'], ['D|LPM', 'Przekręć śrubokrętem'], ['ESC', 'Wyjdź']]);
    } else {
      g.pins = makePins(d.pins || (mode === 'round' ? 7 : 5), d);
      Object.assign(g, { sel: 0, pickX: 0, dip: 0, spring: d.spring || 0.35, stallT: d.stall || 0.8 });
      g.static = layer(c => (mode === 'round' ? roundStatic(c) : standardStatic(c)));
      g.pickX = pinX(0);
      prompts([[mode === 'round' ? 'A|D' : 'A|D', 'Zmień zapadkę'], ['S|PPM', 'Stuknij zapadkę'], ['LPM|SPACJA', 'Zablokuj (gdy stanie)'], ['ESC', 'Wyjdź']]);
    }

    cv.addEventListener('mousemove', e => {
      if (!g || g.over) return;
      const v = g.view;
      if (g.mode === 'diy') {
        const x = ((e.clientX - v.ox) / v.s) / VW;
        const want = TH_MIN + DL.clamp((x - 0.15) / 0.7, 0, 1) * (TH_MAX - TH_MIN);
        g.thWant = g.turning ? DL.lerp(g.thWant, want, 0.12) : want;
      }
    });
    cv.addEventListener('mousedown', e => {
      if (!g || g.over) return;
      if (g.mode === 'diy') { if (e.button === 0) g.turning = true; return; }
      if (e.button === 0) secure(); else if (e.button === 2) knock();
    });
    cv.addEventListener('wheel', e => {
      if (!g || g.over || g.mode === 'diy') return;
      e.preventDefault();
      if (e.deltaY > 0) knock(); else select(e.shiftKey ? -1 : 1);
    }, { passive: false });
    g.up = e => { if (g && e.button === 0) g.turning = false; };
    window.addEventListener('mouseup', g.up);
    const up = g.up;
    DL.layer.open('lockpick', box, () => { window.removeEventListener('mouseup', up); window.removeEventListener('resize', fit); if (g) { cancelAnimationFrame(g.raf); g = null; } });
    window.addEventListener('resize', fit);
    fit();
    status();
    g.raf = requestAnimationFrame(loop);
    DL.Audio.play('open', 0.6);
  };

  const key = (e, down) => {
    if (!g) return false;
    const k = e.code;
    if (k === 'Escape') { if (down && !g.over) { g.over = true; close(false, false); } return true; }
    if (g.over) return true;
    if (g.mode === 'diy') {
      if (k === 'KeyD' || k === 'Space') { g.turning = down; return true; }
      return false;
    }
    if (!down) return ['KeyA', 'KeyD', 'KeyS', 'Space', 'ArrowLeft', 'ArrowRight', 'ArrowDown'].includes(k);
    if (e.repeat && k !== 'KeyS' && k !== 'ArrowDown') return true;
    if (k === 'KeyA' || k === 'ArrowLeft') { select(-1); return true; }
    if (k === 'KeyD' || k === 'ArrowRight') { select(1); return true; }
    if (k === 'KeyS' || k === 'ArrowDown') { knock(); return true; }
    if (k === 'Space' || k === 'Enter') { secure(); return true; }
    return false;
  };

  /** podgląd stanu dla testów automatycznych */
  const peek = () => g && { mode: g.mode, rot: g.rot, over: g.over, fails: g.fails, sel: g.sel, pins: g.pins && g.pins.map(q => ({ p: q.p, set: q.set, stall: q.stall })) };

  return { open, key, peek };
})();
