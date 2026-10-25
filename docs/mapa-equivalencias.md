# Mapa de equivalencias — Administra contra el motor

> **Sólo lectura.** Este documento no cambió una línea de código. Se escribió el **16 de
> octubre de 2026** comparando las **126 tablas** del producto local contra las **100** del
> esquema `app` del motor, tabla por tabla.
>
> Para qué sirve: que al mudar cada módulo **no haya discrepancias en la información**.
> Dónde ya hay sitio, dónde falta, y qué hay que decidir antes de programar.
>
> El plan de la mudanza y su orden están en [`mudanza-a-la-nube.md`](mudanza-a-la-nube.md).
> M1 —la asignación operativa— ya tiene diseño propio y migración.

## Cómo leer este mapa

**«El motor» es el backend SaaS** (`seventra-backend`, esquema `app`). **«Administra» es
este repositorio**, con su base SQLite local.

Tres advertencias que evitan los tres malentendidos más probables:

**El motor tiene cosas que Administra no tiene, y no son huecos al revés.** Planes,
adicionales, suscripciones, descuentos otorgados, invitaciones: eso es **SEVENTRA
vendiéndole a sus clientes**, un plano que en el producto local no existe porque el producto
local se instalaba y ya. No entra en este mapa.

**`subscription_discount` del motor NO es `descuentos_personal` de Administra.** La misma
palabra en dos mundos: uno es el descuento que SEVENTRA le da a su cliente sobre lo que le
cobra; el otro es el descuento que una empresa le aplica a un empleado en su nómina. Nunca
se tocan.

**Las bitácoras y los adjuntos cambian de forma, no de existencia.** Administra tiene **una
tabla `XxxEvento` por entidad** —quince— y **una `XxxAttachment` por entidad** —catorce—. El
motor tiene **un `audit_event`** y **un `file` con slots por recurso**. Eso no es un hueco:
es otro modelo, ya cerrado, y es la **primera decisión transversal** de la sección final.

---

# 1 · Usuarios y accesos — **YA MUDADO**

**Lo que guarda Administra:** `Usuario`, `UsuarioEvento`, `PermisoUsuario`,
`SesionPersistente`, `EliminacionFisicaEvento`.

**En el motor:** `identity`, `identity_credential`, `identity_session`,
`identity_refresh_token`, `identity_token`, `identity_auth_link`, `company_access`,
`company_access_permission`, `organization_membership(_permission)`,
`platform_administrator(_permission)`.

**Huecos: ninguno.** Y está **hecho**: los cinco commits de la plomería acabaron con «la
sesión productiva corre sobre Identity SaaS». Las cinco tablas locales son **peso muerto**
desde entonces.

**Importación:** nada. Las identidades se crean con invitaciones, y las contraseñas locales
no se migran —ni se pueden, ni se debe—.

**Decisión que necesito:** ninguna. Sólo confirmar que las cinco tablas locales se borran
cuando el módulo deje de leerlas.

---

# 2 · Organización, clientes y servicios — **el más grande, y partido en dos**

**Lo que guarda Administra** (30 tablas, 41 642 líneas de código): `Empresa`,
`EmpresaAttachment`, `Sucursal`, `Puesto`, `Ubicacion`, `Cliente`, `ClienteAttachment`,
`ClienteEvento`, `ClientePortal`, `Contacto`, `EntidadFiscal`, `Servicio`, `ServicioEvento`,
`ServicioLineaComercial`, `ServicioLineaComercialVigencia(+Horario)`, y **nueve tablas de
cobranza**: `ConfiguracionCobro(+Correo, +Etapa, +Evento, +Vigencia)` y
`DocumentoPorEmitir(+Attachment, +Configuracion, +Correo, +CorreoEnvio, +Evento, +Hito,
+Linea, +Servicio)`.

**Reglas que importan:** el cliente tiene **varias razones sociales**; un servicio tiene
**varias líneas comerciales**, cada una con **vigencias** y **horario por día**; el código
humano de cada cosa sale de una secuencia; y un servicio pertenece a una **ubicación**.

**En el motor, y es mucho:** `company`, `branch`, `position`, `area`, `client`,
`client_address`, `client_contact`, `client_document`, `client_file_slot`, `client_portal`,
`fiscal_entity(+address, +document)`, `service`, `service_address`, `service_type`,
`service_commercial_line`, `commercial_line_term`, `term_schedule(+span)`, `contract`,
`contract_service`, `contract_amendment(+document)`, y los contadores
`company_client_number` / `company_service_number` / `company_contract_number`.

**El motor además trae lo que Administra no tiene:** contratos de verdad —con sus anexos y
sus documentos—, que en el local no existen como entidad.

**Huecos:**

| Hueco | Qué es |
|---|---|
| **Las nueve tablas de cobranza** | `ConfiguracionCobro*` y `DocumentoPorEmitir*`. **Es la 5D.11**, que está diseñada y **no implementada** |
| `Ubicacion` como entidad | el motor pone la dirección **en** el servicio (`service_address`); el local la tiene aparte y la reutiliza |
| `ClienteEvento`, `ServicioEvento` | bitácora por entidad → `audit_event` |

**⚠️ Y aquí hay la discrepancia de diseño más importante de todo el mapa.** La frontera
congelada de la 5D.11 dice: `Terms → BillingConfiguration → BillingPreparation → documento
emitido → AccountReceivable → Payment`, y que **`BillingPreparation` NO es una cuenta por
cobrar**: la CxC nace **únicamente** al registrar el documento emitido.

El `DocumentoPorEmitir` de Administra **es la preparación**, y hay que comprobar renglón por
renglón que su `Hito`, su `Linea` y su `CorreoEnvio` encajan en esa frontera y no la cruzan.
**Si no encajan, se rediseña el local al mudarlo, no se copia.**

**Importación:** empresas, sucursales, puestos, clientes, contactos, razones sociales,
servicios, líneas y vigencias. **Se perdería** la bitácora por entidad tal como está hoy
—pasa a `audit_event`, con otra forma— y las ubicaciones compartidas entre servicios habría
que **duplicarlas** como dirección de cada servicio.

**Decisiones que necesito:**

1. **La cobranza del local, ¿se muda o se rediseña?** Mi lectura: se rediseña contra la
   5D.11, porque la frontera está congelada y es más estricta que el local.
2. **¿Una ubicación compartida por dos servicios existe de verdad en tus datos?** Si sí, el
   motor necesita algo que hoy no tiene; si no, la dirección por servicio basta.

---

# 3 · Personal — **el que ya está en marcha (M1–M5)**

**Lo que guarda Administra:** `Empleado`, `EmpleadoAttachment`, `EmpleadoEvento`,
`EmpleadoPeriodoLaboral`, `AsignacionServicio`, `AsignacionServicioSueldoVigencia`,
`FichaTecnicaEmpleado`, `ConciliacionBaja(+Renglon)`, `VacanteOperativa`.

**En el motor:** `person(+address)`, `employee`, `employee_banking`, `employee_document`,
`employee_document_type`, `employee_drug_test_result`, `employee_evaluation(+file)`,
`employee_file_slot`, `employee_professional_profile`, `employee_technical_sheet(+number)`,
`employment_period`, `employee_assignment`, `termination_reason`.

**El motor separa `person` de `employee`**, que el local no hace: la persona existe aparte
del empleo. Es mejor —una persona recontratada no se duplica— y la importación tiene que
partir cada fila local en dos.

**Huecos:**

| Hueco | Estado |
|---|---|
| El destino **operativo** de una asignación | **la 0046 lo cierra** (servicio + línea + turno) |
| **Sueldo con vigencias** | **M2**, decidido: vive en Personal y Nómina sólo lo lee |
| `ConciliacionBaja(+Renglon)` | **falta**. Es el finiquito: qué se le debe a quien se va |
| `VacanteOperativa` | **falta**. Un puesto por cubrir en un servicio |

**Importación:** personas, empleados, periodos, asignaciones, documentos, fotos y fichas.
**Y aquí está tu regla:** ningún dato real —ni bancario ni expediente— hasta tener
producción.

**Decisiones que necesito:**

1. **¿La conciliación de baja se muda a la nube o la hace Nómina?** Es dinero que se le debe
   a alguien que se va, y Nómina no existe todavía.
2. **¿La vacante operativa es de Personal o de Servicios?** Describe un **hueco en un
   servicio**, no una persona.

---

# 4 · Nómina — **cero en el motor**

**Lo que guarda Administra:** `Nomina`, `NominaEmpleado`, `NominaEmpleadoTramo`,
`NominaEmpleadoAusencia`, `NominaEvento`, `PagoNomina(+Attachment, +Evento)`,
`AplicacionPagoNomina`.

**Regla clave, y es la que hace a este módulo distinto de todos:** cada nómina generada
guarda su **snapshot**, y el histórico protegido sale de ahí y no de las tablas vivas. Lo
dice el propio código del sueldo administrativo: *«el histórico protegido lo da el snapshot
de cada Nómina ya generada»*.

**En el motor: NADA.** El módulo `payroll` existe en el catálogo de productos —se puede
vender— y **no tiene ni una tabla ni un endpoint**.

**Huecos: todo.** Y dos piezas que el motor ya tiene a su favor:
`commercial_line_term.recruiting_salary_reference_minor` y su bono, que son el sueldo de
referencia que se precarga al asignar.

**Importación:** las nóminas ya generadas son **evidencia de lo que se pagó**. O se importan
con su snapshot intacto, o no se importan: recalcularlas daría otras cifras.

**Decisiones que necesito:**

1. **¿Nómina entra en la nube, y en qué momento?** Es el módulo más grande sin nada hecho.
2. **¿Las nóminas históricas se importan o se consultan en el producto local?** Mi lectura:
   **no se importan**. Son evidencia, y mudar evidencia es la forma más fácil de alterarla.
3. **¿`tiempos_extra` y `descuentos_personal` son parte de Nómina?** No tienen módulo propio
   en el catálogo, y los dos acaban en un recibo.

---

# 5 · Finanzas — **cero en el motor, y es la 5D.11**

**Lo que guarda Administra** (22 tablas, 31 278 líneas): `CuentaFinanciera`,
`CategoriaFinanciera`, `CuentaPorCobrar(+Evento)`, `Pago(+Attachment, +Evento)`,
`AplicacionPago`, `ComplementoPago(+Attachment, +Evento)`, `Ingreso(+Attachment, +Evento)`,
`Egreso(+Attachment, +Evento, +Fuente)`, `Deuda`, `MovimientoDeuda`,
`TransferenciaCuenta(+Evento)`.

**En el motor: NADA.** El módulo `finance` y el módulo `collections` existen en el catálogo
y **ninguno tiene tabla**.

**Huecos: todo.** Y la frontera congelada de la 5D.11 ya dice cómo tiene que verse la parte
de cobranza: la CxC nace **sólo** con el documento emitido.

**Importación:** saldos y pagos son **contabilidad**. Mismo criterio que las nóminas: o se
importan íntegros y cuadrados, o se dejan donde están.

**Decisiones que necesito:**

1. **¿Finanzas completa, o sólo Cobranza primero?** Son dos módulos distintos en el catálogo
   —`collections` y `finance`— y el local los tiene juntos.
2. **¿Los ingresos y egresos que no vienen de un cliente** —transferencias entre cuentas,
   egresos con su fuente— **son de este producto o de un contador?**

---

# 6 · Inventario y Compras — **un módulo en el catálogo, dos en el local**

**Lo que guarda Administra:** `Articulo`, `ArticuloVariante`, `ArticuloUnidad(+Evento,
+Telefono)`, `CategoriaArticulo`, `Asignacion(+Attachment)`, `Entrega`,
`MovimientoInventario(+Attachment)`, `DescuentoInventario` · y en Compras: `Compra(+Attachment,
+Evento, +Partida, +PartidaMovimiento)`.

**Dos reglas que importan:** el inventario distingue **artículo → variante → unidad**, o sea
que una unidad concreta se puede seguir una por una; y una **partida de compra** alimenta el
movimiento de inventario, así que comprar y entrar en almacén están unidos.

**En el motor: NADA.** El catálogo tiene **un solo módulo**, `purchases_inventory`, para los
dos.

**Importación:** el catálogo de artículos y el **saldo actual** de existencias. El histórico
de movimientos es opcional y pesa mucho.

**Decisiones que necesito:**

1. **¿Un módulo o dos?** El catálogo dice uno; el local son dos y se venden juntos.
2. **¿Las unidades individuales se siguen una por una en la nube?** Es la decisión que marca
   el tamaño: seguir unidades es mucho más que contar existencias.
3. **`ArticuloUnidadTelefono` une inventario con telefonía.** ¿Un teléfono es un artículo de
   inventario, o un activo de telefonía? Hoy es las dos cosas.

---

# 7 · Vehículos — **cero, y el módulo del catálogo se llama «Activos»**

**Lo que guarda Administra:** `Vehiculo(+Attachment, +Evento)`, `VehiculoDocumento(+Attachment)`,
`VehiculoKilometraje`, `VehiculoMantenimiento(+Attachment)`, `AsignacionVehiculo`.

**En el motor: NADA.** Existe el módulo `assets` —«Activos»— sin una sola tabla.

**Importación:** los vehículos y sus documentos vigentes. El kilometraje y el histórico de
mantenimiento, opcionales.

**Decisión que necesito:** **¿`assets` es «vehículos» o es «cualquier activo»?** Si es lo
segundo, vehículos, teléfonos y equipo entran en una sola estructura y eso cambia el diseño
entero.

---

# 8 · Telefonía — **cero, y además NO TIENE MÓDULO en el catálogo**

**Lo que guarda Administra:** `LineaTelefonica(+Equipo, +Evento)`,
`AsignacionLineaTelefonica`, `EquipoTelefonicoCredencial`, `EquipoTelefonicoEvento`,
`RecargaLineaTelefonica(+Attachment)`.

**En el motor: NADA. Y esto es un hallazgo, no un hueco más:** el catálogo de módulos de
Administra tiene **siete** —Personal, Nómina, Clientes y Servicios, Cobranza, Finanzas,
Compras e Inventario, Activos— y **telefonía no está en ninguno**. Hoy **no se puede
vender**.

**`EquipoTelefonicoCredencial` guarda credenciales**, así que toca lo mismo que la bóveda: un
secreto en reposo.

**Decisiones que necesito:**

1. **¿Telefonía es parte de «Activos» o es un módulo propio?** Si es propio, hay que abrirlo
   en el catálogo, y eso es una decisión comercial, no técnica.
2. **Las credenciales de los equipos: ¿se mudan?** Entra en la misma decisión que la bóveda.

---

# 9 · Servicios eventuales — **cero, y su diseño ya está esperando**

**Lo que guarda Administra:** `ServicioEventual(+Cobertura, +Costo, +DocumentoFiscal(+Attachment),
+Evento, +Participante)`.

**En el motor: NADA, pero el diseño existe: es la 5D.10G**, pendiente.

### ⚠️ CORRECCIÓN a la primera versión de este mapa

Dije que el diseño congelado manda el eventual **«sin Client y sin identificadores
financieros»** y que eso **chocaba** con el local. **Fui a leer el texto congelado y dice
algo más estrecho.** Literalmente:

> `EventualService` es **aggregate independiente** y **puede existir sin Client**.
> Solicitante libre permitido. `location_text` **obligatorio**; dirección estructurada
> opcional.
>
> **Sin `paid`/`settled` en Comercial** (10B.1 exigió elegir UNA sola verdad): la
> liquidación la determina Finanzas después. **Ningún id financiero dentro de Comercial.**

Las dos diferencias importan:

| Lo que yo escribí | Lo que el diseño dice |
|---|---|
| «va **sin** Client» | «**puede** existir sin Client» — el cliente es **opcional, no prohibido** |
| «sin identificadores financieros» | «ningún id financiero **dentro de Comercial**» — es un asunto de **dónde viven**, no de si el eventual se cobra |

**Y el motor ya declara que un eventual se cobra y se factura.** Está en el catálogo de
permisos de la 0022, con estos dos entre otros siete:

```
servicios_eventuales.cobrar     Cobrar un servicio eventual      clients_services
servicios_eventuales.facturar   Facturar un servicio eventual    clients_services
```

**Así que tu postura ya es el diseño**, no una excepción a él: el eventual **lleva cliente
cuando lo tiene** y **se factura**. Lo que el diseño prohíbe es otra cosa.

### Por qué se decidió «sin ids financieros dentro de Comercial», en simple

**Para que «está pagado» tenga UNA sola respuesta.**

Si el eventual guardara dentro su documento fiscal y su estado de pago, habría **dos sitios**
que contestan si se cobró: el eventual y Finanzas. Y en cuanto hay dos, se separan —alguien
cancela un pago en Finanzas y el eventual sigue diciendo «pagado»— y entonces nadie sabe
cuál creer. La decisión 10B.1 fue elegir una: **Finanzas**.

No dice que el eventual no se cobre. Dice que **el eventual no es quien lleva la cuenta**:
registra lo que se acordó —quién, cuándo, cuánto, con quién— y la cobranza ocurre en el
plano que existe para eso. Es la misma regla de la 5D.11: la cuenta por cobrar nace al
registrar el documento emitido, y en un solo sitio.

**Lo que eso significa para la mudanza, en concreto:** el `ServicioEventualDocumentoFiscal`
del local **invierte su dirección**. Hoy el eventual apunta a su documento fiscal; en el
motor será el documento —en Cobranza— el que apunte al eventual. **El dato no se pierde:
cambia de lado.** Y desde el eventual se sigue pudiendo ver, porque la relación existe igual.

### ✅ DECIDIDO el 25 de octubre de 2026 — ahora es el compromiso CP-11 de la 5D.10G

Era la decisión pendiente de este documento. **Ya no lo es**, y lo que se decidió entra en
`seventra-backend/docs/compromisos.md` como **CP-11**, con su prueba pendiente:

1. **El cliente es OPCIONAL.** El diseño ya decía «puede existir sin Client» y permite un
   **solicitante libre**; obligarlo impediría registrar la posada de una empresa que no es
   cliente, que es un caso real del local.
2. **Si el eventual requiere factura, el receptor fiscal se captura EN EL PROPIO EVENTUAL**
   —RFC, razón social, **régimen** y código postal— **o** se elige una **entidad fiscal
   existente** cuando el eventual sí tiene Client.
3. **El documento fiscal se registra DESDE EL LADO DEL EVENTUAL**, no desde Cobranza. (Mi
   recomendación había sido la contraria; la decisión es ésta.)
4. **El receptor fiscal no es el solicitante**, y eso se conserva: quien pide el evento y
   quien recibe la factura pueden ser distintos.

> ⚠️ **Lo que CP-11 tiene que resolver al construirse:** `fiscal_entity` **no tiene
> régimen** —se dejó fuera a propósito en la 0018, porque el régimen es dato de
> facturación— y el receptor de un eventual **sí lo llevará**. O la entidad fiscal gana esa
> columna, o existen dos formas de receptor fiscal y 5D.11 tiene que leer las dos. Está
> anotado en el compromiso.

---

# 10 · Tiempos extra — **cero, sin módulo propio**

`TiempoExtra`, `TiempoExtraCostoAdicional`, `TiempoExtraEvento`. Usa el catálogo de
modalidades de turno —de ahí salió `12X24`—.

**En el motor: NADA**, y tampoco módulo en el catálogo. Acaba en un recibo, así que lo más
probable es que sea **parte de Nómina**.

---

# 11 · Descuentos a personal — **cero, sin módulo propio**

`DescuentoProgramadoEmpleado`, `DescuentoProgramadoCuota`, `DescuentoProgramadoMovimiento`:
un descuento **en cuotas** aplicado a un empleado.

**En el motor: NADA.** Y **no confundir con `subscription_discount`**, que es otro mundo.
También parece **parte de Nómina**.

---

# 12 · Bóveda — **fuera de la v1 por decisión**

`BovedaCredencial`, `BovedaCredencialEvento`: secretos cifrados en local.

**En el motor:** existe `client_portal` —el portal de un cliente— **sin secreto cifrado**, y
está anotado como deuda conocida: *«la bóveda queda fuera de la v1»*.

**Huecos:** el almacén de secretos entero. En la nube es otro problema: un secreto cifrado en
una máquina es una cosa, y en un servidor compartido es otra.

**Decisión que necesito:** **¿la bóveda se rediseña para la nube o se queda fuera?** Mi
lectura: fuera de la v1, como ya está anotado, y con una decisión aparte cuando toque.

---

# 13 · Respaldo — **desaparece**

`ConfiguracionRecuperacionPortable`, más 14 archivos que usan `dart:io`.

**En el motor:** no aplica. **Respalda Cloud SQL.**

**Decisión que necesito:** **¿se conserva un «exportar mis datos» para el cliente?** No es lo
mismo que un respaldo: uno protege al sistema, el otro le da al cliente lo que es suyo.

---

# 14 · Tablero, búsqueda, reportes y notificaciones — **sin tablas propias**

No guardan nada: **leen de los demás**. 125 archivos y 17 000 líneas que atraviesan todo.

**Se mudan al final**, porque antes no tendrían de dónde leer. Y `reportes` es el que más
`dart:io` tiene después de `respaldo`: son PDF y Excel que hoy se escriben en una ruta y en
web se descargan.

---

# Las tres decisiones transversales

Valen para los catorce módulos y conviene decidirlas una vez.

## 1 · Las bitácoras por entidad contra `audit_event`

Administra tiene **quince tablas `XxxEvento`**. El motor tiene **una** `audit_event`,
append-only, con el evento **en la misma transacción** que la mutación, y una regla dura:
**ningún evento lleva una colección** —uno por fila—.

**Lo que hay que decidir:** si las quince se colapsan en `audit_event` —mi lectura: sí— o si
algún módulo necesita su propia línea de tiempo consultable. El caso que lo pondría a prueba
es Nómina, donde el histórico es evidencia.

## 2 · Los adjuntos por entidad contra `file` + slots

Administra tiene **catorce tablas `XxxAttachment`**. El motor tiene **Files SaaS**, que está
cerrado y es más estricto: el **slot es una tabla**, `ready` no es «seleccionado»,
`singleton` es uno **por recurso**, guarda **historial**, y sólo **desvincular** libera
capacidad.

**Lo que hay que decidir:** nada, en mi lectura. **El modelo del motor gana** y cada
`XxxAttachment` se convierte en un `purpose` de `platform_file_purpose`. Lo que sí hay que
hacer es **listar los catorce propósitos** antes de mudar el primero.

## 3 · Los códigos humanos

Administra tiene `CodigoSecuencia` con prefijo, dígitos y reinicio anual. El motor tiene
contadores **por Company** —`company_client_number`, `company_service_number`,
`company_contract_number`, `company_employee_number`, `company_technical_sheet_folio`— y una
**lista cerrada** de códigos: `CLI`, `SRV`, `COT`, `CTR`, `EVT`, y **nada más**.

**Lo que hay que decidir:** qué pasa con los códigos de las entidades que en el motor **no
llevan** —y la norma dice que **no se inventan códigos por simetría**—. Si en Administra hoy
se ve un folio de algo que en el motor no lo tiene, alguien lo va a echar de menos.

---

# Resumen

| Módulo | Ya existe en el motor | Huecos principales | Tamaño |
|---|---|---|---|
| **Usuarios y accesos** | **100 %** — ya mudado | ninguno | **hecho** |
| **Personal** | **~85 %** con la 0046 | sueldo con vigencias (M2), conciliación de baja, vacante operativa | **mediano** |
| **Organización · clientes · servicios** | **~70 %** | las nueve tablas de cobranza (5D.11), ubicación como entidad | **grande** |
| **Bóveda** | **~20 %** | el almacén de secretos entero | chico, y **fuera de la v1** |
| **Servicios eventuales** | **0 %**, diseño listo (5D.10G) | todo; el cliente es **opcional** y el documento fiscal apunta **desde Cobranza** | **mediano** |
| **Finanzas** | **0 %** | todo. Es la 5D.11 | **grande** |
| **Nómina** | **0 %** | todo. Y el snapshot de cada nómina es evidencia | **grande** |
| **Inventario** | **0 %** | todo; y decidir si se siguen unidades una por una | **grande** |
| **Compras** | **0 %** | todo | **mediano** |
| **Vehículos** | **0 %** | todo. `assets` existe vacío | **mediano** |
| **Telefonía** | **0 %** | todo, **y no tiene módulo en el catálogo** | **mediano** |
| **Tiempos extra** | **0 %** | todo. Sin módulo propio: probablemente Nómina | chico |
| **Descuentos a personal** | **0 %** | todo. Sin módulo propio: probablemente Nómina | chico |
| **Respaldo** | n/a | **desaparece**; decidir «exportar mis datos» | chico |
| **Tablero · búsqueda · reportes · notificaciones** | n/a | se mudan al final, cuando haya de dónde leer | **mediano** |

## El orden recomendado, y por qué

> ### ⚠️ CORREGIDO EL 22 DE OCTUBRE DE 2026 — **Clientes y servicios va ANTES que Personal**
>
> Este orden ponía Personal primero con el argumento de que «es el único con backend
> cerrado». **El argumento era cierto y la conclusión estaba mal**, y lo que la corrige es
> una lectura del escritorio:
>
> **La línea comercial de un servicio define las plazas, el turno, el precio y el sueldo
> de referencia; y la asignación de personal precarga el sueldo desde ahí.** En la nube es
> literal: `commercial_line_term` lleva `position_id`, `shift_modality_id`, **`headcount`**,
> `unit_price_minor` y `recruiting_salary_reference_minor`, todo versionado por fechas.
>
> Así que mudar Personal primero obliga a construir su pantalla de asignación **dos veces**:
> una sin línea comercial —con el sueldo capturado a mano y sin plazas contra las que
> validar— y otra cuando Comercial llegue. El escritorio ya pasó por ahí y lo dejó escrito:
> retiró el respaldo a `Servicio.sueldoMensualReferenciaPersonal` «de la captura nueva,
> columnas conservadas sólo por compatibilidad con datos históricos».
>
> **Y desde la decisión del cupo —BLOQUEAR— la dependencia dejó de ser de comodidad:** sin
> el término vigente de la línea no hay plazas contra las que bloquear, así que la
> asignación **no se puede construir** antes que Comercial.
>
> **Lo que NO cambia:** el expediente, los documentos, los datos bancarios, las
> evaluaciones, la ficha técnica y contratar con destino **sucursal** no dependen de
> Comercial y siguen disponibles cuando toquen. La frontera es el destino de la asignación,
> no el módulo.

1. **Estructura: áreas, puestos, sucursales** — ya tiene endpoints, y es dependencia de todo.
2. **Clientes y servicios** — también tiene endpoints, y es lo que **define las plazas, el
   turno y el sueldo de referencia** que la asignación de personal necesita para significar
   algo. **Va antes que Personal**, por lo de arriba.
3. **Personal**, con su asignación y **los tiempos extra** — el backend está cerrado
   (M1 asignación, M2 sueldo). Los tiempos extra entran **con** Personal y no con Nómina:
   las suplencias van por ahí, y con el cupo bloqueado son la única salida cuando una línea
   está completa.
4. **Contratos** — ya existen en el motor y **no existen en el local**: es ganancia, no
   mudanza.
5. **Servicios eventuales (5D.10G)** — diseño listo, y depende de clientes.
6. **Cobranza y Facturación (5D.11)** — depende de servicios, líneas y vigencias. Aquí se
   resuelve la discrepancia del `DocumentoPorEmitir`.
7. **Finanzas** — después de cobranza, porque los cobros alimentan las cuentas.
8. **Nómina**, con los descuentos a personal dentro — depende de Personal **y** del sueldo
   con vigencias (M2). **Los tiempos extra salieron de aquí** y se adelantan con Personal
   (punto 3): son la vía de las suplencias, y con el cupo bloqueado hacen falta el mismo día
   que la asignación.
9. **Inventario y Compras** — casi independientes del resto. Pueden adelantarse si hace
   falta.
10. **Activos: vehículos y telefonía** — los últimos del dominio, y antes hay que decidir qué
    es `assets`.
11. **Tablero, búsqueda, reportes y notificaciones** — al final por definición.

**Lo que no depende de nada y conviene hacer pronto:** las **tres decisiones transversales**.
Las tres se vuelven caras si se descubren a la mitad del cuarto módulo.

---

# Decisiones tomadas — 16 de octubre de 2026

Lo que sigue **no es propuesta: está decidido** y manda sobre cualquier lectura anterior de
este documento.

## 1 · Administra se organiza como el catálogo comercial: siete módulos

**Activos · Clientes y servicios · Cobranza · Compras e inventario · Finanzas · Nómina ·
Personal.** Los mismos siete que ya se venden, y **las pantallas se reorganizan con este
orden al mudar**, aunque haya que trabajarlas: la meta es que sea práctico y comprensible,
no que se parezca a lo que hay.

Lo que hoy está separado se une:

### Vehículos + Teléfonos → **Activos**, con un TIPO

Un solo módulo de **control general de bienes**, con un **tipo** —vehículo, teléfono, y a
futuro radios, equipo, uniformes— que **conserva los datos propios de cada tipo**: placas y
póliza para un vehículo, número de línea y plan para un teléfono.

**Y resuelve el hallazgo del mapa:** telefonía no tenía módulo en el catálogo y por tanto
**no se podía vender**. Dentro de Activos, sí.

**Lo que esto obliga a diseñar con cuidado:** un activo tiene una parte **común** —qué es, de
quién es, a quién está asignado, su historia— y una parte **propia del tipo**. Dos caminos, y
hay que elegir uno al diseñar el módulo:

| | |
|---|---|
| Una tabla por tipo, con una cabecera común | cada tipo conserva sus columnas con nombre propio y sus reglas; añadir «radios» es una tabla nueva |
| Una tabla con atributos flexibles | añadir un tipo no toca la base, pero **se pierde la validación**: una placa deja de ser una placa y pasa a ser texto en una bolsa |

Mi recomendación: **la primera**. En este proyecto las reglas se sostienen con estructura
—claves compuestas, `CHECK`, nunca un `if`— y una bolsa de atributos es exactamente lo
contrario. El precio es una tabla por tipo nuevo, y es barato.

### Compras + Inventario → **Compras e inventario**

Como ya está en el catálogo. En el local son dos módulos y una **partida de compra** ya
alimenta el movimiento de inventario, así que la unión no inventa una relación: la reconoce.

### Dónde caen los tres sueltos — propuesta, con lo que dicen sus tablas

**Servicios eventuales → Clientes y servicios.** Es un servicio que se le vende a un cliente
para un evento, con su documento fiscal y sus participantes. Su tabla apunta a `Cliente`,
`EntidadFiscal`, `Deuda` y `Egreso`.

✅ **Y NO choca con el diseño del motor, al contrario de lo que escribí antes.** El texto
congelado dice que el eventual **puede** existir sin Client —opcional, no prohibido— y que
ningún id financiero vive **dentro de Comercial**, que es otra cosa. El propio catálogo de
permisos de la 0022 ya trae `servicios_eventuales.cobrar` y `.facturar`. El detalle y la
decisión pendiente, en la sección 9.

**Descuentos a personal → Nómina.** Un descuento en cuotas sobre lo que se le paga a alguien:
préstamos (`PRE`), botas (`DES`) y resguardos nacidos de una baja (`RES`). Apunta a
`Empleado`, `CuentaFinanciera` y `Egreso`.

**Tiempos extra → Personal, y NO Nómina.** Aquí **corrijo lo que supuse en la primera versión
de este mapa**: dije «probablemente Nómina» y su tabla dice otra cosa. `TiempoExtra` cuelga de
un **`Servicio`**, apunta a una **`VacanteOperativa`**, nombra al **empleado ausente** y al
que **cubre** —que puede ser **alguien externo**, con su nombre escrito a mano— y se paga con
un **`Egreso`**, no en un recibo de nómina.

**Es cobertura operativa de una ausencia**, no una percepción. Su sitio es **Personal**, junto
a la vacante operativa y las asignaciones; el dinero sale por Finanzas.

## 2 · Cobranza se rediseña al mudar

**No se copia.** Las nueve tablas de `ConfiguracionCobro*` y `DocumentoPorEmitir*` se
rediseñan contra la frontera congelada de la 5D.11:

```
Terms → BillingConfiguration → BillingPreparation → documento emitido → AccountReceivable → Payment
```

Y la regla que no se negocia: **`BillingPreparation` NO es una cuenta por cobrar.** La CxC
nace **únicamente** al registrar el documento emitido.

## 3 · Las nóminas históricas se importan, pero de SÓLO CONSULTA

**No como datos editables.** Como **archivo histórico**: recibos y reportes consultables, por
SAT, IMSS, finiquitos y aclaraciones, con un **mínimo de cinco años**.

Esto corrige mi recomendación anterior —«no se importan»— y la corrige bien: el motivo real
no era técnico, era que mudar evidencia la pone en riesgo de alterarse. **Sólo consulta
resuelve las dos cosas**: la evidencia se conserva y nadie la puede reescribir.

**Lo que obliga a diseñar:** una nómina histórica importada **no se recalcula nunca**. Entra
con su snapshot intacto, por un camino **sin escritura**, y la pantalla que la muestra dice de
dónde viene. Si algún cálculo nuevo pudiera tocarla, deja de ser archivo.

## 4 · Los folios que se conservan

El local tiene **treinta** contadores. Se conservan **los que el usuario usa en el día a
día** y **no se inventa ninguno**.

**Se conservan** —el usuario los dice en voz alta, los busca, o los escribe en un papel—:

| Folio | Qué numera | Módulo nuevo |
|---|---|---|
| `CLI` | cliente | Clientes y servicios |
| `SER` | servicio | Clientes y servicios |
| `EVT` | servicio eventual | Clientes y servicios |
| `DOC` | documento por emitir | Cobranza |
| `PAG` | pago | Finanzas |
| `ING` · `EGR` | ingreso · egreso | Finanzas |
| `DEU` | deuda | Finanzas |
| `EMP` | empleado | Personal |
| `FICHA` | ficha técnica | Personal |
| `TEX` | tiempo extra | Personal |
| `NOM` · `PAGN` | nómina · pago de nómina | Nómina |
| `PRE` · `DES` · `RES` | préstamo · botas · resguardo | Nómina |
| `ART` · `UNI` | artículo · unidad | Compras e inventario |
| `COM` | compra | Compras e inventario |
| `ENT` | entrega a personal | Compras e inventario |
| `VEH` · `TEL` | vehículo · línea telefónica | Activos |

**Y el motor ya tiene cinco**, con su contador por Company: `CLI`, `SRV` —que el local llama
`SER`—, `CTR`, `COT` y el número de empleado, más el folio de la ficha técnica. **La norma
dice que no se inventan códigos por simetría**, así que los demás se **abren uno por uno**
cuando llegue su módulo, con su contador propio.

**No se conservan** —nadie los pronuncia; son llaves internas—: el `EMP` de empresa, `SUC`,
`UBI`, `PUE`, `ARE`, `ENF`, `CTA`, `TRF`.

⚠️ **Un defecto del local que conviene no heredar:** empresa y empleado **comparten el
prefijo `EMP`**. Como el de empresa no se conserva, se resuelve solo; pero si alguien pide el
folio de empresa, tiene que llevar otro prefijo.

## 5 · Los propósitos de adjuntos — son DIECISIETE, no catorce

**Corrijo mi propio conteo.** La primera versión de este mapa dijo «catorce tablas
`XxxAttachment`»; son **diecisiete**: los conté por módulo y me faltaron tres de Vehículos.

Cada uno se convierte en un `purpose` de `platform_file_purpose`, con su tipo de archivo
permitido, su tamaño máximo y si es `singleton`:

| Propósito local | Módulo nuevo | Nota |
|---|---|---|
| `EmpresaAttachment` | Clientes y servicios | el motor ya tiene el logo de la empresa |
| `ClienteAttachment` | Clientes y servicios | **ya existe**: documento y logo del cliente |
| `DocumentoPorEmitirAttachment` | Cobranza | el PDF y el XML del documento emitido |
| `PagoAttachment` | Finanzas | comprobante de pago |
| `IngresoAttachment` · `EgresoAttachment` | Finanzas | |
| `ComplementoPagoAttachment` | Finanzas | complemento de pago del SAT |
| `EmpleadoAttachment` | Personal | **ya existe**: documento, foto y expediente |
| `PagoNominaAttachment` | Nómina | |
| `CompraAttachment` | Compras e inventario | factura del proveedor |
| `AsignacionAttachment` | Compras e inventario | el vale firmado de una entrega |
| `MovimientoInventarioAttachment` | Compras e inventario | |
| `VehiculoAttachment` | Activos | |
| `VehiculoDocumentoAttachment` | Activos | tarjeta de circulación, póliza, verificación |
| `VehiculoMantenimientoAttachment` | Activos | |
| `RecargaLineaTelefonicaAttachment` | Activos | comprobante de recarga |
| `ServicioEventualDocumentoFiscalAttachment` | Clientes y servicios | |

**Tres ya existen en el motor** —empresa, cliente y empleado—, así que quedan **catorce por
abrir**, y cada uno es **una fila** de `platform_file_purpose` con sus reglas, no una tabla
nueva.

## El orden de mudanza, con los siete módulos

| | Módulo | Por qué ahí |
|---|---|---|
| **1** | **Personal** | en marcha (M1–M5). El único con backend cerrado, y es el medidor que cobra. Se lleva dentro **tiempos extra** y la **vacante operativa** |
| **2** | **Clientes y servicios** | ya tiene endpoints, y es lo que hace que una asignación signifique algo. Incluye **contratos** —que el motor ya tiene y el local no— y los **eventuales** (5D.10G) |
| **3** | **Cobranza** | depende de servicios, líneas y vigencias. **Se rediseña** contra la 5D.11 |
| **4** | **Finanzas** | después de Cobranza, porque los cobros alimentan las cuentas |
| **5** | **Nómina** | depende de Personal **y** del sueldo con vigencias (M2). Se lleva los **descuentos a personal** y el **archivo histórico de sólo consulta** |
| **6** | **Compras e inventario** | casi independiente. Puede adelantarse si hace falta |
| **7** | **Activos** | el último del dominio, y antes hay que decidir **la forma del tipo** |
| **—** | Tablero, búsqueda, reportes, notificaciones | al final por definición: antes no tienen de dónde leer |

**Y antes del segundo módulo, las tres decisiones transversales.** Se vuelven caras si se
descubren a la mitad del cuarto.

## Resumen, con la agrupación nueva

| Módulo | Ya existe en el motor | Huecos principales | Tamaño |
|---|---|---|---|
| **Personal** | **~85 %** con la 0046 | sueldo con vigencias (M2) · conciliación de baja · vacante operativa · **tiempos extra** | **mediano** |
| **Clientes y servicios** | **~75 %** | **eventuales** (5D.10G, con su choque de diseño) · ubicación como entidad | **grande** |
| **Cobranza** | **0 %** | todo, y **se rediseña** contra la 5D.11 | **grande** |
| **Finanzas** | **0 %** | todo | **grande** |
| **Nómina** | **0 %** | todo · **descuentos a personal** · el **archivo histórico** de sólo consulta | **grande** |
| **Compras e inventario** | **0 %** | todo; y decidir si se siguen unidades una por una | **grande** |
| **Activos** | **0 %** | todo, y **la forma del tipo** es la primera decisión | **grande** |
| _Usuarios y accesos_ | **100 %** | ninguno | **hecho** |
| _Bóveda_ | ~20 % | el almacén de secretos. **Fuera de la v1** | chico |
| _Respaldo_ | n/a | **desaparece**; decidir «exportar mis datos» | chico |
| _Tablero · búsqueda · reportes · notificaciones_ | n/a | se mudan al final | **mediano** |

**Siete módulos, y cinco empiezan en cero.** Lo que cambia respecto a la primera versión de
este resumen no es el trabajo que falta: es que ahora **cada hueco tiene un dueño**, y
telefonía dejó de ser un módulo que no se podía vender.

### ✅ DECIDIDO el 16 de octubre de 2026 — eventuales

| | |
|---|---|
| **Cliente** | **opcional.** Hay posadas de empresas que no son clientes, y obligarlo impediría registrarlas |
| **Estado de pago** | vive **sólo en Finanzas**. El eventual registra lo acordado; quién pagó y cuándo se contesta en un solo sitio |
| **Documento fiscal** | **apunta al eventual**, desde Cobranza. El dato no se pierde: cambia de lado |
| **Facturar** | se piden **los datos fiscales del RECEPTOR**, que **puede ser distinto del solicitante** |

Lo último no es un detalle de captura: significa que el eventual necesita **saber a quién se
le factura** sin suponer que es quien lo pidió. En RISEG ONE ya es así —«receptor fiscal ≠
solicitante»— y en el motor se expresa con la razón social (`fiscal_entity`), que puede no
ser la del cliente y existir incluso sin cliente.

### ✅ DECIDIDO el 16 de octubre de 2026 — la importación de asignaciones

**Ninguna asignación se importa sin servicio o sucursal.** Una que no lo tenga **se LISTA
para que lo decida una persona. No se inventa.**

Y no es una preferencia de estilo: es la misma regla que la `0012` escribió al negarse a
poner una sucursal donde faltaba un servicio —*«un dato falso que después nadie
distinguiría del verdadero»*— y la razón por la que el `CHECK` del destino entra
`NOT VALID` en vez de rellenar lo que falte para que cuadre.

**Lo que obliga a construir:** el importador necesita **dos salidas**, no una.

| Salida | Qué lleva |
|---|---|
| Lo importado | las asignaciones con destino claro, que entran con él |
| **La lista de pendientes** | una fila por asignación sin destino, con lo que sí se sabe —empleado, puesto, fechas— para que alguien diga si estaba en un servicio o cubriendo una zona |

**Un importador que termina «bien» habiendo adivinado destinos es peor que uno que termina
con una lista:** el segundo deja trabajo visible, y el primero deja datos falsos que nadie
va a volver a mirar.

En RISEG ONE casi toda asignación **sí tiene servicio** —`AsignacionServicio.servicioId` es
obligatorio— y la sucursal vive en el empleado, así que la lista debería salir corta. Lo que
no se puede es suponerlo antes de mirar: **el conteo es parte de la etapa de importación**,
y sale antes de escribir la primera fila.

---

### ✅ DECIDIDO el 16 de octubre de 2026 — «Fiscal / No fiscal» se renombra al importar

**En la nube se llama «Nómina registrada / Pago complementario»**, en pantallas y documentos.

| Hoy | En la nube | En el código |
|---|---|---|
| `montoFiscal` | **«Nómina registrada»** | `registered_payroll_amount_minor` |
| `montoNoFiscal` | **«Pago complementario»** | `payroll_complement_amount_minor` |

**Nombres neutros en el código: nada que diga `fiscal` ni `no_fiscal`.**

#### Lo que la importación tiene que saber, porque no es lo que el nombre sugería

Se revisó el código antes de escribir esto, y **«fiscal / no fiscal» no clasifica personas.
Divide un importe.**

- **No existe ninguna bandera en `Empleado`.** El único campo con esa palabra es
  `codigoPostalFiscal`, que es un domicilio y no tiene nada que ver.
- Lo que existe son **dos columnas en `NominaEmpleado`** —una persona en una nómina
  concreta—: `montoFiscal` y `montoNoFiscal`, con la invariante
  `montoFiscal + montoNoFiscal == totalAPagar`.
- **Por omisión todo va en `montoFiscal`.** Se edita a mano por persona y por nómina, y
  entonces se marca `distribucionModificadaManualmente`.
- **Una vez editada se conserva tal cual, siempre.** Si el total cambia y deja de sumar, no
  se reparte la diferencia en silencio: se marca `distribucionPendienteRevision`, que
  **bloquea el cierre de la nómina**.
- Es **una sola nómina**, nunca dos, y el pago genera **un solo `Egreso`**.

#### Las tres consecuencias para la importación

1. **No se importa ninguna clasificación de personal, porque no existe.** Si el importador
   buscara un «tipo fiscal» del empleado no lo encontraría, y el riesgo real es que alguien
   lo **invente** derivándolo de la última nómina. **No se deriva.**
2. **La división viaja con las nóminas históricas**, que se importan como **archivo de sólo
   consulta** (ver «Las nóminas históricas se importan, pero de SÓLO CONSULTA»). Ahí los dos
   importes se conservan tal cual, con el nombre nuevo.
3. **El renombre es de etiqueta, no de dato.** Ninguna cifra cambia.

#### Por qué el nombre habla del dinero y no de la persona

La primera propuesta fue «Con alta en IMSS / Sin alta en IMSS», y **se descartó por lo que
el código acababa de demostrar**: esa etiqueta describe a una **persona**, y el dato
describe un **importe**. Como la misma persona puede llevar parte en cada columna, se habría
leído como que alguien está «medio dado de alta» — un nombre que **afirma algo falso del
empleado**, que es peor que el término interno al que venía a sustituir.

**«Nómina registrada» y «Pago complementario» hablan del dinero**, y no prometen ningún cálculo
legal — que es justo lo que esta nómina no hace.

#### Y por qué «Pago complementario» y no «Complemento» a secas

Porque **«Complemento» ya significa otra cosa en este mismo sistema**: el `ComplementoPago`
de Finanzas es el **complemento de pago del SAT**, un documento fiscal, y está en este mismo
mapa. Dos conceptos distintos con el mismo nombre, uno en Nómina y otro en Finanzas, es una
confusión garantizada el día que alguien los vea en la misma pantalla.

**«Pago complementario» no se puede confundir con «Complemento de pago»**, y eso es todo lo
que se le pide a un nombre.

El detalle está en el diseño de M2 del backend (`docs/m2-sueldo-con-vigencias.md`, sección
6) y anotado en `docs/redaccion.md` de Console.

---

### 📌 Anotado para Nómina — la regla de mensual a diario, SIN decidir

Se registra **tal como está medida en el código de RISEG ONE**, para que la decisión se tome
con el dato enfrente. **No se decide aquí.**

```
pagoPorDia         = redondear(sueldoMensualUtilizado / 30)
descuentoPorFaltas = faltas × pagoPorDia
```

**El mes vale 30 días**, tenga 28 o 31. Y **`sueldoMensualUtilizado` es el sueldo del ÚLTIMO
tramo** que cubre el último día pagable, **nunca un promedio**.

**El importe base NO usa esa misma regla.** Son dos fórmulas, según la cobertura:

| Caso | Importe del tramo |
|---|---|
| **Cobertura completa** | `sueldoMensual × díasReales / (2 × díasRealesDelPeriodo)` |
| **Cobertura parcial** (alta, baja o reingreso dentro del periodo) | `sueldoMensual × díasReales / 30` |

Con un solo tramo, la primera se reduce exactamente a `sueldoMensual / 2`. **Existe por un
error real**: con `/ 30`, un cambio de servicio a mitad de una **segunda quincena de 31
días** convertía el periodo en «16 días pagados».

**El bono nunca se prorratea entre tramos:** se toma el del último.

✅ **DECIDIDO el 25 de octubre de 2026 — compromiso CP-12 de Nómina:** **el mes vale 30
días**, el **salario diario es el mensual ÷ 30** y **la quincena son 15 días fijos**, sin
importar si el mes tiene 28 o 31. Es lo mismo que hace RISEG ONE, y trae su consecuencia
conocida: el pago por día se **redondea** antes de multiplicar, así que **15 faltas no dan
exactamente medio sueldo**, y eso es correcto.

⏳(D-43) **Lo único que sigue abierto de este párrafo:** si el descuento por faltas debería
ponderarse como se pondera el importe base. Hoy **no** se pondera, la asimetría es
deliberada, y conviene volver a mirarla cuando toque Nómina.

**Y lo que NO se va a hacer:** la nómina de Administra es un **cálculo interno** de cuánto
se le paga a cada quien. **No calcula SAT, IMSS ni ISR**, y por lo tanto **no existe el
salario diario integrado** ni ningún concepto derivado de él.
