import 'package:riseg_one/core/database/app_database.dart';

import '../usecases/eliminar_tiempo_extra_fisicamente_usecase.dart';

/// Costo adicional capturado al registrar — insumo puro para `crear`,
/// nunca una entidad con vida propia fuera de un TiempoExtra.
///
/// Etapa "origen financiero unificado": cada costo tiene su PROPIO
/// origen financiero independiente del pago base y de cualquier otro
/// costo — exactamente uno de `cuentaFinancieraId`/`deudaIdTarjeta`
/// según `formaPago`, nunca ambos ni ninguno (validado en
/// `RegistrarTiempoExtraUseCase`, nunca aquí).
class CostoAdicionalInput {
  const CostoAdicionalInput({
    required this.concepto,
    required this.monto,
    required this.formaPago,
    this.cuentaFinancieraId,
    this.deudaIdTarjeta,
  });
  final String concepto;
  final int monto;
  final String formaPago;
  final String? cuentaFinancieraId;
  final String? deudaIdTarjeta;
}

/// Corrección de UN costo adicional durante `TiempoExtraRepository.
/// corregir` — sealed, mismo patrón exacto que `CorreccionPartida` de
/// Compra. Un costo no mencionado en la lista de cambios permanece sin
/// tocar (ni su fila ni su origen financiero).
sealed class CorreccionCostoAdicional {}

/// Edita concepto/monto/forma de pago/origen de un costo ya existente
/// — el origen puede cambiar de tipo (Cuenta↔TDC) o de contenedor
/// (Cuenta A→Cuenta B, TDC X→TDC Y), a diferencia de Compra: aquí SÍ se
/// permite, es el pedido explícito de esta etapa.
class CorreccionCostoAdicionalEditar extends CorreccionCostoAdicional {
  CorreccionCostoAdicionalEditar({
    required this.costoAdicionalId,
    required this.concepto,
    required this.monto,
    required this.formaPago,
    this.cuentaFinancieraId,
    this.deudaIdTarjeta,
  });
  final int costoAdicionalId;
  final String concepto;
  final int monto;
  final String formaPago;
  final String? cuentaFinancieraId;
  final String? deudaIdTarjeta;
}

/// Agrega un costo adicional nuevo durante la corrección — mismo
/// origen financiero independiente que un costo capturado desde el
/// alta.
class CorreccionCostoAdicionalAgregar extends CorreccionCostoAdicional {
  CorreccionCostoAdicionalAgregar({
    required this.concepto,
    required this.monto,
    required this.formaPago,
    this.cuentaFinancieraId,
    this.deudaIdTarjeta,
  });
  final String concepto;
  final int monto;
  final String formaPago;
  final String? cuentaFinancieraId;
  final String? deudaIdTarjeta;
}

/// Elimina un costo adicional existente — revierte su efecto
/// financiero por completo (según su origen) y borra la fila; el
/// ledger financiero (`MovimientoDeuda`) permanece append-only, nunca
/// se borra un cargo ya aplicado, solo se compensa.
class CorreccionCostoAdicionalQuitar extends CorreccionCostoAdicional {
  CorreccionCostoAdicionalQuitar(this.costoAdicionalId);
  final int costoAdicionalId;
}

/// Una ausencia ya resuelta para insertarse directo como
/// `NominaEmpleadoAusencia` — nombres ya resueltos (Servicio, quien
/// cubrió), nunca un join adicional desde Nómina.
class AusenciaParaNomina {
  const AusenciaParaNomina({
    required this.tiempoExtraId,
    required this.fecha,
    required this.motivoAusencia,
    required this.servicioId,
    required this.servicioNombre,
    required this.nombreCubre,
  });

  final String tiempoExtraId;
  final DateTime fecha;
  final String motivoAusencia;
  final String servicioId;
  final String servicioNombre;
  final String nombreCubre;
}

/// Cobertura operativa por ausencia (pedido explícito de Marlon) —
/// ninguna validación de negocio vive aquí (cobertura empleado/externo,
/// existencia de Servicio/Empleado, etc.), vive en los casos de uso,
/// como en todo el proyecto.
abstract interface class TiempoExtraRepository {
  Future<TiempoExtraData?> obtenerPorId(String id);

  /// Resuelve el TiempoExtra dueño de un `Egreso` puntual — busca
  /// primero como pago base (`TiempoExtra.egresoId`) y, si no, como
  /// costo adicional (`TiempoExtraCostoAdicional.egresoId`, resolviendo
  /// su `tiempoExtraId` padre) — `null` si ese Egreso no vino de ningún
  /// TiempoExtra. Usado por el bloqueo de corrección/cancelación
  /// directa de Egreso (Etapa "Ingresos y Egresos") y por la
  /// navegación "Ver origen" desde su expediente — en ambos casos basta
  /// con el TiempoExtra dueño, sin distinguir cuál costo específico.
  Future<String?> obtenerTiempoExtraIdPorEgresoId(String egresoId);

  /// Todos los `egresoId` reales generados por TiempoExtra (pago base o
  /// costo adicional) cuya `TiempoExtra.fecha` cae en el rango — mismo
  /// patrón que `DeudaRepository.listarEgresoIdsDePagosEnRango`, usado
  /// por `ClasificarEgresosPorOrigenUseCase` para clasificar en lote sin
  /// N+1 (antes de esta etapa, un Egreso de TiempoExtra se clasificaba
  /// erróneamente como manual — hueco real de auditoría).
  Future<List<String>> listarEgresoIdsEnRango({DateTime? rangoInicio, DateTime? rangoFin});

  Future<List<TiempoExtraData>> listar({
    DateTime? rangoInicio,
    DateTime? rangoFin,
    String? servicioId,
    String? estatus,
  });

  Future<List<TiempoExtraCostoAdicionalData>> listarCostosAdicionales(String tiempoExtraId);

  /// Suma de costos adicionales por `tiempoExtraId` — una sola consulta
  /// en lote sobre TODOS los [tiempoExtraIds] pedidos, nunca una
  /// consulta por fila (mismo criterio que `PagoNominaRepository.
  /// totalAplicadoPorRenglon`).
  Future<Map<String, int>> totalCostosAdicionalesPorTiempoExtra(List<String> tiempoExtraIds);

  Future<List<TiempoExtraEventoData>> listarEventos(String tiempoExtraId);

  /// `TiempoExtra` `registrado` de [empleadoId] (como ausente) cuya
  /// `fecha` cae dentro de `[desde, hasta]` — usado exclusivamente por
  /// `NominaRepositoryImpl.guardarRenglon` para derivar
  /// `NominaEmpleadoAusencia`, nunca por la UI directamente.
  Future<List<TiempoExtraData>> listarPorEmpleadoAusenteYRango({
    required String empleadoId,
    required DateTime desde,
    required DateTime hasta,
  });

  /// Igual que [listarPorEmpleadoAusenteYRango], pero ya con
  /// Servicio/cobertura resueltos — usado exclusivamente por
  /// `NominaRepositoryImpl.guardarRenglon` para insertar
  /// `NominaEmpleadoAusencia` sin que Nómina necesite conocer
  /// `EmpleadoRepository`/`ServicioRepository`.
  Future<List<AusenciaParaNomina>> listarAusenciasParaNomina({
    required String empleadoId,
    required DateTime desde,
    required DateTime hasta,
  });

  /// Crea la cobertura completa. Etapa "origen financiero unificado":
  /// el pago base y cada costo adicional aplican su PROPIO origen
  /// financiero de forma independiente dentro de la misma transacción
  /// — cuenta financiera → su propio `Egreso`; tarjeta → un cargo vía
  /// `DeudaRepository.registrarCargoTiempoExtra`/
  /// `registrarCargoCostoAdicional` (nunca un Egreso combinado). Mismo
  /// patrón de atomicidad que `CompraRepositoryImpl.crear`: si
  /// cualquier efecto financiero falla, toda la transacción se revierte
  /// — nunca queda un TiempoExtra parcialmente registrado.
  Future<TiempoExtraData> crear({
    required DateTime fecha,
    required String servicioId,
    required String origenCobertura,
    String? empleadoAusenteId,
    String? motivoAusencia,
    String? vacanteOperativaId,
    String? descripcionOrigen,
    String? empleadoCubreId,
    String? nombreExternoCubre,
    required String turnoId,
    required int montoTiempoExtra,
    required String formaPago,
    /// Origen del PAGO BASE cuando `formaPago != tarjeta` — exactamente
    /// uno de este o [deudaIdTarjeta] se puebla.
    String? cuentaFinancieraId,
    /// Origen del PAGO BASE cuando `formaPago == tarjeta`.
    String? deudaIdTarjeta,
    String? observaciones,
    List<CostoAdicionalInput> costosAdicionales = const [],
    /// Nombre a mostrar como `Egreso.beneficiario` — resuelto en el caso
    /// de uso (que ya conoce el nombre completo del Empleado que cubre,
    /// o usa directamente `nombreExternoCubre`), nunca adivinado aquí.
    required String beneficiarioEgreso,
    String? actorUsuarioId,
  });

  /// Cancela la cobertura y, si tiene Egreso vinculado, lo cancela
  /// también (mismo patrón que `CompraRepositoryImpl.cancelar`).
  Future<TiempoExtraData> cancelar({
    required String tiempoExtraId,
    required String motivo,
    String? actorUsuarioId,
  });

  /// Corrige una cobertura ya registrada — el pago base se resupone
  /// completo (mismo criterio que el diálogo de alta, precargado); los
  /// costos adicionales son sparse (`cambiosCostos`, mismo patrón que
  /// `cambiosPartidas` de Compra: un costo no mencionado no se toca).
  /// A diferencia de Compra, el origen financiero SÍ puede cambiar de
  /// tipo (Cuenta↔TDC) o de contenedor (Cuenta A→B, TDC X→Y) — pedido
  /// explícito de esta etapa. Por cada ítem (pago base o un costo), la
  /// transición `(origenAnterior, montoAnterior) → (origenNuevo,
  /// montoNuevo)` se resuelve así:
  /// - Cuenta→misma/otra Cuenta: `EgresoRepository.corregir`
  ///   (metadatos/cuenta) + `corregirMonto` si el monto cambió —
  ///   sobreescribe el Egreso existente, nunca duplica.
  /// - TDC X→misma TDC X: `DeudaRepository.registrarAjusteCargo...`
  ///   por la DIFERENCIA — nunca reescribe el cargo original.
  /// - TDC X→TDC Y: revierte el cargo completo de X + aplica un cargo
  ///   completo nuevo en Y.
  /// - Cuenta→TDC / TDC→Cuenta: cancela/revierte el origen viejo por
  ///   completo + aplica el origen nuevo como si fuera un alta.
  /// Todo en una sola transacción — mismo patrón de atomicidad que
  /// [crear]. Registra un `TiempoExtraEvento` tipo `corregido` con
  /// `estadoAnterior`/`estadoNuevo` (JSON, solo los campos que
  /// cambiaron). Rechazar la llamada si `estatus == cancelado` es
  /// responsabilidad del caso de uso, nunca de este método.
  Future<TiempoExtraData> corregir({
    required String tiempoExtraId,
    required DateTime fecha,
    required String servicioId,
    required String origenCobertura,
    String? empleadoAusenteId,
    String? motivoAusencia,
    String? vacanteOperativaId,
    String? descripcionOrigen,
    String? empleadoCubreId,
    String? nombreExternoCubre,
    required String turnoId,
    required int montoTiempoExtra,
    required String formaPago,
    String? cuentaFinancieraId,
    String? deudaIdTarjeta,
    String? observaciones,
    List<CorreccionCostoAdicional> cambiosCostos = const [],
    required String beneficiarioEgreso,
    required String motivo,
    String? actorUsuarioId,
  });

  Future<ResumenEliminacionTiempoExtra> obtenerResumenEliminacionFisica(String tiempoExtraId);

  /// Eliminación física extraordinaria (Maestro-only, vía
  /// `exigirMaestro` en el provider — nunca aquí). Solo elegible cuando
  /// `estatus == cancelado` (validado en el caso de uso): su efecto
  /// financiero neto ya es cero, lo que hace seguro borrar también sus
  /// `MovimientoDeuda` sin corromper ningún saldo vivo. Snapshotea todo
  /// (TiempoExtra + costos + eventos + Egresos + movimientos de deuda)
  /// en `EliminacionFisicaEvento` antes de borrar.
  Future<EliminarTiempoExtraFisicamenteResultado> eliminarFisicamente({
    required String tiempoExtraId,
    required String motivo,
    String? detalle,
    String? actorUsuarioId,
  });
}
