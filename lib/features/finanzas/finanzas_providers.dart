import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/providers.dart';
import 'data/repositories/cuenta_por_cobrar_repository_impl.dart';
import 'domain/repositories/cuenta_por_cobrar_repository.dart';
import 'domain/usecases/actualizar_fecha_vencimiento_cuenta_por_cobrar_usecase.dart';

/// Providers del dominio Finanzas (Etapa 4J.1) — nace aquí, separado
/// de `organizacion`/`comercial` (Resolución B de Marlon, explícita).
final cuentaPorCobrarRepositoryProvider = Provider<CuentaPorCobrarRepository>((ref) {
  return CuentaPorCobrarRepositoryImpl(ref.watch(appDatabaseProvider));
});

final actualizarFechaVencimientoCuentaPorCobrarUseCaseProvider =
    Provider<ActualizarFechaVencimientoCuentaPorCobrarUseCase>((ref) {
  return ActualizarFechaVencimientoCuentaPorCobrarUseCase(ref.watch(cuentaPorCobrarRepositoryProvider));
});
