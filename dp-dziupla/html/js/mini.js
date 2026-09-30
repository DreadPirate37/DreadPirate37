'use strict';
/* ==========================================================================
   Wspólna ramka minigier (wytrych, skaner, stół warsztatowy)
   Logiczna rozdzielczość 960x560, skalowana do okna.
   ========================================================================== */
W.Mini = {
  VW: 960, VH: 560,
  active: null,
  open(game, title, keys) {
    this.close(true);
    this.active = game;
    W.$('mini').classList.remove('hidden');
    W.$('m-title').textContent = title;
    W.$('m-keys').innerHTML = (keys || []).map(([k, d]) => `<span class="key"><b>${k}</b>${W.esc(d)}</span>`).join('');
    W.$('m-hint').textContent = '';
    this.cv = W.$('mcv');
    this.g = this.cv.getContext('2d');
    this.fit();
    this.last = performance.now();
    cancelAnimationFrame(this.raf);
    this.raf = requestAnimationFrame(t => this.loop(t));
  },
  close(silent) {
    if (this.active && this.active.destroy) this.active.destroy();
    this.active = null;
    cancelAnimationFrame(this.raf);
    W.Audio.stopAll();
    W.$('mini').classList.add('hidden');
  },
  fit() {
    const s = Math.min((window.innerWidth * 0.9) / this.VW, (window.innerHeight * 0.8) / this.VH);
    W.$('m-frame').style.setProperty('--s', s.toFixed(4));
    this.scale = s;
  },
  hint(t, kind = '') {
    const el = W.$('m-hint');
    if (el._t === t + kind) return;
    el._t = t + kind;
    el.textContent = t;
    el.className = kind;
  },
  /* mysz w układzie logicznym ramki */
  mouse() {
    const r = this.cv.getBoundingClientRect();
    return { x: ((W.Input.x - r.left) / r.width) * this.VW, y: ((W.Input.y - r.top) / r.height) * this.VH };
  },
  loop(ts) {
    if (!this.active) return;
    const dt = Math.min(0.05, (ts - this.last) / 1000);
    this.last = ts;
    W.Input.tick(dt);
    const game = this.active;
    game.update(dt, this.mouse());
    if (this.active === game) {
      this.g.setTransform(1, 0, 0, 1, 0, 0);
      this.g.clearRect(0, 0, this.VW, this.VH);
      game.render(this.g);
    }
    W.Input.endFrame();
    if (this.active) this.raf = requestAnimationFrame(t => this.loop(t));
  },
};
window.addEventListener('resize', () => W.Mini.active && W.Mini.fit());

/* ==========================================================================
   WYTRYCH – zamek bębenkowy (jak w Thief Simulator)
   Mysz w poziomie wybiera bolec, LPM podnosi. Tylko bolec „blokujący”
   stawia opór; ustawiasz go, puszczając w linii ścinania. Za wysoko =
   wszystkie bolce spadają, a wytrych się zużywa.
   ========================================================================== */
W.Lockpick = {
  open(spec) {
    const rnd = W.rng(spec.seed || 7);
    const n = W.clamp(spec.pins || 5, 3, 8);
    this.spec = spec;
    this.pins = Array.from({ length: n }, () => ({ key: rnd.range(0.28, 0.72), lift: 0, set: false, shake: 0 }));
    this.order = W.rng(spec.seed + 11 || 9);
    const idx = Array.from({ length: n }, (_, i) => i);
    for (let i = n - 1; i > 0; i--) {
      const j = Math.floor(this.order() * (i + 1));
      [idx[i], idx[j]] = [idx[j], idx[i]];
    }
    this.bind = idx;
    this.shear = spec.shear || 0.05;
    this.picks = spec.picks || 1;
    this.broke = 0;
    this.wear = 0;
    this.sel = 0;
    this.pick = 0;
    this.t = 0;
    this.done = false;
    W.Mini.open(this, 'Wytrych – zamek drzwi', [['Mysz ←→', 'wybór bolca'], ['LPM', 'podnoś'], ['Puść', 'ustaw w linii'], ['ESC', 'odpuść']]);
    W.Mini.hint('Szukaj bolca, który stawia opór – tylko on da się ustawić.');
  },
  binding() {
    for (const i of this.bind) if (!this.pins[i].set) return i;
    return -1;
  },
  resetPins(msg) {
    for (const p of this.pins) { p.set = false; }
    W.Audio.thud();
    W.Mini.hint(msg, 'bad');
  },
  wearOut(v) {
    this.wear += v;
    if (this.wear >= 1) {
      this.wear = 0;
      this.broke++;
      this.picks--;
      W.Audio.snapBolt();
      this.resetPins('Wytrych pękł!' + (this.picks > 0 ? ` Zostało: ${this.picks}` : ''));
      if (this.picks <= 0) this.finish(false);
    }
  },
  update(dt, m) {
    const I = W.Input;
    if (this.done) return;
    this.t += dt;
    if (I.hit('Escape')) return this.finish(false);
    const n = this.pins.length;
    const x0 = 250, step = 520 / (n - 1 || 1);
    this.sel = W.clamp(Math.round((m.x - x0) / step), 0, n - 1);
    const p = this.pins[this.sel];
    const b = this.binding();
    const target = p.key;
    if (I.down && !p.set) {
      const isBind = this.sel === b;
      p.lift = Math.min(1, p.lift + dt * (isBind ? 0.42 : 0.95));
      p.shake = isBind ? 1 : 0;
      if (Math.random() < dt * 8) W.Audio.pin();
      if (isBind && p.lift > target + this.shear * 0.6 + 0.1) {
        this.resetPins('Za wysoko – bolce spadły!');
        p.lift = 0;
        this.wearOut(0.34);
      }
      if (!isBind && p.lift > 0.95) this.wearOut(dt * 0.4);
    } else {
      p.shake = 0;
    }
    if (I.released && !p.set) {
      if (this.sel === b && Math.abs(p.lift - target) <= this.shear) {
        p.set = true;
        W.Audio.pinSet();
        W.Mini.hint('Klik! Bolec ustawiony.', 'good');
        if (this.binding() === -1) {
          W.Audio.good();
          return this.finish(true);
        }
      } else if (this.sel === b && p.lift > 0.1) {
        W.Mini.hint(p.lift < target ? 'Za nisko…' : 'Minąłeś linię', 'warn');
        this.wearOut(0.06);
      }
    }
    for (let i = 0; i < n; i++) {
      const q = this.pins[i];
      if (q.set) q.lift = q.key;
      else if (!(I.down && i === this.sel)) q.lift = Math.max(0, q.lift - dt * 2.5);
    }
  },
  finish(ok) {
    this.done = true;
    setTimeout(() => {
      W.Mini.close();
      W.post('lockpick', { success: ok, broke: this.broke });
    }, ok ? 500 : 250);
  },
  render(g) {
    const n = this.pins.length;
    const x0 = 250, step = 520 / (n - 1 || 1);
    const shearY = 250, bodyTop = 170, bodyBot = 400, plugTop = shearY;
    // obudowa
    g.fillStyle = '#20252a';
    g.fillRect(170, 90, 700, 360);
    g.fillStyle = '#6e5a2b';
    g.fillRect(190, plugTop, 660, bodyBot - plugTop);
    g.fillStyle = '#3a4046';
    g.fillRect(190, bodyTop - 70, 660, plugTop - bodyTop + 70);
    g.strokeStyle = 'rgba(255,255,255,0.35)';
    g.setLineDash([8, 6]);
    g.beginPath();
    g.moveTo(190, shearY);
    g.lineTo(850, shearY);
    g.stroke();
    g.setLineDash([]);
    for (let i = 0; i < n; i++) {
      const p = this.pins[i];
      const x = x0 + i * step;
      const jit = p.shake ? (Math.random() - 0.5) * 2.5 : 0;
      const keyH = 40 + p.key * 120;
      const restTop = bodyBot - 30 - keyH;
      // przy lift == key górna krawędź dolnego bolca trafia dokładnie w linię ścinania
      const lift = ((restTop - shearY) * p.lift) / p.key;
      const keyTop = restTop - lift;
      p.bottom = keyTop + keyH;
      g.fillStyle = '#15191c';
      g.fillRect(x - 16, 110, 32, bodyBot - 110);
      // sprężyna
      g.strokeStyle = '#8f979e';
      g.lineWidth = 2;
      g.beginPath();
      const drvTop = keyTop - 70;
      for (let k = 0; k <= 12; k++) {
        const yy = 112 + ((drvTop - 112) * k) / 12;
        g.lineTo(x + (k % 2 ? 9 : -9), yy);
      }
      g.stroke();
      // bolec górny (driver)
      g.fillStyle = '#b9c1c8';
      W.roundRect(g, x - 12 + jit, drvTop, 24, 68, 4);
      g.fill();
      // bolec dolny (key pin)
      g.fillStyle = p.set ? '#3ddc84' : '#d4a94a';
      W.roundRect(g, x - 12 + jit, keyTop + 2, 24, keyH, 6);
      g.fill();
      if (i === this.sel) {
        g.strokeStyle = '#ffb020';
        g.lineWidth = 2;
        g.strokeRect(x - 18, 108, 36, bodyBot - 104);
      }
    }
    // wytrych
    const sx = x0 + this.sel * step;
    const tipY = (this.pins[this.sel].bottom || bodyBot - 30) + 2;
    g.strokeStyle = '#d9dee2';
    g.lineWidth = 5;
    g.beginPath();
    g.moveTo(40, bodyBot - 12);
    g.lineTo(sx - 12, bodyBot - 12);
    g.lineTo(sx, Math.min(bodyBot - 12, tipY));
    g.stroke();
    // info
    g.fillStyle = '#e6e9ec';
    g.font = '600 18px Rajdhani, sans-serif';
    g.textAlign = 'left';
    g.fillText(`Wytrychy: ${this.picks}`, 190, 490);
    g.fillText(`Ustawione: ${this.pins.filter(p => p.set).length}/${n}`, 360, 490);
    g.fillStyle = 'rgba(255,255,255,0.15)';
    g.fillRect(560, 478, 200, 14);
    g.fillStyle = this.wear > 0.6 ? '#ff5c5c' : '#ffb020';
    g.fillRect(560, 478, 200 * this.wear, 14);
    g.fillStyle = '#8b949c';
    g.fillText('zużycie', 770, 490);
  },
};

/* ==========================================================================
   SKANER NADAJNIKA GPS – gorąco/zimno po sygnale, sprawdzanie kryjówek,
   a na końcu przecięcie właściwego przewodu (kolor diody).
   ========================================================================== */
W.Scanner = {
  SPOTS: [
    [480, 70], [255, 130], [705, 400], [400, 250], [340, 205], [480, 280], [480, 470], [480, 505], [480, 140], [480, 360],
  ],
  open(spec) {
    this.spec = spec;
    this.rnd = W.rng(spec.seed || 3);
    this.names = spec.spots || [];
    this.spot = spec.spot || 0;
    this.checked = new Set();
    this.checking = null;
    this.stage = 'scan';
    this.t = 0;
    this.beepT = 0;
    this.alert = false;
    this.wires = ['#d63b3b', '#3a7bd5', '#f2c230'];
    this.ledColor = this.rnd.pick(this.wires);
    W.Mini.open(this, 'Skaner nadajników GPS', [['Mysz', 'skanuj'], ['LPM (przytrzymaj)', 'sprawdź kryjówkę'], ['ENTER', 'auto czyste'], ['ESC', 'odpuść']]);
    W.Mini.hint('Wodź skanerem po aucie – im szybciej piszczy, tym bliżej nadajnik.');
  },
  target() {
    return this.spot > 0 ? this.SPOTS[(this.spot - 1) % this.SPOTS.length] : null;
  },
  update(dt, m) {
    const I = W.Input;
    this.t += dt;
    this.m = m;
    if (I.hit('Escape')) return this.finish(false);
    if (this.stage === 'wires') return this.updateWires(m);
    if (I.hit('Enter') && (this.checked.size >= 3 || this.t > 8)) return this.finish(false);
    const tg = this.target();
    const range = this.spec.tech ? 260 : 190;
    let sig = 0.06 + Math.random() * 0.05;
    if (tg) sig = Math.max(sig, 1 - W.dist(m.x, m.y, tg[0], tg[1]) / range);
    this.sig = W.lerp(this.sig || 0, W.clamp(sig, 0, 1), 0.2);
    this.beepT -= dt;
    if (this.beepT <= 0) {
      W.Audio.beep(700 + this.sig * 1400);
      this.beepT = W.lerp(1.0, 0.07, this.sig);
    }
    let hover = -1;
    this.SPOTS.forEach((s, i) => {
      if (i < this.names.length && W.dist(m.x, m.y, s[0], s[1]) < 28) hover = i;
    });
    this.hover = hover;
    if (I.down && hover >= 0 && !this.checked.has(hover)) {
      if (!this.checking || this.checking.i !== hover) this.checking = { i: hover, t: 0 };
      this.checking.t += dt * (this.spec.tech ? 1.6 : 1);
      if (this.checking.t >= 1.2) {
        this.checked.add(hover);
        this.checking = null;
        if (hover + 1 === this.spot) {
          W.Audio.good();
          this.stage = 'wires';
          W.Mini.hint('Jest! Przetnij przewód w kolorze migającej diody.', 'good');
        } else {
          W.Audio.click();
          W.Mini.hint(`${this.names[hover]} – pusto.`, '');
        }
      }
    } else if (!I.down) this.checking = null;
  },
  updateWires(m) {
    const I = W.Input;
    if (!I.clicked) return;
    this.wires.forEach((c, k) => {
      const x = 380 + k * 100;
      if (Math.abs(m.x - x) < 30 && m.y > 300 && m.y < 470) {
        if (c === this.ledColor) {
          W.Audio.snapBolt();
          this.finish(true);
        } else {
          W.Audio.bad();
          this.alert = true;
          W.Mini.hint('Zły przewód – nadajnik wysłał alarm! Tnij dalej.', 'bad');
          this.wires = this.wires.filter(x2 => x2 !== c);
        }
      }
    });
  },
  finish(found) {
    this.stage = 'done';
    setTimeout(() => {
      W.Mini.close();
      W.post('scanner', { found, alert: this.alert });
    }, 300);
  },
  render(g) {
    // sylwetka auta z góry
    g.fillStyle = '#15191c';
    g.fillRect(0, 0, 960, 560);
    g.fillStyle = '#2b3136';
    W.roundRect(g, 330, 40, 300, 480, 70);
    g.fill();
    g.fillStyle = '#1b2227';
    W.roundRect(g, 360, 150, 240, 90, 20);
    g.fill();
    W.roundRect(g, 360, 350, 240, 70, 18);
    g.fill();
    g.fillStyle = '#0d0f11';
    for (const [x, y] of [[315, 110], [615, 110], [315, 400], [615, 400]]) g.fillRect(x, y, 30, 70);
    if (this.stage === 'wires') {
      g.fillStyle = '#20262b';
      W.roundRect(g, 330, 180, 300, 320, 12);
      g.fill();
      g.fillStyle = '#111';
      g.fillRect(420, 210, 120, 70);
      const on = Math.floor(this.t * 3) % 2 === 0;
      g.fillStyle = on ? this.ledColor : '#333';
      g.beginPath();
      g.arc(480, 245, 12, 0, Math.PI * 2);
      g.fill();
      this.wires.forEach((c, k) => {
        const x = 380 + [0, 1, 2][k] * 100;
        g.strokeStyle = c;
        g.lineWidth = 10;
        g.beginPath();
        g.moveTo(480, 280);
        g.quadraticCurveTo(x, 320, x, 470);
        g.stroke();
      });
      return;
    }
    this.SPOTS.forEach((s, i) => {
      if (i >= this.names.length) return;
      const chk = this.checked.has(i);
      g.fillStyle = chk ? 'rgba(120,120,120,0.35)' : i === this.hover ? 'rgba(255,176,32,0.6)' : 'rgba(78,205,196,0.3)';
      g.beginPath();
      g.arc(s[0], s[1], 20, 0, Math.PI * 2);
      g.fill();
      if (i === this.hover) {
        g.fillStyle = '#e6e9ec';
        g.font = '600 15px Rajdhani, sans-serif';
        g.textAlign = s[0] > 480 ? 'right' : 'left';
        g.fillText(this.names[i], s[0] + (s[0] > 480 ? -28 : 28), s[1] + 5);
      }
    });
    if (this.checking) {
      const s = this.SPOTS[this.checking.i];
      g.strokeStyle = '#ffb020';
      g.lineWidth = 4;
      g.beginPath();
      g.arc(s[0], s[1], 26, -Math.PI / 2, -Math.PI / 2 + (this.checking.t / 1.2) * Math.PI * 2);
      g.stroke();
    }
    // miernik
    g.fillStyle = 'rgba(255,255,255,0.1)';
    g.fillRect(40, 60, 26, 440);
    const s = this.sig || 0;
    g.fillStyle = s > 0.7 ? '#ff5c5c' : s > 0.4 ? '#ffb020' : '#3ddc84';
    g.fillRect(40, 60 + 440 * (1 - s), 26, 440 * s);
    g.fillStyle = '#8b949c';
    g.font = '600 15px Rajdhani, sans-serif';
    g.textAlign = 'left';
    g.fillText('SYGNAŁ', 30, 525);
    if (this.m) {
      g.strokeStyle = '#4ecdc4';
      g.lineWidth = 2;
      g.beginPath();
      g.arc(this.m.x, this.m.y, 16 + Math.sin(this.t * 10) * 2, 0, Math.PI * 2);
      g.stroke();
    }
    if (this.checked.size >= 3 || this.t > 8) {
      g.fillStyle = '#8b949c';
      g.textAlign = 'right';
      g.fillText('ENTER – auto jest czyste', 930, 525);
    }
  },
};

/* ==========================================================================
   STÓŁ WARSZTATOWY – regeneracja części
   dents: klepanie wgnieceń (siła uderzenia = głębokość wgniecenia)
   clean: szczotka na brud + wymiana zużytych uszczelek
   split: montażownica (spuszczenie powietrza, zbicie stopki, łyżka dookoła felgi)
   ========================================================================== */
W.Bench = {
  open(spec) {
    this.spec = spec;
    this.rnd = W.rng(spec.seed || 5);
    this.t = 0;
    this.limit = 60;
    this.mode = spec.mode;
    this.done = false;
    const r = this.rnd;
    if (this.mode === 'dents') {
      this.dents = Array.from({ length: r.int(5, 8) }, () => ({ x: r.range(260, 700), y: r.range(150, 420), r: r.range(26, 48), d: r.range(0.45, 1), bump: 0 }));
      this.hits = 0;
      this.over = 0;
      this.power = null;
      W.Mini.open(this, `Klepanie: ${spec.label}`, [['LPM (trzymaj)', 'siła uderzenia'], ['Puść', 'uderz'], ['ENTER', 'zakończ'], ['ESC', 'anuluj']]);
      W.Mini.hint('Siła uderzenia ma odpowiadać głębokości wgniecenia. Za mocno = wybrzuszenie.');
    } else if (this.mode === 'split') {
      this.step = 0;
      this.valve = 0;
      this.beads = [{ a: -0.6, done: false }, { a: 1.5, done: false }, { a: 3.6, done: false }];
      this.bead = 0;
      this.ringT = 0;
      this.angle = null;
      this.lever = 0;
      this.scratch = 0;
      this.miss = 0;
      W.Mini.open(this, `Montażownica: ${spec.label}`, [['LPM', 'akcja'], ['ESC', 'anuluj']]);
      W.Mini.hint('1/3: Wykręć wentyl – przytrzymaj LPM na wentylu.');
    } else {
      this.grid = [];
      for (let y = 0; y < 18; y++) for (let x = 0; x < 30; x++) this.grid.push(r() < 0.8 ? r.range(0.5, 1) : 0);
      this.gaskets = Array.from({ length: r.int(3, 5) }, () => ({ x: r.range(260, 700), y: r.range(160, 400), t: 0, ok: false }));
      W.Mini.open(this, `Regeneracja: ${spec.label}`, [['LPM + ruch', 'szczotka'], ['LPM (trzymaj) na uszczelce', 'wymiana'], ['ENTER', 'zakończ'], ['ESC', 'anuluj']]);
      W.Mini.hint('Wyszoruj brud i wymień zużyte (czerwone) uszczelki.');
    }
  },
  update(dt, m) {
    const I = W.Input;
    if (this.done) return;
    this.t += dt;
    this.m = m;
    if (I.hit('Escape')) {
      W.Mini.close();
      W.post('bench', { action: 'cancel' });
      return;
    }
    if (this.mode === 'dents') this.updDents(dt, m);
    else if (this.mode === 'split') this.updSplit(dt, m);
    else this.updClean(dt, m);
    if (this.mode !== 'split' && (I.hit('Enter') || this.t >= this.limit)) this.finish();
  },
  updDents(dt, m) {
    const I = W.Input;
    if (I.clicked) this.power = { v: 0, dir: 1 };
    if (this.power && I.down) {
      this.power.v += this.power.dir * dt * 1.4;
      if (this.power.v >= 1) { this.power.v = 1; this.power.dir = -1; }
      if (this.power.v <= 0) { this.power.v = 0; this.power.dir = 1; }
    }
    if (this.power && I.released) {
      const v = this.power.v;
      this.power = null;
      this.hits++;
      W.Audio.hammer();
      const d = this.dents.find(q => W.dist(m.x, m.y, q.x, q.y) < q.r);
      if (!d) return W.Mini.hint('Pudło – uderzyłeś w płaską blachę.', 'warn');
      const need = d.d;
      if (v > need + 0.22) {
        d.bump = Math.min(1, d.bump + 0.3);
        this.over++;
        W.Mini.hint('Za mocno – blacha się wybrzuszyła!', 'bad');
      } else if (v < need - 0.3) {
        d.d = Math.max(0, d.d - 0.08);
        W.Mini.hint('Za słabo.', 'warn');
      } else {
        d.d = Math.max(0, d.d - 0.45);
        d.bump = Math.max(0, d.bump - 0.2);
        W.Mini.hint('Dobre uderzenie!', 'good');
      }
      if (this.dents.every(q => q.d < 0.1 && q.bump < 0.2)) this.finish();
    }
  },
  updClean(dt, m) {
    const I = W.Input;
    if (I.down) {
      const g = this.gaskets.find(q => !q.ok && W.dist(m.x, m.y, q.x, q.y) < 22);
      if (g) {
        g.t += dt;
        if (g.t > 0.8) { g.ok = true; W.Audio.pop(); }
        return;
      }
      if (W.Input.speed > 60) {
        const cx = Math.floor((m.x - 180) / 20), cy = Math.floor((m.y - 100) / 20);
        for (let y = cy - 1; y <= cy + 1; y++) for (let x = cx - 1; x <= cx + 1; x++) {
          if (x < 0 || y < 0 || x >= 30 || y >= 18) continue;
          const k = y * 30 + x;
          this.grid[k] = Math.max(0, this.grid[k] - dt * 2.2);
        }
        if (Math.random() < dt * 10) W.Audio.screw();
      }
    }
    if (this.cleanPct() > 0.96 && this.gaskets.every(q => q.ok)) this.finish();
  },
  cleanPct() {
    const tot = this.grid.length;
    const dirt = this.grid.reduce((a, b) => a + b, 0);
    const start = this._start || (this._start = dirt || 1);
    return 1 - dirt / start;
  },
  updSplit(dt, m) {
    const I = W.Input;
    const cx = 480, cy = 290;
    if (this.step === 0) {
      if (I.down && W.dist(m.x, m.y, cx + 150, cy) < 30) {
        this.valve += dt / 1.5;
        W.Audio.hiss(true);
        if (this.valve >= 1) {
          W.Audio.hiss(false);
          this.step = 1;
          W.Mini.hint('2/3: Zbij stopkę – kliknij, gdy pierścień trafi w znacznik (3 miejsca).');
        }
      } else W.Audio.hiss(false);
    } else if (this.step === 1) {
      this.ringT += dt * 1.5;
      if (I.clicked) {
        const ph = (Math.sin(this.ringT * 2.2) + 1) / 2;
        if (ph > 0.8) {
          this.beads[this.bead].done = true;
          this.bead++;
          W.Audio.thud();
          if (this.bead >= 3) {
            this.step = 2;
            W.Mini.hint('3/3: Prowadź łyżkę dookoła felgi (LPM + ruch po okręgu). Nie za szybko!');
          }
        } else {
          this.miss++;
          W.Audio.bad();
        }
      }
    } else if (this.step === 2) {
      const a = Math.atan2(m.y - cy, m.x - cx);
      const r = W.dist(m.x, m.y, cx, cy);
      if (I.down && r > 150 && r < 230) {
        if (this.angle != null) {
          let d = a - this.angle;
          if (d > Math.PI) d -= Math.PI * 2;
          if (d < -Math.PI) d += Math.PI * 2;
          if (d > 0) {
            this.lever += d;
            if (d / dt > 5.5) {
              this.scratch += dt;
              W.Mini.hint('Za szybko – rysujesz felgę!', 'bad');
            }
            if (Math.random() < dt * 8) W.Audio.creak();
          }
        }
        this.angle = a;
      } else this.angle = null;
      if (this.lever >= Math.PI * 2) {
        W.Audio.pop();
        this.finish();
      }
    }
  },
  score() {
    if (this.mode === 'dents') {
      const rem = this.dents.reduce((a, d) => a + d.d + d.bump * 0.8, 0) / this.dents.length;
      return W.clamp(1 - rem - this.over * 0.04, 0, 1);
    }
    if (this.mode === 'split') return W.clamp(1 - this.scratch * 0.5 - this.miss * 0.06, 0, 1);
    const g = this.gaskets.filter(q => q.ok).length / this.gaskets.length;
    return W.clamp(this.cleanPct() * 0.7 + g * 0.3, 0, 1);
  },
  finish() {
    if (this.done) return;
    this.done = true;
    const score = Math.round(this.score() * 100) / 100;
    W.Mini.hint(`Wynik: ${Math.round(score * 100)}%`, score > 0.7 ? 'good' : 'warn');
    W.Audio.good();
    setTimeout(() => {
      W.Mini.close();
      W.post('bench', { action: 'finish', score });
    }, 700);
  },
  render(g) {
    g.fillStyle = '#15191c';
    g.fillRect(0, 0, 960, 560);
    if (this.mode === 'dents') {
      const gr = g.createLinearGradient(180, 100, 780, 460);
      gr.addColorStop(0, '#8e98a1');
      gr.addColorStop(0.5, '#c3cad0');
      gr.addColorStop(1, '#7b858e');
      g.fillStyle = gr;
      W.roundRect(g, 180, 100, 600, 360, 18);
      g.fill();
      for (const d of this.dents) {
        const rg = g.createRadialGradient(d.x - d.r * 0.3, d.y - d.r * 0.3, 2, d.x, d.y, d.r);
        rg.addColorStop(0, `rgba(30,35,40,${0.15 + d.d * 0.55})`);
        rg.addColorStop(1, 'rgba(30,35,40,0)');
        g.fillStyle = rg;
        g.beginPath();
        g.arc(d.x, d.y, d.r, 0, Math.PI * 2);
        g.fill();
        if (d.bump > 0.05) {
          g.fillStyle = `rgba(255,255,255,${d.bump * 0.4})`;
          g.beginPath();
          g.arc(d.x + 4, d.y + 4, d.r * 0.6, 0, Math.PI * 2);
          g.fill();
        }
      }
      if (this.power) {
        g.fillStyle = 'rgba(0,0,0,0.6)';
        g.fillRect(820, 110, 40, 340);
        g.fillStyle = this.power.v > 0.8 ? '#ff5c5c' : '#ffb020';
        g.fillRect(820, 110 + 340 * (1 - this.power.v), 40, 340 * this.power.v);
        const d = this.m && this.dents.find(q => W.dist(this.m.x, this.m.y, q.x, q.y) < q.r);
        if (d) {
          g.strokeStyle = '#3ddc84';
          g.lineWidth = 3;
          const y = 110 + 340 * (1 - d.d);
          g.beginPath();
          g.moveTo(812, y);
          g.lineTo(868, y);
          g.stroke();
        }
      }
    } else if (this.mode === 'split') {
      const cx = 480, cy = 290;
      g.fillStyle = '#111';
      g.beginPath();
      g.arc(cx, cy, 230, 0, Math.PI * 2);
      g.fill();
      g.fillStyle = '#8e98a1';
      g.beginPath();
      g.arc(cx, cy, 150, 0, Math.PI * 2);
      g.fill();
      g.fillStyle = '#5a636b';
      for (let k = 0; k < 5; k++) {
        const a = (k / 5) * Math.PI * 2;
        g.beginPath();
        g.arc(cx + Math.cos(a) * 60, cy + Math.sin(a) * 60, 22, 0, Math.PI * 2);
        g.fill();
      }
      g.fillStyle = this.step === 0 ? '#ffb020' : '#444';
      g.beginPath();
      g.arc(cx + 150, cy, 10, 0, Math.PI * 2);
      g.fill();
      if (this.step === 0) {
        g.strokeStyle = '#4ecdc4';
        g.lineWidth = 4;
        g.beginPath();
        g.arc(cx + 150, cy, 22, -Math.PI / 2, -Math.PI / 2 + this.valve * Math.PI * 2);
        g.stroke();
      }
      if (this.step === 1) {
        const b = this.beads[this.bead];
        const ph = (Math.sin(this.ringT * 2.2) + 1) / 2;
        const bx = cx + Math.cos(b.a) * 190, by = cy + Math.sin(b.a) * 190;
        g.strokeStyle = '#3ddc84';
        g.lineWidth = 3;
        g.beginPath();
        g.arc(bx, by, 14, 0, Math.PI * 2);
        g.stroke();
        g.strokeStyle = '#ffb020';
        g.beginPath();
        g.arc(bx, by, 14 + (1 - ph) * 40, 0, Math.PI * 2);
        g.stroke();
      }
      for (const b of this.beads) if (b.done) {
        g.fillStyle = '#3ddc84';
        g.beginPath();
        g.arc(cx + Math.cos(b.a) * 190, cy + Math.sin(b.a) * 190, 8, 0, Math.PI * 2);
        g.fill();
      }
      if (this.step === 2) {
        g.strokeStyle = '#ffb020';
        g.lineWidth = 8;
        g.beginPath();
        g.arc(cx, cy, 190, 0, W.clamp(this.lever, 0, Math.PI * 2));
        g.stroke();
      }
    } else {
      g.fillStyle = '#5d666e';
      W.roundRect(g, 180, 100, 600, 360, 30);
      g.fill();
      g.fillStyle = '#4a525a';
      for (let k = 0; k < 4; k++) g.fillRect(230 + k * 135, 150, 90, 260);
      for (let y = 0; y < 18; y++) for (let x = 0; x < 30; x++) {
        const v = this.grid[y * 30 + x];
        if (v <= 0.02) continue;
        g.fillStyle = `rgba(40,28,14,${v * 0.85})`;
        g.fillRect(180 + x * 20, 100 + y * 20, 20, 20);
      }
      for (const q of this.gaskets) {
        g.strokeStyle = q.ok ? '#3ddc84' : '#ff5c5c';
        g.lineWidth = 5;
        g.beginPath();
        g.arc(q.x, q.y, 16, 0, Math.PI * 2);
        g.stroke();
        if (!q.ok && q.t > 0) {
          g.strokeStyle = '#ffb020';
          g.lineWidth = 3;
          g.beginPath();
          g.arc(q.x, q.y, 24, -Math.PI / 2, -Math.PI / 2 + (q.t / 0.8) * Math.PI * 2);
          g.stroke();
        }
      }
    }
    g.fillStyle = '#e6e9ec';
    g.font = '600 18px Rajdhani, sans-serif';
    g.textAlign = 'left';
    g.fillText(`Stan: ${this.spec.cond}%  ·  maks. poprawa: +${this.spec.cap}`, 180, 500);
    if (this.mode !== 'split') {
      g.textAlign = 'right';
      g.fillText(`Czas: ${Math.max(0, Math.ceil(this.limit - this.t))} s`, 780, 500);
    }
    g.textAlign = 'right';
    g.fillStyle = '#ffb020';
    g.fillText(`Wynik: ${Math.round(this.score() * 100)}%`, 780, 530);
  },
};
