import '../domain/manifest_respaldo.dart';

/// Qué se sabe hoy sobre la integridad de un respaldo de la lista.
enum EstadoIntegridad {
  /// Se verificó byte a byte y todo coincide — porque se acaba de crear
  /// o porque alguien pulsó "Verificar integridad".
  verificado,

  /// Formato anterior: la base se puede comprobar, los adjuntos no.
  /// Nunca debe presentarse como "verificado".
  limitada,

  /// Se verificó y NO pasó.
  invalido,

  /// Todavía no se ha verificado. Es el estado honesto por omisión: la
  /// lista no abre ni recorre cada `.zip` al pintarse.
  sinVerificar,
}

/// Un `.zip` de respaldo presente en `AppPaths.backupsDir`.
///
/// Los campos que vienen del manifiesto ([tipo], [formatVersion],
/// [appSchemaVersion]) se leen abriendo **sólo** esa entrada del `.zip`,
/// nunca extrayendo el paquete entero: la lista tiene que abrirse
/// rápido aunque cada respaldo pese cientos de megabytes.
class ArchivoRespaldo {
  const ArchivoRespaldo({
    required this.nombre,
    required this.ruta,
    required this.tamanoBytes,
    required this.modificado,
    this.tipo,
    this.formatVersion,
    this.appSchemaVersion,
    this.archivosAdjuntos,
    this.integridad = EstadoIntegridad.sinVerificar,
  });

  final String nombre;
  final String ruta;
  final int tamanoBytes;
  final DateTime modificado;

  /// `null` si el manifiesto no pudo leerse — un archivo `.zip` que no
  /// es un respaldo, o que está dañado.
  final TipoRespaldo? tipo;
  final int? formatVersion;
  final int? appSchemaVersion;
  final int? archivosAdjuntos;

  final EstadoIntegridad integridad;

  bool get esFormatoAnterior => formatVersion != null && formatVersion! < ManifestRespaldo.versionActual;

  ArchivoRespaldo copyWith({EstadoIntegridad? integridad}) => ArchivoRespaldo(
    nombre: nombre,
    ruta: ruta,
    tamanoBytes: tamanoBytes,
    modificado: modificado,
    tipo: tipo,
    formatVersion: formatVersion,
    appSchemaVersion: appSchemaVersion,
    archivosAdjuntos: archivosAdjuntos,
    integridad: integridad ?? this.integridad,
  );
}

class RespaldoState {
  const RespaldoState({this.cargando = true, this.respaldos = const [], this.procesando = false});

  final bool cargando;
  final List<ArchivoRespaldo> respaldos;

  /// `true` mientras se crea, verifica o restaura — bloquea las acciones
  /// para no superponer dos operaciones sobre los mismos archivos.
  final bool procesando;

  RespaldoState copyWith({bool? cargando, List<ArchivoRespaldo>? respaldos, bool? procesando}) {
    return RespaldoState(
      cargando: cargando ?? this.cargando,
      respaldos: respaldos ?? this.respaldos,
      procesando: procesando ?? this.procesando,
    );
  }
}
