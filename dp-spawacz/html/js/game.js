'use strict';
/* ==========================================================================
   Orkiestrator minigry: kolejka etapów, pętla, HUD, wyniki
   ========================================================================== */
W.Stages = W.Stages || {};

const $ = id => document.getElementById(id);

W.Game = {
  active: false,
  stage: null,
  raf: 0,

  open(task) {
    this.task = task;
    this.rand = W.rng(task.seed || 1);
    this.noise = W.makeNoise(this.rand);
    this.P = W.PROC[task.process] || W.PROC.MMA;
    this.M = W.MAT[task.material] || W.MAT.steel;
    this.POS = W.POSI[task.position] || W.POSI.flat;
    this.scores = {};
    this.stageTimes = {};
    this.passScores = [];
    this.finishScores = [];
    this.def = { burn: 0, lof: 0, poro: 0, incl: 0, undercut: 0, sag: 0, stray: 0, spatter: 0, gouge: 0 };
    this.spatter = [];
    this.slag = [];
    this.tintZones = [];
    this.pendingIncl = null;
    this.fitup = 1;
    this.partT = 0;
    this.setup = { ampF: 1, polOk: true, secF: 1, poolMul: 1 };
    this.dirtAt = () => 0;
    this.cells = null;
    this.layers = { bead: W.canvas(), marks: W.canvas() };
    this.piece = W.buildPiece(task, this.rand);
    this.particles = new W.Particles(700);
    this.t0 = performance.now();

    const q = ['setup', 'prep', task.type === 'crack' ? 'drill' : 'tack'];
    for (let p = 0; p < task.passes; p++) {
      q.push('weld:' + p);
      if (this.P.slag && p < task.passes - 1) q.push('finish:mid');
    }
    q.push('finish:final', 'report');
    this.queue = q;
    this.qi = -1;

    this.cv = $('cv');
    this.g = this.cv.getContext('2d');
    $('game').classList.remove('hidden');
    $('tablet').classList.add('hidden');
    this.clearHud();
    this.active = true;
    this.last = performance.now();
    cancelAnimationFrame(this.raf);
    this.raf = requestAnimationFrame(t => this.loop(t));
    this.next();
  },

  next() {
    if (this.stage && this.stage.destroy) this.stage.destroy();
    W.Audio.stopAll();
    this.qi++;
    const [name, arg] = this.queue[this.qi].split(':');
    this.clearHud();
    this.stageName = name;
    this.stageStart = performance.now();
    this.stage = W.Stages[name](this, arg);
    W.post('stage', { name });
  },

  /* etap zgłasza wynik 0..100 */
  done(key, score, extra) {
    const secs = (performance.now() - this.stageStart) / 1000;
    this.stageTimes[key] = (this.stageTimes[key] || 0) + secs;
    if (key === 'weld') this.passScores.push(score);
    else if (key === 'finish') this.finishScores.push(score);
    else this.scores[key] = W.clamp(score, 0, 100);
    if (extra && extra.msg) this.flash(extra.msg, extra.cls || 'good', 1400);
    setTimeout(() => this.active && this.next(), extra && extra.delay != null ? extra.delay : 900);
  },

  loop(ts) {
    if (!this.active) return;
    const dt = Math.min(0.05, (ts - this.last) / 1000);
    this.last = ts;
    const I = W.Input;
    if (I.hit('Escape') && !this.confirmOpen && this.stageName !== 'report') this.askAbort();
    if (!this.confirmOpen && this.stage) {
      if (this.stage.ready !== false) this.stage.update(dt);
      else if (I.hit('Space') || I.hit('Enter')) this.startIntro();
    }
    this.particles.update(dt);
    const g = this.g;
    g.setTransform(1, 0, 0, 1, 0, 0);
    if (this.stage) this.stage.render(g, dt);
    I.endFrame();
    this.raf = requestAnimationFrame(t => this.loop(t));
  },

  /* wspólne rysowanie: detal + ślady szlifowania + spoiny */
  drawWork(g) {
    g.drawImage(this.piece.base, 0, 0);
    g.drawImage(this.layers.marks, 0, 0);
    g.drawImage(this.layers.bead, 0, 0);
  },

  drawSpatter(g) {
    for (const s of this.spatter) {
      if (s.gone) continue;
      g.fillStyle = '#2f3336';
      g.beginPath();
      g.arc(s.x, s.y, s.r, 0, Math.PI * 2);
      g.fill();
      g.fillStyle = 'rgba(255,255,255,0.45)';
      g.beginPath();
      g.arc(s.x - s.r * 0.35, s.y - s.r * 0.35, s.r * 0.35, 0, Math.PI * 2);
      g.fill();
    }
  },

  /* ---------------- HUD ---------------- */
  clearHud() {
    for (const id of ['hud-left', 'hud-right', 'hud-bottom', 'stageName', 'stageSub', 'timer']) $(id).innerHTML = '';
    $('setup').classList.add('hidden');
    $('report').classList.add('hidden');
    $('intro').classList.add('hidden');
    $('progress').style.width = '0%';
  },

  title(name, sub) {
    const n = this.queue.length;
    $('stageName').innerHTML = `<span class="step">${this.qi + 1}/${n}</span>${W.esc(name)}`;
    $('stageSub').textContent = sub || '';
  },

  keys(list) {
    $('hud-bottom').innerHTML = list.map(([k, d]) => `<span class="key"><b>${k}</b>${W.esc(d)}</span>`).join('');
  },

  timer(sec, warnAt = 5) {
    const el = $('timer');
    if (sec == null) {
      el.textContent = '';
      return;
    }
    const s = Math.max(0, sec);
    el.textContent = s.toFixed(1) + ' s';
    el.classList.toggle('warn', s <= warnAt);
  },

  progress(f) {
    $('progress').style.width = W.clamp(f * 100, 0, 100).toFixed(1) + '%';
  },

  flash(text, cls = 'warn', ms = 1200) {
    const el = $('center-msg');
    el.className = 'show ' + cls;
    el.textContent = text;
    clearTimeout(this._flashT);
    this._flashT = setTimeout(() => (el.className = ''), ms);
  },

  /* karta instrukcji przed etapem */
  intro(stage, title, lines, keys) {
    stage.ready = false;
    this._introStage = stage;
    const el = $('intro');
    el.innerHTML = `
      <div class="card">
        <h2>${W.esc(title)}</h2>
        <ul>${lines.map(l => `<li>${l}</li>`).join('')}</ul>
        ${keys ? `<div class="keys">${keys.map(([k, d]) => `<span class="key"><b>${k}</b>${W.esc(d)}</span>`).join('')}</div>` : ''}
        <button class="btn primary" id="introGo">Zaczynam <small>(SPACJA)</small></button>
      </div>`;
    el.classList.remove('hidden');
    $('introGo').onclick = () => this.startIntro();
  },

  startIntro() {
    const st = this._introStage;
    if (!st || st.ready !== false) return;
    $('intro').classList.add('hidden');
    W.Audio.unlock();
    W.Audio.click();
    this.stageStart = performance.now();
    st.ready = true;
    if (st.onStart) st.onStart();
    W.Input.down = false;
  },

  askAbort() {
    this.confirmOpen = true;
    const el = $('confirm');
    el.innerHTML = `
      <div class="card">
        <h2>Przerwać zlecenie?</h2>
        <p>Postęp tego spawu zostanie utracony. Będziesz mógł podejść do niego ponownie.</p>
        <div class="row"><button class="btn" id="cNo">Wracam do pracy</button><button class="btn danger" id="cYes">Przerwij</button></div>
      </div>`;
    el.classList.remove('hidden');
    $('cNo').onclick = () => { el.classList.add('hidden'); this.confirmOpen = false; };
    $('cYes').onclick = () => { el.classList.add('hidden'); this.confirmOpen = false; this.close(true); };
  },

  close(aborted) {
    this.active = false;
    cancelAnimationFrame(this.raf);
    if (this.stage && this.stage.destroy) this.stage.destroy();
    this.stage = null;
    W.Audio.stopAll();
    this.particles && this.particles.clear();
    $('game').classList.add('hidden');
    W.post(aborted ? 'abort' : 'closeGame', {});
    W.post('arc', { on: false });
  },

  /* ---------------- ocena końcowa ---------------- */
  summary() {
    const avg = (a, empty) => (a.length ? a.reduce((x, y) => x + y, 0) / a.length : empty);
    const s = {
      setup: this.scores.setup ?? 0,
      prep: this.scores.prep ?? 0,
      prep2: this.scores.prep2 ?? 0,
      weld: this.passScores.length < this.task.passes ? 0 : avg(this.passScores, 0),
      finish: avg(this.finishScores, 0),
    };
    let q = 0;
    for (const k in W.WEIGHTS) q += W.WEIGHTS[k] * W.clamp(s[k], 0, 100);
    if (this.def.burn > 0) q = Math.min(q, 90 - (this.def.burn - 1) * 6);
    q = W.clamp(q, 0, 100);
    return {
      scores: s,
      defects: this.def,
      quality: Math.round(q * 10) / 10,
      grade: W.grade(q),
      seconds: Math.round((performance.now() - this.t0) / 1000),
      stageTimes: this.stageTimes,
    };
  },
};
