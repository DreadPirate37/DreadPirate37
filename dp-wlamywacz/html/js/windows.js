/* dp-wlamywacz – okna z fokusem: laptop (UIX-02), paser, dialog, dowody policji, sygnały, raport */
'use strict';
const Win = {
  kind: null, data: null,
  open(kind, data) {
    this.kind = kind; this.data = data;
    const render = Win.render[kind];
    if (!render) return;
    $('#window').replaceChildren(render(data));
    $('#window').hidden = false;
  },
  close(silent) {
    const k = this.kind;
    $('#window').hidden = true;
    $('#window').replaceChildren();
    this.kind = null;
    if (!silent && k) post('window', { kind: k, action: 'close' });
  },
  async act(payload) {
    return await post('window', Object.assign({ kind: this.kind }, payload));
  },
  frame(title, body, opts = {}) {
    return el('div', { class: 'win' + (opts.narrow ? ' narrow' : '') },
      el('div', { class: 'win-head' }, el('b', { text: title }), el('button', { class: 'x', text: 'ESC – zamknij', onclick: () => Win.close() })),
      opts.tabs || null,
      el('div', { class: 'win-body' }, body));
  },
  render: {},
};

const money = (n) => `${Math.round(n).toLocaleString('pl-PL')} $`;
const stars = (n) => '★'.repeat(n || 0) + '☆'.repeat(5 - (n || 0));

/* ---------------- laptop ---------------- */
Win.render.laptop = (d) => {
  let tab = Win.tab || 'profil';
  const body = el('div', { class: 'win-body', style: 'padding:0' });
  const msg = el('div', { class: 'msg' });
  const tabs = el('div', { class: 'tabs' });
  const names = [['profil', 'Profil'], ['notatnik', 'Notatnik'], ['sklep', 'Czarny rynek'], ['poczta', 'Poczta'], ['torba', 'Torba'], ['ekipa', 'Ekipa']];
  const content = el('div', { class: 'win-body' });
  const show = (t) => {
    tab = t; Win.tab = t;
    for (const b of tabs.children) b.classList.toggle('on', b.dataset.t === t);
    content.replaceChildren(Laptop[t](d, msg), msg);
  };
  for (const [k, l] of names) tabs.append(el('button', { class: 'tab', 'data-t': k, text: l, onclick: () => show(k) }));
  const w = el('div', { class: 'win' }, el('div', { class: 'win-head' }, el('b', { text: 'Laptop' }), el('button', { class: 'x', text: 'ESC – zamknij', onclick: () => Win.close() })), tabs, content);
  show(tab);
  body.remove();
  return w;
};

const Laptop = {
  profil(d) {
    const p = d.profile || {};
    const next = p.next || p.xp;
    const pct = p.next ? Math.round((p.xp - p.base) / (p.next - p.base) * 100) : 100;
    const rep = p.rep || {};
    return el('div', { class: 'list' },
      el('div', { class: 'bar' }, el('b', { text: `Poziom ${p.level} · ${p.label}`, style: 'font-family:var(--font-display);font-size:26px' }), el('span', { class: 'mono', text: `${p.xp} / ${next} XP` })),
      el('div', { class: 'xp' }, el('i', { style: `width:${pct}%` })),
      el('div', { class: 'stats' },
        el('div', { class: 'stat' }, el('span', { text: 'Włamania' }), el('b', { text: (p.stats && p.stats.houses) || 0 })),
        el('div', { class: 'stat' }, el('span', { text: 'Łup razem' }), el('b', { text: money((p.stats && p.stats.loot) || 0) })),
        el('div', { class: 'stat' }, el('span', { text: 'Najlepsza ocena' }), el('b', { text: (p.stats && p.stats.best) != null ? p.stats.best + ' pkt' : '—' })),
        el('div', { class: 'stat' }, el('span', { text: 'Heat' }), el('b', { text: p.heat || 0 })),
        el('div', { class: 'stat' }, el('span', { text: 'Reputacja: Wiktor' }), el('b', { text: rep.wiktor || 0 })),
        el('div', { class: 'stat' }, el('span', { text: 'Reputacja: paserzy' }), el('b', { text: Object.keys(rep).filter((k) => k.startsWith('fence_')).reduce((s, k) => s + rep[k], 0) })),
      ));
  },
  notatnik(d) {
    const list = el('div', { class: 'list' });
    if (!d.notebook || !d.notebook.length) list.append(el('div', { class: 'nb' }, 'Pusto. Obserwuj domy przez lornetkę, obejdź je i zadzwoń do drzwi.'));
    for (const h of d.notebook || []) {
      const r = h.rating;
      list.append(el('div', { class: 'nb' + (h.stale ? ' stale' : '') },
        el('h4', {}, h.label, el('small', { text: h.stale ? 'nieaktualne' : (h.active ? 'aktywny cel' : '') })),
        r ? el('div', { class: 'stars', text: `zabezpieczenia ${stars(r.security)} · łup ${stars(r.loot)} · pewność ${r.certainty}%` }) : null,
        el('ul', {}, (h.notes || []).map((n) => el('li', { text: '– ' + n.t })))));
    }
    return list;
  },
  sklep(d, msg) {
    const s = d.shop || { items: [], orders: [] };
    const list = el('div', { class: 'list' });
    for (const it of s.items) {
      list.append(el('div', { class: 'row' },
        el('span', { class: 'badge', text: 'poz. ' + it.minLevel }),
        el('div', {}, el('b', { text: it.label })),
        el('span', { class: 'price', text: money(it.price) }),
        el('button', { class: 'btn' + (it.locked ? '' : ' primary'), text: it.locked ? 'zablokowane' : 'Zamów', disabled: it.locked ? 'disabled' : null, onclick: async () => {
          const r = await Win.act({ action: 'buy', index: it.i, qty: 1 });
          msg.className = 'msg ' + (r && r.ok ? 'good' : 'bad'); msg.textContent = (r && r.msg) || '';
          if (r && r.shop) { d.shop = r.shop; }
        } })));
    }
    const orders = el('div', { class: 'list' }, el('b', { text: 'Zamówienia w drodze', style: 'margin-top:6px' }));
    if (!s.orders.length) orders.append(el('div', { class: 'sub', text: 'Brak. Towar czeka w skrytce oznaczonej na mapie.' }));
    for (const o of s.orders) orders.append(el('div', { class: 'row two' }, el('span', { text: `Skrytka #${o.i} · ${o.n} szt.` }), el('span', { class: 'badge', text: o.ready ? 'gotowe' : `za ${Math.ceil(o.left / 60)} min` })));
    return el('div', { class: 'list' }, list, orders);
  },
  poczta(d) {
    const m = (d.mail && d.mail.mail) || [];
    const view = el('div', { class: 'mail-body', text: 'Wybierz wiadomość.' });
    const list = el('div', { class: 'list' });
    m.forEach((x, i) => {
      const row = el('div', { class: 'row two mail' + (x.read ? '' : ' unread'), onclick: () => {
        view.textContent = x.body; row.classList.remove('unread'); x.read = true;
        Win.act({ action: 'mail', index: i + 1 });
      } }, el('b', { text: x.subject }), el('span', { class: 'sub', text: x.from }));
      list.append(row);
    });
    if (!m.length) list.append(el('div', { class: 'sub', text: 'Skrzynka pusta. Porozmawiaj z Wiktorem.' }));
    const tut = d.mail || {};
    return el('div', { class: 'list' }, el('div', { class: 'sub', text: `Samouczek: ${tut.tutorial || 0} / ${tut.tutorialMax || 5}` }), list, view);
  },
  torba(d) {
    const b = d.bag || { items: [] };
    const list = el('div', { class: 'list' }, el('div', { class: 'bar' }, el('b', { text: 'Łup w torbie' }), el('span', { class: 'mono', text: `${b.kg} / ${b.cap} kg` })));
    for (const it of b.items) list.append(el('div', { class: 'row' },
      el('span', { class: 'badge' + (it.hot ? ' hot' : ''), text: it.hot ? 'gorący' : 'czysty' }),
      el('div', {}, el('b', { text: it.label }), el('div', { class: 'sub', text: it.house })),
      el('span', { class: 'mono', text: it.kg + ' kg' }), el('span', {})));
    if (!b.items.length) list.append(el('div', { class: 'sub', text: 'Pusto.' }));
    return list;
  },
  ekipa(d, msg) {
    const inp = el('input', { class: 'inp', id: 'crew-id', placeholder: 'ID gracza' });
    return el('div', { class: 'list' },
      el('div', { class: 'sub', text: 'Ekipa do 4 osób wchodzi razem do jednego domu i dzieli notatki. Zaproszony gracz wpisuje /wlm_ekipa akceptuj.' }),
      el('div', { class: 'bar' }, inp,
        el('button', { class: 'btn primary', text: 'Zaproś', onclick: async () => { const r = await Win.act({ action: 'invite', id: inp.value }); msg.className = 'msg ' + (r && r.ok ? 'good' : 'bad'); msg.textContent = (r && r.msg) || ''; } }),
        el('button', { class: 'btn', text: 'Opuść ekipę', onclick: async () => { const r = await Win.act({ action: 'leave' }); msg.textContent = (r && r.msg) || ''; } })));
  },
};

/* ---------------- paser / lombard ---------------- */
Win.render.fence = (d) => {
  const sel = new Set();
  const msg = el('div', { class: 'msg' });
  const total = el('b', { class: 'price', text: money(0) });
  const list = el('div', { class: 'list' });
  const upd = () => { let s = 0; for (const it of d.items) if (sel.has(it.uid) && !it.hot) s += it.price; total.textContent = money(s); };
  const fill = () => {
    list.replaceChildren();
    if (!d.items.length) list.append(el('div', { class: 'sub', text: 'Nie masz nic, co by go interesowało.' }));
    for (const it of d.items) {
      const cb = el('input', { type: 'checkbox', onchange: (e) => { e.target.checked ? sel.add(it.uid) : sel.delete(it.uid); upd(); } });
      list.append(el('label', { class: 'row' }, cb,
        el('div', {}, el('b', { text: it.label }), el('div', { class: 'sub', text: `${it.kg} kg` })),
        el('span', { class: 'badge' + (it.hot ? ' hot' : it.from === 'trunk' ? ' trunk' : ''), text: it.hot ? 'gorący' : it.from === 'trunk' ? 'bagażnik' : 'torba' }),
        el('span', { class: 'price', text: money(it.price) })));
    }
  };
  fill();
  const info = d.pawn ? 'Lombard płaci legalną gotówką, ale gorącego towaru nie weźmie – może też zadzwonić na policję.'
    : `Reputacja: ${d.repLabel} (${Math.floor(d.rep)}) · prowizja ${Math.round(d.cut * 100)}% · dzienny limit: ${money(d.limit)}`;
  const body = el('div', { class: 'list' },
    el('div', { class: 'sub', text: info }), list,
    el('div', { class: 'bar' }, el('span', {}, 'Razem: ', total),
      el('button', { class: 'btn primary', text: 'Sprzedaj zaznaczone', onclick: async () => {
        if (!sel.size) return;
        const r = await Win.act({ action: 'sell', uids: [...sel] });
        msg.className = 'msg ' + (r && r.ok ? 'good' : 'bad'); msg.textContent = (r && r.msg) || '';
        if (r && r.ok && r.offer) { d.items = r.offer.items || []; sel.clear(); fill(); upd(); Snd.cash(); }
      } })), msg);
  return Win.frame(d.fence || 'Paser', body);
};

/* ---------------- dialog (Wiktor) ---------------- */
Win.render.dialog = (d) => {
  const text = el('div', { class: 'dialog-text', text: d.text });
  const opts = el('div', { class: 'dialog-opts' });
  const fill = (dd) => {
    text.textContent = dd.text;
    opts.replaceChildren(...dd.options.map((o) => el('button', { class: 'btn' + (o.id === 'close' ? '' : ' primary'), text: o.label, onclick: async () => {
      if (o.id === 'close') { Win.close(true); post('window', { kind: 'dialog', id: 'close' }); return; }
      const r = await Win.act({ id: o.id });
      if (r && r.dialog) fill(r.dialog);
    } })));
  };
  fill(d);
  return Win.frame(d.title, el('div', { class: 'list' }, text, opts), { narrow: true });
};

/* ---------------- policja: ślady i sprawdzenie łupu ---------------- */
const EV = { finger: 'Odcisk palca', blood: 'Krew', tool: 'Ślad narzędzia', footage: 'Nagranie z kamery', witness: 'Zeznanie świadka', vehicle: 'Pojazd pod domem' };
Win.render.evidence = (d) => Win.frame('Ślady: ' + d.label, el('div', { class: 'list' },
  d.list.length ? d.list.map((e) => el('div', { class: 'row two' }, el('div', {}, el('b', { text: EV[e.kind] || e.kind }), el('div', { class: 'sub', text: [e.where, e.desc, e.who].filter(Boolean).join(' · ') })), el('span', { class: 'badge', text: `${e.ago} min temu` })))
    : el('div', { class: 'sub', text: 'Nic tu nie ma. Albo sprawca był w rękawiczkach.' })));
Win.render.inspect = (d) => Win.frame('Przeszukanie: ' + d.name, el('div', { class: 'list' },
  d.list.length ? d.list.map((e) => el('div', { class: 'row two' }, el('div', {}, el('b', { text: e.label }), el('div', { class: 'sub', text: 'zgłoszony jako skradziony: ' + e.house })), el('span', { class: 'badge hot', text: `${e.ago} min` })))
    : el('div', { class: 'sub', text: 'Brak przedmiotów z rejestru skradzionych.' })), { narrow: true });

/* ---------------- sygnały ekipy (EKI-07) ---------------- */
Win.render.signals = (d) => {
  const w = el('div', { class: 'win narrow' }, el('div', { class: 'win-head' }, el('b', { text: 'Sygnał dla ekipy' }), el('button', { class: 'x', text: 'ESC', onclick: () => Win.close() })),
    el('div', { class: 'radial' }, d.options.map((o) => el('button', { class: 'btn', text: o.label, onclick: () => { Win.close(true); post('window', { kind: 'signals', id: o.id }); } }))));
  return w;
};

/* ---------------- raport po włamaniu (UIX-14, SKR-23) ---------------- */
let reportTimer;
function showReport(r) {
  const m = Math.floor(r.time / 60), s = r.time % 60;
  const rows = [['Czas', `${m}:${pad2(s)}`], ['Łup', `${r.items} szt. · ~${money(r.value)}`], ['Hałas', r.noise], ['Wykrycia', r.detections], ['Odciski', r.prints],
    ['Alarm', r.alarm ? 'tak' : 'nie'], ['Policja', r.police ? 'wezwana' : 'nie'], ['Nagranie', r.footage ? 'zostało' : 'brak'], ['XP', '+' + r.xp]];
  const box = $('#report');
  box.replaceChildren(el('h3', { text: r.house }), el('div', { class: 'stamp ' + r.grade, text: r.grade }), el('div', { class: 'sub', style: 'text-align:center;color:var(--muted)', text: `${r.score} / 100 pkt` }),
    el('dl', {}, rows.map(([k, v]) => [el('dt', { text: k }), el('dd', { text: String(v) })])));
  box.hidden = false;
  Snd.thunk(0.5);
  clearTimeout(reportTimer);
  reportTimer = setTimeout(() => { box.hidden = true; }, 14000);
}
