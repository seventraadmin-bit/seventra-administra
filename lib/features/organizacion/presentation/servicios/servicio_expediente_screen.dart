import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/organizacion/data/tables/servicio_table.dart';
import 'package:riseg_one/features/organizacion/domain/repositories/catalogo_repository.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/cambiar_estatus_servicio_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/servicio_errors.dart';

import '../../organizacion_providers.dart';
import 'servicio_expediente_controller.dart';
import 'servicio_expediente_form_controllers.dart';
import 'servicio_expediente_state.dart';
import 'widgets/servicio_datos_generales_section.dart';

final _formatoFecha = DateFormat('dd/MM/yyyy');

/// Pantalla de expediente de Servicio — mismo patrón consulta/edición
/// que Cliente/Puesto/Sucursal; se apila (`push`) sobre el listado. En
/// la Etapa 4F.1 solo administra datos generales y estatus — Entidad
/// fiscal, Dirección operativa, responsables y referencias llegan en la
/// Etapa 4F.2.
class ServicioExpedienteScreen extends ConsumerStatefulWidget {
  const ServicioExpedienteScreen({required this.servicioId, super.key});

  final String servicioId;

  @override
  ConsumerState<ServicioExpedienteScreen> createState() => _ServicioExpedienteScreenState();
}

class _ServicioExpedienteScreenState extends ConsumerState<ServicioExpedienteScreen> {
  final _datosGenerales = ServicioDatosGeneralesControllers();
  List<CatalogoItem> _tiposServicio = const [];

  @override
  void initState() {
    super.initState();
    ref.read(catalogoRepositoryProvider).listarTiposServicio().then((tipos) {
      if (mounted) setState(() => _tiposServicio = tipos);
    });
  }

  @override
  void dispose() {
    _datosGenerales.dispose();
    super.dispose();
  }

  ServicioExpedienteController get _notifier =>
      ref.read(servicioExpedienteControllerProvider(widget.servicioId).notifier);

  void _iniciarEdicion(ServicioData servicio) {
    _datosGenerales.poblar(servicio);
    _notifier.entrarModoEdicion();
  }

  void _onTipoServicioCambiado(String? valor) {
    setState(() => _datosGenerales.tipoServicioId = valor ?? '');
    _notifier.marcarCambiosSinGuardar();
  }

  void _onFechaInicioCambiada(DateTime valor) {
    setState(() => _datosGenerales.fechaInicio = valor);
    _notifier.marcarCambiosSinGuardar();
  }

  Future<void> _cancelar(bool tieneCambios) async {
    if (!tieneCambios) {
      _notifier.cancelarEdicion();
      return;
    }

    final l10n = AppLocalizations.of(context)!;
    final confirmado = await RisegDialog.showConfirmation(
      context: context,
      title: l10n.empresaCancelarConfirmacionTitulo,
      message: l10n.empresaCancelarConfirmacionMensaje,
      confirmLabel: l10n.empresaCancelarConfirmacionConfirmar,
      cancelLabel: l10n.empresaCancelarConfirmacionCancelar,
      destructive: true,
    );
    if (confirmado == true) _notifier.cancelarEdicion();
  }

  Future<void> _guardar() async {
    final l10n = AppLocalizations.of(context)!;
    final exito = await _notifier.guardar(_datosGenerales.capturar());
    if (!mounted) return;

    final estadoActual = ref.read(servicioExpedienteControllerProvider(widget.servicioId));
    if (exito) {
      if (estadoActual.datos != null) {
        _datosGenerales.poblar(estadoActual.datos!.servicio);
      }
      RisegFeedback.showSuccess(context, l10n.servicioGuardadoExito);
    } else if (estadoActual.errorGuardadoGeneral) {
      RisegFeedback.showError(context, l10n.servicioGuardadoErrorGeneral);
    }
  }

  void _mostrarResultadoCambioEstatus(CambiarEstatusServicioResultado? resultado) {
    final l10n = AppLocalizations.of(context)!;
    switch (resultado) {
      case CambiarEstatusServicioExitoso():
        RisegFeedback.showSuccess(context, l10n.servicioCambiarEstatusExito);
      case CambiarEstatusServicioTransicionInvalida():
        RisegFeedback.showError(context, l10n.servicioCambiarEstatusErrorTransicionInvalida);
      case CambiarEstatusServicioClienteNoDisponible():
        RisegFeedback.showError(context, l10n.servicioCambiarEstatusErrorClienteNoDisponible);
      case CambiarEstatusServicioFaltaDireccionOperativa():
        RisegFeedback.showError(context, l10n.servicioCambiarEstatusErrorFaltaDireccion);
      case CambiarEstatusServicioRequiereFechaTermino():
        RisegFeedback.showError(context, l10n.servicioCambiarEstatusErrorRequiereFechaTermino);
      case CambiarEstatusServicioFechaTerminoInvalida():
        RisegFeedback.showError(context, l10n.servicioCambiarEstatusErrorFechaTerminoInvalida);
      case CambiarEstatusServicioErrorInesperado():
        RisegFeedback.showError(context, l10n.servicioCambiarEstatusErrorInesperado);
      case null:
        break;
    }
  }

  Future<void> _activarOReactivar(EstatusServicio actual) async {
    final l10n = AppLocalizations.of(context)!;
    final esReactivar = actual == EstatusServicio.terminado;

    final confirmado = await RisegDialog.showConfirmation(
      context: context,
      title: esReactivar ? l10n.servicioConfirmarReactivarTitulo : l10n.servicioBotonActivar,
      message: esReactivar ? l10n.servicioConfirmarReactivarMensaje : l10n.servicioBotonActivar,
      confirmLabel: esReactivar ? l10n.servicioBotonReactivar : l10n.servicioBotonActivar,
      cancelLabel: l10n.servicioTerminarBotonCancelar,
    );
    if (confirmado != true) return;

    final resultado = await _notifier.cambiarEstatus(EstatusServicio.activo);
    if (!mounted) return;
    _mostrarResultadoCambioEstatus(resultado);
  }

  Future<void> _suspender() async {
    final l10n = AppLocalizations.of(context)!;
    final confirmado = await RisegDialog.showConfirmation(
      context: context,
      title: l10n.servicioConfirmarSuspenderTitulo,
      message: l10n.servicioConfirmarSuspenderMensaje,
      confirmLabel: l10n.servicioBotonSuspender,
      cancelLabel: l10n.servicioTerminarBotonCancelar,
    );
    if (confirmado != true) return;

    final resultado = await _notifier.cambiarEstatus(EstatusServicio.suspendido);
    if (!mounted) return;
    _mostrarResultadoCambioEstatus(resultado);
  }

  Future<void> _terminar(DateTime? fechaTerminoExistente) async {
    final l10n = AppLocalizations.of(context)!;

    if (fechaTerminoExistente != null) {
      final confirmado = await RisegDialog.showConfirmation(
        context: context,
        title: l10n.servicioTerminarDialogoTitulo,
        message: '${l10n.servicioTerminarDialogoMensaje} ${_formatoFecha.format(fechaTerminoExistente)}',
        confirmLabel: l10n.servicioTerminarBotonConfirmar,
        cancelLabel: l10n.servicioTerminarBotonCancelar,
        destructive: true,
      );
      if (confirmado != true) return;

      final resultado = await _notifier.cambiarEstatus(EstatusServicio.terminado);
      if (!mounted) return;
      _mostrarResultadoCambioEstatus(resultado);
      return;
    }

    DateTime? fechaEfectiva;
    final confirmado = await RisegDialog.showForm<bool>(
      context: context,
      title: l10n.servicioTerminarDialogoTitulo,
      confirmLabel: l10n.servicioTerminarBotonConfirmar,
      cancelLabel: l10n.servicioTerminarBotonCancelar,
      contentBuilder: (_) => RisegDateField(
        label: l10n.servicioTerminarCampoFecha,
        value: fechaEfectiva,
        onChanged: (valor) => fechaEfectiva = valor,
      ),
      onConfirm: () async => true,
    );
    if (confirmado != true) return;

    final resultado = await _notifier.cambiarEstatus(
      EstatusServicio.terminado,
      fechaTerminoEfectiva: fechaEfectiva,
    );
    if (!mounted) return;
    _mostrarResultadoCambioEstatus(resultado);
  }

  String _nombreEstatus(AppLocalizations l10n, EstatusServicio estatus) {
    return switch (estatus) {
      EstatusServicio.activo => l10n.servicioEstatusActivo,
      EstatusServicio.suspendido => l10n.servicioEstatusSuspendido,
      EstatusServicio.terminado => l10n.servicioEstatusTerminado,
      EstatusServicio.cotizado => l10n.servicioEstatusCotizado,
    };
  }

  RisegStatusTone _tonoEstatus(EstatusServicio estatus) {
    return switch (estatus) {
      EstatusServicio.activo => RisegStatusTone.success,
      EstatusServicio.suspendido => RisegStatusTone.warning,
      EstatusServicio.terminado => RisegStatusTone.neutral,
      EstatusServicio.cotizado => RisegStatusTone.info,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(servicioExpedienteControllerProvider(widget.servicioId));

    return Scaffold(
      appBar: AppBar(title: Text(state.datos?.servicio.nombre ?? l10n.servicioSeccionDatosGeneralesTitulo)),
      body: _buildBody(context, l10n, state),
    );
  }

  Widget _buildBody(BuildContext context, AppLocalizations l10n, ServicioExpedienteState state) {
    if (state.datos == null && state.errorCarga != null) {
      return RisegEmptyState(
        icon: Icons.error_outline,
        title: l10n.servicioExpedienteCargaErrorTitulo,
        message: l10n.servicioExpedienteCargaErrorMensaje,
        primaryAction: RisegButton(
          key: const Key('servicio_expediente_boton_reintentar'),
          label: l10n.servicioExpedienteBotonReintentar,
          onPressed: _notifier.reintentarCarga,
        ),
      );
    }

    if (state.datos == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final datos = state.datos!;
    final servicio = datos.servicio;
    final esEdicion = state.modo == ServicioExpedienteModo.edicion;
    final habilitado = !state.guardando;
    final errorNombreRequerido =
        state.erroresGuardado.any((e) => e.campo == CampoServicio.nombre && e.codigo == CodigoErrorServicio.requerido);
    final errorTipoServicio = state.erroresGuardado.any((e) => e.campo == CampoServicio.tipoServicio)
        ? l10n.servicioErrorTipoServicioRequerido
        : null;
    final errorFechaInicioRequerida = state.erroresGuardado.any((e) => e.campo == CampoServicio.fechaInicio);
    final estatusActual = EstatusServicio.values.byName(servicio.estatus);

    final mostrarActivar = estatusActual != EstatusServicio.activo;
    final mostrarSuspender = estatusActual == EstatusServicio.cotizado || estatusActual == EstatusServicio.activo;
    final mostrarTerminar = estatusActual != EstatusServicio.terminado;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RisegSectionHeader(
                title: l10n.servicioSeccionDatosGeneralesTitulo,
                primaryAction: esEdicion
                    ? RisegButton(
                        key: const Key('servicio_expediente_boton_guardar'),
                        label: l10n.servicioExpedienteBotonGuardar,
                        loading: state.guardando,
                        onPressed: _guardar,
                      )
                    : RisegButton(
                        key: const Key('servicio_expediente_boton_editar'),
                        label: l10n.servicioExpedienteBotonEditar,
                        onPressed: () => _iniciarEdicion(servicio),
                      ),
                secondaryAction: esEdicion
                    ? RisegButton(
                        key: const Key('servicio_expediente_boton_cancelar'),
                        label: l10n.servicioExpedienteBotonCancelar,
                        variant: RisegButtonVariant.ghost,
                        onPressed: state.guardando ? null : () => _cancelar(state.tieneCambiosSinGuardar),
                      )
                    : null,
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                children: [
                  RisegStatusBadge(
                    label: _nombreEstatus(l10n, estatusActual),
                    tone: _tonoEstatus(estatusActual),
                  ),
                  if (mostrarActivar)
                    RisegButton(
                      key: const Key('servicio_boton_activar'),
                      label: estatusActual == EstatusServicio.terminado
                          ? l10n.servicioBotonReactivar
                          : l10n.servicioBotonActivar,
                      variant: RisegButtonVariant.secondary,
                      size: RisegButtonSize.compact,
                      loading: state.cambiandoEstatus,
                      onPressed: datos.tieneDireccionOperativaActiva
                          ? () => _activarOReactivar(estatusActual)
                          : null,
                    ),
                  if (mostrarSuspender)
                    RisegButton(
                      key: const Key('servicio_boton_suspender'),
                      label: l10n.servicioBotonSuspender,
                      variant: RisegButtonVariant.secondary,
                      size: RisegButtonSize.compact,
                      loading: state.cambiandoEstatus,
                      onPressed: _suspender,
                    ),
                  if (mostrarTerminar)
                    RisegButton(
                      key: const Key('servicio_boton_terminar'),
                      label: l10n.servicioBotonTerminar,
                      variant: RisegButtonVariant.secondary,
                      size: RisegButtonSize.compact,
                      loading: state.cambiandoEstatus,
                      onPressed: () => _terminar(servicio.fechaTermino),
                    ),
                ],
              ),
              if (mostrarActivar && !datos.tieneDireccionOperativaActiva) ...[
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  l10n.servicioBotonActivarAyudaSinDireccion,
                  style: AppTypography.caption.copyWith(color: Theme.of(context).colorScheme.outline),
                ),
              ],
              const SizedBox(height: AppSpacing.xl),
              RisegCard(
                child: ServicioDatosGeneralesSection(
                  modo: state.modo,
                  servicio: servicio,
                  controllers: _datosGenerales,
                  tiposServicio: _tiposServicio,
                  habilitado: habilitado,
                  errorNombreRequerido: errorNombreRequerido,
                  errorTipoServicio: errorTipoServicio,
                  errorFechaInicioRequerida: errorFechaInicioRequerida,
                  onCampoModificado: _notifier.marcarCambiosSinGuardar,
                  onTipoServicioCambiado: _onTipoServicioCambiado,
                  onFechaInicioCambiado: _onFechaInicioCambiada,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
