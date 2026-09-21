import 'package:flutter/material.dart';

import '../theme_context.dart';
import '../tokens/app_radius.dart';
import '../tokens/app_spacing.dart';
import '../tokens/app_typography.dart';

/// Llave del panel de resultados abierto.
///
/// Permite distinguir en pruebas una opción del panel de un texto igual
/// que ya esté pintado en la pantalla de fondo.
const panelBuscable = Key('riseg_search_select_panel');

/// Una opción de [RisegSearchSelect].
///
/// [etiqueta] es lo que se ve y sobre lo que se busca; [detalle] es el
/// dato secundario que desempata homónimos (un puesto, un cliente) y
/// también entra en la búsqueda.
class RisegSearchOption<T> {
  const RisegSearchOption({required this.value, required this.etiqueta, this.detalle});

  final T value;
  final String etiqueta;
  final String? detalle;

  bool coincideCon(String consulta) {
    final texto = '$etiqueta ${detalle ?? ''}'.toLowerCase();
    return consulta.toLowerCase().split(' ').where((p) => p.isNotEmpty).every(texto.contains);
  }
}

/// Selector **buscable** de RISEG ONE.
///
/// Existe para lo que `RisegSelect` no debe hacer: elegir entre decenas
/// o cientos de entidades (personas, servicios). Un `DropdownButton`
/// plano con toda la plantilla es imposible de usar y además obliga a
/// tener la lista completa en pantalla.
///
/// Reutiliza el mismo patrón de overlay anclado que ya usa la Búsqueda
/// global (`CompositedTransformTarget` + `OverlayPortal` + `TapRegion`),
/// no una segunda invención: el panel se ancla debajo del campo, se
/// cierra al tocar fuera y nunca desplaza el layout de la pantalla.
///
/// El catálogo que recibe en [opciones] es responsabilidad del llamador
/// y **no** debe derivarse del resultado ya filtrado: si se recorta con
/// cada selección, el filtro se vuelve un callejón sin salida.
class RisegSearchSelect<T> extends StatefulWidget {
  const RisegSearchSelect({
    required this.label,
    required this.opciones,
    required this.value,
    required this.onChanged,
    required this.hint,
    required this.textoSinResultados,
    this.tooltipLimpiar,
    this.enabled = true,
    this.maxOpcionesVisibles = 8,
    super.key,
  });

  final String label;
  final List<RisegSearchOption<T>> opciones;
  final T? value;
  final ValueChanged<T?> onChanged;

  /// Texto del campo cuando no hay nada elegido.
  final String hint;

  /// Qué decir cuando la búsqueda no encuentra nada. Nunca se deja el
  /// panel vacío en silencio.
  final String textoSinResultados;

  final String? tooltipLimpiar;
  final bool enabled;

  /// Cuántas opciones caben en el panel antes de que haga scroll.
  final int maxOpcionesVisibles;

  @override
  State<RisegSearchSelect<T>> createState() => _RisegSearchSelectState<T>();
}

class _RisegSearchSelectState<T> extends State<RisegSearchSelect<T>> {
  // El controlador lo posee este State y se destruye aquí: nunca se
  // libera desde fuera mientras el campo sigue montado.
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _layerLink = LayerLink();
  final _overlayController = OverlayPortalController();

  late String _grupoAncla;
  String _consulta = '';

  @override
  void initState() {
    super.initState();
    _grupoAncla = 'riseg_search_select_${identityHashCode(this)}';
    _focusNode.addListener(_alCambiarFoco);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_alCambiarFoco);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _alCambiarFoco() {
    if (_focusNode.hasFocus && !_overlayController.isShowing) {
      _overlayController.show();
    }
  }

  RisegSearchOption<T>? get _seleccionada {
    for (final opcion in widget.opciones) {
      if (opcion.value == widget.value) return opcion;
    }
    return null;
  }

  List<RisegSearchOption<T>> get _visibles {
    final consulta = _consulta.trim();
    if (consulta.isEmpty) return widget.opciones;
    return [for (final o in widget.opciones) if (o.coincideCon(consulta)) o];
  }

  void _cerrar() {
    if (_overlayController.isShowing) _overlayController.hide();
    _controller.clear();
    if (_consulta.isNotEmpty) setState(() => _consulta = '');
  }

  void _elegir(RisegSearchOption<T> opcion) {
    _cerrar();
    _focusNode.unfocus();
    widget.onChanged(opcion.value);
  }

  void _limpiar() {
    _cerrar();
    widget.onChanged(null);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final seleccionada = _seleccionada;

    final border = OutlineInputBorder(
      borderRadius: AppRadius.mdRadius,
      borderSide: BorderSide(color: colors.borderInteractive),
    );
    final focusedBorder = OutlineInputBorder(
      borderRadius: AppRadius.mdRadius,
      borderSide: BorderSide(color: colors.focusRing, width: 2),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(widget.label, style: AppTypography.label.copyWith(color: colors.textMuted)),
        const SizedBox(height: AppSpacing.xxs),
        TapRegion(
          groupId: _grupoAncla,
          onTapOutside: (_) => _cerrar(),
          child: CompositedTransformTarget(
            link: _layerLink,
            child: OverlayPortal(
              controller: _overlayController,
              overlayChildBuilder: (context) => CompositedTransformFollower(
                link: _layerLink,
                targetAnchor: Alignment.bottomLeft,
                followerAnchor: Alignment.topLeft,
                offset: const Offset(0, 4),
                child: TapRegion(
                  groupId: _grupoAncla,
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: _Panel<T>(
                      // Ancla estable para pruebas: sólo hay un panel
                      // abierto a la vez, porque abrirlo exige el foco.
                      key: panelBuscable,
                      opciones: _visibles,
                      seleccionada: widget.value,
                      textoSinResultados: widget.textoSinResultados,
                      maxVisibles: widget.maxOpcionesVisibles,
                      onElegir: _elegir,
                    ),
                  ),
                ),
              ),
              child: SizedBox(
                height: 40,
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  enabled: widget.enabled,
                  style: AppTypography.body.copyWith(color: colors.textPrimary),
                  decoration: InputDecoration(
                    isDense: true,
                    prefixIcon: Icon(Icons.search, size: 18, color: colors.textMuted),
                    prefixIconConstraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                    contentPadding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                    // Con algo elegido, el valor vive en el `hintText`:
                    // así el campo queda listo para teclear otra
                    // búsqueda sin borrar antes lo que ya está puesto.
                    hintText: seleccionada?.etiqueta ?? widget.hint,
                    hintStyle: AppTypography.body.copyWith(
                      color: seleccionada == null ? colors.textMuted : colors.textPrimary,
                    ),
                    suffixIcon: seleccionada == null
                        ? null
                        : IconButton(
                            tooltip: widget.tooltipLimpiar,
                            icon: const Icon(Icons.close, size: 16),
                            onPressed: widget.enabled ? _limpiar : null,
                          ),
                    suffixIconConstraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                    filled: true,
                    fillColor: colors.surface,
                    border: border,
                    enabledBorder: border,
                    focusedBorder: focusedBorder,
                  ),
                  onChanged: (texto) {
                    if (!_overlayController.isShowing) _overlayController.show();
                    setState(() => _consulta = texto);
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Panel<T> extends StatelessWidget {
  const _Panel({
    super.key,
    required this.opciones,
    required this.seleccionada,
    required this.textoSinResultados,
    required this.maxVisibles,
    required this.onElegir,
  });

  final List<RisegSearchOption<T>> opciones;
  final T? seleccionada;
  final String textoSinResultados;
  final int maxVisibles;
  final ValueChanged<RisegSearchOption<T>> onElegir;

  static const _altoRenglon = 44.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Material(
      elevation: 4,
      borderRadius: AppRadius.mdRadius,
      color: colors.surface,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: 240,
          maxWidth: 340,
          maxHeight: _altoRenglon * maxVisibles,
        ),
        child: opciones.isEmpty
            ? Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: Text(
                  textoSinResultados,
                  style: AppTypography.body.copyWith(color: colors.textMuted),
                ),
              )
            : ListView.builder(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: opciones.length,
                itemBuilder: (context, indice) {
                  final opcion = opciones[indice];
                  final esActual = opcion.value == seleccionada;
                  return InkWell(
                    onTap: () => onElegir(opcion),
                    child: Container(
                      height: _altoRenglon,
                      width: double.infinity,
                      color: esActual ? colors.accentSoftBg : null,
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xxs),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            opcion.etiqueta,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.body.copyWith(color: colors.textPrimary),
                          ),
                          if (opcion.detalle != null)
                            Text(
                              opcion.detalle!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.caption.copyWith(color: colors.textMuted),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
