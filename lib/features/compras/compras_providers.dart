import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/providers.dart';
import '../../core/permissions/authorization_service.dart';
import '../finanzas/finanzas_providers.dart';
import '../inventario/inventario_providers.dart';
import '../organizacion/organizacion_providers.dart' show attachmentStorageProvider, generarCodigoUseCaseProvider;
import '../usuarios/presentation/sesion_controller.dart';
import '../usuarios/usuarios_providers.dart';
import 'data/repositories/compra_repository_impl.dart';
import 'domain/repositories/compra_repository.dart';
import 'domain/usecases/adjuntar_comprobante_compra_usecase.dart';
import 'domain/usecases/cancelar_compra_usecase.dart';
import 'domain/usecases/corregir_compra_usecase.dart';
import 'domain/usecases/eliminar_cadena_prueba_compra_usecase.dart';
import 'domain/usecases/eliminar_compra_fisicamente_usecase.dart';
import 'domain/usecases/registrar_compra_usecase.dart';

/// Providers del dominio Compras (Etapa 10) — compone con los
/// repositorios reales de Inventario y Finanzas (`inventarioRepository`/
/// `articuloRepository`/`egresoRepository`), nunca con sus casos de
/// uso — mismo criterio ya establecido por Telefonía→Inventario (9B) y
/// Nómina→Finanzas (6D).
final compraRepositoryProvider = Provider<CompraRepository>((ref) {
  return CompraRepositoryImpl(
    ref.watch(appDatabaseProvider),
    ref.watch(inventarioRepositoryProvider),
    ref.watch(articuloRepositoryProvider),
    ref.watch(egresoRepositoryProvider),
    ref.watch(deudaRepositoryProvider),
  );
});

final registrarCompraUseCaseProvider = Provider<RegistrarCompraUseCase>((ref) {
  return RegistrarCompraUseCase(
    ref.watch(compraRepositoryProvider),
    ref.watch(articuloRepositoryProvider),
    ref.watch(inventarioRepositoryProvider),
    ref.watch(deudaRepositoryProvider),
    ref.watch(generarCodigoUseCaseProvider),
  );
});

final corregirCompraUseCaseProvider = Provider<CorregirCompraUseCase>((ref) {
  return CorregirCompraUseCase(
    ref.watch(compraRepositoryProvider),
    ref.watch(articuloRepositoryProvider),
    ref.watch(inventarioRepositoryProvider),
    ref.watch(deudaRepositoryProvider),
  );
});

final cancelarCompraUseCaseProvider = Provider<CancelarCompraUseCase>((ref) {
  return CancelarCompraUseCase(ref.watch(compraRepositoryProvider));
});

final adjuntarComprobanteCompraUseCaseProvider = Provider<AdjuntarComprobanteCompraUseCase>((ref) {
  return AdjuntarComprobanteCompraUseCase(ref.watch(compraRepositoryProvider), ref.watch(attachmentStorageProvider));
});

// Eliminación física extraordinaria (Etapa 15) — facultad exclusiva del
// Usuario Maestro, mismo patrón exacto que Cliente/Servicio/Documento
// por emitir/Egreso (`exigirMaestro`, nunca `AuthorizationService.verificar`).
final eliminarCompraFisicamenteUseCaseProvider = Provider<EliminarCompraFisicamenteUseCase>((ref) {
  return EliminarCompraFisicamenteUseCase(ref.watch(compraRepositoryProvider));
});

typedef EliminarCompraFisicamenteAutorizado = Future<EliminarCompraFisicamenteResultado> Function({
  required String compraId,
  required MotivoEliminacionFisicaCompra motivo,
  String? detalle,
});

final eliminarCompraFisicamenteAutorizadoProvider = Provider<EliminarCompraFisicamenteAutorizado>((ref) {
  return ({required String compraId, required MotivoEliminacionFisicaCompra motivo, String? detalle}) {
    return exigirMaestro(
      ref.read(permissionServiceProvider),
      () => ref.read(eliminarCompraFisicamenteUseCaseProvider).ejecutar(
            compraId: compraId,
            motivo: motivo,
            detalle: detalle,
            actorUsuarioId: ref.read(sesionControllerProvider)?.usuarioId,
          ),
      EliminarCompraFisicamenteErrorInesperado.new,
    );
  };
});

// "Eliminar cadena de prueba" (Etapa 15, limpieza segura de datos de
// prueba) — ofrecida SOLO cuando la eliminación física normal está
// bloqueada por historia posterior; misma facultad exclusiva Maestro.
final eliminarCadenaPruebaCompraUseCaseProvider = Provider<EliminarCadenaPruebaCompraUseCase>((ref) {
  return EliminarCadenaPruebaCompraUseCase(ref.watch(compraRepositoryProvider));
});

typedef EliminarCadenaPruebaCompraAutorizado = Future<EliminarCadenaPruebaCompraResultado> Function({
  required String compraId,
  required MotivoCadenaPruebaCompra motivo,
  String? detalle,
});

final eliminarCadenaPruebaCompraAutorizadoProvider = Provider<EliminarCadenaPruebaCompraAutorizado>((ref) {
  return ({required String compraId, required MotivoCadenaPruebaCompra motivo, String? detalle}) {
    return exigirMaestro(
      ref.read(permissionServiceProvider),
      () => ref.read(eliminarCadenaPruebaCompraUseCaseProvider).ejecutar(
            compraId: compraId,
            motivo: motivo,
            detalle: detalle,
            actorUsuarioId: ref.read(sesionControllerProvider)?.usuarioId,
          ),
      EliminarCadenaPruebaCompraErrorInesperado.new,
    );
  };
});
