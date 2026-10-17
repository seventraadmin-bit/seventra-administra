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

De **M3** en adelante el trabajo es siempre el mismo: **cambiar el repositorio de Drift por
uno de HTTP detrás de la misma interfaz de dominio**, sin tocar las pantallas. El cimiento
de `8fb1c49`–`d7b4132` se construyó para eso.

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
