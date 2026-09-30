/* ==========================================================================
   DP Mechanic – WYTRYCH (zamek bębenkowy z przekrojem, w stylu Thief Simulator)
   Mechanika:
   - ruch myszy w poziomie – wsuwanie/wysuwanie wytrycha pod kolejne zapadki,
   - LPM + ruch w górę (lub kółko) – podnoszenie zapadki,
   - napinacz obraca rdzeń: tylko JEDNA zapadka naraz „wiąże” (losowa kolejność);
     wiążąca zapadka stawia opór, a doprowadzona do linii podziału „klika” i zostaje,
   - przepchnięcie wiążącej zapadki ponad linię = naprężenie wytrycha → złamanie,
   - hałas (drapanie, kliknięcia, przeciążenie) → pełny miernik = alarm,
   - [F] wyjście, [E] latarka, [R] noktowizor, (PPM – napięcie, gdy tryb ręczny).
   ========================================================================== */
(function () {
    'use strict';

    const VW = 1200, VH = 675;               // wirtualna scena
    const KEYWAY_Y = 330;                    // oś kanału klucza
    const KEYWAY_TOP = 318;                  // górna krawędź kanału (spód zapadek)
    const SHEAR = 262;                       // linia podziału rdzeń/korpus
    const CH_TOP = 185;                      // góra komór zapadek
    const WIN = { x: 560, y: 175, w: 262, h: 200 }; // okno przekroju
    const PLATE = { x: 450, y: 338, rx: 88, ry: 300 };
    const KEYHOLE = { x: 450, y: 300 };
    const DRIVER_LEN = 46;
    const PIVOT_X = 450;                     // punkt podparcia wytrycha w otworze
    const TIP_MIN = 572, TIP_MAX = 812;
    const PICK_TOTAL = 520;                  // długość wytrycha od końcówki do rączki

    let root, canvas, ctx, shade, sctx, back, bctx, plate, pctx;
    let ui = {};
    let W = 0, H = 0, dpr = 1, k = 1, ox = 0, oy = 0;
    let raf = 0, last = 0, running = false;
    let S = null;                            // stan gry

    /* ------------------------------------------------------------------ */
    /*  Losowość z ziarnem (tekstury – te same przy każdym przerysowaniu)   */
    /* ------------------------------------------------------------------ */
    function rng(seed) {
        let s = seed >>> 0;
        return function () { s = (s * 1664525 + 1013904223) >>> 0; return s / 4294967296; };
    }

    /* ------------------------------------------------------------------ */
    /*  DOM                                                                */
    /* ------------------------------------------------------------------ */
    function build() {
        root = App.root('lockpick', 'lp-root');
        root.innerHTML =
            '<canvas class="lp-canvas"></canvas>' +
            '<div class="lp-nv"></div>' +
            '<div class="lp-keys">' +
                '<div><b>[ F ]</b> Wyjście</div>' +
                '<div class="lp-k-light"><b>[ E ]</b> Latarka <span></span></div>' +
                '<div class="lp-k-nv"><b>[ R ]</b> Noktowizor <span></span></div>' +
                '<div class="lp-k-tension hidden"><b>[ PPM ]</b> Napięcie</div>' +
            '</div>' +
            '<div class="lp-label"></div>' +
            '<div class="lp-msg"></div>' +
            '<div class="lp-help">Ruch myszy – przesuń wytrych · <b>LPM + ruch w górę</b> (lub kółko) – podnieś zapadkę · wyczuj opór i usłysz klik</div>' +
            '<div class="lp-bl">' +
                '<div class="lp-timer mono">00:00</div>' +
                '<div class="lp-noise"><span class="lp-br">[</span><div class="lp-noise-track"><i></i></div><span class="lp-br">]</span></div>' +
                '<svg class="lp-eye" viewBox="0 0 24 24" width="26" height="26" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><path d="M2 12s4-7 10-7 10 7 10 7-4 7-10 7S2 12 2 12z"/><circle cx="12" cy="12" r="3"/><path class="lp-eye-slash" d="M4 4l16 16"/></svg>' +
            '</div>' +
            '<div class="lp-picks"><span>Ilość wytrychów:</span><b class="mono">1</b></div>' +
            '<div class="lp-tension hidden"><span>NAPIĘCIE</span><div class="lp-tension-track"><i></i></div></div>' +
            '<div class="lp-br-box">' +
                '<div class="lp-xp"><div class="lp-xp-row"><span class="lp-xp-val mono">0 / 0XP</span><span class="lp-lvl">LVL 1</span></div><div class="lp-xp-bar"><i></i></div></div>' +
                '<div class="lp-bag">' +
                    '<svg viewBox="0 0 64 80" width="54" height="68"><defs><linearGradient id="lpBag" x1="0" y1="1" x2="0" y2="0"><stop offset="0" stop-color="#1f8fff"/><stop offset="1" stop-color="#6fc3ff"/></linearGradient></defs>' +
                    '<path d="M22 14v-4a10 10 0 0 1 20 0v4" fill="none" stroke="#fff" stroke-width="4"/>' +
                    '<rect x="8" y="14" width="48" height="60" rx="14" fill="#fff"/>' +
                    '<rect class="lp-bag-fill" x="13" y="40" width="38" height="29" rx="9" fill="url(#lpBag)"/>' +
                    '<rect x="18" y="24" width="28" height="10" rx="4" fill="none" stroke="#1b2a3a" stroke-width="3"/>' +
                    '<path d="M8 40c-6 0-6 20 0 20M56 40c6 0 6 20 0 20" fill="none" stroke="#fff" stroke-width="4"/></svg>' +
                    '<div class="lp-money mono">$0</div>' +
                '</div>' +
            '</div>';
        canvas = root.querySelector('.lp-canvas');
        ctx = canvas.getContext('2d');
        shade = document.createElement('canvas'); sctx = shade.getContext('2d');
        back = document.createElement('canvas'); bctx = back.getContext('2d');
        plate = document.createElement('canvas'); pctx = plate.getContext('2d');
        ui = {
            label: root.querySelector('.lp-label'),
            msg: root.querySelector('.lp-msg'),
            timer: root.querySelector('.lp-timer'),
            noise: root.querySelector('.lp-noise-track i'),
            noiseBox: root.querySelector('.lp-noise'),
            eye: root.querySelector('.lp-eye'),
            picks: root.querySelector('.lp-picks b'),
            picksBox: root.querySelector('.lp-picks'),
            xpVal: root.querySelector('.lp-xp-val'),
            lvl: root.querySelector('.lp-lvl'),
            xpBar: root.querySelector('.lp-xp-bar i'),
            money: root.querySelector('.lp-money'),
            light: root.querySelector('.lp-k-light span'),
            nv: root.querySelector('.lp-k-nv span'),
            tensionKey: root.querySelector('.lp-k-tension'),
            tension: root.querySelector('.lp-tension'),
            tensionBar: root.querySelector('.lp-tension-track i'),
        };

        canvas.addEventListener('mousemove', onMove);
        canvas.addEventListener('mousedown', onDown);
        window.addEventListener('mouseup', onUp);
        canvas.addEventListener('wheel', onWheel, { passive: true });
        canvas.addEventListener('contextmenu', function (e) { e.preventDefault(); });
        window.addEventListener('resize', function () { if (running) resize(); });
        document.addEventListener('keydown', onKey);
        document.addEventListener('keyup', onKeyUp);
    }

    /* ------------------------------------------------------------------ */
    /*  Rozmiar i warstwy statyczne                                        */
    /* ------------------------------------------------------------------ */
    function resize() {
        dpr = Math.min(window.devicePixelRatio || 1, 2);
        W = window.innerWidth; H = window.innerHeight;
        [canvas, shade, back, plate].forEach(function (c) { c.width = Math.round(W * dpr); c.height = Math.round(H * dpr); });
        canvas.style.width = W + 'px'; canvas.style.height = H + 'px';
        const s = Math.max(W / VW, H / VH);
        k = s * dpr;
        ox = (W * dpr - VW * k) / 2;
        oy = (H * dpr - VH * k) / 2;
        renderBack();
        renderPlate();
    }
    function vt(c) { c.setTransform(k, 0, 0, k, ox, oy); }

    // tekstura porysowanego metalu w prostokącie (w bieżącej transformacji)
    function scratches(c, x, y, w, h, n, seed, light) {
        const r = rng(seed);
        c.save();
        c.lineCap = 'round';
        for (let i = 0; i < n; i++) {
            const sx = x + r() * w, sy = y + r() * h;
            const len = 4 + r() * 38, a = r() * Math.PI;
            const bright = r() < (light || 0.55);
            c.strokeStyle = bright ? 'rgba(255,236,200,' + (0.04 + r() * 0.12) + ')' : 'rgba(0,0,0,' + (0.08 + r() * 0.2) + ')';
            c.lineWidth = 0.3 + r() * 0.8;
            c.beginPath();
            c.moveTo(sx, sy);
            c.quadraticCurveTo(sx + Math.cos(a) * len * 0.5 + (r() - 0.5) * 4, sy + Math.sin(a) * len * 0.5, sx + Math.cos(a) * len, sy + Math.sin(a) * len);
            c.stroke();
        }
        // plamy / zmatowienia
        for (let i = 0; i < n / 8; i++) {
            const g = c.createRadialGradient(x + r() * w, y + r() * h, 0, x + r() * w, y + r() * h, 10 + r() * 40);
            g.addColorStop(0, 'rgba(0,0,0,' + (0.05 + r() * 0.1) + ')');
            g.addColorStop(1, 'rgba(0,0,0,0)');
            c.fillStyle = g;
            c.fillRect(x, y, w, h);
        }
        c.restore();
    }

    function roundRect(c, x, y, w, h, r) {
        c.beginPath();
        c.moveTo(x + r, y);
        c.arcTo(x + w, y, x + w, y + h, r);
        c.arcTo(x + w, y + h, x, y + h, r);
        c.arcTo(x, y + h, x, y, r);
        c.arcTo(x, y, x + w, y, r);
        c.closePath();
    }

    function renderBack() {
        const c = bctx;
        c.setTransform(1, 0, 0, 1, 0, 0);
        c.clearRect(0, 0, back.width, back.height);
        // tło nocnej sceny (ekranowo)
        const g = c.createLinearGradient(0, 0, back.width, back.height);
        g.addColorStop(0, '#0a0d1c'); g.addColorStop(0.55, '#10152b'); g.addColorStop(1, '#1b2345');
        c.fillStyle = g; c.fillRect(0, 0, back.width, back.height);
        vt(c);
        // rozmyte kształty: cegły z lewej, okno z niebieskim światłem z prawej
        c.save();
        c.filter = 'blur(' + Math.round(7 * k) + 'px)';
        const rb = rng(7);
        for (let row = 0; row < 18; row++) {
            for (let col = 0; col < 7; col++) {
                c.fillStyle = 'rgba(' + (40 + rb() * 30) + ',' + (18 + rb() * 12) + ',' + (26 + rb() * 18) + ',0.55)';
                c.fillRect(-60 + col * 58 + (row % 2) * 29, row * 40, 52, 34);
            }
        }
        c.strokeStyle = 'rgba(120,170,255,0.45)'; c.lineWidth = 16;
        c.strokeRect(930, -40, 300, 360);
        c.beginPath(); c.moveTo(1080, -40); c.lineTo(1080, 320); c.moveTo(930, 140); c.lineTo(1230, 140); c.stroke();
        c.fillStyle = 'rgba(80,120,220,0.25)'; c.fillRect(940, -30, 280, 340);
        c.fillStyle = 'rgba(60,90,200,0.22)'; c.fillRect(760, 470, 480, 260);
        c.restore();
        c.filter = 'none';

        // --- korpus wkładki (za szyldem) ---
        const bx = 500, by = 150, bw = 360, bh = 252;
        c.save();
        roundRect(c, bx, by, bw, bh, 26);
        const bg = c.createLinearGradient(0, by, 0, by + bh);
        bg.addColorStop(0, '#6d5a45'); bg.addColorStop(0.12, '#4a3c2e'); bg.addColorStop(0.5, '#2c241c'); bg.addColorStop(1, '#17130f');
        c.fillStyle = bg; c.fill();
        c.clip();
        scratches(c, bx, by, bw, bh, 520, 11, 0.5);
        // górna, oświetlona powierzchnia (bryła)
        const tg = c.createLinearGradient(0, by, 0, by + 34);
        tg.addColorStop(0, 'rgba(255,220,170,0.35)'); tg.addColorStop(1, 'rgba(255,220,170,0)');
        c.fillStyle = tg; c.fillRect(bx, by, bw, 34);
        c.restore();
        c.strokeStyle = 'rgba(0,0,0,0.6)'; c.lineWidth = 2; roundRect(c, bx, by, bw, bh, 26); c.stroke();

        // kołnierz / krzywka po prawej (walec widziany z boku)
        c.save();
        const fx = 845, fy = 128, fw = 82, fh = 296;
        roundRect(c, fx, fy, fw, fh, 30);
        const fg = c.createLinearGradient(fx, 0, fx + fw, 0);
        fg.addColorStop(0, '#2a2119'); fg.addColorStop(0.25, '#7a6346'); fg.addColorStop(0.45, '#a88a60'); fg.addColorStop(0.7, '#4a3b2b'); fg.addColorStop(1, '#1a1410');
        c.fillStyle = fg; c.fill();
        c.clip();
        scratches(c, fx, fy, fw, fh, 200, 23, 0.6);
        c.restore();
        c.strokeStyle = 'rgba(0,0,0,0.7)'; c.lineWidth = 2; roundRect(c, fx, fy, fw, fh, 30); c.stroke();
        // śruba mocująca na korpusie
        screw(c, 790, 212, 7, 0.4);

        // --- wnętrze okna przekroju: korpus (część górna) ---
        c.save();
        c.beginPath(); c.rect(WIN.x, WIN.y, WIN.w, SHEAR - WIN.y); c.clip();
        const sg = c.createLinearGradient(0, WIN.y, 0, SHEAR);
        sg.addColorStop(0, '#8d7f70'); sg.addColorStop(0.5, '#6b6057'); sg.addColorStop(1, '#4a423c');
        c.fillStyle = sg; c.fillRect(WIN.x, WIN.y, WIN.w, SHEAR - WIN.y);
        scratches(c, WIN.x, WIN.y, WIN.w, SHEAR - WIN.y, 260, 31, 0.6);
        c.restore();
        // cień na krawędzi okna (grubość ścianki)
        c.save();
        c.strokeStyle = 'rgba(0,0,0,0.55)'; c.lineWidth = 6;
        c.strokeRect(WIN.x - 3, WIN.y - 3, WIN.w + 6, WIN.h + 6);
        c.strokeStyle = 'rgba(255,225,180,0.25)'; c.lineWidth = 1.2;
        c.beginPath(); c.moveTo(WIN.x - 6, WIN.y + WIN.h + 6); c.lineTo(WIN.x + WIN.w + 6, WIN.y + WIN.h + 6); c.stroke();
        c.restore();
    }

    function screw(c, x, y, r, rot) {
        const g = c.createRadialGradient(x - r * 0.4, y - r * 0.4, 1, x, y, r);
        g.addColorStop(0, '#fff2d0'); g.addColorStop(0.35, '#c9a36a'); g.addColorStop(1, '#3b2c1c');
        c.fillStyle = g; c.beginPath(); c.arc(x, y, r, 0, Math.PI * 2); c.fill();
        c.strokeStyle = 'rgba(0,0,0,0.6)'; c.lineWidth = 1; c.stroke();
        c.save(); c.translate(x, y); c.rotate(rot || 0);
        c.strokeStyle = 'rgba(30,20,10,0.85)'; c.lineWidth = r * 0.28;
        c.beginPath(); c.moveTo(-r * 0.75, 0); c.lineTo(r * 0.75, 0); c.stroke();
        c.strokeStyle = 'rgba(255,240,200,0.35)'; c.lineWidth = 0.8;
        c.beginPath(); c.moveTo(-r * 0.75, r * 0.18); c.lineTo(r * 0.75, r * 0.18); c.stroke();
        c.restore();
    }

    // lilia heraldyczna (wygrawerowana)
    function fleur(c, x, y, s) {
        c.save(); c.translate(x, y); c.scale(s, s);
        function path() {
            c.beginPath();
            // płatek środkowy
            c.moveTo(0, -46); c.bezierCurveTo(14, -28, 14, -8, 0, 8); c.bezierCurveTo(-14, -8, -14, -28, 0, -46);
            // płatek prawy
            c.moveTo(4, 2); c.bezierCurveTo(18, -18, 40, -16, 38, -2); c.bezierCurveTo(36, 8, 24, 8, 22, 0);
            c.bezierCurveTo(26, -2, 26, -8, 22, -8); c.bezierCurveTo(14, -8, 10, 6, 6, 12);
            // płatek lewy
            c.moveTo(-4, 2); c.bezierCurveTo(-18, -18, -40, -16, -38, -2); c.bezierCurveTo(-36, 8, -24, 8, -22, 0);
            c.bezierCurveTo(-26, -2, -26, -8, -22, -8); c.bezierCurveTo(-14, -8, -10, 6, -6, 12);
            // opaska
            c.moveTo(-18, 12); c.lineTo(18, 12); c.lineTo(18, 19); c.lineTo(-18, 19); c.closePath();
            // stopa
            c.moveTo(-4, 19); c.bezierCurveTo(-4, 30, -12, 38, -20, 40); c.moveTo(4, 19); c.bezierCurveTo(4, 30, 12, 38, 20, 40);
            c.moveTo(0, 19); c.lineTo(0, 42);
        }
        c.lineWidth = 2.4; c.strokeStyle = 'rgba(255,230,190,0.28)'; c.translate(0.8, 0.8); path(); c.stroke();
        c.translate(-1.6, -1.6); c.strokeStyle = 'rgba(0,0,0,0.55)'; path(); c.stroke();
        c.restore();
    }

    function renderPlate() {
        const c = pctx;
        c.setTransform(1, 0, 0, 1, 0, 0);
        c.clearRect(0, 0, plate.width, plate.height);
        vt(c);
        const P = PLATE;
        // cień rzucony
        c.save();
        c.fillStyle = 'rgba(0,0,0,0.55)';
        c.filter = 'blur(' + Math.round(10 * k) + 'px)';
        c.beginPath(); c.ellipse(P.x + 18, P.y + 16, P.rx, P.ry, 0, 0, Math.PI * 2); c.fill();
        c.restore();
        c.filter = 'none';
        // krawędź (fazka)
        c.save();
        c.beginPath(); c.ellipse(P.x, P.y, P.rx, P.ry, 0, 0, Math.PI * 2);
        const eg = c.createLinearGradient(P.x - P.rx, P.y - P.ry, P.x + P.rx, P.y + P.ry);
        eg.addColorStop(0, '#d8b98a'); eg.addColorStop(0.35, '#6e5439'); eg.addColorStop(0.7, '#2d2117'); eg.addColorStop(1, '#8a6b48');
        c.fillStyle = eg; c.fill();
        // lico
        c.beginPath(); c.ellipse(P.x - 2, P.y, P.rx - 8, P.ry - 9, 0, 0, Math.PI * 2);
        const fg = c.createRadialGradient(P.x - 40, P.y - 120, 10, P.x, P.y, P.ry);
        fg.addColorStop(0, '#9c7d58'); fg.addColorStop(0.4, '#6a5238'); fg.addColorStop(1, '#2e2319');
        c.fillStyle = fg; c.fill();
        c.clip();
        scratches(c, P.x - P.rx, P.y - P.ry, P.rx * 2, P.ry * 2, 900, 3, 0.55);
        // połysk
        const hg = c.createLinearGradient(P.x - P.rx, 0, P.x + P.rx, 0);
        hg.addColorStop(0, 'rgba(255,220,160,0.18)'); hg.addColorStop(0.3, 'rgba(255,220,160,0.02)'); hg.addColorStop(1, 'rgba(0,0,0,0.25)');
        c.fillStyle = hg; c.fillRect(P.x - P.rx, P.y - P.ry, P.rx * 2, P.ry * 2);
        c.restore();

        // otwór na klucz (tuleja + dziurka)
        c.save();
        c.beginPath(); c.ellipse(KEYHOLE.x, KEYHOLE.y + 10, 34, 58, 0, 0, Math.PI * 2);
        const rg = c.createRadialGradient(KEYHOLE.x - 10, KEYHOLE.y - 20, 4, KEYHOLE.x, KEYHOLE.y + 10, 60);
        rg.addColorStop(0, '#b89468'); rg.addColorStop(0.6, '#5c4530'); rg.addColorStop(1, '#241a11');
        c.fillStyle = rg; c.fill();
        c.strokeStyle = 'rgba(0,0,0,0.6)'; c.lineWidth = 2; c.stroke();
        // dziurka: koło + szczelina
        c.beginPath();
        c.arc(KEYHOLE.x, KEYHOLE.y, 15, Math.PI * 0.62, Math.PI * 2.38);
        c.lineTo(KEYHOLE.x + 7, KEYWAY_Y + 30); c.lineTo(KEYHOLE.x - 7, KEYWAY_Y + 30); c.closePath();
        const dg = c.createLinearGradient(0, KEYHOLE.y - 15, 0, KEYWAY_Y + 30);
        dg.addColorStop(0, '#050403'); dg.addColorStop(1, '#120d08');
        c.fillStyle = dg; c.fill();
        c.strokeStyle = 'rgba(255,220,170,0.25)'; c.lineWidth = 1; c.stroke();
        c.restore();

        screw(c, P.x - 8, P.y - 222, 9, 0.5);
        screw(c, P.x - 8, P.y + 232, 9, -0.9);
        fleur(c, P.x - 4, P.y + 130, 1.05);
    }

    /* ------------------------------------------------------------------ */
    /*  Stan gry                                                           */
    /* ------------------------------------------------------------------ */
    function newGame(d) {
        const n = App.clamp(d.pins || 5, 3, 7);
        const spacing = Math.min(46, 232 / Math.max(n - 1, 1));
        const x0 = WIN.x + WIN.w / 2 - spacing * (n - 1) / 2;
        const pins = [];
        for (let i = 0; i < n; i++) {
            const keyLen = 14 + Math.round(Math.random() * 30);
            const need = (KEYWAY_TOP - keyLen) - SHEAR;       // o ile podnieść, by stos doszedł do linii
            const driverTop = KEYWAY_TOP - keyLen - DRIVER_LEN;
            pins.push({
                x: x0 + i * spacing, keyLen: keyLen, need: need, max: driverTop - (CH_TOP + 9),
                key: 0, drv: 0, vk: 0, set: false, flash: 0, jitter: 0,
            });
        }
        const order = pins.map(function (_, i) { return i; });
        for (let i = order.length - 1; i > 0; i--) { const j = Math.floor(Math.random() * (i + 1)); const t = order[i]; order[i] = order[j]; order[j] = t; }
        const cfg = d.cfg || {};
        const level = d.level || 1;
        S = {
            pins: pins, order: order, bindIdx: 0, spacing: spacing,
            tipX: TIP_MIN, tipXTarget: TIP_MIN, lift: 0, liftTarget: 0, pushing: false, downY: 0, downLift: 0, wheelLift: 0,
            tension: cfg.autoTension === false ? 0 : 0.62, auto: cfg.autoTension !== false, rmb: false,
            stress: 0, noise: 0, alarm: false, broken: null, newPick: 0,
            picks: d.picks, xp: d.xp || 0, level: level, levelXp: d.levelXp || 0, nextXp: d.nextXp,
            tol: (cfg.tolerance || 5) + (level - 1) * (cfg.toleranceStep || 0.8),
            stressRate: cfg.stressRate || 1.6, maxSetSpeed: cfg.maxSetSpeed || 110,
            nz: cfg.noise || {}, resetOnBreak: !!cfg.resetOnBreak, timeLimit: cfg.timeLimit || 0,
            t0: performance.now(), done: false, open: 0, light: true, nv: false,
            mx: VW * 0.6, my: VH * 0.45, lastTip: TIP_MIN, shake: 0, lastScrape: 0,
            ended: false,
        };
        ui.label.textContent = d.label || 'Zamek';
        ui.money.textContent = (d.currency || '$') + App.num(d.money || 0);
        ui.tensionKey.classList.toggle('hidden', S.auto);
        ui.tension.classList.toggle('hidden', S.auto);
        updatePicks();
        updateXp();
        setLight(true);
        setNv(false);
        msg('');
    }

    function bindingPin() {
        while (S.bindIdx < S.order.length && S.pins[S.order[S.bindIdx]].set) S.bindIdx++;
        return S.bindIdx < S.order.length ? S.order[S.bindIdx] : -1;
    }

    function addNoise(v) {
        if (!S || S.done) return;
        S.noise = Math.min(1.05, S.noise + v);
        if (S.noise >= 1 && !S.alarm) {
            S.alarm = true;
            ui.eye.classList.add('alarm');
            ui.noiseBox.classList.add('alarm');
            msg('ALARM! Za głośno…', 'err', 2600);
            App.post('lockpick_alarm', {});
        }
    }

    /* ------------------------------------------------------------------ */
    /*  Wejście                                                            */
    /* ------------------------------------------------------------------ */
    function toVirt(e) {
        return { x: (e.clientX * dpr - ox) / k, y: (e.clientY * dpr - oy) / k };
    }
    function onMove(e) {
        if (!S || S.done) return;
        const p = toVirt(e);
        S.mx = p.x; S.my = p.y;
        if (S.pushing) {
            S.liftTarget = App.clamp(S.downLift + (S.downY - p.y) * 0.9, 0, 78);
        } else if (!S.broken && S.newPick <= 0) {
            S.tipXTarget = App.clamp(p.x, TIP_MIN, TIP_MAX);
        }
    }
    function onDown(e) {
        if (!S || S.done) return;
        if (e.button === 0) {
            if (S.broken || S.newPick > 0) return;
            const p = toVirt(e);
            S.pushing = true; S.downY = p.y; S.downLift = S.liftTarget;
            root.classList.add('lp-push');
        } else if (e.button === 2) {
            S.rmb = true;
        }
    }
    function onUp(e) {
        if (!S) return;
        if (e.button === 0) { S.pushing = false; S.liftTarget = 0; S.wheelLift = 0; root.classList.remove('lp-push'); }
        else if (e.button === 2) S.rmb = false;
    }
    function onWheel(e) {
        if (!S || S.done || S.broken || S.newPick > 0) return;
        S.wheelLift = App.clamp(S.wheelLift - Math.sign(e.deltaY) * 4, 0, 78);
        if (!S.pushing) S.liftTarget = S.wheelLift;
    }
    function onKey(e) {
        if (!running || !S) return;
        const key = e.key.toLowerCase();
        if (key === 'f' || key === 'escape') { e.preventDefault(); end(false, 0); }
        else if (key === 'e' && !e.repeat) { setLight(!S.light); App.sound('click'); }
        else if (key === 'r' && !e.repeat) { setNv(!S.nv); App.sound('click'); }
    }
    function onKeyUp() { /* rezerwa */ }

    function setLight(on) {
        S.light = on;
        ui.light.textContent = on ? 'WŁ' : 'WYŁ';
        ui.light.className = on ? 'on' : '';
    }
    function setNv(on) {
        S.nv = on;
        root.classList.toggle('lp-nv-on', on);
        ui.nv.textContent = on ? 'WŁ' : 'WYŁ';
        ui.nv.className = on ? 'on' : '';
        App.post('lockpick_nv', { on: on });
    }

    /* ------------------------------------------------------------------ */
    /*  Symulacja                                                          */
    /* ------------------------------------------------------------------ */
    function pinUnderTip() {
        let best = -1, bd = 13;
        for (let i = 0; i < S.pins.length; i++) {
            const d = Math.abs(S.pins[i].x - S.tipX);
            if (d < bd) { bd = d; best = i; }
        }
        return best;
    }

    function update(dt) {
        const now = performance.now();
        // czas
        const el = (now - S.t0) / 1000;
        let shown = el;
        if (S.timeLimit > 0) {
            shown = Math.max(0, S.timeLimit - el);
            if (shown <= 0 && !S.done) { msg('Koniec czasu', 'err', 2000); end(false, 1600); }
        }
        const mm = Math.floor(shown / 60), ss = Math.floor(shown % 60);
        const t = (mm < 10 ? '0' : '') + mm + ':' + (ss < 10 ? '0' : '') + ss;
        if (ui.timer.textContent !== t) ui.timer.textContent = t;

        if (S.done) { S.open = Math.min(1, S.open + dt * 1.6); return; }

        // napięcie (tryb ręczny)
        if (!S.auto) {
            const target = S.rmb ? 0.72 : 0.0;
            S.tension += (target - S.tension) * Math.min(1, dt * 5);
            ui.tensionBar.style.transform = 'scaleX(' + S.tension.toFixed(3) + ')';
            if (S.tension < 0.22) {
                let dropped = false;
                S.pins.forEach(function (p) { if (p.set) { p.set = false; dropped = true; } });
                if (dropped) { S.bindIdx = 0; App.sound('pinDrop'); }
            }
        }
        const tensioned = S.tension >= 0.22;

        // nowy wytrych wsuwa się po złamaniu
        if (S.newPick > 0) {
            S.newPick = Math.max(0, S.newPick - dt * 1.4);
            S.tipX = TIP_MIN - 120 * S.newPick;
        }
        if (S.broken) {
            S.broken.t += dt;
            S.broken.vy += 900 * dt; S.broken.y += S.broken.vy * dt; S.broken.rot += dt * 7;
            if (S.broken.t > 1.3) S.broken = null;
        }

        // ruch poziomy (tylko gdy wytrych opuszczony)
        const canSlide = S.lift < 6 && !S.broken && S.newPick <= 0;
        if (canSlide && S.tipXTarget !== undefined) {
            const before = S.tipX;
            S.tipX += (S.tipXTarget - S.tipX) * Math.min(1, dt * 14);
            const moved = Math.abs(S.tipX - before);
            if (moved > 0.6) {
                addNoise((S.nz.scrape || 0.015) * moved * 0.02);
                if (now - S.lastScrape > 90 && moved > 2.2) { S.lastScrape = now; App.sound('scrape'); }
            }
        }

        // podnoszenie
        const under = pinUnderTip();
        const bind = tensioned ? bindingPin() : -1;
        let target = S.liftTarget;
        const prevLift = S.lift;
        // wiążąca zapadka stawia opór – idzie wolniej niż ręka
        const rate = (under >= 0 && under === bind) ? 170 : 480;
        const dl = App.clamp(target - S.lift, -420 * dt, rate * dt);
        S.lift = App.clamp(S.lift + dl, 0, 78);
        const liftSpeed = (S.lift - prevLift) / Math.max(dt, 0.001);

        // kontakt z zapadką: wysokość popchnięcia = lift - 8 (luz haczyka)
        const push = Math.max(0, S.lift - 8);
        let over = 0;
        for (let i = 0; i < S.pins.length; i++) {
            const p = S.pins[i];
            const touching = i === under;
            let wantKey = touching ? push : 0;
            if (p.set) {
                wantKey = Math.min(wantKey, p.need);
                p.drv = p.need;
            }
            // limit sprężyny (zablokowana)
            const lim = p.set ? p.need : p.max;
            if (wantKey > lim) { over = Math.max(over, (wantKey - lim)); wantKey = lim; }

            if (wantKey > p.key) {
                if (p.key < 0.5 && wantKey > 1.5) { App.sound('pinTap'); addNoise((S.nz.click || 0.035) * 0.3); }
                p.key = wantKey; p.vk = 0;
            } else {
                // sprężyna dociska stos w dół (z lekkim odbiciem)
                p.vk += 2600 * dt;
                p.key = Math.max(wantKey, p.key - p.vk * dt);
                if (p.key <= wantKey + 0.01) {
                    if (p.vk > 400 && p.key < 1) App.sound('spring');
                    p.vk = 0;
                }
            }
            if (!p.set) p.drv = p.key;

            // ustawianie wiążącej zapadki
            if (i === bind && touching && !p.set) {
                const diff = p.key - p.need;
                p.jitter = diff > -10 && diff < 0 ? (Math.random() - 0.5) * 0.8 : 0;
                if (Math.abs(diff) <= S.tol && liftSpeed < S.maxSetSpeed) {
                    p.set = true; p.drv = p.need; p.flash = 1;
                    App.sound('pinSet');
                    addNoise(S.nz.set || 0.05);
                    S.shake = 0.12;
                    App.post('lockpick_pin', {}).then(function (r) {
                        if (r && r.ok) { S.xp = r.xp; S.level = r.level; S.levelXp = r.levelXp; S.nextXp = r.nextXp; updateXp(); }
                    });
                    if (bindingPin() < 0) win();
                } else if (diff > S.tol) {
                    over = Math.max(over, diff - S.tol);
                }
            }
            if (p.flash > 0) p.flash = Math.max(0, p.flash - dt * 1.8);
        }

        // naprężenie wytrycha
        const hardTension = !S.auto && S.tension > 0.9;
        if (over > 0.5 || (hardTension && under === bind && push > 0)) {
            S.stress += dt * S.stressRate * (0.3 + Math.min(over, 24) / 24);
            addNoise((S.nz.over || 0.22) * dt);
            if (Math.random() < dt * 14) App.sound('strain');
        } else {
            S.stress = Math.max(0, S.stress - dt * 0.6);
        }
        if (S.stress >= 1) snap();

        // wygaszanie hałasu
        if (!S.alarm) S.noise = Math.max(0, S.noise - dt * (S.nz.decay || 0.07));
        ui.noise.style.transform = 'scaleX(' + Math.min(1, S.noise).toFixed(3) + ')';
        ui.noise.parentNode.classList.toggle('hot', S.noise > 0.7);
        if (S.shake > 0) S.shake = Math.max(0, S.shake - dt);
    }

    function snap() {
        S.stress = 0;
        S.pushing = false; S.liftTarget = 0;
        S.broken = { x: S.tipX, y: KEYWAY_Y - S.lift, vy: -60, rot: 0, t: 0 };
        S.lift = 0;
        S.shake = 0.35;
        App.sound('snap');
        addNoise(S.nz.snap || 0.3);
        msg('Wytrych złamany!', 'err', 1800);
        if (S.resetOnBreak) {
            S.pins.forEach(function (p) { p.set = false; });
            S.bindIdx = 0;
            setTimeout(function () { App.sound('pinDrop'); }, 150);
        }
        const hadLimit = S.picks !== -1;
        App.post('lockpick_break', {}).then(function (r) {
            if (!S || S.done) return;
            if (r && typeof r.picks === 'number') S.picks = r.picks;
            else if (hadLimit) S.picks = Math.max(0, S.picks - 1);
            updatePicks(true);
            if (hadLimit && S.picks === 0) {
                msg('Nie masz więcej wytrychów', 'err', 2200);
                end(false, 1800);
            } else {
                S.newPick = 1;
            }
        });
    }

    function win() {
        S.done = true;
        S.pushing = false; S.liftTarget = 0;
        App.sound('unlock');
        msg('Zamek otwarty', 'ok', 2000);
        end(true, 1700);
    }

    function end(success, delay) {
        if (!S || S.ended) return;
        S.ended = true;
        S.done = true;
        setTimeout(function () {
            close();
            App.post('lockpick_end', { success: success });
        }, delay || 0);
    }

    /* ------------------------------------------------------------------ */
    /*  HUD                                                                */
    /* ------------------------------------------------------------------ */
    let msgTimer = null;
    function msg(text, kind, time) {
        ui.msg.textContent = text || '';
        ui.msg.className = 'lp-msg' + (text ? ' in ' + (kind || '') : '');
        clearTimeout(msgTimer);
        if (text && time) msgTimer = setTimeout(function () { ui.msg.className = 'lp-msg'; }, time);
    }
    function updatePicks(bump) {
        ui.picks.textContent = S.picks === -1 ? '∞' : String(S.picks);
        if (bump) {
            ui.picksBox.classList.remove('bump');
            void ui.picksBox.offsetWidth;
            ui.picksBox.classList.add('bump');
        }
    }
    function updateXp() {
        const next = S.nextXp;
        const cur = S.xp;
        ui.xpVal.textContent = next ? (cur + ' / ' + next + 'XP') : (cur + 'XP · MAX');
        ui.lvl.textContent = 'LVL ' + S.level;
        const frac = next ? App.clamp((cur - S.levelXp) / Math.max(1, next - S.levelXp), 0, 1) : 1;
        ui.xpBar.style.transform = 'scaleX(' + frac.toFixed(3) + ')';
    }

    /* ------------------------------------------------------------------ */
    /*  Rysowanie                                                          */
    /* ------------------------------------------------------------------ */
    function brass(c, x, w, y0, y1, set, tint) {
        const g = c.createLinearGradient(x - w / 2, 0, x + w / 2, 0);
        if (tint === 'pink') {
            g.addColorStop(0, '#5a3d33'); g.addColorStop(0.35, '#c79a88'); g.addColorStop(0.5, '#f1d2c2'); g.addColorStop(0.7, '#9d7263'); g.addColorStop(1, '#3a2620');
        } else {
            g.addColorStop(0, '#5a3a0c'); g.addColorStop(0.3, '#d49a2a'); g.addColorStop(0.5, set ? '#fff1b0' : '#ffd97a'); g.addColorStop(0.72, '#a86d14'); g.addColorStop(1, '#3d2706');
        }
        c.fillStyle = g;
        roundRect(c, x - w / 2, y0, w, y1 - y0, 3);
        c.fill();
        c.strokeStyle = 'rgba(0,0,0,0.45)'; c.lineWidth = 0.8; c.stroke();
    }

    function spring(c, x, y0, y1) {
        const coils = 8, w = 9;
        const len = Math.max(4, y1 - y0);
        c.save();
        c.lineCap = 'round';
        // tył zwojów (ciemniejszy)
        c.strokeStyle = '#4b4f55'; c.lineWidth = 2;
        c.beginPath();
        for (let i = 0; i < coils; i++) {
            const a = y0 + (i / coils) * len, b = y0 + ((i + 0.5) / coils) * len;
            c.moveTo(x + w, a); c.lineTo(x - w, b);
        }
        c.stroke();
        // przód zwojów
        const g = c.createLinearGradient(x - w, 0, x + w, 0);
        g.addColorStop(0, '#7c8288'); g.addColorStop(0.45, '#f3f6f8'); g.addColorStop(1, '#6a7076');
        c.strokeStyle = g; c.lineWidth = 2.6;
        c.beginPath();
        for (let i = 0; i < coils; i++) {
            const a = y0 + ((i + 0.5) / coils) * len, b = y0 + ((i + 1) / coils) * len;
            c.moveTo(x - w, a); c.lineTo(x + w, b);
        }
        c.stroke();
        c.restore();
    }

    function drawInterior(c) {
        const open = S.open;
        c.save();
        c.beginPath(); c.rect(WIN.x, WIN.y, WIN.w, WIN.h); c.clip();

        // rdzeń (plug) – część dolna; przy otwieraniu obraca się (przesunięcie + ciemnienie)
        const plugShift = open * 26 + (S.tension > 0.2 ? 1.2 : 0);
        const pg = c.createLinearGradient(0, SHEAR, 0, WIN.y + WIN.h);
        pg.addColorStop(0, '#b59c7d'); pg.addColorStop(0.35, '#8a7359'); pg.addColorStop(1, '#3e3226');
        c.fillStyle = pg;
        c.fillRect(WIN.x, SHEAR + 1.5, WIN.w, WIN.h);
        c.save();
        c.globalAlpha = 0.9;
        scratchesLive(c);
        c.restore();
        // kanał klucza
        c.fillStyle = '#0b0806';
        c.fillRect(WIN.x, KEYWAY_TOP + plugShift * 0.4, WIN.w, 26);
        const kg = c.createLinearGradient(0, KEYWAY_TOP, 0, KEYWAY_TOP + 26);
        kg.addColorStop(0, 'rgba(255,220,160,0.12)'); kg.addColorStop(1, 'rgba(0,0,0,0)');
        c.fillStyle = kg; c.fillRect(WIN.x, KEYWAY_TOP + plugShift * 0.4, WIN.w, 8);

        // komory + zapadki
        for (let i = 0; i < S.pins.length; i++) {
            const p = S.pins[i];
            const x = p.x + (p.jitter || 0);
            // komora (szklana rurka jak w przekroju)
            const tg = c.createLinearGradient(x - 13, 0, x + 13, 0);
            tg.addColorStop(0, 'rgba(0,0,0,0.55)'); tg.addColorStop(0.15, 'rgba(255,255,255,0.10)'); tg.addColorStop(0.5, 'rgba(20,14,10,0.55)'); tg.addColorStop(0.85, 'rgba(255,255,255,0.08)'); tg.addColorStop(1, 'rgba(0,0,0,0.55)');
            c.fillStyle = tg;
            c.fillRect(x - 13, CH_TOP, 26, KEYWAY_TOP - CH_TOP);
            c.strokeStyle = 'rgba(255,240,220,0.18)'; c.lineWidth = 1;
            c.strokeRect(x - 13, CH_TOP, 26, KEYWAY_TOP - CH_TOP);

            const keyBottom = KEYWAY_TOP - p.key + (open * 40);
            const keyTop = keyBottom - p.keyLen;
            const drvBottom = KEYWAY_TOP - p.keyLen - p.drv;
            const drvTop = drvBottom - DRIVER_LEN;
            spring(c, x, CH_TOP + 2, drvTop);
            brass(c, x, 18, drvTop, drvBottom - 0.5, p.set, p.set ? null : 'pink');
            // zapadka dolna (z zaokrąglonym czubkiem)
            brass(c, x, 18, keyTop + 0.5, keyBottom - 4, false, null);
            c.beginPath();
            c.moveTo(x - 9, keyBottom - 6); c.quadraticCurveTo(x, keyBottom + 3, x + 9, keyBottom - 6); c.closePath();
            c.fillStyle = '#b07a1c'; c.fill();
            if (p.flash > 0) {
                c.save();
                c.globalCompositeOperation = 'lighter';
                const fg = c.createRadialGradient(x, SHEAR, 0, x, SHEAR, 34);
                fg.addColorStop(0, 'rgba(255,220,120,' + (0.55 * p.flash) + ')'); fg.addColorStop(1, 'rgba(255,200,80,0)');
                c.fillStyle = fg; c.fillRect(x - 36, SHEAR - 36, 72, 72);
                c.restore();
            }
        }
        // linia podziału (szczelina rośnie z napięciem)
        c.fillStyle = 'rgba(0,0,0,' + (0.55 + S.tension * 0.3) + ')';
        c.fillRect(WIN.x, SHEAR - 0.5, WIN.w, 1.2 + S.tension * 1.3 + open * 4);
        c.fillStyle = 'rgba(255,230,190,0.18)';
        c.fillRect(WIN.x, SHEAR + 1.6 + S.tension * 1.3, WIN.w, 0.8);

        // wytrych w kanale (część wewnątrz)
        drawPick(c, true);
        c.restore();

        // ramka okna
        c.strokeStyle = 'rgba(20,14,10,0.9)'; c.lineWidth = 2.2;
        c.strokeRect(WIN.x, WIN.y, WIN.w, WIN.h);
    }

    let plugTex = null;
    function scratchesLive(c) {
        // tekstura rdzenia prerenderowana (lekka)
        if (!plugTex || plugTex.k !== k) {
            const cv = document.createElement('canvas');
            cv.width = Math.ceil(WIN.w * k); cv.height = Math.ceil((WIN.y + WIN.h - SHEAR) * k);
            const x = cv.getContext('2d');
            x.scale(k, k);
            scratches(x, 0, 0, WIN.w, WIN.y + WIN.h - SHEAR, 220, 41, 0.6);
            plugTex = { cv: cv, k: k };
        }
        c.drawImage(plugTex.cv, WIN.x, SHEAR + 1.5, WIN.w, WIN.y + WIN.h - SHEAR);
    }

    // wytrych: obraca się wokół otworu – końcówka podnosi się, rączka opada
    function pickGeom() {
        const tipY = KEYWAY_Y + 6 - S.lift;
        const ang = Math.atan2(tipY - KEYWAY_Y, S.tipX - PIVOT_X);
        return { tipX: S.tipX, tipY: tipY, ang: ang };
    }

    function drawPick(c, inside) {
        if (S.broken && inside) {
            c.save();
            c.translate(S.broken.x, S.broken.y);
            c.rotate(S.broken.rot);
            c.globalAlpha = Math.max(0, 1 - S.broken.t / 1.3);
            c.fillStyle = '#c9ced4';
            c.fillRect(-26, -2, 26, 4);
            c.fillRect(-4, -9, 4, 9);
            c.restore();
        }
        const g = pickGeom();
        const stress = S.stress;
        c.save();
        c.translate(PIVOT_X, KEYWAY_Y);
        c.rotate(g.ang);
        const reach = Math.hypot(g.tipX - PIVOT_X, g.tipY - KEYWAY_Y);
        const len = S.broken ? Math.max(0, reach - 30) : reach;
        const bend = stress * 5;
        const sg = c.createLinearGradient(0, -3, 0, 3);
        sg.addColorStop(0, '#f4f7fa'); sg.addColorStop(0.5, stress > 0.5 ? '#e8a38f' : '#9aa1a8'); sg.addColorStop(1, '#3f454b');
        if (inside) {
            // trzonek do końcówki + haczyk
            c.strokeStyle = sg; c.lineWidth = 4.2; c.lineCap = 'round';
            c.beginPath(); c.moveTo(0, 0); c.quadraticCurveTo(len * 0.6, bend, len, 0); c.stroke();
            if (!S.broken) {
                c.beginPath(); c.moveTo(len - 1, 0); c.quadraticCurveTo(len + 3, -4, len + 1, -11); c.stroke();
            }
        } else {
            // część na zewnątrz: stała długość wytrycha – wsuwanie przesuwa rączkę
            const hx = reach - PICK_TOTAL;
            c.strokeStyle = sg; c.lineWidth = 5; c.lineCap = 'round';
            c.beginPath(); c.moveTo(-8, 0); c.lineTo(hx, 0); c.stroke();
            // rączka
            c.save();
            c.translate(hx, 0);
            const hg = c.createLinearGradient(0, -22, 0, 22);
            hg.addColorStop(0, '#a28a70'); hg.addColorStop(0.3, '#6b5847'); hg.addColorStop(0.7, '#3b3027'); hg.addColorStop(1, '#1c1611');
            c.fillStyle = hg;
            roundRect(c, -330, -24, 332, 48, 22);
            c.fill();
            c.strokeStyle = 'rgba(0,0,0,0.6)'; c.lineWidth = 1.5; c.stroke();
            c.fillStyle = 'rgba(255,235,200,0.12)';
            roundRect(c, -320, -20, 310, 10, 6); c.fill();
            // nit + ornament
            screw(c, -34, 0, 8, 0);
            c.strokeStyle = 'rgba(255,230,190,0.35)'; c.lineWidth = 1.2;
            c.beginPath(); c.moveTo(-90, -6); c.lineTo(-84, 0); c.lineTo(-90, 6); c.lineTo(-96, 0); c.closePath(); c.stroke();
            c.restore();
        }
        c.restore();
    }

    function drawWrench(c) {
        // napinacz: krótki odcinek w górnej części otworu, wygięty do góry
        const ang = -S.tension * 0.09 - S.open * 0.9;
        c.save();
        c.translate(KEYHOLE.x, KEYHOLE.y - 6);
        c.rotate(ang);
        const g = c.createLinearGradient(-3, 0, 3, 0);
        g.addColorStop(0, '#3a3f44'); g.addColorStop(0.5, '#dfe4e8'); g.addColorStop(1, '#4a5056');
        c.strokeStyle = g; c.lineCap = 'round'; c.lineWidth = 5;
        c.beginPath(); c.moveTo(6, 4); c.lineTo(-4, 4); c.quadraticCurveTo(-10, 4, -10, -6); c.lineTo(-24, -330); c.stroke();
        c.restore();
    }

    function drawLight(c) {
        // cień/latarka na osobnej warstwie
        sctx.setTransform(1, 0, 0, 1, 0, 0);
        sctx.globalCompositeOperation = 'source-over';
        sctx.clearRect(0, 0, shade.width, shade.height);
        sctx.fillStyle = S.light ? 'rgba(2,3,10,0.62)' : 'rgba(2,3,10,0.86)';
        sctx.fillRect(0, 0, shade.width, shade.height);
        vt(sctx);
        sctx.globalCompositeOperation = 'destination-out';
        if (S.light) {
            const lx = App.lerp(S.mx, 640, 0.35), ly = App.lerp(S.my, 300, 0.35);
            const g = sctx.createRadialGradient(lx, ly, 20, lx, ly, 420);
            g.addColorStop(0, 'rgba(0,0,0,1)'); g.addColorStop(0.55, 'rgba(0,0,0,0.75)'); g.addColorStop(1, 'rgba(0,0,0,0)');
            sctx.fillStyle = g;
            sctx.fillRect(-100, -100, VW + 200, VH + 200);
        } else {
            // słaba poświata z okna
            const g = sctx.createRadialGradient(1050, 120, 10, 1050, 120, 700);
            g.addColorStop(0, 'rgba(0,0,0,0.6)'); g.addColorStop(1, 'rgba(0,0,0,0)');
            sctx.fillStyle = g;
            sctx.fillRect(-100, -100, VW + 200, VH + 200);
        }
        c.setTransform(1, 0, 0, 1, 0, 0);
        c.drawImage(shade, 0, 0);
        if (S.light) {
            vt(c);
            c.save();
            c.globalCompositeOperation = 'lighter';
            const lx = App.lerp(S.mx, 640, 0.35), ly = App.lerp(S.my, 300, 0.35);
            const g = c.createRadialGradient(lx, ly, 0, lx, ly, 260);
            g.addColorStop(0, 'rgba(255,190,110,0.16)'); g.addColorStop(1, 'rgba(255,170,80,0)');
            c.fillStyle = g; c.fillRect(lx - 260, ly - 260, 520, 520);
            c.restore();
        }
        // winieta
        c.setTransform(1, 0, 0, 1, 0, 0);
        const vg = c.createRadialGradient(canvas.width / 2, canvas.height / 2, canvas.height * 0.35, canvas.width / 2, canvas.height / 2, canvas.height * 0.95);
        vg.addColorStop(0, 'rgba(0,0,0,0)'); vg.addColorStop(1, 'rgba(0,0,0,0.6)');
        c.fillStyle = vg; c.fillRect(0, 0, canvas.width, canvas.height);
    }

    function draw() {
        const c = ctx;
        c.setTransform(1, 0, 0, 1, 0, 0);
        c.clearRect(0, 0, canvas.width, canvas.height);
        let sx = 0, sy = 0;
        if (S.shake > 0) { sx = (Math.random() - 0.5) * S.shake * 30 * dpr; sy = (Math.random() - 0.5) * S.shake * 30 * dpr; }
        c.save();
        c.translate(sx, sy);
        c.drawImage(back, 0, 0);
        c.restore();
        c.setTransform(k, 0, 0, k, ox + sx, oy + sy);
        drawInterior(c);
        c.setTransform(1, 0, 0, 1, sx, sy);
        c.drawImage(plate, 0, 0);
        c.setTransform(k, 0, 0, k, ox + sx, oy + sy);
        drawWrench(c);
        if (S.newPick < 0.98) drawPick(c, false);
        drawLight(c);
    }

    function frame(t) {
        if (!running) return;
        const dt = Math.min(0.05, (t - last) / 1000 || 0.016);
        last = t;
        update(dt);
        draw();
        raf = requestAnimationFrame(frame);
    }

    /* ------------------------------------------------------------------ */
    /*  Start / stop                                                       */
    /* ------------------------------------------------------------------ */
    function open(d) {
        if (!root) build();
        App.show(root, true);
        running = true;
        resize();
        newGame(d);
        App.sound('open');
        last = performance.now();
        cancelAnimationFrame(raf);
        raf = requestAnimationFrame(frame);
    }

    function close() {
        running = false;
        cancelAnimationFrame(raf);
        if (root) App.show(root, false);
        root && root.classList.remove('lp-nv-on');
        if (ui.eye) ui.eye.classList.remove('alarm');
        if (ui.noiseBox) ui.noiseBox.classList.remove('alarm');
    }

    if (App.isDev) window.__lp = function () { return { S: S, k: k, ox: ox, oy: oy, dpr: dpr }; };
    App.on('lockpick:start', open);
    App.on('lockpick:stop', function () { if (S) S.ended = true; close(); });
})();
