import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import '../manifest_respaldo.dart';

sealed class ResultadoCrearRespaldo {}

class RespaldoCreado extends ResultadoCrearRespaldo {
  RespaldoCreado({required this.rutaZip, required this.manifiesto});
  final String rutaZip;
  final ManifestRespaldo manifiesto;
}

/// `PRAGMA integrity_check` del `.sqlite` recién copiado no dio `ok` —
/// nunca se produce un `.zip` en este caso.
class RespaldoIntegridadFallida extends ResultadoCrearRespaldo {}

class RespaldoErrorInesperado extends ResultadoCrearRespaldo {
  RespaldoErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Crea un respaldo consistente de RISEG ONE (Etapa 14C) sin cerrar la
/// aplicación ni tocar la conexión Drift viva.
///
/// Usa la [Database.backup] nativa de `package:sqlite3` (API oficial de
/// respaldo en caliente de SQLite, https://www.sqlite.org/backup.html)
/// sobre una conexión de solo lectura completamente independiente de
/// Drift — copia consistente incluso si hay una escritura en curso en
/// la conexión de la app, sin necesidad de `WAL`/checkpoints ni de
/// pausar nada.
///
/// Empaqueta `riseg_one.sqlite` + [attachmentsDir] (irremplazable) +
/// `manifest.json` en un único `.zip`. Deliberadamente **excluye**
/// `AppPaths.reportesDir` (100% regenerable desde la base de datos) y la
/// clave de cifrado de Telefonía (vive en el Almacén de Credenciales de
/// Windows, nunca en un archivo — ver `credential_cipher.dart`).
///
/// Recibe rutas planas, no `AppPaths` completo — mismo criterio que
/// `AttachmentStorage`: permite probar el caso de uso con carpetas
/// temporales, sin depender de `path_provider`.
class CrearRespaldoUseCase {
  CrearRespaldoUseCase({required String databaseFile, required String attachmentsDir})
      : _databaseFile = databaseFile,
        _attachmentsDir = attachmentsDir;

  final String _databaseFile;
  final String _attachmentsDir;

  Future<ResultadoCrearRespaldo> ejecutar({required String destinoZip}) async {
    final staging = await Directory.systemTemp.createTemp('riseg_respaldo_');
    try {
      final sqliteStaging = p.join(staging.path, 'riseg_one.sqlite');

      final int appSchemaVersion;
      final bool integridadOk;
      try {
        final origen = sqlite3.open(_databaseFile, mode: OpenMode.readOnly);
        final destino = sqlite3.open(sqliteStaging);
        try {
          await origen.backup(destino).drain<void>();
          appSchemaVersion = destino.userVersion;
          final chequeo = destino.select('PRAGMA integrity_check');
          integridadOk = chequeo.length == 1 && chequeo.first.values.first == 'ok';
        } finally {
          origen.dispose();
          destino.dispose();
        }
      } catch (e) {
        return RespaldoErrorInesperado(e.toString());
      }

      if (!integridadOk) return RespaldoIntegridadFallida();

      final attachmentsDir = Directory(_attachmentsDir);
      final adjuntos =
          attachmentsDir.existsSync() ? attachmentsDir.listSync(recursive: true).whereType<File>().toList() : <File>[];
      final bytesAdjuntos = adjuntos.fold<int>(0, (total, archivo) => total + archivo.lengthSync());

      final manifiesto = ManifestRespaldo(
        formatVersion: 1,
        createdAt: DateTime.now(),
        appSchemaVersion: appSchemaVersion,
        integridadVerificada: true,
        archivosAdjuntos: adjuntos.length,
        bytesAdjuntos: bytesAdjuntos,
      );

      try {
        final encoder = ZipFileEncoder();
        encoder.create(destinoZip);
        await encoder.addFile(File(sqliteStaging), 'riseg_one.sqlite');
        // Prefijo `attachments/` fijo en el `.zip`, nunca derivado del
        // nombre real de la carpeta de origen (que `ZipFileEncoder.
        // addDirectory` usaría por defecto) — así el paquete es
        // consistente sin importar cómo esté nombrada localmente
        // `AppPaths.attachmentsDir`, y `ValidarPaqueteRespaldoUseCase`/
        // `PrepararRestauracionUseCase` pueden esperar ese prefijo con
        // total seguridad.
        for (final adjunto in adjuntos) {
          final relativo = p.relative(adjunto.path, from: attachmentsDir.path).replaceAll(r'\', '/');
          await encoder.addFile(adjunto, 'attachments/$relativo');
        }
        final manifiestoBytes = utf8.encode(jsonEncode(manifiesto.toJson()));
        encoder.addArchiveFile(ArchiveFile('manifest.json', manifiestoBytes.length, manifiestoBytes));
        await encoder.close();
      } catch (e) {
        return RespaldoErrorInesperado(e.toString());
      }

      return RespaldoCreado(rutaZip: destinoZip, manifiesto: manifiesto);
    } finally {
      await staging.delete(recursive: true);
    }
  }
}
