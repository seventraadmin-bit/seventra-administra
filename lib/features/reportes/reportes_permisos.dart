import 'package:riseg_one/core/permissions/permission_service.dart';

/// Guardia de permiso de una sección de Reportes (Etapa 12A).
///
/// `permisoRequeridoParaRuta` (`app/shell/shell_permissions.dart`) solo
/// lee el primer segmento de la ruta — para `/reportes/finanzas` el
/// router únicamente exige `reportes.ver`, nunca `finanzas.ver`. Esta
/// función es la barrera real: cada controller de sección debe
/// llamarla **antes** de tocar cualquier repositorio del dominio que
/// muestra, y si es `false`, no debe ejecutar ninguna consulta —
/// devolver un estado vacío/sin autorización, nunca datos parciales.
/// Ocultar la pestaña correspondiente en la UI es solo la capa
/// cosmética, no sustituye esta verificación.
bool tienePermisoSeccionReportes(PermissionService permissionService, String codigoPermiso) {
  return permissionService.hasCode(codigoPermiso);
}

/// Resultado de filtrar una lista de pestañas por permiso — mismo
/// remapeo de índice que ya usa `AppShellScreen` para el sidebar
/// (`visibleDestinations`/`visibleToRealIndex`), generalizado aquí para
/// que `ReportesShellScreen` pueda ocultar pestañas completas sin que
/// `RisegTabs` reciba nunca un índice fuera de rango. Primer precedente
/// de un Shell filtrando sus propias pestañas por permiso — patrón a
/// copiar si otro módulo lo necesita después.
class PestanasVisibles<T> {
  const PestanasVisibles({required this.visibles, required this.indiceActivo});

  final List<T> visibles;
  final int indiceActivo;
}

/// [todas] en el orden real de la UI; [permisoPara] devuelve `null`
/// cuando una pestaña no requiere permiso propio (ej. "General").
PestanasVisibles<T> filtrarPestanasPorPermiso<T>({
  required List<T> todas,
  required String? Function(T tab) permisoPara,
  required PermissionService permissionService,
  required T activa,
}) {
  final visibles = <T>[
    for (final tab in todas)
      if (permisoPara(tab) == null || permissionService.hasCode(permisoPara(tab)!)) tab,
  ];
  final indice = visibles.indexOf(activa);
  return PestanasVisibles(visibles: visibles, indiceActivo: indice == -1 ? 0 : indice);
}
