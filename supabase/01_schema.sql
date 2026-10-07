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
