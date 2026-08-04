import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'package:riseg_one/core/design_system/design_system.dart';

/// Sección "Logotipo institucional" — siempre de solo lectura en ambos
/// modos: muestra el logotipo estático de la aplicación
/// (`assets/images/logo.png`), sin recorte ni filtros. No escribe
/// `logoAttachmentId` ni crea un `Attachment`; eso queda fuera del
/// alcance de la Etapa 4B.
class LogotipoSection extends StatelessWidget {
  const LogotipoSection({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;

    return RisegFormSection(
      title: l10n.empresaSeccionLogotipoTitulo,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 88),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Image.asset('assets/images/logo.png', fit: BoxFit.contain),
          ),
        ),
        Text(l10n.empresaSeccionLogotipoNota, style: AppTypography.caption.copyWith(color: colors.textMuted)),
      ],
    );
  }
}
