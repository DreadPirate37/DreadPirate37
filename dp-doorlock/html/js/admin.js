'use strict';
/* ==========================================================================
   Panel administratora: lista drzwi, statystyki, edytor z zakładkami,
   wybór drzwi celownikiem, szybkie akcje stanu, dziennik.
   Edytujemy kopię roboczą (draft) – zapis wysyła całość do serwera,
   który ją normalizuje i rozsyła klientom.
   ========================================================================== */
DL.Admin = (() => {
  let A = null;   // { box, doors: Map, states, stats, sel, draft, dirty, tab, filter, group, pickFor }

  const TYPES = [['single', 'door', 'Pojedyncze'], ['double', 'double', 'Podwójne'], ['sliding', 'sliding', 'Brama'], ['garage', 'garage', 'Garaż']];
  const SECS = [
    ['standard', 'keys', 'Klucz', 'Praca, gang, przedmiot lub klucz cyfrowy'],
    ['keypad', 'keypad', 'Klawiatura', 'Kod PIN + identyfikator służbowy'],
    ['card', 'card', 'Karta', 'Karta dostępu o minimalnym poziomie'],
    ['bio', 'finger', 'Biometria', 'Skaner linii papilarnych'],
  ];
  const TYPE_ICON = { single: 'door', double: 'double', sliding: 'sliding', garage: 'garage' };
  const SEC_ICON = { standard: 'keys', keypad: 'keypad', card: 'card', bio: 'finger' };
  const TYPE_LABEL = { single: 'pojedyncze', double: 'podwójne', sliding: 'brama', garage: 'garaż' };
  const TABS = [['general', 'door', 'Ogólne'], ['access', 'keys', 'Dostęp'], ['security', 'shield', 'Ochrona'], ['auto', 'clock', 'Automatyka'], ['log', 'log', 'Stan i dziennik']];

  const clone = o => JSON.parse(JSON.stringify(o));
  const stCls = st => (!st ? 's-locked' : st.d ? 's-lockdown' : st.b ? 's-broken' : st.l ? 's-locked' : 's-open');
  const stTxt = st => (!st ? 'Zamknięte' : st.d ? 'Blokada' : st.b ? 'Wyłamane' : st.l ? 'Zamknięte' : 'Otwarte');
  const blank = leaves => ({
    name: 'Nowe drzwi', group: '', type: leaves && leaves.length > 1 ? 'double' : 'single', doors: leaves || [], security: 'standard', locked: true,
    distance: 2, autoLock: 0, lockpick: 0, lockModel: 'euro', hack: 0, breach: false, alarm: false, doorbell: false, hideUi: false,
    access: { jobs: {}, gangs: {}, items: [], identifiers: {}, public: false },
  });

  /* ---------------- szkielet ---------------- */
  const open = data => {
    const box = DL.h('div.admin');
    box.innerHTML = `
      <aside class="ad-side">
        <div class="brand"><div class="logo">${DL.padlock()}</div><div><b>Doorlock</b><span>Panel zarządzania zamkami</span></div></div>
        <div class="ad-search">${DL.icon('search')}<input class="inp" placeholder="Szukaj drzwi, grupy, #id…"></div>
        <div class="groups"></div>
        <div class="dlist"></div>
        <div class="ad-new"><button class="btn pri">${DL.icon('target')}Dodaj drzwi celownikiem</button></div>
      </aside>
      <main class="ad-main">
        <div class="ad-top"><div class="stats"></div><button class="ad-close">${DL.icon('x')}</button></div>
        <div class="ad-view"></div>
      </main>`;
    A = { box, doors: new Map(), states: data.states || {}, stats: data.stats || {}, sel: null, draft: null, dirty: false, tab: 'general', filter: '', group: '*', keycards: data.keycards || {} };
    for (const d of data.doors || []) A.doors.set(d.id, d);
    DL.$('.ad-search input', box).addEventListener('input', e => { A.filter = e.target.value.toLowerCase(); renderList(); });
    DL.$('.ad-new .btn', box).onclick = () => pick(null);
    DL.$('.ad-close', box).onclick = () => DL.layer.close();
    DL.layer.open('admin', box, () => { A = null; });
    fit();
    renderStats();
    renderGroups();
    renderList();
    if (data.focus && A.doors.has(data.focus)) select(data.focus); else renderView();
  };

  const fit = () => {
    if (!A) return;
    const s = Math.min(1, (window.innerWidth * 0.96) / 1240, (window.innerHeight * 0.94) / 760);
    A.box.style.setProperty('--as', s.toFixed(3));
  };
  window.addEventListener('resize', fit);

  /* ---------------- statystyki ---------------- */
  const renderStats = () => {
    const s = A.stats;
    const open = (s.total || 0) - (s.locked || 0);
    DL.$('.stats', A.box).innerHTML = [
      ['', 'layers', s.total || 0, 'Drzwi'],
      ['c-locked', 'lock', s.locked || 0, 'Zamknięte'],
      ['c-open', 'unlock', open, 'Otwarte'],
      ['c-broken', 'bolt', s.broken || 0, 'Wyłamane'],
      ['c-alarm', 'alarm', (s.alarm || 0) + (s.lockdown || 0), 'Alarmy'],
    ].map(([c, ic, n, l]) => `<div class="stat ${c}"><div class="si">${DL.icon(ic)}</div><div><b>${n}</b><span>${l}</span></div></div>`).join('');
  };
  const recount = () => {
    const s = { total: A.doors.size, locked: 0, broken: 0, lockdown: 0, alarm: 0 };
    for (const [id] of A.doors) {
      const st = A.states[id];
      if (!st || st.l) s.locked++;
      if (st && st.b) s.broken++;
      if (st && st.d) s.lockdown++;
      if (st && st.a) s.alarm++;
    }
    A.stats = s;
    renderStats();
  };

  /* ---------------- lista ---------------- */
  const groupsOf = () => {
    const m = new Map();
    for (const [, d] of A.doors) if (d.group) m.set(d.group, (m.get(d.group) || 0) + 1);
    return [...m.entries()].sort((a, b) => a[0].localeCompare(b[0]));
  };
  const renderGroups = () => {
    const el = DL.$('.groups', A.box);
    const gs = groupsOf();
    el.innerHTML = '';
    const mk = (key, label, n) => el.append(DL.h('button' + (A.group === key ? '.on' : ''), { html: `${DL.esc(label)}<em>${n}</em>`, onclick: () => { A.group = key; renderGroups(); renderList(); } }));
    mk('*', 'Wszystkie', A.doors.size);
    gs.forEach(([g, n]) => mk(g, g, n));
  };
  const renderList = () => {
    const el = DL.$('.dlist', A.box);
    const f = A.filter;
    const rows = [...A.doors.values()].filter(d => {
      if (A.group !== '*' && d.group !== A.group) return false;
      if (!f) return true;
      return d.name.toLowerCase().includes(f) || (d.group || '').toLowerCase().includes(f) || ('#' + d.id) === f;
    }).sort((a, b) => (a.group || '').localeCompare(b.group || '') || a.name.localeCompare(b.name));
    el.innerHTML = '';
    if (!rows.length) { el.innerHTML = `<div class="empty">${DL.icon('search')}Nic nie znaleziono</div>`; return; }
    const frag = document.createDocumentFragment();
    for (const d of rows) {
      const st = A.states[d.id];
      const b = DL.h(`button.drow.${stCls(st)}${st && st.a ? '.alarm' : ''}${A.sel === d.id ? '.on' : ''}`, { 'data-id': d.id, onclick: () => select(d.id) });
      b.innerHTML = `<div class="dic">${DL.icon(TYPE_ICON[d.type] || 'door')}</div><div class="nm"><b>${DL.esc(d.name)}</b><span>${DL.esc(d.group || 'bez grupy')} · #${d.id}</span></div><span class="sec${d.security !== 'standard' ? ' el' : ''}">${DL.icon(SEC_ICON[d.security])}</span>`;
      frag.append(b);
    }
    el.append(frag);
  };

  /* ---------------- wybór / widok ---------------- */
  const select = id => {
    A.sel = id;
    A.draft = clone(A.doors.get(id));
    A.dirty = false;
    DL.$$('.drow', A.box).forEach(r => r.classList.toggle('on', Number(r.dataset.id) === id));
    renderView();
  };

  const renderView = () => {
    const view = DL.$('.ad-view', A.box);
    view.className = 'ad-view';
    view.style.cssText = 'flex:1;display:flex;flex-direction:column;min-height:0';
    if (!A.draft) {
      view.innerHTML = `<div class="ad-empty"><div><div class="art">${DL.padlock()}</div><b>Wybierz drzwi z listy</b><p>albo dodaj nowe – wyceluj w drzwi w grze, a edytor sam rozpozna model, pozycję i skrzydła.</p></div></div>`;
      const b = DL.h('button.btn.pri', { html: `${DL.icon('target')}Wybierz drzwi celownikiem`, onclick: () => pick(null) });
      DL.$('.ad-empty > div', view).append(b);
      return;
    }
    const d = A.draft, st = A.states[d.id];
    view.innerHTML = `
      <div class="editor">
        <div class="ed-head">
          <div class="preview"></div>
          <div class="ed-title"><b></b><span></span></div>
          <div class="ed-actions"></div>
        </div>
        <div class="tabs" style="margin:16px 22px 0"></div>
        <div class="ed-body"></div>
        <div class="ed-foot"><button class="btn bad del">${DL.icon('trash')}Usuń</button><span class="sp"></span><span class="dirty">Niezapisane zmiany</span><button class="btn ghost rev">Cofnij</button><button class="btn pri save">${DL.icon('check')}${d.id ? 'Zapisz zmiany' : 'Utwórz drzwi'}</button></div>
      </div>`;
    const acts = DL.$('.ed-actions', view);
    if (d.doors && d.doors[0]) acts.append(DL.h('button.btn.sm', { html: `${DL.icon('pin')}Teleport`, onclick: () => { DL.post('adminTp', { coords: d.doors[0].coords }); DL.toast('Teleportowano do drzwi', 'info', 2000); } }));
    if (d.id) acts.append(DL.h('button.btn.sm', { html: `${DL.icon(st && st.l ? 'unlock' : 'lock')}${st && st.l ? 'Otwórz' : 'Zamknij'}`, onclick: () => setState(st && st.l ? 'unlock' : 'lock') }));
    const tabs = DL.$('.tabs', view);
    TABS.forEach(([k, ic, l]) => {
      if (k === 'log' && !d.id) return;
      tabs.append(DL.h('button' + (A.tab === k ? '.on' : ''), { html: `${DL.icon(ic)}${l}`, onclick: () => { A.tab = k; renderView(); } }));
    });
    if (!d.id && A.tab === 'log') A.tab = 'general';
    DL.$('.del', view).style.visibility = d.id ? 'visible' : 'hidden';
    DL.$('.del', view).onclick = askDelete;
    DL.$('.rev', view).onclick = () => { if (d.id) select(d.id); else { A.draft = null; renderView(); } };
    DL.$('.save', view).onclick = save;
    head();
    body();
    markDirty(A.dirty);
  };

  const head = () => {
    const view = DL.$('.ad-view', A.box), d = A.draft, st = A.states[d.id] || { l: d.locked };
    const prev = DL.$('.preview', view);
    prev.innerHTML = '';
    const chip = DL.h(`div.chip.${stCls(st)}.f${st.a ? '.alarm' : ''}`);
    const secIc = { keypad: 'keypad', card: 'card', bio: 'finger' }[d.security];
    chip.innerHTML = `<div class="chip-ico">${DL.padlock()}<div class="chip-sec">${secIc ? DL.icon(secIc) : ''}</div></div>`;
    prev.append(chip);
    DL.$('.ed-title b', view).textContent = d.name || 'Bez nazwy';
    DL.$('.ed-title span', view).innerHTML = `${d.id ? `<code>#${d.id}</code>` : '<code>nowe</code>'}<span class="pill ${stCls(st)}">${stTxt(st)}</span>${DL.esc(d.group || 'bez grupy')} · ${TYPE_LABEL[d.type]}`;
  };

  const markDirty = on => {
    A.dirty = on;
    const f = DL.$('.ed-foot', A.box);
    if (f) f.classList.toggle('is-dirty', on);
  };
  const change = (fn, rerender) => { fn(A.draft); markDirty(true); head(); if (rerender) body(); };

  /* ---------------- kontrolki ---------------- */
  const field = (label, ctrl, opts = {}) => {
    const f = DL.h('div.field' + (opts.full ? '.full' : ''));
    f.append(DL.h('label', { html: `<span>${label}</span>${opts.em ? `<em>${opts.em}</em>` : ''}` }), ctrl);
    if (opts.hint) f.append(DL.h('div.hint', { text: opts.hint }));
    return f;
  };
  const input = (val, on, attrs = {}) => {
    const i = DL.h('input.inp' + (attrs.mono ? '.mono' : ''), { value: val ?? '', placeholder: attrs.ph || '', maxlength: attrs.max || 64, type: attrs.type || 'text', list: attrs.list });
    i.addEventListener('input', () => on(i.value));
    i.addEventListener('keydown', e => e.stopPropagation());
    return i;
  };
  const seg = (items, val, on) => {
    const s = DL.h('div.seg');
    items.forEach(([k, ic, l]) => {
      const b = DL.h('button' + (val === k ? '.on' : ''), { html: `${ic ? DL.icon(ic) : ''}${l}` });
      b.onclick = () => { DL.$$('button', s).forEach(x => x.classList.remove('on')); b.classList.add('on'); on(k); };
      s.append(b);
    });
    return s;
  };
  const sw = (checked, on) => {
    const l = DL.h('label.sw');
    const i = DL.h('input', { type: 'checkbox' });
    i.checked = !!checked;
    i.addEventListener('change', () => { on(i.checked); DL.Audio.play('tick', 0.6); });
    l.append(i, DL.h('i'));
    return l;
  };
  const rowSw = (icon, title, desc, checked, on) => {
    const r = DL.h('div.row-sw');
    r.innerHTML = `${DL.icon(icon, 'big')}<div class="tx"><b>${title}</b><span>${desc}</span></div>`;
    r.append(sw(checked, on));
    return r;
  };
  const range = (val, min, max, step, on, fmt) => {
    const wrap = DL.h('div');
    const r = DL.h('input.rng', { type: 'range', min, max, step, value: val });
    const paint = () => r.style.setProperty('--v', ((r.value - min) / (max - min)) * 100 + '%');
    r.addEventListener('input', () => { paint(); on(Number(r.value)); if (fmt) fmt(Number(r.value)); });
    paint();
    wrap.append(r);
    return wrap;
  };
  /** tagi: mapa {nazwa: grade} albo lista ['a','b'] */
  const tags = (value, isMap, on, ph) => {
    const box = DL.h('div.tags');
    const draw = () => {
      box.innerHTML = '';
      const entries = isMap ? Object.entries(value) : value.map(v => [v]);
      entries.forEach(([k, g]) => {
        const t = DL.h('span.tag', { html: `${DL.esc(k)}${isMap ? ` <em>≥${g}</em>` : ''}` });
        t.append(DL.h('button', { html: DL.icon('x'), onclick: () => { if (isMap) delete value[k]; else value.splice(value.indexOf(k), 1); on(value); draw(); } }));
        box.append(t);
      });
      const i = DL.h('input', { placeholder: ph });
      i.addEventListener('keydown', e => {
        e.stopPropagation();
        if (e.key !== 'Enter' && e.key !== ',') return;
        e.preventDefault();
        const raw = i.value.trim().toLowerCase();
        if (!raw) return;
        if (isMap) {
          const [n, g] = raw.split(':');
          if (n) value[n.replace(/[^a-z0-9_-]/g, '')] = Math.max(0, parseInt(g, 10) || 0);
        } else if (!value.includes(raw)) value.push(raw.replace(/[^a-z0-9_-]/g, ''));
        on(value);
        draw();
        DL.$('input', box).focus();
      });
      box.append(i);
    };
    draw();
    return box;
  };

  /* ---------------- zakładki ---------------- */
  const body = () => {
    const el = DL.$('.ed-body', A.box);
    if (!el) return;
    el.innerHTML = '';
    const d = A.draft;
    const g = DL.h('div.grid2');
    el.append(g);

    if (A.tab === 'general') {
      g.append(field('Nazwa', input(d.name, v => change(x => (x.name = v)), { max: 48 })));
      const dl = DL.h('datalist#adGroups', { html: groupsOf().map(([k]) => `<option value="${DL.esc(k)}">`).join('') });
      g.append(field('Grupa / budynek', input(d.group, v => change(x => (x.group = v)), { max: 32, ph: 'np. MRPD', list: 'adGroups' }), { hint: 'Grupa służy do blokady całego budynku i filtrowania listy.' }), dl);
      g.append(field('Rodzaj drzwi', seg(TYPES, d.type, v => change(x => (x.type = v))), { full: true }));
      g.append(field('Stan początkowy', seg([['locked', 'lock', 'Zamknięte'], ['open', 'unlock', 'Otwarte']], d.locked ? 'locked' : 'open', v => change(x => (x.locked = v === 'locked')))));
      const dv = DL.h('em', { text: d.distance.toFixed(1) + ' m' });
      const fd = field('Zasięg interakcji', range(d.distance, 0.5, 12, 0.5, v => change(x => (x.distance = v)), v => (dv.textContent = v.toFixed(1) + ' m')));
      DL.$('label', fd).append(dv);
      g.append(fd);
      const leaves = DL.h('div', { style: { display: 'flex', flexDirection: 'column', gap: '8px' } });
      (d.doors || []).forEach((l, i) => {
        const c = l.coords;
        const row = DL.h('div.leaf', { html: `<div class="n">${i + 1}</div><div class="tx"><b>model ${l.model}</b><br>${c.x.toFixed(2)}, ${c.y.toFixed(2)}, ${c.z.toFixed(2)}</div>` });
        row.append(DL.h('button.btn.sm', { html: `${DL.icon('pin')}Teleport`, onclick: () => DL.post('adminTp', { coords: c }) }));
        leaves.append(row);
      });
      leaves.append(DL.h('button.btn', { html: `${DL.icon('target')}${d.doors && d.doors.length ? 'Wybierz skrzydła ponownie' : 'Wybierz drzwi celownikiem'}`, onclick: () => pick(d) }));
      g.append(field('Skrzydła drzwi', leaves, { full: true, hint: 'Podwójne drzwi = dwa skrzydła. Model i pozycja są pobierane z obiektu w grze.' }));
      g.append(DL.h('div.full', null, rowSw('eyeoff', 'Ukryj znacznik', 'Brak ikony w świecie – interakcja nadal działa (np. ukryte przejścia).', d.hideUi, v => change(x => (x.hideUi = v)))));
    }

    if (A.tab === 'access') {
      const cards = DL.h('div.seccards');
      SECS.forEach(([k, ic, l, desc]) => cards.append(DL.h('button.seccard' + (d.security === k ? '.on' : ''), {
        html: `${DL.icon(ic)}<b>${l}</b><span>${desc}</span>`, onclick: () => change(x => { x.security = k; if (k === 'keypad' && !x.pin) x.pin = '0000'; if (k === 'card' && !x.cardLevel) x.cardLevel = 1; }, true),
      })));
      g.append(field('Zabezpieczenie', cards, { full: true }));
      if (d.security === 'keypad') {
        g.append(field('Kod PIN', input(d.pin, v => change(x => (x.pin = v.replace(/\D/g, ''))), { mono: true, max: 8, ph: '4–8 cyfr' }), { hint: 'Osoby z dostępem służbowym otwierają przyciskiem „Identyfikator”.' }));
      }
      if (d.security === 'card') {
        const names = Object.entries(A.keycards).sort((a, b) => a[1] - b[1]);
        const max = Math.max(4, ...names.map(n => n[1]));
        const lv = DL.h('div.levels', { html: Array.from({ length: max }, (_, i) => `<span class="${i + 1 >= d.cardLevel ? 'on' : ''}">${i + 1}${names.find(n => n[1] === i + 1) ? ' · ' + names.find(n => n[1] === i + 1)[0].replace('keycard_', '') : ''}</span>`).join('') });
        const r = range(d.cardLevel || 1, 1, max, 1, v => { change(x => (x.cardLevel = v)); DL.$$('span', lv).forEach((s, i) => s.classList.toggle('on', i + 1 >= v)); });
        r.append(lv);
        g.append(field('Minimalny poziom karty', r));
      }
      g.append(DL.h('div.full', null, rowSw('users', 'Drzwi publiczne', 'Każdy może otwierać i zamykać (np. sklep w godzinach pracy).', d.access.public, v => change(x => (x.access.public = v)))));
      g.append(field('Prace', tags(d.access.jobs, true, v => change(x => (x.access.jobs = v))), { hint: 'Wpisz „police:2” i Enter – praca i minimalny stopień.' }));
      g.append(field('Gangi (QB / QBox)', tags(d.access.gangs, true, v => change(x => (x.access.gangs = v))), { hint: 'Np. „ballas:0”.' }));
      g.append(field('Przedmioty-klucze', tags(d.access.items, false, v => change(x => (x.access.items = v)), 'np. klucz_magazyn'), { hint: 'Wystarczy mieć jeden z nich w ekwipunku (tylko zabezpieczenie „Klucz”).' }));
      g.append(field('Właściciel (identyfikator)', input(d.owner, v => change(x => (x.owner = v || undefined)), { mono: true, max: 80, ph: 'citizenid / license:…' }), { hint: 'Właściciel rozdaje klucze cyfrowe z menu drzwi [G].' }));
      const ids = Object.entries(d.access.identifiers || {});
      const list = DL.h('div');
      if (!ids.length) list.innerHTML = '<div class="hint">Nikt nie ma jeszcze klucza cyfrowego.</div>';
      ids.forEach(([id, label]) => {
        const row = DL.h('div.holder', { html: `<div class="avatar">${DL.esc(DL.initials(label))}</div><div class="nm"><b>${DL.esc(label)}</b><span>${DL.esc(id)}</span></div>` });
        row.append(DL.h('button.btn.sm.bad', { html: DL.icon('trash'), onclick: () => change(x => delete x.access.identifiers[id], true) }));
        list.append(row);
      });
      g.append(field(`Klucze cyfrowe (${ids.length})`, list, { full: true }));
    }

    if (A.tab === 'security') {
      const lvl = v => (v ? `${v}/5` : 'wył.');
      const lp = DL.h('em', { text: lvl(d.lockpick) }), hk = DL.h('em', { text: lvl(d.hack) });
      const f1 = field('Wytrych – trudność', range(d.lockpick, 0, 5, 1, v => change(x => (x.lockpick = v)), v => (lp.textContent = lvl(v))), { hint: d.security === 'standard' ? '0 = zamka nie da się otworzyć wytrychem.' : 'Wytrych działa tylko przy zabezpieczeniu „Klucz”.' });
      DL.$('label', f1).append(lp);
      const f2 = field('Hakowanie – trudność', range(d.hack, 0, 5, 1, v => change(x => (x.hack = v)), v => (hk.textContent = lvl(v))), { hint: d.security === 'standard' ? 'Hakowanie działa tylko przy zamkach elektronicznych.' : '0 = czytnika nie da się zhakować.' });
      DL.$('label', f2).append(hk);
      g.append(f1, f2);
      g.append(field('Model zamka (widok w minigrze wytrycha)', seg([['euro', 'door', 'Wkładka w szyldzie'], ['rim', 'target', 'Rozeta'], ['padlock', 'lock', 'Kłódka']], d.lockModel || 'euro', v => change(x => (x.lockModel = v))), { full: true, hint: 'Szyld na stalowych drzwiach, rozeta na drewnianych, kłódka na kratach i bramach.' }));
      g.append(DL.h('div.full', null, rowSw('fire', 'Można wyważyć', 'Termit (przestępcy) i taran (służby) – drzwi zostają wyłamane do naprawy.', d.breach, v => change(x => (x.breach = v)))));
      g.append(DL.h('div.full', null, rowSw('alarm', 'Alarm', 'Włamanie, termit lub zablokowana klawiatura powiadamiają policję (blip + dispatch).', d.alarm, v => change(x => (x.alarm = v)))));
      g.append(DL.h('div.full', null, rowSw('bell', 'Dzwonek', 'Goście mogą zadzwonić – osoby z dostępem w pobliżu dostaną powiadomienie.', d.doorbell, v => change(x => (x.doorbell = v)))));
    }

    if (A.tab === 'auto') {
      const al = DL.h('em', { text: d.autoLock ? d.autoLock + ' s' : 'wył.' });
      const f = field('Autozamek', range(d.autoLock, 0, 120, 1, v => change(x => (x.autoLock = v)), v => (al.textContent = v ? v + ' s' : 'wył.')), { full: true, hint: 'Po otwarciu drzwi zamkną się same. Na znaczniku widać odliczanie.' });
      DL.$('label', f).append(al);
      g.append(f);
      const on = !!d.schedule;
      g.append(DL.h('div.full', null, rowSw('clock', 'Harmonogram', 'W tych godzinach (czas serwera) drzwi są otwarte, poza nimi zamknięte.', on, v => change(x => (x.schedule = v ? { open: '08:00', close: '22:00' } : undefined), true))));
      if (on) {
        const s = d.schedule;
        const bar = DL.h('div.sched');
        const paint = () => {
          const m = t => { const [h, mm] = t.split(':').map(Number); return ((h * 60 + mm) / 1440) * 100; };
          const o = m(s.open), c = m(s.close);
          bar.innerHTML = o < c ? `<i class="win" style="left:${o}%;width:${c - o}%"></i>` : `<i class="win" style="left:0;width:${c}%"></i><i class="win" style="left:${o}%;right:0"></i>`;
          const now = new Date();
          bar.innerHTML += `<i class="now" style="left:${((now.getHours() * 60 + now.getMinutes()) / 1440) * 100}%"></i>`;
        };
        g.append(field('Otwarcie', input(s.open, v => { if (/^\d\d:\d\d$/.test(v)) { change(x => (x.schedule.open = v)); paint(); } }, { type: 'time' })));
        g.append(field('Zamknięcie', input(s.close, v => { if (/^\d\d:\d\d$/.test(v)) { change(x => (x.schedule.close = v)); paint(); } }, { type: 'time' })));
        const wrap = DL.h('div', null, bar, DL.h('div.sched-lbl', { html: '<span>00:00</span><span>06:00</span><span>12:00</span><span>18:00</span><span>24:00</span>' }));
        g.append(field('Oś doby', wrap, { full: true }));
        paint();
      }
    }

    if (A.tab === 'log') {
      g.className = '';
      const st = A.states[d.id] || {};
      const qa = DL.h('div.qa');
      const add = (ic, l, what, cls = '') => qa.append(DL.h('button.btn' + cls, { html: `${DL.icon(ic)}${l}`, onclick: () => setState(what) }));
      add('lock', 'Zamknij', 'lock');
      add('unlock', 'Otwórz', 'unlock', '.good');
      add('bolt', 'Wyłam', 'breach');
      add('wrench', 'Napraw', 'repair');
      add('alarm', 'Test alarmu', 'alarm', '.bad');
      add('shield', st.d ? 'Zdejmij blokadę' : 'Blokada grupy', 'lockdown');
      if (!d.group) qa.lastChild.disabled = true;
      g.append(qa);
      const logBox = DL.h('div', { html: '<div class="empty">Wczytywanie…</div>' });
      g.append(logBox);
      DL.post('req', { name: 'admin_logs', args: [d.id] }).then(res => { if (A && A.draft === d) logBox.innerHTML = DL.timeline(res && res.logs); });
    }
  };

  /* ---------------- akcje ---------------- */
  const setState = async what => {
    const id = A.draft.id;
    const res = await DL.post('req', { name: 'admin_state', args: [id, what] });
    if (!A) return;
    if (res && res.ok) {
      A.states[id] = res.state;
      if (res.stats) { A.stats = res.stats; renderStats(); }
      renderList();
      renderView();
      DL.Audio.play(what === 'lock' ? 'lock' : what === 'alarm' ? 'alarm' : 'unlock', 0.7);
    } else DL.toast((res && res.msg) || 'Nie udało się', 'error');
  };

  const save = async () => {
    const d = A.draft;
    if (!d.doors || !d.doors.length) return DL.toast('Najpierw wybierz drzwi celownikiem', 'warn');
    if (!d.name.trim()) return DL.toast('Podaj nazwę drzwi', 'warn');
    if (d.security === 'keypad' && !(d.pin && d.pin.length >= DL.cfg.keypad.min)) return DL.toast(`PIN musi mieć co najmniej ${DL.cfg.keypad.min} cyfry`, 'warn');
    const btn = DL.$('.save', A.box);
    btn.disabled = true;
    const res = await DL.post('req', { name: 'admin_save', args: [d] });
    if (!A) return;
    btn.disabled = false;
    if (!res || !res.ok) return DL.toast((res && res.msg) || 'Błąd zapisu', 'error');
    A.doors.set(res.id, res.door);
    A.states[res.id] = res.state;
    if (res.stats) A.stats = res.stats;
    A.sel = res.id;
    A.draft = clone(res.door);
    A.dirty = false;
    renderStats();
    renderGroups();
    renderList();
    renderView();
    DL.toast(res.msg || 'Zapisano', 'success');
    DL.Audio.play('ok');
  };

  const askDelete = () => {
    const d = A.draft;
    const c = DL.h('div.confirm');
    c.innerHTML = `<div class="box">${DL.icon('trash')}<b>Usunąć „${DL.esc(d.name)}”?</b><p>Drzwi przestaną być zamykane, a ich dziennik zostanie skasowany. Tego nie da się cofnąć.</p><div class="row"></div></div>`;
    DL.$('.row', c).append(
      DL.h('button.btn.ghost', { text: 'Anuluj', onclick: () => c.remove() }),
      DL.h('button.btn.bad', { html: `${DL.icon('trash')}Usuń`, onclick: async () => {
        const res = await DL.post('req', { name: 'admin_delete', args: [d.id] });
        c.remove();
        if (!A || !res || !res.ok) return DL.toast((res && res.msg) || 'Błąd', 'error');
        A.doors.delete(d.id);
        delete A.states[d.id];
        if (res.stats) A.stats = res.stats;
        A.sel = null; A.draft = null; A.dirty = false;
        renderStats(); renderGroups(); renderList(); renderView();
        DL.toast(res.msg || 'Usunięto', 'success');
      } }),
    );
    A.box.append(c);
  };

  /** Wybór drzwi celownikiem – panel chowa się na czas wyboru */
  const pick = forDraft => {
    A.pickFor = forDraft ? 'edit' : 'new';
    A.box.style.display = 'none';
    DL.$('#layer').classList.remove('show');
    DL.post('adminPick');
  };

  const picked = (leaves, me) => {
    if (!A) return;
    A.box.style.display = '';
    DL.$('#layer').classList.add('show');
    if (!leaves || !leaves.length) return DL.toast('Anulowano wybór drzwi', 'info', 2000);
    if (A.pickFor === 'edit' && A.draft) {
      change(x => { x.doors = leaves; if (leaves.length > 1 && x.type === 'single') x.type = 'double'; if (leaves.length === 1 && x.type === 'double') x.type = 'single'; }, true);
    } else {
      A.sel = null;
      A.draft = blank(leaves);
      A.tab = 'general';
      A.dirty = true;
      DL.$$('.drow', A.box).forEach(r => r.classList.remove('on'));
      renderView();
    }
    DL.toast(`Wybrano ${leaves.length === 2 ? 'dwa skrzydła' : 'jedno skrzydło'} – uzupełnij ustawienia i zapisz`, 'success');
  };

  /** Zmiana stanu przyszła z serwera (inny gracz, autozamek…) */
  const liveState = (id, st) => {
    if (!A || !A.doors.has(id)) return;
    A.states[id] = st;
    recount();
    const row = DL.$(`.drow[data-id="${id}"]`, A.box);
    if (row) row.className = `drow ${stCls(st)}${st && st.a ? ' alarm' : ''}${A.sel === id ? ' on' : ''}`;
    if (A.draft && A.draft.id === id) head();
  };

  return { open, picked, liveState, isOpen: () => !!A };
})();
