import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/organizacion/organizacion_providers.dart';
import 'package:riseg_one/features/vehiculos/domain/usecases/calcular_estado_vigencia_documento.dart';

import '../vehiculo_labels.dart';

final _formatoFecha = DateFormat('dd/MM/yyyy');

/// Histórico de renovaciones de un `tipo` de documento (Etapa 8C) —
/// [documentos] ya viene filtrado a un solo tipo y ordenado (el mismo
/// orden de `listarPorVehiculo`, el primero es el vigente). Solo
/// lectura, mismo patrón que `mostrarDialogoHistorialUnidad`.
Future<void> mostrarDialogoHistorialDocumentoVehiculo(
  BuildContext context,
  WidgetRef ref,
  List<VehiculoDocumentoData> documentos,
) async {
  final l10n = AppLocalizations.of(context)!;
  final adjuntoPorDocumento = <String, AttachmentData>{};
  for (final documento in documentos) {
    final adjuntos = await ref.read(attachmentRepositoryProvider).listarActivosPorVehiculoDocumento(documento.id);
    if (adjuntos.isNotEmpty) adjuntoPorDocumento[documento.id] = adjuntos.first;
  }
  if (!context.mounted) return;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.vehiculoDocumentoHistorialDialogoTitulo),
      content: SizedBox(
        width: 460,
        child: documentos.isEmpty
            ? Text(l10n.vehiculoDocumentoHistorialVacio)
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final documento in documentos)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  documento.fechaEmision == null
                                      ? '—'
                                      : _formatoFecha.format(documento.fechaEmision!),
                                ),
                                if (documento.numeroFolio != null)
                                  Text(
                                    documento.numeroFolio!,
                                    style: AppTypography.caption.copyWith(color: context.colors.textMuted),
                                  ),
                              ],
                            ),
                          ),
                          RisegStatusBadge(
                            label: estadoVigenciaDocumentoLabel(l10n, calcularEstadoVigenciaDocumento(documento.fechaVencimiento)),
                            tone: estadoVigenciaDocumentoTono(calcularEstadoVigenciaDocumento(documento.fechaVencimiento)),
                          ),
                          if (adjuntoPorDocumento.containsKey(documento.id)) ...[
                            const SizedBox(width: AppSpacing.xs),
                            RisegButton(
                              label: l10n.vehiculoDocumentoBotonAbrir,
                              variant: RisegButtonVariant.ghost,
                              size: RisegButtonSize.compact,
                              onPressed: () => ref.read(attachmentStorageProvider).abrir(adjuntoPorDocumento[documento.id]!.path),
                            ),
                          ],
                        ],
                      ),
                    ),
                ],
              ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: Text(l10n.vehiculoDocumentoHistorialBotonCerrar)),
      ],
    ),
  );
}
