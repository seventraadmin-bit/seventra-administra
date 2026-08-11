import 'package:riseg_one/core/database/app_database.dart';

import '../../domain/usecases/buscar_auditoria_usecase.dart';

class AuditoriaState {
  const AuditoriaState({
    this.cargando = false,
    this.eventos = const [],
    this.usuarios = const [],
    this.actorUsuarioId,
    this.modulo,
    this.accion,
    this.desde,
    this.hasta,
    this.errorCarga,
  });

  final bool cargando;
  final List<EventoAuditoria> eventos;
  final List<UsuarioData> usuarios;

  final String? actorUsuarioId;
  final String? modulo;
  final String? accion;
  final DateTime? desde;
  final DateTime? hasta;

  final String? errorCarga;

  String? nombreUsuario(String? usuarioId) {
    if (usuarioId == null) return null;
    for (final u in usuarios) {
      if (u.id == usuarioId) return u.nombre;
    }
    return null;
  }

  /// Acciones distintas presentes en el resultado actual — alimenta el
  /// filtro de Acción sin necesitar un catálogo estático (los valores
  /// de `accion` son heterogéneos entre dominios).
  List<String> get accionesDisponibles {
    final set = <String>{for (final e in eventos) e.accion};
    final lista = set.toList()..sort();
    return lista;
  }

  AuditoriaState copyWith({
    bool? cargando,
    List<EventoAuditoria>? eventos,
    List<UsuarioData>? usuarios,
    String? actorUsuarioId,
    bool limpiarActorUsuarioId = false,
    String? modulo,
    bool limpiarModulo = false,
    String? accion,
    bool limpiarAccion = false,
    DateTime? desde,
    bool limpiarDesde = false,
    DateTime? hasta,
    bool limpiarHasta = false,
    String? errorCarga,
  }) {
    return AuditoriaState(
      cargando: cargando ?? this.cargando,
      eventos: eventos ?? this.eventos,
      usuarios: usuarios ?? this.usuarios,
      actorUsuarioId: limpiarActorUsuarioId ? null : (actorUsuarioId ?? this.actorUsuarioId),
      modulo: limpiarModulo ? null : (modulo ?? this.modulo),
      accion: limpiarAccion ? null : (accion ?? this.accion),
      desde: limpiarDesde ? null : (desde ?? this.desde),
      hasta: limpiarHasta ? null : (hasta ?? this.hasta),
      errorCarga: errorCarga,
    );
  }
}
