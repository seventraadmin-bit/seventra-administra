import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/telefonia/data/tables/linea_telefonica_table.dart' show MotivoBajaLineaTelefonica;
import 'package:riseg_one/features/telefonia/domain/usecases/cambiar_estatus_linea_telefonica_usecase.dart';
import 'package:riseg_one/features/telefonia/domain/usecases/corregir_linea_telefonica_usecase.dart';
import 'package:riseg_one/features/telefonia/domain/usecases/crear_linea_telefonica_usecase.dart';
import 'package:riseg_one/features/telefonia/domain/usecases/dar_de_baja_linea_telefonica_usecase.dart';

import '../telefonia_providers.dart';
import 'telefonia_state.dart';

part 'telefonia_controller.g.dart';

/// Controlador de Telefonía (Etapa 9A) — listado de líneas + todas las
/// operaciones de expediente, mismo criterio que `VehiculosController`
/// (un solo controlador para listado + expediente).
@riverpod
class TelefoniaController extends _$TelefoniaController {
  @override
  TelefoniaState build() {
    Future.microtask(_cargar);
    return const TelefoniaState();
  }

  Future<void> _cargar() async {
    state = state.copyWith(cargando: true, errorCarga: null);
    try {
      final lineas = await ref.read(lineaTelefonicaRepositoryProvider).listar();
      state = state.copyWith(cargando: false, lineas: lineas, errorCarga: null);
    } catch (e) {
      state = state.copyWith(cargando: false, errorCarga: e.toString());
    }
  }

  Future<void> reintentarCarga() => _cargar();

  Future<void> recargar() => _cargar();

  Future<LineaTelefonicaData?> obtenerLinea(String lineaTelefonicaId) {
    return ref.read(lineaTelefonicaRepositoryProvider).obtenerPorId(lineaTelefonicaId);
  }

  Future<CrearLineaTelefonicaResultado> crearLinea({
    String? numero,
    required String operador,
    String? operadorOtroNombre,
    required String modalidadSim,
    String? iccid,
    DateTime? fechaActivacion,
    String? observaciones,
  }) async {
    final resultado = await ref.read(crearLineaTelefonicaUseCaseProvider).ejecutar(
          numero: numero,
          operador: operador,
          operadorOtroNombre: operadorOtroNombre,
          modalidadSim: modalidadSim,
          iccid: iccid,
          fechaActivacion: fechaActivacion,
          observaciones: observaciones,
        );
    if (resultado is CrearLineaTelefonicaExitoso) await _cargar();
    return resultado;
  }

  Future<CorregirLineaTelefonicaResultado> corregirLinea({
    required String lineaTelefonicaId,
    String? numero,
    String? operador,
    String? operadorOtroNombre,
    String? modalidadSim,
    String? iccid,
    DateTime? fechaActivacion,
    String? observaciones,
    bool limpiarNumero = false,
    bool limpiarOperadorOtroNombre = false,
    bool limpiarIccid = false,
    bool limpiarFechaActivacion = false,
    bool limpiarObservaciones = false,
  }) async {
    final resultado = await ref.read(corregirLineaTelefonicaUseCaseProvider).ejecutar(
          lineaTelefonicaId: lineaTelefonicaId,
          numero: numero,
          operador: operador,
          operadorOtroNombre: operadorOtroNombre,
          modalidadSim: modalidadSim,
          iccid: iccid,
          fechaActivacion: fechaActivacion,
          observaciones: observaciones,
          limpiarNumero: limpiarNumero,
          limpiarOperadorOtroNombre: limpiarOperadorOtroNombre,
          limpiarIccid: limpiarIccid,
          limpiarFechaActivacion: limpiarFechaActivacion,
          limpiarObservaciones: limpiarObservaciones,
        );
    if (resultado is CorregirLineaTelefonicaExitoso) await _cargar();
    return resultado;
  }

  Future<CambiarEstatusLineaTelefonicaResultado> cambiarEstatus({
    required String lineaTelefonicaId,
    required String estatus,
  }) async {
    final resultado = await ref
        .read(cambiarEstatusLineaTelefonicaUseCaseProvider)
        .ejecutar(lineaTelefonicaId: lineaTelefonicaId, estatus: estatus);
    if (resultado is CambiarEstatusLineaTelefonicaExitoso) await _cargar();
    return resultado;
  }

  Future<DarDeBajaLineaTelefonicaResultado> darDeBaja({
    required String lineaTelefonicaId,
    required DateTime fechaBaja,
    required MotivoBajaLineaTelefonica motivoBaja,
    String? observacionesBaja,
  }) async {
    final resultado = await ref.read(darDeBajaLineaTelefonicaUseCaseProvider).ejecutar(
          lineaTelefonicaId: lineaTelefonicaId,
          fechaBaja: fechaBaja,
          motivoBaja: motivoBaja,
          observacionesBaja: observacionesBaja,
        );
    if (resultado is DarDeBajaLineaTelefonicaExitoso) await _cargar();
    return resultado;
  }
}
