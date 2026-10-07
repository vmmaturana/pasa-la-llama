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
