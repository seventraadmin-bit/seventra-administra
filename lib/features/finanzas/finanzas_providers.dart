import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/app_database.dart';
import '../../core/di/providers.dart';
import '../vehiculos/data/repositories/asignacion_vehiculo_repository_impl.dart';
import '../vehiculos/data/repositories/vehiculo_mantenimiento_repository_impl.dart';
import '../vehiculos/data/repositories/vehiculo_repository_impl.dart';
import '../../core/permissions/authorization_service.dart';
import '../compras/compras_providers.dart' show compraRepositoryProvider;
import '../nomina/nomina_providers.dart';
import '../descuentos_personal/descuentos_personal_providers.dart' show descuentoProgramadoRepositoryProvider;
import '../tiempos_extra/tiempos_extra_providers.dart' show tiempoExtraRepositoryProvider;
import '../organizacion/organizacion_providers.dart';
import '../usuarios/presentation/sesion_controller.dart';
import '../usuarios/usuarios_providers.dart';
import 'data/repositories/categoria_financiera_repository_impl.dart';
import 'data/repositories/complemento_pago_repository_impl.dart';
import 'data/repositories/cuenta_financiera_repository_impl.dart';
import 'data/repositories/cuenta_por_cobrar_repository_impl.dart';
import 'data/repositories/deuda_repository_impl.dart';
import 'data/repositories/egreso_repository_impl.dart';
import 'data/repositories/ingreso_repository_impl.dart';
import 'data/repositories/pago_repository_impl.dart';
import 'domain/repositories/categoria_financiera_repository.dart';
import 'domain/repositories/complemento_pago_repository.dart';
import 'domain/repositories/cuenta_financiera_repository.dart';
import 'domain/repositories/cuenta_por_cobrar_repository.dart';
import 'domain/repositories/deuda_repository.dart';
import 'domain/repositories/egreso_repository.dart';
import 'domain/repositories/ingreso_repository.dart';
import 'domain/repositories/pago_repository.dart';
import 'data/repositories/transferencia_cuenta_repository_impl.dart';
import 'domain/usecases/corregir_origen_financiero_egreso_usecase.dart';
import 'domain/usecases/transferir_entre_cuentas_usecase.dart';
import 'domain/usecases/activar_cuenta_financiera_usecase.dart';
import 'domain/usecases/actualizar_categoria_financiera_usecase.dart';
import 'domain/usecases/adjuntar_archivo_complemento_pago_usecase.dart';
import 'domain/usecases/adjuntar_comprobante_egreso_usecase.dart';
import 'domain/usecases/adjuntar_comprobante_ingreso_usecase.dart';
import 'domain/usecases/adjuntar_comprobante_pago_usecase.dart';
import 'domain/usecases/aplicar_pago_a_cuenta_usecase.dart';
import 'domain/usecases/archivar_categoria_financiera_usecase.dart';
import 'domain/usecases/cancelar_cuenta_por_cobrar_usecase.dart';
import 'domain/usecases/corregir_cuenta_por_cobrar_usecase.dart';
import 'domain/usecases/quitar_reprogramacion_cobro_cuenta_por_cobrar_usecase.dart';
import 'domain/usecases/cancelar_aplicacion_pago_usecase.dart';
import 'domain/usecases/cancelar_complemento_pago_usecase.dart';
import 'domain/usecases/cancelar_deuda_usecase.dart';
import 'domain/usecases/cancelar_egreso_usecase.dart';
import 'domain/usecases/cancelar_ingreso_usecase.dart';
import 'domain/usecases/cancelar_pago_deuda_usecase.dart';
import 'domain/usecases/cancelar_pago_usecase.dart';
import 'domain/usecases/corregir_complemento_pago_usecase.dart';
import 'domain/usecases/corregir_cuenta_financiera_usecase.dart';
import 'domain/usecases/corregir_deuda_usecase.dart';
import 'domain/usecases/corregir_egreso_usecase.dart';
import 'domain/usecases/corregir_ingreso_usecase.dart';
import 'domain/usecases/corregir_pago_deuda_usecase.dart';
import 'domain/usecases/corregir_pago_usecase.dart';
import 'domain/usecases/crear_categoria_financiera_usecase.dart';
import 'domain/usecases/desactivar_cuenta_financiera_usecase.dart';
import 'domain/usecases/eliminar_categoria_financiera_fisicamente_usecase.dart';
import 'domain/usecases/eliminar_cuenta_financiera_fisicamente_usecase.dart';
import 'domain/usecases/eliminar_deuda_fisicamente_usecase.dart';
import 'domain/usecases/eliminar_egreso_fisicamente_usecase.dart';
import 'domain/usecases/eliminar_pago_fisicamente_usecase.dart';
import 'domain/usecases/obtener_flujo_efectivo_usecase.dart';
import 'domain/usecases/obtener_credito_disponible_tarjetas_usecase.dart';
import 'domain/usecases/obtener_origen_automatico_egreso_usecase.dart';
import 'domain/usecases/obtener_posicion_de_caja_usecase.dart';
import 'domain/usecases/obtener_proyeccion_caja_usecase.dart';
import 'domain/usecases/obtener_resumen_financiero_usecase.dart';
import 'domain/usecases/obtener_complementos_pendientes_usecase.dart';
import 'domain/usecases/registrar_complemento_pago_usecase.dart';
import 'domain/usecases/registrar_cuenta_financiera_usecase.dart';
import 'domain/usecases/registrar_deuda_usecase.dart';
import 'domain/usecases/registrar_egreso_usecase.dart';
import 'domain/usecases/registrar_ingreso_manual_usecase.dart';
import 'domain/usecases/registrar_pago_aplicado_usecase.dart';
import 'domain/usecases/resolver_nombres_contraparte_usecase.dart';
import 'domain/usecases/registrar_pago_deuda_usecase.dart';
import 'domain/usecases/registrar_pago_usecase.dart';
import 'domain/usecases/reprogramar_cobro_cuenta_por_cobrar_usecase.dart';
import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/features/inventario/data/repositories/asignacion_repository_impl.dart';
import 'package:riseg_one/features/servicios_eventuales/data/repositories/servicio_eventual_repository_impl.dart';
import 'package:riseg_one/features/servicios_eventuales/domain/repositories/servicio_eventual_repository.dart';
import 'package:riseg_one/features/telefonia/data/repositories/asignacion_linea_telefonica_repository_impl.dart';
import 'package:riseg_one/features/telefonia/data/repositories/linea_telefonica_equipo_repository_impl.dart';
import 'package:riseg_one/features/telefonia/data/repositories/linea_telefonica_repository_impl.dart';
import 'package:riseg_one/features/telefonia/data/repositories/recarga_linea_telefonica_repository_impl.dart';

/// Providers del dominio Finanzas (Etapa 4J.1) — nace aquí, separado
/// de `organizacion`/`comercial` (Resolución B de Marlon, explícita).
final cuentaPorCobrarRepositoryProvider = Provider<CuentaPorCobrarRepository>((ref) {
  return CuentaPorCobrarRepositoryImpl(ref.watch(appDatabaseProvider));
});

final corregirCuentaPorCobrarUseCaseProvider = Provider<CorregirCuentaPorCobrarUseCase>((ref) {
  return CorregirCuentaPorCobrarUseCase(ref.watch(cuentaPorCobrarRepositoryProvider));
});

final reprogramarCobroCuentaPorCobrarUseCaseProvider = Provider<ReprogramarCobroCuentaPorCobrarUseCase>((ref) {
  return ReprogramarCobroCuentaPorCobrarUseCase(ref.watch(cuentaPorCobrarRepositoryProvider));
});

final quitarReprogramacionCobroCuentaPorCobrarUseCaseProvider =
    Provider<QuitarReprogramacionCobroCuentaPorCobrarUseCase>((ref) {
  return QuitarReprogramacionCobroCuentaPorCobrarUseCase(ref.watch(cuentaPorCobrarRepositoryProvider));
});

final cancelarCuentaPorCobrarUseCaseProvider = Provider<CancelarCuentaPorCobrarUseCase>((ref) {
  return CancelarCuentaPorCobrarUseCase(
    ref.watch(cuentaPorCobrarRepositoryProvider),
    ref.watch(pagoRepositoryProvider),
  );
});

// Auditoría integral 19A-19D: `CuentasPorCobrarController` llamaba estos
// use cases directamente, sin ningún wrapper de `autorizarUseCase` —
// a diferencia de cualquier otra escritura financiera del módulo.
// Cualquier usuario con acceso a la pantalla podía corregir la fecha
// contractual o reprogramar un cobro sin verificación de permiso.
//
// Etapa 7: `cuentaPorCobrar.corregirFecha` evoluciona a
// `cuentaPorCobrar.corregir` (ahora cubre también `observaciones`,
// nunca solo la fecha) — migrado de forma aditiva/idempotente (v74,
// ver `migrar_correccion_cuenta_por_cobrar_v74.dart`).
typedef CorregirCuentaPorCobrarAutorizado = Future<CorregirCuentaPorCobrarResultado> Function({
  required String cuentaPorCobrarId,
  DateTime? fechaVencimiento,
  bool limpiarFechaVencimiento,
  String? observaciones,
  bool limpiarObservaciones,
  required String motivo,
});

final corregirCuentaPorCobrarAutorizadoProvider = Provider<CorregirCuentaPorCobrarAutorizado>((ref) {
  return ({
    required String cuentaPorCobrarId,
    DateTime? fechaVencimiento,
    bool limpiarFechaVencimiento = false,
    String? observaciones,
    bool limpiarObservaciones = false,
    required String motivo,
  }) {
    final actorUsuarioId = ref.read(sesionControllerProvider)?.usuarioId;
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'cuentaPorCobrar.corregir',
      () => ref.read(corregirCuentaPorCobrarUseCaseProvider).ejecutar(
            cuentaPorCobrarId: cuentaPorCobrarId,
            fechaVencimiento: fechaVencimiento,
            limpiarFechaVencimiento: limpiarFechaVencimiento,
            observaciones: observaciones,
            limpiarObservaciones: limpiarObservaciones,
            motivo: motivo,
            actorUsuarioId: actorUsuarioId,
          ),
      CorregirCuentaPorCobrarErrorInesperado.new,
    );
  };
});

typedef ReprogramarCobroCuentaPorCobrarAutorizado = Future<ReprogramarCobroCuentaPorCobrarResultado> Function({
  required String cuentaPorCobrarId,
  required DateTime? fechaCobroReprogramada,
  required String motivo,
});

final reprogramarCobroCuentaPorCobrarAutorizadoProvider = Provider<ReprogramarCobroCuentaPorCobrarAutorizado>((ref) {
  return ({required String cuentaPorCobrarId, required DateTime? fechaCobroReprogramada, required String motivo}) {
    final actorUsuarioId = ref.read(sesionControllerProvider)?.usuarioId;
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'cuentaPorCobrar.reprogramarCobro',
      () => ref.read(reprogramarCobroCuentaPorCobrarUseCaseProvider).ejecutar(
            cuentaPorCobrarId: cuentaPorCobrarId,
            fechaCobroReprogramada: fechaCobroReprogramada,
            motivo: motivo,
            actorUsuarioId: actorUsuarioId,
          ),
      ReprogramarCobroCuentaPorCobrarErrorInesperado.new,
    );
  };
});

// Misma facultad que reprogramar (decisión de cobranza), acción
// inversa — nunca un permiso nuevo.
typedef QuitarReprogramacionCobroCuentaPorCobrarAutorizado = Future<QuitarReprogramacionCobroCuentaPorCobrarResultado>
    Function({required String cuentaPorCobrarId, required String motivo});

final quitarReprogramacionCobroCuentaPorCobrarAutorizadoProvider =
    Provider<QuitarReprogramacionCobroCuentaPorCobrarAutorizado>((ref) {
  return ({required String cuentaPorCobrarId, required String motivo}) {
    final actorUsuarioId = ref.read(sesionControllerProvider)?.usuarioId;
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'cuentaPorCobrar.reprogramarCobro',
      () => ref.read(quitarReprogramacionCobroCuentaPorCobrarUseCaseProvider).ejecutar(
            cuentaPorCobrarId: cuentaPorCobrarId,
            motivo: motivo,
            actorUsuarioId: actorUsuarioId,
          ),
      QuitarReprogramacionCobroCuentaPorCobrarErrorInesperado.new,
    );
  };
});

typedef CancelarCuentaPorCobrarAutorizado = Future<CancelarCuentaPorCobrarResultado> Function({
  required String cuentaPorCobrarId,
  required String motivo,
});

final cancelarCuentaPorCobrarAutorizadoProvider = Provider<CancelarCuentaPorCobrarAutorizado>((ref) {
  return ({required String cuentaPorCobrarId, required String motivo}) {
    final actorUsuarioId = ref.read(sesionControllerProvider)?.usuarioId;
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'cuentaPorCobrar.cancelar',
      () => ref.read(cancelarCuentaPorCobrarUseCaseProvider).ejecutar(
            cuentaPorCobrarId: cuentaPorCobrarId,
            motivo: motivo,
            actorUsuarioId: actorUsuarioId,
          ),
      CancelarCuentaPorCobrarErrorInesperado.new,
    );
  };
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
  String? cuentaFinancieraId,
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
    String? cuentaFinancieraId,
    String? observaciones,
  }) {
    final actorUsuarioId = ref.read(sesionControllerProvider)?.usuarioId;
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'pagos.registrar',
      () => ref.read(registrarPagoAplicadoUseCaseProvider).ejecutar(
            cuentaPorCobrarId: cuentaPorCobrarId,
            monto: monto,
            fechaPago: fechaPago,
            formaPago: formaPago,
            referencia: referencia,
            bancoOrigen: bancoOrigen,
            cuentaBancariaDestino: cuentaBancariaDestino,
            cuentaFinancieraId: cuentaFinancieraId,
            observaciones: observaciones,
            actorUsuarioId: actorUsuarioId,
          ),
      RegistrarPagoAplicadoErrorInesperado.new,
    );
  };
});

final corregirPagoUseCaseProvider = Provider<CorregirPagoUseCase>((ref) {
  return CorregirPagoUseCase(
    ref.watch(pagoRepositoryProvider),
    ref.watch(cuentaPorCobrarRepositoryProvider),
    ref.watch(complementoPagoRepositoryProvider),
  );
});

final cancelarAplicacionPagoUseCaseProvider = Provider<CancelarAplicacionPagoUseCase>((ref) {
  return CancelarAplicacionPagoUseCase(ref.watch(pagoRepositoryProvider));
});

final cancelarPagoUseCaseProvider = Provider<CancelarPagoUseCase>((ref) {
  return CancelarPagoUseCase(ref.watch(pagoRepositoryProvider), ref.watch(complementoPagoRepositoryProvider));
});

// Contingencia del Maestro: corregir de qué cuenta salió un Egreso ya
// registrado. Misma frontera que las eliminaciones físicas
// (`exigirMaestro`, nunca un permiso dinámico) porque mueve saldos de
// un movimiento que otro módulo generó.
final corregirOrigenFinancieroEgresoUseCaseProvider =
    Provider<CorregirOrigenFinancieroEgresoUseCase>((ref) {
  return CorregirOrigenFinancieroEgresoUseCase(
    ref.watch(egresoRepositoryProvider),
    ref.watch(cuentaFinancieraRepositoryProvider),
    ref.watch(obtenerOrigenAutomaticoEgresoUseCaseProvider),
  );
});

typedef CorregirOrigenFinancieroEgresoAutorizado
    = Future<CorregirOrigenFinancieroEgresoResultado> Function({
  required String egresoId,
  required String? cuentaFinancieraId,
  required String motivo,
});

final corregirOrigenFinancieroEgresoAutorizadoProvider =
    Provider<CorregirOrigenFinancieroEgresoAutorizado>((ref) {
  return ({required String egresoId, required String? cuentaFinancieraId, required String motivo}) {
    return exigirMaestro(
      ref.read(permissionServiceProvider),
      () => ref.read(corregirOrigenFinancieroEgresoUseCaseProvider).ejecutar(
            egresoId: egresoId,
            cuentaFinancieraId: cuentaFinancieraId,
            motivo: motivo,
            actorUsuarioId: ref.read(sesionControllerProvider)?.usuarioId,
          ),
      CorregirOrigenFinancieroEgresoErrorInesperado.new,
    );
  };
});

final adjuntarComprobantePagoUseCaseProvider = Provider<AdjuntarComprobantePagoUseCase>((ref) {
  return AdjuntarComprobantePagoUseCase(ref.watch(pagoRepositoryProvider), ref.watch(attachmentStorageProvider));
});

// Eliminación física extraordinaria (Etapa 15) — facultad exclusiva del
// Usuario Maestro, mismo patrón exacto que Cliente/Servicio/Documento
// por emitir/Egreso/Compra (`exigirMaestro`, nunca
// `AuthorizationService.verificar`).
final eliminarPagoFisicamenteUseCaseProvider = Provider<EliminarPagoFisicamenteUseCase>((ref) {
  return EliminarPagoFisicamenteUseCase(ref.watch(pagoRepositoryProvider));
});

typedef EliminarPagoFisicamenteAutorizado = Future<EliminarPagoFisicamenteResultado> Function({
  required String pagoId,
  required String motivo,
});

final eliminarPagoFisicamenteAutorizadoProvider = Provider<EliminarPagoFisicamenteAutorizado>((ref) {
  return ({required String pagoId, required String motivo}) {
    return exigirMaestro(
      ref.read(permissionServiceProvider),
      () => ref.read(eliminarPagoFisicamenteUseCaseProvider).ejecutar(
            pagoId: pagoId,
            motivo: motivo,
            actorUsuarioId: ref.read(sesionControllerProvider)?.usuarioId,
          ),
      EliminarPagoFisicamenteErrorInesperado.new,
    );
  };
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
      'pagos.registrar',
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

final obtenerComplementosPendientesUseCaseProvider = Provider<ObtenerComplementosPendientesUseCase>((ref) {
  return ObtenerComplementosPendientesUseCase(
    ref.watch(pagoRepositoryProvider),
    ref.watch(cuentaPorCobrarRepositoryProvider),
    ref.watch(complementoPagoRepositoryProvider),
  );
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

final actualizarCategoriaFinancieraUseCaseProvider = Provider<ActualizarCategoriaFinancieraUseCase>((ref) {
  return ActualizarCategoriaFinancieraUseCase(ref.watch(categoriaFinancieraRepositoryProvider));
});

// Etapa 0 (auditoría de consistencia transversal — corrección de un
// hueco real de autorización): estas 3 operaciones se invocaban desde
// la pantalla directo sobre el use case crudo, sin ningún
// `autorizarUseCase` en toda la cadena. Mismos códigos ya usados para
// el resto de Finanzas (Egreso/Ingreso/Deuda/etc. dentro del mismo
// módulo) — nunca un código nuevo.
typedef CrearCategoriaFinancieraAutorizado = Future<CrearCategoriaFinancieraResultado> Function({
  required String codigo,
  required String nombre,
  required String tipo,
  required String tipoMovimiento,
});

final crearCategoriaFinancieraAutorizadoProvider = Provider<CrearCategoriaFinancieraAutorizado>((ref) {
  return ({required String codigo, required String nombre, required String tipo, required String tipoMovimiento}) {
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'categoriasFinancieras.crear',
      () => ref.read(crearCategoriaFinancieraUseCaseProvider).ejecutar(
            codigo: codigo,
            nombre: nombre,
            tipo: tipo,
            tipoMovimiento: tipoMovimiento,
          ),
      CrearCategoriaFinancieraErrorInesperado.new,
    );
  };
});

typedef ActualizarCategoriaFinancieraAutorizado = Future<ActualizarCategoriaFinancieraResultado> Function({
  required String id,
  required String codigo,
  required String nombre,
  required String tipo,
  required String tipoMovimiento,
});

final actualizarCategoriaFinancieraAutorizadoProvider = Provider<ActualizarCategoriaFinancieraAutorizado>((ref) {
  return ({required String id, required String codigo, required String nombre, required String tipo, required String tipoMovimiento}) {
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'categoriasFinancieras.corregir',
      () => ref.read(actualizarCategoriaFinancieraUseCaseProvider).ejecutar(
            id: id,
            codigo: codigo,
            nombre: nombre,
            tipo: tipo,
            tipoMovimiento: tipoMovimiento,
          ),
      ActualizarCategoriaFinancieraErrorInesperado.new,
    );
  };
});

typedef ArchivarCategoriaFinancieraAutorizado = Future<ArchivarCategoriaFinancieraResultado> Function(String categoriaId);

final archivarCategoriaFinancieraAutorizadoProvider = Provider<ArchivarCategoriaFinancieraAutorizado>((ref) {
  return (String categoriaId) {
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'categoriasFinancieras.archivar',
      () => ref.read(archivarCategoriaFinancieraUseCaseProvider).ejecutar(categoriaId),
      ArchivarCategoriaFinancieraErrorInesperado.new,
    );
  };
});

// Eliminación física extraordinaria (Etapa 18) — facultad exclusiva del
// Usuario Maestro, mismo patrón exacto que Egreso/Pago arriba
// (`exigirMaestro`, nunca `AuthorizationService.verificar`). Solo
// elegible si ningún Ingreso/Egreso real referencia la categoría.
final eliminarCategoriaFinancieraFisicamenteUseCaseProvider =
    Provider<EliminarCategoriaFinancieraFisicamenteUseCase>((ref) {
  return EliminarCategoriaFinancieraFisicamenteUseCase(ref.watch(categoriaFinancieraRepositoryProvider));
});

typedef EliminarCategoriaFinancieraFisicamenteAutorizado = Future<EliminarCategoriaFinancieraFisicamenteResultado>
    Function({required String categoriaFinancieraId, required String motivo});

final eliminarCategoriaFinancieraFisicamenteAutorizadoProvider =
    Provider<EliminarCategoriaFinancieraFisicamenteAutorizado>((ref) {
  return ({required String categoriaFinancieraId, required String motivo}) {
    return exigirMaestro(
      ref.read(permissionServiceProvider),
      () => ref.read(eliminarCategoriaFinancieraFisicamenteUseCaseProvider).ejecutar(
            categoriaFinancieraId: categoriaFinancieraId,
            motivo: motivo,
            actorUsuarioId: ref.read(sesionControllerProvider)?.usuarioId,
          ),
      EliminarCategoriaFinancieraFisicamenteErrorInesperado.new,
    );
  };
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

// NO leer `deudaRepositoryProvider` aquí, en ninguna forma —ni siquiera
// diferida dentro de un callback—: `deudaRepositoryProvider` ya depende
// de este provider, y cualquier lectura en sentido contrario cierra el
// ciclo en el grafo de Riverpod (`CircularDependencyError` en tiempo de
// ejecución, bug real del caso EGR-000035). `EgresoRepositoryImpl`
// compone internamente su propio `DeudaRepositoryImpl` sobre la misma
// `AppDatabase` — ver el doc comment de su campo `_deudaRepository`.
final egresoRepositoryProvider = Provider<EgresoRepository>((ref) {
  return EgresoRepositoryImpl(ref.watch(appDatabaseProvider));
});

final registrarEgresoUseCaseProvider = Provider<RegistrarEgresoUseCase>((ref) {
  return RegistrarEgresoUseCase(
    ref.watch(egresoRepositoryProvider),
    ref.watch(generarCodigoUseCaseProvider),
    ref.watch(deudaRepositoryProvider),
  );
});

// Fuente única de "¿este Egreso es automático, y de dónde?" — la usan
// CorregirEgresoUseCase/CancelarEgresoUseCase (bloqueo) y la UI ("Ver
// origen"), nunca dos lógicas de clasificación distintas para el mismo
// Egreso puntual (para el desglose EN LOTE de Reportes, ver
// `clasificarEgresosPorOrigenUseCaseProvider`, que resuelve el mismo
// origen sin N+1 para un rango completo).
final obtenerOrigenAutomaticoEgresoUseCaseProvider = Provider<ObtenerOrigenAutomaticoEgresoUseCase>((ref) {
  return ObtenerOrigenAutomaticoEgresoUseCase(
    ref.watch(compraRepositoryProvider),
    ref.watch(pagoNominaRepositoryProvider),
    ref.watch(tiempoExtraRepositoryProvider),
    ref.watch(deudaRepositoryProvider),
    ref.watch(descuentoProgramadoRepositoryProvider),
    // schemaVersion 80 — Vehículos también genera Egresos automáticos.
    // Se construyen directo (no vía `vehiculos_providers`) para no
    // invertir la dirección de dependencia: Vehículos ya depende de
    // Finanzas, y un `watch` de vuelta cerraría el ciclo.
    VehiculoMantenimientoRepositoryImpl(ref.watch(appDatabaseProvider)),
    VehiculoRepositoryImpl(
      ref.watch(appDatabaseProvider),
      AsignacionVehiculoRepositoryImpl(ref.watch(appDatabaseProvider)),
    ),
    // Telefonía (Rebanada 1) — mismo criterio y misma razón que
    // Vehículos: se construyen directo para no invertir la dirección de
    // dependencia.
    RecargaLineaTelefonicaRepositoryImpl(
      ref.watch(appDatabaseProvider),
      ref.watch(egresoRepositoryProvider),
      ref.watch(deudaRepositoryProvider),
      CodigoSecuenciaService(ref.watch(appDatabaseProvider)),
    ),
    LineaTelefonicaRepositoryImpl(
      ref.watch(appDatabaseProvider),
      AsignacionLineaTelefonicaRepositoryImpl(ref.watch(appDatabaseProvider)),
      LineaTelefonicaEquipoRepositoryImpl(
        ref.watch(appDatabaseProvider),
        AsignacionLineaTelefonicaRepositoryImpl(ref.watch(appDatabaseProvider)),
        AsignacionRepositoryImpl(ref.watch(appDatabaseProvider)),
      ),
    ),
    // Servicios Eventuales (schemaVersion 87) — misma razón y mismo
    // criterio que Vehículos y Telefonía: se construye directo para no
    // invertir la dirección de dependencia (el dominio ya depende de
    // Finanzas, y un `watch` de vuelta cerraría el ciclo).
    ref.watch(servicioEventualRepositoryParaFinanzasProvider),
  );
});

/// El repositorio de Servicios Eventuales visto DESDE Finanzas.
///
/// Se construye directo, sin `servicios_eventuales_providers`, por la
/// misma razón que Vehículos y Telefonía: ese archivo ya depende de
/// éste, y un `watch` de vuelta cerraría el ciclo.
final servicioEventualRepositoryParaFinanzasProvider = Provider<ServicioEventualRepository>((ref) {
  return ServicioEventualRepositoryImpl(
    ref.watch(appDatabaseProvider),
    ref.watch(egresoRepositoryProvider),
    ref.watch(deudaRepositoryProvider),
    CodigoSecuenciaService(ref.watch(appDatabaseProvider)),
    ref.watch(cuentaPorCobrarRepositoryProvider),
    ref.watch(pagoRepositoryProvider),
  );
});

/// Fuente única del nombre de una contraparte de cobranza — Cliente o
/// Servicio Eventual (schemaVersion 88). Ninguna pantalla resuelve
/// nombres por su cuenta.
final resolverNombresContraparteUseCaseProvider = Provider<ResolverNombresContraparteUseCase>((ref) {
  return ResolverNombresContraparteUseCase(
    ref.watch(clienteRepositoryProvider),
    ref.watch(servicioEventualRepositoryParaFinanzasProvider),
  );
});

final corregirEgresoUseCaseProvider = Provider<CorregirEgresoUseCase>((ref) {
  return CorregirEgresoUseCase(
    ref.watch(egresoRepositoryProvider),
    ref.watch(obtenerOrigenAutomaticoEgresoUseCaseProvider),
    ref.watch(deudaRepositoryProvider),
  );
});

final cancelarEgresoUseCaseProvider = Provider<CancelarEgresoUseCase>((ref) {
  return CancelarEgresoUseCase(ref.watch(egresoRepositoryProvider), ref.watch(obtenerOrigenAutomaticoEgresoUseCaseProvider));
});

final adjuntarComprobanteEgresoUseCaseProvider = Provider<AdjuntarComprobanteEgresoUseCase>((ref) {
  return AdjuntarComprobanteEgresoUseCase(ref.watch(egresoRepositoryProvider), ref.watch(attachmentStorageProvider));
});

final obtenerResumenFinancieroUseCaseProvider = Provider<ObtenerResumenFinancieroUseCase>((ref) {
  return ObtenerResumenFinancieroUseCase(
    ref.watch(ingresoRepositoryProvider),
    ref.watch(egresoRepositoryProvider),
    ref.watch(compraRepositoryProvider),
  );
});

// Eliminación física extraordinaria (Etapa 15) — facultad exclusiva del
// Usuario Maestro, mismo patrón exacto que Cliente/Servicio/Documento
// por emitir (`exigirMaestro`, nunca `AuthorizationService.verificar`).
final eliminarEgresoFisicamenteUseCaseProvider = Provider<EliminarEgresoFisicamenteUseCase>((ref) {
  return EliminarEgresoFisicamenteUseCase(ref.watch(egresoRepositoryProvider));
});

typedef EliminarEgresoFisicamenteAutorizado = Future<EliminarEgresoFisicamenteResultado> Function({
  required String egresoId,
  required String motivo,
});

final eliminarEgresoFisicamenteAutorizadoProvider = Provider<EliminarEgresoFisicamenteAutorizado>((ref) {
  return ({required String egresoId, required String motivo}) {
    return exigirMaestro(
      ref.read(permissionServiceProvider),
      () => ref.read(eliminarEgresoFisicamenteUseCaseProvider).ejecutar(
            egresoId: egresoId,
            motivo: motivo,
            actorUsuarioId: ref.read(sesionControllerProvider)?.usuarioId,
          ),
      EliminarEgresoFisicamenteErrorInesperado.new,
    );
  };
});

// --- Etapa 19 — Deudas y crédito empresarial ---

final deudaRepositoryProvider = Provider<DeudaRepository>((ref) {
  return DeudaRepositoryImpl(ref.watch(appDatabaseProvider), ref.watch(egresoRepositoryProvider));
});

final registrarDeudaUseCaseProvider = Provider<RegistrarDeudaUseCase>((ref) {
  return RegistrarDeudaUseCase(ref.watch(deudaRepositoryProvider), ref.watch(generarCodigoUseCaseProvider));
});

final registrarPagoDeudaUseCaseProvider = Provider<RegistrarPagoDeudaUseCase>((ref) {
  return RegistrarPagoDeudaUseCase(ref.watch(deudaRepositoryProvider), ref.watch(generarCodigoUseCaseProvider));
});

final corregirDeudaUseCaseProvider = Provider<CorregirDeudaUseCase>((ref) {
  return CorregirDeudaUseCase(ref.watch(deudaRepositoryProvider));
});

final cancelarDeudaUseCaseProvider = Provider<CancelarDeudaUseCase>((ref) {
  return CancelarDeudaUseCase(ref.watch(deudaRepositoryProvider));
});

// Eliminación física extraordinaria — facultad exclusiva del Usuario
// Maestro, mismo patrón exacto que Egreso/Compra (`exigirMaestro`).
final eliminarDeudaFisicamenteUseCaseProvider = Provider<EliminarDeudaFisicamenteUseCase>((ref) {
  return EliminarDeudaFisicamenteUseCase(ref.watch(deudaRepositoryProvider));
});

/// Reutiliza `finanzas.crear` — "registrar deuda" y "registrar pago"
/// comparten el mismo código (decisión confirmada), igual que Cuentas
/// por cobrar hoy.
typedef RegistrarDeudaAutorizado = Future<RegistrarDeudaResultado> Function({
  required String nombre,
  required String tipo,
  String? acreedor,
  DateTime? fechaOrigen,
  int? importeOriginal,
  required int saldoInicial,
  DateTime? fechaSaldoInicial,
  DateTime? fechaVencimiento,
  int? pagoProgramado,
  String? periodicidad,
  double? tasaInteres,
  String? referencia,
  String? observaciones,
  String? tarjetaUltimosDigitos,
  int? tarjetaLimiteCredito,
  int? tarjetaDiaCorte,
  int? tarjetaDiaPago,
  int? tarjetaPagoMinimo,
  String? tarjetaReglaFechaPago,
  int? tarjetaDiasDespuesCorte,
  String? tarjetaTipoTasa,
  String? tarjetaTasaReferencia,
  double? tarjetaTasaDiferencial,
  bool? tarjetaTasaMasIva,
  String? tarjetaTasaDescripcion,
  double? tarjetaCat,
  bool? tarjetaCatIncluyeIva,
  DateTime? tarjetaVencimientoCubiertoHasta,
});

final registrarDeudaAutorizadoProvider = Provider<RegistrarDeudaAutorizado>((ref) {
  return ({
    required String nombre,
    required String tipo,
    String? acreedor,
    DateTime? fechaOrigen,
    int? importeOriginal,
    required int saldoInicial,
    DateTime? fechaSaldoInicial,
    DateTime? fechaVencimiento,
    int? pagoProgramado,
    String? periodicidad,
    double? tasaInteres,
    String? referencia,
    String? observaciones,
    String? tarjetaUltimosDigitos,
    int? tarjetaLimiteCredito,
    int? tarjetaDiaCorte,
    int? tarjetaDiaPago,
    int? tarjetaPagoMinimo,
    String? tarjetaReglaFechaPago,
    int? tarjetaDiasDespuesCorte,
    String? tarjetaTipoTasa,
    String? tarjetaTasaReferencia,
    double? tarjetaTasaDiferencial,
    bool? tarjetaTasaMasIva,
    String? tarjetaTasaDescripcion,
    double? tarjetaCat,
    bool? tarjetaCatIncluyeIva,
    DateTime? tarjetaVencimientoCubiertoHasta,
  }) {
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'deudas.crear',
      () => ref.read(registrarDeudaUseCaseProvider).ejecutar(
            nombre: nombre,
            tipo: tipo,
            acreedor: acreedor,
            fechaOrigen: fechaOrigen,
            importeOriginal: importeOriginal,
            saldoInicial: saldoInicial,
            fechaSaldoInicial: fechaSaldoInicial,
            fechaVencimiento: fechaVencimiento,
            pagoProgramado: pagoProgramado,
            periodicidad: periodicidad,
            tasaInteres: tasaInteres,
            referencia: referencia,
            observaciones: observaciones,
            tarjetaUltimosDigitos: tarjetaUltimosDigitos,
            tarjetaLimiteCredito: tarjetaLimiteCredito,
            tarjetaDiaCorte: tarjetaDiaCorte,
            tarjetaDiaPago: tarjetaDiaPago,
            tarjetaPagoMinimo: tarjetaPagoMinimo,
            tarjetaReglaFechaPago: tarjetaReglaFechaPago,
            tarjetaDiasDespuesCorte: tarjetaDiasDespuesCorte,
            tarjetaTipoTasa: tarjetaTipoTasa,
            tarjetaTasaReferencia: tarjetaTasaReferencia,
            tarjetaTasaDiferencial: tarjetaTasaDiferencial,
            tarjetaTasaMasIva: tarjetaTasaMasIva,
            tarjetaTasaDescripcion: tarjetaTasaDescripcion,
            tarjetaCat: tarjetaCat,
            tarjetaCatIncluyeIva: tarjetaCatIncluyeIva,
            tarjetaVencimientoCubiertoHasta: tarjetaVencimientoCubiertoHasta,
            actorUsuarioId: ref.read(sesionControllerProvider)?.usuarioId,
          ),
      RegistrarDeudaErrorInesperado.new,
    );
  };
});

typedef RegistrarPagoDeudaAutorizado = Future<RegistrarPagoDeudaResultado> Function({
  required String deudaId,
  required DateTime fecha,
  required int importe,
  required String formaPago,
  String? cuentaCaja,
  String? cuentaFinancieraId,
  String? referencia,
  String? observaciones,
});

final registrarPagoDeudaAutorizadoProvider = Provider<RegistrarPagoDeudaAutorizado>((ref) {
  return ({
    required String deudaId,
    required DateTime fecha,
    required int importe,
    required String formaPago,
    String? cuentaCaja,
    String? cuentaFinancieraId,
    String? referencia,
    String? observaciones,
  }) {
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'deudas.registrarPago',
      () => ref.read(registrarPagoDeudaUseCaseProvider).ejecutar(
            deudaId: deudaId,
            fecha: fecha,
            importe: importe,
            formaPago: formaPago,
            cuentaCaja: cuentaCaja,
            cuentaFinancieraId: cuentaFinancieraId,
            referencia: referencia,
            observaciones: observaciones,
            actorUsuarioId: ref.read(sesionControllerProvider)?.usuarioId,
          ),
      RegistrarPagoDeudaErrorInesperado.new,
    );
  };
});

// --- Etapa 9 — corrección y cancelación individual de pagos ---

final corregirPagoDeudaUseCaseProvider = Provider<CorregirPagoDeudaUseCase>((ref) {
  return CorregirPagoDeudaUseCase(ref.watch(deudaRepositoryProvider));
});

final cancelarPagoDeudaUseCaseProvider = Provider<CancelarPagoDeudaUseCase>((ref) {
  return CancelarPagoDeudaUseCase(ref.watch(deudaRepositoryProvider));
});

typedef CorregirPagoDeudaAutorizado = Future<CorregirPagoDeudaResultado> Function({
  required int pagoId,
  int? nuevoImporte,
  String? nuevaCuentaFinancieraId,
  bool limpiarCuentaFinanciera,
  required String motivo,
});

final corregirPagoDeudaAutorizadoProvider = Provider<CorregirPagoDeudaAutorizado>((ref) {
  return ({
    required int pagoId,
    int? nuevoImporte,
    String? nuevaCuentaFinancieraId,
    bool limpiarCuentaFinanciera = false,
    required String motivo,
  }) {
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'deudas.corregirPago',
      () => ref.read(corregirPagoDeudaUseCaseProvider).ejecutar(
            pagoId: pagoId,
            nuevoImporte: nuevoImporte,
            nuevaCuentaFinancieraId: nuevaCuentaFinancieraId,
            limpiarCuentaFinanciera: limpiarCuentaFinanciera,
            motivo: motivo,
            actorUsuarioId: ref.read(sesionControllerProvider)?.usuarioId,
          ),
      CorregirPagoDeudaErrorInesperado.new,
    );
  };
});

typedef CancelarPagoDeudaAutorizado = Future<CancelarPagoDeudaResultado> Function({
  required int pagoId,
  required String motivo,
});

final cancelarPagoDeudaAutorizadoProvider = Provider<CancelarPagoDeudaAutorizado>((ref) {
  return ({required int pagoId, required String motivo}) {
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'deudas.cancelarPago',
      () => ref.read(cancelarPagoDeudaUseCaseProvider).ejecutar(
            pagoId: pagoId,
            motivo: motivo,
            actorUsuarioId: ref.read(sesionControllerProvider)?.usuarioId,
          ),
      CancelarPagoDeudaErrorInesperado.new,
    );
  };
});

typedef CorregirDeudaAutorizado = Future<CorregirDeudaResultado> Function({
  required String deudaId,
  String? nombre,
  String? acreedor,
  DateTime? fechaOrigen,
  bool limpiarFechaOrigen,
  DateTime? fechaVencimiento,
  bool limpiarFechaVencimiento,
  int? pagoProgramado,
  bool limpiarPagoProgramado,
  String? periodicidad,
  bool limpiarPeriodicidad,
  double? tasaInteres,
  bool limpiarTasaInteres,
  String? referencia,
  String? observaciones,
  String? tarjetaUltimosDigitos,
  int? tarjetaLimiteCredito,
  int? tarjetaDiaCorte,
  int? tarjetaDiaPago,
  int? tarjetaPagoMinimo,
  String? tarjetaReglaFechaPago,
  int? tarjetaDiasDespuesCorte,
  String? tarjetaTipoTasa,
  bool limpiarTarjetaTipoTasa,
  String? tarjetaTasaReferencia,
  double? tarjetaTasaDiferencial,
  bool? tarjetaTasaMasIva,
  String? tarjetaTasaDescripcion,
  bool limpiarTasaVariable,
  double? tarjetaCat,
  bool? tarjetaCatIncluyeIva,
  bool limpiarCat,
  DateTime? tarjetaVencimientoCubiertoHasta,
  bool limpiarTarjetaVencimientoCubierto,
});

final corregirDeudaAutorizadoProvider = Provider<CorregirDeudaAutorizado>((ref) {
  return ({
    required String deudaId,
    String? nombre,
    String? acreedor,
    DateTime? fechaOrigen,
    bool limpiarFechaOrigen = false,
    DateTime? fechaVencimiento,
    bool limpiarFechaVencimiento = false,
    int? pagoProgramado,
    bool limpiarPagoProgramado = false,
    String? periodicidad,
    bool limpiarPeriodicidad = false,
    double? tasaInteres,
    bool limpiarTasaInteres = false,
    String? referencia,
    String? observaciones,
    String? tarjetaUltimosDigitos,
    int? tarjetaLimiteCredito,
    int? tarjetaDiaCorte,
    int? tarjetaDiaPago,
    int? tarjetaPagoMinimo,
    String? tarjetaReglaFechaPago,
    int? tarjetaDiasDespuesCorte,
    String? tarjetaTipoTasa,
    bool limpiarTarjetaTipoTasa = false,
    String? tarjetaTasaReferencia,
    double? tarjetaTasaDiferencial,
    bool? tarjetaTasaMasIva,
    String? tarjetaTasaDescripcion,
    bool limpiarTasaVariable = false,
    double? tarjetaCat,
    bool? tarjetaCatIncluyeIva,
    bool limpiarCat = false,
    DateTime? tarjetaVencimientoCubiertoHasta,
    bool limpiarTarjetaVencimientoCubierto = false,
  }) {
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'deudas.corregir',
      () => ref.read(corregirDeudaUseCaseProvider).ejecutar(
            deudaId: deudaId,
            nombre: nombre,
            acreedor: acreedor,
            fechaOrigen: fechaOrigen,
            limpiarFechaOrigen: limpiarFechaOrigen,
            fechaVencimiento: fechaVencimiento,
            limpiarFechaVencimiento: limpiarFechaVencimiento,
            pagoProgramado: pagoProgramado,
            limpiarPagoProgramado: limpiarPagoProgramado,
            periodicidad: periodicidad,
            limpiarPeriodicidad: limpiarPeriodicidad,
            tasaInteres: tasaInteres,
            limpiarTasaInteres: limpiarTasaInteres,
            referencia: referencia,
            observaciones: observaciones,
            tarjetaUltimosDigitos: tarjetaUltimosDigitos,
            tarjetaLimiteCredito: tarjetaLimiteCredito,
            tarjetaDiaCorte: tarjetaDiaCorte,
            tarjetaDiaPago: tarjetaDiaPago,
            tarjetaPagoMinimo: tarjetaPagoMinimo,
            tarjetaReglaFechaPago: tarjetaReglaFechaPago,
            tarjetaDiasDespuesCorte: tarjetaDiasDespuesCorte,
            tarjetaTipoTasa: tarjetaTipoTasa,
            limpiarTarjetaTipoTasa: limpiarTarjetaTipoTasa,
            tarjetaTasaReferencia: tarjetaTasaReferencia,
            tarjetaTasaDiferencial: tarjetaTasaDiferencial,
            tarjetaTasaMasIva: tarjetaTasaMasIva,
            tarjetaTasaDescripcion: tarjetaTasaDescripcion,
            limpiarTasaVariable: limpiarTasaVariable,
            tarjetaCat: tarjetaCat,
            tarjetaCatIncluyeIva: tarjetaCatIncluyeIva,
            limpiarCat: limpiarCat,
            tarjetaVencimientoCubiertoHasta: tarjetaVencimientoCubiertoHasta,
            limpiarTarjetaVencimientoCubierto: limpiarTarjetaVencimientoCubierto,
          ),
      CorregirDeudaErrorInesperado.new,
    );
  };
});

typedef CancelarDeudaAutorizado = Future<CancelarDeudaResultado> Function({
  required String deudaId,
  required String motivo,
});

final cancelarDeudaAutorizadoProvider = Provider<CancelarDeudaAutorizado>((ref) {
  return ({required String deudaId, required String motivo}) {
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'deudas.cancelar',
      () => ref.read(cancelarDeudaUseCaseProvider).ejecutar(
            deudaId: deudaId,
            motivo: motivo,
            actorUsuarioId: ref.read(sesionControllerProvider)?.usuarioId,
          ),
      CancelarDeudaErrorInesperado.new,
    );
  };
});

typedef EliminarDeudaFisicamenteAutorizado = Future<EliminarDeudaFisicamenteResultado> Function({
  required String deudaId,
  required String motivo,
});

final eliminarDeudaFisicamenteAutorizadoProvider = Provider<EliminarDeudaFisicamenteAutorizado>((ref) {
  return ({required String deudaId, required String motivo}) {
    return exigirMaestro(
      ref.read(permissionServiceProvider),
      () => ref.read(eliminarDeudaFisicamenteUseCaseProvider).ejecutar(
            deudaId: deudaId,
            motivo: motivo,
            actorUsuarioId: ref.read(sesionControllerProvider)?.usuarioId,
          ),
      EliminarDeudaFisicamenteErrorInesperado.new,
    );
  };
});

// --- Etapa 19C — Cuentas financieras, posición de caja y proyección ---

final cuentaFinancieraRepositoryProvider = Provider<CuentaFinancieraRepository>((ref) {
  return CuentaFinancieraRepositoryImpl(ref.watch(appDatabaseProvider));
});

final registrarCuentaFinancieraUseCaseProvider = Provider<RegistrarCuentaFinancieraUseCase>((ref) {
  return RegistrarCuentaFinancieraUseCase(ref.watch(cuentaFinancieraRepositoryProvider), ref.watch(generarCodigoUseCaseProvider));
});

final corregirCuentaFinancieraUseCaseProvider = Provider<CorregirCuentaFinancieraUseCase>((ref) {
  return CorregirCuentaFinancieraUseCase(ref.watch(cuentaFinancieraRepositoryProvider));
});

final eliminarCuentaFinancieraFisicamenteUseCaseProvider = Provider<EliminarCuentaFinancieraFisicamenteUseCase>((ref) {
  return EliminarCuentaFinancieraFisicamenteUseCase(ref.watch(cuentaFinancieraRepositoryProvider));
});

final activarCuentaFinancieraUseCaseProvider = Provider<ActivarCuentaFinancieraUseCase>((ref) {
  return ActivarCuentaFinancieraUseCase(ref.watch(cuentaFinancieraRepositoryProvider));
});

final desactivarCuentaFinancieraUseCaseProvider = Provider<DesactivarCuentaFinancieraUseCase>((ref) {
  return DesactivarCuentaFinancieraUseCase(ref.watch(cuentaFinancieraRepositoryProvider));
});

/// Reutiliza `finanzas.crear`/`finanzas.modificar` — mismo criterio que
/// Deuda arriba, no se crea un código de permiso nuevo para un catálogo
/// hermano dentro del mismo módulo.
typedef RegistrarCuentaFinancieraAutorizado = Future<RegistrarCuentaFinancieraResultado> Function({
  required String nombre,
  required String tipo,
  String? institucionId,
  String? ultimosDigitos,
  required int saldoInicial,
  required DateTime fechaSaldoInicial,
  String? observaciones,
});

final registrarCuentaFinancieraAutorizadoProvider = Provider<RegistrarCuentaFinancieraAutorizado>((ref) {
  return ({
    required String nombre,
    required String tipo,
    String? institucionId,
    String? ultimosDigitos,
    required int saldoInicial,
    required DateTime fechaSaldoInicial,
    String? observaciones,
  }) {
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'cuentasFinancieras.crear',
      () => ref.read(registrarCuentaFinancieraUseCaseProvider).ejecutar(
            nombre: nombre,
            tipo: tipo,
            institucionId: institucionId,
            ultimosDigitos: ultimosDigitos,
            saldoInicial: saldoInicial,
            fechaSaldoInicial: fechaSaldoInicial,
            observaciones: observaciones,
          ),
      RegistrarCuentaFinancieraErrorInesperado.new,
    );
  };
});

typedef CorregirCuentaFinancieraAutorizado = Future<CorregirCuentaFinancieraResultado> Function({
  required String cuentaId,
  String? nombre,
  String? institucionId,
  bool limpiarInstitucionId,
  String? ultimosDigitos,
  bool limpiarUltimosDigitos,
  String? observaciones,
});

final corregirCuentaFinancieraAutorizadoProvider = Provider<CorregirCuentaFinancieraAutorizado>((ref) {
  return ({
    required String cuentaId,
    String? nombre,
    String? institucionId,
    bool limpiarInstitucionId = false,
    String? ultimosDigitos,
    bool limpiarUltimosDigitos = false,
    String? observaciones,
  }) {
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'cuentasFinancieras.corregir',
      () => ref.read(corregirCuentaFinancieraUseCaseProvider).ejecutar(
            cuentaId: cuentaId,
            nombre: nombre,
            institucionId: institucionId,
            limpiarInstitucionId: limpiarInstitucionId,
            ultimosDigitos: ultimosDigitos,
            limpiarUltimosDigitos: limpiarUltimosDigitos,
            observaciones: observaciones,
          ),
      CorregirCuentaFinancieraErrorInesperado.new,
    );
  };
});

typedef ActivarDesactivarCuentaFinancieraAutorizado = Future<CuentaFinancieraData?> Function(String cuentaId);

final activarCuentaFinancieraAutorizadoProvider = Provider<ActivarDesactivarCuentaFinancieraAutorizado>((ref) {
  return (String cuentaId) {
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'cuentasFinancieras.cambiarEstatus',
      () => ref.read(activarCuentaFinancieraUseCaseProvider).ejecutar(cuentaId),
      (mensaje) => null,
    );
  };
});

final desactivarCuentaFinancieraAutorizadoProvider = Provider<ActivarDesactivarCuentaFinancieraAutorizado>((ref) {
  return (String cuentaId) {
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'cuentasFinancieras.cambiarEstatus',
      () => ref.read(desactivarCuentaFinancieraUseCaseProvider).ejecutar(cuentaId),
      (mensaje) => null,
    );
  };
});

typedef EliminarCuentaFinancieraFisicamenteAutorizado = Future<EliminarCuentaFinancieraFisicamenteResultado> Function({
  required String cuentaId,
  required String motivo,
});

final eliminarCuentaFinancieraFisicamenteAutorizadoProvider =
    Provider<EliminarCuentaFinancieraFisicamenteAutorizado>((ref) {
  return ({required String cuentaId, required String motivo}) {
    return exigirMaestro(
      ref.read(permissionServiceProvider),
      () => ref.read(eliminarCuentaFinancieraFisicamenteUseCaseProvider).ejecutar(
            cuentaId: cuentaId,
            motivo: motivo,
            actorUsuarioId: ref.read(sesionControllerProvider)?.usuarioId,
          ),
      EliminarCuentaFinancieraFisicamenteErrorInesperado.new,
    );
  };
});

final obtenerPosicionDeCajaUseCaseProvider = Provider<ObtenerPosicionDeCajaUseCase>((ref) {
  return ObtenerPosicionDeCajaUseCase(ref.watch(cuentaFinancieraRepositoryProvider));
});

final obtenerCreditoDisponibleTarjetasUseCaseProvider = Provider<ObtenerCreditoDisponibleTarjetasUseCase>((ref) {
  return ObtenerCreditoDisponibleTarjetasUseCase(ref.watch(deudaRepositoryProvider));
});

final obtenerFlujoEfectivoUseCaseProvider = Provider<ObtenerFlujoEfectivoUseCase>((ref) {
  return ObtenerFlujoEfectivoUseCase(ref.watch(ingresoRepositoryProvider), ref.watch(egresoRepositoryProvider));
});

final obtenerProyeccionCajaUseCaseProvider = Provider<ObtenerProyeccionCajaUseCase>((ref) {
  return ObtenerProyeccionCajaUseCase(
    ref.watch(cuentaFinancieraRepositoryProvider),
    ref.watch(cuentaPorCobrarRepositoryProvider),
    ref.watch(resolverNombresContraparteUseCaseProvider),
    ref.watch(nominaRepositoryProvider),
    ref.watch(pagoNominaRepositoryProvider),
    ref.watch(deudaRepositoryProvider),
  );
});

// ---------------------------------------------------------------------
// Transferencias entre cuentas propias (schemaVersion 91)
//
// Permiso propio `cuentasFinancieras.transferir`: transferir MUEVE
// dinero, lo que es cualitativamente distinto de editar la ficha de
// una cuenta, así que no reutiliza `corregir`. No es Maestro-only —
// no destruye historia.
// ---------------------------------------------------------------------

final transferenciaCuentaRepositoryProvider = Provider<TransferenciaCuentaRepositoryImpl>((ref) {
  return TransferenciaCuentaRepositoryImpl(ref.watch(appDatabaseProvider));
});

final transferirEntreCuentasUseCaseProvider = Provider<TransferirEntreCuentasUseCase>((ref) {
  return TransferirEntreCuentasUseCase(
    ref.watch(transferenciaCuentaRepositoryProvider),
    ref.watch(generarCodigoUseCaseProvider),
  );
});

final corregirTransferenciaUseCaseProvider = Provider<CorregirTransferenciaUseCase>((ref) {
  return CorregirTransferenciaUseCase(ref.watch(transferenciaCuentaRepositoryProvider));
});

final cancelarTransferenciaUseCaseProvider = Provider<CancelarTransferenciaUseCase>((ref) {
  return CancelarTransferenciaUseCase(ref.watch(transferenciaCuentaRepositoryProvider));
});

typedef TransferirEntreCuentasAutorizado = Future<TransferirEntreCuentasResultado> Function({
  required String cuentaOrigenId,
  required String cuentaDestinoId,
  required int importe,
  required DateTime fecha,
  String? concepto,
  String? observaciones,
});

final transferirEntreCuentasAutorizadoProvider = Provider<TransferirEntreCuentasAutorizado>((ref) {
  return ({
    required String cuentaOrigenId,
    required String cuentaDestinoId,
    required int importe,
    required DateTime fecha,
    String? concepto,
    String? observaciones,
  }) {
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'cuentasFinancieras.transferir',
      () => ref.read(transferirEntreCuentasUseCaseProvider).ejecutar(
            cuentaOrigenId: cuentaOrigenId,
            cuentaDestinoId: cuentaDestinoId,
            importe: importe,
            fecha: fecha,
            concepto: concepto,
            observaciones: observaciones,
            actorUsuarioId: ref.read(sesionControllerProvider)?.usuarioId,
          ),
      TransferirEntreCuentasErrorInesperado.new,
    );
  };
});

typedef CorregirTransferenciaAutorizado = Future<TransferirEntreCuentasResultado> Function({
  required String transferenciaId,
  int? importe,
  DateTime? fecha,
  String? concepto,
  String? observaciones,
  required String motivo,
});

final corregirTransferenciaAutorizadoProvider = Provider<CorregirTransferenciaAutorizado>((ref) {
  return ({
    required String transferenciaId,
    int? importe,
    DateTime? fecha,
    String? concepto,
    String? observaciones,
    required String motivo,
  }) {
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'cuentasFinancieras.transferir',
      () => ref.read(corregirTransferenciaUseCaseProvider).ejecutar(
            transferenciaId: transferenciaId,
            importe: importe,
            fecha: fecha,
            concepto: concepto,
            observaciones: observaciones,
            motivo: motivo,
            actorUsuarioId: ref.read(sesionControllerProvider)?.usuarioId,
          ),
      TransferirEntreCuentasErrorInesperado.new,
    );
  };
});

typedef CancelarTransferenciaAutorizado = Future<TransferirEntreCuentasResultado> Function({
  required String transferenciaId,
  required String motivo,
});

final cancelarTransferenciaAutorizadoProvider = Provider<CancelarTransferenciaAutorizado>((ref) {
  return ({required String transferenciaId, required String motivo}) {
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'cuentasFinancieras.transferir',
      () => ref.read(cancelarTransferenciaUseCaseProvider).ejecutar(
            transferenciaId: transferenciaId,
            motivo: motivo,
            actorUsuarioId: ref.read(sesionControllerProvider)?.usuarioId,
          ),
      TransferirEntreCuentasErrorInesperado.new,
    );
  };
});
