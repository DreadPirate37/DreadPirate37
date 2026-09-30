/* ==========================================================================
   dp-pojazdy – NUI: HUD, panel sterowania, toasty, dźwięki (WebAudio)
   ========================================================================== */
(() => {
  'use strict';
  const isFiveM = typeof GetParentResourceName === 'function';
  const RES = isFiveM ? GetParentResourceName() : 'dp-pojazdy';
  const $ = id => document.getElementById(id);
  const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

  function post(name, data) {
    if (!isFiveM) return Promise.resolve();
    return fetch(`https://${RES}/${name}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(data || {}) }).catch(() => {});
  }

  /* ---------------- toasty ---------------- */
  function toast(text, kind = 'info', time = 3200) {
    const box = $('toasts');
    const el = document.createElement('div');
    el.className = `toast ${kind}`;
    el.textContent = text;
    box.appendChild(el);
    while (box.children.length > 4) box.firstChild.remove();
    setTimeout(() => { el.classList.add('out'); setTimeout(() => el.remove(), 260); }, time);
  }

  /* ---------------- dźwięki (syntezowane, zero plików) ---------------- */
  const Audio = {
    ctx: null,
    vol: 0.35,
    get() {
      if (!this.ctx) {
        const C = window.AudioContext || window.webkitAudioContext;
        if (!C) return null;
        this.ctx = new C();
        this.master = this.ctx.createGain();
        this.master.gain.value = this.vol;
        this.master.connect(this.ctx.destination);
      }
      if (this.ctx.state === 'suspended') this.ctx.resume();
      return this.ctx;
    },
    tone(freq, dur, type = 'sine', gain = 0.5, delay = 0, slide = 0) {
      const c = this.get(); if (!c) return;
      const t = c.currentTime + delay;
      const o = c.createOscillator(), g = c.createGain();
      o.type = type; o.frequency.setValueAtTime(freq, t);
      if (slide) o.frequency.exponentialRampToValueAtTime(Math.max(20, freq + slide), t + dur);
      g.gain.setValueAtTime(0.0001, t);
      g.gain.exponentialRampToValueAtTime(gain, t + 0.008);
      g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
      o.connect(g); g.connect(this.master);
      o.start(t); o.stop(t + dur + 0.02);
    },
    noise(dur, freq, q = 1, gain = 0.4, delay = 0, type = 'bandpass') {
      const c = this.get(); if (!c) return;
      const t = c.currentTime + delay;
      const len = Math.floor(c.sampleRate * dur);
      const buf = c.createBuffer(1, len, c.sampleRate);
      const d = buf.getChannelData(0);
      for (let i = 0; i < len; i++) d[i] = Math.random() * 2 - 1;
      const s = c.createBufferSource(); s.buffer = buf;
      const f = c.createBiquadFilter(); f.type = type; f.frequency.value = freq; f.Q.value = q;
      const g = c.createGain();
      g.gain.setValueAtTime(gain, t);
      g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
      s.connect(f); f.connect(g); g.connect(this.master);
      s.start(t);
    },
    play(name) {
      switch (name) {
        case 'tick': this.noise(0.025, 3200, 4, 0.5); break;
        case 'tock': this.noise(0.025, 2300, 4, 0.45); break;
        case 'on': this.tone(880, 0.08, 'square', 0.18); this.tone(1320, 0.1, 'square', 0.18, 0.08); break;
        case 'off': this.tone(1100, 0.08, 'square', 0.16); this.tone(700, 0.12, 'square', 0.16, 0.08); break;
        case 'mode': this.tone(660, 0.07, 'triangle', 0.3); this.tone(990, 0.12, 'triangle', 0.3, 0.07); break;
        case 'drive': this.noise(0.09, 400, 2, 0.6); this.tone(90, 0.18, 'sine', 0.5, 0.02, -40); break;
        case 'lock': this.noise(0.05, 900, 3, 0.5); this.noise(0.08, 300, 2, 0.6, 0.06); this.tone(70, 0.2, 'sine', 0.55, 0.06, -20); break;
        case 'air': this.noise(0.9, 2400, 0.6, 0.25, 0, 'highpass'); break;
        case 'launch': [0, 0.12, 0.24].forEach(d => this.tone(1500, 0.07, 'square', 0.15, d)); break;
        case 'belt_on': this.noise(0.03, 2600, 6, 0.6); this.noise(0.04, 1400, 5, 0.5, 0.05); break;
        case 'belt_off': this.noise(0.04, 1600, 5, 0.5); this.noise(0.12, 800, 1, 0.25, 0.04); break;
        case 'chime': this.tone(784, 0.6, 'sine', 0.22); this.tone(659, 0.8, 'sine', 0.2, 0.35); break;
      }
    },
  };

  let blinkTimer = null, blinkPhase = false;
  function blinker(on) {
    clearInterval(blinkTimer); blinkTimer = null;
    if (!on) return;
    blinkTimer = setInterval(() => { Audio.play(blinkPhase ? 'tock' : 'tick'); blinkPhase = !blinkPhase; }, 370);
  }

  let chimeTimer = null;
  function chime(on) {
    clearInterval(chimeTimer); chimeTimer = null;
    if (!on) return;
    Audio.play('chime');
    chimeTimer = setInterval(() => Audio.play('chime'), 1600);
  }

  /* ---------------- HUD ---------------- */
  const beltSvg = c => `<svg class="belt-ico" viewBox="0 0 24 24" fill="none" stroke="${c}" stroke-width="2.4" stroke-linecap="round"><circle cx="12" cy="4" r="2.4"/><path d="M8 22V11a4 4 0 0 1 8 0v11"/><path d="M8.5 9.5 16 20"/></svg>`;

  function renderHud(d) {
    const hud = $('hud');
    if (!d || !d.show) { hud.classList.add('hidden'); hud.innerHTML = ''; return; }
    const out = [];
    if (d.driver && d.mode) {
      out.push(`<div class="chip mode" style="--c:${esc(d.mode.color)}">${esc(d.mode.label)}</div>`);
      if (d.drive) out.push(`<div class="chip ${d.switching ? 'on flash' : ''}">${esc(d.drive)}</div>`);
      if (d.low) out.push(`<div class="chip on">4L</div>`);
      if (d.diff) out.push(`<div class="chip on"><small>DIFF</small>${esc(d.diff)}</div>`);
      if (d.susp) out.push(`<div class="chip on"><small>AIR</small>${esc(d.susp)}</div>`);
      if (d.tc) {
        const cls = d.tc.active ? 'on flash' : d.tc.off ? 'warn' : 'off';
        out.push(`<div class="chip ${cls}">${esc(d.tc.label)}</div>`);
      }
      if (d.launch) {
        const txt = d.launch === 'go' ? 'LAUNCH ▶' : d.launch === 'ready' ? 'LAUNCH ●' : 'LAUNCH';
        out.push(`<div class="chip on ${d.launch === 'ready' ? 'flash' : d.launch === 'armed' ? 'pulse' : ''}">${txt}</div>`);
      }
      if (d.cruise) out.push(`<div class="chip good"><small>CRUISE</small>${d.cruise} ${esc(d.unit)}</div>`);
      if (d.limiter) out.push(`<div class="chip on"><small>LIM</small>${d.limiter} ${esc(d.unit)}</div>`);
    }
    if (d.beltEnabled) {
      out.push(`<div class="chip ${d.belt ? 'good' : 'warn'}" title="Pasy">${beltSvg(d.belt ? '#3ddc84' : '#ff5c5c')}</div>`);
    }
    hud.innerHTML = out.join('');
    hud.classList.toggle('hidden', out.length === 0);
  }

  /* ---------------- panel ---------------- */
  let P = null; // ostatnie dane panelu

  const act = (type, value) => post('action', { type, value });

  function seg(items, isActive, onClickAttr, disabled = false) {
    return `<div class="seg">${items.map(it =>
      `<button ${disabled ? 'disabled' : ''} class="${isActive(it) ? 'act' : ''}" ${it.color ? `style="--c:${esc(it.color)}"` : ''} data-a="${onClickAttr}" data-v='${esc(JSON.stringify(it.value !== undefined ? it.value : it.id))}'>${esc(it.label)}</button>`
    ).join('')}</div>`;
  }

  function renderPanel(d) {
    P = d;
    $('p-name').textContent = d.name;
    $('p-plate').textContent = (d.plate || '').trim();
    $('t-unit').textContent = d.unit;
    const s = d.state, out = [];
    const mode = d.modes.find(m => m.id === s.mode);

    out.push(`<div class="sec"><h3>Tryb jazdy <span>${esc(mode ? mode.label : '')}</span></h3>${seg(d.modes, m => m.id === s.mode, 'mode')}</div>`);

    if (d.drives.length >= 2) {
      out.push(`<div class="sec"><h3>Napęd <span>${esc(d.drive)}</span></h3>${seg(d.drives.map(x => ({ id: x, label: x })), x => x.id === d.drive, 'drive', d.driveLocked)}
        ${d.driveLocked ? '<div class="note warn">Napęd wymuszony przez tryb, reduktor lub blokadę centralną.</div>' : '<div class="note">Przełączanie tylko przy niskiej prędkości.</div>'}</div>`);
    } else if (d.drive) {
      out.push(`<div class="sec"><h3>Napęd <span>${esc(d.drive)}</span></h3><div class="note">Napęd fabryczny – to auto nie ma przełączania.</div></div>`);
    }

    if (d.diffMax > 0) {
      const lv = [{ id: 0, label: 'Otwarte' }];
      for (let i = 1; i <= d.diffMax; i++) lv.push({ id: i, label: d.diffLabels[i - 1] });
      out.push(`<div class="sec"><h3>Blokady dyferencjałów</h3>${seg(lv, x => x.id === s.diff, 'diff')}
        <div class="note">Rozłączają się same przy większej prędkości. Zablokowany dyferencjał wyłącza TC.</div></div>`);
    }

    if (d.lowRange) {
      out.push(`<div class="sec"><h3>Reduktor</h3>${seg([{ id: false, value: false, label: '4H – szosa' }, { id: true, value: true, label: '4L – teren' }], x => x.id === s.low, 'low')}</div>`);
    }

    if (d.tcLevels) {
      out.push(`<div class="sec"><h3>Kontrola trakcji</h3>${seg(d.tcLevels, x => x.id === d.tcEff, 'tc', d.tcLocked)}
        ${d.tcLocked ? '<div class="note warn">Wyłączona – zablokowane dyferencjały.</div>' : ''}</div>`);
    }

    if (d.susp) {
      out.push(`<div class="sec"><h3>Zawieszenie pneumatyczne</h3>${seg(d.susp, x => x.id === s.susp, 'susp')}</div>`);
    }

    const f = d.features;
    const assist = [];
    if (d.launch) assist.push(`<button class="btn ${d.launchState ? 'act' : ''} ${d.launchState === 'armed' ? 'armed' : ''}" data-a="launch">Launch</button>`);
    if (f.cruise) assist.push(`<button class="btn ${d.cruise ? 'act' : ''}" data-a="cruise">Tempomat</button>`);
    if (f.limiter) assist.push(`<button class="btn ${d.limiter ? 'act' : ''}" data-a="limiter">Ogranicznik</button>`);
    if (assist.length) {
      const v = d.cruise || d.limiter;
      out.push(`<div class="sec"><h3>Asystenci</h3><div class="row">${assist.join('')}</div>
        ${v ? `<div class="row"><button class="btn" data-a="speed" data-v="-1">−</button><div class="val">${v} ${esc(d.unit)}</div><button class="btn" data-a="speed" data-v="1">+</button></div>` : ''}</div>`);
    }

    const misc = [];
    if (f.indicators) {
      misc.push(`<button class="btn ${d.ind === 1 ? 'act' : ''}" data-a="ind" data-v="1">◀</button>`);
      misc.push(`<button class="btn ${d.ind === 3 ? 'act' : ''}" data-a="ind" data-v="3">⚠</button>`);
      misc.push(`<button class="btn ${d.ind === 2 ? 'act' : ''}" data-a="ind" data-v="2">▶</button>`);
    }
    if (f.belt) misc.push(`<button class="btn ${d.belt ? 'act' : ''}" data-a="belt">Pasy</button>`);
    if (f.engine) misc.push(`<button class="btn ${d.engine ? 'act' : ''}" data-a="engine">Silnik</button>`);
    if (misc.length) out.push(`<div class="sec"><h3>Pojazd</h3><div class="row">${misc.join('')}</div></div>`);

    $('p-sections').innerHTML = out.join('');
    $('panel').classList.remove('hidden');
  }

  $('p-sections').addEventListener('click', e => {
    const b = e.target.closest('button[data-a]');
    if (!b || b.disabled) return;
    let v = b.dataset.v;
    if (v !== undefined) { try { v = JSON.parse(v); } catch (_) { /* zostaje tekst */ } }
    act(b.dataset.a, v);
    if (!isFiveM) demoAction(b.dataset.a, v);
  });

  function closePanel(notify) {
    $('panel').classList.add('hidden');
    P = null;
    if (notify) post('close');
  }
  $('p-close').addEventListener('click', () => closePanel(true));
  window.addEventListener('keydown', e => {
    if (e.code === 'Escape' && !$('panel').classList.contains('hidden')) closePanel(true);
  });

  /* ---------------- telemetria ---------------- */
  let wheelCount = 0;
  function buildWheels(n) {
    const car = $('t-car');
    car.querySelectorAll('.wheel').forEach(w => w.remove());
    const rows = Math.ceil(n / 2);
    for (let i = 0; i < n; i++) {
      const row = Math.floor(i / 2);
      const el = document.createElement('div');
      el.className = 'wheel';
      el.style.left = (i % 2 === 0 ? 22 : 88) + 'px';
      el.style.top = (rows <= 1 ? 65 : 30 + row * (70 / (rows - 1))) + 'px';
      car.appendChild(el);
    }
    wheelCount = n;
  }

  function telemetry(t) {
    $('t-speed').textContent = t.speed;
    $('t-gear').textContent = t.gear === 0 ? 'R' : t.speed === 0 && t.throttle === 0 ? 'N' : t.gear;
    $('t-rpm').style.width = Math.round(Math.min(1, t.rpm) * 100) + '%';
    const pw = document.querySelector('.bar.pwr');
    $('t-pwr').style.width = Math.round(Math.min(1, t.power) * 100) + '%';
    pw.classList.toggle('cut', !!t.tc || t.power < 0.97);
    $('t-tc').textContent = t.power === 0 ? 'SPRZĘGŁO' : t.tc ? 'TC ●' : t.power > 1.01 ? 'BOOST' : 'MOC';
    if (t.wheels.length !== wheelCount) buildWheels(t.wheels.length);
    const els = $('t-car').querySelectorAll('.wheel');
    t.wheels.forEach((w, i) => {
      const el = els[i]; if (!el) return;
      el.classList.toggle('pw', !!w.p);
      el.classList.toggle('slip', !!w.p && w.s > 15);
    });
  }

  /* ---------------- wiadomości z Lua ---------------- */
  window.addEventListener('message', ({ data: d }) => {
    if (!d || !d.action) return;
    switch (d.action) {
      case 'toast': toast(d.text, d.kind); break;
      case 'sound': Audio.play(d.name); break;
      case 'blinker': blinker(d.on); break;
      case 'chime': chime(d.on); break;
      case 'hud': renderHud(d.data); break;
      case 'panel': d.open ? renderPanel(d.data) : closePanel(false); break;
      case 'telemetry': if (P) telemetry(d); break;
    }
  });

  /* ---------------- tryb demo (otwarcie index.html w przeglądarce) ---------------- */
  if (isFiveM) return;
  document.body.classList.add('demo');
  const demo = {
    name: 'Sandking XL', plate: ' DP 4X4 ', unit: 'km/h',
    modes: [{ id: 'eco', label: 'ECO', color: '#3ddc84' }, { id: 'comfort', label: 'KOMFORT', color: '#4ecdc4' }, { id: 'sport', label: 'SPORT', color: '#ffb020' }],
    drives: ['RWD', 'AWD'], drive: 'RWD', driveLocked: false, diffMax: 3, diffLabels: ['TYŁ', 'TYŁ + CENTR.', 'WSZYSTKIE'],
    lowRange: true, susp: [{ id: 'low', label: 'NISKO' }, { id: 'normal', label: 'NORMAL' }, { id: 'high', label: 'WYSOKO' }, { id: 'offroad', label: 'TEREN' }],
    tcLevels: [{ id: 'on', label: 'TC' }, { id: 'sport', label: 'TC SPORT' }, { id: 'off', label: 'TC OFF' }],
    launch: true, features: { cruise: true, limiter: true, belt: true, indicators: true, engine: true },
    state: { mode: 'comfort', drive: 'RWD', diff: 0, low: false, tc: 'on', susp: 'normal' },
    tcEff: 'on', tcLocked: false, launchState: null, cruise: null, limiter: null, belt: false, engine: true, ind: 0,
  };
  function demoHud() {
    const s = demo.state, m = demo.modes.find(x => x.id === s.mode);
    renderHud({ show: true, driver: true, unit: 'km/h', beltEnabled: true, belt: demo.belt, mode: m, drive: demo.drive, low: s.low,
      diff: s.diff ? demo.diffLabels[s.diff - 1] : null, susp: s.susp !== 'normal' ? demo.susp.find(x => x.id === s.susp).label : null,
      tc: { label: demo.tcLevels.find(x => x.id === demo.tcEff).label, off: demo.tcEff === 'off', active: false }, launch: demo.launchState,
      cruise: demo.cruise, limiter: demo.limiter });
  }
  function demoAction(a, v) {
    const s = demo.state;
    if (a === 'mode') s.mode = v;
    if (a === 'drive') { s.drive = v; demo.drive = v; Audio.play('drive'); }
    if (a === 'diff') { s.diff = v; Audio.play(v ? 'lock' : 'off'); }
    if (a === 'low') { s.low = v; Audio.play('lock'); }
    if (a === 'tc') s.tc = v;
    if (a === 'susp') { s.susp = v; Audio.play('air'); }
    if (a === 'belt') { demo.belt = !demo.belt; Audio.play(demo.belt ? 'belt_on' : 'belt_off'); }
    if (a === 'launch') demo.launchState = demo.launchState ? null : 'armed';
    if (a === 'cruise') { demo.cruise = demo.cruise ? null : 90; demo.limiter = null; }
    if (a === 'limiter') { demo.limiter = demo.limiter ? null : 50; demo.cruise = null; }
    if (a === 'speed') { if (demo.cruise) demo.cruise += v * 5; if (demo.limiter) demo.limiter += v * 5; }
    if (a === 'ind') { demo.ind = demo.ind === v ? 0 : v; blinker(demo.ind !== 0); }
    if (a === 'engine') demo.engine = !demo.engine;
    demo.driveLocked = s.low || s.diff >= 2;
    if (demo.driveLocked) demo.drive = 'AWD'; else demo.drive = s.drive;
    demo.tcLocked = s.diff > 0;
    demo.tcEff = demo.tcLocked ? 'off' : s.tc;
    renderPanel(demo); demoHud();
  }
  renderPanel(demo); demoHud();
  toast('Tryb demo – kliknij przyciski w panelu', 'info', 5000);
  let tt = 0;
  setInterval(() => {
    tt += 0.1;
    const spd = Math.round(40 + Math.sin(tt / 2) * 30);
    const slip = Math.sin(tt * 1.7) > 0.8;
    const wheels = [0, 1, 2, 3].map(i => ({ p: demo.drive === 'AWD' || (demo.drive === 'RWD' ? i >= 2 : i < 2), s: slip && i >= 2 ? 30 : 2 }));
    telemetry({ speed: spd, rpm: 0.35 + (tt % 3) / 5, gear: 1 + Math.floor((tt % 12) / 3), throttle: 1, power: slip && demo.tcEff !== 'off' ? 0.55 : 1, tc: slip && demo.tcEff !== 'off', wheels });
  }, 100);
})();
