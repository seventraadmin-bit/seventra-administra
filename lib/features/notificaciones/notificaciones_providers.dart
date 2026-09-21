import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../finanzas/finanzas_providers.dart';
import '../organizacion/organizacion_providers.dart';
import '../vehiculos/vehiculos_providers.dart';
import 'domain/usecases/obtener_notificaciones_complementos_usecase.dart';
import 'domain/usecases/obtener_notificaciones_cxc_usecase.dart';
import 'domain/usecases/obtener_notificaciones_documentos_por_emitir_usecase.dart';
import 'domain/usecases/obtener_notificaciones_pagos_usecase.dart';
import 'domain/usecases/obtener_notificaciones_usecase.dart';
import 'domain/usecases/obtener_notificaciones_vehiculos_usecase.dart';

/// Providers del Centro de notificaciones (Etapa 14B) — solo compone
/// use cases/repositorios ya existentes de sus dominios propios, nunca
/// declara un repositorio nuevo (mismo criterio que Reportes/
/// Dashboard/Búsqueda global). `obtenerNotificacionesVehiculosUseCaseProvider`
/// reutiliza `obtenerAlertasVehiculosUseCaseProvider` (ya existe) —
/// cero queries nuevas.
final obtenerNotificacionesVehiculosUseCaseProvider = Provider<ObtenerNotificacionesVehiculosUseCase>((ref) {
  return ObtenerNotificacionesVehiculosUseCase(ref.watch(obtenerAlertasVehiculosUseCaseProvider));
});

final obtenerNotificacionesDocumentosPorEmitirUseCaseProvider =
    Provider<ObtenerNotificacionesDocumentosPorEmitirUseCase>((ref) {
  return ObtenerNotificacionesDocumentosPorEmitirUseCase(
    ref.watch(documentoPorEmitirRepositoryProvider),
    ref.watch(clienteRepositoryProvider),
  );
});

final obtenerNotificacionesCxcUseCaseProvider = Provider<ObtenerNotificacionesCxcUseCase>((ref) {
  return ObtenerNotificacionesCxcUseCase(
    ref.watch(cuentaPorCobrarRepositoryProvider),
    ref.watch(resolverNombresContraparteUseCaseProvider),
  );
});

final obtenerNotificacionesPagosUseCaseProvider = Provider<ObtenerNotificacionesPagosUseCase>((ref) {
  return ObtenerNotificacionesPagosUseCase(
    ref.watch(pagoRepositoryProvider),
    ref.watch(resolverNombresContraparteUseCaseProvider),
  );
});

/// Complementos de pago pendientes (etapa "Complemento dependiente del
/// Pago real") — reutiliza `obtenerComplementosPendientesUseCaseProvider`
/// de Finanzas, que a su vez usa `complemento_pago_derivado.dart`. Cero
/// lógica de "pendiente" duplicada aquí.
final obtenerNotificacionesComplementosUseCaseProvider =
    Provider<ObtenerNotificacionesComplementosUseCase>((ref) {
  return ObtenerNotificacionesComplementosUseCase(
    ref.watch(obtenerComplementosPendientesUseCaseProvider),
    ref.watch(resolverNombresContraparteUseCaseProvider),
  );
});

final obtenerNotificacionesUseCaseProvider = Provider<ObtenerNotificacionesUseCase>((ref) {
  return ObtenerNotificacionesUseCase(
    ref.watch(obtenerNotificacionesVehiculosUseCaseProvider),
    ref.watch(obtenerNotificacionesDocumentosPorEmitirUseCaseProvider),
    ref.watch(obtenerNotificacionesCxcUseCaseProvider),
    ref.watch(obtenerNotificacionesPagosUseCaseProvider),
    ref.watch(obtenerNotificacionesComplementosUseCaseProvider),
  );
});
