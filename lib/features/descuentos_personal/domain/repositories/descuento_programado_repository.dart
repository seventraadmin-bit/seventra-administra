import 'package:riseg_one/core/database/app_database.dart';

/// Resumen de solo lectura de si un descuento programado es elegible
/// para eliminación física (pedido explícito: "eliminar el movimiento
/// por pruebas" desde un descuento ya cancelado) — insumo del mensaje
/// de confirmación que la UI muestra antes de pedir el motivo.
/// `detalleBloqueo` no nulo significa que alguna cuota ya llegó a
/// `aplicada` (una Nómina real ya la pagó) — esa historia nunca se
/// borra en silencio.
class ResumenEliminacionDescuentoProgramado {
  const ResumenEliminacionDescuentoProgramado({
    required this.existe,
    this.detalleBloqueo,
  });

  final bool existe;
  final String? detalleBloqueo;

  bool get bloqueado => detalleBloqueo != null;
}

sealed class EliminarDescuentoProgramadoFisicamenteResultado {}

class EliminarDescuentoProgramadoFisicamenteExitoso
    extends EliminarDescuentoProgramadoFisicamenteResultado {}

class EliminarDescuentoProgramadoFisicamenteNoExiste
    extends EliminarDescuentoProgramadoFisicamenteResultado {}

/// El descuento no está `cancelado` — la eliminación física de esta
/// obligación solo es alcanzable desde ahí (pedido explícito: el botón
/// vive únicamente en el expediente de un descuento ya cancelado).
class EliminarDescuentoProgramadoFisicamenteNoPermitido
    extends EliminarDescuentoProgramadoFisicamenteResultado {}

/// Al menos una cuota ya está `aplicada` (una Nómina real ya la pagó) —
/// `detalle` siempre nombra cuántas, nunca un mensaje genérico.
class EliminarDescuentoProgramadoFisicamenteTieneDependencias
    extends EliminarDescuentoProgramadoFisicamenteResultado {
  EliminarDescuentoProgramadoFisicamenteTieneDependencias(this.detalle);
  final String detalle;
}

class EliminarDescuentoProgramadoFisicamenteErrorInesperado
    extends EliminarDescuentoProgramadoFisicamenteResultado {
  EliminarDescuentoProgramadoFisicamenteErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Un renglón del plan de recuperación completo, ya resuelto (Etapa 15)
/// — usado por la previsualización del diálogo "Registrar descuento" y
/// por el expediente del descuento (folio de Nómina cuando aplica).
class DescuentoProgramadoConCuotas {
  const DescuentoProgramadoConCuotas({
    required this.descuento,
    required this.cuotas,
  });
  final DescuentoProgramadoEmpleadoData descuento;
  final List<DescuentoProgramadoCuotaData> cuotas;
}

/// Descuentos Programados al Personal (Etapa 15) — préstamos, costo de
/// botas, y futuros tipos, recuperados automáticamente vía Nómina.
/// Ninguna validación de negocio vive aquí (empleado activo, importe >
/// 0, motivo obligatorio para reprogramar/cancelar, etc.) — vive en los
/// casos de uso, como en todo el proyecto. `NominaRepositoryImpl`
/// compone este repositorio (patrón "repositorio compone repositorio",
/// mismo criterio que `AsignacionRepository` para
/// `DescuentoInventario`) para resolver/reservar/aplicar/liberar cuotas
/// dentro de sus propias transacciones.
abstract interface class DescuentoProgramadoRepository {
  Future<DescuentoProgramadoEmpleadoData?> obtenerPorId(String id);

  Future<List<DescuentoProgramadoEmpleadoData>> listarPorEmpleado(
    String empleadoId,
  );

  Future<List<DescuentoProgramadoEmpleadoData>> listarTodos();

  Future<List<DescuentoProgramadoCuotaData>> listarCuotas(
    String descuentoProgramadoId,
  );

  /// Cuántas cuotas NO canceladas tiene cada descuento de [ids], en
  /// una sola consulta agregada.
  ///
  /// Existe porque el numero de cuotas no vive en la obligacion sino
  /// en sus cuotas: pedirlas una por una seria una consulta por
  /// descuento. Los descuentos sin cuotas simplemente no aparecen.
  Future<Map<String, int>> contarCuotasPorDescuento(Iterable<String> ids);

  Future<List<DescuentoProgramadoMovimientoData>> listarMovimientos(
    String descuentoProgramadoId,
  );

  /// El descuento vinculado a [egresoId] (vía su propio `egresoId`,
  /// nunca por concepto/folio en texto) — usado por
  /// `ObtenerOrigenAutomaticoEgresoUseCase` para reconocer el Egreso de
  /// un desembolso (típicamente un préstamo) como automático. Mismo
  /// shape que `PagoNominaRepository.obtenerPorEgresoId`.
  Future<DescuentoProgramadoEmpleadoData?> obtenerPorEgresoId(String egresoId);

  /// `egresoId` de cada `DescuentoProgramadoEmpleado` (un desembolso
  /// real, típicamente un préstamo) cuya `fechaRegistro` cae en el
  /// rango — insumo de `ClasificarEgresosPorOrigenUseCase`, mismo
  /// criterio que `TiempoExtraRepository.listarEgresoIdsEnRango`/
  /// `DeudaRepository.listarEgresoIdsDePagosEnRango`. Un descuento de
  /// recuperación de concepto (ej. botas, sin `egresoId`) nunca
  /// aparece aquí — no existe ningún Egreso que clasificar.
  Future<List<String>> listarEgresoIdsEnRango({DateTime? rangoInicio, DateTime? rangoFin});

  /// Cuotas `pendiente` de [empleadoId] — sin filtrar por fecha (el
  /// llamador, `NominaRepositoryImpl`, decide cuáles ya vencieron contra
  /// la fecha de pago de la Nómina que está resolviendo — nunca
  /// incorporar una cuota futura, ver
  /// `NominaRepositoryImpl._resolverCuotasProgramadasAplicables`).
  Future<List<DescuentoProgramadoCuotaData>> listarCuotasPendientesPorEmpleado(
    String empleadoId,
  );

  /// Cuotas ya `reservada` en [nominaEmpleadoId] — usado por
  /// `guardarRenglon` para no volver a resolver lo que ya está
  /// reservado (mismo criterio que `yaAplicadoPrevio` de
  /// `DescuentoInventario`).
  Future<List<DescuentoProgramadoCuotaData>> listarCuotasReservadasPorRenglon(
    String nominaEmpleadoId,
  );

  /// TODAS las cuotas vinculadas a [nominaEmpleadoId] sin importar su
  /// estatus (`reservada` o `aplicada`) — a diferencia de
  /// [listarCuotasReservadasPorRenglon], usado por la UI
  /// (`RenglonNominaDetalleDialog`) para mostrar la sección
  /// "Deducciones automáticas" tanto en una Nómina Borrador/Cerrada
  /// (cuotas `reservada`) como en una ya Pagada (cuotas `aplicada`).
  /// Mismo criterio que `AsignacionRepository.
  /// listarDescuentosPorNominaEmpleado`.
  Future<List<DescuentoProgramadoCuotaData>> listarCuotasPorRenglon(
    String nominaEmpleadoId,
  );

  /// Crea la obligación completa + sus cuotas `pendiente` + el
  /// movimiento `otorgamiento` — una sola transacción. Si
  /// [cuentaFinancieraId] no es `null`, también crea un `Egreso` real
  /// por [importeOriginal] contra esa cuenta y lo vincula (`egresoId`)
  /// — representa un desembolso real (típicamente un préstamo). Si es
  /// `null` (recuperación de un costo ya pagado en otro módulo, ej.
  /// botas), no se crea ningún `Egreso` — comportamiento sin cambio. La
  /// SEÑAL de si hubo desembolso es la presencia de [cuentaFinancieraId]
  /// aquí, nunca el valor de [tipo].
  Future<DescuentoProgramadoEmpleadoData> registrar({
    required String folio,
    required String empleadoId,
    required String tipo,
    required DateTime fechaRegistro,
    required int importeOriginal,
    String? descripcion,
    String? asignacionOrigenId,
    String? observaciones,
    required List<({int numeroCuota, DateTime fechaProgramada, int importe})>
    cuotas,
    String? cuentaFinancieraId,
    String? beneficiarioEgreso,
    String? formaPagoEgreso,
    String? actorUsuarioId,
  });

  /// `pendiente → reservada`, vincula [nominaEmpleadoId] — nunca toca
  /// `saldoPendiente` (una cuota reservada no es una cuota recuperada,
  /// ver el doc comment de `EstatusDescuentoProgramadoCuota`).
  Future<void> reservarCuotas({
    required List<String> cuotaIds,
    required String nominaEmpleadoId,
  });

  /// `reservada → aplicada` para TODAS las cuotas reservadas en
  /// [nominaEmpleadoId] — el único punto donde `saldoPendiente`
  /// realmente decrece, llamado exclusivamente desde
  /// `PagoNominaRepositoryImpl._aplicarInterna` cuando ese renglón llega
  /// a `estatusPago == 'pagado'`. Si el saldo llega a 0, el padre pasa a
  /// `liquidado`.
  Future<void> aplicarCuotasReservadas({
    required String nominaEmpleadoId,
    String? actorUsuarioId,
  });

  /// `aplicada → reservada` para las cuotas de [nominaEmpleadoId] —
  /// reversa simétrica de [aplicarCuotasReservadas], llamada desde
  /// `PagoNominaRepositoryImpl._cancelarAplicacionInterna` cuando se
  /// cancela un pago ya aplicado. Restaura `saldoPendiente` y
  /// des-liquida el padre si corresponde.
  Future<void> revertirCuotasAplicadasPorCancelacionPago({
    required String nominaEmpleadoId,
    String? actorUsuarioId,
  });

  /// Libera TODAS las cuotas (`reservada` o `aplicada`, cualquiera que
  /// sea su estado real) vinculadas a cualquiera de [nominaEmpleadoIds]
  /// de vuelta a `pendiente`, desvinculando `nominaEmpleadoId`/
  /// `fechaAplicacion` — usado cuando la Nómina completa desaparece
  /// (`eliminarFisicamente` de un Borrador: cuotas siempre `reservada`;
  /// `eliminarCadenaPrueba` de una Nómina Cerrada nunca pagada: mismo
  /// caso; de una Nómina Pagada: cuotas `aplicada`, con
  /// `saldoPendiente` ya decrecido — se restaura y se des-liquida el
  /// padre si corresponde). Nunca cancela, nunca borra la cuota misma —
  /// solo la regresa al pool disponible para una Nómina futura.
  ///
  /// [descuentoProgramadoId] es opcional y acota la operación a las
  /// cuotas de ESE descuento únicamente (uso: `reprogramarCuotasPendientes`/
  /// `cancelarSaldo`, donde liberar debe afectar solo al descuento que
  /// se está corrigiendo — nunca a otro descuento del mismo empleado
  /// que comparta renglón de Nómina). Sin él, libera TODAS las cuotas
  /// vinculadas a [nominaEmpleadoIds] sin importar de qué descuento
  /// sean (uso: `NominaRepositoryImpl` al eliminar una Nómina completa,
  /// donde sí debe liberar cualquier descuento involucrado).
  Future<void> liberarCuotasDeRenglones(
    List<String> nominaEmpleadoIds, {
    String? descuentoProgramadoId,
    String? observacion,
    String? actorUsuarioId,
  });

  /// Solo cuotas `pendiente`/`reservada` (una `reservada` se libera
  /// primero, en la misma transacción) — reemplaza el plan futuro
  /// completo por uno nuevo. Nunca toca una cuota `aplicada`. Registra
  /// `reprogramacion` con el plan anterior y el nuevo.
  Future<void> reprogramarCuotasPendientes({
    required String descuentoProgramadoId,
    required List<({int numeroCuota, DateTime fechaProgramada, int importe})>
    nuevoPlan,
    required String motivo,
    String? actorUsuarioId,
  });

  /// Corrección administrativa y/o de monto total (Etapa 5) — solo
  /// aplicable a un descuento `activo` (verificado por el caso de uso,
  /// nunca aquí). `empleadoId`/`folio` son permanentemente inmutables —
  /// ningún parámetro los acepta. Cuando [nuevoImporteOriginal] cambia,
  /// el llamador (`CorregirDescuentoProgramadoUseCase`) ya validó que no
  /// cae por debajo de lo históricamente aplicado y ya calculó
  /// [nuevoSaldoPendiente] + [nuevoPlanCuotas] (mismo mecanismo exacto
  /// de `reprogramarCuotasPendientes`: libera cuotas `reservada`,
  /// cancela — nunca borra — las reprogramables viejas, inserta el plan
  /// nuevo). `nuevoPlanCuotas == null` dejar las cuotas futuras intactas
  /// (el monto no cambió); `[]` el nuevo saldo pendiente ya es 0.
  /// Recalcula `estatus` (`activo`/`liquidado`) según el saldo final —
  /// nunca `cancelado` (esa transición solo la hace [cancelarSaldo]).
  /// Registra `correccion` con `estadoAnterior`/`estadoNuevo`
  /// (`DiffEvento`, solo campos que cambiaron) — nunca si nada cambió.
  ///
  /// Si el descuento tiene un `egresoId` vinculado (hubo desembolso):
  /// [nuevoCuentaFinancieraId] mueve el MISMO Egreso a otra cuenta
  /// (`Egreso.corregir`, nunca crea uno nuevo); [limpiarCuentaFinancieraId]
  /// lo deja sin cuenta. Un cambio en [nuevoImporteOriginal] también
  /// sincroniza `Egreso.monto` (vía `corregirMonto`) — el Egreso
  /// siempre refleja el desembolso ORIGINAL completo, nunca el saldo
  /// pendiente; corregir el importe original es "arreglar un error de
  /// captura", mismo criterio que Compra/TiempoExtra. Si el descuento
  /// NO tiene `egresoId`, estos dos parámetros son ignorados — nunca se
  /// crea un Egreso donde no existía uno (ver "fuera de alcance" en el
  /// plan de esta etapa).
  Future<DescuentoProgramadoEmpleadoData> corregir({
    required String descuentoProgramadoId,
    String? tipo,
    String? descripcion,
    bool limpiarDescripcion = false,
    String? observaciones,
    bool limpiarObservaciones = false,
    DateTime? fechaRegistro,
    int? nuevoImporteOriginal,
    int? nuevoSaldoPendiente,
    List<({int numeroCuota, DateTime fechaProgramada, int importe})>?
    nuevoPlanCuotas,
    String? nuevoCuentaFinancieraId,
    bool limpiarCuentaFinancieraId = false,
    required String motivo,
    String? actorUsuarioId,
  });

  /// Cancela cuotas `pendiente`/`reservada` (libera la `reservada`
  /// primero), `saldoPendiente → 0` por cancelación, estatus del padre
  /// → `cancelado`. Nunca toca el historial de cuotas ya `aplicada`.
  ///
  /// Si el descuento tiene un `egresoId` vinculado, esta operación
  /// distingue dos semánticas según cuánto se haya recuperado ya vía
  /// Nómina: si NADA se ha recuperado (`saldoPendiente ==
  /// importeOriginal`), también CANCELA ese Egreso — el desembolso
  /// nunca llegó a tener ningún efecto downstream, así que "cancelar"
  /// aquí equivale a "esto nunca debió registrarse" (mismo criterio que
  /// Compra/TiempoExtra: cancelar revierte el efecto financiero cuando
  /// nada lo bloquea). Si YA se recuperó algo, el Egreso NUNCA se toca
  /// — el desembolso histórico ocurrió realmente y no puede
  /// desaparecer; esta llamada se vuelve condonación pura (deja de
  /// cobrar el resto, sin negar lo ya entregado/recuperado).
  Future<void> cancelarSaldo({
    required String descuentoProgramadoId,
    required String motivo,
    String? actorUsuarioId,
  });

  Future<ResumenEliminacionDescuentoProgramado> obtenerResumenEliminacionFisica(
    String descuentoProgramadoId,
  );

  /// Eliminación física extraordinaria (Maestro-only, vía
  /// `exigirMaestro` en el provider — nunca aquí), alcanzable solo
  /// desde un descuento ya `cancelado`. Snapshotea el descuento + todas
  /// sus cuotas + todo su historial de movimientos (+ su Egreso
  /// vinculado, si existe) en `EliminacionFisicaEvento`, y borra todo
  /// el agregado (cascada de FK se encarga de cuotas/movimientos) —
  /// nunca si alguna cuota ya está `aplicada` O `reservada` (una
  /// `reservada` en una Nómina viva debe liberarse primero). Si el
  /// descuento tiene un `egresoId`, ese Egreso siempre llega aquí ya
  /// `cancelado` (invariante garantizada por [cancelarSaldo]: solo se
  /// alcanza `cancelado` sin cuotas `aplicada` cuando nada se recuperó,
  /// y en ese caso [cancelarSaldo] ya canceló el Egreso) — esta
  /// operación solo lo snapshotea y lo borra, nunca decide si
  /// cancelarlo.
  Future<EliminarDescuentoProgramadoFisicamenteResultado> eliminarFisicamente({
    required String descuentoProgramadoId,
    required String motivo,
    String? actorUsuarioId,
  });
}
