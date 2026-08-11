import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/tables/audit_columns.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/organizacion/data/tables/puesto_table.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';

import 'puesto_expediente_controller.dart';
import 'puesto_expediente_form_controllers.dart';
import 'puesto_expediente_state.dart';
import 'widgets/eliminar_puesto_fisicamente_dialog.dart';
import 'widgets/puesto_datos_generales_section.dart';

/// Pantalla de expediente de Puesto — mismo patrón consulta/edición que
/// `SucursalExpedienteScreen`, sin sub-entidades: una sola sección. Se
/// apila (`push`) sobre el listado, así que trae su propio `Scaffold`/
/// `AppBar` con botón de regreso.
class PuestoExpedienteScreen extends ConsumerStatefulWidget {
  const PuestoExpedienteScreen({required this.puestoId, super.key});

  final String puestoId;

  @override
  ConsumerState<PuestoExpedienteScreen> createState() => _PuestoExpedienteScreenState();
}

class _PuestoExpedienteScreenState extends ConsumerState<PuestoExpedienteScreen> {
  final _datosGenerales = PuestoDatosGeneralesControllers();

  @override
  void dispose() {
    _datosGenerales.dispose();
    super.dispose();
  }

  PuestoExpedienteController get _notifier =>
      ref.read(puestoExpedienteControllerProvider(widget.puestoId).notifier);

  void _iniciarEdicion(PuestoData puesto) {
    _datosGenerales.poblar(puesto);
    _notifier.entrarModoEdicion();
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

    final estadoActual = ref.read(puestoExpedienteControllerProvider(widget.puestoId));
    if (exito) {
      if (estadoActual.datos != null) _datosGenerales.poblar(estadoActual.datos!);
      RisegFeedback.showSuccess(context, l10n.puestoGuardadoExito);
    } else if (estadoActual.errorGuardadoGeneral) {
      RisegFeedback.showError(context, l10n.puestoGuardadoErrorGeneral);
    }
  }

  Future<void> _confirmarCambioCiclo(CicloVidaRegistro nuevo) async {
    final l10n = AppLocalizations.of(context)!;
    final archivando = nuevo == CicloVidaRegistro.archivado;

    final confirmado = await RisegDialog.showConfirmation(
      context: context,
      title: archivando ? l10n.puestoConfirmarArchivarTitulo : l10n.puestoConfirmarReactivarTitulo,
      message: archivando ? l10n.puestoConfirmarArchivarMensaje : l10n.puestoConfirmarReactivarMensaje,
      confirmLabel: l10n.sucursalConfirmarAceptar,
      cancelLabel: l10n.sucursalConfirmarCancelar,
    );
    if (confirmado != true) return;

    final exito = await _notifier.cambiarCicloVida(nuevo);
    if (!mounted) return;
    if (exito) {
      RisegFeedback.showSuccess(context, l10n.puestoCicloVidaCambiadoExito);
    } else {
      RisegFeedback.showError(
        context,
        archivando ? l10n.puestoCicloVidaCambiadoErrorGeneral : l10n.puestoReactivarBloqueadoError,
      );
    }
  }

  Future<void> _eliminarFisicamente() async {
    final eliminado = await mostrarDialogoEliminarPuestoFisicamente(context, ref, widget.puestoId);
    if (eliminado && mounted) context.pop();
  }

  void _onAreaCambiada(String? valor) {
    setState(() => _datosGenerales.areaId = valor);
    _notifier.marcarCambiosSinGuardar();
  }

  void _onTipoCambiado(TipoPuesto? valor) {
    setState(() => _datosGenerales.tipo = valor);
    _notifier.marcarCambiosSinGuardar();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(puestoExpedienteControllerProvider(widget.puestoId));

    return Scaffold(
      appBar: AppBar(title: Text(state.datos?.nombre ?? l10n.puestoSeccionDatosGeneralesTitulo)),
      body: _buildBody(context, l10n, state),
    );
  }

  Widget _buildBody(BuildContext context, AppLocalizations l10n, PuestoExpedienteState state) {
    if (state.datos == null && state.errorCarga != null) {
      return RisegEmptyState(
        icon: Icons.error_outline,
        title: l10n.puestoExpedienteCargaErrorTitulo,
        message: l10n.puestoExpedienteCargaErrorMensaje,
        primaryAction: RisegButton(
          key: const Key('puesto_expediente_boton_reintentar'),
          label: l10n.puestoExpedienteBotonReintentar,
          onPressed: _notifier.reintentarCarga,
        ),
      );
    }

    if (state.datos == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final puesto = state.datos!;
    final esEdicion = state.modo == PuestoExpedienteModo.edicion;
    final habilitado = !state.guardando;
    final archivado = puesto.cicloVidaRegistro == CicloVidaRegistro.archivado.name;
    final esMaestro = ref.watch(sesionControllerProvider)?.esMaestro ?? false;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RisegSectionHeader(
                title: l10n.puestoSeccionDatosGeneralesTitulo,
                primaryAction: esEdicion
                    ? RisegButton(
                        key: const Key('puesto_expediente_boton_guardar'),
                        label: l10n.puestoExpedienteBotonGuardar,
                        loading: state.guardando,
                        onPressed: _guardar,
                      )
                    : RisegButton(
                        key: const Key('puesto_expediente_boton_editar'),
                        label: l10n.puestoExpedienteBotonEditar,
                        onPressed: () => _iniciarEdicion(puesto),
                      ),
                secondaryAction: esEdicion
                    ? RisegButton(
                        key: const Key('puesto_expediente_boton_cancelar'),
                        label: l10n.puestoExpedienteBotonCancelar,
                        variant: RisegButtonVariant.ghost,
                        onPressed: state.guardando ? null : () => _cancelar(state.tieneCambiosSinGuardar),
                      )
                    : null,
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  RisegStatusBadge(
                    label: archivado ? l10n.puestoEstadoArchivado : l10n.puestoEstadoActivo,
                    tone: archivado ? RisegStatusTone.neutral : RisegStatusTone.success,
                  ),
                  RisegButton(
                    key: const Key('puesto_boton_ciclo_vida'),
                    label: archivado ? l10n.puestoBotonReactivar : l10n.puestoBotonArchivar,
                    variant: RisegButtonVariant.secondary,
                    size: RisegButtonSize.compact,
                    loading: state.cambiandoCicloVida,
                    onPressed: () => _confirmarCambioCiclo(
                      archivado ? CicloVidaRegistro.activo : CicloVidaRegistro.archivado,
                    ),
                  ),
                  if (esMaestro && !esEdicion)
                    RisegButton(
                      key: const Key('puesto_boton_eliminar_fisicamente'),
                      label: l10n.eliminacionFisicaAccionMenu,
                      variant: RisegButtonVariant.danger,
                      size: RisegButtonSize.compact,
                      onPressed: _eliminarFisicamente,
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),
              RisegCard(
                child: PuestoDatosGeneralesSection(
                  modo: state.modo,
                  puesto: puesto,
                  areas: state.areas,
                  controllers: _datosGenerales,
                  habilitado: habilitado,
                  errores: state.erroresGuardado,
                  onAreaCambiada: _onAreaCambiada,
                  onTipoCambiado: _onTipoCambiado,
                  onCampoModificado: _notifier.marcarCambiosSinGuardar,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
