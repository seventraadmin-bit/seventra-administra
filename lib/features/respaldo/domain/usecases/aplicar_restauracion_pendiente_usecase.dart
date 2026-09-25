import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// En qué punto va una restauración a medio aplicar.
///
/// Se guarda en el marcador porque la computadora puede apagarse entre
/// dos operaciones de archivo, y al volver hay que saber cuál de los
/// dos conjuntos —el anterior o el restaurado— es el que ya está
/// instalado. Deducirlo mirando qué carpetas existen no alcanza: el
/// mismo dibujo en disco significa cosas distintas según cuándo se
/// interrumpió.
enum FaseRestauracion {
  /// El paquete está validado y en espera. Nada de lo vivo se ha
  /// tocado todavía.
  preparado,

  /// La base restaurada ya está instalada; la anterior está apartada en
  /// `restore_old`. Los adjuntos todavía son los de antes.
  baseInstalada,

  /// Base y adjuntos restaurados ya están instalados, y los anteriores
  /// apartados. Falta que el arranque confirme que la base abre.
  aplicada,
}

sealed class ResultadoAplicarRestauracion {}

/// No había ninguna restauración pendiente — el caso de cada arranque
/// normal.
class SinRestauracionPendiente extends ResultadoAplicarRestauracion {}

/// Los archivos restaurados ya están en su sitio, y los anteriores
/// siguen apartados. Quien llama debe abrir la base y después llamar a
/// `confirmar()` o a `revertir()`; hasta entonces la vuelta atrás sigue
/// disponible.
class RestauracionAplicadaPendienteConfirmar extends ResultadoAplicarRestauracion {}

/// Algo falló a mitad de la aplicación. **No se borró nada**: tanto el
/// estado anterior como el paquete siguen en disco, y [detalle] dice
/// dónde, para que una persona pueda recuperarlos a mano.
class RestauracionFallidaConEvidencia extends ResultadoAplicarRestauracion {
  RestauracionFallidaConEvidencia({required this.detalle, required this.carpetaEstadoAnterior});
  final String detalle;
  final String carpetaEstadoAnterior;
}

/// Lo instalado no coincide con lo que se validó antes de guardar el
/// paquete en espera.
///
/// Se compara **conteo y bytes**, nunca los hashes otra vez: esos ya se
/// comprobaron uno por uno al validar el `.zip`, y volver a recorrer
/// varios gigabytes en cada restauración costaría minutos para defender
/// contra alguien que, teniendo acceso al disco, podría modificar
/// `attachments/` directamente en cualquier otro momento. Lo que sí
/// puede ocurrir sin malicia —un archivo en cuarentena del antivirus,
/// una copia truncada por disco lleno, una sincronización a medias
/// mientras la aplicación estuvo cerrada— cambia el conteo o el tamaño,
/// y eso es justo lo que esto ve.
class DiscrepanciaAdjuntos {
  const DiscrepanciaAdjuntos({
    required this.archivosEsperados,
    required this.archivosEncontrados,
    required this.bytesEsperados,
    required this.bytesEncontrados,
  });

  final int archivosEsperados;
  final int archivosEncontrados;
  final int bytesEsperados;
  final int bytesEncontrados;

  @override
  String toString() =>
      'adjuntos: se esperaban $archivosEsperados archivos ($bytesEsperados bytes), '
      'hay $archivosEncontrados ($bytesEncontrados bytes)';
}

/// Aplica una restauración dejada en espera por
/// `PrepararRestauracionUseCase` — se ejecuta desde `bootstrap()`,
/// **antes** de abrir la conexión Drift, para nunca intentar sustituir
/// un archivo que la propia aplicación ya tiene abierto.
///
/// **Reentrante por diseño (Etapa 4B).** Llamarla una vez, dos o veinte,
/// con interrupciones en cualquier frontera, converge siempre al mismo
/// resultado y **nunca** deja la base restaurada junto a unos adjuntos
/// borrados.
///
/// Lo que lo garantiza es una sola regla: **jamás se borra el único
/// conjunto bueno conocido; se aparta.** Lo que se reemplaza se mueve a
/// `restore_old`, y sólo se elimina cuando el arranque confirma que la
/// base restaurada abre. Antes esta clase borraba los adjuntos vivos
/// para hacer sitio, y reentrar después de instalar los nuevos los
/// borraba a ellos: una interrupción de un segundo costaba todos los
/// documentos.
class AplicarRestauracionPendienteUseCase {
  AplicarRestauracionPendienteUseCase({
    required String databaseFile,
    required String attachmentsDir,
    required String restorePendingDir,
    required String restorePendingMarkerFile,
    required String restoreOldDir,
  }) : _databaseFile = databaseFile,
       _attachmentsDir = attachmentsDir,
       _restorePendingDir = restorePendingDir,
       _restorePendingMarkerFile = restorePendingMarkerFile,
       _restoreOldDir = restoreOldDir;

  final String _databaseFile;
  final String _attachmentsDir;
  final String _restorePendingDir;
  final String _restorePendingMarkerFile;
  final String _restoreOldDir;

  String get _baseAnterior => p.join(_restoreOldDir, 'riseg_one.sqlite');
  String get _adjuntosAnteriores => p.join(_restoreOldDir, 'attachments');

  Future<ResultadoAplicarRestauracion> ejecutar() async {
    final marcador = File(_restorePendingMarkerFile);
    if (!marcador.existsSync()) return SinRestauracionPendiente();

    try {
      var fase = await _leerFase(marcador);
      Directory(_restoreOldDir).createSync(recursive: true);

      if (fase == FaseRestauracion.preparado) {
        await _instalarBase();
        fase = FaseRestauracion.baseInstalada;
        await _escribirFase(marcador, fase);
      }

      if (fase == FaseRestauracion.baseInstalada) {
        await _instalarAdjuntos();
        fase = FaseRestauracion.aplicada;
        await _escribirFase(marcador, fase);
      }

      return RestauracionAplicadaPendienteConfirmar();
    } catch (e) {
      // Deliberadamente NO se limpia nada: el estado anterior sigue en
      // `restore_old` y el paquete en `restore_pending`. Borrar aquí
      // sería destruir justamente lo que permite recuperarse a mano.
      return RestauracionFallidaConEvidencia(detalle: e.toString(), carpetaEstadoAnterior: _restoreOldDir);
    }
  }

  /// `null` si los adjuntos instalados corresponden a lo que se validó,
  /// o si el marcador no declara ninguna expectativa.
  ///
  /// Un marcador de la Etapa 14C no la trae, y tampoco uno escrito por
  /// una preparación que no encontró adjuntos que medir. En ese caso no
  /// se inventa una respuesta: no saber no es lo mismo que estar mal.
  Future<DiscrepanciaAdjuntos?> revisarAdjuntosInstalados() async {
    final marcador = File(_restorePendingMarkerFile);
    if (!marcador.existsSync()) return null;

    final Map<String, dynamic> json;
    try {
      json = jsonDecode(await marcador.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
    final archivosEsperados = json[campoAdjuntosEsperados] as int?;
    final bytesEsperados = json[campoBytesAdjuntosEsperados] as int?;
    if (archivosEsperados == null || bytesEsperados == null) return null;

    final medida = await medirCarpeta(Directory(_attachmentsDir));
    if (medida.archivos == archivosEsperados && medida.bytes == bytesEsperados) return null;

    return DiscrepanciaAdjuntos(
      archivosEsperados: archivosEsperados,
      archivosEncontrados: medida.archivos,
      bytesEsperados: bytesEsperados,
      bytesEncontrados: medida.bytes,
    );
  }

  /// Los campos del marcador, o `null` si no hay restauración pendiente.
  ///
  /// La restauración portable (Etapa 4D) lo usa para recuperar su
  /// `restoreOperationId` tras un reinicio: el estado tiene que poder
  /// deducirse de lo que quedó escrito, nunca de marcas de tiempo ni de
  /// suposiciones sobre hasta dónde llegó la operación.
  Future<Map<String, dynamic>?> leerMarcador() async {
    final marcador = File(_restorePendingMarkerFile);
    if (!marcador.existsSync()) return null;
    try {
      return jsonDecode(await marcador.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// La restauración salió bien y la base abrió: recién ahora se puede
  /// soltar el estado anterior.
  Future<void> confirmar() async {
    await _borrarSiExiste(Directory(_restoreOldDir));
    await _borrarSiExiste(Directory(_restorePendingDir));
    final marcador = File(_restorePendingMarkerFile);
    if (marcador.existsSync()) await marcador.delete();
  }

  /// Vuelta atrás: la base restaurada no sirvió (por ejemplo, su
  /// migración falló), así que se reinstala el estado anterior.
  ///
  /// Devuelve `false` si no había estado anterior que reponer o si la
  /// reposición misma falló — en ese caso **no se borra nada** y el
  /// llamador debe reportarlo, nunca seguir como si nada.
  Future<bool> revertir() async {
    try {
      final baseAnterior = File(_baseAnterior);
      if (!baseAnterior.existsSync()) return false;
      await _mover(baseAnterior, _databaseFile);

      final adjuntosAnteriores = Directory(_adjuntosAnteriores);
      if (adjuntosAnteriores.existsSync()) {
        await _borrarSiExiste(Directory(_attachmentsDir));
        await _moverDirectorio(adjuntosAnteriores, _attachmentsDir);
      }

      await _borrarSiExiste(Directory(_restoreOldDir));
      await _borrarSiExiste(Directory(_restorePendingDir));
      final marcador = File(_restorePendingMarkerFile);
      if (marcador.existsSync()) await marcador.delete();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Instala la base restaurada apartando la anterior.
  ///
  /// Idempotente: si el archivo en espera ya no está, es que esta fase
  /// ya corrió y no hay nada que hacer. Y si el hueco de "anterior" ya
  /// está ocupado, no se pisa — lo que hay ahí es el original, y es
  /// justo lo que no se puede perder.
  Future<void> _instalarBase() async {
    final enEspera = File(p.join(_restorePendingDir, 'riseg_one.sqlite'));
    if (!enEspera.existsSync()) return;

    final viva = File(_databaseFile);
    if (viva.existsSync() && !File(_baseAnterior).existsSync()) {
      await _mover(viva, _baseAnterior);
    }
    await _mover(enEspera, _databaseFile);
  }

  /// Instala los adjuntos restaurados apartando los anteriores.
  ///
  /// Si el paquete no traía adjuntos, los actuales se apartan igual: el
  /// respaldo describe un estado completo, y dejar los viejos mezclados
  /// con una base que no los conoce sería peor que no tener ninguno.
  Future<void> _instalarAdjuntos() async {
    final enEspera = Directory(p.join(_restorePendingDir, 'attachments'));
    final vivos = Directory(_attachmentsDir);
    final anteriores = Directory(_adjuntosAnteriores);

    // Si ya se apartaron los anteriores, esta fase ya corrió: lo que
    // está vivo es el resultado restaurado y no se toca.
    if (anteriores.existsSync()) return;

    if (vivos.existsSync()) {
      await _moverDirectorio(vivos, _adjuntosAnteriores);
    } else {
      // Marca de que esta fase ya pasó, incluso sin nada que apartar.
      anteriores.createSync(recursive: true);
    }

    if (enEspera.existsSync()) {
      await _moverDirectorio(enEspera, _attachmentsDir);
    }
  }

  Future<FaseRestauracion> _leerFase(File marcador) async {
    try {
      final json = jsonDecode(await marcador.readAsString()) as Map<String, dynamic>;
      final nombre = json['fase'] as String?;
      for (final f in FaseRestauracion.values) {
        if (f.name == nombre) return f;
      }
    } catch (_) {
      // Un marcador de la Etapa 14C no tiene `fase`. Se trata como
      // recién preparado, que es lo que era: aquella versión escribía
      // el marcador justo después de dejar el paquete en espera.
    }
    return FaseRestauracion.preparado;
  }

  Future<void> _escribirFase(File marcador, FaseRestauracion fase) async {
    Map<String, dynamic> previo;
    try {
      previo = jsonDecode(await marcador.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      previo = {};
    }
    await marcador.writeAsString(jsonEncode({...previo, 'fase': fase.name}), flush: true);
  }

  Future<void> _borrarSiExiste(Directory dir) async {
    if (dir.existsSync()) await dir.delete(recursive: true);
  }

  /// `rename` falla entre unidades distintas; se intenta primero por ser
  /// instantáneo y sólo si falla se copia y se borra el original.
  Future<void> _mover(File origen, String destino) async {
    Directory(p.dirname(destino)).createSync(recursive: true);
    try {
      await origen.rename(destino);
    } on FileSystemException {
      await origen.copy(destino);
      await origen.delete();
    }
  }

  Future<void> _moverDirectorio(Directory origen, String destino) async {
    Directory(p.dirname(destino)).createSync(recursive: true);
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

/// Claves del marcador donde la preparación deja lo que el arranque
/// debe volver a encontrar. Viven aquí, junto a quien las lee, para que
/// quien las escribe no pueda renombrar una sin romper la compilación.
const campoAdjuntosEsperados = 'adjuntosEsperados';
const campoBytesAdjuntosEsperados = 'bytesAdjuntosEsperados';

/// Conteo de archivos y suma de tamaños de una carpeta, recursivo.
///
/// Compartido entre quien lo mide sobre el paquete validado y quien lo
/// vuelve a medir sobre lo ya instalado: si cada uno contara a su
/// manera, compararlos no probaría nada.
Future<({int archivos, int bytes})> medirCarpeta(Directory dir) async {
  if (!dir.existsSync()) return (archivos: 0, bytes: 0);
  var archivos = 0;
  var bytes = 0;
  await for (final entidad in dir.list(recursive: true)) {
    if (entidad is File) {
      archivos++;
      bytes += await entidad.length();
    }
  }
  return (archivos: archivos, bytes: bytes);
}
