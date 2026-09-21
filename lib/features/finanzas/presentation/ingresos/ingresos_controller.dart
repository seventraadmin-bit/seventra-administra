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
import '../planeacion/planeacion_financiera_controller.dart';
import '../resumen/resumen_financiero_controller.dart';
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
            rangoInicio: state.rangoInicio,
            rangoFin: state.rangoFin,
          );

      // Folio del Pago de origen por Ingreso automático — una sola
      // consulta en lote, nunca una consulta por fila (Etapa 17).
      final pagos = await ref.read(pagoRepositoryProvider).listar();
      final folioPorPagoId = {for (final p in pagos) p.id: p.folioPago};
      final folioPagoPorIngreso = {
        for (final i in ingresos)
          if (i.pagoId != null && folioPorPagoId.containsKey(i.pagoId)) i.id: folioPorPagoId[i.pagoId]!,
      };

      state = state.copyWith(
        cargando: false,
        ingresos: ingresos,
        folioPagoPorIngreso: folioPagoPorIngreso,
        errorCarga: null,
      );
    } catch (e) {
      state = state.copyWith(cargando: false, errorCarga: e.toString());
    }
  }

  Future<void> reintentarCarga() => _cargar();

  Future<void> aplicarFiltros({
    String? estatus,
    String? servicioId,
    DateTime? rangoInicio,
    DateTime? rangoFin,
    bool limpiarEstatus = false,
    bool limpiarServicioId = false,
    bool limpiarRango = false,
  }) async {
    state = state.copyWith(
      estatus: estatus,
      servicioId: servicioId,
      rangoInicio: rangoInicio,
      rangoFin: rangoFin,
      limpiarEstatus: limpiarEstatus,
      limpiarServicioId: limpiarServicioId,
      limpiarRango: limpiarRango,
    );
    await _cargar();
  }

  /// Origen/Forma de pago (Etapa 17) — filtros en memoria, nunca
  /// recargan desde el repositorio (ver doc de `IngresosState`).
  void aplicarFiltrosLocales({FiltroOrigenIngreso? origen, String? formaPago, bool limpiarFormaPago = false}) {
    state = state.copyWith(origen: origen, formaPago: formaPago, limpiarFormaPago: limpiarFormaPago);
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
    String? cuentaFinancieraId,
    required String formaPago,
    required String concepto,
    String? observaciones,
  }) async {
    final resultado = await autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'ingresos.crear',
      () => ref.read(registrarIngresoManualUseCaseProvider).ejecutar(
            monto: monto,
            fecha: fecha,
            categoriaFinancieraId: categoriaFinancieraId,
            servicioId: servicioId,
            sucursalId: sucursalId,
            areaId: areaId,
            cuentaCaja: cuentaCaja,
            cuentaFinancieraId: cuentaFinancieraId,
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
      ref.invalidate(resumenFinancieroControllerProvider);
      ref.invalidate(planeacionFinancieraControllerProvider);
    }
    return resultado;
  }

  Future<CorregirIngresoResultado> corregir({
    required String ingresoId,
    int? monto,
    DateTime? fecha,
    String? categoriaFinancieraId,
    String? servicioId,
    String? sucursalId,
    String? areaId,
    String? cuentaCaja,
    String? cuentaFinancieraId,
    bool limpiarCuentaFinancieraId = false,
    String? formaPago,
    String? concepto,
    String? observaciones,
    required String motivo,
  }) async {
    final resultado = await autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'ingresos.corregir',
      () => ref.read(corregirIngresoUseCaseProvider).ejecutar(
            ingresoId: ingresoId,
            monto: monto,
            fecha: fecha,
            categoriaFinancieraId: categoriaFinancieraId,
            servicioId: servicioId,
            sucursalId: sucursalId,
            areaId: areaId,
            cuentaCaja: cuentaCaja,
            cuentaFinancieraId: cuentaFinancieraId,
            limpiarCuentaFinancieraId: limpiarCuentaFinancieraId,
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
      ref.invalidate(resumenFinancieroControllerProvider);
      ref.invalidate(planeacionFinancieraControllerProvider);
    }
    return resultado;
  }

  Future<CancelarIngresoResultado> cancelar({required String ingresoId, required String motivo}) async {
    final resultado = await autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'ingresos.cancelar',
      () => ref
          .read(cancelarIngresoUseCaseProvider)
          .ejecutar(ingresoId: ingresoId, motivo: motivo, actorUsuarioId: _actorUsuarioId),
      CancelarIngresoErrorInesperado.new,
    );
    if (resultado is CancelarIngresoExitoso) {
      await _cargar();
      ref.invalidate(dashboardControllerProvider);
      ref.invalidate(resumenFinancieroControllerProvider);
      ref.invalidate(planeacionFinancieraControllerProvider);
    }
    return resultado;
  }

  Future<AdjuntarComprobanteIngresoResultado> adjuntarComprobante({
    required String ingresoId,
    required String sourceFilePath,
    required String originalFileName,
    required String mimeType,
  }) {
    // Etapa 0 (auditoría de consistencia transversal — corrección de un
    // hueco real de autorización): antes llamaba al use case crudo, sin
    // ningún `autorizarUseCase`. Mismo código que corregir.
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'ingresos.corregir',
      () => ref.read(adjuntarComprobanteIngresoUseCaseProvider).ejecutar(
            ingresoId: ingresoId,
            sourceFilePath: sourceFilePath,
            originalFileName: originalFileName,
            mimeType: mimeType,
          ),
      AdjuntarComprobanteIngresoErrorInesperado.new,
    );
  }
}
