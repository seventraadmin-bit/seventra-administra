import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:riseg_one/core/attachments/attachment_storage.dart';

import 'exportar_reporte_resultado.dart';
import 'sanitizar_nombre_archivo.dart';

/// Escribe los bytes ya renderizados en `AppPaths.reportesDir` con un
/// nombre sanitizado, y abre el archivo con el programa predeterminado
/// del sistema (`AttachmentStorage.abrir`, mismo mecanismo que
/// Ficha técnica/Resguardo) — compartido por los 9 use cases de
/// exportación de Reportes para no repetir esta orquestación 9 veces.
Future<ExportarReporteResultado> guardarYAbrirReporte({
  required List<int> bytes,
  required String nombreBase,
  required String extension,
  required DateTime generadoEn,
  required String reportesDir,
  required AttachmentStorage attachmentStorage,
}) async {
  try {
    final directorio = Directory(reportesDir);
    await directorio.create(recursive: true);

    final nombreArchivo = sanitizarNombreArchivo(base: nombreBase, generadoEn: generadoEn, extension: extension);
    final rutaArchivo = p.join(reportesDir, nombreArchivo);
    await File(rutaArchivo).writeAsBytes(bytes);

    await attachmentStorage.abrir(rutaArchivo);

    return ExportarReporteExitoso(rutaArchivo);
  } catch (e) {
    return ExportarReporteErrorInesperado(e.toString());
  }
}
