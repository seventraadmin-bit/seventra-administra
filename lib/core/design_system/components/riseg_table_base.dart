import 'package:flutter/material.dart';

import '../theme_context.dart';
import '../tokens/app_spacing.dart';
import '../tokens/app_typography.dart';

/// Definición de una columna de [RisegTableBase].
///
/// `cellBuilder` es puro presentacional: recibe la fila ya resuelta y
/// devuelve el widget de la celda — [RisegTableBase] no sabe ni le
/// importa de dónde salió `T` (repositorio, provider, lista en memoria).
/// Esa separación es deliberada: la tabla es solo presentación.
@immutable
class RisegColumn<T> {
  const RisegColumn({required this.label, required this.cellBuilder, this.alignment = TextAlign.left, this.width});

  final String label;
  final TextAlign alignment;
  final Widget Function(T row) cellBuilder;

  /// `null` = la columna reparte el espacio restante (`Expanded`); un
  /// valor fijo la vuelve de ancho constante (típico para columnas de
  /// estado/acciones).
  final double? width;
}

/// Base mínima de tabla de RISEG ONE.
///
/// Deliberadamente sin paginación, ordenamiento, filtros, edición inline,
/// columnas redimensionables, selección múltiple ni virtualización — eso
/// se evalúa si un módulo real lo necesita, no antes. Lo que sí resuelve:
/// encabezados, hover, selección visual, estados vacío/carga, alineación
/// por columna, acciones por fila y una respuesta básica a anchos
/// reducidos (scroll horizontal en vez de reflow).
class RisegTableBase<T> extends StatelessWidget {
  const RisegTableBase({
    required this.columns,
    required this.rows,
    this.rowActionsBuilder,
    this.onRowTap,
    this.selectedRow,
    this.loading = false,
    this.emptyState,
    this.actionsWidth = 96,
    super.key,
  });

  final List<RisegColumn<T>> columns;
  final List<T> rows;
  final Widget Function(T row)? rowActionsBuilder;

  /// `null` deja las filas como no-interactivas (sin foco, sin hover, sin
  /// `InkWell`) — una tabla de solo lectura no debe fingir ser botón.
  final void Function(T row)? onRowTap;
  final T? selectedRow;
  final bool loading;
  final Widget? emptyState;

  /// Ancho de la columna de acciones cuando `rowActionsBuilder` no es
  /// nulo — 96px por defecto (sin cambio para ningún uso existente).
  /// Una fila con más de 1-2 acciones compactas necesita más espacio
  /// (Etapa 4G.2, Configuración comercial: hasta 3 acciones por fila).
  final double actionsWidth;

  double get _actionsWidth => rowActionsBuilder == null ? 0 : actionsWidth;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    // `Row` con columnas `Expanded` necesita un ancho acotado — un
    // `ConstrainedBox` con solo `minWidth` no lo da dentro de un
    // `SingleChildScrollView` horizontal (su hijo recibe ancho máximo
    // infinito). Por eso el ancho se calcula aquí, con el ancho
    // disponible real, y se aplica con `SizedBox` a un `Row` ya con
    // restricciones acotadas en ambos extremos.
    return LayoutBuilder(
      builder: (context, constraints) {
        final minWidth = _minTableWidth(context);
        final width = constraints.maxWidth > minWidth ? constraints.maxWidth : minWidth;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: width,
                child: _RisegTableHeader<T>(columns: columns, actionsWidth: _actionsWidth),
              ),
            ),
            Container(height: 1, color: colors.borderSubtle),
            if (loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (rows.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
                child: emptyState ?? const SizedBox.shrink(),
              )
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: width,
                  child: FocusTraversalGroup(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final row in rows)
                          _RisegTableRow<T>(
                            row: row,
                            columns: columns,
                            actionsWidth: _actionsWidth,
                            actionsBuilder: rowActionsBuilder,
                            onTap: onRowTap == null ? null : () => onRowTap!(row),
                            selected: selectedRow != null && selectedRow == row,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  double _minTableWidth(BuildContext context) {
    final fixed = columns.where((c) => c.width != null).fold<double>(0, (sum, c) => sum + c.width!);
    final flexCount = columns.where((c) => c.width == null).length;
    // Ancho mínimo razonable por columna flexible, solo para que el
    // scroll horizontal tenga un punto de partida sensato en anchos muy
    // reducidos — no es un layout definitivo por columna.
    return fixed + (flexCount * 120) + _actionsWidth;
  }
}

class _RisegTableHeader<T> extends StatelessWidget {
  const _RisegTableHeader({required this.columns, required this.actionsWidth});

  final List<RisegColumn<T>> columns;
  final double actionsWidth;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs, horizontal: AppSpacing.sm),
      child: Row(
        children: [
          for (final column in columns)
            _cellSlot(
              width: column.width,
              child: Semantics(
                header: true,
                child: Text(
                  column.label,
                  textAlign: column.alignment,
                  style: AppTypography.label.copyWith(color: colors.textMuted),
                ),
              ),
            ),
          if (actionsWidth > 0) SizedBox(width: actionsWidth),
        ],
      ),
    );
  }

  Widget _cellSlot({required double? width, required Widget child}) {
    if (width != null) return SizedBox(width: width, child: child);
    return Expanded(child: child);
  }
}

class _RisegTableRow<T> extends StatefulWidget {
  const _RisegTableRow({
    required this.row,
    required this.columns,
    required this.actionsWidth,
    required this.actionsBuilder,
    required this.onTap,
    required this.selected,
  });

  final T row;
  final List<RisegColumn<T>> columns;
  final double actionsWidth;
  final Widget Function(T row)? actionsBuilder;
  final VoidCallback? onTap;
  final bool selected;

  @override
  State<_RisegTableRow<T>> createState() => _RisegTableRowState<T>();
}

class _RisegTableRowState<T> extends State<_RisegTableRow<T>> {
  final _focusNode = FocusNode();
  bool _focused = false;
  bool _hovered = false;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final interactive = widget.onTap != null;

    final background = widget.selected
        ? colors.accentSoftBg
        : (_hovered ? colors.surfaceSunken : Colors.transparent);
    final borderColor = _focused ? colors.focusRing : Colors.transparent;

    final content = Container(
      decoration: BoxDecoration(
        color: background,
        border: Border.all(color: borderColor, width: 2),
      ),
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm, horizontal: AppSpacing.sm),
      child: Row(
        children: [
          for (final column in widget.columns)
            _cellSlot(
              width: column.width,
              child: DefaultTextStyle.merge(
                style: AppTypography.body.copyWith(color: colors.textPrimary),
                child: Align(alignment: _alignmentFor(column.alignment), child: column.cellBuilder(widget.row)),
              ),
            ),
          if (widget.actionsWidth > 0)
            SizedBox(
              width: widget.actionsWidth,
              child: Align(
                alignment: Alignment.centerRight,
                child: widget.actionsBuilder?.call(widget.row) ?? const SizedBox.shrink(),
              ),
            ),
        ],
      ),
    );

    final row = Semantics(
      selected: widget.selected,
      button: interactive,
      child: content,
    );

    if (!interactive) return row;

    return InkWell(
      focusNode: _focusNode,
      onFocusChange: (value) => setState(() => _focused = value),
      onHover: (value) => setState(() => _hovered = value),
      onTap: widget.onTap,
      hoverColor: Colors.transparent,
      focusColor: Colors.transparent,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      child: row,
    );
  }

  Widget _cellSlot({required double? width, required Widget child}) {
    if (width != null) return SizedBox(width: width, child: child);
    return Expanded(child: child);
  }

  Alignment _alignmentFor(TextAlign align) {
    switch (align) {
      case TextAlign.center:
        return Alignment.center;
      case TextAlign.right:
      case TextAlign.end:
        return Alignment.centerRight;
      default:
        return Alignment.centerLeft;
    }
  }
}
