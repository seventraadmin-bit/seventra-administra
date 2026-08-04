import 'package:flutter/material.dart';

import '../theme_context.dart';
import '../tokens/app_typography.dart';

/// Una pestaña de [RisegTabs] — solo etiqueta e ícono opcional.
@immutable
class RisegTabItem {
  const RisegTabItem({required this.label, this.icon});

  final String label;
  final IconData? icon;
}

/// Franja visual de navegación por pestañas de RISEG ONE.
///
/// Solo la franja — no un `TabBarView` ni una pantalla con contenido por
/// pestaña; eso lo arma quien la use (ver, por ejemplo, la futura vista
/// de expediente con pestañas General/Direcciones/Contactos/...).
///
/// Compone sobre `TabBar`, así que la navegación por flechas entre
/// pestañas y la semántica de "tab seleccionado" ya vienen resueltas por
/// Material; este widget solo sincroniza un `TabController` interno con
/// [selectedIndex] para que el llamador no tenga que administrar uno.
class RisegTabs extends StatefulWidget {
  const RisegTabs({required this.tabs, required this.selectedIndex, required this.onChanged, super.key});

  final List<RisegTabItem> tabs;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  @override
  State<RisegTabs> createState() => _RisegTabsState();
}

class _RisegTabsState extends State<RisegTabs> with SingleTickerProviderStateMixin {
  late TabController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TabController(length: widget.tabs.length, initialIndex: widget.selectedIndex, vsync: this);
  }

  @override
  void didUpdateWidget(covariant RisegTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tabs.length != widget.tabs.length) {
      _controller.dispose();
      _controller = TabController(length: widget.tabs.length, initialIndex: widget.selectedIndex, vsync: this);
    } else if (_controller.index != widget.selectedIndex) {
      _controller.index = widget.selectedIndex;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return TabBar(
      controller: _controller,
      isScrollable: true,
      tabAlignment: TabAlignment.start,
      labelColor: colors.accentText,
      unselectedLabelColor: colors.textMuted,
      labelStyle: AppTypography.bodyStrong,
      unselectedLabelStyle: AppTypography.body,
      indicatorColor: colors.accent,
      indicatorSize: TabBarIndicatorSize.label,
      dividerColor: colors.borderSubtle,
      onTap: widget.onChanged,
      tabs: [
        for (final tab in widget.tabs)
          Tab(
            icon: tab.icon == null ? null : Icon(tab.icon, size: 18),
            text: tab.label,
            iconMargin: const EdgeInsets.only(bottom: 4),
          ),
      ],
    );
  }
}
