import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import '../manifest_respaldo.dart';

sealed class ResultadoValidarPaqueteRespaldo {}

/// [staging] es la carpeta temporal ya extraída, con `riseg_one.sqlite`
/// y (si el respaldo tenía adjuntos) `attachments/` adentro — el
/// llamador (`PrepararRestauracionUseCase`) es responsable de moverla o
/// borrarla; este caso de uso nunca la borra en el caso exitoso.
class PaqueteRespaldoValido extends ResultadoValidarPaqueteRespaldo {
  PaqueteRespaldoValido({required this.staging, required this.manifiesto});
  final Directory staging;
  final ManifestRespaldo manifiesto;
}

/// `.zip` sin `manifest.json` válido, sin `riseg_one.sqlite`, o
/// cualquier otra forma inesperada del paquete.
class PaqueteRespaldoInvalido extends ResultadoValidarPaqueteRespaldo {
  PaqueteRespaldoInvalido(this.detalle);
  final String detalle;
}

class PaqueteRespaldoIntegridadFallida extends ResultadoValidarPaqueteRespaldo {}

/// El paquete fue creado con una versión de esquema más nueva que la
/// que esta build de RISEG ONE conoce — restaurarlo sin protección
/// dejaría a la aplicación operando sobre una forma de base de datos
/// que no entiende. Se bloquea siempre, sin excepción.
class PaqueteRespaldoVersionMasNueva extends ResultadoValidarPaqueteRespaldo {
  PaqueteRespaldoVersionMasNueva({required this.versionPaquete, required this.versionApp});
  final int versionPaquete;
  final int versionApp;
}

class PaqueteRespaldoErrorInesperado extends ResultadoValidarPaqueteRespaldo {
  PaqueteRespaldoErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Valida un `.zip` de respaldo candidato a restauración (Etapa 14C)
/// **antes** de tocar cualquier archivo vivo de la aplicación — nunca
/// abre la conexión Drift, siempre trabaja sobre una copia extraída a
/// una carpeta temporal.
class ValidarPaqueteRespaldoUseCase {
  Future<ResultadoValidarPaqueteRespaldo> ejecutar({
    required String rutaZip,
    required int appSchemaVersionActual,
  }) async {
    final staging = await Directory.systemTemp.createTemp('riseg_restauracion_');
    var stagingEntregada = false;
    try {
      try {
        await extractFileToDisk(rutaZip, staging.path);
      } catch (e) {
        return PaqueteRespaldoInvalido('El archivo no es un respaldo válido de RISEG ONE ($e).');
      }

      final manifestFile = File(p.join(staging.path, 'manifest.json'));
      final sqliteFile = File(p.join(staging.path, 'riseg_one.sqlite'));
      if (!manifestFile.existsSync() || !sqliteFile.existsSync()) {
        return PaqueteRespaldoInvalido('El paquete no contiene un respaldo completo de RISEG ONE.');
      }

      final ManifestRespaldo manifiesto;
      try {
        final json = jsonDecode(await manifestFile.readAsString()) as Map<String, dynamic>;
        final parseado = ManifestRespaldo.fromJson(json);
        if (parseado == null) return PaqueteRespaldoInvalido('El manifiesto del respaldo está dañado.');
        manifiesto = parseado;
      } catch (e) {
        return PaqueteRespaldoInvalido('El manifiesto del respaldo está dañado ($e).');
      }

      final int versionArchivo;
      final bool integridadOk;
      try {
        final db = sqlite3.open(sqliteFile.path, mode: OpenMode.readOnly);
        try {
          versionArchivo = db.userVersion;
          final chequeo = db.select('PRAGMA integrity_check');
          integridadOk = chequeo.length == 1 && chequeo.first.values.first == 'ok';
        } finally {
          db.dispose();
        }
      } catch (e) {
        return PaqueteRespaldoErrorInesperado(e.toString());
      }

      if (!integridadOk) return PaqueteRespaldoIntegridadFallida();

      if (versionArchivo > appSchemaVersionActual) {
        return PaqueteRespaldoVersionMasNueva(versionPaquete: versionArchivo, versionApp: appSchemaVersionActual);
      }

      stagingEntregada = true;
      return PaqueteRespaldoValido(staging: staging, manifiesto: manifiesto);
    } catch (e) {
      return PaqueteRespaldoErrorInesperado(e.toString());
    } finally {
      if (!stagingEntregada) {
        await staging.delete(recursive: true);
      }
    }
  }
}
