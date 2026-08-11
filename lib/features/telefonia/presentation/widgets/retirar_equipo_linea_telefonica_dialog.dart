import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/telefonia/domain/usecases/retirar_equipo_linea_telefonica_usecase.dart';

import '../../telefonia_providers.dart';

/// Diálogo "Retirar equipo" (Etapa 9B) — quita el teléfono asociado a
/// una línea sin reemplazo; la línea queda sin equipo, algo
/// completamente válido. Devuelve `true` si tuvo éxito.
Future<bool> mostrarDialogoRetirarEquipoLineaTelefonica(
  BuildContext context,
  WidgetRef ref,
  String lineaTelefonicaId,
) async {
  final l10n = AppLocalizations.of(context)!;

  DateTime fechaFin = DateTime.now();
  String? errorGeneral;

  final resultado = await RisegDialog.showForm<bool>(
    context: context,
    title: l10n.lineaTelefonicaRetirarEquipoDialogoTitulo,
    confirmLabel: l10n.lineaTelefonicaRetirarEquipoBotonConfirmar,
    cancelLabel: l10n.lineaTelefonicaBotonCancelar,
    contentBuilder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        return SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RisegDateField(
                label: l10n.lineaTelefonicaRetirarEquipoCampoFecha,
                value: fechaFin,
                onChanged: (valor) => setState(() => fechaFin = valor),
              ),
              if (errorGeneral != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(errorGeneral!, style: AppTypography.caption.copyWith(color: Theme.of(dialogContext).colorScheme.error)),
              ],
            ],
          ),
        );
      },
    ),
    onConfirm: () async {
      final resultado = await ref
          .read(retirarEquipoLineaTelefonicaAutorizadoProvider)(lineaTelefonicaId: lineaTelefonicaId, fechaFin: fechaFin);
      switch (resultado) {
        case RetirarEquipoLineaTelefonicaExitoso():
          if (context.mounted) RisegFeedback.showSuccess(context, l10n.lineaTelefonicaRetirarEquipoExito);
          return true;
        case RetirarEquipoLineaTelefonicaSinEquipoVigente():
          errorGeneral = l10n.lineaTelefonicaEquipoErrorSinEquipoVigente;
          return null;
        case RetirarEquipoLineaTelefonicaErrorInesperado():
          if (context.mounted) RisegFeedback.showError(context, l10n.lineaTelefonicaErrorInesperado);
          return false;
      }
    },
  );

  return resultado ?? false;
}
