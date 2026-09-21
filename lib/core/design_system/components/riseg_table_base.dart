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
    this.hoverColor,
    this.rowVerticalPadding,
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

  /// Sobrescribe el fondo de hover (`colors.surfaceSunken` por defecto).
  /// `null` conserva el comportamiento actual en el resto del proyecto —
  /// Etapa 15, rediseño visual de Personal/Bajas: azul RISEG extremadamente
  /// suave (`colors.accentSoftBg`, el mismo tono que ya usa `selected`) en
  /// vez del gris neutro, solo en esas dos tablas.
  final Color? hoverColor;

  /// Sobrescribe el padding vertical de cada fila (`AppSpacing.sm` por
  /// defecto — `null` conserva ese valor en todas las tablas existentes).
  /// Etapa 16, evolución visual: filas con `RisegEntityIdentity` (avatar)
  /// necesitan un poco más de aire vertical que una fila de solo texto.
  final double? rowVerticalPadding;

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
              _estadoNoTabular(
                acotado: constraints.hasBoundedHeight,
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl),
                  child: Center(child: CircularProgressIndicator()),
                ),
              )
            else if (rows.isEmpty)
              _estadoNoTabular(
                acotado: constraints.hasBoundedHeight,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
                  child: emptyState ?? const SizedBox.shrink(),
                ),
              )
            else if (constraints.hasBoundedHeight)
              // Scroll vertical PROPIO — solo válido cuando el padre da
              // una altura acotada (`Expanded` en la pantalla llamadora,
              // ej. Egresos/Ingresos/Pagos). Etapa 15, hallazgo real:
              // sin esto, muchas filas desbordaban verticalmente
              // ("BOTTOM OVERFLOWED BY N PIXELS").
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: width,
                    child: SingleChildScrollView(child: _filas()),
                  ),
                ),
              )
            else
              // Padre con altura NO acotada (esta tabla embebida dentro
              // de una página con su propio `SingleChildScrollView` de
              // nivel superior, ej. la sección Unidades de Artículo) —
              // `Expanded` sería inválido aquí (`RenderFlex... incoming
              // height constraints are unbounded`). Se conserva el
              // comportamiento original: la `Column` de filas crece
              // libremente y es la página exterior quien scrollea.
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(width: width, child: _filas()),
              ),
          ],
        );
      },
    );
  }

  /// Envuelve el estado de carga/vacío (Etapa 16, evolución visual —
  /// hallazgo real: "RenderFlex overflowed" en una tabla dentro de un
  /// `Expanded` con muy poca altura disponible, ej. Nómina en ventanas
  /// bajas). Antes, el bloque de carga/vacío tenía un alto fijo (padding
  /// + spinner) que nunca respetaba el espacio acotado del padre — a
  /// diferencia de la rama "con filas", que ya usaba `Expanded` +
  /// scroll. Mismo criterio aquí: si el padre da altura acotada, el
  /// bloque se vuelve desplazable dentro de ese espacio en vez de
  /// desbordar; si no la da (página con su propio scroll), se conserva
  /// tal cual.
  Widget _estadoNoTabular({required bool acotado, required Widget child}) {
    if (!acotado) return child;
    return Expanded(child: SingleChildScrollView(child: child));
  }

  Widget _filas() {
    return FocusTraversalGroup(
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
              hoverColor: hoverColor,
              verticalPadding: rowVerticalPadding,
            ),
        ],
      ),
    );
  }

  double _minTableWidth(BuildContext context) {
    final fixed = columns.where((c) => c.width != null).fold<double>(0, (sum, c) => sum + c.width!);
    final flexCount = columns.where((c) => c.width == null).length;
    // Ancho mínimo razonable por columna flexible, solo para que el
    // scroll horizontal tenga un punto de partida sensato en anchos muy
    // reducidos — no es un layout definitivo por columna.
    //
    // 80, no 120 (Etapa 15, hallazgo real de Marlon en Configuración
    // comercial): con varias columnas fijas + acciones, 120px por
    // columna flexible empujaba el ancho mínimo por encima del ancho
    // real disponible (`AppBreakpoints.wide` menos el padding de página
    // y de `RisegCard`) incluso en pantallas anchas — forzando scroll
    // horizontal innecesario que dejaba la columna de acciones fuera del
    // viewport visible, sin ninguna pista de que hubiera más contenido a
    // la derecha. Bajar el piso es seguro en cualquier dirección: nunca
    // reduce el ancho real que reciben las columnas flexibles (`Expanded`
    // siempre usa el espacio disponible de verdad), solo pospone el
    // punto en que se activa el scroll forzado.
    final childCount = columns.length + (_actionsWidth > 0 ? 1 : 0);
    final gaps = childCount > 1 ? (childCount - 1) * AppSpacing.sm : 0.0;
    // El `Padding` horizontal de `_RisegTableHeader`/`_RisegTableRow`
    // (`AppSpacing.sm` por lado) y el borde de foco de la fila
    // (`Border.all(width: 2)`, siempre presente aunque transparente)
    // restan espacio real al `Row` interno una vez que `width` ya se
    // fijó — sin esto, cualquier tabla SIN ninguna columna flexible
    // (nada que absorba el faltante vía `Expanded`) desbordaba por
    // exactamente esta cantidad al forzarse al ancho mínimo (Etapa 15,
    // hallazgo real de Marlon: Pagos de Nómina, 4 columnas fijas, "RIGHT
    // OVERFLOWED BY 28 PIXELS"). Una tabla con columnas flexibles nunca
    // lo notaba porque `Expanded` absorbía el faltante en silencio.
    const chromeHorizontal = AppSpacing.sm * 2 + 4;
    return fixed + (flexCount * 80) + _actionsWidth + gaps + chromeHorizontal;
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
        // Sin esto, columnas consecutivas de ancho fijo quedaban sin
        // ningún espacio real entre sí — el label de una tocaba
        // visualmente al de la siguiente ("Monto totalMonto aplicado",
        // Etapa 15). Mismo `spacing` en `_RisegTableRow` para que
        // encabezado y celdas de datos sigan alineados.
        spacing: AppSpacing.sm,
        children: [
          for (final column in columns)
            _cellSlot(
              width: column.width,
              child: Semantics(
                header: true,
                child: Text(
                  column.label,
                  textAlign: column.alignment,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  softWrap: false,
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
    this.hoverColor,
    this.verticalPadding,
  });

  final T row;
  final List<RisegColumn<T>> columns;
  final double actionsWidth;
  final Widget Function(T row)? actionsBuilder;
  final VoidCallback? onTap;
  final bool selected;
  final Color? hoverColor;
  final double? verticalPadding;

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
        : (_hovered ? (widget.hoverColor ?? colors.surfaceSunken) : Colors.transparent);
    final borderColor = _focused ? colors.focusRing : Colors.transparent;

    final content = Container(
      decoration: BoxDecoration(
        color: background,
        border: Border.all(color: borderColor, width: 2),
      ),
      padding: EdgeInsets.symmetric(vertical: widget.verticalPadding ?? AppSpacing.sm, horizontal: AppSpacing.sm),
      child: Row(
        spacing: AppSpacing.sm,
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
