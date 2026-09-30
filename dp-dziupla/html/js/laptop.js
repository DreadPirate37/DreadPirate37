'use strict';
/* ==========================================================================
   Laptop „ChopNet” – pulpit, zlecenia, magazyn, zamówienia, rynek,
   sklep i umiejętności. Wszystkie akcje idą przez Lua do serwera.
   ========================================================================== */
(() => {
  const $ = W.$;
  const TABS = [
    ['home', 'Pulpit'],
    ['contracts', 'Zlecenia'],
    ['warehouse', 'Magazyn'],
    ['orders', 'Zamówienia'],
    ['market', 'Rynek'],
    ['shop', 'Sklep'],
    ['skills', 'Umiejętności'],
    ['crew', 'Ekipa'],
  ];
  const stars = n => '★'.repeat(n) + '☆'.repeat(Math.max(0, 4 - n));
  const pct = v => Math.round((v || 0) * 100) + '%';
  const mins = s => Math.round((s || 0) / 60) + ' min';

  const Lp = (W.Laptop = {
    data: null,
    tab: 'home',
    sel: new Set(),
    filter: 'all',
    sort: 'value',

    open(data, tab) {
      this.data = data;
      if (tab) this.tab = tab;
      this.sel.clear();
      $('laptop').classList.remove('hidden');
      this.render();
    },

    close(silent) {
      $('laptop').classList.add('hidden');
      if (!silent) W.post('laptop', { action: 'close' });
    },

    async act(action, arg, arg2) {
      W.Audio.click();
      const res = await W.post('laptop', { action, arg, arg2 });
      if (!res) return;
      if (res.msg) W.toast(res.msg, res.ok ? 'good' : 'bad');
      if (res.data) {
        this.data = res.data;
        this.sel.clear();
        this.render();
      }
      return res;
    },

    render() {
      const d = this.data;
      if (!d) return;
      const p = d.profile;
      const span = Math.max(1, (p.nextXp || p.xp) - p.curXp);
      const xpPct = p.nextXp ? W.clamp(((p.xp - p.curXp) / span) * 100, 0, 100) : 100;
      $('laptop').innerHTML = `
        <div class="lt-win">
          <aside class="lt-side">
            <div class="lt-logo">Chop<b>Net</b><small>anonimowy rynek części</small></div>
            <nav>${TABS.map(([k, l]) => `<button class="lt-tab ${this.tab === k ? 'on' : ''}" data-tab="${k}">${l}${this.badge(k)}</button>`).join('')}</nav>
            <div class="lt-prof">
              <div class="lt-lvl">Poz. ${p.level} · ${W.esc(p.label)}</div>
              <div class="bar"><i style="width:${xpPct}%"></i></div>
              <small>${p.nextXp ? `${p.xp} / ${p.nextXp} XP → ${W.esc(p.nextLabel)}` : `${p.xp} XP · maks. poziom`}</small>
              ${p.points > 0 ? `<div class="lt-pts">${p.points} pkt umiejętności do wydania</div>` : ''}
            </div>
            ${d.atShop ? '' : '<div class="lt-warn">Połączenie zdalne – sprzedaż i zakupy tylko w dziupli</div>'}
          </aside>
          <main class="lt-main">
            <header><h1>${TABS.find(t => t[0] === this.tab)[1]}</h1><button class="btn" id="ltClose">Zamknij <small>(ESC)</small></button></header>
            <section id="ltBody">${this['tab_' + this.tab]()}</section>
          </main>
        </div>`;
      $('ltClose').onclick = () => this.close();
      $('laptop').querySelectorAll('[data-tab]').forEach(b => (b.onclick = () => { this.tab = b.dataset.tab; W.Audio.click(); this.render(); }));
      this.bind();
    },

    badge(k) {
      const d = this.data;
      let n = 0;
      if (k === 'contracts') n = d.contracts && d.contracts.active ? 1 : 0;
      if (k === 'orders') n = d.orders && d.orders.active ? 1 : 0;
      if (k === 'skills') n = d.profile.points;
      if (k === 'crew') n = d.crew && d.crew.invite ? 1 : 0;
      if (k === 'warehouse') return `<em>${d.warehouse.items.length}/${d.warehouse.cap}</em>`;
      return n ? `<em class="hot">${n}</em>` : '';
    },

    bind() {
      const root = $('laptop');
      root.querySelectorAll('[data-act]').forEach(b => {
        b.onclick = () => {
          let arg = b.dataset.arg;
          if (b.dataset.from) {
            const el = W.$(b.dataset.from);
            arg = el ? el.value : '';
            if (b.dataset.neg != null) arg = -Math.abs(Number(arg) || 0);
          }
          this.act(b.dataset.act, arg, b.dataset.arg2 != null ? Number(b.dataset.arg2) : undefined);
        };
      });
      root.querySelectorAll('[data-gps]').forEach(b => {
        b.onclick = async () => {
          const [x, y] = b.dataset.gps.split(',').map(Number);
          W.Audio.click();
          const r = await W.post('laptop', { action: 'waypoint', x, y });
          if (r && r.msg) W.toast(r.msg, 'info');
        };
      });
      root.querySelectorAll('[data-sel]').forEach(c => {
        c.onchange = () => {
          const u = Number(c.dataset.sel);
          if (c.checked) this.sel.add(u);
          else this.sel.delete(u);
          this.updateSel();
        };
      });
      root.querySelectorAll('[data-filter]').forEach(b => (b.onclick = () => { this.filter = b.dataset.filter; this.render(); }));
      const sortEl = root.querySelector('#whSort');
      if (sortEl) sortEl.onchange = () => { this.sort = sortEl.value; this.render(); };
      const all = root.querySelector('#whAll');
      if (all) all.onclick = () => {
        const items = this.filtered().filter(i => !i.reserved);
        const allOn = items.every(i => this.sel.has(i.u));
        items.forEach(i => (allOn ? this.sel.delete(i.u) : this.sel.add(i.u)));
        this.render();
      };
      const sell = root.querySelector('#whSell');
      if (sell) sell.onclick = () => this.sel.size && this.act('sell', [...this.sel]);
      const scrap = root.querySelector('#whScrap');
      if (scrap) scrap.onclick = () => this.sel.size && this.act('scrap', [...this.sel]);
      this.updateSel();
    },

    updateSel() {
      const el = $('whTotal');
      if (!el) return;
      const items = this.data.warehouse.items.filter(i => this.sel.has(i.u));
      const sum = items.reduce((a, i) => a + i.value, 0);
      el.innerHTML = `Zaznaczone: <b>${items.length}</b> · paser zapłaci <b>${W.fmtMoney(sum)}</b>`;
    },

    /* ---------------- zakładki ---------------- */
    tab_home() {
      const d = this.data, s = d.profile.stats;
      const ev = d.market.event;
      const c = d.contracts && d.contracts.active, o = d.orders && d.orders.active, e = d.exports && d.exports.active;
      const tile = (l, v) => `<div class="tile"><small>${l}</small><b>${v}</b></div>`;
      return `
        ${ev ? `<div class="lt-event"><b>Wydarzenie rynkowe</b> ${W.esc(ev.label)} <small>jeszcze ${mins(ev.left)}</small></div>` : ''}
        ${this.raidPanel()}
        <div class="tiles">
          ${tile('Rozebrane auta', s.cars)}${tile('Zdjęte części', s.parts)}${tile('Zarobek', W.fmtMoney(s.earned))}
          ${tile('Zlecenia', s.contracts)}${tile('Zamówienia', s.orders)}${tile('Eksport', s.exports)}${tile('Regeneracje', s.regen)}
          ${tile('Magazyn', `${d.warehouse.items.length}/${d.warehouse.cap}`)}
        </div>
        <h2>W toku</h2>
        <div class="cards">
          ${c ? this.activeContract(c) : '<div class="card empty">Brak zlecenia kradzieży – zajrzyj do „Zlecenia”.</div>'}
          ${o ? this.activeOrder(o) : ''}
          ${e ? this.activeExport(e) : ''}
        </div>
        <h2>Jak to działa</h2>
        <ol class="howto">
          <li>Weź zlecenie albo kup cynk na auto stojące na mieście – dziupla bierze tylko auta z listy.</li>
          <li>Wjedź na stanowisko i wciśnij <b>E</b>. Patrz na część, <b>E</b> = demontaż, <b>G</b> = oględziny, <b>H</b> = podnośnik.</li>
          <li>Odkręcaj jak w warsztacie: dobierz nasadkę, uważaj na rdzę, klipsy, płyny i akumulator.</li>
          <li>Zdjęte części zanieś na regał. Sprzedaj paserowi, zregeneruj na stole albo zrealizuj zamówienie.</li>
          <li>Zamykaj bramę – szlifierka przy otwartej bramie potrafi ściągnąć policję.</li>
        </ol>`;
    },

    raidPanel() {
      const r = this.data.raid;
      if (!r) return '';
      const k = W.clamp(r.heat / r.threshold, 0, 1.3) / 1.3;
      const col = r.heat >= r.threshold ? 'var(--bad)' : r.heat >= r.threshold * 0.6 ? 'var(--acc)' : 'var(--good)';
      const phase = r.phase === 'warning' ? `<b class="bad">OBŁAWA za ${r.left}s!</b>` : r.phase === 'raid' ? `<b class="bad">Trwa obława – dziupla zamknięta (${mins(r.left)})</b>` : '';
      return `<div class="card raid"><div class="c-head"><h3>Heat: ${W.esc(r.shop)}</h3>${phase}</div>
        <div class="risk"><span>${r.heat} / ${r.threshold}</span><i><s style="width:${(k * 100).toFixed(0)}%;background:${col}"></s></i></div>
        <p>Każde auto, część i zgłoszenie podbija heat. Powyżej progu policja może zrobić nalot i zabezpieczyć świeże części z regałów.</p>
        <div class="c-foot"><span></span><button class="btn" data-act="raidBribe" ${r.canBribe ? '' : 'disabled'}>Koperta dla dzielnicowego ${W.fmtMoney(r.bribe)}</button></div></div>`;
    },

    tab_crew() {
      const c = this.data.crew || {};
      if (!c.enabled) return '<div class="card empty">Ekipy są wyłączone na tym serwerze.</div>';
      const inv = c.invite ? `<div class="card act"><div class="c-head"><h3>Zaproszenie: ${W.esc(c.invite.name)}</h3></div><p>Od: ${W.esc(c.invite.from)}</p>
        <div class="c-foot"><span></span><button class="btn primary" data-act="crewAccept">Dołącz</button></div></div>` : '';
      const k = c.crew;
      if (!k) {
        return `<div class="cards">${inv}<div class="card"><div class="c-head"><h3>Załóż ekipę</h3><b>${W.fmtMoney(c.price)}</b></div>
          <p>Wspólny magazyn i regały, kasa ekipy (${Math.round(c.cut * 100)}% zarobków członków), poziom ekipy podnosi ceny u pasera. Do ${c.maxMembers} osób.</p>
          <input id="crewName" class="inp" maxlength="24" placeholder="Nazwa ekipy">
          <div class="c-foot"><span></span><button class="btn primary" data-act="crewCreate" data-from="crewName">Załóż</button></div></div></div>`;
      }
      const boss = k.myRole === 'boss', deputy = boss || k.myRole === 'deputy';
      return `<div class="tiles">
          <div class="tile"><small>Ekipa</small><b>${W.esc(k.name)}</b></div>
          <div class="tile"><small>Poziom</small><b>${k.level}${k.priceBonus ? ` <small>+${Math.round(k.priceBonus * 100)}% cen</small>` : ''}</b></div>
          <div class="tile"><small>Kasa</small><b>${W.fmtMoney(k.bank)}</b></div>
          <div class="tile"><small>Zarobek ekipy</small><b>${W.fmtMoney(k.earned)}</b></div>
        </div>
        <h2>Członkowie</h2>
        <table class="wh"><tbody>${k.members.map(m => `<tr><td><b>${W.esc(m.name)}</b>${m.me ? ' <span class="tag ok">ty</span>' : ''}</td><td>${W.esc(m.roleLabel)}</td>
          <td style="text-align:right">${boss && !m.me ? `<button class="btn tiny" data-act="crewPromote" data-arg="${W.esc(m.id)}">${m.role === 'deputy' ? 'Degraduj' : 'Awansuj'}</button> ` : ''}
          ${deputy && !m.me && m.role !== 'boss' ? `<button class="btn tiny danger" data-act="crewKick" data-arg="${W.esc(m.id)}">Wyrzuć</button>` : ''}</td></tr>`).join('')}</tbody></table>
        <div class="cards" style="margin-top:12px">
          ${deputy ? `<div class="card"><div class="c-head"><h3>Zaproś gracza</h3></div><p>ID gracza z serwera (musi być online).</p>
            <input id="crewInv" class="inp" placeholder="ID"><div class="c-foot"><span></span><button class="btn primary" data-act="crewInvite" data-from="crewInv">Zaproś</button></div></div>` : ''}
          <div class="card"><div class="c-head"><h3>Kasa ekipy</h3><b>${W.fmtMoney(k.bank)}</b></div>
            <input id="crewAmt" class="inp" placeholder="Kwota"><div class="c-foot"><span></span>
            <button class="btn" data-act="crewBank" data-from="crewAmt">Wpłać</button>
            ${boss ? '<button class="btn primary" data-act="crewBank" data-from="crewAmt" data-neg>Wypłać</button>' : ''}</div></div>
          <div class="card"><div class="c-head"><h3>${boss ? 'Rozwiąż / opuść' : 'Opuść ekipę'}</h3></div>
            <p>${boss ? 'Szef może rozwiązać ekipę, gdy zostanie sam (kasa wraca do szefa, magazyn ekipy przepada).' : 'Twoje części zostają w magazynie ekipy.'}</p>
            <div class="c-foot"><span></span><button class="btn danger" data-act="crewLeave">${boss ? 'Rozwiąż' : 'Opuść'}</button></div></div>
        </div>`;
    },

    activeContract(c) {
      return `<div class="card act">
        <div class="c-head"><h3>Zlecenie: ${W.esc(c.label)}</h3><span class="tier">${stars(c.tier)}</span></div>
        <p>Obszar: <b>${W.esc(c.zone || '?')}</b>${c.plate ? ` · tablice <b>${W.esc(c.plate)}</b>` : ''} · zostało <b>${W.esc(c.left)}</b></p>
        <p>Premia: <b>${W.fmtMoney(c.reward)}</b> + ${c.xp} XP po wstawieniu auta na stanowisko.</p>
        <div class="row"><button class="btn" data-gps="${c.area.x},${c.area.y}">GPS</button><button class="btn danger" data-act="contractCancel">Anuluj</button></div>
      </div>`;
    },

    activeOrder(o) {
      return `<div class="card act">
        <div class="c-head"><h3>Dostawa: ${W.esc(o.client)}</h3><b>${W.fmtMoney(o.pay)}</b></div>
        <p>${o.lines.map(l => `${l.n}× ${W.esc(l.label)} (min. ${l.min}%)`).join(', ')}</p>
        <p>Zostało <b>${W.esc(o.left)}</b> · punkt odbioru zaznaczony na mapie.</p>
        <div class="row"><button class="btn danger" data-act="orderCancel">Anuluj (części wrócą)</button></div>
      </div>`;
    },

    activeExport(e) {
      return `<div class="card act">
        <div class="c-head"><h3>Eksport: ${W.esc(e.label)}</h3><b>do ${W.fmtMoney(e.pay)}</b></div>
        <p>Dostarcz auto do kontenera w porcie. Min. stan: ${pct(e.minHealth)} · zostało <b>${W.esc(e.left)}</b></p>
        <div class="row"><button class="btn danger" data-act="exportCancel">Anuluj</button></div>
      </div>`;
    },

    tab_contracts() {
      const c = this.data.contracts || { offers: [] };
      const ex = this.data.exports || { offers: [] };
      const risk = (l, v, cls) => `<div class="risk"><span>${l}</span><i><s class="${cls}" style="width:${pct(v)}"></s></i></div>`;
      const offers = c.active ? this.activeContract(c.active) : (c.offers || []).map(o => `
        <div class="card">
          <div class="c-head"><h3>${W.esc(o.label)}</h3><span class="tier">${stars(o.tier)}</span></div>
          <p>Obszar: <b>${W.esc(o.zone || '?')}</b> · czas: ${mins(o.time)}</p>
          ${risk('Alarm', o.risk.alarm, 'warn')}${risk('Nadajnik GPS', o.risk.tracker, 'bad')}
          <div class="c-foot"><div><small>Premia</small><b>${W.fmtMoney(o.reward)}</b></div><div><small>XP</small><b>${o.xp}</b></div>
          <button class="btn" data-gps="${o.area.x},${o.area.y}">GPS</button>
          <button class="btn primary" data-act="contractAccept" data-arg="${W.esc(o.id)}">Biorę</button></div>
        </div>`).join('');
      let exp;
      if (ex.locked) exp = `<div class="card empty">Eksport odblokujesz na poziomie ${ex.minLevel}.</div>`;
      else if (ex.active) exp = this.activeExport(ex.active);
      else exp = (ex.offers || []).map(o => `
        <div class="card">
          <div class="c-head"><h3>Kontener: ${W.esc(o.label)}</h3><b>${W.fmtMoney(o.pay)}</b></div>
          <p>Auto z listy (zlecenie albo cynk) tej klasy, stan min. ${pct(o.minHealth)}. Czas: ${mins(o.time)}. Całe auto – bez rozbierania.</p>
          <div class="c-foot"><span></span><button class="btn primary" data-act="exportAccept" data-arg="${W.esc(o.id)}">Biorę</button></div>
        </div>`).join('');
      const street = (this.data.street || []).map(t => `
        <div class="card">
          <div class="c-head"><h3>${W.esc(t.label)}</h3><span class="tier">${stars(t.tier)}</span></div>
          <p>Zaparkowane i zamknięte gdzieś w mieście.${t.tracker ? ' <b>Możliwy nadajnik GPS.</b>' : ''} Bez premii za zlecenie – zarabiasz na częściach.</p>
          <div class="c-foot"><span></span><button class="btn primary" data-act="tipBuy" data-arg="${t.net}">Kup cynk ${W.fmtMoney(t.price)}</button></div>
        </div>`).join('');
      return `<h2>Lista życzeń – auta na zamówienie</h2><div class="cards">${offers || '<div class="card empty">Brak ofert.</div>'}</div>
        <h2>Auta na mieście – cynki</h2><p class="lead">Dziupla bierze tylko auta z listy. Te stoją teraz na mieście – kup cynk, żeby dostać przybliżone miejsce.</p>
        <div class="cards">${street || '<div class="card empty">Chwilowo nic nie stoi.</div>'}</div>
        <h2>Eksport w kontenerze</h2><div class="cards">${exp}</div>`;
    },

    filtered() {
      let items = this.data.warehouse.items.slice();
      if (this.filter !== 'all') items = items.filter(i => i.cat === this.filter);
      const s = this.sort;
      items.sort((a, b) => (s === 'value' ? b.value - a.value : s === 'cond' ? b.cond - a.cond : s === 'name' ? a.label.localeCompare(b.label) : b.u - a.u));
      return items;
    },

    tab_warehouse() {
      const wh = this.data.warehouse;
      const cats = {};
      wh.items.forEach(i => (cats[i.cat] = i.catLabel));
      const items = this.filtered();
      const used = wh.items.length / Math.max(1, wh.cap);
      return `
        <div class="wh-top">
          <div class="cap"><span>Miejsce: ${wh.items.length}/${wh.cap}</span><i><s style="width:${pct(used)};background:${used > 0.9 ? 'var(--bad)' : 'var(--acc)'}"></s></i></div>
          <div class="chips"><button class="chip ${this.filter === 'all' ? 'on' : ''}" data-filter="all">Wszystko</button>
            ${Object.entries(cats).map(([k, l]) => `<button class="chip ${this.filter === k ? 'on' : ''}" data-filter="${k}">${W.esc(l)}</button>`).join('')}</div>
          <select id="whSort">${[['value', 'Wartość'], ['cond', 'Stan'], ['name', 'Nazwa'], ['new', 'Najnowsze']].map(([k, l]) => `<option value="${k}" ${this.sort === k ? 'selected' : ''}>${l}</option>`).join('')}</select>
        </div>
        <table class="wh">
          <thead><tr><th><button class="btn tiny" id="whAll">✓</button></th><th>Część</th><th>Z auta</th><th>Stan</th><th>Wartość</th></tr></thead>
          <tbody>${items.map(i => `
            <tr class="${i.reserved ? 'res' : ''}">
              <td>${i.reserved ? '📦' : `<input type="checkbox" data-sel="${i.u}" ${this.sel.has(i.u) ? 'checked' : ''}>`}</td>
              <td><b>${W.esc(i.label)}</b>${i.regen ? ' <span class="tag">regenerowana</span>' : ''}${i.reserved ? ' <span class="tag">w zamówieniu</span>' : ''}<small>${W.esc(i.catLabel || '')}</small></td>
              <td>${W.esc(i.vehicle || '–')}</td>
              <td><div class="cond"><i style="width:${i.cond}%;background:${W.condColor(i.cond)}"></i></div><small>${i.cond}%</small></td>
              <td><b>${W.fmtMoney(i.value)}</b></td>
            </tr>`).join('') || '<tr><td colspan="5" class="empty">Magazyn jest pusty. Zdejmij coś z auta i odłóż na regał.</td></tr>'}
          </tbody>
        </table>
        <div class="wh-foot"><span id="whTotal"></span>
          <button class="btn" id="whScrap" ${this.data.atShop ? '' : 'disabled'}>Na złom (wg wagi)</button>
          <button class="btn primary" id="whSell" ${this.data.atShop ? '' : 'disabled'}>Sprzedaj paserowi</button></div>`;
    },

    tab_orders() {
      const o = this.data.orders || { offers: [] };
      if (o.active) return `<div class="cards">${this.activeOrder(o.active)}</div>`;
      return `<p class="lead">Klienci płacą więcej niż paser, ale chcą konkretnych części w konkretnym stanie – i trzeba je dowieźć.</p>
        <div class="cards">${(o.offers || []).map(of => {
          const ok = of.lines.every((l, i) => (of.have[i] || 0) >= l.n);
          return `<div class="card">
            <div class="c-head"><h3>${W.esc(of.client)}</h3><b>${W.fmtMoney(of.pay)}</b></div>
            <ul class="lines">${of.lines.map((l, i) => `<li class="${(of.have[i] || 0) >= l.n ? 'ok' : ''}"><span>${l.n}× ${W.esc(l.label)} <small>min. ${l.min}%</small></span><b>${Math.min(of.have[i] || 0, l.n)}/${l.n}</b></li>`).join('')}</ul>
            <div class="c-foot"><small>Czas: ${mins(of.time)}</small><button class="btn primary" data-act="orderAccept" data-arg="${W.esc(of.id)}" ${ok && this.data.atShop ? '' : 'disabled'}>Pakuj i jedź</button></div>
          </div>`;
        }).join('') || '<div class="card empty">Brak zamówień.</div>'}</div>`;
    },

    spark(hist) {
      if (!hist || hist.length < 2) return '';
      const w = 140, h = 34, lo = 0.5, hi = 1.5;
      const pts = hist.map((v, i) => `${((i / (hist.length - 1)) * w).toFixed(1)},${(h - ((v - lo) / (hi - lo)) * h).toFixed(1)}`).join(' ');
      return `<svg viewBox="0 0 ${w} ${h}" class="spark"><line x1="0" x2="${w}" y1="${h / 2}" y2="${h / 2}"/><polyline points="${pts}"/></svg>`;
    },

    tab_market() {
      const m = this.data.market;
      return `${m.event ? `<div class="lt-event"><b>Wydarzenie</b> ${W.esc(m.event.label)} <small>jeszcze ${mins(m.event.left)}</small></div>` : ''}
        <p class="lead">Popyt spada, gdy wszyscy sprzedają to samo, i wraca z czasem. Ceny w magazynie liczą się z bieżącym popytem.</p>
        <div class="cards market">${m.cats.map(c => {
          const h = c.hist || [];
          const prev = h.length > 1 ? h[h.length - 2] : c.d;
          const tr = c.d > prev + 0.01 ? '▲' : c.d < prev - 0.01 ? '▼' : '■';
          const cls = c.d >= 1.1 ? 'good' : c.d <= 0.85 ? 'bad' : '';
          return `<div class="card mk"><div class="c-head"><h3>${W.esc(c.label)}</h3><b class="${cls}">${tr} ${pct(c.d)}</b></div>${this.spark(h.concat([c.d]))}</div>`;
        }).join('')}</div>`;
    },

    tab_shop() {
      const s = this.data.shop, at = this.data.atShop;
      return `<h2>Narzędzia</h2><div class="cards tools">${s.tools.map(t => `
          <div class="card ${t.owned ? 'owned' : ''} ${t.locked ? 'locked' : ''}">
            <div class="c-head"><h3>${W.esc(t.label)}</h3>${t.owned ? '<span class="tag ok">masz</span>' : `<b>${W.fmtMoney(t.price)}</b>`}</div>
            <p>${t.locked ? `Wymaga poziomu ${t.minLevel}` : this.toolDesc(t.key)}</p>
            ${t.owned ? '' : `<div class="c-foot"><span></span><button class="btn primary" data-act="buy" data-arg="${t.key}" ${t.locked || !at ? 'disabled' : ''}>Kup</button></div>`}
          </div>`).join('')}</div>
        <h2>Materiały</h2><div class="cards">${s.cons.map(c => `
          <div class="card"><div class="c-head"><h3>${W.esc(c.label)}</h3><b>${W.fmtMoney(c.price)}/szt.</b></div>
            <p>Masz: <b>${c.have}</b> / ${c.max}</p>
            <div class="c-foot"><span></span><button class="btn" data-act="buy" data-arg="${c.key}" data-arg2="1" ${at && c.have < c.max ? '' : 'disabled'}>+1</button><button class="btn" data-act="buy" data-arg="${c.key}" data-arg2="5" ${at && c.have < c.max ? '' : 'disabled'}>+5</button></div></div>`).join('')}</div>
        <h2>Ulepszenia dziupli</h2><div class="cards">${s.upg.map(u => `
          <div class="card"><div class="c-head"><h3>${W.esc(u.label)}</h3><b>${W.fmtMoney(u.price)}</b></div><p>Poziom: ${u.have}/${u.max}</p>
            <div class="c-foot"><span></span><button class="btn primary" data-act="buy" data-arg="${u.key}" ${at && u.have < u.max ? '' : 'disabled'}>Kup</button></div></div>`).join('')}</div>`;
    },

    toolDesc(k) {
      return {
        pliers: 'Szybkie i bezpieczne zdejmowanie opasek z węży.',
        jack: 'Kradzież kół prosto z zaparkowanych aut na ulicy.',
        drill: 'Wykręcanie ukręconych i zaokrąglonych śrub (zużywa wykrętaki).',
        grinder: 'Cięcie zapieczonych śrub, wydechu i karoserii. Głośna! Zużywa tarcze.',
        wire: 'Wycinanie szyb czołowych i tylnych w całości.',
        impact: 'Błyskawiczne odkręcanie i rozbijanie rdzy. Głośny.',
        hoist: 'Wyjmowanie silnika i skrzyni biegów.',
        scanner: 'Namierzanie i wyrywanie nadajników GPS z kradzionych aut.',
        tyretool: 'Rozbieranie kół na felgę i oponę – razem są warte więcej.',
        stamps: 'Przebitka numerów VIN – otwiera handel „czystymi” autami.',
      }[k] || '';
    },

    tab_skills() {
      const p = this.data.profile;
      return `<p class="lead">Punkty: <b>${p.points}</b> (1 za każdy poziom). <button class="btn tiny" data-act="perkReset" ${this.data.atShop ? '' : 'disabled'}>Reset umiejętności</button></p>
        <div class="cards perks">${this.data.perks.map(k => `
          <div class="card ${k.locked ? 'locked' : ''}">
            <div class="c-head"><h3>${W.esc(k.label)}</h3><span class="dots">${'●'.repeat(k.rank)}${'○'.repeat(k.ranks - k.rank)}</span></div>
            <p>${W.esc(k.desc)}</p>
            <div class="c-foot"><small>${k.locked ? `od poziomu ${k.minLevel}` : ''}</small>
            <button class="btn primary" data-act="perk" data-arg="${k.key}" ${k.locked || k.rank >= k.ranks || p.points <= 0 ? 'disabled' : ''}>+</button></div>
          </div>`).join('')}</div>`;
    },
  });

  /* ---------------- drobne okna: stół, lakiernia, HUD stanowiska ---------------- */
  W.BenchPick = {
    open(mode, items) {
      const el = $('modal');
      const title = mode === 'split' ? 'Montażownica – wybierz koło' : 'Stół warsztatowy – wybierz część';
      el.innerHTML = `<div class="card wide"><h2>${title}</h2>
        <p class="lead">${mode === 'split' ? 'Koło rozbierzesz na felgę i oponę – osobno są warte więcej.' : 'Każdą część można zregenerować raz. Blacharka = klepanie, mechanika = czyszczenie i uszczelki.'}</p>
        <div class="pick">${items.map(i => `<button class="pick-it" data-uid="${i.u}"><b>${W.esc(i.label)}</b><small>${W.esc(i.vehicle || '')}</small><span style="color:${W.condColor(i.cond)}">${i.cond}%</span><em>${W.fmtMoney(i.value)}</em></button>`).join('')}</div>
        <div class="row"><button class="btn" id="bpCancel">Anuluj</button></div></div>`;
      el.classList.remove('hidden');
      el.querySelectorAll('[data-uid]').forEach(b => (b.onclick = async () => {
        W.Audio.click();
        const r = await W.post('bench', { action: 'pick', uid: Number(b.dataset.uid) });
        if (r && r.ok) el.classList.add('hidden');
        else if (!W.isFiveM) { el.classList.add('hidden'); W.Bench.open({ mode: mode === 'split' ? 'split' : 'dents', seed: 5, label: 'Demo', cond: 50, cap: 20 }); }
      }));
      $('bpCancel').onclick = () => { el.classList.add('hidden'); W.post('bench', { action: 'cancel' }); };
    },
    close() { $('modal').classList.add('hidden'); },
  };

  W.Paint = {
    open(colors, paint, papers) {
      const el = $('modal');
      this.color = colors[0][0];
      el.innerHTML = `<div class="card wide"><h2>Lakiernia i papiery</h2>
        <p class="lead">Nowy kolor i fałszywe papiery. Papiery podnoszą cenę u handlarza i zmniejszają ryzyko wpadki.</p>
        <div class="swatches">${colors.map(([id, name]) => `<button class="sw ${id === this.color ? 'on' : ''}" data-col="${id}"><i class="c${id}"></i>${W.esc(name)}</button>`).join('')}</div>
        <label class="chk"><input type="checkbox" id="ppPapers" checked> Fałszywe papiery (+${W.fmtMoney(papers)})</label>
        <p>Lakierowanie: ${W.fmtMoney(paint)}</p>
        <div class="row"><button class="btn" id="ppCancel">Później</button><button class="btn primary" id="ppGo">Lakieruj</button></div></div>`;
      el.classList.remove('hidden');
      el.querySelectorAll('[data-col]').forEach(b => (b.onclick = () => {
        this.color = Number(b.dataset.col);
        el.querySelectorAll('[data-col]').forEach(x => x.classList.toggle('on', x === b));
        W.Audio.click();
      }));
      $('ppCancel').onclick = () => { el.classList.add('hidden'); W.post('paint', { cancel: true }); };
      $('ppGo').onclick = async () => {
        W.Audio.spray();
        const r = await W.post('paint', { color: this.color, papers: $('ppPapers').checked });
        if (r && r.ok) el.classList.add('hidden');
        if (!W.isFiveM) el.classList.add('hidden');
      };
    },
  };

  W.BayHud = {
    update(show, d) {
      const el = $('bayhud');
      if (!show || !d) return el.classList.add('hidden');
      el.classList.remove('hidden');
      const lifts = ['ziemia', 'koła', 'podwozie'];
      const nz = W.clamp(d.noise || 0, 0, 1.2) / 1.2;
      const flags = d.flags || {};
      el.innerHTML = `
        <div class="bh-title">${W.esc(d.label || '')}<small>${d.mode === 'revin' ? 'przebitka' : 'rozbiórka'}</small></div>
        ${d.mode === 'chop' ? `<div class="bh-row"><span>Części</span><b>${d.done}/${d.total}</b></div><div class="bar"><i style="width:${d.total ? (d.done / d.total) * 100 : 0}%"></i></div>
        <div class="bh-row"><span>Podnośnik [H]</span><b>${d.moving ? 'jedzie…' : `${d.lift} · ${lifts[d.lift] || ''}`}</b></div>` : ''}
        <div class="bh-row"><span>Brama</span><b class="${d.gate ? 'good' : 'bad'}">${d.gate ? 'zamknięta' : 'otwarta'}</b></div>
        <div class="bh-row"><span>Hałas w okolicy</span><i class="nz"><s style="width:${(nz * 100).toFixed(0)}%;background:${nz > 0.7 ? 'var(--bad)' : nz > 0.4 ? 'var(--acc)' : 'var(--good)'}"></s></i></div>
        ${d.mode === 'chop' ? `<div class="bh-flags">${['@batteryOff', '@oil', '@coolant', '@fuel'].map(f => `<span class="${flags[f] ? 'ok' : ''}">${{ '@batteryOff': 'Akumulator', '@oil': 'Olej', '@coolant': 'Chłodnica', '@fuel': 'Paliwo' }[f]}</span>`).join('')}</div>` : ''}
        <div class="bh-keys"><b>E</b> demontaż <b>G</b> oględziny <b>H</b> podnośnik <b>X×2</b> przerwij</div>`;
    },
  };
})();
