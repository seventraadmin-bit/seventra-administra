# Funciones que cruzan apartados — el índice general, primera parte

**Qué es este documento y para qué sirve.** El riesgo real de mudar RISEG ONE apartado por
apartado no es olvidar una pantalla: una pantalla que falta se ve. El riesgo es **mudar un
apartado y dejar sin conectar lo que hacía por otro**, porque eso no se ve hasta que alguien
lo necesita, y a veces ni entonces.

Este documento es la lista de esas conexiones, **medida sobre el código del escritorio**, no
recordada. La segunda parte del índice general —el catálogo apartado por apartado— se
escribe cuando a cada apartado le toque su inventario.

> El escritorio **no se toca**: es la referencia. Todo lo que dice «archivo:línea» apunta a
> él, bajo `lib/features/`.

---

## 0 · La medición, en un número

De los **18 módulos** del escritorio, **ninguno es una hoja**: no hay un solo módulo que no
importe a otro. Y **88 casos de uso** llaman al repositorio o a las tablas de **otro**
módulo: ésos son los renglones de este documento.

| Módulo | Cuántos lo usan | A cuántos usa |
|---|---|---|
| `usuarios` | **17** | 6 |
| `organizacion` | **16** | 10 |
| `finanzas` | **13** | 13 |
| `personal` | **12** | 10 |
| `inventario` · `dashboard` | 11 | 8 · 11 |
| `telefonia` | 7 | 7 |
| `compras` · `nomina` · `vehiculos` | 6 | 5 · 9 · 7 |
| `reportes` · `tiempos_extra` | 5 | **12** · 5 |
| `descuentos_personal` · `notificaciones` · `servicios_eventuales` | 4 | 7 · 4 · 5 |
| `boveda` · `respaldo` | 1 | 2 · 1 |
| `busqueda` | **0** | 7 |

Dos lecturas que cambian el plan:

- **`usuarios` y `organizacion` son el suelo.** Mudarlos primero no fue una preferencia:
  todo lo demás se apoya en ellos. Ya están mudados.
- **`busqueda` no lo usa nadie y usa a siete.** Es el único módulo que se puede mudar
  **último sin coste**, y el único que **no se puede mudar antes** que los siete.

---

## 1 · LA ESPINA: los dos registros donde cada módulo que gasta dinero tiene que apuntarse

Esto es lo más importante del documento, porque el escritorio **ya se equivocó aquí tres
veces** y lo dejó escrito en su propio código.

### 1.1 Qué son

| | |
|---|---|
| **`ObtenerOrigenAutomaticoEgresoUseCase`** · `finanzas/domain/usecases/obtener_origen_automatico_egreso_usecase.dart:118` | De UN egreso: ¿qué lo creó? Resuelto **siempre por FK real, nunca por el texto del concepto** |
| **`ClasificarEgresosPorOrigenUseCase`** · `reportes/domain/usecases/clasificar_egresos_por_origen_usecase.dart:89` | De MUCHOS egresos a la vez, sin N+1: ¿cuánto vino de cada origen? |

El `Egreso` **no tiene ninguna columna que diga de dónde vino** —«confirmado por
auditoría»—. El origen se deriva **recorriendo la FK en sentido inverso**: se le pregunta a
cada módulo «¿tienes una fila que apunte a este egreso?».

Los **ocho** orígenes de hoy · `obtener_origen_automatico_egreso_usecase.dart:23-116`:

```
Compra · Nómina · TiempoExtra · Deuda · DescuentoProgramado
Vehículo (v80) · Telefonía · ServicioEventual (v87)
```

### 1.2 Por qué importa tanto, con las tres pruebas

El primero de los dos es **«la ÚNICA fuente de verdad de ¿es manual?»**, y de ahí cuelga una
regla de negocio: **un egreso con origen automático NO se puede corregir ni cancelar desde
Finanzas** — se arregla desde el módulo que lo creó. Lo consumen `CorregirEgresoUseCase` y
`CancelarEgresoUseCase`.

Así que un módulo que no se apunta ahí no produce un hueco cosmético: **abre la puerta de
atrás**. El código lo dice de los tres casos que ya pasaron:

> «como este caso de uso es la ÚNICA fuente de verdad de "¿es manual?", el Egreso de una
> recarga se podía corregir y cancelar desde Finanzas, **por encima de Telefonía**»
> · `obtener_origen_automatico_egreso_usecase.dart:72-76`

> «un origen que falta aquí deja su Egreso corregible y cancelable desde Finanzas, por
> encima del dominio que lo creó — **exactamente lo que pasó con Préstamos, Vehículos y
> Telefonía**» · `:92-98`

Y en el de reportes, los dos agujeros fueron de **auditoría**, no de permisos:

> «**hueco real de auditoría**: un Egreso de Tiempo Extra se clasificaba como `manual`
> porque nadie consultaba `TiempoExtra.egresoId`» · `clasificar_egresos_por_origen_usecase.dart:14-17`

> «mismo hueco real: el Egreso de un préstamo se clasificaba como `manual` porque nadie
> consultaba `DescuentoProgramadoEmpleado.egresoId`» · `:17-20`

### 1.3 🔖 LA REGLA QUE SALE DE AQUÍ, PARA TODA LA MUDANZA

> **Cuando un módulo de la nube estrene su primer gasto, su alta en estos DOS registros
> entra en el mismo commit, cada uno con su prueba.** No «después»: el escritorio probó tres
> veces que «después» significa «cuando alguien lo note», y dos de las tres veces nadie lo
> notó hasta auditar.

El equivalente en el servidor SaaS todavía no existe —Finanzas es 5D.11—, así que **esta
regla se cumple el día que se diseñe, no se puede cumplir antes**. Queda escrita aquí para
que 5D.11 nazca con los dos registros desde el primer origen.

### 1.4 El tercer registro, el de cobrar

`ContraparteCobro` · `finanzas/domain/contraparte_cobro.dart` hace lo mismo del lado del
ingreso, y vale la pena por una frase suya:

> «Existe **una sola** definición de "misma contraparte" en todo el proyecto, y vive aquí.»
> Sustituyó a la comparación `cuenta.clienteId == pago.clienteId` «que se repartía por el
> dominio».

Con una regla de negocio dentro: **el Cliente gana cuando existe.** Un servicio eventual de
un cliente real es, para cobrar, ese cliente; el `servicioEventualId` de esas filas es **el
origen de la venta, no la contraparte**. Y `nombreContraparte` **nunca filtra el UUID a la
pantalla**: si el catálogo no trae el nombre, dice que no se conoce.

---

## 2 · LA OPERACIÓN MÁS CRUZADA DE TODO EL PRODUCTO: la baja de un empleado

Un solo botón escribe en **cinco módulos**. Si se muda Personal sin esto, se muda una baja
que miente.

`ConciliarBajaEmpleadoUseCase` · `personal/domain/usecases/conciliar_baja_empleado_usecase.dart:144`
importa `inventario`, `vehiculos` y `descuentos_personal`;
`RegistrarBajaLaboralUseCase` · `registrar_baja_laboral_usecase.dart:71` importa además
`usuarios`.

**Una sola operación de negocio** · `conciliar_baja_empleado_usecase.dart:133-137`:

```
baja laboral + cierre de Servicio + cierre de Línea telefónica
+ resoluciones físicas + movimientos de Inventario
+ resolución de Vehículo + creación de descuentos
      ... todo dentro de UNA transacción
```

> «Si algo falla, no queda empleado de baja con inventario a medias.»

Y **cuatro reglas que no son de la pantalla**, con su línea:

| Regla | Dónde |
|---|---|
| **La baja se RECHAZA si la persona conserva bienes vigentes sin resolver.** «No es un capricho de la UI: es el dominio el que impide que alguien salga de RISEG dejando un radio en el aire» | `registrar_baja_laboral_usecase.dart:26-32` |
| **La baja se BLOQUEA ENTERA, sin escribir nada, si la persona tiene la única cuenta Maestra activa.** Las alternativas eran peores: dejar el sistema sin acceso administrativo, o no desactivar la cuenta — «el agujero silencioso que esta etapa cierra». **Quien decide es una persona** | `:39-47` |
| **Lo obligatorio es saber qué pasó, no haber recuperado todo.** La baja se confirma con bienes perdidos o no entregados; **lo que no se permite es dejar uno sin explicar** | `conciliar_baja_empleado_usecase.dart:129-131` |
| **No existe un «No» barato.** Decidir no cobrar un costo real exige motivo **y** autorizador | `:58-60` |
| **La baja nunca borra al empleado**: cambia `estatus` y completa la fecha y el motivo del periodo vigente | `registrar_baja_laboral_usecase.dart:65-68` |

Y la verificación de bienes es **sobre el estado real, no sobre una bandera de confianza** ·
`:88-93`.

---

## 3 · Los cuatro servicios horizontales: leen de todos, y se mudan al final

Ninguno de los cuatro tiene datos propios. **Cada uno se completa un apartado a la vez**, y
por eso ninguno se puede «terminar» antes que los demás.

### 3.1 Permisos — `usuarios`, 17 módulos lo usan

El consumidor universal. Ya está mudado, y la web ya aplica la regla del Maestro.

### 3.2 Notificaciones — siete categorías de cuatro módulos

`ObtenerNotificacionesUseCase` · `notificaciones/domain/usecases/obtener_notificaciones_usecase.dart:53`
**compone casos de uso y «nunca importa un repositorio directamente»**:

```
verificación de vehículos · tenencia y refrendo · documentos por emitir
CxC próximas a vencer · CxC vencidas · pagos recientes · complementos pendientes
```

Dos criterios que se copian tal cual a la nube:

- **`null` cuando la sesión no tiene el permiso de esa sección** —y entonces **ni se calcula
  ni se consulta**—, **`[]` cuando sí lo tiene y no hay nada pendiente**. Es la norma
  «ausencia nunca es cero» puesta a trabajar · `:9-12`
- Hay «complementos pendientes» y **no existe «complemento vencido»**: «el sistema no tiene
  regla de plazo fiscal», así que la séptima categoría nace de un **pago real** y nunca de
  una fecha del calendario · `:31-35`

### 3.3 Búsqueda global — ocho buscadores, uno por entidad

`BuscarGlobalUseCase` · `busqueda/domain/usecases/buscar_global_usecase.dart:55`, y debajo
ocho casos de uso independientes: artículos, clientes, compras, empleados, líneas
telefónicas, servicios, usuarios, vehículos.

Es **el módulo que nadie usa**, así que se muda al final sin bloquear nada. Lo que no se
puede es mudarlo antes: cada buscador necesita su entidad en la nube.

### 3.4 Dashboard y Reportes — los dos lectores de todo

| | |
|---|---|
| `dashboard` | 8 casos de uso cruzados; `obtener_actividad_reciente_usecase.dart` toca **seis** módulos a la vez |
| `reportes` | **usa 12 módulos**, el que más; `obtener_resumen_general_usecase.dart` toca cinco |

Los dos deciden qué calcular **preguntando el permiso antes**, igual que notificaciones:
«cada `incluirXxx` la resuelve el llamador consultando `PermissionService` … mismo criterio
que `ObtenerResumenGeneralUseCase` de Reportes» · `obtener_notificaciones_usecase.dart:48-52`.

---

## 4 · Los demás cruces, por pareja

Lo que queda, agrupado por la pareja que lo sostiene. Cada renglón es una función que
**desaparece en silencio** si se muda un lado sin el otro.

### Personal ↔ Organización — **la pareja más pesada: 43 contactos de dominio**

Y ya está medido que **no la manda la estructura**: la dominan `servicio_table.dart` (9),
`servicio_repository.dart` (7), `servicio_comercial_repository.dart` (4) y
`linea_comercial_con_vigencia.dart` (6) — **22 de los 43 son Servicio**, no áreas ni puestos.

| Función | Archivo |
|---|---|
| Asignar un empleado a un servicio, y cambiarlo | `asignar_empleado_servicio_usecase.dart:76` · `cambiar_servicio_empleado_usecase.dart` |
| Crear un empleado (necesita área, puesto y sucursal) | `crear_empleado_usecase.dart` |
| Plantilla de personal y ficha técnica | `obtener_plantilla_personal_usecase.dart` · `generar_ficha_tecnica_empleado_usecase.dart` |
| Regularizar el perfil de una asignación | `regularizar_perfil_asignacion_usecase.dart` |
| **Y al revés:** el expediente de un servicio lee su personal | `organizacion/…/obtener_expediente_servicio_usecase.dart` |

En el servidor **el camino ya está abierto**: la migración `0046_operational_assignment.sql`
añadió `service_id`, `service_commercial_line_id`, `shift_modality_id` y `shift_notes` a
`employee_assignment`, con `CHECK ((branch_id IS NULL) <> (service_id IS NULL))`. El
comentario «SIN `service_id`» de la 0012 **está desactualizado**.

### Nómina ↔ Personal ↔ Finanzas

| Función | Archivo |
|---|---|
| Generar la nómina (lee personal y organización) | `nomina/…/generar_nomina_usecase.dart` |
| **Actualizar la nómina desde Personal** — el sueldo cambió después de generarla | `actualizar_nomina_desde_personal_usecase.dart:83` |
| Marcar qué renglones requieren revisión | `evaluar_renglones_requieren_revision_usecase.dart` |
| Registrar el pago de la nómina → Finanzas | `registrar_pago_nomina_usecase.dart` |
| Dispersión en PDF (datos de la empresa) | `generar_nomina_dispersion_pdf_usecase.dart` |

### Descuentos de personal ↔ Nómina ↔ Finanzas

El préstamo y el descuento programado nacen en su módulo, **se cobran en la nómina** y
**pagan en Finanzas**. `registrar_descuento_programado_usecase.dart` escribe en `personal`,
y es el que invoca la baja para convertir un bien no devuelto en una obligación.

### Tiempos extra ↔ Finanzas ↔ Organización ↔ Personal

`registrar_tiempo_extra_usecase.dart` y `corregir_tiempo_extra_usecase.dart` tocan **los
tres** a la vez. Y aquí vive la pieza compartida con Compras:
`validarOrigenTarjeta` · `finanzas/domain/origen_financiero_gasto.dart` — «única fuente de
verdad, reutilizada por `RegistrarCompraUseCase` y `RegistrarTiempoExtraUseCase`», con la
nota de que Compras **tenía la bifurcación duplicada 3 veces sin ningún tipo compartido**.

### Compras → Inventario (+ Finanzas)

Registrar, corregir y cancelar una compra escribe en **Inventario** —las unidades nacen de
la compra— y en **Finanzas** —el egreso—. Las tres en
`compras/domain/usecases/registrar|corregir|cancelar_compra_usecase.dart`. Y al revés,
`inventario/…/obtener_origen_compra_usecase.dart` responde «¿de qué compra salió esto?».

### Telefonía → Inventario — **23 contactos de dominio, la segunda pareja más pesada**

**El equipo telefónico ES un artículo de inventario.** Ocho casos de uso de Telefonía
escriben o leen en Inventario, incluidos los de credenciales:
`configurar_equipo_telefonico_usecase.dart`, `cambiar_contrasena_…`,
`revelar_credencial_…`, `actualizar_correo_…`, `asociar_equipo_linea_…`,
`cambiar_equipo_linea_…`, `obtener_equipos_disponibles_…`, `obtener_historia_equipo_…`.

Más Finanzas, por las recargas (`registrar_recarga_…`, `corregir_recarga_…`), y
Personal/Organización por la asignación de la línea.

### Servicios eventuales → Finanzas (33 contactos) + Organización (22)

**Diez** casos de uso cruzados: crear, corregir, cancelar, listar, pagar cobertura, pagar
costo, documento fiscal (registrar y corregir), reconciliar anulaciones, y agregar
participante (que va a **Personal**). Es el módulo con la frontera financiera más densa del
producto después de Nómina.

### Vehículos → Finanzas + Personal

`registrar_mantenimiento_vehiculo_usecase.dart` y su corrección generan egreso;
`obtener_opciones_asignacion_vehiculo_usecase.dart` lee personal y organización. Y
`notificaciones` le pide verificación, tenencia y refrendo.

### Inventario ↔ Personal + Organización

`generar_documento_resguardo_usecase.dart` necesita los datos de la persona **y** de la
empresa; `obtener_opciones_responsable_asignacion_usecase.dart` y
`obtener_empleados_responsables_servicio_usecase.dart` resuelven **a quién se le puede
asignar algo**, que es una pregunta de Personal contestada desde Inventario.

### Usuarios ↔ Personal

**`Employee != User`, y el vínculo es una función con su propio caso de uso:**
`cambiar_vinculo_empleado_usecase.dart`. `crear_usuario_usecase.dart` toca
`organizacion` y `personal`. En la nube esta frontera ya está construida y es más estricta:
CompanyAccess consume licencia.

### Bóveda y Respaldo — los dos pequeños

`boveda` depende de `usuarios` y `organizacion`; `respaldo` sólo de `usuarios`. Son los dos
únicos módulos que **casi** se pueden mudar solos. En la nube, la bóveda **queda fuera de la
v1** (deuda ya registrada: `ClientPortal` sin secreto cifrado), y el respaldo lo hace la
plataforma.

---

## 4 bis · LOS CAMINOS ESPEJO: la clase de hueco que cuesta encontrar

Esto no sale de medir los `import`. Sale de cerrar Organización, y es la lección más
reutilizable del apartado.

**Cuando una entidad cuelga de otra —puesto de área, sucursal de tipo—, el invariante
«nada ACTIVO cuelga de un padre APAGADO» tiene varias puertas, y cerrarlas de una en una
deja las demás abiertas sin que nada lo diga.** Las puertas son cuatro:

| Puerta | Pregunta |
|---|---|
| **Crear** | ¿se puede crear un hijo bajo un padre inactivo? |
| **Reasignar** | ¿se puede mover un hijo a un padre inactivo? |
| **Apagar el padre** | ¿se puede desactivar un padre con hijos activos? |
| **Encender el hijo** | ¿se puede reactivar un hijo cuyo padre está apagado? |

En Organización estaban implementadas **a medias y de forma distinta en cada pareja**:

| | Crear | Reasignar | Apagar el padre | Encender el hijo |
|---|---|---|---|---|
| Puesto ← Área | ❌ faltaba | *imposible: el área es inmutable* | ✅ la tenía el escritorio | ❌ faltaba |
| Sucursal ← Tipo | ✅ la tenía | ✅ la tenía | ❌ faltaba | ❌ faltaba |

Las cuatro cruces se arreglaron en M3, pero **ninguna se encontró razonando sobre el
código**:

- *Apagar el padre* salió de la revisión del dueño, que pidió las reglas en cascada.
- *Encender el hijo (puesto)* salió de comparar contra el escritorio, que la tenía.
- **Encender el hijo (sucursal) salió de PROBAR EN PANTALLA**, ejecutando la secuencia
  completa: cerrar, desactivar, desactivar el tipo, reactivar.
- *Crear (puesto)* salió de buscar las demás **después** de encontrar la tercera.

### 🔖 LA REGLA QUE SALE DE AQUÍ

> **Cuando un apartado tenga una entidad que cuelga de otra, las cuatro puertas se
> revisan EN TABLA antes de dar el apartado por cerrado**, y cada celda queda como
> «implementada», «imposible por diseño» o «decidida a sabiendas». Tres celdas bien y una
> vacía no es un invariante: es una puerta de servicio.

Y la razón por la que esto no lo caza una prueba suelta: **cada puerta pasa sus propias
pruebas en verde.** El hueco no está en ninguna de las cuatro, está en el conjunto, y por
eso la tabla es la herramienta y no más casos de prueba.

**Dónde cuelga algo de algo, en los apartados que faltan** —para que la tabla se haga sin
tener que redescubrirlo—:

| Hijo | Padre | Apartado |
|---|---|---|
| Línea comercial | Servicio | Comercial |
| Vigencia comercial | Línea comercial · Puesto | Comercial |
| Servicio eventual | Cliente *(opcional)* | Comercial |
| Entidad fiscal | Cliente | Comercial |
| Unidad de artículo | Artículo · Categoría | Inventario |
| Línea telefónica | Equipo telefónico | Telefonía |
| Asignación | Empleado · Servicio · Sucursal | Personal |
| Cuota | Descuento programado | Descuentos |

---

## 5 · Cómo se usa este documento en el método

El método de la mudanza es: **investigar → revisar → construir → comprobar → cerrar**, un
apartado a la vez, y no se empieza otro con uno abierto.

Este documento añade **un paso al «investigar»**:

> Antes de cerrar el inventario de un apartado, se busca ese apartado en la sección 4 de
> aquí y **cada renglón de su pareja entra en el inventario**, aunque la función «viva» en el
> otro módulo. Un renglón que cruza se cierra cuando funciona **de los dos lados**, o se
> anota explícitamente como abierto con el nombre del apartado que falta.

Y añade **una condición al «cerrar»**:

> Un apartado que gasta o cobra dinero **no se cierra** sin su alta en los registros de la
> sección 1, con prueba.

### Lo que esto significa para el orden

| Se pueden cerrar del todo | Quedan abiertos hasta el final, por diseño |
|---|---|
| `usuarios` · `organizacion` · `boveda` | `dashboard` · `reportes` · `notificaciones` · `busqueda` |

Los cuatro de la derecha **crecen un renglón por cada apartado que se muda**. Su inventario
no es una lista que se completa: es una lista que se **va llenando**, y el único momento en
que se puede dar por cerrada es cuando no quedan apartados por mudar.
