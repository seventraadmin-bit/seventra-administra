import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../compras/compras_providers.dart';
import '../finanzas/finanzas_providers.dart';
import '../inventario/inventario_providers.dart';
import '../organizacion/organizacion_providers.dart';
import '../personal/personal_providers.dart';
import '../telefonia/telefonia_providers.dart';
import 'domain/usecases/obtener_actividad_reciente_usecase.dart';
import 'domain/usecases/obtener_alertas_dashboard_usecase.dart';
import 'domain/usecases/obtener_empleados_baja_con_pendiente_usecase.dart';

/// Providers del módulo Dashboard (Etapa 13) — los 6 resúmenes por
/// dominio se reutilizan TAL CUAL desde `reportes_providers.dart`
/// (`obtenerResumenGeneralUseCaseProvider`,
/// `obtenerResumenPersonalUseCaseProvider`, etc.) — Dashboard no
/// redefine ningún provider de Reportes, solo los importa. Aquí solo
/// viven los 3 use cases genuinamente nuevos de esta etapa.
final obtenerEmpleadosBajaConPendienteUseCaseProvider = Provider<ObtenerEmpleadosBajaConPendienteUseCase>((ref) {
  return ObtenerEmpleadosBajaConPendienteUseCase(ref.watch(empleadoRepositoryProvider), ref.watch(asignacionRepositoryProvider));
});

final obtenerAlertasDashboardUseCaseProvider = Provider<ObtenerAlertasDashboardUseCase>((ref) {
  return ObtenerAlertasDashboardUseCase(
    ref.watch(cuentaPorCobrarRepositoryProvider),
    ref.watch(obtenerEmpleadosBajaConPendienteUseCaseProvider),
  );
});

final obtenerActividadRecienteUseCaseProvider = Provider<ObtenerActividadRecienteUseCase>((ref) {
  return ObtenerActividadRecienteUseCase(
    ref.watch(compraRepositoryProvider),
    ref.watch(pagoRepositoryProvider),
    ref.watch(clienteRepositoryProvider),
    ref.watch(inventarioRepositoryProvider),
    ref.watch(articuloRepositoryProvider),
    ref.watch(recargaLineaTelefonicaRepositoryProvider),
    ref.watch(lineaTelefonicaRepositoryProvider),
  );
});
