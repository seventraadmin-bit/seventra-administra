import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/organizacion/data/tables/puesto_table.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_puesto_resultado.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/puesto_validator.dart';

import '../../organizacion_providers.dart';
import 'puestos_list_controller.dart';

/// Listado de Puestos — buscador (código/nombre/área/tipo/descripción),
/// tabla y alta vía diálogo.
class PuestosListScreen extends ConsumerStatefulWidget {
  const PuestosListScreen({super.key});

  @override
  ConsumerState<PuestosListScreen> createState() => _PuestosListScreenState();
}

class _PuestosListScreenState extends ConsumerState<PuestosListScreen> {
  final _busquedaController = TextEditingController();

  @override
  void dispose() {
    _busquedaController.dispose();
    super.dispose();
  }

  Future<void> _mostrarDialogoAlta(List<AreaData> areas) async {
    final l10n = AppLocalizations.of(context)!;
    var borrador = const PuestoBorrador(nombre: '', areaId: '', tipo: null, nivelJerarquico: null);

    final creado = await RisegDialog.showForm<PuestoData?>(
      context: context,
      title: l10n.puestoAltaTitulo,
      confirmLabel: l10n.puestoAltaBotonCrear,
      cancelLabel: l10n.puestoAltaBotonCancelar,
      contentBuilder: (_) => _AltaPuestoForm(areas: areas, onCambio: (nuevo) => borrador = nuevo),
      onConfirm: () async {
        final resultado = await ref.read(crearPuestoUseCaseProvider).ejecutar(borrador);
        return resultado is GuardarPuestoExitoso ? resultado.puesto : null;
      },
    );

    if (!mounted) return;

    if (creado != null) {
      ref.read(puestosListControllerProvider.notifier).recargar();
      RisegFeedback.showSuccess(context, l10n.puestoCrearExito);
      context.push('/organizacion/puestos/${creado.id}');
    } else {
      RisegFeedback.showError(context, l10n.puestoCrearError);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(puestosListControllerProvider);
    final notifier = ref.read(puestosListControllerProvider.notifier);

    if (state.errorCarga != null && state.puestos.isEmpty) {
      return RisegEmptyState(
        icon: Icons.error_outline,
        title: l10n.puestosListadoCargaErrorTitulo,
        message: l10n.puestosListadoCargaErrorMensaje,
        primaryAction: RisegButton(
          key: const Key('puestos_boton_reintentar'),
          label: l10n.puestosListadoBotonReintentar,
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
            title: l10n.puestosListadoTitulo,
            primaryAction: RisegButton(
              key: const Key('puestos_boton_nueva'),
              label: l10n.puestosListadoBotonNueva,
              onPressed: () => _mostrarDialogoAlta(state.areas.where((a) => a.activo).toList()),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          RisegSearchField(
            hint: l10n.puestosListadoBuscarHint,
            controller: _busquedaController,
            onChanged: notifier.actualizarBusqueda,
          ),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: RisegTableBase<PuestoData>(
              loading: state.cargando,
              rows: state.puestosFiltrados,
              onRowTap: (puesto) => context.push('/organizacion/puestos/${puesto.id}'),
              emptyState: RisegEmptyState(
                title: l10n.puestosListadoVacioTitulo,
                message: l10n.puestosListadoVacioMensaje,
              ),
              columns: [
                RisegColumn<PuestoData>(label: l10n.puestosColumnaCodigo, width: 100, cellBuilder: (p) => Text(p.codigo)),
                RisegColumn<PuestoData>(label: l10n.puestosColumnaNombre, cellBuilder: (p) => Text(p.nombre)),
                RisegColumn<PuestoData>(
                  label: l10n.puestosColumnaArea,
                  cellBuilder: (p) => Text(state.nombreArea(p.areaId) ?? ''),
                ),
                RisegColumn<PuestoData>(
                  label: l10n.puestosColumnaTipo,
                  width: 140,
                  cellBuilder: (p) => Text(
                    p.tipo == TipoPuesto.administrativo.name ? l10n.puestoTipoAdministrativo : l10n.puestoTipoOperativo,
                  ),
                ),
                RisegColumn<PuestoData>(label: l10n.puestosColumnaNivel, width: 80, cellBuilder: (p) => Text('${p.nivelJerarquico}')),
                RisegColumn<PuestoData>(
                  label: l10n.puestosColumnaEstado,
                  width: 140,
                  cellBuilder: (p) => RisegStatusBadge(
                    label: p.cicloVidaRegistro == 'archivado' ? l10n.puestoEstadoArchivado : l10n.puestoEstadoActivo,
                    tone: p.cicloVidaRegistro == 'archivado' ? RisegStatusTone.neutral : RisegStatusTone.success,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Contenido del diálogo de alta — `StatefulWidget` propio para que sus
/// `TextEditingController` vivan y mueran con el ciclo de vida real del
/// widget (mismo motivo que `_AltaSucursalForm`/`_AltaUbicacionForm`).
class _AltaPuestoForm extends StatefulWidget {
  const _AltaPuestoForm({required this.areas, required this.onCambio});

  final List<AreaData> areas;
  final ValueChanged<PuestoBorrador> onCambio;

  @override
  State<_AltaPuestoForm> createState() => _AltaPuestoFormState();
}

class _AltaPuestoFormState extends State<_AltaPuestoForm> {
  final _nombreController = TextEditingController();
  final _nivelController = TextEditingController();
  String? _areaId;
  TipoPuesto? _tipo;

  @override
  void dispose() {
    _nombreController.dispose();
    _nivelController.dispose();
    super.dispose();
  }

  void _notificar() {
    widget.onCambio(
      PuestoBorrador(
        nombre: _nombreController.text,
        areaId: _areaId ?? '',
        tipo: _tipo,
        nivelJerarquico: int.tryParse(_nivelController.text.trim()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RisegTextField(
          label: l10n.puestoCampoNombre,
          controller: _nombreController,
          autofocus: true,
          onChanged: (_) => _notificar(),
        ),
        const SizedBox(height: AppSpacing.md),
        RisegSelect<String>(
          label: l10n.puestoCampoArea,
          value: _areaId,
          items: [for (final area in widget.areas) RisegSelectItem(value: area.id, label: area.nombre)],
          onChanged: (valor) {
            setState(() => _areaId = valor);
            _notificar();
          },
        ),
        const SizedBox(height: AppSpacing.md),
        RisegSelect<TipoPuesto>(
          label: l10n.puestoCampoTipo,
          value: _tipo,
          items: [
            RisegSelectItem(value: TipoPuesto.operativo, label: l10n.puestoTipoOperativo),
            RisegSelectItem(value: TipoPuesto.administrativo, label: l10n.puestoTipoAdministrativo),
          ],
          onChanged: (valor) {
            setState(() => _tipo = valor);
            _notificar();
          },
        ),
        const SizedBox(height: AppSpacing.md),
        RisegTextField(
          label: l10n.puestoCampoNivelJerarquico,
          controller: _nivelController,
          helperText: l10n.puestoAyudaNivelJerarquico,
          keyboardType: TextInputType.number,
          onChanged: (_) => _notificar(),
        ),
      ],
    );
  }
}
