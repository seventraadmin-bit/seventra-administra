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
