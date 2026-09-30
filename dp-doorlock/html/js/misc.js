'use strict';
/* ==========================================================================
   Pasek postępu akcji, HUD trybu wyboru, panel kluczy cyfrowych, dziennik
   ========================================================================== */

/* ---------------- dziennik: etykiety wpisów ---------------- */
DL.LOG = {
  lock: ['Zamknięto', 'lock', 'info'], unlock: ['Otwarto', 'unlock', 'good'], denied: ['Odmowa dostępu', 'x', 'bad'],
  pin_fail: ['Błędny PIN', 'hash', 'bad'], alarm: ['Alarm', 'alarm', 'bad'], breach: ['Wyłamanie', 'bolt', 'warn'],
  repair: ['Naprawa zamka', 'wrench', 'good'], lockpick: ['Wytrych', 'pick', 'warn'], hack: ['Hakowanie', 'chip', 'warn'],
  lockdown: ['Blokada budynku', 'shield', 'bad'], lockdown_off: ['Koniec blokady', 'shield', 'good'], bell: ['Dzwonek', 'bell', 'info'],
  key_add: ['Nadano klucz', 'keys', 'good'], key_remove: ['Odebrano klucz', 'keys', 'warn'], pin_change: ['Zmiana PIN-u', 'hash', 'info'],
  created: ['Utworzono drzwi', 'plus', 'info'], edited: ['Edycja ustawień', 'edit', 'info'],
};
DL.VIA = {
  key: 'klucz', pin: 'PIN', badge: 'identyfikator', card: 'karta', bio: 'biometria', auto: 'autozamek', schedule: 'harmonogram',
  admin: 'admin', lockpick: 'wytrych', hack: 'hakowanie', thermite: 'termit', ram: 'taran', repair: 'naprawa', lockdown: 'blokada',
  export: 'skrypt', expired: 'wygasło', manual: 'ręcznie', ok: 'sukces', fail: 'porażka', test: 'test',
};
DL.timeline = logs => {
  if (!logs || !logs.length) return `<div class="empty">${DL.icon('log')}Brak wpisów w dzienniku</div>`;
  return '<div class="timeline">' + logs.map((l, i) => {
    const [label, icon, tone] = DL.LOG[l.a] || [l.a, 'info', 'info'];
    const via = l.x ? (DL.VIA[l.x] || l.x) : '';
    return `<div class="tl ${tone}" style="animation-delay:${Math.min(i, 12) * 25}ms"><i class="dot">${DL.icon(icon)}</i><b>${DL.esc(label)}</b>
      <div class="meta"><time>${DL.fmtTime(l.t)}</time><span>${DL.esc(l.who)}</span>${via ? `<span>· ${DL.esc(via)}</span>` : ''}</div></div>`;
  }).join('') + '</div>';
};

/* ---------------- postęp ---------------- */
DL.Progress = (() => {
  let el = null;
  const LEN = 163.4;
  return {
    start(d) {
      this.end(false, true);
      el = DL.h('div#progress');
      el.innerHTML = `<div class="pg-ring"><svg viewBox="0 0 58 58"><defs><linearGradient id="pgGrad"><stop offset="0" stop-color="var(--acc)"/><stop offset="1" stop-color="var(--acc2)"/></linearGradient></defs>
        <circle class="bg" cx="29" cy="29" r="26"/><circle class="fg" cx="29" cy="29" r="26"/></svg>${DL.icon(d.icon || 'timer')}</div>
        <div class="pg-txt"><b>${DL.esc(d.label)}</b><span>0%</span></div>`;
      document.body.append(el);
      const fg = DL.$('.fg', el), pct = DL.$('.pg-txt span', el);
      fg.getBoundingClientRect();
      fg.style.transition = `stroke-dashoffset ${d.ms}ms linear`;
      fg.style.strokeDashoffset = '0';
      const t0 = performance.now();
      el._iv = setInterval(() => { pct.textContent = Math.min(100, Math.round(((performance.now() - t0) / d.ms) * 100)) + '%'; }, 200);
    },
    end(ok, silent) {
      if (!el) return;
      const e = el;
      el = null;
      clearInterval(e._iv);
      if (silent) return e.remove();
      e.classList.add(ok ? 'done' : 'fail');
      if (!ok) { DL.$('.fg', e).style.transition = 'none'; DL.Audio.play('error', 0.5); }
      setTimeout(() => e.remove(), ok ? 300 : 700);
    },
  };
})();

/* ---------------- HUD trybu wyboru drzwi ---------------- */
DL.PickHud = {
  show(on, count = 0) {
    let el = DL.$('#pickhud');
    if (!on) { el && el.remove(); DL.$('#crosshair')?.remove(); return; }
    if (!el) {
      el = DL.h('div#pickhud');
      document.body.append(el, DL.h('div#crosshair', { html: DL.icon('target') }));
    }
    el.innerHTML = `<div class="ttl">${DL.icon('target')}Wybór drzwi</div>
      <span><kbd>E</kbd>dodaj skrzydło <b class="cnt">${count}/2</b></span>
      <span><kbd>ENTER</kbd>zatwierdź</span><span><kbd>G</kbd>wyczyść</span><span><kbd>⌫</kbd>anuluj</span>`;
  },
};

/* ---------------- klucze cyfrowe ---------------- */
DL.Keys = (() => {
  let cur = null;

  const render = () => {
    const d = cur.data;
    const body = DL.$('.pn-body', cur.box);
    DL.$$('.tabs button', cur.box).forEach(b => b.classList.toggle('on', b.dataset.t === cur.tab));
    DL.$('.tabs .cnt', cur.box).textContent = d.holders.length;
    if (cur.tab === 'log') { body.innerHTML = DL.timeline(d.logs); return; }
    body.innerHTML = '';
    if (!d.holders.length) body.append(DL.h('div.empty', { html: `${DL.icon('keys')}Nikt poza Tobą nie ma jeszcze klucza` }));
    d.holders.forEach((h, i) => {
      const row = DL.h('div.holder', { style: { animationDelay: i * 30 + 'ms' } });
      row.innerHTML = `<div class="avatar">${DL.esc(DL.initials(h.label))}</div><div class="nm"><b>${DL.esc(h.label)}</b><span>${DL.esc(h.id)}</span></div>`;
      row.append(DL.h('button.btn.sm.bad', { html: `${DL.icon('trash')}Odbierz`, onclick: () => call('keys_remove', h.id) }));
      body.append(row);
    });
    const inp = DL.h('input.inp.mono', { placeholder: 'ID gracza (np. 12)', inputmode: 'numeric', maxlength: 5 });
    const addBtn = DL.h('button.btn.pri', { html: `${DL.icon('plus')}Nadaj klucz`, onclick: () => inp.value && call('keys_add', Number(inp.value)) });
    inp.addEventListener('keydown', e => { if (e.key === 'Enter') addBtn.click(); e.stopPropagation(); });
    body.append(DL.h('div.add-row', null, inp, addBtn), DL.h('div.hint', { style: { marginTop: '10px' }, text: 'Klucz cyfrowy działa od razu – osoba z kluczem otwiera drzwi klawiszem E, bez przedmiotu. Możesz go odebrać w każdej chwili.' }));
  };

  const call = async (name, arg) => {
    const res = await DL.post('req', { name, args: [cur.data.id, arg] });
    if (!cur) return;
    if (res && res.ok) {
      res.id = cur.data.id;
      cur.data = res;
      DL.Audio.play(name === 'keys_add' ? 'ok' : 'lock', 0.7);
      render();
    } else DL.Audio.play('deny');
    if (res && res.msg) DL.toast(res.msg, res.ok ? 'success' : 'error');
  };

  const open = data => {
    const box = DL.h('div.panel');
    box.innerHTML = `
      <div class="pn-head">
        <div class="pn-title"><div class="badge">${DL.icon('keys')}</div><div><b>${DL.esc(data.name)}</b><span>Klucze cyfrowe i historia</span></div>
          <button class="btn icon ghost">${DL.icon('x')}</button></div>
        <div class="tabs"><button data-t="keys">${DL.icon('users')}Klucze <span class="cnt">0</span></button><button data-t="log">${DL.icon('log')}Dziennik</button></div>
      </div>
      <div class="pn-body"></div>`;
    DL.$('.pn-title .btn', box).onclick = () => DL.layer.close();
    DL.$$('.tabs button', box).forEach(b => (b.onclick = () => { cur.tab = b.dataset.t; render(); }));
    cur = { data, box, tab: 'keys' };
    DL.layer.open('keys', box, () => { cur = null; });
    render();
  };
  return { open };
})();
