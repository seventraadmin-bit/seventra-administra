import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../compras/compras_providers.dart';
import '../finanzas/finanzas_providers.dart';
import '../inventario/inventario_providers.dart';
import '../notificaciones/notificaciones_providers.dart';
import '../nomina/nomina_providers.dart';
import '../organizacion/organizacion_providers.dart';
import '../personal/personal_providers.dart';
import '../telefonia/telefonia_providers.dart';
import 'domain/usecases/obtener_actividad_reciente_usecase.dart';
import 'domain/usecases/obtener_alertas_dashboard_usecase.dart';
import 'domain/usecases/obtener_cobertura_operativa_usecase.dart';
import 'domain/usecases/obtener_empleados_baja_con_pendiente_usecase.dart';
import 'domain/usecases/obtener_proxima_nomina_usecase.dart';
import 'domain/usecases/obtener_resumen_cobranza_usecase.dart';
import 'domain/usecases/obtener_serie_financiera_usecase.dart';

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
    ref.watch(deudaRepositoryProvider),
    ref.watch(obtenerNotificacionesDocumentosPorEmitirUseCaseProvider),
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
    ref.watch(vacanteOperativaRepositoryProvider),
    ref.watch(servicioRepositoryProvider),
  );
});

/// Cobertura operativa por Servicio (Parte C.1/C.2/C.3/D del rediseño
/// gerencial) — compone `ServicioRepository`/`ServicioComercialRepository`
/// (ya existentes) con la nueva bitácora `VacanteOperativaRepository`.
final obtenerCoberturaOperativaUseCaseProvider = Provider<ObtenerCoberturaOperativaUseCase>((ref) {
  return ObtenerCoberturaOperativaUseCase(
    ref.watch(servicioRepositoryProvider),
    ref.watch(servicioComercialRepositoryProvider),
    ref.watch(vacanteOperativaRepositoryProvider),
  );
});

/// Cobranza clasificada (Parte I/J) — compone `CuentaPorCobrarRepository`
/// (ya existente) con las reglas de dominio ya establecidas
/// (`estaVencida`/`diasParaVencerCxc`), nunca un estado nuevo.
final obtenerResumenCobranzaUseCaseProvider = Provider<ObtenerResumenCobranzaUseCase>((ref) {
  return ObtenerResumenCobranzaUseCase(ref.watch(cuentaPorCobrarRepositoryProvider));
});

/// Próxima Nómina real pendiente de pago (Parte C.4).
final obtenerProximaNominaUseCaseProvider = Provider<ObtenerProximaNominaUseCase>((ref) {
  return ObtenerProximaNominaUseCase(ref.watch(nominaRepositoryProvider));
});

/// Serie diaria Ingresos/Egresos (Parte H).
final obtenerSerieFinancieraUseCaseProvider = Provider<ObtenerSerieFinancieraUseCase>((ref) {
  return ObtenerSerieFinancieraUseCase(ref.watch(ingresoRepositoryProvider), ref.watch(egresoRepositoryProvider));
});
