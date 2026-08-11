/// Catálogo único de módulos y acciones de permiso (Etapa 11B).
///
/// Fuente de verdad para la matriz de administración de permisos, el
/// gate del sidebar/router y el conjunto completo que recibe el
/// Maestro (`todosLosCodigosDePermiso`). Agregar un módulo o una acción
/// especial nueva es agregar una entrada aquí — nunca una migración de
/// `Usuario` ni de `PermisoUsuario` (el código es un TEXT libre, sin
/// columnas rígidas tipo `puedeVerFinanzas`).
library;

enum AccionBase { ver, crear, modificar, archivar, eliminar }

class ModuloPermiso {
  const ModuloPermiso({
    required this.codigo,
    required this.accionesBase,
    this.accionesEspeciales = const [],
  });

  /// Coincide con el segmento de ruta del Shell (`shellModuleDefs`),
  /// salvo `'usuarios'` — pseudo-módulo sin ruta propia en el catálogo
  /// de rutas; gatea `/configuracion` (ver `shell_permissions.dart`).
  final String codigo;

  /// Subconjunto real de acciones que aplican a este módulo — nunca se
  /// muestra un permiso ficticio solo para llenar la matriz (ej.
  /// Reportes solo tiene `ver`; Usuarios no tiene ninguna acción base,
  /// solo el permiso especial `usuarios.administrar`).
  final Set<AccionBase> accionesBase;

  /// Códigos sensibles fuera de la matriz base — `'modulo.accionEspecifica'`.
  final List<String> accionesEspeciales;

  String codigoPara(AccionBase accion) => '$codigo.${accion.name}';

  Set<String> get todosLosCodigos => {
        for (final a in accionesBase) codigoPara(a),
        ...accionesEspeciales,
      };
}

/// Sin `'dashboard'`: no tiene permiso propio, cualquier sesión válida
/// entra (ver `shell_permissions.dart`). Sin `'documentos'`/`'activos'`:
/// nunca existieron como módulos reales, no hay nada que administrar.
const modulosPermiso = <ModuloPermiso>[
  ModuloPermiso(
    codigo: 'personal',
    accionesBase: {AccionBase.ver, AccionBase.crear, AccionBase.modificar, AccionBase.archivar},
    accionesEspeciales: ['personal.cambiarSueldo'],
  ),
  ModuloPermiso(
    codigo: 'nomina',
    accionesBase: {AccionBase.ver, AccionBase.crear, AccionBase.modificar},
    accionesEspeciales: ['nomina.cerrar', 'nomina.pagar'],
  ),
  ModuloPermiso(
    codigo: 'finanzas',
    accionesBase: {AccionBase.ver, AccionBase.crear, AccionBase.modificar, AccionBase.archivar},
  ),
  ModuloPermiso(
    codigo: 'compras',
    accionesBase: {AccionBase.ver, AccionBase.crear, AccionBase.archivar},
  ),
  ModuloPermiso(
    codigo: 'inventario',
    accionesBase: {AccionBase.ver, AccionBase.crear, AccionBase.modificar, AccionBase.archivar},
  ),
  ModuloPermiso(
    codigo: 'vehiculos',
    accionesBase: {AccionBase.ver, AccionBase.crear, AccionBase.modificar, AccionBase.archivar},
  ),
  ModuloPermiso(
    codigo: 'telefonia',
    accionesBase: {AccionBase.ver, AccionBase.crear, AccionBase.modificar, AccionBase.archivar},
  ),
  ModuloPermiso(
    codigo: 'organizacion',
    accionesBase: {AccionBase.ver, AccionBase.crear, AccionBase.modificar, AccionBase.archivar},
  ),
  ModuloPermiso(
    codigo: 'comercial',
    accionesBase: {AccionBase.ver, AccionBase.crear, AccionBase.modificar, AccionBase.archivar},
  ),
  ModuloPermiso(
    codigo: 'reportes',
    accionesBase: {AccionBase.ver},
  ),
  // Sin acciones base: "administrar usuarios" es un todo-o-nada en esta
  // etapa, no hay hoy una necesidad real de distinguir "puede ver la
  // lista pero no editar" — se agrega el día que exista esa necesidad
  // concreta, sin migración (ver el doc comment de `PermisoUsuario`).
  ModuloPermiso(
    codigo: 'usuarios',
    accionesBase: {},
    accionesEspeciales: ['usuarios.administrar'],
  ),
];

/// Todos los códigos conocidos hoy — lo que recibe un Usuario Maestro,
/// recalculado siempre en el momento (nunca una copia congelada
/// guardada en `PermisoUsuario`), así un módulo agregado después ya
/// "existe" para el Maestro sin ninguna migración de datos.
Set<String> todosLosCodigosDePermiso() {
  return {for (final m in modulosPermiso) ...m.todosLosCodigos};
}

/// Normaliza un conjunto de códigos para que ninguna acción de un
/// módulo quede concedida sin `ver` en ese mismo módulo (Etapa 11B,
/// dependencia Ver → nunca `crear=true, ver=false`). Función pura,
/// compartida por la UI (mantiene los checkboxes coherentes en vivo) y
/// por `GuardarPermisosUsuarioUseCase` (red de seguridad — nunca
/// persiste una combinación absurda aunque la UI tuviera un bug).
///
/// Dirección deliberada: siempre "corrige hacia adelante" (agrega
/// `ver`), nunca retira una acción que el llamador pidió explícitamente
/// — la dirección contraria ("si se desmarca Ver, desmarcar las
/// demás") es responsabilidad de la UI en el momento de la interacción
/// (ver `gestionar_permisos_usuario_dialog.dart`), no de esta función.
/// Los códigos especiales (`accionesEspeciales`) no participan de esta
/// regla — son independientes de `ver`.
Set<String> normalizarPermisos(Set<String> codigos) {
  final resultado = Set<String>.from(codigos);
  for (final modulo in modulosPermiso) {
    if (!modulo.accionesBase.contains(AccionBase.ver)) continue;
    final tieneOtraAccion = modulo.accionesBase
        .where((a) => a != AccionBase.ver)
        .any((a) => resultado.contains(modulo.codigoPara(a)));
    if (tieneOtraAccion) resultado.add(modulo.codigoPara(AccionBase.ver));
  }
  return resultado;
}
