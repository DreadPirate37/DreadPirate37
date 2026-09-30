/* dp-wlamywacz – router wiadomości z Lua i tryb podglądu w przeglądarce (UIX-09) */
'use strict';
Host.init();

const SOUNDS = { click: () => Snd.click(0.2), mail: () => Snd.mail(), cash: () => Snd.cash(), alert: () => Snd.alert(), sus: () => Snd.sus(), doorbell: () => Snd.doorbell() };

window.addEventListener('message', (e) => {
  const m = e.data || {};
  switch (m.action) {
    case 'hud': Hud.apply(m.data || {}); break;
    case 'toast': toast(m.text, m.kind, m.time); break;
    case 'note': noteToast(m.house, m.text); break;
    case 'signal': showSignal(m.text, m.from); break;
    case 'progress': showProgress(m.label, m.time); break;
    case 'progressEnd': endProgress(); break;
    case 'binoculars': binoculars(m); break;
    case 'game': Host.open(m.params || {}); break;
    case 'gameWarn': Host.setWarn(m.level || 0); break;
    case 'open': Win.open(m.kind, m.data); break;
    case 'update': if (Win.kind === m.kind) Win.open(m.kind, m.data); break;
    case 'close': if (!m.kind || Win.kind === m.kind) Win.close(true); break;
    case 'report': showReport(m.data); break;
    case 'siren': Snd.setSiren(!!m.on, m.volume || 1); break;
    case 'sound': if (SOUNDS[m.kind]) SOUNDS[m.kind](); break;
  }
});

window.addEventListener('keydown', (e) => {
  if (e.key === 'Escape' && Win.kind && !Host.inst) Win.close();
});

/* ------------------------------------------------------------------------
   Podgląd w przeglądarce: otwórz html/index.html (bez serwera).
   ?game=lockpick&cls=C · ?game=safe&cls=B · ?game=keypad · ?win=laptop · ?hud=1
   ------------------------------------------------------------------------ */
if (DEMO) {
  document.body.classList.add('demo-mode');
  const SAMPLE = {
    lockpick: (cls) => ({ game: 'lockpick', cls, stages: { A: 1, B: 2, C: 3, D: 1 }[cls] || 2, tol: { A: 14, B: 9, C: 5, D: 18 }[cls] || 9, fall: 45, dmg: 27, hp: 100, picks: 3, pick: 'Wytrych stalowy', seed: 123 }),
    rake: (cls) => ({ game: 'rake', cls, chance: { A: 0.55, B: 0.25, D: 0.8 }[cls] || 0.25, seed: 5 }),
    shim: () => ({ game: 'shim', seed: 7 }),
    pry: () => ({ game: 'pry', diff: 2 }),
    glass: () => ({ game: 'glass', seed: 3 }),
    keypad: () => ({ game: 'keypad', len: 4, delay: 30, attempts: 3, smudge: '0148', seed: 11 }),
    safe: (cls) => ({ game: 'safe', cls, combo: [23, 67, 5], seed: 9 }),
    fuse: () => ({ game: 'fuse', seed: 1 }),
  };
  const laptopData = {
    profile: { xp: 540, level: 2, label: 'Kieszonkowiec', next: 900, base: 300, rep: { wiktor: 90, fence_szczur: 340 }, stats: { houses: 3, loot: 2840, best: 82 }, heat: 22 },
    notebook: [
      { id: 'grove_3', label: 'Grove Street 3', active: true, stale: false, rating: { security: 3, loot: 3, certainty: 36 }, notes: [{ t: '14:20 – w domu: Anna Nowak' }, { t: 'Adam Nowak wychodzi ok. 07:40, wraca ok. 16:55' }, { t: 'Drzwi drewniane, zamek klasy B, kontaktron' }, { t: 'Naklejka ochrony: monitoring' }] },
      { id: 'forum_7', label: 'Forum Drive 7', active: false, stale: true, notes: [{ t: 'Pies: mops' }] },
    ],
    shop: { items: [{ i: 1, label: 'Wytrych z drutu', price: 60, minLevel: 1 }, { i: 7, label: 'Łom', price: 150, minLevel: 1 }, { i: 3, label: 'Wytrych tytanowy', price: 520, minLevel: 3, locked: true }], orders: [{ i: 1, n: 1, ready: false, left: 140 }] },
    mail: { tutorial: 2, tutorialMax: 5, mail: [{ from: 'Wiktor', subject: 'Szopa to dopiero początek', body: 'Dobra robota z szopą. Teraz weź lornetkę i popatrz na jakiś dom.', read: false }] },
    bag: { kg: 4.3, cap: 31, items: [{ label: 'Laptop', kg: 2.2, house: 'Grove Street 3', hot: true }, { label: 'Zegarek', kg: 0.1, house: 'Grove Street 3', hot: false }] },
  };
  const fenceData = { fence: 'Szczur', rep: 340, repLabel: 'Obcy', limit: 24000, cut: 0.22, items: [{ uid: 'a', label: 'Laptop', price: 262, from: 'bag', kg: 2.2 }, { uid: 'b', label: 'Telewizor', price: 330, from: 'trunk', kg: 18 }] };
  window.demoReply = (name, data) => {
    if (name === 'gameResult') toast('wynik gry: ' + JSON.stringify(data), data.ok ? 'good' : 'bad');
    if (name === 'window' && data.action === 'sell') return { ok: true, msg: 'Sprzedano za 592 $.', offer: { items: [] } };
    return { ok: true };
  };
  const d = $('#demo');
  d.hidden = false;
  d.append(el('b', { text: 'Podgląd NUI' }));
  for (const [k, cls] of [['lockpick', 'A'], ['lockpick', 'C'], ['rake', 'A'], ['shim'], ['pry'], ['glass'], ['keypad'], ['safe', 'B'], ['fuse']]) {
    d.append(el('button', { class: 'btn', text: `${k}${cls ? ' · ' + cls : ''}`, onclick: () => Host.open(SAMPLE[k](cls)) }));
  }
  d.append(el('button', { class: 'btn', text: 'HUD', onclick: () => Hud.apply({ show: true, inside: true, house: 'Grove Street 3', room: 'Salon', vis: 45, noise: 38, alert: 'sus', alarm: { stage: 'delay', left: 25 }, bag: { kg: 4.3, cap: 31 }, gloves: true, flashlight: true, cam: 40 }) }));
  d.append(el('button', { class: 'btn', text: 'Laptop', onclick: () => Win.open('laptop', laptopData) }));
  d.append(el('button', { class: 'btn', text: 'Paser', onclick: () => Win.open('fence', fenceData) }));
  d.append(el('button', { class: 'btn', text: 'Wiktor', onclick: () => Win.open('dialog', { title: 'Wiktor', text: 'Słyszałem, że szukasz roboty. Zacznij od szopy za przyczepą w Sandy.', options: [{ id: 'new', label: 'Nowe zlecenie' }, { id: 'close', label: 'Zamknij' }] }) }));
  d.append(el('button', { class: 'btn', text: 'Raport', onclick: () => showReport({ house: 'Grove Street 3', grade: 'A', score: 81, time: 312, items: 5, value: 1840, noise: 120, detections: 0, prints: 1, alarm: false, police: false, footage: false, xp: 88 }) }));
  d.append(el('button', { class: 'btn', text: 'Lornetka', onclick: () => binoculars({ on: true, target: 'Mirror Park, Nikola Ave 12', progress: 0.7, zoom: 2.5, rating: { security: 4, loot: 3, certainty: 24 } }) }));
  d.append(el('button', { class: 'btn', text: 'Toast + notatka', onclick: () => { toast('Zamek puścił.', 'good'); noteToast('Grove Street 3', 'Adam Nowak wychodzi ok. 07:40'); } }));
  const q = new URLSearchParams(location.search);
  if (q.get('game') && SAMPLE[q.get('game')]) Host.open(SAMPLE[q.get('game')](q.get('cls') || 'B'));
  if (q.get('win') === 'laptop') Win.open('laptop', laptopData);
  if (q.get('hud')) d.querySelector('button:nth-of-type(10)').click();
}
