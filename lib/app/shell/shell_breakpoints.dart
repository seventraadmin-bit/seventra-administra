/// Constantes centralizadas de responsividad del Shell.
///
/// Ningún widget del Shell debe usar un número mágico de ancho — todos los
/// umbrales de layout se leen de aquí.
///
/// **Exclusivo del Shell** — no lo uses fuera de `lib/app/shell/`. Para
/// formularios y contenido de módulos, usa `AppBreakpoints`
/// (`lib/core/design_system/tokens/app_breakpoints.dart`). Son dos
/// sistemas con responsabilidades distintas a propósito: este resuelve
/// cuándo colapsa el sidebar o se reduce el Top Bar; el otro, cómo se
/// reorganiza el contenido de un módulo. Si algún día conviene unificarlos,
/// se hace con evidencia real, no de forma preventiva.
abstract final class ShellBreakpoints {
  /// Por debajo de este ancho de ventana, el sidebar en modo `automatico`
  /// se colapsa por sí solo.
  static const double sidebarAutoCollapse = 900;

  /// Piso de seguridad: por debajo de este ancho, el sidebar se colapsa sin
  /// importar el modo (incluso si el usuario lo forzó a expandido). Evita
  /// que el área de contenido quede sin espacio utilizable.
  static const double sidebarForceCollapse = 640;

  /// Piso de seguridad por **altura**: por debajo de esta altura de
  /// ventana disponible, el sidebar se colapsa sin importar el modo ni el
  /// ancho — mismo criterio exacto que [sidebarForceCollapse], solo que
  /// para la otra dimensión (bug real encontrado por Marlon: con ventana
  /// angosta en altura, el encabezado fijo + el control de colapso fijo
  /// dejaban muy poco margen antes de desbordar). En modo colapsado, el
  /// encabezado y cada destino ocupan mucho menos alto, lo que da margen
  /// de sobra incluso en ventanas bastante reducidas — medido: sin este
  /// piso, el sidebar expandido desborda por debajo de ~400px de alto
  /// disponible; colapsado, el piso real queda muy por debajo de este
  /// valor. 560 dejando margen de seguridad generoso, nunca al límite.
  static const double sidebarForceCollapseHeight = 560;

  /// Ancho del sidebar expandido.
  ///
  /// Reducido de 240 a 224 en el refinamiento visual previo a la Etapa 3B —
  /// más angosto se siente más elegante sin perder espacio útil para las
  /// etiquetas de los 10 destinos.
  static const double sidebarExpandedWidth = 224;

  /// Ancho del sidebar colapsado (modo ícono).
  ///
  /// Deja margen de seguridad deliberado sobre el contenido mínimo del
  /// ítem de navegación (ícono + padding constante) para que, durante la
  /// animación de expansión/colapso, nunca haya un instante en que el
  /// contenido "expandido" (ícono + etiqueta) se calcule sobre un ancho
  /// todavía angosto y desborde.
  static const double sidebarCollapsedWidth = 80;

  /// Por debajo de este ancho disponible en el Top Bar, el campo de
  /// búsqueda visual se reduce a un botón de ícono. Es lo primero en
  /// sacrificarse — nunca los controles esenciales.
  static const double topBarSearchCompact = 1100;

  /// Por debajo de este ancho disponible en el Top Bar, el perfil de
  /// usuario oculta el nombre y muestra solo el avatar.
  static const double topBarProfileCompact = 850;
}
