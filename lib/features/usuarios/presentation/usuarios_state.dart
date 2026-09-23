import 'package:riseg_one/core/database/app_database.dart';

import '../domain/identidad_usuario.dart';

/// Mismo molde que `ComprasState`/`EgresosState` — cargando/lista/error,
/// más el catálogo de Puestos ya cargado para el selector del
/// formulario (evita una consulta aparte en cada apertura de diálogo).
///
/// Etapa 3B: la lista ya no son `UsuarioData` crudos sino
/// [IdentidadUsuario] — cada cuenta con su nombre y su puesto EFECTIVOS
/// ya resueltos. La pantalla no vuelve a decidir de dónde sale un
/// nombre; esa regla vive en un solo sitio y llega resuelta.
class UsuariosState {
  const UsuariosState({
    this.cargando = false,
    this.identidades = const [],
    this.puestos = const [],
    this.errorCarga,
  });

  final bool cargando;
  final List<IdentidadUsuario> identidades;

  /// Sólo los Puestos ACTIVOS, y sólo para el selector del formulario:
  /// no se puede asignar un puesto dado de baja. Para *mostrar* el
  /// puesto de una cuenta nunca se usa esta lista — se usa el puesto ya
  /// resuelto de `IdentidadUsuario`, que sí incluye los inactivos.
  final List<PuestoData> puestos;
  final String? errorCarga;

  UsuariosState copyWith({
    bool? cargando,
    List<IdentidadUsuario>? identidades,
    List<PuestoData>? puestos,
    String? errorCarga,
    bool limpiarError = false,
  }) {
    return UsuariosState(
      cargando: cargando ?? this.cargando,
      identidades: identidades ?? this.identidades,
      puestos: puestos ?? this.puestos,
      errorCarga: limpiarError ? null : (errorCarga ?? this.errorCarga),
    );
  }
}
