/// Metadatos de un paquete de respaldo — se escribe como `manifest.json`
/// dentro del `.zip`. Puro Dart (sin Flutter): el mismo tipo se usa para
/// escribir al crear un respaldo y para leer al validar uno antes de
/// restaurar.
///
/// **Versionado (Etapa 4B).** `formatVersion` describe la FORMA del
/// manifiesto; [capacidades] describe lo que el paquete puede
/// garantizar. Van separados a propósito: cuando el respaldo portable
/// cifrado llegue, añadirá una capacidad nueva sin obligar a
/// reinterpretar todo lo anterior, y un validador viejo podrá decir
/// "este paquete declara algo que no sé comprobar" en vez de fingir que
/// lo comprobó. Un número solo no permite eso.
class ManifestRespaldo {
  const ManifestRespaldo({
    required this.formatVersion,
    required this.createdAt,
    required this.appSchemaVersion,
    required this.capacidades,
    required this.tipo,
    this.baseDatos,
    this.adjuntos = const [],
  });

  /// Forma del manifiesto. `1` es el formato original (Etapa 14C), sin
  /// integridad por archivo. `2` añade hash y tamaño de cada archivo
  /// irremplazable.
  final int formatVersion;

  static const versionActual = 2;

  final DateTime createdAt;

  /// `PRAGMA user_version` del `riseg_one.sqlite` empaquetado — se
  /// vuelve a leer del archivo al restaurar (nunca se confía ciegamente
  /// en este campo), pero queda aquí para poder mostrarlo sin abrir el
  /// `.zip`.
  final int appSchemaVersion;

  /// Lo que este paquete permite verificar o hacer. Hoy sólo existe
  /// [capacidadIntegridad]; el respaldo portable cifrado añadirá la
  /// suya sin tocar las demás.
  final Set<String> capacidades;

  /// Cada archivo irremplazable viene con tamaño y SHA-256, así que una
  /// alteración de bytes se detecta antes de restaurar.
  static const capacidadIntegridad = 'integridad';

  final TipoRespaldo tipo;

  /// `null` sólo en un manifiesto v1, que no registraba integridad.
  final ArchivoRespaldado? baseDatos;

  /// Vacía en v1 (no se registraban) y también en un v2 legítimo sin
  /// adjuntos. Para distinguirlos está [verificaIntegridad].
  final List<ArchivoRespaldado> adjuntos;

  /// El paquete trae la información necesaria para comprobar byte a
  /// byte lo que contiene. Un v1 nunca la trae.
  bool get verificaIntegridad => capacidades.contains(capacidadIntegridad) && baseDatos != null;

  int get bytesAdjuntos => adjuntos.fold<int>(0, (total, a) => total + a.bytes);
  int get archivosAdjuntos => adjuntos.length;

  Map<String, dynamic> toJson() => {
    'formatVersion': formatVersion,
    'createdAt': createdAt.toIso8601String(),
    'appSchemaVersion': appSchemaVersion,
    'capacidades': capacidades.toList()..sort(),
    'tipo': tipo.name,
    if (baseDatos != null) 'baseDatos': baseDatos!.toJson(),
    'adjuntos': [for (final a in adjuntos) a.toJson()],
  };

  /// `null` si [json] no tiene la forma esperada — un manifiesto
  /// corrupto o de un formato desconocido se trata como paquete
  /// inválido, nunca como una excepción no controlada.
  ///
  /// Lee tanto v1 como v2. Un v1 se reconoce por no traer
  /// `capacidades`: se carga sin integridad y sin lista de adjuntos, y
  /// todo el sistema lo tratará después como "verificación limitada".
  static ManifestRespaldo? fromJson(Map<String, dynamic> json) {
    try {
      final formatVersion = json['formatVersion'] as int;
      final capacidades = (json['capacidades'] as List<dynamic>?)?.cast<String>().toSet() ?? const <String>{};
      final baseDatosJson = json['baseDatos'] as Map<String, dynamic>?;
      final adjuntosJson = (json['adjuntos'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? const [];

      final adjuntos = <ArchivoRespaldado>[];
      for (final a in adjuntosJson) {
        final archivo = ArchivoRespaldado.fromJson(a);
        if (archivo == null) return null;
        adjuntos.add(archivo);
      }

      return ManifestRespaldo(
        formatVersion: formatVersion,
        createdAt: DateTime.parse(json['createdAt'] as String),
        appSchemaVersion: json['appSchemaVersion'] as int,
        capacidades: capacidades,
        // Un v1 no distinguía manual de preventivo. Se deduce del
        // nombre del archivo más arriba, nunca aquí.
        tipo: TipoRespaldo.desdeNombre(json['tipo'] as String?),
        baseDatos: baseDatosJson == null ? null : ArchivoRespaldado.fromJson(baseDatosJson),
        adjuntos: adjuntos,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Un archivo irremplazable dentro del paquete, con lo necesario para
/// comprobar que llegó íntegro.
class ArchivoRespaldado {
  const ArchivoRespaldado({required this.rutaRelativa, required this.bytes, required this.sha256});

  /// Siempre relativa al paquete y con `/` como separador — nunca una
  /// ruta absoluta ni con letra de unidad. `ValidarPaqueteRespaldoUseCase`
  /// lo vuelve a comprobar al leerla: el manifiesto describe el
  /// paquete, no manda sobre el sistema de archivos.
  final String rutaRelativa;
  final int bytes;
  final String sha256;

  Map<String, dynamic> toJson() => {'rutaRelativa': rutaRelativa, 'bytes': bytes, 'sha256': sha256};

  static ArchivoRespaldado? fromJson(Map<String, dynamic> json) {
    try {
      return ArchivoRespaldado(
        rutaRelativa: json['rutaRelativa'] as String,
        bytes: json['bytes'] as int,
        sha256: json['sha256'] as String,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Por qué existe este respaldo. Lo decide quien lo crea, y viaja en el
/// manifiesto para que la lista no tenga que adivinarlo del nombre del
/// archivo.
enum TipoRespaldo {
  /// Lo pidió una persona desde Configuración → Respaldo.
  manual,

  /// Lo creó la propia aplicación justo antes de una restauración, como
  /// red de seguridad. Nunca se borra mientras esa restauración siga
  /// pendiente de aplicarse.
  preventivo;

  static TipoRespaldo desdeNombre(String? nombre) {
    for (final t in TipoRespaldo.values) {
      if (t.name == nombre) return t;
    }
    return TipoRespaldo.manual;
  }
}
