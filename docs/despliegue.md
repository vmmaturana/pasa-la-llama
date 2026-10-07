# Publicar Pasa la Llama

El sitio es estático, así que cualquier hosting sirve. El camino elegido es
GitHub + Vercel, que republica solo con cada cambio.

## 1. Repositorio en GitHub

Crear un repositorio **privado** llamado `pasa-la-llama`, vacío: sin README, sin
`.gitignore` y sin licencia (el repo local ya los tiene).

Luego, desde la carpeta del proyecto:

```bash
git remote add origin https://github.com/TU-USUARIO/pasa-la-llama.git
git push -u origin main
```

GitHub pedirá usuario y contraseña. La contraseña **no** es la de la cuenta: hay
que crear un token en `github.com/settings/tokens` → *Generate new token
(classic)* → permiso `repo`. macOS lo guarda en el llavero y no vuelve a
pedirlo. Ese token es una credencial personal: no se comparte ni se guarda en el
repositorio.

## 2. Importar en Vercel

En `vercel.com/new`, importar el repositorio. No hay que configurar nada más:

- Framework preset: **Other**
- Build command: vacío
- Output directory: vacío (la raíz del repo)

`.vercelignore` ya deja fuera `supabase/`, `docs/` y `.claude/`, así que el SQL
no se publica.

## 3. Configurar Supabase con el dominio nuevo

Sin esto, el enlace de acceso al panel no funciona en producción. En el proyecto
de Supabase, `Authentication → URL Configuration`:

- **Site URL**: la dirección de Vercel, por ejemplo
  `https://pasa-la-llama.vercel.app`
- **Redirect URLs**: agregar esa misma dirección con `/admin/**`, y también
  `http://localhost:4322/**` para seguir trabajando en local.

Si más adelante se compra un dominio propio, hay que repetir este paso con él.

## 4. Antes de imprimir los encendedores

El QR lleva la dirección dentro. Una vez impreso no se puede cambiar, así que
**el dominio definitivo tiene que estar decidido antes de mandar la tirada**. Si
va a haber dominio propio, conectarlo a Vercel primero y recién después generar
e imprimir las etiquetas.

## 5. Qué revisar antes de compartir el enlace

- [ ] Aprobación de Haus Of Wonder: el sitio usa su nombre y enlaza su Instagram.
- [ ] Fotos y logo reales en vez del fondo generativo provisional.
- [ ] `og.png` (1200×630): sin él, el link pegado en Instagram o WhatsApp sale
      sin imagen de vista previa.
- [ ] Fecha y lugar del evento, si ya están definidos.
- [ ] El evento en estado `live` solo cuando empiece la fiesta; mientras tanto,
      `draft` impide que alguien escanee antes de tiempo.

## El panel es público, pero vacío sin sesión

`/admin/` queda accesible en internet. No es un problema: lleva `noindex`, y sin
sesión de administrador no muestra ni permite nada, porque todo lo decide la
base de datos. Para que alguien entre, su email tiene que estar en
`admin_invites`.
