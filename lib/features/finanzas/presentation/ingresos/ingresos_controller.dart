import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/dashboard/presentation/dashboard_controller.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/adjuntar_comprobante_ingreso_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/cancelar_ingreso_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/corregir_ingreso_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_ingreso_manual_usecase.dart';
import 'package:riseg_one/core/permissions/authorization_service.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';
import 'package:riseg_one/features/usuarios/usuarios_providers.dart';

import '../../../organizacion/organizacion_providers.dart';
import '../../finanzas_providers.dart';
import 'ingresos_state.dart';

part 'ingresos_controller.g.dart';

/// Controlador del listado de Ingresos (Etapa 4K.1) — mismo diseño que
/// `PagosController`.
@riverpod
class IngresosController extends _$IngresosController {
  @override
  IngresosState build() {
    Future.microtask(_cargar);
    return const IngresosState();
  }

  /// Usuario autenticado que ejecuta la operación (Etapa 11D) — mismo
  /// criterio que `UsuariosController._actorUsuarioId`.
  String? get _actorUsuarioId => ref.read(sesionControllerProvider)?.usuarioId;

  Future<void> _cargar() async {
    state = state.copyWith(cargando: true, errorCarga: null);
    try {
      final ingresos = await ref.read(ingresoRepositoryProvider).listar(
            estatus: state.estatus,
            servicioId: state.servicioId,
          );
      state = state.copyWith(cargando: false, ingresos: ingresos, errorCarga: null);
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

  Future<IngresoData?> obtenerPorId(String ingresoId) {
    return ref.read(ingresoRepositoryProvider).obtenerPorId(ingresoId);
  }

  Future<List<IngresoEventoData>> listarEventos(String ingresoId) {
    return ref.read(ingresoRepositoryProvider).listarEventos(ingresoId);
  }

  Future<List<AttachmentData>> listarComprobantes(String ingresoId) {
    return ref.read(attachmentRepositoryProvider).listarActivosPorIngreso(ingresoId);
  }

  Future<void> abrirArchivo(String path) {
    return ref.read(attachmentStorageProvider).abrir(path);
  }

  Future<RegistrarIngresoManualResultado> registrarManual({
    required int monto,
    required DateTime fecha,
    String? categoriaFinancieraId,
    String? servicioId,
    String? sucursalId,
    String? areaId,
    String? cuentaCaja,
    required String formaPago,
    required String concepto,
    String? observaciones,
  }) async {
    final resultado = await autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'finanzas.crear',
      () => ref.read(registrarIngresoManualUseCaseProvider).ejecutar(
            monto: monto,
            fecha: fecha,
            categoriaFinancieraId: categoriaFinancieraId,
            servicioId: servicioId,
            sucursalId: sucursalId,
            areaId: areaId,
            cuentaCaja: cuentaCaja,
            formaPago: formaPago,
            concepto: concepto,
            observaciones: observaciones,
            actorUsuarioId: _actorUsuarioId,
          ),
      RegistrarIngresoManualErrorInesperado.new,
    );
    if (resultado is RegistrarIngresoManualExitoso) {
      await _cargar();
      ref.invalidate(dashboardControllerProvider);
    }
    return resultado;
  }

  Future<CorregirIngresoResultado> corregir({
    required String ingresoId,
    DateTime? fecha,
    String? categoriaFinancieraId,
    String? servicioId,
    String? sucursalId,
    String? areaId,
    String? cuentaCaja,
    String? formaPago,
    String? concepto,
    String? observaciones,
    required String motivo,
  }) async {
    final resultado = await autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'finanzas.modificar',
      () => ref.read(corregirIngresoUseCaseProvider).ejecutar(
            ingresoId: ingresoId,
            fecha: fecha,
            categoriaFinancieraId: categoriaFinancieraId,
            servicioId: servicioId,
            sucursalId: sucursalId,
            areaId: areaId,
            cuentaCaja: cuentaCaja,
            formaPago: formaPago,
            concepto: concepto,
            observaciones: observaciones,
            motivo: motivo,
            actorUsuarioId: _actorUsuarioId,
          ),
      CorregirIngresoErrorInesperado.new,
    );
    if (resultado is CorregirIngresoExitoso) {
      await _cargar();
      ref.invalidate(dashboardControllerProvider);
    }
    return resultado;
  }

  Future<CancelarIngresoResultado> cancelar({required String ingresoId, required String motivo}) async {
    final resultado = await autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'finanzas.archivar',
      () => ref
          .read(cancelarIngresoUseCaseProvider)
          .ejecutar(ingresoId: ingresoId, motivo: motivo, actorUsuarioId: _actorUsuarioId),
      CancelarIngresoErrorInesperado.new,
    );
    if (resultado is CancelarIngresoExitoso) {
      await _cargar();
      ref.invalidate(dashboardControllerProvider);
    }
    return resultado;
  }

  Future<AdjuntarComprobanteIngresoResultado> adjuntarComprobante({
    required String ingresoId,
    required String sourceFilePath,
    required String originalFileName,
    required String mimeType,
  }) {
    return ref.read(adjuntarComprobanteIngresoUseCaseProvider).ejecutar(
          ingresoId: ingresoId,
          sourceFilePath: sourceFilePath,
          originalFileName: originalFileName,
          mimeType: mimeType,
        );
  }
}
