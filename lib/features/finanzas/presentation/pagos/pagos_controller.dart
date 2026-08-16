import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/dashboard/presentation/dashboard_controller.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/adjuntar_comprobante_pago_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/cancelar_aplicacion_pago_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/cancelar_pago_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/corregir_pago_usecase.dart';
import 'package:riseg_one/core/permissions/authorization_service.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';
import 'package:riseg_one/features/usuarios/usuarios_providers.dart';

import '../../../organizacion/organizacion_providers.dart';
import '../../finanzas_providers.dart';
import '../cuentas_por_cobrar/cuentas_por_cobrar_controller.dart';
import 'pagos_state.dart';

part 'pagos_controller.g.dart';

/// Controlador del listado de Pagos (Etapa 4J.2) — mismo diseño que
/// `CuentasPorCobrarController`.
@riverpod
class PagosController extends _$PagosController {
  @override
  PagosState build() {
    Future.microtask(_cargar);
    return const PagosState();
  }

  /// Usuario autenticado que ejecuta la operación (Etapa 11D) — mismo
  /// criterio que `UsuariosController._actorUsuarioId`.
  String? get _actorUsuarioId => ref.read(sesionControllerProvider)?.usuarioId;

  Future<void> _cargar() async {
    state = state.copyWith(cargando: true, errorCarga: null);
    try {
      final pagos = await ref.read(pagoRepositoryProvider).listar(
            clienteId: state.clienteId,
            formaPago: state.formaPago,
            estatus: state.estatus,
          );
      state = state.copyWith(cargando: false, pagos: pagos, errorCarga: null);
    } catch (e) {
      state = state.copyWith(cargando: false, errorCarga: e.toString());
    }
  }

  Future<void> reintentarCarga() => _cargar();

  Future<void> aplicarFiltros({
    String? clienteId,
    String? formaPago,
    String? estatus,
    bool limpiarClienteId = false,
    bool limpiarFormaPago = false,
    bool limpiarEstatus = false,
  }) async {
    state = state.copyWith(
      clienteId: clienteId,
      formaPago: formaPago,
      estatus: estatus,
      limpiarClienteId: limpiarClienteId,
      limpiarFormaPago: limpiarFormaPago,
      limpiarEstatus: limpiarEstatus,
    );
    await _cargar();
  }

  Future<PagoData?> obtenerPorId(String pagoId) {
    return ref.read(pagoRepositoryProvider).obtenerPorId(pagoId);
  }

  Future<List<AplicacionPagoData>> listarAplicaciones(String pagoId) {
    return ref.read(pagoRepositoryProvider).listarAplicacionesPorPago(pagoId);
  }

  Future<List<PagoEventoData>> listarEventos(String pagoId) {
    return ref.read(pagoRepositoryProvider).listarEventos(pagoId);
  }

  Future<List<AttachmentData>> listarComprobantes(String pagoId) {
    return ref.read(attachmentRepositoryProvider).listarActivosPorPago(pagoId);
  }

  Future<void> abrirArchivo(String path) {
    return ref.read(attachmentStorageProvider).abrir(path);
  }

  Future<CorregirPagoResultado> corregir({
    required String pagoId,
    DateTime? fechaPago,
    String? formaPago,
    String? referencia,
    String? bancoOrigen,
    String? cuentaBancariaDestino,
    String? observaciones,
    required String motivo,
  }) async {
    final resultado = await autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'finanzas.modificar',
      () => ref.read(corregirPagoUseCaseProvider).ejecutar(
            pagoId: pagoId,
            fechaPago: fechaPago,
            formaPago: formaPago,
            referencia: referencia,
            bancoOrigen: bancoOrigen,
            cuentaBancariaDestino: cuentaBancariaDestino,
            observaciones: observaciones,
            motivo: motivo,
            actorUsuarioId: _actorUsuarioId,
          ),
      CorregirPagoErrorInesperado.new,
    );
    if (resultado is CorregirPagoExitoso) {
      await _cargar();
    }
    return resultado;
  }

  Future<CancelarPagoResultado> cancelar({required String pagoId, required String motivo}) async {
    final resultado = await autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'finanzas.archivar',
      () => ref
          .read(cancelarPagoUseCaseProvider)
          .ejecutar(pagoId: pagoId, motivo: motivo, actorUsuarioId: _actorUsuarioId),
      CancelarPagoErrorInesperado.new,
    );
    if (resultado is CancelarPagoExitoso) {
      await _cargar();
      // Cancelar el Pago completo cascada a cancelar todas sus
      // `AplicacionPago` activas y reabre el saldo de cada
      // `CuentaPorCobrar` afectada — `cuentasPorCobrarControllerProvider`
      // es un provider ajeno a Pagos que nunca se enteraba de este
      // cambio (a diferencia de la ruta de cancelación desde el propio
      // diálogo de CxC, que ya invalida correctamente).
      ref.invalidate(cuentasPorCobrarControllerProvider);
      ref.invalidate(dashboardControllerProvider);
    }
    return resultado;
  }

  Future<CancelarAplicacionPagoResultado> cancelarAplicacion({
    required String aplicacionPagoId,
    required String motivo,
  }) async {
    final resultado = await autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'finanzas.archivar',
      () => ref.read(cancelarAplicacionPagoUseCaseProvider).ejecutar(
            aplicacionPagoId: aplicacionPagoId,
            motivo: motivo,
            actorUsuarioId: _actorUsuarioId,
          ),
      CancelarAplicacionPagoErrorInesperado.new,
    );
    if (resultado is CancelarAplicacionPagoExitoso) {
      await _cargar();
      ref.invalidate(cuentasPorCobrarControllerProvider);
      ref.invalidate(dashboardControllerProvider);
    }
    return resultado;
  }

  Future<AdjuntarComprobantePagoResultado> adjuntarComprobante({
    required String pagoId,
    required String sourceFilePath,
    required String originalFileName,
    required String mimeType,
  }) {
    return ref.read(adjuntarComprobantePagoUseCaseProvider).ejecutar(
          pagoId: pagoId,
          sourceFilePath: sourceFilePath,
          originalFileName: originalFileName,
          mimeType: mimeType,
        );
  }
}
