import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design_system/design_system.dart';
import '../theme/theme_mode_controller.dart';
import 'catalog_sections/button_section.dart';
import 'catalog_sections/card_section.dart';
import 'catalog_sections/dialog_section.dart';
import 'catalog_sections/focus_section.dart';
import 'catalog_sections/misc_section.dart';
import 'catalog_sections/status_section.dart';
import 'catalog_sections/table_section.dart';
import 'catalog_sections/text_field_section.dart';

/// Catálogo de desarrollo del Design System de RISEG ONE.
///
/// Referencia oficial: todo componente nuevo debe aparecer aquí antes de
/// usarse en un módulo real. Solo existe cuando `Env.resolve().isDev` —
/// ver el registro condicional en `createAppRouter` — y no depende del
/// Shell (es una pantalla independiente, con su propio selector de tema
/// para poder revisar claro/oscuro sin salir de ella).
class DesignSystemCatalogScreen extends ConsumerStatefulWidget {
  const DesignSystemCatalogScreen({super.key});

  @override
  ConsumerState<DesignSystemCatalogScreen> createState() => _DesignSystemCatalogScreenState();
}

class _DesignSystemCatalogScreenState extends ConsumerState<DesignSystemCatalogScreen> {
  int _selectedTab = 0;

  static const _tabs = [
    RisegTabItem(label: 'Botones'),
    RisegTabItem(label: 'Campos'),
    RisegTabItem(label: 'Cards'),
    RisegTabItem(label: 'Estados'),
    RisegTabItem(label: 'Diálogos'),
    RisegTabItem(label: 'Tabla'),
    RisegTabItem(label: 'Otros'),
    RisegTabItem(label: 'Foco y teclado'),
  ];

  static const _sections = [
    ButtonCatalogSection(),
    TextFieldCatalogSection(),
    CardCatalogSection(),
    StatusCatalogSection(),
    DialogCatalogSection(),
    TableCatalogSection(),
    MiscCatalogSection(),
    FocusCatalogSection(),
  ];

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeControllerProvider);
    final isDark = themeMode == ThemeMode.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Design System — Seventra Administra'),
        actions: [
          IconButton(
            tooltip: isDark ? 'Cambiar a modo claro' : 'Cambiar a modo oscuro',
            icon: Icon(isDark ? Icons.dark_mode_outlined : Icons.light_mode_outlined),
            onPressed: () => ref
                .read(themeModeControllerProvider.notifier)
                .setThemeMode(isDark ? ThemeMode.light : ThemeMode.dark),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: RisegTabs(
            tabs: _tabs,
            selectedIndex: _selectedTab,
            onChanged: (index) => setState(() => _selectedTab = index),
          ),
        ),
      ),
      body: IndexedStack(index: _selectedTab, children: _sections),
    );
  }
}
