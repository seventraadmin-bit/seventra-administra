import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/organizacion/data/tables/cliente_table.dart';
import 'package:riseg_one/features/organizacion/data/tables/contacto_table.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/cliente_expediente_errors.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/cliente_expediente_input.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/contacto_validator.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_contacto_resultado.dart';
import 'package:riseg_one/features/organizacion/presentation/shared/direccion_controllers.dart';

import 'cliente_expediente_controller.dart';
import 'cliente_expediente_form_controllers.dart';
import 'cliente_expediente_state.dart';
import 'widgets/cliente_datos_generales_section.dart';
import 'widgets/contactos_section.dart';
import 'widgets/direccion_referencia_section.dart';

/// Pantalla de expediente de Cliente comercial — mismo patrón consulta/
/// edición que Puesto/Sucursal; se apila (`push`) sobre el listado, así
/// que trae su propio `Scaffold`/`AppBar` con botón de regreso.
class ClienteExpedienteScreen extends ConsumerStatefulWidget {
  const ClienteExpedienteScreen({required this.clienteId, super.key});

  final String clienteId;

  @override
  ConsumerState<ClienteExpedienteScreen> createState() => _ClienteExpedienteScreenState();
}

class _ClienteExpedienteScreenState extends ConsumerState<ClienteExpedienteScreen> {
  final _datosGenerales = ClienteDatosGeneralesControllers();
  final _direccionReferencia = DireccionControllers();

  @override
  void dispose() {
    _datosGenerales.dispose();
    _direccionReferencia.dispose();
    super.dispose();
  }

  ClienteExpedienteController get _notifier =>
      ref.read(clienteExpedienteControllerProvider(widget.clienteId).notifier);

  void _iniciarEdicion(ClienteData cliente, DireccionData? direccion) {
    _datosGenerales.poblar(cliente);
    _direccionReferencia.poblar(direccion);
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
    final input = ClienteExpedienteInput(
      datosGenerales: _datosGenerales.capturar(),
      direccionReferencia: _direccionReferencia.capturar(),
    );

    final exito = await _notifier.guardar(input);
    if (!mounted) return;

    final estadoActual = ref.read(clienteExpedienteControllerProvider(widget.clienteId));
    if (exito) {
      if (estadoActual.datos != null) {
        _datosGenerales.poblar(estadoActual.datos!.cliente);
        _direccionReferencia.poblar(estadoActual.datos!.direccionReferencia);
      }
      RisegFeedback.showSuccess(context, l10n.clienteGuardadoExito);
    } else if (estadoActual.errorGuardadoGeneral) {
      RisegFeedback.showError(context, l10n.clienteGuardadoErrorGeneral);
    }
  }

  Future<void> _mostrarDialogoCambiarEstatus(EstatusCliente actual) async {
    final l10n = AppLocalizations.of(context)!;
    var nuevo = actual;

    final confirmado = await RisegDialog.showForm<bool>(
      context: context,
      title: l10n.clienteCambiarEstatusTitulo,
      confirmLabel: l10n.clienteCambiarEstatusBotonGuardar,
      cancelLabel: l10n.clienteCambiarEstatusBotonCancelar,
      contentBuilder: (_) => _CambiarEstatusForm(
        estatusInicial: actual,
        onCambio: (valor) => nuevo = valor,
      ),
      onConfirm: () async {
        if (nuevo == actual) return true;
        return _notifier.cambiarEstatus(nuevo);
      },
    );

    if (!mounted || confirmado != true) return;
    if (nuevo == actual) return;

    final estadoActual = ref.read(clienteExpedienteControllerProvider(widget.clienteId));
    if (estadoActual.datos?.cliente.estatus == nuevo.name) {
      RisegFeedback.showSuccess(context, l10n.clienteCambiarEstatusExito);
    } else {
      RisegFeedback.showError(context, l10n.clienteCambiarEstatusError);
    }
  }

  Future<void> _mostrarDialogoContacto({ContactoData? contactoExistente}) async {
    final l10n = AppLocalizations.of(context)!;
    var borrador = ContactoBorrador(
      nombre: contactoExistente?.nombre ?? '',
      tipo: contactoExistente == null ? null : TipoContacto.values.byName(contactoExistente.tipo),
      puesto: contactoExistente?.puesto,
      telefono: contactoExistente?.telefono,
      correo: contactoExistente?.correo,
      esPrincipal: contactoExistente?.esPrincipal ?? false,
    );

    final resultado = await RisegDialog.showForm<GuardarContactoResultado>(
      context: context,
      title: contactoExistente == null
          ? l10n.clienteContactoDialogoTituloAlta
          : l10n.clienteContactoDialogoTituloEdicion,
      confirmLabel: l10n.clienteContactoDialogoBotonGuardar,
      cancelLabel: l10n.clienteContactoDialogoBotonCancelar,
      contentBuilder: (_) => ContactoForm(
        contactoInicial: contactoExistente,
        onCambio: (nuevo) => borrador = nuevo,
      ),
      onConfirm: () async {
        if (contactoExistente == null) {
          return _notifier.agregarContacto(borrador);
        }
        return _notifier.actualizarContacto(contactoExistente.id, borrador);
      },
    );

    if (!mounted) return;

    switch (resultado) {
      case GuardarContactoExitoso():
        RisegFeedback.showSuccess(context, l10n.clienteContactoGuardadoExito);
      case GuardarContactoErroresValidacion():
      case GuardarContactoErrorInesperado():
        RisegFeedback.showError(context, l10n.clienteContactoGuardadoError);
      case null:
        break;
    }
  }

  Future<void> _archivarContacto(ContactoData contacto) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmado = await RisegDialog.showConfirmation(
      context: context,
      title: l10n.clienteContactoArchivarConfirmarTitulo,
      message: l10n.clienteContactoArchivarConfirmarMensaje,
      confirmLabel: l10n.sucursalConfirmarAceptar,
      cancelLabel: l10n.sucursalConfirmarCancelar,
      destructive: true,
    );
    if (confirmado != true) return;

    await _notifier.archivarContacto(contacto.id);
    if (!mounted) return;
    RisegFeedback.showSuccess(context, l10n.clienteContactoArchivadoExito);
  }

  Future<void> _marcarComoPrincipal(ContactoData contacto) async {
    final l10n = AppLocalizations.of(context)!;
    final resultado = await _notifier.actualizarContacto(
      contacto.id,
      ContactoBorrador(
        nombre: contacto.nombre,
        tipo: TipoContacto.values.byName(contacto.tipo),
        puesto: contacto.puesto,
        telefono: contacto.telefono,
        correo: contacto.correo,
        esPrincipal: true,
      ),
    );
    if (!mounted) return;
    if (resultado is GuardarContactoExitoso) {
      RisegFeedback.showSuccess(context, l10n.clienteContactoGuardadoExito);
    } else {
      RisegFeedback.showError(context, l10n.clienteContactoGuardadoError);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(clienteExpedienteControllerProvider(widget.clienteId));

    return Scaffold(
      appBar: AppBar(title: Text(state.datos?.cliente.nombreComercial ?? l10n.clienteSeccionDatosGeneralesTitulo)),
      body: _buildBody(context, l10n, state),
    );
  }

  Widget _buildBody(BuildContext context, AppLocalizations l10n, ClienteExpedienteState state) {
    if (state.datos == null && state.errorCarga != null) {
      return RisegEmptyState(
        icon: Icons.error_outline,
        title: l10n.clienteExpedienteCargaErrorTitulo,
        message: l10n.clienteExpedienteCargaErrorMensaje,
        primaryAction: RisegButton(
          key: const Key('cliente_expediente_boton_reintentar'),
          label: l10n.clienteExpedienteBotonReintentar,
          onPressed: _notifier.reintentarCarga,
        ),
      );
    }

    if (state.datos == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final datos = state.datos!;
    final cliente = datos.cliente;
    final esEdicion = state.modo == ClienteExpedienteModo.edicion;
    final habilitado = !state.guardando;
    final erroresDireccion = state.erroresGuardado.whereType<ErrorDireccionCliente>().map((e) => e.error).toList();
    final errorNombreRequerido = state.erroresGuardado.any((e) => e is ErrorNombreComercialRequerido);
    final estatusActual = EstatusCliente.values.byName(cliente.estatus);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RisegSectionHeader(
                title: l10n.clienteSeccionDatosGeneralesTitulo,
                primaryAction: esEdicion
                    ? RisegButton(
                        key: const Key('cliente_expediente_boton_guardar'),
                        label: l10n.clienteExpedienteBotonGuardar,
                        loading: state.guardando,
                        onPressed: _guardar,
                      )
                    : RisegButton(
                        key: const Key('cliente_expediente_boton_editar'),
                        label: l10n.clienteExpedienteBotonEditar,
                        onPressed: () => _iniciarEdicion(cliente, datos.direccionReferencia),
                      ),
                secondaryAction: esEdicion
                    ? RisegButton(
                        key: const Key('cliente_expediente_boton_cancelar'),
                        label: l10n.clienteExpedienteBotonCancelar,
                        variant: RisegButtonVariant.ghost,
                        onPressed: state.guardando ? null : () => _cancelar(state.tieneCambiosSinGuardar),
                      )
                    : null,
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  RisegStatusBadge(label: _nombreEstatus(l10n, estatusActual), tone: _tonoEstatus(estatusActual)),
                  const SizedBox(width: AppSpacing.sm),
                  RisegButton(
                    key: const Key('cliente_boton_cambiar_estatus'),
                    label: l10n.clienteBotonCambiarEstatus,
                    variant: RisegButtonVariant.secondary,
                    size: RisegButtonSize.compact,
                    loading: state.cambiandoEstatus,
                    onPressed: () => _mostrarDialogoCambiarEstatus(estatusActual),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),
              RisegCard(
                child: ClienteDatosGeneralesSection(
                  modo: state.modo,
                  cliente: cliente,
                  controllers: _datosGenerales,
                  habilitado: habilitado,
                  errorNombreComercialRequerido: errorNombreRequerido,
                  onCampoModificado: _notifier.marcarCambiosSinGuardar,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              RisegCard(
                child: DireccionReferenciaSection(
                  modo: state.modo,
                  direccion: datos.direccionReferencia,
                  controllers: _direccionReferencia,
                  habilitado: habilitado,
                  errores: erroresDireccion,
                  onCampoModificado: _notifier.marcarCambiosSinGuardar,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              RisegCard(
                child: ContactosSection(
                  contactos: datos.contactos,
                  onAgregar: () => _mostrarDialogoContacto(),
                  onEditar: (contacto) => _mostrarDialogoContacto(contactoExistente: contacto),
                  onArchivar: _archivarContacto,
                  onMarcarPrincipal: _marcarComoPrincipal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _nombreEstatus(AppLocalizations l10n, EstatusCliente estatus) {
    return switch (estatus) {
      EstatusCliente.activo => l10n.clienteEstatusActivo,
      EstatusCliente.suspendido => l10n.clienteEstatusSuspendido,
      EstatusCliente.terminado => l10n.clienteEstatusTerminado,
      EstatusCliente.descartado => l10n.clienteEstatusDescartado,
      EstatusCliente.prospecto => l10n.clienteEstatusProspecto,
    };
  }

  RisegStatusTone _tonoEstatus(EstatusCliente estatus) {
    return switch (estatus) {
      EstatusCliente.activo => RisegStatusTone.success,
      EstatusCliente.suspendido => RisegStatusTone.warning,
      EstatusCliente.descartado => RisegStatusTone.error,
      EstatusCliente.terminado => RisegStatusTone.neutral,
      EstatusCliente.prospecto => RisegStatusTone.info,
    };
  }
}

/// Contenido del diálogo de cambio de estatus — un simple `RisegSelect`
/// entre los 5 valores posibles; cualquier transición está permitida en
/// esta etapa (ver `CambiarEstatusClienteUseCase`).
class _CambiarEstatusForm extends StatefulWidget {
  const _CambiarEstatusForm({required this.estatusInicial, required this.onCambio});

  final EstatusCliente estatusInicial;
  final ValueChanged<EstatusCliente> onCambio;

  @override
  State<_CambiarEstatusForm> createState() => _CambiarEstatusFormState();
}

class _CambiarEstatusFormState extends State<_CambiarEstatusForm> {
  late EstatusCliente _valor = widget.estatusInicial;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return RisegSelect<EstatusCliente>(
      label: l10n.clienteCambiarEstatusCampoNuevoEstatus,
      value: _valor,
      items: [
        RisegSelectItem(value: EstatusCliente.prospecto, label: l10n.clienteEstatusProspecto),
        RisegSelectItem(value: EstatusCliente.activo, label: l10n.clienteEstatusActivo),
        RisegSelectItem(value: EstatusCliente.suspendido, label: l10n.clienteEstatusSuspendido),
        RisegSelectItem(value: EstatusCliente.terminado, label: l10n.clienteEstatusTerminado),
        RisegSelectItem(value: EstatusCliente.descartado, label: l10n.clienteEstatusDescartado),
      ],
      onChanged: (valor) {
        if (valor == null) return;
        setState(() => _valor = valor);
        widget.onCambio(valor);
      },
    );
  }
}
