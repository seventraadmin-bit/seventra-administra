# Inventario de Organización — el apartado renglón por renglón

**Qué es este documento.** Los pasos 1 y 2 del método de la mudanza para Organización:
todo lo que RISEG ONE hace en este apartado, medido **con archivo y línea**, y la decisión
del dueño para cada renglón.

**Organización no se da por terminada hasta que cada renglón de abajo funciona en la nube
con su prueba.**

> El escritorio **no se toca**: es la referencia. Todo lo que dice «archivo:línea» apunta a
> él.

---

## Lo primero: qué llamamos «Organización»

En el escritorio, `features/organizacion` tiene **326 archivos** y es el módulo más grande
del producto. Dentro viven cosas que en la nube son apartados distintos:

| En el escritorio | En la nube |
|---|---|
| Áreas · Puestos · Sucursales · Tipos de sucursal · **Empresa** · Ubicaciones | **Organización** — este inventario |
| Clientes · Servicios · Entidades fiscales · Portales · Agenda · Configuración de cobro · Líneas comerciales | **Comercial** — apartado 4 del orden |

Este inventario cubre **sólo la primera fila**. Lo demás tendrá su propio inventario cuando
le toque, y queda anotado aquí para que no se pierda entre los dos.

---

## 1 · Ciclo de vida: eliminar, desactivar, cerrar

### 1.1 Eliminación física — SE TRAE IGUAL

El escritorio la tiene para Áreas, Puestos y Sucursales (y Clientes, Servicios y Agenda,
que son de Comercial).

| | |
|---|---|
| Quién | **Sólo el Maestro**, y la protección vive en el provider — «nunca en la UI» · `eliminar_puesto_fisicamente_dialog.dart:10-14` |
| Motivo | **Obligatorio siempre, sin excepción** · `eliminar_puesto_fisicamente_usecase.dart:33-34` |
| Cómo | Validación + **instantánea** + auditoría + `DELETE`, **en una transacción** |
| Sólo si **nunca se usó** | Y rechaza **con el conteo** |

**Las validaciones exactas de un puesto** · `puesto_repository_impl.dart:78-110`:

```
vigencias comerciales → «Tiene N vigencia(s) comercial(es) registrada(s).»
usuarios              → «Tiene N usuario(s) registrado(s).»
empleados             → «Tiene N empleado(s) registrado(s).»
```

Para una sucursal: «Servicios, Ubicaciones, Empleados o cualquier otra dependencia real
descubierta en el grafo de FK» · `eliminar_sucursal_fisicamente_usecase.dart:15-18`.

> **DECISIÓN DEL DUEÑO:** se trae **igual**, con la regla **en el servidor**. Si ya se usó,
> sólo desactivar.
>
> ✅ **HECHO** en la 0049 y en las cuatro rutas `DELETE`. Y una corrección que hay que
> dejar escrita: el inventario decía que **no** hacía falta migración, y era falso. La
> 0011 niega el `DELETE` **a propósito** y lo argumenta; traerlo es revertir esa decisión,
> y eso se hace con una migración. Lo que sí resultó cierto es que el motor ya respalda la
> regla: las seis FK son `ON DELETE RESTRICT`, así que el `RESTRICT` dejó de ser la
> prohibición y pasó a ser **la red**.

### 1.2 Desactivar en cascada — dos ya existen, dos son nuevas

| Regla | ¿Existe en el escritorio? |
|---|---|
| **Área** no se desactiva con **puestos activos** | **SÍ, exacta**, y ya devuelve el conteo: `DesactivarAreaBloqueadaPorPuestosActivos(cantidad)` · `desactivar_area_usecase.dart:13-17`. «Los Puestos archivados nunca cuentan para este bloqueo» |
| Reactivar un **puesto** exige **área activa** | **SÍ en el escritorio** · `cambiar_ciclo_vida_puesto_usecase.dart:17,26`. ⚠️ **La nube NO la tenía**, y este inventario dio a entender que sí: se midió al programar y `UpdatePositionAsync` no la comprobaba. Se añadió como quinta regla |
| **Puesto** no se desactiva con **personal activo** | **NO.** «Archivar un Puesto siempre está permitido». **Nueva** |
| **Tipo de sucursal** no se desactiva si una **sucursal activa** lo usa | **NO.** En el escritorio los tipos son un **catálogo de sólo lectura**: existe `listar_tipos_sucursal_usecase` y **ningún** caso de uso de alta, edición ni ciclo de vida. **Nueva** |

> **DECISIÓN DEL DUEÑO:** las cuatro, con **leyenda y conteo**, y la regla **en el
> servidor**. Ejemplo: «No se puede desactivar: 3 personas activas tienen este puesto.
> Primero cámbialas a otro puesto.»
>
> ✅ **HECHO, y son CINCO**: las cuatro aprobadas más la de reactivar-exige-área-activa,
> que el escritorio tenía y la nube no. Todas con su conteo y su leyenda, todas en el
> servidor, todas con prueba. **Sin migración**: salen de `employee_assignment` cruzado
> con `employment_period`, `position.area_id` y `branch.branch_type_id`.
>
> Y dos motivos de rechazo **distintos**, que es lo que permite a la pantalla ofrecer la
> acción correcta sin leer el texto: **409 `estructura_en_uso`** lleva a «desactívalo» y
> **409 `desactivacion_bloqueada`** lleva a «ciérrala primero» o «mueve a la gente».

### 1.3 Sucursal: «cerrar temporalmente» y activa/inactiva — NO SE DUPLICAN

El escritorio tiene «Cerrar temporalmente / Reabrir» como **transición de negocio
explícita**, «nunca un campo silencioso del formulario de edición», y con confirmación ·
`cambiar_estado_operativo_sucursal_usecase.dart:7-9`. **No tiene «desactivar sucursal».**

El servidor tiene **los dos**, y ya trae la frontera escrita en su propio código:

> «Si una sucursal está abierta HOY. **Dos valores, no tres**: son los que el producto
> local tiene, y una cerrada para siempre se marca `inactiva`.» — `BranchOperationalStatus`

| Campo | Qué pregunta contesta | Quién lo cambia |
|---|---|---|
| `operationalStatus` · `operando` / `cerrada_temporalmente` | **¿Está abierta hoy?** | Acción de negocio con confirmación: «Cerrar temporalmente» / «Reabrir». Alguien tiene que volver a abrirla |
| `status` · `activa` / `inactiva` | **¿Sigue existiendo para el sistema?** | Desactivar: no vuelve sola. Desaparece de los selectores |

> **DECISIÓN DEL DUEÑO:** las dos, sin solaparse. **La función del escritorio no se
> pierde.**
>
> Y la pantalla las separa como el escritorio: «Cerrar temporalmente» es un **botón con
> confirmación**, no un interruptor del formulario. El interruptor Activa/Inactiva se queda
> en el panel de edición.
>
> **DECISIÓN DEL DUEÑO: desactivar una sucursal exige DOS cosas** — que esté **cerrada
> temporalmente** primero, y que **no tenga personal activo asignado**. Cada caso con su
> leyenda.
>
> Es más estricto que el escritorio, que no tiene desactivar, y es coherente: desactivar
> es la salida definitiva, así que pasar por el cierre temporal obliga a un paso
> reversible antes del irreversible.
>
> **El personal se cuenta por `employee_assignment.branch_id`**, y ahí el motor ayuda: la
> 0046 trae `CHECK ((branch_id IS NULL) <> (service_id IS NULL))`, así que sólo las
> asignaciones **administrativas** llevan sucursal. Una sucursal nunca tendrá asignado al
> personal operativo, que va por servicio.
>
> ✅ **HECHO**, y la 0049 añadió algo que no estaba en el diseño y conviene saber:
> **`CHECK (status <> 'inactiva' OR operational_status = 'cerrada_temporalmente')`**. Así
> la coherencia no depende de que cada ruta se acuerde — ni una corrección manual ni un
> script pueden dejar una sucursal inactiva que diga estar operando. La dirección importa:
> **`activa` + `cerrada_temporalmente` SÍ es legítimo**, y es la razón de ser de la columna.
>
> Y **`operationalStatus` salió del `PATCH`**: cerrar y reabrir tienen sus dos rutas
> `POST`, así que la disciplina del escritorio —«nunca un campo silencioso del formulario
> de edición»— la impone el servidor y no la pantalla.

### 1.4 ⚠️ LAS CUATRO PUERTAS — la tabla que faltaba, y por qué

Tres de las reglas de arriba **no estaban en el diseño aprobado**: aparecieron una por una
mientras se cerraba el apartado, y la tercera sólo apareció **probando en pantalla**. La
causa es que estábamos revisando reglas sueltas en vez del invariante completo.

El invariante es uno: **nada ACTIVO cuelga de un padre APAGADO.** Y tiene cuatro puertas.

| | Crear el hijo | Reasignarlo | Apagar el padre | **Encender el hijo** |
|---|---|---|---|---|
| **Puesto ← Área** | ✅ nueva | *imposible: el área es inmutable* | ✅ la tenía el escritorio | ✅ nueva |
| **Sucursal ← Tipo** | ✅ ya estaba (M3) | ✅ ya estaba (M3) | ✅ nueva | ✅ **nueva — la del dueño** |

Antes de M3 la tabla tenía **cuatro celdas vacías de siete**, y cada celda llena pasaba sus
propias pruebas en verde. **El hueco no estaba en ninguna de las cuatro puertas: estaba en
el conjunto**, y por eso ninguna prueba suelta lo iba a encontrar.

Cómo apareció cada una, porque dice qué método funciona:

| Regla | Cómo se encontró |
|---|---|
| Apagar el padre (área, tipo) | La **revisión del dueño**, que pidió las cascadas |
| Encender el hijo (puesto) | **Comparar contra el escritorio**, que la tenía |
| **Encender el hijo (sucursal)** | **PROBANDO EN PANTALLA**: cerrar → desactivar → desactivar el tipo → reactivar |
| Crear el hijo (puesto) | **Buscar las demás** después de encontrar la anterior |

> 🔖 **La regla general quedó escrita en [funciones que cruzan apartados](funciones-que-cruzan-apartados.md):**
> cuando un apartado tenga una entidad que cuelga de otra, **las cuatro puertas se revisan
> en tabla antes de cerrarlo**, y cada celda queda como «implementada», «imposible por
> diseño» o «decidida a sabiendas». Allí está la lista de dónde cuelga algo de algo en los
> apartados que faltan.

**Un caso que la regla NO debe atrapar, y está probado:** `branch_type_id` es nullable y
hay sucursales de antes de la 0048 **sin tipo**. Exigirles un tipo activo las dejaría
congeladas en inactiva para siempre, sin forma de arreglarlo desde la API.

**Y una consecuencia de cerrar las tres puertas de la sucursal:** el estado «sucursal
activa con tipo inactivo» pasa a ser **inalcanzable por la API**. Sigue existiendo en datos
—cualquier sucursal cuyo tipo se desactivó antes de la regla—, y por eso el `PATCH` sigue
validando el tipo **sólo cuando cambia**: si lo exigiera siempre, esas filas no se podrían
ni renombrar.

---

## 2 · El efecto automático: ubicación raíz y Almacén General

**Lo que hace el escritorio.** Crear una sucursal crea **tres filas en una transacción** ·
`crear_sucursal_usecase.dart:7-8` · `sucursal_repository_impl.dart:38-52`:

```
1. la Sucursal                 código SUC-####
2. el nodo RAÍZ de Ubicación   tipo «sucursal», sucursalId = la sucursal, parentId NULL
3. el Almacén General          tipo «almacen», parentId = la raíz
```

El árbol está bien diseñado: ocho tipos de nodo (`sucursal, oficina, almacen, servicio,
areaInternaServicio, taller, resguardo, bajaTemporal`), la raíz se identifica por ser «el
único nodo con `parentId IS NULL` para ese dueño», el dueño vive **sólo en la raíz** y los
hijos lo heredan subiendo por `parentId`, con **`CHECK` de tabla** que lo garantiza ·
`ubicacion_table.dart:24-35`.

### ⚠️ Y AQUÍ EL DATO QUE CAMBIA LA DECISIÓN

**Nada en todo el producto consume ese árbol.** Medido:

| Medición | Resultado |
|---|---|
| Tablas con FK a `Ubicacion`, además de su propio `parentId` | **0** |
| Columnas llamadas `ubicacionId` en todo el producto | **0** |
| Archivos de Inventario (de 91) que la mencionan | **3**, y ninguno la referencia |

Inventario localiza las cosas **por estado y por quién las tiene**, no por nodo:
`Asignacion` apunta a `empleadoId` o `servicioId` · `asignacion_table.dart:87-89`, y
`ArticuloUnidad` lleva un `estatus` —`disponible, asignado, enLavanderia, enReparacion,
pendienteDesecho, danado, perdido, baja`— · `articulo_unidad_table.dart:28-36`.

**O sea: el Almacén General es una fila que el escritorio crea y que nadie lee.** Es una
función diseñada y nunca consumida.

> **DECISIÓN DEL DUEÑO: NO se construyen ahora.** Quedan como renglón abierto con esta
> medición detrás: nadie los consume hoy.
>
> 🔖 **REQUISITO ANOTADO PARA INVENTARIO:** en RISEG **sí** se quiere llevar **inventario
> por sucursal**. Ése es el consumidor que justificará el árbol, y la decisión de si las
> existencias se manejan por **sucursal** o por **almacén dentro de la sucursal** se toma
> al mudar Inventario, con ese consumidor delante.
>
> Lo que NO puede pasar es construir la tabla antes y descubrir después que las
> existencias necesitaban otra forma.

---

## 3 · Paridad pendiente con el escritorio

| Renglón | Estado |
|---|---|
| **Códigos automáticos `ARE-####` y `SUC-####`** | ✅ **Hecho.** Los sugiere el cliente, como `PUE`: máximo + 1 —no el primer hueco—, y **nada si la lista no se pudo leer**. Una sola función, `siguienteCodigo(prefijo, …)`, en vez de tres copias. Sin consecutivo en el servidor: habría necesitado tabla, bloqueo y un sitio en el orden global de bloqueos. La contra, escrita: dos personas a la vez reciben la misma sugerencia y la segunda recibe 409 |
| **Expediente de Sucursal**: dirección principal + **horario semanal**, guardados en **una** transacción con los datos generales, y «reúne todos los errores de las tres secciones antes de fallar» · `guardar_expediente_sucursal_usecase.dart:31-35` | ⏳ **Pendiente** |
| **Expediente de Área** | ⏳ Pendiente |
| **Pestaña Empresa** (expediente de la empresa) | ⏳ Pendiente — es la única pestaña de Organización sin pantalla |
| **Expediente de Puesto**: fecha de creación y última actualización | ⏳ Parcial: la web tiene descripción, faltan las fechas |
| Árbol de ubicaciones (pantalla) | ⏳ Depende de la decisión del punto 2 |

### Lo que la web YA da y el escritorio no

No es una pérdida, es una suma, y conviene que esté escrito:

- **Tipos de sucursal administrables**: crear, editar, desactivar y «Agregar tipos
  recomendados». En el escritorio es un catálogo de sólo lectura.
- **Auditoría legible** en pantalla, con el objeto nombrado.
- **Capacidad de accesos** del plan, visible para el Maestro.

---

## 4 · Lo que Organización necesita del SERVIDOR

| Renglón | ¿Migración? | Estado |
|---|---|---|
| Eliminación física de área, puesto, sucursal y tipo: motivo, Maestro, validación de dependencias, instantánea y auditoría | **SÍ, la 0049.** El inventario decía «no» y era falso: la 0011 niega el `DELETE` a propósito, y revertir esa decisión es una migración | ✅ |
| Las cinco reglas de desactivar, con conteo | **No.** `employee_assignment.position_id` / `.branch_id` con `ended_on IS NULL` y `status='efectiva'`, cruzado con `employment_period.ended_on IS NULL`; `position.area_id`; `branch.branch_type_id` | ✅ |
| Cerrar temporalmente / reabrir, fuera del `PATCH` | No, pero la 0049 añade el `CHECK` que impide `inactiva` + `operando` | ✅ |
| Códigos automáticos `ARE-####` / `SUC-####` | **No.** Los sugiere el cliente | ✅ |
| Expediente de sucursal: dirección y horario | **SÍ**, tablas nuevas | ⏳ |
| Expediente de empresa | A medir: el servidor ya tiene `company` y su logo | ⏳ |
| Ubicación raíz y almacén | **SÍ** si se decide traerlos | 🔖 Abierto por decisión |

> «Activo» **se deriva de un periodo abierto**, nunca de una columna de estado. Es la
> invariante de Personal, y `fn_active_employee_usage` ya la usa así.
