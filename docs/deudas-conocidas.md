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
| D-39 | **La vía del `bool` en Sucursales**, que el router haría innecesaria | `mudanza-a-la-nube.md:1497` · `sucursales_web_screen.dart:95` | **C1 de Clientes y servicios**: es cuando entra un apartado nuevo con pestañas y la pregunta del router se vuelve inevitable |
| D-40 | **Paridad de Organización:** el expediente de Área y el árbol de ubicaciones no tienen pantalla | `inventario-organizacion.md:237` y `:241` | **O-1 · Paridad y choque de edición en Organización**, con **D-03** |
| D-41 | **El ícono por dato en la tarjeta fiscal** | `requisitos-nuevos-del-dueno.md:40` | **E4 · La tarjeta fiscal en PDF** |
| D-42 | ✅ **DECIDIDA el 25-oct-2026** y convertida en compromiso: el Client de un eventual es **opcional**, el receptor fiscal se captura en el propio eventual y el documento fiscal se registra **desde el lado del eventual** | `mapa-equivalencias.md:330` | **Ya no es deuda: es el compromiso CP-11**, con su prueba pendiente |
| D-43 | ✅ **DECIDIDA ENTERA el 25-oct-2026** y convertida en dos compromisos: el mes vale 30 días (**CP-12**) y **cada falta descuenta un día de salario diario = mensual ÷ 30, sin ponderar** (**CP-14**) | `mapa-equivalencias.md:845` | **Ya no es deuda: son los compromisos CP-12 y CP-14**, cada uno con su prueba pendiente |
| D-44 | **El sistema de diseño está duplicado**: `riseg_entity_identity` no es compatible con la web | `design_system_web.dart:14` | **Fin de la mudanza**, con D-31 |
| D-45 | **Buscador global y notificaciones** no existen en la web | `marco_administra.dart:47` | **Cuando se muden Búsqueda y Notificaciones** |
| D-46 | **La web no escucha `restricted`.** Con la suscripción restringida toda mutación responde 402 y la pantalla muestra un error genérico | `porton_web.dart:65` | **C1 de Clientes y servicios**: es la primera etapa que mete muchas mutaciones nuevas |
| D-47 | **El diálogo de tiempo extra necesita que su contenido sea un widget con estado propio** (escritorio) | `registrar_tiempo_extra_dialog.dart:791` | **Personal y Tiempos extra en la web** |
| D-53 | **`flutter analyze lib test` reporta 190 avisos `info`** —`prefer_const_constructors` y similares—, con cero warnings y cero errores. Se descubrió el 25-oct-2026 al medirlo para un commit, y contradecía el «analyze limpio» que estaba registrado. **El dueño decidió ese mismo día qué significa limpio: CERO errores, CERO warnings y CERO info.** Al cerrar C1, en un **commit propio y separado**: `dart fix --apply`, lo que quede se corrige a mano, y la suite completa en verde | medido con `flutter analyze lib test` | **Al cerrar C1** |
| D-48 | **Tres inventarios quedaron superados** por los nueve de `seventra-backend/docs/inventario-riseg-one/`: `inventario-comercial.md`, `inventario-personal.md` e `inventario-nomina.md` conservan decisiones que no se pueden perder y ya no son la referencia | `inventario-comercial.md:3` · `inventario-personal.md:3` · `inventario-nomina.md:3` | **Cada uno en su módulo**: el comercial en **C1**, los otros dos en el suyo. Se convierten en «decisiones del dueño sobre este apartado» y apuntan al inventario que manda |

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
