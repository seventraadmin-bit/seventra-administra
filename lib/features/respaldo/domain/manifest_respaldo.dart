/// Metadatos de un paquete de respaldo (Etapa 14C) — se escribe como
/// `manifest.json` dentro del `.zip`. Puro Dart (sin Flutter): el mismo
/// tipo se usa para escribir al crear un respaldo y para leer al
/// validar uno antes de restaurar.
class ManifestRespaldo {
  const ManifestRespaldo({
    required this.formatVersion,
    required this.createdAt,
    required this.appSchemaVersion,
    required this.integridadVerificada,
    required this.archivosAdjuntos,
    required this.bytesAdjuntos,
  });

  /// Versión del formato del propio manifiesto (no de RISEG ONE) — por
  /// si su forma cambia en el futuro.
  final int formatVersion;

  final DateTime createdAt;

  /// `PRAGMA user_version` del `riseg_one.sqlite` empaquetado en el
  /// momento de crear el respaldo — se vuelve a leer directamente del
  /// archivo al restaurar (nunca se confía ciegamente en este campo),
  /// pero queda aquí para que la pantalla pueda mostrarlo sin abrir el
  /// `.zip`.
  final int appSchemaVersion;

  /// Resultado de `PRAGMA integrity_check` al momento de crear el
  /// respaldo. Un respaldo nunca se produce si esto es `false` — ver
  /// `CrearRespaldoUseCase`.
  final bool integridadVerificada;

  final int archivosAdjuntos;
  final int bytesAdjuntos;

  Map<String, dynamic> toJson() => {
        'formatVersion': formatVersion,
        'createdAt': createdAt.toIso8601String(),
        'appSchemaVersion': appSchemaVersion,
        'integridadVerificada': integridadVerificada,
        'archivosAdjuntos': archivosAdjuntos,
        'bytesAdjuntos': bytesAdjuntos,
      };

  /// `null` si [json] no tiene la forma esperada — un manifiesto
  /// corrupto o de un formato desconocido se trata como paquete
  /// inválido, nunca como una excepción no controlada.
  static ManifestRespaldo? fromJson(Map<String, dynamic> json) {
    try {
      return ManifestRespaldo(
        formatVersion: json['formatVersion'] as int,
        createdAt: DateTime.parse(json['createdAt'] as String),
        appSchemaVersion: json['appSchemaVersion'] as int,
        integridadVerificada: json['integridadVerificada'] as bool,
        archivosAdjuntos: json['archivosAdjuntos'] as int,
        bytesAdjuntos: json['bytesAdjuntos'] as int,
      );
    } catch (_) {
      return null;
    }
  }
}
