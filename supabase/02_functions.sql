-- =============================================================================
-- Pasa la Llama · 02 · Funciones
-- Aquí vive todo lo delicado: validar el código impreso, calcular la posición
-- en la línea y generar los encendedores. Son funciones con permisos elevados
-- (security definer), así que cada una comprueba por su cuenta quién llama.
-- =============================================================================

-- Alfabeto del código impreso: sin I, O, 0 ni 1, que se confunden al leerlos.
create or replace function public.code_alphabet()
returns text language sql immutable as
$$ select 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789' $$;

-- El código se guarda como hash, salado con el id del encendedor.
create or replace function public.hash_code(p_lighter uuid, p_code text)
returns text
language sql
immutable
set search_path = public, extensions, pg_temp
as $$
  select encode(
    extensions.digest(upper(regexp_replace(p_code, '[^a-zA-Z0-9]', '', 'g')) || p_lighter::text, 'sha256'),
    'hex')
$$;

-- -----------------------------------------------------------------------------
-- Ayudantes de permisos. Los usan las reglas de acceso del archivo 03.
-- -----------------------------------------------------------------------------
create or replace function public.is_admin(p_event uuid default null)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.admins a
    where a.user_id = (select auth.uid())
      and (a.event_id is null or p_event is null or a.event_id = p_event)
  )
$$;

create or replace function public.guest_event()
returns uuid
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select event_id from public.guests where id = (select auth.uid())
$$;

create or replace function public.is_in_family(p_family uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.family_members
    where family_id = p_family and guest_id = (select auth.uid())
  )
$$;

-- ¿Compartimos algún encendedor? Es la condición para pedir chat directo.
create or replace function public.shares_line_with(p_other uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.line_members mine
    join public.line_members theirs using (lighter_id)
    where mine.guest_id = (select auth.uid())
      and theirs.guest_id = p_other
  )
$$;

create or replace function public.can_speak()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.guests g
    join public.events e on e.id = g.event_id
    where g.id = (select auth.uid())
      and g.banned_at is null
      and (g.muted_until is null or g.muted_until < now())
      and e.state = 'live'
  )
$$;

-- -----------------------------------------------------------------------------
-- Vistas reducidas. Corren con los permisos de su dueño, así que saltan las
-- reglas de la tabla y filtran por su cuenta: solo el evento de quien pregunta.
-- -----------------------------------------------------------------------------
create or replace view public.lighters_public as
  select id, event_id, family_id, number, status, scan_count, last_scan_at
  from public.lighters
  where event_id = public.guest_event() or public.is_admin(event_id);

-- Nombre y avatar de los demás invitados. Nunca el email.
create or replace view public.guests_public as
  select id, event_id, display_name, avatar_seed, created_at
  from public.guests
  where event_id = public.guest_event() or public.is_admin(event_id);

grant select on public.lighters_public, public.guests_public to authenticated;

-- -----------------------------------------------------------------------------
-- Escanear un encendedor. Es la única forma de entrar a una línea.
-- Devuelve un jsonb con el resultado para que la página lo muestre.
-- -----------------------------------------------------------------------------
create or replace function public.claim_lighter(
  p_token   text,
  p_code    text,
  p_name    text,
  p_zone    uuid default null,
  p_email   text default null,
  p_consent boolean default false,
  p_adult   boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_uid     uuid := (select auth.uid());
  v_lighter public.lighters%rowtype;
  v_event   public.events%rowtype;
  v_prev    uuid;
  v_prev_name text;
  v_seq     int;
  v_count   int;
  v_family  public.families%rowtype;
begin
  if v_uid is null then
    raise exception 'sin_sesion' using hint = 'Hay que iniciar sesión antes de escanear.';
  end if;

  if p_name is null or length(btrim(p_name)) < 2 then
    raise exception 'nombre_invalido' using hint = 'Escribe tu nombre.';
  end if;

  -- Se bloquea la fila: dos personas escaneando a la vez no pueden tomar la
  -- misma posición en la línea.
  select * into v_lighter from public.lighters where token = p_token for update;

  if not found or v_lighter.code_hash is distinct from public.hash_code(v_lighter.id, coalesce(p_code, '')) then
    insert into public.scan_attempts (token, guest_id, ok) values (p_token, v_uid, false);
    -- Mismo error para token inexistente y código equivocado: no se filtra nada.
    raise exception 'codigo_invalido' using hint = 'El código no coincide.';
  end if;

  select * into v_event from public.events where id = v_lighter.event_id;

  if v_event.state <> 'live' then
    raise exception 'evento_cerrado' using hint = 'La experiencia no está activa.';
  end if;
  if v_lighter.status <> 'active' then
    raise exception 'encendedor_retirado' using hint = 'Este encendedor ya no está en circulación.';
  end if;
  if v_lighter.scan_count >= v_event.max_scans_per_lighter then
    raise exception 'limite_encendedor' using hint = 'Este encendedor llegó a su límite de escaneos.';
  end if;

  -- Perfil del invitado: se crea en el primer escaneo y se respeta después.
  insert into public.guests (id, event_id, display_name, email, email_consent, adult_declared, first_zone_id)
  values (v_uid, v_lighter.event_id, btrim(p_name), nullif(btrim(coalesce(p_email, '')), ''),
          p_consent, p_adult, p_zone)
  on conflict (id) do update
    set display_name  = btrim(p_name),
        email         = coalesce(nullif(btrim(coalesce(p_email, '')), ''), public.guests.email),
        email_consent = public.guests.email_consent or p_consent,
        adult_declared = public.guests.adult_declared or p_adult;

  if exists (select 1 from public.guests where id = v_uid and banned_at is not null) then
    raise exception 'expulsado' using hint = 'Tu acceso fue bloqueado por la organización.';
  end if;

  -- ¿Ya estabas en esta línea? Entonces no pasa nada nuevo.
  select seq into v_seq from public.scans
  where lighter_id = v_lighter.id and guest_id = v_uid;

  if found then
    insert into public.scan_attempts (token, guest_id, ok) values (p_token, v_uid, true);
    select * into v_family from public.families where id = v_lighter.family_id;
    return jsonb_build_object(
      'already', true, 'lighter_id', v_lighter.id, 'number', v_lighter.number,
      'family', v_family.name, 'family_color', v_family.color, 'seq', v_seq
    );
  end if;

  select count(*) into v_count from public.line_members where guest_id = v_uid;
  if v_count >= v_event.max_lighters_per_guest then
    raise exception 'limite_persona' using hint = 'Llegaste al máximo de encendedores por persona.';
  end if;

  select guest_id into v_prev from public.scans
  where lighter_id = v_lighter.id
  order by seq desc limit 1;

  select coalesce(max(seq), 0) + 1 into v_seq from public.scans where lighter_id = v_lighter.id;

  insert into public.scans (event_id, lighter_id, guest_id, seq, prev_guest_id, zone_id)
  values (v_lighter.event_id, v_lighter.id, v_uid, v_seq, v_prev, p_zone);

  update public.lighters
     set scan_count = scan_count + 1, last_scan_at = now()
   where id = v_lighter.id;

  insert into public.scan_attempts (token, guest_id, ok) values (p_token, v_uid, true);

  select display_name into v_prev_name from public.guests where id = v_prev;
  select * into v_family from public.families where id = v_lighter.family_id;

  return jsonb_build_object(
    'already', false,
    'lighter_id', v_lighter.id,
    'number', v_lighter.number,
    'family', v_family.name,
    'family_color', v_family.color,
    'seq', v_seq,
    'prev_name', v_prev_name
  );
end;
$$;

revoke all on function public.claim_lighter(text, text, text, uuid, text, boolean, boolean) from public;
grant execute on function public.claim_lighter(text, text, text, uuid, text, boolean, boolean) to authenticated;

-- -----------------------------------------------------------------------------
-- Generar los encendedores. Solo un administrador, y nunca duplica: completa
-- hasta llegar a la cantidad pedida por familia.
-- -----------------------------------------------------------------------------
create or replace function public.admin_generate_lighters(
  p_event uuid,
  p_per_family int default null
)
returns int
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_family   record;
  v_total    int := 0;
  v_existing int;
  v_number   int;
  v_id       uuid;
  v_token    text;
  v_code     text;
  v_per      int;
  v_families int;
  i int;
  j int;
begin
  if not public.is_admin(p_event) then
    raise exception 'no_autorizado';
  end if;

  select count(*) into v_families from public.families where event_id = p_event;
  if v_families = 0 then
    raise exception 'sin_familias' using hint = 'Crea al menos una familia antes de generar.';
  end if;

  if p_per_family is null then
    select ceil(lighter_count::numeric / v_families) into v_per
    from public.events where id = p_event;
  else
    v_per := p_per_family;
  end if;

  select coalesce(max(number), 0) into v_number from public.lighters where event_id = p_event;

  for v_family in
    select id from public.families where event_id = p_event order by sort_order, name
  loop
    select count(*) into v_existing from public.lighters where family_id = v_family.id;

    for i in 1 .. greatest(v_per - v_existing, 0) loop
      v_id := gen_random_uuid();
      v_number := v_number + 1;

      -- Token del QR: 16 bytes al azar en base64 apto para URL.
      v_token := rtrim(translate(encode(extensions.gen_random_bytes(16), 'base64'), '+/', '-_'), '=');

      -- Código impreso de 4 caracteres.
      v_code := '';
      for j in 1 .. 4 loop
        v_code := v_code || substr(public.code_alphabet(),
                                   1 + floor(random() * length(public.code_alphabet()))::int, 1);
      end loop;

      insert into public.lighters (id, event_id, family_id, number, token, code_hash, code_plain)
      values (v_id, p_event, v_family.id, v_number, v_token,
              public.hash_code(v_id, v_code), v_code);

      v_total := v_total + 1;
    end loop;
  end loop;

  return v_total;
end;
$$;

revoke all on function public.admin_generate_lighters(uuid, int) from public;
grant execute on function public.admin_generate_lighters(uuid, int) to authenticated;

-- Reemplazar el QR y el código de un encendedor perdido o mal impreso.
create or replace function public.admin_regenerate_lighter(p_lighter uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_event uuid;
  v_token text;
  v_code  text := '';
  j int;
begin
  select event_id into v_event from public.lighters where id = p_lighter;
  if v_event is null or not public.is_admin(v_event) then
    raise exception 'no_autorizado';
  end if;

  v_token := rtrim(translate(encode(extensions.gen_random_bytes(16), 'base64'), '+/', '-_'), '=');
  for j in 1 .. 4 loop
    v_code := v_code || substr(public.code_alphabet(),
                               1 + floor(random() * length(public.code_alphabet()))::int, 1);
  end loop;

  update public.lighters
     set token = v_token, code_hash = public.hash_code(p_lighter, v_code), code_plain = v_code
   where id = p_lighter;

  return jsonb_build_object('token', v_token, 'code', v_code);
end;
$$;

revoke all on function public.admin_regenerate_lighter(uuid) from public;
grant execute on function public.admin_regenerate_lighter(uuid) to authenticated;

-- Borrar los códigos en claro cuando ya estén impresos.
create or replace function public.admin_forget_codes(p_event uuid)
returns int
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_n int;
begin
  if not public.is_admin(p_event) then
    raise exception 'no_autorizado';
  end if;
  update public.lighters set code_plain = null
   where event_id = p_event and code_plain is not null;
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;

revoke all on function public.admin_forget_codes(uuid) from public;
grant execute on function public.admin_forget_codes(uuid) to authenticated;
