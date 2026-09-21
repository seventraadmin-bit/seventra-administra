import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/organizacion/data/tables/cliente_table.dart' show EstatusCliente;

import '../../organizacion_providers.dart';
import 'clientes_list_controller.dart';
import 'clientes_list_state.dart';

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
    String? logoPath;
    String? logoNombre;

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
        onCambioLogo: (path, nombre) {
          logoPath = path;
          logoNombre = nombre;
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
      // Mismo criterio que Empleado (Etapa 5A): el logo es opcional y
      // se sube DESPUÉS de crear el Cliente — no puede compartir
      // transacción de BD con una operación de archivo. Un fallo aquí
      // no invalida el alta; el Cliente ya es válido sin logo.
      if (logoPath != null) {
        final extension = logoPath!.contains('.') ? logoPath!.split('.').last : 'png';
        await ref.read(registrarLogoClienteAutorizadoProvider)(
              clienteId: creado.id,
              sourceFilePath: logoPath!,
              originalFileName: logoNombre ?? logoPath!,
              mimeType: 'image/$extension',
            );
      }
      if (!mounted) return;
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

    final colors = context.colors;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RisegSectionHeader(
            title: l10n.clientesListadoTitulo,
            description: l10n.clientesListadoSubtitulo,
            primaryAction: RisegButton(
              key: const Key('clientes_boton_nueva'),
              label: l10n.clientesListadoBotonNueva,
              icon: Icons.add,
              onPressed: _mostrarDialogoAlta,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          // División comercial primaria (pedido explícito) — separa
          // Clientes con relación vigente de aquellos cuya relación ya
          // terminó, antes de cualquier otro filtro más granular.
          Wrap(
            spacing: AppSpacing.sm,
            children: [
              ChoiceChip(
                key: const Key('clientes_grupo_vigentes'),
                label: Text(l10n.clientesGrupoVigentes),
                selected: state.grupo == GrupoComercialCliente.vigentes,
                onSelected: (_) => notifier.cambiarGrupo(GrupoComercialCliente.vigentes),
              ),
              ChoiceChip(
                key: const Key('clientes_grupo_finalizados'),
                label: Text(l10n.clientesGrupoFinalizados),
                selected: state.grupo == GrupoComercialCliente.finalizados,
                onSelected: (_) => notifier.cambiarGrupo(GrupoComercialCliente.finalizados),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 260,
                child: RisegSearchField(
                  hint: l10n.clientesListadoBuscarHint,
                  controller: _busquedaController,
                  onChanged: notifier.actualizarBusqueda,
                ),
              ),
              SizedBox(
                width: 190,
                child: RisegSelect<String?>(
                  label: l10n.clientesColumnaEstatus,
                  value: state.filtroEstado,
                  items: [
                    RisegSelectItem(value: null, label: l10n.clientesFiltroEstadoTodos),
                    for (final e in EstatusCliente.values) RisegSelectItem(value: e.name, label: _nombreEstatus(l10n, e.name)),
                  ],
                  onChanged: notifier.cambiarFiltroEstado,
                ),
              ),
              SizedBox(
                width: 190,
                child: RisegSelect<FiltroServiciosCliente>(
                  label: l10n.clientesColumnaServicios,
                  value: state.filtroServicios,
                  items: [
                    RisegSelectItem(value: FiltroServiciosCliente.todos, label: l10n.clientesFiltroServiciosTodos),
                    RisegSelectItem(value: FiltroServiciosCliente.conServicios, label: l10n.clientesFiltroConServicios),
                    RisegSelectItem(value: FiltroServiciosCliente.sinServicios, label: l10n.clientesFiltroSinServicios),
                  ],
                  onChanged: (v) => notifier.cambiarFiltroServicios(v ?? FiltroServiciosCliente.todos),
                ),
              ),
              RisegButton(
                label: l10n.personalActivoLimpiarFiltros,
                variant: RisegButtonVariant.ghost,
                onPressed: state.hayFiltrosActivos
                    ? () {
                        _busquedaController.clear();
                        notifier.limpiarTodosLosFiltros();
                      }
                    : null,
              ),
            ],
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
              hoverColor: colors.accentSoftBg,
              rowVerticalPadding: AppSpacing.sm + AppSpacing.xxs,
              rowActionsBuilder: (_) => Icon(Icons.chevron_right, size: AppSizes.iconMd, color: colors.textMuted),
              actionsWidth: 40,
              columns: [
                RisegColumn<ClienteData>(
                  label: l10n.clientesColumnaNombre,
                  cellBuilder: (c) => RisegEntityIdentity(
                    forma: RisegEntityImageShape.cuadradaRedondeada,
                    primario: c.nombreComercial,
                    secundario: c.codigo,
                    imagenPath: state.logoPathPorClienteId[c.id],
                  ),
                ),
                RisegColumn<ClienteData>(
                  label: l10n.clientesColumnaServicios,
                  width: 120,
                  cellBuilder: (c) => Text(l10n.clientesCantidadServicios(state.serviciosActivosPorCliente[c.id] ?? 0)),
                ),
                RisegColumn<ClienteData>(
                  label: l10n.clientesColumnaPersonal,
                  width: 120,
                  cellBuilder: (c) => Text(l10n.clientesCantidadPersonal(state.personalPorCliente[c.id] ?? 0)),
                ),
                RisegColumn<ClienteData>(
                  label: l10n.clientesColumnaUbicacion,
                  cellBuilder: (c) {
                    final direccion = state.direccionReferenciaPorClienteId[c.id];
                    return Text(
                      direccion == null ? l10n.clientesUbicacionNoRegistrada : '${direccion.municipioAlcaldia}, ${direccion.estado}',
                      style: direccion == null ? AppTypography.body.copyWith(color: colors.textMuted) : null,
                    );
                  },
                ),
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
  const _AltaClienteForm({required this.onCambio, required this.onCambioLogo});

  final void Function(String nombreComercial, String observaciones) onCambio;

  /// `null`/`null` cuando no se elige logo — es opcional (Resolución de
  /// Marlon).
  final void Function(String? logoPath, String? logoNombre) onCambioLogo;

  @override
  State<_AltaClienteForm> createState() => _AltaClienteFormState();
}

class _AltaClienteFormState extends State<_AltaClienteForm> {
  final _nombreController = TextEditingController();
  final _observacionesController = TextEditingController();
  String? _logoPath;
  String? _logoNombre;

  @override
  void dispose() {
    _nombreController.dispose();
    _observacionesController.dispose();
    super.dispose();
  }

  void _notificar() => widget.onCambio(_nombreController.text, _observacionesController.text);

  Future<void> _seleccionarLogo() async {
    final seleccion = await FilePicker.platform.pickFiles(type: FileType.image);
    final archivo = seleccion?.files.singleOrNull;
    if (archivo?.path == null) return;
    setState(() {
      _logoPath = archivo!.path;
      _logoNombre = archivo.name;
    });
    widget.onCambioLogo(_logoPath, _logoNombre);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;

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
        const SizedBox(height: AppSpacing.md),
        Text(l10n.clienteLogoTitulo, style: AppTypography.label.copyWith(color: colors.textMuted)),
        const SizedBox(height: AppSpacing.xs),
        KeyedSubtree(
          key: ValueKey(_logoPath == null),
          child: _logoPath == null
              ? RisegButton(
                  label: l10n.clienteLogoBotonSeleccionar,
                  variant: RisegButtonVariant.secondary,
                  icon: Icons.add_photo_alternate_outlined,
                  onPressed: _seleccionarLogo,
                )
              : Row(
                  children: [
                    ClipRRect(
                      borderRadius: AppRadius.mdRadius,
                      child: Image.file(File(_logoPath!), width: 48, height: 48, fit: BoxFit.contain),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(child: Text(_logoNombre ?? '', overflow: TextOverflow.ellipsis)),
                    RisegButton(
                      label: l10n.clienteLogoBotonQuitar,
                      variant: RisegButtonVariant.ghost,
                      onPressed: () {
                        setState(() {
                          _logoPath = null;
                          _logoNombre = null;
                        });
                        widget.onCambioLogo(null, null);
                      },
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}
