import 'dart:io';

/// Muestra un archivo en el Explorador de Windows.
///
/// Mismo criterio que `AbridorEnlaces`: **sin intérprete de comandos**.
/// Los argumentos viajan como lista a `explorer.exe`, así que un nombre
/// de archivo con `&`, `|` o comillas no puede convertirse en otro
/// comando. Tampoco se acepta una ruta arbitraria: sólo se abre algo
/// que existe y que es un archivo.
class AbridorUbicacion {
  const AbridorUbicacion();

  /// `true` si se lanzó el Explorador. `false` —sin lanzar— cuando la
  /// ruta no señala un archivo existente o no estamos en Windows: no
  /// poder mostrar una carpeta es un dato malo, no una falla.
  Future<bool> mostrarArchivo(String ruta) async {
    if (!Platform.isWindows) return false;
    if (ruta.trim().isEmpty) return false;
    if (!File(ruta).existsSync()) return false;

    // `/select,<ruta>` abre la carpeta contenedora con el archivo ya
    // seleccionado. Va en UN solo argumento porque así lo espera
    // `explorer.exe`; al viajar en la lista, nunca pasa por una shell.
    await Process.run('explorer.exe', ['/select,${File(ruta).absolute.path}']);
    return true;
  }
}
