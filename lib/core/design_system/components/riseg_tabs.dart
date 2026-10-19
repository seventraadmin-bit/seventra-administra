import 'package:flutter/material.dart';

import '../theme_context.dart';
import '../tokens/app_typography.dart';

/// Una pestaña de [RisegTabs] — solo etiqueta e ícono opcional.
@immutable
class RisegTabItem {
  const RisegTabItem({required this.label, this.icon, this.atenuada = false});

  final String label;
  final IconData? icon;

  /// Se pinta **más clara que las demás**, sin cambiar de alto ni de tipografía.
  ///
  /// Llegó con Administra en la nube, donde conviven pestañas que ya tienen pantalla
  /// con otras que todavía no. **Tres cosas que no se deben confundir:**
  ///
  ///  · **No es `enabled: false`.** La pestaña **sí** se abre: su contenido explica
  ///    qué va a haber ahí. Deshabilitarla dejaría al usuario sin saberlo.
  ///  · **No se marca con el ícono.** `Tab` lo pinta **encima** del texto, así que
  ///    marcar sólo algunas las haría **más altas** y desalinearía la franja.
  ///  · **Atenúa SOBRE el color que le toca**, no a un gris fijo. Un `TabBar` pinta
  ///    la seleccionada y las demás con colores distintos; con un gris absoluto, al
  ///    seleccionarla se quedaría clarita sobre el subrayado azul y parecería
  ///    deshabilitada.
  ///
  /// El valor por omisión es `false`, así que ninguna pestaña del escritorio cambia.
  final bool atenuada;
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

/// `TickerProviderStateMixin`, NO `SingleTickerProviderStateMixin`.
///
/// BUG REAL (Etapa "Usuarios, permisos y UX de seguridad"):
/// `didUpdateWidget` construye un `TabController` nuevo cuando cambia el
/// NÚMERO de pestañas, y `SingleTickerProviderStateMixin` solo admite un
/// ticker en toda la vida del `State` — disponer el anterior no libera
/// el lugar. El segundo `TabController` reventaba con
/// "_RisegTabsState is a SingleTickerProviderStateMixin but multiple
/// tickers were created".
///
/// No era teórico: el juego de pestañas SÍ cambia en caliente. Basta
/// que la sesión pase de Maestro a Normal para que Configuración pierda
/// Respaldo y Bóveda (4 → 2) — reproducido al escribir la prueba de
/// cambio de sesión. Cualquier pantalla con pestañas filtradas por
/// permiso tiene el mismo camino.
class _RisegTabsState extends State<RisegTabs> with TickerProviderStateMixin {
  late TabController _controller;

  /// Nunca fuera de rango: al perder pestañas, el índice seleccionado
  /// puede apuntar a una que ya no existe (Configuración en Respaldo,
  /// índice 2, cuando la sesión deja de ser Maestra y quedan 2). El
  /// llamador corrige su propio estado en el frame siguiente; mientras
  /// tanto esto evita el rango inválido de `TabController`.
  int get _indiceValido => widget.tabs.isEmpty ? 0 : widget.selectedIndex.clamp(0, widget.tabs.length - 1);

  @override
  void initState() {
    super.initState();
    _controller = TabController(length: widget.tabs.length, initialIndex: _indiceValido, vsync: this);
  }

  @override
  void didUpdateWidget(covariant RisegTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tabs.length != widget.tabs.length) {
      _controller.dispose();
      _controller = TabController(length: widget.tabs.length, initialIndex: _indiceValido, vsync: this);
    } else if (_controller.index != _indiceValido) {
      _controller.index = _indiceValido;
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
        for (final (indice, tab) in widget.tabs.indexed)
          Tab(
            icon: tab.icon == null ? null : Icon(tab.icon, size: 18),
            // LA ATENUADA LLEVA SU PROPIO `child` y no `text`, porque `text` toma el
            // color del `TabBar` y no admite uno propio. Y se atenúa SOBRE el que le
            // tocaría —seleccionada o no—, para que al seleccionarla no quede
            // clarita sobre el subrayado azul.
            text: tab.atenuada ? null : tab.label,
            iconMargin: const EdgeInsets.only(bottom: 4),
            child: tab.atenuada
                ? Text(
                    tab.label,
                    style:
                        (indice == widget.selectedIndex
                                ? AppTypography.bodyStrong
                                : AppTypography.body)
                            .copyWith(
                              color:
                                  (indice == widget.selectedIndex
                                          ? colors.accentText
                                          : colors.textMuted)
                                      .withValues(alpha: 0.55),
                            ),
                  )
                : null,
          ),
      ],
    );
  }
}
