import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/boveda/data/tables/boveda_credencial_table.dart';
import 'package:riseg_one/features/boveda/domain/usecases/actualizar_credencial_boveda_usecase.dart';
import 'package:riseg_one/features/boveda/domain/usecases/crear_credencial_boveda_usecase.dart';

import '../../boveda_providers.dart';
import '../boveda_labels.dart';

/// Diálogo de alta/edición de una credencial de la Bóveda (Etapa 14D)
/// — mismo formulario reutilizado en los dos contextos (patrón ya
/// usado por `mostrarDialogoConfigurarEquipoTelefonico`, Etapa 9D).
/// **Nunca captura el secreto en edición** (solo en alta, opcional) —
/// cambiarlo después es siempre a través de
/// `CambiarSecretoCredencialBovedaDialog`, un flujo dedicado y
/// separado. Devuelve `true` si hubo un cambio persistido.
Future<bool> mostrarDialogoGestionarCredencialBoveda(BuildContext context, WidgetRef ref, {BovedaCredencialData? existente}) async {
  final l10n = AppLocalizations.of(context)!;
  final esAlta = existente == null;

  final nombreCtrl = TextEditingController(text: existente?.nombre ?? '');
  final usuarioAccesoCtrl = TextEditingController(text: existente?.usuarioAcceso ?? '');
  final correoCtrl = TextEditingController(text: existente?.correo ?? '');
  final secretoCtrl = TextEditingController();
  final urlCtrl = TextEditingController(text: existente?.url ?? '');
  final observacionesCtrl = TextEditingController(text: existente?.observaciones ?? '');
  String tipoSeleccionado = existente?.tipo ?? TipoAccesoBoveda.otro.name;
  String? errorGeneral;

  final resultado = await RisegDialog.showForm<bool>(
    context: context,
    title: esAlta ? l10n.bovedaGestionarDialogoTituloAlta : l10n.bovedaGestionarDialogoTituloEdicion,
    confirmLabel: l10n.bovedaGestionarBotonConfirmar,
    cancelLabel: l10n.bovedaGestionarBotonCancelar,
    contentBuilder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        return SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RisegTextField(label: l10n.bovedaCampoNombre, controller: nombreCtrl),
              const SizedBox(height: AppSpacing.md),
              RisegSelect<String>(
                label: l10n.bovedaCampoTipo,
                value: tipoSeleccionado,
                items: [
                  for (final t in TipoAccesoBoveda.values) RisegSelectItem(value: t.name, label: tipoAccesoBovedaLabel(l10n, t.name)),
                ],
                onChanged: (valor) => setState(() => tipoSeleccionado = valor ?? tipoSeleccionado),
              ),
              const SizedBox(height: AppSpacing.md),
              RisegTextField(label: l10n.bovedaCampoUsuarioAcceso, controller: usuarioAccesoCtrl),
              const SizedBox(height: AppSpacing.md),
              RisegTextField(label: l10n.bovedaCampoCorreo, controller: correoCtrl),
              if (esAlta) ...[
                const SizedBox(height: AppSpacing.md),
                RisegTextField(label: l10n.bovedaCampoSecreto, controller: secretoCtrl, obscureText: true),
              ],
              const SizedBox(height: AppSpacing.md),
              RisegTextField(label: l10n.bovedaCampoUrl, controller: urlCtrl),
              const SizedBox(height: AppSpacing.md),
              // Para qué sirve este acceso: es lo que permite que otra persona
              // autorizada entienda la credencial sin preguntarle a nadie.
              // Arranca con cuatro líneas y crece hasta ocho antes de
              // desplazarse por dentro, para no empujar los botones fuera
              // del formulario.
              RisegTextField(
                key: const Key('boveda_campo_descripcion'),
                label: l10n.bovedaCampoObservaciones,
                controller: observacionesCtrl,
                minLines: 4,
                maxLines: 8,
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
      if (nombreCtrl.text.trim().isEmpty) {
        errorGeneral = l10n.bovedaErrorNombreRequerido;
        return null;
      }

      if (esAlta) {
        final crear = ref.read(crearCredencialBovedaAutorizadoProvider);
        final resultado = await crear(
          nombre: nombreCtrl.text.trim(),
          tipo: tipoSeleccionado,
          usuarioAcceso: usuarioAccesoCtrl.text.trim().isEmpty ? null : usuarioAccesoCtrl.text.trim(),
          correo: correoCtrl.text.trim().isEmpty ? null : correoCtrl.text.trim(),
          secreto: secretoCtrl.text.isEmpty ? null : secretoCtrl.text,
          url: urlCtrl.text.trim().isEmpty ? null : urlCtrl.text.trim(),
          observaciones: observacionesCtrl.text.trim().isEmpty ? null : observacionesCtrl.text.trim(),
        );
        if (!context.mounted) return false;
        switch (resultado) {
          case CrearCredencialBovedaExitoso():
            RisegFeedback.showSuccess(context, l10n.bovedaGestionarExito);
            return true;
          case CrearCredencialBovedaNombreRequerido():
            errorGeneral = l10n.bovedaErrorNombreRequerido;
            return null;
          case CrearCredencialBovedaErrorInesperado():
            RisegFeedback.showError(context, l10n.bovedaErrorInesperado);
            return false;
        }
      } else {
        final actualizar = ref.read(actualizarCredencialBovedaAutorizadoProvider);
        final resultado = await actualizar(
          id: existente.id,
          nombre: nombreCtrl.text.trim(),
          tipo: tipoSeleccionado,
          usuarioAcceso: usuarioAccesoCtrl.text.trim().isEmpty ? null : usuarioAccesoCtrl.text.trim(),
          correo: correoCtrl.text.trim().isEmpty ? null : correoCtrl.text.trim(),
          url: urlCtrl.text.trim().isEmpty ? null : urlCtrl.text.trim(),
          observaciones: observacionesCtrl.text.trim().isEmpty ? null : observacionesCtrl.text.trim(),
          limpiarUsuarioAcceso: usuarioAccesoCtrl.text.trim().isEmpty,
          limpiarCorreo: correoCtrl.text.trim().isEmpty,
          limpiarUrl: urlCtrl.text.trim().isEmpty,
          limpiarObservaciones: observacionesCtrl.text.trim().isEmpty,
        );
        if (!context.mounted) return false;
        switch (resultado) {
          case ActualizarCredencialBovedaExitoso():
            RisegFeedback.showSuccess(context, l10n.bovedaGestionarExito);
            return true;
          case ActualizarCredencialBovedaNombreRequerido():
            errorGeneral = l10n.bovedaErrorNombreRequerido;
            return null;
          case ActualizarCredencialBovedaNoExiste():
          case ActualizarCredencialBovedaErrorInesperado():
            RisegFeedback.showError(context, l10n.bovedaErrorInesperado);
            return false;
        }
      }
    },
  );

  WidgetsBinding.instance.addPostFrameCallback((_) {
    nombreCtrl.dispose();
    usuarioAccesoCtrl.dispose();
    correoCtrl.dispose();
    secretoCtrl.dispose();
    urlCtrl.dispose();
    observacionesCtrl.dispose();
  });
  return resultado ?? false;
}
