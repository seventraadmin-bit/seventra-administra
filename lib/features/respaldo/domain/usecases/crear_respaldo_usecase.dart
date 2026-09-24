import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import '../huella_archivo.dart';
import '../manifest_respaldo.dart';
import '../rutas_paquete.dart';
import 'validar_paquete_respaldo_usecase.dart';

sealed class ResultadoCrearRespaldo {}

class RespaldoCreado extends ResultadoCrearRespaldo {
  RespaldoCreado({required this.rutaZip, required this.manifiesto});
  final String rutaZip;
  final ManifestRespaldo manifiesto;
}

/// `PRAGMA integrity_check`/`foreign_key_check` del `.sqlite` recién
/// copiado no dio limpio — nunca se produce un `.zip` en este caso.
class RespaldoIntegridadFallida extends ResultadoCrearRespaldo {}

/// El paquete se escribió pero NO pasó la validación que haría
/// Restaurar. No se entrega: un respaldo que no se puede restaurar no
/// es un respaldo, y descubrirlo el día de la emergencia sería lo peor
/// que podría pasar.
class RespaldoNoSuperaValidacion extends ResultadoCrearRespaldo {}

/// No se pudo escribir en el destino: unidad desconectada, sin espacio,
/// sin permisos. [detalle] es para registro, nunca para mostrarse tal
/// cual.
class RespaldoDestinoNoDisponible extends ResultadoCrearRespaldo {
  RespaldoDestinoNoDisponible(this.detalle);
  final String detalle;
}

class RespaldoErrorInesperado extends ResultadoCrearRespaldo {
  RespaldoErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Crea un respaldo consistente de RISEG ONE sin cerrar la aplicación ni
/// tocar la conexión Drift viva.
///
/// Usa la [Database.backup] nativa de `package:sqlite3` (API oficial de
/// respaldo en caliente de SQLite, https://www.sqlite.org/backup.html)
/// sobre una conexión de solo lectura completamente independiente de
/// Drift — copia consistente incluso si hay una escritura en curso en
/// la conexión de la app, sin necesidad de `WAL`/checkpoints ni de
/// pausar nada.
///
/// Empaqueta `riseg_one.sqlite` + [attachmentsDir] (irremplazable) +
/// `manifest.json` en un único `.zip`. Deliberadamente **excluye** las
/// carpetas de documentos regenerables (`reportes`, `recibos`,
/// `nomina_dispersion`, `datos_fiscales`: todos se vuelven a producir
/// desde la base) y la clave de cifrado de credenciales, que vive en el
/// Almacén de Credenciales de Windows y nunca en un archivo — ver
/// `credential_cipher.dart`.
///
/// **Etapa 4B — tres garantías nuevas:**
///
///  1. se escribe a un archivo temporal y sólo al final se renombra al
///     nombre definitivo, así un fallo a media escritura no deja un
///     `.zip` con aspecto de respaldo bueno;
///  2. cada archivo irremplazable viaja con su tamaño y su SHA-256;
///  3. el paquete terminado se valida con el MISMO validador que usa
///     Restaurar antes de darse por bueno.
class CrearRespaldoUseCase {
  CrearRespaldoUseCase({
    required String databaseFile,
    required String attachmentsDir,
    ValidarPaqueteRespaldoUseCase? validador,
  }) : _databaseFile = databaseFile,
       _attachmentsDir = attachmentsDir,
       _validador = validador ?? ValidarPaqueteRespaldoUseCase();

  final String _databaseFile;
  final String _attachmentsDir;
  final ValidarPaqueteRespaldoUseCase _validador;

  /// Sufijo del archivo mientras se construye. Si algo interrumpe la
  /// creación y no se puede limpiar, lo que queda en disco lleva este
  /// nombre: nadie lo confundirá con un respaldo utilizable.
  static const sufijoParcial = '.parcial';

  Future<ResultadoCrearRespaldo> ejecutar({required String destinoZip, TipoRespaldo tipo = TipoRespaldo.manual}) async {
    final staging = await Directory.systemTemp.createTemp('riseg_respaldo_');
    final parcial = File('$destinoZip$sufijoParcial');
    try {
      final sqliteStaging = p.join(staging.path, RutasPaquete.nombreBaseDatos);

      final int appSchemaVersion;
      final bool integridadOk;
      try {
        final origen = sqlite3.open(_databaseFile, mode: OpenMode.readOnly);
        final destino = sqlite3.open(sqliteStaging);
        try {
          await origen.backup(destino).drain<void>();
          appSchemaVersion = destino.userVersion;
          final chequeo = destino.select('PRAGMA integrity_check');
          final estructuraOk = chequeo.length == 1 && chequeo.first.values.first == 'ok';
          integridadOk = estructuraOk && destino.select('PRAGMA foreign_key_check').isEmpty;
        } finally {
          origen.dispose();
          destino.dispose();
        }
      } catch (e) {
        return RespaldoErrorInesperado(e.toString());
      }

      if (!integridadOk) return RespaldoIntegridadFallida();

      final copiaBase = File(sqliteStaging);
      final baseDatos = ArchivoRespaldado(
        rutaRelativa: RutasPaquete.nombreBaseDatos,
        bytes: await copiaBase.length(),
        sha256: await sha256DeArchivo(copiaBase),
      );

      final attachmentsDir = Directory(_attachmentsDir);
      final adjuntos = <({File archivo, ArchivoRespaldado descripcion})>[];
      if (attachmentsDir.existsSync()) {
        for (final archivo in attachmentsDir.listSync(recursive: true).whereType<File>()) {
          final relativa = p.relative(archivo.path, from: attachmentsDir.path).replaceAll(r'\', '/');
          adjuntos.add((
            archivo: archivo,
            descripcion: ArchivoRespaldado(
              rutaRelativa: relativa,
              bytes: await archivo.length(),
              sha256: await sha256DeArchivo(archivo),
            ),
          ));
        }
      }

      final manifiesto = ManifestRespaldo(
        formatVersion: ManifestRespaldo.versionActual,
        createdAt: DateTime.now(),
        appSchemaVersion: appSchemaVersion,
        capacidades: const {ManifestRespaldo.capacidadIntegridad},
        tipo: tipo,
        baseDatos: baseDatos,
        adjuntos: [for (final a in adjuntos) a.descripcion],
      );

      try {
        if (parcial.existsSync()) await parcial.delete();
        parcial.parent.createSync(recursive: true);
        final encoder = ZipFileEncoder();
        encoder.create(parcial.path);
        await encoder.addFile(copiaBase, RutasPaquete.nombreBaseDatos);
        // Prefijo `attachments/` fijo en el `.zip`, nunca derivado del
        // nombre real de la carpeta de origen — así el paquete es
        // consistente sin importar cómo esté nombrada localmente, y el
        // validador puede esperar ese prefijo con total seguridad.
        for (final adjunto in adjuntos) {
          await encoder.addFile(adjunto.archivo, '${RutasPaquete.prefijoAdjuntos}${adjunto.descripcion.rutaRelativa}');
        }
        final manifiestoBytes = utf8.encode(jsonEncode(manifiesto.toJson()));
        encoder.addArchiveFile(ArchiveFile(RutasPaquete.nombreManifiesto, manifiestoBytes.length, manifiestoBytes));
        await encoder.close();
      } catch (e) {
        await _borrarSiSePuede(parcial);
        return RespaldoDestinoNoDisponible(e.toString());
      }

      // El paquete se juzga con la misma vara que usará Restaurar. Si
      // no pasa, no se entrega y no queda con nombre definitivo.
      final validacion = await _validador.ejecutar(rutaZip: parcial.path, appSchemaVersionActual: appSchemaVersion);
      if (validacion is PaqueteRespaldoValido) {
        await validacion.staging.delete(recursive: true);
      } else {
        await _borrarSiSePuede(parcial);
        return RespaldoNoSuperaValidacion();
      }

      try {
        final definitivo = File(destinoZip);
        if (definitivo.existsSync()) await definitivo.delete();
        await parcial.rename(destinoZip);
      } catch (e) {
        await _borrarSiSePuede(parcial);
        return RespaldoDestinoNoDisponible(e.toString());
      }

      return RespaldoCreado(rutaZip: destinoZip, manifiesto: manifiesto);
    } catch (e) {
      await _borrarSiSePuede(parcial);
      return RespaldoErrorInesperado(e.toString());
    } finally {
      if (staging.existsSync()) await staging.delete(recursive: true);
    }
  }

  /// Si no se puede borrar el temporal (la unidad se desconectó), se
  /// deja: lleva `.parcial` en el nombre y no engaña a nadie.
  Future<void> _borrarSiSePuede(File archivo) async {
    try {
      if (archivo.existsSync()) await archivo.delete();
    } catch (_) {}
  }
}
