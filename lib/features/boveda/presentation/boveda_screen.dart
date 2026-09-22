import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/boveda/data/tables/boveda_credencial_table.dart';
import 'package:riseg_one/features/boveda/domain/usecases/dar_de_baja_credencial_boveda_usecase.dart';
import 'package:riseg_one/features/boveda/domain/usecases/reactivar_credencial_boveda_usecase.dart';
import 'package:riseg_one/features/boveda/domain/usecases/revelar_secreto_credencial_boveda_usecase.dart';

import '../boveda_providers.dart';
import 'boveda_controller.dart';
import 'boveda_labels.dart';
import 'widgets/cambiar_secreto_credencial_boveda_dialog.dart';
import 'widgets/credencial_boveda_historial_dialog.dart';
import 'widgets/credencial_boveda_detalle_dialog.dart';
import 'widgets/gestionar_credencial_boveda_dialog.dart';

/// Pantalla de la Bóveda de Accesos del Maestro (Etapa 14D) — pestaña
/// de `/configuracion`, exclusiva del Usuario Maestro (doble candado:
/// pestaña oculta + guard de router, ver `configuracion_shell_screen.dart`
/// y `app_router.dart`). Mostrar/copiar un secreto se resuelve en un
/// diálogo efímero (a diferencia del expediente único de un equipo
/// telefónico, esta es una tabla de varias filas — no tiene sentido un
/// estado "visible" persistente por fila) — se cierra solo, nunca deja
/// el secreto visible en la tabla.
class BovedaScreen extends ConsumerWidget {
  const BovedaScreen({super.key});

  Future<void> _nuevaCredencial(BuildContext context, WidgetRef ref) async {
    final actualizo = await mostrarDialogoGestionarCredencialBoveda(context, ref);
    if (actualizo) ref.read(bovedaControllerProvider.notifier).recargar();
  }

  Future<void> _editar(BuildContext context, WidgetRef ref, BovedaCredencialData credencial) async {
    final actualizo = await mostrarDialogoGestionarCredencialBoveda(context, ref, existente: credencial);
    if (actualizo) ref.read(bovedaControllerProvider.notifier).recargar();
  }

  Future<void> _cambiarSecreto(BuildContext context, WidgetRef ref, BovedaCredencialData credencial) async {
    await mostrarDialogoCambiarSecretoCredencialBoveda(context, ref, credencialId: credencial.id);
  }

  Future<void> _mostrarSecreto(BuildContext context, WidgetRef ref, BovedaCredencialData credencial) async {
    final l10n = AppLocalizations.of(context)!;
    final revelar = ref.read(revelarSecretoCredencialBovedaAutorizadoProvider);
    final resultado = await revelar(credencialId: credencial.id, accion: AccionRevelacionSecreto.mostrar);
    if (!context.mounted) return;
    switch (resultado) {
      case RevelarSecretoCredencialBovedaExitoso(:final secreto):
        await showDialog<void>(
          context: context,
          builder:
              (dialogContext) => AlertDialog(
                title: Text(credencial.nombre),
                content: SelectableText(secreto),
                actions: [
                  TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: Text(l10n.bovedaBotonCerrar)),
                ],
              ),
        );
      case RevelarSecretoCredencialBovedaSinSecreto():
        RisegFeedback.showError(context, l10n.bovedaSecretoNoConfigurado);
      case RevelarSecretoCredencialBovedaErrorInesperado():
        RisegFeedback.showError(context, l10n.bovedaErrorInesperado);
    }
  }

  Future<void> _copiarSecreto(BuildContext context, WidgetRef ref, BovedaCredencialData credencial) async {
    final l10n = AppLocalizations.of(context)!;
    final revelar = ref.read(revelarSecretoCredencialBovedaAutorizadoProvider);
    final resultado = await revelar(credencialId: credencial.id, accion: AccionRevelacionSecreto.copiar);
    if (!context.mounted) return;
    switch (resultado) {
      case RevelarSecretoCredencialBovedaExitoso(:final secreto):
        await Clipboard.setData(ClipboardData(text: secreto));
        if (!context.mounted) return;
        RisegFeedback.showSuccess(context, l10n.bovedaSecretoCopiadoExito);
      case RevelarSecretoCredencialBovedaSinSecreto():
        RisegFeedback.showError(context, l10n.bovedaSecretoNoConfigurado);
      case RevelarSecretoCredencialBovedaErrorInesperado():
        RisegFeedback.showError(context, l10n.bovedaErrorInesperado);
    }
  }

  Future<void> _historial(BuildContext context, WidgetRef ref, BovedaCredencialData credencial) {
    return mostrarDialogoHistorialCredencialBoveda(context, ref, credencialId: credencial.id);
  }

  Future<void> _darDeBaja(BuildContext context, WidgetRef ref, BovedaCredencialData credencial) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmado = await RisegDialog.showConfirmation(
      context: context,
      title: l10n.bovedaDarDeBajaConfirmarTitulo,
      message: l10n.bovedaDarDeBajaConfirmarMensaje,
      confirmLabel: l10n.bovedaDarDeBajaBotonConfirmar,
      cancelLabel: l10n.bovedaGestionarBotonCancelar,
      destructive: true,
      onConfirm: () async {
        final resultado = await ref.read(darDeBajaCredencialBovedaAutorizadoProvider)(id: credencial.id);
        if (!context.mounted) return;
        switch (resultado) {
          case DarDeBajaCredencialBovedaExitoso():
            ref.read(bovedaControllerProvider.notifier).recargar();
          case DarDeBajaCredencialBovedaErrorInesperado():
            RisegFeedback.showError(context, l10n.bovedaErrorInesperado);
        }
      },
    );
    if (confirmado != true) return;
  }

  Future<void> _reactivar(BuildContext context, WidgetRef ref, BovedaCredencialData credencial) async {
    final l10n = AppLocalizations.of(context)!;
    final resultado = await ref.read(reactivarCredencialBovedaAutorizadoProvider)(id: credencial.id);
    if (!context.mounted) return;
    switch (resultado) {
      case ReactivarCredencialBovedaExitoso():
        ref.read(bovedaControllerProvider.notifier).recargar();
      case ReactivarCredencialBovedaErrorInesperado():
        RisegFeedback.showError(context, l10n.bovedaErrorInesperado);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(bovedaControllerProvider);
    final notifier = ref.read(bovedaControllerProvider.notifier);

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RisegSectionHeader(
            title: l10n.bovedaTitulo,
            primaryAction: RisegButton(
              key: const Key('boveda_boton_nueva_credencial'),
              label: l10n.bovedaBotonNuevaCredencial,
              onPressed: () => _nuevaCredencial(context, ref),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          RisegCard(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.md,
                children: [
                  SizedBox(
                    width: 220,
                    child: RisegSelect<String?>(
                      label: l10n.bovedaCampoTipo,
                      value: state.tipo,
                      items: [
                        for (final t in TipoAccesoBoveda.values)
                          RisegSelectItem(value: t.name, label: tipoAccesoBovedaLabel(l10n, t.name)),
                      ],
                      onChanged: (valor) => notifier.aplicarFiltros(tipo: valor, limpiarTipo: valor == null),
                    ),
                  ),
                  SizedBox(
                    width: 160,
                    child: RisegSelect<bool>(
                      label: l10n.bovedaCampoEstatus,
                      value: state.soloActivos,
                      items: [
                        RisegSelectItem(value: true, label: l10n.bovedaEstatusActivo),
                        RisegSelectItem(value: false, label: l10n.bovedaFiltroTodos),
                      ],
                      onChanged: (valor) => notifier.aplicarFiltros(soloActivos: valor ?? true),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: RisegTableBase<BovedaCredencialData>(
              loading: state.cargando,
              rows: state.credenciales,
              // La fila entera abre la ficha: hasta ahora no hacía nada y
              // todo vivía escondido detrás del menú.
              onRowTap: (c) => mostrarDetalleCredencialBoveda(context, c.id),
              emptyState: RisegEmptyState(title: l10n.bovedaListaVaciaTitulo, message: l10n.bovedaListaVaciaMensaje),
              columns: [
                RisegColumn<BovedaCredencialData>(label: l10n.bovedaCampoNombre, cellBuilder: (c) => Text(c.nombre)),
                RisegColumn<BovedaCredencialData>(
                  label: l10n.bovedaCampoTipo,
                  width: 140,
                  cellBuilder: (c) => Text(tipoAccesoBovedaLabel(l10n, c.tipo)),
                ),
                RisegColumn<BovedaCredencialData>(
                  label: l10n.bovedaCampoUsuarioAcceso,
                  cellBuilder: (c) => Text(c.usuarioAcceso ?? '—'),
                ),
                RisegColumn<BovedaCredencialData>(
                  label: l10n.bovedaCampoEstatus,
                  width: 110,
                  cellBuilder:
                      (c) => RisegStatusBadge(
                        label: c.cicloVidaRegistro == 'activo' ? l10n.bovedaEstatusActivo : l10n.bovedaEstatusBaja,
                        tone: c.cicloVidaRegistro == 'activo' ? RisegStatusTone.success : RisegStatusTone.neutral,
                      ),
                ),
              ],
              actionsWidth: 56,
              rowActionsBuilder:
                  (c) => PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert),
                    onSelected: (accion) {
                      switch (accion) {
                        case 'editar':
                          _editar(context, ref, c);
                        case 'cambiarSecreto':
                          _cambiarSecreto(context, ref, c);
                        case 'mostrarSecreto':
                          _mostrarSecreto(context, ref, c);
                        case 'copiarSecreto':
                          _copiarSecreto(context, ref, c);
                        case 'historial':
                          _historial(context, ref, c);
                        case 'darDeBaja':
                          _darDeBaja(context, ref, c);
                        case 'reactivar':
                          _reactivar(context, ref, c);
                      }
                    },
                    itemBuilder:
                        (menuContext) => [
                          PopupMenuItem(value: 'editar', child: Text(l10n.bovedaAccionEditar)),
                          PopupMenuItem(value: 'cambiarSecreto', child: Text(l10n.bovedaAccionCambiarSecreto)),
                          PopupMenuItem(value: 'mostrarSecreto', child: Text(l10n.bovedaAccionMostrarSecreto)),
                          PopupMenuItem(value: 'copiarSecreto', child: Text(l10n.bovedaAccionCopiarSecreto)),
                          PopupMenuItem(value: 'historial', child: Text(l10n.bovedaAccionHistorial)),
                          if (c.cicloVidaRegistro == 'activo')
                            PopupMenuItem(value: 'darDeBaja', child: Text(l10n.bovedaAccionDarDeBaja))
                          else
                            PopupMenuItem(value: 'reactivar', child: Text(l10n.bovedaAccionReactivar)),
                        ],
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
