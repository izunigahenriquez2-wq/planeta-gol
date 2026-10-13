# Planeta Gol · Cuentas, Balones de Oro y Ranking Mundial

> **Tienda de Premios: desactivada por ahora** (migración `20261013000000_tienda_desactivada.sql`). El sitio ya no la muestra y el servidor rechaza cualquier canje. Las tablas y funciones de la tienda siguen guardadas para poder reactivarla más adelante.

## Arquitectura
- **Frontend:** `index.html` (un solo archivo). Usa `@supabase/supabase-js` por CDN y lee `window.PG_SUPABASE` (`/supabase-config.js`).
- **Configuración:** `scripts/build.mjs` (comando de build en `vercel.json`) genera `dist/supabase-config.js` desde las variables de Vercel `NEXT_PUBLIC_SUPABASE_URL` y `NEXT_PUBLIC_SUPABASE_ANON_KEY`. Un sitio HTML estático no las recibe solo. El build **falla** si detecta una clave secreta (`service_role` / `sb_secret_*`).
- **Base de datos:** `supabase/migrations/` (3 archivos, ya aplicados en el proyecto «Planeta Gol»).

## Modelo de datos
| Tabla / vista | Contenido | Acceso desde el navegador |
|---|---|---|
| `profiles` | usuario único (sin distinguir mayúsculas), cosméticos equipados | lectura pública; solo `username` editable por su dueño |
| `balones_oro` | **total histórico ganado** | lectura pública; nadie escribe |
| `balones_saldo` | **saldo disponible** (privado) | solo lo ve su dueño; nadie escribe |
| `premios` | catálogo (precio, disponibilidad, tipo) | lectura pública; solo SQL/service_role escribe |
| `premios_usuario` | premios adquiridos | solo los ve su dueño; nadie escribe |
| `actividad` | avance hacia el próximo Balón y conteo del día (no es historial) | ninguno (se lee con `mi_progreso`) |
| `balones_config` | parámetros de ganancia por tiempo | ninguno |
| `partidas_premiadas` | solo `partida_id` + hora; hoy vacía | ninguno |
| `ranking_mundial` (vista) | posición, usuario, total, cosméticos | lectura pública |

## Funciones (SECURITY DEFINER, `search_path` vacío)
- `registrar_latido()` y `mi_progreso()`: Balones por tiempo activo (usuarios con sesión; la identidad sale de `auth.uid()`).
- `admin_configurar_balones(segundos, tope, sin_tope)`: **solo `service_role`**.
- `otorgar_victoria(partida_id, ganador)`: +1 total. **Solo `service_role`.** Idempotente por partida. Hoy no la usa nadie (queda lista para el futuro).
- `canjear_premio(premio_id)`: bloquea la fila de saldo, lee el precio en el servidor, descuenta y registra la propiedad en una sola transacción. Errores: `SALDO_INSUFICIENTE`, `YA_LO_TIENES`, `PREMIO_NO_DISPONIBLE`, `NO_AUTENTICADO`.
- `equipar_premio` / `desequipar_premio`: solo premios que el usuario posee.
- `username_disponible(nombre)`: comprobación previa al registro.
- `admin_actualizar_premio(id, precio, disponible)`: **solo `service_role`**. Alternativa: SQL Editor.

### `partidas_premiadas` (hoy sin uso)
Guarda únicamente el identificador de la partida y la hora, para impedir recompensas duplicadas (reintentos, recargas, solicitudes simultáneas). **No** guarda ganador, participantes ni resultado, y `otorgar_victoria` borra los registros de más de 7 días. Ningún cliente puede leerla.

## Cambiar precios (solo si se reactiva la tienda)
```sql
select public.admin_actualizar_premio('avatar_leon', 4);            -- nuevo precio
select public.admin_actualizar_premio('avatar_dragon', null, false); -- ocultar a la venta
```

## Cómo se ganan los Balones de Oro: AUTOMÁTICAMENTE mientras la página está abierta
Con la sesión iniciada, el navegador envía un **latido** (`registrar_latido`) cada minuto mientras Planeta Gol está abierto. **El servidor cuenta el tiempo con su propio reloj**:
- **1 Balón de Oro cada 5 minutos**, **sin límite diario** (`tope_diario = NULL`).
- Un latido que llega antes de 45 s del anterior no suma (dos pestañas o dispositivos del mismo usuario no suman a la vez: la fila se bloquea).
- Cada latido suma como máximo 90 s, aunque haya pasado más tiempo (si el navegador suspende la pestaña o se apaga el equipo, no acumula).
- No se exige actividad (ratón/teclado): basta con tener la página abierta. Con la pestaña oculta puede contar menos si el navegador la suspende (sobre todo en celulares).
- Nadie declara ganadores y no hay recompensas por partidas.
- El perfil muestra una barra con el avance hacia el próximo Balón.

**Efectos de no tener tope:** el ranking mide quién deja la página abierta más tiempo (unos 288 Balones al día con 24 horas abierta), y una persona puede acumular Balones sin jugar. Si se quiere moderar: `select public.admin_configurar_balones(300, 50);` (tope de 50 al día) o `select public.admin_configurar_balones(600);` (1 cada 10 minutos). Para quitar el tope otra vez: `select public.admin_configurar_balones(null, null, true);`.
Si más adelante se quieren Balones por ganar partidas, la función `otorgar_victoria` ya existe (solo `service_role`), pero necesita un servidor que valide los resultados.

## Variables de entorno de Vercel
- `NEXT_PUBLIC_SUPABASE_URL` (ya creada)
- `NEXT_PUBLIC_SUPABASE_ANON_KEY` (ya creada; clave pública `anon`/publishable)
- **No** crear ninguna variable `NEXT_PUBLIC_` con `service_role`.

## Acciones manuales pendientes
1. Crear la rama `feature/balones-oro`, copiar los archivos de este directorio y hacer *push* (Vercel crea el Preview solo).
2. Supabase → Authentication → URL Configuration: poner la URL del sitio y añadir las URL de Preview a *Redirect URLs* (necesario para confirmar correo y recuperar contraseña).
3. Supabase → Authentication → Providers → Email: decidir si exige confirmación de correo (la interfaz funciona con ambas opciones). Activar *leaked password protection*.
4. Probar el registro real con un correo tuyo en el Preview.

## Pruebas
`supabase/tests/balones_oro_pruebas.sql` y `supabase/tests/balones_por_tiempo_pruebas.sql` (se revierten solos). Ejecutadas con éxito en el proyecto real.
