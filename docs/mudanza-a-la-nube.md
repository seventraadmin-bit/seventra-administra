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
