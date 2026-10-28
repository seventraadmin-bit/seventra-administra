# Las pantallas de Clientes en la web — diseño de C1

**Estado:** propuesto el 25 de octubre de 2026. Es la mitad de C1 que se ve; la otra —el servidor— ya
está entregada salvo los indicadores y el aviso de RFC repetido.

**Contra qué se escribió:** el inventario **02 — Comercial** de RISEG ONE
(`seventra-backend/docs/inventario-riseg-one/02-comercial-clientes-servicios.md`), sección por
sección. Lo que el escritorio hace y aquí no se va a hacer **está dicho con su razón**; no hay nada
omitido en silencio.

---

## 0. Los cinco estatus del escritorio contra los tres de la nube — **DECIDIDO**

**DECISIÓN DEL DUEÑO, 25 de octubre de 2026: la opción A.** Tres estatus, **el alta nace `active`**,
y **no se reabre `Client != Prospect`**. Con dos compromisos registrados, cada uno con su prueba
pendiente en `CompromisosPendientesTests`:

- **CP-15** — el **Prospect de 5D.10F cubre «Prospecto» y «Descartado»** del escritorio, y **se
  entrega antes de producción de Administra**: un producto a la venta no puede salir sin dónde
  registrar prospectos.
- **CP-16** — **la importación no convierte un prospecto en cliente**: los clientes del escritorio
  en Prospecto o Descartado se importan como **`Prospect`, con su estatus**, nunca como `Client`.
  Ninguno se pierde ni aparece como cliente activo por error.

Lo que sigue es el razonamiento con el que se tomó, que se conserva porque la decisión se va a
releer dentro de un año.

| Escritorio (5) | Nube hoy (3) |
|---|---|
| **Prospecto** (azul, y **todo cliente nace aquí**) | **no existe** |
| Activo | `active` |
| Suspendido | `suspended` |
| Terminado | `terminated` |
| **Descartado** (rojo) | **no existe** |

No es un olvido: la arquitectura congelada separa **`Client` de `Prospect`** —son dos cosas, no dos
estados de una— y el Prospect llega en **5D.10F** con el CRM. Pero el escritorio hoy **da de alta
todo cliente como Prospecto**, así que si las pantallas salen con tres estatus, quien use el
producto notará que falta.

**Las tres salidas que se pesaron:**

| | Qué implica |
|---|---|
| **A. Salir con tres y decirlo** ← **la elegida** | El alta nace **`active`**. La pantalla no habla de prospectos. Cuando llegue 5D.10F, los prospectos son otra lista —no otro filtro— y ningún dato se convierte en nada. **Es lo que el diseño congelado ya decidió**, y C1 no lo reabre |
| B. Añadir los dos estatus al `CHECK` del cliente | Migración nueva, y **contradice `Client != Prospect`**: un «cliente» prospecto es justo lo que 5D.10F viene a separar. Además «Descartado» sin Prospect no significa nada: un cliente que facturó no se descarta, se termina |
| C. Esperar a 5D.10F para las pantallas | Retrasa C1 entero por un estado de la lista |

**Por qué A y no B**, que es la que parecía más fácil: añadir «Prospecto» y «Descartado» al `CHECK`
del cliente deja el problema peor que antes, porque entonces **hay dos sitios donde vive un
prospecto** —el estatus del cliente y, en cuanto llegue, el Prospect— y la importación tendría que
decidir fila por fila a cuál de los dos va. A deja una sola respuesta: un prospecto es un Prospect.

**Lo demás que cambia respecto al escritorio ya lo decidiste tú** y está en el diseño del módulo: el
RFC pasa a **opcional y único por cliente** (en el escritorio es obligatorio y único global), los
contactos pasan a **tres tipos**, la entidad fiscal gana **régimen fiscal**, y el importe mensual
cuenta **sólo los servicios no terminados** (en el escritorio cuenta todos, terminados incluidos).

---

## 1. Las rutas, que son las del router (D-39)

```
/comercial                              → redirige a /comercial/clientes
/comercial/clientes                       el listado
/comercial/clientes/<id>                  el expediente, en consulta
/comercial/clientes/<id>/editar           el expediente, en edición
```

Y con esto el router queda completo para C1, porque éstas fijan la forma que faltaba:

```
/entrar                                   login
/elegir-empresa                           selector

/organizacion/empresa
/organizacion/sucursales
/organizacion/sucursales/tipos            ← el `bool` de hoy, que es D-39
/organizacion/sucursales/<id>/expediente
/organizacion/puestos
/organizacion/areas
/configuracion/usuarios
/configuracion/auditoria
```

**Qué tiene ruta y qué no, y es una regla, no caso por caso:** tienen ruta **los lugares** —una
lista, un expediente, un modo de edición—; **no** la tienen los diálogos. Un diálogo es transitorio
y publicar su dirección sería publicar un enlace a un formulario a medio llenar, que al abrirlo no
sabría de dónde venía. Así que contactos, entidades fiscales, domicilio fiscal, cambio de estatus y
logotipo **siguen siendo diálogos**, como en el escritorio.

**El rastro sale de la ruta:** «Comercial › Clientes › CLI-000004 Sportium». El tercer segmento es
el cliente, y lo resuelve la pantalla que ya lo tiene cargado.

---

## 2. El listado — `/comercial/clientes`

**Contra el inventario §2.3**, y sale completo salvo lo que depende de C5:

| Pieza | Cómo sale |
|---|---|
| Título y «Nuevo cliente» | igual |
| **Vigentes / Finalizados** | igual, chips. «Finalizados» = `terminated`. En el escritorio es Terminado **o Descartado**; sin Descartado, es un solo estatus |
| Buscador | **folio, nombre comercial y observaciones**. Hoy el servidor busca en folio y nombre: le falta observaciones, y entra en este commit |
| Filtro de estatus | los tres, más «Todos» |
| Filtro de servicios | «Todos / Con servicios / Sin servicios», donde «con servicios» = **al menos uno activo**, igual que el escritorio |
| «Limpiar filtros» | igual |
| Columna Nombre | **hoy iniciales** y el folio debajo. El **logotipo está pendiente de tu decisión**, y no es un olvido: ver el aviso de abajo |
| Columna Servicios | «N servicios», **sólo activos** |
| Columna Personal | «N personas» → **C5**, y hasta entonces **la columna no existe**. No sale en cero: ausencia nunca es cero, y un cero diría que el cliente no tiene gente |
| Columna Ubicación | «Municipio, Estado» del domicilio de referencia, o «No registrada» |
| Columna Estatus | insignia con color |
| Clic en la fila | abre el expediente |

**Los filtros se aplican en el servidor**, no en la pantalla, y por una razón medida: **Clientes no
tiene paginación** (es una deuda conocida del backend) y filtrar en el cliente obligaría a traer la
cartera entera para enseñar tres filas. El día que haya paginación, el filtro ya estará donde debe.

**Los indicadores por fila los calcula el servidor en una sola sentencia** (§5 del diseño del
módulo): una consulta por fila sería un N+1 en la pantalla que más se mira.

### El logotipo en el listado — **DECIDIDO el 26 de octubre de 2026**

**DECISIÓN DEL DUEÑO: la A para C1, y la C es el destino**, registrada como compromiso
**CP-20** con etapa **C2** y su prueba pendiente. Las tres condiciones de la C, que
hacen falta las tres:

1. **`GET /clients` dice si cada cliente tiene logotipo** y la **URL de una miniatura**;
2. el listado carga **sólo las miniaturas de las filas visibles**, con **caché**, y las
   **iniciales quedan como respaldo** cuando no hay logotipo **y mientras carga**;
3. **nunca se disparan cientos de descargas** al abrir la pestaña.

Lo que sigue es el razonamiento con el que se decidió, que se conserva porque la
decisión se va a releer.

El escritorio pinta el logotipo de cada cliente en la columna del nombre, y lo puede hacer
porque lo lee **del disco**. En la web cuesta **una petición HTTP por fila**: `GET /clients`
no trae el logotipo ni dice si hay uno, `RisegTableBase` **no virtualiza** —construye todas
las filas— y Clientes **no tiene paginación**, así que abrir la pestaña con doscientos
clientes dispararía doscientas descargas de golpe.

Las tres salidas, medidas:

| | Qué implica |
|---|---|
| **A. Iniciales en el listado, logotipo en la ficha** ← **lo entregado en C1** | Una petición en total. El color de las iniciales sale del `id`, así que renombrar un cliente no le cambia el color que lo vuelve reconocible. Lo que se pierde es ver la marca de un vistazo en la lista |
| B. Logotipo en el listado, una petición por fila | Fiel al escritorio y con el coste dicho arriba. La caché evita repetirlas al volver, no la primera ronda |
| **C. Que el servidor diga en `GET /clients` si hay logotipo** ← **el destino, CP-20 en C2** | Lo correcto a la larga —una columna más en la respuesta, y sólo se piden los que existen— y es **cambiar el servidor**, que en C1 ya estaba cerrado. Exige además **virtualizar la tabla o pedir por visibilidad**, que es trabajo propio de la web |

La A se entregó porque es la que **no se arrepiente**: con la C puesta, las iniciales
siguen siendo el respaldo de un cliente sin logotipo y mientras la miniatura carga, así
que nada de lo hecho se tira.

---

## 3. El alta — diálogo

**Contra el inventario §2.4.** Nombre comercial obligatorio, observaciones opcionales, logotipo
opcional con vista previa.

Tres diferencias con el escritorio, todas a favor:

1. **El alta pide la fecha de inicio**, porque el servidor la exige (`startedOn`) y el escritorio la
   pone sola. Se propone **hoy** por omisión y se puede cambiar: es la fecha en que empezó la
   relación, y en una alta de un cliente que ya era cliente no es hoy.
2. **El logotipo se sube después del alta**, igual que en el escritorio, y **si falla, el cliente
   queda creado**. La pantalla lo dice: «Se creó el cliente, pero no se pudo subir el logotipo».
   Callarlo dejaría a alguien creyendo que tiene que volver a crearlo.
3. **El error dice qué pasó.** En el escritorio cualquier fallo —nombre vacío, falta de permiso,
   error de red— sale como «No se pudo crear el Cliente. Intenta de nuevo.», y el inventario lo
   anota como duda. Aquí lo traduce `MensajesHumanos` en un solo sitio, que es lo que D-46 acaba de
   dejar montado.

**El alta no pide motivo**, y eso es del contrato: el motivo es para corregir, no para crear.

---

## 4. El expediente — `/comercial/clientes/<id>`

**Contra el inventario §2.5**, de arriba abajo:

1. **Cabecera.** Logotipo o iniciales, nombre comercial, folio, insignia de estatus. La razón social
   y el RFC se muestran **sólo si el cliente tiene exactamente una entidad fiscal activa** —con 0 o
   2+ sería ambiguo—, que es la regla del escritorio y es correcta. Botones: **Editar logotipo**,
   **Cambiar estatus**, **Editar**.
2. **Indicadores.** Servicios activos · Importe mensual contratado. **Personal asignado es C5** y
   hasta entonces no aparece. El importe lleva su letra chica, con estas palabras: *«Importe mensual
   contratado, sin IVA, de los servicios no terminados.»*
3. **Datos generales.** Folio (no editable), nombre comercial, observaciones y, en consulta, fecha
   de creación y última actualización.
4. **Domicilio de referencia**, opcional al capturarlo, con los diez campos y las reglas de
   dirección que ya usa el expediente de una sucursal — **el mismo widget, no una copia**. Y **una
   vez capturado se corrige, no se borra**: ver la decisión de abajo.
5. **Contactos**, con sus **tres** tipos y un principal por tipo. ⚠️ **En la nube un
   contacto SE ELIMINA, no se archiva** —es del contrato del servidor: «no son historia de
   nada, y son listas donde una fila capturada por error no se puede corregir
   sobrescribiendo»—, así que el diálogo lo dice con esas palabras en lugar de llamarlo
   «archivar», que prometería poder recuperarlo. **Eliminar pide motivo**, y el evento de
   la bitácora se queda con el nombre, el tipo, si era principal y las vías **enmascaradas**
   (`•••• 5678`, `an•••@sportium.mx`). Y **no se elimina al responsable de un servicio**: el
   servidor lo bloquea **nombrando el servicio**.
6. **Entidades fiscales**, incluidas las archivadas, con régimen fiscal y domicilio fiscal.
   Una **archivada no se edita** y sus acciones salen apagadas **con el porqué en el
   tooltip**; archivar y reactivar siempre se pueden, con motivo. El **régimen** sale del
   catálogo del SAT con **código y nombre** —«601 · General de Ley Personas Morales»— y un
   **retirado que ya está puesto se sigue ofreciendo**, porque si no el selector abriría en
   blanco y lo borraría al guardar. El **aviso de RFC repetido** deja el panel abierto con
   el aviso **junto al campo** y los otros clientes nombrados con su folio.
7. **Servicios del cliente** → **C2**. En C1 la sección existe con el aviso de que llega en la
   siguiente subetapa, porque su hueco explica más que su ausencia.
8. **Portales** → **C4**, por la misma razón.

**Lo que NO se trae del escritorio, y por qué:** «Ver en Agenda», «Ver cuentas por cobrar» y «Ver
pagos» son botones a módulos que en la nube no existen todavía (Agenda y Finanzas). Un botón que
lleva a un «Próximamente» es peor que no tenerlo.

### El domicilio de referencia **se corrige y no se borra** — DECISIÓN DEL DUEÑO (D-59)

**Decidido el 26 de octubre de 2026**, y es una decisión del producto, no un hueco:

> **En la nube, el domicilio de referencia de un cliente se corrige y no se borra.** El
> escritorio permitía vaciarlo —y vaciarlo lo archivaba—, pero **no hay caso de negocio para
> dejar a un cliente sin domicilio una vez capturado**.

Lo que la pantalla hace con eso:

- **al capturarlo sigue siendo opcional**: un cliente nuevo puede quedarse sin domicilio, y si los
  diez campos están vacíos no se manda nada;
- **en cuanto hay uno registrado**, la letra chica de la sección cambia y lo dice: «Una vez
  registrado, el domicilio se corrige: no se puede quitar desde aquí»;
- y si alguien lo vacía de todas formas, **no se manda la petición** y el mensaje lo explica, en
  lugar de dejar que el servidor conteste «Falta la calle.» —que es cierto y no dice qué pasa—.

**El servidor ya lo imponía**: no hay `DELETE` de domicilio y su `PUT` exige los seis campos
obligatorios. Lo que esta decisión fija es que **eso es lo correcto** y no algo que haya que
corregir después, así que no queda como pendiente de nadie.

---

## 5. Los cinco candados de la pantalla

Los pone el servidor; la pantalla los **explica**, y ninguno los sustituye.

| Candado | Dónde se nota |
|---|---|
| **El motivo es obligatorio** en corregir el cliente, su estatus, un contacto, retirarlo, una entidad fiscal y un portal | El diálogo tiene el campo, y el `400 motivo_requerido` lo señala en lugar de mostrar un error general |
| **El RFC repetido en otro cliente avisa y no bloquea** | Aviso ámbar junto al campo, con el folio y el nombre del otro cliente. **Se guarda igual**: lo decidiste así |
| **Un principal por tipo** | Mover de tipo a un principal cuyo destino ya tiene principal responde 409, y el mensaje dice qué resolver: «designa otro principal de ese tipo antes de moverlo» |
| **Una entidad fiscal archivada no se edita** | Las acciones de edición y de domicilio salen deshabilitadas, con el porqué |
| **La suscripción limitada** responde 402 a toda mutación | La franja del marco lo dice antes, y el mensaje de D-46 lo dice al intentar |

**Y uno que es de la web y no del escritorio:** aquí **lo que no se puede hacer no se muestra**. En
el escritorio los botones de Comercial no se ocultan y el bloqueo ocurre al pulsar; en la web, desde
Organización, la regla es la contraria y se queda así — con una excepción deliberada: **ningún botón
se apaga por `restricted`**, porque quien decide si una escritura procede es el servidor y una
pantalla que los apaga por su cuenta acaba apagándolos cuando no debía.

---

## 6. Los permisos, traducidos

| Escritorio | Nube |
|---|---|
| `comercial.ver` | `clients_services.read` |
| `clientes.crear` · `clientes.corregir` | `clients_services.manage` |
| `clientes.archivar` | `clients_services.manage` (no hay un permiso aparte para archivar) |
| Portales | `clients_services.portals.read` y `.portals.manage`, **protegidos**: el Maestro no los hereda |
| Eliminar físicamente (sólo Maestro) | **no existe en la nube**, y es deliberado: el rol de aplicación no tiene `DELETE` sobre `client` |

---

## 7. Qué falta del servidor antes de las pantallas

Dos cosas, las dos de C1 y las dos en este orden:

1. **Los indicadores** del listado y de la ficha, en una sola sentencia (§5 del diseño del módulo).
2. **El aviso de RFC repetido en otro cliente**, que viaja en la respuesta del alta y de la
   corrección de una entidad fiscal:
   `{ "warning": { "code": "rfc_en_otro_cliente", "clients": [{ "code": "CLI-000004", … }] } }`
3. Y de paso, **el buscador por observaciones**, que hoy no busca ahí.

---

## 8. El orden de entrega

| | Qué |
|---|---|
| 1 | Servidor: indicadores, aviso de RFC, buscador por observaciones |
| 2 | ✅ **El router** (D-39), con las rutas de §1 completas — entregado el 26-oct-2026 |
| 3 | ✅ **El trabajo sin guardar no se tira** (D-56) — entregado el 26-oct-2026 |
| 4 | ✅ **El listado y el alta** — entregados el 26-oct-2026, con **D-55** cerrada (el «hoy» del alta) |
| 5 | ✅ **El expediente: cabecera, indicadores, datos generales y domicilio** — entregado el 26-oct-2026, con el cambio de estatus y el logotipo. Dos hallazgos del contrato quedaron como **D-58** (la fecha de creación no existe en la respuesta) y uno escrito en pantalla: **el domicilio no se puede quitar desde la web** |
| 6 | ✅ **Contactos y entidades fiscales** — entregados el 26-oct-2026. Dos cambios del servidor que pediste y entraron con ellos: el **catálogo de regímenes del SAT acepta también `clients_services.read`** —antes exigía `company.settings.read` y dejaba sin selector a quien administra clientes—, y **eliminar un contacto responsable de un servicio se bloquea nombrando el servicio**, con el teléfono y el correo enmascarados en la bitácora |
| 7 | `flutter analyze` en cero (D-53) y las pruebas en pantalla contigo |

### Las pruebas en pantalla del cierre de C1

**No se automatizan ni se fabrican**, que es la regla de este proyecto para la verificación
por captura. Las tres primeras son de D-56 y son lo que la suite **no puede** afirmar,
porque el diálogo y el historial son del navegador:

| | Qué comprobar |
|---|---|
| 1 | **Recargar** con el expediente a medio escribir avisa, y cancelar deja lo escrito intacto |
| 2 | **Cerrar la pestaña** con el expediente a medio escribir avisa |
| 3 | **«Atrás»** con el expediente a medio escribir pregunta, y al cancelar **la barra del navegador vuelve a decir la dirección correcta** — hay una entrada de más en el historial, así que volver a pulsar «atrás» vuelve a preguntar; es lo esperado |
| 4 | El recorrido de Clientes completo: listado, alta, expediente, contactos y entidades fiscales |

### ⚠️ La regla permanente que nace con C1

> **Toda pantalla con «Guardar» se registra en el `GuardiaDeSalida`.**

Decidida por el dueño el 26 de octubre de 2026 al aprobar D-56, y **con candado**:
`test/app/shell/guardia_cubre_los_formularios_test.dart` pone la suite roja si un
formulario de guardado no participa. Así que **las pantallas de Clientes nacen con esto
puesto**, no se añade después:

- el formulario usa el mixin **`DeclaraSuTrabajoSinGuardar`** y responde tres cosas: dónde
  está el `guardia`, si **`hayCambiosSinGuardar`** y **`queSePierde`** —una frase que
  completa «Tienes cambios sin guardar en …», como «los datos del cliente Sportium: sus
  contactos y razones sociales ya están guardados»—;

> ### ✅ La frase nombra LO QUE SE DESCARTA, no «el expediente» (27 de octubre de 2026)
>
> **Decisión del dueño al revisar C1 en pantalla.** Decía «el expediente del cliente
> Sportium», y el expediente tiene partes que **ya están guardadas**: los contactos, las
> razones sociales y el domicilio fiscal se escriben **al momento**, cada uno por su propia
> ruta. Agregar un contacto y pulsar «Cancelar» deja el contacto puesto —que es lo
> correcto— y la pantalla insinuaba lo contrario.
>
> **No se arregla metiendo las tres secciones en el «Guardar»**: eso exigiría una ruta que
> escriba todo junto en una transacción, y es rediseñar el contrato de C1 por un problema
> de letra. Se arregla diciendo la verdad en tres sitios:
>
> - cada sección que se escribe sola lleva **«Se guarda al momento»** en su descripción, y
>   **se comporta igual en consulta y en edición** —el aviso es de la sección, no del modo—;
> - la fila de acciones dice qué abarca **«Guardar»**: los datos del cliente y su domicilio
>   de referencia;
> - y la pregunta de salida nombra **los datos del cliente**, con los contactos y las
>   razones sociales declarados como ya guardados.
- **se compara contra lo cargado, nunca contra un «se tocó algo»**: escribir una letra y
  borrarla no es un cambio, y una pregunta que sale por nada enseña a contestar el diálogo
  sin leerlo;
- **si el formulario es una hoja modal**, lleva además **`SeCierraAlCambiarLaDireccion`**:
  una hoja no vive en el historial del router, así que sin eso se quedaría encima de la
  pantalla nueva;
- **si el formulario vive en una dirección** —`…/clientes/<id>/editar`—, esa ruta lleva su
  **`onExit`** en `router_web.dart`. Una ruta sin `onExit` no pregunta.

**Y el nombre nunca sale de la URL**: sale de la fila que la pantalla ya cargó, por la
misma razón que el rastro de D-39 — en la URL quedaría viejo en cuanto alguien renombrara
al cliente.
