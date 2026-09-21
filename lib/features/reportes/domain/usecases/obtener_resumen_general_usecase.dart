import 'package:riseg_one/features/compras/domain/repositories/compra_repository.dart';
import 'package:riseg_one/features/finanzas/domain/repositories/cuenta_por_cobrar_repository.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/cuenta_por_cobrar_antiguedad.dart';
import 'package:riseg_one/features/nomina/domain/repositories/pago_nomina_repository.dart';
import 'package:riseg_one/features/organizacion/data/tables/servicio_table.dart';
import 'package:riseg_one/features/organizacion/domain/repositories/servicio_repository.dart';
import 'package:riseg_one/features/personal/domain/repositories/empleado_repository.dart';

import '../analitica/comparacion_periodo.dart';
import '../analitica/obtener_analisis_operativo_usecase.dart';

/// Antigüedad de la cobranza pendiente, por cubeta.
///
/// Es una foto de HOY, nunca del periodo seleccionado: una cuenta que
/// lleva 70 días vencida los lleva hoy, independientemente del rango que
/// el usuario tenga puesto arriba. Mezclarla con las cifras del periodo
/// sería sumar un saldo devengado con un flujo.
class AntiguedadCartera {
  const AntiguedadCartera({required this.montoPorCubeta, required this.cuentasPorCubeta});

  final Map<RangoAntiguedadCuentaPorCobrar, int> montoPorCubeta;
  final Map<RangoAntiguedadCuentaPorCobrar, int> cuentasPorCubeta;

  int get total => montoPorCubeta.values.fold(0, (a, b) => a + b);

  /// Todo lo que ya pasó su fecha de vencimiento — la cubeta "al
  /// corriente" no cuenta.
  int get vencido => montoPorCubeta.entries
      .where((e) => e.key != RangoAntiguedadCuentaPorCobrar.alCorriente)
      .fold(0, (a, e) => a + e.value);
}

/// Resumen consolidado del Reporte General.
///
/// Cada campo es `null` cuando el llamador no incluyó esa sección
/// (`incluirXxx == false` en [ObtenerResumenGeneralUseCase.ejecutar]) —
/// nunca `0`: la diferencia importa, `null` significa "sin autorización
/// para esta cifra", `0` significa "autorizado, y el valor real es
/// cero". La UI nunca debe renderizar una tarjeta cuyo campo es `null`.
///
/// [analisis] trae de una sola vez el KPI, la serie temporal y la
/// composición del gasto — no son tres consultas: la pantalla, la
/// gráfica y la exportación leen el mismo objeto, así que no pueden
/// mostrar cifras distintas.
///
/// [totalComprasPeriodo] y [totalNominaPagadaPeriodo] son **indicadores
/// informativos**, no sumandos del resultado: ambos ya están contenidos
/// dentro del gasto operativo (vía `Compra.egresoId`/`PagoNomina.
/// egresoId` o, con tarjeta, vía el cargo correspondiente).
/// [personalActivoActual]/[serviciosActivosActual] son snapshots a la
/// fecha de ejecución, no cifras del periodo — nunca se combinan
/// aritméticamente con las demás.
class ResumenGeneralReportes {
  const ResumenGeneralReportes({
    this.analisis,
    this.analisisAnterior,
    this.antiguedadCartera,
    this.totalComprasPeriodo,
    this.totalNominaPagadaPeriodo,
    this.personalActivoActual,
    this.serviciosActivosActual,
  });

  final AnalisisOperativoPeriodo? analisis;

  /// El mismo análisis sobre el periodo inmediatamente anterior de la
  /// misma longitud — la base de toda comparación mostrada en pantalla.
  final AnalisisOperativoPeriodo? analisisAnterior;

  final AntiguedadCartera? antiguedadCartera;

  final int? totalComprasPeriodo;
  final int? totalNominaPagadaPeriodo;
  final int? personalActivoActual;
  final int? serviciosActivosActual;

  int? get totalIngresos => analisis?.ingresos;

  /// Gasto operativo del periodo — la única definición del sistema (ver
  /// [AnalisisOperativoPeriodo.gastoOperativo]). Sustituyó al "total de
  /// Egresos" crudo que se mostraba antes, que contaba los pagos de
  /// tarjeta como gasto y omitía el gasto financiado con TDC que aún no
  /// se había pagado.
  int? get gastoOperativo => analisis?.gastoOperativo;

  int? get resultadoOperativo => analisis?.resultadoOperativo;

  /// Salidas de caja reales del periodo — informativo, deliberadamente
  /// distinto del gasto operativo.
  int? get salidasDeEfectivo => analisis?.salidasDeEfectivo;

  bool get sinNingunaSeccionAutorizada =>
      analisis == null &&
      antiguedadCartera == null &&
      totalComprasPeriodo == null &&
      totalNominaPagadaPeriodo == null &&
      personalActivoActual == null &&
      serviciosActivosActual == null;
}

/// Compone [ObtenerAnalisisOperativoUseCase] (la fuente única del
/// resultado operativo) con Compras/Nómina/Personal/Servicios/Cartera —
/// nunca recalcula Ingresos ni gasto por su cuenta.
///
/// Deliberadamente **ajeno a permisos**: quién puede ver cada sección
/// se decide en la capa de presentación (mismo criterio que el resto
/// del proyecto — `autorizarUseCase` nunca vive dentro de un caso de
/// uso). Los `incluirXxx` los resuelve el llamador consultando
/// `PermissionService` antes de invocar `ejecutar` — este caso de uso
/// solo confía en lo que se le pide y omite (`null`) lo que no.
class ObtenerResumenGeneralUseCase {
  ObtenerResumenGeneralUseCase(
    this._analisisOperativo,
    this._compraRepository,
    this._pagoNominaRepository,
    this._empleadoRepository,
    this._servicioRepository,
    this._cuentaPorCobrarRepository,
  );

  final ObtenerAnalisisOperativoUseCase _analisisOperativo;
  final CompraRepository _compraRepository;
  final PagoNominaRepository _pagoNominaRepository;
  final EmpleadoRepository _empleadoRepository;
  final ServicioRepository _servicioRepository;
  final CuentaPorCobrarRepository _cuentaPorCobrarRepository;

  Future<ResumenGeneralReportes> ejecutar({
    required RangoPeriodo rango,
    required bool incluirFinanzas,
    required bool incluirCompras,
    required bool incluirNomina,
    required bool incluirPersonal,
    required bool incluirComercial,
    // El periodo anterior y la antigüedad de cartera solo los consume la
    // pantalla de Reportes. El Dashboard, que comparte este caso de uso,
    // los apaga: son dos barridos completos que no mostraría, y pagar
    // consultas por datos que nadie va a ver es exactamente el tipo de
    // costo que se acumula sin que nadie lo note.
    bool incluirComparacion = true,
    bool incluirCartera = true,
    DateTime? hoy,
  }) async {
    AnalisisOperativoPeriodo? analisis;
    AnalisisOperativoPeriodo? analisisAnterior;
    AntiguedadCartera? antiguedad;
    if (incluirFinanzas) {
      analisis = await _analisisOperativo.ejecutar(rango: rango);
      // La comparación usa la MISMA granularidad que el periodo actual:
      // si el anterior eligiera otra por su cuenta, dos periodos de
      // igual longitud podrían quedar con series incomparables.
      if (incluirComparacion) {
        analisisAnterior = await _analisisOperativo.ejecutar(
          rango: rango.anterior,
          granularidad: analisis.granularidad,
        );
      }
      if (incluirCartera) antiguedad = await _antiguedad(hoy ?? DateTime.now());
    }

    final totalCompras = incluirCompras
        ? await _compraRepository.totalCompradoEnRango(desde: rango.inicio, hasta: rango.fin)
        : null;

    final totalNomina = incluirNomina
        ? await _pagoNominaRepository.totalPagadoEnRango(rangoInicio: rango.inicio, rangoFin: rango.fin)
        : null;

    int? personalActivo;
    if (incluirPersonal) {
      final empleadosActivos = await _empleadoRepository.listar(estatus: 'activo');
      personalActivo = empleadosActivos.length;
    }

    int? serviciosActivos;
    if (incluirComercial) {
      final servicios = await _servicioRepository.listar();
      serviciosActivos = servicios.where((s) => s.servicio.estatus == EstatusServicio.activo.name).length;
    }

    return ResumenGeneralReportes(
      analisis: analisis,
      analisisAnterior: analisisAnterior,
      antiguedadCartera: antiguedad,
      totalComprasPeriodo: totalCompras,
      totalNominaPagadaPeriodo: totalNomina,
      personalActivoActual: personalActivo,
      serviciosActivosActual: serviciosActivos,
    );
  }

  /// Reutiliza `calcularRangoAntiguedad` —la misma función que ya usa
  /// la pestaña de Finanzas— en vez de una segunda definición de
  /// "vencido".
  Future<AntiguedadCartera> _antiguedad(DateTime hoy) async {
    final cuentas = await _cuentaPorCobrarRepository.listar();
    final monto = <RangoAntiguedadCuentaPorCobrar, int>{};
    final conteo = <RangoAntiguedadCuentaPorCobrar, int>{};
    for (final cuenta in cuentas.where((c) => c.estatus != 'pagada')) {
      final cubeta = calcularRangoAntiguedad(cuenta, hoy);
      monto[cubeta] = (monto[cubeta] ?? 0) + cuenta.saldoPendiente;
      conteo[cubeta] = (conteo[cubeta] ?? 0) + 1;
    }
    return AntiguedadCartera(montoPorCubeta: monto, cuentasPorCubeta: conteo);
  }
}
