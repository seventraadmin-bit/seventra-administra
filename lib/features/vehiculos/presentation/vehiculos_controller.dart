import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/permissions/authorization_service.dart';
import 'package:riseg_one/features/dashboard/presentation/dashboard_controller.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';
import 'package:riseg_one/features/usuarios/usuarios_providers.dart';
import 'package:riseg_one/features/vehiculos/data/tables/vehiculo_table.dart' show MotivoBajaVehiculo;
import 'package:riseg_one/features/vehiculos/domain/usecases/actualizar_fotografia_vehiculo_usecase.dart';
import 'package:riseg_one/features/vehiculos/domain/usecases/cambiar_estatus_vehiculo_usecase.dart';
import 'package:riseg_one/features/vehiculos/domain/usecases/corregir_vehiculo_usecase.dart';
import 'package:riseg_one/features/vehiculos/domain/usecases/crear_vehiculo_usecase.dart';
import 'package:riseg_one/features/vehiculos/domain/usecases/asignar_vehiculo_usecase.dart';
import 'package:riseg_one/features/vehiculos/domain/usecases/cambiar_asignacion_vehiculo_usecase.dart';
import 'package:riseg_one/features/vehiculos/domain/usecases/dar_de_baja_vehiculo_usecase.dart';
import 'package:riseg_one/features/vehiculos/domain/usecases/finalizar_mantenimiento_vehiculo_usecase.dart';
import 'package:riseg_one/features/vehiculos/domain/usecases/registrar_kilometraje_vehiculo_usecase.dart';
import 'package:riseg_one/features/vehiculos/domain/usecases/retirar_asignacion_vehiculo_usecase.dart';

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

  /// Usuario autenticado que ejecuta la operación (Etapa 11D) — mismo
  /// criterio que `UsuariosController._actorUsuarioId`.
  String? get _actorUsuarioId => ref.read(sesionControllerProvider)?.usuarioId;

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
    final resultado = await autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'vehiculos.crear',
      () => ref.read(crearVehiculoUseCaseProvider).ejecutar(
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
          ),
      CrearVehiculoErrorInesperado.new,
    );
    if (resultado is CrearVehiculoExitoso) {
      await _cargar();
      ref.invalidate(dashboardControllerProvider);
    }
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
    required String motivo,
  }) async {
    final resultado = await autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'vehiculos.modificar',
      () => ref.read(corregirVehiculoUseCaseProvider).ejecutar(
            // schemaVersion 80: motivo y actor obligatorios — toda
            // corrección del expediente deja rastro.
            motivo: motivo,
            actorUsuarioId: _actorUsuarioId,
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
          ),
      CorregirVehiculoErrorInesperado.new,
    );
    if (resultado is CorregirVehiculoExitoso) {
      await _cargar();
      ref.invalidate(dashboardControllerProvider);
    }
    return resultado;
  }

  Future<CambiarEstatusVehiculoResultado> cambiarEstatus({required String vehiculoId, required String estatus}) async {
    final resultado = await autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'vehiculos.modificar',
      () => ref.read(cambiarEstatusVehiculoUseCaseProvider).ejecutar(
            vehiculoId: vehiculoId,
            estatus: estatus,
          ),
      CambiarEstatusVehiculoErrorInesperado.new,
    );
    if (resultado is CambiarEstatusVehiculoExitoso) {
      await _cargar();
      ref.invalidate(dashboardControllerProvider);
    }
    return resultado;
  }

  /// Cierra el paso por `enMantenimiento` recalculando el estatus
  /// correcto (Etapa 8D, punto 3) — ver el doc comment de
  /// `FinalizarMantenimientoVehiculoUseCase`.
  Future<FinalizarMantenimientoVehiculoResultado> finalizarMantenimiento({required String vehiculoId}) async {
    final resultado = await autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'vehiculos.modificar',
      () => ref.read(finalizarMantenimientoVehiculoUseCaseProvider).ejecutar(vehiculoId: vehiculoId),
      FinalizarMantenimientoVehiculoErrorInesperado.new,
    );
    if (resultado is FinalizarMantenimientoVehiculoExitoso) {
      await _cargar();
      ref.invalidate(dashboardControllerProvider);
    }
    return resultado;
  }

  Future<DarDeBajaVehiculoResultado> darDeBaja({
    required String vehiculoId,
    required DateTime fechaBaja,
    required MotivoBajaVehiculo motivoBaja,
    String? observacionesBaja,
  }) async {
    final resultado = await autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'vehiculos.archivar',
      () => ref.read(darDeBajaVehiculoUseCaseProvider).ejecutar(
            vehiculoId: vehiculoId,
            fechaBaja: fechaBaja,
            motivoBaja: motivoBaja,
            observacionesBaja: observacionesBaja,
          ),
      DarDeBajaVehiculoErrorInesperado.new,
    );
    if (resultado is DarDeBajaVehiculoExitoso) {
      await _cargar();
      ref.invalidate(dashboardControllerProvider);
    }
    return resultado;
  }

  Future<ActualizarFotografiaVehiculoResultado> actualizarFotografia({
    required String vehiculoId,
    required String sourceFilePath,
    required String originalFileName,
    required String mimeType,
  }) async {
    final resultado = await autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'vehiculos.modificar',
      () => ref.read(actualizarFotografiaVehiculoUseCaseProvider).ejecutar(
            vehiculoId: vehiculoId,
            sourceFilePath: sourceFilePath,
            originalFileName: originalFileName,
            mimeType: mimeType,
          ),
      ActualizarFotografiaVehiculoErrorInesperado.new,
    );
    if (resultado is ActualizarFotografiaVehiculoExitoso) await _cargar();
    return resultado;
  }

  // --- Asignaciones y kilometraje (Etapa 8B) ---

  Future<AsignarVehiculoResultado> asignar({
    required String vehiculoId,
    String? empleadoId,
    String? servicioId,
    required DateTime fechaInicio,
    String? observaciones,
    int? kilometrajeEntrega,
  }) async {
    final resultado = await autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'vehiculos.operar',
      () => ref.read(asignarVehiculoUseCaseProvider).ejecutar(
            vehiculoId: vehiculoId,
            empleadoId: empleadoId,
            servicioId: servicioId,
            fechaInicio: fechaInicio,
            observaciones: observaciones,
            kilometrajeEntrega: kilometrajeEntrega,
            actorUsuarioId: _actorUsuarioId,
          ),
      AsignarVehiculoErrorInesperado.new,
    );
    if (resultado is AsignarVehiculoExitoso) {
      await _cargar();
      ref.invalidate(dashboardControllerProvider);
    }
    return resultado;
  }

  Future<CambiarAsignacionVehiculoResultado> cambiarAsignacion({
    required String asignacionVehiculoActualId,
    required DateTime fecha,
    String? observacionesTermino,
    String? nuevoEmpleadoId,
    String? nuevoServicioId,
    String? observacionesNueva,
  }) async {
    final resultado = await autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'vehiculos.modificar',
      () => ref.read(cambiarAsignacionVehiculoUseCaseProvider).ejecutar(
            asignacionVehiculoActualId: asignacionVehiculoActualId,
            fecha: fecha,
            observacionesTermino: observacionesTermino,
            nuevoEmpleadoId: nuevoEmpleadoId,
            nuevoServicioId: nuevoServicioId,
            observacionesNueva: observacionesNueva,
            actorUsuarioId: _actorUsuarioId,
          ),
      CambiarAsignacionVehiculoErrorInesperado.new,
    );
    if (resultado is CambiarAsignacionVehiculoExitoso) {
      await _cargar();
      ref.invalidate(dashboardControllerProvider);
    }
    return resultado;
  }

  Future<RetirarAsignacionVehiculoResultado> retirarAsignacion({
    required String asignacionVehiculoId,
    required DateTime fechaTermino,
    String? observacionesTermino,
    int? kilometrajeDevolucion,
  }) async {
    final resultado = await autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'vehiculos.modificar',
      () => ref.read(retirarAsignacionVehiculoUseCaseProvider).ejecutar(
            asignacionVehiculoId: asignacionVehiculoId,
            fechaTermino: fechaTermino,
            observacionesTermino: observacionesTermino,
            kilometrajeDevolucion: kilometrajeDevolucion,
            actorUsuarioId: _actorUsuarioId,
          ),
      RetirarAsignacionVehiculoErrorInesperado.new,
    );
    if (resultado is RetirarAsignacionVehiculoExitoso) {
      await _cargar();
      ref.invalidate(dashboardControllerProvider);
    }
    return resultado;
  }

  Future<RegistrarKilometrajeVehiculoResultado> registrarKilometraje({
    required String vehiculoId,
    required DateTime fecha,
    required int kilometraje,
    required String origen,
    String? observaciones,
  }) async {
    // No afecta el listado (kilometraje no es una columna de Vehiculo),
    // pero sí puede afectar el estatus si en el futuro se deriva de
    // aquí — se refresca por consistencia con el resto de acciones.
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'vehiculos.modificar',
      () => ref.read(registrarKilometrajeVehiculoUseCaseProvider).ejecutar(
            vehiculoId: vehiculoId,
            fecha: fecha,
            kilometraje: kilometraje,
            origen: origen,
            observaciones: observaciones,
            actorUsuarioId: _actorUsuarioId,
          ),
      RegistrarKilometrajeVehiculoErrorInesperado.new,
    );
  }
}
