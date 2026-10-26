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
| D-39 | **La vía del `bool` en Sucursales**, que el router hace innecesaria. **El router YA ENTRÓ** y se quedó con el apartado y la pestaña: la memoria de la pestaña por apartado, el guardia de las direcciones que esta sesión no puede ver y el historial del navegador. **Lo que falta para cerrarla** es que lo que se abre DENTRO de una pestaña —Tipos de sucursal, el expediente de una sucursal y los pasos de Empresa— sea una **ruta hija**; hasta entonces la pantalla sigue publicando su tercer segmento del rastro con un callback. El traductor ya existe y está probado: `rutas.nombreDeLoDeDentro` | `porton_web.dart` (el ⏳ del tercer segmento) · `sucursales_web_screen.dart:95` | **C1, en el commit siguiente al del router** — y **C1 no cierra sin ella** |
| D-40 | **Paridad de Organización:** el expediente de Área y el árbol de ubicaciones no tienen pantalla | `inventario-organizacion.md:237` y `:241` | **O-1 · Paridad y choque de edición en Organización**, con **D-03** |
| D-41 | **El ícono por dato en la tarjeta fiscal** | `requisitos-nuevos-del-dueno.md:40` | **E4 · La tarjeta fiscal en PDF** |
| D-42 | ✅ **DECIDIDA el 25-oct-2026** y convertida en compromiso: el Client de un eventual es **opcional**, el receptor fiscal se captura en el propio eventual y el documento fiscal se registra **desde el lado del eventual** | `mapa-equivalencias.md:330` | **Ya no es deuda: es el compromiso CP-11**, con su prueba pendiente |
| D-43 | ✅ **DECIDIDA ENTERA el 25-oct-2026** y convertida en dos compromisos: el mes vale 30 días (**CP-12**) y **cada falta descuenta un día de salario diario = mensual ÷ 30, sin ponderar** (**CP-14**) | `mapa-equivalencias.md:845` | **Ya no es deuda: son los compromisos CP-12 y CP-14**, cada uno con su prueba pendiente |
| D-44 | **El sistema de diseño está duplicado**: `riseg_entity_identity` no es compatible con la web | `design_system_web.dart:14` | **Fin de la mudanza**, con D-31 |
| D-45 | **Buscador global y notificaciones** no existen en la web | `marco_administra.dart:47` | **Cuando se muden Búsqueda y Notificaciones** |
| D-46 | ✅ **CERRADA el 25-oct-2026, en C1.** El 402 de una suscripción restringida se traduce en **un solo lugar** —`MensajesHumanos.deMutacion`— y las dieciséis mutaciones de Organización pasan por ahí: dicen que se puede consultar pero no guardar, y que lo resuelve quien administra el pago. El marco lleva además la franja «Suscripción limitada: sólo consulta», que el portón enciende con el `restricted` del contexto | `mensajes_humanos.dart` · `marco_administra.dart` · `porton_web.dart` | **Entregada** |
| D-47 | **El diálogo de tiempo extra necesita que su contenido sea un widget con estado propio** (escritorio) | `registrar_tiempo_extra_dialog.dart:791` | **Personal y Tiempos extra en la web** |
| D-53 | **`flutter analyze lib test` reporta 190 avisos `info`** —`prefer_const_constructors` y similares—, con cero warnings y cero errores. Se descubrió el 25-oct-2026 al medirlo para un commit, y contradecía el «analyze limpio» que estaba registrado. **El dueño decidió ese mismo día qué significa limpio: CERO errores, CERO warnings y CERO info.** Al cerrar C1, en un **commit propio y separado**: `dart fix --apply`, lo que quede se corrige a mano, y la suite completa en verde | medido con `flutter analyze lib test` | **Al cerrar C1** |
| D-55 | **La web todavía no calcula ningún «hoy», y cuando lo haga tiene que ser el día de México.** Medido el 25-oct-2026, al corregir el mismo error en el backend: hoy la web **no deriva ninguna fecha de negocio** —lo único que convierte a UTC son caducidades de token, que es correcto, y el único `DateTime.now()` es el valor inicial del selector de fechas, que en Dart ya es hora local—. **El riesgo llega con las pantallas de Clientes**, donde la fecha de inicio se propone con «hoy»: si sale de `DateTime.now().toUtc()`, de las 18:00 a las 23:59 propondrá mañana. **Tiene que pasar por un solo ayudante** —el equivalente de `FechaDeNegocio` del servidor— con su prueba a las 23:30, y entonces hay un sitio al que ponerle candado | medido en `lib/core/api/json_api.dart` y `riseg_date_field.dart` | **C1, con las pantallas de Clientes** |
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
