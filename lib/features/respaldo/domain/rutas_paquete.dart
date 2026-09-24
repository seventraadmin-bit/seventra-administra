import 'package:path/path.dart' as p;

/// Reglas de qué ruta puede venir dentro de un paquete de respaldo
/// (Etapa 4B).
///
/// Un `.zip` es contenido ajeno: puede haberlo escrito cualquiera. Una
/// entrada llamada `../../Windows/System32/algo.dll` o `C:\algo` haría
/// que extraerlo escribiera FUERA de la carpeta temporal. Este
/// contenedor no confía en la librería de ZIP para evitarlo: comprueba
/// cada nombre antes de tocar el disco.
class RutasPaquete {
  const RutasPaquete._();

  /// Carpeta, dentro del paquete, donde viven los adjuntos.
  static const prefijoAdjuntos = 'attachments/';

  /// Nombre de la base de datos dentro del paquete.
  static const nombreBaseDatos = 'riseg_one.sqlite';

  /// Nombre del manifiesto dentro del paquete.
  static const nombreManifiesto = 'manifest.json';

  /// `true` si [ruta] puede extraerse con seguridad dentro del staging.
  ///
  /// Rechaza, en este orden:
  ///  * vacía o sólo espacios;
  ///  * separador invertido de Windows (`\`), que `path` no interpreta
  ///    como separador en POSIX y podría colarse dentro de un segmento;
  ///  * cualquier forma absoluta —`/x`, `C:\x`, `\\servidor\x`—;
  ///  * cualquier segmento `..`, esté donde esté;
  ///  * una ruta que, ya normalizada, siga saliendo del staging.
  static bool esSegura(String ruta) {
    if (ruta.trim().isEmpty) return false;
    if (ruta.contains(r'\')) return false;
    if (ruta.startsWith('/')) return false;
    // Letra de unidad (`C:`, `c:/…`) o UNC.
    if (RegExp(r'^[A-Za-z]:').hasMatch(ruta)) return false;
    if (ruta.startsWith('//')) return false;

    final segmentos = ruta.split('/');
    if (segmentos.any((s) => s == '..')) return false;
    // Un segmento vacío intermedio (`a//b`) o final (`a/`) describe algo
    // que no es un archivo.
    if (segmentos.any((s) => s.isEmpty)) return false;

    // Última red: normalizar y comprobar que no escapa.
    final normalizada = p.posix.normalize(ruta);
    if (normalizada.startsWith('..') || p.posix.isAbsolute(normalizada)) return false;

    return true;
  }

  /// La ruta de un adjunto **relativa a la carpeta de adjuntos**, o
  /// `null` si [rutaEnPaquete] no es un adjunto seguro.
  static String? adjuntoRelativo(String rutaEnPaquete) {
    if (!rutaEnPaquete.startsWith(prefijoAdjuntos)) return null;
    final relativa = rutaEnPaquete.substring(prefijoAdjuntos.length);
    if (!esSegura(relativa)) return null;
    return relativa;
  }
}
