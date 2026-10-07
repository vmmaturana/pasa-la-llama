/* Panel de administración de Pasa la Llama.
   Habla directo con Supabase desde el navegador: lo que puede hacer esta página
   lo decide la base de datos, no este archivo. */
(function () {
  'use strict';

  var S = window.PLL;
  var $ = function (id) { return document.getElementById(id); };
  var state = { event: null, families: [], zones: [], lighters: [], counts: {} };

  function show(id, on) { $(id).classList.toggle('is-hidden', !on); }
  function esc(s) {
    return String(s == null ? '' : s).replace(/[&<>"]/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c];
    });
  }
  function say(el, text, kind) {
    if (!text) { el.innerHTML = ''; return; }
    el.innerHTML = '<span class="msg msg--' + (kind || 'ok') + '">' + esc(text) + '</span>';
  }
  function block(el, text, kind) {
    el.innerHTML = text ? '<div class="msg msg--' + (kind || 'ok') + '">' + text + '</div>' : '';
  }
  /* La base guarda UTC; el formulario trabaja en hora local. */
  function toLocalInput(iso) {
    if (!iso) return '';
    var d = new Date(iso);
    var pad = function (n) { return String(n).padStart(2, '0'); };
    return d.getFullYear() + '-' + pad(d.getMonth() + 1) + '-' + pad(d.getDate()) +
           'T' + pad(d.getHours()) + ':' + pad(d.getMinutes());
  }
  function fromLocalInput(value) { return value ? new Date(value).toISOString() : null; }

  /* ---------- Entrar ---------- */
  async function boot() {
    if (!S.configured) { show('setup', true); return; }

    var session = (await S.client.auth.getSession()).data.session;
    if (!session) { show('login', true); return; }

    var admin = await S.client.from('admins').select('role').eq('user_id', session.user.id).maybeSingle();
    if (!admin.data) {
      show('login', true);
      block($('loginMsg'),
        'Entraste como <b>' + esc(session.user.email) + '</b>, pero esa cuenta no es administradora. ' +
        'Agrégala en Supabase con:<br><code>insert into admin_invites (email) values (\'' +
        esc(session.user.email) + '\');</code><br>y vuelve a entrar.', 'warn');
      $('loginForm').insertAdjacentHTML('beforeend',
        '<div class="actions"><button class="btn-ghost" type="button" id="logout2">Salir de esta cuenta</button></div>');
      $('logout2').onclick = signOut;
      return;
    }

    show('app', true);
    $('who').textContent = session.user.email;
    await loadAll();
  }

  async function signOut() {
    await S.client.auth.signOut();
    window.location.replace(window.location.pathname);
  }

  $('loginForm').addEventListener('submit', async function (e) {
    e.preventDefault();
    var email = $('loginEmail').value.trim();
    $('loginBtn').disabled = true;
    var res = await S.client.auth.signInWithOtp({
      email: email,
      options: { emailRedirectTo: window.location.href }
    });
    $('loginBtn').disabled = false;
    if (res.error) { block($('loginMsg'), esc(S.message(res.error)), 'error'); return; }
    block($('loginMsg'), 'Listo: te enviamos un enlace a <b>' + esc(email) +
      '</b>. Ábrelo en este mismo teléfono o computador.', 'ok');
  });

  /* ---------- Pestañas ---------- */
  document.querySelector('.tabs').addEventListener('click', function (e) {
    var btn = e.target.closest('button[data-tab]');
    if (!btn) return;
    document.querySelectorAll('.tabs button').forEach(function (b) {
      b.setAttribute('aria-selected', String(b === btn));
    });
    ['evento', 'familias', 'zonas', 'encendedores'].forEach(function (name) {
      show('tab-' + name, name === btn.dataset.tab);
    });
  });

  $('logout').onclick = signOut;

  /* ---------- Cargar todo ---------- */
  async function loadAll() {
    var ev = await S.client.from('events').select('*').eq('slug', S.cfg.eventSlug).maybeSingle();
    if (ev.error) { block($('globalMsg'), esc(S.message(ev.error)), 'error'); return; }
    if (!ev.data) {
      block($('globalMsg'),
        'No encuentro el evento <code>' + esc(S.cfg.eventSlug) + '</code>. ' +
        'Ejecuta <code>supabase/04_seed.sql</code> en el editor SQL de Supabase.', 'warn');
      return;
    }
    state.event = ev.data;
    block($('globalMsg'), '');
    renderEvent();

    var fam = await S.client.from('families').select('*').eq('event_id', state.event.id)
      .order('sort_order').order('name');
    state.families = fam.data || [];

    var zon = await S.client.from('zones').select('*').eq('event_id', state.event.id)
      .order('sort_order').order('name');
    state.zones = zon.data || [];

    var lig = await S.client.from('lighters').select('*').eq('event_id', state.event.id).order('number');
    state.lighters = lig.data || [];

    renderFamilies();
    renderZones();
    renderLighters();
  }

  /* ---------- Evento ---------- */
  function renderEvent() {
    var e = state.event;
    $('evName').value = e.name || '';
    $('evVenue').value = e.venue || '';
    $('evStarts').value = toLocalInput(e.starts_at);
    $('evEnds').value = toLocalInput(e.ends_at);
    $('evCount').value = e.lighter_count;
    $('evState').value = e.state;
    $('evMaxScans').value = e.max_scans_per_lighter;
    $('evMaxLighters').value = e.max_lighters_per_guest;
    $('evSlow').value = e.slow_mode_seconds;
    $('evChatEvent').checked = e.event_chat_open;
    $('evChatFamily').checked = e.family_chat_open;
    $('evDm').checked = e.dm_open;
  }

  $('eventForm').addEventListener('submit', async function (e) {
    e.preventDefault();
    var patch = {
      name: $('evName').value.trim(),
      venue: $('evVenue').value.trim() || null,
      starts_at: fromLocalInput($('evStarts').value),
      ends_at: fromLocalInput($('evEnds').value),
      lighter_count: parseInt($('evCount').value, 10),
      state: $('evState').value,
      max_scans_per_lighter: parseInt($('evMaxScans').value, 10),
      max_lighters_per_guest: parseInt($('evMaxLighters').value, 10),
      slow_mode_seconds: parseInt($('evSlow').value, 10),
      event_chat_open: $('evChatEvent').checked,
      family_chat_open: $('evChatFamily').checked,
      dm_open: $('evDm').checked
    };
    var res = await S.client.from('events').update(patch).eq('id', state.event.id).select().maybeSingle();
    if (res.error) { say($('eventMsg'), S.message(res.error), 'error'); return; }
    state.event = res.data;
    say($('eventMsg'), 'Guardado.', 'ok');
    renderLighters();
  });

  /* ---------- Familias ---------- */
  function renderFamilies() {
    $('familyRows').innerHTML = state.families.map(function (f, i) {
      var n = state.lighters.filter(function (l) { return l.family_id === f.id; }).length;
      return '<tr data-i="' + i + '">' +
        '<td><input data-k="name" value="' + esc(f.name) + '" maxlength="40"></td>' +
        '<td><input data-k="color" type="color" value="' + esc(f.color || '#ff2a1f') + '"></td>' +
        '<td><input data-k="sort_order" type="number" class="mono" value="' + (f.sort_order || 0) + '"></td>' +
        '<td class="mono">' + n + '</td>' +
        '<td>' + (n === 0
          ? '<button class="btn-ghost btn--sm" type="button" data-del="' + i + '">Borrar</button>'
          : '<span class="admin__who">en uso</span>') + '</td>' +
      '</tr>';
    }).join('');
  }

  $('addFamily').onclick = function () {
    state.families.push({ id: null, name: 'Nueva familia', color: '#ff2a1f',
                          sort_order: state.families.length + 1 });
    renderFamilies();
  };

  $('familyRows').addEventListener('click', async function (e) {
    var btn = e.target.closest('[data-del]');
    if (!btn) return;
    var f = state.families[+btn.dataset.del];
    if (!window.confirm('¿Borrar la familia "' + f.name + '"?')) return;
    if (f.id) {
      var res = await S.client.from('families').delete().eq('id', f.id);
      if (res.error) { say($('familyMsg'), S.message(res.error), 'error'); return; }
    }
    state.families.splice(+btn.dataset.del, 1);
    renderFamilies();
  });

  $('saveFamilies').onclick = async function () {
    collectRows('familyRows', state.families);
    for (var i = 0; i < state.families.length; i++) {
      var f = state.families[i];
      var row = { event_id: state.event.id, name: f.name.trim(),
                  color: f.color, sort_order: Number(f.sort_order) || 0 };
      var res = f.id
        ? await S.client.from('families').update(row).eq('id', f.id)
        : await S.client.from('families').insert(row);
      if (res.error) { say($('familyMsg'), S.message(res.error), 'error'); return; }
    }
    say($('familyMsg'), 'Guardado.', 'ok');
    await loadAll();
  };

  /* ---------- Zonas ---------- */
  function renderZones() {
    $('zoneRows').innerHTML = state.zones.map(function (z, i) {
      return '<tr data-i="' + i + '">' +
        '<td><input data-k="name" value="' + esc(z.name) + '" maxlength="40"></td>' +
        '<td><input data-k="sort_order" type="number" class="mono" value="' + (z.sort_order || 0) + '"></td>' +
        ['x', 'y', 'w', 'h'].map(function (k) {
          return '<td><input data-k="' + k + '" type="number" class="mono" value="' + (z[k] == null ? '' : z[k]) + '"></td>';
        }).join('') +
        '<td><button class="btn-ghost btn--sm" type="button" data-del="' + i + '">Borrar</button></td>' +
      '</tr>';
    }).join('');
  }

  $('addZone').onclick = function () {
    state.zones.push({ id: null, name: 'Nueva zona', sort_order: state.zones.length + 1 });
    renderZones();
  };

  $('zoneRows').addEventListener('click', async function (e) {
    var btn = e.target.closest('[data-del]');
    if (!btn) return;
    var z = state.zones[+btn.dataset.del];
    if (!window.confirm('¿Borrar la zona "' + z.name + '"?')) return;
    if (z.id) {
      var res = await S.client.from('zones').delete().eq('id', z.id);
      if (res.error) { say($('zoneMsg'), S.message(res.error), 'error'); return; }
    }
    state.zones.splice(+btn.dataset.del, 1);
    renderZones();
  });

  $('saveZones').onclick = async function () {
    collectRows('zoneRows', state.zones);
    for (var i = 0; i < state.zones.length; i++) {
      var z = state.zones[i];
      var row = { event_id: state.event.id, name: z.name.trim(), sort_order: Number(z.sort_order) || 0,
                  x: num(z.x), y: num(z.y), w: num(z.w), h: num(z.h) };
      var res = z.id
        ? await S.client.from('zones').update(row).eq('id', z.id)
        : await S.client.from('zones').insert(row);
      if (res.error) { say($('zoneMsg'), S.message(res.error), 'error'); return; }
    }
    say($('zoneMsg'), 'Guardado.', 'ok');
    await loadAll();
  };

  function num(v) { return v === '' || v == null ? null : Number(v); }

  /* Lee lo escrito en la tabla y lo vuelca en el arreglo que la generó. */
  function collectRows(tbodyId, list) {
    document.querySelectorAll('#' + tbodyId + ' tr').forEach(function (tr) {
      var item = list[+tr.dataset.i];
      tr.querySelectorAll('[data-k]').forEach(function (input) {
        item[input.dataset.k] = input.value;
      });
    });
  }

  /* ---------- Encendedores ---------- */
  function renderLighters() {
    var total = state.lighters.length;
    var scanned = state.lighters.filter(function (l) { return l.scan_count > 0; }).length;
    var people = state.lighters.reduce(function (s, l) { return s + l.scan_count; }, 0);
    var target = state.event.lighter_count;

    $('lighterStats').innerHTML =
      stat(total + '<span style="font-size:16px;color:var(--paper-soft)">/' + target + '</span>', 'generados') +
      stat(state.families.length, 'familias') +
      stat(scanned, 'en circulación') +
      stat(people, 'escaneos');

    var byId = {};
    state.families.forEach(function (f) { byId[f.id] = f; });

    $('lighterRows').innerHTML = state.lighters.map(function (l) {
      var f = byId[l.family_id] || { name: '—', color: '#555' };
      return '<tr>' +
        '<td class="mono">' + l.number + '</td>' +
        '<td><span class="dot" style="background:' + esc(f.color) + '"></span> ' + esc(f.name) + '</td>' +
        '<td class="mono">' + esc(l.code_plain || '····') + '</td>' +
        '<td class="mono">' + l.scan_count + '</td>' +
        '<td>' +
          '<select data-status="' + l.id + '">' +
            ['active', 'lost', 'retired'].map(function (s) {
              var label = { active: 'activo', lost: 'perdido', retired: 'retirado' }[s];
              return '<option value="' + s + '"' + (l.status === s ? ' selected' : '') + '>' + label + '</option>';
            }).join('') +
          '</select>' +
        '</td>' +
        '<td><button class="btn-ghost btn--sm" type="button" data-regen="' + l.id + '">Nuevo QR</button></td>' +
      '</tr>';
    }).join('');
  }

  function stat(value, label) {
    return '<div class="stat"><b>' + value + '</b><span>' + label + '</span></div>';
  }

  $('generate').onclick = async function () {
    var faltan = state.event.lighter_count - state.lighters.length;
    if (faltan <= 0) {
      say($('genMsg'), 'Ya están los ' + state.event.lighter_count + ' encendedores generados.', 'warn');
      return;
    }
    if (!window.confirm('Se van a crear ' + faltan + ' encendedores nuevos con su QR y su código. ¿Seguimos?')) return;
    $('generate').disabled = true;
    say($('genMsg'), 'Generando…', 'ok');
    var res = await S.client.rpc('admin_generate_lighters', { p_event: state.event.id });
    $('generate').disabled = false;
    if (res.error) { say($('genMsg'), S.message(res.error), 'error'); return; }
    say($('genMsg'), 'Listos ' + res.data + ' encendedores nuevos.', 'ok');
    await loadAll();
  };

  $('lighterRows').addEventListener('click', async function (e) {
    var btn = e.target.closest('[data-regen]');
    if (!btn) return;
    if (!window.confirm('El QR y el código actuales dejarán de servir. Hay que volver a imprimir esta etiqueta. ¿Seguimos?')) return;
    var res = await S.client.rpc('admin_regenerate_lighter', { p_lighter: btn.dataset.regen });
    if (res.error) { say($('genMsg'), S.message(res.error), 'error'); return; }
    say($('genMsg'), 'Nuevo código: ' + res.data.code + '. Reimprime esa etiqueta.', 'ok');
    await loadAll();
  });

  $('lighterRows').addEventListener('change', async function (e) {
    var sel = e.target.closest('[data-status]');
    if (!sel) return;
    var res = await S.client.from('lighters').update({ status: sel.value }).eq('id', sel.dataset.status);
    say($('genMsg'), res.error ? S.message(res.error) : 'Estado actualizado.', res.error ? 'error' : 'ok');
  });

  boot();
})();
