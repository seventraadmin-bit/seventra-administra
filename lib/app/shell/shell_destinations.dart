import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

/// Un destino de navegación de primer nivel del Shell.
///
/// `path` es también la clave estable usada para construir los `Key` de
/// prueba (`nav_item_<path sin barra>`) y para el marcado semántico del
/// ítem activo — no cambiar sin actualizar los tests.
@immutable
class ShellDestination {
  const ShellDestination({
    required this.path,
    required this.label,
    required this.icon,
    this.proximamente = false,
  });

  final String path;
  final String label;
  final IconData icon;

  /// ¿Está en el menú pero todavía no tiene pantalla?
  ///
  /// Lo usa **sólo Administra en la nube**, donde la mudanza es gradual y el menú
  /// completo tiene que estar desde el primer día: un cliente que no ve «Personal»
  /// no sabe si llegará o si el producto no lo tiene. En el escritorio todo existe,
  /// así que el valor por omisión es `false` y nada de allá cambia.
  ///
  /// **El rótulo va en una SEGUNDA LÍNEA, no al lado del nombre.** Al lado le robaba
  /// el ancho y «Tipos de sucursal» salía cortado; abajo cuesta alto, que en un menú
  /// de nueve entradas sobra.
  final bool proximamente;

  /// Identificador corto usado en Keys (`dashboard`, `organizacion`, ...).
  String get id => path.replaceFirst('/', '');
}

/// Definición estructural (ruta + ícono) de los 11 módulos, sin depender de
/// localización — la usa el router para construir las ramas del
/// `StatefulShellRoute`, que se arma una sola vez sin `BuildContext`.
///
/// Sin `/documentos`: era un placeholder heredado del boceto inicial del
/// Shell, nunca desarrollado. Revisión explícita de Marlon (después de
/// Etapa 7C): RISEG ONE ya sigue una arquitectura donde cada documento
/// vive ligado a su dominio (documentos del empleado y ficha técnica en
/// Personal, resguardos en Inventario, comprobantes en Finanzas/Nómina,
/// documentos de Empresa/Cliente en su dominio — todos vía la
/// infraestructura compartida de `Attachment`, nunca duplicados). Un
/// módulo "Documentos" global no tendría función propia más allá de
/// volver a mostrar archivos que ya pertenecen a otros módulos —
/// exactamente el tipo de redundancia que el principio de "información
/// ligada, sin duplicados" de este proyecto evita. Que un destino haya
/// aparecido en el menú original no obliga a construirlo como módulo:
/// mismo criterio aplicaría a cualquier otro placeholder heredado que
/// resulte ser igual de redundante al revisarlo.
///
/// Sin `/activos`: mismo criterio, retirado tras la Etapa 10. Era otro
/// placeholder heredado del boceto inicial, nunca desarrollado (nunca
/// tuvo tabla, repositorio, proveedor ni pantalla propia — solo caía en
/// el `ModulePlaceholderScreen` genérico). Revisión explícita de Marlon:
/// con Inventario (artículos, equipo, teléfonos físicos y unidades
/// serializadas), Vehículos (flotilla) y Telefonía (líneas) ya cubriendo
/// toda su función real, un módulo "Activos" independiente sería
/// redundante — la decisión funcional es que no habrá módulo de Activos
/// mientras esos tres dominios cubran su función.
const List<({String path, IconData icon})> shellModuleDefs = [
  (path: '/dashboard', icon: Icons.dashboard_outlined),
  (path: '/organizacion', icon: Icons.apartment_outlined),
  (path: '/comercial', icon: Icons.handshake_outlined),
  (path: '/finanzas', icon: Icons.account_balance_outlined),
  (path: '/personal', icon: Icons.people_outline),
  (path: '/inventario', icon: Icons.inventory_2_outlined),
  (path: '/compras', icon: Icons.shopping_cart_outlined),
  (path: '/vehiculos', icon: Icons.directions_car_outlined),
  (path: '/telefonia', icon: Icons.phone_iphone_outlined),
  (path: '/reportes', icon: Icons.bar_chart_outlined),
  (path: '/configuracion', icon: Icons.settings_outlined),
];

String _labelFor(String path, AppLocalizations l10n) {
  return switch (path) {
    '/dashboard' => l10n.moduleDashboard,
    '/organizacion' => l10n.moduleOrganizacion,
    '/comercial' => l10n.moduleComercial,
    '/finanzas' => l10n.moduleFinanzas,
    '/personal' => l10n.modulePersonal,
    '/inventario' => l10n.moduleInventario,
    '/compras' => l10n.moduleCompras,
    '/vehiculos' => l10n.moduleVehiculos,
    '/telefonia' => l10n.moduleTelefonia,
    '/reportes' => l10n.moduleReportes,
    '/configuracion' => l10n.moduleConfiguracion,
    _ => path,
  };
}

/// Construye los 11 destinos con sus etiquetas localizadas.
///
/// Se llama con el `BuildContext` disponible (en el Shell o en cada
/// builder de rama) — no se puede memorizar como lista `const` porque
/// `AppLocalizations` depende del contexto.
List<ShellDestination> buildShellDestinations(AppLocalizations l10n) {
  return [
    for (final def in shellModuleDefs)
      ShellDestination(path: def.path, icon: def.icon, label: _labelFor(def.path, l10n)),
  ];
}

/// Busca el destino localizado correspondiente a [path] dentro de
/// [destinations]. Lanza si no existe — indicaría una ruta del router sin
/// su correspondiente definición en [shellModuleDefs].
ShellDestination destinationForPath(List<ShellDestination> destinations, String path) {
  return destinations.firstWhere((d) => d.path == path);
}
