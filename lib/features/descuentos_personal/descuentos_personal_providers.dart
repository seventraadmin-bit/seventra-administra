import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/providers.dart';
import '../../core/permissions/authorization_service.dart';
import '../finanzas/finanzas_providers.dart' show egresoRepositoryProvider;
import '../organizacion/organizacion_providers.dart';
import '../personal/personal_providers.dart';
import '../usuarios/presentation/sesion_controller.dart';
import '../usuarios/usuarios_providers.dart';
import 'data/repositories/descuento_programado_repository_impl.dart';
import 'domain/repositories/descuento_programado_repository.dart';
import 'domain/usecases/cancelar_saldo_descuento_programado_usecase.dart';
import 'domain/usecases/corregir_descuento_programado_usecase.dart';
import 'domain/usecases/eliminar_descuento_programado_fisicamente_usecase.dart';
import 'domain/usecases/registrar_descuento_programado_usecase.dart';
import 'domain/usecases/reprogramar_cuotas_pendientes_usecase.dart';

/// Providers de Descuentos Programados al Personal (Etapa 15) — nace
/// separado de `personal`/`nomina` porque cruza ambos dominios (y
/// opcionalmente Inventario), mismo criterio que `nomina` nació
/// separado de `personal` en la Etapa 6C.
final descuentoProgramadoRepositoryProvider =
    Provider<DescuentoProgramadoRepository>((ref) {
      return DescuentoProgramadoRepositoryImpl(
        ref.watch(appDatabaseProvider),
        ref.watch(egresoRepositoryProvider),
        ref.watch(codigoSecuenciaServiceProvider),
      );
    });

final registrarDescuentoProgramadoUseCaseProvider =
    Provider<RegistrarDescuentoProgramadoUseCase>((ref) {
      return RegistrarDescuentoProgramadoUseCase(
        ref.watch(descuentoProgramadoRepositoryProvider),
        ref.watch(empleadoRepositoryProvider),
        ref.watch(generarCodigoUseCaseProvider),
      );
    });

final reprogramarCuotasPendientesUseCaseProvider =
    Provider<ReprogramarCuotasPendientesUseCase>((ref) {
      return ReprogramarCuotasPendientesUseCase(
        ref.watch(descuentoProgramadoRepositoryProvider),
      );
    });

final cancelarSaldoDescuentoProgramadoUseCaseProvider =
    Provider<CancelarSaldoDescuentoProgramadoUseCase>((ref) {
      return CancelarSaldoDescuentoProgramadoUseCase(
        ref.watch(descuentoProgramadoRepositoryProvider),
      );
    });

final corregirDescuentoProgramadoUseCaseProvider =
    Provider<CorregirDescuentoProgramadoUseCase>((ref) {
      return CorregirDescuentoProgramadoUseCase(
        ref.watch(descuentoProgramadoRepositoryProvider),
      );
    });

final eliminarDescuentoProgramadoFisicamenteUseCaseProvider =
    Provider<EliminarDescuentoProgramadoFisicamenteUseCase>((ref) {
      return EliminarDescuentoProgramadoFisicamenteUseCase(
        ref.watch(descuentoProgramadoRepositoryProvider),
      );
    });

// Las 3 operaciones (registrar/reprogramar/cancelar) mueven dinero
// real — códigos dedicados `descuentos.crear`/`descuentos.corregir`/
// `descuentos.cancelar` (nunca `personal.modificar`), mismo criterio
// que `nomina.pagar` (Etapa 1, rediseño de catálogo de permisos: el
// antiguo `personal.gestionarDescuentos` se dividió en el módulo
// `descuentos` propio, con su propio código de lectura `descuentos.ver`
// — ver `descuentos_personal_controller.dart`).

typedef RegistrarDescuentoProgramadoAutorizado =
    Future<RegistrarDescuentoProgramadoResultado> Function({
      required String empleadoId,
      required String tipo,
      required DateTime fechaRegistro,
      required int importeOriginal,
      required int numeroCuotas,
      required DateTime fechaPrimeraCuota,
      String? descripcion,
      String? asignacionOrigenId,
      String? observaciones,
      bool esEntregaDinero,
      String? cuentaFinancieraId,
      String? formaPagoEgreso,
    });

final registrarDescuentoProgramadoAutorizadoProvider =
    Provider<RegistrarDescuentoProgramadoAutorizado>((ref) {
      return ({
        required String empleadoId,
        required String tipo,
        required DateTime fechaRegistro,
        required int importeOriginal,
        required int numeroCuotas,
        required DateTime fechaPrimeraCuota,
        String? descripcion,
        String? asignacionOrigenId,
        String? observaciones,
        bool esEntregaDinero = false,
        String? cuentaFinancieraId,
        String? formaPagoEgreso,
      }) {
        return autorizarUseCase(
          ref.read(authorizationServiceProvider),
          'descuentos.crear',
          () => ref
              .read(registrarDescuentoProgramadoUseCaseProvider)
              .ejecutar(
                empleadoId: empleadoId,
                tipo: tipo,
                fechaRegistro: fechaRegistro,
                importeOriginal: importeOriginal,
                numeroCuotas: numeroCuotas,
                fechaPrimeraCuota: fechaPrimeraCuota,
                descripcion: descripcion,
                asignacionOrigenId: asignacionOrigenId,
                observaciones: observaciones,
                esEntregaDinero: esEntregaDinero,
                cuentaFinancieraId: cuentaFinancieraId,
                formaPagoEgreso: formaPagoEgreso,
                actorUsuarioId: ref.read(sesionControllerProvider)?.usuarioId,
              ),
          RegistrarDescuentoProgramadoErrorInesperado.new,
        );
      };
    });

typedef ReprogramarCuotasPendientesAutorizado =
    Future<ReprogramarCuotasPendientesResultado> Function({
      required String descuentoProgramadoId,
      required int numeroCuotas,
      required DateTime fechaPrimeraCuota,
      required String motivo,
    });

final reprogramarCuotasPendientesAutorizadoProvider =
    Provider<ReprogramarCuotasPendientesAutorizado>((ref) {
      return ({
        required String descuentoProgramadoId,
        required int numeroCuotas,
        required DateTime fechaPrimeraCuota,
        required String motivo,
      }) {
        return autorizarUseCase(
          ref.read(authorizationServiceProvider),
          'descuentos.corregir',
          () => ref
              .read(reprogramarCuotasPendientesUseCaseProvider)
              .ejecutar(
                descuentoProgramadoId: descuentoProgramadoId,
                numeroCuotas: numeroCuotas,
                fechaPrimeraCuota: fechaPrimeraCuota,
                motivo: motivo,
                actorUsuarioId: ref.read(sesionControllerProvider)?.usuarioId,
              ),
          ReprogramarCuotasPendientesErrorInesperado.new,
        );
      };
    });

typedef CorregirDescuentoProgramadoAutorizado =
    Future<CorregirDescuentoProgramadoResultado> Function({
      required String descuentoProgramadoId,
      String? tipo,
      String? descripcion,
      bool limpiarDescripcion,
      String? observaciones,
      bool limpiarObservaciones,
      DateTime? fechaRegistro,
      int? importeOriginal,
      int? numeroCuotas,
      DateTime? fechaPrimeraCuota,
      String? cuentaFinancieraId,
      bool limpiarCuentaFinancieraId,
      required String motivo,
    });

// Reutiliza el mismo código `descuentos.corregir` que ya gatea
// `ReprogramarCuotasPendientesUseCase` — ambas son la misma facultad
// ("corregir un descuento programado"), ahora con dos rutas: solo
// reprogramar cuotas futuras, o una corrección completa que también
// puede tocar el monto total y campos administrativos.
final corregirDescuentoProgramadoAutorizadoProvider =
    Provider<CorregirDescuentoProgramadoAutorizado>((ref) {
      return ({
        required String descuentoProgramadoId,
        String? tipo,
        String? descripcion,
        bool limpiarDescripcion = false,
        String? observaciones,
        bool limpiarObservaciones = false,
        DateTime? fechaRegistro,
        int? importeOriginal,
        int? numeroCuotas,
        DateTime? fechaPrimeraCuota,
        String? cuentaFinancieraId,
        bool limpiarCuentaFinancieraId = false,
        required String motivo,
      }) {
        return autorizarUseCase(
          ref.read(authorizationServiceProvider),
          'descuentos.corregir',
          () => ref
              .read(corregirDescuentoProgramadoUseCaseProvider)
              .ejecutar(
                descuentoProgramadoId: descuentoProgramadoId,
                tipo: tipo,
                descripcion: descripcion,
                limpiarDescripcion: limpiarDescripcion,
                observaciones: observaciones,
                limpiarObservaciones: limpiarObservaciones,
                fechaRegistro: fechaRegistro,
                importeOriginal: importeOriginal,
                numeroCuotas: numeroCuotas,
                fechaPrimeraCuota: fechaPrimeraCuota,
                cuentaFinancieraId: cuentaFinancieraId,
                limpiarCuentaFinancieraId: limpiarCuentaFinancieraId,
                motivo: motivo,
                actorUsuarioId: ref.read(sesionControllerProvider)?.usuarioId,
              ),
          CorregirDescuentoProgramadoErrorInesperado.new,
        );
      };
    });

typedef CancelarSaldoDescuentoProgramadoAutorizado =
    Future<CancelarSaldoDescuentoProgramadoResultado> Function({
      required String descuentoProgramadoId,
      required String motivo,
    });

final cancelarSaldoDescuentoProgramadoAutorizadoProvider =
    Provider<CancelarSaldoDescuentoProgramadoAutorizado>((ref) {
      return ({required String descuentoProgramadoId, required String motivo}) {
        return autorizarUseCase(
          ref.read(authorizationServiceProvider),
          'descuentos.cancelar',
          () => ref
              .read(cancelarSaldoDescuentoProgramadoUseCaseProvider)
              .ejecutar(
                descuentoProgramadoId: descuentoProgramadoId,
                motivo: motivo,
                actorUsuarioId: ref.read(sesionControllerProvider)?.usuarioId,
              ),
          CancelarSaldoDescuentoProgramadoErrorInesperado.new,
        );
      };
    });

// Eliminación física extraordinaria (pedido explícito, "eliminar el
// movimiento por pruebas") — facultad exclusiva del Usuario Maestro,
// mismo patrón exacto que Deuda/Cuenta financiera (`exigirMaestro`,
// nunca `AuthorizationService.verificar`).
typedef EliminarDescuentoProgramadoFisicamenteAutorizado =
    Future<EliminarDescuentoProgramadoFisicamenteResultado> Function({
      required String descuentoProgramadoId,
      required String motivo,
    });

final eliminarDescuentoProgramadoFisicamenteAutorizadoProvider =
    Provider<EliminarDescuentoProgramadoFisicamenteAutorizado>((ref) {
      return ({required String descuentoProgramadoId, required String motivo}) {
        return exigirMaestro(
          ref.read(permissionServiceProvider),
          () => ref
              .read(eliminarDescuentoProgramadoFisicamenteUseCaseProvider)
              .ejecutar(
                descuentoProgramadoId: descuentoProgramadoId,
                motivo: motivo,
                actorUsuarioId: ref.read(sesionControllerProvider)?.usuarioId,
              ),
          EliminarDescuentoProgramadoFisicamenteErrorInesperado.new,
        );
      };
    });
