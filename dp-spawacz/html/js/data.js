'use strict';
/* ==========================================================================
   Stałe rozgrywki: procesy, materiały, pozycje, wagi oceny
   (wagi i progi ocen MUSZĄ zgadzać się z Config.Scoring po stronie serwera)
   ========================================================================== */

W.PROC = {
  MMA: {
    label: 'MMA', name: 'Elektroda otulona (MMA / 111)',
    v: 62, poolR: 12, heat: 1.0, sparks: 95, arcDrift: 0.2, creep: 0.05,
    consumable: 'electrode', slag: true,
  },
  MAG: {
    label: 'MIG/MAG', name: 'Drut w osłonie gazu (MAG / 135)',
    v: 92, poolR: 13, heat: 0.9, sparks: 150, arcDrift: 0.15, creep: 0,
    consumable: 'nozzle', slag: false,
  },
  TIG: {
    label: 'TIG', name: 'Elektroda wolframowa (TIG / 141)',
    v: 42, poolR: 10, heat: 1.05, sparks: 6, arcDrift: 0.11, creep: 0,
    consumable: 'filler', slag: false,
  },
};

W.MAT = {
  steel: {
    label: 'Stal węglowa S235', heat: 1.0, cool: 1.0, burn: 1.0, speed: 1.0, interpass: 250,
    col: ['#3b4147', '#5c636a', '#8a9198'], bead: ['#d9dde0', '#8f969c', '#4a5055'], tint: false,
  },
  stainless: {
    label: 'Stal nierdzewna 1.4301', heat: 1.08, cool: 0.8, burn: 0.94, speed: 0.95, interpass: 150,
    col: ['#6a7178', '#9aa1a8', '#cdd2d7'], bead: ['#f1f3f5', '#aab1b8', '#62696f'], tint: true,
  },
  aluminium: {
    label: 'Aluminium 6061', heat: 0.85, cool: 1.6, burn: 0.86, speed: 1.25, interpass: 120,
    col: ['#8b9197', '#bbc0c5', '#e6e9ec'], bead: ['#ffffff', '#c3c8cc', '#7d8388'], tint: false,
  },
};

W.POSI = {
  flat: { label: 'PA – podolna', tremor: 0, heat: 1.0, drip: 9 },
  vertical: { label: 'PF – pionowa z dołu do góry', tremor: 1.6, heat: 1.06, drip: 0.84 },
  overhead: { label: 'PE – pułapowa', tremor: 3.0, heat: 1.1, drip: 0.72 },
};

W.TYPES = {
  crack: 'Pęknięcie rury',
  butt: 'Złącze doczołowe',
  fillet: 'Spoina pachwinowa',
  patch: 'Łata na zbiorniku',
};

W.PASS_NAMES = ['Graniowe', 'Wypełniające', 'Licowe'];

W.WEIGHTS = { setup: 0.1, prep: 0.15, prep2: 0.1, weld: 0.55, finish: 0.1 };
W.GRADES = [[93, 'S'], [82, 'A'], [68, 'B'], [52, 'C'], [40, 'D'], [0, 'F']];
W.grade = q => W.GRADES.find(g => q >= g[0])[1];

W.DEFECTS = {
  burn: 'Przepalenia',
  lof: 'Brak przetopu / wypełnienia',
  poro: 'Porowatość',
  incl: 'Wtrącenia',
  undercut: 'Podtopienia lica',
  sag: 'Nawisy / krople',
  stray: 'Zajarzenia poza rowkiem',
  spatter: 'Odpryski',
  gouge: 'Podcięcia szlifierką',
};

/* Parametry idealne wg karty WPS (gracz musi je wyliczyć ze ściągawki) */
W.ideal = t => {
  const th = t.thickness;
  const posM = t.position === 'vertical' ? 0.9 : t.position === 'overhead' ? 0.88 : 1;
  const alu = t.material === 'aluminium';
  if (t.process === 'MMA') {
    const d = th <= 3 ? 2.5 : th <= 8 ? 3.2 : 4.0;
    return {
      amp: Math.round(d * 38 * posM), pol: 'DC+',
      sec: { kind: 'choice', value: d, options: [2.5, 3.2, 4.0], label: 'Średnica elektrody', unit: 'mm' },
    };
  }
  if (t.process === 'MAG') {
    const amp = Math.round((35 + th * 18) * (alu ? 0.9 : 1) * posM);
    const wire = Math.round((amp / 22) * (alu ? 1.4 : 1) * 10) / 10;
    return {
      amp, pol: 'DC+',
      sec: { kind: 'knob', value: wire, min: 2, max: 16, step: 0.1, fine: 0.1, label: 'Posuw drutu', unit: 'm/min', tolRel: 0.12 },
    };
  }
  const per = t.material === 'stainless' ? [28, 5] : alu ? [40, 10] : [32, 5];
  const gas = t.material === 'stainless' ? 9 : alu ? 12 : 8;
  return {
    amp: Math.round((th * per[0] + per[1]) * posM),
    pol: alu ? 'AC' : 'DC-',
    sec: { kind: 'knob', value: gas, min: 4, max: 20, step: 0.5, fine: 0.5, label: 'Przepływ argonu', unit: 'l/min', tolAbs: 2 },
  };
};

W.CHEATSHEET = {
  MMA: [
    ['Średnica elektrody', 'do 3 mm → 2,5 · do 8 mm → 3,2 · powyżej → 4,0'],
    ['Natężenie prądu', '≈ 38 A × średnica elektrody [mm]'],
    ['Biegunowość', 'elektrody zasadowe: DC+ (plus na uchwycie)'],
    ['Pozycja', 'PF: −10% prądu · PE: −12% prądu'],
  ],
  MAG: [
    ['Natężenie prądu', '≈ 35 A + 18 A × grubość [mm] (aluminium ×0,9)'],
    ['Posuw drutu', '≈ prąd ÷ 22 [m/min] (aluminium ×1,4)'],
    ['Biegunowość', 'DC+ (drut na plusie)'],
    ['Pozycja', 'PF: −10% prądu · PE: −12% prądu'],
  ],
  TIG: [
    ['Natężenie prądu', 'stal: 32 A/mm + 5 · nierdzewna: 28 A/mm + 5 · alu: 40 A/mm + 10'],
    ['Biegunowość', 'stal i nierdzewna: DC− · aluminium: AC (czyszczenie tlenków)'],
    ['Argon', 'stal 8 · nierdzewna 9 · aluminium 12 l/min (±2)'],
    ['Pozycja', 'PF: −10% prądu · PE: −12% prądu'],
  ],
};
