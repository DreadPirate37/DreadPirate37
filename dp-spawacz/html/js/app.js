'use strict';
/* ==========================================================================
   Punkt wejścia NUI – router wiadomości z Lua + tryb demo w przeglądarce
   ========================================================================== */
(() => {
  const frame = document.getElementById('frame');
  const fit = () => {
    const s = Math.min((window.innerWidth * 0.96) / W.VW, (window.innerHeight * 0.96) / W.VH);
    frame.style.setProperty('--s', s.toFixed(4));
  };
  window.addEventListener('resize', fit);
  fit();
  W.Input.attach(document.getElementById('cv'));

  window.addEventListener('message', e => {
    const d = e.data || {};
    switch (d.action) {
      case 'openGame':
        W.Game.open(d.task);
        break;
      case 'openTablet':
        W.Tablet.open(d.data);
        break;
      case 'closeTablet':
        W.Tablet.close(true);
        break;
      case 'forceClose':
        if (W.Game.active) W.Game.close(true);
        W.Tablet.close(true);
        break;
      case 'toast':
        W.toast(d.text, d.kind, d.time);
        break;
      case 'volume':
        W.Audio.volume = d.value;
        if (W.Audio.master) W.Audio.master.gain.value = d.value;
        break;
    }
  });

  window.addEventListener('keydown', e => {
    if (e.code === 'Escape' && !document.getElementById('tablet').classList.contains('hidden')) W.Tablet.close();
  });

  /* ---------------- tryb demo (poza FiveM) ---------------- */
  if (W.isFiveM) return;
  const qs = new URLSearchParams(location.search);
  W.mock = (name, data) => {
    if (name === 'finish') {
      const q = data.quality;
      const g = W.grade(q);
      return new Promise(r => setTimeout(() => r({ ok: true, pay: g === 'F' ? 0 : Math.round(600 * (0.3 + 0.9 * Math.pow(q / 100, 1.5))), grade: g, xp: Math.round(q / 2), failed: g === 'F', attemptsLeft: 1 }), 900));
    }
    if (name === 'closeGame' || name === 'abort') setTimeout(() => startDemo(), 400);
    if (name === 'tablet') return { ok: true, msg: 'Demo – akcja: ' + data.action, close: data.action !== 'waypoint' };
    return { ok: true };
  };
  const startDemo = () => {
    const proc = (qs.get('proc') || 'MMA').toUpperCase();
    const mat = qs.get('mat') || (proc === 'TIG' ? 'stainless' : 'steel');
    W.Game.open({
      token: 'demo',
      seed: Number(qs.get('seed')) || Math.floor(Math.random() * 1e9),
      type: qs.get('type') || 'crack',
      material: mat,
      process: proc,
      thickness: Number(qs.get('th')) || 6,
      position: qs.get('pos') || 'flat',
      passes: Number(qs.get('passes')) || 2,
      difficulty: Number(qs.get('diff')) || 2,
    });
  };
  document.body.classList.add('demo');
  if (qs.get('tablet')) {
    W.Tablet.open({
      profile: { level: 2, label: 'Spawacz', xp: 620, curXp: 400, nextXp: 1200, nextLabel: 'Spawacz certyfikowany', stats: { tasks: 14, earned: 8420, best: 'A' },
        unlocks: [{ ok: true, label: 'MMA', level: 1 }, { ok: true, label: 'MIG/MAG', level: 2 }, { ok: false, label: 'TIG', level: 3 }] },
      offers: [
        { id: 'a', siteLabel: 'Port – rurociąg paliwowy', tier: 2, estPay: 1840, estXp: 120, deposit: 500, tasks: [
          { typeLabel: 'Pęknięcie rury', materialLabel: 'Stal węglowa', thickness: 6, process: 'MMA', positionLabel: 'PA', passes: 2 },
          { typeLabel: 'Złącze doczołowe', materialLabel: 'Stal węglowa', thickness: 4, process: 'MAG', positionLabel: 'PF', passes: 1 }] },
      ],
    });
  } else startDemo();
})();
