import 'dart:io';

import 'package:drift/native.dart';

import '../../../../core/database/app_database.dart';

/// En qué situación está esta instalación de cara a una restauración
/// portable (Etapa 4D).
enum EstadoInstalacion {
  /// **No hay aquí nada que una restauración pueda destruir.** Es la
  /// única situación que habilita la recuperación sin sesión.
  vaciaSegura,

  /// Hay datos, o una restauración a medio aplicar. Restaurar exige
  /// Maestro local **además** de la credencial del paquete.
  existente,

  /// No se pudo comprobar algo. **Nunca** habilita pre-auth: ante la
  /// duda se protegen los datos, que es la única respuesta que no puede
  /// salir cara.
  indeterminada,
}

/// Decide si una instalación está realmente vacía (Etapa 4D).
///
/// El giro que hace esto seguro es la pregunta. No se responde *"¿es una
/// instalación nueva?"* —que no tiene respuesta fiable— sino **"¿hay
/// aquí algo que una restauración pueda destruir?"**. Si no hay nada,
/// restaurar no puede perder nada, y la posesión del archivo más la
/// credencial es autoridad suficiente.
///
/// `contarUsuarios() == 0` **no basta**: una base dañada, o una
/// restauración a medio aplicar, puede tener cero usuarios y a la vez
/// contener el trabajo de años.
///
/// ## Cómo se decide que no hay nada
///
/// La comparación **no** usa una lista de tablas escrita a mano. Se
/// construye una base recién creada en memoria —el estado exacto de
/// fábrica, con sus catálogos sembrados— y se comparan los conteos de
/// filas de **todas** las tablas del esquema. Si alguno difiere, alguien
/// ha usado esta instalación.
///
/// Se eligió así después de que una lista a mano se quedara corta en el
/// primer intento: omitía `empresa`, que el sembrado crea. Una
/// clasificación que hay que recordar actualizar es una clasificación
/// que algún día no se actualiza, y el precio de olvidarla aquí es
/// sobrescribir los datos de alguien sin pedirle nada. Derivarla del
/// esquema vivo hace que **cualquier tabla futura quede cubierta sola**,
/// y que el error posible sea sólo el inofensivo: declarar "existente"
/// una instalación que estaba vacía.
class EvaluadorInstalacion {
  const EvaluadorInstalacion({
    required AppDatabase db,
    required String attachmentsDir,
    required String restorePendingDir,
    required String restorePendingMarkerFile,
    required String restoreOldDir,
    Future<Map<String, int>> Function()? conteosDeFabrica,
  }) : _db = db,
       _attachmentsDir = attachmentsDir,
       _restorePendingDir = restorePendingDir,
       _restorePendingMarkerFile = restorePendingMarkerFile,
       _restoreOldDir = restoreOldDir,
       _conteosDeFabrica = conteosDeFabrica;

  final AppDatabase _db;
  final String _attachmentsDir;
  final String _restorePendingDir;
  final String _restorePendingMarkerFile;
  final String _restoreOldDir;

  /// Inyectable para las pruebas, que no quieren pagar la creación de un
  /// esquema completo en cada caso. En producción se calcula.
  final Future<Map<String, int>> Function()? _conteosDeFabrica;

  Future<EstadoInstalacion> evaluar() async {
    try {
      // 1. Cualquier rastro de una restauración en curso descalifica de
      //    inmediato: los datos de verdad pueden estar apartados.
      if (File(_restorePendingMarkerFile).existsSync()) return EstadoInstalacion.existente;
      if (Directory(_restorePendingDir).existsSync()) return EstadoInstalacion.existente;
      if (Directory(_restoreOldDir).existsSync()) return EstadoInstalacion.existente;

      // 2. Un solo adjunto ya es trabajo irremplazable.
      final adjuntos = Directory(_attachmentsDir);
      if (adjuntos.existsSync() && adjuntos.listSync(recursive: true).whereType<File>().isNotEmpty) {
        return EstadoInstalacion.existente;
      }

      // 3. Ninguna tabla puede tener más filas que una instalación de
      //    fábrica.
      final fabrica = await (_conteosDeFabrica?.call() ?? conteosDeInstalacionDeFabrica());
      final actuales = await conteosDe(_db);

      // Una tabla que existe aquí y no en la referencia significa que no
      // se pudo comparar: no se afirma que esté vacía.
      for (final tabla in actuales.keys) {
        final esperado = fabrica[tabla];
        if (esperado == null) return EstadoInstalacion.indeterminada;
        if (actuales[tabla] != esperado) return EstadoInstalacion.existente;
      }
      if (fabrica.keys.any((t) => !actuales.containsKey(t))) return EstadoInstalacion.indeterminada;

      return EstadoInstalacion.vaciaSegura;
    } catch (_) {
      // Una base que no se deja consultar es exactamente el caso en que
      // no se puede afirmar que esté vacía.
      return EstadoInstalacion.indeterminada;
    }
  }

  /// Conteo de filas de cada tabla del esquema.
  static Future<Map<String, int>> conteosDe(AppDatabase db) async {
    final conteos = <String, int>{};
    for (final tabla in db.allTables) {
      final nombre = tabla.actualTableName;
      final fila = await db.customSelect('SELECT COUNT(*) AS n FROM "$nombre"').getSingle();
      conteos[nombre] = fila.data['n'] as int;
    }
    return conteos;
  }

  /// Los conteos de una instalación recién creada: se abre una base en
  /// memoria, que dispara `onCreate` y el sembrado de catálogos.
  static Future<Map<String, int>> conteosDeInstalacionDeFabrica() async {
    final referencia = AppDatabase(NativeDatabase.memory());
    try {
      await referencia.customSelect('SELECT 1').get();
      await referencia.ensureMetadata(appVersion: 'referencia');
      return await conteosDe(referencia);
    } finally {
      await referencia.close();
    }
  }
}
