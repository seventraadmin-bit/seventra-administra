import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/providers.dart';
import '../../core/permissions/authorization_service.dart';
import '../finanzas/finanzas_providers.dart';
import '../organizacion/organizacion_providers.dart';
import '../personal/personal_providers.dart';
import '../usuarios/presentation/sesion_controller.dart';
import '../usuarios/usuarios_providers.dart';
import 'data/repositories/tiempo_extra_repository_impl.dart';
import 'data/repositories/vacante_cobertura_reader.dart';
import 'domain/repositories/tiempo_extra_repository.dart';
import 'domain/usecases/cancelar_tiempo_extra_usecase.dart';
import 'domain/usecases/corregir_tiempo_extra_usecase.dart';
import 'domain/usecases/eliminar_tiempo_extra_fisicamente_usecase.dart';
import 'domain/usecases/obtener_resumen_tiempos_extra_usecase.dart';
import 'domain/usecases/registrar_tiempo_extra_usecase.dart';

/// Providers de Tiempos Extra (cobertura operativa por ausencia) — nace
/// separado porque cruza Personal/Nómina/Finanzas, mismo criterio que
/// `descuentos_personal` nació separado de `personal`.
final tiempoExtraRepositoryProvider = Provider<TiempoExtraRepository>((ref) {
  return TiempoExtraRepositoryImpl(
    ref.watch(appDatabaseProvider),
    ref.watch(egresoRepositoryProvider),
    ref.watch(deudaRepositoryProvider),
    ref.watch(codigoSecuenciaServiceProvider),
    ref.watch(empleadoRepositoryProvider),
    ref.watch(servicioRepositoryProvider),
  );
});

/// Contexto legible de las vacantes (puesto — turno, estado, fecha de
/// apertura) tanto para elegir una al registrar como para resolver la
/// de un TiempoExtra histórico.
final vacanteCoberturaReaderProvider = Provider<VacanteCoberturaReader>((ref) {
  return VacanteCoberturaReader(ref.watch(appDatabaseProvider));
});

final registrarTiempoExtraUseCaseProvider = Provider<RegistrarTiempoExtraUseCase>((ref) {
  return RegistrarTiempoExtraUseCase(
    ref.watch(tiempoExtraRepositoryProvider),
    ref.watch(empleadoRepositoryProvider),
    ref.watch(servicioRepositoryProvider),
    ref.watch(deudaRepositoryProvider),
    ref.watch(vacanteCoberturaReaderProvider),
  );
});

final cancelarTiempoExtraUseCaseProvider = Provider<CancelarTiempoExtraUseCase>((ref) {
  return CancelarTiempoExtraUseCase(ref.watch(tiempoExtraRepositoryProvider));
});

final corregirTiempoExtraUseCaseProvider = Provider<CorregirTiempoExtraUseCase>((ref) {
  return CorregirTiempoExtraUseCase(
    ref.watch(tiempoExtraRepositoryProvider),
    ref.watch(empleadoRepositoryProvider),
    ref.watch(servicioRepositoryProvider),
    ref.watch(deudaRepositoryProvider),
    ref.watch(vacanteCoberturaReaderProvider),
  );
});

final eliminarTiempoExtraFisicamenteUseCaseProvider = Provider<EliminarTiempoExtraFisicamenteUseCase>((ref) {
  return EliminarTiempoExtraFisicamenteUseCase(ref.watch(tiempoExtraRepositoryProvider));
});

final obtenerResumenTiemposExtraUseCaseProvider = Provider<ObtenerResumenTiemposExtraUseCase>((ref) {
  return ObtenerResumenTiemposExtraUseCase(ref.watch(tiempoExtraRepositoryProvider), ref.watch(servicioRepositoryProvider));
});

// Registrar/corregir/cancelar mueven dinero real — 3 códigos separados
// (Etapa "corrección real de Tiempo Extra": reemplaza el único
// `personal.gestionarTiemposExtra` de antes, pedido explícito de
// Marlon — acciones financieras distintas deben poder otorgarse
// independientemente). Eliminación física NUNCA es un permiso
// otorgable — `exigirMaestro`, mismo criterio que los demás módulos.

typedef RegistrarTiempoExtraAutorizado = Future<RegistrarTiempoExtraResultado> Function({
  required DateTime fecha,
  required String servicioId,
  required String origenCobertura,
  String? empleadoAusenteId,
  String? motivoAusencia,
  String? vacanteOperativaId,
  String? descripcionOrigen,
  String? empleadoCubreId,
  String? nombreExternoCubre,
  required String turnoId,
  required int montoTiempoExtra,
  required String formaPago,
  String? cuentaFinancieraId,
  String? deudaIdTarjeta,
  String? observaciones,
  List<CostoAdicionalInput> costosAdicionales,
});

final registrarTiempoExtraAutorizadoProvider = Provider<RegistrarTiempoExtraAutorizado>((ref) {
  return ({
    required DateTime fecha,
    required String servicioId,
    required String origenCobertura,
    String? empleadoAusenteId,
    String? motivoAusencia,
    String? vacanteOperativaId,
    String? descripcionOrigen,
    String? empleadoCubreId,
    String? nombreExternoCubre,
    required String turnoId,
    required int montoTiempoExtra,
    required String formaPago,
    String? cuentaFinancieraId,
    String? deudaIdTarjeta,
    String? observaciones,
    List<CostoAdicionalInput> costosAdicionales = const [],
  }) {
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'tiempoExtra.crear',
      () => ref.read(registrarTiempoExtraUseCaseProvider).ejecutar(
            fecha: fecha,
            servicioId: servicioId,
            origenCobertura: origenCobertura,
            empleadoAusenteId: empleadoAusenteId,
            motivoAusencia: motivoAusencia,
            vacanteOperativaId: vacanteOperativaId,
            descripcionOrigen: descripcionOrigen,
            empleadoCubreId: empleadoCubreId,
            nombreExternoCubre: nombreExternoCubre,
            turnoId: turnoId,
            montoTiempoExtra: montoTiempoExtra,
            formaPago: formaPago,
            cuentaFinancieraId: cuentaFinancieraId,
            deudaIdTarjeta: deudaIdTarjeta,
            observaciones: observaciones,
            costosAdicionales: costosAdicionales,
            actorUsuarioId: ref.read(sesionControllerProvider)?.usuarioId,
          ),
      RegistrarTiempoExtraErrorInesperado.new,
    );
  };
});

typedef CancelarTiempoExtraAutorizado = Future<CancelarTiempoExtraResultado> Function({
  required String tiempoExtraId,
  required String motivo,
});

final cancelarTiempoExtraAutorizadoProvider = Provider<CancelarTiempoExtraAutorizado>((ref) {
  return ({required String tiempoExtraId, required String motivo}) {
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'tiempoExtra.cancelar',
      () => ref.read(cancelarTiempoExtraUseCaseProvider).ejecutar(
            tiempoExtraId: tiempoExtraId,
            motivo: motivo,
            actorUsuarioId: ref.read(sesionControllerProvider)?.usuarioId,
          ),
      CancelarTiempoExtraErrorInesperado.new,
    );
  };
});

typedef CorregirTiempoExtraAutorizado = Future<CorregirTiempoExtraResultado> Function({
  required String tiempoExtraId,
  required DateTime fecha,
  required String servicioId,
  required String origenCobertura,
  String? empleadoAusenteId,
  String? motivoAusencia,
  String? vacanteOperativaId,
  String? descripcionOrigen,
  String? empleadoCubreId,
  String? nombreExternoCubre,
  required String turnoId,
  required int montoTiempoExtra,
  required String formaPago,
  String? cuentaFinancieraId,
  String? deudaIdTarjeta,
  String? observaciones,
  List<CorreccionCostoAdicional> cambiosCostos,
  required String motivo,
});

final corregirTiempoExtraAutorizadoProvider = Provider<CorregirTiempoExtraAutorizado>((ref) {
  return ({
    required String tiempoExtraId,
    required DateTime fecha,
    required String servicioId,
    required String origenCobertura,
    String? empleadoAusenteId,
    String? motivoAusencia,
    String? vacanteOperativaId,
    String? descripcionOrigen,
    String? empleadoCubreId,
    String? nombreExternoCubre,
    required String turnoId,
    required int montoTiempoExtra,
    required String formaPago,
    String? cuentaFinancieraId,
    String? deudaIdTarjeta,
    String? observaciones,
    List<CorreccionCostoAdicional> cambiosCostos = const [],
    required String motivo,
  }) {
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'tiempoExtra.corregir',
      () => ref.read(corregirTiempoExtraUseCaseProvider).ejecutar(
            tiempoExtraId: tiempoExtraId,
            fecha: fecha,
            servicioId: servicioId,
            origenCobertura: origenCobertura,
            empleadoAusenteId: empleadoAusenteId,
            motivoAusencia: motivoAusencia,
            vacanteOperativaId: vacanteOperativaId,
            descripcionOrigen: descripcionOrigen,
            empleadoCubreId: empleadoCubreId,
            nombreExternoCubre: nombreExternoCubre,
            turnoId: turnoId,
            montoTiempoExtra: montoTiempoExtra,
            formaPago: formaPago,
            cuentaFinancieraId: cuentaFinancieraId,
            deudaIdTarjeta: deudaIdTarjeta,
            observaciones: observaciones,
            cambiosCostos: cambiosCostos,
            motivo: motivo,
            actorUsuarioId: ref.read(sesionControllerProvider)?.usuarioId,
          ),
      CorregirTiempoExtraErrorInesperado.new,
    );
  };
});

// Eliminación física — nunca un permiso otorgable, exclusiva del
// Usuario Maestro (`exigirMaestro`, mismo criterio que
// `eliminarDescuentoProgramadoFisicamenteAutorizadoProvider`/
// `eliminarCompraFisicamenteAutorizadoProvider`).
typedef EliminarTiempoExtraFisicamenteAutorizado = Future<EliminarTiempoExtraFisicamenteResultado> Function({
  required String tiempoExtraId,
  required MotivoEliminacionFisicaTiempoExtra motivo,
  String? detalle,
});

final eliminarTiempoExtraFisicamenteAutorizadoProvider = Provider<EliminarTiempoExtraFisicamenteAutorizado>((ref) {
  return ({required String tiempoExtraId, required MotivoEliminacionFisicaTiempoExtra motivo, String? detalle}) {
    return exigirMaestro(
      ref.read(permissionServiceProvider),
      () => ref.read(eliminarTiempoExtraFisicamenteUseCaseProvider).ejecutar(
            tiempoExtraId: tiempoExtraId,
            motivo: motivo,
            detalle: detalle,
            actorUsuarioId: ref.read(sesionControllerProvider)?.usuarioId,
          ),
      EliminarTiempoExtraFisicamenteErrorInesperado.new,
    );
  };
});
