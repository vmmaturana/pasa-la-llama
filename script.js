/* Haus Of Wonder — landing
   Sin dependencias. Un solo IIFE, igual que el resto de piezas de la agencia. */
(function () {
  'use strict';

  var reduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  /* ---------- Año del footer ---------- */
  var year = document.getElementById('year');
  if (year) year.textContent = new Date().getFullYear();

  /* ---------- Header al hacer scroll ---------- */
  var header = document.getElementById('header');
  window.addEventListener('scroll', function () {
    header.classList.toggle('is-scrolled', window.scrollY > 12);
  }, { passive: true });

  /* ---------- Menú móvil ---------- */
  var toggle = document.getElementById('navToggle');
  var nav = document.getElementById('nav');
  function closeNav() {
    nav.classList.remove('is-open');
    toggle.setAttribute('aria-expanded', 'false');
    toggle.setAttribute('aria-label', 'Abrir menú');
  }
  toggle.addEventListener('click', function () {
    var open = nav.classList.toggle('is-open');
    toggle.setAttribute('aria-expanded', open ? 'true' : 'false');
    toggle.setAttribute('aria-label', open ? 'Cerrar menú' : 'Abrir menú');
  });
  nav.addEventListener('click', function (e) {
    if (e.target.tagName === 'A') closeNav();
  });
  document.addEventListener('keydown', function (e) {
    if (e.key === 'Escape') closeNav();
  });

  /* ---------- Revelado al entrar en pantalla ---------- */
  var revealables = document.querySelectorAll('.reveal');
  if ('IntersectionObserver' in window && !reduced) {
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry, i) {
        if (!entry.isIntersecting) return;
        var el = entry.target;
        setTimeout(function () { el.classList.add('is-visible'); }, i * 70);
        io.unobserve(el);
      });
    }, { rootMargin: '0px 0px -10% 0px' });
    revealables.forEach(function (el) { io.observe(el); });
  } else {
    revealables.forEach(function (el) { el.classList.add('is-visible'); });
  }

  /* ---------- Árbol de muestra ----------
     Cuatro familias, diez líneas por familia y cadenas de hasta cinco personas.
     Datos de ejemplo con semilla fija: la misma forma en todas las visitas. */
  var tree = document.getElementById('tree');
  if (!tree) return;

  var seed = 1907;
  function rnd() {
    seed = (seed * 1103515245 + 12345) & 0x7fffffff;
    return seed / 0x7fffffff;
  }

  var SIZE = 600, C = SIZE / 2, R_FAM = 74, R_LINE = 112, STEP = 25;
  var FAMILIES = [
    { name: 'ORÁCULO', color: '#ff2a1f' },
    { name: 'CARRUSEL', color: '#ff8a7a' },
    { name: 'ALQUIMIA', color: '#f4efe9' },
    { name: 'INVERNADERO', color: '#c23b2f' }
  ];
  var LINES_PER_FAMILY = 10;

  var ns = 'http://www.w3.org/2000/svg';
  function el(name, attrs) {
    var node = document.createElementNS(ns, name);
    for (var k in attrs) node.setAttribute(k, attrs[k]);
    return node;
  }
  function at(angle, radius) {
    return [C + Math.cos(angle) * radius, C + Math.sin(angle) * radius];
  }

  var svg = el('svg', { viewBox: '0 0 ' + SIZE + ' ' + SIZE, 'aria-hidden': 'true' });
  svg.appendChild(el('circle', {
    cx: C, cy: C, r: R_LINE - 4, fill: 'none',
    stroke: '#2a2424', 'stroke-dasharray': '2 7'
  }));

  var grown = [];   // trazos que se dibujan progresivamente
  var dots = [];    // personas que aparecen después de su trazo

  FAMILIES.forEach(function (fam, fi) {
    var a = -Math.PI / 2 + fi * Math.PI / 2;
    var famPoint = at(a, R_FAM);

    var trunk = el('line', {
      x1: C, y1: C, x2: famPoint[0], y2: famPoint[1],
      stroke: fam.color, 'stroke-width': 7, 'stroke-linecap': 'round'
    });
    svg.appendChild(trunk);
    grown.push({ node: trunk, length: R_FAM, delay: fi * 90 });

    for (var i = 0; i < LINES_PER_FAMILY; i++) {
      var la = a + (i - (LINES_PER_FAMILY - 1) / 2) * 0.115;
      var start = at(la, R_LINE);
      var people = Math.floor(Math.pow(rnd(), 1.3) * 6);
      var end = at(la, R_LINE + STEP * Math.max(people, 0.4));

      var ctrl = at(a, R_FAM + 28);
      var branch = el('path', {
        d: 'M' + famPoint[0] + ' ' + famPoint[1] + ' Q' + ctrl[0] + ' ' + ctrl[1] + ' ' + start[0] + ' ' + start[1],
        fill: 'none', stroke: fam.color, 'stroke-width': 1.4, opacity: '.75'
      });
      svg.appendChild(branch);
      grown.push({ node: branch, length: branch.getTotalLength ? 0 : 0, delay: 260 + fi * 90 + i * 28 });

      var line = el('line', {
        x1: start[0], y1: start[1], x2: end[0], y2: end[1],
        stroke: fam.color, 'stroke-width': people ? 2 : 1,
        opacity: people ? '.9' : '.35',
        'stroke-dasharray': people ? '' : '3 4'
      });
      svg.appendChild(line);
      // Las líneas sin escanear quedan punteadas y quietas: el trazo animado
      // sobrescribiría su patrón de guiones.
      if (people) grown.push({ node: line, length: STEP * people, delay: 480 + fi * 90 + i * 28 });

      for (var k = 0; k < people; k++) {
        var p = at(la, R_LINE + STEP * (k + 1));
        var dot = el('circle', {
          cx: p[0], cy: p[1], r: 3.6, fill: fam.color,
          stroke: '#000', 'stroke-width': 1.2, opacity: '0'
        });
        svg.appendChild(dot);
        dots.push({ node: dot, delay: 640 + fi * 90 + i * 28 + k * 60 });
      }
    }

    var label = at(a, 286);
    var text = el('text', {
      x: label[0], y: label[1] + 4, 'text-anchor': 'middle',
      fill: '#a39a95', 'font-size': 11, 'letter-spacing': '2.4',
      'font-family': 'Roboto Mono, monospace'
    });
    text.textContent = fam.name;
    svg.appendChild(text);

    var hub = el('circle', { cx: famPoint[0], cy: famPoint[1], r: 7, fill: fam.color });
    svg.appendChild(hub);
  });

  var core = el('circle', { cx: C, cy: C, r: 26, fill: '#ff2a1f' });
  svg.appendChild(core);
  var coreText = el('text', {
    x: C, y: C + 4, 'text-anchor': 'middle', fill: '#120403',
    'font-size': 10, 'letter-spacing': '1.6', 'font-family': 'Roboto Mono, monospace'
  });
  coreText.textContent = 'HOW';
  svg.appendChild(coreText);

  tree.appendChild(svg);

  if (reduced) {
    dots.forEach(function (d) { d.node.setAttribute('opacity', '1'); });
    return;
  }

  /* El árbol se dibuja solo la primera vez que entra en pantalla. */
  function animate() {
    grown.forEach(function (item) {
      var node = item.node;
      var length = node.getTotalLength ? node.getTotalLength() : item.length;
      node.style.strokeDasharray = length + ' ' + length;
      node.style.strokeDashoffset = length;
      setTimeout(function () {
        node.style.transition = 'stroke-dashoffset .7s cubic-bezier(.22,1,.36,1)';
        node.style.strokeDashoffset = '0';
      }, item.delay);
    });
    dots.forEach(function (d) {
      setTimeout(function () {
        d.node.style.transition = 'opacity .45s ease';
        d.node.setAttribute('opacity', '1');
      }, d.delay);
    });
  }

  if ('IntersectionObserver' in window) {
    var treeIO = new IntersectionObserver(function (entries) {
      if (entries[0].isIntersecting) { animate(); treeIO.disconnect(); }
    }, { threshold: 0.25 });
    treeIO.observe(tree);
  } else {
    animate();
  }
})();
