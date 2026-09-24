/// Las tres preguntas que deciden si una base SQLite puede usarse.
///
/// Existe para que haya **una sola definición** de "esta base está
/// sana", y no una en el validador del paquete y otra en el arranque.
/// Las dos situaciones son distintas —una mira un archivo dentro de un
/// `.zip` recién extraído, la otra la base ya instalada y migrada que
/// sostiene la aplicación— pero las preguntas son exactamente las
/// mismas, y ninguna de las dos debe poder responderlas a su manera.
///
/// Lo que NO se comparte a propósito es la **política de versión**: el
/// validador acepta cualquier `user_version` que no sea más nueva que
/// la aplicación (una vieja se migrará); el arranque, después de
/// migrar, exige igualdad exacta. Son reglas distintas porque miran
/// momentos distintos, así que este archivo devuelve el número y deja
/// que cada quien aplique la suya.
library;

/// Ejecuta un `PRAGMA` y devuelve sus filas como listas de valores.
///
/// Se recibe como función y no como conexión porque los dos llamadores
/// sostienen la base de formas incompatibles: el validador la abre de
/// sólo lectura con `package:sqlite3`, el arranque la consulta a través
/// de la conexión Drift que acaba de correr las migraciones. Obligar a
/// uno de los dos a abrir una segunda conexión sólo para compartir este
/// código sería peor que duplicarlo.
typedef ConsultaPragma = Future<List<List<Object?>>> Function(String sql);

/// Lo que se puede saber de una base sin interpretar sus datos.
class SaludBaseDatos {
  const SaludBaseDatos({required this.userVersion, required this.integridadOk, required this.referenciasOk});

  /// `PRAGMA user_version` — el número de esquema grabado en el archivo.
  final int userVersion;

  /// `PRAGMA integrity_check` devolvió exactamente `ok`.
  final bool integridadOk;

  /// `PRAGMA foreign_key_check` no devolvió ni una fila.
  ///
  /// Siempre `false` si [integridadOk] lo es: preguntar por referencias
  /// en un archivo estructuralmente roto no significa nada.
  final bool referenciasOk;

  /// Sana en todo lo que no depende de qué versión se esperaba.
  bool get sinDanos => integridadOk && referenciasOk;
}

Future<SaludBaseDatos> revisarSaludBaseDatos(ConsultaPragma consultar) async {
  final version = await consultar('PRAGMA user_version');
  final integridad = await consultar('PRAGMA integrity_check');
  final integridadOk = integridad.length == 1 && integridad.first.first == 'ok';

  // `foreign_key_check` es independiente de `integrity_check`: el
  // primero mira la estructura del archivo, este mira si los datos se
  // contradicen entre sí. Una base que abre perfectamente puede tener
  // referencias colgando. Sólo se pregunta si lo anterior dio bien,
  // porque sobre un archivo dañado la respuesta no es interpretable.
  final referencias = integridadOk ? await consultar('PRAGMA foreign_key_check') : const <List<Object?>>[];

  return SaludBaseDatos(
    userVersion: (version.first.first as int?) ?? 0,
    integridadOk: integridadOk,
    referenciasOk: integridadOk && referencias.isEmpty,
  );
}
