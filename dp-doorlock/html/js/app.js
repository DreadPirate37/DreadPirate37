'use strict';
/* ==========================================================================
   Punkt wejścia NUI: router wiadomości z Lua, klawiatura, tryb demo
   ========================================================================== */
(() => {
  const handlers = {
    init: d => {
      document.body.dataset.theme = d.theme || 'aurora';
      DL.Audio.enabled = d.sounds !== false;
      DL.Audio.setVolume(d.volume ?? 0.55);
      DL.cfg.showNames = d.showNames !== false;
      if (d.keys) DL.cfg.keys = d.keys;
      if (d.keypad) DL.cfg.keypad = d.keypad;
    },
    chips: d => DL.Chips.update(d.list || []),
    chipMeta: d => DL.Chips.meta(d.doors || []),
    chipState: d => DL.Chips.state(d.id, d.st),
    chipFx: d => DL.Chips.fx(d.id, d.fx),
    toast: d => DL.toast(d.text, d.kind, d.time),
    sound: d => DL.Audio.play(d.name, d.vol ?? 1, d.ms),
    radial: d => DL.Radial.open(d),
    keypad: d => DL.Keypad.open(d),
    reader: d => DL.Reader.open(d),
    keys: d => DL.Keys.open(d.data),
    lockpick: d => DL.Lockpick.open(d.data),
    hack: d => DL.Hack.open(d.data),
    progress: d => DL.Progress.start(d),
    progressEnd: d => DL.Progress.end(d.ok),
    pickHud: d => DL.PickHud.show(d.show, d.count),
    admin: d => DL.Admin.open(d.data),
    adminPicked: d => DL.Admin.picked(d.leaves, d.me),
    adminState: d => DL.Admin.liveState(d.id, d.st),
    closeAll: () => DL.layer.close(true),
  };

  window.addEventListener('message', e => {
    const d = e.data;
    if (d && handlers[d.action]) handlers[d.action](d);
  });

  // klawiatura: kolejno minigry → panele → ESC
  window.addEventListener('keydown', e => {
    if (DL.Hack.key(e, true) || DL.Lockpick.key(e, true) || DL.Keypad.key(e) || DL.Radial.key(e)) { e.preventDefault(); return; }
    if (e.key === 'Escape' && DL.layer.cur) DL.layer.close();
  });
  window.addEventListener('keyup', e => { DL.Hack.key(e, false); DL.Lockpick.key(e, false); });
  window.addEventListener('contextmenu', e => e.preventDefault());

  if (DL.isFiveM) return;

  /* ==========================================================================
     TRYB DEMO – podgląd całego interfejsu w przeglądarce (bez FiveM)
     ========================================================================== */
  document.body.classList.add('demo');
  const qs = new URLSearchParams(location.search);
  if (qs.get('theme')) document.body.dataset.theme = qs.get('theme');

  const DOORS = [
    { id: 1, name: 'Wejście główne', group: 'MRPD', security: 'standard', type: 'double', st: { l: false } },
    { id: 2, name: 'Gabinet kapitana', group: 'MRPD', security: 'bio', type: 'single', st: { l: true } },
    { id: 3, name: 'Zbrojownia', group: 'MRPD', security: 'card', type: 'single', st: { l: true, a: true } },
    { id: 4, name: 'Brama garażu', group: 'MRPD', security: 'keypad', type: 'sliding', st: { l: false, t: 8000, T: 10000 } },
    { id: 5, name: 'Skarbiec – krata', group: 'Fleeca', security: 'standard', type: 'single', st: { l: false, b: true } },
    { id: 6, name: 'Cele', group: 'MRPD', security: 'standard', type: 'single', st: { l: true, d: true } },
  ];
  const scene = DL.$('#scene');
  const pos = [[0.2, 'door'], [0.42, 'door dbl'], [0.66, 'door'], [0.86, 'door gate']];
  pos.forEach(([x, cls]) => scene.append(DL.h('div.' + cls.split(' ').join('.'), { style: { left: `calc(${x * 100}% - ${cls.includes('dbl') ? 120 : cls.includes('gate') ? 165 : 75}px)`, bottom: '18%' } })));

  const place = () => {
    DL.Chips.update([
      { id: 2, x: 0.2 + 0.035, y: 0.52, s: 0.8, f: false },
      { id: 1, x: 0.42, y: 0.5, s: 1, f: true },
      { id: 3, x: 0.66 + 0.035, y: 0.52, s: 0.85, f: false },
      { id: 4, x: 0.86, y: 0.56, s: 0.75, f: false },
    ]);
  };
  const focusRot = [1, 2, 3, 4];
  let fi = 0;
  const cycle = () => {
    fi = (fi + 1) % focusRot.length;
    const base = { 1: [0.42, 0.5, 1], 2: [0.235, 0.52, 0.8], 3: [0.695, 0.52, 0.85], 4: [0.86, 0.56, 0.75] };
    DL.Chips.update(Object.entries(base).map(([id, [x, y, s]]) => ({ id: Number(id), x, y, s: focusRot[fi] === Number(id) ? 1 : s, f: focusRot[fi] === Number(id) })));
  };

  const RADIAL = [
    { id: 'use', icon: 'unlock', label: 'Otwórz', tone: 'primary' },
    { id: 'knock', icon: 'knock', label: 'Zapukaj' },
    { id: 'bell', icon: 'bell', label: 'Zadzwoń' },
    { id: 'lockpick', icon: 'pick', label: 'Wytrych', desc: 'Trudność 3/5', tone: 'crime' },
    { id: 'thermite', icon: 'fire', label: 'Ładunek termitowy', desc: 'Brak potrzebnego przedmiotu', disabled: true, tone: 'crime' },
    { id: 'lockdown', icon: 'shield', label: 'Zablokuj budynek', desc: 'MRPD', tone: 'danger' },
    { id: 'keys', icon: 'keys', label: 'Klucze', desc: 'Zarządzaj dostępem' },
    { id: 'edit', icon: 'edit', label: 'Edytuj drzwi', desc: '#1' },
  ];
  const LOGS = [
    { t: Date.now() / 1000 - 40, a: 'unlock', x: 'bio', who: 'Jan Kowalski' },
    { t: Date.now() / 1000 - 400, a: 'denied', x: 'bio', who: 'Marek Nowak' },
    { t: Date.now() / 1000 - 900, a: 'alarm', x: 'hack', who: 'Nieznany' },
    { t: Date.now() / 1000 - 1600, a: 'lock', x: 'auto', who: 'System' },
    { t: Date.now() / 1000 - 3600, a: 'key_add', x: 'Anna Zielińska', who: 'Jan Kowalski' },
    { t: Date.now() / 1000 - 7200, a: 'repair', x: 'manual', who: 'Piotr Mechanik' },
  ];
  const adminData = () => ({
    focus: 2,
    stats: { total: 6, locked: 4, broken: 1, lockdown: 1, alarm: 1 },
    keycards: { keycard_green: 1, keycard_blue: 2, keycard_red: 3, keycard_black: 4 },
    states: Object.fromEntries(DOORS.map(d => [d.id, d.st])),
    doors: DOORS.map(d => ({
      id: d.id, name: d.name, group: d.group, type: d.type, security: d.security, locked: true, distance: 2, autoLock: d.id === 4 ? 10 : 0,
      lockpick: d.id === 6 ? 5 : 0, hack: d.id === 2 ? 4 : 0, breach: d.id === 5, alarm: d.id !== 1, doorbell: d.id === 1, hideUi: false,
      pin: d.security === 'keypad' ? '1337' : undefined, cardLevel: d.security === 'card' ? 3 : undefined,
      schedule: d.id === 1 ? { open: '06:00', close: '23:00' } : undefined,
      owner: d.id === 2 ? 'char1:ab12cd34' : undefined,
      doors: [{ model: -1215222675, coords: { x: 434.7, y: -980.6, z: 30.8 } }].concat(d.type === 'double' ? [{ model: -2023754432, coords: { x: 434.7, y: -983.2, z: 30.8 } }] : []),
      access: { jobs: { police: d.id === 2 ? 3 : 0 }, gangs: {}, items: d.id === 5 ? ['klucz_skarbiec'] : [], identifiers: d.id === 2 ? { 'char1:ff00aa11': 'Anna Zielińska', 'char1:bb22cc33': 'Tomasz Wiśniewski' } : {}, public: false },
    })),
  });

  let demoPin = '1337';
  DL.mock = (name, data) => {
    const wait = (v, ms = 450) => new Promise(r => setTimeout(() => r(v), ms));
    if (name === 'keypad') {
      if (data.change) { demoPin = data.change; return wait({ ok: true, msg: 'Kod został zmieniony.' }); }
      if (data.badge) return wait({ ok: true, locked: false });
      return wait(data.pin === demoPin ? { ok: true, locked: false } : { ok: false, reason: 'wrong_pin', left: 2, msg: 'Błędny kod.' });
    }
    if (name === 'reader') return wait(Math.random() < 0.75 ? { ok: true, locked: false } : { ok: false, reason: 'denied', msg: 'Brak dostępu.' }, 600);
    if (name === 'radial') {
      const run = { use: () => openKeypad(), lockpick: () => openLockpick(), keys: () => openKeys(), edit: () => openAdmin(), knock: () => DL.Audio.play('knock'), bell: () => DL.Audio.play('bell'),
        lockdown: () => { DL.Chips.state(1, { l: true, d: true }); DL.toast('Blokada budynku MRPD: zamknięto 5 drzwi.', 'warn'); } };
      setTimeout(() => run[data.option] && run[data.option](), 200);
      return { ok: true };
    }
    if (name === 'gameDone') { setTimeout(() => DL.toast(data.success ? 'Zamek ustąpił.' : 'Nie udało się.', data.success ? 'success' : 'error'), 300); return { ok: true }; }
    if (name === 'adminPick') { setTimeout(() => DL.Admin.picked([{ model: 1557126584, coords: { x: 449.6, y: -986.4, z: 30.6 } }]), 900); return { ok: true }; }
    if (name === 'req') {
      const [id, arg] = data.args || [];
      if (data.name === 'keys_add') return wait({ ok: true, msg: 'Klucz przekazany.', id, name: 'Gabinet kapitana', holders: [...keyHolders, { id: 'char1:new' + arg, label: 'Gracz #' + arg }], logs: LOGS });
      if (data.name === 'keys_remove') return wait({ ok: true, msg: 'Klucz odebrany.', id, name: 'Gabinet kapitana', holders: keyHolders.filter(h => h.id !== arg), logs: LOGS });
      if (data.name === 'admin_logs') return wait({ ok: true, logs: LOGS }, 300);
      if (data.name === 'admin_state') {
        const st = { lock: { l: true }, unlock: { l: false }, breach: { l: false, b: true }, repair: { l: true }, alarm: { l: true, a: true }, lockdown: { l: true, d: true } }[arg];
        return wait({ ok: true, state: st });
      }
      if (data.name === 'admin_save') { const d = data.args[0]; d.id = d.id || 7; return wait({ ok: true, id: d.id, door: d, state: { l: d.locked }, msg: 'Zmiany zapisane.' }); }
      if (data.name === 'admin_delete') return wait({ ok: true, msg: 'Drzwi usunięte.' });
    }
    return { ok: true };
  };

  const keyHolders = [{ id: 'char1:ff00aa11', label: 'Anna Zielińska' }, { id: 'char1:bb22cc33', label: 'Tomasz Wiśniewski' }];
  const openKeypad = () => DL.Keypad.open({ id: 4, name: 'Brama garażu', group: 'MRPD', mode: 'use' });
  const openLockpick = (mode, model) => DL.Lockpick.open({
    seed: Math.floor(Math.random() * 1e9), difficulty: 3, maxFails: 4, knockMax: 2, stall: 0.8, spring: 0.35,
    mode: typeof mode === 'string' ? mode : qs.get('mode') || 'diy', model: model || qs.get('model') || undefined,
  });
  const openKeys = () => DL.Keys.open({ id: 2, name: 'Gabinet kapitana', holders: keyHolders, logs: LOGS });
  const openAdmin = () => DL.Admin.open(adminData());

  const bar = DL.$('#demobar');
  const btn = (ic, label, fn) => bar.append(DL.h('button', { html: `${DL.icon(ic)}${label}`, onclick: fn }));
  const sep = () => bar.append(DL.h('i.sep'));
  btn('target', 'Znaczniki', cycle);
  btn('layers', 'Menu [G]', () => DL.Radial.open({ id: 1, name: 'Wejście główne', group: 'MRPD', st: { l: true }, options: RADIAL }));
  sep();
  btn('keypad', 'PIN', openKeypad);
  btn('card', 'Karta', () => DL.Reader.open({ id: 3, name: 'Zbrojownia', group: 'MRPD', kind: 'card', level: 3 }));
  btn('finger', 'Biometria', () => DL.Reader.open({ id: 2, name: 'Gabinet kapitana', group: 'MRPD', kind: 'bio' }));
  sep();
  btn('pick', 'Spinka', () => openLockpick('diy', 'euro'));
  btn('door', 'Rozeta', () => openLockpick('diy', 'rim'));
  btn('lock', 'Kłódka', () => openLockpick('diy', 'padlock'));
  btn('keys', 'Wytrych', () => openLockpick('standard'));
  btn('target', 'Okrągły', () => openLockpick('round'));
  btn('chip', 'Hakowanie', () => DL.Hack.open({ seed: Math.floor(Math.random() * 1e9), difficulty: 3, stages: 2, time: 45 }));
  btn('fire', 'Termit', () => { DL.Progress.start({ label: 'Termit się pali…', icon: 'fire', ms: 5000 }); DL.Audio.play('sizzle', 0.6, 5000); setTimeout(() => { DL.Progress.end(true); DL.Chips.state(3, { l: false, b: true, a: true }); DL.toast('Zamek przepalony!', 'warn'); }, 5000); });
  sep();
  btn('keys', 'Klucze', openKeys);
  btn('cog', 'Panel admina', openAdmin);
  btn('alarm', 'Toasty', () => { DL.toast('Drzwi odblokowane.', 'success'); setTimeout(() => DL.toast('ALARM – Zbrojownia (MRPD)', 'alarm', 6000), 250); setTimeout(() => DL.toast('Wytrych pękł!', 'error'), 500); });
  btn('spark', 'Motyw', () => { const t = ['aurora', 'noir', 'ember', 'ice']; const b = document.body; b.dataset.theme = t[(t.indexOf(b.dataset.theme) + 1) % t.length]; DL.toast('Motyw: ' + b.dataset.theme, 'info', 1500); });

  DL.Chips.meta(DOORS);
  place();
  const open = qs.get('open');
  if (open === 'admin') openAdmin();
  else if (open === 'radial') bar.children[1].click();
  else if (open === 'keypad') openKeypad();
  else if (open === 'card') bar.children[4].click();
  else if (open === 'bio') bar.children[5].click();
  else if (open === 'lockpick') openLockpick();
  else if (open === 'hack') DL.Hack.open({ seed: 7, difficulty: 3, stages: 2, time: 45 });
  else if (open === 'keys') openKeys();
  else if (open === 'progress') { DL.Progress.start({ label: 'Termit się pali…', icon: 'fire', ms: 5000 }); }
})();
