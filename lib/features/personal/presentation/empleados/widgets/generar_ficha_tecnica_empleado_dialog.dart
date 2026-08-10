import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/personal/domain/usecases/ficha_tecnica_data.dart';
import 'package:riseg_one/features/personal/domain/usecases/generar_ficha_tecnica_empleado_usecase.dart';

import '../../../personal_providers.dart';

String _seccionLabel(AppLocalizations l10n, String clave) {
  return switch (clave) {
    SeccionFichaTecnica.fotografia => l10n.fichaTecnicaSeccionFotografia,
    SeccionFichaTecnica.zonaResidencia => l10n.fichaTecnicaSeccionZonaResidencia,
    SeccionFichaTecnica.contacto => l10n.fichaTecnicaSeccionContacto,
    SeccionFichaTecnica.perfilPsicologico => l10n.fichaTecnicaSeccionPerfilPsicologico,
    SeccionFichaTecnica.estudioSocioeconomico => l10n.fichaTecnicaSeccionEstudioSocioeconomico,
    SeccionFichaTecnica.antidoping => l10n.fichaTecnicaSeccionAntidoping,
    SeccionFichaTecnica.servicioTurno => l10n.fichaTecnicaSeccionServicioTurno,
    _ => clave,
  };
}

/// Diálogo previo a generar la Ficha técnica (Etapa 5E) — deja elegir
/// qué secciones **opcionales** incluir; los datos núcleo (nombre,
/// edad, puesto, experiencia) nunca se preguntan, siempre se incluyen.
/// Solo se ofrece una sección si el expediente realmente tiene ese dato
/// capturado (Resolución 5 de Marlon) — nunca se muestra una opción
/// para algo que de todas formas saldría vacío.
///
/// Devuelve `true` si la Ficha se generó correctamente.
Future<bool> mostrarDialogoGenerarFichaTecnicaEmpleado(
  BuildContext context,
  WidgetRef ref, {
  required EmpleadoData empleado,
  required DireccionData? domicilio,
  required AsignacionServicioData? asignacionVigente,
}) async {
  final l10n = AppLocalizations.of(context)!;

  final antidopingDisponible = empleado.fechaAntidoping != null &&
      [
        empleado.resultadoAmp,
        empleado.resultadoBzd,
        empleado.resultadoCoc,
        empleado.resultadoMet,
        empleado.resultadoOpi,
      ].any((r) => r != null && r != 'noAplica');

  final disponibilidad = <String, bool>{
    SeccionFichaTecnica.fotografia: empleado.fotografiaAttachmentId != null,
    SeccionFichaTecnica.zonaResidencia: domicilio != null,
    SeccionFichaTecnica.contacto: empleado.telefono != null ||
        empleado.contactoEmergenciaNombre != null ||
        empleado.telefonoEmergencia != null ||
        empleado.parentescoEmergencia != null,
    SeccionFichaTecnica.perfilPsicologico:
        empleado.fechaEvaluacionPsicologica != null && (empleado.resumenPsicologico?.trim().isNotEmpty ?? false),
    SeccionFichaTecnica.estudioSocioeconomico:
        empleado.fechaEstudioSocioeconomico != null && (empleado.resumenEstudioSocioeconomico?.trim().isNotEmpty ?? false),
    SeccionFichaTecnica.antidoping: antidopingDisponible,
    SeccionFichaTecnica.servicioTurno: asignacionVigente != null,
  };

  final seccionesDisponibles = [for (final c in SeccionFichaTecnica.todas) if (disponibilidad[c] == true) c];
  // Todo marcado por defecto (Resolución 5 de Marlon).
  final seccionesIncluidas = seccionesDisponibles.toSet();

  final confirmado = await RisegDialog.showForm<bool>(
    context: context,
    title: l10n.fichaTecnicaDialogoTitulo,
    confirmLabel: l10n.fichaTecnicaBotonGenerar,
    cancelLabel: l10n.fichaTecnicaBotonCancelar,
    contentBuilder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.fichaTecnicaDialogoDescripcion, style: AppTypography.body),
            const SizedBox(height: AppSpacing.md),
            if (seccionesDisponibles.isEmpty)
              Text(l10n.fichaTecnicaSinSeccionesOpcionales, style: AppTypography.caption)
            else
              for (final clave in seccionesDisponibles)
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(_seccionLabel(l10n, clave)),
                  value: seccionesIncluidas.contains(clave),
                  onChanged: (marcado) => setState(() {
                    if (marcado ?? false) {
                      seccionesIncluidas.add(clave);
                    } else {
                      seccionesIncluidas.remove(clave);
                    }
                  }),
                ),
          ],
        );
      },
    ),
    onConfirm: () async {
      final excluidas = seccionesDisponibles.where((c) => !seccionesIncluidas.contains(c)).toSet();
      final resultado = await ref
          .read(generarFichaTecnicaEmpleadoUseCaseProvider)
          .ejecutar(empleadoId: empleado.id, seccionesExcluidas: excluidas);

      if (!context.mounted) return null;

      switch (resultado) {
        case GenerarFichaTecnicaEmpleadoExitoso():
          return true;
        case GenerarFichaTecnicaEmpleadoNoExiste():
        case GenerarFichaTecnicaEmpleadoErrorInesperado():
          RisegFeedback.showError(context, l10n.fichaTecnicaErrorInesperado);
          return null;
      }
    },
  );

  if (confirmado != true) return false;
  if (!context.mounted) return false;
  RisegFeedback.showSuccess(context, l10n.fichaTecnicaExito);
  return true;
}
