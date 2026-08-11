import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/organizacion/data/tables/sucursal_table.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/sucursal_expediente_data.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/sucursal_expediente_errors.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/sucursal_expediente_input.dart';
import 'package:riseg_one/features/organizacion/presentation/shared/direccion_controllers.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';

import 'sucursal_expediente_controller.dart';
import 'sucursal_expediente_form_controllers.dart';
import 'sucursal_expediente_state.dart';
import 'widgets/direccion_principal_section.dart';
import 'widgets/eliminar_sucursal_fisicamente_dialog.dart';
import 'widgets/horario_section.dart';
import 'widgets/sucursal_datos_generales_section.dart';
import 'widgets/ubicaciones_arbol_widget.dart';

/// Pantalla de expediente de Sucursal — mismo patrón consulta/edición
/// que `EmpresaExpedienteScreen`, más el árbol de Ubicaciones (fuera del
/// ciclo de edición) y el estado operativo (acción de botón, no campo).
/// A diferencia del expediente de Empresa, esta pantalla se apila
/// (`push`) sobre el listado, así que trae su propio `Scaffold`/`AppBar`
/// con botón de regreso.
class SucursalExpedienteScreen extends ConsumerStatefulWidget {
  const SucursalExpedienteScreen({required this.sucursalId, super.key});

  final String sucursalId;

  @override
  ConsumerState<SucursalExpedienteScreen> createState() => _SucursalExpedienteScreenState();
}

class _SucursalExpedienteScreenState extends ConsumerState<SucursalExpedienteScreen> {
  final _datosGenerales = SucursalDatosGeneralesControllers();
  final _direccionPrincipal = DireccionControllers();
  final _horario = HorarioControllers();

  @override
  void dispose() {
    _datosGenerales.dispose();
    _direccionPrincipal.dispose();
    super.dispose();
  }

  void _poblarControladores(SucursalExpedienteData datos) {
    _datosGenerales.poblar(datos.sucursal);
    _direccionPrincipal.poblar(datos.direccionPrincipal);
    _horario.poblar(datos.horario);
  }

  SucursalExpedienteController get _notifier =>
      ref.read(sucursalExpedienteControllerProvider(widget.sucursalId).notifier);

  void _iniciarEdicion(SucursalExpedienteData datos) {
    _poblarControladores(datos);
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
    final input = SucursalExpedienteInput(
      datosGenerales: _datosGenerales.capturar(),
      direccionPrincipal: _direccionPrincipal.capturar(),
      horario: _horario.capturar(),
    );

    final exito = await _notifier.guardar(input);
    if (!mounted) return;

    final estadoActual = ref.read(sucursalExpedienteControllerProvider(widget.sucursalId));
    if (exito) {
      if (estadoActual.datos != null) _poblarControladores(estadoActual.datos!);
      RisegFeedback.showSuccess(context, l10n.sucursalGuardadoExito);
    } else if (estadoActual.errorGuardadoGeneral) {
      RisegFeedback.showError(context, l10n.sucursalGuardadoErrorGeneral);
    }
  }

  Future<void> _confirmarCambioEstado(EstadoOperativoSucursal nuevo) async {
    final l10n = AppLocalizations.of(context)!;
    final cerrando = nuevo == EstadoOperativoSucursal.cerradaTemporalmente;

    final confirmado = await RisegDialog.showConfirmation(
      context: context,
      title: cerrando ? l10n.sucursalConfirmarCerrarTitulo : l10n.sucursalConfirmarReabrirTitulo,
      message: cerrando ? l10n.sucursalConfirmarCerrarMensaje : l10n.sucursalConfirmarReabrirMensaje,
      confirmLabel: l10n.sucursalConfirmarAceptar,
      cancelLabel: l10n.sucursalConfirmarCancelar,
    );
    if (confirmado != true) return;

    final exito = await _notifier.cambiarEstadoOperativo(nuevo);
    if (!mounted) return;
    if (exito) {
      RisegFeedback.showSuccess(context, l10n.sucursalEstadoOperativoCambiadoExito);
    } else {
      RisegFeedback.showError(context, l10n.sucursalEstadoOperativoCambiadoError);
    }
  }

  Future<void> _eliminarFisicamente() async {
    final eliminado = await mostrarDialogoEliminarSucursalFisicamente(context, ref, widget.sucursalId);
    if (eliminado && mounted) context.pop();
  }

  void _onTipoCambiado(String? valor) {
    setState(() => _datosGenerales.tipoSucursalId = valor);
    _notifier.marcarCambiosSinGuardar();
  }

  void _onDiaCambiado(int diaSemana, HorarioDiaControlador nuevoValor) {
    setState(() => _horario.dias[diaSemana] = nuevoValor);
    _notifier.marcarCambiosSinGuardar();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(sucursalExpedienteControllerProvider(widget.sucursalId));

    return Scaffold(
      appBar: AppBar(title: Text(state.datos?.sucursal.nombre ?? l10n.sucursalSeccionDatosGeneralesTitulo)),
      body: _buildBody(context, l10n, state),
    );
  }

  Widget _buildBody(BuildContext context, AppLocalizations l10n, SucursalExpedienteState state) {
    if (state.datos == null && state.errorCarga != null) {
      return RisegEmptyState(
        icon: Icons.error_outline,
        title: l10n.sucursalExpedienteCargaErrorTitulo,
        message: l10n.sucursalExpedienteCargaErrorMensaje,
        primaryAction: RisegButton(
          key: const Key('sucursal_expediente_boton_reintentar'),
          label: l10n.sucursalExpedienteBotonReintentar,
          onPressed: _notifier.reintentarCarga,
        ),
      );
    }

    if (state.datos == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final datos = state.datos!;
    final esEdicion = state.modo == SucursalExpedienteModo.edicion;
    final habilitado = !state.guardando;
    final erroresDireccion = state.erroresGuardado.whereType<ErrorDireccionSucursal>().map((e) => e.error).toList();
    final erroresHorario = state.erroresGuardado.whereType<ErrorHorarioSucursal>().toList();
    final errorTipoRequerido = state.erroresGuardado.any((e) => e is ErrorTipoSucursalRequerido);
    final operando = datos.sucursal.estadoOperativo == EstadoOperativoSucursal.operando.name;
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
                title: l10n.sucursalSeccionDatosGeneralesTitulo,
                primaryAction: esEdicion
                    ? RisegButton(
                        key: const Key('sucursal_expediente_boton_guardar'),
                        label: l10n.sucursalExpedienteBotonGuardar,
                        loading: state.guardando,
                        onPressed: _guardar,
                      )
                    : RisegButton(
                        key: const Key('sucursal_expediente_boton_editar'),
                        label: l10n.sucursalExpedienteBotonEditar,
                        onPressed: () => _iniciarEdicion(datos),
                      ),
                secondaryAction: esEdicion
                    ? RisegButton(
                        key: const Key('sucursal_expediente_boton_cancelar'),
                        label: l10n.sucursalExpedienteBotonCancelar,
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
                    label: operando ? l10n.sucursalEstadoOperativoOperando : l10n.sucursalEstadoOperativoCerradaTemporalmente,
                    tone: operando ? RisegStatusTone.success : RisegStatusTone.warning,
                  ),
                  RisegButton(
                    key: const Key('sucursal_boton_estado_operativo'),
                    label: operando ? l10n.sucursalBotonCerrarTemporalmente : l10n.sucursalBotonReabrir,
                    variant: RisegButtonVariant.secondary,
                    size: RisegButtonSize.compact,
                    loading: state.cambiandoEstadoOperativo,
                    onPressed: () => _confirmarCambioEstado(
                      operando ? EstadoOperativoSucursal.cerradaTemporalmente : EstadoOperativoSucursal.operando,
                    ),
                  ),
                  if (esMaestro && !esEdicion)
                    RisegButton(
                      key: const Key('sucursal_boton_eliminar_fisicamente'),
                      label: l10n.eliminacionFisicaAccionMenu,
                      variant: RisegButtonVariant.danger,
                      size: RisegButtonSize.compact,
                      onPressed: _eliminarFisicamente,
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),
              RisegCard(
                child: SucursalDatosGeneralesSection(
                  modo: state.modo,
                  sucursal: datos.sucursal,
                  tipos: state.tipos,
                  controllers: _datosGenerales,
                  habilitado: habilitado,
                  errorTipoRequerido: errorTipoRequerido,
                  onTipoCambiado: _onTipoCambiado,
                  onCampoModificado: _notifier.marcarCambiosSinGuardar,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              RisegCard(
                child: DireccionPrincipalSection(
                  modo: state.modo,
                  direccion: datos.direccionPrincipal,
                  controllers: _direccionPrincipal,
                  habilitado: habilitado,
                  errores: erroresDireccion,
                  onCampoModificado: _notifier.marcarCambiosSinGuardar,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              RisegCard(
                child: HorarioSection(
                  modo: state.modo,
                  horario: datos.horario,
                  controllers: _horario,
                  habilitado: habilitado,
                  errores: erroresHorario,
                  onDiaCambiado: _onDiaCambiado,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              RisegCard(child: UbicacionesArbolWidget(sucursalId: widget.sucursalId)),
            ],
          ),
        ),
      ),
    );
  }
}
