/* dp-wlamywacz – HUD włamania (UIX-01), toasty, pasek postępu, lornetka, sygnały.
   DOM zmieniany tylko przy wiadomości z Lua; jedyne timery to odliczanie alarmu i zanik wskaźnika hałasu. */
'use strict';
const Hud = {
  st: {}, noise: 0, noiseTimer: null, alarmTimer: null, alarmLeft: 0,
  apply(d) {
    Object.assign(this.st, d);
    const s = this.st;
    if ('show' in d) $('#hud').hidden = !d.show;
    if ('house' in d) $('#hud-house').textContent = d.house || '';
    if ('room' in d) $('#hud-room').textContent = d.room || (s.inside ? '' : 'na zewnątrz');
    if ('noise' in d && d.noise !== false) this.setNoise(d.noise);
    if ('vis' in d) $('#hud-vis').style.width = (d.vis || 0) + '%';
    if ('cam' in d) {
      $('#hud-cam-row').hidden = !d.cam;
      $('#hud-cam').style.width = (d.cam || 0) + '%';
    }
    if ('alert' in d) {
      const a = $('#hud-alert');
      const map = { calm: ['calm', 'spokój'], sus: ['sus', 'coś słyszeli'], alarm: ['alarm', 'wykryty!'], call: ['call', 'dzwoni na policję'] };
      const m = map[d.alert] || map.calm;
      a.className = 'chip ' + m[0]; a.textContent = m[1];
      if (d.alert === 'sus' || d.alert === 'alarm') Snd.heart(d.alert === 'alarm' ? 0.35 : 0.2);
    }
    if ('alarm' in d) this.setAlarm(d.alarm);
    if ('police' in d) {
      const p = $('#hud-police');
      p.hidden = !d.police;
      if (d.police) p.textContent = `policja ~${d.police} s`;
    }
    if ('calling' in d) $('#hud-calling').hidden = !d.calling;
    if ('bag' in d && d.bag) $('#hud-bag').textContent = `${(+d.bag.kg || 0).toFixed(1)} / ${d.bag.cap} kg`;
    if ('carry' in d) { const c = $('#hud-carry'); c.hidden = !d.carry; c.textContent = d.carry ? '↥ ' + d.carry : ''; }
    if ('gloves' in d) $('#t-gloves').classList.toggle('on', !!d.gloves);
    if ('mask' in d) $('#t-mask').classList.toggle('on', !!d.mask);
    if ('flashlight' in d) $('#t-light').classList.toggle('on', !!d.flashlight);
    if ('hidden' in d) $('#hud-hidden').hidden = !d.hidden;
    if ('breath' in d) { $('#hud-breath-wrap').hidden = d.breath === false || d.breath === undefined; $('#hud-breath').style.width = (d.breath || 0) + '%'; }
  },
  setNoise(v) {
    this.noise = Math.max(this.noise, v);
    $('#hud-noise').style.width = clamp(this.noise, 0, 100) + '%';
    if (!this.noiseTimer) {
      this.noiseTimer = setInterval(() => {
        this.noise = Math.max(0, this.noise - 9);
        $('#hud-noise').style.width = clamp(this.noise, 0, 100) + '%';
        if (this.noise <= 0) { clearInterval(this.noiseTimer); this.noiseTimer = null; }
      }, 200);
    }
  },
  // panel alarmu: odliczanie opóźnienia wejścia z pikaniem (ZAB-11)
  setAlarm(a) {
    const el = $('#hud-alarm');
    clearInterval(this.alarmTimer); this.alarmTimer = null;
    if (!a || !a.stage || a.stage === 'idle') { el.hidden = true; return; }
    el.hidden = false;
    if (a.stage === 'disarmed') { el.className = 'chip ok'; el.textContent = 'alarm wyłączony'; return; }
    if (a.stage === 'siren') { el.className = 'chip call'; el.textContent = 'SYRENA'; return; }
    el.className = 'chip alarm';
    this.alarmLeft = Math.max(0, a.left || 0);
    const tick = () => {
      el.textContent = `alarm za ${Math.ceil(this.alarmLeft)} s`;
      Snd.beep(this.alarmLeft < 10 ? 1900 : 1500, 0.05, 0.06);
      this.alarmLeft -= 1;
      if (this.alarmLeft < 0) { clearInterval(this.alarmTimer); this.alarmTimer = null; }
    };
    tick();
    this.alarmTimer = setInterval(tick, 1000);
  },
};

function toast(text, kind = 'info', time = 5000) {
  const t = el('div', { class: 'toast ' + kind, text });
  $('#toasts').prepend(t);
  while ($('#toasts').children.length > 5) $('#toasts').lastChild.remove();
  setTimeout(() => t.remove(), time);
}

function noteToast(house, text) {
  const t = el('div', { class: 'toast note' }, el('small', { text: 'Notatnik · ' + house }), text);
  $('#toasts').prepend(t);
  setTimeout(() => t.remove(), 7000);
}

let signalTimer;
function showSignal(text, from) {
  const s = $('#signal');
  s.replaceChildren(el('b', { text }), el('span', { text: from || '' }));
  s.hidden = false;
  Snd.tone(740, 0.08, 'triangle', 0.08);
  clearTimeout(signalTimer);
  signalTimer = setTimeout(() => { s.hidden = true; }, 2600);
}

let progTimer;
function showProgress(label, time) {
  $('#p-label').textContent = label;
  const f = $('#p-fill');
  f.style.transition = 'none'; f.style.width = '0%';
  $('#progress').hidden = false;
  requestAnimationFrame(() => { f.style.transition = `width ${time}s linear`; f.style.width = '100%'; });
  clearTimeout(progTimer);
}
function endProgress() { progTimer = setTimeout(() => { $('#progress').hidden = true; }, 120); }

function binoculars(d) {
  $('#bino').hidden = !d.on;
  if (!d.on) return;
  $('#bino-target').textContent = d.target || 'wyceluj w dom';
  if (d.zoom) $('#bino-zoom').textContent = `zoom ×${d.zoom}`;
  $('#bino-prog').style.width = Math.round((d.progress || 0) * 100) + '%';
  if (d.rating) {
    const r = d.rating, star = (n) => '★'.repeat(n) + '☆'.repeat(5 - n);
    $('#bino-rating').textContent = `zabezpieczenia ${star(r.security)} · łup ${star(r.loot)} · pewność ${r.certainty}%`;
  } else if (!d.target) {
    $('#bino-rating').textContent = '';
  }
}
