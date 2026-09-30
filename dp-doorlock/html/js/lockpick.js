'use strict';
/* ==========================================================================
   Minigra: wytrych – widok frontowy zamka (zbliżenie jak w symulatorach
   włamywacza). Trzy modele: wkładka europejska w szyldzie (stalowe drzwi),
   wkładka w okrągłej rozecie (drewniane drzwi), kłódka na kracie.

   Mechanika:
   • mysz obraca wytrych wokół kanału klucza – szukasz „słodkiego punktu”,
   • LPM / D / SPACJA – napinacz przekręca bębenek; im bliżej punktu, tym
     dalej się obróci; poza punktem zamek się blokuje, drga, a wytrych gnie się
     i w końcu pęka,
   • wyższe poziomy mają kilka zapadek (etapów) – każda z nowym punktem.

   Wydajność: drzwi, szyld, klamka i obudowa wkładki są renderowane raz do
   bufora (offscreen canvas); na klatkę rysujemy tylko bębenek i narzędzia.
   ========================================================================== */
DL.Lockpick = (() => {
  const VW = 1000, VH = 540;
  const CX = 500, CY = 322;           // środek bębenka
  const PLUG_R = 33, HOUSE_R = 47;
  const OPEN = Math.PI / 2;           // obrót, przy którym zamek puszcza
  const TH_MIN = 0.06 * Math.PI, TH_MAX = 0.94 * Math.PI;
  let g = null;

  const MODELS = {
    euro: { label: 'Wkładka europejska', surface: 'steel' },
    rim: { label: 'Wkładka w rozecie', surface: 'wood' },
    padlock: { label: 'Kłódka', surface: 'gate' },
  };

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

  /* ---------------- tła (raz, do bufora) ---------------- */
  const surfaceSteel = (c, rnd) => {
    c.fillStyle = lin(c, 0, 0, VW, VH, [[0, '#2b3140'], [0.5, '#222735'], [1, '#161a24']]);
    c.fillRect(0, 0, VW, VH);
    c.globalAlpha = 0.5; c.fillStyle = c.createPattern(noise(160, 160, 14, rnd), 'repeat'); c.fillRect(0, 0, VW, VH); c.globalAlpha = 1;
    // przetłoczenie panelu drzwi
    c.strokeStyle = 'rgba(0,0,0,.45)'; c.lineWidth = 3; rr(c, 110, -40, 780, 640, 26); c.stroke();
    c.strokeStyle = 'rgba(255,255,255,.05)'; c.lineWidth = 2; rr(c, 113, -37, 780, 640, 26); c.stroke();
  };

  const surfaceWood = (c, rnd) => {
    c.fillStyle = lin(c, 0, 0, VW, 0, [[0, '#3a2414'], [0.5, '#4a2f1a'], [1, '#2e1c0f']]);
    c.fillRect(0, 0, VW, VH);
    // słoje
    for (let i = 0; i < 90; i++) {
      const x = rnd() * VW, amp = 4 + rnd() * 16, f = 0.004 + rnd() * 0.01, ph = rnd() * 6;
      c.strokeStyle = `rgba(${rnd() > 0.5 ? '20,10,4' : '120,80,45'},${0.08 + rnd() * 0.14})`;
      c.lineWidth = 0.6 + rnd() * 2.2;
      c.beginPath();
      for (let y = -10; y <= VH + 10; y += 10) { const xx = x + Math.sin(y * f + ph) * amp; y < 0 ? c.moveTo(xx, y) : c.lineTo(xx, y); }
      c.stroke();
    }
    // sęk
    c.save(); c.translate(250, 120); c.scale(1, 2.2);
    for (let k = 8; k > 0; k--) { c.strokeStyle = `rgba(25,12,5,${0.12 + k * 0.02})`; c.lineWidth = 1.4; c.beginPath(); c.arc(0, 0, k * 4, 0, Math.PI * 2); c.stroke(); }
    c.restore();
    c.globalAlpha = 0.4; c.fillStyle = c.createPattern(noise(120, 120, 18, rnd), 'repeat'); c.fillRect(0, 0, VW, VH); c.globalAlpha = 1;
    // lakier – połysk
    c.fillStyle = lin(c, 0, 0, VW, VH, [[0, 'rgba(255,220,180,.08)'], [0.4, 'rgba(255,220,180,0)'], [1, 'rgba(0,0,0,.25)']]);
    c.fillRect(0, 0, VW, VH);
  };

  const surfaceGate = (c, rnd) => {
    c.fillStyle = rad(c, CX, CY, 40, 700, [[0, '#1c212c'], [1, '#07080c']]);
    c.fillRect(0, 0, VW, VH);
    // cela w tle (rozmyta)
    c.fillStyle = 'rgba(255,255,255,.03)';
    for (let x = 40; x < VW; x += 130) c.fillRect(x, 0, 60, VH);
    // pręty kraty
    for (let x = 90; x < VW; x += 150) {
      c.save(); c.shadowColor = 'rgba(0,0,0,.7)'; c.shadowBlur = 18; c.shadowOffsetX = 8;
      c.fillStyle = lin(c, x - 16, 0, x + 16, 0, [[0, '#23272f'], [0.35, '#6c7380'], [0.55, '#3f4550'], [1, '#191c22']]);
      c.fillRect(x - 16, -10, 32, VH + 20);
      c.restore();
    }
    // poprzeczka + skobel
    c.save(); c.shadowColor = 'rgba(0,0,0,.7)'; c.shadowBlur = 20; c.shadowOffsetY = 10;
    c.fillStyle = lin(c, 0, 90, 0, 150, [[0, '#6c7380'], [0.5, '#3a3f49'], [1, '#1e2128']]);
    c.fillRect(0, 96, VW, 50);
    c.restore();
    // rdza
    for (let i = 0; i < 260; i++) { c.fillStyle = `rgba(${120 + rnd() * 60},${50 + rnd() * 30},20,${rnd() * 0.18})`; c.beginPath(); c.arc(rnd() * VW, 96 + rnd() * 50, rnd() * 3, 0, 7); c.fill(); }
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
    const x = CX - 70, y = 36, w = 140, h = 470;
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
    const hy = 150;
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

  const buildStatic = (model, rnd, dpr) => {
    const cv = document.createElement('canvas');
    cv.width = VW * dpr; cv.height = VH * dpr;
    const c = cv.getContext('2d');
    c.scale(dpr, dpr);
    const m = MODELS[model];
    if (m.surface === 'wood') surfaceWood(c, rnd);
    else if (m.surface === 'gate') surfaceGate(c, rnd);
    else surfaceSteel(c, rnd);
    if (model === 'rim') escutcheonRim(c, rnd);
    else if (model === 'padlock') padlockBody(c, rnd, false);
    else escutcheonEuro(c, rnd);
    // winieta obiektywu
    c.fillStyle = rad(c, CX, CY, 180, 640, [[0, 'rgba(0,0,0,0)'], [1, 'rgba(0,0,0,.6)']]);
    c.fillRect(0, 0, VW, VH);
    return cv;
  };

  /* ---------------- części ruchome ---------------- */
  const keyway = c => {
    // kanał klucza w profilu paracentrycznym (zygzak)
    c.beginPath();
    c.moveTo(-3, -24); c.lineTo(3, -24); c.lineTo(3, -14); c.lineTo(6, -9); c.lineTo(1, -3); c.lineTo(4, 3);
    c.lineTo(1, 9); c.lineTo(5, 14); c.lineTo(5, 22); c.quadraticCurveTo(0, 27, -5, 22); c.lineTo(-5, 12);
    c.lineTo(-1, 7); c.lineTo(-5, 1); c.lineTo(-2, -5); c.lineTo(-6, -11); c.lineTo(-3, -16); c.closePath();
  };

  const drawPlug = (c, rot, shake) => {
    c.save();
    c.translate(CX + shake.x, CY + shake.y);
    c.rotate(rot);
    c.fillStyle = rad(c, 0, 0, 2, PLUG_R, [[0, '#f9e4a6'], [0.55, '#d2ab58'], [0.9, '#9d7529'], [1, '#6f5117']], -10, -12);
    c.beginPath(); c.arc(0, 0, PLUG_R, 0, 7); c.fill();
    // koncentryczne ślady toczenia
    c.strokeStyle = 'rgba(90,60,15,.25)'; c.lineWidth = 0.7;
    for (let r = 8; r < PLUG_R; r += 4) { c.beginPath(); c.arc(0, 0, r, 0, 7); c.stroke(); }
    // odbłysk
    c.strokeStyle = 'rgba(255,250,225,.55)'; c.lineWidth = 2.5;
    c.beginPath(); c.arc(0, 0, PLUG_R - 3, Math.PI * 1.1, Math.PI * 1.55); c.stroke();
    // kanał
    c.save();
    keyway(c);
    c.fillStyle = '#0b0805'; c.fill();
    c.clip();
    c.fillStyle = 'rgba(255,200,120,.18)';
    c.fillRect(-8, -26, 3, 52);
    c.restore();
    c.strokeStyle = 'rgba(70,45,10,.9)'; c.lineWidth = 1.2; keyway(c); c.stroke();
    // napinacz – wchodzi w dół kanału i wychodzi w lewo, obraca się z bębenkiem
    c.save();
    c.shadowColor = 'rgba(0,0,0,.6)'; c.shadowBlur = 8; c.shadowOffsetY = 4;
    c.fillStyle = lin(c, 0, 14, 0, 26, [[0, '#f1f3f7'], [0.5, '#9aa1ae'], [1, '#5c6370']]);
    rr(c, -2.5, 12, 5, 13, 1.5); c.fill();
    c.beginPath();
    c.moveTo(-2, 20); c.lineTo(-58, 20); c.lineTo(-64, 25); c.lineTo(-230, 25); c.lineTo(-230, 32); c.lineTo(-62, 32); c.lineTo(-54, 27); c.lineTo(-2, 27); c.closePath();
    c.fill();
    c.fillStyle = 'rgba(255,255,255,.6)'; c.fillRect(-228, 25.5, 166, 1.2);
    c.restore();
    c.restore();
  };

  /** wytrych: grot w kanale, trzon i rękojeść pod kątem th (0 = w prawo, π = w lewo, w dół) */
  const drawPick = (c, th, rot, bend, shake, broken, fall) => {
    const tip = { x: CX + shake.x, y: CY + shake.y - 6 };
    const dx = Math.cos(th), dy = Math.sin(th);
    const px = -dy, py = dx;                       // prostopadła
    const b = bend * 18;                           // ugięcie trzonu
    const L1 = broken ? 55 : 105, L2 = 265;
    c.save();
    c.shadowColor = 'rgba(0,0,0,.55)'; c.shadowBlur = 12; c.shadowOffsetX = 6; c.shadowOffsetY = 10;
    // trzon (cienka stal, lekko ugięta przy napięciu)
    c.lineCap = 'round';
    c.strokeStyle = lin(c, tip.x + px * 3, tip.y + py * 3, tip.x - px * 3, tip.y - py * 3, [[0, '#ffffff'], [0.5, '#b9c0cc'], [1, '#626979']]);
    c.lineWidth = 4;
    c.beginPath();
    c.moveTo(tip.x, tip.y);
    c.quadraticCurveTo(tip.x + dx * L1 * 0.5 + px * b, tip.y + dy * L1 * 0.5 + py * b, tip.x + dx * L1, tip.y + dy * L1);
    c.stroke();
    if (!broken) {
      // rękojeść – rośnie z perspektywą (bliżej kamery)
      const h0 = { x: tip.x + dx * L1, y: tip.y + dy * L1 }, h1 = { x: tip.x + dx * L2, y: tip.y + dy * L2 };
      c.beginPath();
      c.moveTo(h0.x + px * 5, h0.y + py * 5);
      c.lineTo(h1.x + px * 15, h1.y + py * 15);
      c.quadraticCurveTo(h1.x + dx * 18, h1.y + dy * 18, h1.x - px * 15, h1.y - py * 15);
      c.lineTo(h0.x - px * 5, h0.y - py * 5);
      c.closePath();
      c.fillStyle = lin(c, h0.x + px * 14, h0.y + py * 14, h0.x - px * 14, h0.y - py * 14, [[0, '#3b4150'], [0.35, '#1c2029'], [1, '#0b0d12']]);
      c.fill();
      c.shadowColor = 'transparent';
      // prążki gumowego uchwytu
      c.strokeStyle = 'rgba(255,255,255,.07)'; c.lineWidth = 2;
      for (let k = 0.2; k < 0.95; k += 0.08) {
        const t = L1 + (L2 - L1) * k, wd = 5 + 10 * k;
        const cx = tip.x + dx * t, cy = tip.y + dy * t;
        c.beginPath(); c.moveTo(cx + px * wd, cy + py * wd); c.lineTo(cx - px * wd, cy - py * wd); c.stroke();
      }
      c.strokeStyle = 'rgba(255,255,255,.18)'; c.lineWidth = 1.5;
      c.beginPath(); c.moveTo(h0.x + px * 4.5, h0.y + py * 4.5); c.lineTo(h1.x + px * 13, h1.y + py * 13); c.stroke();
    }
    c.restore();
    // odłamana część spada
    if (broken && fall) {
      c.save();
      c.translate(tip.x + dx * (L1 + 60) + fall.x, tip.y + dy * (L1 + 60) + fall.y);
      c.rotate(th + fall.r);
      c.fillStyle = '#1c2029';
      rr(c, 0, -8, 240, 16, 8); c.fill();
      c.fillStyle = '#b9c0cc'; c.fillRect(-60, -2, 62, 4);
      c.restore();
    }
  };

  /* ---------------- HUD ---------------- */
  const msg = (text, cls) => {
    const m = g.ui.msg;
    m.textContent = text;
    m.className = 'g-msg show ' + cls;
    clearTimeout(g.msgT);
    g.msgT = setTimeout(() => (m.className = 'g-msg ' + cls), 1100);
  };
  const hud = () => {
    g.ui.pins.forEach((p, i) => p.classList.toggle('on', i < g.stage));
    g.ui.hp.style.transform = `scaleX(${Math.max(0, g.hp) / 100})`;
    g.ui.hpv.textContent = Math.max(0, Math.round(g.hp)) + '%';
  };

  /* ---------------- logika ---------------- */
  const newSweet = () => {
    g.sweet = TH_MIN + 0.08 + g.rnd() * (TH_MAX - TH_MIN - 0.16);
  };

  const loop = t => {
    if (!g) return;
    const dt = Math.min(0.05, (t - (g.last || t)) / 1000);
    g.last = t;
    const stageStep = OPEN / g.stages;
    const base = g.stage * stageStep, target = Math.min(OPEN, base + stageStep);
    g.th = DL.lerp(g.th, g.thWant, Math.min(1, dt * 18));
    let binding = false;

    if (!g.over) {
      const d = Math.abs(g.th - g.sweet);
      const allow = d <= g.tol ? 1 : DL.clamp(1 - (d - g.tol) / g.zone, 0, 1);
      const limit = base + (target - base) * allow * (allow < 1 ? 0.92 : 1);
      if (g.turning) {
        if (g.rot < limit) g.rot = Math.min(limit, g.rot + 1.9 * dt);
        else if (g.rot > limit + 0.01) g.rot = Math.max(limit, g.rot - 2.5 * dt);
        if (allow >= 1 && g.rot >= target - 0.002) {
          g.stage++;
          hud();
          if (g.stage >= g.stages) return win();
          DL.Audio.play('set');
          msg(`Zapadka ${g.stage}/${g.stages} puściła`, 'good');
          newSweet();
        } else if (g.rot >= limit - 0.01) {
          binding = true;
          const force = 1 - allow * 0.6;
          g.bindT += dt;
          // najpierw czujesz opór (0,25 s), dopiero potem wytrych zaczyna się giąć
          if (g.bindT > 0.25) g.hp -= g.dmg * force * dt;
          g.bend = DL.lerp(g.bend, 0.6 + force * 0.5, dt * 8);
          if ((g.creakT -= dt) <= 0) { g.creakT = 0.28 + g.rnd() * 0.2; DL.Audio.play('creak', 0.35 + force * 0.4); }
          if (g.hp <= 0) return lose(true);
          if (g.hp < 30 && !g.warned) { g.warned = true; msg('Wytrych zaraz pęknie!', 'bad'); }
          hud();
        }
      } else {
        g.bindT = 0;
        g.rot = Math.max(base, g.rot - 3.2 * dt);
        g.bend = DL.lerp(g.bend, 0, dt * 10);
      }
      if (!binding) g.bend = DL.lerp(g.bend, g.turning ? 0.2 : 0, dt * 8);
      // subtelna wskazówka: drgnięcie bębenka, gdy jesteś blisko punktu
      g.hint = g.turning ? allow : 0;
    }

    // drgania przy blokowaniu
    const amp = binding ? 1.4 + (1 - g.hint) * 1.8 : 0;
    const shake = { x: (g.rnd() - 0.5) * amp, y: (g.rnd() - 0.5) * amp };

    const c = g.ctx;
    c.drawImage(g.bg, 0, 0, VW, VH);
    if (g.model === 'padlock') drawShackle(c, g.shackle);
    if (g.model === 'padlock') c.drawImage(g.bgPad, 0, 0, VW, VH);
    drawPlug(c, g.rot, shake);
    drawPick(c, g.th, g.rot, g.bend, shake, g.broken, g.fall);
    if (g.fall) { g.fall.vy += 1600 * dt; g.fall.y += g.fall.vy * dt; g.fall.r += dt * 3; }
    if (g.opening) { g.shackle = Math.min(60, g.shackle + dt * 220); }
    g.raf = requestAnimationFrame(loop);
  };

  const win = () => {
    g.over = true;
    g.turning = false;
    g.rot = OPEN;
    g.opening = true;
    DL.Audio.play('turn');
    setTimeout(() => DL.Audio.play('unlock'), 350);
    setTimeout(() => end(true, false), 900);
  };

  const lose = broken => {
    if (g.over) return;
    g.over = true;
    g.turning = false;
    if (broken) {
      g.broken = true;
      g.fall = { x: 0, y: 0, vy: -120, r: 0 };
      DL.Audio.play('snap');
      msg('Wytrych pękł!', 'bad');
    }
    setTimeout(() => end(false, broken), broken ? 1100 : 200);
  };

  const end = (win, broken) => {
    if (!g) return;
    const box = DL.h('div.g-end.' + (win ? 'win' : 'lose'));
    box.innerHTML = `<div class="box"><div class="big">${DL.icon(win ? 'unlock' : 'x')}</div><b>${win ? 'Zamek otwarty' : broken ? 'Wytrych pękł' : 'Czas minął'}</b><span>${win ? 'Bębenek obrócony' : broken ? 'Szukaj punktu, zanim przekręcisz na siłę' : 'Spróbuj ponownie'}</span></div>`;
    g.box.append(box);
    setTimeout(() => close(win, broken), 1300);
  };

  const close = (win, broken) => {
    if (!g) return;
    const done = g;
    g = null;
    cancelAnimationFrame(done.raf);
    clearInterval(done.iv);
    DL.layer.close(true);
    DL.post('gameDone', { success: !!win, broke: !!broken });
  };

  const open = d => {
    if (d.style === 'pins') return DL.LockpickPins.open(d);
    const model = MODELS[d.model] ? d.model : 'euro';
    const diff = DL.clamp(d.difficulty || 2, 1, 5);
    const stages = d.stages || [1, 1, 2, 2, 3][diff - 1];
    const box = DL.h('div.game.lockpick.front');
    box.innerHTML = `
      <canvas></canvas>
      <div class="g-top">
        <div class="ttl"><div class="bdg">${DL.icon('pick')}</div><div><b>${d.advanced ? 'Zaawansowany wytrych' : 'Wytrych'}</b><span>${MODELS[model].label} · trudność ${diff}/5</span></div></div>
        <div class="g-stat">
          <div class="st"><small>Zapadki</small><div class="pins">${'<i></i>'.repeat(stages)}</div></div>
          <div class="st"><small>Wytrych <em class="hpv">100%</em></small><div class="bar hp"><i></i></div></div>
          <div class="g-time"></div>
        </div>
      </div>
      <div class="g-msg"></div>
      <div class="g-foot"><span><kbd>MYSZ</kbd>kąt wytrycha</span><span><kbd>LPM</kbd> / <kbd>D</kbd>przekręć napinaczem</span><span>Obraca się dalej = jesteś bliżej</span><span><kbd>ESC</kbd>odpuść</span></div>`;
    const cv = DL.$('canvas', box);
    const dpr = Math.min(2, window.devicePixelRatio || 1);
    cv.width = VW * dpr; cv.height = VH * dpr;
    const ctx = cv.getContext('2d');
    ctx.scale(dpr, dpr);
    const rnd = DL.rng(d.seed || 1);

    g = {
      box, ctx, model, rnd, stages, stage: 0, rot: 0, th: Math.PI / 2, thWant: Math.PI / 2, bend: 0, hint: 0,
      turning: false, over: false, hp: 100, bindT: 0, warned: false, creakT: 0, shackle: 0, opening: false,
      tol: [0.11, 0.085, 0.065, 0.05, 0.04][diff - 1] * Math.PI / 1.3 * (d.advanced ? 1.35 : 1),
      zone: [0.9, 0.8, 0.7, 0.6, 0.5][diff - 1],
      dmg: [26, 32, 38, 44, 52][diff - 1] * (d.advanced ? 0.6 : 1),
      ui: { pins: DL.$$('.pins i', box), hp: DL.$('.bar.hp i', box), hpv: DL.$('.hpv', box), msg: DL.$('.g-msg', box), time: DL.$('.g-time', box) },
    };
    g.bg = buildStatic(model, DL.rng((d.seed || 1) ^ 0x5f3759df), dpr);
    if (model === 'padlock') {
      // korpus kłódki na osobnej warstwie – kabłąk jest pod nim i się animuje
      const pad = document.createElement('canvas');
      pad.width = VW * dpr; pad.height = VH * dpr;
      const pc = pad.getContext('2d'); pc.scale(dpr, dpr);
      padlockBody(pc, DL.rng(7), false);
      g.bgPad = pad;
      const bgOnly = document.createElement('canvas');
      bgOnly.width = VW * dpr; bgOnly.height = VH * dpr;
      const bc = bgOnly.getContext('2d'); bc.scale(dpr, dpr);
      surfaceGate(bc, DL.rng(3));
      g.bg = bgOnly;
    }
    newSweet();

    const endAt = performance.now() + (d.time || 60) * 1000;
    const tick = () => {
      if (!g || g.over) return;
      const s = Math.max(0, Math.ceil((endAt - performance.now()) / 1000));
      g.ui.time.textContent = `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`;
      g.ui.time.classList.toggle('warn', s <= 10);
      if (s <= 0) lose(false);
    };
    g.iv = setInterval(tick, 250);
    tick();

    cv.addEventListener('mousemove', e => {
      if (!g || g.over) return;
      const r = cv.getBoundingClientRect();
      const x = (e.clientX - r.left) / r.width;
      // pełny zakres kąta = cała szerokość okna; kierunek jak ruch ręki
      const want = TH_MAX - DL.clamp((x - 0.1) / 0.8, 0, 1) * (TH_MAX - TH_MIN);
      if (g.turning) g.thWant = DL.lerp(g.thWant, want, 0.15);   // pod napięciem ręka chodzi ciężko
      else g.thWant = want;
      if (Math.abs(want - g.lastTick) > 0.08) { g.lastTick = want; DL.Audio.play('pin', 0.15); }
    });
    cv.addEventListener('mousedown', e => { if (e.button === 0 && g && !g.over) g.turning = true; });
    g.up = e => { if (e.button === 0 && g) g.turning = false; };
    window.addEventListener('mouseup', g.up);
    g.lastTick = 0;
    const up = g.up;
    DL.layer.open('game', box, () => { window.removeEventListener('mouseup', up); if (g) { cancelAnimationFrame(g.raf); clearInterval(g.iv); g = null; } });
    DL.fitGame(box);
    hud();
    g.raf = requestAnimationFrame(loop);
    DL.Audio.play('open');
  };

  const key = (e, down) => {
    if (!g) return DL.LockpickPins.key(e);
    if (e.key === 'Escape' && down) { if (!g.over) { g.over = true; close(false, false); } return true; }
    if (e.code === 'KeyD' || e.code === 'Space') { if (!g.over) g.turning = down; return true; }
    return false;
  };

  /** podgląd stanu dla testów automatycznych */
  const peek = () => g && { rot: g.rot, over: g.over, hp: g.hp, stage: g.stage };
  return { open, key, peek };
})();
