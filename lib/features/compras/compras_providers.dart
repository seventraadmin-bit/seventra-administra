import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/providers.dart';
import '../finanzas/finanzas_providers.dart';
import '../inventario/inventario_providers.dart';
import '../organizacion/organizacion_providers.dart' show attachmentStorageProvider, generarCodigoUseCaseProvider;
import 'data/repositories/compra_repository_impl.dart';
import 'domain/repositories/compra_repository.dart';
import 'domain/usecases/adjuntar_comprobante_compra_usecase.dart';
import 'domain/usecases/cancelar_compra_usecase.dart';
import 'domain/usecases/corregir_compra_usecase.dart';
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
  );
});

final registrarCompraUseCaseProvider = Provider<RegistrarCompraUseCase>((ref) {
  return RegistrarCompraUseCase(
    ref.watch(compraRepositoryProvider),
    ref.watch(articuloRepositoryProvider),
    ref.watch(inventarioRepositoryProvider),
    ref.watch(generarCodigoUseCaseProvider),
  );
});

final corregirCompraUseCaseProvider = Provider<CorregirCompraUseCase>((ref) {
  return CorregirCompraUseCase(ref.watch(compraRepositoryProvider));
});

final cancelarCompraUseCaseProvider = Provider<CancelarCompraUseCase>((ref) {
  return CancelarCompraUseCase(ref.watch(compraRepositoryProvider));
});

final adjuntarComprobanteCompraUseCaseProvider = Provider<AdjuntarComprobanteCompraUseCase>((ref) {
  return AdjuntarComprobanteCompraUseCase(ref.watch(compraRepositoryProvider), ref.watch(attachmentStorageProvider));
});
