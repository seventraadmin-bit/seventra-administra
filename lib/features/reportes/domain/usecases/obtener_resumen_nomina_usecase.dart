import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/nomina/domain/repositories/nomina_repository.dart';
import 'package:riseg_one/features/nomina/domain/repositories/pago_nomina_repository.dart';

/// Una Nómina ya con sus totales resueltos — Etapa 12B (Reportes).
///
/// [totalGenerado] (Σ `totalAPagar` de sus renglones) y [totalPagado]
/// (Σ aplicaciones activas de esos mismos renglones, sin importar
/// cuándo se aplicó el pago) son ejes distintos por diseño — nunca se
/// deriva [saldoPendiente] restando "pagos del mismo rango de fechas"
/// (`PagoNomina.fechaPago` puede caer en un periodo de calendario
/// distinto al de esta Nómina). [totalPagado] nunca se confunde con
/// `Egreso` — ver `ClasificarEgresosPorOrigenUseCase` (Etapa 12A) si se
/// necesita ese desglose.
class NominaConTotales {
  const NominaConTotales({
    required this.nomina,
    required this.totalGenerado,
    required this.totalPagado,
    required this.saldoPendiente,
    required this.empleadosIncluidos,
    required this.totalFiscal,
    required this.totalNoFiscal,
    required this.totalBono,
    required this.totalFaltas,
    required this.totalPrestamo,
    required this.totalTiempoExtra,
    required this.totalOtrosDescuentos,
    required this.esPagoParcial,
  });

  final NominaData nomina;
  final int totalGenerado;
  final int totalPagado;
  final int saldoPendiente;
  final int empleadosIncluidos;
  final int totalFiscal;
  final int totalNoFiscal;
  final int totalBono;
  final int totalFaltas;
  final int totalPrestamo;
  final int totalTiempoExtra;
  final int totalOtrosDescuentos;

  /// Al menos un renglón tiene algún pago aplicado, pero la Nómina
  /// completa todavía no llega a `pagada`.
  final bool esPagoParcial;
}

class ResumenNominaReportes {
  const ResumenNominaReportes({
    required this.nominas,
    required this.totalGeneradoGlobal,
    required this.totalPagadoGlobal,
    required this.totalPendienteGlobal,
  });

  final List<NominaConTotales> nominas;
  final int totalGeneradoGlobal;
  final int totalPagadoGlobal;
  final int totalPendienteGlobal;
}

/// Compone `NominaRepository.listarEnRango`/`listarRenglonesEnRango`
/// (proyección segura, sin datos bancarios) con
/// `PagoNominaRepository.totalAplicadoPorRenglon` (en lote, sin N+1) —
/// toda cifra histórica sale de estas dos fuentes, nunca se recalcula
/// desde Personal/AsignacionServicio actuales. Una Nómina en
/// `borrador` se incluye en la lista pero **nunca** se mezcla en los
/// totales globales sin que el llamador la distinga (`nomina.estatus`
/// va en cada [NominaConTotales], la UI decide cómo marcarla).
class ObtenerResumenNominaUseCase {
  ObtenerResumenNominaUseCase(this._nominaRepository, this._pagoNominaRepository);

  final NominaRepository _nominaRepository;
  final PagoNominaRepository _pagoNominaRepository;

  Future<ResumenNominaReportes> ejecutar({DateTime? rangoInicio, DateTime? rangoFin, String? estatus}) async {
    final nominas = await _nominaRepository.listarEnRango(rangoInicio: rangoInicio, rangoFin: rangoFin, estatus: estatus);
    final renglones = await _nominaRepository.listarRenglonesEnRango(
      rangoInicio: rangoInicio,
      rangoFin: rangoFin,
      estatus: estatus,
    );

    final renglonesPorNomina = <String, List<NominaEmpleadoReporteRow>>{};
    for (final renglon in renglones) {
      (renglonesPorNomina[renglon.nominaId] ??= []).add(renglon);
    }

    final aplicadoPorRenglon = await _pagoNominaRepository.totalAplicadoPorRenglon(
      renglones.map((r) => r.id).toList(),
    );

    final nominasConTotales = <NominaConTotales>[];
    var totalGeneradoGlobal = 0;
    var totalPagadoGlobal = 0;
    var totalPendienteGlobal = 0;

    for (final nomina in nominas) {
      final suyos = renglonesPorNomina[nomina.id] ?? const <NominaEmpleadoReporteRow>[];

      final generado = suyos.fold<int>(0, (s, r) => s + r.totalAPagar);
      final pagado = suyos.fold<int>(0, (s, r) => s + (aplicadoPorRenglon[r.id] ?? 0));
      final pendiente = generado - pagado;

      final esPagoParcial = nomina.estatus != 'pagada' && suyos.any((r) => r.estatusPago != 'pendiente');

      nominasConTotales.add(NominaConTotales(
        nomina: nomina,
        totalGenerado: generado,
        totalPagado: pagado,
        saldoPendiente: pendiente,
        empleadosIncluidos: suyos.length,
        totalFiscal: suyos.fold<int>(0, (s, r) => s + r.montoFiscal),
        totalNoFiscal: suyos.fold<int>(0, (s, r) => s + r.montoNoFiscal),
        totalBono: suyos.fold<int>(0, (s, r) => s + r.bono),
        totalFaltas: suyos.fold<int>(0, (s, r) => s + r.faltas),
        totalPrestamo: suyos.fold<int>(0, (s, r) => s + r.prestamo),
        totalTiempoExtra: suyos.fold<int>(0, (s, r) => s + r.tiempoExtra),
        totalOtrosDescuentos: suyos.fold<int>(0, (s, r) => s + r.otrosDescuentos),
        esPagoParcial: esPagoParcial,
      ));

      totalGeneradoGlobal += generado;
      totalPagadoGlobal += pagado;
      totalPendienteGlobal += pendiente;
    }

    return ResumenNominaReportes(
      nominas: nominasConTotales,
      totalGeneradoGlobal: totalGeneradoGlobal,
      totalPagadoGlobal: totalPagadoGlobal,
      totalPendienteGlobal: totalPendienteGlobal,
    );
  }
}
