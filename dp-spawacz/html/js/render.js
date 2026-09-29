'use strict';
/* ==========================================================================
   Grafika: generowanie detalu (rura/blachy/zbiornik), lico spoiny, cząsteczki
   ========================================================================== */

/* --------------------------------------------------------------------------
   Cząsteczki – bufor pierścieniowy na typowanych tablicach (zero GC)
   rodzaje: 0 iskra, 1 opiłek, 2 mgiełka, 3 żużel, 4 kropla, 5 dym
   -------------------------------------------------------------------------- */
W.Particles = class {
  constructor(n) {
    this.n = n;
    this.x = new Float32Array(n); this.y = new Float32Array(n);
    this.vx = new Float32Array(n); this.vy = new Float32Array(n);
    this.life = new Float32Array(n); this.max = new Float32Array(n);
    this.size = new Float32Array(n); this.kind = new Uint8Array(n);
    this.i = 0;
  }
  emit(x, y, vx, vy, life, kind = 0, size = 1) {
    const i = this.i;
    this.i = (i + 1) % this.n;
    this.x[i] = x; this.y[i] = y; this.vx[i] = vx; this.vy[i] = vy;
    this.life[i] = life; this.max[i] = life; this.kind[i] = kind; this.size[i] = size;
  }
  burst(x, y, count, speed, kind, life = 0.6, size = 1, dir = -Math.PI / 2, spread = Math.PI) {
    for (let k = 0; k < count; k++) {
      const a = dir + (Math.random() - 0.5) * spread * 2;
      const s = speed * (0.3 + Math.random() * 0.9);
      this.emit(x, y, Math.cos(a) * s, Math.sin(a) * s, life * (0.5 + Math.random()), kind, size * (0.6 + Math.random() * 0.8));
    }
  }
  clear() { this.life.fill(0); }
  update(dt) {
    const G = [620, 900, -10, 900, 700, -25];
    const D = [0.4, 0.8, 2.5, 0.6, 0.2, 1.2];
    for (let i = 0; i < this.n; i++) {
      if (this.life[i] <= 0) continue;
      const k = this.kind[i];
      this.life[i] -= dt;
      this.vy[i] += G[k] * dt;
      const d = 1 - Math.min(1, D[k] * dt);
      this.vx[i] *= d; this.vy[i] *= d;
      this.x[i] += this.vx[i] * dt;
      this.y[i] += this.vy[i] * dt;
      if (k === 0 && this.y[i] > 700 && this.vy[i] > 0) { this.vy[i] *= -0.35; this.vx[i] *= 0.6; }
    }
  }
  render(g) {
    g.save();
    g.globalCompositeOperation = 'lighter';
    g.lineCap = 'round';
    for (let i = 0; i < this.n; i++) {
      if (this.life[i] <= 0 || this.kind[i] !== 0) continue;
      const t = this.life[i] / this.max[i];
      g.strokeStyle = `hsla(${28 + t * 22},100%,${45 + t * 45}%,${Math.min(1, t * 1.6)})`;
      g.lineWidth = this.size[i] * (0.8 + t);
      g.beginPath();
      g.moveTo(this.x[i], this.y[i]);
      g.lineTo(this.x[i] - this.vx[i] * 0.022, this.y[i] - this.vy[i] * 0.022);
      g.stroke();
    }
    for (let i = 0; i < this.n; i++) {
      if (this.life[i] <= 0 || this.kind[i] !== 4) continue;
      const t = this.life[i] / this.max[i];
      g.fillStyle = `rgba(255,${120 + t * 100},40,${t})`;
      g.beginPath();
      g.arc(this.x[i], this.y[i], 2.2 * this.size[i], 0, Math.PI * 2);
      g.fill();
    }
    g.globalCompositeOperation = 'source-over';
    for (let i = 0; i < this.n; i++) {
      const k = this.kind[i];
      if (this.life[i] <= 0 || k === 0 || k === 4) continue;
      const t = this.life[i] / this.max[i];
      if (k === 1 || k === 3) {
        g.fillStyle = k === 1 ? `rgba(190,195,200,${t})` : `rgba(70,55,40,${t})`;
        const s = this.size[i] * (k === 3 ? 4 : 2);
        g.fillRect(this.x[i] - s / 2, this.y[i] - s / 2, s, s);
      } else {
        g.fillStyle = k === 2 ? `rgba(200,230,255,${t * 0.25})` : `rgba(120,120,120,${t * 0.18})`;
        g.beginPath();
        g.arc(this.x[i], this.y[i], this.size[i] * (k === 5 ? 30 : 10) * (1.6 - t), 0, Math.PI * 2);
        g.fill();
      }
    }
    g.restore();
  }
};

/* --------------------------------------------------------------------------
   Tekstury
   -------------------------------------------------------------------------- */
function brushed(g, x, y, w, h, rand, alpha = 0.06, vertical = false) {
  g.save();
  g.beginPath();
  g.rect(x, y, w, h);
  g.clip();
  for (let i = 0; i < 900; i++) {
    const l = rand() > 0.5 ? 255 : 0;
    g.strokeStyle = `rgba(${l},${l},${l},${alpha * rand()})`;
    g.lineWidth = rand() * 1.4 + 0.3;
    g.beginPath();
    if (vertical) {
      const px = x + rand() * w, py = y + rand() * h;
      g.moveTo(px, py);
      g.lineTo(px + (rand() - 0.5) * 3, py + 40 + rand() * 260);
    } else {
      const px = x + rand() * w, py = y + rand() * h;
      g.moveTo(px, py);
      g.lineTo(px + 40 + rand() * 300, py + (rand() - 0.5) * 3);
    }
    g.stroke();
  }
  for (let i = 0; i < 260; i++) {
    g.fillStyle = `rgba(0,0,0,${0.05 + rand() * 0.08})`;
    g.fillRect(x + rand() * w, y + rand() * h, 1 + rand() * 2, 1 + rand() * 2);
  }
  g.restore();
}

function bench(g, rand) {
  const gr = g.createLinearGradient(0, 0, 0, W.VH);
  gr.addColorStop(0, '#15181b');
  gr.addColorStop(1, '#0b0d0f');
  g.fillStyle = gr;
  g.fillRect(0, 0, W.VW, W.VH);
  for (let i = 0; i < 1500; i++) {
    g.fillStyle = `rgba(255,255,255,${rand() * 0.025})`;
    g.fillRect(rand() * W.VW, rand() * W.VH, 2, 2);
  }
}

function regionFromPath(g, path, off, corners) {
  g.beginPath();
  for (let i = 0; i < path.n; i++) {
    const x = path.x[i] + path.nx[i] * off, y = path.y[i] + path.ny[i] * off;
    if (i === 0) g.moveTo(x, y);
    else g.lineTo(x, y);
  }
  for (const c of corners) g.lineTo(c[0], c[1]);
  g.closePath();
}

/* --------------------------------------------------------------------------
   Detal – generowany z seeda zlecenia
   -------------------------------------------------------------------------- */
W.buildPiece = (task, rand) => {
  const M = W.MAT[task.material] || W.MAT.steel;
  const [lo, mid, hi] = M.col;
  const base = W.canvas();
  const g = base.getContext('2d');
  bench(g, rand);
  const diff = task.difficulty || 1;
  const piece = { kind: task.type, zone: 44, M };

  if (task.type === 'crack') {
    /* rura – cieniowanie cylindryczne */
    const y0 = 110, y1 = 610;
    const gr = g.createLinearGradient(0, y0, 0, y1);
    gr.addColorStop(0, '#16191c');
    gr.addColorStop(0.08, lo);
    gr.addColorStop(0.3, hi);
    gr.addColorStop(0.5, mid);
    gr.addColorStop(0.82, lo);
    gr.addColorStop(1, '#101214');
    g.fillStyle = gr;
    g.fillRect(0, y0, W.VW, y1 - y0);
    brushed(g, 0, y0, W.VW, y1 - y0, rand, 0.05);
    /* stary spaw obwodowy (dekoracja) */
    for (const sx of [90, 1190]) {
      for (let yy = y0; yy < y1; yy += 3) {
        const sh = 0.5 + 0.5 * Math.sin(((yy - y0) / (y1 - y0)) * Math.PI);
        g.fillStyle = `rgba(${140 * sh + 40},${140 * sh + 40},${145 * sh + 40},0.9)`;
        g.beginPath();
        g.ellipse(sx, yy, 11, 3, 0, 0, Math.PI * 2);
        g.fill();
      }
    }
    /* pęknięcie */
    const n = 7 + rand.int(0, 2) + diff;
    const x0 = rand.range(250, 320), x1 = rand.range(900, 970);
    const amp = 40 + diff * 18;
    const ctrl = [];
    let yy = 360 + rand.range(-60, 60);
    for (let i = 0; i < n; i++) {
      const t = i / (n - 1);
      ctrl.push([W.lerp(x0, x1, t) + rand.range(-18, 18), W.clamp(yy, 220, 500)]);
      yy += rand.range(-amp, amp);
    }
    piece.path = new W.Path(ctrl, { steps: 10 });
    const p = piece.path;
    /* rysunek pęknięcia: poszarpana linia zanikająca przy końcach (końce ukryte!) */
    const hide = 34;
    g.lineCap = 'round';
    for (let pass = 0; pass < 2; pass++) {
      for (let i = 1; i < p.n; i++) {
        const s = i * p.sp;
        const edge = Math.min(s, p.len - s);
        const a = W.clamp((edge - hide) / 50, 0, 1);
        if (a <= 0) continue;
        const j = () => (rand() - 0.5) * 2.4;
        g.strokeStyle = pass === 0 ? `rgba(255,255,255,${0.12 * a})` : `rgba(8,8,10,${0.9 * a})`;
        g.lineWidth = pass === 0 ? 3.5 : 1.2 + 1.3 * a;
        g.beginPath();
        g.moveTo(p.x[i - 1] + j() + (pass === 0 ? 1 : 0), p.y[i - 1] + j() + (pass === 0 ? 1.5 : 0));
        g.lineTo(p.x[i] + j() + (pass === 0 ? 1 : 0), p.y[i] + j() + (pass === 0 ? 1.5 : 0));
        g.stroke();
      }
    }
    /* mikropęknięcia boczne */
    for (let k = 0; k < 4 + diff; k++) {
      const i = rand.int(Math.floor(p.n * 0.2), Math.floor(p.n * 0.8));
      let x = p.x[i], y = p.y[i];
      const dir = rand() > 0.5 ? 1 : -1;
      g.strokeStyle = 'rgba(10,10,12,0.55)';
      g.lineWidth = 0.8;
      g.beginPath();
      g.moveTo(x, y);
      for (let s = 0; s < 4; s++) {
        x += p.nx[i] * dir * rand.range(3, 7) + rand.range(-4, 4);
        y += p.ny[i] * dir * rand.range(3, 7) + rand.range(-4, 4);
        g.lineTo(x, y);
      }
      g.stroke();
    }
    piece.tips = [
      { x: p.x[0], y: p.y[0], dx: -Math.cos(p.ang[0]), dy: -Math.sin(p.ang[0]) },
      { x: p.x[p.n - 1], y: p.y[p.n - 1], dx: Math.cos(p.ang[p.n - 1]), dy: Math.sin(p.ang[p.n - 1]) },
    ];
    piece.zone = 40;
  } else if (task.type === 'butt' || task.type === 'fillet') {
    const n = 6;
    const ctrl = [];
    const tilt = rand.range(-80, 80);
    const wav = task.type === 'butt' ? 25 + diff * 12 : 8;
    for (let i = 0; i < n; i++) {
      const t = i / (n - 1);
      ctrl.push([W.lerp(160, 1120, t), 360 + tilt * (t - 0.5) + Math.sin(t * Math.PI * rand.range(1, 2.2)) * wav]);
    }
    if (task.type === 'fillet' && diff >= 3) {
      /* spoina z zagięciem – wymusza zmianę kierunku prowadzenia */
      ctrl[3][1] += rand() > 0.5 ? 70 : -70;
    }
    /* złącze biegnie przez cały kadr, spawamy odcinek między znacznikami */
    const ext = [[-80, ctrl[0][1] - tilt * 0.2], ...ctrl, [1360, ctrl[n - 1][1] + tilt * 0.2]];
    const full = new W.Path(ext);
    const keep = [];
    for (let i = 0; i < full.n; i++) if (full.x[i] >= 230 && full.x[i] <= 985) keep.push([full.x[i], full.y[i]]);
    piece.path = new W.Path(keep, { smooth: false });
    piece.full = full;
    const p = piece.full;
    const wp = piece.path;
    if (task.type === 'butt') {
      const gap = 3;
      /* blacha dolna */
      g.fillStyle = mid;
      regionFromPath(g, p, gap, [[1300, 730], [-20, 730]]);
      g.fill();
      /* blacha górna */
      const gr = g.createLinearGradient(0, 0, 0, W.VH);
      gr.addColorStop(0, hi);
      gr.addColorStop(1, mid);
      g.fillStyle = gr;
      regionFromPath(g, p, -gap, [[1300, -20], [-20, -20]]);
      g.fill();
      brushed(g, 0, 0, W.VW, W.VH, rand, 0.045);
      /* ukosowanie (fazowanie krawędzi) */
      g.lineWidth = 12;
      g.strokeStyle = 'rgba(255,255,255,0.18)';
      p.strokeOffset(g, -9);
      g.strokeStyle = 'rgba(0,0,0,0.22)';
      p.strokeOffset(g, 9);
      g.lineWidth = gap * 2;
      g.strokeStyle = '#07080a';
      p.stroke(g);
    } else {
      /* płyta pozioma */
      g.fillStyle = mid;
      g.fillRect(0, 0, W.VW, W.VH);
      brushed(g, 0, 0, W.VW, W.VH, rand, 0.045);
      /* środnik (pionowa ścianka) nad linią spoiny */
      const gr = g.createLinearGradient(0, 0, 0, 380);
      gr.addColorStop(0, '#202428');
      gr.addColorStop(1, lo);
      g.fillStyle = gr;
      regionFromPath(g, p, -2, [[1300, -20], [-20, -20]]);
      g.fill();
      brushed(g, 0, 0, W.VW, 360, rand, 0.04, true);
      g.lineWidth = 10;
      g.strokeStyle = 'rgba(0,0,0,0.35)';
      p.strokeOffset(g, 5);
      g.lineWidth = 2;
      g.strokeStyle = 'rgba(255,255,255,0.25)';
      p.strokeOffset(g, -3);
    }
    /* znaczniki kredą: początek i koniec spoiny */
    g.strokeStyle = 'rgba(245,245,235,0.8)';
    g.lineWidth = 3;
    g.lineCap = 'round';
    for (const i of [0, wp.n - 1]) {
      g.beginPath();
      g.moveTo(wp.x[i] - wp.nx[i] * 34, wp.y[i] - wp.ny[i] * 34);
      g.lineTo(wp.x[i] - wp.nx[i] * 14, wp.y[i] - wp.ny[i] * 14);
      g.moveTo(wp.x[i] + wp.nx[i] * 14, wp.y[i] + wp.ny[i] * 14);
      g.lineTo(wp.x[i] + wp.nx[i] * 34, wp.y[i] + wp.ny[i] * 34);
      g.stroke();
    }

  } else {
    /* patch – zbiornik + łata; ścieżka zamknięta wokół łaty */
    const gr = g.createLinearGradient(0, 0, W.VW, 0);
    gr.addColorStop(0, lo);
    gr.addColorStop(0.45, hi);
    gr.addColorStop(1, lo);
    g.fillStyle = gr;
    g.fillRect(0, 60, W.VW, 600);
    brushed(g, 0, 60, W.VW, 600, rand, 0.05, true);
    /* rdzawe zacieki starego zbiornika */
    for (let i = 0; i < 40; i++) {
      g.fillStyle = `rgba(120,60,20,${rand() * 0.08})`;
      g.fillRect(rand() * W.VW, 60 + rand() * 500, 3 + rand() * 8, 40 + rand() * 140);
    }
    const w = rand.range(360, 470) + diff * 10, h = rand.range(190, 240);
    const cx = 640 + rand.range(-50, 50), cy = 360 + rand.range(-20, 20);
    const r = 34;
    const ctrl = [];
    const corner = (ox, oy, a0) => {
      for (let k = 0; k <= 6; k++) {
        const a = a0 + (k / 6) * (Math.PI / 2);
        ctrl.push([ox + Math.cos(a) * r, oy + Math.sin(a) * r]);
      }
    };
    corner(cx + w / 2 - r, cy - h / 2 + r, -Math.PI / 2);
    corner(cx + w / 2 - r, cy + h / 2 - r, 0);
    corner(cx - w / 2 + r, cy + h / 2 - r, Math.PI / 2);
    corner(cx - w / 2 + r, cy - h / 2 + r, Math.PI);
    piece.path = new W.Path(ctrl, { closed: true, smooth: false });
    const p = piece.path;
    /* otwór pod łatą (ciemna szczelina) i sama łata */
    g.save();
    g.shadowColor = 'rgba(0,0,0,0.6)';
    g.shadowBlur = 14;
    g.shadowOffsetY = 5;
    const pg = g.createLinearGradient(cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2);
    pg.addColorStop(0, hi);
    pg.addColorStop(1, mid);
    g.fillStyle = pg;
    g.beginPath();
    for (let i = 0; i < p.n; i++) {
      const x = p.x[i] - p.nx[i] * 3, y = p.y[i] - p.ny[i] * 3;
      if (i === 0) g.moveTo(x, y);
      else g.lineTo(x, y);
    }
    g.closePath();
    g.fill();
    g.restore();
    brushed(g, cx - w / 2, cy - h / 2, w, h, rand, 0.05);
    g.lineWidth = 3;
    g.strokeStyle = '#08090b';
    p.stroke(g);
    g.lineWidth = 1.5;
    g.strokeStyle = 'rgba(255,255,255,0.3)';
    p.strokeOffset(g, -6);
  }

  /* winieta */
  const vg = g.createRadialGradient(640, 360, 250, 640, 360, 780);
  vg.addColorStop(0, 'rgba(0,0,0,0)');
  vg.addColorStop(1, 'rgba(0,0,0,0.55)');
  g.fillStyle = vg;
  g.fillRect(0, 0, W.VW, W.VH);

  piece.base = base;
  return piece;
};

/* --------------------------------------------------------------------------
   Pojedyncza „łuska” lica spoiny
   -------------------------------------------------------------------------- */
W.ripple = (g, x, y, ang, w, cols, alpha = 1) => {
  g.save();
  g.translate(x, y);
  g.rotate(ang);
  g.globalAlpha = alpha;
  const gr = g.createRadialGradient(-w * 0.15, -w * 0.3, 0.5, 0, 0, w);
  gr.addColorStop(0, cols[0]);
  gr.addColorStop(0.55, cols[1]);
  gr.addColorStop(1, cols[2]);
  g.fillStyle = gr;
  g.beginPath();
  g.ellipse(0, 0, w * 0.55, w, 0, 0, Math.PI * 2);
  g.fill();
  g.strokeStyle = 'rgba(25,25,25,0.28)';
  g.lineWidth = 0.9;
  g.beginPath();
  g.ellipse(-1, 0, w * 0.5, w * 0.9, 0, -Math.PI / 2, Math.PI / 2);
  g.stroke();
  g.restore();
};

W.hole = (g, x, y, r) => {
  const gr = g.createRadialGradient(x, y, r * 0.2, x, y, r * 1.6);
  gr.addColorStop(0, '#000');
  gr.addColorStop(0.55, '#050505');
  gr.addColorStop(0.7, 'rgba(110,60,25,0.9)');
  gr.addColorStop(1, 'rgba(60,40,30,0)');
  g.fillStyle = gr;
  g.beginPath();
  g.arc(x, y, r * 1.6, 0, Math.PI * 2);
  g.fill();
};

W.heatColor = h => {
  /* 0..1+ → czerwień → pomarańcz → żółć → biel */
  const t = W.clamp(h, 0, 1.2);
  const r = 255;
  const gg = Math.round(W.clamp((t - 0.25) * 330, 30, 255));
  const b = Math.round(W.clamp((t - 0.75) * 500, 0, 255));
  return `rgba(${r},${gg},${b},`;
};

/* uchwyt / elektroda / palnik rysowany przy kursorze */
W.drawTorch = (g, x, y, proc, t, extra = 0) => {
  g.save();
  g.translate(x, y);
  if (proc === 'MMA') {
    const L = 30 + 120 * W.clamp(extra, 0, 1);
    g.rotate(-0.75);
    g.strokeStyle = '#3c2f25';
    g.lineWidth = 5;
    g.beginPath();
    g.moveTo(0, 0);
    g.lineTo(0, -L);
    g.stroke();
    g.strokeStyle = '#9aa0a5';
    g.lineWidth = 2;
    g.beginPath();
    g.moveTo(0, -L);
    g.lineTo(0, -L - 14);
    g.stroke();
    g.fillStyle = '#1b1b1b';
    g.fillRect(-9, -L - 60, 18, 48);
    g.fillStyle = '#c1121f';
    g.fillRect(-9, -L - 60, 18, 8);
  } else if (proc === 'MAG') {
    g.rotate(-0.6);
    g.fillStyle = '#6b6f73';
    g.fillRect(-7, -34, 14, 30);
    g.fillStyle = '#a58d53';
    g.fillRect(-5, -6, 10, 6);
    g.fillStyle = '#1c1c1c';
    g.fillRect(-10, -120, 20, 88);
    g.strokeStyle = '#bb8a2b';
    g.lineWidth = 1.5;
    g.beginPath();
    g.moveTo(0, 0);
    g.lineTo(0, 5);
    g.stroke();
  } else {
    g.rotate(-0.5);
    g.fillStyle = '#c9c1b5';
    g.fillRect(-6, -30, 12, 22);
    g.fillStyle = '#b0b5ba';
    g.fillRect(-1.2, -8, 2.4, 9);
    g.fillStyle = '#1a1a1a';
    g.fillRect(-8, -120, 16, 90);
    /* pręt spoiwa z lewej */
    g.rotate(1.2);
    g.strokeStyle = '#d6c28b';
    g.lineWidth = 2;
    g.beginPath();
    g.moveTo(6 + t * 6, -6);
    g.lineTo(6 + t * 6, -150);
    g.stroke();
  }
  g.restore();
};
