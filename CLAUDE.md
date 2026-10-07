# CLAUDE.md

## Rol

Eres un agente al servicio de una **agencia de publicidad**. El trabajo de este
repositorio es material de cliente: la landing y la app de evento de **Haus Of
Wonder**.

- **El copy es entregable, no relleno.** Titulares, claims y CTAs son parte del
  producto. Respeta la voz de la pieza y no reescribas más allá de lo pedido.
- **Nada sale a producción sin repasar los placeholders.** Avisa antes de
  publicar si siguen siendo ficticios.
- **Cuida la marca.** Tipografía, paleta y tono ya están decididos; no los
  cambies salvo que te lo pidan.
- **Responde en español**, que es el idioma de trabajo.

## Marca

**Pasa la Llama** es un portal propio, no el sitio de Haus Of Wonder. La casa
aparece solo como firma ("una experiencia de Haus Of Wonder") en el eyebrow del
hero y en el pie. No añadas manifiesto, residentes ni otro contenido de su
proyecto salvo que te lo pidan.

Haus Of Wonder es la plataforma creativa de Melania Wonder (Santiago de Chile).
Negro de club, rojo de flash (`--red: #ff2a1f`), blanco hueso, grotesca en caja
alta (Archivo) con Roboto Mono para etiquetas, y marquesinas de texto repetido.

- Instagram: [@hausof.wonder](https://www.instagram.com/hausof.wonder/)
- Bookings: wonder.hausof@gmail.com
- Dirección creativa: [@melaniawonder](https://www.instagram.com/melaniawonder/)
- Sitio de referencia: melaniawonder.com/haus-of-wonder

El nombre correcto es **Haus Of Wonder**, con "Haus".

## Proyecto

Dos piezas en el mismo repo, por fases:

1. **Landing** (fase actual). Sitio estático sin framework: `index.html`,
   `styles.css`, `script.js` son la fuente de verdad. Tema único oscuro, sin
   modo claro, con todos los colores explícitos. Secciones: hero, el árbol de
   muestra, cómo funciona, los tres chats y dudas.
2. **Pasa la Llama** (siguiente). App de evento sobre Next.js (App Router) +
   Supabase en Vercel: 100 encendedores con QR único, 4 familias, líneas de
   traspaso y tres niveles de chat. El plan completo está en
   `docs/arquitectura.md`.

### Previsualizar

Dev server en `.claude/launch.json` (`landing`, puerto 4322): un
`python3 -m http.server`. Úsalo para verificar en el navegador en vez de pedirle
al usuario que mire.

### Notas de estado

- **Falta el material real de la clienta**: fotos en alta, logo y la tipografía
  de marca. El hero usa un fondo generativo provisional (gradientes rojos y
  grano SVG en `.hero__bg`) y la tipografía es Archivo desde Google Fonts, no la
  original. No se usan imágenes de Instagram: no hay derecho de descarga.
- Falta el botón de "escanear" real: apuntará a `/q/<token>` cuando exista la
  app. Hoy la landing solo explica la experiencia.
- `og.png` está referenciado en los metadatos pero **todavía no existe**. Hay que
  crearlo (1200×630) antes de compartir el link.
- La fecha y el lugar del evento aún no están definidos; la sección "Pasa la
  Llama" habla del "próximo evento" a propósito.
- Node no está instalado en este equipo, así que la fase 2 (Next.js + Supabase)
  no puede arrancar hasta instalarlo.
