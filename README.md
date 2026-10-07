# Pasa la Llama

Portal y app de evento para **Haus Of Wonder**: cien encendedores con QR único,
cuatro familias, la cadena de personas que se los van pasando y tres niveles de
chat (fiesta, familia y directo dentro de una misma línea).

Sitio estático, sin framework ni compilación. El backend es Supabase.

## Estructura

| Ruta | Qué es |
|---|---|
| `index.html`, `styles.css`, `script.js` | La landing pública |
| `lib/supabase.js` | Conexión al proyecto de Supabase y mensajes de error |
| `admin/` | Panel: evento, familias, zonas, encendedores y hoja de QR |
| `supabase/*.sql` | Esquema, funciones, reglas de acceso y datos iniciales |
| `docs/arquitectura.md` | El diseño completo del sistema |
| `docs/despliegue.md` | Cómo publicarlo y qué configurar |

## Previsualizar

```bash
python3 -m http.server 4322
```

Landing en `http://localhost:4322`, panel en `http://localhost:4322/admin/`.

## Base de datos

Los archivos de `supabase/` se ejecutan en el editor SQL del proyecto, en orden,
o todos de una vez con `supabase/00_todo_junto.sql`. Se pueden volver a correr
sin romper nada.

## Claves

La URL y la clave `anon` son públicas por diseño y viven en `lib/supabase.js`:
lo que protege los datos son las reglas de acceso de `supabase/03_rls.sql`. La
clave `service_role` nunca entra al repositorio.
