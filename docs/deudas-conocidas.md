# Deudas conocidas de la web de Administra

**Lo que falta, con su etapa.** No es una lista de tareas: es el registro de lo que se dejó
a medias a propósito, de lo que no se puede hacer todavía y de lo que está esperando una
decisión.

**La numeración `D-xx` es única entre los dos repositorios.** Las del backend viven en
`seventra-backend/docs/deudas-conocidas.md` y van de **D-01 a D-27**; aquí empiezan en
**D-28**. Así un número nunca significa dos cosas, y un `TODO(D-38)` en cualquier archivo
de cualquiera de los dos repositorios apunta a una sola fila.

## Qué significa «limpio», decidido el 25 de octubre de 2026

**`flutter analyze lib test` tiene que salir en CERO: cero errores, cero warnings y cero
`info`.** No «cero warnings y los `info` se toleran», que es lo que la frase «analyze
limpio» había acabado significando sin que nadie lo decidiera.

**Y es parte de cerrar una etapa**, junto con la suite completa en verde. Está escrito
también en la hoja de comandos de `mudanza-a-la-nube.md`, que es de donde se copian los
bloques que se corren.

> **Por qué no lo vigila una prueba.** Haría falta que la suite invocara la cadena de
> herramientas desde dentro —una prueba lanzando `flutter analyze`—, que tarda lo que tarda
> el análisis entero y falla por razones que no son del código. Va en la **checklist de
> cierre de etapa**, que es donde se mira una vez y de verdad.

## La regla, la misma que en el backend

1. **Al abrir una etapa** se leen este archivo, el del backend y
   `seventra-backend/docs/compromisos.md`, completos.
2. **Al cerrar una etapa** se leen otra vez. **Ninguna etapa se cierra con una deuda que
   tenía asignada.**
3. **Ninguna deuda puede quedar sin etapa.** Una deuda nueva se anota con su etapa en el
   momento en que se descubre, no al final.
4. Una deuda **no se borra**: pasa a ✅ con el commit que la resolvió.

Creado el 25 de octubre de 2026, en el barrido completo de pendientes previo a C1.

---

## Tabla

| # | Deuda | Dónde está escrita | Etapa que la resuelve |
|---|---|---|---|
| D-28 | **Identidad unificada**: misma tipografía, paleta y logotipo en correos, Console y Administra. Hoy el verde `#1E7F45` es lo único común y la tipografía ya difiere | `mudanza-a-la-nube.md:292` · `marca_seventra.dart:18,23` | **Antes del piloto y antes de vender** |
| D-29 | **«¿Olvidaste tu contraseña?» en la web.** El backend ya la tiene, con correo real y token de un solo uso; el botón no está enganchado | `mudanza-a-la-nube.md:787` · `login_web_screen.dart:40` | **Antes del piloto** (requisito). El registro de cuentas nuevas sigue siendo decisión comercial y no entra aquí |
| D-30 | **Cookie `HttpOnly` para el token de refresco.** Hoy vive en el almacenamiento del navegador y un token robado abre una sesión con sueldos e INE detrás | `mudanza-a-la-nube.md:292` · `almacen_sesion_remota_web.dart:23` | **Antes del piloto, no antes de producción** (el piloto ya trae datos reales) |
| D-31 | **Dos modelos por entidad** mientras dure la mudanza: el del escritorio y el de la web | `mudanza-a-la-nube.md:161` · `area.dart:12` | **Fin de la mudanza.** Se cierra sola cuando no quede pantalla de escritorio |
| D-32 | **Plantillas de permisos editables por empresa** | `mudanza-a-la-nube.md:745` | **A la espera de que un cliente lo pida**, y se revisa **al cerrar el piloto** para que la espera tenga un punto de control |
| D-33 | **Pantalla para enviar la invitación de alta.** La ruta existe y no hay desde dónde llamarla | `mudanza-a-la-nube.md:762` | **Usuarios en la web** |
| D-34 | **Mostrar los accesos usados contra los del plan** («2 de 5 del plan») | `mudanza-a-la-nube.md:764` y `:1237` | **Antes del piloto**, junto con **D-06**, que es su lado de servidor |
| D-35 | **Mantener el catálogo de regímenes fiscales del SAT desde Console**, sin migración | `mudanza-a-la-nube.md:767` y `:1940` · `requisitos-nuevos-del-dueno.md:137` | **Console mínimo para vender** (CP-10), con **D-27** |
| D-36 | **Ajuste visual del login web** | `mudanza-a-la-nube.md:848` | **Antes del piloto**, con D-28 |
| D-37 | **El catálogo de permisos no manda el nombre del módulo**, sólo `moduleCode`, así que la pantalla lo traduce por su cuenta | `mudanza-a-la-nube.md:1053` | **Usuarios en la web** |
| D-38 | **Toda ruta que reemplaza una colección completa pierde la escritura de quien guardó primero, sin avisar.** Los dos expedientes ya están cubiertos con `*_version` + 409; las demás no | `mudanza-a-la-nube.md:1885` | **C3 de Clientes y servicios**, y la razón es que **las condiciones comerciales son una de esas rutas**: el horario semanal se reemplaza completo |
| D-39 | ✅ **CERRADA el 26-oct-2026.** El router entró con el apartado y la pestaña, y este commit se llevó **lo que se abre dentro**: `…/sucursales/tipos`, `…/sucursales/<id>/expediente`, `…/empresa/editar` y `…/empresa/administracion` son direcciones, así que el rastro **se deriva** de la dirección y ninguna pantalla lo publica con un callback. Las cuatro decisiones que quedan escritas: la URL lleva **sólo el id** y el nombre sale de los datos cargados (nunca de la URL, que quedaría vieja al renombrar); un id que no está en la lista **devuelve a la lista**; `seAbreLoDeDentro` deja el rastro mudo para la administración de empresas sin autoridad de Organization —la única dirección que el guardia del router no puede juzgar—; y la pantalla **pide**, no navega | `rutas_web.dart` · `porton_web.dart` (`_rastroDeDentro`) · `rutas_hijas_en_pantalla_test.dart` | **Entregada en C1** |
| D-40 | **Paridad de Organización:** el expediente de Área y el árbol de ubicaciones no tienen pantalla | `inventario-organizacion.md:237` y `:241` | **O-1 · Paridad y choque de edición en Organización**, con **D-03** |
| D-41 | **El ícono por dato en la tarjeta fiscal** | `requisitos-nuevos-del-dueno.md:40` | **E4 · La tarjeta fiscal en PDF** |
| D-42 | ✅ **DECIDIDA el 25-oct-2026** y convertida en compromiso: el Client de un eventual es **opcional**, el receptor fiscal se captura en el propio eventual y el documento fiscal se registra **desde el lado del eventual** | `mapa-equivalencias.md:330` | **Ya no es deuda: es el compromiso CP-11**, con su prueba pendiente |
| D-43 | ✅ **DECIDIDA ENTERA el 25-oct-2026** y convertida en dos compromisos: el mes vale 30 días (**CP-12**) y **cada falta descuenta un día de salario diario = mensual ÷ 30, sin ponderar** (**CP-14**) | `mapa-equivalencias.md:845` | **Ya no es deuda: son los compromisos CP-12 y CP-14**, cada uno con su prueba pendiente |
| D-44 | **El sistema de diseño está duplicado**: `riseg_entity_identity` no es compatible con la web | `design_system_web.dart:14` | **Fin de la mudanza**, con D-31 |
| D-45 | **Buscador global y notificaciones** no existen en la web | `marco_administra.dart:47` | **Cuando se muden Búsqueda y Notificaciones** |
| D-46 | ✅ **CERRADA el 25-oct-2026, en C1.** El 402 de una suscripción restringida se traduce en **un solo lugar** —`MensajesHumanos.deMutacion`— y las dieciséis mutaciones de Organización pasan por ahí: dicen que se puede consultar pero no guardar, y que lo resuelve quien administra el pago. El marco lleva además la franja «Suscripción limitada: sólo consulta», que el portón enciende con el `restricted` del contexto | `mensajes_humanos.dart` · `marco_administra.dart` · `porton_web.dart` | **Entregada** |
| D-47 | **El diálogo de tiempo extra necesita que su contenido sea un widget con estado propio** (escritorio) | `registrar_tiempo_extra_dialog.dart:791` | **Personal y Tiempos extra en la web** |
| D-53 | **`flutter analyze lib test` reporta 190 avisos `info`** —`prefer_const_constructors` y similares—, con cero warnings y cero errores. Se descubrió el 25-oct-2026 al medirlo para un commit, y contradecía el «analyze limpio» que estaba registrado. **El dueño decidió ese mismo día qué significa limpio: CERO errores, CERO warnings y CERO info.** Al cerrar C1, en un **commit propio y separado**: `dart fix --apply`, lo que quede se corrige a mano, y la suite completa en verde | medido con `flutter analyze lib test` | **Al cerrar C1** |
| D-56 | **El trabajo sin guardar se puede perder por tres caminos que el router abre, y los tres hay que cerrarlos.** Hoy salir del formulario de Empresa pasa por `_seguroDeSalir`, que pregunta; con la dirección como estado, **cambiarla no pasa por la pantalla**. Decidido por el dueño el 25-oct-2026: se entregan las rutas hijas con el guardia que ya existe —que sigue cubriendo la navegación dentro de la aplicación— y **esta deuda es de etapa C1: C1 NO CIERRA sin ella, y nada de esto llega al ensayo con el hueco abierto**. Los tres caminos, **cada uno con su prueba**: (1) el **botón «atrás»** del navegador, con `GoRoute.onExit` —que pide partir la ruta única del router en rutas de verdad—; (2) **recargar** la página; (3) **cerrar la pestaña**, con el aviso `beforeunload` del navegador. Los tres comparten la misma pregunta que ya existe, así que lo que falta es el gancho, no la decisión | `porton_web.dart` (el router) · `empresas_web_screen.dart` (`_seguroDeSalir`) · `core/company/guardia_de_salida.dart` | **C1 — y C1 no cierra sin ella** |
| D-55 | **El «hoy» que proponga la web tiene que ser el día de la Ciudad de México, −06:00 FIJO** —el mismo criterio que `FechaDeNegocio` del servidor—, **y no la hora del navegador**. Decidido por el dueño el 25-oct-2026, y la razón es que **México tiene varias zonas**: Cancún está en −05, el Pacífico en −07 y Tijuana en −08/−07. Con la hora del navegador, alguien en Cancún vería un «hoy» **distinto al del servidor** durante una hora cada día, y en Tijuana durante dos: propondría una fecha que el servidor leería como otra. Hoy la web **no deriva ninguna fecha de negocio** —lo único que convierte a UTC son caducidades de token, y el único `DateTime.now()` es el valor inicial del selector—, así que no hay nada que corregir todavía; **el riesgo llega con las pantallas de Clientes**, donde la fecha de inicio se propone con «hoy». **Tiene que pasar por un solo ayudante**, con **dos pruebas**: a las 23:30 de la Ciudad de México, y **con el navegador en otra zona** —Cancún y Tijuana— comprobando que el día propuesto es el mismo. **Mostrar un instante con `.toLocal()` sigue siendo correcto** y no entra aquí: la bitácora dice cuándo pasó algo en la hora de quien lo lee, que es lo que esa persona quiere | medido en `lib/core/api/json_api.dart` y `riseg_date_field.dart` · candado en `test/core/fechas_de_negocio_test.dart` | **C1, con las pantallas de Clientes** |
| D-54 | **La URL de la web lleva `#`** —`…/#/organizacion/sucursales`— y falta pasarla a URL limpia. **No es cosmética: exige que el hospedaje devuelva `index.html` en TODA ruta**, porque un router de rutas limpias no existe para el servidor: recargar en `/organizacion` pediría un archivo que no está y daría 404. En Cloud Run lo resuelve el propio contenedor sirviendo `index.html` como respaldo de cualquier ruta no encontrada; en un hospedaje estático, su regla de reescritura. El cambio en Flutter es **una línea** —`usePathUrlStrategy()`—, y por eso se deja para cuando el hospedaje esté decidido y se pueda comprobar la recarga en pantalla, no antes | `diseno-router-web.md` §8 | **El hospedaje definitivo de la web** |
| D-48 | ✅ **CERRADA el 25-oct-2026, en C1.** Los tres inventarios que los nueve de `inventario-riseg-one/` dejaron superados —`inventario-comercial.md`, `inventario-personal.md` e `inventario-nomina.md`— ya no se presentan como inventarios: su encabezado dice cuál es la referencia que manda y conservan, como «decisiones del dueño», los requisitos que ningún inventario del escritorio puede saber | `inventario-comercial.md` · `inventario-personal.md` · `inventario-nomina.md` | **Entregada** |

---

## Lo que NO es deuda, y por qué se dice aquí

- **La bóveda y el respaldo no están en la mudanza a propósito** (`mudanza-a-la-nube.md:455`).
  Es una decisión tomada, no un pendiente.
- **`fallo_de_conexion_web.dart:13`** decía con ⏳ que el mensaje de error «se podría
  afinar». No es un pendiente: es la decisión de no afinarlo. El marcador se reescribe como
  decisión para que no lo cuente el candado.
- **«PENDIENTE» como palabra del negocio** no es un marcador: una cuota pendiente, una
  invitación pendiente, un bien pendiente de recuperación y un complemento pendiente son
  **estados de datos**. El candado sólo mira los marcadores (⏳ y `PENDIENTE` como etiqueta
  al principio de una línea o de un título).
