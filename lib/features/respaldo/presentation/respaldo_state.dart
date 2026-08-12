/// Un `.zip` de respaldo ya existente en `AppPaths.backupsDir` —
/// transparencia mínima para la pantalla, sin ninguna gestión de
/// historial más allá de listar lo que hay en disco.
class ArchivoRespaldo {
  const ArchivoRespaldo({required this.nombre, required this.ruta, required this.tamanoBytes, required this.modificado});

  final String nombre;
  final String ruta;
  final int tamanoBytes;
  final DateTime modificado;
}

class RespaldoState {
  const RespaldoState({this.cargando = true, this.respaldos = const [], this.procesando = false});

  final bool cargando;
  final List<ArchivoRespaldo> respaldos;

  /// `true` mientras se crea un respaldo o se prepara una restauración
  /// — bloquea ambas acciones para no superponer dos operaciones sobre
  /// los mismos archivos.
  final bool procesando;

  RespaldoState copyWith({bool? cargando, List<ArchivoRespaldo>? respaldos, bool? procesando}) {
    return RespaldoState(
      cargando: cargando ?? this.cargando,
      respaldos: respaldos ?? this.respaldos,
      procesando: procesando ?? this.procesando,
    );
  }
}
