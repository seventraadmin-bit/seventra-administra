import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../compras/compras_providers.dart';
import '../finanzas/finanzas_providers.dart';
import '../nomina/nomina_providers.dart';
import '../organizacion/organizacion_providers.dart';
import '../personal/personal_providers.dart';
import 'domain/usecases/clasificar_egresos_por_origen_usecase.dart';
import 'domain/usecases/obtener_resumen_general_usecase.dart';
import 'domain/usecases/obtener_resumen_nomina_usecase.dart';
import 'domain/usecases/obtener_resumen_personal_usecase.dart';

/// Providers del módulo Reportes (Etapa 12A) — solo compone
/// repositorios/casos de uso ya existentes en sus dominios propios,
/// nunca declara un repositorio nuevo (Reportes no es dueño de ninguna
/// tabla).
final obtenerResumenGeneralUseCaseProvider = Provider<ObtenerResumenGeneralUseCase>((ref) {
  return ObtenerResumenGeneralUseCase(
    ref.watch(obtenerResumenFinancieroUseCaseProvider),
    ref.watch(compraRepositoryProvider),
    ref.watch(pagoNominaRepositoryProvider),
    ref.watch(empleadoRepositoryProvider),
    ref.watch(servicioRepositoryProvider),
  );
});

final clasificarEgresosPorOrigenUseCaseProvider = Provider<ClasificarEgresosPorOrigenUseCase>((ref) {
  return ClasificarEgresosPorOrigenUseCase(
    ref.watch(egresoRepositoryProvider),
    ref.watch(compraRepositoryProvider),
    ref.watch(pagoNominaRepositoryProvider),
  );
});

/// Etapa 12B — Personal · Nómina.
final obtenerResumenPersonalUseCaseProvider = Provider<ObtenerResumenPersonalUseCase>((ref) {
  return ObtenerResumenPersonalUseCase(ref.watch(empleadoRepositoryProvider), ref.watch(asignacionServicioRepositoryProvider));
});

final obtenerResumenNominaUseCaseProvider = Provider<ObtenerResumenNominaUseCase>((ref) {
  return ObtenerResumenNominaUseCase(ref.watch(nominaRepositoryProvider), ref.watch(pagoNominaRepositoryProvider));
});
