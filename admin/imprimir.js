/* Hoja de etiquetas: un QR por encendedor, con su código impreso debajo. */
(function () {
  'use strict';

  var S = window.PLL;
  var $ = function (id) { return document.getElementById(id); };
  var data = { event: null, families: [], lighters: [] };

  function esc(s) {
    return String(s == null ? '' : s).replace(/[&<>"]/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c];
    });
  }
  function block(text, kind) {
    $('msg').innerHTML = text ? '<div class="msg msg--' + (kind || 'ok') + '">' + text + '</div>' : '';
  }

  async function boot() {
    if (!S.configured) {
      block('Falta conectar Supabase en <code>lib/supabase.js</code>.', 'warn');
      return;
    }
    var session = (await S.client.auth.getSession()).data.session;
    if (!session) {
      block('Entra primero en el <a href="/admin/index.html">panel</a>: las etiquetas solo las ve un administrador.', 'warn');
      return;
    }

    $('base').value = S.cfg.scanBase;

    var ev = await S.client.from('events').select('*').eq('slug', S.cfg.eventSlug).maybeSingle();
    if (!ev.data) { block('No encuentro el evento.', 'error'); return; }
    data.event = ev.data;

    data.families = (await S.client.from('families').select('*')
      .eq('event_id', data.event.id).order('sort_order')).data || [];
    $('familyFilter').innerHTML = '<option value="">Todas</option>' +
      data.families.map(function (f) {
        return '<option value="' + f.id + '">' + esc(f.name) + '</option>';
      }).join('');

    var lig = await S.client.from('lighters').select('*').eq('event_id', data.event.id).order('number');
    if (lig.error) { block(esc(S.message(lig.error)), 'error'); return; }
    data.lighters = lig.data || [];

    if (!data.lighters.length) {
      block('Todavía no hay encendedores. Genéralos en el <a href="/admin/index.html">panel</a>.', 'warn');
      return;
    }
    $('toN').value = data.lighters[data.lighters.length - 1].number;
    render();
  }

  async function render() {
    var base = $('base').value.trim();
    var fam = $('familyFilter').value;
    var from = parseInt($('fromN').value, 10) || 1;
    var to = parseInt($('toN').value, 10) || 9999;

    var colors = {};
    data.families.forEach(function (f) { colors[f.id] = f; });

    var list = data.lighters.filter(function (l) {
      return l.number >= from && l.number <= to && (!fam || l.family_id === fam);
    });

    var sinCodigo = list.filter(function (l) { return !l.code_plain; }).length;
    block(list.length
      ? 'Van <b>' + list.length + '</b> etiquetas, ' + Math.ceil(list.length / 24) + ' hoja(s).' +
        (sinCodigo ? ' Ojo: ' + sinCodigo + ' sin código guardado, se imprimen con puntos.' : '')
      : 'Ningún encendedor en ese rango.', sinCodigo ? 'warn' : 'ok');

    var sheet = $('sheet');
    sheet.innerHTML = '';

    for (var i = 0; i < list.length; i++) {
      var l = list[i];
      var f = colors[l.family_id] || { name: '', color: '#000' };
      var svg = await window.QRCode.toString(base + l.token, {
        type: 'svg', margin: 0, errorCorrectionLevel: 'Q',
        color: { dark: '#000000', light: '#ffffff' }
      });

      var div = document.createElement('div');
      div.className = 'label';
      div.innerHTML =
        '<span class="label__bar" style="background:' + esc(f.color) + '"></span>' +
        '<div class="label__qr">' + svg + '</div>' +
        '<div class="label__code">' + esc(l.code_plain || '····') + '</div>' +
        '<div class="label__meta">' + esc(f.name) + ' · Nº ' + l.number + '</div>' +
        '<div class="label__meta">Pasa la Llama</div>';
      sheet.appendChild(div);
    }
  }

  $('apply').onclick = render;
  $('print').onclick = function () { window.print(); };

  boot();
})();
