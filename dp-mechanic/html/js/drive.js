/* ==========================================================================
   DP Mechanic – HUD jazdy
   - 'nitro'       – wskaźnik N2O (łuk poziomu, manometr psi, dysza, ARM/PURGE/COLD/HEAT)
   - 'dash'        – kontrolki awarii, temperatura silnika, SERWIS / BADANIE
   - 'odo'         – odometr bębnowy + TRIP
   - 'drive:sound' – lokalny syntezator (pisk klocków, bicie tarcz, rozrusznik, blow-off…)
   Bez pętli rAF: wartości animowane przejściami CSS (transform/opacity),
   DOM aktualizowany tylko przy zmianie wartości.
   ========================================================================== */
(function () {
    'use strict';

    const App = window.App;
    const h = App.h;
    const root = App.root('drive', 'dr-root');
    App.show(root, true);

    /* ------------------------------------------------------------------ */
    /*  Ikony kontrolek (styl lampek z deski rozdzielczej)                  */
    /* ------------------------------------------------------------------ */
    const LAMP = {
        engine: '<path d="M3 10h2V8h3V6h7v2h2l2 2h2v6h-2l-2 2H8l-2-2H5v-2H3z"/><path d="M9.5 11.5h4"/>',
        oil: '<path d="M2.5 12.5l4-3h7l3 2 4.5-2.5v2l-4.5 4.5H6.5l-4-1.5z"/><path d="M8 9.5V7.5h3M20 16.5a1.4 1.4 0 0 0 2.8 0c0-1-1.4-2.8-1.4-2.8S20 15.5 20 16.5z"/>',
        battery: '<rect x="3" y="7" width="18" height="12" rx="1.5"/><path d="M7 7V5h2.5v2M14.5 7V5H17v2M6.5 13h3.5M14 13h3.5M15.75 11.25v3.5"/>',
        temp: '<path d="M12 3a2 2 0 0 0-2 2v8.5a3.8 3.8 0 1 0 4 0V5a2 2 0 0 0-2-2z"/><path d="M12 9v6.5M15.5 6h3M15.5 9h3"/><path d="M3 21c1.5-1 3-1 4.5 0s3 1 4.5 0 3-1 4.5 0 3 1 4.5 0"/>',
        coolant: '<path d="M12 3a2 2 0 0 0-2 2v8.5a3.8 3.8 0 1 0 4 0V5a2 2 0 0 0-2-2z"/><path d="M12 10v5.5"/><path d="M3 21c1.5-1 3-1 4.5 0s3 1 4.5 0 3-1 4.5 0 3 1 4.5 0"/>',
        brake: '<circle cx="12" cy="12" r="6.2"/><path d="M4.6 5.8a9.5 9.5 0 0 0 0 12.4M19.4 5.8a9.5 9.5 0 0 1 0 12.4M12 8.8v4M12 15.2v.3"/>',
        tire: '<path d="M6.5 4.5C4 8 4 16 6.5 19.5h11C20 16 20 8 17.5 4.5"/><path d="M4 19.5h16M12 8v5M12 15.5v.3"/>',
        align: '<circle cx="12" cy="12" r="8.5"/><circle cx="12" cy="12" r="2.2"/><path d="M3.8 10.5h6M14.2 10.5h6M12 14.2v6.3"/><path d="M1.5 5l2 -2M22.5 5l-2-2"/>',
        balance: '<circle cx="12" cy="12" r="8.5"/><circle cx="12" cy="12" r="3.5"/><path d="M12 3.5v2M20.5 12h-2M12 20.5v-2M3.5 12h2"/><rect x="14.5" y="4.5" width="3" height="2.4" rx=".6"/>',
        clutch: '<circle cx="12" cy="12" r="8.5"/><circle cx="12" cy="12" r="4"/><path d="M12 8v8M8 12h8"/>',
        gearbox: '<circle cx="6" cy="6" r="1.7"/><circle cx="12" cy="6" r="1.7"/><circle cx="18" cy="6" r="1.7"/><circle cx="6" cy="18" r="1.7"/><circle cx="12" cy="18" r="1.7"/><path d="M6 7.7v8.6M12 7.7v8.6M18 7.7V12H6"/>',
        plug: '<path d="M12 2v3M9.5 5h5v3.5h-5zM10 8.5h4V15h-4zM12 15v3.5l-2.2 3"/><path d="M8 11.5h1.5M14.5 11.5H16"/>',
        belt: '<circle cx="7" cy="14" r="4"/><circle cx="17" cy="8" r="3"/><path d="M5 10.5L15.2 5.6M9.4 17.2l9.9-6.6"/>',
        filter: '<path d="M4 5h16l-6 7.5V18l-4 2.5v-8z"/>',
        shock: '<path d="M12 2v3M12 19v3M8 5h8M8 19h8M8.5 7.5l7 1.8-7 1.8 7 1.8-7 1.8 7 1.8"/>',
        service: '<path d="M14.7 6.3a4 4 0 0 0 5 5L21 13l-8 8-3-3 8-8-1.3-1.3a4 4 0 0 0-5-5L14 5z"/><path d="M3 21l6-6"/>',
        inspect: '<rect x="4" y="4" width="16" height="16" rx="3"/><path d="M8 12.5l2.6 2.6L16 9.6"/>',
    };
    function lampSvg(name, size) {
        const body = LAMP[name];
        if (!body) return App.icon(name, size);
        const s = size || 20;
        return '<svg class="ico" width="' + s + '" height="' + s + '" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">' + body + '</svg>';
    }

    /* ------------------------------------------------------------------ */
    /*  Budowa DOM                                                          */
    /* ------------------------------------------------------------------ */
    const hud = h('div', { class: 'dr-hud' });
    root.appendChild(hud);

    // ---------- deska: kontrolki, temperatura, odometr ----------
    const dash = h('div', { class: 'dr-dash dr-off hidden' });
    dash.innerHTML =
        '<div class="dr-dash-top">' +
            '<div class="dr-lamps"></div>' +
            '<div class="dr-allok"><i class="dr-okdot"></i><span>Systemy OK</span></div>' +
            '<div class="dr-badges">' +
                '<span class="dr-badge dr-svc hidden">' + lampSvg('service', 13) + '<span>SERWIS</span></span>' +
                '<span class="dr-badge dr-insp hidden">' + lampSvg('inspect', 13) + '<span>BADANIE</span></span>' +
            '</div>' +
        '</div>' +
        '<div class="dr-ticker"><span class="dr-ticker-text"></span></div>' +
        '<div class="dr-temp">' +
            '<span class="dr-temp-ico">' + lampSvg('temp', 16) + '</span>' +
            '<span class="dr-temp-mark">C</span>' +
            '<div class="dr-temp-track"><i class="dr-temp-fill"></i><b class="dr-temp-needle"></b></div>' +
            '<span class="dr-temp-mark">H</span>' +
            '<span class="dr-temp-val mono">--°C</span>' +
        '</div>' +
        '<div class="dr-odo">' +
            '<div class="dr-drums"></div>' +
            '<span class="dr-odo-unit">km</span>' +
            '<span class="spacer"></span>' +
            '<div class="dr-trip"><span>TRIP</span><b class="mono">0.0</b></div>' +
        '</div>';
    hud.appendChild(dash);

    const lampsBox = dash.querySelector('.dr-lamps');
    const allOk = dash.querySelector('.dr-allok');
    const svcBadge = dash.querySelector('.dr-svc');
    const inspBadge = dash.querySelector('.dr-insp');
    const ticker = dash.querySelector('.dr-ticker');
    const tickerText = dash.querySelector('.dr-ticker-text');
    const tempRow = dash.querySelector('.dr-temp');
    const tempFill = dash.querySelector('.dr-temp-fill');
    const tempNeedle = dash.querySelector('.dr-temp-needle');
    const tempVal = dash.querySelector('.dr-temp-val');
    const drumsBox = dash.querySelector('.dr-drums');
    const odoUnit = dash.querySelector('.dr-odo-unit');
    const tripVal = dash.querySelector('.dr-trip b');

    // ---------- N2O ----------
    const ARC_START = 150, ARC_SWEEP = 240, ARC_R = 48, ARC_C = 60;
    function polar(cx, cy, r, deg) {
        const a = deg * Math.PI / 180;
        return [cx + r * Math.cos(a), cy + r * Math.sin(a)];
    }
    function arcPath(cx, cy, r, from, to) {
        const p1 = polar(cx, cy, r, from), p2 = polar(cx, cy, r, to);
        const large = (to - from) > 180 ? 1 : 0;
        return 'M' + p1[0].toFixed(2) + ' ' + p1[1].toFixed(2) + ' A' + r + ' ' + r + ' 0 ' + large + ' 1 ' + p2[0].toFixed(2) + ' ' + p2[1].toFixed(2);
    }
    let ticks = '';
    for (let i = 0; i <= 10; i++) {
        const a = ARC_START + ARC_SWEEP * i / 10;
        const major = i % 5 === 0;
        const p1 = polar(ARC_C, ARC_C, 38, a), p2 = polar(ARC_C, ARC_C, major ? 33 : 35.5, a);
        ticks += '<line x1="' + p1[0].toFixed(2) + '" y1="' + p1[1].toFixed(2) + '" x2="' + p2[0].toFixed(2) + '" y2="' + p2[1].toFixed(2) + '" class="' + (major ? 'mj' : '') + '"/>';
    }
    const levelArc = arcPath(ARC_C, ARC_C, ARC_R, ARC_START, ARC_START + ARC_SWEEP);

    const PSI_CX = 50, PSI_CY = 50, PSI_R = 38;
    const nos = h('div', { class: 'dr-nos dr-off hidden' });
    nos.innerHTML =
        '<div class="dr-nos-glow"></div>' +
        '<div class="dr-nos-head">' +
            '<span class="dr-nos-title">N<sub>2</sub>O</span>' +
            '<span class="dr-nos-kit"></span>' +
            '<span class="dr-nos-state">SAFE</span>' +
        '</div>' +
        '<div class="dr-nos-body">' +
            '<div class="dr-arc">' +
                '<div class="dr-arc-halo"></div>' +
                '<svg viewBox="0 0 120 120" class="dr-arc-svg">' +
                    '<defs>' +
                        '<linearGradient id="drNosGrad" x1="0" y1="1" x2="1" y2="0"><stop offset="0" stop-color="#2463ff"/><stop offset=".55" stop-color="#3b9eff"/><stop offset="1" stop-color="#6ff0ff"/></linearGradient>' +
                        '<linearGradient id="drNosLow" x1="0" y1="1" x2="1" y2="0"><stop offset="0" stop-color="#b3212c"/><stop offset="1" stop-color="#ff6b74"/></linearGradient>' +
                    '</defs>' +
                    '<path class="dr-arc-track" d="' + levelArc + '"/>' +
                    '<path class="dr-arc-fill" d="' + levelArc + '" pathLength="100"/>' +
                    '<g class="dr-arc-ticks">' + ticks + '</g>' +
                '</svg>' +
                '<div class="dr-arc-center">' +
                    '<div class="dr-level mono"><span>0</span><small>%</small></div>' +
                    '<div class="dr-units mono">0 / 0</div>' +
                '</div>' +
                '<div class="dr-empty">PUSTA</div>' +
            '</div>' +
            '<div class="dr-nos-side">' +
                '<div class="dr-psi">' +
                    '<svg viewBox="0 0 100 58" class="dr-psi-svg">' +
                        '<path class="dr-psi-track" d="' + arcPath(PSI_CX, PSI_CY, PSI_R, 180, 360) + '"/>' +
                        '<g class="dr-psi-zones"></g>' +
                        '<g class="dr-psi-needle"><line x1="' + PSI_CX + '" y1="' + PSI_CY + '" x2="' + (PSI_CX - PSI_R + 5) + '" y2="' + PSI_CY + '"/><circle cx="' + PSI_CX + '" cy="' + PSI_CY + '" r="3.4"/></g>' +
                    '</svg>' +
                    '<div class="dr-psi-val mono"><span>0</span><small>PSI</small></div>' +
                '</div>' +
                '<div class="dr-shot">' +
                    '<div class="dr-pips"></div>' +
                    '<span class="dr-shot-label mono">—</span>' +
                '</div>' +
            '</div>' +
        '</div>' +
        '<div class="dr-leds">' +
            '<span class="dr-led" data-k="armed"><i></i>ARM</span>' +
            '<span class="dr-led" data-k="purge"><i></i>PURGE</span>' +
            '<span class="dr-led" data-k="cold"><i></i>COLD</span>' +
            '<span class="dr-led" data-k="heat"><i></i>HEAT</span>' +
        '</div>';
    hud.appendChild(nos);

    const nosKit = nos.querySelector('.dr-nos-kit');
    const nosState = nos.querySelector('.dr-nos-state');
    const arcFill = nos.querySelector('.dr-arc-fill');
    const levelNum = nos.querySelector('.dr-level span');
    const unitsEl = nos.querySelector('.dr-units');
    const psiZones = nos.querySelector('.dr-psi-zones');
    const psiNeedle = nos.querySelector('.dr-psi-needle');
    const psiNum = nos.querySelector('.dr-psi-val span');
    const pipsBox = nos.querySelector('.dr-pips');
    const shotLabel = nos.querySelector('.dr-shot-label');
    const leds = {};
    App.qsa('.dr-led', nos).forEach(function (el) { leds[el.dataset.k] = el; });

    /* ------------------------------------------------------------------ */
    /*  Pokazywanie paneli (wejście/wyjście transform + opacity)            */
    /* ------------------------------------------------------------------ */
    function setPanel(el, on) {
        if (el._on === on) return;
        el._on = on;
        clearTimeout(el._t);
        if (on) {
            el.classList.remove('hidden');
            void el.offsetWidth;
            el.classList.remove('dr-off');
        } else {
            el.classList.add('dr-off');
            el._t = setTimeout(function () { el.classList.add('hidden'); }, 380);
        }
    }

    function setText(el, v) {
        if (el._v !== v) { el._v = v; el.textContent = v; }
    }
    function setClass(el, cls, on) {
        const key = '_c_' + cls;
        if (el[key] !== on) { el[key] = on; el.classList.toggle(cls, on); }
    }
    function setTransform(el, v) {
        if (el._tr !== v) { el._tr = v; el.style.transform = v; }
    }

    /* ------------------------------------------------------------------ */
    /*  Syntezator dźwięków jazdy (WebAudio, własny kontekst)               */
    /* ------------------------------------------------------------------ */
    const Synth = (function () {
        let ctx = null, out = null, noiseBuf = null, purge = null;
        function ac() {
            if (!ctx) {
                const C = window.AudioContext || window.webkitAudioContext;
                if (!C) return null;
                ctx = new C();
                out = ctx.createGain();
                out.gain.value = 0.55;
                out.connect(ctx.destination);
            }
            if (ctx.state === 'suspended') ctx.resume();
            return ctx;
        }
        function muted() { return typeof App.isMuted === 'function' && App.isMuted(); }
        function noise(c) {
            if (!noiseBuf) {
                const len = Math.floor(c.sampleRate * 2);
                noiseBuf = c.createBuffer(1, len, c.sampleRate);
                const d = noiseBuf.getChannelData(0);
                for (let i = 0; i < len; i++) d[i] = Math.random() * 2 - 1;
            }
            const s = c.createBufferSource();
            s.buffer = noiseBuf;
            return s;
        }
        function gainEnv(c, t, attack, peak, hold, release) {
            const g = c.createGain();
            g.gain.setValueAtTime(0.0001, t);
            g.gain.exponentialRampToValueAtTime(Math.max(0.0002, peak), t + attack);
            g.gain.setValueAtTime(Math.max(0.0002, peak), t + attack + hold);
            g.gain.exponentialRampToValueAtTime(0.0001, t + attack + hold + release);
            return g;
        }
        function osc(c, type, f) {
            const o = c.createOscillator();
            o.type = type;
            o.frequency.value = f;
            return o;
        }
        function filt(c, type, f, q) {
            const b = c.createBiquadFilter();
            b.type = type;
            b.frequency.value = f;
            b.Q.value = q || 0.8;
            return b;
        }
        function end(t) { return t + 0.05; }

        // pisk klocków: wysoki, lekko drgający ton + wąskopasmowy szum
        function squeal(v) {
            const c = ac(); if (!c) return;
            const t = c.currentTime, f = 2500 + Math.random() * 1700, dur = 0.55 + Math.random() * 0.7;
            const vol = 0.05 + 0.07 * v;
            const g = gainEnv(c, t, 0.07, vol, dur - 0.25, 0.22);
            const o1 = osc(c, 'sine', f), o2 = osc(c, 'sine', f * 2.01);
            o1.frequency.linearRampToValueAtTime(f * 0.965, t + dur);
            o2.frequency.linearRampToValueAtTime(f * 2.01 * 0.965, t + dur);
            const lfo = osc(c, 'sine', 6 + Math.random() * 4), lfoG = c.createGain();
            lfoG.gain.value = f * 0.012;
            lfo.connect(lfoG); lfoG.connect(o1.frequency); lfoG.connect(o2.frequency);
            const g2 = c.createGain(); g2.gain.value = 0.28;
            o1.connect(g); o2.connect(g2); g2.connect(g);
            const n = noise(c), bp = filt(c, 'bandpass', f, 22), ng = c.createGain();
            ng.gain.value = 0.35;
            n.connect(bp); bp.connect(ng); ng.connect(g);
            g.connect(out);
            const stop = end(t + dur + 0.1);
            [o1, o2, lfo, n].forEach(function (s) { s.start(t); s.stop(stop); });
        }

        // bicie tarcz: rytmiczne, niskie uderzenia
        function judder(v) {
            const c = ac(); if (!c) return;
            const t0 = c.currentTime, count = 7, step = 0.07 + Math.random() * 0.02;
            for (let i = 0; i < count; i++) {
                const t = t0 + i * step;
                const g = gainEnv(c, t, 0.006, 0.18 + 0.25 * v, 0.0, 0.06);
                const o = osc(c, 'sine', 52), o2 = osc(c, 'triangle', 104);
                const g2 = c.createGain(); g2.gain.value = 0.35;
                o.connect(g); o2.connect(g2); g2.connect(g); g.connect(out);
                o.start(t); o.stop(t + 0.1); o2.start(t); o2.stop(t + 0.1);
            }
            const n = noise(c), lp = filt(c, 'lowpass', 190, 0.7);
            const ng = gainEnv(c, t0, 0.02, 0.12 * v + 0.04, count * step - 0.05, 0.1);
            n.connect(lp); lp.connect(ng); ng.connect(out);
            n.start(t0); n.stop(end(t0 + count * step + 0.15));
        }

        // rozrusznik: wycie silnika elektrycznego + takty sprężania; słaby akumulator = wolniej i niżej
        function crank(d) {
            const c = ac(); if (!c) return;
            const weak = App.clamp(Number(d.weak) || 0, 0, 1);
            const dur = App.clamp(Number(d.dur) || 1.2, 0.3, 4);
            const t0 = c.currentTime;
            // klik elektromagnesu
            const k = noise(c), kf = filt(c, 'highpass', 2600, 1), kg = gainEnv(c, t0, 0.002, 0.35, 0.0, 0.04);
            k.connect(kf); kf.connect(kg); kg.connect(out); k.start(t0); k.stop(t0 + 0.08);
            const rate = 7.5 - 3.8 * weak;
            const f0 = 120 - 35 * weak;
            // wycie rozrusznika
            const whine = osc(c, 'sawtooth', f0 * 3.2), wl = filt(c, 'lowpass', 900, 1.2);
            const wg = gainEnv(c, t0 + 0.03, 0.05, 0.05, dur - 0.15, 0.1);
            whine.frequency.setValueAtTime(f0 * 3.2, t0);
            whine.frequency.linearRampToValueAtTime(f0 * 3.2 * (1 - 0.25 * weak), t0 + dur);
            whine.connect(wl); wl.connect(wg); wg.connect(out);
            whine.start(t0); whine.stop(end(t0 + dur + 0.1));
            // takty sprężania
            const period = 1 / rate;
            for (let t = t0 + 0.05; t < t0 + dur - 0.05; t += period) {
                const p = (t - t0) / dur;
                const f = f0 * (1 - 0.22 * weak * p);
                const o = osc(c, 'sawtooth', f * 1.18), lp = filt(c, 'lowpass', 520, 1.5);
                o.frequency.setValueAtTime(f * 1.18, t);
                o.frequency.exponentialRampToValueAtTime(f * 0.82, t + period * 0.85);
                const g = gainEnv(c, t, 0.018, 0.22, period * 0.25, period * 0.5);
                o.connect(lp); lp.connect(g); g.connect(out);
                o.start(t); o.stop(t + period + 0.02);
            }
            if (d.fail) {
                const t = t0 + dur;
                const e = noise(c), ef = filt(c, 'bandpass', 1500, 3), eg = gainEnv(c, t, 0.002, 0.25, 0.0, 0.05);
                e.connect(ef); ef.connect(eg); eg.connect(out); e.start(t); e.stop(t + 0.1);
            }
        }

        // wypadnięcie zapłonu – głuche „pyk” w wydechu
        function misfire() {
            const c = ac(); if (!c) return;
            const t = c.currentTime;
            const n = noise(c), lp = filt(c, 'lowpass', 320, 1), g = gainEnv(c, t, 0.004, 0.55, 0.02, 0.1);
            n.connect(lp); lp.connect(g); g.connect(out); n.start(t); n.stop(t + 0.2);
            const o = osc(c, 'sine', 62), og = gainEnv(c, t, 0.004, 0.35, 0.02, 0.13);
            o.frequency.exponentialRampToValueAtTime(34, t + 0.15);
            o.connect(og); og.connect(out); o.start(t); o.stop(t + 0.22);
        }

        // strzał w dolot (uszkodzenie od N2O)
        function backfire() {
            const c = ac(); if (!c) return;
            const t = c.currentTime;
            const n = noise(c), lp = filt(c, 'lowpass', 900, 0.8), g = gainEnv(c, t, 0.003, 0.9, 0.03, 0.28);
            n.connect(lp); lp.connect(g); g.connect(out); n.start(t); n.stop(t + 0.4);
            const o = osc(c, 'sine', 85), og = gainEnv(c, t, 0.003, 0.6, 0.02, 0.3);
            o.frequency.exponentialRampToValueAtTime(28, t + 0.32);
            o.connect(og); og.connect(out); o.start(t); o.stop(t + 0.4);
            for (let i = 0; i < 5; i++) {
                const tt = t + 0.06 + Math.random() * 0.3;
                const cr = noise(c), hp = filt(c, 'highpass', 3000, 1), cg = gainEnv(c, tt, 0.002, 0.18, 0.0, 0.02);
                cr.connect(hp); hp.connect(cg); cg.connect(out); cr.start(tt); cr.stop(tt + 0.05);
            }
        }

        // zawór upustowy turbo (psssh)
        function bov(v) {
            const c = ac(); if (!c) return;
            const t = c.currentTime, dur = 0.38;
            const n = noise(c), bp = filt(c, 'bandpass', 2600, 1.1);
            bp.frequency.setValueAtTime(2800, t);
            bp.frequency.exponentialRampToValueAtTime(850, t + dur);
            const g = gainEnv(c, t, 0.008, 0.1 + 0.14 * v, 0.05, dur - 0.06);
            n.connect(bp); bp.connect(g); g.connect(out);
            n.start(t); n.stop(end(t + dur));
        }

        // początek podania N2O – syk + niski pomruk
        function nitroOn() {
            const c = ac(); if (!c) return;
            const t = c.currentTime;
            const n = noise(c), bp = filt(c, 'bandpass', 600, 0.7);
            bp.frequency.exponentialRampToValueAtTime(2600, t + 0.5);
            const g = gainEnv(c, t, 0.03, 0.14, 0.2, 0.35);
            n.connect(bp); bp.connect(g); g.connect(out); n.start(t); n.stop(t + 0.7);
            const o = osc(c, 'sine', 44), og = gainEnv(c, t, 0.05, 0.14, 0.25, 0.35);
            o.connect(og); og.connect(out); o.start(t); o.stop(t + 0.8);
        }

        // przedmuch – ciągły syk trwający, dopóki trzymasz przycisk
        function purgeSet(on) {
            const c = ac(); if (!c) return;
            const t = c.currentTime;
            if (on) {
                if (purge) return;
                const n = noise(c);
                n.loop = true;
                const hp = filt(c, 'highpass', 3200, 0.6), bp = filt(c, 'peaking', 6500, 1.2);
                bp.gain.value = 6;
                const g = c.createGain();
                g.gain.setValueAtTime(0.0001, t);
                g.gain.exponentialRampToValueAtTime(0.16, t + 0.06);
                n.connect(hp); hp.connect(bp); bp.connect(g); g.connect(out);
                n.start(t);
                purge = { n: n, g: g };
            } else if (purge) {
                const p = purge;
                purge = null;
                p.g.gain.cancelScheduledValues(t);
                p.g.gain.setValueAtTime(Math.max(0.0002, p.g.gain.value), t);
                p.g.gain.exponentialRampToValueAtTime(0.0001, t + 0.28);
                p.n.stop(t + 0.32);
            }
        }

        function arm(on) {
            const c = ac(); if (!c) return;
            const t = c.currentTime;
            const seq = on ? [880, 1320] : [1100, 660];
            seq.forEach(function (f, i) {
                const o = osc(c, 'square', f), lp = filt(c, 'lowpass', 3500, 0.7);
                const g = gainEnv(c, t + i * 0.09, 0.004, 0.07, 0.05, 0.05);
                o.connect(lp); lp.connect(g); g.connect(out);
                o.start(t + i * 0.09); o.stop(t + i * 0.09 + 0.14);
            });
        }

        return {
            play: function (d) {
                if (d.name === 'purge' && !d.on) { purgeSet(false); return; }
                if (muted()) return;
                try {
                    switch (d.name) {
                        case 'squeal': squeal(App.clamp(Number(d.v) || 0.6, 0, 1)); break;
                        case 'judder': judder(App.clamp(Number(d.v) || 0.5, 0, 1)); break;
                        case 'crank': crank(d); break;
                        case 'misfire': misfire(); break;
                        case 'backfire': backfire(); break;
                        case 'bov': bov(App.clamp(Number(d.v) || 0.8, 0, 1)); break;
                        case 'nitro': nitroOn(); break;
                        case 'purge': purgeSet(true); break;
                        case 'arm': arm(!!d.on); break;
                        case 'shot': App.sound('tick'); break;
                        case 'tick': App.sound('tick'); break;
                        default: App.sound(d.name);
                    }
                } catch (e) { /* audio niedostępne */ }
            },
            stopAll: function () { purgeSet(false); },
        };
    })();

    App.on('drive:sound', function (d) { Synth.play(d); });

    /* ------------------------------------------------------------------ */
    /*  N2O                                                                 */
    /* ------------------------------------------------------------------ */
    const nosCfg = { pmin: -1, pmax: -1, pideal: -1, sMin: 300, sMax: 1150 };
    let pipsCount = -1;

    function psiAngle(psi) {
        const t = App.clamp((psi - nosCfg.sMin) / (nosCfg.sMax - nosCfg.sMin), 0, 1);
        return t * 180;
    }
    function psiToDeg(psi) { return 180 + psiAngle(psi); }

    function buildPsiScale(pmin, pmax, pideal) {
        if (nosCfg.pmin === pmin && nosCfg.pmax === pmax && nosCfg.pideal === pideal) return;
        nosCfg.pmin = pmin; nosCfg.pmax = pmax; nosCfg.pideal = pideal;
        nosCfg.sMin = Math.max(0, Math.floor(pmin * 0.6 / 50) * 50);
        nosCfg.sMax = Math.max(nosCfg.sMin + 100, pmax);
        const band = Math.max(30, (pmax - pmin) * 0.08);
        const zones = [
            [nosCfg.sMin, pmin, 'z-cold'],
            [pmin, pideal - band, 'z-low'],
            [pideal - band, Math.min(pmax, pideal + band), 'z-ok'],
            [Math.min(pmax, pideal + band), nosCfg.sMax, 'z-high'],
        ];
        let html = '';
        zones.forEach(function (z) {
            if (z[1] - z[0] <= 0) return;
            html += '<path class="' + z[2] + '" d="' + arcPath(PSI_CX, PSI_CY, PSI_R, psiToDeg(z[0]), psiToDeg(z[1])) + '"/>';
        });
        // podziałka
        for (let i = 0; i <= 8; i++) {
            const a = 180 + 180 * i / 8;
            const p1 = polar(PSI_CX, PSI_CY, PSI_R - 5, a), p2 = polar(PSI_CX, PSI_CY, PSI_R - (i % 4 === 0 ? 10 : 8), a);
            html += '<line class="tk" x1="' + p1[0].toFixed(2) + '" y1="' + p1[1].toFixed(2) + '" x2="' + p2[0].toFixed(2) + '" y2="' + p2[1].toFixed(2) + '"/>';
        }
        psiZones.innerHTML = html;
    }

    function buildPips(n) {
        if (n === pipsCount) return;
        pipsCount = n;
        pipsBox.innerHTML = '';
        for (let i = 1; i <= n; i++) pipsBox.appendChild(h('i', { class: 'dr-pip' }));
    }

    let nosPrev = { active: false, armed: false };
    App.on('nitro', function (d) {
        if (!d.visible) {
            setPanel(nos, false);
            Synth.stopAll();
            nosPrev = { active: false, armed: false };
            return;
        }
        buildPsiScale(Number(d.pmin) || 500, Number(d.pmax) || 1150, Number(d.pideal) || 950);
        buildPips(Math.max(1, Number(d.maxShot) || 1));

        const cap = Math.max(1, Number(d.capacity) || 1);
        const level = Math.max(0, Number(d.level) || 0);
        const pct = App.clamp(level / cap * 100, 0, 100);
        arcFill.style.strokeDashoffset = String(100 - pct);
        setText(levelNum, String(Math.round(pct)));
        setText(unitsEl, Math.round(level) + ' / ' + cap);
        setText(nosKit, d.kit || '');
        setClass(nos, 'dr-low', pct < 15 && level > 0);
        setClass(nos, 'dr-isempty', level <= 0);

        const psi = Number(d.psi) || 0;
        setTransform(psiNeedle, 'rotate(' + psiAngle(psi).toFixed(1) + 'deg)');
        setText(psiNum, String(Math.round(psi)));
        setClass(nos, 'dr-psi-bad', psi < (Number(d.pmin) || 500));
        setClass(nos, 'dr-psi-ok', Math.abs(psi - (Number(d.pideal) || 950)) <= Math.max(30, ((Number(d.pmax) || 1150) - (Number(d.pmin) || 500)) * 0.08));

        const shot = Number(d.shot) || 1;
        const pips = pipsBox.children;
        for (let i = 0; i < pips.length; i++) {
            setClass(pips[i], 'on', i < shot);
            setClass(pips[i], 'cur', i === shot - 1);
        }
        setText(shotLabel, d.shotLabel || '');

        setClass(leds.armed, 'on', !!d.armed);
        setClass(leds.purge, 'on', !!d.purge);
        setClass(leds.purge, 'na', !d.hasPurge);
        setClass(leds.cold, 'on', !!d.cold);
        setClass(leds.heat, 'on', !!d.heater);
        setClass(leds.heat, 'na', !d.hasHeater);
        setClass(leds.heat, 'warming', !!d.heater && psi < (Number(d.pideal) || 950) - 10);

        setClass(nos, 'dr-armed', !!d.armed);
        setClass(nos, 'dr-active', !!d.active);
        setClass(nos, 'dr-purging', !!d.purge);
        setText(nosState, d.active ? 'FLOW' : (d.purge ? 'PURGE' : (d.armed ? 'ARMED' : 'SAFE')));

        // mikro-animacja przy uzbrojeniu / starcie podania
        if ((d.armed && !nosPrev.armed || d.active && !nosPrev.active) && nos._on) {
            nos.classList.remove('dr-kick');
            void nos.offsetWidth;
            nos.classList.add('dr-kick');
            clearTimeout(nos._kick);
            nos._kick = setTimeout(function () { nos.classList.remove('dr-kick'); }, 320);
        }
        nosPrev = { active: !!d.active, armed: !!d.armed };
        setPanel(nos, true);
    });

    /* ------------------------------------------------------------------ */
    /*  Kontrolki                                                           */
    /* ------------------------------------------------------------------ */
    const lamps = new Map();     // id → { el, level, label }
    let dashOn = false, odoOn = false, dashFresh = true, tickerTimer = null;

    function showTicker(text, level) {
        tickerText.textContent = text;
        ticker.classList.remove('warn', 'err');
        ticker.classList.add(level === 'err' ? 'err' : 'warn');
        ticker.classList.remove('in');
        void ticker.offsetWidth;
        ticker.classList.add('in');
        clearTimeout(tickerTimer);
        tickerTimer = setTimeout(function () { ticker.classList.remove('in'); }, 4200);
    }

    function updateLamps(list) {
        const seen = new Set();
        const added = [];
        list.forEach(function (w) {
            if (!w || !w.id) return;
            const id = String(w.id);
            seen.add(id);
            let l = lamps.get(id);
            if (!l) {
                const el = h('span', { class: 'dr-lamp', html: lampSvg(w.icon || 'engine', 19) });
                lampsBox.appendChild(el);
                requestAnimationFrame(function () { el.classList.add('in'); });
                l = { el: el, level: null, label: '' };
                lamps.set(id, l);
                added.push(w);
            } else if (l.level !== w.level && w.level === 'err') {
                added.push(w);   // przejście z ostrzeżenia w awarię
            }
            if (l.level !== w.level) {
                l.el.classList.toggle('err', w.level === 'err');
                l.el.classList.toggle('warn', w.level !== 'err');
                l.level = w.level;
            }
            l.label = w.label || '';
        });
        lamps.forEach(function (l, id) {
            if (seen.has(id)) return;
            lamps.delete(id);
            l.el.classList.remove('in');
            l.el.classList.add('out');
            setTimeout(function () { l.el.remove(); }, 260);
        });
        setClass(allOk, 'hidden', lamps.size > 0);

        if (dashFresh) {
            dashFresh = false;
            const errs = list.filter(function (w) { return w && w.level === 'err'; });
            if (list.length) {
                const first = errs[0] || list[0];
                showTicker(list.length > 1 ? first.label + '  ·  +' + (list.length - 1) + ' ' + (list.length - 1 === 1 ? 'kontrolka' : 'kontrolki') : first.label, first.level);
                if (errs.length) Synth.play({ name: 'beep' });
            }
        } else if (added.length) {
            const w = added.find(function (x) { return x.level === 'err'; }) || added[0];
            showTicker(w.label, w.level);
            Synth.play({ name: w.level === 'err' ? 'beep' : 'tick' });
        }
    }

    function tempToC(t) {
        return t < 0.45 ? 20 + t / 0.45 * 70 : 90 + (t - 0.45) / 0.55 * 40;
    }

    const TEMP_W = 118;
    function updateDashSections() {
        setClass(dash, 'no-dash', !dashOn);
        setClass(dash, 'no-odo', !odoOn);
        setPanel(dash, dashOn || odoOn);
    }

    App.on('dash', function (d) {
        if (!d.visible) {
            dashOn = false;
            dashFresh = true;
            updateDashSections();
            return;
        }
        const list = Array.isArray(d.warnings) ? d.warnings : [];
        updateLamps(list);
        const t = App.clamp(Number(d.temp) || 0, 0, 1.05);
        setTransform(tempFill, 'scaleX(' + Math.min(1, t).toFixed(3) + ')');
        setTransform(tempNeedle, 'translate3d(' + (Math.min(1, t) * TEMP_W).toFixed(1) + 'px,0,0)');
        setText(tempVal, Math.round(tempToC(t)) + '°C');
        setClass(tempRow, 'hot', t >= 0.8);
        setClass(tempRow, 'cold', t < 0.3);
        setClass(svcBadge, 'hidden', !d.service);
        setClass(inspBadge, 'hidden', !d.inspection);
        dashOn = true;
        updateDashSections();
    });

    /* ------------------------------------------------------------------ */
    /*  Odometr bębnowy                                                     */
    /* ------------------------------------------------------------------ */
    const CELL = 22;
    const INT_DRUMS = 6;
    const drums = [];            // [0] = dziesiąte części, [1..6] = cyfry całkowite (od jedności)
    function makeDrum(tenth) {
        const strip = h('span', { class: 'dr-strip' });
        for (let i = 0; i <= 10; i++) strip.appendChild(h('span', { text: String(i % 10) }));
        const el = h('span', { class: 'dr-drum' + (tenth ? ' dr-tenth' : '') }, strip);
        return { el: el, strip: strip, pos: 0, token: 0 };
    }
    for (let i = INT_DRUMS; i >= 1; i--) drums[i] = makeDrum(false);
    drums[0] = makeDrum(true);
    for (let i = INT_DRUMS; i >= 1; i--) drumsBox.appendChild(drums[i].el);
    drumsBox.appendChild(h('span', { class: 'dr-dot' }));
    drumsBox.appendChild(drums[0].el);

    function moveDrum(d, p, ms) {
        d.strip.style.transition = ms > 0 ? 'transform ' + Math.round(ms) + 'ms linear' : 'none';
        d.strip.style.transform = 'translate3d(0,' + (-p * CELL).toFixed(2) + 'px,0)';
    }
    function setDrum(d, p, ms) {
        if (Math.abs(p - d.pos) < 0.0005) return;
        const tok = ++d.token;
        if (ms > 0 && p < d.pos - 0.0005) {
            // przejście 9 → 0: dokręć do „10”, przeskocz na 0 i dokończ
            const a = 10 - d.pos, total = a + p;
            const t1 = total > 0 ? ms * a / total : ms;
            moveDrum(d, 10, t1);
            setTimeout(function () {
                if (d.token !== tok) return;
                moveDrum(d, 0, 0);
                void d.strip.offsetWidth;
                moveDrum(d, p, ms - t1);
            }, t1);
        } else {
            moveDrum(d, p, ms);
        }
        d.pos = p;
    }

    let odoLast = null;
    function setOdo(value) {
        const v = Math.max(0, value) % 1000000;
        const x = v * 10;                        // w dziesiątych
        const jump = odoLast === null || Math.abs(value - odoLast) > 3;
        const ms = jump ? 0 : 260;
        odoLast = value;
        setDrum(drums[0], x % 10, ms);
        let pow = 10;
        for (let k = 1; k <= INT_DRUMS; k++) {
            const digit = Math.floor(x / pow) % 10;
            const lower = x % pow;
            const carry = Math.max(0, lower - (pow - 1));   // mechaniczne przeniesienie
            setDrum(drums[k], digit + carry, ms);
            pow *= 10;
        }
    }

    App.on('odo', function (d) {
        if (!d.visible) {
            odoOn = false;
            odoLast = null;
            updateDashSections();
            return;
        }
        const mi = d.unit === 'mi';
        const k = mi ? 0.621371 : 1;
        setOdo((Number(d.km) || 0) * k);
        setText(odoUnit, mi ? 'mi' : 'km');
        setText(tripVal, ((Number(d.trip) || 0) * k).toFixed(1));
        odoOn = true;
        updateDashSections();
    });
})();
