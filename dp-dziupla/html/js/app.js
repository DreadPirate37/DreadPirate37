'use strict';
/* ==========================================================================
   Punkt wejścia NUI – router wiadomości z Lua + tryb demo w przeglądarce
   ========================================================================== */
(() => {
  W.Input.init();

  window.addEventListener('message', e => {
    const d = e.data || {};
    switch (d.action) {
      case 'toast': W.toast(d.text, d.kind, d.time); break;
      case 'partOpen': W.Part.open(d.part, d.ctx, d.F); break;
      case 'partPoints': W.Part.points(d.pts, d.scale); break;
      case 'partClose': W.Part.close(); break;
      case 'lockpickOpen': W.Lockpick.open(d.spec); break;
      case 'scannerOpen': W.Scanner.open(d.spec); break;
      case 'benchPick': W.BenchPick.open(d.mode, d.items); break;
      case 'benchOpen': W.Bench.open(d.spec); break;
      case 'benchClose': W.Mini.close(); W.BenchPick.close(); break;
      case 'laptopOpen': W.Laptop.open(d.data, d.tab); break;
      case 'laptopClose': W.Laptop.close(true); break;
      case 'paintOpen': W.Paint.open(d.colors, d.paint, d.papers); break;
      case 'bayHud': W.BayHud.update(d.show, d.data); break;
      case 'forceClose':
        if (W.Part.active) W.Part.close();
        W.Mini.close();
        W.Laptop.close(true);
        W.$('modal').classList.add('hidden');
        break;
    }
  });

  window.addEventListener('keydown', e => {
    if (e.code !== 'Escape') return;
    if (!W.$('modal').classList.contains('hidden')) {
      const c = W.$('bpCancel') || W.$('ppCancel');
      if (c) c.click();
      return;
    }
    if (!W.$('laptop').classList.contains('hidden')) W.Laptop.close();
  });

  /* ---------------- tryb demo (poza FiveM) ---------------- */
  if (W.isFiveM) return;
  document.body.classList.add('demo');
  const qs = new URLSearchParams(location.search);

  W.mock = (name, data) => {
    if (name === 'laptop') {
      if (data.action === 'close') return { ok: true };
      return { ok: true, msg: 'Demo – akcja: ' + data.action };
    }
    if (name === 'lockpick' || name === 'scanner') {
      W.toast(`Demo: ${name} → ${JSON.stringify(data)}`, 'info');
      setTimeout(start, 800);
      return { ok: true };
    }
    if (name === 'bench') {
      if (data.action === 'finish') { W.toast(`Demo: wynik stołu ${Math.round(data.score * 100)}%`, 'good'); setTimeout(start, 800); }
      return { ok: false };
    }
    if (name === 'part' && data.action === 'abort') { setTimeout(start, 400); return { ok: true }; }
    if (name === 'part' && data.action === 'finish') { setTimeout(start, 1400); return { ok: true }; }
    return { ok: true };
  };

  /* ---- dema części: te same typy mocowań co w config_parts.lua ---- */
  const V = (x, y) => [x, y];
  const DEMOS = {
    wheel: { label: 'Koło LP', cond: 78, value: 196, F: Array.from({ length: 5 }, (_, i) => ({ t: 'nut', size: 19 })), rust: [0.8, 0, 0.5, 0, 0],
      pts: Array.from({ length: 5 }, (_, i) => V(0.5 + Math.cos(i / 5 * Math.PI * 2 + 0.3) * 0.09, 0.47 + Math.sin(i / 5 * Math.PI * 2 + 0.3) * 0.16)) },
    radiator: { label: 'Chłodnica', cond: 64, value: 120, F: [
      { t: 'drain', fluid: 'coolant', size: 13, sets: '@coolant' }, { t: 'hose', fluid: 'coolant' }, { t: 'hose', fluid: 'coolant' }, { t: 'bolt', size: 10 }, { t: 'bolt', size: 10 }],
      pts: [V(0.6, 0.66), V(0.36, 0.36), V(0.64, 0.5), V(0.3, 0.3), V(0.7, 0.3)] },
    battery: { label: 'Akumulator', cond: 81, value: 90, F: [
      { t: 'terminal', sign: '+', size: 10 }, { t: 'terminal', sign: '-', size: 10, sets: '@batteryOff' }, { t: 'bolt', size: 13 }],
      pts: [V(0.44, 0.42), V(0.56, 0.42), V(0.5, 0.6)] },
    radio: { label: 'Radio / multimedia', cond: 90, value: 240, F: [
      { t: 'clip' }, { t: 'clip' }, { t: 'clip' }, { t: 'clip' },
      { t: 'screw', bit: 'PH2', after: [1, 2, 3, 4] }, { t: 'screw', bit: 'PH2', after: [1, 2, 3, 4] }, { t: 'screw', bit: 'PH2', after: [1, 2, 3, 4] }, { t: 'screw', bit: 'PH2', after: [1, 2, 3, 4] },
      { t: 'connector', after: [5, 6, 7, 8] }, { t: 'connector', after: [5, 6, 7, 8], sensitive: true }],
      pts: [V(0.38, 0.36), V(0.62, 0.36), V(0.38, 0.62), V(0.62, 0.62), V(0.42, 0.4), V(0.58, 0.4), V(0.42, 0.58), V(0.58, 0.58), V(0.46, 0.5), V(0.54, 0.5)] },
    airbag: { label: 'Poduszka kierowcy', cond: 88, value: 280, F: [{ t: 'screw', bit: 'T30' }, { t: 'screw', bit: 'T30' }, { t: 'connector', airbag: true, after: [1, 2] }],
      pts: [V(0.38, 0.5), V(0.62, 0.5), V(0.5, 0.58)] },
    engine: { label: 'Silnik', cond: 70, value: 1100, F: [
      { t: 'connector' }, { t: 'connector' }, { t: 'hose', fluid: 'fuel' }, { t: 'hose' },
      { t: 'bolt', size: 18 }, { t: 'bolt', size: 18 }, { t: 'bolt', size: 18 }, { t: 'bolt', size: 18 }, { t: 'hoist', after: [1, 2, 3, 4, 5, 6, 7, 8] }],
      rust: [0, 0, 0, 0, 0.7, 0, 0.5, 0.9, 0],
      pts: [V(0.4, 0.38), V(0.6, 0.36), V(0.68, 0.46), V(0.5, 0.3), V(0.34, 0.66), V(0.66, 0.66), V(0.36, 0.52), V(0.64, 0.56), V(0.5, 0.2)] },
    windscreen: { label: 'Szyba czołowa', cond: 85, value: 180, F: [{ t: 'cut', tool: 'wire', closed: true }],
      pts: [[V(0.28, 0.66), V(0.72, 0.66), V(0.66, 0.32), V(0.34, 0.32)]] },
    catalyst: { label: 'Katalizator', cond: 72, value: 560, F: [
      { t: 'connector' }, { t: 'bolt', size: 15, cut: true, fire: true }, { t: 'bolt', size: 15, cut: true, fire: true }, { t: 'bolt', size: 15, cut: true, fire: true }, { t: 'bolt', size: 15, cut: true, fire: true }],
      rust: [0, 0.9, 0.8, 0.7, 0.95], pts: [V(0.5, 0.35), V(0.3, 0.46), V(0.3, 0.56), V(0.7, 0.46), V(0.7, 0.56)] },
    vin: { label: 'Wybicie nowego VIN', cond: 100, op: true, F: Array.from({ length: 8 }, () => ({ t: 'stamp' })), ch: 'WVZ7K2DP'.split(''),
      pts: Array.from({ length: 8 }, (_, i) => V(0.36 + i * 0.04, 0.5)) },
  };

  function start() {
    if (qs.get('laptop') != null) return demoLaptop();
    if (qs.get('lockpick') != null) return W.Lockpick.open({ pins: Number(qs.get('pins')) || 5, seed: Math.floor(Math.random() * 1e9), picks: 3, shear: 0.05 });
    if (qs.get('scanner') != null) return W.Scanner.open({ seed: 4, spots: ['Zderzak przedni', 'Nadkole LP', 'Nadkole PT', 'Pod fotelem kierowcy', 'Gniazdo OBD', 'Podsufitka', 'Bagażnik – koło zapasowe', 'Zderzak tylny', 'Komora silnika', 'Pod kanapą'], spot: 1 + Math.floor(Math.random() * 10) });
    if (qs.get('bench')) return W.Bench.open({ mode: qs.get('bench'), seed: Math.floor(Math.random() * 1e9), label: 'Drzwi LP', cond: 48, cap: 20 });
    if (qs.get('paint') != null) return W.Paint.open([[0, 'Czarny'], [111, 'Biały'], [27, 'Czerwony'], [64, 'Niebieski'], [158, 'Złoty']], 400, 1500);
    if (qs.get('hud') != null) return W.BayHud.update(true, { label: 'Sultan', done: 12, total: 31, lift: 1, noise: 0.6, gate: false, mode: 'chop', flags: { '@batteryOff': true, '@oil': true } });
    const key = qs.get('part') || 'wheel';
    const dm = DEMOS[key] || DEMOS.wheel;
    const tools = { ratchet: true, screw: true, trim: true, basin: true, pliers: true, drill: true, grinder: true, wire: true, impact: true, hoist: true, stamps: true };
    W.Part.open(
      { id: key, label: dm.label, cond: dm.cond, value: dm.value, op: !!dm.op, flags: {}, F: dm.F.map((f, i) => ({ i: i + 1, rust: (dm.rust && dm.rust[i]) || 0, done: false, ch: dm.ch && dm.ch[i] })) },
      { tools, cons: { penetrant: 3, disc: 2, extractor: 2 }, fx: { speed: 1, steady: 1, quiet: 1, eye: qs.get('eye') != null }, vehicle: 'Karin Sultan (demo)', sockets: [8, 10, 13, 15, 17, 18, 19, 21, 'T50'], bits: ['PH1', 'PH2', 'T20', 'T30'] },
      dm.F,
    );
    const pts = dm.pts.map(p => (Array.isArray(p[0]) ? p.map(q => [q[0], q[1], 1]) : [[p[0], p[1], 1]]));
    W.Part.points(pts, 1.4);
  }

  function demoLaptop() {
    const items = [
      ['wheel', 'Koło', 'wheels', 'Koła i zawieszenie', 82, 196], ['engine', 'Silnik', 'engine', 'Silnik i napęd', 64, 890], ['door', 'Drzwi', 'body', 'Karoseria', 45, 120],
      ['catalyst', 'Katalizator', 'exhaust', 'Układ wydechowy', 71, 510], ['radio', 'Radio / multimedia', 'electro', 'Elektronika', 93, 250], ['seat', 'Fotel', 'interior', 'Wnętrze', 88, 160],
    ].map((x, i) => ({ u: i + 1, t: x[0], label: x[1], cat: x[2], catLabel: x[3], cond: x[4], value: x[5], vehicle: i % 2 ? 'Sultan' : 'Buffalo', regen: i === 2, reserved: i === 5 }));
    W.Laptop.open({
      profile: { level: 4, label: 'Mechanik z dziupli', xp: 2100, curXp: 1600, nextXp: 2800, nextLabel: 'Specjalista od części', points: 1, stats: { cars: 14, parts: 212, earned: 48210, contracts: 6, regen: 9, exports: 2, orders: 4 } },
      warehouse: { items, cap: 35 },
      market: { cats: [['body', 'Karoseria', 0.92], ['electro', 'Elektronika', 1.21], ['engine', 'Silnik i napęd', 1.04], ['exhaust', 'Układ wydechowy', 1.38], ['glass', 'Szyby', 0.8], ['interior', 'Wnętrze', 1.0], ['lights', 'Oświetlenie', 0.97], ['wheels', 'Koła i zawieszenie', 1.12]].map(([key, label, d]) => ({ key, label, d, hist: Array.from({ length: 12 }, (_, i) => 1 + Math.sin(i / 2 + d * 3) * 0.2) })),
        event: { label: 'Boom na katalizatory – skupy płacą jak za zboże', cat: 'exhaust', left: 2400 } },
      shop: {
        tools: [['pliers', 'Szczypce do opasek', 180, 1, true], ['drill', 'Wiertarka (do wykrętaków)', 650, 1, false], ['grinder', 'Szlifierka kątowa', 900, 2, false], ['impact', 'Klucz udarowy', 2600, 3, false], ['hoist', 'Żuraw warsztatowy', 4200, 3, false], ['stamps', 'Zestaw puncerów (przebitka)', 6500, 6, false]]
          .map(([key, label, price, minLevel, owned]) => ({ key, label, price, minLevel, owned, locked: minLevel > 4 })),
        cons: [{ key: 'penetrant', label: 'Penetrant (odrdzewiacz)', price: 35, have: 3, max: 20 }, { key: 'disc', label: 'Tarcza do szlifierki', price: 25, have: 0, max: 30 }, { key: 'lockpick', label: 'Wytrych', price: 120, have: 2, max: 10 }],
        upg: [{ key: 'shelf', label: 'Dodatkowy regał (+10 miejsc w magazynie)', price: 2500, have: 1, max: 5 }],
      },
      perks: [['speed', 'Szybkie ręce', 3, 2, 1], ['steady', 'Pewna ręka', 2, 0, 2], ['eye', 'Oko fachowca', 1, 0, 3], ['thief', 'Włamywacz', 2, 0, 4], ['contacts', 'Kontakty', 2, 0, 6]]
        .map(([key, label, ranks, rank, minLevel]) => ({ key, label, ranks, rank, minLevel, locked: minLevel > 4, desc: 'Opis umiejętności z configu.' })),
      atShop: true,
      contracts: { offers: [
        { id: 'a1', tier: 2, label: 'Sultan', model: 'sultan', reward: 1540, xp: 110, time: 2100, risk: { alarm: 0.5, tracker: 0.25 }, area: { x: 0, y: 0, z: 0 }, zone: 'Mirror Park' },
        { id: 'a2', tier: 1, label: 'Asea', model: 'asea', reward: 720, xp: 60, time: 1900, risk: { alarm: 0.3, tracker: 0 }, area: { x: 0, y: 0, z: 0 }, zone: 'La Mesa' }] },
      orders: { offers: [{ id: 'o1', client: 'Tuner z Vespucci', pay: 1980, lines: [{ t: 'wheel', n: 4, min: 60, label: 'Koło' }, { t: 'seat', n: 1, min: 45, label: 'Fotel' }], have: [1, 1], time: 2400 }] },
      exports: { minLevel: 2, locked: false, offers: [{ id: 'e1', label: 'Sportowe', pay: 5800, time: 1800, minHealth: 0.7 }] },
    }, qs.get('laptop') || 'home');
  }

  start();
})();
