import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/adjuntar_comprobante_egreso_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/cancelar_egreso_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/corregir_egreso_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_egreso_usecase.dart';
import 'package:riseg_one/core/permissions/authorization_service.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';
import 'package:riseg_one/features/usuarios/usuarios_providers.dart';

import '../../../organizacion/organizacion_providers.dart';
import '../../finanzas_providers.dart';
import 'egresos_state.dart';

part 'egresos_controller.g.dart';

/// Controlador del listado de Egresos (Etapa 4K.1) — mismo diseño que
/// `IngresosController`.
@riverpod
class EgresosController extends _$EgresosController {
  @override
  EgresosState build() {
    Future.microtask(_cargar);
    return const EgresosState();
  }

  /// Usuario autenticado que ejecuta la operación (Etapa 11D) — mismo
  /// criterio que `UsuariosController._actorUsuarioId`.
  String? get _actorUsuarioId => ref.read(sesionControllerProvider)?.usuarioId;

  Future<void> _cargar() async {
    state = state.copyWith(cargando: true, errorCarga: null);
    try {
      final egresos = await ref.read(egresoRepositoryProvider).listar(
            estatus: state.estatus,
            servicioId: state.servicioId,
          );
      state = state.copyWith(cargando: false, egresos: egresos, errorCarga: null);
    } catch (e) {
      state = state.copyWith(cargando: false, errorCarga: e.toString());
    }
  }

  Future<void> reintentarCarga() => _cargar();

  Future<void> aplicarFiltros({
    String? estatus,
    String? servicioId,
    bool limpiarEstatus = false,
    bool limpiarServicioId = false,
  }) async {
    state = state.copyWith(
      estatus: estatus,
      servicioId: servicioId,
      limpiarEstatus: limpiarEstatus,
      limpiarServicioId: limpiarServicioId,
    );
    await _cargar();
  }

  Future<void> recargar() => _cargar();

  Future<EgresoData?> obtenerPorId(String egresoId) {
    return ref.read(egresoRepositoryProvider).obtenerPorId(egresoId);
  }

  Future<List<EgresoEventoData>> listarEventos(String egresoId) {
    return ref.read(egresoRepositoryProvider).listarEventos(egresoId);
  }

  Future<List<AttachmentData>> listarComprobantes(String egresoId) {
    return ref.read(attachmentRepositoryProvider).listarActivosPorEgreso(egresoId);
  }

  Future<void> abrirArchivo(String path) {
    return ref.read(attachmentStorageProvider).abrir(path);
  }

  Future<RegistrarEgresoResultado> registrar({
    required int monto,
    required DateTime fecha,
    String? categoriaFinancieraId,
    String? servicioId,
    String? sucursalId,
    String? areaId,
    String? cuentaCaja,
    required String formaPago,
    String? beneficiario,
    required String concepto,
    String? observaciones,
  }) async {
    final resultado = await autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'finanzas.crear',
      () => ref.read(registrarEgresoUseCaseProvider).ejecutar(
            monto: monto,
            fecha: fecha,
            categoriaFinancieraId: categoriaFinancieraId,
            servicioId: servicioId,
            sucursalId: sucursalId,
            areaId: areaId,
            cuentaCaja: cuentaCaja,
            formaPago: formaPago,
            beneficiario: beneficiario,
            concepto: concepto,
            observaciones: observaciones,
            actorUsuarioId: _actorUsuarioId,
          ),
      RegistrarEgresoErrorInesperado.new,
    );
    if (resultado is RegistrarEgresoExitoso) {
      await _cargar();
    }
    return resultado;
  }

  Future<CorregirEgresoResultado> corregir({
    required String egresoId,
    DateTime? fecha,
    String? categoriaFinancieraId,
    String? servicioId,
    String? sucursalId,
    String? areaId,
    String? cuentaCaja,
    String? formaPago,
    String? beneficiario,
    String? concepto,
    String? observaciones,
    required String motivo,
  }) async {
    final resultado = await autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'finanzas.modificar',
      () => ref.read(corregirEgresoUseCaseProvider).ejecutar(
            egresoId: egresoId,
            fecha: fecha,
            categoriaFinancieraId: categoriaFinancieraId,
            servicioId: servicioId,
            sucursalId: sucursalId,
            areaId: areaId,
            cuentaCaja: cuentaCaja,
            formaPago: formaPago,
            beneficiario: beneficiario,
            concepto: concepto,
            observaciones: observaciones,
            motivo: motivo,
            actorUsuarioId: _actorUsuarioId,
          ),
      CorregirEgresoErrorInesperado.new,
    );
    if (resultado is CorregirEgresoExitoso) {
      await _cargar();
    }
    return resultado;
  }

  Future<CancelarEgresoResultado> cancelar({required String egresoId, required String motivo}) async {
    final resultado = await autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'finanzas.archivar',
      () => ref
          .read(cancelarEgresoUseCaseProvider)
          .ejecutar(egresoId: egresoId, motivo: motivo, actorUsuarioId: _actorUsuarioId),
      CancelarEgresoErrorInesperado.new,
    );
    if (resultado is CancelarEgresoExitoso) {
      await _cargar();
    }
    return resultado;
  }

  Future<AdjuntarComprobanteEgresoResultado> adjuntarComprobante({
    required String egresoId,
    required String sourceFilePath,
    required String originalFileName,
    required String mimeType,
  }) {
    return ref.read(adjuntarComprobanteEgresoUseCaseProvider).ejecutar(
          egresoId: egresoId,
          sourceFilePath: sourceFilePath,
          originalFileName: originalFileName,
          mimeType: mimeType,
        );
  }
}
