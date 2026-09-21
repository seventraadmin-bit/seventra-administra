# Mapa Caso de uso → Permiso → Punto de enforcement (Etapa 11C)

Referencia del proyecto: qué permiso exige cada operación de escritura protegida y, sobre
todo, **dónde se verifica de forma autoritativa** — el punto que sigue rechazando la
operación aunque una pantalla tenga un bug y muestre un botón que no debería, o aunque el
caller nunca pase por ningún diálogo. Ver `project_riseg_one_etapa_11c_...md` en memoria
para el razonamiento arquitectónico completo (fue corregido tras el rechazo explícito de
Marlon a la primera versión de esta etapa).

**Mecanismo único**: `autorizarUseCase()` (`lib/core/permissions/authorization_service.dart`)
es el único punto que evalúa `AuthorizationService.verificar(codigo)`. Se invoca desde
exactamente uno de dos lugares por operación — nunca ambos, para no duplicar la regla:

- **Controller** (`@riverpod class XController`) cuando la UI ya llama
  `ref.read(xControllerProvider.notifier).metodo(...)` — el método del Controller envuelve la
  llamada al caso de uso con `autorizarUseCase`.
- **Fachada `Provider`** (`xAutorizadoProvider` en el `..._providers.dart` del dominio) cuando
  la UI llama un caso de uso directo sin Controller de por medio — el `Provider` expone un
  cierre que aplica `autorizarUseCase` antes de invocar el caso de uso real. Existe porque
  `WidgetRef` (diálogos) y `Ref`/`ProviderContainer` (Controllers, pruebas) no son
  intercambiables en este Riverpod, así que la fachada tiene que ser un `Provider`, no una
  función suelta.

En ambos casos, la verificación reutiliza la variante sellada `XxxErrorInesperado` que cada
caso de uso ya tenía (o que se le agregó ex profeso para esta etapa, documentado abajo donde
aplica) — no se deformó ningún tipo de dominio para introducir permisos.

Los diálogos pueden seguir consultando `permissionServiceProvider`/`authorizationServiceProvider`
para ocultar/deshabilitar botones (UX), pero ya no repiten la verificación — el punto listado
en la columna "Enforcement" de cada tabla es el único lugar donde `verificar()` realmente se
evalúa para esa operación.

**Lecturas protegidas**: las fachadas públicas que exponen datos sensibles de un módulo
distinto embebidos en la pantalla de otro (ej. Inventario/Vehículos/Telefonía/Personal
mostrados dentro del expediente de otro dominio) se gatean en el widget con
`ref.watch(permissionServiceProvider).hasCode('modulo.ver')`. Las consultas internas que un
caso de uso hace a otro dominio como plomería (ej. Compras leyendo Artículos de Inventario
para componer una Compra) NO se gatean — el permiso ya se validó en la puerta de entrada real
que el usuario invocó.

Un Usuario Maestro (`esMaestro: true`) pasa cualquier verificación automáticamente — nunca
tiene filas en `PermisoUsuario`, y las operaciones compuestas (ej. Compra → Inventario +
Egreso) nunca exigen un permiso secundario sobre los dominios que solo componen internamente.

Catálogo completo de módulos/acciones: `lib/core/permissions/modulos_permiso.dart`.

## Personal

| Caso de uso | Permiso | Enforcement |
|---|---|---|
| `CrearEmpleadoUseCase` | `personal.crear` | `crearEmpleadoAutorizadoProvider` (fachada) |
| `CorregirEmpleadoUseCase` | `personal.modificar` | `corregirEmpleadoAutorizadoProvider` (fachada) |
| `RegistrarBajaLaboralUseCase` | `personal.modificar` | `registrarBajaLaboralAutorizadoProvider` (fachada) |
| `RegistrarReingresoUseCase` | `personal.modificar` | `registrarReingresoAutorizadoProvider` (fachada) |
| `CambiarVigenciaSueldoAsignacionUseCase` (sueldo/bono de una Asignación) | `personal.cambiarSueldo` | `cambiarVigenciaSueldoAsignacionAutorizadoProvider` (fachada) |
| `GenerarFichaTecnicaEmpleadoUseCase` | `personal.ver` (Etapa 1B — antes `personal.crear`, sin razón real: generar la ficha de un Empleado existente no lo crea) | `generarFichaTecnicaEmpleadoAutorizadoProvider` (fachada) |
Lecturas protegidas: `EmpleadoExpedienteScreen` gatea las secciones embebidas de
Inventario/Vehículos/Telefonía con `inventario.ver`/`vehiculos.ver`/`telefonia.ver`.

## Descuentos Programados al Personal

Sin ruta propia en el Shell — vive anidado bajo Personal, mismo criterio que Tiempos
Extra. El antiguo `personal.gestionarDescuentos` (Etapa 15) se dividió en `descuentos.ver`/
`crear`/`corregir`/`cancelar` — acciones financieras distintas otorgables por separado.
`descuentos.corregir` gatea a la vez `ReprogramarCuotasPendientesUseCase` y
`CorregirDescuentoProgramadoUseCase` (misma facultad).

| Caso de uso | Permiso | Enforcement |
|---|---|---|
| `RegistrarDescuentoProgramadoUseCase` (préstamo/botas — un préstamo con `cuentaFinancieraId` genera un Egreso real, Etapa "Cierre del ciclo financiero") | `descuentos.crear` | `registrarDescuentoProgramadoAutorizadoProvider` (fachada) |
| `ReprogramarCuotasPendientesUseCase` | `descuentos.corregir` | `reprogramarCuotasPendientesAutorizadoProvider` (fachada) |
| `CorregirDescuentoProgramadoUseCase` | `descuentos.corregir` | `corregirDescuentoProgramadoAutorizadoProvider` (fachada) |
| `CancelarSaldoDescuentoProgramadoUseCase` (revierte el Egreso del desembolso solo si nada se ha recuperado todavía) | `descuentos.cancelar` | `cancelarSaldoDescuentoProgramadoAutorizadoProvider` (fachada) |
| `EliminarDescuentoProgramadoFisicamenteUseCase` | Ninguno — `exigirMaestro` | `eliminarDescuentoProgramadoFisicamenteAutorizadoProvider` (fachada) |

Lectura: `DescuentosPersonalController.tieneDescuentos` gatea la carga de datos con
`descuentos.ver` — barrera real independiente de si la pestaña se oculta en la UI.

## Tiempos Extra

Sin ruta propia en el Shell — vive anidado bajo Personal, mismo criterio que
`personal.gestionarDescuentos`. Registrar/corregir/cancelar mueven dinero real, así que son 3
códigos separados en vez del único `personal.gestionarTiemposExtra` de antes (Etapa "corrección
real de Tiempo Extra": pedido explícito de Marlon — acciones financieras distintas deben poder
otorgarse independientemente).

| Caso de uso | Permiso | Enforcement |
|---|---|---|
| `RegistrarTiempoExtraUseCase` | `tiempoExtra.crear` | `registrarTiempoExtraAutorizadoProvider` (fachada) |
| `CorregirTiempoExtraUseCase` | `tiempoExtra.corregir` | `corregirTiempoExtraAutorizadoProvider` (fachada) |
| `CancelarTiempoExtraUseCase` | `tiempoExtra.cancelar` | `cancelarTiempoExtraAutorizadoProvider` (fachada) |
| `EliminarTiempoExtraFisicamenteUseCase` | Ninguno — `exigirMaestro` | `eliminarTiempoExtraFisicamenteAutorizadoProvider` (fachada) |

## Nómina

| Caso de uso | Permiso | Enforcement |
|---|---|---|
| `GenerarNominaUseCase` | `nomina.crear` | `NominasController.generar` |
| `ActualizarDesdePersonalUseCase` | `nomina.modificar` | `NominasController.actualizarDesdePersonal` |
| `ActualizarRenglonNominaUseCase` | `nomina.modificar` | `NominasController.actualizarRenglon` |
| `CerrarNominaUseCase` | `nomina.cerrar` | `NominasController.cerrar` |
| Registrar pago de Nómina | `nomina.pagar` | `NominasController.registrarPago` |
| Cancelar pago de Nómina | `nomina.pagar` | `NominasController.cancelarPago` |
| Generar PDF de dispersión de Nómina | `nomina.pagar` | `NominasController.generarDispersionPdf` |

`CorregirPagoNominaUseCase` y `AdjuntarComprobantePagoNominaUseCase` no están conectados a
ningún botón de UI todavía — sin guard, documentado como pendiente si algún día se exponen.

## Finanzas

| Caso de uso | Permiso | Enforcement |
|---|---|---|
| Registrar Ingreso / Egreso | `finanzas.crear` | `IngresosController.registrarManual` / `EgresosController.registrar` |
| Registrar Pago aplicado a CxC | `finanzas.crear` | `registrarPagoAplicadoAutorizadoProvider` (fachada) |
| Registrar Complemento de pago | `finanzas.crear` | `registrarComplementoPagoAutorizadoProvider` (fachada) |
| Corregir Ingreso / Egreso | `finanzas.modificar` | `IngresosController.corregir` / `EgresosController.corregir` |
| Corregir Pago / Complemento de pago | `finanzas.modificar` | `PagosController.corregir` / `ComplementosController.corregir` |
| Cancelar Ingreso / Egreso / Pago / Complemento de pago | `finanzas.archivar` | `IngresosController.cancelar` / `EgresosController.cancelar` / `PagosController.cancelar` / `ComplementosController.cancelar` |

## Compras

| Caso de uso | Permiso | Enforcement |
|---|---|---|
| `RegistrarCompraUseCase` | `compras.crear` | `ComprasController.registrarCompra` |
| `CorregirCompraUseCase` | `compras.crear` (el catálogo de Compras no tiene código `modificar`; corregir reutiliza `crear`) | `ComprasController.corregirCompra` |
| `CancelarCompraUseCase` | `compras.archivar` | `ComprasController.cancelarCompra` |

La composición Compra → Inventario + Egreso no exige `inventario.crear`/`finanzas.crear`
adicional — solo `compras.crear` en la puerta de entrada real (verificado con prueba
dedicada en `authorization_service_test.dart`).

## Inventario

| Caso de uso | Permiso | Enforcement |
|---|---|---|
| `CrearArticuloUseCase`, `CrearCategoriaArticuloUseCase`, `CrearVarianteArticuloUseCase` | `inventario.crear` | `ArticulosController.crearArticulo` / `.crearCategoria` / `.crearVariante` |
| `RegistrarEntradaUseCase` / `RegistrarEntradaUnidadUseCase` | `inventario.crear` | `ArticulosController.registrarEntrada` / `.registrarEntradaUnidad` |
| `CrearAsignacionUseCase` (asignar artículo) | `inventario.crear` | `crearAsignacionAutorizadoProvider` (fachada) |
| `CorregirArticuloUseCase` | `inventario.modificar` | `ArticulosController.corregirArticulo` |
| `RegistrarAjusteUseCase` | `inventario.modificar` | `ArticulosController.registrarAjuste` |
| `AdjuntarComprobanteMovimientoUseCase` | `inventario.modificar` | `ArticulosController.adjuntarComprobante` |
| `CerrarAsignacionUseCase` (devolver / reportar daño-pérdida) | `inventario.modificar` | `cerrarAsignacionAutorizadoProvider` (fachada) |
| `ReemplazarAsignacionUseCase` | `inventario.modificar` | `reemplazarAsignacionAutorizadoProvider` (fachada) |
| `AdjuntarResguardoFirmadoUseCase` | `inventario.modificar` | `adjuntarResguardoFirmadoAutorizadoProvider` (fachada) |
| `RegistrarBajaUseCase` / `RegistrarBajaUnidadUseCase` | `inventario.archivar` | `ArticulosController.registrarBaja` / `.registrarBajaUnidad` |
| `ArchivarCategoriaArticuloUseCase` | `inventario.archivar` | `ArticulosController.archivarCategoria` |
| `ArchivarArticuloUseCase` | `inventario.archivar` | `ArticulosController.archivarArticulo` |
| `ArchivarVarianteArticuloUseCase` | `inventario.archivar` | `ArticulosController.archivarVariante` |

`GenerarDocumentoResguardoUseCase` no persiste nada (solo genera un PDF de lo ya existente)
— no requiere guard propio, cubierto por el `inventario.ver` implícito de estar en la
pantalla. `CancelarDescuentoInventarioUseCase` no está conectado a ningún botón de UI
todavía — mismo caso que `CorregirPagoNominaUseCase` en Nómina.

Lecturas protegidas: `EmpleadoExpedienteScreen` (Personal) gatea la sección de Inventario
asignado con `inventario.ver`.

## Vehículos

| Caso de uso | Permiso | Enforcement |
|---|---|---|
| `CrearVehiculoUseCase` | `vehiculos.crear` | `VehiculosController.crearVehiculo` |
| `AsignarVehiculoUseCase` | `vehiculos.operar` | `VehiculosController.asignar` |
| `RegistrarDocumentoVehiculoUseCase` | `vehiculos.operar` | `registrarDocumentoVehiculoAutorizadoProvider` (fachada) |
| `AdjuntarArchivoDocumentoVehiculoUseCase` | `vehiculos.operar` | `adjuntarArchivoDocumentoVehiculoAutorizadoProvider` (fachada) |
| `CorregirDocumentoVehiculoUseCase` | `vehiculos.operar` | `corregirDocumentoVehiculoAutorizadoProvider` (fachada) |
| `RegistrarMantenimientoVehiculoUseCase` | `vehiculos.operar` | `registrarMantenimientoVehiculoAutorizadoProvider` (fachada) |
| `AdjuntarComprobanteMantenimientoVehiculoUseCase` | `vehiculos.operar` | `adjuntarComprobanteMantenimientoVehiculoAutorizadoProvider` (fachada) |
| `CorregirMantenimientoVehiculoUseCase` | `vehiculos.operar` | `corregirMantenimientoVehiculoAutorizadoProvider` (fachada) |
| `CancelarMantenimientoVehiculoUseCase` | **`vehiculos.cancelar`** | `cancelarMantenimientoVehiculoAutorizadoProvider` (fachada) |
| `CorregirVehiculoUseCase` | `vehiculos.modificar` | `VehiculosController.corregirVehiculo` |
| `CambiarAsignacionVehiculoUseCase` / `RetirarAsignacionVehiculoUseCase` | `vehiculos.modificar` | `VehiculosController.cambiarAsignacion` / `.retirarAsignacion` |
| `RegistrarKilometrajeVehiculoUseCase` | `vehiculos.modificar` | `VehiculosController.registrarKilometraje` |
| `FinalizarMantenimientoVehiculoUseCase` | `vehiculos.modificar` | `VehiculosController.finalizarMantenimiento` |
| `CambiarEstatusVehiculoUseCase` | `vehiculos.modificar` | `VehiculosController.cambiarEstatus` |
| `ActualizarFotografiaVehiculoUseCase` | `vehiculos.modificar` | `VehiculosController.actualizarFotografia` |
| `DarDeBajaVehiculoUseCase` | `vehiculos.archivar` | `VehiculosController.darDeBaja` |
| `EliminarVehiculoFisicamenteUseCase` | **Maestro** (`exigirMaestro`, sin código de permiso) | `eliminarVehiculoFisicamenteAutorizadoProvider` |

`vehiculos.cancelar` (schemaVersion 80) es la única facultad de Vehículos que **revierte
dinero real**: anular un mantenimiento cancela su `Egreso` de `CuentaFinanciera`, o libera
su cargo de TDC con un ajuste negativo. Va aparte de `vehiculos.operar` por el mismo
criterio ya vigente en `compras.cancelar`, `tiempoExtra.cancelar` y `nomina.cancelarPago`:
quien captura la operación no necesariamente puede revertirla. Corregir se queda en
`vehiculos.operar` — ajusta el importe, no lo devuelve.

Lecturas protegidas: `EmpleadoExpedienteScreen` (Personal) gatea la sección de Vehículo
asignado con `vehiculos.ver`.

## Telefonía

| Caso de uso | Permiso | Enforcement |
|---|---|---|
| `CrearLineaTelefonicaUseCase` | `telefonia.crear` | `TelefoniaController.crearLinea` |
| `AsignarLineaTelefonicaUseCase` | `telefonia.crear` | `asignarLineaTelefonicaAutorizadoProvider` (fachada) |
| `RegistrarRecargaLineaTelefonicaUseCase` | `telefonia.crear` | `registrarRecargaLineaTelefonicaAutorizadoProvider` (fachada) |
| `CorregirLineaTelefonicaUseCase` | `telefonia.modificar` | `TelefoniaController.corregirLinea` |
| `CambiarEstatusLineaTelefonicaUseCase` | `telefonia.modificar` | `TelefoniaController.cambiarEstatus` |
| `CambiarAsignacionLineaTelefonicaUseCase` / `RetirarAsignacionLineaTelefonicaUseCase` | `telefonia.modificar` | `cambiarAsignacionLineaTelefonicaAutorizadoProvider` / `retirarAsignacionLineaTelefonicaAutorizadoProvider` (fachadas) |
| `AsociarEquipoLineaTelefonicaUseCase` / `CambiarEquipoLineaTelefonicaUseCase` / `RetirarEquipoLineaTelefonicaUseCase` | `telefonia.modificar` | `asociarEquipoLineaTelefonicaAutorizadoProvider` / `cambiarEquipoLineaTelefonicaAutorizadoProvider` / `retirarEquipoLineaTelefonicaAutorizadoProvider` (fachadas) |
| `DarDeBajaLineaTelefonicaUseCase` | `telefonia.archivar` | `TelefoniaController.darDeBaja` |

`CambiarEstatusLineaTelefonicaUseCase` no tenía ningún guard antes de esta corrección (hueco
real, cerrado ahora junto con el resto del dominio).

Lecturas protegidas: `EmpleadoExpedienteScreen` (Personal) gatea la sección de Línea
telefónica asignada con `telefonia.ver`.

## Organización

| Caso de uso | Permiso | Enforcement |
|---|---|---|
| `CrearAreaUseCase` | `organizacion.crear` | `crearAreaAutorizadoProvider` (fachada) |
| `ActualizarAreaUseCase` | `organizacion.modificar` | `actualizarAreaAutorizadoProvider` (fachada) |
| `ActivarAreaUseCase` | `organizacion.archivar` | `activarAreaAutorizadoProvider` (fachada; `ActivarAreaUseCase` no tiene tipo sellado — devuelve `AreaData` a secas — la denegación usa `null`, valor que la operación nunca produce por sí misma) |
| `DesactivarAreaUseCase` | `organizacion.archivar` | `desactivarAreaAutorizadoProvider` (fachada; se le agregó `DesactivarAreaErrorInesperado`, variante que no existía) |
| `CrearPuestoUseCase` | `organizacion.crear` | `crearPuestoAutorizadoProvider` (fachada) |
| `PuestoExpedienteController.guardar` | `organizacion.modificar` | `PuestoExpedienteController.guardar` |
| `PuestoExpedienteController.cambiarCicloVida` (archivar/reactivar) | `organizacion.archivar` | `PuestoExpedienteController.cambiarCicloVida` |
| `CrearSucursalUseCase` | `organizacion.crear` | `crearSucursalAutorizadoProvider` (fachada; retorna `Result<SucursalData>` — denegación reutiliza `PermissionFailure`, ya definida en `core/error/failure.dart` y sin uso real hasta ahora) |
| `SucursalExpedienteController.guardar` / `.cambiarEstadoOperativo` | `organizacion.modificar` | `SucursalExpedienteController` |
| `UbicacionesArbolController.agregarUbicacion` | `organizacion.crear` | `UbicacionesArbolController.agregarUbicacion` |
| `UbicacionesArbolController.moverUbicacion` | `organizacion.modificar` | `UbicacionesArbolController.moverUbicacion` |
| Editar Empresa (registro único, sin alta/baja) | `organizacion.modificar` | `EmpresaExpedienteController.guardar` |
| `GenerarTarjetaFiscalPdfUseCase` (Etapa 1B — antes sin ningún gate) | `organizacion.ver` (solo lectura/generación de documento sobre datos de Empresa ya visibles en su ficha, nunca escribe en BD) | `generarTarjetaFiscalPdfAutorizadoProvider` (fachada) |

## Comercial

| Caso de uso | Permiso | Enforcement |
|---|---|---|
| `CrearClienteUseCase` | `comercial.crear` | `crearClienteAutorizadoProvider` (fachada; `Result<ClienteData>` — denegación vía `PermissionFailure`, mismo criterio que Sucursal) |
| `ClienteExpedienteController.guardar` / `.cambiarEstatus` / `.agregarContacto` / `.actualizarContacto` / `.agregarEntidadFiscal` / `.actualizarEntidadFiscal` / `.guardarDomicilioFiscal` | `comercial.modificar` | `ClienteExpedienteController` |
| `ClienteExpedienteController.archivarContacto` | `clientes.archivar` | `ClienteExpedienteController.archivarContacto` (`ArchivarContactoResultado` distingue motivo faltante; denegación de permiso vía `null`) |
| `ClienteExpedienteController.cambiarCicloVidaEntidadFiscal` (archivar/reactivar) | `clientes.archivar` | `ClienteExpedienteController.cambiarCicloVidaEntidadFiscal` |
| `crearServicioAutorizadoProvider` | `comercial.crear` | fachada, `organizacion_providers.dart` |
| `ServicioExpedienteController` — 18 métodos de escritura (`guardar`, `cambiarEstatus`, `asignarEntidadFiscal`, `asignarResponsableCliente`, `asignarSucursalAdministrativa`, `guardarDireccionOperativa`, `cambiarVigenciaConfiguracionCobro`, `cerrarConfiguracionCobro`, `cancelarVigenciaProgramadaConfiguracionCobro`, `actualizarObservacionesConfiguracionCobroVigencia`, `cambiarVigenciaLinea`, `cerrarLineaComercial`, `cancelarVigenciaProgramada`, `actualizarAnotacionesVigencia`, `guardarSueldoReferencia`) | `comercial.modificar` | `ServicioExpedienteController` |
| `ServicioExpedienteController.guardarResponsableInterno` | `comercial.modificar` | `ServicioExpedienteController.guardarResponsableInterno` (`GuardarResponsableInternoUseCase` no tiene tipo sellado — denegación vía `null`, mismo criterio que `ActivarAreaUseCase`) |
| `ServicioExpedienteController.agregarLineaComercial` / `.agregarConfiguracionCobro` | `comercial.crear` | `ServicioExpedienteController` |
| `AgendaController.generar` (Agenda automática) | `comercial.crear` | `AgendaController.generar` (`GenerarAgendaUseCase` nunca falla por reglas de negocio — no tiene tipo sellado; denegación vía `null`) |
| `AgendaController.crearManual` | `comercial.crear` | `AgendaController.crearManual` |
| `AgendaController.cambiarEstatus` / `.actualizarAjusteManual` / `.registrarEmision` / `.corregirDatosEmision` / `.registrarEnvio` / `.adjuntarArchivo` / `.reemplazarArchivo` | `comercial.modificar` | `AgendaController` |

Lecturas protegidas: `ServicioExpedienteScreen` gatea las secciones embebidas de
Inventario/Vehículos/Telefonía/Personal con `inventario.ver`/`vehiculos.ver`/
`telefonia.ver`/`personal.ver`.

## Servicios Eventuales

Subdominio de Comercial (schemaVersion 87). Las facultades que **mueven dinero**
van aparte de las de captura, mismo criterio que `telefonia.recargar` frente a
`telefonia.crear`: pagar a quien cubrió un evento genera un Egreso real o un
cargo a una tarjeta, y revertir ese pago lo deshace.

| Caso de uso | Permiso | Enforcement |
|---|---|---|
| `CrearServicioEventualUseCase` | `serviciosEventuales.crear` | `crearServicioEventualAutorizadoProvider` (fachada) |
| `CorregirServicioEventualUseCase`, `FinalizarServicioEventualUseCase` | `serviciosEventuales.corregir` | fachadas `*AutorizadoProvider` |
| `AgregarParticipanteServicioEventualUseCase`, `RetirarParticipanteServicioEventualUseCase`, `AgregarCoberturaServicioEventualUseCase`, `CorregirCoberturaServicioEventualUseCase`, `AgregarCostoServicioEventualUseCase`, `CorregirCostoServicioEventualUseCase` | `serviciosEventuales.corregir` | fachadas `*AutorizadoProvider` |
| `CancelarServicioEventualUseCase`, `CancelarCoberturaServicioEventualUseCase`, `CancelarCostoServicioEventualUseCase` | `serviciosEventuales.cancelar` | fachadas `*AutorizadoProvider` |
| `PagarCoberturaServicioEventualUseCase`, `PagarCostoServicioEventualUseCase` | `serviciosEventuales.pagar` | fachadas `*AutorizadoProvider` |
| `RevertirPagoCoberturaServicioEventualUseCase`, `RevertirPagoCostoServicioEventualUseCase` | `serviciosEventuales.revertirPago` | fachadas `*AutorizadoProvider` |
| `RegistrarCobroServicioEventualUseCase` | `serviciosEventuales.cobrar` | fachada; vender con cobro inmediato exige la MISMA facultad, comprobada antes de abrir la transacción |
| `RegistrarDocumentoFiscalEventualUseCase`, `CorregirDocumentoFiscalEventualUseCase`, `CancelarDocumentoFiscalEventualUseCase` | `serviciosEventuales.facturar` | fachadas `*AutorizadoProvider`; cancelar un CFDI es facultad fiscal, no comercial |
| `EliminarServicioEventualFisicamenteUseCase` | Maestro-only | `eliminarServicioEventualFisicamenteAutorizadoProvider` (`exigirMaestro`, nunca `PermisoUsuario`) |

No hay `serviciosEventuales.ver`: la ruta `/comercial/eventuales` la gatea
`comercial.ver` a nivel router (`permisoRequeridoParaRuta` sólo lee el primer
segmento de la URL), mismo criterio que Clientes y Servicios.

## Usuarios

| Caso de uso | Permiso | Enforcement |
|---|---|---|
| `CrearUsuarioUseCase`, `CorregirUsuarioUseCase`, `CambiarContrasenaUsuarioUseCase`, `ActivarUsuarioUseCase`, `DesactivarUsuarioUseCase`, `GuardarPermisosUsuarioUseCase` | `usuarios.administrar` | `UsuariosController` (los 6 métodos de escritura) |

`CrearPrimerMaestroUseCase` y `LoginUseCase` son las únicas excepciones documentadas: se
ejecutan sin sesión activa (bootstrap/login), por diseño.

## Eliminar

Ningún caso de uso del proyecto realiza borrado físico (`DELETE`) — toda "eliminación" es
lifecycle suave (`cicloVidaRegistro`, `estatus`). El código `<modulo>.eliminar` existe en el
catálogo por completitud pero no está conectado a ninguna operación — el Maestro no necesita
saltarse ninguna regla porque no existe ninguna operación insegura que saltarse.
