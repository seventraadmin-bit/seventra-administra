/// Repositorio de permisos dinámicos por Usuario (Etapa 11B).
abstract interface class PermisoUsuarioRepository {
  Future<Set<String>> obtenerCodigos(String usuarioId);

  /// Reemplaza el conjunto completo de permisos del Usuario por
  /// [codigos] — no hay `agregar`/`quitar` individuales a nivel de
  /// repositorio porque la UI siempre trabaja sobre el estado completo
  /// de la matriz (mismo criterio que un `PUT` idempotente). Registra
  /// `UsuarioEvento(permisosModificados)` con el diff real
  /// (agregados/removidos) en la misma transacción — nunca hay un
  /// cambio de permisos sin su evento de auditoría.
  Future<void> guardar({
    required String usuarioId,
    required Set<String> codigos,
    String? actorUsuarioId,
  });
}
