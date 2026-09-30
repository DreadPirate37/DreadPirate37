'use strict';
/* ==========================================================================
   Demontaż części – nakładka na widok z gry (styl Car Mechanic Simulator)
   Śruby, klipsy, wtyczki, węże itd. są rzutowane z 3D na ekran przez Lua.
   Każdy typ ma własną mechanikę; wszystko wpływa na stan zdjętej części.
   ========================================================================== */
(() => {
  const TOOLS = [
    { key: 'ratchet', label: 'Grzechotka', hot: 'Digit1', k: '1' },
    { key: 'impact', label: 'Udarowy', hot: 'Digit2', k: '2' },
    { key: 'screw', label: 'Wkrętak', hot: 'Digit3', k: '3' },
    { key: 'trim', label: 'Łyżka', hot: 'Digit4', k: '4' },
    { key: 'pliers', label: 'Szczypce', hot: 'Digit5', k: '5' },
    { key: 'hand', label: 'Ręka', hot: 'Digit6', k: '6' },
    { key: 'grinder', label: 'Szlifierka', hot: 'Digit7', k: '7' },
    { key: 'wire', label: 'Struna', hot: 'Digit8', k: '8' },
    { key: 'spray', label: 'Penetrant', hot: 'Digit9', k: '9' },
    { key: 'drill', label: 'Wiertarka', hot: 'Digit0', k: '0' },
    { key: 'stamps', label: 'Puncerzy', hot: 'KeyT', k: 'T' },
  ];
  const TYPE = {
    bolt: 'Śruba', nut: 'Nakrętka', terminal: 'Klema', drain: 'Korek spustowy', screw: 'Wkręt', clip: 'Klips',
    hanger: 'Wieszak gumowy', connector: 'Wtyczka', hose: 'Wąż z opaską', cut: 'Linia cięcia', stamp: 'Znak VIN', hoist: 'Żuraw',
  };
  const TYPE_PL = { bolt: 'Śruby', nut: 'Nakrętki', terminal: 'Klemy', drain: 'Korki', screw: 'Wkręty', clip: 'Klipsy', hanger: 'Wieszaki', connector: 'Wtyczki', hose: 'Węże', cut: 'Cięcia', stamp: 'Znaki VIN', hoist: 'Żuraw' };
  const TOOL_FOR = {
    bolt: 'Grzechotka (1) / udarowy (2)', nut: 'Grzechotka (1) / udarowy (2)', terminal: 'Grzechotka (1)', drain: 'Grzechotka (1) + miska (B)',
    screw: 'Wkrętak (3)', clip: 'Łyżka (4)', hanger: 'Łyżka (4)', connector: 'Ręka (6)', hose: 'Szczypce (5)', stamp: 'Puncerzy (T)', hoist: 'Kliknij – żuraw',
  };
  const FLUID_FLAG = { coolant: '@coolant', fuel: '@fuel', oil: '@oil', gearOil: '@gearOil' };
  const FLUID = { coolant: 'płyn chłodniczy', fuel: 'paliwo', oil: 'olej', gearOil: 'olej przekładniowy', brake: 'płyn hamulcowy' };
  const FLUID_COL = { coolant: '#43d18b', fuel: '#e8d36a', oil: '#6b4a1f', gearOil: '#8a5a22', brake: '#d9c7a0' };
  const $ = W.$;
  const fmtSock = s => (typeof s === 'number' ? s + ' mm' : s);

  const P = (W.Part = {
    active: false,

    open(part, ctx, F) {
      this.part = part;
      this.ctx = ctx || {};
      this.fx = Object.assign({ speed: 1, steady: 1, quiet: 1, eye: false, tech: false }, this.ctx.fx || {});
      this.flags = Object.assign({}, part.flags || {});
      this.cons = Object.assign({ penetrant: 0, disc: 0, extractor: 0 }, this.ctx.cons || {});
      this.used = { penetrant: 0, disc: 0, extractor: 0 };
      this.rep = { broken: 0, stripped: 0, snapped: 0, cut: 0, gouge: 0, spills: 0, sparks: 0, bumps: 0, sensitive: 0, airbag: false, fire: false, noise: 0 };
      this.owned = Object.assign({ hand: true, spray: true }, this.ctx.tools || {});
      this.sockets = this.ctx.sockets || [8, 10, 13, 15, 17, 18, 19, 21, 'T50'];
      this.bits = this.ctx.bits || ['PH1', 'PH2', 'T20', 'T30'];
      this.sockIdx = Math.max(0, this.sockets.indexOf(10));
      this.bitIdx = Math.max(0, this.bits.indexOf('PH2'));
      this.fs = F.map((d, k) => {
        const s = (part.F && part.F[k]) || {};
        return Object.assign({}, d, {
          i: k + 1, rust: s.rust || 0, ch: s.ch, state: s.done ? 'done' : 'on', gone: !!s.done,
          prog: 0, torque: 0, stress: 0, crack: 0, wear: 0, soak: 0, soaked: false, latch: 0, squeeze: 0, drillP: 0,
          cutProg: 0, known: !!this.fx.eye, pts: [], samples: null, pop: 0, vis: false, x: -99, y: -99,
        });
      });
      this.scratches = [];
      this.particles = new W.Particles();
      this.tool = this.fs.some(f => f.t === 'stamp') ? 'stamps' : this.fs.some(f => f.t === 'cut' && f.tool === 'wire') ? 'wire' : this.fs.some(f => f.t === 'cut') ? 'grinder' : 'ratchet';
      if (!this.owned[this.tool]) this.tool = 'hand';
      this.scale = 1.2;
      this.hover = null;
      this.target = null;
      this.hoist = null;
      this.removeHold = 0;
      this.discMounted = false;
      this.discWear = 0;
      this.finishing = false;
      this.confirmOpen = false;
      this.msg = null;
      this.once = new Set();
      this.sparkPost = 0;
      this.sparkOn = false;
      this.flash = 0;
      this.t0 = performance.now();
      this.cv = $('pcv');
      $('part').classList.remove('hidden');
      $('p-confirm').classList.add('hidden');
      this.buildTools();
      this.renderCard();
      this.active = true;
      this.last = performance.now();
      cancelAnimationFrame(this.raf);
      this.raf = requestAnimationFrame(t => this.loop(t));
    },

    points(pts, scale) {
      if (!this.active || !Array.isArray(pts)) return;
      const w = window.innerWidth, h = window.innerHeight;
      this.scale = scale || this.scale;
      pts.forEach((arr, k) => {
        const f = this.fs[k];
        if (!f || !Array.isArray(arr)) return;
        f.pts = arr.map(p => ({ x: p[0] * w, y: p[1] * h, v: p[2] === 1 }));
        f.x = f.pts[0].x;
        f.y = f.pts[0].y;
        f.vis = f.pts.some(p => p.v);
        if (f.t === 'cut') this.buildCut(f);
      });
      let sx = 0, sy = 0, n = 0;
      for (const f of this.fs) {
        if (f.vis && f.t !== 'cut') { sx += f.x; sy += f.y; n++; }
      }
      if (n) { this.cx = sx / n; this.cy = sy / n; }
      else { this.cx = w / 2; this.cy = h / 2; }
    },

    close() {
      this.active = false;
      cancelAnimationFrame(this.raf);
      W.Audio.stopAll();
      $('part').classList.add('hidden');
      $('p-tip').classList.add('hidden');
    },

    /* ------------------------------------------------------------------ */
    get R() { return W.clamp(this.scale * window.innerHeight * 0.016, 9, 26); },

    hidden(f) { return f.after && f.after.some(j => this.fs[j - 1] && this.fs[j - 1].state !== 'done'); },

    allDone() { return this.fs.every(f => f.state === 'done'); },

    dirOf(f) {
      let dx = f.x - (this.cx ?? f.x), dy = f.y - (this.cy ?? f.y);
      const l = Math.hypot(dx, dy);
      if (l < 8) return { x: 0, y: -1 };
      return { x: dx / l, y: dy / l };
    },

    buildCut(f) {
      const pts = f.pts.slice();
      if (f.closed && pts.length > 2) pts.push(pts[0]);
      const seg = [];
      let total = 0;
      for (let i = 0; i < pts.length - 1; i++) {
        const l = Math.hypot(pts[i + 1].x - pts[i].x, pts[i + 1].y - pts[i].y);
        seg.push(l);
        total += l;
      }
      if (!f.samples) {
        const n = W.clamp(Math.round(total / 7), 16, 160);
        const hp = f.tool === 'wire' ? 0.14 : 0.09;
        f.samples = Array.from({ length: n }, (_, j) => ({ t: (j + 0.5) / n, hp, hp0: hp, cut: false, x: 0, y: 0 }));
      }
      for (const s of f.samples) {
        let want = s.t * total, i = 0;
        while (i < seg.length - 1 && want > seg[i]) { want -= seg[i]; i++; }
        const k = seg[i] ? W.clamp(want / seg[i], 0, 1) : 0;
        s.x = W.lerp(pts[i].x, pts[i + 1] ? pts[i + 1].x : pts[i].x, k);
        s.y = W.lerp(pts[i].y, pts[i + 1] ? pts[i + 1].y : pts[i].y, k);
      }
    },

    findHover() {
      const I = W.Input;
      let best = null, bd = 1e9;
      const R = this.R;
      for (const f of this.fs) {
        if (f.state === 'done' || !f.vis || this.hidden(f)) continue;
        if (f.t === 'cut') {
          for (const s of f.samples || []) {
            if (s.cut) continue;
            const d = W.dist(I.x, I.y, s.x, s.y);
            if (d < 18 && d < bd) { bd = d; best = f; }
          }
          continue;
        }
        const d = W.dist(I.x, I.y, f.x, f.y);
        const r = R * (f.t === 'hoist' ? 2.4 : f.t === 'hose' || f.t === 'connector' ? 1.6 : 1.35);
        if (d < r && d < bd) { bd = d; best = f; }
      }
      return best;
    },

    /* ---------------- komunikaty ---------------- */
    say(text, kind = 'info', ms = 2400) {
      this.msg = { text, kind, until: performance.now() + ms };
    },
    onceSay(key, text, kind = 'warn') {
      if (this.once.has(key)) return;
      this.once.add(key);
      this.say(text, kind);
    },
    pressSay(text, kind = 'warn') {
      if (this.pressHinted) return;
      this.pressHinted = true;
      this.say(text, kind);
      W.Audio.click();
    },

    noise(v) { this.rep.noise += v; },

    fxPost(kind, extra = {}) { W.post('part', Object.assign({ action: 'fx', kind }, extra)); },

    selectTool(key) {
      if (!this.owned[key]) {
        const t = TOOLS.find(x => x.key === key);
        this.say(`Nie masz: ${t ? t.label : key} – kupisz w ChopNecie`, 'warn');
        W.Audio.bad();
        return;
      }
      if (key === 'spray' && this.cons.penetrant - this.used.penetrant <= 0) this.say('Puszka penetrantu jest pusta', 'warn');
      this.tool = key;
      W.Audio.click();
      this.buildTools();
    },

    /* ---------------- pętla ---------------- */
    loop(ts) {
      if (!this.active) return;
      const dt = Math.min(0.05, (ts - this.last) / 1000);
      this.last = ts;
      const I = W.Input;
      I.tick(dt);
      if (!this.confirmOpen && !this.finishing) {
        if (this.hoist) this.updateHoist(dt);
        else this.updateMain(dt);
      }
      this.passive(dt);
      this.particles.update(dt);
      this.render(dt);
      this.renderHud();
      I.endFrame();
      this.raf = requestAnimationFrame(t => this.loop(t));
    },

    updateMain(dt) {
      const I = W.Input;
      for (const t of TOOLS) if (I.hit(t.hot)) this.selectTool(t.key);
      if (I.wheel) {
        if (this.tool === 'ratchet' || this.tool === 'impact') {
          this.sockIdx = (this.sockIdx + (I.wheel > 0 ? 1 : -1) + this.sockets.length) % this.sockets.length;
          W.Audio.click();
          this.buildTools();
        } else if (this.tool === 'screw') {
          this.bitIdx = (this.bitIdx + (I.wheel > 0 ? 1 : -1) + this.bits.length) % this.bits.length;
          W.Audio.click();
          this.buildTools();
        }
      }
      if (I.hit('KeyQ') || I.hit('KeyE')) {
        const d = I.hit('KeyE') ? 1 : -1;
        if (this.tool === 'screw') this.bitIdx = (this.bitIdx + d + this.bits.length) % this.bits.length;
        else this.sockIdx = (this.sockIdx + d + this.sockets.length) % this.sockets.length;
        W.Audio.click();
        this.buildTools();
      }
      if (I.hit('Escape')) return this.askAbort();

      const hover = I.down && this.target ? this.target : this.findHover();
      this.hover = hover;

      // pomiar (PPM)
      if (I.rclicked && hover && !hover.known) this.measure = { f: hover, t: 0 };
      if (this.measure) {
        if (!I.rdown || this.hover !== this.measure.f) this.measure = null;
        else {
          this.measure.t += dt;
          if (this.measure.t > 0.45) {
            this.measure.f.known = true;
            W.Audio.click();
            this.measure = null;
          }
        }
      }

      // miska pod korek
      if (I.hit('KeyB') && hover && hover.t === 'drain') {
        if (!this.owned.basin) this.say('Nie masz miski na płyny', 'warn');
        else if (hover.draining != null) this.say('Już cieknie…', 'info');
        else {
          hover.basin = !hover.basin;
          W.Audio.thud();
          this.say(hover.basin ? 'Miska podstawiona' : 'Miska zabrana', 'info', 1400);
        }
      }

      if (I.clicked) {
        this.target = hover;
        this.pressX = I.x;
        this.pressY = I.y;
        this.pressHinted = false;
        if (hover) this.onPress(hover);
      }
      this.busyFrame = false;
      if (I.down) {
        if (this.target && this.target.state !== 'done') this.act(this.target, dt);
        else if (!this.target && this.tool === 'grinder' && this.owned.grinder) this.gouge(dt);
      }
      if (!this.busyFrame) this.stopLoops();
      if (I.released) {
        if (this.target) this.onRelease(this.target);
        this.target = null;
      }

      // zdjęcie części
      if (this.allDone() && I.key('Space')) {
        this.removeHold += dt;
        if (this.removeHold >= 0.9) this.finish();
      } else this.removeHold = Math.max(0, this.removeHold - dt * 2);
    },

    stopLoops() {
      if (!this.loopsOn && !this.sparkOn) return;
      this.loopsOn = false;
      W.Audio.impact(false);
      W.Audio.grinder(false);
      W.Audio.wire(false);
      W.Audio.drill(false);
      if (this.sparkOn) {
        this.sparkOn = false;
        this.fxPost('sparks', { on: false });
      }
    },

    passive(dt) {
      const I = W.Input;
      let draining = false;
      for (const f of this.fs) {
        const acting = I.down && this.target === f;
        if (!acting) {
          f.torque = Math.max(0, f.torque - dt * 1.6);
          f.stress = Math.max(0, f.stress - dt * 0.2);
          if (f.t === 'stamp' && f.ring != null) f.ring = null;
        }
        if (f.soak > 0) {
          f.soak -= dt;
          if (Math.random() < dt * 6) this.particles.add({ x: f.x + (Math.random() - 0.5) * 6, y: f.y + 4, vx: 0, vy: 30, g: 200, life: 0.6, max: 0.6, r: 1.6, c: '#c9a94a' });
          if (f.soak <= 0) {
            f.soaked = true;
            this.say('Penetrant wsiąkł – śruba powinna łatwiej puścić', 'good', 1800);
          }
        }
        if (f.draining != null) {
          draining = true;
          f.draining += dt / f.drainTime;
          if (Math.random() < dt * 30) this.particles.add({ x: f.x + (Math.random() - 0.5) * 4, y: f.y + this.R * 0.6, vx: (Math.random() - 0.5) * 10, vy: 60, g: 1400, life: 0.5, max: 0.5, r: 2.2, c: FLUID_COL[f.fluid] || '#777' });
          if (f.draining >= 1) {
            f.draining = null;
            f.state = 'done';
            f.pop = 1;
            if (f.sets) this.flags[f.sets] = true;
            this.say(`Spuszczono: ${FLUID[f.fluid] || 'płyn'}`, 'good');
            W.Audio.good();
          }
        }
        if (f.pop > 0) f.pop = Math.max(0, f.pop - dt * 2.5);
      }
      W.Audio.pour(draining);
      if (this.flash > 0) this.flash = Math.max(0, this.flash - dt * 1.5);
    },

    /* ---------------- akcje ---------------- */
    onPress(f) {
      if (f.t === 'hoist') {
        if (!this.owned.hoist) return this.say('Bez żurawia warsztatowego tego nie podniesiesz', 'bad');
        this.hoist = { f, prog: 0, swing: 0.35, t: 0, hits: 0 };
        this.say('Pompuj żurawiem: SPACJA / LPM, gdy wskazówka jest w zielonym polu', 'info', 3500);
        return;
      }
      if (f.t === 'stamp' && this.tool === 'stamps') {
        f.ring = 1;
        return;
      }
      if (this.tool === 'spray') this.actSpray(f);
    },

    onRelease(f) {
      if ((f.t === 'clip' || f.t === 'hanger') && f.state !== 'done') f.drag = 0;
      if (f.t === 'connector' && f.state !== 'done' && f.latch < 1) f.latch = 0;
      if (f.t === 'hose' && f.state !== 'done' && f.squeeze < 1) f.squeeze = 0;
      if (f.t === 'stamp' && f.ring != null && f.state !== 'done') {
        const q = W.clamp(1 - Math.abs(f.ring - 0.3) / 0.3, 0, 1);
        f.q = Math.round(q * 100) / 100;
        f.ring = null;
        W.Audio.hammer();
        this.noise(0.03);
        this.say(q > 0.8 ? 'Równo wybity!' : q > 0.45 ? 'Lekko krzywo…' : 'Krzywy znak – to będzie widać', q > 0.8 ? 'good' : q > 0.45 ? 'warn' : 'bad', 1400);
        this.complete(f);
      }
    },

    act(f, dt) {
      switch (f.t) {
        case 'bolt': case 'nut': case 'terminal': case 'drain': return this.actBolt(f, dt);
        case 'screw': return this.actScrew(f, dt);
        case 'clip': case 'hanger': return this.actClip(f, dt);
        case 'connector': return this.actConnector(f, dt);
        case 'hose': return this.actHose(f, dt);
        case 'cut': return this.actCut(f, dt);
        case 'stamp': return this.actStamp(f, dt);
      }
    },

    actSpray(f) {
      if (!['bolt', 'nut'].includes(f.t)) return this.say('Penetrant daje się na zapieczone śruby', 'info');
      if (f.rust <= 0 || f.crack >= 1) return this.say('Ta śruba nie jest zapieczona', 'info');
      if (f.soaked || f.soak > 0) return this.say('Już spryskana', 'info');
      if (this.cons.penetrant - this.used.penetrant <= 0) return this.say('Brak penetrantu!', 'bad');
      this.used.penetrant++;
      f.soak = 2.5;
      W.Audio.spray();
      for (let k = 0; k < 18; k++) this.particles.add({ x: f.x, y: f.y, vx: (Math.random() - 0.5) * 160, vy: (Math.random() - 0.7) * 120, g: 80, life: 0.5, max: 0.5, r: 2, c: 'rgba(230,220,160,0.8)' });
    },

    mountDisc() {
      if (this.discMounted) return true;
      if (this.cons.disc - this.used.disc <= 0) return false;
      this.used.disc++;
      this.discMounted = true;
      this.discWear = 0;
      return true;
    },

    grind(dt, f, t, x, y) {
      this.busyFrame = this.loopsOn = true;
      W.Audio.grinder(true);
      this.noise(dt * 0.25);
      this.discWear += dt * 0.13;
      if (this.discWear >= 1) {
        this.discMounted = false;
        this.say('Tarcza zużyta – zakładasz nową', 'info', 1500);
      }
      for (let k = 0; k < 3; k++) {
        const a = -Math.PI / 2 + (Math.random() - 0.5) * 1.6;
        const v = 250 + Math.random() * 450;
        this.particles.add({ kind: 'spark', x, y, vx: Math.cos(a) * v * (Math.random() < 0.5 ? -1 : 1), vy: Math.sin(a) * v * 0.5 + 80, g: 1200, life: 0.35, max: 0.35 });
      }
      const now = performance.now();
      if (f && now - this.sparkPost > 160) {
        this.sparkPost = now;
        this.sparkOn = true;
        this.fxPost('sparks', { on: true, i: f.i, t });
      }
      if (f && f.fire && !this.flags['@fuel'] && !this.rep.fire && Math.random() < dt * 0.035) {
        this.rep.fire = true;
        this.fxPost('fire', { i: f.i, t });
        W.Audio.boom();
        this.flash = 0.6;
        this.say('Iskry zapaliły opary paliwa! Trzeba było spuścić paliwo.', 'bad', 4000);
      }
    },

    gouge(dt) {
      if (!this.mountDisc()) return this.onceSay('nodisc', 'Brak tarcz do szlifierki!', 'bad');
      const I = W.Input;
      this.rep.gouge += dt;
      this.grind(dt, null, 0, I.x, I.y);
      if (this.scratches.length < 400) this.scratches.push({ x: I.x + (Math.random() - 0.5) * 4, y: I.y + (Math.random() - 0.5) * 4 });
      this.onceSay('gouge', 'Tniesz obok – niszczysz część (stan spada)!', 'bad');
    },

    actDrill(f, dt) {
      if (!this.owned.drill) return this.pressSay('Nie masz wiertarki (ChopNet → sklep)');
      if (!f.extracting) {
        if (this.cons.extractor - this.used.extractor <= 0) return this.pressSay('Brak wykrętaków!', 'bad');
        f.extracting = true;
        this.used.extractor++;
      }
      f.drillP += dt / 2.4;
      this.busyFrame = this.loopsOn = true;
      W.Audio.drill(true);
      this.noise(dt * 0.04);
      if (Math.random() < dt * 20) this.particles.add({ x: f.x, y: f.y, vx: (Math.random() - 0.5) * 120, vy: -Math.random() * 80, g: 900, life: 0.4, max: 0.4, r: 1.3, c: '#c0c6cc' });
      if (f.drillP >= 1) {
        W.Audio.drill(false);
        this.say('Wykręcone wykrętakiem', 'good', 1500);
        this.complete(f);
      }
    },

    actBolt(f, dt) {
      const tool = this.tool;
      if (f.draining != null) return this.pressSay('Płyn jeszcze cieknie…', 'info');
      if (f.stripped || f.snapped) {
        if (tool === 'drill') return this.actDrill(f, dt);
        return this.pressSay(f.snapped ? 'Śruba ukręcona – wiertarka + wykrętak (0)' : 'Łeb zaokrąglony – wiertarka + wykrętak (0)', 'bad');
      }
      if (tool === 'grinder') {
        if (!f.cut) return this.pressSay('Tego nie przetniesz – odkręć');
        if (!this.owned.grinder) return this.pressSay('Nie masz szlifierki');
        if (!this.mountDisc()) return this.pressSay('Brak tarcz do szlifierki!', 'bad');
        f.cutProg += dt * 0.9;
        this.grind(dt, f, 0, f.x, f.y);
        if (f.cutProg >= 1) {
          this.rep.cut++;
          this.say('Przecięta (część trochę na tym cierpi)', 'warn', 1500);
          this.complete(f, { cut: true });
        }
        return;
      }
      if (tool === 'spray') return;
      if (tool !== 'ratchet' && tool !== 'impact') return this.pressSay('Tu potrzebujesz grzechotki (1) albo klucza udarowego (2)');
      if (tool === 'impact' && f.t === 'terminal') return this.pressSay('Udarowym na klemę? Grzechotka!');
      const sock = this.sockets[this.sockIdx];
      if (sock !== f.size) {
        if (!this.pressHinted) {
          this.pressHinted = true;
          if (typeof sock === 'number' && typeof f.size === 'number' && sock > f.size) {
            f.wear += 0.34 * this.fx.steady;
            f.known = true;
            W.Audio.slip();
            if (f.wear >= 1) {
              f.stripped = true;
              this.rep.stripped++;
              this.say('Łeb zaokrąglony! Teraz tylko wykrętak.', 'bad');
            } else this.say(`Nasadka ${fmtSock(sock)} za duża – ślizga się i zaokrągla łeb!`, 'bad');
          } else {
            this.say(`Nasadka ${fmtSock(sock)} nie wchodzi${f.known ? ` – potrzebna ${fmtSock(f.size)}` : ' (PPM = zmierz)'}`, 'warn');
            W.Audio.click();
          }
        }
        return;
      }
      f.known = true;
      const drive = tool === 'impact';
      if (f.rust > 0 && f.crack < 1) {
        const pen = f.soaked ? 2.2 : 1;
        if (drive) {
          f.crack += dt * (f.rust < 0.6 ? 1.6 : 0.55) * pen;
          this.busyFrame = this.loopsOn = true;
          W.Audio.impact(true);
          this.noise(dt * 0.12);
          if (f.rust > 0.85) f.stress += dt * 0.12 * this.fx.steady;
        } else {
          f.torque = Math.min(1.15, f.torque + dt * 0.85);
          if (f.torque > 0.55 && f.torque <= 0.88) {
            f.crack += dt * (0.5 / Math.max(0.35, f.rust)) * pen;
            if (Math.random() < dt * 5) W.Audio.creak();
          } else if (f.torque > 0.88) {
            f.stress += dt * 1.7 * this.fx.steady;
            if (Math.random() < dt * 9) W.Audio.creak();
            this.onceSay('red', 'Za mocno! Puść i ciągnij impulsami w zielonym polu', 'bad');
          }
        }
        if (f.stress >= 1) {
          f.snapped = true;
          f.torque = 0;
          this.rep.snapped++;
          W.Audio.snapBolt();
          this.say('Ukręciłeś śrubę! Wiertarka + wykrętak (0)', 'bad', 3000);
          return;
        }
        if (f.crack >= 1) {
          f.torque = 0;
          W.Audio.crackLoose();
          this.say('Puściła!', 'good', 1200);
        }
        return;
      }
      const spd = (drive ? 2.4 : 0.85) * this.fx.speed / (typeof f.size === 'number' && f.size >= 17 ? 1.2 : 1);
      const before = f.prog;
      f.prog += dt * spd;
      if (drive) {
        this.busyFrame = this.loopsOn = true;
        W.Audio.impact(true);
        this.noise(dt * 0.1);
      } else if (Math.floor(before * 9) !== Math.floor(f.prog * 9)) W.Audio.ratchet();
      if (f.prog >= 1) this.complete(f);
    },

    actScrew(f, dt) {
      const tool = this.tool, I = W.Input;
      if (f.stripped) {
        if (tool === 'drill') return this.actDrill(f, dt);
        return this.pressSay('Gniazdo wkrętu zerwane – wiertarka + wykrętak (0)', 'bad');
      }
      if (tool !== 'screw') return this.pressSay('Tu potrzebny wkrętak (3)');
      const bit = this.bits[this.bitIdx];
      if (bit !== f.bit) {
        if (!this.pressHinted) {
          this.pressHinted = true;
          f.wear += 0.1 * this.fx.steady;
          W.Audio.slip();
          this.say(`Końcówka ${bit} nie pasuje${f.known ? ` – potrzebna ${f.bit}` : ' (PPM = zmierz)'}`, 'warn');
        }
        return;
      }
      f.known = true;
      f.prog += dt * 1.0 * this.fx.speed;
      if (Math.random() < dt * 6) W.Audio.screw();
      if (I.speed > 380) {
        f.wear += dt * 2.2 * this.fx.steady;
        this.onceSay('camout', 'Ręka ucieka – trzymaj kursor nieruchomo przy wkręcaniu!', 'warn');
        if (f.wear >= 1) {
          f.stripped = true;
          this.rep.stripped++;
          W.Audio.slip();
          this.say('Zerwałeś gniazdo wkrętu!', 'bad');
          return;
        }
      }
      if (f.prog >= 1) this.complete(f);
    },

    actClip(f) {
      const I = W.Input;
      if (this.tool !== 'trim') return this.pressSay('Klipsy i wieszaki podważa się łyżką (4)');
      const d = this.dirOf(f);
      const along = (I.x - this.pressX) * d.x + (I.y - this.pressY) * d.y;
      f.drag = Math.max(f.drag || 0, along);
      const v = I.vx * d.x + I.vy * d.y;
      const brk = (f.t === 'hanger' ? 900 : 1250) / this.fx.steady;
      if (f.t === 'clip' && f.drag > 6 && v > brk) {
        this.rep.broken++;
        W.Audio.clipSnap();
        this.say('Klips pękł – za gwałtownie!', 'bad');
        for (let k = 0; k < 8; k++) this.particles.add({ x: f.x, y: f.y, vx: (Math.random() - 0.5) * 300, vy: -Math.random() * 250, life: 0.8, max: 0.8, r: 2, c: '#2b2f33' });
        return this.complete(f, { broken: true });
      }
      const need = f.t === 'hanger' ? 70 : 42;
      if (f.drag >= need) {
        W.Audio.pop();
        this.complete(f);
      }
    },

    unplug(f) {
      W.Audio.unplug();
      if (!this.flags['@batteryOff']) {
        if (f.airbag) {
          this.rep.airbag = true;
          this.fxPost('airbag', { i: f.i });
          W.Audio.boom();
          this.flash = 1;
          this.say('BUM! Poduszka wystrzeliła – akumulator był podłączony!', 'bad', 4000);
        } else if (f.sensitive) {
          this.rep.sensitive++;
          this.fxPost('spark', { i: f.i });
          W.Audio.zap();
          this.say('Zwarcie! Elektronika oberwała – najpierw odłącz akumulator', 'bad', 3000);
        }
      }
      this.complete(f);
    },

    actConnector(f, dt) {
      const I = W.Input;
      if (this.tool !== 'hand') return this.pressSay('Wtyczki odpina się ręką (6)');
      if (f.latch < 1) {
        f.latch += dt / 0.35;
        if (W.dist(I.x, I.y, this.pressX, this.pressY) > 22) {
          this.rep.broken++;
          W.Audio.clipSnap();
          this.say('Wyrwałeś wtyczkę bez wciśnięcia zatrzasku!', 'bad');
          return this.unplug(f);
        }
        if (f.latch >= 1) {
          W.Audio.click();
          this.pressX = I.x;
          this.pressY = I.y;
        }
        return;
      }
      const d = this.dirOf(f);
      const along = (I.x - this.pressX) * d.x + (I.y - this.pressY) * d.y;
      if (along >= 42) this.unplug(f);
    },

    actHose(f, dt) {
      const I = W.Input, tool = this.tool;
      const pl = tool === 'pliers' && this.owned.pliers, hand = tool === 'hand';
      if (!pl && !hand) return this.pressSay(tool === 'pliers' ? 'Nie masz szczypiec – spróbuj ręką (6)' : 'Opaskę ściśnij szczypcami (5)');
      if (f.squeeze < 1) {
        f.squeeze += dt / (pl ? 0.7 : 2.0);
        if (Math.random() < dt * 4) W.Audio.screw();
        if (f.squeeze >= 1) {
          W.Audio.click();
          this.pressX = I.x;
          this.pressY = I.y;
        }
        return;
      }
      const d = this.dirOf(f);
      const along = (I.x - this.pressX) * d.x + (I.y - this.pressY) * d.y;
      if (along < 48) return;
      if (hand && Math.random() < 0.25) {
        this.rep.broken++;
        this.say('Wąż się rozerwał – bez szczypiec ciężko', 'bad');
      }
      const flag = FLUID_FLAG[f.fluid];
      if (flag && !this.flags[flag]) {
        this.rep.spills++;
        W.Audio.splash();
        this.say(`Rozlałeś ${FLUID[f.fluid]}! Najpierw spuść płyn.`, 'bad', 3000);
        for (let k = 0; k < 40; k++) this.particles.add({ x: f.x, y: f.y, vx: (Math.random() - 0.5) * 220, vy: Math.random() * 60, g: 1300, life: 0.9, max: 0.9, r: 2.5, c: FLUID_COL[f.fluid] });
      } else W.Audio.pop();
      this.complete(f);
    },

    actCut(f, dt) {
      const I = W.Input, need = f.tool || 'grinder';
      if (this.tool !== need) return this.pressSay(need === 'wire' ? 'Szybę wycina się struną (8)' : 'Tu tnie się szlifierką (7)');
      if (!this.owned[need]) return this.pressSay(need === 'wire' ? 'Nie masz struny do szyb' : 'Nie masz szlifierki');
      if (need === 'grinder' && !this.mountDisc()) return this.pressSay('Brak tarcz do szlifierki!', 'bad');
      let near = null, nd = 1e9;
      for (const s of f.samples || []) {
        if (s.cut) continue;
        const d = W.dist(I.x, I.y, s.x, s.y);
        if (d < nd) { nd = d; near = s; }
      }
      if (near && nd < 16) {
        for (const s of f.samples) {
          if (!s.cut && W.dist(I.x, I.y, s.x, s.y) < 11) {
            s.hp -= dt;
            if (s.hp <= 0) s.cut = true;
          }
        }
        if (need === 'grinder') this.grind(dt, f, near.t, near.x, near.y);
        else {
          this.busyFrame = this.loopsOn = true;
          W.Audio.wire(true);
          if (Math.random() < dt * 20) this.particles.add({ x: near.x, y: near.y, vx: (Math.random() - 0.5) * 60, vy: -20, g: 300, life: 0.4, max: 0.4, r: 1.2, c: '#222' });
        }
      } else if (need === 'grinder') {
        this.gouge(dt);
      }
      const cut = f.samples.filter(s => s.cut).length / f.samples.length;
      f.cutProg = cut;
      if (cut >= 0.97) {
        f.samples.forEach(s => (s.cut = true));
        this.complete(f);
      }
    },

    actStamp(f, dt) {
      if (this.tool !== 'stamps') return this.pressSay('Znaki wybija się puncerem (T)');
      if (f.ring == null) return;
      f.ring -= dt * 1.2;
      if (f.ring < -0.15) this.onRelease(f);
    },

    updateHoist(dt) {
      const I = W.Input, h = this.hoist;
      if (I.hit('Escape')) {
        this.hoist = null;
        return;
      }
      h.t += dt;
      h.swing = Math.max(0.2, h.swing - dt * 0.12);
      h.needle = Math.sin(h.t * (2.4 + h.swing * 1.5)) * (0.55 + h.swing * 0.5);
      if (I.hit('Space') || I.clicked) {
        if (Math.abs(h.needle) < 0.2) {
          h.prog += 0.2;
          W.Audio.ratchet();
          W.Audio.creak();
          this.noise(0.02);
        } else {
          h.swing += 0.28;
          W.Audio.thud();
          if (h.swing > 1.05) {
            this.rep.bumps++;
            h.swing = 0.5;
            this.say('Silnik zahaczył o karoserię!', 'bad', 1800);
          }
        }
        if (h.prog >= 0.999) {
          this.complete(h.f);
          this.hoist = null;
          this.say('Podniesione!', 'good');
        }
      }
    },

    complete(f, opt = {}) {
      if (f.state === 'done') return;
      this.stopLoops();
      if (f.t === 'drain') {
        f.state = 'draining';
        f.draining = 0;
        f.drainTime = 3.5 + Math.random() * 2.5;
        f.plugOut = true;
        if (!f.basin) {
          this.rep.spills++;
          W.Audio.splash();
          this.say(`Bez miski – ${FLUID[f.fluid] || 'płyn'} leje się na posadzkę!`, 'bad', 3000);
        } else this.say('Korek wykręcony – płyn spływa do miski', 'info');
        return;
      }
      f.state = 'done';
      f.pop = 1;
      f.prog = 1;
      if (f.t === 'terminal') {
        if (f.sign === '+' && !this.flags['@batteryOff']) {
          this.rep.sparks++;
          this.fxPost('spark', { i: f.i });
          W.Audio.zap();
          this.flash = 0.35;
          this.say('Iskra! Zawsze najpierw klema MINUSOWA.', 'bad', 3000);
        }
      }
      if (f.sets) this.flags[f.sets] = true;
      if (['bolt', 'nut', 'terminal', 'screw'].includes(f.t) && !opt.cut) {
        this.particles.add({ kind: 'hex', x: f.x, y: f.y, vx: (Math.random() - 0.5) * 80, vy: -120, g: 1100, life: 1.1, max: 1.1, r: this.R * 0.55, rot: 0, vr: (Math.random() - 0.5) * 14 });
      }
      if (this.allDone()) {
        W.Audio.good();
        this.say('Wszystko odpięte – przytrzymaj SPACJĘ, żeby zdjąć część', 'good', 4000);
      }
    },

    /* ---------------- koniec ---------------- */
    penalty() {
      const r = this.rep;
      let p = 3 * r.broken + 2 * r.stripped + 3 * r.snapped + 4 * r.cut + 1.5 * r.gouge + 6 * r.spills + 8 * r.sparks + 4 * r.bumps + 14 * r.sensitive * (this.fx.tech ? 0.5 : 1);
      if (r.fire) p += 20;
      return p;
    },

    async finish() {
      if (this.finishing) return;
      this.finishing = true;
      this.stopLoops();
      W.Audio.thud();
      const report = Object.assign({}, this.rep, {
        gouge: Math.round(this.rep.gouge * 10) / 10,
        noise: Math.round(this.rep.noise * 100) / 100,
        used: this.used,
        stamps: this.fs.filter(f => f.t === 'stamp').map(f => f.q ?? 0),
        secs: Math.round((performance.now() - this.t0) / 1000),
      });
      $('p-remove').classList.add('busy');
      const res = await W.post('part', { action: 'finish', report });
      if (!W.isFiveM) {
        this.close();
        W.toast(`Demo: część zdjęta · stan ${Math.max(1, Math.round(this.part.cond - this.penalty()))}%`, 'good');
        return;
      }
      if (!res || !res.ok) this.finishing = false;
    },

    askAbort() {
      this.confirmOpen = true;
      this.stopLoops();
      const el = $('p-confirm');
      el.innerHTML = `
        <div class="card">
          <h2>Odejść od części?</h2>
          <p>Odkręcone elementy zostaną odkręcone – możesz wrócić później (jak w warsztacie).</p>
          <div class="row"><button class="btn" id="pcNo">Wracam</button><button class="btn danger" id="pcYes">Odejdź</button></div>
        </div>`;
      el.classList.remove('hidden');
      $('pcNo').onclick = () => { el.classList.add('hidden'); this.confirmOpen = false; };
      $('pcYes').onclick = () => {
        el.classList.add('hidden');
        this.confirmOpen = false;
        const done = this.fs.filter(f => f.state === 'done').map(f => f.i);
        W.post('part', { action: 'abort', done });
        if (!W.isFiveM) this.close();
      };
    },

    /* ---------------- rysowanie ---------------- */
    render() {
      const { g, w, h } = W.fitCanvas(this.cv);
      g.clearRect(0, 0, w, h);
      const R = this.R;
      // winieta skupiająca wzrok na części
      const cx = this.cx ?? w / 2, cy = this.cy ?? h / 2;
      const vg = g.createRadialGradient(cx, cy, Math.min(w, h) * 0.18, cx, cy, Math.max(w, h) * 0.75);
      vg.addColorStop(0, 'rgba(0,0,0,0)');
      vg.addColorStop(1, 'rgba(0,0,0,0.45)');
      g.fillStyle = vg;
      g.fillRect(0, 0, w, h);

      g.fillStyle = 'rgba(40,30,20,0.55)';
      for (const s of this.scratches) g.fillRect(s.x, s.y, 2, 2);

      for (const f of this.fs) {
        if (!f.vis || this.hidden(f)) continue;
        if (f.state === 'done' && f.pop <= 0 && f.t !== 'cut' && f.t !== 'stamp') continue;
        g.save();
        if (f.state === 'done' && f.t !== 'cut' && f.t !== 'stamp') {
          g.globalAlpha = f.pop;
          g.translate(f.x, f.y);
          g.scale(1 + (1 - f.pop) * 0.6, 1 + (1 - f.pop) * 0.6);
          g.translate(-f.x, -f.y);
        }
        this.drawFastener(g, f, R);
        g.restore();
      }

      // podświetlenie
      const hv = this.hover;
      if (hv && hv.state !== 'done' && hv.t !== 'cut') {
        g.strokeStyle = 'rgba(255,176,32,0.95)';
        g.lineWidth = 2;
        g.setLineDash([5, 4]);
        g.beginPath();
        g.arc(hv.x, hv.y, R * 1.55, 0, Math.PI * 2);
        g.stroke();
        g.setLineDash([]);
        if (['clip', 'hanger', 'connector', 'hose'].includes(hv.t)) this.drawArrow(g, hv, R);
      }
      if (this.measure) {
        g.strokeStyle = '#4ecdc4';
        g.lineWidth = 3;
        g.beginPath();
        g.arc(this.measure.f.x, this.measure.f.y, R * 1.8, -Math.PI / 2, -Math.PI / 2 + (this.measure.t / 0.45) * Math.PI * 2);
        g.stroke();
      }
      if (this.hoist) this.drawHoist(g, w, h);
      this.particles.draw(g);
      if (this.flash > 0) {
        g.fillStyle = `rgba(255,255,255,${this.flash * 0.7})`;
        g.fillRect(0, 0, w, h);
      }
      this.drawCursor(g);
    },

    ring(g, f, R, k, col, width = 3) {
      if (k <= 0) return;
      g.strokeStyle = col;
      g.lineWidth = width;
      g.beginPath();
      g.arc(f.x, f.y, R * 1.3, -Math.PI / 2, -Math.PI / 2 + W.clamp(k, 0, 1) * Math.PI * 2);
      g.stroke();
    },

    drawArrow(g, f, R) {
      const d = this.dirOf(f);
      const x0 = f.x + d.x * R * 1.9, y0 = f.y + d.y * R * 1.9;
      const x1 = x0 + d.x * R * 1.6, y1 = y0 + d.y * R * 1.6;
      g.strokeStyle = 'rgba(255,176,32,0.9)';
      g.fillStyle = 'rgba(255,176,32,0.9)';
      g.lineWidth = 2.5;
      g.beginPath();
      g.moveTo(x0, y0);
      g.lineTo(x1, y1);
      g.stroke();
      const a = Math.atan2(d.y, d.x);
      g.beginPath();
      g.moveTo(x1 + Math.cos(a) * 7, y1 + Math.sin(a) * 7);
      g.lineTo(x1 + Math.cos(a + 2.4) * 7, y1 + Math.sin(a + 2.4) * 7);
      g.lineTo(x1 + Math.cos(a - 2.4) * 7, y1 + Math.sin(a - 2.4) * 7);
      g.closePath();
      g.fill();
    },

    drawFastener(g, f, R) {
      const x = f.x, y = f.y;
      switch (f.t) {
        case 'bolt': case 'nut': case 'drain': case 'terminal': {
          if (f.t === 'drain' && f.basin) {
            g.fillStyle = '#3b4650';
            g.beginPath();
            g.ellipse(x, y + R * 2.4, R * 2.2, R * 0.7, 0, 0, Math.PI * 2);
            g.fill();
            g.fillStyle = f.draining != null ? FLUID_COL[f.fluid] || '#666' : '#1d2429';
            g.beginPath();
            g.ellipse(x, y + R * 2.3, R * 1.8, R * 0.45, 0, 0, Math.PI * 2);
            g.fill();
          }
          if (f.state === 'draining') {
            g.strokeStyle = FLUID_COL[f.fluid] || '#777';
            g.lineWidth = Math.max(2, R * 0.35);
            g.beginPath();
            g.moveTo(x, y);
            g.lineTo(x + Math.sin(performance.now() / 90) * 1.5, y + R * 2.3);
            g.stroke();
            g.fillStyle = '#111';
            g.beginPath();
            g.arc(x, y, R * 0.45, 0, Math.PI * 2);
            g.fill();
            this.ring(g, f, R, f.draining, FLUID_COL[f.fluid] || '#aaa');
            break;
          }
          const out = f.prog;
          g.fillStyle = 'rgba(0,0,0,0.35)';
          g.beginPath();
          g.arc(x + 2 + out * 4, y + 3 + out * 5, R * (1.1 + out * 0.2), 0, Math.PI * 2);
          g.fill();
          g.fillStyle = '#6f777e';
          g.beginPath();
          g.arc(x, y, R * 1.15, 0, Math.PI * 2);
          g.fill();
          const s = 1 + out * 0.22;
          if (f.snapped) {
            g.fillStyle = '#4a4f54';
            g.beginPath();
            g.arc(x, y, R * 0.5, 0, Math.PI * 2);
            g.fill();
            g.strokeStyle = '#ff5c5c';
            g.lineWidth = 2;
            g.stroke();
            this.ring(g, f, R, f.drillP, '#4ecdc4');
            break;
          }
          let fill = '#b9c1c8';
          if (f.t === 'terminal') fill = f.sign === '+' ? '#c0392b' : '#1f1f1f';
          if (f.t === 'drain') fill = '#8d8f86';
          if (f.stripped) {
            g.fillStyle = fill;
            g.beginPath();
            g.arc(x, y, R * 0.8 * s, 0, Math.PI * 2);
            g.fill();
            g.strokeStyle = '#ff5c5c';
            g.lineWidth = 2;
            g.stroke();
          } else W.hex(g, x, y, R * 0.85 * s, fill, '#50585f', out * Math.PI * 5 + (f.i * 0.4));
          if (f.t === 'nut' || f.t === 'drain') {
            g.fillStyle = '#3c4247';
            g.beginPath();
            g.arc(x, y, R * 0.32 * s, 0, Math.PI * 2);
            g.fill();
          }
          if (f.t === 'terminal') {
            g.fillStyle = '#fff';
            g.font = `bold ${Math.round(R * 0.9)}px Rajdhani, sans-serif`;
            g.textAlign = 'center';
            g.textBaseline = 'middle';
            g.fillText(f.sign === '+' ? '+' : '−', x, y + 1);
          }
          const rustVis = f.rust > 0 ? f.rust * (1 - W.clamp(f.crack, 0, 1) * 0.75) : 0;
          if (rustVis > 0.02) {
            g.fillStyle = `rgba(150,72,22,${0.25 + rustVis * 0.55})`;
            g.beginPath();
            g.arc(x, y, R * 0.95, 0, Math.PI * 2);
            g.fill();
            g.fillStyle = `rgba(90,40,10,${rustVis * 0.6})`;
            for (let k = 0; k < 5; k++) {
              const a = f.i * 1.7 + k * 1.3;
              g.beginPath();
              g.arc(x + Math.cos(a) * R * 0.5, y + Math.sin(a) * R * 0.5, R * 0.18, 0, Math.PI * 2);
              g.fill();
            }
          }
          if (f.soak > 0 || f.soaked) {
            g.fillStyle = 'rgba(230,210,120,0.35)';
            g.beginPath();
            g.arc(x, y, R * 1.05, 0, Math.PI * 2);
            g.fill();
          }
          if (f.stripped) this.ring(g, f, R, f.drillP, '#4ecdc4');
          else if (f.torque > 0 && f.crack < 1) this.drawTorque(g, f, R);
          else if (f.cutProg > 0) this.ring(g, f, R, f.cutProg, '#ff8a3d');
          else this.ring(g, f, R, f.rust > 0 && f.crack < 1 ? f.crack : f.prog, '#3ddc84');
          if (f.rust > 0 && f.crack > 0 && f.crack < 1 && f.torque <= 0) this.ring(g, f, R * 1.15, f.crack, '#ffb020', 2);
          if (f.known && f.size != null && f.t !== 'terminal') this.label(g, fmtSock(f.size), x, y + R * 1.75, R);
          break;
        }
        case 'screw': {
          g.fillStyle = 'rgba(0,0,0,0.35)';
          g.beginPath();
          g.arc(x + 2, y + 3, R * 0.85, 0, Math.PI * 2);
          g.fill();
          g.fillStyle = f.stripped ? '#8d8f86' : '#c9cfd4';
          g.beginPath();
          g.arc(x, y, R * 0.8 * (1 + f.prog * 0.2), 0, Math.PI * 2);
          g.fill();
          g.strokeStyle = f.stripped ? '#ff5c5c' : '#555d63';
          g.lineWidth = 2;
          g.stroke();
          g.save();
          g.translate(x, y);
          g.rotate(f.prog * Math.PI * 6);
          g.strokeStyle = '#3a4046';
          g.lineWidth = Math.max(2, R * 0.16);
          const n = String(f.bit).startsWith('T') ? 6 : 4;
          for (let k = 0; k < n / 2; k++) {
            const a = (k / n) * Math.PI * 2;
            g.beginPath();
            g.moveTo(Math.cos(a) * -R * 0.45, Math.sin(a) * -R * 0.45);
            g.lineTo(Math.cos(a) * R * 0.45, Math.sin(a) * R * 0.45);
            g.stroke();
          }
          g.restore();
          this.ring(g, f, R, f.stripped ? f.drillP : f.prog, f.stripped ? '#4ecdc4' : '#3ddc84');
          if (f.wear > 0 && !f.stripped) this.ring(g, f, R * 1.15, f.wear, '#ff5c5c', 2);
          if (f.known) this.label(g, f.bit, x, y + R * 1.6, R);
          break;
        }
        case 'clip': case 'hanger': {
          const d = this.dirOf(f);
          const off = W.clamp((f.drag || 0) * 0.4, 0, 18);
          const px = x + d.x * off, py = y + d.y * off;
          if (f.t === 'hanger') {
            g.save();
            g.translate(px, py);
            g.rotate(Math.atan2(d.y, d.x) + Math.PI / 2);
            g.fillStyle = '#1c1c1c';
            W.roundRect(g, -R * 0.5, -R * 1.2, R, R * 2.4, R * 0.45);
            g.fill();
            g.fillStyle = '#3a3a3a';
            g.beginPath();
            g.arc(0, -R * 0.6, R * 0.25, 0, Math.PI * 2);
            g.arc(0, R * 0.6, R * 0.25, 0, Math.PI * 2);
            g.fill();
            g.restore();
          } else {
            g.fillStyle = '#26292c';
            g.beginPath();
            g.arc(px, py, R * 0.85, 0, Math.PI * 2);
            g.fill();
            g.strokeStyle = '#4a5055';
            g.lineWidth = 2;
            g.stroke();
            g.fillStyle = '#3a3f44';
            g.beginPath();
            g.arc(px, py, R * 0.35, 0, Math.PI * 2);
            g.fill();
          }
          this.ring(g, f, R, (f.drag || 0) / (f.t === 'hanger' ? 70 : 42), '#3ddc84');
          break;
        }
        case 'connector': {
          const d = this.dirOf(f);
          const a = Math.atan2(d.y, d.x);
          const off = f.latch >= 1 ? 6 : 0;
          g.save();
          g.translate(x + d.x * off, y + d.y * off);
          g.rotate(a);
          g.strokeStyle = '#222';
          g.lineWidth = 3;
          for (let k = -1; k <= 1; k++) {
            g.beginPath();
            g.moveTo(-R * 0.9, k * R * 0.3);
            g.lineTo(-R * 2.4, k * R * 0.45);
            g.stroke();
          }
          g.fillStyle = f.airbag ? '#f2c230' : f.sensitive ? '#3a7bd5' : '#5a6066';
          W.roundRect(g, -R * 0.9, -R * 0.6, R * 1.8, R * 1.2, 3);
          g.fill();
          g.fillStyle = f.latch > 0 ? '#9be7b0' : '#2d3135';
          g.fillRect(-R * 0.3, -R * 0.85, R * 0.6, R * 0.3);
          g.restore();
          this.ring(g, f, R, f.latch, '#4ecdc4');
          break;
        }
        case 'hose': {
          const d = this.dirOf(f);
          const px = -d.y, py = d.x;
          g.strokeStyle = '#161616';
          g.lineCap = 'round';
          g.lineWidth = R * 1.1;
          g.beginPath();
          g.moveTo(x - px * R * 2.2, y - py * R * 2.2);
          g.lineTo(x + px * R * 2.2, y + py * R * 2.2);
          g.stroke();
          g.lineCap = 'butt';
          g.strokeStyle = f.squeeze >= 1 ? '#9be7b0' : '#c8ced3';
          g.lineWidth = R * 0.35;
          g.beginPath();
          g.moveTo(x - d.x * R * 0.7, y - d.y * R * 0.7);
          g.lineTo(x + d.x * R * 0.7, y + d.y * R * 0.7);
          g.stroke();
          if (f.fluid) {
            g.fillStyle = FLUID_COL[f.fluid] || '#999';
            g.beginPath();
            g.arc(x + px * R * 1.6, y + py * R * 1.6, R * 0.25, 0, Math.PI * 2);
            g.fill();
          }
          this.ring(g, f, R, f.squeeze, '#4ecdc4');
          break;
        }
        case 'cut': {
          const S = f.samples || [];
          // przerywana linia do cięcia
          g.strokeStyle = 'rgba(255,138,61,0.55)';
          g.lineWidth = 2;
          g.setLineDash([6, 6]);
          g.beginPath();
          S.forEach((s, k) => (k ? g.lineTo(s.x, s.y) : g.moveTo(s.x, s.y)));
          if (f.closed && S.length) g.closePath();
          g.stroke();
          g.setLineDash([]);
          // przecięte odcinki: jasna szczelina (w trakcie) / ciemna (gotowe)
          g.lineCap = 'round';
          for (let k = 0; k < S.length; k++) {
            const s = S[k], n = S[(k + 1) % S.length];
            const heat = s.cut ? 1 : 1 - s.hp / (s.hp0 || 1);
            if (heat > 0.02) {
              g.fillStyle = f.state === 'done' ? '#101214' : `rgba(255,${Math.round(150 + heat * 90)},${Math.round(60 + heat * 120)},${0.35 + heat * 0.65})`;
              g.beginPath();
              g.arc(s.x, s.y, 2 + heat * 2, 0, Math.PI * 2);
              g.fill();
            }
            if (s.cut && n && n.cut && (k + 1 < S.length || f.closed)) {
              g.strokeStyle = f.state === 'done' ? '#101214' : '#ffe2a8';
              g.lineWidth = 4;
              g.beginPath();
              g.moveTo(s.x, s.y);
              g.lineTo(n.x, n.y);
              g.stroke();
            }
          }
          g.lineCap = 'butt';
          if (f.state !== 'done' && f.cutProg > 0 && S.length) this.label(g, Math.round(f.cutProg * 100) + '%', S[0].x, S[0].y - 18, this.R);
          break;
        }
        case 'stamp': {
          g.fillStyle = '#5f676e';
          g.fillRect(x - R * 0.7, y - R * 0.9, R * 1.4, R * 1.8);
          g.font = `bold ${Math.round(R * 1.2)}px "Share Tech Mono", monospace`;
          g.textAlign = 'center';
          g.textBaseline = 'middle';
          if (f.state === 'done') {
            const q = f.q ?? 1;
            g.save();
            g.translate(x, y);
            g.rotate((1 - q) * 0.35 * (f.i % 2 ? 1 : -1));
            g.fillStyle = q > 0.8 ? '#1b1f22' : q > 0.45 ? '#3a2f1c' : '#5a1c1c';
            g.fillText(f.ch || '?', (1 - q) * 3, (1 - q) * 3);
            g.restore();
          } else {
            g.fillStyle = 'rgba(255,255,255,0.28)';
            g.fillText(f.ch || '?', x, y);
          }
          if (f.ring != null) {
            g.strokeStyle = '#3ddc84';
            g.lineWidth = 2;
            g.beginPath();
            g.arc(x, y, R * 1.2 * 1.3 * 0.3 + R * 0.5, 0, Math.PI * 2);
            g.stroke();
            g.strokeStyle = '#ffb020';
            g.lineWidth = 3;
            g.beginPath();
            g.arc(x, y, Math.max(2, R * 1.2 * 1.3 * f.ring + R * 0.5), 0, Math.PI * 2);
            g.stroke();
          }
          break;
        }
        case 'hoist': {
          g.strokeStyle = '#8a9096';
          g.lineWidth = 3;
          g.setLineDash([6, 4]);
          g.beginPath();
          g.moveTo(x, 0);
          g.lineTo(x, y - R);
          g.stroke();
          g.setLineDash([]);
          g.strokeStyle = '#ffb020';
          g.lineWidth = 4;
          g.beginPath();
          g.arc(x, y, R * 0.8, -Math.PI * 0.1, Math.PI * 1.1);
          g.stroke();
          this.label(g, 'ŻURAW – kliknij', x, y + R * 1.9, R);
          break;
        }
      }
    },

    drawTorque(g, f, R) {
      const r = R * 1.55;
      const a0 = Math.PI * 0.8, span = Math.PI * 1.4;
      const seg = (from, to, col) => {
        g.strokeStyle = col;
        g.lineWidth = 5;
        g.beginPath();
        g.arc(f.x, f.y, r, a0 + span * from, a0 + span * to);
        g.stroke();
      };
      const k = 1 / 1.15;
      seg(0, 0.55 * k, 'rgba(255,255,255,0.25)');
      seg(0.55 * k, 0.88 * k, 'rgba(61,220,132,0.85)');
      seg(0.88 * k, 1, 'rgba(255,92,92,0.9)');
      const a = a0 + span * W.clamp(f.torque * k, 0, 1);
      g.strokeStyle = '#fff';
      g.lineWidth = 3;
      g.beginPath();
      g.moveTo(f.x + Math.cos(a) * (r - 9), f.y + Math.sin(a) * (r - 9));
      g.lineTo(f.x + Math.cos(a) * (r + 7), f.y + Math.sin(a) * (r + 7));
      g.stroke();
      if (f.stress > 0.05) this.ring(g, f, R * 1.45, f.stress, 'rgba(255,92,92,0.9)', 2);
      this.ring(g, f, R * 1.15, f.crack, '#ffb020', 2);
    },

    drawHoist(g, w, h) {
      const H = this.hoist;
      const cx = w / 2, cy = h * 0.72, r = Math.min(w, h) * 0.12;
      g.fillStyle = 'rgba(12,14,16,0.85)';
      W.roundRect(g, cx - r * 1.5, cy - r * 1.35, r * 3, r * 1.9, 10);
      g.fill();
      const a0 = -Math.PI / 2;
      g.lineWidth = 12;
      g.strokeStyle = 'rgba(255,255,255,0.15)';
      g.beginPath();
      g.arc(cx, cy, r, Math.PI, 0);
      g.stroke();
      g.strokeStyle = '#3ddc84';
      g.beginPath();
      g.arc(cx, cy, r, a0 - 0.2 * (Math.PI / 2) / 0.95, a0 + 0.2 * (Math.PI / 2) / 0.95);
      g.stroke();
      const a = a0 + (H.needle || 0) * (Math.PI / 2) / 0.95;
      g.strokeStyle = '#fff';
      g.lineWidth = 4;
      g.beginPath();
      g.moveTo(cx, cy);
      g.lineTo(cx + Math.cos(a) * r * 1.05, cy + Math.sin(a) * r * 1.05);
      g.stroke();
      g.fillStyle = '#ffb020';
      g.fillRect(cx - r * 1.2, cy + r * 0.3, r * 2.4 * H.prog, 8);
      g.strokeStyle = 'rgba(255,255,255,0.3)';
      g.lineWidth = 1;
      g.strokeRect(cx - r * 1.2, cy + r * 0.3, r * 2.4, 8);
      g.fillStyle = '#e6e9ec';
      g.font = '600 16px Rajdhani, sans-serif';
      g.textAlign = 'center';
      g.fillText('ŻURAW – SPACJA / LPM w zielonym polu · ESC anuluj', cx, cy - r * 1.1);
      g.fillStyle = H.swing > 0.8 ? '#ff5c5c' : '#8b949c';
      g.fillText(`Kołysanie: ${Math.round(H.swing * 100)}%`, cx, cy + r * 0.6 + 14);
    },

    label(g, text, x, y, R) {
      g.font = `600 ${Math.round(W.clamp(R * 0.8, 11, 15))}px Rajdhani, sans-serif`;
      g.textAlign = 'center';
      g.textBaseline = 'middle';
      const w = g.measureText(text).width + 8;
      g.fillStyle = 'rgba(10,12,14,0.75)';
      g.fillRect(x - w / 2, y - 8, w, 16);
      g.fillStyle = '#e6e9ec';
      g.fillText(text, x, y + 1);
    },

    drawCursor(g) {
      const I = W.Input;
      const x = I.x, y = I.y;
      g.strokeStyle = '#fff';
      g.lineWidth = 1.5;
      g.beginPath();
      g.arc(x, y, 6, 0, Math.PI * 2);
      g.moveTo(x - 11, y); g.lineTo(x - 7, y);
      g.moveTo(x + 7, y); g.lineTo(x + 11, y);
      g.moveTo(x, y - 11); g.lineTo(x, y - 7);
      g.moveTo(x, y + 7); g.lineTo(x, y + 11);
      g.stroke();
      const t = TOOLS.find(z => z.key === this.tool);
      let txt = t ? t.label : '';
      if (this.tool === 'ratchet' || this.tool === 'impact') txt += ' · ' + fmtSock(this.sockets[this.sockIdx]);
      if (this.tool === 'screw') txt += ' · ' + this.bits[this.bitIdx];
      g.font = '600 13px Rajdhani, sans-serif';
      g.textAlign = 'left';
      g.textBaseline = 'middle';
      const w = g.measureText(txt).width + 10;
      g.fillStyle = 'rgba(10,12,14,0.7)';
      g.fillRect(x + 14, y + 10, w, 18);
      g.fillStyle = '#ffb020';
      g.fillText(txt, x + 19, y + 19.5);
    },

    /* ---------------- HUD (DOM) ---------------- */
    buildTools() {
      const el = $('p-tools');
      el.innerHTML = TOOLS.map(t => {
        const owned = !!this.owned[t.key];
        let sub = '';
        if (t.key === 'ratchet' || t.key === 'impact') sub = fmtSock(this.sockets[this.sockIdx]);
        if (t.key === 'screw') sub = this.bits[this.bitIdx];
        if (t.key === 'spray') sub = '×' + Math.max(0, this.cons.penetrant - this.used.penetrant);
        if (t.key === 'grinder') sub = '×' + Math.max(0, this.cons.disc - this.used.disc) + (this.discMounted ? '+1' : '');
        if (t.key === 'drill') sub = '×' + Math.max(0, this.cons.extractor - this.used.extractor);
        return `<button class="tool ${this.tool === t.key ? 'on' : ''} ${owned ? '' : 'locked'}" data-tool="${t.key}"><b>${t.k}</b><span>${t.label}</span>${sub ? `<small>${W.esc(sub)}</small>` : ''}</button>`;
      }).join('');
      el.querySelectorAll('[data-tool]').forEach(b => (b.onclick = () => this.selectTool(b.dataset.tool)));
      this._toolsKey = this.toolKey();
    },

    toolKey() {
      return [this.tool, this.sockIdx, this.bitIdx, this.used.penetrant, this.used.disc, this.used.extractor, this.discMounted].join('|');
    },

    renderCard() {
      const p = this.part;
      $('p-card').innerHTML = `
        <div class="pc-title">${W.esc(p.label)}</div>
        <div class="pc-sub">${W.esc(this.ctx.vehicle || '')}${p.op ? ' · czynność serwisowa' : ''}${p.install ? ` · MONTAŻ (część z: ${W.esc(p.from || '?')})` : ''}</div>
        <div id="pc-cond"></div>
        <ul id="pc-list"></ul>
        <div id="pc-flags"></div>`;
    },

    renderHud() {
      if (this._toolsKey !== this.toolKey()) this.buildTools();
      const p = this.part;
      // stan
      if (!p.op) {
        const pen = this.penalty();
        let c = Math.max(1, Math.round(p.cond - pen));
        if (this.rep.airbag) c = p.id === 'airbag' ? 3 : Math.max(1, c - 30);
        const html = `<div class="pc-row"><span>Stan części</span><b style="color:${W.condColor(c)}">${c}%</b>${pen > 0 || this.rep.airbag ? `<em>(−${Math.round(p.cond - c)})</em>` : ''}</div>
          ${p.value ? `<div class="pc-row"><span>Wycena</span><b>${W.fmtMoney(p.value * Math.max(0.15, (c / Math.max(1, p.cond))))}</b></div>` : ''}`;
        if (html !== this._condHtml) { $('pc-cond').innerHTML = html; this._condHtml = html; }
      }
      // lista elementów
      const groups = {};
      for (const f of this.fs) {
        const g = (groups[f.t] = groups[f.t] || { n: 0, d: 0 });
        g.n++;
        if (f.state === 'done') g.d++;
      }
      const list = Object.entries(groups).map(([t, g]) => `<li class="${g.d === g.n ? 'ok' : ''}"><span>${TYPE_PL[t] || t}</span><b>${g.d}/${g.n}</b></li>`).join('');
      if (list !== this._list) { $('pc-list').innerHTML = list; this._list = list; }
      // flagi (akumulator, płyny)
      const fl = [];
      if (this.fs.some(f => f.airbag || f.sensitive || f.t === 'terminal')) {
        fl.push(this.flags['@batteryOff'] ? '<li class="ok">Akumulator odłączony</li>' : '<li class="warn">Akumulator podłączony!</li>');
      }
      const fluids = new Set(this.fs.filter(f => f.fluid && FLUID_FLAG[f.fluid]).map(f => f.fluid));
      for (const fl2 of fluids) fl.push(this.flags[FLUID_FLAG[fl2]] ? `<li class="ok">${FLUID[fl2]}: spuszczony</li>` : `<li class="warn">${FLUID[fl2]}: w układzie</li>`);
      const flHtml = fl.length ? `<ul class="pc-flags">${fl.join('')}</ul>` : '';
      if (flHtml !== this._fl) { $('pc-flags').innerHTML = flHtml; this._fl = flHtml; }

      // hałas + czas
      const nz = W.clamp(this.rep.noise, 0, 1.2) / 1.2;
      const secs = Math.round((performance.now() - this.t0) / 1000);
      const side = `<div class="pn-row"><span>Hałas</span><i><s style="width:${(nz * 100).toFixed(0)}%;background:${nz > 0.7 ? 'var(--bad)' : nz > 0.4 ? 'var(--acc)' : 'var(--good)'}"></s></i></div>
        <div class="pn-row"><span>Czas</span><b>${W.fmtTime(secs)}</b></div>`;
      if (side !== this._side) { $('p-side').innerHTML = side; this._side = side; }

      // podpowiedź
      const now = performance.now();
      let hint = '', kind = 'info';
      if (this.msg && this.msg.until > now) { hint = this.msg.text; kind = this.msg.kind; }
      else if (this.hover && this.hover.state !== 'done') hint = this.hoverHint(this.hover);
      const hEl = $('p-hint');
      if (hEl._t !== hint + kind) {
        hEl._t = hint + kind;
        hEl.className = hint ? 'show ' + kind : '';
        hEl.textContent = hint;
      }

      // tooltip
      const tip = $('p-tip');
      const hv = this.hover;
      if (hv && hv.state !== 'done' && !this.hoist) {
        const lines = this.tipLines(hv);
        const html = `<b>${W.esc(lines[0])}</b>${lines.slice(1).map(l => `<span>${W.esc(l)}</span>`).join('')}`;
        if (tip._h !== html) { tip.innerHTML = html; tip._h = html; }
        const I = W.Input;
        const tx = hv.t === 'cut' ? I.x + 34 : hv.x + this.R * 2 + 10, ty = hv.t === 'cut' ? I.y - 64 : hv.y - 20;
        tip.style.transform = `translate(${Math.round(tx)}px, ${Math.round(ty)}px)`;
        tip.classList.remove('hidden');
      } else tip.classList.add('hidden');

      // zdejmowanie
      const rm = $('p-remove');
      if (this.allDone() && !this.finishing) {
        rm.classList.remove('hidden');
        rm.querySelector('b').textContent = p.op ? `Gotowe: ${p.label} – przytrzymaj SPACJĘ` : p.install ? `Zamontowane: ${p.label} – przytrzymaj SPACJĘ` : `Zdejmij: ${p.label} – przytrzymaj SPACJĘ`;
        rm.querySelector('s').style.width = ((this.removeHold / 0.9) * 100).toFixed(0) + '%';
      } else if (!this.finishing) rm.classList.add('hidden');
    },

    tipLines(f) {
      const out = [];
      let head = TYPE[f.t] || f.t;
      if (['bolt', 'nut', 'drain', 'terminal'].includes(f.t)) head += f.known ? ' ' + fmtSock(f.size) : ' ? mm';
      if (f.t === 'terminal') head += f.sign === '+' ? ' (plus)' : ' (minus)';
      if (f.t === 'screw') head += ' ' + (f.known ? f.bit : '?');
      out.push(head);
      out.push('Narzędzie: ' + (f.t === 'cut' ? (f.tool === 'wire' ? 'struna (8)' : 'szlifierka (7)') : TOOL_FOR[f.t] || '–'));
      if (f.rust > 0 && f.crack < 1) out.push('Zapieczona rdzą' + (f.soaked ? ' · penetrant działa' : ''));
      if (f.stripped) out.push('Łeb zaokrąglony – wykrętak');
      if (f.snapped) out.push('Ukręcona – wykrętak');
      if (f.cut && f.t !== 'cut') out.push('Można przeciąć szlifierką');
      if (f.fluid && FLUID[f.fluid]) out.push('Płyn: ' + FLUID[f.fluid]);
      if (f.t === 'drain') out.push(f.basin ? 'Miska podstawiona' : 'B – podstaw miskę');
      if (f.airbag) out.push('Poduszka powietrzna – odłącz akumulator!');
      if (f.sensitive) out.push('Elektronika – wrażliwa na zwarcie');
      if (!f.known && ['bolt', 'nut', 'drain', 'screw'].includes(f.t)) out.push('PPM – zmierz');
      return out;
    },

    hoverHint(f) {
      switch (f.t) {
        case 'bolt': case 'nut':
          if (f.rust > 0 && f.crack < 1) return 'Zapieczona: ciągnij grzechotką impulsami (zielone pole) albo spryskaj penetrantem (9)';
          return 'Dobierz nasadkę (kółko / Q E) i trzymaj LPM';
        case 'terminal': return 'Klemy: najpierw MINUS, potem plus';
        case 'drain': return f.basin ? 'Odkręć korek – płyn zejdzie do miski' : 'Podstaw miskę (B), potem odkręć korek';
        case 'screw': return 'Dobierz końcówkę i trzymaj LPM – nie ruszaj myszą';
        case 'clip': return 'Podważ łyżką i pociągnij spokojnie w kierunku strzałki';
        case 'hanger': return 'Zsuń gumowy wieszak łyżką w kierunku strzałki';
        case 'connector': return 'Przytrzymaj, by wcisnąć zatrzask, potem wyciągnij w kierunku strzałki';
        case 'hose': return 'Ściśnij opaskę szczypcami, potem ściągnij wąż';
        case 'cut': return f.tool === 'wire' ? 'Prowadź strunę po linii, trzymając LPM' : 'Prowadź szlifierkę po linii – obok niszczysz część';
        case 'stamp': return 'Trzymaj LPM i puść, gdy pomarańczowy pierścień zrówna się z zielonym';
        case 'hoist': return 'Kliknij, żeby podpiąć żuraw';
      }
      return '';
    },
  });
})();
