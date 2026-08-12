import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';

import '../../domain/export/reporte_export_context.dart';

/// Arma el `ReporteExportContext` de cualquier exportación de Reportes
/// (Etapa 12D) a partir de datos ya disponibles en la sesión activa —
/// sin ninguna consulta nueva. Compartido por las 4 pestañas para no
/// repetir esta construcción 8 veces.
ReporteExportContext construirContextoExportacion(
  WidgetRef ref, {
  required String nombreReporte,
  required DateTime? rangoInicio,
  required DateTime? rangoFin,
}) {
  final sesion = ref.read(sesionControllerProvider);
  return ReporteExportContext(
    nombreReporte: nombreReporte,
    rangoInicio: rangoInicio,
    rangoFin: rangoFin,
    generadoPor: sesion?.nombre ?? '—',
    generadoEn: DateTime.now(),
  );
}
