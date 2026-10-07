-- =============================================================================
-- Pasa la Llama · TODO JUNTO
--
-- Este archivo es los cuatro (01, 02, 03 y 04) pegados en orden, para poder
-- ejecutarlos de una sola vez desde el editor SQL de Supabase.
--
-- Cómo se usa:
--   1. Entra a tu proyecto en supabase.com
--   2. Menú de la izquierda → SQL Editor → New query
--   3. Pega TODO este archivo y pulsa Run (o Cmd+Enter)
--
-- Se puede volver a ejecutar sin romper nada: no borra ni duplica datos.
-- Si cambia el esquema, se edita el archivo numerado correspondiente y se
-- vuelve a generar este con:  cat 0{1,2,3,4}*.sql > 00_todo_junto.sql
-- =============================================================================

-- =============================================================================
-- Pasa la Llama · 01 · Esquema
-- Pegar en el editor SQL de Supabase y ejecutar. Es idempotente: se puede
-- volver a correr sin romper nada.
-- =============================================================================

create extension if not exists pgcrypto with schema extensions;

-- -----------------------------------------------------------------------------
-- Evento
-- -----------------------------------------------------------------------------
create table if not exists public.events (
  id                 uuid primary key default gen_random_uuid(),
  slug               text unique not null,
  name               text not null,
  venue              text,
  starts_at          timestamptz,
  ends_at            timestamptz,
  lighter_count      int  not null default 100,
  state              text not null default 'draft'
                     check (state in ('draft','live','closed')),
  event_chat_open    boolean not null default true,
  family_chat_open   boolean not null default true,
  dm_open            boolean not null default true,
  slow_mode_seconds  int not null default 0,
  max_scans_per_lighter int not null default 60,
  max_lighters_per_guest int not null default 12,
  created_at         timestamptz not null default now()
);

-- -----------------------------------------------------------------------------
-- Zonas del lugar (barra, pista, terraza...) y familias (las ramas)
-- -----------------------------------------------------------------------------
create table if not exists public.zones (
  id          uuid primary key default gen_random_uuid(),
  event_id    uuid not null references public.events(id) on delete cascade,
  name        text not null,
  color       text,
  sort_order  int  not null default 0,
  -- geometría en el plano de la fiesta, en el sistema de coordenadas del SVG
  x           numeric, y numeric, w numeric, h numeric,
  created_at  timestamptz not null default now(),
  unique (event_id, name)
);
create index if not exists zones_event_idx on public.zones (event_id, sort_order);

create table if not exists public.families (
  id          uuid primary key default gen_random_uuid(),
  event_id    uuid not null references public.events(id) on delete cascade,
  name        text not null,
  color       text not null default '#ff2a1f',
  sort_order  int  not null default 0,
  created_at  timestamptz not null default now(),
  unique (event_id, name)
);
create index if not exists families_event_idx on public.families (event_id, sort_order);

-- -----------------------------------------------------------------------------
-- Encendedores. Esta tabla nunca se expone al navegador de un invitado:
-- contiene el token del QR y el código impreso.
-- -----------------------------------------------------------------------------
create table if not exists public.lighters (
  id           uuid primary key default gen_random_uuid(),
  event_id     uuid not null references public.events(id) on delete cascade,
  family_id    uuid not null references public.families(id) on delete cascade,
  number       int  not null,
  token        text not null unique,
  code_hash    text not null,
  code_plain   text,                     -- solo hasta imprimir; se puede borrar
  status       text not null default 'active'
               check (status in ('active','retired','lost')),
  scan_count   int  not null default 0,
  last_scan_at timestamptz,
  created_at   timestamptz not null default now(),
  unique (event_id, number)
);
create index if not exists lighters_family_idx on public.lighters (family_id);

-- La vista reducida de esta tabla (lighters_public) se crea en 02, porque
-- necesita las funciones de permisos.

-- -----------------------------------------------------------------------------
-- Invitados. Una fila por cuenta de Supabase.
-- -----------------------------------------------------------------------------
create table if not exists public.guests (
  id            uuid primary key references auth.users(id) on delete cascade,
  event_id      uuid not null references public.events(id) on delete cascade,
  display_name  text not null check (length(btrim(display_name)) between 2 and 24),
  email         text,
  email_consent boolean not null default false,
  adult_declared boolean not null default false,
  first_zone_id uuid references public.zones(id) on delete set null,
  avatar_seed   text not null default encode(extensions.gen_random_bytes(4), 'hex'),
  muted_until   timestamptz,
  banned_at     timestamptz,
  created_at    timestamptz not null default now()
);
create index if not exists guests_event_idx on public.guests (event_id);

-- El perfil público (guests_public) también se crea en 02.

-- -----------------------------------------------------------------------------
-- Escaneos: la fuente de verdad de cada línea. Solo se agrega, nunca se edita.
-- -----------------------------------------------------------------------------
create table if not exists public.scans (
  id            uuid primary key default gen_random_uuid(),
  event_id      uuid not null references public.events(id) on delete cascade,
  lighter_id    uuid not null references public.lighters(id) on delete cascade,
  guest_id      uuid not null references public.guests(id) on delete cascade,
  seq           int  not null,
  prev_guest_id uuid references public.guests(id) on delete set null,
  zone_id       uuid references public.zones(id) on delete set null,
  created_at    timestamptz not null default now(),
  unique (lighter_id, seq),
  unique (lighter_id, guest_id)   -- reescanear no duplica
);
create index if not exists scans_guest_idx on public.scans (guest_id);
create index if not exists scans_event_idx on public.scans (event_id, created_at desc);

-- Quién se lo pasó a quién, para el árbol y el plano.
create or replace view public.handoffs
with (security_invoker = true) as
  select lighter_id, event_id, prev_guest_id as from_guest, guest_id as to_guest,
         zone_id, created_at
  from public.scans
  where prev_guest_id is not null;

-- -----------------------------------------------------------------------------
-- Pertenencias. Son una proyección de `scans`, mantenida por disparador, para
-- que los permisos se resuelvan con una búsqueda por clave y no recorriendo
-- la cadena entera.
-- -----------------------------------------------------------------------------
create table if not exists public.line_members (
  lighter_id uuid not null references public.lighters(id) on delete cascade,
  guest_id   uuid not null references public.guests(id) on delete cascade,
  event_id   uuid not null references public.events(id) on delete cascade,
  primary key (lighter_id, guest_id)
);
create index if not exists line_members_guest_idx on public.line_members (guest_id);

create table if not exists public.family_members (
  family_id      uuid not null references public.families(id) on delete cascade,
  guest_id       uuid not null references public.guests(id) on delete cascade,
  event_id       uuid not null references public.events(id) on delete cascade,
  first_scan_at  timestamptz not null default now(),
  primary key (family_id, guest_id)
);
create index if not exists family_members_guest_idx on public.family_members (guest_id);

create or replace function public.sync_memberships()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_family uuid;
begin
  insert into public.line_members (lighter_id, guest_id, event_id)
  values (new.lighter_id, new.guest_id, new.event_id)
  on conflict do nothing;

  select family_id into v_family from public.lighters where id = new.lighter_id;

  insert into public.family_members (family_id, guest_id, event_id, first_scan_at)
  values (v_family, new.guest_id, new.event_id, new.created_at)
  on conflict do nothing;

  return new;
end;
$$;

drop trigger if exists scans_sync_memberships on public.scans;
create trigger scans_sync_memberships
  after insert on public.scans
  for each row execute function public.sync_memberships();

-- -----------------------------------------------------------------------------
-- Chats: evento y familia comparten tabla; los directos van aparte porque su
-- regla de acceso es distinta.
-- -----------------------------------------------------------------------------
create table if not exists public.messages (
  id          uuid primary key default gen_random_uuid(),
  event_id    uuid not null references public.events(id) on delete cascade,
  scope       text not null check (scope in ('event','family')),
  family_id   uuid references public.families(id) on delete cascade,
  guest_id    uuid not null references public.guests(id) on delete cascade,
  body        text not null check (length(btrim(body)) between 1 and 500),
  created_at  timestamptz not null default now(),
  deleted_at  timestamptz,
  deleted_by  uuid,
  check ((scope = 'event' and family_id is null)
      or (scope = 'family' and family_id is not null))
);
create index if not exists messages_event_idx on public.messages (event_id, created_at desc);
create index if not exists messages_family_idx on public.messages (family_id, created_at desc);
create index if not exists messages_guest_idx on public.messages (guest_id, created_at desc);

create table if not exists public.dm_threads (
  id           uuid primary key default gen_random_uuid(),
  event_id     uuid not null references public.events(id) on delete cascade,
  lighter_id   uuid not null references public.lighters(id) on delete cascade,
  guest_a      uuid not null references public.guests(id) on delete cascade,
  guest_b      uuid not null references public.guests(id) on delete cascade,
  requested_by uuid not null references public.guests(id) on delete cascade,
  status       text not null default 'pending'
               check (status in ('pending','accepted','rejected','blocked')),
  created_at   timestamptz not null default now(),
  responded_at timestamptz,
  check (guest_a < guest_b),      -- orden canónico: un solo hilo por par
  unique (guest_a, guest_b)
);
create index if not exists dm_threads_a_idx on public.dm_threads (guest_a);
create index if not exists dm_threads_b_idx on public.dm_threads (guest_b);

create table if not exists public.dm_messages (
  id         uuid primary key default gen_random_uuid(),
  thread_id  uuid not null references public.dm_threads(id) on delete cascade,
  guest_id   uuid not null references public.guests(id) on delete cascade,
  body       text not null check (length(btrim(body)) between 1 and 1000),
  created_at timestamptz not null default now(),
  deleted_at timestamptz
);
create index if not exists dm_messages_thread_idx on public.dm_messages (thread_id, created_at desc);

create table if not exists public.blocks (
  blocker_id uuid not null references public.guests(id) on delete cascade,
  blocked_id uuid not null references public.guests(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id)
);
create index if not exists blocks_blocked_idx on public.blocks (blocked_id);

create table if not exists public.reports (
  id              uuid primary key default gen_random_uuid(),
  event_id        uuid not null references public.events(id) on delete cascade,
  reporter_id     uuid not null references public.guests(id) on delete cascade,
  target_guest_id uuid references public.guests(id) on delete set null,
  message_table   text check (message_table in ('messages','dm_messages')),
  message_id      uuid,
  reason          text not null,
  note            text,
  status          text not null default 'open'
                  check (status in ('open','actioned','dismissed')),
  resolved_by     uuid,
  created_at      timestamptz not null default now(),
  resolved_at     timestamptz
);
create index if not exists reports_open_idx on public.reports (event_id, status, created_at desc);

-- -----------------------------------------------------------------------------
-- Administradores y registro de intentos de escaneo (antifraude)
-- -----------------------------------------------------------------------------
create table if not exists public.admins (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  event_id   uuid references public.events(id) on delete cascade,  -- null = todos
  role       text not null default 'owner' check (role in ('owner','moderator')),
  created_at timestamptz not null default now()
);

-- Emails autorizados que todavía no han entrado nunca. Al primer ingreso, el
-- disparador de abajo los convierte en administradores de verdad.
create table if not exists public.admin_invites (
  email      text primary key,
  event_id   uuid references public.events(id) on delete cascade,
  role       text not null default 'owner' check (role in ('owner','moderator')),
  created_at timestamptz not null default now()
);

create or replace function public.claim_admin_invite()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_invite public.admin_invites%rowtype;
begin
  if new.email is null then
    return new;
  end if;

  select * into v_invite
  from public.admin_invites
  where lower(email) = lower(new.email);

  if found then
    insert into public.admins (user_id, event_id, role)
    values (new.id, v_invite.event_id, v_invite.role)
    on conflict (user_id) do nothing;
  end if;

  return new;
end;
$$;

drop trigger if exists on_auth_user_claim_admin on auth.users;
create trigger on_auth_user_claim_admin
  after insert on auth.users
  for each row execute function public.claim_admin_invite();

create table if not exists public.scan_attempts (
  id         bigserial primary key,
  token      text,
  guest_id   uuid,
  ok         boolean not null,
  created_at timestamptz not null default now()
);
create index if not exists scan_attempts_token_idx on public.scan_attempts (token, created_at desc);
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
-- =============================================================================
-- Pasa la Llama · 03 · Reglas de acceso (RLS)
-- Todo lo que puede hacer el navegador pasa por aquí. La interfaz no protege
-- nada: lo protege esta capa.
-- =============================================================================

alter table public.events          enable row level security;
alter table public.zones           enable row level security;
alter table public.families        enable row level security;
alter table public.lighters        enable row level security;
alter table public.guests          enable row level security;
alter table public.scans           enable row level security;
alter table public.line_members    enable row level security;
alter table public.family_members  enable row level security;
alter table public.messages        enable row level security;
alter table public.dm_threads      enable row level security;
alter table public.dm_messages     enable row level security;
alter table public.blocks          enable row level security;
alter table public.reports         enable row level security;
alter table public.admins          enable row level security;
alter table public.admin_invites   enable row level security;
alter table public.scan_attempts   enable row level security;

-- -----------------------------------------------------------------------------
-- Evento: lo público es público; configurarlo es cosa de administradores.
-- -----------------------------------------------------------------------------
drop policy if exists events_read on public.events;
create policy events_read on public.events for select
  using (state in ('live','closed') or public.is_admin(id));

drop policy if exists events_admin_insert on public.events;
create policy events_admin_insert on public.events for insert
  with check (public.is_admin(null));

drop policy if exists events_admin_update on public.events;
create policy events_admin_update on public.events for update
  using (public.is_admin(id)) with check (public.is_admin(id));

drop policy if exists events_admin_delete on public.events;
create policy events_admin_delete on public.events for delete
  using (public.is_admin(id));

-- -----------------------------------------------------------------------------
-- Zonas y familias: se leen sin sesión, porque la página del QR las necesita
-- antes de que la persona entre. No contienen nada sensible.
-- -----------------------------------------------------------------------------
drop policy if exists zones_read on public.zones;
create policy zones_read on public.zones for select using (true);

drop policy if exists zones_admin_write on public.zones;
create policy zones_admin_write on public.zones for all
  using (public.is_admin(event_id)) with check (public.is_admin(event_id));

drop policy if exists families_read on public.families;
create policy families_read on public.families for select using (true);

drop policy if exists families_admin_write on public.families;
create policy families_admin_write on public.families for all
  using (public.is_admin(event_id)) with check (public.is_admin(event_id));

-- -----------------------------------------------------------------------------
-- Encendedores: tokens y códigos. Solo administradores, nunca un invitado.
-- -----------------------------------------------------------------------------
drop policy if exists lighters_admin_read on public.lighters;
create policy lighters_admin_read on public.lighters for select
  using (public.is_admin(event_id));

drop policy if exists lighters_admin_write on public.lighters;
create policy lighters_admin_write on public.lighters for all
  using (public.is_admin(event_id)) with check (public.is_admin(event_id));

-- -----------------------------------------------------------------------------
-- Invitados: cada quien ve y edita su propia ficha. Lo que ven los demás sale
-- de la vista guests_public, que solo entrega nombre y avatar.
-- -----------------------------------------------------------------------------
drop policy if exists guests_read_own on public.guests;
create policy guests_read_own on public.guests for select
  using (id = (select auth.uid()) or public.is_admin(event_id));

drop policy if exists guests_insert_own on public.guests;
create policy guests_insert_own on public.guests for insert
  with check (id = (select auth.uid()));

drop policy if exists guests_update_own on public.guests;
create policy guests_update_own on public.guests for update
  using (id = (select auth.uid())) with check (id = (select auth.uid()));

drop policy if exists guests_admin_update on public.guests;
create policy guests_admin_update on public.guests for update
  using (public.is_admin(event_id)) with check (public.is_admin(event_id));

-- Nadie se silencia, se expulsa ni se cambia de evento a sí mismo.
revoke update (muted_until, banned_at, event_id, id) on public.guests from authenticated;

-- -----------------------------------------------------------------------------
-- Escaneos y pertenencias: se leen dentro del evento (son el producto), y solo
-- se escriben desde claim_lighter, que corre con permisos elevados.
-- -----------------------------------------------------------------------------
drop policy if exists scans_read on public.scans;
create policy scans_read on public.scans for select
  using (event_id = public.guest_event() or public.is_admin(event_id));

drop policy if exists line_members_read on public.line_members;
create policy line_members_read on public.line_members for select
  using (event_id = public.guest_event() or public.is_admin(event_id));

drop policy if exists family_members_read on public.family_members;
create policy family_members_read on public.family_members for select
  using (event_id = public.guest_event() or public.is_admin(event_id));

-- -----------------------------------------------------------------------------
-- Chat de la fiesta y de la familia
-- -----------------------------------------------------------------------------
drop policy if exists messages_read on public.messages;
create policy messages_read on public.messages for select
  using (
    public.is_admin(event_id)
    or (
      deleted_at is null
      and event_id = public.guest_event()
      and (
        (scope = 'event'  and exists (select 1 from public.events e where e.id = event_id and e.event_chat_open))
        or
        (scope = 'family' and public.is_in_family(family_id)
                          and exists (select 1 from public.events e where e.id = event_id and e.family_chat_open))
      )
      and not exists (
        select 1 from public.blocks b
        where b.blocker_id = (select auth.uid()) and b.blocked_id = messages.guest_id
      )
    )
  );

drop policy if exists messages_write on public.messages;
create policy messages_write on public.messages for insert
  with check (
    guest_id = (select auth.uid())
    and event_id = public.guest_event()
    and public.can_speak()
    and (
      (scope = 'event'  and exists (select 1 from public.events e where e.id = event_id and e.event_chat_open))
      or
      -- Solo escribo en la familia donde escaneé.
      (scope = 'family' and public.is_in_family(family_id)
                        and exists (select 1 from public.events e where e.id = event_id and e.family_chat_open))
    )
  );

-- Borrar es moderar: se marca, no se elimina, y solo lo hace un administrador.
drop policy if exists messages_admin_update on public.messages;
create policy messages_admin_update on public.messages for update
  using (public.is_admin(event_id)) with check (public.is_admin(event_id));

-- -----------------------------------------------------------------------------
-- Chats directos: pedir, aceptar y hablar
-- -----------------------------------------------------------------------------
drop policy if exists dm_threads_read on public.dm_threads;
create policy dm_threads_read on public.dm_threads for select
  using ((select auth.uid()) in (guest_a, guest_b) or public.is_admin(event_id));

drop policy if exists dm_threads_request on public.dm_threads;
create policy dm_threads_request on public.dm_threads for insert
  with check (
    requested_by = (select auth.uid())
    and (select auth.uid()) in (guest_a, guest_b)
    and public.can_speak()
    and exists (select 1 from public.events e where e.id = event_id and e.dm_open)
    -- Solo con alguien de mi misma línea, y por un encendedor que ambos tuvieron.
    and public.shares_line_with(case when guest_a = (select auth.uid()) then guest_b else guest_a end)
    and exists (select 1 from public.line_members m
                 where m.lighter_id = dm_threads.lighter_id and m.guest_id = guest_a)
    and exists (select 1 from public.line_members m
                 where m.lighter_id = dm_threads.lighter_id and m.guest_id = guest_b)
    and not exists (
      select 1 from public.blocks b
      where (b.blocker_id = guest_a and b.blocked_id = guest_b)
         or (b.blocker_id = guest_b and b.blocked_id = guest_a)
    )
  );

-- Responder la solicitud: solo quien la recibió.
drop policy if exists dm_threads_respond on public.dm_threads;
create policy dm_threads_respond on public.dm_threads for update
  using (
    (select auth.uid()) in (guest_a, guest_b)
    and requested_by <> (select auth.uid())
    and status = 'pending'
  )
  with check (status in ('accepted','rejected','blocked'));

drop policy if exists dm_messages_read on public.dm_messages;
create policy dm_messages_read on public.dm_messages for select
  using (
    deleted_at is null
    and exists (
      select 1 from public.dm_threads t
      where t.id = thread_id and t.status = 'accepted'
        and (select auth.uid()) in (t.guest_a, t.guest_b)
    )
  );

drop policy if exists dm_messages_write on public.dm_messages;
create policy dm_messages_write on public.dm_messages for insert
  with check (
    guest_id = (select auth.uid())
    and public.can_speak()
    and exists (
      select 1 from public.dm_threads t
      where t.id = thread_id and t.status = 'accepted'
        and (select auth.uid()) in (t.guest_a, t.guest_b)
        and not exists (
          select 1 from public.blocks b
          where (b.blocker_id = t.guest_a and b.blocked_id = t.guest_b)
             or (b.blocker_id = t.guest_b and b.blocked_id = t.guest_a)
        )
    )
  );

-- -----------------------------------------------------------------------------
-- Bloqueos y reportes
-- -----------------------------------------------------------------------------
drop policy if exists blocks_own on public.blocks;
create policy blocks_own on public.blocks for all
  using (blocker_id = (select auth.uid()))
  with check (blocker_id = (select auth.uid()));

drop policy if exists reports_read on public.reports;
create policy reports_read on public.reports for select
  using (reporter_id = (select auth.uid()) or public.is_admin(event_id));

drop policy if exists reports_insert on public.reports;
create policy reports_insert on public.reports for insert
  with check (reporter_id = (select auth.uid()));

drop policy if exists reports_admin_update on public.reports;
create policy reports_admin_update on public.reports for update
  using (public.is_admin(event_id)) with check (public.is_admin(event_id));

-- -----------------------------------------------------------------------------
-- Administradores: se leen a sí mismos; agregar gente se hace por SQL desde
-- el panel de Supabase, no desde el navegador.
-- -----------------------------------------------------------------------------
drop policy if exists admins_read_self on public.admins;
create policy admins_read_self on public.admins for select
  using (user_id = (select auth.uid()));

-- admin_invites y scan_attempts quedan con RLS activo y sin ninguna regla:
-- nadie los lee ni los escribe desde el navegador.
-- =============================================================================
-- Pasa la Llama · 04 · Datos iniciales
--
-- El email de abajo es el que entra al panel: al iniciar sesión por primera vez
-- con él, la cuenta queda registrada como administradora automáticamente.
-- Para sumar a otra persona, repite el insert con su email.
-- =============================================================================

insert into public.admin_invites (email, event_id, role)
values ('vmmaturana@gmail.com', null, 'owner')
on conflict (email) do nothing;

-- -----------------------------------------------------------------------------
-- Evento. Cambia el nombre, el lugar y las fechas desde el panel cuando
-- quieras: esto es solo el punto de partida.
-- -----------------------------------------------------------------------------
insert into public.events (slug, name, venue, lighter_count, state)
values ('haus-of-wonder', 'Haus Of Wonder', 'Por confirmar', 100, 'draft')
on conflict (slug) do nothing;

-- -----------------------------------------------------------------------------
-- Las cuatro familias. Colores de la casa: rojo de flash y sus vecinos.
-- -----------------------------------------------------------------------------
insert into public.families (event_id, name, color, sort_order)
select e.id, f.name, f.color, f.sort_order
from public.events e,
     (values ('Oráculo',     '#ff2a1f', 1),
             ('Carrusel',    '#ff8a7a', 2),
             ('Alquimia',    '#f4efe9', 3),
             ('Invernadero', '#c23b2f', 4)) as f(name, color, sort_order)
where e.slug = 'haus-of-wonder'
on conflict (event_id, name) do nothing;

-- -----------------------------------------------------------------------------
-- Zonas del lugar. Las coordenadas son las del plano de la fiesta; se ajustan
-- desde el panel cuando se sepa el recinto real.
-- -----------------------------------------------------------------------------
insert into public.zones (event_id, name, sort_order, x, y, w, h)
select e.id, z.name, z.sort_order, z.x, z.y, z.w, z.h
from public.events e,
     (values ('Entrada',            1,  40, 400, 150, 100),
             ('Barra',              2,  40, 268, 150, 112),
             ('Pista',              3, 208, 230, 214, 270),
             ('Salón del Oráculo',  4,  40,  40, 168, 206),
             ('Lounge',             5, 228,  40, 194, 166),
             ('Terraza',            6, 442,  40, 218, 200),
             ('Jardín',             7, 442, 262, 218, 238)) as z(name, sort_order, x, y, w, h)
where e.slug = 'haus-of-wonder'
on conflict (event_id, name) do nothing;

-- Los encendedores NO se crean aquí: se generan desde el panel, en
-- "Encendedores → Generar", para que los códigos queden registrados de una vez.
