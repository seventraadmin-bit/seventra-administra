import 'package:riseg_one/features/notificaciones/presentation/notificaciones_controller.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/dashboard/presentation/dashboard_controller.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/adjuntar_comprobante_pago_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/cancelar_aplicacion_pago_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/cancelar_pago_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/complemento_pago_derivado.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/corregir_pago_usecase.dart';
import 'package:riseg_one/core/permissions/authorization_service.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';
import 'package:riseg_one/features/usuarios/usuarios_providers.dart';

import '../../../organizacion/organizacion_providers.dart';
import '../../finanzas_providers.dart';
import '../cuentas_financieras/cuentas_financieras_controller.dart';
import '../cuentas_por_cobrar/cuentas_por_cobrar_controller.dart';
import '../ingresos/ingresos_controller.dart';
import '../planeacion/planeacion_financiera_controller.dart';
import '../resumen/resumen_financiero_controller.dart';
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
            rangoInicio: state.rangoInicio,
            rangoFin: state.rangoFin,
          );

      // Estado del Complemento por Pago (pedido explícito: mostrarlo en
      // el listado) — tres consultas en lote sobre universos completos
      // (aplicaciones activas, Cuentas por cobrar, Complementos; mismo
      // criterio ya usado por `ResumenFinancieroController`/
      // `ClientesListController`), nunca una consulta por fila.
      final aplicacionesActivas = await ref.read(pagoRepositoryProvider).listarTodasLasAplicacionesActivas();
      final cuentas = await ref.read(cuentaPorCobrarRepositoryProvider).listar();
      final cuentaPorId = {for (final c in cuentas) c.id: c};
      final complementos = await ref.read(complementoPagoRepositoryProvider).listar();
      // Histórico completo por Pago (schemaVersion 79): un Pago puede
      // tener varios Complementos cancelados y a lo más uno vigente. Un
      // mapa de una sola fila se quedaba con una arbitraria.
      final complementosPorPagoId = <String, List<ComplementoPagoData>>{};
      for (final c in complementos) {
        complementosPorPagoId.putIfAbsent(c.pagoId, () => []).add(c);
      }

      final cuentasPorPagoId = <String, List<CuentaPorCobrarData>>{};
      for (final a in aplicacionesActivas) {
        final cuenta = cuentaPorId[a.cuentaPorCobrarId];
        if (cuenta == null) continue;
        cuentasPorPagoId.putIfAbsent(a.pagoId, () => []).add(cuenta);
      }

      final estadoComplementoPorPago = <String, EstadoComplementoPago>{
        for (final p in pagos)
          p.id: () {
            final requiere = pagoRequiereComplemento(cuentasPorPagoId[p.id] ?? const []);
            if (!requiere) return EstadoComplementoPago.noAplica;
            final pendiente = complementoPendiente(
              requiereComplemento: true,
              complementosDelPago: complementosPorPagoId[p.id] ?? const [],
            );
            return pendiente ? EstadoComplementoPago.pendiente : EstadoComplementoPago.realizado;
          }(),
      };

      final nombres = await ref.read(resolverNombresContraparteUseCaseProvider).paraPagos(pagos);
      state = state.copyWith(
        cargando: false,
        pagos: pagos,
        errorCarga: null,
        estadoComplementoPorPago: estadoComplementoPorPago,
        nombres: nombres,
      );
    } catch (e) {
      state = state.copyWith(cargando: false, errorCarga: e.toString());
    }
  }

  Future<void> reintentarCarga() => _cargar();

  Future<void> aplicarFiltros({
    String? clienteId,
    String? formaPago,
    String? estatus,
    DateTime? rangoInicio,
    DateTime? rangoFin,
    bool limpiarClienteId = false,
    bool limpiarFormaPago = false,
    bool limpiarEstatus = false,
    bool limpiarRango = false,
  }) async {
    state = state.copyWith(
      clienteId: clienteId,
      formaPago: formaPago,
      estatus: estatus,
      rangoInicio: rangoInicio,
      rangoFin: rangoFin,
      limpiarClienteId: limpiarClienteId,
      limpiarFormaPago: limpiarFormaPago,
      limpiarEstatus: limpiarEstatus,
      limpiarRango: limpiarRango,
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
    String? cuentaFinancieraId,
    bool limpiarCuentaFinancieraId = false,
    String? observaciones,
    int? montoTotal,
    List<({String cuentaPorCobrarId, int monto})>? nuevaDistribucion,
    required String motivo,
  }) async {
    final resultado = await autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'pagos.corregir',
      () => ref.read(corregirPagoUseCaseProvider).ejecutar(
            pagoId: pagoId,
            fechaPago: fechaPago,
            formaPago: formaPago,
            referencia: referencia,
            bancoOrigen: bancoOrigen,
            cuentaBancariaDestino: cuentaBancariaDestino,
            cuentaFinancieraId: cuentaFinancieraId,
            limpiarCuentaFinancieraId: limpiarCuentaFinancieraId,
            observaciones: observaciones,
            montoTotal: montoTotal,
            nuevaDistribucion: nuevaDistribucion,
            motivo: motivo,
            actorUsuarioId: _actorUsuarioId,
          ),
      CorregirPagoErrorInesperado.new,
    );
    if (resultado is CorregirPagoExitoso) {
      await _cargar();
      // Etapa 6: `corregir()` ahora puede tocar `montoTotal`
      // (Ingreso.monto/Caja y bancos), `cuentaFinancieraId`
      // (Ingreso.cuentaFinancieraId) y la distribución completa de
      // `AplicacionPago` (saldo de cada CxC) — mismos providers ajenos
      // que ya invalida `cancelar()`, nunca solo el propio listado.
      ref.invalidate(cuentasPorCobrarControllerProvider);
      ref.invalidate(dashboardControllerProvider);
      // Mismo motivo que en Cuentas por cobrar: la campana lee pagos
      // recientes y el vencimiento de las CxC afectadas.
      ref.invalidate(notificacionesControllerProvider);
      ref.invalidate(ingresosControllerProvider);
      ref.invalidate(cuentasFinancierasControllerProvider);
      ref.invalidate(resumenFinancieroControllerProvider);
      ref.invalidate(planeacionFinancieraControllerProvider);
    }
    return resultado;
  }

  Future<CancelarPagoResultado> cancelar({required String pagoId, required String motivo}) async {
    final resultado = await autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'pagos.cancelar',
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
      // Mismo motivo que en Cuentas por cobrar: la campana lee pagos
      // recientes y el vencimiento de las CxC afectadas.
      ref.invalidate(notificacionesControllerProvider);
      // Auditoría integral 19A-19D: `PagoRepositoryImpl.cancelar` también
      // cancela el Ingreso automático ligado al Pago en la misma
      // transacción — Ingresos/Cuentas financieras/Resumen/Planeación
      // son providers ajenos que nunca se enteraban de este cambio.
      ref.invalidate(ingresosControllerProvider);
      ref.invalidate(cuentasFinancierasControllerProvider);
      ref.invalidate(resumenFinancieroControllerProvider);
      ref.invalidate(planeacionFinancieraControllerProvider);
    }
    return resultado;
  }

  Future<CancelarAplicacionPagoResultado> cancelarAplicacion({
    required String aplicacionPagoId,
    required String motivo,
  }) async {
    final resultado = await autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'pagos.cancelarAplicacion',
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
      // Mismo motivo que en Cuentas por cobrar: la campana lee pagos
      // recientes y el vencimiento de las CxC afectadas.
      ref.invalidate(notificacionesControllerProvider);
      // Auditoría integral 19A-19D: el mismo `CancelarAplicacionPagoUseCase`
      // invocado desde `CuentaPorCobrarDetalleDialog` sí invalida
      // Resumen/Planeación (cambia el saldo de la CxC) — invocado desde
      // el Pago no los invalidaba, misma acción con comportamiento
      // inconsistente según la pantalla de origen.
      ref.invalidate(resumenFinancieroControllerProvider);
      ref.invalidate(planeacionFinancieraControllerProvider);
    }
    return resultado;
  }

  Future<AdjuntarComprobantePagoResultado> adjuntarComprobante({
    required String pagoId,
    required String sourceFilePath,
    required String originalFileName,
    required String mimeType,
  }) {
    // Etapa 0 (auditoría de consistencia transversal — corrección de un
    // hueco real de autorización): antes llamaba al use case crudo, sin
    // ningún `autorizarUseCase`. Mismo código que corregir.
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'pagos.corregir',
      () => ref.read(adjuntarComprobantePagoUseCaseProvider).ejecutar(
            pagoId: pagoId,
            sourceFilePath: sourceFilePath,
            originalFileName: originalFileName,
            mimeType: mimeType,
          ),
      AdjuntarComprobantePagoErrorInesperado.new,
    );
  }
}
