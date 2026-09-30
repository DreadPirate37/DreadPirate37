'use strict';
/* ==========================================================================
   Klawiatura PIN – obsługa myszą i klawiaturą, identyfikator służbowy,
   tryb zmiany kodu (nowy + powtórzenie), blokada po błędach.
   ========================================================================== */
DL.Keypad = (() => {
  let cur = null;
  const LETTERS = ['', 'ABC', 'DEF', 'GHI', 'JKL', 'MNO', 'PQRS', 'TUV', 'WXYZ'];

  const lcd = (l1, l2, cls = '') => {
    cur.lcd.className = 'lcd ' + cls;
    cur.l1.innerHTML = l1;
    cur.l2.innerHTML = l2;
  };
  const dots = () => {
    const max = DL.cfg.keypad.max;
    return cur.pin.split('').map(() => '<i></i>').join('') + (cur.pin.length < max ? '<span class="cur"></span>' : '');
  };
  const title = () => (cur.mode === 'change' ? (cur.first ? 'POWTÓRZ KOD' : 'NOWY KOD') : 'WPROWADŹ KOD');
  const idle = () => lcd(`<span>${title()}</span><span>${cur.pin.length}/${DL.cfg.keypad.max}</span>`, dots());

  const setLed = c => { cur.led.className = 'led ' + (c || ''); };

  const press = k => {
    if (!cur || cur.busy) return;
    const btn = cur.keys[k];
    if (btn) { btn.classList.add('down'); setTimeout(() => btn.classList.remove('down'), 110); }
    if (/^\d$/.test(k)) {
      if (cur.pin.length >= DL.cfg.keypad.max) return DL.Audio.play('error', 0.4);
      cur.pin += k;
      DL.Audio.play('beep');
      idle();
    } else if (k === 'C') {
      cur.pin = cur.pin.slice(0, -1);
      DL.Audio.play('beep', 0.6);
      idle();
    } else if (k === 'OK') {
      submit();
    }
  };

  const fail = (msg, cls = 'err', led = 'red') => {
    lcd(`<span>${msg}</span><span></span>`, cls === 'lock' ? '— — — —' : 'BŁĄD', cls);
    setLed(led);
    cur.box.classList.remove('shake');
    void cur.box.offsetWidth;
    cur.box.classList.add('shake');
    DL.Audio.play('deny');
  };

  const success = (l2 = 'OTWARTE') => {
    lcd('<span>DOSTĘP PRZYZNANY</span><span>✓</span>', l2, 'ok');
    setLed('green');
    DL.Audio.play('ok');
    setTimeout(() => DL.layer.close(), 900);
  };

  const submit = async () => {
    const min = DL.cfg.keypad.min;
    if (cur.pin.length < min) return fail(`MIN. ${min} CYFRY`);
    if (cur.mode === 'change') {
      if (!cur.first) { cur.first = cur.pin; cur.pin = ''; DL.Audio.play('lockin', 0.7); return idle(); }
      if (cur.first !== cur.pin) { cur.first = null; cur.pin = ''; fail('KODY RÓŻNE'); return setTimeout(() => cur && idle(), 1200); }
      cur.busy = true;
      lcd('<span>ZAPISYWANIE…</span><span></span>', '· · ·');
      const res = await DL.post('keypad', { id: cur.id, change: cur.pin });
      if (!cur) return;
      cur.busy = false;
      if (res && res.ok) { DL.toast(res.msg || 'Kod zmieniony', 'success'); return success('ZAPISANO'); }
      cur.first = null; cur.pin = '';
      fail('ODRZUCONO');
      if (res && res.msg) DL.toast(res.msg, 'error');
      return setTimeout(() => cur && idle(), 1400);
    }
    send({ id: cur.id, pin: cur.pin });
  };

  const send = async payload => {
    cur.busy = true;
    lcd('<span>WERYFIKACJA…</span><span></span>', '· · ·');
    setLed('amber');
    const res = await DL.post('keypad', payload);
    if (!cur) return;
    cur.busy = false;
    cur.pin = '';
    if (res && res.ok) return success(res.locked ? 'ZAMKNIĘTE' : 'OTWARTE');
    if (res && res.reason === 'lockout') {
      fail(`BLOKADA ${res.seconds}s`, 'lock', 'amber');
      cur.busy = true;
      let s = res.seconds;
      const iv = setInterval(() => {
        if (!cur) return clearInterval(iv);
        s -= 1;
        cur.l1.innerHTML = `<span>BLOKADA ${s}s</span><span></span>`;
        if (s <= 0) { clearInterval(iv); cur.busy = false; setLed(); idle(); }
      }, 1000);
      return;
    }
    fail(res && res.reason === 'wrong_pin' ? `BŁĘDNY KOD · ${res.left}` : (res && res.reason === 'denied' ? 'BRAK DOSTĘPU' : 'ODMOWA'));
    setTimeout(() => { if (cur && !cur.busy) { setLed(); idle(); } }, 1300);
  };

  const open = d => {
    const box = DL.h('div.device.keypad');
    const map = { 1: 1, 2: 2, 3: 3, 4: 4, 5: 5, 6: 6, 7: 7, 8: 8, 9: 9 };
    box.innerHTML = `
      <i class="screw tl"></i><i class="screw tr"></i><i class="screw bl"></i><i class="screw br"></i>
      <button class="dev-close">${DL.icon('x')}</button>
      <div class="dev-head"><div class="t"><b>${DL.esc(d.name)}</b><span>${DL.esc(d.group || 'Zamek szyfrowy')}</span></div><i class="led"></i></div>
      <div class="lcd"><div class="l1"></div><div class="l2"></div></div>
      <div class="keys"></div>
      <div class="kp-foot"></div>`;
    const keys = DL.$('.keys', box), btns = {};
    const add = (k, html, cls = '') => {
      const b = DL.h('button.key' + cls, { html, onmousedown: e => { e.preventDefault(); press(k); } });
      btns[k] = b;
      keys.append(b);
    };
    Object.keys(map).forEach(n => add(n, `<b>${n}</b><small>${LETTERS[n - 1] || '&nbsp;'}</small>`));
    add('C', `${DL.icon('back')}<small>USUŃ</small>`, '.fn.clear');
    add('0', '<b>0</b><small>+</small>');
    add('OK', `${DL.icon('check')}<small>OK</small>`, '.fn.enter');
    const foot = DL.$('.kp-foot', box);
    if (d.mode !== 'change') {
      foot.append(DL.h('button.btn', { html: `${DL.icon('shield')}Identyfikator`, onclick: () => cur && !cur.busy && send({ id: cur.id, badge: true }) }));
    }
    foot.append(DL.h('button.btn.ghost', { html: 'Anuluj', onclick: () => DL.layer.close() }));
    DL.$('.dev-close', box).onclick = () => DL.layer.close();

    cur = { id: d.id, mode: d.mode || 'use', pin: '', first: null, busy: false, box, keys: btns,
      lcd: DL.$('.lcd', box), l1: DL.$('.l1', box), l2: DL.$('.l2', box), led: DL.$('.led', box) };
    DL.layer.open('keypad', box, () => { cur = null; });
    idle();
    DL.Audio.play('open');
  };

  const key = e => {
    if (!cur) return false;
    if (/^\d$/.test(e.key)) press(e.key);
    else if (e.key === 'Backspace') press('C');
    else if (e.key === 'Enter') press('OK');
    else return false;
    return true;
  };

  return { open, key };
})();
