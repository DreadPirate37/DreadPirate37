/* dp-wlamywacz – dźwięki syntezowane WebAudio (UIX-17), zero plików audio */
'use strict';
const Snd = {
  ctx: null, out: null, buf: null, siren: null,
  ensure() {
    if (!this.ctx) {
      const AC = window.AudioContext || window.webkitAudioContext;
      if (!AC) return null;
      try { this.ctx = new AC(); } catch (e) { return null; }
      this.out = this.ctx.createGain(); this.out.gain.value = 0.5; this.out.connect(this.ctx.destination);
      const len = this.ctx.sampleRate;
      this.buf = this.ctx.createBuffer(1, len, len);
      const d = this.buf.getChannelData(0);
      for (let i = 0; i < len; i++) d[i] = Math.random() * 2 - 1;
    }
    if (this.ctx.state === 'suspended') this.ctx.resume();
    return this.ctx;
  },
  noise(dur, freq, q, vol, type = 'bandpass', pan = 0, delay = 0) {
    const c = this.ensure(); if (!c) return;
    const t = c.currentTime + delay;
    const s = c.createBufferSource(); s.buffer = this.buf;
    const f = c.createBiquadFilter(); f.type = type; f.frequency.value = freq; f.Q.value = q;
    const g = c.createGain(); g.gain.setValueAtTime(vol, t); g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
    s.connect(f); f.connect(g);
    let node = g;
    if (pan && c.createStereoPanner) { const p = c.createStereoPanner(); p.pan.value = pan; g.connect(p); node = p; }
    node.connect(this.out);
    s.start(t, Math.random() * 0.8); s.stop(t + dur + 0.02);
  },
  tone(freq, dur, type, vol, slide, delay = 0) {
    const c = this.ensure(); if (!c) return;
    const t = c.currentTime + delay;
    const o = c.createOscillator(); o.type = type || 'sine';
    o.frequency.setValueAtTime(freq, t);
    if (slide) o.frequency.exponentialRampToValueAtTime(slide, t + dur);
    const g = c.createGain(); g.gain.setValueAtTime(vol, t); g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
    o.connect(g); g.connect(this.out); o.start(t); o.stop(t + dur + 0.02);
  },
  click(v = 0.3) { this.noise(0.035, 3200, 4, v); },
  pinSet() { this.noise(0.04, 2600, 6, 0.55); this.tone(1900, 0.03, 'triangle', 0.07); this.noise(0.03, 3400, 5, 0.3, 'bandpass', 0, 0.06); },
  rattle() { this.noise(0.025, 2300, 3, 0.12); },
  scrape() { this.noise(0.07, 1300, 1.2, 0.08); },
  creak(v) { this.noise(0.1, 380, 2, v, 'lowpass'); },
  snap() { this.noise(0.12, 4200, 0.8, 0.85, 'highpass'); this.tone(320, 0.12, 'square', 0.07, 90); },
  open() { this.noise(0.08, 900, 2, 0.5); this.noise(0.16, 280, 1.5, 0.65, 'lowpass', 0, 0.09); },
  thunk(v, pan = 0) { this.noise(0.07, 230, 3, v, 'lowpass', pan); this.tone(150, 0.07, 'sine', v * 0.5, 90); },
  tick(v) { this.noise(0.014, 5200, 5, v); },
  beep(f = 1250, d = 0.07, v = 0.1) { this.tone(f, d, 'square', v); },
  glass() { for (let i = 0; i < 6; i++) this.tone(2400 + Math.random() * 2600, 0.12, 'triangle', 0.05, 900, i * 0.02); this.noise(0.25, 5000, 0.7, 0.4, 'highpass'); },
  metal() { this.noise(0.09, 1800, 2, 0.4); this.tone(520, 0.12, 'sawtooth', 0.05, 300); },
  heart(v = 0.25) { this.tone(58, 0.09, 'sine', v); this.tone(52, 0.1, 'sine', v * 0.7, null, 0.18); },
  cash() { for (let i = 0; i < 4; i++) this.noise(0.03, 4200, 3, 0.25, 'bandpass', 0, i * 0.06); this.tone(1320, 0.12, 'triangle', 0.08, null, 0.25); },
  mail() { this.tone(880, 0.09, 'triangle', 0.1); this.tone(1320, 0.12, 'triangle', 0.1, null, 0.1); },
  alert() { this.tone(520, 0.12, 'square', 0.1); this.tone(390, 0.18, 'square', 0.1, null, 0.12); },
  sus() { this.tone(660, 0.1, 'triangle', 0.08, 720); },
  doorbell() { this.tone(988, 0.45, 'sine', 0.2); this.tone(784, 0.6, 'sine', 0.2, null, 0.45); },
  // syrena alarmu: pętla dwutonowa z głośnością zależną od odległości (ZAB-25)
  setSiren(on, volume = 1) {
    const c = this.ensure(); if (!c) return;
    if (on && !this.siren) {
      const o = c.createOscillator(); o.type = 'sawtooth';
      const lfo = c.createOscillator(); lfo.frequency.value = 1.6;
      const lg = c.createGain(); lg.gain.value = 260;
      lfo.connect(lg); lg.connect(o.frequency); o.frequency.value = 900;
      const g = c.createGain(); g.gain.value = 0;
      o.connect(g); g.connect(this.out); o.start(); lfo.start();
      this.siren = { o, lfo, g };
    }
    if (this.siren) {
      this.siren.g.gain.setTargetAtTime(on ? 0.07 * volume : 0, c.currentTime, 0.15);
      if (!on) { const s = this.siren; this.siren = null; setTimeout(() => { try { s.o.stop(); s.lfo.stop(); } catch (e) {} }, 600); }
    }
  },
};
