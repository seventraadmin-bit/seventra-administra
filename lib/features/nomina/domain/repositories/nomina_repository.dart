import 'package:riseg_one/core/database/app_database.dart';

import '../../data/tables/nomina_table.dart';
import '../usecases/calcular_periodo_nomina.dart';
import '../usecases/eliminar_cadena_prueba_nomina_usecase.dart';
import '../usecases/eliminar_nomina_fisicamente_usecase.dart';
import '../usecases/fila_nomina_generada.dart';

/// Proyección segura de `NominaEmpleado` para Reportes (Etapa 12B) —
/// allow-list explícito, poblado siempre vía `selectOnly`.
/// Deliberadamente **sin** `bancoNombre`/`numeroCuentaTarjeta`/`clabe`
/// (columnas reales de `NominaEmpleado`, snapshot bancario de la
/// Nómina) — un caso de uso operativo (pagar Nómina) sí las necesita
/// vía `NominaRepository.listarEmpleados`; un reporte administrativo
/// nunca.
class NominaEmpleadoReporteRow {
  const NominaEmpleadoReporteRow({
    required this.id,
    required this.nominaId,
    required this.numeroEmpleado,
    required this.nombreCompleto,
    this.puestoNombre,
    this.servicioId,
    this.servicioNombre,
    this.turnoNombre,
    required this.importeBase,
    required this.bono,
    required this.faltas,
    required this.descuentoPorFaltas,
    required this.prestamo,
    required this.tiempoExtra,
    required this.otrosDescuentos,
    required this.montoFiscal,
    required this.montoNoFiscal,
    required this.totalAPagar,
    required this.estatusPago,
  });

  final String id;
  final String nominaId;
  final int numeroEmpleado;
  final String nombreCompleto;
  final String? puestoNombre;
  final String? servicioId;
  final String? servicioNombre;
  final String? turnoNombre;
  final int importeBase;
  final int bono;
  final int faltas;
  final int descuentoPorFaltas;
  final int prestamo;
  final int tiempoExtra;
  final int otrosDescuentos;
  final int montoFiscal;
  final int montoNoFiscal;
  final int totalAPagar;
  final String estatusPago;
}

/// Repositorio del motor de Nómina (Etapa 6C). Los métodos de escritura
/// compuesta (`generar`/`guardarRenglon`/`cerrar`) son transaccionales y
/// registran su propio `NominaEvento` — ninguna validación de negocio
/// vive aquí (existencia, unicidad de periodo, bloqueo de cierre por
/// distribución pendiente, etc. viven en los casos de uso), mismo
/// criterio que el resto del proyecto.
abstract interface class NominaRepository {
  Future<NominaData?> obtenerPorId(String id);

  Future<NominaData?> obtenerPorPeriodo({required int anio, required int mes, required TipoPeriodoNomina tipo});

  Future<List<NominaData>> listar();

  /// Nóminas cuyo periodo (`fechaInicioPeriodo`/`fechaFinPeriodo`) se
  /// traslapa con el rango dado — Etapa 12B (Reportes). Eje de fecha
  /// deliberadamente distinto de `PagoNomina.fechaPago`
  /// (`PagoNominaRepository.listarEnRango`/`totalPagadoEnRango`, Etapa
  /// 12A): un pago puede caer en un periodo de calendario distinto al
  /// de la Nómina que liquida.
  Future<List<NominaData>> listarEnRango({DateTime? rangoInicio, DateTime? rangoFin, String? estatus});

  /// Renglones de las Nóminas en rango, ya proyectados a
  /// [NominaEmpleadoReporteRow] (sin datos bancarios) — el único punto
  /// de lectura de Nómina que Reportes debe usar; nunca
  /// `listarEmpleados` directo dentro de código de Reportes.
  Future<List<NominaEmpleadoReporteRow>> listarRenglonesEnRango({
    DateTime? rangoInicio,
    DateTime? rangoFin,
    String? estatus,
  });

  Future<List<NominaEmpleadoData>> listarEmpleados(String nominaId);

  Future<NominaEmpleadoData?> obtenerEmpleado(String nominaEmpleadoId);

  Future<NominaEmpleadoData?> obtenerEmpleadoPorNominaYEmpleado({required String nominaId, required String empleadoId});

  Future<List<NominaEmpleadoTramoData>> listarTramos(String nominaEmpleadoId);

  /// Ausencias del periodo (Etapa Tiempos Extra) — puramente
  /// informativas, ver el doc comment de `NominaEmpleadoAusencia`.
  Future<List<NominaEmpleadoAusenciaData>> listarAusencias(String nominaEmpleadoId);

  Future<List<NominaEventoData>> listarEventos(String nominaId);

  /// Crea el encabezado de la Nómina y todos sus renglones/tramos
  /// iniciales en una sola transacción — registra el evento `generada`.
  Future<NominaData> generar({
    required String folio,
    required PeriodoNomina periodo,
    required List<FilaNominaGenerada> filas,
    String? actorUsuarioId,
  });

  /// Reemplaza el renglón (y sus tramos) de un Empleado dentro de una
  /// Nómina ya existente — usado por "Actualizar desde Personal" para
  /// los renglones que sí siguen teniendo días pagables. Los campos de
  /// movimientos manuales los decide el llamador (ya resueltos contra
  /// la fila anterior) y se pasan explícitos. Fiscal/No fiscal NO se
  /// reciben aquí — el repositorio los resuelve internamente contra el
  /// `totalAPagar` final (después de TODAS las deducciones, incluidos
  /// los descuentos de Inventario recién resueltos en esta misma
  /// llamada), preservando la distribución manual previa o
  /// reiniciándola al default — ver el doc comment de
  /// `NominaRepositoryImpl._resolverDistribucionFiscal` (Etapa 15, bug
  /// real: antes se recibía como parámetro ya calculado por el
  /// llamador contra un total que todavía no incluía el descuento de
  /// Inventario, dejando la distribución desincronizada).
  Future<NominaEmpleadoData> guardarRenglon({
    required String nominaId,
    required FilaNominaGenerada datos,
    required int prestamo,
    required int tiempoExtra,
    required int bono,
    required bool bonoModificadoManualmente,
    required int faltas,
    required int otrosDescuentos,
    required String? observaciones,
  });

  /// Elimina por completo un renglón (y sus tramos) — solo válido para
  /// un renglón que perdió todos sus días pagables **y** nunca tuvo
  /// movimientos manuales capturados (ver
  /// `ActualizarNominaDesdePersonalUseCase`). Etapa 4: antes de borrar,
  /// desvincula (`nominaEmpleadoId = null`) cualquier `NominaEvento`
  /// previo de este renglón — sin esto, el `cascade` de
  /// `NominaEvento.nominaEmpleadoId` los destruiría junto con la fila
  /// — y escribe un evento `renglonEliminado` con los valores clave
  /// del renglón (única excepción a "nunca snapshots completos": la
  /// fila en sí desaparece, así que es la única evidencia que quedará).
  Future<void> eliminarRenglon(String nominaEmpleadoId, {String? motivo, String? actorUsuarioId});

  /// Movimientos manuales y distribución Fiscal/No fiscal de un renglón
  /// en UNA sola escritura transaccional (Etapa 15, calculadora
  /// auditable — reemplaza los antiguos `actualizarMovimientos`/
  /// `actualizarDistribucion` separados). [distribucionManual] es
  /// `null` para el comportamiento automático de siempre
  /// (`_resolverDistribucionFiscal`); si se provee, se persiste tal
  /// cual contra el `totalAPagar` recién calculado en esta misma
  /// llamada — ninguna validación de negocio vive aquí (si no
  /// balancea, igual se escribe; esa validación vive en
  /// `ActualizarRenglonNominaUseCase`, mismo criterio que el resto del
  /// proyecto).
  /// Etapa 4: [tipoEvento] lo decide el llamador — `'movimientoModificado'`
  /// para la edición operativa normal de Borrador
  /// (`ActualizarRenglonNominaUseCase`), `'corregida'` para una
  /// corrección de una Nómina ya `cerrada`/`pagada`
  /// (`CorregirRenglonNominaUseCase`). El evento se escribe DENTRO de
  /// esta misma transacción (nunca como una llamada separada después:
  /// antes de esta etapa, la auditoría corría en una segunda
  /// transacción no atómica y `actorUsuarioId` nunca se pasaba) — solo
  /// si `DiffEvento` detecta al menos un campo realmente distinto.
  Future<NominaEmpleadoData> actualizarRenglon({
    required String nominaEmpleadoId,
    required int prestamo,
    required int tiempoExtra,
    required int bono,
    required bool bonoModificadoManualmente,
    required int faltas,
    required int otrosDescuentos,
    required String? observaciones,
    ({int montoFiscal, int montoNoFiscal})? distribucionManual,
    required String tipoEvento,
    String? motivo,
    String? actorUsuarioId,
  });

  Future<NominaData> cerrar({required String nominaId, String? actorUsuarioId});

  /// Cancelación de la Nómina completa (Etapa 4) — solo Borrador o
  /// Cerrada-sin-`PagoNomina` (validado por
  /// `CancelarNominaUseCase`, nunca aquí). Revierte a `pendiente`
  /// cualquier `DescuentoInventario` aplicado y libera TODAS las
  /// cuotas reservadas de cada renglón (mismo mecanismo exacto que
  /// [eliminarFisicamente] — nunca `aplicada`, estructuralmente
  /// imposible sin un `PagoNomina` real), antes de marcar
  /// `estatus = cancelada`.
  Future<NominaData> cancelar({
    required String nominaId,
    required String motivo,
    String? detalle,
    String? observaciones,
    String? actorUsuarioId,
  });

  Future<void> registrarEvento({
    required String nominaId,
    String? nominaEmpleadoId,
    required String tipoEvento,
    String? observacion,
    String? estadoAnterior,
    String? estadoNuevo,
    String? actorUsuarioId,
  });

  /// Elegibilidad de solo lectura para [eliminarFisicamente] — ver el
  /// doc comment de `ResumenEliminacionNomina`.
  Future<ResumenEliminacionNomina> obtenerResumenEliminacionFisica(String nominaId);

  /// Eliminación física extraordinaria (Etapa 15) — ver el doc comment
  /// completo en `NominaRepositoryImpl.eliminarFisicamente`. [motivo]
  /// es el nombre estable del enum `MotivoEliminacionFisicaNomina`,
  /// nunca la etiqueta traducida.
  Future<EliminarNominaFisicamenteResultado> eliminarFisicamente({
    required String nominaId,
    required String motivo,
    String? detalle,
    String? actorUsuarioId,
  });

  /// Vista previa de solo lectura para [eliminarCadenaPrueba] — ver el
  /// doc comment de `ResumenCadenaPruebaNomina`.
  Future<ResumenCadenaPruebaNomina> obtenerResumenCadenaPrueba(String nominaId);

  /// "Eliminar cadena de prueba" (Etapa 15, limpieza segura de datos de
  /// prueba) — ver el doc comment completo en
  /// `NominaRepositoryImpl.eliminarCadenaPrueba`. [motivo] es el
  /// nombre estable del enum `MotivoCadenaPruebaNomina`, nunca la
  /// etiqueta traducida.
  Future<EliminarCadenaPruebaNominaResultado> eliminarCadenaPrueba({
    required String nominaId,
    required String motivo,
    String? detalle,
    String? actorUsuarioId,
  });
}
