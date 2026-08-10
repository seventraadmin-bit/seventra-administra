import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'shell_breakpoints.dart';

part 'sidebar_mode_controller.g.dart';

/// Modo de comportamiento del sidebar.
///
/// No es un simple booleano: "colapsado" es un *resultado*, no un modo —
/// se calcula combinando este modo con el ancho disponible
/// ([resolveSidebarCollapsed]).
enum SidebarMode {
  /// El breakpoint decide: colapsado si el ancho es insuficiente.
  automatico,

  /// El usuario forzó expandido — se respeta mientras haya ancho suficiente.
  expandidoForzado,

  /// El usuario forzó colapsado — se mantiene colapsado.
  colapsadoForzado,
}

/// Calcula si el sidebar debe verse colapsado dado su [mode] y el tamaño
/// disponible de la ventana ([availableWidth]/[availableHeight]).
///
/// La seguridad del layout siempre tiene prioridad: por debajo de
/// [ShellBreakpoints.sidebarForceCollapse] (ancho) o
/// [ShellBreakpoints.sidebarForceCollapseHeight] (alto) se colapsa sin
/// importar el modo, incluso si el usuario lo forzó a expandido —
/// [availableHeight] es opcional (`null` omite el chequeo de alto) para no
/// romper a quien ya llame esta función solo con ancho.
bool resolveSidebarCollapsed({
  required SidebarMode mode,
  required double availableWidth,
  double? availableHeight,
}) {
  if (availableWidth < ShellBreakpoints.sidebarForceCollapse) {
    return true;
  }
  if (availableHeight != null && availableHeight < ShellBreakpoints.sidebarForceCollapseHeight) {
    return true;
  }
  return switch (mode) {
    SidebarMode.automatico => availableWidth < ShellBreakpoints.sidebarAutoCollapse,
    SidebarMode.expandidoForzado => false,
    SidebarMode.colapsadoForzado => true,
  };
}

/// Controla el [SidebarMode] elegido por el usuario en la sesión actual.
///
/// No se persiste entre reinicios (decisión deliberada de esta etapa):
/// siempre arranca en [SidebarMode.automatico].
@riverpod
class SidebarModeController extends _$SidebarModeController {
  @override
  SidebarMode build() => SidebarMode.automatico;

  void setMode(SidebarMode mode) => state = mode;

  /// Alterna entre forzar expandido y forzar colapsado, a partir del
  /// estado *visual* actual (no del modo interno) — para que el botón de
  /// colapso se comporte de forma predecible sin importar si se llegó al
  /// estado actual por automatismo o por una elección manual previa.
  void toggleFrom({required bool currentlyCollapsed}) {
    state = currentlyCollapsed ? SidebarMode.expandidoForzado : SidebarMode.colapsadoForzado;
  }
}
