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

> ⏳ **Deuda, y con fecha de fin:** mientras la mudanza dure habrá **dos modelos por
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

### ⏳ Tres pendientes, con su límite

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
| **M3** | Estructura *(en curso)* | áreas, puestos, sucursales, tipos | no |
| **M4** | Personal: leer | empleados, expediente | no |
| **M5** | Personal: escribir | altas, asignaciones, periodos, documentos | no |
| **M6** | Comercial | clientes, servicios, agenda | no |
| **M7** | Nómina y su periferia | nómina, tiempos extra, descuentos | **sí**, los dos últimos |
| **M8** | Activos | vehículos y telefonía, juntos | **sí** |
| **M9** | Compras e inventario | los dos, juntos | **sí** |
| **M10** | Finanzas | CxC, pagos, ingresos, egresos, cuentas | **sí — 5D.11, la etapa más grande** |
| **M11** | Eventuales | servicios eventuales | **sí — 5D.10G** |
| **M12** | Transversales | dashboard, reportes, búsqueda, notificaciones | no |

**Por qué este orden.**

**M4 y M5 van inmediatamente después de M3** porque Personal es el corazón del producto
y su backend **ya está hecho** —M1 le dio la asignación operativa y M2 el sueldo con
vigencias—. Es la mayor cantidad de producto por la menor cantidad de backend nuevo.

**M6 antes que Nómina** porque los servicios y los clientes son a quien se asigna el
personal, y 5D.10C/D ya existen en la nube.

**M7 trae el primer backend nuevo**, y es pequeño a propósito: tiempos extra y
descuentos son dos tablas y sus reglas. Conviene estrenar ahí el camino «diseñar backend
nuevo → mudarlo» antes de hacerlo con Finanzas. **Y aquí se decide dónde se componen los
recibos**, que es el requisito de arriba.

**M8 y M9 son los dos agrupamientos** de la decisión 1, cada uno con su backend
diseñado una sola vez.

**M10 es Finanzas y va casi al final** no por importancia sino porque **5D.11 no
existe** —`Terms → BillingConfiguration → BillingPreparation → documento emitido →
AccountReceivable → Payment`— y es la etapa más grande que queda del backend.

**M12 cierra**, porque dashboard, reportes y búsqueda **leen de todos los demás**:
mudarlos antes dejaría pantallas que consultan módulos que todavía viven en SQLite.

> ⏳ **La bóveda y el respaldo no están en esta lista a propósito.** El respaldo
> desaparece —respalda Cloud SQL— y queda decidir si se ofrece «exportar mis datos». La
> bóveda se rediseña fuera de la v1. Administra al 100 % **no los incluye**.

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

> ⏳ **Plantillas editables por empresa: pendiente, y a la espera de que un cliente lo
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

- ⏳ **Pantalla para enviar la invitación de alta** (paso 3). La ruta existe
  —`POST /platform/invitations`, con reenviar y revocar— y Console no la llama.
- ⏳ **Mostrar los accesos usados contra los del plan** (paso 7). La ruta existe
  —`GET /organizations/{id}/access-usage`— y Console no la llama; hoy sólo pinta
  capacidad y consumo de medidores.

### Decisión pendiente: la dirección de entrada

El botón que debería aparecer después de poner la contraseña **no se muestra** porque
`Web:SignInUrl` está vacío, y está vacío porque esa dirección todavía no existe.

Candidatas sugeridas: **`app.seventra.mx`** o **`administra.seventra.mx`**. La primera
sirve a los tres productos y la segunda nombra a uno; la diferencia importa porque esa
dirección es la que va a quedar escrita en todos los correos.

**Se decide al montar producción.** Hasta entonces, quien acepta una invitación termina
leyendo «Ya puedes iniciar sesión con tu correo y tu contraseña» y **sin ningún enlace
que seguir** — es correcto y es incómodo, y conviene que conste.

### ⏳ «¿Olvidaste tu contraseña?» en la web — REQUISITO antes del piloto

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

### ⏳ Ajuste visual pendiente del login web

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

> ⏳ **El catálogo de permisos no manda el NOMBRE DEL MÓDULO**, sólo `moduleCode`. La
> pantalla tiene un mapa de los **siete módulos** del producto para poder titular los
> grupos. No es el catálogo replicado —los permisos, sus nombres y su condición de
> protegido vienen del servidor—, pero es texto que el cliente decide. **Un código
> desconocido se muestra tal cual**, nunca se oculta: un módulo nuevo aparecería feo y
> corregible en vez de desaparecer con sus permisos dentro.

> ⏳ **La auditoría manda `action` y `entityType` en CÓDIGO.** Se traducen los
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
> ⏳ Para decirlo con número, `GET /companies/{id}/access` tendría que mandar su propio
> `protectedPermissionCount`. Son unas quince líneas en `TenancyRepository` y su DTO.

**Las pestañas no llevan marca visual de «Próximamente»**, y es una limitación del
componente, no una decisión: `RisegTabs` pinta el ícono **encima** del texto, así que
marcar sólo algunas las haría más altas que el resto y desalinearía la barra. Se abren
y se explican, que es lo acordado. Si hace falta la marca, pide un tratamiento distinto
—un sufijo en la etiqueta, por ejemplo— y se hace aparte.

#### Cómo correr la web en local

```powershell
# 1. La API, en otra ventana
$env:ASPNETCORE_ENVIRONMENT = 'Development'
dotnet run --project "C:\Users\segur\seventra-backend\src\Seventra.Api" --urls http://localhost:5080

# 2. La web
cd C:\Users\segur\riseg_control_activos
flutter run -d chrome --web-port=5301 `
  --target lib/main_web.dart `
  --dart-define=SEVENTRA_API_BASE_URL=http://localhost:5080
```

**El `--dart-define` no es opcional:** `ApiConfig` **no tiene valor por omisión** a
propósito, así que sin él la app no arranca y lo dice.

**Y el puerto 5301 tampoco es arbitrario:** es el origen que el guion de siembra deja
autorizado en `Web:AllowedOrigins:1`, y **se queda configurado**. Con otro puerto el
navegador bloquearía las peticiones por CORS y la pantalla diría que no hay conexión,
que es indistinguible de un servidor caído.

### ⏳ Deuda menor: el rastro no baja a Tipos de sucursal

Dentro de **Sucursales → Tipos de sucursal** el rastro sigue diciendo «Organización ›
Sucursales». Debería decir **«Organización › Sucursales › Tipos de sucursal»**.

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

### ⏳ Cuatro ajustes menores del «Próximamente», para el siguiente commit

Salieron de revisar Empresa y Puestos en pantalla. **Ninguno bloquea nada**, y los cuatro
viven en el mismo sitio —`_Proximamente` y `RisegTabs`—, así que conviene hacerlos juntos.

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
no es una pestaña: vive dentro de Sucursales con un `bool` local. La pantalla avisa con
un callback, y **desde un solo método** —`_verTipos`— para que no se pueda cambiar el
estado sin avisar. El portón lo **limpia al cambiar de pestaña o de apartado**: sin eso,
el rastro seguiría diciendo «Tipos de sucursal» estando en Configuración.

⏳ Lo que hará innecesaria esa vía es el router: cuando el `bool` sea una ruta hija, el
rastro saldrá de la ruta.
