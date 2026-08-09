import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

/// Resultado de guardar un adjunto físicamente en disco.
class ArchivoGuardado {
  const ArchivoGuardado({required this.storedFileName, required this.path, required this.sizeBytes});

  final String storedFileName;
  final String path;
  final int sizeBytes;
}

/// Almacenamiento físico de adjuntos bajo una carpeta raíz (Etapa
/// 4I.2.2) — recibe la ruta como `String` (no `AppPaths` completo) para
/// poder probarse con un directorio temporal, sin depender de
/// `path_provider`; en producción el provider la resuelve desde
/// `AppPaths.attachmentsDir`.
///
/// Regla de negocio permanente (Resolución 2 de Marlon): `storedFileName`
/// nunca deriva de `originalFileName` — se genera aquí como un UUID más
/// la extensión original, así que un nombre de archivo con caracteres
/// problemáticos, rutas incrustadas o colisiones nunca llega al disco.
/// `originalFileName` es puramente informativo para mostrarlo al
/// usuario, nunca se usa para resolver una ruta física.
class AttachmentStorage {
  AttachmentStorage(this._attachmentsDir);

  final String _attachmentsDir;

  /// Copia el archivo en `sourceFilePath` a
  /// `attachmentsDir/<ownerId>/<categoria>/<storedFileName>`. Nunca
  /// mueve ni borra el archivo origen (puede seguir abierto en otro
  /// programa, seguir siendo el archivo temporal de un selector, etc.).
  ///
  /// `ownerId` es el id del dueño del adjunto (`DocumentoPorEmitir` o,
  /// desde la Etapa 4J.2, `Pago`) — nombre genérico porque esta clase
  /// es infraestructura compartida entre dueños, no propia de ningún
  /// módulo.
  Future<ArchivoGuardado> guardar({
    required String ownerId,
    required String categoria,
    required String sourceFilePath,
    required String originalFileName,
  }) async {
    final extension = p.extension(originalFileName).toLowerCase();
    final storedFileName = '${const Uuid().v4()}$extension';
    final destinoDir = Directory(p.join(_attachmentsDir, ownerId, categoria));
    await destinoDir.create(recursive: true);
    final destinoPath = p.join(destinoDir.path, storedFileName);

    final origen = File(sourceFilePath);
    await origen.copy(destinoPath);
    final sizeBytes = await File(destinoPath).length();

    return ArchivoGuardado(storedFileName: storedFileName, path: destinoPath, sizeBytes: sizeBytes);
  }

  /// Abre un archivo con el programa predeterminado del sistema
  /// operativo (Resolución 5 de Marlon: nunca un visor propio).
  /// RISEG ONE es Windows desktop — usa el manejador nativo de Windows
  /// (`cmd /c start`) sin depender de un paquete adicional.
  Future<void> abrir(String path) async {
    if (Platform.isWindows) {
      await Process.run('cmd', ['/c', 'start', '""', path]);
    }
  }
}
