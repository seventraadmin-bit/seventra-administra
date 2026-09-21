import 'package:riseg_one/features/personal/domain/usecases/obtener_plantilla_personal_usecase.dart';
import 'package:riseg_one/features/personal/data/tables/empleado_table.dart';
import 'package:riseg_one/features/personal/domain/repositories/asignacion_servicio_repository.dart';
import 'package:riseg_one/features/personal/domain/repositories/empleado_repository.dart';
import 'package:riseg_one/features/personal/domain/usecases/alerta_recontratacion_empleado.dart';
import 'package:riseg_one/features/personal/domain/usecases/calcular_ciclo_laboral_empleado.dart';

/// Una baja dentro del rango consultado — unifica la fuente vigente
/// (`Empleado.fechaBaja`, empleado actualmente de baja) y la archivada
/// (`EmpleadoPeriodoLaboral.fechaBaja`, empleado que ya reingresó desde
/// entonces) en una sola forma, ya que el reporte no distingue de dónde
/// vino para el usuario — solo que fue una baja real en el periodo.
class BajaEnPeriodo {
  const BajaEnPeriodo({
    required this.empleadoId,
    required this.nombreCompleto,
    required this.fechaBaja,
    required this.motivoBaja,
  });

  final String empleadoId;
  final String nombreCompleto;
  final DateTime fechaBaja;
  final MotivoBajaEmpleado motivoBaja;
}

class EmpleadoConCiclo {
  const EmpleadoConCiclo({required this.empleado, required this.ciclo});

  final EmpleadoReporteRow empleado;
  final CicloLaboralEmpleado ciclo;
}

class EmpleadoConAlerta {
  const EmpleadoConAlerta({required this.empleado, required this.alerta});

  final EmpleadoReporteRow empleado;
  final AlertaRecontratacionEmpleado alerta;
}

/// Resumen de la subsección Personal (Etapa 12B). `null` en cualquier
/// campo significa que la sección no se incluyó (sin autorización);
/// listas vacías (`[]`)/ceros (`0`) son resultados reales autorizados.
class ResumenPersonalReportes {
  const ResumenPersonalReportes({
    required this.totalActivos,
    required this.totalAdministrativos,
    required this.totalOperativos,
    required this.personalPorServicio,
    required this.altasEnPeriodo,
    required this.reingresosEnPeriodo,
    required this.bajasEnPeriodo,
    required this.motivosBajaConteo,
    required this.proximosAniversarios,
    required this.alertasRecontratacion,
  });

  final int totalActivos;
  final int totalAdministrativos;
  final int totalOperativos;

  /// `servicioId` → cantidad de empleados operativos activos ahí.
  final Map<String, int> personalPorServicio;

  final List<EmpleadoReporteRow> altasEnPeriodo;
  final List<EmpleadoReporteRow> reingresosEnPeriodo;
  final List<BajaEnPeriodo> bajasEnPeriodo;
  final Map<MotivoBajaEmpleado, int> motivosBajaConteo;

  /// Empleados activos con aniversario dentro de los próximos 30 días.
  final List<EmpleadoConCiclo> proximosAniversarios;

  /// Empleados actualmente de baja cuyo motivo (vigente o de algún
  /// periodo archivado) genera advertencia de recontratación.
  final List<EmpleadoConAlerta> alertasRecontratacion;
}

/// Compone `EmpleadoRepository`/`AsignacionServicioRepository` en una
/// sola pasada de lectura por dominio (sin N+1): carga los activos, TODOS
/// los empleados (para altas/reingresos/bajas del rango), todas las
/// asignaciones activas, y los periodos archivados en lote — nunca una
/// consulta por fila.
///
/// **Limitación documentada** (ver plan técnico de la Etapa 12B):
/// "¿tiene periodos archivados?" reconstruye correctamente el
/// alta/reingreso *más reciente* de cada empleado, no un historial
/// completo de múltiples reingresos dentro de una sola consulta de
/// rango — aceptado deliberadamente dado el tamaño real de RISEG.
class ObtenerResumenPersonalUseCase {
  ObtenerResumenPersonalUseCase(
    this._empleadoRepository,
    this._asignacionServicioRepository,
    this._obtenerPlantillaPersonal,
  );

  final EmpleadoRepository _empleadoRepository;
  final AsignacionServicioRepository _asignacionServicioRepository;
  final ObtenerPlantillaPersonalUseCase _obtenerPlantillaPersonal;

  static const _diasVentanaAniversario = 30;

  Future<ResumenPersonalReportes> ejecutar({DateTime? rangoInicio, DateTime? rangoFin, DateTime? hoy}) async {
    final referencia = hoy ?? DateTime.now();

    final activos = await _empleadoRepository.listarParaReporte(estatus: EstatusEmpleado.activo.name);
    final todos = await _empleadoRepository.listarParaReporte();
    final asignacionesActivas = await _asignacionServicioRepository.listarTodasActivas();
    final periodosPorEmpleado = await _empleadoRepository.listarPeriodosLaboralesArchivadosPorEmpleados(
      todos.map((e) => e.id).toList(),
    );

    final servicioIdPorEmpleado = {for (final a in asignacionesActivas) a.empleadoId: a.servicioId};

    // BUG REAL corregido (Etapa "Plantilla operativa vs.
    // administrativa"): antes se contaba como ADMINISTRATIVO a todo el
    // que no tuviera Servicio, sin mirar nunca `sucursalId`. Un
    // empleado sin ningún destino se volvía administrativo en silencio,
    // y el conteo no coincidía con el del Dashboard, que al mismo
    // empleado lo llamaba "sin asignar". Ahora ambos consumen la misma
    // fuente de verdad y no puede haber dos respuestas.
    final plantilla = await _obtenerPlantillaPersonal.ejecutar();
    final administrativos = plantilla.administrativa.activos;
    final operativos = plantilla.operativa.activos;

    final personalPorServicio = <String, int>{};
    for (final empleado in activos) {
      final servicioId = servicioIdPorEmpleado[empleado.id];
      if (servicioId != null) {
        personalPorServicio[servicioId] = (personalPorServicio[servicioId] ?? 0) + 1;
      }
    }

    final enRango = _enRango(rangoInicio, rangoFin);

    final altas = <EmpleadoReporteRow>[];
    final reingresos = <EmpleadoReporteRow>[];
    for (final empleado in todos) {
      if (!enRango(empleado.fechaIngreso)) continue;
      final periodos = periodosPorEmpleado[empleado.id] ?? const [];
      if (periodos.isEmpty) {
        altas.add(empleado);
      } else {
        reingresos.add(empleado);
      }
    }

    final bajas = <BajaEnPeriodo>[];
    for (final empleado in todos) {
      final fechaBaja = empleado.fechaBaja;
      if (fechaBaja != null && empleado.motivoBaja != null && enRango(fechaBaja)) {
        bajas.add(BajaEnPeriodo(
          empleadoId: empleado.id,
          nombreCompleto: empleado.nombreCompleto,
          fechaBaja: fechaBaja,
          motivoBaja: MotivoBajaEmpleado.values.byName(empleado.motivoBaja!),
        ));
      }
    }
    for (final empleado in todos) {
      for (final periodo in periodosPorEmpleado[empleado.id] ?? const []) {
        if (enRango(periodo.fechaBaja)) {
          bajas.add(BajaEnPeriodo(
            empleadoId: empleado.id,
            nombreCompleto: empleado.nombreCompleto,
            fechaBaja: periodo.fechaBaja,
            motivoBaja: MotivoBajaEmpleado.values.byName(periodo.motivoBaja),
          ));
        }
      }
    }

    final motivosConteo = <MotivoBajaEmpleado, int>{};
    for (final baja in bajas) {
      motivosConteo[baja.motivoBaja] = (motivosConteo[baja.motivoBaja] ?? 0) + 1;
    }

    final proximosAniversarios = <EmpleadoConCiclo>[];
    for (final empleado in activos) {
      final ciclo = calcularCicloLaboralDesdeFechas(
        fechaIngreso: empleado.fechaIngreso,
        estatus: empleado.estatus,
        fechaBaja: empleado.fechaBaja,
        hoy: referencia,
      );
      final proximo = ciclo.fechaProximoAniversario;
      if (proximo != null && proximo.difference(referencia).inDays <= _diasVentanaAniversario) {
        proximosAniversarios.add(EmpleadoConCiclo(empleado: empleado, ciclo: ciclo));
      }
    }

    final bajaActual = todos.where((e) => e.estatus == EstatusEmpleado.baja.name);
    final alertas = <EmpleadoConAlerta>[];
    for (final empleado in bajaActual) {
      final alerta = calcularAlertaRecontratacionDesdeMotivo(
        empleado.motivoBaja,
        periodosPorEmpleado[empleado.id] ?? const [],
      );
      if (alerta.tieneAdvertencia) alertas.add(EmpleadoConAlerta(empleado: empleado, alerta: alerta));
    }

    return ResumenPersonalReportes(
      totalActivos: activos.length,
      totalAdministrativos: administrativos,
      totalOperativos: operativos,
      personalPorServicio: personalPorServicio,
      altasEnPeriodo: altas,
      reingresosEnPeriodo: reingresos,
      bajasEnPeriodo: bajas,
      motivosBajaConteo: motivosConteo,
      proximosAniversarios: proximosAniversarios,
      alertasRecontratacion: alertas,
    );
  }

  bool Function(DateTime) _enRango(DateTime? rangoInicio, DateTime? rangoFin) {
    return (fecha) {
      if (rangoInicio != null && fecha.isBefore(rangoInicio)) return false;
      if (rangoFin != null && fecha.isAfter(rangoFin)) return false;
      return true;
    };
  }
}
