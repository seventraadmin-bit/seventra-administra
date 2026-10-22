import '../error/failure.dart';
import '../error/result.dart';

/// Qué puede hacer esta persona **sobre la Organization**, no dentro de una empresa.
///
/// ## Por qué hacía falta un modelo nuevo
///
/// Hasta E2, la web sólo conocía la autoridad **de Company**: el contexto que resuelve
/// la empresa activa trae `role` —`maestro` o `user`—, los permisos efectivos y los
/// módulos. Nada de eso dice si esta persona puede **dar de alta una empresa**, porque
/// crear una empresa no ocurre dentro de ninguna.
///
/// Son dos planos y no se deducen uno del otro: **un Maestro puede no ser miembro de la
/// Organization**, y un Owner de la Organization puede no tener acceso a ninguna
/// empresa. Es la distinción que sostiene todo el modelo de aislamiento.
///
/// ## Lo que NO es
///
/// 🚫 **No es una lista de lo que la pantalla enseña.** Es lo que el servidor dijo que
/// esta persona es, y la pantalla decide qué hacer con eso. Si algún día hiciera falta
/// un «puedeVerLaPestaña», sale de aquí por derivación — nunca al revés.
class AutoridadDeOrganizacion {
  const AutoridadDeOrganizacion({
    required this.organizationId,
    required this.role,
    required this.permisos,
  });

  final String organizationId;

  /// `owner` o `admin`. El catálogo del backend es cerrado; aquí se conserva como texto
  /// porque **el cliente no decide autorización con él**: decide qué ofrecer, y el
  /// servidor vuelve a decidir en cada petición.
  final String role;

  /// Los permisos de organización concedidos a **este periodo** de membresía.
  ///
  /// ⚠️ **El Owner llega con la lista VACÍA, y no es un error:** su autoridad es
  /// intrínseca al rol y el backend **no le materializa filas** de permiso. Por eso
  /// [puedeAdministrarEmpresas] pregunta por el rol **antes** que por la lista; al
  /// revés, el Owner se quedaría sin la pestaña de administración.
  final Set<String> permisos;

  static const String _owner = 'owner';
  static const String _companiesManage = 'companies.manage';

  bool get esOwner => role == _owner;

  /// Crear, desactivar y reactivar empresas: **Owner, o Admin con `companies.manage`**.
  bool get puedeAdministrarEmpresas =>
      esOwner || permisos.contains(_companiesManage);

  /// Eliminar una empresa: **sólo el Owner**. Es la única operación de E2 sin vuelta
  /// atrás, y un Admin con el permiso **no** la alcanza.
  bool get puedeEliminarEmpresas => esOwner;

  static Result<AutoridadDeOrganizacion> desdeJson(
    String organizationId,
    Map<String, Object?> json,
  ) {
    final role = json['role'];

    if (role is! String || role.trim().isEmpty) {
      return const Result.failure(
        ApiRespuestaInesperadaFailure('La membresía no trae: role.'),
      );
    }

    // LOS PERMISOS PUEDEN NO VENIR, y la ausencia es la lista vacía —que es
    // justamente lo que el Owner recibe—. Lo que NO se hace es inferir permisos
    // del rol: eso lo decide el servidor, y duplicarlo aquí daría dos respuestas.
    final crudos = json['permissions'];

    return Result.ok(
      AutoridadDeOrganizacion(
        organizationId: organizationId,
        role: role.trim(),
        permisos: {
          if (crudos is List)
            for (final p in crudos)
              if (p is String && p.trim().isNotEmpty) p.trim(),
        },
      ),
    );
  }

  @override
  String toString() =>
      'AutoridadDeOrganizacion($role, ${permisos.length} permisos)';

  @override
  bool operator ==(Object other) =>
      other is AutoridadDeOrganizacion &&
      other.organizationId == organizationId &&
      other.role == role &&
      other.permisos.length == permisos.length &&
      other.permisos.containsAll(permisos);

  @override
  int get hashCode =>
      Object.hash(organizationId, role, Object.hashAllUnordered(permisos));
}
