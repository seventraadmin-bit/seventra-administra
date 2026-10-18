import 'package:flutter/material.dart';

import '../theme_context.dart';
import '../tokens/app_spacing.dart';
import '../tokens/app_typography.dart';

/// Campo de texto de RISEG ONE.
///
/// Compone sobre `TextFormField` — bordes, color de foco y de error ya
/// están resueltos en `InputDecorationTheme`; este widget solo agrega la
/// etiqueta estática arriba del campo (en vez del label flotante de
/// Material) y una API reducida a lo que los formularios de RISEG
/// necesitan de verdad.
class RisegTextField extends StatelessWidget {
  const RisegTextField({
    required this.label,
    this.controller,
    this.hint,
    this.helperText,
    this.errorText,
    this.enabled = true,
    this.readOnly = false,
    this.prefixIcon,
    this.suffixAction,
    this.keyboardType,
    this.obscureText = false,
    this.onChanged,
    this.onSubmitted,
    this.focusNode,
    this.autofocus = false,
    this.minLines,
    this.maxLines = 1,
    this.autofillHints,
    super.key,
  });

  final String label;
  final TextEditingController? controller;
  final String? hint;
  final String? helperText;

  /// No nulo activa el estado visual de error del borde/label, sin
  /// importar el resultado de ningún `Form` — el llamador decide cuándo
  /// mostrarlo.
  final String? errorText;
  final bool enabled;
  final bool readOnly;
  final IconData? prefixIcon;

  /// Acción al final del campo (ej. limpiar, mostrar contraseña) — un
  /// widget completo y no solo un ícono, para que el llamador controle su
  /// propio `onTap`/tooltip/estado.
  final Widget? suffixAction;
  final TextInputType? keyboardType;
  final bool obscureText;
  final ValueChanged<String>? onChanged;

  /// Dispara al presionar Enter/Intro (`TextInputAction.done` es el
  /// valor por defecto de `TextFormField` sin `keyboardType` de texto
  /// multilínea) — pensado para "Enter en Contraseña inicia sesión" y
  /// formularios similares de una sola línea por campo.
  final ValueChanged<String>? onSubmitted;
  final FocusNode? focusNode;
  final bool autofocus;

  /// Altura inicial en líneas — sólo tiene efecto junto con un
  /// [maxLines] mayor que uno.
  final int? minLines;

  /// `1` por defecto: TODOS los campos del proyecto eran de una línea y
  /// siguen siéndolo. Se sube sólo donde el dato es redacción y no un
  /// valor corto — el primer caso real es "Descripción y uso" de la
  /// Bóveda, que explica para qué sirve un acceso y tiene que poder
  /// escribirse en varios párrafos. `null` significa sin límite.
  final int? maxLines;

  /// Las pistas que el gestor de contrasenas del navegador lee.
  ///
  /// PASA DERECHO AL CAMPO DE FLUTTER y por omision es nula, asi que el escritorio
  /// no cambia en nada. Existe porque en la web, sin ellas —y sin un AutofillGroup
  /// alrededor— Chrome no ofrece la contrasena guardada ni propone guardar la nueva,
  /// y una aplicacion donde el gestor de contrasenas no funciona empuja a usar
  /// contrasenas que se puedan recordar.
  final List<String>? autofillHints;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: AppTypography.label.copyWith(color: colors.textMuted)),
        const SizedBox(height: AppSpacing.xxs),
        TextFormField(
          controller: controller,
          enabled: enabled,
          readOnly: readOnly,
          keyboardType: keyboardType,
          obscureText: obscureText,
          onChanged: onChanged,
          onFieldSubmitted: onSubmitted,
          focusNode: focusNode,
          autofillHints: autofillHints,
          autofocus: autofocus,
          minLines: minLines,
          maxLines: maxLines,
          style: AppTypography.body.copyWith(color: colors.textPrimary),
          decoration: InputDecoration(
            hintText: hint,
            helperText: helperText,
            errorText: errorText,

            // UN MENSAJE DE ERROR CORTADO NO SIRVE DE NADA, y por omisión Flutter
            // los corta: `errorMaxLines` vale 1, así que todo lo que no quepa en el
            // ancho del campo se sustituye por puntos suspensivos.
            //
            // Medido el 17 de octubre de 2026 con el 409 de un código de área
            // repetido: en pantalla se leía «Los códigos no se re…», que es
            // exactamente la mitad que no dice qué hacer.
            //
            // Los errores que vienen del servidor no se pueden acortar desde aquí
            // —los escribe el backend— así que lo que tiene que ceder es el número
            // de líneas. Tres bastan para cualquiera de los mensajes actuales y
            // evitan que un texto desbocado empuje el formulario entero.
            errorMaxLines: 3,

            // Lo mismo para la ayuda: «En mayúsculas, sin espacios. Por ejemplo
            // OPERACIONES.» se corta en un panel estrecho.
            helperMaxLines: 2,
            prefixIcon: prefixIcon == null ? null : Icon(prefixIcon, size: 20),
            suffixIcon: suffixAction,
          ),
        ),
      ],
    );
  }
}
