import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/usuarios/usuarios_providers.dart';

import '../../boveda_providers.dart';
import '../boveda_labels.dart';

final _formatoFechaHora = DateFormat('dd/MM/yyyy HH:mm');

/// Historial de alta/cambios/baja/reactivación de una credencial de la
/// Bóveda (Etapa 14D) — sección inline por credencial, no integrada en
/// la Auditoría central en esta etapa (alcance controlado, ver plan).
/// `observacion` nunca contiene el secreto ni su forma cifrada — lo
/// garantiza `BovedaCredencialRepositoryImpl.registrarEvento`, este
/// diálogo solo muestra lo que ya llegó limpio.
Future<void> mostrarDialogoHistorialCredencialBoveda(BuildContext context, WidgetRef ref, {required String credencialId}) async {
  final l10n = AppLocalizations.of(context)!;
  final eventos = await ref.read(bovedaCredencialRepositoryProvider).listarEventos(credencialId);
  final usuarios = await ref.read(usuarioRepositoryProvider).listar(cicloVidaRegistro: null);
  final nombrePorId = {for (final u in usuarios) u.id: u.nombre};
  if (!context.mounted) return;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.bovedaHistorialDialogoTitulo),
      content: SizedBox(
        width: 460,
        child: eventos.isEmpty
            ? Text(l10n.bovedaHistorialVacio)
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final evento in eventos)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${_formatoFechaHora.format(evento.fechaHora)} · ${eventoCredencialBovedaLabel(l10n, evento.tipoEvento)}',
                              style: AppTypography.label,
                            ),
                            Text(
                              nombrePorId[evento.actorUsuarioId] ?? l10n.usuarioHistorialConfiguracionInicial,
                              style: AppTypography.caption,
                            ),
                            if (evento.observacion != null && evento.observacion!.trim().isNotEmpty)
                              Text(evento.observacion!, style: AppTypography.caption),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: Text(l10n.vehiculoDocumentoHistorialBotonCerrar)),
      ],
    ),
  );
}
