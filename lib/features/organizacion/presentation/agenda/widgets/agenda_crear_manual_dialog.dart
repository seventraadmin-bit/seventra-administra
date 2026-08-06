import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/organizacion/domain/repositories/entidad_fiscal_repository.dart';
import 'package:riseg_one/features/organizacion/domain/repositories/servicio_repository.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_documento_manual_usecase.dart';

import '../../../organizacion_providers.dart';
import '../agenda_controller.dart';

/// Abre el diálogo "Crear documento manual" (Etapa 4I.1, Resolución B)
/// — la única vía para Configuraciones de cobro con agrupación `manual`
/// y para cualquier vigencia sin regla de Emisión calculable (Toluca
/// 32, Tikal, Mirabilia): el periodo se indica directamente en vez de
/// calcularse. Produce el mismo snapshot que la generación automática.
/// Devuelve `true` si se creó un documento — mismo criterio que
/// `_mostrarDialogoAlta` en `ServiciosListScreen`.
Future<bool> mostrarDialogoCrearDocumentoManual(BuildContext context, WidgetRef ref) async {
  final l10n = AppLocalizations.of(context)!;
  final clientes = await ref.read(clienteRepositoryProvider).listarActivos();
  if (!context.mounted) return false;

  var datos = const _DatosFormularioManual();

  final resultado = await RisegDialog.showForm<CrearDocumentoManualResultado?>(
    context: context,
    title: l10n.agendaCrearManualDialogoTitulo,
    confirmLabel: l10n.agendaCrearManualBotonCrear,
    cancelLabel: l10n.agendaCrearManualBotonCancelar,
    contentBuilder: (_) => _CrearManualForm(
      clientes: clientes,
      onCambio: (nuevosDatos) => datos = nuevosDatos,
    ),
    onConfirm: () async {
      if (datos.clienteId == null || datos.servicioIds.isEmpty) {
        return CrearDocumentoManualSinServicios();
      }
      if (datos.periodoInicio == null || datos.periodoFin == null) {
        return CrearDocumentoManualSinServicios();
      }
      return ref.read(agendaControllerProvider.notifier).crearManual(
            clienteId: datos.clienteId!,
            servicioIds: datos.servicioIds.toList(),
            periodoInicio: datos.periodoInicio!,
            periodoFin: datos.periodoFin!,
            entidadFiscalId: datos.entidadFiscalId,
          );
    },
  );

  if (!context.mounted) return false;

  switch (resultado) {
    case CrearDocumentoManualExitoso():
      return true;
    case CrearDocumentoManualSinServicios():
      RisegFeedback.showError(context, l10n.agendaCrearManualErrorSinServicios);
    case CrearDocumentoManualSinConfiguracionAplicable():
      RisegFeedback.showError(context, l10n.agendaCrearManualErrorSinConfiguracion);
    case CrearDocumentoManualServiciosIncompatibles():
      RisegFeedback.showError(context, l10n.agendaCrearManualErrorIncompatibles);
    case CrearDocumentoManualYaExiste():
      RisegFeedback.showError(context, l10n.agendaCrearManualErrorYaExiste);
    case CrearDocumentoManualErrorInesperado():
      RisegFeedback.showError(context, l10n.agendaCrearManualErrorInesperado);
    case null:
      break;
  }
  return false;
}

class _DatosFormularioManual {
  const _DatosFormularioManual({
    this.clienteId,
    this.entidadFiscalId,
    this.servicioIds = const {},
    this.periodoInicio,
    this.periodoFin,
  });

  final String? clienteId;
  final String? entidadFiscalId;
  final Set<String> servicioIds;
  final DateTime? periodoInicio;
  final DateTime? periodoFin;

  _DatosFormularioManual copyWith({
    String? clienteId,
    String? entidadFiscalId,
    Set<String>? servicioIds,
    DateTime? periodoInicio,
    DateTime? periodoFin,
    bool limpiarEntidadFiscalId = false,
  }) {
    return _DatosFormularioManual(
      clienteId: clienteId ?? this.clienteId,
      entidadFiscalId: limpiarEntidadFiscalId ? null : (entidadFiscalId ?? this.entidadFiscalId),
      servicioIds: servicioIds ?? this.servicioIds,
      periodoInicio: periodoInicio ?? this.periodoInicio,
      periodoFin: periodoFin ?? this.periodoFin,
    );
  }
}

class _CrearManualForm extends ConsumerStatefulWidget {
  const _CrearManualForm({required this.clientes, required this.onCambio});

  final List<ClienteData> clientes;
  final void Function(_DatosFormularioManual datos) onCambio;

  @override
  ConsumerState<_CrearManualForm> createState() => _CrearManualFormState();
}

class _CrearManualFormState extends ConsumerState<_CrearManualForm> {
  _DatosFormularioManual _datos = const _DatosFormularioManual();
  List<ServicioListItem> _serviciosDelCliente = const [];
  List<EntidadFiscalConDomicilio> _entidadesDelCliente = const [];
  bool _cargandoCliente = false;

  void _actualizar(_DatosFormularioManual nuevo) {
    setState(() => _datos = nuevo);
    widget.onCambio(nuevo);
  }

  Future<void> _seleccionarCliente(String? clienteId) async {
    _actualizar(
      _DatosFormularioManual(periodoInicio: _datos.periodoInicio, periodoFin: _datos.periodoFin)
          .copyWith(clienteId: clienteId),
    );
    setState(() {
      _serviciosDelCliente = const [];
      _entidadesDelCliente = const [];
      _cargandoCliente = clienteId != null;
    });
    if (clienteId == null) return;

    final todosLosServicios = await ref.read(servicioRepositoryProvider).listar();
    final entidades = await ref.read(entidadFiscalRepositoryProvider).listarPorCliente(clienteId);
    if (!mounted) return;
    setState(() {
      _serviciosDelCliente = todosLosServicios.where((s) => s.servicio.clienteId == clienteId).toList();
      _entidadesDelCliente = entidades;
      _cargandoCliente = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RisegSelect<String?>(
          label: l10n.agendaCrearManualCampoCliente,
          value: _datos.clienteId,
          items: [
            for (final c in widget.clientes) RisegSelectItem(value: c.id, label: c.nombreComercial),
          ],
          onChanged: _seleccionarCliente,
        ),
        const SizedBox(height: AppSpacing.md),
        if (_datos.clienteId == null)
          Text(l10n.agendaCrearManualSinCliente, style: AppTypography.caption)
        else if (_cargandoCliente)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Center(child: CircularProgressIndicator()),
          )
        else ...[
          RisegSelect<String?>(
            label: l10n.agendaCrearManualCampoEntidadFiscal,
            value: _datos.entidadFiscalId,
            items: [
              RisegSelectItem(value: null, label: l10n.agendaCrearManualCampoEntidadFiscalNinguna),
              for (final e in _entidadesDelCliente)
                RisegSelectItem(value: e.entidadFiscal.id, label: e.entidadFiscal.razonSocial),
            ],
            onChanged: (valor) => _actualizar(
              _datos.copyWith(entidadFiscalId: valor, limpiarEntidadFiscalId: valor == null),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(l10n.agendaCrearManualCampoServicios, style: AppTypography.label),
          const SizedBox(height: AppSpacing.xxs),
          if (_serviciosDelCliente.isEmpty)
            Text(l10n.agendaCrearManualSinServiciosDelCliente, style: AppTypography.caption)
          else
            for (final item in _serviciosDelCliente)
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text('${item.servicio.codigo} — ${item.servicio.nombre}'),
                value: _datos.servicioIds.contains(item.servicio.id),
                onChanged: (marcado) {
                  final nuevos = Set<String>.from(_datos.servicioIds);
                  if (marcado ?? false) {
                    nuevos.add(item.servicio.id);
                  } else {
                    nuevos.remove(item.servicio.id);
                  }
                  _actualizar(_datos.copyWith(servicioIds: nuevos));
                },
              ),
          const SizedBox(height: AppSpacing.md),
          RisegDateField(
            label: l10n.agendaCrearManualCampoPeriodoInicio,
            value: _datos.periodoInicio,
            onChanged: (valor) => _actualizar(_datos.copyWith(periodoInicio: valor)),
          ),
          const SizedBox(height: AppSpacing.md),
          RisegDateField(
            label: l10n.agendaCrearManualCampoPeriodoFin,
            value: _datos.periodoFin,
            onChanged: (valor) => _actualizar(_datos.copyWith(periodoFin: valor)),
          ),
        ],
      ],
    );
  }
}
