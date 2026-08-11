import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/providers.dart';
import '../../core/permissions/authorization_service.dart';
import '../organizacion/organizacion_providers.dart';
import '../usuarios/presentation/sesion_controller.dart';
import '../usuarios/usuarios_providers.dart';
import 'data/repositories/categoria_financiera_repository_impl.dart';
import 'data/repositories/complemento_pago_repository_impl.dart';
import 'data/repositories/cuenta_por_cobrar_repository_impl.dart';
import 'data/repositories/egreso_repository_impl.dart';
import 'data/repositories/ingreso_repository_impl.dart';
import 'data/repositories/pago_repository_impl.dart';
import 'domain/repositories/categoria_financiera_repository.dart';
import 'domain/repositories/complemento_pago_repository.dart';
import 'domain/repositories/cuenta_por_cobrar_repository.dart';
import 'domain/repositories/egreso_repository.dart';
import 'domain/repositories/ingreso_repository.dart';
import 'domain/repositories/pago_repository.dart';
import 'domain/usecases/actualizar_fecha_vencimiento_cuenta_por_cobrar_usecase.dart';
import 'domain/usecases/adjuntar_archivo_complemento_pago_usecase.dart';
import 'domain/usecases/adjuntar_comprobante_egreso_usecase.dart';
import 'domain/usecases/adjuntar_comprobante_ingreso_usecase.dart';
import 'domain/usecases/adjuntar_comprobante_pago_usecase.dart';
import 'domain/usecases/aplicar_pago_a_cuenta_usecase.dart';
import 'domain/usecases/archivar_categoria_financiera_usecase.dart';
import 'domain/usecases/cancelar_aplicacion_pago_usecase.dart';
import 'domain/usecases/cancelar_complemento_pago_usecase.dart';
import 'domain/usecases/cancelar_egreso_usecase.dart';
import 'domain/usecases/cancelar_ingreso_usecase.dart';
import 'domain/usecases/cancelar_pago_usecase.dart';
import 'domain/usecases/corregir_complemento_pago_usecase.dart';
import 'domain/usecases/corregir_egreso_usecase.dart';
import 'domain/usecases/corregir_ingreso_usecase.dart';
import 'domain/usecases/corregir_pago_usecase.dart';
import 'domain/usecases/crear_categoria_financiera_usecase.dart';
import 'domain/usecases/obtener_resumen_financiero_usecase.dart';
import 'domain/usecases/registrar_complemento_pago_usecase.dart';
import 'domain/usecases/registrar_egreso_usecase.dart';
import 'domain/usecases/registrar_ingreso_manual_usecase.dart';
import 'domain/usecases/registrar_pago_aplicado_usecase.dart';
import 'domain/usecases/registrar_pago_usecase.dart';

/// Providers del dominio Finanzas (Etapa 4J.1) — nace aquí, separado
/// de `organizacion`/`comercial` (Resolución B de Marlon, explícita).
final cuentaPorCobrarRepositoryProvider = Provider<CuentaPorCobrarRepository>((ref) {
  return CuentaPorCobrarRepositoryImpl(ref.watch(appDatabaseProvider));
});

final actualizarFechaVencimientoCuentaPorCobrarUseCaseProvider =
    Provider<ActualizarFechaVencimientoCuentaPorCobrarUseCase>((ref) {
  return ActualizarFechaVencimientoCuentaPorCobrarUseCase(ref.watch(cuentaPorCobrarRepositoryProvider));
});

// --- Etapa 4J.2 — Pagos y aplicación a Cuentas por cobrar ---

final pagoRepositoryProvider = Provider<PagoRepository>((ref) {
  return PagoRepositoryImpl(ref.watch(appDatabaseProvider));
});

final registrarPagoUseCaseProvider = Provider<RegistrarPagoUseCase>((ref) {
  return RegistrarPagoUseCase(
    ref.watch(pagoRepositoryProvider),
    ref.watch(clienteRepositoryProvider),
    ref.watch(generarCodigoUseCaseProvider),
  );
});

final aplicarPagoACuentaUseCaseProvider = Provider<AplicarPagoACuentaUseCase>((ref) {
  return AplicarPagoACuentaUseCase(ref.watch(pagoRepositoryProvider), ref.watch(cuentaPorCobrarRepositoryProvider));
});

final registrarPagoAplicadoUseCaseProvider = Provider<RegistrarPagoAplicadoUseCase>((ref) {
  return RegistrarPagoAplicadoUseCase(
    ref.watch(pagoRepositoryProvider),
    ref.watch(cuentaPorCobrarRepositoryProvider),
    ref.watch(generarCodigoUseCaseProvider),
  );
});

/// Fachada de aplicación autorizada (Etapa 11C) — Cuentas por cobrar no
/// tiene Controller de escritura, así que este es el punto de entrada
/// más bajo y reutilizable para `RegistrarPagoAplicadoUseCase` (mismo
/// criterio que `personal_providers.dart`).
typedef RegistrarPagoAplicadoAutorizado = Future<RegistrarPagoAplicadoResultado> Function({
  required String cuentaPorCobrarId,
  required int monto,
  required DateTime fechaPago,
  required String formaPago,
  String? referencia,
  String? bancoOrigen,
  String? cuentaBancariaDestino,
  String? observaciones,
});

final registrarPagoAplicadoAutorizadoProvider = Provider<RegistrarPagoAplicadoAutorizado>((ref) {
  return ({
    required String cuentaPorCobrarId,
    required int monto,
    required DateTime fechaPago,
    required String formaPago,
    String? referencia,
    String? bancoOrigen,
    String? cuentaBancariaDestino,
    String? observaciones,
  }) {
    final actorUsuarioId = ref.read(sesionControllerProvider)?.usuarioId;
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'finanzas.crear',
      () => ref.read(registrarPagoAplicadoUseCaseProvider).ejecutar(
            cuentaPorCobrarId: cuentaPorCobrarId,
            monto: monto,
            fechaPago: fechaPago,
            formaPago: formaPago,
            referencia: referencia,
            bancoOrigen: bancoOrigen,
            cuentaBancariaDestino: cuentaBancariaDestino,
            observaciones: observaciones,
            actorUsuarioId: actorUsuarioId,
          ),
      RegistrarPagoAplicadoErrorInesperado.new,
    );
  };
});

final corregirPagoUseCaseProvider = Provider<CorregirPagoUseCase>((ref) {
  return CorregirPagoUseCase(ref.watch(pagoRepositoryProvider));
});

final cancelarAplicacionPagoUseCaseProvider = Provider<CancelarAplicacionPagoUseCase>((ref) {
  return CancelarAplicacionPagoUseCase(ref.watch(pagoRepositoryProvider));
});

final cancelarPagoUseCaseProvider = Provider<CancelarPagoUseCase>((ref) {
  return CancelarPagoUseCase(ref.watch(pagoRepositoryProvider));
});

final adjuntarComprobantePagoUseCaseProvider = Provider<AdjuntarComprobantePagoUseCase>((ref) {
  return AdjuntarComprobantePagoUseCase(ref.watch(pagoRepositoryProvider), ref.watch(attachmentStorageProvider));
});

// --- Etapa 4J.3 — Complementos de pago y cierre de cobranza ---

final complementoPagoRepositoryProvider = Provider<ComplementoPagoRepository>((ref) {
  return ComplementoPagoRepositoryImpl(ref.watch(appDatabaseProvider));
});

final registrarComplementoPagoUseCaseProvider = Provider<RegistrarComplementoPagoUseCase>((ref) {
  return RegistrarComplementoPagoUseCase(ref.watch(complementoPagoRepositoryProvider), ref.watch(pagoRepositoryProvider));
});

/// Fachada de aplicación autorizada (Etapa 11C) — mismo criterio que
/// `registrarPagoAplicadoAutorizadoProvider`.
typedef RegistrarComplementoPagoAutorizado = Future<RegistrarComplementoPagoResultado> Function({
  required String pagoId,
  required String uuid,
  String? serieFiscal,
  String? folioFiscal,
  required DateTime fechaTimbrado,
  required int montoTotal,
  String? observaciones,
});

final registrarComplementoPagoAutorizadoProvider = Provider<RegistrarComplementoPagoAutorizado>((ref) {
  return ({
    required String pagoId,
    required String uuid,
    String? serieFiscal,
    String? folioFiscal,
    required DateTime fechaTimbrado,
    required int montoTotal,
    String? observaciones,
  }) {
    final actorUsuarioId = ref.read(sesionControllerProvider)?.usuarioId;
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'finanzas.crear',
      () => ref.read(registrarComplementoPagoUseCaseProvider).ejecutar(
            pagoId: pagoId,
            uuid: uuid,
            serieFiscal: serieFiscal,
            folioFiscal: folioFiscal,
            fechaTimbrado: fechaTimbrado,
            montoTotal: montoTotal,
            observaciones: observaciones,
            actorUsuarioId: actorUsuarioId,
          ),
      RegistrarComplementoPagoErrorInesperado.new,
    );
  };
});

final corregirComplementoPagoUseCaseProvider = Provider<CorregirComplementoPagoUseCase>((ref) {
  return CorregirComplementoPagoUseCase(ref.watch(complementoPagoRepositoryProvider));
});

final cancelarComplementoPagoUseCaseProvider = Provider<CancelarComplementoPagoUseCase>((ref) {
  return CancelarComplementoPagoUseCase(ref.watch(complementoPagoRepositoryProvider));
});

final adjuntarArchivoComplementoPagoUseCaseProvider = Provider<AdjuntarArchivoComplementoPagoUseCase>((ref) {
  return AdjuntarArchivoComplementoPagoUseCase(
    ref.watch(complementoPagoRepositoryProvider),
    ref.watch(attachmentStorageProvider),
  );
});

// --- Etapa 4K.1 — Ingresos y Egresos, fundamentos ---

final categoriaFinancieraRepositoryProvider = Provider<CategoriaFinancieraRepository>((ref) {
  return CategoriaFinancieraRepositoryImpl(ref.watch(appDatabaseProvider));
});

final crearCategoriaFinancieraUseCaseProvider = Provider<CrearCategoriaFinancieraUseCase>((ref) {
  return CrearCategoriaFinancieraUseCase(ref.watch(categoriaFinancieraRepositoryProvider));
});

final archivarCategoriaFinancieraUseCaseProvider = Provider<ArchivarCategoriaFinancieraUseCase>((ref) {
  return ArchivarCategoriaFinancieraUseCase(ref.watch(categoriaFinancieraRepositoryProvider));
});

final ingresoRepositoryProvider = Provider<IngresoRepository>((ref) {
  return IngresoRepositoryImpl(ref.watch(appDatabaseProvider));
});

final registrarIngresoManualUseCaseProvider = Provider<RegistrarIngresoManualUseCase>((ref) {
  return RegistrarIngresoManualUseCase(ref.watch(ingresoRepositoryProvider), ref.watch(generarCodigoUseCaseProvider));
});

final corregirIngresoUseCaseProvider = Provider<CorregirIngresoUseCase>((ref) {
  return CorregirIngresoUseCase(ref.watch(ingresoRepositoryProvider));
});

final cancelarIngresoUseCaseProvider = Provider<CancelarIngresoUseCase>((ref) {
  return CancelarIngresoUseCase(ref.watch(ingresoRepositoryProvider));
});

final adjuntarComprobanteIngresoUseCaseProvider = Provider<AdjuntarComprobanteIngresoUseCase>((ref) {
  return AdjuntarComprobanteIngresoUseCase(ref.watch(ingresoRepositoryProvider), ref.watch(attachmentStorageProvider));
});

final egresoRepositoryProvider = Provider<EgresoRepository>((ref) {
  return EgresoRepositoryImpl(ref.watch(appDatabaseProvider));
});

final registrarEgresoUseCaseProvider = Provider<RegistrarEgresoUseCase>((ref) {
  return RegistrarEgresoUseCase(ref.watch(egresoRepositoryProvider), ref.watch(generarCodigoUseCaseProvider));
});

final corregirEgresoUseCaseProvider = Provider<CorregirEgresoUseCase>((ref) {
  return CorregirEgresoUseCase(ref.watch(egresoRepositoryProvider));
});

final cancelarEgresoUseCaseProvider = Provider<CancelarEgresoUseCase>((ref) {
  return CancelarEgresoUseCase(ref.watch(egresoRepositoryProvider));
});

final adjuntarComprobanteEgresoUseCaseProvider = Provider<AdjuntarComprobanteEgresoUseCase>((ref) {
  return AdjuntarComprobanteEgresoUseCase(ref.watch(egresoRepositoryProvider), ref.watch(attachmentStorageProvider));
});

final obtenerResumenFinancieroUseCaseProvider = Provider<ObtenerResumenFinancieroUseCase>((ref) {
  return ObtenerResumenFinancieroUseCase(ref.watch(ingresoRepositoryProvider), ref.watch(egresoRepositoryProvider));
});
