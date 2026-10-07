/* La página que abre el QR: registro y, una vez dentro, la línea del
   encendedor. Todo contra Supabase; las reglas de acceso están en la base. */
(function () {
  'use strict';

  var S = window.PLL;
  var $ = function (id) { return document.getElementById(id); };
  var token = new URLSearchParams(window.location.search).get('t');
  var ctx = { event: null, zones: [], zonesById: {}, families: {} };

  function show(id, on) { $(id).classList.toggle('is-hidden', !on); }
  function esc(s) {
    return String(s == null ? '' : s).replace(/[&<>"]/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c];
    });
  }
  function note(el, text, kind) {
    el.innerHTML = text ? '<div class="msg ' + (kind === 'ok' ? 'msg--ok' : '') + '">' + text + '</div>' : '';
  }
  function intro(title, text) {
    $('introTitle').textContent = title;
    $('introText').textContent = text;
    show('intro', true); show('form', false); show('result', false);
  }
  function hora(iso) {
    return new Date(iso).toLocaleTimeString('es', { hour: '2-digit', minute: '2-digit', hour12: false });
  }

  async function boot() {
    if (!S.configured) { intro('Falta configurar', 'Esta página todavía no está conectada a su base de datos.'); return; }
    if (!token) { intro('Falta el código del QR', 'Abre esta página escaneando el QR de un encendedor.'); return; }

    var ev = await S.client.from('events').select('*').eq('slug', S.cfg.eventSlug).maybeSingle();
    if (ev.error || !ev.data) {
      intro('Todavía no', 'La experiencia aún no está abierta. Vuelve a escanear durante la fiesta.');
      return;
    }
    ctx.event = ev.data;

    var zonas = await S.client.from('zones').select('id,name').eq('event_id', ctx.event.id).order('sort_order');
    ctx.zones = zonas.data || [];
    ctx.zones.forEach(function (z) { ctx.zonesById[z.id] = z.name; });
    $('zone').innerHTML = ctx.zones.map(function (z) {
      return '<option value="' + z.id + '">' + esc(z.name) + '</option>';
    }).join('');

    var fam = await S.client.from('families').select('id,name,color').eq('event_id', ctx.event.id);
    (fam.data || []).forEach(function (f) { ctx.families[f.id] = f; });

    /* Si ya entraste antes esta noche, el nombre viene puesto. */
    var session = (await S.client.auth.getSession()).data.session;
    if (session) {
      var g = await S.client.from('guests').select('display_name').eq('id', session.user.id).maybeSingle();
      if (g.data) $('name').value = g.data.display_name;
    }

    if (ctx.event.state !== 'live') {
      intro('Todavía no', 'La experiencia se abre la noche de la fiesta. Guarda tu encendedor.');
      return;
    }

    show('intro', false); show('form', true);
    $('code').focus();
  }

  $('scanForm').addEventListener('submit', async function (e) {
    e.preventDefault();
    var code = $('code').value.trim().toUpperCase();
    var name = $('name').value.trim();

    if (code.length !== 4) { note($('formMsg'), 'El código tiene cuatro caracteres.'); return; }
    if (name.length < 2) { note($('formMsg'), 'Escribe tu nombre.'); return; }
    if (!$('adult').checked) { note($('formMsg'), 'La experiencia es para mayores de 18 años.'); return; }

    $('submit').disabled = true;
    $('submit').textContent = 'Entrando…';
    note($('formMsg'), '');

    try {
      /* Cuenta sin contraseña: se crea sola y queda guardada en el teléfono. */
      if (!(await S.client.auth.getSession()).data.session) {
        var anon = await S.client.auth.signInAnonymously();
        if (anon.error) throw anon.error;
      }

      var res = await S.client.rpc('claim_lighter', {
        p_token: token,
        p_code: code,
        p_name: name,
        p_zone: $('zone').value || null,
        p_email: $('email').value.trim() || null,
        p_consent: $('consent').checked,
        p_adult: $('adult').checked
      });
      if (res.error) throw res.error;

      await mostrarLinea(res.data);
    } catch (err) {
      note($('formMsg'), esc(S.message(err)));
      $('submit').disabled = false;
      $('submit').textContent = 'Entrar a la línea';
    }
  });

  async function mostrarLinea(info) {
    show('form', false); show('result', true);
    window.scrollTo(0, 0);

    var color = info.family_color || '#ff2a1f';

    $('resultTitle').textContent = info.already ? 'Ya estabas aquí' : 'Entraste';
    $('resultText').textContent = info.already
      ? 'Este encendedor ya pasó por tus manos esta noche.'
      : (info.prev_name
          ? info.prev_name + ' lo tuvo antes que tú.'
          : 'Eres la primera persona de esta línea. Empieza contigo.');

    $('lighterName').innerHTML = 'Nº ' + info.number + ' · <span style="color:' +
      esc(color) + '">' + esc(info.family) + '</span>';
    $('position').textContent = info.seq;
    $('positionLabel').textContent = info.seq === 1
      ? 'eres quien lo empezó'
      : 'eres la persona ' + info.seq + ' de esta línea';

    var uid = (await S.client.auth.getSession()).data.session.user.id;

    var scans = await S.client.from('scans')
      .select('seq,created_at,guest_id,zone_id')
      .eq('lighter_id', info.lighter_id).order('seq');

    var gente = scans.data || [];
    var nombres = {};
    if (gente.length) {
      var perfiles = await S.client.from('guests_public').select('id,display_name')
        .in('id', gente.map(function (s) { return s.guest_id; }));
      (perfiles.data || []).forEach(function (p) { nombres[p.id] = p.display_name; });
    }

    $('lineList').innerHTML = gente.map(function (s) {
      var yo = s.guest_id === uid;
      return '<li class="' + (yo ? 'you' : '') + '">' +
        '<span class="dot" style="background:' + esc(color) + '"></span>' +
        '<div><div class="who">' + esc(nombres[s.guest_id] || 'Alguien') +
          (yo ? '<span class="tag">TÚ</span>' : '') + '</div>' +
          '<div class="where">' + esc(ctx.zonesById[s.zone_id] || 'por ahí') + '</div></div>' +
        '<div class="when">' + hora(s.created_at) + '</div>' +
      '</li>';
    }).join('');

    /* Todos los encendedores por los que ya pasé esta noche. */
    var mine = await S.client.from('line_members').select('lighter_id').eq('guest_id', uid);
    var ids = (mine.data || []).map(function (m) { return m.lighter_id; });
    if (ids.length > 1) {
      var lista = await S.client.from('lighters_public').select('id,number,family_id').in('id', ids).order('number');
      $('mineList').innerHTML = (lista.data || []).map(function (l) {
        var f = ctx.families[l.family_id] || { name: '', color: '#ff2a1f' };
        return '<li style="border-color:' + esc(f.color) + '">Nº ' + l.number + ' · ' + esc(f.name) + '</li>';
      }).join('');
    } else {
      show('mineCard', false);
    }
  }

  boot();
})();
