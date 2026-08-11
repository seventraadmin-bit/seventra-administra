import 'package:riseg_one/core/database/app_database.dart';

/// Mismo molde que `ComprasState`/`EgresosState` — cargando/lista/error,
/// más el catálogo de Puestos ya cargado para el selector del
/// formulario (evita una consulta aparte en cada apertura de diálogo).
class UsuariosState {
  const UsuariosState({
    this.cargando = false,
    this.usuarios = const [],
    this.puestos = const [],
    this.errorCarga,
  });

  final bool cargando;
  final List<UsuarioData> usuarios;
  final List<PuestoData> puestos;
  final String? errorCarga;

  String? nombrePuesto(String? puestoId) {
    if (puestoId == null) return null;
    for (final p in puestos) {
      if (p.id == puestoId) return p.nombre;
    }
    return null;
  }

  UsuariosState copyWith({
    bool? cargando,
    List<UsuarioData>? usuarios,
    List<PuestoData>? puestos,
    String? errorCarga,
    bool limpiarError = false,
  }) {
    return UsuariosState(
      cargando: cargando ?? this.cargando,
      usuarios: usuarios ?? this.usuarios,
      puestos: puestos ?? this.puestos,
      errorCarga: limpiarError ? null : (errorCarga ?? this.errorCarga),
    );
  }
}
