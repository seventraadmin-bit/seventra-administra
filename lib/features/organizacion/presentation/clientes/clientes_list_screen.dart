import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';

import '../../organizacion_providers.dart';
import 'clientes_list_controller.dart';

/// Listado de Clientes comerciales — buscador (código/nombre comercial/
/// observaciones), tabla y alta vía diálogo mínimo (nombre comercial +
/// observaciones; dirección, contactos y estatus se administran después
/// en el expediente).
class ClientesListScreen extends ConsumerStatefulWidget {
  const ClientesListScreen({super.key});

  @override
  ConsumerState<ClientesListScreen> createState() => _ClientesListScreenState();
}

class _ClientesListScreenState extends ConsumerState<ClientesListScreen> {
  final _busquedaController = TextEditingController();

  @override
  void dispose() {
    _busquedaController.dispose();
    super.dispose();
  }

  Future<void> _mostrarDialogoAlta() async {
    final l10n = AppLocalizations.of(context)!;
    var nombreComercial = '';
    var observaciones = '';

    final creado = await RisegDialog.showForm<ClienteData?>(
      context: context,
      title: l10n.clienteAltaTitulo,
      confirmLabel: l10n.clienteAltaBotonCrear,
      cancelLabel: l10n.clienteAltaBotonCancelar,
      contentBuilder: (_) => _AltaClienteForm(
        onCambio: (nombre, obs) {
          nombreComercial = nombre;
          observaciones = obs;
        },
      ),
      onConfirm: () async {
        final resultado = await ref
            .read(crearClienteAutorizadoProvider)(nombreComercial: nombreComercial, observaciones: observaciones);
        return resultado.when(ok: (c) => c, failure: (_) => null);
      },
    );

    if (!mounted) return;

    if (creado != null) {
      ref.read(clientesListControllerProvider.notifier).recargar();
      RisegFeedback.showSuccess(context, l10n.clienteCrearExito);
      context.push('/comercial/clientes/${creado.id}');
    } else {
      RisegFeedback.showError(context, l10n.clienteCrearError);
    }
  }

  String _nombreEstatus(AppLocalizations l10n, String estatus) {
    return switch (estatus) {
      'activo' => l10n.clienteEstatusActivo,
      'suspendido' => l10n.clienteEstatusSuspendido,
      'terminado' => l10n.clienteEstatusTerminado,
      'descartado' => l10n.clienteEstatusDescartado,
      _ => l10n.clienteEstatusProspecto,
    };
  }

  RisegStatusTone _tonoEstatus(String estatus) {
    return switch (estatus) {
      'activo' => RisegStatusTone.success,
      'suspendido' => RisegStatusTone.warning,
      'descartado' => RisegStatusTone.error,
      'terminado' => RisegStatusTone.neutral,
      _ => RisegStatusTone.info,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(clientesListControllerProvider);
    final notifier = ref.read(clientesListControllerProvider.notifier);

    if (state.errorCarga != null && state.clientes.isEmpty) {
      return RisegEmptyState(
        icon: Icons.error_outline,
        title: l10n.clientesListadoCargaErrorTitulo,
        message: l10n.clientesListadoCargaErrorMensaje,
        primaryAction: RisegButton(
          key: const Key('clientes_boton_reintentar'),
          label: l10n.clientesListadoBotonReintentar,
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
            title: l10n.clientesListadoTitulo,
            primaryAction: RisegButton(
              key: const Key('clientes_boton_nueva'),
              label: l10n.clientesListadoBotonNueva,
              onPressed: _mostrarDialogoAlta,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          RisegSearchField(
            hint: l10n.clientesListadoBuscarHint,
            controller: _busquedaController,
            onChanged: notifier.actualizarBusqueda,
          ),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: RisegTableBase<ClienteData>(
              loading: state.cargando,
              rows: state.clientesFiltrados,
              onRowTap: (cliente) => context.push('/comercial/clientes/${cliente.id}'),
              emptyState: RisegEmptyState(
                title: l10n.clientesListadoVacioTitulo,
                message: l10n.clientesListadoVacioMensaje,
              ),
              columns: [
                RisegColumn<ClienteData>(label: l10n.clientesColumnaCodigo, width: 100, cellBuilder: (c) => Text(c.codigo)),
                RisegColumn<ClienteData>(label: l10n.clientesColumnaNombre, cellBuilder: (c) => Text(c.nombreComercial)),
                RisegColumn<ClienteData>(
                  label: l10n.clientesColumnaEstatus,
                  width: 140,
                  cellBuilder: (c) => RisegStatusBadge(
                    label: _nombreEstatus(l10n, c.estatus),
                    tone: _tonoEstatus(c.estatus),
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
/// widget (mismo motivo que `_AltaPuestoForm`/`_AltaSucursalForm`).
class _AltaClienteForm extends StatefulWidget {
  const _AltaClienteForm({required this.onCambio});

  final void Function(String nombreComercial, String observaciones) onCambio;

  @override
  State<_AltaClienteForm> createState() => _AltaClienteFormState();
}

class _AltaClienteFormState extends State<_AltaClienteForm> {
  final _nombreController = TextEditingController();
  final _observacionesController = TextEditingController();

  @override
  void dispose() {
    _nombreController.dispose();
    _observacionesController.dispose();
    super.dispose();
  }

  void _notificar() => widget.onCambio(_nombreController.text, _observacionesController.text);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RisegTextField(
          label: l10n.clienteCampoNombreComercial,
          controller: _nombreController,
          autofocus: true,
          onChanged: (_) => _notificar(),
        ),
        const SizedBox(height: AppSpacing.md),
        RisegTextField(
          label: l10n.clienteCampoObservaciones,
          controller: _observacionesController,
          onChanged: (_) => _notificar(),
        ),
      ],
    );
  }
}
