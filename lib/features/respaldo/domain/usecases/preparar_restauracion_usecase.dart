import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../manifest_respaldo.dart';
import 'aplicar_restauracion_pendiente_usecase.dart';
import 'crear_respaldo_usecase.dart';
import 'validar_paquete_respaldo_usecase.dart';

sealed class ResultadoPrepararRestauracion {}

/// El paquete quedó validado y en espera en `AppPaths.restorePendingDir`
/// — `bootstrap()` lo aplicará en el próximo arranque, antes de abrir la
/// base de datos. La aplicación debe cerrarse para completar la
/// restauración (no hay mecanismo de recarga en caliente de la conexión
/// Drift).
class RestauracionPreparada extends ResultadoPrepararRestauracion {}

class RestauracionPaqueteInvalido extends ResultadoPrepararRestauracion {
  RestauracionPaqueteInvalido(this.motivo);
  final MotivoPaqueteInvalido motivo;
}

class RestauracionIntegridadFallida extends ResultadoPrepararRestauracion {}

class RestauracionVersionMasNueva extends ResultadoPrepararRestauracion {
  RestauracionVersionMasNueva({required this.versionPaquete, required this.versionApp});
  final int versionPaquete;
  final int versionApp;
}

/// El respaldo preventivo automático (paso previo obligatorio, ver
/// [PrepararRestauracionUseCase]) falló — la restauración se aborta por
/// completo sin tocar nada más, nunca se restaura sin esa red de
/// seguridad.
class RestauracionRespaldoPreventivoFallido extends ResultadoPrepararRestauracion {
  RestauracionRespaldoPreventivoFallido(this.detalle);
  final String detalle;
}

class RestauracionErrorInesperado extends ResultadoPrepararRestauracion {
  RestauracionErrorInesperado(this.mensaje);
  final String mensaje;
}

/// Orquesta la preparación de una restauración (Etapa 14C): valida el
/// paquete elegido, crea un respaldo preventivo automático del estado
/// actual, y deja el paquete validado listo en [restorePendingDir] para
/// que `bootstrap()` lo aplique en el siguiente arranque. Nunca
/// reemplaza ningún archivo vivo directamente.
///
/// Recibe rutas planas, no `AppPaths` completo — mismo criterio que
/// [CrearRespaldoUseCase].
class PrepararRestauracionUseCase {
  PrepararRestauracionUseCase({
    required String backupsDir,
    required String restorePendingDir,
    required String restorePendingMarkerFile,
    required ValidarPaqueteRespaldoUseCase validar,
    required CrearRespaldoUseCase crearRespaldo,
  }) : _backupsDir = backupsDir,
       _restorePendingDir = restorePendingDir,
       _restorePendingMarkerFile = restorePendingMarkerFile,
       _validar = validar,
       _crearRespaldo = crearRespaldo;

  final String _backupsDir;
  final String _restorePendingDir;
  final String _restorePendingMarkerFile;
  final ValidarPaqueteRespaldoUseCase _validar;
  final CrearRespaldoUseCase _crearRespaldo;

  /// [datosExtra] se mezcla en el marcador. Lo usa la restauración
  /// portable (Etapa 4D) para dejar ahí su `restoreOperationId` y el
  /// `keyId` que espera encontrar promovido, de modo que un arranque
  /// posterior pueda correlacionar el marcador con el respaldo
  /// preventivo y con las ranuras de clave sin depender de nombres de
  /// archivo.
  Future<ResultadoPrepararRestauracion> ejecutar({
    required String rutaZip,
    required int appSchemaVersionActual,
    Map<String, dynamic> datosExtra = const {},
  }) async {
    final validacion = await _validar.ejecutar(rutaZip: rutaZip, appSchemaVersionActual: appSchemaVersionActual);

    switch (validacion) {
      case PaqueteRespaldoInvalido(:final motivo):
        return RestauracionPaqueteInvalido(motivo);
      case PaqueteRespaldoIntegridadFallida():
        return RestauracionIntegridadFallida();
      case PaqueteRespaldoVersionMasNueva(:final versionPaquete, :final versionApp):
        return RestauracionVersionMasNueva(versionPaquete: versionPaquete, versionApp: versionApp);
      case PaqueteRespaldoErrorInesperado(:final mensaje):
        return RestauracionErrorInesperado(mensaje);
      case PaqueteRespaldoValido(:final staging):
        return _continuar(staging, datosExtra);
    }
  }

  Future<ResultadoPrepararRestauracion> _continuar(Directory staging, Map<String, dynamic> datosExtra) async {
    try {
      final marcaTiempo = DateTime.now().toIso8601String().replaceAll(RegExp('[:.]'), '-');
      Directory(_backupsDir).createSync(recursive: true);
      final respaldoPreventivo = await _crearRespaldo.ejecutar(
        destinoZip: p.join(_backupsDir, 'pre-restore-$marcaTiempo.zip'),
        // Queda marcado en su propio manifiesto: la lista lo distingue
        // de un respaldo manual sin tener que adivinarlo del nombre.
        tipo: TipoRespaldo.preventivo,
      );
      switch (respaldoPreventivo) {
        case RespaldoNoSuperaValidacion():
          return RestauracionRespaldoPreventivoFallido(
            'El respaldo preventivo del estado actual no superó su propia verificación.',
          );
        case RespaldoDestinoNoDisponible(:final detalle):
          return RestauracionRespaldoPreventivoFallido(detalle);
        case RespaldoIntegridadFallida():
          return RestauracionRespaldoPreventivoFallido(
            'No fue posible verificar la integridad del estado actual antes de restaurar.',
          );
        case RespaldoErrorInesperado(:final mensaje):
          return RestauracionRespaldoPreventivoFallido(mensaje);
        case RespaldoCreado():
          break;
      }

      final restorePendingDir = Directory(_restorePendingDir);
      if (restorePendingDir.existsSync()) {
        await restorePendingDir.delete(recursive: true);
      }
      restorePendingDir.createSync(recursive: true);

      final sqliteStaged = File(p.join(staging.path, 'riseg_one.sqlite'));
      await _moverArchivo(sqliteStaged, p.join(restorePendingDir.path, 'riseg_one.sqlite'));

      final attachmentsStaged = Directory(p.join(staging.path, 'attachments'));
      if (attachmentsStaged.existsSync()) {
        await _moverDirectorio(attachmentsStaged, p.join(restorePendingDir.path, 'attachments'));
      }

      // Se mide lo que quedó en espera, no lo que el manifiesto dice
      // que debería haber: estos son exactamente los archivos cuyos
      // hashes acaban de comprobarse uno por uno, y son los que el
      // arranque tendrá que volver a encontrar intactos.
      final medida = await medirCarpeta(Directory(p.join(restorePendingDir.path, 'attachments')));

      final marcador = File(_restorePendingMarkerFile);
      await marcador.writeAsString(
        jsonEncode({
          'preparedAt': DateTime.now().toIso8601String(),
          // La fase inicial viaja desde el primer momento: el arranque
          // nunca tiene que deducir en qué punto quedó todo.
          'fase': FaseRestauracion.preparado.name,
          campoAdjuntosEsperados: medida.archivos,
          campoBytesAdjuntosEsperados: medida.bytes,
          ...datosExtra,
        }),
        flush: true,
      );

      return RestauracionPreparada();
    } catch (e) {
      return RestauracionErrorInesperado(e.toString());
    } finally {
      if (staging.existsSync()) {
        await staging.delete(recursive: true);
      }
    }
  }

  /// `File.rename` falla si [origen] y [destino] viven en unidades
  /// distintas (posible: la carpeta temporal del sistema no siempre
  /// comparte unidad con la carpeta de datos de la aplicación) — se
  /// intenta primero por ser instantáneo, y solo si falla se recurre a
  /// copiar y borrar el original.
  Future<void> _moverArchivo(File origen, String destino) async {
    try {
      await origen.rename(destino);
    } on FileSystemException {
      await origen.copy(destino);
      await origen.delete();
    }
  }

  Future<void> _moverDirectorio(Directory origen, String destino) async {
    try {
      await origen.rename(destino);
    } on FileSystemException {
      await for (final entidad in origen.list(recursive: true)) {
        final relativo = p.relative(entidad.path, from: origen.path);
        final destinoEntidad = p.join(destino, relativo);
        if (entidad is Directory) {
          await Directory(destinoEntidad).create(recursive: true);
        } else if (entidad is File) {
          await Directory(p.dirname(destinoEntidad)).create(recursive: true);
          await entidad.copy(destinoEntidad);
        }
      }
      await origen.delete(recursive: true);
    }
  }
}
