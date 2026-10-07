# Pasa la Llama — landing + arquitectura (Haus Of Wonder)

## Contexto

El prototipo publicado (artifact `KHYEKbCyWXZ3CMHxG4GwYR`) ya validó la UX: 4 familias, 100 encendedores con QR único, línea de traspasos y tres niveles de chat (fiesta, familia, directo con solicitud). Es una sola página estática sin backend: los datos son de ejemplo y se pierden al recargar.

Ahora hay que convertirlo en algo usable en una fiesta real de Haus Of Wonder (@hausof.wonder, plataforma creativa de Melania Wonder, Santiago) y construir la landing pública alineada a su identidad. Además, la organizadora tiene que poder ajustar sin tocar código la cantidad de encendedores, las familias y las zonas del lugar.

Decisiones ya tomadas: **Next.js (App Router) + Supabase sobre Vercel**, **repo nuevo e independiente**, **landing primero y app después**, y acceso de invitados con **nombre + código del encendedor, email opcional** (sin contraseña).

Marca observada hoy en IG y en melaniawonder.com/haus-of-wonder: fondo negro, fotografía de club teñida de rojo, grotesca en mayúsculas, texto en marquesina, "Clubbing is our favourite sport 🌹🪩". Contacto: wonder.hausof@gmail.com. El nombre correcto es **Haus Of Wonder** (el prototipo dice "House"; hay que corregirlo).

## Repositorio nuevo

`~/Claude Code/pasa-la-llama`, git propio y proyecto Vercel propio. No se toca el repo de Sonrisa Imperial. Se replica de ahí lo que funciona: `CLAUDE.md` con el rol y el idioma, `vercel.json` con los headers de seguridad, tokens de color en `:root` triplicados para los tres estados de tema, y nombres BEM + estados `is-`.

```
pasa-la-llama/
├── supabase/migrations/   # init_core, guests_scans, chat, admins, functions, rls, realtime
├── supabase/seed.sql      # evento demo: 4 familias, 7 zonas, 100 encendedores
├── scripts/generate-lighters.ts
├── public/fonts/          # grotesca autoalojada (sin depender de red externa en el club)
└── src/
    ├── app/
    │   ├── page.tsx              # FASE 1 · landing
    │   ├── q/[token]/page.tsx    # registro al escanear (HTML puro, sin JS crítico)
    │   ├── (guest)/              # app/, arbol/, plano/, chat/{evento,familia,dm}, cuenta/
    │   ├── admin/                # evento, familias, zonas, encendedores/imprimir, moderacion, stats
    │   └── api/scan/route.ts     # camino crítico: valida, crea sesión y registra el escaneo
    ├── components/viz/           # RadialTree, VenueMap (port del prototipo SVG)
    └── lib/supabase, realtime, codes, qr, ratelimit
```

## Fase 1 — Landing de Haus Of Wonder (lo primero que se entrega)

Página estática, sin Supabase, desplegada y enlazable desde la bio de Instagram.

- Hero negro con fotografía de club teñida de rojo y marquesina "HAUS OF WONDER" repetida, igual que su sitio.
- Secciones: el manifiesto ("más que una fiesta… una casa y una familia en expansión", tomado de su propio texto), residentes (JAVIERSS, JO AEDO, ANDRÉS GALUÉ, MATÍAS HERNÁN, CARLA PADOVANI, ERWIN GUZMÁN), **Pasa la Llama** como experiencia del próximo evento con el árbol SVG animado de muestra, y contacto/bookings.
- Metadatos y OG card correctos para cuando peguen el link en Instagram y WhatsApp.
- **Necesito de la clienta**: fotos en alta, logo, el nombre de la tipografía real y la fecha/lugar del evento. Instagram no permite descargar su material y no voy a usar imágenes de terceros; hasta tenerlas, la landing va con fotografía de reemplazo marcada como provisional.

## Fase 2 — Núcleo: escaneo e identidad

**Modelo de datos** (Postgres, todo con `event_id`): `events`, `zones`, `families`, `lighters`, `guests`, `scans`, `messages`, `dm_threads`, `dm_messages`, `blocks`, `reports`, `admins`, `scan_attempts`.

La pieza central es `scans`, append-only: `(lighter_id, guest_id, seq, prev_guest_id, zone_id, created_at)`.
- La **línea** de un encendedor es `select * from scans where lighter_id = X order by seq`.
- **Quién se lo pasó a quién** queda explícito en `prev_guest_id`, para que el árbol y el plano se dibujen con una sola consulta.
- `unique (lighter_id, guest_id)` hace que reescanear sea idempotente: responde "ya estás en esta línea, posición N" en vez de duplicar.
- Dos tablas de pertenencia mantenidas por trigger, `line_members` y `family_members`, para que los permisos se resuelvan con una búsqueda por clave primaria en vez de recorrer la cadena.

**Acceso sin contraseña**: `/q/<token>` es un Server Component con un formulario HTML nativo (nombre, código de 4 caracteres, zona, email opcional, casilla +18). Un solo `POST /api/scan` valida el código, crea la sesión con `signInAnonymously()` **desde el servidor** y llama a la función `claim_lighter`, que en una transacción bloquea la fila del encendedor, calcula `seq` y `prev_guest_id` e inserta el escaneo. La sesión viaja en cookies escritas por el servidor: en Safari, lo guardado por JavaScript muere a los 7 días, y queremos que la línea siga ahí la semana siguiente. Vincular el email después convierte la cuenta en permanente conservando el mismo id, y con él toda la línea y los chats.

Riesgo a cubrir en la UI: dos personas que escanean desde el mismo teléfono. Si ya hay sesión, `/q/<token>` muestra "Estás como NOMBRE" y un botón "No soy yo".

## Fase 3 — Visualizaciones

Port del árbol radial y el plano de zonas del prototipo a componentes React con datos reales, actualizados en vivo. Las zonas dejan de estar escritas en el código: vienen de la tabla `zones`, con su nombre, color y forma en el plano.

## Fase 4 — Chats

`messages` cubre el chat de la fiesta y el de familia en una sola tabla (`scope` = `event` o `family`); los directos van aparte porque su acceso es distinto. `dm_threads` en estado `pending` **es** la solicitud, así que no hace falta una tabla de solicitudes.

Las reglas de acceso se aplican en la base de datos (RLS), no solo en la interfaz:
- **"Solo escribo en la familia donde escaneé"**: al insertar se exige que exista mi fila en `family_members`.
- **"Solo pido chat directo a alguien de mi misma línea"**: se exige que ambos aparezcan en `line_members` del mismo encendedor, que no haya bloqueo en ninguna dirección y que los directos estén abiertos.
- `lighters` nunca se expone al cliente (contiene el token y el código); los invitados leen una vista reducida.

Tiempo real por **broadcast** desde triggers, no por escucha de cambios de tabla: con 300 personas, lo segundo evalúa los permisos una vez por cliente y por mensaje. Canales: `event:{id}`, `family:{id}`, `dm:{id}`, `guest:{id}` (solicitudes y avisos) y `admin:{id}`. El cliente se suscribe **solo al canal visible**. Para 200-400 simultáneos hace falta el plan Pro de Supabase (el gratuito topa en 200 conexiones): contratarlo antes del ensayo, no la noche del evento.

## Fase 5 — Panel de administración

Es el requisito de "ajustable sin tocar código":
- **Evento**: nombre, fecha, número de encendedores, abrir/cerrar cada chat, modo lento como botón de pánico.
- **Familias** y **zonas**: crear, renombrar, color, orden. Cambia el árbol y el plano sin desplegar nada.
- **Encendedores**: generar los 100 con token y código, ver su estado y reimprimir los perdidos.
- **Impresión**: hoja A4 con 24 etiquetas (QR en SVG, código en grande, número y color de familia), lista para "Guardar como PDF" desde el navegador. Nada de generar PDF en el servidor para imprimir una vez.
- **Moderación**: reportes, borrar mensajes, silenciar, expulsar.
- **Stats en vivo**: escaneos totales, por familia y por zona, personas conectadas, mensajes por minuto.

## Antifraude

Token de 22 caracteres aleatorios en la URL (no derivable del número del encendedor) y código de 4 caracteres con alfabeto sin ambigüedades (sin I, O, 0, 1), guardado como hash. Tope de escaneos por encendedor, espera mínima entre escaneos del mismo encendedor, tope de encendedores por persona y límite de intentos por IP mediante el firewall de Vercel más un contador en `scan_attempts`. Sin captcha: añade segundos justo donde no los tenemos.

## Riesgos principales

- **Señal en el club**, el mayor de todos: registro en un solo POST, menos de 40 KB en el primer render, fuentes locales, cola de reintento para los mensajes y degradación a "solo ver mi línea" si la red cae. Y pedir al recinto wifi dedicado con semanas de antelación.
- **Moderación**: dos personas con el panel abierto toda la noche. Ninguna lista de palabras prohibidas sustituye eso, y en jerga chilena daría falsos positivos.
- **Privacidad**: evento +18 declarado, datos mínimos (nombre o apodo, zona, email opcional), consentimiento separado para recibir comunicaciones después, política de privacidad enlazada desde el propio formulario, y opción de borrar mis datos.
- **El día después**: chats abiertos 72 horas (la resaca es cuando la gente vuelve a mirar), solo lectura a los 7 días salvo los directos, purga a los 30 días y exportación previa para la organizadora. Hay que decidir ahora si la app es un recuerdo compartible o algo efímero; las dos opciones son defendibles, la ambigüedad no.

## Esfuerzo

Landing 2-3 días · núcleo 4 · visualizaciones 2-3 · chats 4-5 · admin 4-5 · endurecimiento y ensayo 2-3. Total **20-24 días hábiles** de una persona. Si aprieta el calendario, lo que se recorta es la fase de visualizaciones.

## Verificación

- **Landing**: Lighthouse móvil ≥ 90, carga bajo 2 s en 4G simulado, correcta en iPhone SE y Android de gama baja, OG card al pegar el link en Instagram y WhatsApp, sin scroll horizontal por la marquesina.
- **Escaneo**: cronómetro en mano, menos de 10 segundos desde apuntar la cámara hasta "estás en la línea" con red 3G simulada. 20 peticiones concurrentes al mismo encendedor producen posiciones correlativas sin colisión. Reescanear no duplica. La sesión sobrevive a cerrar el navegador y a 7 días en Safari iOS.
- **Chats**: suite de pruebas que, con los tokens de tres invitados distintos, intenta las escrituras prohibidas **directamente contra la API de Supabase** (no por la interfaz) y verifica que todas fallan.
- **Admin**: la organizadora, sola y sin ayuda, cambia el número de encendedores, renombra una familia, agrega una zona, imprime los QR, cierra y reabre un chat, borra un mensaje y expulsa a alguien. Si algo le toma más de dos minutos, está mal diseñado.
- **Ensayo**: 300 sesiones sintéticas en 10 minutos sin errores, y una prueba presencial en el recinto con teléfonos reales, incluido un iPhone viejo y un Android en ahorro de batería. Antes de la tirada de 100 encendedores, imprimir una hoja de prueba y escanearla con tres teléfonos distintos.

## Lo que necesito de ti antes de empezar

1. Fotos, logo y tipografía reales de Haus Of Wonder, más fecha y lugar del evento.
2. Confirmar si la experiencia es un recuerdo compartible o efímera.
3. Cuenta de Supabase y de Vercel para el proyecto nuevo, y el dominio a usar.
