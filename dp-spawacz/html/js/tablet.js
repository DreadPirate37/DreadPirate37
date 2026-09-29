'use strict';
/* ==========================================================================
   Tablet brygadzisty – profil spawacza, zlecenia, aktywny kontrakt
   ========================================================================== */
W.Tablet = {
  data: null,
  open(data) {
    this.data = data;
    document.getElementById('tablet').classList.remove('hidden');
    this.render();
  },
  close(silent) {
    document.getElementById('tablet').classList.add('hidden');
    if (!silent) W.post('tablet', { action: 'close' });
  },
  async act(action, id) {
    W.Audio.click();
    const res = await W.post('tablet', { action, id });
    if (!res) return;
    if (res.msg) W.toast(res.msg, res.ok ? 'good' : 'bad');
    if (res.close) this.close(true);
    else if (res.data) {
      this.data = res.data;
      this.render();
    }
  },
  render() {
    const d = this.data;
    const p = d.profile;
    const span = Math.max(1, p.nextXp - p.curXp);
    const pct = p.nextXp ? W.clamp(((p.xp - p.curXp) / span) * 100, 0, 100) : 100;
    const stars = n => '★'.repeat(n) + '☆'.repeat(5 - n);
    const offers = (d.offers || []).map(o => `
      <div class="offer">
        <div class="o-head"><h3>${W.esc(o.siteLabel)}</h3><span class="tier">${stars(o.tier)}</span></div>
        <ul>${o.tasks.map(t => `
          <li><b>${W.esc(t.typeLabel)}</b><span>${W.esc(t.materialLabel)} · ${t.thickness} mm · ${W.esc(t.process)} · ${W.esc(t.positionLabel)}${t.passes > 1 ? ` · ${t.passes} ściegi` : ''}</span></li>`).join('')}
        </ul>
        <div class="o-foot">
          <div><small>Szac. zarobek</small><b>${W.fmtMoney(o.estPay)}</b></div>
          <div><small>XP</small><b>~${o.estXp}</b></div>
          ${o.deposit ? `<div><small>Kaucja za auto</small><b>${W.fmtMoney(o.deposit)}</b></div>` : ''}
          <button class="btn primary" data-accept="${W.esc(o.id)}">Przyjmij</button>
        </div>
      </div>`).join('');
    const a = d.active;
    const active = a ? `
      <div class="active">
        <h3>Aktywne zlecenie: ${W.esc(a.siteLabel)}</h3>
        <ul>${a.tasks.map(t => `<li class="${t.done ? 'done' : t.failed ? 'failed' : ''}"><span>${W.esc(t.typeLabel)}</span><b>${t.done ? 'Ocena ' + W.esc(t.grade) : t.failed ? 'Przepadło' : 'Do zrobienia'}</b></li>`).join('')}</ul>
        <p>${a.left > 0 ? `Zostało zadań: <b>${a.left}</b>. Punkty pracy są zaznaczone na mapie.` : 'Wszystko zrobione! Oddaj zlecenie (i pojazd) w bazie po premię.'}</p>
        <div class="row">
          <button class="btn" data-act="waypoint">Pokaż na mapie</button>
          ${a.atDepot ? `<button class="btn primary" data-act="finish">${a.left > 0 ? 'Rozlicz częściowo' : 'Rozlicz zlecenie'}</button>` : ''}
          <button class="btn danger" data-act="cancel">Anuluj zlecenie</button>
        </div>
      </div>` : '';
    document.getElementById('tablet').innerHTML = `
      <div class="tab-frame">
        <header>
          <div class="logo">⚡ SPAWALNIA <b>DP</b></div>
          <button class="x" data-act="close">✕</button>
        </header>
        <section class="profile">
          <div class="lvl">${p.level}</div>
          <div class="pinfo">
            <b>${W.esc(p.label)}</b>
            <div class="xpbar"><i style="width:${pct}%"></i></div>
            <small>${p.nextXp ? `${p.xp} / ${p.nextXp} XP → ${W.esc(p.nextLabel)}` : `${p.xp} XP · poziom maksymalny`}</small>
          </div>
          <div class="pstats">
            <div><small>Spawy</small><b>${p.stats.tasks || 0}</b></div>
            <div><small>Zarobek</small><b>${W.fmtMoney(p.stats.earned || 0)}</b></div>
            <div><small>Najlepsza</small><b>${W.esc(p.stats.best || '–')}</b></div>
          </div>
        </section>
        <section class="unlocks">${(p.unlocks || []).map(u => `<span class="${u.ok ? 'ok' : ''}">${u.ok ? '✔' : '🔒 ' + u.level} ${W.esc(u.label)}</span>`).join('')}</section>
        ${active || `<section class="offers">${offers || '<p class="empty">Brak zleceń – wróć za chwilę.</p>'}</section>`}
      </div>`;
    const root = document.getElementById('tablet');
    root.querySelectorAll('[data-accept]').forEach(b => (b.onclick = () => this.act('accept', b.dataset.accept)));
    root.querySelectorAll('[data-act]').forEach(b => {
      b.onclick = () => (b.dataset.act === 'close' ? this.close() : this.act(b.dataset.act));
    });
  },
};
