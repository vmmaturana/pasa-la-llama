/* Conexión con Supabase.
 *
 * Estos dos valores son públicos por diseño: van dentro del HTML y cualquiera
 * puede verlos. No dan acceso a nada por sí solos; lo que protege los datos son
 * las reglas de acceso de la base (supabase/03_rls.sql).
 *
 * La clave `service_role` NUNCA va aquí ni en ningún archivo del repo.
 *
 * Para conectarlo: Supabase → Settings → API, y pega la URL y la clave anon.
 */
window.PLL_CONFIG = {
  url: 'https://rihtvipwxpusnfvlhzbf.supabase.co',
  anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJpaHR2aXB3eHB1c25mdmxoemJmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTEzNDYzNDAsImV4cCI6MjEwNjkyMjM0MH0.mSIlqcHPYIW125zipnJfWttfQvb91UKGlosouwc6U0s',
  eventSlug: 'haus-of-wonder',
  // Dirección que lleva el QR impreso. Va escrita a mano y no se deduce de
  // dónde esté abierta la página: si se generan las etiquetas desde el servidor
  // local, los QR tienen que apuntar igualmente a producción.
  // Tiene que ser la definitiva ANTES de imprimir: el QR no se puede cambiar
  // después. Si se compra un dominio propio, se cambia aquí primero.
  scanBase: 'https://pasa-la-llama.vercel.app/q?t='
};

window.PLL = (function () {
  'use strict';

  var cfg = window.PLL_CONFIG;
  var configured = cfg.url.indexOf('TU-PROYECTO') === -1 && cfg.anonKey.indexOf('TU-CLAVE') === -1;

  var client = configured && window.supabase
    ? window.supabase.createClient(cfg.url, cfg.anonKey, {
        auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true }
      })
    : null;

  /* Mensajes de error en castellano para los códigos que lanza la base. */
  var ERRORS = {
    sin_sesion: 'No pudimos abrir tu sesión. Recarga la página e inténtalo otra vez.',
    nombre_invalido: 'Escribe tu nombre, de dos letras en adelante.',
    codigo_invalido: 'El código no coincide. Revisa los cuatro caracteres impresos bajo el QR.',
    evento_cerrado: 'La experiencia todavía no está abierta.',
    encendedor_retirado: 'Este encendedor ya no está en circulación.',
    limite_encendedor: 'Este encendedor llegó a su límite de escaneos por esta noche.',
    limite_persona: 'Llegaste al máximo de encendedores por persona.',
    expulsado: 'Tu acceso fue bloqueado por la organización.',
    no_autorizado: 'Tu cuenta no tiene permiso para esto.',
    sin_familias: 'Crea al menos una familia antes de generar encendedores.'
  };

  function message(error) {
    if (!error) return '';
    var raw = error.message || String(error);
    for (var key in ERRORS) {
      if (raw.indexOf(key) !== -1) return ERRORS[key];
    }
    if (raw.indexOf('Failed to fetch') !== -1) {
      return 'Sin conexión. Revisa la señal e inténtalo de nuevo.';
    }
    return raw;
  }

  return {
    cfg: cfg,
    client: client,
    configured: configured,
    message: message
  };
})();
