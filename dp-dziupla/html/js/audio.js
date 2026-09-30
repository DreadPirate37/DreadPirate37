'use strict';
/* ==========================================================================
   Dźwięk warsztatu – w całości syntezowany (WebAudio), zero plików audio
   ========================================================================== */
W.Audio = {
  ctx: null, master: null, noise: null, loops: {}, volume: 0.5,

  unlock() {
    if (!this.ctx) this.init();
    if (this.ctx && this.ctx.state === 'suspended') this.ctx.resume();
  },

  init() {
    try {
      this.ctx = new (window.AudioContext || window.webkitAudioContext)();
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

  /* krótki impuls szumu przez filtr */
  burst(freq, q, dur, gain, type = 'bandpass', delay = 0) {
    if (!this.ctx) return;
    const c = this.ctx, t = c.currentTime + delay;
    const s = c.createBufferSource();
    s.buffer = this.noise;
    const f = c.createBiquadFilter();
    f.type = type;
    f.frequency.value = freq;
    f.Q.value = q;
    const g = c.createGain();
    g.gain.setValueAtTime(gain, t);
    g.gain.exponentialRampToValueAtTime(0.0008, t + dur);
    s.connect(f);
    f.connect(g);
    g.connect(this.master);
    s.start(t, Math.random() * 1.5);
    s.stop(t + dur + 0.05);
  },

  /* krótki ton */
  tone(freq, dur, gain, type = 'sine', slide = 0, delay = 0) {
    if (!this.ctx) return;
    const c = this.ctx, t = c.currentTime + delay;
    const o = c.createOscillator();
    o.type = type;
    o.frequency.setValueAtTime(freq, t);
    if (slide) o.frequency.exponentialRampToValueAtTime(Math.max(20, freq + slide), t + dur);
    const g = c.createGain();
    g.gain.setValueAtTime(gain, t);
    g.gain.exponentialRampToValueAtTime(0.0008, t + dur);
    o.connect(g);
    g.connect(this.master);
    o.start(t);
    o.stop(t + dur + 0.05);
  },

  /* pętla: szum -> filtr -> gain (+ opcjonalny oscylator) */
  loop(name, on, { freq = 2500, q = 1, type = 'bandpass', osc = null, oscFreq = 60, gain = 0.2, oscGain = 0.08 } = {}) {
    if (!this.ctx) return;
    let L = this.loops[name];
    if (!L && on) {
      const c = this.ctx;
      const g = c.createGain();
      g.gain.value = 0;
      g.connect(this.master);
      const f = c.createBiquadFilter();
      f.type = type;
      f.frequency.value = freq;
      f.Q.value = q;
      f.connect(g);
      const s = c.createBufferSource();
      s.buffer = this.noise;
      s.loop = true;
      s.connect(f);
      s.start();
      let o = null;
      if (osc) {
        o = c.createOscillator();
        o.type = osc;
        o.frequency.value = oscFreq;
        const og = c.createGain();
        og.gain.value = oscGain;
        o.connect(og);
        og.connect(g);
        o.start();
      }
      L = this.loops[name] = { g, f, s, o, target: gain };
    }
    if (!L) return;
    const t = this.ctx.currentTime;
    L.g.gain.cancelScheduledValues(t);
    L.g.gain.setTargetAtTime(on ? L.target : 0, t, on ? 0.03 : 0.08);
  },

  loopFreq(name, freq, oscFreq) {
    const L = this.loops[name];
    if (!L || !this.ctx) return;
    const t = this.ctx.currentTime;
    if (freq) L.f.frequency.setTargetAtTime(freq, t, 0.05);
    if (oscFreq && L.o) L.o.frequency.setTargetAtTime(oscFreq, t, 0.05);
  },

  stopAll() {
    for (const k in this.loops) this.loop(k, false);
  },

  /* ---------------- gotowe efekty ---------------- */
  click() { this.tone(1800, 0.03, 0.08, 'square'); },
  ratchet() { this.burst(4200, 6, 0.035, 0.35, 'bandpass'); this.tone(2600, 0.02, 0.05, 'square'); },
  creak() { this.tone(90 + Math.random() * 40, 0.25, 0.12, 'sawtooth', 30); this.burst(600, 3, 0.2, 0.15); },
  crackLoose() { this.burst(1800, 1.5, 0.12, 0.9, 'highpass'); this.tone(220, 0.15, 0.2, 'triangle', -120); },
  snapBolt() { this.burst(3000, 1, 0.2, 1.0, 'highpass'); this.tone(900, 0.2, 0.25, 'square', -700); },
  slip() { this.burst(5200, 2, 0.18, 0.5, 'bandpass'); this.tone(1200, 0.15, 0.08, 'sawtooth', -500); },
  pop() { this.tone(700, 0.07, 0.25, 'sine', -400); this.burst(2500, 2, 0.05, 0.3); },
  clipSnap() { this.burst(6000, 3, 0.06, 0.8, 'highpass'); this.tone(1500, 0.05, 0.15, 'square', -800); },
  unplug() { this.tone(1100, 0.03, 0.12, 'square'); this.tone(700, 0.05, 0.12, 'square', 0, 0.06); },
  zap() { this.burst(7000, 0.5, 0.25, 0.9, 'highpass'); this.tone(120, 0.25, 0.2, 'sawtooth', 300); },
  boom() { this.burst(180, 0.7, 0.6, 1.4, 'lowpass'); this.tone(60, 0.5, 0.6, 'sine', -30); },
  splash() { this.burst(900, 0.6, 0.5, 0.5, 'lowpass'); },
  drip() { this.tone(1400 + Math.random() * 600, 0.05, 0.05, 'sine', -900); },
  hammer() { this.tone(820, 0.25, 0.35, 'triangle', -200); this.burst(3500, 2, 0.08, 0.6); },
  spray() { this.burst(7000, 0.8, 0.5, 0.25, 'highpass'); },
  screw() { this.burst(3000, 8, 0.06, 0.12); },
  pin() { this.tone(2400 + Math.random() * 400, 0.03, 0.12, 'square'); },
  pinSet() { this.tone(3100, 0.04, 0.2, 'square'); this.tone(1900, 0.06, 0.12, 'square', 0, 0.04); },
  beep(f = 1400) { this.tone(f, 0.06, 0.12, 'sine'); },
  good() { this.tone(660, 0.1, 0.15, 'triangle'); this.tone(990, 0.16, 0.15, 'triangle', 0, 0.08); },
  bad() { this.tone(220, 0.25, 0.2, 'sawtooth', -80); },
  thud() { this.tone(80, 0.3, 0.5, 'sine', -40); this.burst(400, 1, 0.2, 0.4, 'lowpass'); },

  impact(on) { this.loop('impact', on, { freq: 900, q: 0.7, osc: 'sawtooth', oscFreq: 38, gain: 0.28, oscGain: 0.25 }); },
  grinder(on) { this.loop('grinder', on, { freq: 5200, q: 0.9, osc: 'sawtooth', oscFreq: 190, gain: 0.26, oscGain: 0.07 }); },
  wire(on) { this.loop('wire', on, { freq: 2600, q: 4, gain: 0.12 }); },
  drill(on) { this.loop('drill', on, { freq: 1600, q: 1, osc: 'square', oscFreq: 95, gain: 0.2, oscGain: 0.05 }); },
  hiss(on) { this.loop('hiss', on, { freq: 6000, q: 0.7, type: 'highpass', gain: 0.12 }); },
  pour(on) { this.loop('pour', on, { freq: 700, q: 0.8, type: 'lowpass', gain: 0.16 }); },
  hum(on) { this.loop('hum', on, { freq: 200, q: 1, osc: 'sine', oscFreq: 55, gain: 0.08, oscGain: 0.12 }); },
};
