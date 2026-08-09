import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:riseg_one/core/design_system/design_system.dart';

import '../agenda_controller.dart';

final _formatoFechaHora = DateFormat('dd/MM/yyyy HH:mm');

/// Muestra las versiones archivadas de los adjuntos de un documento
/// (Resolución 6 de Marlon: nunca se pierde trazabilidad, pero solo se
/// consultan explícitamente desde el historial — nunca en la lista
/// normal de adjuntos).
Future<void> mostrarDialogoVersionesArchivadas(BuildContext context, WidgetRef ref, String documentoPorEmitirId) async {
  final l10n = AppLocalizations.of(context)!;
  final archivados =
      await ref.read(agendaControllerProvider.notifier).listarAdjuntosArchivados(documentoPorEmitirId);
  if (!context.mounted) return;

  await RisegDialog.showInformational(
    context: context,
    title: l10n.agendaVersionesArchivadasDialogoTitulo,
    message: archivados.isEmpty
        ? l10n.agendaVersionesArchivadasSinVersiones
        : archivados
            .map((a) => '${a.originalFileName} · ${a.categoria ?? ''} · ${_formatoFechaHora.format(a.createdAt)}')
            .join('\n'),
    dismissLabel: l10n.agendaVersionesArchivadasBotonCerrar,
  );
}
