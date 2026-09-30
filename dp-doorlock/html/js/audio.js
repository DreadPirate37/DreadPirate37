'use strict';
/* ==========================================================================
   Dźwięki syntezowane w WebAudio – bez plików. Kontekst tworzony leniwie,
   bufor szumu generowany raz i współdzielony.
   ========================================================================== */
DL.Audio = (() => {
  let ctx = null, master = null, noise = null;
  const A = { enabled: true, volume: 0.55 };

  const init = () => {
    if (ctx) return ctx;
    const AC = window.AudioContext || window.webkitAudioContext;
    if (!AC) return null;
    ctx = new AC();
    master = ctx.createGain();
    master.gain.value = A.volume;
    master.connect(ctx.destination);
    const len = ctx.sampleRate;
    noise = ctx.createBuffer(1, len, ctx.sampleRate);
    const d = noise.getChannelData(0);
    for (let i = 0; i < len; i++) d[i] = Math.random() * 2 - 1;
    return ctx;
  };

  /** ton z obwiednią */
  const tone = (t0, { f = 440, f2, type = 'sine', dur = 0.12, vol = 0.3, attack = 0.004, q } = {}, out) => {
    const o = ctx.createOscillator(), g = ctx.createGain();
    o.type = type;
    o.frequency.setValueAtTime(f, t0);
    if (f2) o.frequency.exponentialRampToValueAtTime(Math.max(20, f2), t0 + dur);
    g.gain.setValueAtTime(0.0001, t0);
    g.gain.exponentialRampToValueAtTime(vol, t0 + attack);
    g.gain.exponentialRampToValueAtTime(0.0001, t0 + dur);
    o.connect(g);
    if (q) { const f3 = ctx.createBiquadFilter(); f3.type = 'bandpass'; f3.frequency.value = f; f3.Q.value = q; g.connect(f3); f3.connect(out); }
    else g.connect(out);
    o.start(t0);
    o.stop(t0 + dur + 0.02);
  };

  /** krótki szum przez filtr – kliknięcia, uderzenia, syk */
  const burst = (t0, { dur = 0.05, vol = 0.4, type = 'bandpass', f = 2000, q = 1, f2 } = {}, out) => {
    const s = ctx.createBufferSource(), fl = ctx.createBiquadFilter(), g = ctx.createGain();
    s.buffer = noise;
    fl.type = type;
    fl.frequency.setValueAtTime(f, t0);
    if (f2) fl.frequency.exponentialRampToValueAtTime(f2, t0 + dur);
    fl.Q.value = q;
    g.gain.setValueAtTime(vol, t0);
    g.gain.exponentialRampToValueAtTime(0.0001, t0 + dur);
    s.connect(fl); fl.connect(g); g.connect(out);
    s.start(t0, Math.random() * 0.5);
    s.stop(t0 + dur + 0.02);
  };

  const S = {
    lock: (t, o) => { burst(t, { f: 1800, q: 3, dur: 0.035, vol: 0.5 }, o); burst(t + 0.07, { f: 900, q: 2, dur: 0.06, vol: 0.6 }, o); tone(t + 0.07, { f: 180, f2: 90, dur: 0.08, vol: 0.25 }, o); },
    unlock: (t, o) => { burst(t, { f: 2600, q: 4, dur: 0.03, vol: 0.45 }, o); burst(t + 0.05, { f: 1400, q: 3, dur: 0.04, vol: 0.4 }, o); tone(t + 0.1, { f: 660, f2: 990, dur: 0.12, vol: 0.12, type: 'triangle' }, o); },
    deny: (t, o) => { tone(t, { f: 150, type: 'square', dur: 0.16, vol: 0.13 }, o); tone(t + 0.2, { f: 120, type: 'square', dur: 0.24, vol: 0.13 }, o); },
    beep: (t, o) => tone(t, { f: 1650, type: 'square', dur: 0.06, vol: 0.06 }, o),
    ok: (t, o) => { tone(t, { f: 880, dur: 0.12, vol: 0.18 }, o); tone(t + 0.1, { f: 1320, dur: 0.22, vol: 0.18 }, o); },
    error: (t, o) => { tone(t, { f: 320, f2: 180, type: 'sawtooth', dur: 0.3, vol: 0.1 }, o); },
    knock: (t, o) => { for (let i = 0; i < 3; i++) { const tt = t + i * 0.24; tone(tt, { f: 110, f2: 60, dur: 0.14, vol: 0.7 }, o); burst(tt, { f: 500, q: 0.8, dur: 0.07, vol: 0.5, type: 'lowpass' }, o); } },
    bell: (t, o) => { tone(t, { f: 784, dur: 1.1, vol: 0.22, attack: 0.002 }, o); tone(t, { f: 1568, dur: 0.6, vol: 0.05 }, o); tone(t + 0.55, { f: 622, dur: 1.4, vol: 0.22, attack: 0.002 }, o); tone(t + 0.55, { f: 1244, dur: 0.7, vol: 0.05 }, o); },
    pin: (t, o) => burst(t, { f: 4200, q: 6, dur: 0.02, vol: 0.25 }, o),
    set: (t, o) => { burst(t, { f: 3200, q: 8, dur: 0.03, vol: 0.55 }, o); tone(t, { f: 2400, dur: 0.05, vol: 0.06, type: 'triangle' }, o); },
    snap: (t, o) => { burst(t, { f: 5000, q: 2, dur: 0.05, vol: 0.8 }, o); burst(t + 0.02, { f: 1200, q: 1, dur: 0.12, vol: 0.4 }, o); },
    turn: (t, o) => { burst(t, { f: 700, f2: 300, q: 2, dur: 0.35, vol: 0.35 }, o); burst(t + 0.34, { f: 1500, q: 4, dur: 0.05, vol: 0.6 }, o); },
    slam: (t, o) => { tone(t, { f: 90, f2: 40, dur: 0.4, vol: 0.9 }, o); burst(t, { f: 300, q: 0.7, dur: 0.35, vol: 0.9, type: 'lowpass' }, o); burst(t + 0.05, { f: 2500, q: 1, dur: 0.2, vol: 0.3 }, o); },
    scan: (t, o) => tone(t, { f: 400, f2: 1600, dur: 1.2, vol: 0.05, type: 'sine' }, o),
    swipe: (t, o) => burst(t, { f: 1200, f2: 3500, q: 1.5, dur: 0.18, vol: 0.25 }, o),
    glitch: (t, o) => { for (let i = 0; i < 4; i++) tone(t + i * 0.04, { f: 200 + Math.random() * 1800, type: 'square', dur: 0.03, vol: 0.05 }, o); },
    lockin: (t, o) => { tone(t, { f: 660, dur: 0.1, vol: 0.12, type: 'triangle' }, o); tone(t + 0.08, { f: 990, dur: 0.1, vol: 0.12, type: 'triangle' }, o); tone(t + 0.16, { f: 1320, dur: 0.18, vol: 0.12, type: 'triangle' }, o); },
    alarm: (t, o) => { for (let i = 0; i < 4; i++) tone(t + i * 0.3, { f: 880, f2: 660, type: 'sawtooth', dur: 0.28, vol: 0.07 }, o); },
    sizzle: (t, o, ms = 3000) => burst(t, { f: 5000, q: 0.5, dur: ms / 1000, vol: 0.25, type: 'highpass' }, o),
    tick: (t, o) => tone(t, { f: 2000, dur: 0.015, vol: 0.05, type: 'square' }, o),
    open: (t, o) => { tone(t, { f: 520, dur: 0.1, vol: 0.08, type: 'triangle' }, o); tone(t + 0.06, { f: 780, dur: 0.14, vol: 0.08, type: 'triangle' }, o); },
  };

  A.play = (name, vol = 1, ms) => {
    if (!A.enabled || !S[name]) return;
    if (!init()) return;
    if (ctx.state === 'suspended') ctx.resume();
    const g = ctx.createGain();
    g.gain.value = DL.clamp(vol, 0, 1.5);
    g.connect(master);
    S[name](ctx.currentTime + 0.005, g, ms);
    setTimeout(() => g.disconnect(), (ms || 2000) + 800);
  };
  A.setVolume = v => { A.volume = v; if (master) master.gain.value = v; };
  return A;
})();
