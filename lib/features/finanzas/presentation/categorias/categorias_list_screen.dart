import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/finanzas/data/tables/categoria_financiera_table.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/actualizar_categoria_financiera_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/archivar_categoria_financiera_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/crear_categoria_financiera_usecase.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';

import '../../finanzas_providers.dart';
import 'categorias_list_controller.dart';
import 'widgets/eliminar_categoria_financiera_fisicamente_dialog.dart';

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

/// Catálogo administrable de Categorías financieras (Etapa 4K.1) —
/// alta, edición y archivado (el catálogo nace vacío y RISEG lo
/// captura/ajusta conforme lo necesita; mismo criterio simple que
/// `Área`).
class CategoriasListScreen extends ConsumerWidget {
  const CategoriasListScreen({super.key});

  Future<void> _mostrarDialogoAlta(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    var codigoActual = '';
    var nombreActual = '';
    var tipoActual = TipoCategoriaFinanciera.ambos;
    var tipoMovimientoActual = TipoMovimientoCategoriaFinanciera.operativo;

    final resultado = await RisegDialog.showForm<CrearCategoriaFinancieraResultado>(
      context: context,
      title: l10n.categoriaDialogoTituloAlta,
      confirmLabel: l10n.categoriaDialogoBotonGuardar,
      cancelLabel: l10n.categoriaDialogoBotonCancelar,
      contentBuilder: (_) => _CategoriaFinancieraForm(
        onCodigoChanged: (v) => codigoActual = v,
        onNombreChanged: (v) => nombreActual = v,
        onTipoChanged: (v) => tipoActual = v,
        onTipoMovimientoChanged: (v) => tipoMovimientoActual = v,
      ),
      onConfirm: () => ref.read(crearCategoriaFinancieraAutorizadoProvider)(
            codigo: codigoActual,
            nombre: nombreActual,
            tipo: tipoActual.name,
            tipoMovimiento: tipoMovimientoActual.name,
          ),
    );

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

  Future<void> _mostrarDialogoEditar(BuildContext context, WidgetRef ref, CategoriaFinancieraData categoria) async {
    final l10n = AppLocalizations.of(context)!;
    var codigoActual = categoria.codigo;
    var nombreActual = categoria.nombre;
    var tipoActual = TipoCategoriaFinanciera.values.byName(categoria.tipo);
    var tipoMovimientoActual = TipoMovimientoCategoriaFinanciera.values.byName(categoria.tipoMovimiento);

    final resultado = await RisegDialog.showForm<ActualizarCategoriaFinancieraResultado>(
      context: context,
      title: l10n.categoriaDialogoTituloEditar,
      confirmLabel: l10n.categoriaDialogoBotonGuardar,
      cancelLabel: l10n.categoriaDialogoBotonCancelar,
      contentBuilder: (_) => _CategoriaFinancieraForm(
        codigoInicial: categoria.codigo,
        nombreInicial: categoria.nombre,
        tipoInicial: tipoActual,
        tipoMovimientoInicial: tipoMovimientoActual,
        onCodigoChanged: (v) => codigoActual = v,
        onNombreChanged: (v) => nombreActual = v,
        onTipoChanged: (v) => tipoActual = v,
        onTipoMovimientoChanged: (v) => tipoMovimientoActual = v,
      ),
      onConfirm: () => ref.read(actualizarCategoriaFinancieraAutorizadoProvider)(
            id: categoria.id,
            codigo: codigoActual,
            nombre: nombreActual,
            tipo: tipoActual.name,
            tipoMovimiento: tipoMovimientoActual.name,
          ),
    );

    if (!context.mounted) return;

    switch (resultado) {
      case ActualizarCategoriaFinancieraExitoso():
        ref.read(categoriasListControllerProvider.notifier).recargar();
        RisegFeedback.showSuccess(context, l10n.categoriaGuardadoExito);
      case ActualizarCategoriaFinancieraNoExiste():
      case ActualizarCategoriaFinancieraCodigoRequerido():
      case ActualizarCategoriaFinancieraNombreRequerido():
      case ActualizarCategoriaFinancieraErrorInesperado():
        RisegFeedback.showError(context, l10n.categoriaGuardadoError);
      case null:
        break;
    }
  }

  Future<void> _eliminarFisicamente(BuildContext context, WidgetRef ref, CategoriaFinancieraData categoria) async {
    final eliminado = await mostrarDialogoEliminarCategoriaFinancieraFisicamente(context, ref, categoria.id);
    if (eliminado) ref.read(categoriasListControllerProvider.notifier).recargar();
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

    final resultado = await ref.read(archivarCategoriaFinancieraAutorizadoProvider)(categoria.id);
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
    final esMaestro = ref.watch(sesionControllerProvider)?.esMaestro ?? false;

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

    final colors = context.colors;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RisegSectionHeader(
            title: l10n.categoriasListadoTitulo,
            description: l10n.categoriasListadoSubtitulo,
            primaryAction: RisegButton(
              key: const Key('categorias_boton_nueva'),
              label: l10n.categoriasListadoBotonNueva,
              icon: Icons.add,
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
              hoverColor: colors.accentSoftBg,
              rowVerticalPadding: AppSpacing.sm + AppSpacing.xxs,
              columns: [
                RisegColumn<CategoriaFinancieraData>(
                  label: l10n.categoriasColumnaNombre,
                  cellBuilder: (c) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(c.nombre, style: AppTypography.bodyStrong.copyWith(color: colors.textPrimary)),
                      const SizedBox(height: 2),
                      Text(c.codigo, style: AppTypography.caption.copyWith(color: colors.textMuted)),
                    ],
                  ),
                ),
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
              actionsWidth: 48,
              rowActionsBuilder: (categoria) => RisegActionsMenu(
                menuKey: Key('categoria_menu_acciones_${categoria.id}'),
                actions: [
                  RisegMenuAction(
                    key: Key('categoria_accion_editar_${categoria.id}'),
                    label: l10n.categoriaAccionEditar,
                    icon: Icons.edit_outlined,
                    onTap: () => _mostrarDialogoEditar(context, ref, categoria),
                  ),
                  RisegMenuAction(
                    key: Key('categoria_accion_archivar_${categoria.id}'),
                    label: l10n.categoriaAccionArchivar,
                    icon: Icons.archive_outlined,
                    onTap: () => _archivar(context, ref, categoria),
                  ),
                  if (esMaestro)
                    RisegMenuAction(
                      key: Key('categoria_accion_eliminar_${categoria.id}'),
                      label: l10n.eliminacionFisicaAccionMenu,
                      icon: Icons.delete_forever_outlined,
                      destructive: true,
                      onTap: () => _eliminarFisicamente(context, ref, categoria),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Contenido del formulario de alta/edición — un `StatefulWidget` propio
/// (no una pareja `TextEditingController` + `StatefulBuilder` en el
/// método que abre el diálogo) para que los `TextEditingController` se
/// creen y se destruyan con el ciclo de vida real del widget. Deshacerlos
/// a mano justo después de `await RisegDialog.showForm(...)` compite con
/// la animación de salida del diálogo (el campo puede seguir montado un
/// frame más), lanzando "TextEditingController usado después de
/// dispose()" — mismo bug real ya documentado en
/// `_AltaSucursalForm` (`sucursales_list_screen.dart`).
class _CategoriaFinancieraForm extends StatefulWidget {
  const _CategoriaFinancieraForm({
    this.codigoInicial = '',
    this.nombreInicial = '',
    this.tipoInicial = TipoCategoriaFinanciera.ambos,
    this.tipoMovimientoInicial = TipoMovimientoCategoriaFinanciera.operativo,
    required this.onCodigoChanged,
    required this.onNombreChanged,
    required this.onTipoChanged,
    required this.onTipoMovimientoChanged,
  });

  final String codigoInicial;
  final String nombreInicial;
  final TipoCategoriaFinanciera tipoInicial;
  final TipoMovimientoCategoriaFinanciera tipoMovimientoInicial;
  final ValueChanged<String> onCodigoChanged;
  final ValueChanged<String> onNombreChanged;
  final ValueChanged<TipoCategoriaFinanciera> onTipoChanged;
  final ValueChanged<TipoMovimientoCategoriaFinanciera> onTipoMovimientoChanged;

  @override
  State<_CategoriaFinancieraForm> createState() => _CategoriaFinancieraFormState();
}

class _CategoriaFinancieraFormState extends State<_CategoriaFinancieraForm> {
  late final _codigoController = TextEditingController(text: widget.codigoInicial);
  late final _nombreController = TextEditingController(text: widget.nombreInicial);
  late TipoCategoriaFinanciera _tipoSeleccionado = widget.tipoInicial;
  late TipoMovimientoCategoriaFinanciera _tipoMovimientoSeleccionado = widget.tipoMovimientoInicial;

  @override
  void dispose() {
    _codigoController.dispose();
    _nombreController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RisegTextField(
          label: l10n.categoriaCampoCodigo,
          controller: _codigoController,
          autofocus: true,
          onChanged: widget.onCodigoChanged,
        ),
        const SizedBox(height: AppSpacing.md),
        RisegTextField(
          label: l10n.categoriaCampoNombre,
          controller: _nombreController,
          onChanged: widget.onNombreChanged,
        ),
        const SizedBox(height: AppSpacing.md),
        RisegSelect<TipoCategoriaFinanciera>(
          label: l10n.categoriaCampoTipo,
          value: _tipoSeleccionado,
          items: [
            for (final t in TipoCategoriaFinanciera.values)
              RisegSelectItem(value: t, label: categoriaTipoLabel(l10n, t.name)),
          ],
          onChanged: (valor) {
            if (valor == null) return;
            setState(() => _tipoSeleccionado = valor);
            widget.onTipoChanged(valor);
          },
        ),
        const SizedBox(height: AppSpacing.md),
        RisegSelect<TipoMovimientoCategoriaFinanciera>(
          label: l10n.categoriaCampoTipoMovimiento,
          value: _tipoMovimientoSeleccionado,
          items: [
            for (final t in TipoMovimientoCategoriaFinanciera.values)
              RisegSelectItem(value: t, label: categoriaTipoMovimientoLabel(l10n, t.name)),
          ],
          onChanged: (valor) {
            if (valor == null) return;
            setState(() => _tipoMovimientoSeleccionado = valor);
            widget.onTipoMovimientoChanged(valor);
          },
        ),
      ],
    );
  }
}
