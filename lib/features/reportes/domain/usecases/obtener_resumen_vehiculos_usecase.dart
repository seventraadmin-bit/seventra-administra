import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/vehiculos/data/tables/vehiculo_mantenimiento_table.dart';
import 'package:riseg_one/features/vehiculos/domain/repositories/vehiculo_mantenimiento_repository.dart';
import 'package:riseg_one/features/vehiculos/domain/repositories/vehiculo_repository.dart';
import 'package:riseg_one/features/vehiculos/domain/usecases/calcular_estado_vigencia_documento.dart';
import 'package:riseg_one/features/vehiculos/domain/usecases/calcular_proximo_mantenimiento.dart';
import 'package:riseg_one/features/vehiculos/domain/usecases/obtener_alertas_vehiculos_usecase.dart';

/// Un renglón de mantenimiento/incidencia ya con la etiqueta del
/// Vehículo resuelta (Etapa 12D — soporta la exportación XLSX; el
/// resumen en pantalla nunca usó esta lista, solo los totales).
class MantenimientoConVehiculo {
  const MantenimientoConVehiculo({required this.registro, required this.vehiculoLabel});

  final VehiculoMantenimientoData registro;
  final String vehiculoLabel;
}

/// Resumen de Vehículos para el bloque "Operación" de Reportes (Etapa
/// 12C). [vehiculosPorEstatus] es un **snapshot** (a la fecha de hoy,
/// ignora el rango); los totales de mantenimiento/incidencias sí son
/// **del periodo** consultado — nunca se mezclan visualmente sin esa
/// distinción explícita. No existe forma de preguntar "qué vehículos
/// estuvieron en mantenimiento durante el periodo X" (sin historial de
/// estatus) — limitación real del modelo, no omitida a propósito.
class ResumenVehiculosReportes {
  const ResumenVehiculosReportes({
    required this.vehiculosPorEstatus,
    required this.totalMantenimientoEnPeriodo,
    required this.totalIncidenciasEnPeriodo,
    required this.documentosPorVencer,
    required this.documentosVencidos,
    required this.mantenimientosProximos,
    required this.mantenimientosVencidos,
    required this.detalleMantenimientos,
  });

  final Map<String, int> vehiculosPorEstatus;
  final int totalMantenimientoEnPeriodo;
  final int totalIncidenciasEnPeriodo;
  final int documentosPorVencer;
  final int documentosVencidos;
  final int mantenimientosProximos;
  final int mantenimientosVencidos;

  /// Renglones de mantenimiento/incidencia del periodo consultado, ya
  /// con el Vehículo etiquetado (Etapa 12D — soporta la exportación
  /// XLSX; ninguna tarjeta en pantalla usa esta lista).
  final List<MantenimientoConVehiculo> detalleMantenimientos;
}

/// Compone `ObtenerAlertasVehiculosUseCase` (ya existente, compartido
/// con la pantalla de Alertas) con los costos de mantenimiento del
/// periodo — nunca reimplementa la orquestación de alertas.
class ObtenerResumenVehiculosUseCase {
  ObtenerResumenVehiculosUseCase(this._obtenerAlertas, this._mantenimientoRepository, this._vehiculoRepository);

  final ObtenerAlertasVehiculosUseCase _obtenerAlertas;
  final VehiculoMantenimientoRepository _mantenimientoRepository;
  final VehiculoRepository _vehiculoRepository;

  Future<ResumenVehiculosReportes> ejecutar({DateTime? rangoInicio, DateTime? rangoFin, DateTime? hoy}) async {
    final alertas = await _obtenerAlertas.ejecutar(hoy: hoy);

    final mantenimientos = await _mantenimientoRepository.listarTodos();
    final vehiculos = await _vehiculoRepository.listar(soloActivos: false);
    final labelPorVehiculo = {
      for (final v in vehiculos) v.id: '${v.marca} ${v.modelo}${v.placas != null ? ' (${v.placas})' : ''}',
    };

    var totalMantenimiento = 0;
    var totalIncidencias = 0;
    final detalle = <MantenimientoConVehiculo>[];
    for (final registro in mantenimientos) {
      if (rangoInicio != null && registro.fecha.isBefore(rangoInicio)) continue;
      if (rangoFin != null && registro.fecha.isAfter(rangoFin)) continue;
      final esIncidencia = TipoMantenimientoVehiculo.values.byName(registro.tipo).esIncidencia;
      final costo = registro.costo ?? 0;
      if (esIncidencia) {
        totalIncidencias += costo;
      } else {
        totalMantenimiento += costo;
      }
      detalle.add(MantenimientoConVehiculo(
        registro: registro,
        vehiculoLabel: labelPorVehiculo[registro.vehiculoId] ?? registro.vehiculoId,
      ));
    }

    return ResumenVehiculosReportes(
      vehiculosPorEstatus: alertas.vehiculosPorEstatus,
      totalMantenimientoEnPeriodo: totalMantenimiento,
      totalIncidenciasEnPeriodo: totalIncidencias,
      documentosPorVencer: alertas.alertasDocumentos.where((a) => a.estado == EstadoVigenciaDocumento.proximoAVencer).length,
      documentosVencidos: alertas.alertasDocumentos.where((a) => a.estado == EstadoVigenciaDocumento.vencido).length,
      mantenimientosProximos:
          alertas.alertasMantenimiento.where((a) => a.proximo.estado == EstadoProximoMantenimiento.proximo).length,
      mantenimientosVencidos:
          alertas.alertasMantenimiento.where((a) => a.proximo.estado == EstadoProximoMantenimiento.vencido).length,
      detalleMantenimientos: detalle,
    );
  }
}
