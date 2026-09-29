'use strict';
/* ==========================================================================
   Etap 1 – Karta WPS i ustawienie spawarki (+ próbne zajarzenie na złomie)
   ========================================================================== */
W.Stages.setup = game => {
  const t = game.task;
  const ideal = W.ideal(t);
  const P = game.P;
  const el = document.getElementById('setup');
  const st = { ready: true };

  const state = {
    amp: Math.round(ideal.amp * (0.55 + game.rand() * 0.9)),
    pol: ['DC+', 'DC-', 'AC'][game.rand.int(0, 2)],
    sec: ideal.sec.kind === 'choice' ? ideal.sec.options[game.rand.int(0, 2)] : Math.round(ideal.sec.value * (0.5 + game.rand()) * 10) / 10,
    tests: 0,
  };
  state.amp = W.clamp(state.amp, 10, 250);
  if (ideal.sec.kind === 'knob') state.sec = W.clamp(state.sec, ideal.sec.min, ideal.sec.max);

  game.title('Karta WPS i ustawienia', 'Wylicz parametry ze ściągawki, sprawdź na złomie i zacznij');
  game.keys([['LPM + przeciągnij', 'kręć pokrętłem'], ['Kółko', 'dokładnie ±1'], ['ENTER', 'zatwierdź']]);

  const cheat = W.CHEATSHEET[t.process].map(([a, b]) => `<tr><td>${a}</td><td>${b}</td></tr>`).join('');
  const secHtml = ideal.sec.kind === 'choice'
    ? `<div class="choice" id="secChoice">${ideal.sec.options.map(o => `<button data-v="${o}">${o.toFixed(1)}</button>`).join('')}</div>`
    : `<div class="knob-wrap"><div class="knob small" id="knobSec"><i></i></div><div class="lcd small" id="lcdSec"></div></div>`;

  el.innerHTML = `
    <div class="wps">
      <div class="wps-head">KARTA TECHNOLOGICZNA WPS <span>#${String(t.seed).slice(-5)}</span></div>
      <table class="params">
        <tr><td>Zadanie</td><td>${W.esc(W.TYPES[t.type])}</td></tr>
        <tr><td>Materiał</td><td>${W.esc(game.M.label)}</td></tr>
        <tr><td>Grubość</td><td><b>${t.thickness} mm</b></td></tr>
        <tr><td>Metoda</td><td>${W.esc(P.name)}</td></tr>
        <tr><td>Pozycja</td><td>${W.esc(game.POS.label)}</td></tr>
        <tr><td>Ściegi</td><td>${t.passes} (${W.PASS_NAMES.slice(0, t.passes).join(', ')})</td></tr>
        <tr><td>Trudność</td><td>${'★'.repeat(t.difficulty)}${'☆'.repeat(5 - t.difficulty)}</td></tr>
      </table>
      <div class="wps-head sub">ŚCIĄGAWKA</div>
      <table class="cheat">${cheat}</table>
    </div>
    <div class="machine">
      <div class="brand">SPAWMAX <b>${P.label}</b> 250</div>
      <div class="panel-row">
        <div class="knob-wrap">
          <div class="lbl">Natężenie</div>
          <div class="lcd" id="lcdAmp"></div>
          <div class="knob" id="knobAmp"><i></i></div>
        </div>
        <div class="col">
          <div class="lbl">Biegunowość</div>
          <div class="pol" id="pol">${['DC+', 'DC-', 'AC'].map(p => `<button data-v="${p}">${p.replace('-', '−')}</button>`).join('')}</div>
          <div class="lbl">${ideal.sec.label} <small>[${ideal.sec.unit}]</small></div>
          ${secHtml}
        </div>
      </div>
      <div class="scrap"><canvas id="scrapCv" width="420" height="110"></canvas><div id="scrapMsg">Próbne zajarzenie pokaże, czy parametry są dobre.</div></div>
      <div class="row">
        <button class="btn" id="btnTest">Próbne zajarzenie <small id="testsLeft"></small></button>
        <button class="btn primary" id="btnGo">Zatwierdź ustawienia</button>
      </div>
    </div>`;
  el.classList.remove('hidden');

  const lcdAmp = el.querySelector('#lcdAmp');
  const knobAmp = el.querySelector('#knobAmp');
  const refresh = () => {
    lcdAmp.textContent = String(state.amp).padStart(3, '0') + ' A';
    knobAmp.firstElementChild.style.transform = `rotate(${-135 + ((state.amp - 10) / 240) * 270}deg)`;
    el.querySelectorAll('#pol button').forEach(b => b.classList.toggle('on', b.dataset.v === state.pol));
    if (ideal.sec.kind === 'choice') {
      el.querySelectorAll('#secChoice button').forEach(b => b.classList.toggle('on', Number(b.dataset.v) === state.sec));
    } else {
      el.querySelector('#lcdSec').textContent = state.sec.toFixed(1);
      const s = ideal.sec;
      el.querySelector('#knobSec').firstElementChild.style.transform = `rotate(${-135 + ((state.sec - s.min) / (s.max - s.min)) * 270}deg)`;
    }
    el.querySelector('#testsLeft').textContent = `(${Math.max(0, 3 - state.tests)}/3)`;
  };

  const bindKnob = (knob, get, set, step, fine) => {
    let drag = null;
    knob.addEventListener('mousedown', e => {
      drag = { y: e.clientY, v: get() };
      e.preventDefault();
    });
    const mm = e => {
      if (!drag) return;
      set(drag.v + Math.round((drag.y - e.clientY) / 3) * step);
      refresh();
    };
    const mu = () => (drag = null);
    window.addEventListener('mousemove', mm);
    window.addEventListener('mouseup', mu);
    knob.addEventListener('wheel', e => {
      set(get() + (e.deltaY < 0 ? fine : -fine));
      W.Audio.tick();
      refresh();
    }, { passive: true });
    return () => {
      window.removeEventListener('mousemove', mm);
      window.removeEventListener('mouseup', mu);
    };
  };
  const unb = [bindKnob(knobAmp, () => state.amp, v => (state.amp = W.clamp(Math.round(v), 10, 250)), 2, 1)];
  if (ideal.sec.kind === 'knob') {
    const s = ideal.sec;
    const knobSec = el.querySelector('#knobSec');
    unb.push(bindKnob(knobSec, () => state.sec, v => (state.sec = W.clamp(Math.round(v * 10) / 10, s.min, s.max)), s.step, s.fine));
  } else {
    el.querySelectorAll('#secChoice button').forEach(b => (b.onclick = () => { state.sec = Number(b.dataset.v); W.Audio.click(); refresh(); }));
  }
  el.querySelectorAll('#pol button').forEach(b => (b.onclick = () => { state.pol = b.dataset.v; W.Audio.thud(0.3, 600); refresh(); }));

  /* ------------ ocena ustawień ------------ */
  const evaluate = () => {
    const ampF = state.amp / ideal.amp;
    const ampS = W.gauss(ampF - 1, 0.15);
    const polOk = state.pol === ideal.pol;
    let secS, secF;
    if (ideal.sec.kind === 'choice') {
      secF = state.sec / ideal.sec.value;
      secS = state.sec === ideal.sec.value ? 1 : 0.35;
    } else if (ideal.sec.tolRel) {
      secF = state.sec / ideal.sec.value;
      secS = W.gauss(secF - 1, ideal.sec.tolRel * 1.4);
    } else {
      secF = 1 + (state.sec - ideal.sec.value) / 10;
      secS = W.gauss(state.sec - ideal.sec.value, ideal.sec.tolAbs * 1.4);
    }
    return { ampF, ampS, polOk, secF, secS };
  };

  const verdict = e => {
    const msgs = [];
    if (!e.polOk) {
      if (t.process === 'TIG' && state.pol === 'DC+') msgs.push('Wolfram się topi i kulkuje – zła biegunowość!');
      else if (t.material === 'aluminium' && t.process === 'TIG') msgs.push('Brak czyszczenia tlenków, jeziorko „brudne” – aluminium wymaga AC.');
      else msgs.push('Łuk błądzi i mocno pryska – sprawdź biegunowość.');
    }
    if (e.ampF < 0.85) msgs.push('Łuk zimny i niestabilny, spoina wąska i wypukła – za mało prądu.');
    else if (e.ampF < 0.94) msgs.push('Trochę zimno – przetop płytki.');
    else if (e.ampF <= 1.06) msgs.push('Jeziorko stabilne, ładny przetop – natężenie w punkt.');
    else if (e.ampF <= 1.16) msgs.push('Trochę gorąco – jeziorko rzadkie, ryzyko podtopień.');
    else msgs.push('Za gorąco! Przepala materiał.');
    if (ideal.sec.kind === 'choice' && state.sec !== ideal.sec.value) {
      msgs.push(state.sec < ideal.sec.value ? 'Elektroda za cienka do tej grubości.' : 'Elektroda za gruba – trudno prowadzić jeziorko.');
    } else if (ideal.sec.kind === 'knob' && e.secS < 0.7) {
      if (t.process === 'MAG') msgs.push(e.secF < 1 ? 'Drut się przepala do końcówki – posuw za wolny.' : 'Drut stuka o materiał – posuw za szybki.');
      else msgs.push(state.sec < ideal.sec.value ? 'Spoina szara i utleniona – za mało argonu.' : 'Turbulencje gazu, pory – za duży przepływ.');
    }
    return msgs;
  };

  /* animacja próbnego ściegu na złomie */
  const scrap = el.querySelector('#scrapCv');
  const sg = scrap.getContext('2d');
  const drawScrapBase = () => {
    const gr = sg.createLinearGradient(0, 0, 0, 110);
    gr.addColorStop(0, game.M.col[2]);
    gr.addColorStop(1, game.M.col[0]);
    sg.fillStyle = gr;
    sg.fillRect(0, 0, 420, 110);
  };
  drawScrapBase();
  let testAnim = null;

  el.querySelector('#btnTest').onclick = () => {
    if (state.tests >= 3 || testAnim) return;
    state.tests++;
    refresh();
    drawScrapBase();
    const e = evaluate();
    const wBase = W.clamp(7 * Math.pow(e.ampF, 1.4), 3, 16);
    let x = 20;
    const msgEl = el.querySelector('#scrapMsg');
    msgEl.textContent = '…';
    const step = () => {
      const bad = (e.polOk ? 0 : 1) + Math.abs(e.ampF - 1) * 3;
      W.Audio.arc(true, t.process, bad);
      for (let k = 0; k < 3; k++) {
        const y = 55 + (Math.random() - 0.5) * (2 + bad * 4);
        const w = wBase * (0.9 + Math.random() * 0.2);
        const cols = e.ampF > 1.16 ? ['#fff', '#8a8f94', '#3a3e42'] : game.M.bead;
        W.ripple(sg, x, y, 0, w, cols);
        if (e.ampF > 1.2 && Math.random() < 0.05) W.hole(sg, x, y, 3);
        if (Math.random() < bad * 0.25) {
          sg.fillStyle = '#2d3033';
          sg.beginPath();
          sg.arc(x + (Math.random() - 0.5) * 40, 55 + (Math.random() - 0.5) * 70, 1 + Math.random() * 1.6, 0, 6.3);
          sg.fill();
        }
        x += 2.2;
      }
      if (x < 400) testAnim = requestAnimationFrame(step);
      else {
        testAnim = null;
        W.Audio.arc(false, t.process);
        msgEl.innerHTML = verdict(e).map(m => `<div>${W.esc(m)}</div>`).join('');
      }
    };
    step();
  };

  const confirm = () => {
    if (testAnim) return;
    const e = evaluate();
    let score = 100 * (0.55 * e.ampS + 0.25 * (e.polOk ? 1 : 0) + 0.2 * e.secS) - Math.max(0, state.tests - 2) * 3;
    game.setup = {
      ampF: e.ampF,
      polOk: e.polOk,
      secF: e.secF,
      secOk: e.secS > 0.7,
      poolMul: ideal.sec.kind === 'choice' ? W.clamp(state.sec / ideal.sec.value, 0.75, 1.3) : 1,
    };
    el.classList.add('hidden');
    W.Audio.good();
    game.done('setup', score, { msg: 'Parametry zapisane', delay: 500 });
    st.update = () => {};
  };
  el.querySelector('#btnGo').onclick = confirm;
  refresh();

  st.update = () => {
    if (W.Input.hit('Enter')) confirm();
  };
  st.render = g => {
    game.drawWork(g);
    g.fillStyle = 'rgba(5,7,9,0.72)';
    g.fillRect(0, 0, W.VW, W.VH);
  };
  st.destroy = () => {
    unb.forEach(f => f());
    if (testAnim) cancelAnimationFrame(testAnim);
    el.innerHTML = '';
  };
  return st;
};
