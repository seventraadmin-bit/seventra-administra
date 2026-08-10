import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/app/shell/shell_breakpoints.dart';
import 'package:riseg_one/app/shell/sidebar_mode_controller.dart';

void main() {
  group('resolveSidebarCollapsed — altura', () {
    test('colapsa por debajo de sidebarForceCollapseHeight, incluso con modo expandidoForzado', () {
      final resultado = resolveSidebarCollapsed(
        mode: SidebarMode.expandidoForzado,
        availableWidth: 1440,
        availableHeight: ShellBreakpoints.sidebarForceCollapseHeight - 1,
      );
      expect(resultado, isTrue);
    });

    test('no colapsa por altura cuando hay espacio suficiente, aunque el ancho también sea amplio', () {
      final resultado = resolveSidebarCollapsed(
        mode: SidebarMode.automatico,
        availableWidth: 1440,
        availableHeight: ShellBreakpoints.sidebarForceCollapseHeight + 1,
      );
      expect(resultado, isFalse);
    });

    test('sin availableHeight (parámetro omitido), el comportamiento previo por ancho no cambia', () {
      final resultado = resolveSidebarCollapsed(mode: SidebarMode.automatico, availableWidth: 1440);
      expect(resultado, isFalse);
    });

    test('el piso de ancho sigue teniendo prioridad independientemente de la altura', () {
      final resultado = resolveSidebarCollapsed(
        mode: SidebarMode.expandidoForzado,
        availableWidth: ShellBreakpoints.sidebarForceCollapse - 1,
        availableHeight: 2000,
      );
      expect(resultado, isTrue);
    });
  });
}
