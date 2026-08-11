import 'package:riseg_one/features/compras/domain/repositories/compra_repository.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/obtener_resumen_financiero_usecase.dart';
import 'package:riseg_one/features/nomina/domain/repositories/pago_nomina_repository.dart';
import 'package:riseg_one/features/organizacion/data/tables/servicio_table.dart';
import 'package:riseg_one/features/organizacion/domain/repositories/servicio_repository.dart';
import 'package:riseg_one/features/personal/domain/repositories/empleado_repository.dart';

/// Resumen consolidado del Reporte General (Etapa 12A).
///
/// Cada campo es `null` cuando el llamador no incluyó esa sección
/// (`incluirXxx == false` en [ObtenerResumenGeneralUseCase.ejecutar]) —
/// nunca `0`: la diferencia importa, `null` significa "sin autorización
/// para esta cifra", `0` significa "autorizado, y el valor real es
/// cero". La UI nunca debe renderizar una tarjeta cuyo campo es `null`.
///
/// [totalComprasPeriodo] y [totalNominaPagadaPeriodo] son **indicadores
/// informativos**, no sumandos del resultado: ambos ya están contenidos
/// dentro de `totalEgresos` (vía `Compra.egresoId`/`PagoNomina.egresoId`
/// — todo Compra y todo pago de Nómina genera exactamente un `Egreso`).
/// [personalActivoActual]/[serviciosActivosActual] son snapshots a la
/// fecha de ejecución, no cifras del periodo — nunca se combinan
/// aritméticamente con las demás.
class ResumenGeneralReportes {
  const ResumenGeneralReportes({
    this.totalIngresos,
    this.totalEgresos,
    this.resultadoOperativo,
    this.totalComprasPeriodo,
    this.totalNominaPagadaPeriodo,
    this.personalActivoActual,
    this.serviciosActivosActual,
  });

  final int? totalIngresos;
  final int? totalEgresos;
  final int? resultadoOperativo;
  final int? totalComprasPeriodo;
  final int? totalNominaPagadaPeriodo;
  final int? personalActivoActual;
  final int? serviciosActivosActual;
}

/// Compone [ObtenerResumenFinancieroUseCase] (ya existente, sin uso
/// hasta esta etapa) con Compras/Nómina/Personal/Servicios — nunca
/// recalcula Ingresos/Egresos por su cuenta, siempre delega en la
/// fuente única de Finanzas.
///
/// Deliberadamente **ajeno a permisos**: quién puede ver cada sección
/// se decide en la capa de presentación (mismo criterio que el resto
/// del proyecto — `autorizarUseCase` nunca vive dentro de un caso de
/// uso). Los `incluirXxx` los resuelve el llamador consultando
/// `PermissionService` antes de invocar `ejecutar` — este caso de uso
/// solo confía en lo que se le pide y omite (`null`) lo que no.
class ObtenerResumenGeneralUseCase {
  ObtenerResumenGeneralUseCase(
    this._resumenFinanciero,
    this._compraRepository,
    this._pagoNominaRepository,
    this._empleadoRepository,
    this._servicioRepository,
  );

  final ObtenerResumenFinancieroUseCase _resumenFinanciero;
  final CompraRepository _compraRepository;
  final PagoNominaRepository _pagoNominaRepository;
  final EmpleadoRepository _empleadoRepository;
  final ServicioRepository _servicioRepository;

  Future<ResumenGeneralReportes> ejecutar({
    DateTime? rangoInicio,
    DateTime? rangoFin,
    required bool incluirFinanzas,
    required bool incluirCompras,
    required bool incluirNomina,
    required bool incluirPersonal,
    required bool incluirComercial,
  }) async {
    int? totalIngresos;
    int? totalEgresos;
    int? resultadoOperativo;
    if (incluirFinanzas) {
      final resumenFinanciero = await _resumenFinanciero.ejecutar(rangoInicio: rangoInicio, rangoFin: rangoFin);
      totalIngresos = resumenFinanciero.totalIngresos;
      totalEgresos = resumenFinanciero.totalEgresos;
      resultadoOperativo = resumenFinanciero.resultadoOperativo;
    }

    final totalCompras = incluirCompras
        ? await _compraRepository.totalCompradoEnRango(desde: rangoInicio, hasta: rangoFin)
        : null;

    final totalNomina = incluirNomina
        ? await _pagoNominaRepository.totalPagadoEnRango(rangoInicio: rangoInicio, rangoFin: rangoFin)
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
      totalIngresos: totalIngresos,
      totalEgresos: totalEgresos,
      resultadoOperativo: resultadoOperativo,
      totalComprasPeriodo: totalCompras,
      totalNominaPagadaPeriodo: totalNomina,
      personalActivoActual: personalActivo,
      serviciosActivosActual: serviciosActivos,
    );
  }
}
