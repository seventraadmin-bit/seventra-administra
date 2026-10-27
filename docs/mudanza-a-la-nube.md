# La mudanza de Administra a la nube

> Decisiones tomadas el **15 de octubre de 2026**. Este archivo es el plan, no una
> bitácora: lo que ya se hizo está en el historial de git y se nombra aquí sólo cuando el
> plan se apoya en ello.

## Dónde estamos: la plomería ya está hecha

Cinco commits, después de `c02f2cb`, movieron a la nube todo lo que **no** son datos de
negocio:

| Commit | Qué trajo |
|---|---|
| `8fb1c49` | el cimiento HTTP: cliente, configuración, errores |
| `f8f9c4d` | autenticación remota: sesión, renovación, almacén |
| `4c42482` | contexto de empresa: en qué Company estás, y recordarla |
| `d7b4132` | autorización por empresa: permisos reales del servidor |
| `7255de8` | **la sesión productiva corre sobre Identity SaaS** |

Entrar, saber quién eres, en qué empresa estás y qué puedes hacer **ya viene de la nube**.
Lo que sigue en el SQLite local son los **catorce módulos de negocio**.

## Las decisiones

| | |
|---|---|
| **Destino** | **WEB.** Cada módulo se muda **una sola vez** |
| **Repositorio** | **este mismo** (`riseg_control_activos`, `administra` en GitHub) |
| **Personal en el backend** | **se reabre** para M1 y M2 |
| **El sueldo con vigencias** | **vive en Personal.** Nómina sólo lo **leerá** |
| **Datos** | Personal **arranca vacío** en la nube. Importar lo real de RISEG es **etapa propia**, antes del piloto |
| **Para probar** | una Organization **«RISEG Piloto»** en el ensayo, con **datos inventados** |
| **🚫 Prohibido hasta producción** | **ningún dato real de empleados**: ni bancarios, ni expedientes |

Esa última no es una precaución de estilo. El expediente sensible y los datos bancarios son
las dos cosas del sistema que, filtradas, no se pueden deshacer.

## ¿Puede compilarse este mismo código para web?

**Sí, y lo que lo impide hoy es exactamente lo que la mudanza borra.** Medido, no supuesto.

### Lo que bloquea

**`dart:io` no compila para web**: basta importarlo para que la build falle. Está en
**43 archivos de `lib/`**, y su reparto es la mejor noticia de este documento:

| Dónde | Archivos | Qué pasa con la mudanza |
|---|---|---|
| `features/respaldo` | 14 | **desaparece.** En la nube respalda Cloud SQL, no la máquina |
| `features/organizacion` | 11 | exportar a PDF y Excel: en web se **descarga**, no se escribe en una ruta |
| `features/reportes` | 4 | lo mismo |
| `features/personal` | 3 | lo mismo, más adjuntos |
| `core/database` | 1 | **desaparece** con Drift |
| `core/config/app_paths` | 1 | **desaparece**: en web no hay rutas locales |
| `core/api/api_client` | 1 | **sólo** para atrapar `SocketException`. Cambio pequeño |
| `core/security` | 2 | abrir enlaces y cifrado por flujo de archivos |
| el resto | 6 | sueltos |

Y la base de datos: `NativeDatabase.createInBackground(File(...))` con
`sqlite3_flutter_libs`. **Eso es SQLite nativo y en web no existe.** Hay un camino
—`drift/wasm` con `sqlite3.wasm` y un worker— pero **no hace falta recorrerlo**: el destino
de cada módulo es la API, no un SQLite en el navegador. Drift se va, no se traduce.

### Lo que no bloquea

De las 22 dependencias, **las que son Dart puro viajan intactas**: `drift` como lenguaje de
consulta se va, pero `crypto`, `encrypt`, `pointycastle`, `convert`, `uuid`, `intl`,
`archive`, `excel`, `pdf`, `http`, `go_router`, `flutter_riverpod` y `path` **funcionan en
web sin cambios**. No hay `window_manager` ni ningún plugin de escritorio.

Tres cambian de forma, no de existencia:

| Paquete | En web |
|---|---|
| `file_picker` | funciona, pero devuelve **bytes** y no una ruta |
| `shared_preferences` | funciona, sobre el almacenamiento del navegador |
| `flutter_secure_storage` | **existe y es otro modelo de seguridad**: no hay llavero del sistema. Lo que hoy guarda hay que revisarlo uno por uno |

### El mecanismo que ya existe para dirigir esto

El repositorio tiene **pruebas de arquitectura que leen `lib/` buscando cadenas
prohibidas** —así se vigila que `/api/v1` tenga un solo dueño, y que ninguna feature
consuma todavía el cliente HTTP—.

**La mudanza se dirige con ese mismo mecanismo, en los dos sentidos:** una prueba que
prohíbe `dart:io` en las capas ya migradas, apretada módulo a módulo; y la prueba
«NINGUNA feature consume todavía el cliente HTTP», que se afloja **nombrando** la que sí,
una por etapa. El día que la lista de excepciones esté vacía por el otro lado, la mudanza
terminó.

## Qué módulo va primero: **Personal**

No por tamaño —`organizacion` tiene 315 archivos y 41.642 líneas, el triple— sino por
cuatro razones:

1. **Es el único módulo de negocio con backend CERRADO y completo.** La API ya tiene
   empleados, periodos, asignaciones, documentos, foto, datos bancarios, evaluaciones,
   perfil profesional, recontratación, expediente sensible y ficha técnica. Para `nomina`,
   `finanzas`, `compras`, `inventario`, `vehiculos` y `telefonia` **no existe un solo
   endpoint**: están en el catálogo de módulos y no en el backend.
2. **Ejercita todo lo difícil una vez:** aislamiento por Company, el **402** de
   `restricted`, permisos por módulo, archivos de verdad —foto y documentos—, auditoría, y
   la regla de que «activo» **se deriva** de un periodo abierto. Lo aprendido sirve para los
   trece restantes.
3. **Es el medidor que cobra.** `active_employees` decide si un cliente se pasó de su plan.
   Mientras Personal viva en el SQLite de cada máquina, ese medidor cuenta **cero**: la
   facturación de SEVENTRA no es real hasta que Personal esté arriba.
4. **Su dependencia está lista:** áreas, puestos y sucursales ya tienen endpoints.

## El hueco que hay que cerrar antes

Comparado tabla contra tabla, el producto local guarda en una asignación cosas que el SaaS
**no tiene**:

| Lo que guarda `AsignacionServicio` | ¿Está en `app.employee_assignment`? |
|---|---|
| empleado, fecha de inicio y término, motivo | **sí** |
| puesto y **sucursal** (destino administrativo) | **sí** |
| **servicio** (destino operativo) | **NO** |
| línea comercial y turno | **NO** |
| **sueldo y bono mensual, con vigencias** | **NO** |

La `0012` lo dejó escrito al crear la tabla:

> «SIN `service_id`, y sin ningún sustituto. Servicios no existe en el backend, así que no
> se falsea.»

Era verdad entonces. **Hoy Servicios existe** (5D.10D cerrada). Y la regla que no se
reinterpreta es justamente ésta: **Sucursal es el destino administrativo, Servicio el
operativo, y Personal no usa una como sustituto de la otra.**

## Las cinco etapas

Las dos primeras son backend; las tres siguientes, pantalla.

| | Etapa | Qué incluye |
|---|---|---|
| **M1** | **La asignación operativa** | `service_id` + línea comercial + turno en la asignación, con su migración. **Reabre Personal** |
| **M2** | **Sueldo con vigencias** | dinero en enteros menores, vigencias **sin solape** —la forma que ya tiene `CommercialLineTerm`—. **Vive en Personal; Nómina lo lee** |
| **M3** | **Estructura contra la API** | áreas, puestos y sucursales. El más pequeño de los tres y la dependencia de todo: el que prueba la plomería con datos reales |
| **M4** | **Personal: lista y expediente** | leer de la nube. **Sin escribir todavía** |
| **M5** | **Personal: escrituras y archivos** | alta, asignaciones, periodos, foto y documentos. Aquí aparecen el 402 y la auditoría |

### ⚠️ Corrección: «detrás de la misma interfaz de dominio» NO se cumple

Esto decía que de M3 en adelante el trabajo sería siempre el mismo —**cambiar el
repositorio de Drift por uno de HTTP detrás de la misma interfaz de dominio, sin tocar
las pantallas**— y al programar M3 se comprobó que **no se puede**.

El motivo es concreto y no se arregla con disciplina: `AreaRepository` no habla de un
modelo propio, habla de **`AreaData`**, una clase que **genera Drift** y cuyo archivo
importa `dart:io`. Implementar esa interfaz desde la web **rompe la build**. Y lo mismo
vale para las demás: la interfaz de dominio quedó atada al tipo de la base.

Así que la forma real de cada etapa es **tres piezas, no una**:

1. un **modelo plano** del módulo (`features/<m>/web/modelos/`), sin Drift;
2. un **repositorio HTTP** que lo devuelve, **sin implementar la interfaz vieja**;
3. una **pantalla web** que consume ese repositorio.

> ⏳(D-31) **Deuda, y con fecha de fin:** mientras la mudanza dure habrá **dos modelos por
> módulo**. El de Drift queda **congelado** —no se mantiene en paralelo— y **se retira
> con el módulo**, cuando su última pantalla deje de leer de la base local. Lo que no
> puede pasar es que los dos evolucionen: ahí nacen las divergencias que nadie ve hasta
> que dos pantallas muestran números distintos.

El cimiento de `8fb1c49`–`d7b4132` sigue sirviendo para lo que sí resolvió: sesión,
empresa, permisos y transporte.

## Lo que queda fuera, y hay que decidir cuando toque

- **`respaldo`** (36 archivos): en la nube **no tiene sentido**. Cloud SQL respalda. Lo que
  sí hay que decidir es si se conserva un **exportar mis datos** para el cliente.
- **`boveda`**: hoy guarda secretos con cifrado local. En web el modelo de seguridad es
  otro, y en el SaaS la bóveda **quedó fuera de la v1** —`ClientPortal` sin secreto
  cifrado—. **No se muda: se rediseña aparte.**
- **`servicios_eventuales`**: su backend es **5D.10G**, que está **pendiente**.
- **`dashboard`, `busqueda`, `reportes`, `notificaciones`**: atraviesan todos los módulos.
  Se mudan **al final**, porque antes no tendrían de dónde leer.

> ⚠️ **«Reportes» aparece aquí sólo por CUÁNDO se mudan, no porque puedan recortarse.**
> Los reportes, los recibos de nómina y los PDF son **requisito** de la mudanza, con el
> mismo contenido y el mismo diseño que en el escritorio. Ver «Decisión 2» más abajo.
> Esta lista ordena, no descarta — los dos únicos que de verdad quedan fuera de
> Administra al 100 % son **`respaldo`** y **`boveda`**.

## Lo que la pantalla de Administra tendrá que traer, y no estaba previsto

Apuntado el **16 de octubre de 2026**, mientras se diseñaba M1.

### «Agregar turnos recomendados», un botón en la pantalla de catálogo

El catálogo de modalidades de turno es **de cada empresa** y en la nube nace **vacío** —así
lo hizo la 5D.10D, con su CRUD en `/shift-modalities`—. Nadie lo siembra por detrás, y eso
es deliberado: sembrar al crear la empresa obligaría a Tenancy a conocer un catálogo
comercial.

Pero una empresa nueva **no debe empezar escribiendo once filas a mano.** Así que la
pantalla de turnos de **Administra** —la del cliente, no Console— cuando el catálogo esté
**vacío** ofrece **«Agregar turnos recomendados»**: crea los once de un clic, y después cada
empresa **edita o desactiva** los que no use.

Las once son las ocho que RISEG ONE usa hoy —Diurno, Nocturno, Mixto, 12×12, 12×24, 24×24,
24×48, Personalizado— más **8 horas**, **12×36** y **2×2×2**. La lista, con sus códigos y
descripciones, está en el diseño de M1:
`seventra-backend/docs/m1-asignacion-operativa.md`.

**Y lo que el botón crea es de la empresa desde el primer minuto.** Una fila sembrada por el
sistema invita a preguntarse si se puede borrar; una que alguien creó con un clic, no.

**Es de M4/M5**, o de la etapa de catálogos de Administra. No de M1, que es motor y
migración.

## El portón web: login, empresa y Áreas

Escrito el **17 de octubre de 2026**, al cerrar la primera pantalla de M3.

La web de Administra ya tiene entrada propia. Son seis archivos y un punto de entrada:

| Archivo | Qué hace |
|---|---|
| `lib/main_web.dart` | la composición completa, **sin Riverpod** |
| `features/usuarios/web/marca_seventra.dart` | la identidad de SEVENTRA: verde `#1E7F45`, tinta, fondo, logotipo |
| `features/usuarios/web/login_web_screen.dart` | correo y contraseña |
| `features/usuarios/web/selector_de_empresa_screen.dart` | elegir empresa cuando hay varias |
| `features/usuarios/web/porton_web.dart` | **el único que decide qué pantalla se ve** |
| `features/usuarios/web/mensajes_humanos.dart` | `Failure` → una frase que se puede usar |

### Las decisiones que no se reinterpretan

**La puerta dice SEVENTRA, no RISEG ONE.** Quien abre esa dirección entra a la
plataforma, y dentro puede tener Administra, Opera o Cumple. Por eso el login **no usa
el Design System**: sus componentes llevan la identidad del producto local, que es justo
lo que esta pantalla no debe parecer. Las pantallas de dentro sí lo usan.

**Con una sola empresa se entra directo, y eso NO se comprueba en la pantalla.**
`GestorDeCompany` ya lo resuelve antes de publicar un estado: con una, la abre; con
varias, pide elegir si no hay una recordada válida. El selector sólo existe para el
estado «hay que elegir». Comprobarlo también en la pantalla serían dos sitios decidiendo
lo mismo.

**Ni el login ni el selector navegan.** Publican su resultado en su gestor; el portón
observa y decide. Si una pantalla empujara una ruta habría dos autoridades sobre lo que
se ve, y es así como se acaba viendo el selector después de haber entrado.

**No hay `go_router` todavía.** Lo que se ve depende de dos estados del servidor, no de
una URL, y publicar rutas antes de tener pantallas dentro prometería direcciones que la
sesión quizá no permite. Entra con la segunda pantalla.

**El `companyId` que recibe Áreas sale del contexto que el servidor confirmó**, nunca de
la lista, de la preferencia guardada ni de la URL.

### Dos puntos de entrada, un solo motor de identidad

`lib/main.dart` compila para Windows y `lib/main_web.dart` para el navegador, y **no
pueden compartir pantalla de login**: la del escritorio pasa por
`sesionControllerProvider`, que arrastra Drift y por tanto `dart:ffi`.

El candado de arquitectura que exigía **una sola** pantalla de login se ajustó a **una
por punto de entrada** y, en el mismo movimiento, se le añadió lo que de verdad
protegía: que las dos autentiquen contra el **mismo** `GestorDeSesion`, y que ninguna
mencione `PasswordHasher` ni el `Usuario` local. Dos puertas son aceptables; dos formas
de decidir quién eres, no.

### ⚠️ Un verde falso encontrado y corregido

`test/arquitectura/web_limpia_test.dart` declaraba la carpeta web de organización como
`lib/features/organizacion/presentation/web/`. **La carpeta real es
`lib/features/organizacion/web/presentation/`.** La prueba pasaba **sin mirar la pantalla
de Áreas**: una ruta que no coincide con ningún archivo no deja rastro.

Corregida, y **con una prueba nueva** que exige que cada entrada de la lista coincida con
al menos un archivo. Es el riesgo propio de un guardia declarado con cadenas de texto: no
falla, se calla.

### Lo que falta para verlo funcionando contra el ensayo

Dos cosas, y ninguna es código del cliente:

1. **El origen del navegador tiene que estar autorizado en la API.** Un
   `Web__AllowedOrigins` que no incluya el origen de Administra web hace que el navegador
   no deje salir ni la primera petición — y **un CORS rechazado se lee en pantalla como
   «No se pudo contactar con el servidor»**. Ya costó media hora de diagnóstico una vez,
   con la API perfectamente sana. Por eso el puerto de desarrollo es **fijo**, igual que
   el `5300` de Console.
2. **El ensayo tiene cero empresas.** Así lo dejó escrito el diseño de M1 —«cero
   empresas, cero asignaciones»— y lo repite el de M2. Con la cuenta creada pero sin
   `CompanyAccess`, el portón llega hasta **«Todavía no tienes ninguna empresa»** y para
   ahí. **Eso es el comportamiento correcto**, no un fallo: hace falta sembrar
   Organization, Company y acceso antes de poder ver Áreas.

### ⏳(D-28, D-29, D-30) Tres pendientes, con su límite

| Pendiente | Límite | Por qué ése |
|---|---|---|
| **Identidad unificada** (misma tipografía, paleta y logo en correos, Console, Administra y luego Opera) | **antes del piloto y antes de vender** | hoy el verde `#1E7F45` es lo único común; la tipografía ya difiere —los correos usan `Archivo`, el Design System `Segoe UI`—. Un cliente que ve tres estéticas no ve una plataforma |
| **Registro y «olvidé mi contraseña» en la web** | sin fecha, decisión comercial | el backend ya tiene las dos, con correo real y token de un solo uso; `AuthApi.solicitarRestablecimiento` existe. Lo que no está decidido es **quién puede crear cuentas** en algo que se vende por suscripción |
| **Cookie `HttpOnly` para el token de refresco** | **antes del piloto, no antes de producción** | el piloto ya trae datos reales de RISEG: nombres, sueldos e INE. Un token robado del almacenamiento del navegador abre una sesión con todo eso detrás, y los permisos protegidos no defienden de una sesión legítima robada. Está escrito en `almacen_sesion_remota_web.dart` |

**Lo que la pestaña del navegador trae hoy**, y entra en el pendiente de identidad:
`web/index.html` y `web/manifest.json` ya dicen **SEVENTRA** —antes decían `riseg_one` y
pintaban el azul por omisión de Flutter durante toda la carga—, con el fondo
`#F7F6F2` y el verde `#1E7F45` como color de tema. Lo que sigue siendo **de plantilla**
son `web/favicon.png` y los cuatro `web/icons/*.png`: son el logotipo de Flutter. No se
pueden escribir desde el código, hacen falta los archivos de imagen de la marca.

Por el mismo motivo, el logotipo del login es **texto compuesto y no una imagen**
(`LogotipoSeventra`): un texto bien espaciado se ve intencional, y un ícono genérico de
relleno se ve provisional en la primera pantalla que alguien ve. Cuando exista el
logotipo real **se cambia en ese widget y en ningún otro sitio**.

## El inventario de pantallas, y dos decisiones que lo reordenan

Levantado el **17 de octubre de 2026**, al volver a abrir el escritorio para comparar
con la web. **74 archivos `*_screen.dart`.**

### Decisión 1 — los módulos se agrupan: **Activos** y **Compras e inventario**

Vehículos y Telefonía dejan de ser dos módulos y pasan a ser **uno: «Activos»**.
Compras e Inventario, lo mismo. No es una reorganización de carpetas: es cómo se va a
**vender y a mudar**, y por tanto cómo se diseña el backend.

| Antes | Ahora | Pantallas |
|---|---|---|
| `vehiculos` (4) + `telefonia` (5) | **Activos** | **9** |
| `compras` (4) + `inventario` (4) | **Compras e inventario** | **8** |

**Lo que esto cambia de verdad** es que el backend de cada grupo se diseña **una vez**:
un vehículo y una línea telefónica son el mismo problema —algo que se asigna a alguien,
tiene documentos, vence y se devuelve—, y resolverlo dos veces habría producido dos
modelos de asignación que divergen. Lo mismo con una compra y una entrada de almacén.

### Decisión 2 — **recibos, reportes y PDF son REQUISITO, no un rediseño opcional**

Una versión anterior de este documento decía que lo que depende de `dart:io` —generar
PDF, imprimir, exportar— «se rediseña, no se muda». **Eso se leía como que podía
quedarse por el camino, y no puede.**

> 📌 **REQUISITO DE LA MUDANZA, al mismo nivel que los datos:** los **recibos de
> nómina**, los **reportes** y los **PDF** de la web tienen que salir **igual de
> completos y con el mismo diseño** que los del escritorio. Una web que imprima un
> recibo más pobre que el que ya se entrega no es una mudanza terminada, es una
> regresión que el cliente nota el primer día de pago.

**Qué cambia técnicamente, y por qué no es sólo copiar el código.** En el escritorio el
PDF se compone en el cliente con `dart:io` y se escribe en una carpeta. En el navegador
no hay carpeta, así que hay **dos caminos** y hay que elegir uno por su sitio:

| Camino | Dónde se compone | A favor | En contra |
|---|---|---|---|
| **En el navegador** | el mismo código de `pdf`/`printing`, que **sí tiene soporte web** | se reaprovecha la plantilla tal cual | el documento depende de la máquina del cliente |
| **En el servidor** | el backend lo genera y lo entrega | un recibo idéntico para todos, archivable y auditable | hay que **reescribir** la plantilla fuera de Dart |

**No está decidido**, y la decisión es de la etapa que mude Nómina. Lo que sí queda
fijado aquí es el listón: **mismo contenido y mismo diseño**, se componga donde se
componga. Las plantillas actuales son la especificación.

### El inventario

| Módulo | Pant. | Se reutiliza | Hay que rehacer | ¿Backend nuevo? |
|---|---:|---|---|---|
| **organizacion** | 15 | diseño y textos al 100 % | repositorios y modelos | **no** — 5D.10C/D y estructura ya existen |
| **finanzas** | 13 | diseño y reglas | todo el backend | **SÍ — 5D.11, no existe** |
| **Activos** (vehículos + telefonía) | 9 | diseño y validaciones | repositorios y el modelo de asignación | **SÍ** |
| **Compras e inventario** | 8 | diseño y la validación de líneas | repositorios | **SÍ** |
| **personal** | 6 | diseño, validaciones, expediente | repositorios y el modelo de asignación | **no** — M1 y M2 ya lo cubren |
| **usuarios** | 6 | las pantallas de permisos | usuarios y bóveda | **no** — lo resuelve Identity |
| **reportes** | 6 | diseño de gráficas y KPIs | las consultas | **no**, pero depende de todos |
| **nomina** | 2 | diseño y reglas de cálculo | repositorios | **no** — lee el sueldo de M2 |
| **tiempos_extra** | 2 | casi todo | repositorios | **SÍ** |
| **descuentos_personal** | 2 | casi todo | repositorios | **SÍ** |
| **servicios_eventuales** | 2 | diseño | todo | **SÍ — 5D.10G, pendiente** |
| **dashboard** | 1 | diseño | las consultas | **no**, pero depende de todos |
| **respaldo** | 1 | nada | **no se muda** | no |
| **boveda** | 1 | nada | **se rediseña aparte** | sí, fuera de la v1 |

**Lo que se conserva entero, y es mucho:** los **28 componentes del Design System**
—sólo queda fuera `riseg_entity_identity`, que lee del disco—, las validaciones de
dominio puro (RFC, código postal fiscal, dirección, UUID), las **imágenes**, y **los
textos**, que se copian literalmente. De **443 casos de uso**, **162 no tocan Drift** y
se mueven sin cambios.

## El orden de mudanza, hasta Administra al 100 %

El criterio no es el tamaño: es **qué desbloquea a qué**, y dejar para el final lo que
necesita que todo lo demás exista.

| # | Etapa | Módulos | ¿Backend nuevo? |
|---|---|---|---|
| **M3** | Estructura *(cerrado)* | áreas, puestos, sucursales, tipos | no |
| **M4** | **Clientes y servicios** | clientes, servicios, líneas comerciales y sus términos, contratos | no |
| **M4-B** | **Campana de avisos** | la campana **derivada**, con su primer grupo: contratos por vencer | no |
| **M5** | Personal: leer | empleados, expediente | no |
| **M6** | Personal: escribir | altas, asignaciones, periodos, documentos, **tiempos extra** | **sí**, los tiempos extra |
| **M7** | Nómina y su periferia | nómina, descuentos | **sí**, los descuentos |
| **M8** | Activos | vehículos y telefonía, juntos | **sí** |
| **M9** | Compras e inventario | los dos, juntos | **sí** |
| **M10** | Finanzas y cobranza | **agenda de documentos por emitir**, CxC, pagos, complementos, ingresos, egresos, cuentas | **sí — 5D.11, la etapa más grande** |
| **M11** | Eventuales | servicios eventuales | **sí — 5D.10G** |
| **M12** | Transversales | **dashboard**, reportes, búsqueda | no |

### Decisión — **la Agenda es de cobranza y va en M10** (27 de octubre de 2026)

**La contradicción que esto cierra.** Este documento ponía «agenda» entre los módulos de
**M4 · Clientes y servicios**, y el diseño de las seis subetapas de Clientes y servicios
—C1 a C6, en
[diseño de pantallas de Clientes](diseno-pantallas-clientes.md)— **no la tiene**. Un
módulo citado en dos sitios con alcances distintos acaba construyéndose dos veces o
ninguna, así que se decide una vez y se escribe donde toca.

**Qué es la Agenda, y por eso cae de este lado.** No es una lista de citas: es
**«Documentos por emitir»**, con folio **DOC**, y su contenido es la obligación
administrativa de preparar un CFDI o un recibo para un periodo — prorrateo, IVA, importe
esperado, importe emitido y diferencia
([inventario 03 · Cobranza, §2](../../seventra-backend/docs/inventario-riseg-one/03-cobranza.md)).
Eso es **5D.11** entero: `Terms → BillingConfiguration → BillingPreparation → documento
emitido → AccountReceivable → Payment`, y de ahí sus compromisos
[CP-02 a CP-06](../../seventra-backend/docs/compromisos.md).

**Lo que NO significa.** La Agenda del escritorio **se ve** con `comercial.ver` y su
plantilla de permisos de Comercial incluye `agendaComercial.*` (inventario 03 §7). Que el
escritorio la colgara del menú de Comercial no la convierte en parte de **Clientes y
servicios**: lo que decide la etapa es de qué depende para existir, y ésta depende de la
configuración de cobro y del documento emitido, que no existen hasta 5D.11. Es la misma
frontera que el diseño congelado ya mantiene: **`BillingPreparation` no es CxC**, y
preparar no es emitir.

**Consecuencia en la web, y es la que se ve.** La pestaña «Agenda — Próximamente» **no va
en Comercial**: va en **Finanzas**, donde vivirá. Comercial enseña **Clientes**,
**Servicios** y **Eventuales**. El detalle de las tres pestañas está más abajo, en los
ajustes del 27 de octubre.

### M4-B · La campana, y por qué va ahí y no en M12

**Entra el 25 de octubre de 2026**, con el requisito nuevo de avisar cuando un contrato de
cliente está por vencerse ([CP-18](../../seventra-backend/docs/compromisos.md)). Las
notificaciones estaban dentro de **M12 · Transversales**, al final, y ahí **el aviso de
contratos se habría quedado sin dónde aparecer durante ocho etapas**.

**Por qué se puede adelantar sin partirlo:** la campana del escritorio es **aditiva por
diseño** (inventario 01 §12). No es una pantalla que lo sepa todo: son **grupos
independientes**, cada uno con **su permiso**, su regla y su destino. Así que M4-B entrega
**la cáscara y un grupo** —contratos por vencer, con `clients_services.read`— y **cada
módulo posterior añade el suyo en su propia etapa**: vehículos los suyos en M8, Finanzas los
de cobranza en M10. Construirla al final obligaría a tener los ocho grupos listos a la vez
para estrenarla.

**Y el Dashboard NO se adelanta**, a propósito: «requiere atención» es un **resumen de
todo**, así que un Dashboard construido en M4-B tendría una sola tarjeta y habría que
rehacerlo con cada módulo. Se queda en **M12**, que sigue siendo antes de producción.

**Por qué `M4-B` y no renumerar.** Insertar una etapa entre M4 y M5 movería ocho números en
un documento que se cita por número en commits, deudas y compromisos — y un número que
cambia de significado es peor que un número con letra. Es el mismo criterio con el que E1-B
entró entre E1 y E2.

**Por qué este orden.**

> ### ⚠️ REORDENADO EL 22 DE OCTUBRE DE 2026 — **Clientes y servicios ANTES que Personal**
>
> Este orden ponía Personal en M4 y M5, con el argumento de que su backend ya estaba hecho
> y era «la mayor cantidad de producto por la menor cantidad de backend nuevo». **El
> argumento era cierto y la conclusión estaba mal.**
>
> **La línea comercial de un servicio define las plazas, el turno, el precio y el sueldo de
> referencia, y la asignación precarga el sueldo desde ahí.** En la nube es literal:
> `commercial_line_term` —la 0019— lleva `position_id`, `shift_modality_id`,
> **`headcount`**, `unit_price_minor` y `recruiting_salary_reference_minor`, versionado por
> fechas y sin solape. La asignación de la 0046 apunta a `service_id` y
> `service_commercial_line_id` precisamente para eso.
>
> **Mudar Personal primero obligaría a construir la asignación dos veces:** una sin línea
> comercial —sueldo a mano, ninguna plaza contra la que validar, ningún «Asignados X de Y»—
> y otra al llegar Comercial. El escritorio ya recorrió ese camino y lo dejó escrito: la
> referencia salarial del Servicio quedó «retirada de la captura nueva, columnas conservadas
> sólo por compatibilidad con datos históricos».
>
> **Y con el cupo BLOQUEADO ya no es comodidad, es imposibilidad:** sin el término vigente
> de la línea no hay plazas contra las que bloquear.
>
> **Los tiempos extra se adelantan a M6**, fuera de Nómina: las suplencias van por ahí, y
> con una línea completa son la **única** salida legítima. Dejarlos en M7 habría dejado
> meses un bloqueo sin alternativa.
>
> **Lo que NO cambia:** el expediente, los documentos, los datos bancarios, las
> evaluaciones, la ficha técnica y contratar con destino **sucursal** no dependen de
> Comercial. La frontera es el destino de la asignación, no el módulo.

**M4 va inmediatamente después de M3** porque define lo que hace que una asignación
signifique algo —plazas, turno y sueldo de referencia—, y porque 5D.10C/D ya existen en la
nube: es producto nuevo sin backend nuevo.

**M5 y M6 son Personal**, que es el corazón del producto y cuyo backend **ya está hecho**
—M1 le dio la asignación operativa y M2 el sueldo con vigencias—. Lo único nuevo son los
tiempos extra, que entran aquí por lo dicho arriba.

**M7 es Nómina y sus descuentos.** Conviene estrenar en los tiempos extra de M6 el camino
«diseñar backend nuevo → mudarlo» antes de hacerlo con Finanzas. **Y aquí se decide dónde se
componen los recibos**, que es el requisito de arriba.

**M8 y M9 son los dos agrupamientos** de la decisión 1, cada uno con su backend
diseñado una sola vez.

**M10 es Finanzas y va casi al final** no por importancia sino porque **5D.11 no
existe** —`Terms → BillingConfiguration → BillingPreparation → documento emitido →
AccountReceivable → Payment`— y es la etapa más grande que queda del backend.

**M12 cierra**, porque dashboard, reportes y búsqueda **leen de todos los demás**:
mudarlos antes dejaría pantallas que consultan módulos que todavía viven en SQLite.

> **DECISIÓN REGISTRADA, no pendiente: la bóveda y el respaldo no están en esta lista a propósito.** El respaldo
> desaparece —respalda Cloud SQL— y queda decidir si se ofrece «exportar mis datos». La
> bóveda se rediseña fuera de la v1. Administra al 100 % **no los incluye**.

## 🔒 LO QUE NO SE PUEDE PERDER DE «CLIENTES Y SERVICIOS» + PERSONAL

**Decidido el 22 de octubre de 2026**, al reordenar la mudanza. Son requisitos del dueño y
entran enteros al inventario de M4 y M6. No es una lista de ideas: es lo que hoy funciona en
el escritorio y tiene que seguir funcionando.

### 1 · El alta de personal, con la línea comercial dentro

- Al elegir **servicio**, la **sucursal se excluye** —uno y sólo uno, que es lo que la 0046
  ya impone en la base con `CHECK ((branch_id IS NULL) <> (service_id IS NULL))`—.
- Aparece la **línea comercial** del servicio, y **precarga el turno y el sueldo** desde su
  término vigente: `shift_modality_id` y `recruiting_salary_reference_minor`. La captura
  individual sigue ganando como excepción, igual que en el escritorio.
- Se muestra **«Asignados X de Y»** por línea, con Y = `headcount` del término vigente.

### 2 · El Dashboard de cobertura, con sus indicadores

- **Por servicio activo: X/Y**, en **verde si está completo** y en **rojo si falta**. El
  clic **abre el personal asignado** de ese servicio.
- Los indicadores: **activos**, **asignados**, **sin asignar**, **promedio de cobertura**,
  **rotación** y **plantilla administrativa**.

> ⚠️ **Dos semánticas que no se pueden mezclar, y el escritorio ya lo señala en pantalla:**
> activos, asignados, sin asignar e inconsistentes son **fotografía de hoy**; la **rotación**
> y el promedio de días de cobertura son **de periodo**. «La UI lo señala para que nadie lea
> una como la otra», y eso se muda tal cual.
>
> **Y dos porcentajes que tampoco:** el de **posiciones** —5/14 = 36 %— y el de **servicios
> completos** —3 de 9—. El escritorio los lleva separados porque «el % agregado de
> POSICIONES puede verse peor de lo que realmente está la operación». Son dos preguntas y
> nunca se reemplazan.
>
> **El denominador de «asignados» es su PROPIA plantilla**, nunca el total de la empresa:
> «ese era exactamente el error del 94 %».

**La rotación, con su fórmula medida:** `bajas / plantillaPromedio × 100`, donde
`plantillaPromedio = (activos al inicio + activos al cierre) / 2`. **Nula —no cero— cuando
la plantilla promedio es 0**, porque «con plantilla vacía la rotación no está definida, y
devolver 0 fingiría cero rotación». Se reconstruye sobre **ciclos laborales reales**: pedir
agosto reconstruye agosto, aunque hoy no quede nadie de entonces. Y los **reingresos** se
cuentan como alta del periodo pero se exponen aparte.

> ### ✅ Y AQUÍ LA NUBE GANA ALGO QUE EL ESCRITORIO NO PUEDE DAR
>
> El escritorio calcula **sólo rotación operativa**, y lo dice con su razón: la pertenencia
> administrativa a una fecha pasada no se puede reconstruir porque `Empleado.sucursalId` es
> «un puntero plano sin vigencia», así que calcularla «sería atribuir el presente al pasado».
>
> **En la nube esa limitación no existe.** Desde la 0046 **toda** asignación tiene destino
> —sucursal o servicio— y la fila lleva `started_on` / `ended_on`. Así que «¿pertenecía a la
> sucursal X el día Y?» **tiene respuesta exacta**, y la rotación **administrativa** se puede
> calcular igual que la operativa. Es ganancia de la mudanza, no una pérdida: entra al
> inventario como requisito nuevo y no como copia.

### 3 · 🚫 EL CUPO SE BLOQUEA — decisión del dueño, y cambia lo que hay que construir

**Si la línea comercial tiene todas sus plazas cubiertas, no se puede asignar a nadie más, y
lo impone el SERVIDOR, no sólo la pantalla.** En la pantalla, las líneas llenas aparecen como
**«completa»** y **no se pueden elegir**.

> ⚠️ **ES UNA REGLA NUEVA, NO UNA QUE SE MUDE, y conviene que conste.** Medido el 22 de
> octubre de 2026: **ni el escritorio ni la nube validan hoy el cupo**. `headcount` no
> aparece ni una vez en `Seventra.Data/Personnel/`, y `AsignarEmpleadoServicioUseCase` tiene
> doce resultados nombrados y ninguno es «cupo excedido». El escritorio **lo permite a
> propósito** y lo refleja como excedente: «personal extra puede existir, pero no aumenta
> artificialmente la cobertura sobre 100 %».
>
> Así que esto **no es rescatar una función perdida**: es endurecer una regla, con lo que
> eso implica para los casos de abajo.

**Y las plazas están en el TÉRMINO, no en la línea.** `headcount` vive en
`commercial_line_term`, versionado por fechas; la asignación apunta a la **línea**
(`service_commercial_line_id`). Así que bloquear exige **resolver el término vigente a la
fecha de la asignación** y contar las asignaciones vigentes de esa línea. No es un `if`: es
una lectura con fecha dentro de la transacción que escribe.

**Tres casos que el bloqueo NO puede romper:**

| Caso | Qué tiene que pasar |
|---|---|
| **Reemplazo** — se retira a un guardia y se asigna a otro | **En la misma operación no debe chocar con el bloqueo.** Cerrar y abrir son un solo acto: si se evalúan por separado, el alta del sustituto ve la plaza todavía ocupada y la niega |
| **Suplencia** — alguien cubre un turno sin tener plaza | Va por **Tiempos extra**, que por eso se adelanta a M6: con el cupo bloqueado es la **única** salida legítima cuando una línea está completa |
| **Bajan las plazas** por debajo de los asignados | **Se avisa y NO se saca a nadie.** El sistema no elige a quién desasignar: eso lo decide una persona. Queda un excedente visible y señalado |

> **Falta decidir el turno.** El término declara `shift_modality_id` y la asignación lleva el
> suyo, y **nada comprueba hoy que coincidan**. ¿El cupo se cuenta por línea, o por línea **y
> turno**? Con dos turnos en la misma línea la respuesta cambia el conteo. **Entra como
> pregunta del inventario de M4/M6**, no se resuelve aquí.

### 4 · Tiempos extra — **las reglas del escritorio, copiadas sin reinterpretar**

Leídas de `registrar_tiempo_extra_usecase.dart`, `corregir_tiempo_extra_usecase.dart`,
`tiempo_extra_validator.dart` y `tiempo_extra_table.dart`. **Se mudan tal cual.**

**🚫 EL BLOQUEO DE CUPO NO APLICA AQUÍ.** Una cobertura **no crea ni mueve ninguna
asignación**: el bloqueo es de asignaciones y sólo de asignaciones. Y lo dice la propia
tabla del escritorio: «Registrar este TiempoExtra **NO cierra la vacante** ni la marca como
cubierta: fue una cobertura temporal de un turno, no una contratación».

**Son TRES orígenes, no dos** —y conviene decirlo, porque el tercero existe y funciona:

| Origen | Exige | **Prohíbe** |
|---|---|---|
| `ausenciaEmpleado` | el empleado ausente **y** el motivo | vacante, descripción |
| `vacante` | la vacante operativa | empleado ausente, motivo, descripción |
| **`otro`** | una descripción breve, máx. **200** caracteres | empleado ausente, motivo, vacante |

> **`otro` es deliberadamente texto y no catálogo:** «el abanico real —apoyo extraordinario,
> reforzamiento, capacitación, traslado…— no se cierra bien, y un catálogo obligaría a
> mantenerlo». Y **no reutiliza `motivoAusencia`**: ese enum dice por qué faltó una
> **persona**, que aquí no aplica.
>
> **Cada origen tiene una forma EXACTA:** no basta que estén los campos que necesita, además
> **deben faltar los que no le corresponden**. Si no se exigiera lo segundo, una cobertura
> corregida de `vacante` a `ausenciaEmpleado` se quedaría «con la FK de la vacante colgando,
> y el registro diría dos cosas a la vez».

**Quién cubre:** exactamente uno de **empleado** o **nombre de un externo**, nunca los dos y
nunca ninguno —`faltaCobertura` / `coberturaAmbigua`—. El empleado que cubre **puede ser
cualquiera, sin importar su asignación**: no se comprueba ni su servicio ni su línea. Lo
único prohibido es que **el ausente y quien cubre sean el mismo**, «el turno quedaría
descubierto igual», y sólo aplica a `ausenciaEmpleado`.

**La vacante, cuando el origen es `vacante`:** tiene que ser **de ESE servicio** —«cubrir una
plaza de otro Servicio no es una cobertura de éste»— y **seguir abierta**. Y una regla que
no se puede perder: eso **sólo bloquea el registro o la corrección nuevos**; «un TiempoExtra
histórico sigue resolviendo su vacante aunque después se cubra», y por eso la FK es
`restrict`.

**El alta valida lo que llega TAL CUAL; la corrección NORMALIZA antes de validar.** No es una
inconsistencia, es la regla: en un alta «no existe un origen anterior del que arrastrar
residuos, así que mandar una vacante y además un empleado ausente es una contradicción del
llamador», mientras que al corregir «limpiar el residuo del origen previo es justo el
requisito».

**Corregir sólo vale sobre una cobertura `registrado`**: una ya **cancelada** no se corrige
—se cancela y se vuelve a registrar—. Y la corrección **reutiliza exactamente** las mismas
validaciones del alta; a diferencia de Compra, aquí **el origen financiero sí puede cambiar
de tipo** durante una corrección.

**Lo demás de la fila**, para que el inventario no lo descubra tarde: `turnoId` es **FK
obligatoria** al catálogo de modalidades; el monto y cada costo adicional deben ser **> 0**;
el pago base y **cada costo adicional llevan su propio origen financiero** —cuenta o
tarjeta— validado por separado, y la tarjeta se comprueba activa, con límite capturado y con
crédito disponible, citando el monto exacto; y un **saldo insuficiente no es un error
inesperado**: se propaga para que la pantalla diga disponible, requerido y faltante.

⚠️ **Y lo que arrastra a Finanzas:** registrar una cobertura escribe el **Egreso automático**
en la misma transacción, con el beneficiario resuelto —el nombre del empleado que cubre, o el
del externo—. En la nube, Finanzas es **5D.11 y no existe**. Así que **la pregunta del
inventario de M6 es qué hace la nube con el egreso**: si se aplaza, si se registra sin él, o
si Tiempos extra espera a Finanzas. No se decide aquí.

### 5 · El menú de Personal — **se conserva el agrupamiento del escritorio**

**Personal es UN apartado con CUATRO pestañas**, y la primera tiene dos sub-pestañas:

| Pestaña | Sub-pestañas | En el escritorio aparece si… |
|---|---|---|
| **Empleados** | **Plantilla activa** · **Bajas** | siempre *(el router ya exige `personal.ver` para todo `/personal/**`)* |
| **Nómina** | — | `nomina.ver` |
| **Descuentos** | — | `descuentos.ver` |
| **Tiempos extra** | — | siempre *(mismo `personal.ver` del router)* |

**En la nube, cada pestaña aparece según el módulo contratado Y el permiso** — los dos
filtros, que ya existen y son distintos: «una pestaña sin mudar se enseña y se explica; una
que no te toca no se enseña».

> ⚠️ **TRES HUECOS MEDIDOS, y ninguno se rellena por simetría.**
>
> 1. El registro de la web tiene `/personal` con `modulos: {personal, payroll}` y
>    **`pestanas: []`** — vacío. Las cuatro pestañas **no están declaradas todavía**.
> 2. **No existe ningún módulo para Descuentos ni para Tiempos extra.** Los módulos del
>    servidor son siete —`personal`, `payroll`, `clients_services`, `collections`,
>    `finance`, `purchases_inventory`, `assets`— así que las dos pestañas cuelgan de uno de
>    los existentes, y **de cuál es una decisión del inventario**, no un detalle.
> 3. **No existe ningún permiso de `payroll`, ni para descuentos, ni para tiempos extra.**
>    `payroll` es uno de los cuatro módulos «que existen y todavía no tienen ni un permiso»,
>    y el aviso de ese archivo vale aquí: completarlos por simetría no da una denegación
>    elegante, **el backend responde 500**, porque un código que nadie sembró es un error de
>    programación y no una negativa.
>
> Y la referencia manda: en el escritorio **Tiempos extra no tiene permiso propio** —la
> pestaña se muestra siempre y la barrera es `personal.ver`—. Si la nube le inventa uno,
> **es una regla nueva** y se presenta como tal.

---

## 📐 REGLA DEL INVENTARIO — la referencia es RISEG ONE

**Desde el 22 de octubre de 2026, y aplica a todo inventario de aquí en adelante.**

**Antes de proponer una regla nueva, se verifica en el escritorio si ya existe y cómo.** No
«si parece razonable»: se busca el caso de uso, se lee, y lo que diga se copia **sin
reinterpretar**. Si de verdad no existe, entonces se propone **nombrándola como regla nueva**,
para que la decisión sea visible.

**Por qué es una regla y no una recomendación.** Ya costó dos veces en un solo día: el cupo
se describió como «se valida contra las plazas» y **nadie lo validaba** —ni el escritorio ni
la nube—, y los tiempos extra se resumieron en dos orígenes cuando el escritorio tiene
**tres**. Las dos veces, leer el código cambió la decisión.

## El alta de un cliente, de punta a punta

Dictado por el dueño el **17 de octubre de 2026**. Es el recorrido completo desde que
alguien compra hasta que su equipo está trabajando, y sirve para situar cada etapa: los
pasos **1 y 2 son de facturación y de la web pública**; los **3 al 7 son parte de
Administra al 100 %**.

```
  1. compra y paga en seventra.mx        → deja nombre, correo y teléfono
  2. Console recibe aviso                 → correo o notificación
  3. Console envía la invitación          → por correo
  4. el cliente pone su contraseña        → ve «listo» y el enlace a su producto
  5. entra al producto como Maestro       → con los módulos y límites de su plan
  6. da de alta a su equipo               → cada quien recibe SU invitación;
                                            SEVENTRA sugiere permisos por puesto
  7. Console muestra el uso del plan      → accesos, empleados, empresas
```

> 📌 **Para el piloto con RISEG, el alta se hace desde Console.** Los pasos 1 y 2 no
> hacen falta para empezar: lo que se prueba es del 3 en adelante.

### Qué existe hoy, paso por paso

| # | Paso | Servidor | Console | Web (Administra) |
|---|---|---|---|---|
| 1 | Compra y pago en seventra.mx | ❌ **falta** (F7 timbrado, F8 cobro automático) | — | ❌ la página es «Próximamente» |
| 2 | Console recibe aviso | ❌ **falta** — no hay notificación de compra | ❌ falta | — |
| 3 | Console envía la invitación | ✅ `POST /platform/invitations` + reenviar y revocar | ❌ **falta la pantalla**: Console no llama esa ruta | — |
| 4 | El cliente pone su contraseña | ✅ `POST /invitations/lookup` y `/accept`, con sus páginas | — | — |
| 4b | Ve «listo» y el enlace a su producto | ⚠️ **el botón NO aparece**: `Web:SignInUrl` está vacío y esa entrada única todavía no existe | — | — |
| 5 | Entra al producto como Maestro | ✅ login, `/context` con módulos, permisos y `restricted` | — | ✅ **hecho**: login, empresa y Áreas |
| 6 | Da de alta a su equipo | ⚠️ **a medias** (ver abajo) | — | ❌ falta la pantalla |
| 7 | Console muestra el uso del plan | ✅ `GET /platform/organizations/{id}` trae capacidad y consumo; `GET /organizations/{id}/access-usage` trae los accesos | ⚠️ muestra «Capacidad y consumo», pero **no llama a `access-usage`** | — |

### El paso 6, desglosado: es el que más falta

| Pieza | Estado |
|---|---|
| Conceder acceso a una empresa | ✅ `POST /companies/{id}/access` |
| Revocar acceso, protegiendo al último Maestro | ✅ |
| Catálogo de permisos, **ya agrupado por módulo** | ✅ 103 permisos en 8 grupos |
| Conceder y retirar un permiso | ✅ idempotentes, sólo Maestro |
| Los 6 permisos **protegidos** que ni el Maestro recibe solo | ✅ |
| Módulos de la empresa | ✅ `GET`/`PUT /companies/{id}/modules` |
| **Auditoría de la empresa** | ✅ `GET /companies/{id}/audit`, exige `company.audit.read` |
| **Invitar por correo A UNA EMPRESA** | ❌ **no existe.** Las invitaciones son de plataforma e invitan a un **Owner de Organization**, no a un usuario de empresa |
| **Listar quién tiene acceso a una empresa** | ❌ **no existe.** Sin esto no hay lista que mostrar |
| **Plantillas de permisos por puesto** | ❌ **no existe nada**, ni en la base ni en la API |

⚠️ **El detalle que más cambia el trabajo:** `POST /companies/{id}/access` recibe un
**`IdentityId`**, un UUID — **no un correo**. La identidad tiene que existir ya. Así que
«crear usuario» desde Administra **no se puede** hoy por ningún camino: o la persona se
registró por su cuenta, o no hay a quién conceder acceso.

### Dónde entra esto en el orden de mudanza

**Paso 2, justo después de Estructura**, y partido en dos para no bloquear lo que ya
funciona:

- **2A · Usuarios, permisos y Auditoría.** La lista de accesos, los permisos agrupados
  por módulo con «Marcar todo» y contador, el indicador de accesos usados contra el plan,
  y Auditoría. Backend nuevo: **sólo el listado de accesos**; todo lo demás existe.
- **2B · Invitar por correo.** La ruta de invitación a nivel de empresa, su token, su
  correo y su aceptación. Es el trozo grande.

**Las plantillas se deciden en 2A**: o viven en la base y cada empresa las edita, o son
una constante del cliente. No está decidido.

**Y una regla que sale de aquí:** los permisos de un módulo **aparecen en la pantalla
cuando ese módulo se muda**. Mostrar hoy las casillas de Finanzas sería ofrecer control
sobre algo que todavía no existe en la nube.

**Respaldo y Bóveda siguen fuera** de Administra al 100 %, como se acordó.

### Decisiones sobre Usuarios y permisos (17 de octubre de 2026)

**Las plantillas son CONSTANTES DEL CLIENTE, no filas de la base.** Iguales para todas
las empresas —Recursos Humanos, Operaciones, Administración, Finanzas…— y son
**sugerencias**: el Maestro aplica una y después ajusta las casillas que quiera.

**Se sugieren según el ÁREA del puesto elegido.** Es lo que las hace útiles sin
convertirlas en una segunda fuente de verdad: no deciden nada, proponen. Quien decide
sigue siendo el Maestro, casilla por casilla.

> ⏳(D-32) **Plantillas editables por empresa: pendiente, y a la espera de que un cliente lo
> pida.** Guardarlas en la base hoy obligaría a diseñar su versionado, su auditoría y
> qué pasa con los accesos ya concedidos cuando la plantilla cambia —tres problemas
> reales— para resolver una necesidad que nadie ha expresado.

> 🚫 **LOS SEIS PERMISOS PROTEGIDOS NUNCA SE MARCAN POR PLANTILLA NI POR SER MAESTRO.**
> `personal.sueldo.ver` · `personal.sueldo.cambiar` · `personal.sensitive.read` ·
> `personal.sensitive.manage` · `clients_services.portals.read` ·
> `clients_services.portals.manage`.
>
> Se conceden **uno por uno y con un aviso claro** de lo que abren. Es la misma regla
> que el backend ya impone con `maestro_auto_grant = false`: la pantalla no la repite
> por simetría, la hace visible. Una plantilla que los marcara convertiría una decisión
> deliberada en un efecto colateral de elegir un puesto.

### Pendientes que esto deja en Console

- ⏳(D-33) **Pantalla para enviar la invitación de alta** (paso 3). La ruta existe
  —`POST /platform/invitations`, con reenviar y revocar— y Console no la llama.
- ⏳(D-34) **Mostrar los accesos usados contra los del plan** (paso 7). La ruta existe
  —`GET /organizations/{id}/access-usage`— y Console no la llama; hoy sólo pinta
  capacidad y consumo de medidores.
- ⏳(D-35) **Mantener el catálogo de regímenes fiscales del SAT** (requisito del dueño, 19 de
  octubre de 2026). A diferencia de los dos de arriba, **la ruta NO existe todavía**:
  hoy el catálogo se siembra por migración, así que cada cambio del SAT necesita un
  programador y un despliegue. Permiso de **plataforma** —no de empresa—, con
  **auditoría en `security_event`**, y **retirar nunca es borrar**. El detalle y las
  tres condiciones, al final de este documento.

### Decisión pendiente: la dirección de entrada

El botón que debería aparecer después de poner la contraseña **no se muestra** porque
`Web:SignInUrl` está vacío, y está vacío porque esa dirección todavía no existe.

Candidatas sugeridas: **`app.seventra.mx`** o **`administra.seventra.mx`**. La primera
sirve a los tres productos y la segunda nombra a uno; la diferencia importa porque esa
dirección es la que va a quedar escrita en todos los correos.

**Se decide al montar producción.** Hasta entonces, quien acepta una invitación termina
leyendo «Ya puedes iniciar sesión con tu correo y tu contraseña» y **sin ningún enlace
que seguir** — es correcto y es incómodo, y conviene que conste.

### ⏳(D-29) «¿Olvidaste tu contraseña?» en la web — REQUISITO antes del piloto

Junto con **2B**, y por la misma razón: sin esto, una persona que olvide su contraseña
**no tiene ninguna salida** salvo pedírselo a quien administra, que tampoco puede
cambiársela —la nube no guarda contraseñas de nadie—.

El escritorio **sí lo tiene**: su login muestra el enlace y llama a la API. La web lo
perdió al rehacerse, y eso fue un descuido, no una decisión.

**Lo que YA existe, que es casi todo:**

| Pieza | Dónde |
|---|---|
| `POST /auth/forgot-password` | API. Responde **202 siempre**, exista o no la cuenta: decir cuál tiene cuenta convertiría la pantalla en un oráculo |
| `POST /auth/reset-password` | API, con token de un solo uso |
| `AuthApi.solicitarRestablecimiento({email})` | **Ya está en el cliente Dart**, sin usar |
| La página de restablecer | **La sirve la propia API**, en `/restablecer-contrasena`. Sin dependencias, sin secretos y **no canjea sola** —hay que pulsar un botón—, para que un antivirus de correo no gaste el token |
| Los textos | `loginOlvideContrasena`, `loginRecuperacionEnviada` |

**Lo que falta, y son dos cosas de distinto tamaño:**

1. **Enganchar el enlace en el login web** —diálogo que pide el correo, llama a
   `solicitarRestablecimiento` y muestra siempre el mismo mensaje—. Es pequeño: el
   cliente, la ruta y los textos ya existen.

2. ⚠️ **A dónde llevan los enlaces lo decide `Email:LinkBaseUrl`, y hay que mirarlo.**

   **UNA SOLA VARIABLE PARA LOS TRES CORREOS**, comprobado en el compositor:
   `Compose(email, linkBaseUrl)` arma `/verificar-correo`, `/restablecer-contrasena` y
   `/aceptar-invitacion` desde la misma base. No hay una por tipo de correo, así que
   cambiarla mueve los tres a la vez.

   ✅ **MEDIDO EN EL SERVICIO EL 17 DE OCTUBRE DE 2026:**
   `Email__LinkBaseUrl = https://api.seventra.mx`. **Ya está como se necesita para el
   piloto; no hay nada que cambiar en el ensayo.**

   > ⚠️ **DOS AFIRMACIONES MÍAS QUE ERAN FALSAS, y conviene que consten las dos.**
   >
   > Dije que «el enlace está roto» porque la variable valía `https://app.seventra.mx`.
   > **Ése era el valor de los user-secrets LOCALES**, y lo presenté como general.
   >
   > Después dije que el runbook ponía `https://console.seventra.mx` en el ensayo. El
   > runbook **lo decía**, pero el servicio **no**: la documentación estaba desfasada, no
   > el despliegue. El runbook ya está corregido.
   >
   > La lección es la de siempre: la fuente de verdad de una variable de despliegue es
   > el servicio, no un archivo de configuración local ni un documento.

   **DECISIÓN:** para el piloto se queda `api.seventra.mx`, que es donde las páginas de
   identidad viven de verdad —las sirve la propia API, no Console—. **`app.seventra.mx`
   se crea al montar producción**, porque esa dirección acaba escrita en todos los
   correos y conviene que sea la definitiva.

   **El día que se cambie** se hace con `--update-env-vars` —nunca `--set-env-vars`, que
   borra las demás— y se verifica con un **correo de restablecimiento real** que abra la
   página, acepte una contraseña nueva y permita entrar con ella. Ver la página con buen
   aspecto no basta: el canje puede fallar después.

> 🚫 **Lo que NO se trae del escritorio:** «Recuperar desde un respaldo portable». Lee un
> archivo del disco con `dart:io` y el respaldo desaparece en la nube.

### ⏳(D-36) Ajuste visual pendiente del login web

En el escritorio el formulario va **dentro de una tarjeta con borde**; en la web quedó
suelto sobre el fondo. **Igualarlo la próxima vez que se toque el login** —no bloquea
nada, y conviene hacerlo en el mismo cambio que añada «¿Olvidaste tu contraseña?», que
toca ese archivo de todas formas.

### Decisiones de 2A (17 de octubre de 2026)

#### 1 · El contador de accesos: ruta nueva, a nivel de empresa

**El problema medido:** un Maestro **no puede leer el límite de su plan**.
`GET /organizations/{id}/capacity` y `GET /organizations/{id}/access-usage` exigen
`EnsureOrganizationAuthorityAsync` —una fila en `organization_membership`—, y un
Maestro tiene `company_access`, no membresía. El modelo separa las dos autoridades a
propósito: «Requiere CompanyAccess activo. Ser Owner de la Organization no basta», y al
revés.

**Y un segundo problema, más sutil:** el límite es **de la Organization** y la lista es
**de una empresa**. Un cliente con tres empresas reparte 5 accesos entre las tres; poner
«3 de 5» junto a una lista de 3 haría creer que quedan 2 para esa empresa cuando quizá
no queda ninguno.

**DECISIÓN:** se añade una **ruta de sólo lectura a nivel de empresa** que un Maestro
pueda leer, dentro de 2A, **sin migración**, con pruebas y mutaciones. Se despliega
junto con `GET /companies/{id}/access` en **un solo despliegue**.

La pantalla muestra **dos números separados, nunca mezclados**:

```
  3 personas con acceso a esta empresa      ← sale de contar la propia lista
  4 de 5 accesos de tu plan, en todas tus empresas   ← la ruta nueva
```

**Y se conserva la protección del servidor:** el botón de agregar **no se apaga por
cálculo del cliente**. Si no hay cupo, el servidor rechaza con su error de capacidad y
la pantalla dice **«Tu plan no tiene más accesos disponibles.»** El cliente informa; la
autoridad decide. Un botón apagado por una cuenta hecha en el navegador sería una
segunda fuente de verdad sobre la capacidad.

#### 2 · Las plantillas NO entran en 2A

**Por qué:** con la regla de que los permisos de un módulo aparecen cuando ese módulo
se muda, hoy la pantalla sólo puede mostrar **los 10 permisos del núcleo**
—`organizacion.*` (el módulo que sí está mudado), `company.settings.manage`,
`company.audit.read`, los tres de `usuarios.*` y `reportes.ver`—. Los otros 93 son de
módulos que siguen en SQLite.

De esos 10, **tres son de gobierno** y ninguna plantilla los otorga nunca. Así que una
plantilla hoy marcaría, como mucho, `organizacion.*` + `reportes.ver` +
`company.settings.manage`: un desplegable que existe y casi no cambia nada.

**Y el mapeo no es trivial:** de 68 códigos del escritorio, **30 coinciden exactos** con
los de la nube y **38 no** (`personal.ver` → `personal.read`). Mapear los 38 ahora sería
escribir una tabla para módulos que nadie puede todavía conceder.

**DECISIÓN:** las plantillas entran en **M4 (Personal)** y **crecen módulo por módulo**.
Cada mapeo llega con **su prueba de que no toca los seis protegidos ni los de
gobierno**. **La sugerencia por área del puesto llega con ellas**, no antes: sugerir una
plantilla vacía sería peor que no sugerir nada.

> Son **siete** plantillas en el escritorio, no ocho: Recursos Humanos, Nómina,
> Tesorería, Comercial, Operaciones, Compras y Solo consulta.

### La regla de consumo de accesos (decisión del dueño, 17 de octubre de 2026)

```
  · cualquier persona             → 1 acceso POR EMPRESA
  · el OWNER de la Organization   → 1 acceso EN TOTAL, tenga las que tenga
  · el owner SIN ningún acceso    → 0
  · un `admin` de la Organization → como todos: 1 por empresa
```

**La bolsa es el total del plan repartido entre todas las empresas del cliente**
—Esencial 5, Profesional 10, Corporativo 15—; para más, el adicional de acceso.

**Ejemplo (Profesional):** el dueño en 3 empresas = 1 · alguien de RH en 2 = 2 · un
operativo en 1 = 1 → **4 de 10**. Sin la excepción serían 6.

**La excepción sigue al dueño:** si cambia el owner, pasa al nuevo. **No se guarda en
ninguna parte** —`ux_organization_single_active_owner` garantiza un solo owner activo
por Organization, así que se deriva de quién lo es hoy—. Sin estado que sincronizar y
**sin migración**.

> ⚠️ **ERAN CUATRO SITIOS CONTANDO ACCESOS, NO TRES.** Al aplicar la regla quedó fuera
> `CountActiveCompanyAccessAsync`, que es la que alimenta `access-usage` y tenía su
> propia consulta: el snapshot ya decía 1 y `access-usage` seguía diciendo 3. **Lo cazó
> la prueba del ejemplo**, no una revisión. Los cuatro comparten ahora la misma
> expresión, `SubscriptionRepository.ConsumoDeAccesosSql`.

> ⚠️ **Y DESAPARECIÓ EL `+ 1` AL CONCEDER.** El cálculo contaba «todos menos el par» y
> sumaba uno. Con la excepción del owner eso **sería falso**: conceder a quien ya cuenta
> no consume nada. Ahora la consulta devuelve el consumo **tal como quedaría después de
> conceder**, y quien llama compara directo. Pedir capacidad de accesos **sin el par**
> lanza: contar de menos en silencio sería conceder capacidad sin comprobarla.

**Efecto comercial, decidido a sabiendas:** la regla **libera cupo** en organizaciones
que ya existen (6 → 4 en el ejemplo). La capacidad contratada rinde más que antes.

### `GET /companies/{id}/access-capacity` — construida (18 de octubre de 2026)

La ruta decidida arriba, ya en el servidor. **Sólo Maestro**, y devuelve **sólo la línea
de accesos**: `included`, `extra`, `total`, `usage`, `remaining`, más el `companyId` desde
el que se preguntó. Ni plan, ni precios, ni estado de la suscripción, ni las capacidades de
empresas, empleados o almacenamiento — el snapshot del que sale trae todo eso, y una prueba
afirma la lista exacta de propiedades para que nada se cuele después.

| | |
|---|---|
| **Quién** | Maestro de esa empresa. Un acceso corriente recibe **403**; quien no tiene acceso, **404**, idéntico byte a byte a una empresa inventada |
| **Qué cifra** | La de **toda la Organization** —la bolsa se reparte entre sus empresas—, con la **regla del owner** ya aplicada |
| **Bajo `restricted`** | **Responde 200.** Leer el límite no lo gasta, y negarlo dejaría al Maestro sin saber por qué no puede sumar a nadie |
| **`extra` hoy** | Siempre **0**: el adicional de accesos existe como identidad pero **no tiene versión vendible** —no se le inventó precio—. Es un hecho medido, no una ausencia disfrazada |

**Dos correcciones que salieron de medir, no de pensar:**

> ⚠️ **EL 409 `subscription_missing` QUE ESPECIFIQUÉ ERA CÓDIGO MUERTO.** Lo copié de la
> ruta de Organization sin notar que las dos autorizan distinto: aquélla mira la
> **membresía**, que no evalúa el estado comercial, así que puede dejar pasar a un Owner
> sin plan. Ésta autoriza por `company_access` **evaluando antes la relación comercial**,
> y sin línea vigente ya ha contestado **402**. La prueba que escribí para el 409 midió
> `PaymentRequired`. La rama se retiró y la ruta responde **402 `subscription_restricted`**,
> el mismo código que el resto del plano operativo.

> ⚠️ **Y LA RAMA SÍ ERA ALCANZABLE, por el multiproducto.** Lo cazó **una mutación que
> sobrevivió**: cambiar el rechazo por `total: 0, usage: 0` no rompía ninguna prueba. El
> autorizador evalúa **todas** las líneas de producto —a propósito: un cliente de sólo
> Cumple tiene que poder entrar a lo que paga— y el snapshot de capacidad mira **sólo
> Administra**. Así que **con Cumple vigente y Administra terminada la autorización pasa y
> el snapshot viene vacío**. Hay prueba de ese estado exacto, y exige lo que no se negocia:
> **que no haya cifras**. Unos ceros dirían «tu plan no incluye accesos» cuando lo que pasa
> es que no hay plan de Administra que medir.

**Pendiente de producto, anotado y no inventado:** ese estado responde hoy **402
`subscription_restricted`**, cuyo mensaje —«la suscripción de la organización no permite la
operación normal»— **no es exacto**: la suscripción de Cumple está perfecta; lo que falta es
Administra. «No tienes Administra» no es «debes dinero», y los motivos de denegación no se
colapsan. Merece **su propio código**, y la pregunta es más ancha que esta ruta: afecta a
todo el plano de Administra para una empresa cuya línea terminó mientras otro producto
sigue vivo. **Se decide aparte; esta ruta no inventa un código por su cuenta.**

**Las seis mutaciones, todas muertas:** quitar la exigencia de Maestro · declarar la lectura
como mutación · devolver la línea de empresas en vez de la de accesos · devolver el consumo
de empresas · devolver ceros en vez del rechazo · mandar el id de la Organization donde va
el de la empresa.

> Y se añadieron a `RestrictedReadOnlyTests` **las dos** lecturas de la pantalla de
> Usuarios: `access-capacity` y **`access`, que faltaba** —entró con la etapa E y no se
> anotó, que es exactamente lo que esa prueba existe para evitar—.

### La pantalla de 2A — construida (18 de octubre de 2026)

`Configuración › Usuarios`, con **dos pestañas**: Usuarios y Auditoría.

**Archivos nuevos**, todos bajo `lib/features/usuarios/web/`:

| Archivo | Qué es |
|---|---|
| `modelos/miembro_de_empresa.dart` | Una persona con acceso. «Es Maestro» **se deriva** de `role`, no es un campo |
| `modelos/permiso_de_empresa.dart` | Un permiso del catálogo. `protegido` es la **negación** de `maestroAutoGrant` |
| `modelos/capacidad_de_accesos.dart` | Las cinco cifras del plan. El total **no se recalcula** aquí |
| `modelos/evento_de_auditoria.dart` | Un hecho y una página con su cursor opaco |
| `datos/usuarios_repositorio_http.dart` | Las seis llamadas, todas devolviendo `Result` |
| `presentation/usuarios_web_screen.dart` | La lista, los dos contadores y el panel de permisos |
| `presentation/auditoria_web_pestana.dart` | La auditoría con «Cargar más» |

#### Las decisiones que no se ven en el código y conviene no reabrir

**Las dos cifras van en LÍNEAS SEPARADAS.** «3 personas con acceso a esta empresa» y
«4 de 10 accesos de tu plan, en todas tus empresas». La segunda es de toda la
organización; juntarlas —«3 de 10»— prometería 7 libres para esta empresa cuando el
cliente quizá los gastó en otra.

**No se pudo averiguar NO es cero.** Si la ruta de capacidad falla, la pantalla dice
«No se pudo leer el uso de tu plan» con un «Reintentar», y la lista de personas sigue
funcionando. Un «0 de 0 accesos» diría que el plan no incluye ninguno.

**Usuarios sólo aparece en el menú para un Maestro**, y la pestaña de Auditoría sólo
con `company.audit.read` — leído de los **permisos efectivos** que calculó el
servidor, nunca de una regla escrita en el cliente. **Ocultar no es autorizar**: el
servidor vuelve a decidir en cada petición; lo que se evita es ofrecer una puerta que
va a responder 403.

**Se guarda la DIFERENCIA, no el conjunto.** El servidor concede y retira de uno en
uno, así que se mandan sólo los que cambiaron: mandar los 103 cada vez escribiría en
la auditoría cien hechos que no pasaron. Si uno falla **se para ahí** —los siguientes
fallarían por lo mismo— y se recarga, porque los anteriores sí se aplicaron.

**Los seis protegidos van en su propio bloque, y NO tiene «Marcar todo».** Un botón
que los conceda de golpe convertiría seis decisiones deliberadas en un clic. Y el
bloque **explica la diferencia que confunde a todo el mundo**: el primer Maestro de una
empresa nace con los seis concedidos; uno añadido después empieza sin ninguno. El aviso
aparece justo donde se ve.

**De un Maestro se dice «N + su rol», no «N permisos».** Enseñar «6 permisos» junto a
«Maestro» haría creer que sólo puede hacer seis cosas, y alguien podría quitarle todas
las casillas creyendo que así lo limita.

**En la auditoría, un actor que ya no tiene acceso se muestra por su identidad, nunca
se oculta la fila.** Una auditoría que esconde lo que no sabe nombrar deja de servir
justo para lo que existe. Y la fecha va **completa y en local**, no «hace 3 horas»: en
una auditoría la hora exacta es el dato.

#### Dos pendientes del SERVIDOR que el cliente está tapando

> ⏳(D-37) **El catálogo de permisos no manda el NOMBRE DEL MÓDULO**, sólo `moduleCode`. La
> pantalla tiene un mapa de los **siete módulos** del producto para poder titular los
> grupos. No es el catálogo replicado —los permisos, sus nombres y su condición de
> protegido vienen del servidor—, pero es texto que el cliente decide. **Un código
> desconocido se muestra tal cual**, nunca se oculta: un módulo nuevo aparecería feo y
> corregible en vez de desaparecer con sus permisos dentro.

> ⏳(D-14) **La auditoría manda `action` y `entityType` en CÓDIGO.** Se traducen los
> **verbos** —vocabulario cerrado y corto— y **sólo las entidades que esta etapa
> produce de verdad**: accesos, permisos, módulos, la empresa y la estructura mudada.
> Las otras cincuenta se muestran con su código, que es más honesto que inventar el
> nombre oficial de algo que todavía no tiene pantalla. El día que el servidor mande
> etiquetas, los dos mapas sobran.

#### Lo que 2A NO incluye, a propósito

- **Dar de alta a alguien nuevo** → **2B**, por invitación al correo. Hoy el acceso se
  concede sobre una identidad que ya existe, y pedir un UUID a mano no es una pantalla.
- **Las plantillas de permisos** → **M4 (Personal)**, cuando haya puestos que las hagan
  significar algo.
- **Filtros en la auditoría.** El servidor acepta fecha, actor, entidad y acción, y no
  se exponen: con un solo módulo mudado, la auditoría de una empresa cabe en dos o tres
  páginas. Cuando haya volumen, los filtros van **al servidor**, no a un `where` sobre
  lo ya descargado.
- **Secciones en el menú.** Usuarios es de Configuración, no de Estructura, y hoy cuelga
  del mismo nivel porque este menú **todavía no agrupa**. En cuanto se mude Personal o
  Clientes habrá que agrupar, y entonces Usuarios baja a Configuración.

### Los tres ajustes de 2A y la estructura del menú (18 de octubre de 2026)

#### 1 · Auditoría legible: nunca JSON

Cada fila dice una frase con **el objeto nombrado** —«Creó el área Monitoreo», «Dio
acceso a Juan Pérez», «Concedió el permiso Ver sueldo»— y el detalle es una lista de
campos con etiquetas en español. Toda la traducción vive en **un archivo sin widgets**,
`auditoria_legible.dart`, que por eso se prueba entero.

| Decisión | Por qué |
|---|---|
| El nombre sale **del propio registro** —`after.name`, `after.code`— y para un acceso del `subjectIdentityId` cruzado con quién tiene acceso hoy | No hace falta ir a buscarlo, y un actor que ya no está se muestra por su identidad abreviada: **nunca se oculta la fila** |
| El verbo se **deriva del cambio** cuando el cambio lo dice mejor: `status_changed` a inactiva es «Desactivó», no «Cambió el estado» | Quien lo lee quiere saber qué pasó, no qué columna se tocó |
| El género va con el objeto: «el área», «la sucursal» | «el sucursal» es lo que hace que una pantalla parezca traducida a máquina |
| En un cambio, **sólo los campos distintos**, como «Nombre: Monitoreo → Monitoreo central» | Repetir los diez que siguen iguales esconde el único que se movió |
| Valores traducidos: `true/false` → Sí/No · estado → **chip con color e ícono** · fecha → `18/oct/2026` | `18/10/2026` y `10/18/2026` se confunden; tres letras no se confunden con nada |
| **Los campos técnicos no se muestran** —ids, huellas, marcas internas— pero `area_code` **sí** | No es un identificador: es el código que el cliente escribió y reconoce |
| Lo que ya está en el título no se repite abajo | El permiso y el módulo salen en la frase; volver a listarlos es ruido |
| Un detalle ilegible se dice **con palabras** | No hay ningún camino que vuelque el JSON, ni «para depurar» |

> **LA PRUEBA QUE PROTEGE TODO ESTO ESTÁ EN EL BACKEND.**
> `AuditPayloadVocabularyTests` **ejecuta de verdad** las doce operaciones auditadas que
> esta etapa produce y luego lee del `audit_event` las claves que realmente se
> escribieron. No es una lista copiada a mano: es lo que la base tiene después de
> trabajar. Si alguien añade un campo a un registro y no lo traduce, **falla diciendo
> su nombre y los dos pasos del arreglo**.
>
> Verificado mutando el backend: con un `.Set("hierarchy_level", …)` de más en el alta
> de un puesto, la prueba dice `position.hierarchy_level`. Y su aserción es un
> **subconjunto**, no una lista exacta: añadir un campo ya traducido no la rompe.
>
> Son **ocho entidades y catorce claves** hoy, medidas leyendo `TenancyRepository`,
> `AuthorizationRepository` y `StructureRepository`. Se amplían **cuando un módulo se
> muda**, igual que el registro del menú.

#### 2 · Permisos: sólo de módulos mudados

Hoy eso son **los del núcleo y ninguno más**, y la pantalla **dice cuántos faltan**:
«Hay 93 permisos más de módulos que todavía se usan desde la aplicación de escritorio».
Un panel con 10 de 103 sin explicar el resto parece un catálogo roto.

**La excepción son los seis protegidos, y es deliberada:** sus módulos —Personal y
Clientes— no están mudados, así que por la regla general no deberían verse. Se
exceptúan porque **ese bloque existe precisamente para enseñar** que el primer Maestro
nace con los seis y que uno añadido después no los tiene. Y concederlos ahora no hace
daño: el módulo que los lee sigue en el escritorio, y el permiso queda esperándolo.

#### 3 · Maestro: marcado, deshabilitado y con su razón

Sus permisos ordinarios se ven **marcados, en gris y con «Incluido por ser Maestro»** al
lado. El renglón entero deja de responder —no sólo el cuadro—, porque una etiqueta que
acepta el clic y no cambia nada se siente como un fallo. Y en un grupo entero incluido
por el rol **no se pinta «Marcar todo»**: sería un botón que no hace nada.

`RisegCheckbox` ganó dos parámetros **opcionales** —`enabled` y `nota`—, así que ninguna
pantalla del escritorio se enteró.

**Los seis protegidos siguen editables para el Maestro**, que es justo la diferencia que
el bloque enseña.

#### 4 · El menú: nueve apartados con pestañas

El escritorio tiene **once** entradas planas ([shell_destinations.dart](../lib/app/shell/shell_destinations.dart));
la nube tiene **nueve**, con dos uniones decididas:

| Apartado | Pestañas | Estado |
|---|---|---|
| Dashboard | — | Próximamente |
| **Organización** | Empresa · **Sucursales** · Puestos · **Áreas** | Sucursales y Áreas mudadas |
| Comercial | las del escritorio, al mudarse | Próximamente |
| Finanzas | ídem | Próximamente |
| Personal | ídem | Próximamente |
| **Compras e inventario** | Inventario · Compras | Próximamente |
| **Activos** | Vehículos · Telefonía | Próximamente |
| Reportes | — | Próximamente |
| **Configuración** | **Usuarios** · **Auditoría** | las dos mudadas |

**Las dos uniones no son capricho:** son exactamente los módulos `purchases_inventory` y
`assets` del servidor, así que **el menú y los grupos de permisos acaban diciendo lo
mismo**. Y «Activos» aquí **no es el módulo que se retiró tras la Etapa 10** —aquél era
un placeholder sin tabla, repositorio ni pantalla—: es un contenedor de pestañas.

**Respaldo y Bóveda no se mudan, y no es un pendiente:** el respaldo portable y la bóveda
local son del producto de escritorio, donde los datos viven en el disco de quien los
usa. En la nube el respaldo es del servidor.

**Tipos de sucursal NO es pestaña:** vive dentro de Sucursales, detrás de un botón. Un
cliente abre «Sucursales» para ver sus sucursales; los tipos son el catálogo que las
ordena, y darles el mismo peso sería al revés.

#### El registro único: `lib/app/shell/apartados_web.dart`

De un solo archivo salen **tres cosas que antes podían discrepar**: el menú, las
pestañas con su estado de mudanza, y los grupos del panel de permisos con su nombre.
Mudar un módulo es **una línea**: `mudada: false` → `true`.

> ⚠️ **ESTÁ EN `lib/app/shell/` Y NO EN `features/`, Y ES POR UNA GUARDA.**
> `autorizacion_arquitectura_test` exige que **ninguna feature** mencione
> `PermisoCompany` ni `ModuloCompany`. El registro los necesita —y debe, para no
> escribir los códigos a mano—, así que vive en el shell, que es donde la estructura
> del menú pertenece de todas formas. **Ninguna guarda se aflojó para esto.**

**Tres casos y no dos**, que es el fallo que casi se me pasa:

```
  tiene pestañas para ti        → se abre
  NO está mudado                → «Próximamente»
  mudado, pero nada para ti     → NO APARECE
```

El tercero es real: quien no es Maestro y no puede leer la auditoría no tiene nada en
Configuración. Decirle «Próximamente» le prometería algo **que ya llegó**, y dejarlo
entrar a un apartado vacío es un callejón sin salida. La decisión es una función pura,
`queHacerCon`, y hay prueba de los tres casos.

**«Próximamente» va en una SEGUNDA LÍNEA del ítem del menú**, no como insignia al lado:
al lado le robaba el ancho al nombre, que es exactamente por lo que «Tipos de sucursal»
salía cortado. Colapsado, el rótulo viaja en el tooltip.

> ⚠️ **LO QUE CAZÓ LA SUITE COMPLETA, Y NO LAS CARPETAS SUELTAS.**
>
> Al unificar los nombres de módulo en el registro, la auditoría empezó a decir
> **«Activó el módulo Personal»** cuando el hecho registrado era `module: payroll`. Es
> **falso**: lo que se encendió fue Nómina, no todo Personal.
>
> Confundí dos preguntas que tienen dos respuestas:
>
> | Pregunta | Respuesta |
> |---|---|
> | ¿Cómo se titula el **grupo de permisos**? | El nombre del **apartado** → «Personal» cubre `personal` y `payroll` |
> | ¿Cómo se nombra el **hecho auditado**? | El nombre del **módulo** → `payroll` es «Nómina» |
>
> La primera es la que pediste —que los grupos coincidan con el menú—; la segunda es
> precisión de la auditoría. Ahora son dos funciones, y hay una prueba que **exige que
> discrepen** en los tres módulos que comparten apartado: si algún día coincidieran,
> sería la señal de que alguien volvió a unificarlas y la auditoría volvió a mentir.

### Las seis correcciones de la revisión (18 de octubre de 2026)

| | Qué cambió | La razón, que es lo que no se debe reabrir |
|---|---|---|
| 1 | **Organización enseña sus cuatro pestañas** —Empresa · Sucursales · Puestos · Áreas— en el orden del escritorio. Empresa y Puestos abren «Próximamente» | Mostrar sólo las dos con pantalla haría pensar que el producto perdió las otras. **Una pestaña sin mudar se enseña y se explica** —va a llegar—; **una que no te toca no se enseña** —no tenerla no es algo que esté por llegar—. Son dos filtros distintos y ahora el código los distingue |
| 2 | **La sesión empieza en el primer apartado con pantalla**, hoy Organización | Dashboard es el primero del menú y está en «Próximamente»: recibir ahí haría pensar que no hay nada hecho. Sale del **mismo registro**, así que el día que Dashboard se mude la sesión empezará ahí sin tocar una línea de la pantalla |
| 3 | La lista dice **«Todos los permisos»** para un Maestro y **«N permisos»** para los demás | «6 + su rol» era jerga: sólo se entendía sabiendo que los permisos de un Maestro no son filas |
| 4 | El chip de Estado del detalle es **una pastilla compacta** | Dentro del `Expanded` se estiraba a todo el ancho y dejaba de parecer una pastilla. En la lista de Áreas se ve compacto y aquí tiene que verse igual |
| 5 | Auditoría tiene **título y subtítulo** como Usuarios | Sin encabezado, la segunda pestaña parecía un listado suelto. El subtítulo dice el **orden**, que es lo primero que alguien se pregunta al mirar una traza — y es exacto: el servidor ordena por `occurred_at DESC`, verificado |
| 6 | El rastro dice **«Configuración › Usuarios»** | Con sólo el apartado, dos pestañas distintas se leían igual |

> ⚠️ **POR QUÉ LA LISTA NO DICE «6 PROTEGIDOS», QUE ERA EL EJEMPLO PEDIDO.**
> `permissionCount` cuenta **todas** las concesiones del periodo, no sólo las
> protegidas. Para el primer Maestro esas seis **son** las protegidas, así que el
> número coincidiría hoy — pero si alguien le concediera un permiso ordinario por API
> diría «7 protegidos» y sería falso. Afirmar en una pantalla algo que los datos no
> sostienen es justo lo que no se hace aquí, así que el número se queda donde es
> exacto: el panel, que sí sabe cuáles son.
>
> ⏳(D-34) Para decirlo con número, `GET /companies/{id}/access` tendría que mandar su propio
> `protectedPermissionCount`. Son unas quince líneas en `TenancyRepository` y su DTO.

**Las pestañas no llevan marca visual de «Próximamente»**, y es una limitación del
componente, no una decisión: `RisegTabs` pinta el ícono **encima** del texto, así que
marcar sólo algunas las haría más altas que el resto y desalinearía la barra. Se abren
y se explican, que es lo acordado. Si hace falta la marca, pide un tratamiento distinto
—un sufijo en la etiqueta, por ejemplo— y se hace aparte.

#### 🧾 EL CICLO LOCAL COMPLETO — la hoja de comandos

**Regla desde el 21 de octubre de 2026: estos son LOS comandos, y no se escriben de
memoria.** Cualquier bloque que se entregue para correr en local se copia de aquí.

**Por qué existe esta sección.** Se entregó un bloque con `dotnet run --project
src\Seventra.Migrations` a secas y `flutter run -d chrome --target lib/main_web.dart` a
secas. Los dos habrían fallado, y los dos modos de fallo estaban ya documentados en otro
sitio: la migración muere con «falta la cadena de conexión» —`dotnet run` arranca en
**Production** y no lee los secretos de desarrollo— y la web no arranca porque
`ApiConfig` no tiene valor por omisión. Tenerlos en dos documentos de dos repositorios
distintos es lo que permitió escribirlos mal.

```powershell
# ─── 1. RESPALDO, antes de cualquier migración ─────────────────────────────
cd C:\Users\segur\seventra-backend
.\scripts\respaldar-dev.ps1 -Etiqueta 00NN

# ─── 2. MIGRAR ─────────────────────────────────────────────────────────────
# LA CADENA DEL MIGRADOR NUNCA VA EN EL COMANDO, y las credenciales del
# migrador son DISTINTAS de las de la API.
#
# `Read-Host` EN SU PROPIA LINEA y la cadena EN UNA SOLA: pegar varias lineas
# de golpe en una consola puede partirse justo en la continuacion y dejar la
# variable a medias, con la contrasena ya escrita.
#
# `--target NN` NO ES OPCIONAL: sin el, el migrador aplica TODO lo pendiente,
# y lo pendiente puede incluir una migracion que todavia no se aprobo. Se
# pone el numero de la que se esta aplicando, el mismo de la etiqueta de
# arriba.
$sec = Read-Host -AsSecureString 'Contrasena de seventra_migrator'
$env:SEVENTRA_MIGRATOR_CONNECTION = "Host=127.0.0.1;Port=5432;Database=seventra;Username=seventra_migrator;Password=" + [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))
dotnet run --project src\Seventra.Migrations -- --target NN
Remove-Item Env:SEVENTRA_MIGRATOR_CONNECTION
# Y LA VARIABLE TAMBIEN SE VA: `$sec` sigue en la sesion con la contrasena
# dentro, y esa ventana se queda abierta horas.
Remove-Variable sec

# ─── 3. LA API, en otra ventana ────────────────────────────────────────────
$env:ASPNETCORE_ENVIRONMENT = 'Development'
dotnet run --project "C:\Users\segur\seventra-backend\src\Seventra.Api" --urls http://localhost:5080

# ─── 4. LA WEB, en otra ventana ────────────────────────────────────────────
cd C:\Users\segur\riseg_control_activos
flutter run -d chrome --web-port=5301 `
  --target lib/main_web.dart `
  --dart-define=SEVENTRA_API_BASE_URL=http://localhost:5080
```

```powershell
# ─── 5. AL CERRAR LA ETAPA, y no antes ─────────────────────────────────────
# «LIMPIO» ES CERO: cero errores, cero warnings y cero `info`. Lo decidió el
# dueño el 25 de octubre de 2026, cuando se midió y salieron 190 avisos `info`
# que la frase «analyze limpio» venía tolerando sin que nadie lo decidiera.
cd C:\Users\segur\riseg_control_activos
flutter analyze lib test     # tiene que decir: No issues found!
flutter test                 # y la suite completa en verde
```

**El orden no es cosmético: parar la API → migrar → arrancar.** `DatabaseReadyCheck`
sólo rechaza un esquema **VIEJO**, así que una build vieja contra un esquema nuevo
reporta salud y falla en cada petición. Y **no hay migración inversa**.

**`ASPNETCORE_ENVIRONMENT=Development` no es opcional** para la API: sin él `dotnet run`
arranca en Production, no lee los secretos de usuario y dice que falta la cadena de
conexión, que se lee como si el secreto no estuviera puesto.

**El `--dart-define` no es opcional:** `ApiConfig` **no tiene valor por omisión** a
propósito, así que sin él la app no arranca y lo dice.

**Y el puerto 5301 tampoco es arbitrario:** es el origen que el guion de siembra deja
autorizado en `Web:AllowedOrigins:1`, y **se queda configurado**. Con otro puerto el
navegador bloquearía las peticiones por CORS y la pantalla diría que no hay conexión,
que es indistinguible de un servidor caído.

> **El comando de migrar tiene un gemelo** en
> `seventra-backend/docs/despliegue-google-cloud.md`, que es su autoridad original y
> explica por qué la cadena va en una variable y no en el comando. Si cambia la cadena,
> cambia en los dos sitios — y el de allá lo dice también.

### ✅ El rastro YA baja a Tipos de sucursal — resuelto, y el pendiente se quedó sin tachar

**Se arregló con la segunda salida de las dos que esta sección proponía**, y el texto de
abajo quedó describiendo un problema que ya no existe. Se conserva porque la causa y el
arreglo de raíz siguen siendo ciertos, pero **el síntoma está resuelto**:
`SucursalesWebScreen` avisa con `alCambiarElRastro` y el portón lo pinta como
`dentroDeLaPestana`. Desde el esquema 50 lo usa también el expediente de una sucursal.

Lo encontré al revisar la lista de pendientes el 19 de octubre de 2026, y es justo lo que
la regla de «nada para después» viene a evitar: **un pendiente resuelto que nadie tacha
pesa igual que uno abierto**, porque el siguiente que lea la lista lo cuenta como trabajo.

El problema que describía, para que la causa no se pierda:

Dentro de **Sucursales → Tipos de sucursal** el rastro decía «Organización ›
Sucursales». Debía decir **«Organización › Sucursales › Tipos de sucursal»**.

**Por qué pasa:** el rastro se arma en el portón con lo que éste sabe —el apartado y la
pestaña— y Tipos de sucursal **no es una pestaña**: vive dentro de la pantalla de
Sucursales, detrás de un botón, con un `bool` de estado local. El portón no se entera de
que se entró ahí.

**Lo que lo arregla de raíz:** el router. Cuando la web tenga `go_router`, ese `bool` pasa
a ser una ruta hija y el rastro sale de la ruta, no de un parámetro que hay que acordarse
de pasar hacia arriba.

**Lo que lo arreglaría antes, si molesta:** un callback de la pantalla de Sucursales al
portón para añadir un tercer segmento. Funciona, y añade una vía de comunicación hacia
arriba que el router va a hacer innecesaria — por eso no se hizo todavía.

No bloquea nada: quien está ahí ve el botón «← Sucursales» arriba a la izquierda, que es
la salida.

### ⚠️ Un fallo que cazó una PREGUNTA, no una prueba

El botón «Agregar tipos recomendados» decía **«Se agregaron 3 tipos recomendados» al
segundo clic**, sin haber creado ninguno.

**La causa:** supuse que `POST …/branch-types/recommended` devolvía *lo que creó*. Devuelve
**el conjunto resultante**. Lo dice la prueba del backend, que ya existía:

```csharp
// BranchTypeTests.Los_recomendados_DOS_VECES_no_fallan_ni_duplican
Assert.Equal(3, segunda.Value!.Count);   // tres, no cero
```

Y la de al lado remata el contrato: con un tipo propio preexistente devuelve los tres
**incluyendo el suyo con su nombre original**.

**La base nunca estuvo en riesgo** —el endpoint es idempotente de verdad y eso está
probado—; lo que mentía era la pantalla. Peor aún, mi comentario en el repositorio
afirmaba el contrato equivocado, que es peor que no tener comentario.

**Cómo quedó:** `tiposNuevos(antes:, despues:)` resta contra lo que la pantalla ya tenía
cargado, comparando **por código** —la identidad que el servidor usa para saltarse los que
existen—. Y si la lista no se había podido cargar, no se inventa un número: se dice «Los
tipos recomendados ya están en tu catálogo», que es cierto en los dos casos.

Diez pruebas, y **cinco mueren** si se quita la resta.

> **Lo que esto enseña, y no es sobre tipos de sucursal:** el contrato de un endpoint se
> **lee**, no se supone, y la prueba que lo fija ya existía en el otro repositorio. Lo
> cazó una pregunta en una revisión —«¿qué prueba lo cubre?»— que no tenía respuesta.

### ✅ Cuatro ajustes menores del «Próximamente» — HECHOS (ver el cierre más abajo)

**Los cuatro se hicieron el 18 de octubre de 2026** y el encabezado se quedó en
«pendientes». El cierre está unas líneas más abajo. La tabla se conserva porque explica
*por qué* cada uno estaba mal, que es lo que no se puede reconstruir después.

Salieron de revisar Empresa y Puestos en pantalla. **Ninguno bloqueaba nada**, y los
cuatro vivían en el mismo sitio —`_Proximamente` y `RisegTabs`—, así que se hicieron
juntos.

| | Qué está mal | Qué lo arregla |
|---|---|---|
| 1 | El ícono de **Puestos** es el mismo edificio que el de Empresa | `_Proximamente` recibe `apartado.icono`, así que **todas** las pestañas de Organización salen con el icono del apartado. Hay que darle ícono propio a la pestaña: `PestanaDeApartado` gana un `icono`, y el aviso usa el de la pestaña cuando lo tiene |
| 2 | Dice **«Este apartado…»** estando en una pestaña | Debe decir **«Esta sección…»**. `_Proximamente` tiene que saber qué es lo que se abrió; hoy no lo sabe porque recibe sólo título e ícono |
| 3 | Las pestañas no mudadas **no se distinguen hasta abrirlas** | Ver la propuesta de abajo |
| 4 | El rastro en Tipos de sucursal | Debe decir **«Organización › Sucursales › Tipos de sucursal»**. La causa y las dos salidas están en la deuda de más arriba |

#### Cómo marcar una pestaña no mudada, propuesta

**El camino que NO sirve:** el ícono de `RisegTabItem`. `RisegTabs` lo pinta **encima** del
texto, así que marcar sólo dos pestañas las haría **más altas** que el resto y
desalinearía la barra. Es por lo que no se marcó en su momento.

**La propuesta:** `RisegTabItem` gana un `atenuada` **opcional**, y `RisegTabs` pinta ese
`Tab` con `child: Text(...)` en un gris más claro en vez de dejar que el `TabBar` le
aplique el color de siempre. Mismo alto, misma tipografía, misma barra — sólo el tono.

Dos detalles que no se deben pasar por alto:

- **Atenuar es relativo al estado, no absoluto.** Un `TabBar` pinta la seleccionada con
  `labelColor` y las demás con `unselectedLabelColor`. Si la atenuada se fija a un gris
  fijo, al seleccionarla se quedaría gris clarito sobre el subrayado azul y parecería
  deshabilitada. Tiene que atenuar **sobre** el color que le tocaría.
- **`enabled: false` no vale aquí.** La pestaña **sí** se abre: su contenido es el aviso
  amable. Deshabilitarla dejaría al usuario sin saber qué hay dentro, que es justo lo que
  el aviso viene a contar.

Y es el mismo criterio que el menú lateral, que usa una **segunda línea** en gris en vez de
una insignia al lado: discreto, y sin robarle ancho al nombre.

### ✅ Puestos web y los cuatro ajustes del «Próximamente» (18 de octubre de 2026)

Con esto **Organización sólo espera Empresa**: Sucursales, Puestos y Áreas tienen
pantalla.

#### Lo que el servidor permite, y lo que por tanto no se edita

| | |
|---|---|
| Crear | `areaId`, `code`, `name`, `kind`, **`hierarchyLevel` obligatorio**, `description` opcional |
| Editar | **sólo** nombre, estado, descripción y nivel |
| **NO se edita** | **código, área y tipo** — *«no existen en el contrato»*, **y la base lo respalda con un disparador** |

La razón es del servidor y la pantalla la repite donde se ve: *«son identidad y
configuración estable de una fila que va a ser referenciada por historia laboral»*. De
ahí la línea bajo los tres campos en gris:

> Para cambiar el área o el tipo de un puesto, desactívalo y crea otro: su historia
> laboral ya lo referencia.

#### El código se sugiere, como en el escritorio

`PUE-0001`, `PUE-0002`… El formato sale de `seed_data.dart`, donde el renglón del puesto
es `('puesto', 'PUE', 4)`. Editable, con la ayuda «Se sugiere automáticamente. No se
podrá cambiar».

**Es el máximo más uno, no el primer hueco.** Con `PUE-0001` y `PUE-0003` sugiere
`PUE-0004`: rellenar el hueco reutilizaría un número que alguien pudo imprimir, decir
por teléfono o meter en una hoja de cálculo.

Y cuatro cosas que no rompen, cada una con su prueba: los códigos escritos a mano se
ignoran para la cuenta; pasado el 9999 crece a cinco dígitos en vez de volver a
empezar; la comparación es **numérica** —por texto, `PUE-10000` quedaría antes de
`PUE-9999` y la sugerencia retrocedería—; y **si los puestos no se pudieron leer no se
sugiere nada**, porque un `PUE-0001` inventado chocaría con el primero que ya existe.

#### El nivel, como lista de diez

Del 1 al 10, **y el 1 es el más bajo** — lo dice el propio servidor al rechazar un alta
sin nivel. Sólo los extremos se anotan: «1 · el más bajo», «10 · el más alto».

Una lista no admite un valor inválido, no obliga a teclear, y **enseña la escala antes**
en vez de dejar que se aprenda por un mensaje de error.

> ⚠️ **Y UN NIVEL NULO NO ES CERO.** La columna es opcional en la base —hay puestos de
> antes de que el campo existiera— y la ruta sólo lo exige **al crear**. La lista los
> muestra como **«sin nivel»** en una pastilla ámbar, nunca como «N0», y al editar se
> permite guardar sin ponerlo: corregir el nombre de un puesto viejo no debe forzar a
> inventarle una jerarquía.

#### Las áreas del selector: sólo activas

Y al editar, también la del puesto aunque esté inactiva — ocultarla haría pensar que el
puesto no tiene área.

> ⚠️ **ESTO LO DECIDE EL CLIENTE, NO EL SERVIDOR.** Medido: el servidor **aceptaría** un
> área inactiva, porque sólo valida que exista. Hay prueba de «área inexistente» y
> **ninguna de «área inactiva»**. Archivar un puesto bajo un área fuera de uso es lo
> contrario de lo que el catálogo quiere, así que el cliente no la ofrece.

Sin ninguna área activa **no se apaga el botón**: un diálogo explica qué falta y lleva a
la pestaña Áreas. Quien decide qué pestaña está abierta es el portón, así que la
pantalla **pide** el cambio con un callback; no navega por su cuenta.

#### Los cuatro ajustes

| | Cómo quedó |
|---|---|
| **Ícono propio por pestaña** | `PestanaDeApartado` gana `icono`, y el aviso usa el de la pestaña. Antes todas salían con el del apartado y Puestos enseñaba el mismo edificio que Empresa. Dos pruebas: ninguna pestaña repite el ícono de otra, **ni el de su apartado** |
| **«Esta sección» / «Este apartado»** | El aviso sabe qué se abrió. Llamarle «apartado» a una pestaña es llamarle a la parte como al todo, y quien lee se pregunta si falta Puestos o Organización entera |
| **La pestaña no mudada se atenúa** | `RisegTabItem` gana `atenuada`. **Mismo alto, misma tipografía, sólo el tono** — como la segunda línea gris del menú |
| **El rastro baja tres niveles** | «Organización › Sucursales › Tipos de sucursal» |

**Por qué la pestaña no se marca con el ícono:** `Tab` lo pinta **encima** del texto, así
que marcar sólo algunas las haría más altas y desalinearía la franja.

**Y la atenuación es relativa, no un gris fijo.** Un `TabBar` pinta la seleccionada y las
demás con colores distintos; con un gris absoluto, al seleccionar la atenuada se quedaría
clarita sobre el subrayado azul y parecería deshabilitada. Se atenúa **sobre** el color
que le tocaría. Tampoco se usa `enabled: false`: la pestaña **sí** se abre, y su
contenido es justo lo que explica qué va a haber ahí.

**El tercer segmento del rastro necesitó una vía hacia arriba**, porque Tipos de sucursal
no es una pestaña: vivía dentro de Sucursales con un `bool` local, y la pantalla avisaba
con un callback desde un solo método —`_verTipos`— para que no se pudiera cambiar el
estado sin avisar.

✅ **ESA VÍA YA NO EXISTE** (D-39, cerrada el 26 de octubre de 2026): lo de dentro es una
**dirección** —`/organizacion/sucursales/tipos`— y el rastro **se deriva** de ella. La vía
estaba bien escrita y lo que estaba mal era que existiera: quien sabe dónde estás es la
dirección, no un aviso que alguien tiene que acordarse de mandar. El detalle y las cuatro
reglas que quedaron, en `diseno-router-web.md` §10.

## 🔁 EL MÉTODO DE LA MUDANZA — regla desde el 18 de octubre de 2026

**Por apartado, en este orden, y no se empieza otro con uno abierto.**

| | Paso | Qué significa |
|---|---|---|
| **1** | **INVESTIGAR** | Todo lo que RISEG ONE hace en ese apartado: pantallas, botones, reglas, validaciones, cálculos, **efectos automáticos** —como crear el almacén al crear una sucursal—, permisos y auditoría. Y **con qué otros apartados se conecta**. Con **archivo y línea**, siempre. **Incluye el MAPA DE PERMISOS POR ACCIÓN** (ver abajo) |
| **2** | **REVISAR** | El dueño decide **renglón por renglón**: se trae igual · se mejora · **no se trae, a sabiendas**. Lo que no se trae queda escrito como decisión, nunca como olvido. **El mapa de permisos se aprueba AQUÍ, antes de programar** |
| **3** | **CONSTRUIR** | Completo: servidor + web + **una prueba por renglón** |
| **4** | **COMPROBAR** | La lista contra el escritorio, y el dueño prueba en pantalla |
| **5** | **CERRAR** | Commit y despliegue al ensayo |

**Un apartado no se da por terminado hasta que cada renglón de su inventario funciona en
la nube con su prueba.**

Y la aprobación paso a paso se reserva para **dinero, sueldos, permisos, migraciones y
despliegues**. En catálogos y pantallas de bajo riesgo se construye y se revisa al final,
por apartado. La suite completa corre **antes de cada commit**, sin excepción.

> **Por qué este método y no el anterior.** Las primeras etapas se diseñaron pantalla por
> pantalla, y eso produjo dos cosas malas: mucho ir y venir por cada detalle, y —peor— que
> una función del escritorio se descubriera **después** de dar algo por hecho. El efecto
> automático de la sucursal es el ejemplo: la pantalla web quedó aprobada y sólo al
> inventariar apareció que el escritorio crea **tres** filas y la web una.

### 🚫 NADA «PARA DESPUÉS» DE LA PANTALLA QUE SE ESTÁ TOCANDO

**Regla desde el 19 de octubre de 2026.**

**Si una mejora es de la pantalla o del módulo que se está trabajando, se hace EN ESE
MISMO BLOQUE.** No se anota, no se aplaza, no se deja «para pulir luego».

**Sólo se anota como pendiente lo que depende de algo QUE TODAVÍA NO EXISTE** —una ruta
sin construir, una tabla sin migrar, un módulo sin mudar—, y **siempre nombrando el
apartado donde se construirá**. Un pendiente sin dueño ni sitio no es un pendiente: es un
olvido con buena letra.

**Por qué.** Un «para después» de la pantalla abierta cuesta tres veces: hay que volver a
entender la pantalla, volver a probarla y volver a revisarla en pantalla con el dueño. Y
mientras no se hace, el módulo figura como cerrado **estándolo a medias** — que es
exactamente lo que el paso 5 del método promete que no pasa. El historial de este
proyecto lo confirma: los «cuatro ajustes menores del Próximamente», la ayuda del código
repetida en tres sitios y el nombre que faltaba en la auditoría salieron todos de
aplazamientos de una sola pantalla, y los tres costaron más al volver que al hacerlos.

**Cómo se aplica al revisar un pendiente ya escrito:** si es de un apartado ya tocado, se
hace ahora; si depende de algo inexistente, se le pone apartado y se queda. Lo que no
puede quedarse es un pendiente de una pantalla que ya funciona.

### 🔑 EL MAPA DE PERMISOS POR ACCIÓN, APROBADO ANTES DE PROGRAMAR

**Regla desde el 21 de octubre de 2026.**

**El inventario de cada módulo lleva una tabla de acción → permiso, y el dueño la aprueba
en el paso 2.** No al final, no al revisarlo en pantalla: antes de escribir la primera
ruta.

| Acción | Permiso | Operación |
|---|---|---|
| ver la lista | `modulo.ver` | lectura |
| crear | `modulo.crear` | mutación |
| corregir | `modulo.modificar` | mutación |
| desactivar / reactivar | `modulo.archivar` | mutación |
| eliminar físicamente | Maestro **+** `modulo.archivar` | mutación |
| leer datos sensibles | permiso propio | lectura |

**Antes de proponer un permiso nuevo, se consulta `app.platform_permission` en la base.**
No el código: **la tabla**. Las constantes de C# y de Dart son espejos y pueden estar
incompletos —lo estuvieron—, así que «no existe un permiso para esto» sólo se afirma
después de mirar la tabla.

**Por qué, y cuánto costó.** Pasó dos veces en el mismo día, el 21 de octubre de 2026:

1. **Las siete lecturas de Organización no exigían ningún permiso.** Un usuario con rol
   Usuario y cero permisos leía el expediente fiscal completo —razón social, RFC,
   representante, domicilio— y las listas de sucursales, puestos y áreas. Las escrituras
   estaban bien cerradas desde el principio; las lecturas nunca se decidieron. Lo
   descubrió el dueño mirando la pantalla, que es el peor sitio.
2. **Se propuso una migración para crear cuatro permisos que YA EXISTÍAN.** La sección
   «core» de `PermissionCode` declara dos constantes, y de ahí se concluyó que el
   catálogo tenía dos. La tabla tenía diez, y cuatro eran exactamente los que hacían
   falta: `organizacion.ver`, `.crear`, `.modificar` y `.archivar`, sembrados por la 0022
   y **sin que ninguna ruta los leyera**. Estaban en la tabla, salían en la pantalla de
   permisos, se podían conceder, y no gobernaban nada. Lo cazó el dueño al ver diez
   permisos en una pantalla donde se le habían dicho dos.

Las dos cosas se evitan con la misma tabla aprobada por adelantado: la primera porque
obliga a nombrar el permiso de **cada** acción —incluida la de leer—, y la segunda porque
rellenarla exige mirar el catálogo real.

### 🤖 LA MATRIZ DE PERMISOS ES GENÉRICA: UNA RUTA NUEVA SE CUBRE SOLA

**Regla desde el 21 de octubre de 2026.**

**Cada ruta DECLARA lo que exige, y la prueba de matriz se genera de esas declaraciones.**
Ya no hay lista de rutas escrita a mano.

```csharp
grupo.MapGet("/areas", ListarAreasAsync)
    .ExigePermiso(CompanyOperation.Read, PermissionCode.OrganizacionVer);

grupo.MapDelete("/areas/{areaId:guid}", EliminarAreaAsync)
    .ExigeMaestroY(CompanyOperation.Mutation, PermissionCode.OrganizacionArchivar);

grupo.MapGet("/logo", LeerLogoAsync)
    .ExigeSoloAcceso(CompanyOperation.Read, "ver el logo de tu propia empresa no es una capacidad que nadie delegue");
```

Y el grupo del módulo se marca **una vez**:

```csharp
var grupo = app.MapGroup("/companies/{companyId:guid}")
    .AddEndpointFilter<RequireIdentityFilter>()
    .DeclaracionObligatoria();
```

**Lo que eso compra, y es el punto entero:**

- una ruta que **declara** queda probada sola —cero permisos → 403, un permiso ajeno →
  403, el permiso correcto → no deniega— **sin tocar el archivo de pruebas**;
- una ruta que **no declara** rompe el guardia, con su nombre en el mensaje de error;
- «sin permiso» exige **escribir la razón**, así que deja de ser el estado por omisión de
  una ruta que nadie revisó. Era exactamente el estado de las siete lecturas.

**Por qué funciona sin inventar cuerpos de petición:** la autorización corre **antes** de
la validación, así que un 403 tiene que ocurrir con el cuerpo vacío. La matriz manda `{}`
a todas las rutas e ids inventados a todo menos al `companyId`, y en el caso «con el
permiso correcto» no exige 200 sino **que no sea una denegación** —un 400 de validación ya
demuestra que la autorización dejó pasar—.

**Lo que la matriz NO puede comprobar, y necesita su prueba nombrada:** cuando el permiso
depende del **cuerpo**. En Organización, el mismo `PATCH` corrige el nombre
(`organizacion.modificar`) y mueve el interruptor (`organizacion.archivar`), y una
petición que cambie las dos cosas exige los dos. La declaración dice el **suelo** —lo que
exige con el cuerpo vacío— y la regla de negocio va aparte.

### ❓ UNA PREGUNTA NO DETIENE EL TRABAJO

**Regla desde el 19 de octubre de 2026.**

Cuando haya que preguntar algo al dueño, **se sigue avanzando con todo lo que no dependa
de esa respuesta**. Y la pregunta va **al principio del mensaje**, con el encabezado
**«NECESITO TU DECISIÓN»**, para que no se pierda entre el resto del informe.

**Por qué.** Pasó: se preguntó de dónde debía salir el estado del servidor para el aviso
del 409 —dos opciones, con recomendación— y el trabajo quedó parado esperando, teniendo
al lado dos tareas de Configuración ya decididas y sin ninguna dependencia. La pregunta
era correcta; detenerse no. Y enterrada al final de un informe largo, una decisión
pendiente **se le pasa al dueño**, que es la otra mitad del problema.

**Las dos mitades de la regla:**

1. **Avanzar en paralelo:** lo que no depende de la respuesta se construye mientras se
   espera. Si *todo* depende de ella, se dice explícitamente que no hay nada que adelantar.
2. **La pregunta, visible:** al principio, con su encabezado, con las opciones y con una
   recomendación. Nunca «¿qué prefieres?» a secas.

---

## 🗺️ EL MAPA DE DEPENDENCIAS DEL ESCRITORIO

Medido siguiendo los `import` reales de los **18 módulos**, no por memoria. `D` es el
número de imports de **dominio o datos** —los que de verdad atan— frente a los de
presentación, que suelen ser un widget o una etiqueta.

### Lo primero que hay que entender: **no hay ningún módulo hoja**

Los 18 importan a otro. **Un orden topológico no existe**, así que el orden de migración
no sale del grafo solo: sale de cortar ciclos a propósito.

### De quién dependen los demás

| Módulo | Lo usan | Usa | Archivos |
|---|---|---|---|
| **usuarios** | **17** | 6 | 58 |
| **organizacion** | **16** | 10 | **326** |
| **finanzas** | 13 | 13 | 180 |
| **personal** | 12 | 10 | 84 |
| dashboard | 11 | 11 | 15 |
| inventario | 11 | 8 | 91 |
| telefonia | 7 | 7 | 77 |
| compras · nomina · vehiculos | 6 | 5 · 9 · 7 | 23 · 47 · 63 |
| **reportes** | 5 | **12** | 78 |
| tiempos_extra | 5 | 5 | 20 |
| descuentos_personal · notificaciones · servicios_eventuales | 4 | 7 · 4 · 5 | 24 · 14 · 42 |
| boveda · respaldo | 1 | 2 · 1 | 19 · 36 |
| busqueda | **0** | 7 | 18 |

### Las aristas que de verdad atan (dominio/datos)

```
personal              → organizacion          31 archivos, D43   ← la más pesada del producto
reportes              → finanzas              19 archivos, D33
servicios_eventuales  → finanzas              19 archivos, D33
telefonia             → inventario            20 archivos, D23
servicios_eventuales  → organizacion          14 archivos, D22
compras               → finanzas              11 archivos, D19
finanzas              → organizacion          29 archivos, D17
tiempos_extra         → finanzas               9 archivos, D15
telefonia             → finanzas               8 archivos, D15
compras               → inventario            12 archivos, D15
vehiculos             → finanzas               8 archivos, D14
```

### El orden que sale de ahí

| # | Apartado | Por qué ahí |
|---|---|---|
| **1** | **Organización** (estructura + empresa) | 16 módulos dependen de él y nada estructural depende de los demás. Es el suelo |
| **2** | **Usuarios y permisos** | 17 lo usan, pero es **transversal, no de datos**: ya está hecho |
| **3** | **Personal** | `D43` contra Organización, y nada más pesado. Después de 1, su dependencia está servida |
| **4** | **Comercial** (clientes, servicios, contratos) | `servicios_eventuales → organizacion D22` se resuelve con 1; su atadura a finanzas es de **cobro**, que es 5D.11 |
| **5** | **Finanzas** | 13 lo usan, pero **usa 13**: es el nudo. Va después de que sus proveedores —Organización, Personal, Comercial— estén |
| **6** | Nómina · Tiempos extra · Descuentos | Los tres cuelgan de Personal **y** de Finanzas |
| **7** | Inventario → Compras → Telefonía → Vehículos | Cadena propia: `telefonia → inventario D23`, `compras → inventario D15` |
| **8** | **Reportes** | Usa **12**. Es el agregador: va último por definición |
| **9** | Dashboard · Búsqueda · Notificaciones | Leen de todos. Al final, y son los más baratos |
| — | **Bóveda y Respaldo** | **No se mudan**: son del producto de escritorio, donde los datos viven en el disco de quien los usa |

---

## 🧬 ORGANIZACIÓN: EL CICLO DE VIDA — eliminar, desactivar, cerrar (esquema 49)

Lo que cierra el punto 1 del [inventario de Organización](inventario-organizacion.md).
Aquí sólo queda lo que hay que **saber para no romperlo**; el detalle renglón por renglón
está allá.

### Las dos salidas, y por qué no se colapsan

| Si la fila… | La salida es | El servidor contesta |
|---|---|---|
| **nunca se usó** | **eliminar**, con motivo y sólo el Maestro | el borrado |
| **ya se usó** | **desactivar**: la fila se queda | **409 `estructura_en_uso`** con el conteo |
| **tiene algo ACTIVO colgando** | mover a la gente, o cerrar primero | **409 `desactivacion_bloqueada`** con el conteo |

**Dos códigos distintos a propósito.** La pantalla tiene que poder ofrecer la acción
correcta sin leer el texto del mensaje: uno lleva a «desactívalo» y el otro a «mueve a la
gente» o «ciérrala primero». Mandar a alguien a la acción equivocada cuesta un viaje
entero.

### La asimetría que no se debe «simplificar»

**Borrar cuenta TODO, desactivar cuenta sólo lo ACTIVO.**

- Un **puesto archivado** impide **borrar** su área, y **no** impide desactivarla.
- Una **asignación cerrada** impide **borrar** el puesto, y **no** impide desactivarlo.

No es una incoherencia: borrar es definitivo, así que «nunca se usó» significa **nunca**.
Igualar las dos consultas es el atajo que parece una limpieza y rompe la regla.

### Por qué la 0049 revierte una decisión de la 0011

La 0011 negaba el `DELETE` **a propósito**, y tenía razón para la fila que ya se usó.
Faltaba el otro caso: un área capturada con un error de dedo no es historia de nada, y
obligar a dejarla inactiva para siempre llena el catálogo de basura que nadie puede
limpiar.

Se puede conceder porque **las seis FK son `ON DELETE RESTRICT`**: el `RESTRICT` dejó de
ser la prohibición y pasó a ser **la red**. La regla no depende de un `if`.

Y **la auditoría sobrevive al borrado**, que es lo que lo hace aceptable:
`audit_event.entity_id` no tiene FK, así que el evento con el motivo y la instantánea
queda para siempre aunque la fila no.

### 🚫 LO QUE NO SE REINTERPRETA

1. **El motivo es obligatorio siempre**, y tope **500** — no es una cifra redonda:
   `AuditPayload` **lanza** por encima de 512, así que un motivo largo convertiría un
   borrado legítimo en un error 500.
2. **La instantánea va en `before`, nunca en `after`.** Después del `DELETE` no hay un
   «después» de esa fila.
3. **Borrar es de Maestro, y no es un permiso.** Un permiso se delega por plantilla;
   eliminar definitivamente no. Y **tampoco es un permiso protegido**, que sería lo
   contrario de lo que hace falta: un protegido **no** se autoconcede al Maestro.
4. **`operationalStatus` no vuelve al `PATCH`.** Cerrar temporalmente es una transición
   de negocio con confirmación; mientras viviera en el cuerpo del `PATCH`, la disciplina
   dependería de que la pantalla se portara bien.
5. **El `CHECK` prohíbe `inactiva` + `operando` y NO prohíbe `activa` +
   `cerrada_temporalmente`.** La segunda combinación es legítima y es la razón de ser de
   la columna.
6. **«Activo» se deriva de un periodo laboral abierto**, nunca de una columna de estado.
   Contar sólo `employee_assignment.ended_on IS NULL` bloquearía un puesto para siempre
   por gente que ya se fue.

### ⚠️ EL RIESGO DE LA 0048 QUE NADIE HABÍA VISTO

La 0048 añadió `operational_status` con **`DEFAULT 'operando'`**, y un `DEFAULT` se aplica
a las filas que **ya estaban**. Así que toda sucursal que estuviera `inactiva` antes de la
0048 quedó contradictoria **en el instante de aplicarla**, sin que nadie hiciera nada.

Hoy no se nota —`dev` y el ensayo están en 48 con cero sucursales inactivas, medido antes
de escribir la migración—, pero con datos de un cliente real sí se habría notado: el
`CHECK` de la 0049 **habría abortado el despliegue**.

Por eso la 0049 hace, **en una sola transacción y en este orden**: auditar → `UPDATE` →
`GET DIAGNOSTICS` con `RAISE NOTICE` del número → y **sólo entonces** el `CHECK`. La
transacción es lo que garantiza que no se falle a medias: si algo revienta, el esquema
sigue siendo 48.

🔖 **La lección que se queda:** una columna `NOT NULL DEFAULT` sobre una tabla con datos
**puede crear una fila que una restricción futura prohíba**, y no se ve al escribir la
migración que la añade — se ve dos migraciones más tarde. Cuando una migración añade un
`CHECK` que cruza dos columnas, hay que preguntarse qué valor recibieron las filas viejas.

### La prueba que esto exige

El camino **incremental 48 → 49**, y además **montando la fila prohibida a mano** aunque
hoy no exista en ninguna base. Se verificó por mutación: quitando el `UPDATE` de la
migración, las dos pruebas correctas mueren con
`check constraint "branch_inactiva_exige_cierre" ... is violated by some row` — que es
exactamente el fallo que se habría visto en el despliegue.

---

## 🏢 LOS DOS EXPEDIENTES: EMPRESA Y SUCURSAL (esquema 50)

Lo que el escritorio llama «datos de la empresa» y «datos de la sucursal». Diseño
aprobado por el dueño el 19 de octubre de 2026, con cuatro puntos resueltos antes de
programar.

### Qué trae cada uno

**Empresa:** razón social, RFC, representante legal, eslogan, régimen fiscal,
domicilio y contacto (teléfono, correo, sitio).

**Sucursal:** domicilio y horario semanal.

### Las cinco decisiones que gobiernan

**1 · El domicilio es VERBATIM.** `company_address` y `branch_address` son la quinta y
la sexta copias literales del mismo diseño, con los mismos tres `CHECK`. La razón está
en la 0019 y no ha cambiado: «cuatro direcciones del mismo sistema que validaran
distinto serían un defecto, no una flexibilidad». Hay una prueba que **compara las seis
contra `service_address` columna por columna**, en lugar de afirmar una lista de
nombres — así sigue valiendo cuando llegue la séptima.

**2 · El horario admite VARIOS tramos por día**, y esto el escritorio **no podía
expresarlo**: allá el horario es siempre exactamente siete días, uno por valor de
`diaSemana`, así que una oficina que abre 9–14 y 16–20 no caía en el modelo. La forma
se copia de `term_schedule`, que ya resolvió el problema: `branch_schedule` guarda los
tramos y un disparador proyecta la **semana canónica** en `branch_schedule_span`, donde
un `EXCLUDE` con GiST impide el solape. El rango es **medio abierto** (`'[)'`), así que
un bloque que termina a las 14:00 y otro que empieza a las 14:00 **coexisten**.

🔖 **El error que el dueño cazó con una pregunta.** La primera versión llevaba
`UNIQUE (branch_id, day_of_week)`. Él preguntó si se podían tener dos tramos en un
mismo día; `term_schedule` **no tiene ese único**, así que la tabla nueva habría sido
**menos capaz que su propia hermana**. Una pregunta encontró lo que ninguna prueba
habría encontrado, porque todas las pruebas que había pasaban.

**3 · El catálogo de regímenes es de PLATAFORMA y de sólo lectura.**
`platform_fiscal_regime` se siembra y se actualiza **por migración**, sin RLS y con
`GRANT SELECT` únicamente — hay prueba de que `seventra_app` **no** tiene `INSERT`,
`UPDATE` ni `DELETE`. Si una empresa pudiera escribirla, podría inventarse un régimen o
retirarle el suyo a otra.

**La regla opuesta a `branch_type`, y hay que saber por qué.** En los tipos de sucursal
se bloquea desactivar uno en uso, porque ese catálogo es **del cliente** y retirar algo
en uso es un error suyo. Aquí el catálogo es de una **autoridad externa**: el SAT retira
regímenes por su cuenta, y bloquearlo haría imposible reflejar la realidad. Así que un
régimen retirado **deja de poder elegirse** y **la empresa que lo tenía lo conserva** —
su tarjeta fiscal sigue diciendo la verdad.

**4 · El filtro por RFC avisa, NO bloquea.** Doce caracteres es persona moral, trece es
persona física, y el catálogo se filtra en consecuencia. Pero un RFC de otra longitud
—o uno que todavía se está escribiendo— **no vacía la lista**: devuelve todo. Un filtro
que bloqueara escondería un régimen legítimo, y la persona no tendría forma de saber por
qué no aparece.

**5 · El `codigo` de la empresa NO SE TRAE, a sabiendas.** Decisión del dueño. En el
escritorio la empresa tiene un código humano; en la nube la empresa **ya es** el límite
de aislamiento y su identidad es el `company_id`. Un código más sería un segundo nombre
sin dueño que mantenerlo.

### El control optimista: lo primero en todo el sistema

`company.profile_version` y `branch.profile_version` se leen al abrir y se mandan al
guardar; si no coinciden, **409 `expediente_desactualizado`**.

Hizo falta **medirlo** para creerlo: antes de la 0050 **no había concurrencia optimista
en ninguna parte** del backend — sólo `FOR UPDATE`. Y `FOR UPDATE` **no puede** arreglar
esto, porque el hueco no está dentro de una transacción: está **entre dos peticiones**.
Ana abre el expediente, Beto abre el mismo, Ana guarda, Beto guarda — y el trabajo de
Ana desaparece sin que ningún bloqueo se haya tocado.

### ⏳(D-38) DEUDA: las demás rutas de reemplazo tienen el mismo hueco

Anotada a petición del dueño, el 19 de octubre de 2026.

Todo camino que **reemplace una colección completa** —no sólo los expedientes— pierde
la escritura de quien guardó primero, sin avisar a nadie. Hoy eso aplica a las rutas que
borran e insertan de nuevo: las condiciones comerciales, las líneas de una suscripción,
las asignaciones. Los dos expedientes ya están cubiertos; **las demás no**, y la
corrección es la misma pieza (`*_version` + 409) repetida.

No se arregla ahora porque tocaría varios módulos cerrados a la vez, y el método dice
una etapa a la vez. Queda escrito para que no se descubra con un cliente.

### ⚠️ LA SIEMBRA DEL CATÁLOGO DEL SAT HAY QUE VERIFICARLA

**Los diecinueve regímenes y sus banderas `persona_fisica` / `persona_moral` se
escribieron de memoria, no se copiaron de la fuente oficial.** La migración lo dice en
un comentario, y aquí queda por si el comentario se pierde de vista.

Por qué importa y no es una formalidad: una bandera equivocada **esconde un régimen
legítimo** de la lista filtrada, y la persona que lo necesita no tiene forma de saber por
qué no aparece — el filtro avisa en lugar de bloquear precisamente para que un error así
no impida guardar, pero el régimen correcto seguiría sin estar.

**Antes de producción:** comparar `platform_fiscal_regime` contra el catálogo
`c_RegimenFiscal` publicado por el SAT, y corregir con una migración nueva. Las pruebas
**no lo detectarán**: están escritas para no fijarse a una lista exacta (acotan con
`>= 15` y afirman la propiedad de que ningún régimen quede sin aplicar a nadie), que es
lo correcto para que el catálogo pueda crecer, pero significa que la exactitud de los
datos es una revisión humana.

### ✅ La siembra del SAT, verificada el 19 de octubre de 2026

**Resultado: las diecinueve claves, los diecinueve nombres y las treinta y ocho
banderas coinciden.** Se escribió de memoria y después se comparó fila por fila contra
**dos catálogos de terceros independientes** que coinciden entre sí, los dos sobre la
misma versión: CFDI 4.0, publicado el 01/01/2022, vigente sin fecha de fin.

**Lo que NO se pudo leer** es el archivo del SAT mismo: el catálogo oficial vive como un
`.xls` colgado de la página del Anexo 20 y no se puede abrir con las herramientas de
aquí. Así que el riesgo que queda es estrecho y concreto —**que las dos fuentes de
terceros copien el mismo error del original**— y ya no es «esto salió de la memoria de
alguien». Quien tenga el `.xls` a mano puede cerrarlo en diez minutos.

Las que más convenía mirar, por si alguien las revisa a mano, son las de **persona
moral**: `601`, `603`, `620`, `622`, `623` y `624`. Y las dos que aplican a **las dos**:
`610` (residentes en el extranjero) y `626` (RESICO).

### Por qué el régimen es un CATÁLOGO y no un texto libre

Decisión del dueño, 19 de octubre de 2026, y la razón es la que manda sobre cualquier
comodidad: **un error de captura saldría en la tarjeta fiscal y haría que rechacen
facturas.** Un campo de texto libre convierte un dato con lista cerrada en un dato que
depende de quien teclea, y el costo no lo paga quien lo escribió.

### ⏳(D-35) PENDIENTE: mantener el catálogo desde Console, sin migración

Requisito del dueño, 19 de octubre de 2026. **Hoy cada cambio del SAT es una migración
nueva**, es decir: un programador, un despliegue y una ventana. Eso no puede ser el
camino permanente para una lista que una autoridad externa cambia cuando quiere.

**Lo que se pide:** agregar un régimen nuevo y retirar uno existente desde Console, sin
migración y sin programador, **igual que los planes**.

Y tres condiciones que no son opcionales:

- **Permiso de PLATAFORMA, no de empresa.** El catálogo es de SEVENTRA y lo comparten
  todos los inquilinos; ninguna Company lo edita. Hoy la tabla no tiene RLS y
  `seventra_app` sólo tiene `SELECT` —hay prueba de que no tiene `INSERT`, `UPDATE` ni
  `DELETE`—, así que la pantalla de Console necesitará su propio camino, no el rol de la
  aplicación. Si una empresa pudiera escribir aquí, podría inventarse un régimen o
  retirarle el suyo a otra.
- **Auditoría.** Agregar o retirar un régimen afecta a **todas** las empresas a la vez,
  así que tiene que quedar escrito quién lo hizo y cuándo. Es un hecho de plataforma, no
  de una Organization: le corresponde `security_event`, que existe exactamente para eso
  y no lleva `organization_id`.
- **Retirar NO es borrar.** La regla ya está construida y no cambia: un régimen retirado
  pasa a `inactiva`, deja de poder elegirse y **la empresa que lo tenía lo conserva**. La
  pantalla de Console no debe ofrecer un borrado físico; si lo ofreciera, la tarjeta
  fiscal de un cliente dejaría de poder nombrar su propio régimen.

**Mientras no exista**, la siembra por migración se queda como está — es lo acordado.
