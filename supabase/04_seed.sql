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
