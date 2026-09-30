/* dp-wlamywacz – host minigier (UIX-08). Jedna nakładka i jedna pętla requestAnimationFrame,
   która działa wyłącznie w trakcie gry (TEC-17). Gra dostaje api: finish, noise, rng. */
'use strict';
const Games = {};
const Host = {
  W: 800, H: 600, cv: null, ctx: null, inst: null, raf: 0, last: 0, warn: 0, heartAt: 0,
  init() {
    this.cv = $('#game-cv');
    this.ctx = this.cv.getContext('2d');
    const resize = () => {
      const r = this.cv.getBoundingClientRect();
      const dpr = Math.min(2, window.devicePixelRatio || 1);
      this.cv.width = Math.max(1, Math.round(r.width * dpr));
      this.cv.height = Math.max(1, Math.round(r.height * dpr));
      this.scale = this.cv.width / this.W;
    };
    if (window.ResizeObserver) new ResizeObserver(resize).observe(this.cv); else window.addEventListener('resize', resize);
    resize();
    const P = (e) => { const r = this.cv.getBoundingClientRect(); return { x: (e.clientX - r.left) * this.W / r.width, y: (e.clientY - r.top) * this.H / r.height }; };
    this.cv.addEventListener('pointerdown', (e) => { e.preventDefault(); this.cv.focus(); Snd.ensure(); try { this.cv.setPointerCapture(e.pointerId); } catch (_) {} if (this.inst && this.inst.down) this.inst.down(P(e), e); });
    this.cv.addEventListener('pointermove', (e) => { if (this.inst && this.inst.move) this.inst.move(P(e), e); });
    const up = (e) => { if (this.inst && this.inst.up) this.inst.up(P(e), e); };
    this.cv.addEventListener('pointerup', up); this.cv.addEventListener('pointercancel', up);
    this.cv.addEventListener('contextmenu', (e) => e.preventDefault());
    this.cv.addEventListener('wheel', (e) => { e.preventDefault(); if (this.inst && this.inst.wheel) this.inst.wheel(e.deltaY); }, { passive: false });
    window.addEventListener('keydown', (e) => {
      if (!this.inst) return;
      if (e.key === 'Escape') { this.finish(Object.assign({ ok: false, aborted: true }, this.inst.partial ? this.inst.partial() : {})); return; }
      if (this.inst.key && this.inst.key(e, true)) e.preventDefault();
    });
    window.addEventListener('keyup', (e) => { if (this.inst && this.inst.key && this.inst.key(e, false)) e.preventDefault(); });
  },
  open(params) {
    const def = Games[params.game];
    if (!def) { post('gameResult', { ok: false }); return; }
    const api = {
      W: this.W, H: this.H, params,
      rng: rngFrom(params.seed || Math.floor(Math.random() * 1e9)),
      finish: (res) => this.finish(res),
      noise: (v, src) => post('gameNoise', { v, src }),
    };
    this.inst = def.create(params, api);
    $('#game-title').textContent = def.title(params);
    $('#game-sub').textContent = def.sub ? def.sub(params) : '';
    $('#game-help').innerHTML = def.help(params) + ' <kbd>ESC</kbd> – przerwij.';
    $('#game').hidden = false;
    this.warn = 0;
    $('#game-warn').classList.remove('on');
    setTimeout(() => this.cv.focus(), 30);
    this.last = performance.now();
    const loop = (now) => {
      if (!this.inst) return;
      const dt = Math.min(0.05, (now - this.last) / 1000); this.last = now;
      this.inst.update(dt);
      const c = this.ctx;
      c.setTransform(this.scale, 0, 0, this.scale, 0, 0);
      c.clearRect(0, 0, this.W, this.H);
      this.inst.draw(c);
      if (this.warn && now > this.heartAt) { this.heartAt = now + 900; Snd.heart(0.18); }
      this.raf = requestAnimationFrame(loop);
    };
    this.raf = requestAnimationFrame(loop);
  },
  finish(res) {
    if (!this.inst) return;
    this.inst = null;
    cancelAnimationFrame(this.raf);
    setTimeout(() => { $('#game').hidden = true; }, res && res.ok ? 450 : 150);
    post('gameResult', res || { ok: false });
  },
  // domownik blisko: ekran ciemnieje i słychać serce (WYT-16)
  setWarn(level) {
    this.warn = level;
    $('#game-warn').classList.toggle('on', level > 0);
  },
};
