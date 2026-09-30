'use strict';
/* ==========================================================================
   Otwieranie zamków – odwzorowanie ekranu z Thief Simulator (grafika własna)

   SCENA: widok z pierwszej osoby. Owalny, przybrudzony szyld z brązu (lilia,
   dwie śruby, podświetlona dziurka od klucza), za nim przecięty korpus
   wkładki w ujęciu 3/4 z okienkiem na 5 szklanych rurek z zapadkami
   (mosiężny bolec górny, sprężyna, bolec dolny). Wytrych wchodzi z lewej
   (szeroka rękojeść z nitem, cienki trzon), w przekroju widać drucik
   zagięty na wybraną zapadkę; napinacz sterczy pionowo w górę. Kursor-dłoń.

   HUD: [F] Wyjdź / [E] Latarka / [R] Noktowizor (lewy górny róg),
   „Ilość wytrychów” (dół, środek), nazwa miejsca na niebiesko (prawo),
   zegar + pasek hałasu + oko (lewy dół), XP + poziom + plecak z gotówką
   (prawy dół).

   MECHANIKI:
   • wytrych – zapadkę wybierasz myszą (najechanie) lub A/D, wciskasz ją
     PPM / S / kółkiem; sprężyna czasem odbija; na dnie zapadka chwilę
     STOI – wtedy LPM ją blokuje. 4 kliknięcia w złym momencie = wytrych
     pęka, ilość wytrychów spada o 1, a jeśli masz następny – grasz dalej
     (zapadki wracają na górę).
   • spinka + śrubokręt (proste zamki) – mysz ustawia kąt spinki, D / LPM
     przekręca śrubokrętem; bębenek obraca się tym dalej, im bliżej
     właściwego kąta; zablokowanie = nietrafiona próba.
   • wytrych okrągły – zamek okrągły, 7 zapadek w kole.
   • latarka i noktowizor zmieniają oświetlenie, każde stuknięcie i błąd
     robią hałas – pełny pasek hałasu włącza alarm.
   Płótno jest przezroczyste – w grze pod spodem są drzwi z kamery.
   ========================================================================== */
DL.Lockpick = (() => {
  const VW = 1280, VH = 720;
  const CX = 640, CY = 390;             // środek zamka okrągłego
  const OPEN = Math.PI / 2;
  let g = null;

  const TOOLS = { diy: 'Spinka', standard: 'Wytrych', round: 'Wytrych okrągły' };

  /* ---------------- pomocnicze ---------------- */
  const rr = (c, x, y, w, h, r) => { c.beginPath(); c.moveTo(x + r, y); c.arcTo(x + w, y, x + w, y + h, r); c.arcTo(x + w, y + h, x, y + h, r); c.arcTo(x, y + h, x, y, r); c.arcTo(x, y, x + w, y, r); c.closePath(); };
  const lin = (c, x0, y0, x1, y1, stops) => { const gr = c.createLinearGradient(x0, y0, x1, y1); stops.forEach(([o, col]) => gr.addColorStop(o, col)); return gr; };
  const rad = (c, x, y, r0, r1, stops, fx = x, fy = y) => { const gr = c.createRadialGradient(fx, fy, r0, x, y, r1); stops.forEach(([o, col]) => gr.addColorStop(o, col)); return gr; };
  const poly = (c, pts) => { c.beginPath(); pts.forEach(([x, y], i) => (i ? c.lineTo(x, y) : c.moveTo(x, y))); c.closePath(); };

  /** rysy i przetarcia na zużytym metalu (w obrębie aktualnego clipa) */
  const scratches = (c, x, y, w, h, n, rnd, light = '255,236,210') => {
    for (let i = 0; i < n; i++) {
      const sx = x + rnd() * w, sy = y + rnd() * h, len = 6 + rnd() * 40, a = rnd() * Math.PI;
      c.strokeStyle = rnd() > 0.4 ? `rgba(${light},${0.025 + rnd() * 0.075})` : `rgba(0,0,0,${0.12 + rnd() * 0.2})`;
      c.lineWidth = 0.5 + rnd() * 0.9;
      c.beginPath(); c.moveTo(sx, sy);
      c.quadraticCurveTo(sx + Math.cos(a) * len * 0.5 + (rnd() - 0.5) * 6, sy + Math.sin(a) * len * 0.5 + (rnd() - 0.5) * 6, sx + Math.cos(a) * len, sy + Math.sin(a) * len);
      c.stroke();
    }
    // plamy patyny
    for (let i = 0; i < n / 6; i++) {
      c.fillStyle = `rgba(${rnd() > 0.5 ? '20,14,8' : '120,90,60'},${rnd() * 0.12})`;
      c.beginPath(); c.ellipse(x + rnd() * w, y + rnd() * h, 4 + rnd() * 26, 3 + rnd() * 14, rnd() * 3, 0, 7); c.fill();
    }
  };

  const layer = draw => {
    const cv = document.createElement('canvas');
    cv.width = VW * 2; cv.height = VH * 2;
    const c = cv.getContext('2d');
    c.scale(2, 2);
    draw(c);
    return cv;
  };

  /* ==========================================================================
     GEOMETRIA SCENY (współrzędne wirtualne 1280×720)
     ========================================================================== */
  const E = { cx: 468, cy: 380, rx: 86, ry: 334, depth: 24 };          // szyld
  const K = { x: 460, y: 258 };                                        // dziurka od klucza
  const BODY = { a: [540, 196], b: [868, 188], c: [868, 578], d: [540, 584], dx: 40, dy: -34 };
  const WIN = { x0: 598, y0: 250, x1: 842, y1: 560 };                  // okienko przekroju
  const P = { top: 296, pinH: 54, travel: 162, botTop: 512, botBot: 548, tubeW: 28, keyY: 280 };
  const pinX = i => 636 + i * ((816 - 636) / Math.max(1, g.pins.length - 1));

  /* ---------------- korpus wkładki (za szyldem) ---------------- */
  const drawBody = (c, rnd, cut) => {
    const { a, b, c: cc, d, dx, dy } = BODY;
    // cień rzucany na drzwi
    c.save(); c.shadowColor = 'rgba(0,0,0,.75)'; c.shadowBlur = 50; c.shadowOffsetX = 30; c.shadowOffsetY = 30;
    poly(c, [a, b, cc, d]); c.fillStyle = '#2b2622'; c.fill(); c.restore();
    // bok (koniec korpusu) – profil europejski: zaokrąglona góra
    c.fillStyle = lin(c, b[0], 0, b[0] + dx + 30, 0, [[0, '#2a2521'], [1, '#141210']]);
    poly(c, [b, [b[0] + dx, b[1] + dy], [cc[0] + dx, cc[1] + dy - 60], [cc[0] + dx - 6, cc[1] + dy], cc]); c.fill();
    c.save();
    c.fillStyle = lin(c, b[0] + dx - 30, 0, b[0] + dx + 36, 0, [[0, '#6b5f55'], [0.5, '#3b342e'], [1, '#1c1916']]);
    c.beginPath(); c.ellipse(b[0] + dx - 6, b[1] + dy + 108, 34, 112, 0, -Math.PI / 2, Math.PI / 2); c.fill();
    c.strokeStyle = 'rgba(255,220,180,.18)'; c.lineWidth = 2;
    c.beginPath(); c.ellipse(b[0] + dx - 6, b[1] + dy + 108, 26, 100, 0, -Math.PI / 2, Math.PI / 2); c.stroke();
    c.restore();
    // wierzch
    poly(c, [a, b, [b[0] + dx, b[1] + dy], [a[0] + dx, a[1] + dy]]);
    c.fillStyle = lin(c, 0, a[1] + dy, 0, a[1], [[0, '#5b5249'], [1, '#2c2621']]); c.fill();
    // czoło (strona przekroju)
    c.save();
    poly(c, [a, b, cc, d]); c.clip();
    c.fillStyle = lin(c, a[0], a[1], cc[0], cc[1], [[0, '#4a423b'], [0.45, '#322c27'], [1, '#1b1815']]);
    c.fillRect(a[0], a[1] - 10, 340, 410);
    scratches(c, a[0], a[1], 330, 400, 260, rnd);
    c.restore();
    c.save(); poly(c, [a, b, [b[0] + dx, b[1] + dy], [a[0] + dx, a[1] + dy]]); c.clip(); scratches(c, a[0], a[1] + dy, 370, 40, 70, rnd); c.restore();
    // krawędzie
    c.strokeStyle = 'rgba(255,220,180,.28)'; c.lineWidth = 1.5;
    c.beginPath(); c.moveTo(...a); c.lineTo(...b); c.stroke();
    c.strokeStyle = 'rgba(0,0,0,.6)';
    c.beginPath(); c.moveTo(...b); c.lineTo(...cc); c.stroke();
    // nit na boku
    c.fillStyle = rad(c, 858, 262, 0, 7, [[0, '#b7a896'], [1, '#2a241f']], 856, 259);
    c.beginPath(); c.arc(856, 262, 6, 0, 7); c.fill();
    if (!cut) return;
    // okienko przekroju: głębokie wnętrze z fazą
    const { x0, y0, x1, y1 } = WIN;
    c.fillStyle = lin(c, 0, y0, 0, y1, [[0, '#8b857f'], [0.4, '#6a645e'], [1, '#4b4641']]);
    c.fillRect(x0, y0, x1 - x0, y1 - y0);
    c.save(); c.beginPath(); c.rect(x0, y0, x1 - x0, y1 - y0); c.clip();
    for (let i = 0; i < 140; i++) { c.fillStyle = `rgba(255,255,255,${rnd() * 0.05})`; c.fillRect(x0, y0 + rnd() * (y1 - y0), x1 - x0, 1); }
    scratches(c, x0, y0, x1 - x0, y1 - y0, 60, rnd);
    c.restore();
    // ścianki okienka (grubość materiału)
    c.fillStyle = '#a79e94'; poly(c, [[x0, y0], [x1, y0], [x1 - 10, y0 + 14], [x0 + 12, y0 + 14]]); c.fill();
    c.fillStyle = '#2a2521'; poly(c, [[x0, y0], [x0 + 12, y0 + 14], [x0 + 12, y1], [x0, y1]]); c.fill();
    c.fillStyle = 'rgba(0,0,0,.35)'; c.fillRect(x0 + 12, y0 + 14, x1 - x0 - 22, 10);
    // kanał bębenka (tu biegnie drucik wytrycha)
    c.fillStyle = lin(c, 0, P.keyY - 16, 0, P.keyY + 12, [[0, '#3a3531'], [1, '#1c1916']]);
    c.fillRect(x0 + 12, P.keyY - 16, x1 - x0 - 22, 26);
    c.fillStyle = 'rgba(255,200,140,.12)'; c.fillRect(x0 + 12, P.keyY + 10, x1 - x0 - 22, 2);
  };

  /* ---------------- szyld z brązu ---------------- */
  const fleur = (c, x, y, s) => {
    c.save(); c.translate(x, y); c.scale(s * 0.62, s);
    c.beginPath();
    c.moveTo(0, -30); c.bezierCurveTo(9, -20, 10, -6, 0, 6); c.bezierCurveTo(-10, -6, -9, -20, 0, -30);
    c.moveTo(-3, 2); c.bezierCurveTo(-18, -10, -32, -4, -26, 10); c.bezierCurveTo(-22, 18, -12, 14, -10, 8);
    c.moveTo(3, 2); c.bezierCurveTo(18, -10, 32, -4, 26, 10); c.bezierCurveTo(22, 18, 12, 14, 10, 8);
    c.moveTo(-14, 10); c.lineTo(14, 10); c.lineTo(14, 15); c.lineTo(-14, 15); c.closePath();
    c.moveTo(0, 15); c.bezierCurveTo(4, 22, 3, 30, 0, 36); c.bezierCurveTo(-3, 30, -4, 22, 0, 15);
    c.restore();
  };

  const bronzeFace = c => lin(c, E.cx - E.rx, E.cy - E.ry, E.cx + E.rx, E.cy + E.ry, [[0, '#6e5236'], [0.3, '#4a3624'], [0.65, '#2f2217'], [1, '#18110b']]);

  const drawEscutcheon = (c, rnd) => {
    const { cx, cy, rx, ry, depth } = E;
    // grubość (krawędź widoczna z prawej – ujęcie z lewej)
    c.save(); c.shadowColor = 'rgba(0,0,0,.7)'; c.shadowBlur = 40; c.shadowOffsetX = 26; c.shadowOffsetY = 24;
    c.fillStyle = '#1d150e'; c.beginPath(); c.ellipse(cx + depth, cy, rx, ry, 0, 0, 7); c.fill(); c.restore();
    c.fillStyle = lin(c, cx, 0, cx + rx + depth, 0, [[0, '#5a4330'], [0.6, '#2a1f15'], [1, '#110c08']]);
    c.beginPath(); c.ellipse(cx + depth * 0.5, cy, rx, ry, 0, -Math.PI / 2, Math.PI / 2); c.ellipse(cx + depth, cy, rx, ry, 0, Math.PI / 2, -Math.PI / 2, true); c.fill();
    // lico
    c.fillStyle = bronzeFace(c);
    c.beginPath(); c.ellipse(cx, cy, rx, ry, 0, 0, 7); c.fill();
    c.save(); c.beginPath(); c.ellipse(cx, cy, rx, ry, 0, 0, 7); c.clip();
    scratches(c, cx - rx, cy - ry, rx * 2, ry * 2, 320, rnd, '255,214,160');
    // odblask latarki na górnej krawędzi
    c.fillStyle = rad(c, cx - 20, cy - ry + 60, 0, 150, [[0, 'rgba(255,170,90,.38)'], [1, 'rgba(255,150,70,0)']]);
    c.fillRect(cx - rx, cy - ry, rx * 2, 260);
    c.restore();
    // wypukłe obramowanie
    c.lineWidth = 7;
    c.strokeStyle = lin(c, 0, cy - ry, 0, cy + ry, [[0, '#e0a867'], [0.25, '#7a5a3a'], [0.8, '#2a1e14'], [1, '#5a4330']]);
    c.beginPath(); c.ellipse(cx, cy, rx - 5, ry - 5, 0, 0, 7); c.stroke();
    c.lineWidth = 1.5; c.strokeStyle = 'rgba(0,0,0,.5)';
    c.beginPath(); c.ellipse(cx, cy, rx - 12, ry - 12, 0, 0, 7); c.stroke();
    c.strokeStyle = 'rgba(255,200,140,.35)';
    c.beginPath(); c.ellipse(cx - 1, cy - 1, rx - 1.5, ry - 1.5, 0, Math.PI * 1.05, Math.PI * 1.55); c.stroke();
    // wnęka dziurki od klucza
    c.save(); c.shadowColor = 'rgba(255,200,140,.25)'; c.shadowOffsetY = 2; c.shadowBlur = 2;
    c.fillStyle = lin(c, 0, K.y - 70, 0, K.y + 70, [[0, '#2a1f15'], [0.5, '#4e3a28'], [1, '#6b5038']]);
    c.beginPath(); c.ellipse(K.x, K.y, 40, 74, 0, 0, 7); c.fill(); c.restore();
    c.strokeStyle = 'rgba(0,0,0,.6)'; c.lineWidth = 3; c.beginPath(); c.ellipse(K.x, K.y, 40, 74, 0, Math.PI * 0.9, Math.PI * 1.9); c.stroke();
    // lilia wygrawerowana poniżej
    c.save();
    fleur(c, cx - 2, cy + 108, 1.6);
    c.fillStyle = 'rgba(0,0,0,.28)'; c.fill('evenodd');
    c.translate(-1, -1.2); fleur(c, cx - 2, cy + 108, 1.6);
    c.strokeStyle = 'rgba(255,210,150,.14)'; c.lineWidth = 1; c.stroke();
    c.restore();
    // śruby
    screw(c, cx - 6, cy - ry + 78, 11, 0.5);
    screw(c, cx - 6, cy + ry - 78, 11, 2.2);
  };

  const screw = (c, x, y, r, rot) => {
    c.save(); c.shadowColor = 'rgba(0,0,0,.6)'; c.shadowBlur = 5; c.shadowOffsetX = 2; c.shadowOffsetY = 2;
    c.fillStyle = rad(c, x, y, 0, r, [[0, '#d7b385'], [0.55, '#8b6947'], [1, '#3a2a1c']], x - r * 0.35, y - r * 0.4);
    c.beginPath(); c.arc(x, y, r, 0, 7); c.fill(); c.restore();
    c.save(); c.translate(x, y); c.rotate(rot);
    c.strokeStyle = 'rgba(20,12,6,.85)'; c.lineWidth = r * 0.26; c.lineCap = 'round';
    c.beginPath(); c.moveTo(-r * 0.65, 0); c.lineTo(r * 0.65, 0); c.stroke();
    c.restore();
  };

  /** bębenek w dziurce: klasyczny otwór klucza (koło + trapez), podświetlony od środka */
  const drawKeyhole = (c, rot) => {
    c.save();
    c.translate(K.x, K.y);
    c.rotate(rot);
    c.fillStyle = rad(c, 0, 0, 2, 30, [[0, '#8b6a45'], [1, '#3b2b1c']], -8, -10);
    c.beginPath(); c.arc(0, 0, 30, 0, 7); c.fill();
    c.strokeStyle = 'rgba(0,0,0,.55)'; c.lineWidth = 2; c.beginPath(); c.arc(0, 0, 30, 0, 7); c.stroke();
    const hole = () => { c.beginPath(); c.arc(0, -12, 11, Math.PI * 0.72, Math.PI * 2.28); c.lineTo(7, 30); c.lineTo(-7, 30); c.closePath(); };
    c.save(); c.shadowColor = '#ff9a3c'; c.shadowBlur = 18;
    hole(); c.fillStyle = rad(c, 0, 4, 2, 34, [[0, '#ffd08a'], [0.45, '#f08a2c'], [1, '#6a2e08']]); c.fill();
    c.restore();
    hole(); c.strokeStyle = 'rgba(30,18,8,.9)'; c.lineWidth = 2; c.stroke();
    c.restore();
  };

  /* ---------------- zapadki w szklanych rurkach ---------------- */
  const drawSpring = (c, x, y0, y1, coils = 9, w = 11) => {
    if (y1 - y0 < 3) return;
    c.strokeStyle = lin(c, x - w, 0, x + w, 0, [[0, '#4b4a48'], [0.5, '#c9c6c1'], [1, '#4b4a48']]);
    c.lineWidth = 2.4;
    c.beginPath();
    for (let k = 0; k <= coils * 2; k++) {
      const y = y0 + ((y1 - y0) * k) / (coils * 2);
      const xx = x + (k % 2 ? w : -w);
      k ? c.lineTo(xx, y) : c.moveTo(x, y);
    }
    c.stroke();
  };

  const brass = (c, x, y, w, h, tint) => {
    c.fillStyle = lin(c, x - w / 2, 0, x + w / 2, 0, tint || [[0, '#6e4c14'], [0.3, '#e9c46a'], [0.5, '#ffe7a3'], [0.75, '#c8962f'], [1, '#5a3d0f']]);
    rr(c, x - w / 2, y, w, h, Math.min(w / 2, 6)); c.fill();
    c.fillStyle = 'rgba(0,0,0,.25)'; c.fillRect(x - w / 2 + 1, y + h - 3, w - 2, 2);
  };

  const drawPins = (c, dt) => {
    g.pins.forEach((q, i) => {
      const x = pinX(i), w = P.tubeW;
      const shake = q.stall > 0 ? (Math.random() - 0.5) * 1.2 : 0;
      const topY = P.top + (q.set ? 1 : q.p) * P.travel + shake;
      // rurka (szkło)
      c.fillStyle = 'rgba(210,225,235,.10)';
      rr(c, x - w / 2 - 3, P.top - 4, w + 6, P.botBot - P.top + 6, 6); c.fill();
      // sprężyna między bolcami
      drawSpring(c, x, topY + P.pinH, P.botTop, 6, 10);
      // bolec górny (mosiężny, zaokrąglony)
      brass(c, x, topY, w - 4, P.pinH);
      c.fillStyle = 'rgba(255,255,255,.4)'; c.fillRect(x - 6, topY + 5, 3, P.pinH - 12);
      // bolec dolny
      brass(c, x, P.botTop, w - 4, P.botBot - P.botTop);
      // szkło – odblaski na krawędziach
      c.strokeStyle = 'rgba(255,255,255,.35)'; c.lineWidth = 1.2;
      c.beginPath(); c.moveTo(x - w / 2 - 2, P.top); c.lineTo(x - w / 2 - 2, P.botBot); c.stroke();
      c.strokeStyle = 'rgba(255,255,255,.15)';
      c.beginPath(); c.moveTo(x + w / 2 + 1, P.top); c.lineTo(x + w / 2 + 1, P.botBot); c.stroke();
      c.fillStyle = 'rgba(255,255,255,.08)'; c.fillRect(x - w / 2 + 2, P.top, 5, P.botBot - P.top);
    });
  };

  /** drucik wytrycha w przekroju: biegnie kanałem i zagina się na wybraną zapadkę */
  const drawPickWire = c => {
    if (g.broken) return;
    const q = g.pins[g.sel];
    g.wireX = DL.lerp(g.wireX, pinX(g.sel), 0.3);
    const tipY = P.top + (q.set ? 0 : q.p) * P.travel - 2 + g.dip * 4;
    const x = g.wireX;
    c.save();
    c.shadowColor = 'rgba(0,0,0,.5)'; c.shadowBlur = 5; c.shadowOffsetY = 2;
    c.strokeStyle = lin(c, 0, P.keyY - 4, 0, P.keyY + 4, [[0, '#6a6660'], [0.5, '#d5d1cb'], [1, '#55514c']]);
    c.lineWidth = 4.5; c.lineCap = 'round'; c.lineJoin = 'round';
    c.beginPath();
    c.moveTo(WIN.x0 + 12, P.keyY - 4);
    c.lineTo(x - 12, P.keyY - 4);
    c.quadraticCurveTo(x + 2, P.keyY - 4, x + 2, Math.max(P.keyY + 6, tipY - 8));
    c.lineTo(x + 2, tipY);
    c.stroke();
    c.restore();
  };

  /* ---------------- narzędzia na zewnątrz ---------------- */
  const drawPickHandle = c => {
    c.save();
    c.translate(0, g.dip * 3);
    c.shadowColor = 'rgba(0,0,0,.6)'; c.shadowBlur = 24; c.shadowOffsetX = 14; c.shadowOffsetY = 18;
    // trzon do dziurki
    c.fillStyle = lin(c, 0, K.y - 8, 0, K.y + 6, [[0, '#8f8b86'], [0.5, '#4d4945'], [1, '#2b2825']]);
    poly(c, [[228, K.y - 12], [K.x - 4, K.y - 7], [K.x - 4, K.y + 3], [228, K.y + 8]]); c.fill();
    // zdobienie na trzonie
    c.fillStyle = '#a6a19a';
    c.beginPath(); c.arc(246, K.y - 2, 4, 0, 7); c.arc(254, K.y - 7, 3, 0, 7); c.arc(254, K.y + 3, 3, 0, 7); c.fill();
    // szeroka płaska rękojeść
    const hx0 = -40, hx1 = 214, hy0 = K.y - 60, hy1 = K.y + 36;
    c.beginPath();
    c.moveTo(hx0, hy0 + 6); c.lineTo(hx1 - 40, hy0 + 2);
    c.quadraticCurveTo(hx1 + 2, hy0 + 4, hx1 + 14, K.y - 12);
    c.lineTo(hx1 + 14, K.y + 8);
    c.quadraticCurveTo(hx1 + 2, hy1, hx1 - 40, hy1 + 2); c.lineTo(hx0, hy1 + 8); c.closePath();
    c.fillStyle = lin(c, 0, hy0, 0, hy1, [[0, '#a19c96'], [0.2, '#7b7772'], [0.7, '#5a5753'], [1, '#2f2d2b']]);
    c.fill();
    c.restore();
    c.save();
    c.translate(0, g.dip * 3);
    c.strokeStyle = 'rgba(255,255,255,.3)'; c.lineWidth = 1.5;
    c.beginPath(); c.moveTo(hx0, hy0 + 8); c.lineTo(hx1 - 40, hy0 + 4); c.stroke();
    // nit
    c.fillStyle = rad(c, 160, K.y - 12, 0, 11, [[0, '#f1e3cf'], [0.5, '#a28e75'], [1, '#3b3127']], 157, K.y - 16);
    c.beginPath(); c.arc(160, K.y - 12, 10, 0, 7); c.fill();
    c.restore();
  };

  const drawTension = c => {
    // napinacz: cienka blaszka z dziurki pionowo w górę, poza kadr
    c.save();
    c.shadowColor = 'rgba(0,0,0,.55)'; c.shadowBlur = 12; c.shadowOffsetX = 10; c.shadowOffsetY = 8;
    c.fillStyle = lin(c, K.x - 16, 0, K.x - 4, 0, [[0, '#4b4844'], [0.5, '#a9a49d'], [1, '#3a3734']]);
    poly(c, [[K.x - 13, K.y - 18], [K.x - 4, K.y - 18], [K.x - 16, -20], [K.x - 26, -20]]); c.fill();
    c.fillStyle = '#8f8a84';
    c.beginPath(); c.ellipse(K.x - 22, 40, 7, 16, -0.08, 0, 7); c.fill();
    c.restore();
  };

  /* ---------------- spinka i śrubokręt (proste zamki) ---------------- */
  const TH_MIN = Math.PI * 1.12, TH_MAX = Math.PI * 1.88;

  const drawBobbyPin = (c, th, bend, broken, fall) => {
    const tx = K.x, ty = K.y - 16;
    const dx = Math.cos(th), dy = Math.sin(th), px = -dy, py = dx;
    const L = broken ? 60 : 260, b = bend * 22;
    c.save();
    c.shadowColor = 'rgba(0,0,0,.55)'; c.shadowBlur = 10; c.shadowOffsetX = 8; c.shadowOffsetY = 10;
    c.lineCap = 'round'; c.lineJoin = 'round';
    c.strokeStyle = '#1f1916'; c.lineWidth = 3.6;
    // jasny odblask lakieru, żeby spinka odcinała się od ciemnego brązu
    c.save(); c.shadowColor = 'transparent'; c.strokeStyle = 'rgba(255,225,190,.35)'; c.lineWidth = 6;
    c.beginPath(); c.moveTo(tx, ty); c.quadraticCurveTo(tx + dx * L * 0.5 + px * b, ty + dy * L * 0.5 + py * b, tx + dx * L, ty + dy * L); c.stroke(); c.restore();
    c.beginPath();
    c.moveTo(tx, ty + 8); c.lineTo(tx, ty);
    c.quadraticCurveTo(tx + dx * L * 0.5 + px * b, ty + dy * L * 0.5 + py * b, tx + dx * L, ty + dy * L);
    c.stroke();
    if (!broken) {
      const ex = tx + dx * L, ey = ty + dy * L;
      c.beginPath();
      c.moveTo(ex, ey);
      c.quadraticCurveTo(ex + dx * 14 + px * 7, ey + dy * 14 + py * 7, ex + px * 12, ey + py * 12);
      for (let t = 1; t >= 0.3; t -= 0.04) {
        const w = Math.sin(t * 38) * 3.2;
        c.lineTo(tx + dx * L * t + px * (12 + w) + px * b * 0.6 * Math.sin(t * Math.PI), ty + dy * L * t + py * (12 + w) + py * b * 0.6 * Math.sin(t * Math.PI));
      }
      c.stroke();
      c.shadowColor = 'transparent';
      c.strokeStyle = 'rgba(255,230,210,.22)'; c.lineWidth = 1;
      c.beginPath(); c.moveTo(tx + dx * 30 - px, ty + dy * 30 - py); c.lineTo(tx + dx * (L - 20) - px, ty + dy * (L - 20) - py); c.stroke();
    }
    c.restore();
    if (broken && fall) {
      c.save();
      c.translate(tx + dx * 160 + fall.x, ty + dy * 160 + fall.y); c.rotate(th + fall.r);
      c.strokeStyle = '#1f1916'; c.lineWidth = 3.6; c.lineCap = 'round';
      c.beginPath(); c.moveTo(-90, 0); c.lineTo(100, 0); c.quadraticCurveTo(116, 6, 100, 12); c.lineTo(-40, 12); c.stroke();
      c.restore();
    }
  };

  const drawScrewdriver = (c, rot) => {
    // śrubokręt płaski: grot w dole dziurki, trzon w lewo-dół, żółta rękojeść poza szyldem
    c.save();
    c.translate(K.x, K.y);
    c.rotate(rot);
    c.shadowColor = 'rgba(0,0,0,.6)'; c.shadowBlur = 18; c.shadowOffsetX = 12; c.shadowOffsetY = 16;
    c.rotate(Math.PI * 0.82);
    c.fillStyle = lin(c, 0, -4, 0, 4, [[0, '#f2f4f8'], [0.5, '#9aa1ad'], [1, '#5c6370']]);
    c.fillRect(14, -4, 200, 8);
    c.beginPath(); c.moveTo(214, -14); c.lineTo(420, -30); c.quadraticCurveTo(440, 0, 420, 30); c.lineTo(214, 14); c.closePath();
    c.fillStyle = lin(c, 0, -30, 0, 30, [[0, '#8a6a00'], [0.3, '#f5c518'], [0.5, '#ffe27a'], [1, '#9c7700']]);
    c.fill();
    c.shadowColor = 'transparent';
    c.fillStyle = 'rgba(20,20,22,.92)';
    poly(c, [[280, -19], [380, -26], [380, 26], [280, 19]]); c.fill();
    c.restore();
  };

  /* ==========================================================================
     HUD (DOM) – układ jak w grze
     ========================================================================== */
  const ICON_EYE = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M2 12s3.6-7 10-7 10 7 10 7-3.6 7-10 7S2 12 2 12z"/><circle cx="12" cy="12" r="3"/><path d="M3 3l18 18"/></svg>';
  const ICON_BAG = '<svg viewBox="0 0 48 56"><defs><clipPath id="lpBagClip"><path d="M8 20c0-6 4-10 10-10h12c6 0 10 4 10 10v28c0 3-2 5-5 5H13c-3 0-5-2-5-5z"/></clipPath></defs><path d="M17 11V7a7 7 0 0 1 14 0v4" fill="none" stroke="#fff" stroke-width="3"/><path d="M8 20c0-6 4-10 10-10h12c6 0 10 4 10 10v28c0 3-2 5-5 5H13c-3 0-5-2-5-5z" fill="none" stroke="#fff" stroke-width="3"/><rect class="bag-fill" x="6" y="34" width="36" height="22" fill="#3aa6ff" clip-path="url(#lpBagClip)"/><path d="M4 30c0-3 2-5 4-5M44 30c0-3-2-5-4-5" stroke="#fff" stroke-width="3" fill="none"/><rect x="16" y="30" width="16" height="10" rx="2" fill="none" stroke="#fff" stroke-width="2.5"/></svg>';

  const buildHud = d => {
    const help = [['F', 'Wyjdź'], ['E', 'Latarka'], ['R', 'Noktowizor']];
    const ctl = g.mode === 'diy'
      ? [['MYSZ', 'Kąt spinki'], ['D / LPM', 'Przekręć']]
      : [['MYSZ / A D', 'Wybór zapadki'], ['PPM / S', 'Wciśnij zapadkę'], ['LPM', 'Zablokuj']];
    const cash = d.cash != null ? `$${Number(d.cash).toLocaleString('en-US')}` : '';
    g.box.insertAdjacentHTML('beforeend', `
      <div class="ts-help">${help.concat(ctl).map(([k, t]) => `<div><b>[ ${k} ]</b> ${t}</div>`).join('')}</div>
      <div class="ts-loc">${DL.esc(d.location || '')}</div>
      <div class="ts-amount"><span>${g.mode === 'diy' ? 'Ilość spinek:' : 'Ilość wytrychów:'}</span><b class="amt">${g.amount}</b></div>
      <div class="ts-bl"><span class="clock">--:--</span><span class="noise"><i></i></span><span class="eye">${ICON_EYE}</span></div>
      <div class="ts-br">
        <div class="xp"><div class="xp-t"><span class="xpv"></span><span class="lvl"></span></div><div class="xp-bar"><i></i></div><small>Włamywanie</small></div>
        <div class="bag">${ICON_BAG}<b>${cash}</b></div>
      </div>
      <div class="ts-note"></div>`);
    g.ui = {
      amt: DL.$('.amt', g.box), clock: DL.$('.clock', g.box), noise: DL.$('.noise i', g.box), note: DL.$('.ts-note', g.box),
      xpv: DL.$('.xpv', g.box), lvl: DL.$('.lvl', g.box), xpbar: DL.$('.xp-bar i', g.box), bag: DL.$('.bag-fill', g.box),
    };
    if (g.ui.bag) g.ui.bag.setAttribute('y', String(56 - 22 * DL.clamp(d.bag ?? 0.45, 0, 1)));
    xpHud(d.skill);
  };

  const xpHud = s => {
    if (!s) { DL.$('.ts-br .xp', g.box).style.display = 'none'; return; }
    g.ui.xpv.textContent = `${s.xp} / ${s.next}XP`;
    g.ui.lvl.textContent = `LVL ${s.level}`;
    g.ui.xpbar.style.transform = `scaleX(${DL.clamp(s.xp / Math.max(1, s.next), 0, 1)})`;
  };

  const clockTick = () => {
    // zegar gry: 1 minuta gry = 2 s (domyślne tempo GTA)
    const m = Math.floor(g.clock0 + (performance.now() - g.t0) / 2000) % 1440;
    g.ui.clock.textContent = `${String(Math.floor(m / 60)).padStart(2, '0')}:${String(m % 60).padStart(2, '0')}`;
  };

  const note = (text, cls = '') => {
    const n = g.ui.note;
    n.textContent = text;
    n.className = 'ts-note show ' + cls;
    clearTimeout(g.noteT);
    g.noteT = setTimeout(() => (n.className = 'ts-note ' + cls), 1300);
  };

  const makeNoise = v => {
    g.noise = Math.min(1, g.noise + v);
    if (g.noise >= 1 && !g.alarmed) {
      g.alarmed = true;
      note('Za głośno! Ktoś mógł usłyszeć…', 'bad');
      DL.post('lpEvent', { kind: 'noise' });
    }
  };

  /* ==========================================================================
     PĘKNIĘCIE / WYGRANA / WYJŚCIE
     ========================================================================== */
  const fail = () => {
    g.fails++;
    makeNoise(0.12);
    if (g.fails >= g.maxFails) return snap();
    DL.Audio.play('error', 0.3);
  };

  const snap = async () => {
    g.busy = true;
    g.broken = true;
    g.fall = { x: 0, y: 0, vy: -140, r: 0 };
    DL.Audio.play('snap');
    makeNoise(0.2);
    note(g.mode === 'diy' ? 'Spinka pękła!' : 'Wytrych pękł!', 'bad');
    const res = await DL.post('lpEvent', { kind: 'break' });
    if (!g) return;
    g.amount = res && typeof res.amount === 'number' ? res.amount : Math.max(0, g.amount - 1);
    g.ui.amt.textContent = g.amount;
    if (g.amount <= 0) return setTimeout(() => close(false), 1200);
    // kolejne narzędzie: licznik błędów od zera, zapadki wracają na górę
    setTimeout(() => {
      if (!g) return;
      g.broken = false; g.fall = null; g.fails = 0; g.busy = false; g.rot = 0; g.bend = 0;
      if (g.pins) g.pins.forEach(q => { q.set = false; q.p = 0; q.stall = 0; q.fall = 0; q.bounce = q.bounce0; });
      DL.Audio.play('pin', 0.6);
      note(g.mode === 'diy' ? 'Nowa spinka' : 'Nowy wytrych', '');
    }, 1100);
  };

  const win = () => {
    g.over = true;
    g.opening = 0.0001;
    DL.Audio.play('turn');
    setTimeout(() => DL.Audio.play('unlock'), 380);
    setTimeout(() => close(true), 1300);
  };

  const close = ok => {
    if (!g) return;
    const done = g;
    g = null;
    cancelAnimationFrame(done.raf);
    clearInterval(done.iv);
    window.removeEventListener('resize', fit);
    DL.layer.close(true);
    DL.post('gameDone', { success: !!ok });
  };

  /* ==========================================================================
     ZAPADKI (wytrych i wytrych okrągły)
     ========================================================================== */
  const makePins = (n, d) => Array.from({ length: n }, () => {
    const b = Math.floor(g.rnd() * (d.knockMax || 2));
    return { p: 0, set: false, stall: 0, fall: 0, bounce: b, bounce0: b };
  });

  const pinsUpdate = dt => {
    for (const q of g.pins) {
      if (q.set) continue;
      if (q.stall > 0) {
        q.stall -= dt;
        if (q.stall <= 0) { q.fall = 1; DL.Audio.play('pin', 0.4); }
      } else if (q.fall > 0) {
        q.p = Math.max(0, q.p - dt * 6);
        if (q.p <= 0) q.fall = 0;
      } else if (q.p > 0) q.p = Math.max(0, q.p - g.spring * dt);
    }
    g.dip = Math.max(0, g.dip - dt * 7);
  };

  const knock = () => {
    if (g.over || g.busy || g.knockCd > 0) return;
    g.knockCd = 0.12;
    g.dip = 1;
    makeNoise(0.02);
    const q = g.pins[g.sel];
    if (q.set || q.stall > 0 || q.fall > 0) return DL.Audio.play('pin', 0.25);
    q.p = Math.min(1, q.p + 0.5 * (0.9 + g.rnd() * 0.2));
    if (q.p >= 0.98) {
      if (q.bounce > 0) {               // sprężyna jeszcze nie puściła – odbija
        q.bounce--;
        q.p = 0.35;
        DL.Audio.play('pin', 0.8);
        return;
      }
      q.p = 1;
      q.stall = g.stallT;
      DL.Audio.play('set', 0.4);
    } else DL.Audio.play('pin', 0.6);
  };

  const secure = () => {
    if (g.over || g.busy) return;
    const q = g.pins[g.sel];
    if (q.set) return;
    if (q.stall > 0) {
      q.set = true;
      q.stall = 0;
      DL.Audio.play('set');
      if (g.pins.every(x => x.set)) win();
    } else fail();
  };

  const select = i => {
    if (g.over || i === g.sel) return;
    g.sel = i;
    DL.Audio.play('tick', 0.35);
  };

  /* ==========================================================================
     TRYB DIY
     ========================================================================== */
  const diyUpdate = dt => {
    if (g.over || g.busy) { if (g.opening) g.rot = Math.min(OPEN, g.rot + dt * 3); return; }
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
        if ((g.creakT -= dt) <= 0) { g.creakT = 0.3; DL.Audio.play('creak', 0.3 + (1 - allow) * 0.4); makeNoise(0.02); }
        if (g.bindT > 0.35 && !g.counted) { g.counted = true; fail(); }
      }
    } else {
      g.rot = Math.max(0, g.rot - 3 * dt);
      g.bend = DL.lerp(g.bend, 0, dt * 10);
      g.bindT = 0;
      g.counted = false;
    }
  };

  /* ==========================================================================
     ZAMEK OKRĄGŁY (tubowy)
     ========================================================================== */
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
    const q = g.pins[g.sel], ix = 1020, iy = 330;
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
     RENDER + PĘTLA
     ========================================================================== */
  const fit = () => {
    if (!g) return;
    const dpr = Math.min(2, window.devicePixelRatio || 1);
    const W = window.innerWidth, H = window.innerHeight;
    g.cv.width = W * dpr; g.cv.height = H * dpr;
    g.cv.style.width = W + 'px'; g.cv.style.height = H + 'px';
    const s = Math.max(W / VW, H / VH) * 0.98;          // kadr jak w grze – zamek wypełnia ekran
    g.view = { dpr, W, H, s, ox: (W - VW * s) / 2, oy: (H - VH * s) / 2 };
  };

  /** oświetlenie: latarka (ciepłe światło) / bez latarki (ciemno) / noktowizor (zielony) */
  const lighting = c => {
    const v = g.view;
    c.setTransform(v.dpr, 0, 0, v.dpr, 0, 0);
    if (g.nv) {
      // noktowizor: zamek barwiony na zielono (tylko narysowane piksele), świat – lekki filtr
      c.globalCompositeOperation = 'source-atop';
      c.fillStyle = 'rgba(70,255,110,.55)'; c.fillRect(0, 0, v.W, v.H);
      c.globalCompositeOperation = 'source-over';
      c.fillStyle = 'rgba(30,200,70,.16)'; c.fillRect(0, 0, v.W, v.H);
      c.fillStyle = 'rgba(0,0,0,.18)';
      for (let y = (performance.now() / 30) % 4; y < v.H; y += 4) c.fillRect(0, y, v.W, 1);
      const gr = c.createRadialGradient(v.W / 2, v.H / 2, v.H * 0.3, v.W / 2, v.H / 2, v.W * 0.7);
      gr.addColorStop(0, 'rgba(0,0,0,0)'); gr.addColorStop(1, 'rgba(0,0,0,.8)');
      c.fillStyle = gr; c.fillRect(0, 0, v.W, v.H);
    } else if (!g.light) {
      // bez latarki: zamek w półmroku, świat przyciemniony
      c.globalCompositeOperation = 'source-atop';
      c.fillStyle = 'rgba(6,10,28,.68)'; c.fillRect(0, 0, v.W, v.H);
      c.globalCompositeOperation = 'source-over';
      c.fillStyle = 'rgba(0,0,12,.35)'; c.fillRect(0, 0, v.W, v.H);
    } else {
      c.globalCompositeOperation = 'lighter';
      const x = v.ox + 360 * v.s, y = v.oy + 180 * v.s;
      const gr = c.createRadialGradient(x, y, 0, x, y, 520 * v.s);
      gr.addColorStop(0, 'rgba(255,160,80,.10)'); gr.addColorStop(1, 'rgba(255,150,60,0)');
      c.fillStyle = gr; c.fillRect(0, 0, v.W, v.H);
      c.globalCompositeOperation = 'source-over';
    }
  };

  const render = dt => {
    const c = g.ctx, v = g.view;
    c.setTransform(v.dpr, 0, 0, v.dpr, 0, 0);
    c.clearRect(0, 0, v.W, v.H);
    c.setTransform(v.dpr * v.s, 0, 0, v.dpr * v.s, v.ox * v.dpr, v.oy * v.dpr);
    if (g.mode === 'round') roundDraw(dt);
    else {
      c.drawImage(g.back, 0, 0, VW, VH);                      // korpus (+ okienko)
      if (g.mode === 'standard') { drawPins(c, dt); drawPickWire(c); }
      c.drawImage(g.front, 0, 0, VW, VH);                     // szyld
      const turn = g.mode === 'diy' ? g.rot : (g.opening ? Math.min(OPEN, g.opening * 3) : 0);
      const sh = g.binding ? { x: (Math.random() - 0.5) * 1.6, y: (Math.random() - 0.5) * 1.6 } : { x: 0, y: 0 };
      c.save(); c.translate(sh.x, sh.y); drawKeyhole(c, turn); c.restore();
      if (g.mode === 'standard') {
        drawTension(c);
        if (!g.broken) drawPickHandle(c);
        else if (g.fall) {
          c.save(); c.translate(g.fall.x, g.fall.y); c.rotate(g.fall.r * 0.1); drawPickHandle(c); c.restore();
        }
      } else {
        drawScrewdriver(c, turn);
        drawBobbyPin(c, g.th, g.bend, g.broken, g.fall);
      }
    }
    if (g.opening) g.opening += dt;
    if (g.fall) { g.fall.vy += 1800 * dt; g.fall.y += g.fall.vy * dt; g.fall.r += dt * 3; }
    lighting(c);
  };

  const loop = t => {
    if (!g) return;
    const dt = Math.min(0.05, (t - (g.last || t)) / 1000);
    g.last = t;
    g.knockCd = Math.max(0, (g.knockCd || 0) - dt);
    g.noise = Math.max(0, g.noise - dt * 0.05);
    if (g.mode === 'diy') diyUpdate(dt);
    else if (!g.over && !g.busy) pinsUpdate(dt);
    render(dt);
    if (!g) return;
    g.ui.noise.style.transform = `scaleX(${g.noise.toFixed(3)})`;
    g.raf = requestAnimationFrame(loop);
  };

  /* ==========================================================================
     OTWARCIE
     ========================================================================== */
  const open = d => {
    const mode = TOOLS[d.mode] ? d.mode : 'diy';
    const box = DL.h('div.lp-full.ts');
    box.innerHTML = '<canvas></canvas>';
    const cv = DL.$('canvas', box);
    const diff = DL.clamp(d.difficulty || 2, 1, 5);
    g = {
      box, cv, ctx: cv.getContext('2d'), mode, diff, rnd: DL.rng(d.seed || 1),
      over: false, busy: false, broken: false, fails: 0, maxFails: d.maxFails || 4, opening: 0,
      amount: d.amount ?? 1, noise: 0, alarmed: false, light: true, nv: false,
      clock0: (d.clock ?? 0), t0: performance.now(), rot: 0, bend: 0, binding: false,
    };
    buildHud(d);

    if (mode === 'diy') {
      Object.assign(g, {
        th: Math.PI * 1.5, thWant: Math.PI * 1.5, bindT: 0, creakT: 0, counted: false, turning: false,
        tol: (d.tol || [0.07, 0.055, 0.045, 0.038, 0.032][diff - 1]) * Math.PI, zone: 0.9,
      });
      g.sweet = TH_MIN + 0.1 + g.rnd() * (TH_MAX - TH_MIN - 0.2);
    } else {
      g.pins = makePins(d.pins || (mode === 'round' ? 7 : 5), d);
      Object.assign(g, { sel: 0, dip: 0, spring: d.spring || 0.35, stallT: d.stall || 0.8 });
    }
    const srnd = DL.rng((d.seed || 1) ^ 0x2545f491);
    if (mode === 'round') g.static = layer(roundStatic);
    else {
      g.back = layer(c => drawBody(c, srnd, mode === 'standard'));
      g.front = layer(c => drawEscutcheon(c, srnd));
      if (mode === 'standard') g.wireX = pinX(0);
    }

    const toVirtual = e => { const v = g.view; return [(e.clientX - v.ox) / v.s, (e.clientY - v.oy) / v.s]; };
    cv.addEventListener('mousemove', e => {
      if (!g || g.over) return;
      const [x, y] = toVirtual(e);
      if (g.mode === 'diy') {
        const want = TH_MIN + DL.clamp((x - 200) / 700, 0, 1) * (TH_MAX - TH_MIN);
        g.thWant = g.turning ? DL.lerp(g.thWant, want, 0.12) : want;
      } else if (g.mode === 'standard') {
        // najechanie kursorem-dłonią na rurkę wybiera zapadkę
        if (y > WIN.y0 - 40 && y < WIN.y1 + 30) {
          let best = g.sel, bd = 1e9;
          g.pins.forEach((_, i) => { const dd = Math.abs(pinX(i) - x); if (dd < bd) { bd = dd; best = i; } });
          if (bd < 40) select(best);
        }
      } else {
        const a = Math.atan2(y - CY, x - CX);
        let best = 0, bd = 1e9;
        g.pins.forEach((_, i) => { const h = holeXY(i)[2]; const dd = Math.abs(((a - h + Math.PI * 3) % (Math.PI * 2)) - Math.PI); if (dd < bd) { bd = dd; best = i; } });
        if (Math.hypot(x - CX, y - CY) > 40) select(best);
      }
    });
    cv.addEventListener('mousedown', e => {
      if (!g || g.over || g.busy) return;
      if (g.mode === 'diy') { if (e.button === 0) g.turning = true; return; }
      if (e.button === 0) secure(); else if (e.button === 2) knock();
    });
    cv.addEventListener('wheel', e => {
      if (!g || g.over || g.mode === 'diy') return;
      e.preventDefault();
      if (e.deltaY > 0) knock();
    }, { passive: false });
    const up = e => { if (g && e.button === 0) g.turning = false; };
    window.addEventListener('mouseup', up);
    document.body.classList.add('lp-on');
    DL.layer.open('lockpick', box, () => { document.body.classList.remove('lp-on'); window.removeEventListener('mouseup', up); window.removeEventListener('resize', fit); if (g) { cancelAnimationFrame(g.raf); clearInterval(g.iv); g = null; } });
    window.addEventListener('resize', fit);
    fit();
    clockTick();
    g.iv = setInterval(clockTick, 1000);
    g.raf = requestAnimationFrame(loop);
    DL.Audio.play('open', 0.5);
  };

  const key = (e, down) => {
    if (!g) return false;
    const k = e.code;
    if (k === 'KeyF' || k === 'Escape') { if (down && !g.over) { g.over = true; close(false); } return true; }
    if (!down) {
      if (g.mode === 'diy' && (k === 'KeyD' || k === 'Space')) g.turning = false;
      return ['KeyA', 'KeyD', 'KeyS', 'Space', 'KeyE', 'KeyR'].includes(k);
    }
    if (k === 'KeyE') { if (!e.repeat) { g.light = !g.light; DL.Audio.play('tick', 0.8); } return true; }
    if (k === 'KeyR') { if (!e.repeat) { g.nv = !g.nv; DL.Audio.play('scan', 0.4); } return true; }
    if (g.over || g.busy) return true;
    if (g.mode === 'diy') {
      if (k === 'KeyD' || k === 'Space') { g.turning = true; return true; }
      return false;
    }
    const n = g.pins.length;
    if (k === 'KeyA' && !e.repeat) { select(g.mode === 'round' ? (g.sel - 1 + n) % n : Math.max(0, g.sel - 1)); return true; }
    if (k === 'KeyD' && !e.repeat) { select(g.mode === 'round' ? (g.sel + 1) % n : Math.min(n - 1, g.sel + 1)); return true; }
    if (k === 'KeyS') { knock(); return true; }
    if (k === 'Space' && !e.repeat) { secure(); return true; }
    return false;
  };

  /** podgląd stanu dla testów automatycznych */
  const peek = () => g && { mode: g.mode, rot: g.rot, over: g.over, fails: g.fails, amount: g.amount, noise: g.noise, sel: g.sel, pins: g.pins && g.pins.map(q => ({ p: q.p, set: q.set, stall: q.stall })) };

  return { open, key, peek };
})();
