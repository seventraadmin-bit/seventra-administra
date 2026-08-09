import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/finanzas/data/tables/categoria_financiera_table.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/archivar_categoria_financiera_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/crear_categoria_financiera_usecase.dart';

import '../../finanzas_providers.dart';
import 'categorias_list_controller.dart';

String categoriaTipoLabel(AppLocalizations l10n, String valor) {
  return switch (TipoCategoriaFinanciera.values.byName(valor)) {
    TipoCategoriaFinanciera.ingreso => l10n.categoriaTipoIngreso,
    TipoCategoriaFinanciera.egreso => l10n.categoriaTipoEgreso,
    TipoCategoriaFinanciera.ambos => l10n.categoriaTipoAmbos,
  };
}

String categoriaTipoMovimientoLabel(AppLocalizations l10n, String valor) {
  return switch (TipoMovimientoCategoriaFinanciera.values.byName(valor)) {
    TipoMovimientoCategoriaFinanciera.operativo => l10n.categoriaTipoMovimientoOperativo,
    TipoMovimientoCategoriaFinanciera.administrativo => l10n.categoriaTipoMovimientoAdministrativo,
    TipoMovimientoCategoriaFinanciera.financiero => l10n.categoriaTipoMovimientoFinanciero,
  };
}

/// Catálogo administrable de Categorías financieras (Etapa 4K.1) — solo
/// alta y archivado, sin edición (el catálogo nace vacío y RISEG lo
/// captura conforme lo necesita; mismo criterio simple que `Área`).
class CategoriasListScreen extends ConsumerWidget {
  const CategoriasListScreen({super.key});

  Future<void> _mostrarDialogoAlta(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    final codigoController = TextEditingController();
    final nombreController = TextEditingController();
    TipoCategoriaFinanciera tipoSeleccionado = TipoCategoriaFinanciera.ambos;
    TipoMovimientoCategoriaFinanciera tipoMovimientoSeleccionado = TipoMovimientoCategoriaFinanciera.operativo;

    final resultado = await RisegDialog.showForm<CrearCategoriaFinancieraResultado>(
      context: context,
      title: l10n.categoriaDialogoTituloAlta,
      confirmLabel: l10n.categoriaDialogoBotonGuardar,
      cancelLabel: l10n.categoriaDialogoBotonCancelar,
      contentBuilder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RisegTextField(label: l10n.categoriaCampoCodigo, controller: codigoController, autofocus: true),
              const SizedBox(height: AppSpacing.md),
              RisegTextField(label: l10n.categoriaCampoNombre, controller: nombreController),
              const SizedBox(height: AppSpacing.md),
              RisegSelect<TipoCategoriaFinanciera>(
                label: l10n.categoriaCampoTipo,
                value: tipoSeleccionado,
                items: [
                  for (final t in TipoCategoriaFinanciera.values)
                    RisegSelectItem(value: t, label: categoriaTipoLabel(l10n, t.name)),
                ],
                onChanged: (valor) => setState(() => tipoSeleccionado = valor ?? tipoSeleccionado),
              ),
              const SizedBox(height: AppSpacing.md),
              RisegSelect<TipoMovimientoCategoriaFinanciera>(
                label: l10n.categoriaCampoTipoMovimiento,
                value: tipoMovimientoSeleccionado,
                items: [
                  for (final t in TipoMovimientoCategoriaFinanciera.values)
                    RisegSelectItem(value: t, label: categoriaTipoMovimientoLabel(l10n, t.name)),
                ],
                onChanged: (valor) => setState(() => tipoMovimientoSeleccionado = valor ?? tipoMovimientoSeleccionado),
              ),
            ],
          );
        },
      ),
      onConfirm: () => ref.read(crearCategoriaFinancieraUseCaseProvider).ejecutar(
            codigo: codigoController.text,
            nombre: nombreController.text,
            tipo: tipoSeleccionado.name,
            tipoMovimiento: tipoMovimientoSeleccionado.name,
          ),
    );

    codigoController.dispose();
    nombreController.dispose();

    if (!context.mounted) return;

    switch (resultado) {
      case CrearCategoriaFinancieraExitoso():
        ref.read(categoriasListControllerProvider.notifier).recargar();
        RisegFeedback.showSuccess(context, l10n.categoriaGuardadoExito);
      case CrearCategoriaFinancieraCodigoRequerido():
      case CrearCategoriaFinancieraNombreRequerido():
      case CrearCategoriaFinancieraErrorInesperado():
        RisegFeedback.showError(context, l10n.categoriaGuardadoError);
      case null:
        break;
    }
  }

  Future<void> _archivar(BuildContext context, WidgetRef ref, CategoriaFinancieraData categoria) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmado = await RisegDialog.showConfirmation(
      context: context,
      title: l10n.categoriaConfirmarArchivarTitulo,
      message: l10n.categoriaConfirmarArchivarMensaje,
      confirmLabel: l10n.sucursalConfirmarAceptar,
      cancelLabel: l10n.sucursalConfirmarCancelar,
      destructive: true,
    );
    if (confirmado != true) return;

    final resultado = await ref.read(archivarCategoriaFinancieraUseCaseProvider).ejecutar(categoria.id);
    if (!context.mounted) return;

    switch (resultado) {
      case ArchivarCategoriaFinancieraExitoso():
        ref.read(categoriasListControllerProvider.notifier).recargar();
        RisegFeedback.showSuccess(context, l10n.categoriaCicloVidaCambiadoExito);
      case ArchivarCategoriaFinancieraNoExiste():
      case ArchivarCategoriaFinancieraErrorInesperado():
        RisegFeedback.showError(context, l10n.categoriaGuardadoError);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(categoriasListControllerProvider);
    final notifier = ref.read(categoriasListControllerProvider.notifier);

    if (state.errorCarga != null && state.categorias.isEmpty) {
      return RisegEmptyState(
        icon: Icons.error_outline,
        title: l10n.categoriasListadoCargaErrorTitulo,
        message: l10n.categoriasListadoCargaErrorMensaje,
        primaryAction: RisegButton(
          key: const Key('categorias_boton_reintentar'),
          label: l10n.categoriasListadoBotonReintentar,
          onPressed: notifier.reintentarCarga,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RisegSectionHeader(
            title: l10n.categoriasListadoTitulo,
            primaryAction: RisegButton(
              key: const Key('categorias_boton_nueva'),
              label: l10n.categoriasListadoBotonNueva,
              onPressed: () => _mostrarDialogoAlta(context, ref),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: RisegTableBase<CategoriaFinancieraData>(
              loading: state.cargando,
              rows: state.categorias,
              emptyState: RisegEmptyState(
                title: l10n.categoriasListadoVacioTitulo,
                message: l10n.categoriasListadoVacioMensaje,
              ),
              columns: [
                RisegColumn<CategoriaFinancieraData>(
                  label: l10n.categoriasColumnaCodigo,
                  width: 110,
                  cellBuilder: (c) => Text(c.codigo),
                ),
                RisegColumn<CategoriaFinancieraData>(label: l10n.categoriasColumnaNombre, cellBuilder: (c) => Text(c.nombre)),
                RisegColumn<CategoriaFinancieraData>(
                  label: l10n.categoriasColumnaTipo,
                  width: 130,
                  cellBuilder: (c) => Text(categoriaTipoLabel(l10n, c.tipo)),
                ),
                RisegColumn<CategoriaFinancieraData>(
                  label: l10n.categoriasColumnaTipoMovimiento,
                  width: 150,
                  cellBuilder: (c) => Text(categoriaTipoMovimientoLabel(l10n, c.tipoMovimiento)),
                ),
              ],
              rowActionsBuilder: (categoria) => IconButton(
                tooltip: l10n.categoriaBotonArchivar,
                icon: const Icon(Icons.archive_outlined, size: 18),
                visualDensity: VisualDensity.compact,
                onPressed: () => _archivar(context, ref, categoria),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
