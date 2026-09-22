import 'dart:io';

/// Abre una dirección web en el navegador del sistema, sin pasar por una
/// shell.
///
/// El proyecto abre ARCHIVOS con `cmd /c start`, y ahí la ruta la genera
/// RISEG ONE. Una URL, en cambio, la escribe la persona: mandarla a `cmd`
/// permitiría que caracteres como `&` o `|` se interpretaran como comandos.
/// `rundll32 url.dll,FileProtocolHandler` es la vía estándar de Windows para
/// abrir una dirección y **no hay intérprete de por medio**: los argumentos
/// viajan como lista, nunca como línea de comandos que alguien pueda partir.
///
/// Además sólo se abre lo que es inequívocamente una dirección web. Un
/// `file:` o un `javascript:` no se abren: no es lo que este campo guarda.
class AbridorEnlaces {
  const AbridorEnlaces();

  /// Esquemas que este campo puede contener. Deliberadamente corto.
  static const _esquemasPermitidos = {'http', 'https'};

  /// `true` si [url] es una dirección web que puede abrirse con seguridad.
  /// Es la MISMA comprobación que usa [abrir]: la pantalla la consulta para
  /// decidir si ofrece el botón, y el abridor la repite antes de actuar —
  /// esconder el botón nunca es la protección.
  static bool esAbrible(String? url) => _normalizar(url) != null;

  static Uri? _normalizar(String? url) {
    final texto = url?.trim();
    if (texto == null || texto.isEmpty) return null;
    final uri = Uri.tryParse(texto);
    if (uri == null) return null;
    if (!_esquemasPermitidos.contains(uri.scheme.toLowerCase())) return null;
    // Sin host no hay a dónde ir ("https:///algo" o "http://").
    if (uri.host.isEmpty) return null;
    return uri;
  }

  /// Abre [url] si es válida. Devuelve `false` sin lanzar cuando no lo es:
  /// una dirección mal escrita es un dato malo, no una falla del programa.
  Future<bool> abrir(String? url) async {
    final uri = _normalizar(url);
    if (uri == null) return false;
    if (!Platform.isWindows) return false;
    await Process.run('rundll32', ['url.dll,FileProtocolHandler', uri.toString()]);
    return true;
  }
}
