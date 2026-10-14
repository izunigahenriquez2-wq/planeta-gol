# Planeta Gol · Cuentas, Balones de Oro y Ranking Mundial

> **Tienda de Premios: desactivada por ahora** (migración `20261013000000_tienda_desactivada.sql`). El sitio ya no la muestra y el servidor rechaza cualquier canje. Las tablas y funciones de la tienda siguen guardadas para poder reactivarla más adelante.

## Arquitectura
- **Frontend:** `index.html` (un solo archivo). Usa `@supabase/supabase-js` por CDN y lee `window.PG_SUPABASE` (`/supabase-config.js`).
- **Configuración:** el archivo `supabase-config.js` (junto a `index.html`, en la raíz del repositorio) define `window.PG_SUPABASE` con la URL del proyecto y la clave **anon** (pública por diseño; la protege RLS). Un sitio HTML estático no recibe las variables `NEXT_PUBLIC_*` de Vercel, por eso el archivo va dentro del repositorio. Alternativa con variables de Vercel: carpeta `alternativa-con-variables-de-vercel/`. **Nunca** pongas la clave `service_role` ni `sb_secret_*` en el sitio.
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

## Sobres de jugadores (gacha), álbum y alineación 4-3-3
- **Cuesta 5 Balones disponibles** (`sobres_config.costo`). Cada sobre trae 5 jugadores al azar del **álbum**: 1.133 cartas de 71 selecciones (leyendas y actuales, los mismos jugadores de la Ruleta; las 16 mejores de cada selección, con al menos portero, defensas, medios y delanteros).
- **Todo el azar y todos los cobros ocurren en el servidor** (`abrir_sobre`): el navegador no decide nada y no puede llamar al sorteo. La operación es atómica (cobro, sorteo, colección, alineación) y los sobres simultáneos de una misma persona se atienden en fila.
- **Probabilidades** (por carta, cartas 1–4): Común 58,5 % · Poco común 28 % · Rara 10 % · Épica 3 % · Legendaria 0,5 %. La **5.ª carta nunca es Común** (0 / 67,5 / 24,1 / 7,2 / 1,2 %). La rareza sale de la media del jugador, con un bonus para las leyendas (los más famosos son más difíciles): por carta, una Común sale con 0,136 % y una Legendaria con 0,015 %.
- **Garantías:** Épica o mejor al menos cada 15 sobres; Legendaria al menos cada 60. Los contadores son privados (`sobres_estado`).
- **Reciclaje:** 3 repetidas = 1 Balón **disponible** (no sube el total histórico del ranking, para que no se pueda inflar). Siempre se conserva 1 copia de cada carta.
- **Alineación 4-3-3** (`alineacion`, pública): cada carta nueva se coloca sola en un puesto libre (primero su puesto exacto; los extremos y el delantero aceptan a sus vecinos). Se puede cambiar a mano desde el perfil (solo con cartas propias y puestos compatibles).
- **Álbum:** 71 páginas, una por selección; cada carta obtenida se "pega" sola. Colección privada (`coleccion`), resumen público (`perfil_cartas`).
- **Ranking Mundial:** muestra para cada jugador cuántos puestos lleva de su alineación, cuántas cartas únicas tiene y el mejor jugador de su último sobre; al tocarlo se ve su alineación completa y su último sobre, **en tiempo real**.
- **Añadir cartas:** las cartas son `CARDS` en `index.html` (el id es la posición) y la tabla `cartas`. Solo se pueden **añadir al final**; nunca reordenar ni borrar.
- Cambiar el precio: `select public.admin_configurar_sobres(8);` · cambiar el reciclaje: `select public.admin_configurar_sobres(null, 4);`
- Pruebas: `supabase/tests/sobres_pruebas.sql` y `supabase/tests/sobres_probabilidades.sql` (se revierten solos).

## Variables de entorno de Vercel
Con `supabase-config.js` en el repositorio no se necesita ninguna (las dos `NEXT_PUBLIC_SUPABASE_*` que ya existen quedan sin uso; sirven solo para la alternativa del build).

## Acciones manuales pendientes
1. Subir `index.html` **y** `supabase-config.js` a la raíz del repositorio (rama de prueba o `main`). Comprobar que `https://TU-SITIO/supabase-config.js` muestra el archivo (si da 404, el aviso «Las cuentas no están configuradas» seguirá apareciendo).
2. Supabase → Authentication → URL Configuration: poner la URL del sitio y añadir las de Preview a *Redirect URLs* (correo de confirmación y recuperación de contraseña).
3. Supabase → Authentication → Providers → Email: decidir si se exige confirmar el correo (la interfaz funciona con ambas opciones). Con el correo integrado de Supabase solo se envían mensajes a miembros del equipo y con límite por hora; para pruebas, desactiva «Confirm email» o configura tu propio SMTP.
4. Probar el registro real y comprobar que la barra de progreso avanza.

## Pruebas
`supabase/tests/balones_oro_pruebas.sql` y `supabase/tests/balones_por_tiempo_pruebas.sql` (se revierten solos). Ejecutadas con éxito en el proyecto real.
