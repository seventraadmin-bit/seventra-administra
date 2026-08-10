import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/vehiculos/data/tables/vehiculo_table.dart' show MotivoBajaVehiculo;
import 'package:riseg_one/features/vehiculos/domain/usecases/actualizar_fotografia_vehiculo_usecase.dart';
import 'package:riseg_one/features/vehiculos/domain/usecases/cambiar_estatus_vehiculo_usecase.dart';
import 'package:riseg_one/features/vehiculos/domain/usecases/corregir_vehiculo_usecase.dart';
import 'package:riseg_one/features/vehiculos/domain/usecases/crear_vehiculo_usecase.dart';
import 'package:riseg_one/features/vehiculos/domain/usecases/dar_de_baja_vehiculo_usecase.dart';

import '../vehiculos_providers.dart';
import 'vehiculos_state.dart';

part 'vehiculos_controller.g.dart';

/// Controlador de Vehículos (Etapa 8A) — listado de la flotilla + todas
/// las operaciones de expediente, mismo criterio que
/// `ArticulosController` (un solo controlador para listado + expediente).
@riverpod
class VehiculosController extends _$VehiculosController {
  @override
  VehiculosState build() {
    Future.microtask(_cargar);
    return const VehiculosState();
  }

  Future<void> _cargar() async {
    state = state.copyWith(cargando: true, errorCarga: null);
    try {
      final vehiculos = await ref.read(vehiculoRepositoryProvider).listar();
      state = state.copyWith(cargando: false, vehiculos: vehiculos, errorCarga: null);
    } catch (e) {
      state = state.copyWith(cargando: false, errorCarga: e.toString());
    }
  }

  Future<void> reintentarCarga() => _cargar();

  Future<void> recargar() => _cargar();

  Future<VehiculoData?> obtenerVehiculo(String vehiculoId) {
    return ref.read(vehiculoRepositoryProvider).obtenerPorId(vehiculoId);
  }

  Future<CrearVehiculoResultado> crearVehiculo({
    required String marca,
    required String modelo,
    int? anio,
    String? color,
    String? placas,
    String? vin,
    String? numeroMotor,
    required String tipoVehiculo,
    DateTime? fechaAdquisicion,
    int? costoAdquisicion,
    String? observaciones,
  }) async {
    final resultado = await ref.read(crearVehiculoUseCaseProvider).ejecutar(
          marca: marca,
          modelo: modelo,
          anio: anio,
          color: color,
          placas: placas,
          vin: vin,
          numeroMotor: numeroMotor,
          tipoVehiculo: tipoVehiculo,
          fechaAdquisicion: fechaAdquisicion,
          costoAdquisicion: costoAdquisicion,
          observaciones: observaciones,
        );
    if (resultado is CrearVehiculoExitoso) await _cargar();
    return resultado;
  }

  Future<CorregirVehiculoResultado> corregirVehiculo({
    required String vehiculoId,
    String? marca,
    String? modelo,
    int? anio,
    String? color,
    String? placas,
    String? vin,
    String? numeroMotor,
    String? tipoVehiculo,
    DateTime? fechaAdquisicion,
    int? costoAdquisicion,
    String? observaciones,
    bool limpiarAnio = false,
    bool limpiarColor = false,
    bool limpiarPlacas = false,
    bool limpiarVin = false,
    bool limpiarNumeroMotor = false,
    bool limpiarFechaAdquisicion = false,
    bool limpiarCostoAdquisicion = false,
    bool limpiarObservaciones = false,
  }) async {
    final resultado = await ref.read(corregirVehiculoUseCaseProvider).ejecutar(
          vehiculoId: vehiculoId,
          marca: marca,
          modelo: modelo,
          anio: anio,
          color: color,
          placas: placas,
          vin: vin,
          numeroMotor: numeroMotor,
          tipoVehiculo: tipoVehiculo,
          fechaAdquisicion: fechaAdquisicion,
          costoAdquisicion: costoAdquisicion,
          observaciones: observaciones,
          limpiarAnio: limpiarAnio,
          limpiarColor: limpiarColor,
          limpiarPlacas: limpiarPlacas,
          limpiarVin: limpiarVin,
          limpiarNumeroMotor: limpiarNumeroMotor,
          limpiarFechaAdquisicion: limpiarFechaAdquisicion,
          limpiarCostoAdquisicion: limpiarCostoAdquisicion,
          limpiarObservaciones: limpiarObservaciones,
        );
    if (resultado is CorregirVehiculoExitoso) await _cargar();
    return resultado;
  }

  Future<CambiarEstatusVehiculoResultado> cambiarEstatus({required String vehiculoId, required String estatus}) async {
    final resultado = await ref.read(cambiarEstatusVehiculoUseCaseProvider).ejecutar(
          vehiculoId: vehiculoId,
          estatus: estatus,
        );
    if (resultado is CambiarEstatusVehiculoExitoso) await _cargar();
    return resultado;
  }

  Future<DarDeBajaVehiculoResultado> darDeBaja({
    required String vehiculoId,
    required DateTime fechaBaja,
    required MotivoBajaVehiculo motivoBaja,
    String? observacionesBaja,
  }) async {
    final resultado = await ref.read(darDeBajaVehiculoUseCaseProvider).ejecutar(
          vehiculoId: vehiculoId,
          fechaBaja: fechaBaja,
          motivoBaja: motivoBaja,
          observacionesBaja: observacionesBaja,
        );
    if (resultado is DarDeBajaVehiculoExitoso) await _cargar();
    return resultado;
  }

  Future<ActualizarFotografiaVehiculoResultado> actualizarFotografia({
    required String vehiculoId,
    required String sourceFilePath,
    required String originalFileName,
    required String mimeType,
  }) async {
    final resultado = await ref.read(actualizarFotografiaVehiculoUseCaseProvider).ejecutar(
          vehiculoId: vehiculoId,
          sourceFilePath: sourceFilePath,
          originalFileName: originalFileName,
          mimeType: mimeType,
        );
    if (resultado is ActualizarFotografiaVehiculoExitoso) await _cargar();
    return resultado;
  }
}
