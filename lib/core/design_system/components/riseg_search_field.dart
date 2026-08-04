import 'package:flutter/material.dart';

import '../theme_context.dart';
import '../tokens/app_radius.dart';
import '../tokens/app_spacing.dart';
import '../tokens/app_typography.dart';

/// Campo de búsqueda de RISEG ONE.
///
/// Deliberadamente separado de [RisegTextField]: densidad e intención
/// distintas (más compacto, siempre con ícono de lupa, pensado para vivir
/// en barras/encabezados en vez de formularios). En esta etapa es
/// puramente visual — sin lógica de búsqueda real.
class RisegSearchField extends StatelessWidget {
  const RisegSearchField({
    required this.hint,
    this.controller,
    this.onChanged,
    this.compact = false,
    super.key,
  });

  final String hint;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;

  /// Colapsa a un botón de solo ícono — para anchos reducidos donde el
  /// campo completo no cabe (ver `AppTopBar`, que decide cuándo activarlo
  /// según el ancho disponible).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    if (compact) {
      return IconButton(
        tooltip: hint,
        icon: const Icon(Icons.search),
        onPressed: () {},
      );
    }

    // Sin relleno, solo un borde sutil: un fondo sólido compite demasiado
    // con el resto de la barra que lo contiene. Discreto no significa
    // oculto — sigue siendo claramente un campo de búsqueda.
    final border = OutlineInputBorder(
      borderRadius: AppRadius.mdRadius,
      borderSide: BorderSide(color: colors.borderSubtle),
    );

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 300, minWidth: 160),
      child: SizedBox(
        height: 36,
        child: TextField(
          controller: controller,
          onChanged: onChanged,
          style: AppTypography.body.copyWith(color: colors.textMuted),
          decoration: InputDecoration(
            isDense: true,
            prefixIcon: Icon(Icons.search, size: 18, color: colors.textMuted),
            prefixIconConstraints: const BoxConstraints(minWidth: 34, minHeight: 34),
            contentPadding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            hintText: hint,
            hintStyle: AppTypography.body.copyWith(color: colors.textMuted),
            filled: false,
            border: border,
            enabledBorder: border,
          ),
        ),
      ),
    );
  }
}
