import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/vehiculos/domain/repositories/vehiculo_documento_repository.dart';
import 'package:riseg_one/features/vehiculos/domain/repositories/vehiculo_kilometraje_repository.dart';
import 'package:riseg_one/features/vehiculos/domain/repositories/vehiculo_mantenimiento_repository.dart';
import 'package:riseg_one/features/vehiculos/domain/repositories/vehiculo_repository.dart';

import 'agrupar_documentos_vehiculo.dart';
import 'calcular_estado_vigencia_documento.dart';
import 'calcular_proximo_mantenimiento.dart';

/// Un documento vigente de un tipo, ya en estado `vencido`/
/// `proximoAVencer`, con su Vehículo resuelto.
class AlertaDocumentoVehiculo {
  const AlertaDocumentoVehiculo({required this.vehiculo, required this.documento, required this.estado});
  final VehiculoData vehiculo;
  final VehiculoDocumentoData documento;
  final EstadoVigenciaDocumento estado;
}

/// El próximo mantenimiento derivado de un Vehículo, ya en estado
/// `proximo`/`vencido`.
class AlertaMantenimientoVehiculo {
  const AlertaMantenimientoVehiculo({required this.vehiculo, required this.proximo});
  final VehiculoData vehiculo;
  final ProximoMantenimientoVehiculo proximo;
}

class ResumenAlertasVehiculos {
  const ResumenAlertasVehiculos({
    required this.vehiculosPorEstatus,
    required this.alertasDocumentos,
    required this.alertasMantenimiento,
  });

  /// Conteo snapshot (a la fecha de hoy) por cada valor de
  /// `EstatusVehiculo` — incluye `baja`, a diferencia de las alertas de
  /// abajo, que la excluyen.
  final Map<String, int> vehiculosPorEstatus;

  /// Nunca incluye vehículos en `baja` (mismo criterio ya vigente desde
  /// la Etapa 8C/8D).
  final List<AlertaDocumentoVehiculo> alertasDocumentos;
  final List<AlertaMantenimientoVehiculo> alertasMantenimiento;
}

/// Orquestación de alertas de Vehículos (Etapas 8C/8D) — extraída de
/// `AlertasVehiculosScreen._cargar()` (Etapa 12C, Reportes) para que la
/// pantalla de Alertas existente y el bloque de Vehículos en Reportes
/// generales compartan exactamente la misma lógica, sin duplicarla.
/// Las funciones puras que aplica (`calcularEstadoVigenciaDocumento`/
/// `calcularProximoMantenimiento`) no cambian — esto solo mueve el
/// "cómo se agrupa y se recorre" a un solo lugar.
class ObtenerAlertasVehiculosUseCase {
  ObtenerAlertasVehiculosUseCase(
    this._vehiculoRepository,
    this._documentoRepository,
    this._mantenimientoRepository,
    this._kilometrajeRepository,
  );

  final VehiculoRepository _vehiculoRepository;
  final VehiculoDocumentoRepository _documentoRepository;
  final VehiculoMantenimientoRepository _mantenimientoRepository;
  final VehiculoKilometrajeRepository _kilometrajeRepository;

  Future<ResumenAlertasVehiculos> ejecutar({DateTime? hoy}) async {
    final vehiculos = await _vehiculoRepository.listar();
    final documentos = await _documentoRepository.listarTodos();
    final mantenimientos = await _mantenimientoRepository.listarTodos();
    final kilometrajes = await _kilometrajeRepository.listarTodos();

    final documentosPorVehiculo = <String, List<VehiculoDocumentoData>>{};
    for (final documento in documentos) {
      documentosPorVehiculo.putIfAbsent(documento.vehiculoId, () => []).add(documento);
    }

    final mantenimientosPorVehiculo = <String, List<VehiculoMantenimientoData>>{};
    for (final registro in mantenimientos) {
      mantenimientosPorVehiculo.putIfAbsent(registro.vehiculoId, () => []).add(registro);
    }
    // `kilometrajes` no viene ordenado por Vehículo — se agrupa y solo
    // se conserva la lectura más reciente de cada uno (mismo criterio
    // que `VehiculoKilometrajeRepositoryImpl.obtenerActual`, aquí
    // derivado en memoria para evitar N+1).
    final kilometrajeActualPorVehiculo = <String, int>{};
    for (final lectura in kilometrajes) {
      final actual = kilometrajeActualPorVehiculo[lectura.vehiculoId];
      if (actual == null) kilometrajeActualPorVehiculo[lectura.vehiculoId] = lectura.kilometraje;
    }

    final vehiculosPorEstatus = <String, int>{};
    final alertasDocumentos = <AlertaDocumentoVehiculo>[];
    final alertasMantenimiento = <AlertaMantenimientoVehiculo>[];

    for (final vehiculo in vehiculos) {
      vehiculosPorEstatus[vehiculo.estatus] = (vehiculosPorEstatus[vehiculo.estatus] ?? 0) + 1;
      if (vehiculo.estatus == 'baja') continue;

      final documentosDelVehiculo = documentosPorVehiculo[vehiculo.id];
      if (documentosDelVehiculo != null) {
        for (final documento in documentosVigentesPorTipo(documentosDelVehiculo)) {
          final estado = calcularEstadoVigenciaDocumento(documento.fechaVencimiento, hoy: hoy);
          if (estado == EstadoVigenciaDocumento.vencido || estado == EstadoVigenciaDocumento.proximoAVencer) {
            alertasDocumentos.add(AlertaDocumentoVehiculo(vehiculo: vehiculo, documento: documento, estado: estado));
          }
        }
      }

      final mantenimientosDelVehiculo = mantenimientosPorVehiculo[vehiculo.id];
      if (mantenimientosDelVehiculo != null) {
        // Mismo orden que `listarPorVehiculo` (desc por fecha) — la
        // fuente masiva no lo garantiza, así que se ordena aquí.
        mantenimientosDelVehiculo.sort((a, b) => b.fecha.compareTo(a.fecha));
        final proximo = calcularProximoMantenimiento(
          mantenimientosDelVehiculo,
          kilometrajeActualPorVehiculo[vehiculo.id],
          hoy: hoy,
        );
        if (proximo != null &&
            (proximo.estado == EstadoProximoMantenimiento.proximo || proximo.estado == EstadoProximoMantenimiento.vencido)) {
          alertasMantenimiento.add(AlertaMantenimientoVehiculo(vehiculo: vehiculo, proximo: proximo));
        }
      }
    }

    alertasDocumentos.sort((a, b) {
      if (a.estado != b.estado) return a.estado == EstadoVigenciaDocumento.vencido ? -1 : 1;
      final fechaA = a.documento.fechaVencimiento;
      final fechaB = b.documento.fechaVencimiento;
      if (fechaA == null || fechaB == null) return 0;
      return fechaA.compareTo(fechaB);
    });
    alertasMantenimiento.sort((a, b) {
      if (a.proximo.estado != b.proximo.estado) {
        return a.proximo.estado == EstadoProximoMantenimiento.vencido ? -1 : 1;
      }
      return 0;
    });

    return ResumenAlertasVehiculos(
      vehiculosPorEstatus: vehiculosPorEstatus,
      alertasDocumentos: alertasDocumentos,
      alertasMantenimiento: alertasMantenimiento,
    );
  }
}
