import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/organizacion/domain/repositories/catalogo_repository.dart';
import 'package:riseg_one/features/organizacion/domain/repositories/servicio_repository.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_servicio_resultado.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/servicio_errors.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/servicio_validator.dart';

import '../../organizacion_providers.dart';
import 'servicios_list_controller.dart';

/// Listado de Servicios — buscador (código/nombre/Cliente/Tipo de
/// Servicio/observaciones), tabla y alta mínima vía diálogo (nombre,
/// Cliente, Tipo de Servicio, fecha de inicio, observaciones). Entidad
/// fiscal, Dirección operativa, responsables y referencias se
/// administran después en el expediente (Etapa 4F.2).
class ServiciosListScreen extends ConsumerStatefulWidget {
  const ServiciosListScreen({super.key});

  @override
  ConsumerState<ServiciosListScreen> createState() => _ServiciosListScreenState();
}

class _ServiciosListScreenState extends ConsumerState<ServiciosListScreen> {
  final _busquedaController = TextEditingController();

  @override
  void dispose() {
    _busquedaController.dispose();
    super.dispose();
  }

  Future<void> _mostrarDialogoAlta() async {
    final l10n = AppLocalizations.of(context)!;

    final clientes = (await ref.read(clienteRepositoryProvider).listarActivos())
        .where((c) => c.estatus == 'prospecto' || c.estatus == 'activo')
        .toList();
    final tiposServicio = await ref.read(catalogoRepositoryProvider).listarTiposServicio();

    if (!mounted) return;

    var servicioBorrador = const ServicioBorrador(nombre: '', tipoServicioId: '', fechaInicio: null);
    String? clienteId;

    final resultado = await RisegDialog.showForm<GuardarServicioResultado?>(
      context: context,
      title: l10n.servicioAltaTitulo,
      confirmLabel: l10n.servicioAltaBotonCrear,
      cancelLabel: l10n.servicioAltaBotonCancelar,
      contentBuilder: (_) => _AltaServicioForm(
        clientes: clientes,
        tiposServicio: tiposServicio,
        onCambio: (nuevoClienteId, nuevoBorrador) {
          clienteId = nuevoClienteId;
          servicioBorrador = nuevoBorrador;
        },
      ),
      onConfirm: () async {
        if (clienteId == null || clienteId!.isEmpty) {
          return GuardarServicioErroresValidacion(
            const [ErrorCampoServicio(campo: CampoServicio.cliente, codigo: CodigoErrorServicio.requerido)],
          );
        }
        return ref.read(crearServicioUseCaseProvider).ejecutar(clienteId: clienteId!, borrador: servicioBorrador);
      },
    );

    if (!mounted) return;

    switch (resultado) {
      case GuardarServicioExitoso(servicio: final servicio):
        ref.read(serviciosListControllerProvider.notifier).recargar();
        RisegFeedback.showSuccess(context, l10n.servicioCrearExito);
        context.push('/comercial/servicios/${servicio.id}');
      case GuardarServicioErroresValidacion():
      case GuardarServicioErrorInesperado():
        RisegFeedback.showError(context, l10n.servicioCrearError);
      case null:
        break;
    }
  }

  String _nombreEstatus(AppLocalizations l10n, String estatus) {
    return switch (estatus) {
      'activo' => l10n.servicioEstatusActivo,
      'suspendido' => l10n.servicioEstatusSuspendido,
      'terminado' => l10n.servicioEstatusTerminado,
      _ => l10n.servicioEstatusCotizado,
    };
  }

  RisegStatusTone _tonoEstatus(String estatus) {
    return switch (estatus) {
      'activo' => RisegStatusTone.success,
      'suspendido' => RisegStatusTone.warning,
      'terminado' => RisegStatusTone.neutral,
      _ => RisegStatusTone.info,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(serviciosListControllerProvider);
    final notifier = ref.read(serviciosListControllerProvider.notifier);

    if (state.errorCarga != null && state.servicios.isEmpty) {
      return RisegEmptyState(
        icon: Icons.error_outline,
        title: l10n.serviciosListadoCargaErrorTitulo,
        message: l10n.serviciosListadoCargaErrorMensaje,
        primaryAction: RisegButton(
          key: const Key('servicios_boton_reintentar'),
          label: l10n.serviciosListadoBotonReintentar,
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
            title: l10n.serviciosListadoTitulo,
            primaryAction: RisegButton(
              key: const Key('servicios_boton_nuevo'),
              label: l10n.serviciosListadoBotonNuevo,
              onPressed: _mostrarDialogoAlta,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          RisegSearchField(
            hint: l10n.serviciosListadoBuscarHint,
            controller: _busquedaController,
            onChanged: notifier.actualizarBusqueda,
          ),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: RisegTableBase<ServicioListItem>(
              loading: state.cargando,
              rows: state.serviciosFiltrados,
              onRowTap: (item) => context.push('/comercial/servicios/${item.servicio.id}'),
              emptyState: RisegEmptyState(
                title: l10n.serviciosListadoVacioTitulo,
                message: l10n.serviciosListadoVacioMensaje,
              ),
              columns: [
                RisegColumn<ServicioListItem>(
                  label: l10n.serviciosColumnaCodigo,
                  width: 100,
                  cellBuilder: (item) => Text(item.servicio.codigo),
                ),
                RisegColumn<ServicioListItem>(
                  label: l10n.serviciosColumnaNombre,
                  cellBuilder: (item) => Text(item.servicio.nombre),
                ),
                RisegColumn<ServicioListItem>(
                  label: l10n.serviciosColumnaCliente,
                  cellBuilder: (item) => Text(item.clienteNombre),
                ),
                RisegColumn<ServicioListItem>(
                  label: l10n.serviciosColumnaTipo,
                  width: 160,
                  cellBuilder: (item) => Text(item.tipoServicioNombre),
                ),
                RisegColumn<ServicioListItem>(
                  label: l10n.serviciosColumnaEstatus,
                  width: 140,
                  cellBuilder: (item) => RisegStatusBadge(
                    label: _nombreEstatus(l10n, item.servicio.estatus),
                    tone: _tonoEstatus(item.servicio.estatus),
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

/// Contenido del diálogo de alta mínima — nombre, Cliente comercial,
/// Tipo de Servicio, fecha de inicio, observaciones. Sin Entidad fiscal,
/// Dirección operativa, responsables ni referencias — eso es de la
/// Etapa 4F.2.
class _AltaServicioForm extends StatefulWidget {
  const _AltaServicioForm({required this.clientes, required this.tiposServicio, required this.onCambio});

  final List<ClienteData> clientes;
  final List<CatalogoItem> tiposServicio;
  final void Function(String? clienteId, ServicioBorrador borrador) onCambio;

  @override
  State<_AltaServicioForm> createState() => _AltaServicioFormState();
}

class _AltaServicioFormState extends State<_AltaServicioForm> {
  final _nombreController = TextEditingController();
  final _observacionesController = TextEditingController();
  String? _clienteId;
  String? _tipoServicioId;
  DateTime? _fechaInicio;

  @override
  void dispose() {
    _nombreController.dispose();
    _observacionesController.dispose();
    super.dispose();
  }

  void _notificar() {
    widget.onCambio(
      _clienteId,
      ServicioBorrador(
        nombre: _nombreController.text,
        tipoServicioId: _tipoServicioId ?? '',
        fechaInicio: _fechaInicio,
        observaciones: _observacionesController.text,
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
          label: l10n.servicioCampoNombre,
          controller: _nombreController,
          autofocus: true,
          onChanged: (_) => _notificar(),
        ),
        const SizedBox(height: AppSpacing.md),
        RisegSelect<String>(
          label: l10n.servicioCampoCliente,
          value: _clienteId,
          items: [
            for (final cliente in widget.clientes)
              RisegSelectItem(value: cliente.id, label: cliente.nombreComercial),
          ],
          onChanged: (valor) {
            setState(() => _clienteId = valor);
            _notificar();
          },
        ),
        const SizedBox(height: AppSpacing.md),
        RisegSelect<String>(
          label: l10n.servicioCampoTipoServicio,
          value: _tipoServicioId,
          items: [
            for (final tipo in widget.tiposServicio) RisegSelectItem(value: tipo.id, label: tipo.nombre),
          ],
          onChanged: (valor) {
            setState(() => _tipoServicioId = valor);
            _notificar();
          },
        ),
        const SizedBox(height: AppSpacing.md),
        RisegDateField(
          label: l10n.servicioCampoFechaInicio,
          value: _fechaInicio,
          onChanged: (valor) {
            setState(() => _fechaInicio = valor);
            _notificar();
          },
        ),
        const SizedBox(height: AppSpacing.md),
        RisegTextField(
          label: l10n.servicioCampoObservaciones,
          controller: _observacionesController,
          onChanged: (_) => _notificar(),
        ),
      ],
    );
  }
}
