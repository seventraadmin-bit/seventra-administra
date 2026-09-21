import 'dart:io';

import 'package:flutter/material.dart';

import '../theme_context.dart';
import '../tokens/app_color_scheme.dart';
import '../tokens/app_radius.dart';
import '../tokens/app_spacing.dart';
import '../tokens/app_typography.dart';

/// Forma de la imagen en [RisegEntityIdentity].
enum RisegEntityImageShape {
  /// Fotos de personas — recorta con `BoxFit.cover`, apropiado cuando
  /// perder los bordes de la imagen no pierde información relevante.
  circular,

  /// Logotipos/marcas — `BoxFit.contain` sobre un fondo neutro, NUNCA
  /// recorta: la proporción original del logo se conserva siempre.
  cuadradaRedondeada,
}

/// Identidad visual de una entidad (Etapa 16, evolución visual del
/// Design System) — imagen/avatar + texto primario + texto secundario,
/// con fallback de iniciales cuando no hay imagen. Reutilizable para
/// Cliente (logo), Empleado (fotografía) y futuras entidades — nunca
/// duplicar esta composición a mano por pantalla (antes se repetía
/// distinto en `empleado_expediente_screen.dart`/
/// `vehiculo_expediente_screen.dart`/`app_top_bar.dart`).
///
/// Lee la imagen directamente de disco vía `File(imagenPath)` — mismo
/// criterio ya establecido por el avatar del expediente de Empleado
/// (`AttachmentStorage` no expone lectura de bytes; esta es la única
/// fuente real, nunca una segunda copia).
class RisegEntityIdentity extends StatelessWidget {
  const RisegEntityIdentity({
    required this.primario,
    this.secundario,
    this.imagenPath,
    this.forma = RisegEntityImageShape.circular,
    this.tamano = 40,
    super.key,
  });

  final String primario;
  final String? secundario;

  /// Ruta de archivo real en disco — `null` (o un archivo inexistente)
  /// cae al fallback de iniciales, nunca a un error visual.
  final String? imagenPath;
  final RisegEntityImageShape forma;
  final double tamano;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _imagen(colors),
        const SizedBox(width: AppSpacing.sm),
        Flexible(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                primario,
                style: AppTypography.bodyStrong.copyWith(color: colors.textPrimary),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
              if (secundario != null && secundario!.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  secundario!,
                  style: AppTypography.caption.copyWith(color: colors.textMuted),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _imagen(AppColorScheme colors) {
    final archivo = imagenPath == null ? null : File(imagenPath!);
    final existe = archivo != null && archivo.existsSync();

    if (forma == RisegEntityImageShape.circular) {
      return CircleAvatar(
        radius: tamano / 2,
        backgroundColor: colors.accentSoftBg,
        backgroundImage: existe ? FileImage(archivo) : null,
        child: existe ? null : _iniciales(colors),
      );
    }

    return ClipRRect(
      borderRadius: AppRadius.mdRadius,
      child: Container(
        width: tamano,
        height: tamano,
        color: existe ? colors.surface : colors.accentSoftBg,
        padding: existe ? const EdgeInsets.all(AppSpacing.xxs) : EdgeInsets.zero,
        alignment: Alignment.center,
        child: existe
            ? Image.file(archivo, fit: BoxFit.contain)
            : _iniciales(colors),
      ),
    );
  }

  Widget _iniciales(AppColorScheme colors) {
    return Text(
      inicialesDe(primario),
      style: AppTypography.label.copyWith(color: colors.accentText, fontSize: tamano * 0.32),
    );
  }
}

/// Iniciales de un nombre (Etapa 16) — hasta 2 letras, primera letra de
/// las 2 primeras palabras; una sola palabra da 1 letra. `''` si
/// `nombre` está vacío tras `trim()` (nunca lanza, el llamador decide
/// qué mostrar en ese caso — [RisegEntityIdentity] simplemente queda
/// con un espacio en blanco, no un error).
String inicialesDe(String nombre) {
  final palabras = nombre.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (palabras.isEmpty) return '';
  if (palabras.length == 1) return palabras.first.substring(0, 1).toUpperCase();
  return (palabras[0].substring(0, 1) + palabras[1].substring(0, 1)).toUpperCase();
}
