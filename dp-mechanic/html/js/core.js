/* ==========================================================================
   DP Mechanic – rdzeń NUI
   - App.on(action, fn)         – obsługa wiadomości z Lua (SendNUIMessage {action})
   - App.post(name, data)       – callback NUI → Lua (Promise z wynikiem)
   - App.h(tag, attrs, ...kids) – szybkie tworzenie DOM
   - App.root(id)               – leniwy kontener modułu w #app
   - App.esc.push/pop           – stos obsługi ESC (zamyka najwyższą warstwę)
   - App.sound(name)            – syntezowane dźwięki (WebAudio, zero plików)
   - App.icon(name)             – ikony SVG inline
   - App.money / App.num / App.esc – formatowanie
   ========================================================================== */
(function () {
    'use strict';

    const RES = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'dp-mechanic';
    const handlers = {};
    const App = window.App = {
        res: RES,
        currency: '$',
        isDev: typeof GetParentResourceName !== 'function',
    };

    /* ------------------------------------------------------------------ */
    /*  Wiadomości                                                         */
    /* ------------------------------------------------------------------ */
    App.on = function (action, fn) {
        (handlers[action] = handlers[action] || []).push(fn);
    };

    App.emit = function (action, data) {
        const list = handlers[action];
        if (!list) return;
        for (let i = 0; i < list.length; i++) {
            try { list[i](data || {}); } catch (e) { console.error('[dpm] handler', action, e); }
        }
    };

    window.addEventListener('message', function (e) {
        const d = e.data;
        if (!d || typeof d.action !== 'string') return;
        App.emit(d.action, d);
    });

    App.post = function (name, data) {
        if (App.isDev) {
            return Promise.resolve(App.mock && App.mock[name] ? App.mock[name](data) : { ok: true });
        }
        return fetch('https://' + RES + '/' + name, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify(data || {}),
        }).then(function (r) { return r.json(); }).catch(function () { return { ok: false, err: 'Brak połączenia z grą' }; });
    };

    App.ready = function () {
        App.post('nui_ready', {}).then(function (r) {
            if (r && r.currency) App.currency = r.currency;
        });
    };

    /* ------------------------------------------------------------------ */
    /*  DOM                                                                */
    /* ------------------------------------------------------------------ */
    App.h = function (tag, attrs) {
        const el = document.createElement(tag);
        if (attrs) {
            for (const k in attrs) {
                const v = attrs[k];
                if (v === undefined || v === null || v === false) continue;
                if (k === 'class') el.className = v;
                else if (k === 'html') el.innerHTML = v;
                else if (k === 'text') el.textContent = v;
                else if (k === 'style' && typeof v === 'object') Object.assign(el.style, v);
                else if (k.slice(0, 2) === 'on' && typeof v === 'function') el.addEventListener(k.slice(2).toLowerCase(), v);
                else if (k === 'dataset') Object.assign(el.dataset, v);
                else el.setAttribute(k, v === true ? '' : v);
            }
        }
        for (let i = 2; i < arguments.length; i++) {
            const c = arguments[i];
            if (c === null || c === undefined || c === false) continue;
            if (Array.isArray(c)) c.forEach(function (x) { if (x) el.append(x); });
            else el.append(c);
        }
        return el;
    };

    App.qs = function (sel, root) { return (root || document).querySelector(sel); };
    App.qsa = function (sel, root) { return Array.prototype.slice.call((root || document).querySelectorAll(sel)); };

    const roots = {};
    App.root = function (id, cls) {
        if (roots[id]) return roots[id];
        const el = App.h('div', { id: 'm-' + id, class: 'module hidden ' + (cls || '') });
        document.getElementById('app').appendChild(el);
        roots[id] = el;
        return el;
    };
    App.show = function (el, on) { el.classList.toggle('hidden', !on); };

    /* ------------------------------------------------------------------ */
    /*  ESC – stos warstw                                                  */
    /* ------------------------------------------------------------------ */
    const escStack = [];
    App.escStack = {
        push: function (id, fn) { App.escStack.remove(id); escStack.push({ id: id, fn: fn }); },
        remove: function (id) {
            for (let i = escStack.length - 1; i >= 0; i--) if (escStack[i].id === id) escStack.splice(i, 1);
        },
        top: function () { return escStack.length ? escStack[escStack.length - 1].id : null; },
    };
    document.addEventListener('keydown', function (e) {
        if (e.key === 'Escape' && escStack.length) {
            e.preventDefault();
            const top = escStack[escStack.length - 1];
            top.fn();
        }
    });

    /* ------------------------------------------------------------------ */
    /*  Formatowanie                                                       */
    /* ------------------------------------------------------------------ */
    App.num = function (v, d) {
        v = Number(v) || 0;
        return v.toLocaleString('pl-PL', { minimumFractionDigits: d || 0, maximumFractionDigits: d || 0 });
    };
    App.money = function (v) { return App.num(Math.round(Number(v) || 0)) + ' ' + App.currency; };
    App.escape = function (s) {
        return String(s === undefined || s === null ? '' : s)
            .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
    };
    App.date = function (ts) {
        if (!ts) return '—';
        const d = new Date(ts * 1000);
        const p = function (n) { return (n < 10 ? '0' : '') + n; };
        return p(d.getDate()) + '.' + p(d.getMonth() + 1) + '.' + d.getFullYear() + ' ' + p(d.getHours()) + ':' + p(d.getMinutes());
    };
    App.clamp = function (v, a, b) { return v < a ? a : (v > b ? b : v); };
    App.lerp = function (a, b, t) { return a + (b - a) * t; };
    App.debounce = function (fn, ms) {
        let t = null;
        return function () { const a = arguments, s = this; clearTimeout(t); t = setTimeout(function () { fn.apply(s, a); }, ms); };
    };
    App.throttle = function (fn, ms) {
        let last = 0, t = null;
        return function () {
            const a = arguments, s = this, now = performance.now();
            if (now - last >= ms) { last = now; fn.apply(s, a); }
            else { clearTimeout(t); t = setTimeout(function () { last = performance.now(); fn.apply(s, a); }, ms - (now - last)); }
        };
    };

    /* ------------------------------------------------------------------ */
    /*  Ikony (SVG inline, stroke = currentColor)                          */
    /* ------------------------------------------------------------------ */
    const I = {
        home: '<path d="M3 11l9-7 9 7v9a1 1 0 0 1-1 1h-5v-6H9v6H4a1 1 0 0 1-1-1z"/>',
        wrench: '<path d="M14.7 6.3a4 4 0 0 0 5 5L21 13l-8 8-3-3 8-8-1.3-1.3a4 4 0 0 0-5-5L14 5z"/><path d="M3 21l6-6"/>',
        clipboard: '<rect x="6" y="4" width="12" height="17" rx="2"/><path d="M9 4V3h6v1M9 10h6M9 14h6M9 18h4"/>',
        invoice: '<path d="M6 3h12v18l-3-2-3 2-3-2-3 2z"/><path d="M9 8h6M9 12h6M9 16h3"/>',
        project: '<rect x="3" y="4" width="18" height="14" rx="2"/><path d="M3 9h18M8 21h8"/>',
        car: '<path d="M5 16h14l-1.5-6a2 2 0 0 0-2-1.5h-7a2 2 0 0 0-2 1.5z"/><path d="M3 16v3h3v-2M21 16v3h-3v-2"/><circle cx="7.5" cy="16" r="1.5"/><circle cx="16.5" cy="16" r="1.5"/>',
        gauge: '<path d="M4 18a9 9 0 1 1 16 0"/><path d="M12 14l4-5"/><circle cx="12" cy="14" r="1.5"/>',
        box: '<path d="M3 7l9-4 9 4v10l-9 4-9-4z"/><path d="M3 7l9 4 9-4M12 11v10"/>',
        users: '<circle cx="9" cy="8" r="3.5"/><path d="M2 20c0-3.5 3-6 7-6s7 2.5 7 6"/><circle cx="17" cy="9" r="2.5"/><path d="M16 14c3 0 6 2 6 5"/>',
        bank: '<path d="M3 10l9-6 9 6M5 10v8M9 10v8M15 10v8M19 10v8M3 21h18"/>',
        history: '<path d="M3 12a9 9 0 1 0 3-6.7L3 8"/><path d="M3 3v5h5M12 7v5l3 3"/>',
        settings: '<circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z"/>',
        diag: '<path d="M3 12h4l3-8 4 16 3-8h4"/>',
        dyno: '<path d="M3 20h18M5 16l4-6 4 3 6-8"/><circle cx="19" cy="5" r="1.5"/>',
        plus: '<path d="M12 5v14M5 12h14"/>',
        minus: '<path d="M5 12h14"/>',
        close: '<path d="M6 6l12 12M18 6L6 18"/>',
        check: '<path d="M4 12l5 5L20 6"/>',
        search: '<circle cx="11" cy="11" r="7"/><path d="M20 20l-4-4"/>',
        trash: '<path d="M4 7h16M9 7V4h6v3M6 7l1 13h10l1-13"/>',
        edit: '<path d="M4 20h4L20 8l-4-4L4 16z"/>',
        bolt: '<path d="M13 2L4 14h7l-1 8 9-12h-7z"/>',
        wheel: '<circle cx="12" cy="12" r="9"/><circle cx="12" cy="12" r="3"/><path d="M12 3v6M12 15v6M3 12h6M15 12h6"/>',
        brush: '<path d="M18 3l3 3-9 9-3-3z"/><path d="M9 12c-3 0-5 2-5 5 0 2-1 3-2 4 4 0 8-1 9-5"/>',
        light: '<path d="M9 18h6M10 21h4M12 3a6 6 0 0 0-3.5 10.9V16h7v-2.1A6 6 0 0 0 12 3z"/>',
        seat: '<path d="M7 3h6l-1 10h7l1 8H6z"/>',
        star: '<path d="M12 3l2.8 5.8 6.2.9-4.5 4.4 1 6.2L12 17.4 6.5 20.3l1-6.2L3 9.7l6.2-.9z"/>',
        engine: '<path d="M4 9h3l2-2h5l2 2h2v3h2v4h-2v2h-3l-2 2H9l-2-2H4z"/>',
        cash: '<rect x="2" y="6" width="20" height="12" rx="2"/><circle cx="12" cy="12" r="3"/>',
        card: '<rect x="2" y="5" width="20" height="14" rx="2"/><path d="M2 10h20M6 15h4"/>',
        camera: '<path d="M4 7h3l2-3h6l2 3h3v12H4z"/><circle cx="12" cy="13" r="4"/>',
        orbit: '<ellipse cx="12" cy="12" rx="10" ry="4"/><circle cx="12" cy="12" r="2.5"/>',
        door: '<path d="M5 21V4l10-1v18M5 21h14M12 12h1"/>',
        arrowUp: '<path d="M12 19V5M5 12l7-7 7 7"/>',
        arrowDown: '<path d="M12 5v14M5 12l7 7 7-7"/>',
        chevron: '<path d="M9 6l6 6-6 6"/>',
        back: '<path d="M15 6l-6 6 6 6"/>',
        warning: '<path d="M12 3l10 18H2z"/><path d="M12 10v5M12 18v.5"/>',
        info: '<circle cx="12" cy="12" r="9"/><path d="M12 11v6M12 7.5v.5"/>',
        oil: '<path d="M3 12l4-3h7l3 2 4-2v2l-4 4H7l-4-2z"/><path d="M19 17a1.5 1.5 0 0 0 3 0c0-1-1.5-3-1.5-3S19 16 19 17z"/>',
        temp: '<path d="M12 3a2 2 0 0 0-2 2v9a4 4 0 1 0 4 0V5a2 2 0 0 0-2-2z"/>',
        battery: '<rect x="3" y="7" width="18" height="12" rx="1"/><path d="M7 7V5h2v2M15 7V5h2v2M7 13h3M15 13h3M16.5 11.5v3"/>',
        tire: '<circle cx="12" cy="12" r="9"/><circle cx="12" cy="12" r="5"/>',
        brake: '<circle cx="12" cy="12" r="8"/><path d="M5 5a10 10 0 0 0 0 14M19 5a10 10 0 0 1 0 14"/>',
        nitro: '<rect x="8" y="6" width="8" height="15" rx="3"/><path d="M10 6V3h4v3"/>',
        lock: '<rect x="5" y="11" width="14" height="10" rx="2"/><path d="M8 11V7a4 4 0 0 1 8 0v4"/>',
        print: '<path d="M6 9V3h12v6M6 18H4v-7h16v7h-2M6 14h12v7H6z"/>',
        send: '<path d="M22 2L11 13M22 2l-7 20-4-9-9-4z"/>',
        user: '<circle cx="12" cy="8" r="4"/><path d="M4 21c0-4 4-7 8-7s8 3 8 7"/>',
        chip: '<rect x="6" y="6" width="12" height="12" rx="1"/><path d="M9 2v4M15 2v4M9 18v4M15 18v4M2 9h4M2 15h4M18 9h4M18 15h4"/>',
        swap: '<path d="M4 7h14l-3-3M20 17H6l3 3"/>',
        refresh: '<path d="M20 11a8 8 0 1 0-2.3 5.7M20 4v7h-7"/>',
        eye: '<path d="M2 12s4-7 10-7 10 7 10 7-4 7-10 7S2 12 2 12z"/><circle cx="12" cy="12" r="3"/>',
        volume: '<path d="M4 9h4l5-4v14l-5-4H4z"/><path d="M16 9a4 4 0 0 1 0 6M19 6a8 8 0 0 1 0 12"/>',
    };
    App.icon = function (name, size) {
        const s = size || 18;
        return '<svg class="ico" width="' + s + '" height="' + s + '" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">' + (I[name] || I.info) + '</svg>';
    };

    /* ------------------------------------------------------------------ */
    /*  Dźwięki – syntezowane w WebAudio                                    */
    /* ------------------------------------------------------------------ */
    let ctx = null, master = null;
    let muted = false;
    try { muted = localStorage.getItem('dpm_mute') === '1'; } catch (e) { /* brak storage */ }
    function ac() {
        if (!ctx) {
            const C = window.AudioContext || window.webkitAudioContext;
            if (!C) return null;
            ctx = new C();
            master = ctx.createGain();
            master.gain.value = 0.35;
            master.connect(ctx.destination);
        }
        if (ctx.state === 'suspended') ctx.resume();
        return ctx;
    }
    function tone(freq, dur, type, vol, when, slide) {
        const c = ac(); if (!c) return;
        const t = c.currentTime + (when || 0);
        const o = c.createOscillator(), g = c.createGain();
        o.type = type || 'sine';
        o.frequency.setValueAtTime(freq, t);
        if (slide) o.frequency.exponentialRampToValueAtTime(Math.max(20, slide), t + dur);
        g.gain.setValueAtTime(0.0001, t);
        g.gain.exponentialRampToValueAtTime(vol || 0.3, t + 0.005);
        g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
        o.connect(g); g.connect(master);
        o.start(t); o.stop(t + dur + 0.02);
    }
    function noise(dur, vol, filterFreq, when, q, type) {
        const c = ac(); if (!c) return;
        const t = c.currentTime + (when || 0);
        const len = Math.max(1, Math.floor(c.sampleRate * dur));
        const buf = c.createBuffer(1, len, c.sampleRate);
        const data = buf.getChannelData(0);
        for (let i = 0; i < len; i++) data[i] = Math.random() * 2 - 1;
        const src = c.createBufferSource(); src.buffer = buf;
        const f = c.createBiquadFilter(); f.type = type || 'bandpass'; f.frequency.value = filterFreq || 2000; f.Q.value = q || 1;
        const g = c.createGain();
        g.gain.setValueAtTime(vol || 0.3, t);
        g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
        src.connect(f); f.connect(g); g.connect(master);
        src.start(t); src.stop(t + dur + 0.02);
    }
    const S = {
        click: function () { tone(1800, 0.03, 'square', 0.08); },
        hover: function () { tone(2400, 0.015, 'sine', 0.03); },
        open: function () { tone(520, 0.08, 'sine', 0.12); tone(780, 0.1, 'sine', 0.1, 0.05); },
        close: function () { tone(700, 0.08, 'sine', 0.1); tone(460, 0.1, 'sine', 0.08, 0.05); },
        success: function () { tone(660, 0.12, 'triangle', 0.2); tone(990, 0.18, 'triangle', 0.2, 0.09); },
        error: function () { tone(220, 0.18, 'sawtooth', 0.12); tone(160, 0.22, 'sawtooth', 0.1, 0.1); },
        notify: function () { tone(880, 0.08, 'sine', 0.12); tone(1320, 0.12, 'sine', 0.1, 0.07); },
        ratchet: function () { for (let i = 0; i < 3; i++) noise(0.018, 0.35, 3800, i * 0.028, 8, 'highpass'); },
        ratchetBack: function () { for (let i = 0; i < 4; i++) noise(0.012, 0.16, 5200, i * 0.022, 10, 'highpass'); },
        boltDone: function () { noise(0.05, 0.5, 1800, 0, 4); tone(1400, 0.06, 'square', 0.08, 0.02); },
        torque: function () { noise(0.03, 0.6, 2600, 0, 12); noise(0.03, 0.4, 2600, 0.05, 12); },
        swipe: function () { noise(0.22, 0.25, 1400, 0, 0.8); },
        beep: function () { tone(1760, 0.09, 'square', 0.1); },
        approve: function () { tone(1320, 0.09, 'square', 0.1); tone(1760, 0.16, 'square', 0.1, 0.11); },
        decline: function () { tone(440, 0.2, 'square', 0.12); tone(330, 0.3, 'square', 0.12, 0.2); },
        cash: function () { noise(0.08, 0.3, 3000, 0, 1.5); tone(2600, 0.05, 'sine', 0.05, 0.03); },
        coin: function () { tone(3200, 0.08, 'triangle', 0.12); tone(4100, 0.12, 'triangle', 0.08, 0.04); },
        spray: function () { noise(0.5, 0.2, 6000, 0, 0.6, 'highpass'); },
        air: function () { noise(0.8, 0.22, 3500, 0, 0.5, 'highpass'); },
        pop: function () { noise(0.07, 0.8, 400, 0, 1, 'lowpass'); tone(90, 0.12, 'sine', 0.4, 0, 50); },
        whoosh: function () { noise(0.35, 0.18, 900, 0, 0.7); },
        impact: function () { noise(0.1, 0.6, 250, 0, 1, 'lowpass'); },
        spin: function () { tone(120, 1.4, 'sawtooth', 0.06, 0, 520); },
        spindown: function () { tone(520, 1.6, 'sawtooth', 0.05, 0, 90); },
        knife: function () { noise(0.09, 0.35, 5500, 0, 6, 'highpass'); tone(3000, 0.05, 'sine', 0.05, 0.05); },
        tick: function () { tone(3000, 0.012, 'square', 0.05); },
        pedal: function () { noise(0.12, 0.3, 700, 0, 2); tone(160, 0.1, 'square', 0.06); },
        hiss: function () { noise(1.2, 0.18, 7000, 0, 0.4, 'highpass'); },
        stick: function () { noise(0.04, 0.3, 1200, 0, 3); },
        drill: function () { tone(180, 0.4, 'sawtooth', 0.08, 0, 260); },
    };
    App.sound = function (name) {
        if (muted) return;
        const fn = S[name];
        if (fn) { try { fn(); } catch (e) { /* audio niedostępne */ } }
    };
    App.setMuted = function (m) {
        muted = !!m;
        try { localStorage.setItem('dpm_mute', muted ? '1' : '0'); } catch (e) { /* brak storage */ }
    };
    App.isMuted = function () { return muted; };
    App.on('sound', function (d) { App.sound(d.name); });

    /* ------------------------------------------------------------------ */
    /*  Toasty                                                             */
    /* ------------------------------------------------------------------ */
    let toastBox = null;
    App.toast = function (text, kind, time) {
        if (!toastBox) {
            toastBox = App.h('div', { id: 'toasts' });
            document.body.appendChild(toastBox);
        }
        kind = kind || 'info';
        const icon = kind === 'success' ? 'check' : (kind === 'error' ? 'close' : (kind === 'warning' ? 'warning' : 'info'));
        const t = App.h('div', { class: 'toast ' + kind, html: '<span class="toast-ico">' + App.icon(icon, 16) + '</span><span class="toast-text"></span><i class="toast-bar"></i>' });
        t.querySelector('.toast-text').textContent = text;
        const bar = t.querySelector('.toast-bar');
        bar.style.animationDuration = (time || 5000) + 'ms';
        toastBox.appendChild(t);
        requestAnimationFrame(function () { t.classList.add('in'); });
        if (kind === 'error') App.sound('error'); else App.sound('notify');
        setTimeout(function () {
            t.classList.remove('in');
            t.classList.add('out');
            setTimeout(function () { t.remove(); }, 320);
        }, time || 5000);
        while (toastBox.children.length > 5) toastBox.firstChild.remove();
    };
    App.on('toast', function (d) { App.toast(d.text, d.kind, d.time); });

    /* ------------------------------------------------------------------ */
    /*  Pasek postępu                                                      */
    /* ------------------------------------------------------------------ */
    let prog = null;
    App.on('progress', function (d) {
        if (!prog) {
            prog = App.h('div', { id: 'progress', class: 'hidden', html: '<div class="progress-label"></div><div class="progress-track"><i></i></div><div class="progress-hint">X – przerwij</div>' });
            document.body.appendChild(prog);
        }
        prog.querySelector('.progress-label').textContent = d.label || '';
        const bar = prog.querySelector('i');
        bar.style.transition = 'none';
        bar.style.width = '0%';
        prog.classList.remove('hidden', 'cancelled');
        void bar.offsetWidth;
        bar.style.transition = 'width ' + (d.time || 1000) + 'ms linear';
        bar.style.width = '100%';
    });
    App.on('progressStop', function (d) {
        if (!prog) return;
        if (d.cancelled) prog.classList.add('cancelled');
        setTimeout(function () { prog.classList.add('hidden'); }, d.cancelled ? 400 : 120);
    });

    /* ------------------------------------------------------------------ */
    /*  Podpowiedzi klawiszy                                                */
    /* ------------------------------------------------------------------ */
    let hint = null;
    App.on('keyhint', function (d) {
        if (!hint) {
            hint = App.h('div', { id: 'keyhint', class: 'hidden' });
            document.body.appendChild(hint);
        }
        if (!d.list || !d.list.length) { hint.classList.add('hidden'); return; }
        hint.innerHTML = d.list.map(function (k) {
            return '<div class="kh"><span class="kbd">' + App.escape(k.key) + '</span><span>' + App.escape(k.label) + '</span></div>';
        }).join('');
        hint.classList.remove('hidden');
    });

    /* ------------------------------------------------------------------ */
    /*  Prosty modal potwierdzenia (używany przez wszystkie moduły)         */
    /* ------------------------------------------------------------------ */
    App.confirm = function (title, text, okLabel, danger) {
        return new Promise(function (resolve) {
            const back = App.h('div', { class: 'modal-backdrop' });
            const box = App.h('div', { class: 'modal' },
                App.h('div', { class: 'modal-title', text: title }),
                App.h('div', { class: 'modal-text', text: text || '' }),
                App.h('div', { class: 'modal-actions' },
                    App.h('button', { class: 'btn ghost', text: 'Anuluj', onclick: function () { done(false); } }),
                    App.h('button', { class: 'btn ' + (danger ? 'danger' : 'primary'), text: okLabel || 'Potwierdź', onclick: function () { done(true); } })
                )
            );
            back.appendChild(box);
            document.body.appendChild(back);
            App.escStack.push('confirm', function () { done(false); });
            requestAnimationFrame(function () { back.classList.add('in'); });
            function done(v) {
                App.escStack.remove('confirm');
                back.classList.remove('in');
                setTimeout(function () { back.remove(); }, 200);
                App.sound('click');
                resolve(v);
            }
        });
    };

    // prompt z polami: fields = [{ id, label, type, value, min, max, placeholder, options:[{value,label}] }]
    App.form = function (title, fields, okLabel) {
        return new Promise(function (resolve) {
            const back = App.h('div', { class: 'modal-backdrop' });
            const inputs = {};
            const body = App.h('div', { class: 'modal-fields' }, fields.map(function (f) {
                let input;
                if (f.type === 'select') {
                    input = App.h('select', { class: 'input' }, (f.options || []).map(function (o) {
                        return App.h('option', { value: o.value, text: o.label, selected: String(o.value) === String(f.value) });
                    }));
                } else if (f.type === 'textarea') {
                    input = App.h('textarea', { class: 'input', rows: 3, placeholder: f.placeholder || '' });
                    input.value = f.value || '';
                } else {
                    input = App.h('input', { class: 'input', type: f.type || 'text', min: f.min, max: f.max, step: f.step, placeholder: f.placeholder || '' });
                    input.value = f.value === undefined ? '' : f.value;
                }
                inputs[f.id] = input;
                return App.h('label', { class: 'field' }, App.h('span', { text: f.label }), input);
            }));
            const box = App.h('div', { class: 'modal' },
                App.h('div', { class: 'modal-title', text: title }), body,
                App.h('div', { class: 'modal-actions' },
                    App.h('button', { class: 'btn ghost', text: 'Anuluj', onclick: function () { done(null); } }),
                    App.h('button', { class: 'btn primary', text: okLabel || 'Zapisz', onclick: function () {
                        const out = {};
                        fields.forEach(function (f) {
                            const v = inputs[f.id].value;
                            out[f.id] = f.type === 'number' ? Number(v) : v;
                        });
                        done(out);
                    } })
                )
            );
            back.appendChild(box);
            document.body.appendChild(back);
            App.escStack.push('form', function () { done(null); });
            requestAnimationFrame(function () { back.classList.add('in'); const first = box.querySelector('.input'); if (first) first.focus(); });
            function done(v) {
                App.escStack.remove('form');
                back.classList.remove('in');
                setTimeout(function () { back.remove(); }, 200);
                resolve(v);
            }
        });
    };
})();
