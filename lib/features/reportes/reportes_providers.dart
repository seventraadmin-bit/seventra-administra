import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/providers.dart';
import '../compras/compras_providers.dart';
import '../finanzas/finanzas_providers.dart';
import '../inventario/inventario_providers.dart';
import '../nomina/nomina_providers.dart';
import '../organizacion/organizacion_providers.dart';
import '../personal/personal_providers.dart';
import '../telefonia/telefonia_providers.dart';
import '../vehiculos/vehiculos_providers.dart';
import 'data/pdf/reporte_finanzas_pdf_renderer.dart';
import 'data/pdf/reporte_general_pdf_renderer.dart';
import 'data/xlsx/compras_periodo_xlsx_renderer.dart';
import 'data/xlsx/finanzas_egresos_xlsx_renderer.dart';
import 'data/xlsx/nomina_periodo_xlsx_renderer.dart';
import 'data/xlsx/personal_eventos_xlsx_renderer.dart';
import 'data/xlsx/telefonia_recargas_xlsx_renderer.dart';
import 'data/xlsx/vehiculos_mantenimiento_xlsx_renderer.dart';
import 'domain/usecases/clasificar_egresos_por_origen_usecase.dart';
import 'domain/usecases/exportar_compras_periodo_xlsx_usecase.dart';
import 'domain/usecases/exportar_finanzas_egresos_xlsx_usecase.dart';
import 'domain/usecases/exportar_nomina_periodo_xlsx_usecase.dart';
import 'domain/usecases/exportar_personal_eventos_xlsx_usecase.dart';
import 'domain/usecases/exportar_reporte_finanzas_pdf_usecase.dart';
import 'domain/usecases/exportar_reporte_general_pdf_usecase.dart';
import 'domain/usecases/exportar_telefonia_recargas_xlsx_usecase.dart';
import 'domain/usecases/exportar_vehiculos_mantenimiento_xlsx_usecase.dart';
import 'domain/usecases/obtener_resumen_compras_usecase.dart';
import 'domain/usecases/obtener_resumen_general_usecase.dart';
import 'domain/usecases/obtener_resumen_inventario_usecase.dart';
import 'domain/usecases/obtener_resumen_nomina_usecase.dart';
import 'domain/usecases/obtener_resumen_personal_usecase.dart';
import 'domain/usecases/obtener_resumen_telefonia_usecase.dart';
import 'domain/usecases/obtener_resumen_vehiculos_usecase.dart';

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

/// Etapa 12C — Operación (Compras · Inventario · Vehículos · Telefonía).
final obtenerResumenComprasUseCaseProvider = Provider<ObtenerResumenComprasUseCase>((ref) {
  return ObtenerResumenComprasUseCase(ref.watch(compraRepositoryProvider), ref.watch(articuloRepositoryProvider));
});

final obtenerResumenInventarioUseCaseProvider = Provider<ObtenerResumenInventarioUseCase>((ref) {
  return ObtenerResumenInventarioUseCase(
    ref.watch(articuloRepositoryProvider),
    ref.watch(inventarioRepositoryProvider),
    ref.watch(asignacionRepositoryProvider),
  );
});

final obtenerResumenVehiculosUseCaseProvider = Provider<ObtenerResumenVehiculosUseCase>((ref) {
  return ObtenerResumenVehiculosUseCase(
    ref.watch(obtenerAlertasVehiculosUseCaseProvider),
    ref.watch(vehiculoMantenimientoRepositoryProvider),
    ref.watch(vehiculoRepositoryProvider),
  );
});

/// Nunca depende de `EquipoTelefonicoRepository` — regla dura de
/// Reportes en Telefonía, ver el doc comment de
/// `ObtenerResumenTelefoniaUseCase`.
final obtenerResumenTelefoniaUseCaseProvider = Provider<ObtenerResumenTelefoniaUseCase>((ref) {
  return ObtenerResumenTelefoniaUseCase(
    ref.watch(inventarioRepositoryProvider),
    ref.watch(lineaTelefonicaRepositoryProvider),
    ref.watch(lineaTelefonicaEquipoRepositoryProvider),
    ref.watch(asignacionLineaTelefonicaRepositoryProvider),
    ref.watch(recargaLineaTelefonicaRepositoryProvider),
    ref.watch(empleadoRepositoryProvider),
    ref.watch(servicioRepositoryProvider),
  );
});

/// Etapa 12D — Exportación. Cada use case recibe su renderer puro (sin
/// estado propio, se construye una sola vez), `AttachmentStorage` (solo
/// para `abrir`, nunca `guardar` — estos documentos no tienen dueño de
/// negocio) y `AppPaths.reportesDir`.
final exportarReporteGeneralPdfUseCaseProvider = Provider<ExportarReporteGeneralPdfUseCase>((ref) {
  return ExportarReporteGeneralPdfUseCase(
    ReporteGeneralPdfRenderer(),
    ref.watch(empresaRepositoryProvider),
    ref.watch(attachmentRepositoryProvider),
    ref.watch(attachmentStorageProvider),
    ref.watch(appPathsProvider).reportesDir,
  );
});

final exportarReporteFinanzasPdfUseCaseProvider = Provider<ExportarReporteFinanzasPdfUseCase>((ref) {
  return ExportarReporteFinanzasPdfUseCase(
    ReporteFinanzasPdfRenderer(),
    ref.watch(empresaRepositoryProvider),
    ref.watch(attachmentRepositoryProvider),
    ref.watch(attachmentStorageProvider),
    ref.watch(appPathsProvider).reportesDir,
  );
});

final exportarFinanzasEgresosXlsxUseCaseProvider = Provider<ExportarFinanzasEgresosXlsxUseCase>((ref) {
  return ExportarFinanzasEgresosXlsxUseCase(
    FinanzasEgresosXlsxRenderer(),
    ref.watch(attachmentStorageProvider),
    ref.watch(appPathsProvider).reportesDir,
  );
});

final exportarPersonalEventosXlsxUseCaseProvider = Provider<ExportarPersonalEventosXlsxUseCase>((ref) {
  return ExportarPersonalEventosXlsxUseCase(
    PersonalEventosXlsxRenderer(),
    ref.watch(attachmentStorageProvider),
    ref.watch(appPathsProvider).reportesDir,
  );
});

final exportarNominaPeriodoXlsxUseCaseProvider = Provider<ExportarNominaPeriodoXlsxUseCase>((ref) {
  return ExportarNominaPeriodoXlsxUseCase(
    NominaPeriodoXlsxRenderer(),
    ref.watch(attachmentStorageProvider),
    ref.watch(appPathsProvider).reportesDir,
  );
});

final exportarComprasPeriodoXlsxUseCaseProvider = Provider<ExportarComprasPeriodoXlsxUseCase>((ref) {
  return ExportarComprasPeriodoXlsxUseCase(
    ComprasPeriodoXlsxRenderer(),
    ref.watch(attachmentStorageProvider),
    ref.watch(appPathsProvider).reportesDir,
  );
});

final exportarVehiculosMantenimientoXlsxUseCaseProvider = Provider<ExportarVehiculosMantenimientoXlsxUseCase>((ref) {
  return ExportarVehiculosMantenimientoXlsxUseCase(
    VehiculosMantenimientoXlsxRenderer(),
    ref.watch(attachmentStorageProvider),
    ref.watch(appPathsProvider).reportesDir,
  );
});

/// Nunca depende de `EquipoTelefonicoRepository` — misma regla dura que
/// `obtenerResumenTelefoniaUseCaseProvider`.
final exportarTelefoniaRecargasXlsxUseCaseProvider = Provider<ExportarTelefoniaRecargasXlsxUseCase>((ref) {
  return ExportarTelefoniaRecargasXlsxUseCase(
    TelefoniaRecargasXlsxRenderer(),
    ref.watch(attachmentStorageProvider),
    ref.watch(appPathsProvider).reportesDir,
  );
});
