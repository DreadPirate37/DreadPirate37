'use strict';
/* ==========================================================================
   Dźwięk – w całości syntezowany (WebAudio), zero plików audio
   ========================================================================== */
W.Audio = {
  ctx: null, master: null, noise: null, loops: {}, volume: 0.55,

  unlock() {
    if (!this.ctx) this.init();
    if (this.ctx && this.ctx.state === 'suspended') this.ctx.resume();
  },

  init() {
    try {
      const AC = window.AudioContext || window.webkitAudioContext;
      this.ctx = new AC();
    } catch (e) {
      return;
    }
    const c = this.ctx;
    this.master = c.createGain();
    this.master.gain.value = this.volume;
    this.master.connect(c.destination);
    const len = c.sampleRate * 2;
    this.noise = c.createBuffer(1, len, c.sampleRate);
    const d = this.noise.getChannelData(0);
    for (let i = 0; i < len; i++) d[i] = Math.random() * 2 - 1;
  },

  _noiseSrc() {
    const s = this.ctx.createBufferSource();
    s.buffer = this.noise;
    s.loop = true;
    s.start();
    return s;
  },

  /* pętla: szum -> filtr -> gain, opcjonalnie oscylator (buczenie) */
  _loop(name, { type = 'bandpass', freq = 2500, q = 0.8, osc = null, oscGain = 0 }) {
    if (!this.ctx) return null;
    if (this.loops[name]) return this.loops[name];
    const c = this.ctx;
    const g = c.createGain();
    g.gain.value = 0;
    g.connect(this.master);
    const f = c.createBiquadFilter();
    f.type = type;
    f.frequency.value = freq;
    f.Q.value = q;
    f.connect(g);
    const n = this._noiseSrc();
    n.connect(f);
    let o = null, og = null;
    if (osc) {
      o = c.createOscillator();
      o.type = osc.type;
      o.frequency.value = osc.freq;
      og = c.createGain();
      og.gain.value = oscGain;
      o.connect(og);
      og.connect(g);
      o.start();
    }
    return (this.loops[name] = { g, f, n, o, og });
  },

  set(name, vol, opts = {}, cfg) {
    const l = this._loop(name, cfg || {});
    if (!l) return;
    const t = this.ctx.currentTime;
    l.g.gain.setTargetAtTime(vol, t, opts.tc ?? 0.015);
    if (opts.freq) l.f.frequency.setTargetAtTime(opts.freq, t, 0.03);
    if (opts.oscFreq && l.o) l.o.frequency.setTargetAtTime(opts.oscFreq, t, 0.03);
  },

  arc(on, proc, bad = 0) {
    if (!this.ctx) return;
    if (proc === 'MAG') {
      const crack = on ? 0.18 + Math.random() * 0.1 + bad * 0.25 * Math.random() : 0;
      this.set('arc', crack, { freq: 1800 + Math.random() * 900 }, { freq: 2000, q: 0.6, osc: { type: 'sawtooth', freq: 110 }, oscGain: 0.12 });
    } else if (proc === 'TIG') {
      this.set('arc', on ? 0.1 + bad * 0.15 * Math.random() : 0, { freq: 5200 }, { type: 'highpass', freq: 5000, q: 0.4, osc: { type: 'sine', freq: 100 }, oscGain: 0.08 });
    } else {
      const burst = Math.random() < 0.3 + bad * 0.5 ? Math.random() * 0.35 : 0;
      this.set('arc', on ? 0.14 + burst : 0, { freq: 2600 + Math.random() * 1600, tc: 0.006 }, { freq: 3000, q: 0.7 });
    }
  },

  grinder(rpm) {
    this.set('grind', rpm * 0.2, { freq: 900 + rpm * 2200, oscFreq: 120 + rpm * 380 }, { freq: 1500, q: 1.2, osc: { type: 'sawtooth', freq: 150 }, oscGain: 0.25 });
  },
  drill(on, load = 0) {
    this.set('drill', on ? 0.16 : 0, { oscFreq: 85 + (1 - load) * 40 }, { type: 'lowpass', freq: 1200, q: 1, osc: { type: 'square', freq: 110 }, oscGain: 0.3 });
  },
  hiss(on, vol = 0.12) {
    this.set('hiss', on ? vol : 0, {}, { type: 'highpass', freq: 3500, q: 0.3 });
  },
  brush(on) {
    this.set('brush', on ? 0.12 + Math.random() * 0.06 : 0, { freq: 4000 + Math.random() * 2000 }, { freq: 5000, q: 2 });
  },

  stopAll() {
    if (!this.ctx) return;
    for (const k in this.loops) this.loops[k].g.gain.setTargetAtTime(0, this.ctx.currentTime, 0.02);
  },

  blip(freq = 880, dur = 0.08, type = 'sine', vol = 0.2, slide = 0) {
    if (!this.ctx) return;
    const c = this.ctx, t = c.currentTime;
    const o = c.createOscillator(), g = c.createGain();
    o.type = type;
    o.frequency.setValueAtTime(freq, t);
    if (slide) o.frequency.exponentialRampToValueAtTime(Math.max(40, freq + slide), t + dur);
    g.gain.setValueAtTime(vol, t);
    g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
    o.connect(g);
    g.connect(this.master);
    o.start(t);
    o.stop(t + dur + 0.02);
  },

  thud(vol = 0.35, freq = 900) {
    if (!this.ctx) return;
    const c = this.ctx, t = c.currentTime;
    const n = c.createBufferSource();
    n.buffer = this.noise;
    const f = c.createBiquadFilter();
    f.type = 'bandpass';
    f.frequency.value = freq;
    const g = c.createGain();
    g.gain.setValueAtTime(vol, t);
    g.gain.exponentialRampToValueAtTime(0.0001, t + 0.12);
    n.connect(f);
    f.connect(g);
    g.connect(this.master);
    n.start(t, Math.random());
    n.stop(t + 0.15);
  },

  good() { this.blip(660, 0.09, 'triangle', 0.18); setTimeout(() => this.blip(990, 0.14, 'triangle', 0.18), 80); },
  bad() { this.blip(220, 0.2, 'sawtooth', 0.12, -80); },
  warn() { this.blip(740, 0.07, 'square', 0.08); setTimeout(() => this.blip(740, 0.07, 'square', 0.08), 120); },
  tick() { this.blip(1400, 0.03, 'square', 0.05); },
  click() { this.blip(500, 0.04, 'triangle', 0.12); },
  stamp() { this.thud(0.6, 300); this.blip(120, 0.25, 'sine', 0.3, -60); },
};
