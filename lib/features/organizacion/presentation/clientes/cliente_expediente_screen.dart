import 'clientes_list_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/tables/audit_columns.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/core/validation/direccion_validator.dart';
import 'package:riseg_one/features/organizacion/data/tables/cliente_portal_table.dart';
import 'package:riseg_one/features/organizacion/data/tables/cliente_table.dart';
import 'package:riseg_one/features/organizacion/data/tables/contacto_table.dart';
import 'package:riseg_one/features/organizacion/domain/repositories/entidad_fiscal_repository.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/cliente_expediente_errors.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/cliente_expediente_input.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/cliente_portal_validator.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/contacto_validator.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/entidad_fiscal_validator.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_cliente_portal_resultado.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_contacto_resultado.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_domicilio_fiscal_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_entidad_fiscal_resultado.dart';
import 'package:riseg_one/features/organizacion/presentation/shared/direccion_controllers.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';

import '../../organizacion_providers.dart';
import 'cliente_comercial_resumen.dart';
import 'cliente_expediente_controller.dart';
import 'cliente_expediente_form_controllers.dart';
import 'cliente_expediente_state.dart';
import 'widgets/client_portales_section.dart';
import 'widgets/cliente_datos_generales_section.dart';
import 'widgets/cliente_ficha_header.dart';
import 'widgets/cliente_indicadores_comerciales.dart';
import 'widgets/cliente_servicios_section.dart';
import 'widgets/contactos_section.dart';
import 'widgets/direccion_referencia_section.dart';
import 'widgets/entidades_fiscales_section.dart';
import 'widgets/eliminar_cliente_fisicamente_dialog.dart';
import 'widgets/logo_cliente_dialog.dart';

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

    // Corregir los datos comerciales de un Cliente exige explicar por
    // qué: el motivo se pide antes de persistir nada.
    final motivo = await mostrarDialogoMotivo(
      context,
      titulo: l10n.clienteGuardarMotivoTitulo,
      etiquetaMotivo: l10n.auditoriaCampoMotivo,
      confirmarLabel: l10n.clienteCambiarEstatusBotonGuardar,
      cancelarLabel: l10n.clienteCambiarEstatusBotonCancelar,
      errorMotivoRequerido: l10n.auditoriaErrorMotivoRequerido,
    );
    if (!mounted || motivo == null) return;

    final exito = await _notifier.guardar(input, motivo: motivo);
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

  Future<void> _eliminarFisicamente() async {
    final eliminado = await mostrarDialogoEliminarClienteFisicamente(context, ref, widget.clienteId);
    if (!eliminado) return;
    // La eliminacion fisica no pasa por ningun controlador: sin esto el
    // renglon sobrevive en el listado de Clientes hasta que algo ajeno (cambiar de
    // pestana) reconstruya el provider. Navegar no es refrescar.
    ref.invalidate(clientesListControllerProvider);
    if (mounted) context.pop();
  }

  /// Cabecera de identidad comercial (Etapa 16, ficha comercial) —
  /// `FutureBuilder` propio: es un único detalle (no una lista de
  /// muchas filas), así que la consulta de un solo Attachment aquí no
  /// es el mismo riesgo de N+1 que en un listado.
  Widget _seccionFicha(
    BuildContext context,
    AppLocalizations l10n,
    ClienteData cliente,
    Widget estatusBadge,
    String? razonSocial,
    String? rfc,
    bool esEdicion,
    bool esMaestro,
    EstatusCliente estatusActual,
    bool cambiandoEstatus,
  ) {
    return FutureBuilder<AttachmentData?>(
      future: cliente.logoAttachmentId == null
          ? Future.value(null)
          : ref.read(attachmentRepositoryProvider).obtenerPorId(cliente.logoAttachmentId!),
      builder: (context, snapshot) {
        return ClienteFichaHeader(
          cliente: cliente,
          logoPath: snapshot.data?.path,
          razonSocial: razonSocial,
          rfc: rfc,
          estatusBadge: estatusBadge,
          acciones: esEdicion
              ? null
              : Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  children: [
                    RisegButton(
                      key: const Key('cliente_boton_editar_logo'),
                      label: l10n.clienteLogoBotonEditar,
                      variant: RisegButtonVariant.ghost,
                      size: RisegButtonSize.compact,
                      onPressed: () async {
                        final cambio = await mostrarDialogoLogoCliente(context, ref, cliente);
                        if (cambio) _notifier.reintentarCarga();
                      },
                    ),
                    RisegButton(
                      key: const Key('cliente_boton_cambiar_estatus'),
                      label: l10n.clienteBotonCambiarEstatus,
                      variant: RisegButtonVariant.secondary,
                      size: RisegButtonSize.compact,
                      loading: cambiandoEstatus,
                      onPressed: () => _mostrarDialogoCambiarEstatus(estatusActual),
                    ),
                    RisegButton(
                      key: const Key('cliente_expediente_boton_editar'),
                      label: l10n.clienteExpedienteBotonEditar,
                      size: RisegButtonSize.compact,
                      onPressed: () => _iniciarEdicion(cliente, ref.read(clienteExpedienteControllerProvider(widget.clienteId)).datos?.direccionReferencia),
                    ),
                    if (esMaestro)
                      RisegActionsMenu(
                        menuKey: const Key('cliente_menu_acciones'),
                        actions: [
                          RisegMenuAction(
                            key: const Key('cliente_accion_eliminar_fisicamente'),
                            label: l10n.eliminacionFisicaAccionMenu,
                            icon: Icons.delete_forever_outlined,
                            destructive: true,
                            onTap: _eliminarFisicamente,
                          ),
                        ],
                      ),
                  ],
                ),
        );
      },
    );
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
      onConfirm: () async => true,
    );

    if (!mounted || confirmado != true) return;
    if (nuevo == actual) return;

    // Cambiar el estatus comercial de un Cliente es una decisión que
    // tiene que poder explicarse después: el motivo se pide SIEMPRE,
    // con el diálogo común de motivo, y viaja a la bitácora.
    final motivo = await mostrarDialogoMotivo(
      context,
      titulo: l10n.clienteCambiarEstatusTitulo,
      etiquetaMotivo: l10n.auditoriaCampoMotivo,
      confirmarLabel: l10n.clienteCambiarEstatusBotonGuardar,
      cancelarLabel: l10n.clienteCambiarEstatusBotonCancelar,
      errorMotivoRequerido: l10n.auditoriaErrorMotivoRequerido,
    );
    if (!mounted || motivo == null) return;
    await _notifier.cambiarEstatus(nuevo, motivo: motivo);
    if (!mounted) return;

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

    final confirmadoContacto = await RisegDialog.showForm<bool>(
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
      onConfirm: () async => true,
    );

    if (!mounted || confirmadoContacto != true) return;

    final GuardarContactoResultado resultado;
    if (contactoExistente == null) {
      // Alta: sin motivo, no hay nada que justificar todavía.
      resultado = await _notifier.agregarContacto(borrador);
    } else {
      final motivo = await mostrarDialogoMotivo(
        context,
        titulo: l10n.clienteContactoMotivoTitulo,
        etiquetaMotivo: l10n.auditoriaCampoMotivo,
        confirmarLabel: l10n.clienteContactoDialogoBotonGuardar,
        cancelarLabel: l10n.clienteContactoDialogoBotonCancelar,
        errorMotivoRequerido: l10n.auditoriaErrorMotivoRequerido,
      );
      if (!mounted || motivo == null) return;
      resultado = await _notifier.actualizarContacto(contactoExistente.id, borrador, motivo: motivo);
    }

    if (!mounted) return;

    switch (resultado) {
      case GuardarContactoExitoso():
        RisegFeedback.showSuccess(context, l10n.clienteContactoGuardadoExito);
      case GuardarContactoErroresValidacion():
      case GuardarContactoMotivoRequerido():
      case GuardarContactoErrorInesperado():
        RisegFeedback.showError(context, l10n.clienteContactoGuardadoError);
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
    if (!mounted || confirmado != true) return;

    final motivoArchivo = await mostrarDialogoMotivo(
      context,
      titulo: l10n.clienteContactoMotivoArchivoTitulo,
      etiquetaMotivo: l10n.auditoriaCampoMotivo,
      confirmarLabel: l10n.sucursalConfirmarAceptar,
      cancelarLabel: l10n.sucursalConfirmarCancelar,
      errorMotivoRequerido: l10n.auditoriaErrorMotivoRequerido,
    );
    if (!mounted || motivoArchivo == null) return;

    final exito = await _notifier.archivarContacto(contacto.id, motivo: motivoArchivo);
    if (!mounted) return;
    if (exito) {
      RisegFeedback.showSuccess(context, l10n.clienteContactoArchivadoExito);
    } else {
      RisegFeedback.showError(context, l10n.clienteContactoGuardadoError);
    }
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
      // Marcar principal es un cambio de rol dentro del Cliente, no una
      // corrección de datos: el motivo lo pone la propia acción.
      motivo: l10n.clienteContactoMotivoPrincipal,
    );
    if (!mounted) return;
    if (resultado is GuardarContactoExitoso) {
      RisegFeedback.showSuccess(context, l10n.clienteContactoGuardadoExito);
    } else {
      RisegFeedback.showError(context, l10n.clienteContactoGuardadoError);
    }
  }

  Future<void> _mostrarDialogoEntidadFiscal({EntidadFiscalData? entidadExistente}) async {
    final l10n = AppLocalizations.of(context)!;
    var borrador = EntidadFiscalBorrador(
      razonSocial: entidadExistente?.razonSocial ?? '',
      rfc: entidadExistente?.rfc ?? '',
    );

    final confirmado = await RisegDialog.showForm<bool>(
      context: context,
      title: entidadExistente == null
          ? l10n.entidadFiscalDialogoTituloAlta
          : l10n.entidadFiscalDialogoTituloEdicion,
      confirmLabel: l10n.entidadFiscalDialogoBotonGuardar,
      cancelLabel: l10n.entidadFiscalDialogoBotonCancelar,
      contentBuilder: (_) => EntidadFiscalForm(
        entidadInicial: entidadExistente,
        onCambio: (nuevo) => borrador = nuevo,
      ),
      onConfirm: () async => true,
    );

    if (!mounted || confirmado != true) return;

    final GuardarEntidadFiscalResultado? resultado;
    if (entidadExistente == null) {
      // Un alta no lleva motivo: no hay nada que justificar todavía.
      resultado = await _notifier.agregarEntidadFiscal(borrador);
    } else {
      // Una corrección sí: RFC y razón social son datos fiscales.
      final motivo = await mostrarDialogoMotivo(
        context,
        titulo: l10n.entidadFiscalMotivoTitulo,
        etiquetaMotivo: l10n.auditoriaCampoMotivo,
        confirmarLabel: l10n.entidadFiscalDialogoBotonGuardar,
        cancelarLabel: l10n.entidadFiscalDialogoBotonCancelar,
        errorMotivoRequerido: l10n.auditoriaErrorMotivoRequerido,
      );
      if (!mounted || motivo == null) return;
      resultado = await _notifier.actualizarEntidadFiscal(entidadExistente.id, borrador, motivo: motivo);
    }
    if (!mounted) return;

    switch (resultado) {
      case GuardarEntidadFiscalExitoso():
        RisegFeedback.showSuccess(context, l10n.entidadFiscalGuardadoExito);
      case GuardarEntidadFiscalErroresValidacion():
      case GuardarEntidadFiscalErrorInesperado():
        RisegFeedback.showError(context, l10n.entidadFiscalGuardadoError);
      case GuardarEntidadFiscalArchivada():
        RisegFeedback.showError(context, l10n.entidadFiscalArchivadaNoEditable);
      case GuardarEntidadFiscalMotivoRequerido():
        RisegFeedback.showError(context, l10n.auditoriaErrorMotivoRequerido);
      case null:
        break;
    }
  }

  Future<void> _mostrarDialogoDomicilioFiscal(EntidadFiscalConDomicilio entidad) async {
    final l10n = AppLocalizations.of(context)!;
    final domicilio = entidad.domicilioFiscal;
    var capturado = DireccionBorrador(
      calle: domicilio?.calle ?? '',
      numeroExterior: domicilio?.numeroExterior ?? '',
      numeroInterior: domicilio?.numeroInterior ?? '',
      colonia: domicilio?.colonia ?? '',
      municipioAlcaldia: domicilio?.municipioAlcaldia ?? '',
      ciudadLocalidad: domicilio?.ciudadLocalidad ?? '',
      estado: domicilio?.estado ?? '',
      codigoPostal: domicilio?.codigoPostal ?? '',
      pais: domicilio?.pais ?? 'México',
      referencias: domicilio?.referencias ?? '',
    );

    final resultado = await RisegDialog.showForm<GuardarDomicilioFiscalResultado>(
      context: context,
      title: l10n.entidadFiscalDomicilioDialogoTitulo,
      confirmLabel: l10n.entidadFiscalDomicilioDialogoBotonGuardar,
      cancelLabel: l10n.entidadFiscalDomicilioDialogoBotonCancelar,
      contentBuilder: (_) => DomicilioFiscalForm(
        domicilioInicial: domicilio,
        onCambio: (nuevo) => capturado = nuevo,
      ),
      onConfirm: () {
        return _notifier.guardarDomicilioFiscal(entidad.entidadFiscal.id, capturado);
      },
    );

    if (!mounted) return;

    switch (resultado) {
      case GuardarDomicilioFiscalExitoso():
        RisegFeedback.showSuccess(context, l10n.entidadFiscalDomicilioGuardadoExito);
      case GuardarDomicilioFiscalErroresValidacion():
      case GuardarDomicilioFiscalErrorInesperado():
        RisegFeedback.showError(context, l10n.entidadFiscalDomicilioGuardadoError);
      case GuardarDomicilioFiscalArchivada():
        RisegFeedback.showError(context, l10n.entidadFiscalArchivadaNoEditable);
      case null:
        break;
    }
  }

  Future<void> _archivarEntidadFiscal(EntidadFiscalData entidad) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmado = await RisegDialog.showConfirmation(
      context: context,
      title: l10n.entidadFiscalConfirmarArchivarTitulo,
      message: l10n.entidadFiscalConfirmarArchivarMensaje,
      confirmLabel: l10n.sucursalConfirmarAceptar,
      cancelLabel: l10n.sucursalConfirmarCancelar,
      destructive: true,
    );
    if (!mounted || confirmado != true) return;

    final motivo = await mostrarDialogoMotivo(
      context,
      titulo: l10n.entidadFiscalConfirmarArchivarTitulo,
      etiquetaMotivo: l10n.auditoriaCampoMotivo,
      confirmarLabel: l10n.sucursalConfirmarAceptar,
      cancelarLabel: l10n.sucursalConfirmarCancelar,
      errorMotivoRequerido: l10n.auditoriaErrorMotivoRequerido,
    );
    if (!mounted || motivo == null) return;

    final exito = await _notifier.cambiarCicloVidaEntidadFiscal(
      entidad.id,
      CicloVidaRegistro.archivado,
      motivo: motivo,
    );
    if (!mounted) return;
    if (exito) {
      RisegFeedback.showSuccess(context, l10n.entidadFiscalCicloVidaCambiadoExito);
    } else {
      RisegFeedback.showError(context, l10n.entidadFiscalCicloVidaCambiadoError);
    }
  }

  Future<void> _reactivarEntidadFiscal(EntidadFiscalData entidad) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmado = await RisegDialog.showConfirmation(
      context: context,
      title: l10n.entidadFiscalConfirmarReactivarTitulo,
      message: l10n.entidadFiscalConfirmarReactivarMensaje,
      confirmLabel: l10n.sucursalConfirmarAceptar,
      cancelLabel: l10n.sucursalConfirmarCancelar,
    );
    if (!mounted || confirmado != true) return;

    final motivo = await mostrarDialogoMotivo(
      context,
      titulo: l10n.entidadFiscalConfirmarReactivarTitulo,
      etiquetaMotivo: l10n.auditoriaCampoMotivo,
      confirmarLabel: l10n.sucursalConfirmarAceptar,
      cancelarLabel: l10n.sucursalConfirmarCancelar,
      errorMotivoRequerido: l10n.auditoriaErrorMotivoRequerido,
    );
    if (!mounted || motivo == null) return;

    final exito = await _notifier.cambiarCicloVidaEntidadFiscal(
      entidad.id,
      CicloVidaRegistro.activo,
      motivo: motivo,
    );
    if (!mounted) return;
    if (exito) {
      RisegFeedback.showSuccess(context, l10n.entidadFiscalCicloVidaCambiadoExito);
    } else {
      RisegFeedback.showError(context, l10n.entidadFiscalCicloVidaCambiadoError);
    }
  }

  Future<void> _mostrarDialogoClientePortal({ClientePortalData? portalExistente}) async {
    final l10n = AppLocalizations.of(context)!;
    var borrador = ClientePortalBorrador(
      nombre: portalExistente?.nombre ?? '',
      tipo: portalExistente == null ? TipoPortalCliente.otro : TipoPortalCliente.values.byName(portalExistente.tipo),
      url: portalExistente?.url,
      usuario: portalExistente?.usuario,
      observaciones: portalExistente?.observaciones,
    );

    final confirmadoPortal = await RisegDialog.showForm<bool>(
      context: context,
      title: portalExistente == null ? l10n.clientePortalDialogoTituloAlta : l10n.clientePortalDialogoTituloEdicion,
      confirmLabel: l10n.clientePortalDialogoBotonGuardar,
      cancelLabel: l10n.clientePortalDialogoBotonCancelar,
      contentBuilder: (_) => ClientePortalForm(
        portalInicial: portalExistente,
        onCambio: (nuevo) => borrador = nuevo,
      ),
      onConfirm: () async => true,
    );

    if (!mounted || confirmadoPortal != true) return;

    final GuardarClientePortalResultado? resultado;
    if (portalExistente == null) {
      // Alta: sin motivo, no hay nada que justificar todavía.
      resultado = await _notifier.agregarClientePortal(borrador);
    } else {
      final motivo = await mostrarDialogoMotivo(
        context,
        titulo: l10n.clientePortalMotivoTitulo,
        etiquetaMotivo: l10n.auditoriaCampoMotivo,
        confirmarLabel: l10n.clientePortalDialogoBotonGuardar,
        cancelarLabel: l10n.clientePortalDialogoBotonCancelar,
        errorMotivoRequerido: l10n.auditoriaErrorMotivoRequerido,
      );
      if (!mounted || motivo == null) return;
      resultado = await _notifier.actualizarClientePortal(portalExistente.id, borrador, motivo: motivo);
    }

    if (!mounted) return;

    switch (resultado) {
      case GuardarClientePortalExitoso():
        RisegFeedback.showSuccess(context, l10n.clientePortalGuardadoExito);
      case GuardarClientePortalErroresValidacion():
      case GuardarClientePortalMotivoRequerido():
      case GuardarClientePortalErrorInesperado():
        RisegFeedback.showError(context, l10n.clientePortalGuardadoError);
      case GuardarClientePortalArchivado():
        RisegFeedback.showError(context, l10n.clientePortalArchivadaNoEditable);
      case null:
        break;
    }
  }

  Future<void> _archivarClientePortal(ClientePortalData portal) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmado = await RisegDialog.showConfirmation(
      context: context,
      title: l10n.clientePortalConfirmarArchivarTitulo,
      message: l10n.clientePortalConfirmarArchivarMensaje,
      confirmLabel: l10n.sucursalConfirmarAceptar,
      cancelLabel: l10n.sucursalConfirmarCancelar,
      destructive: true,
    );
    if (!mounted || confirmado != true) return;

    final motivoArchivoPortal = await mostrarDialogoMotivo(
      context,
      titulo: l10n.clientePortalConfirmarArchivarTitulo,
      etiquetaMotivo: l10n.auditoriaCampoMotivo,
      confirmarLabel: l10n.sucursalConfirmarAceptar,
      cancelarLabel: l10n.sucursalConfirmarCancelar,
      errorMotivoRequerido: l10n.auditoriaErrorMotivoRequerido,
    );
    if (!mounted || motivoArchivoPortal == null) return;

    final exito = await _notifier.cambiarCicloVidaClientePortal(
      portal.id,
      CicloVidaRegistro.archivado,
      motivo: motivoArchivoPortal,
    );
    if (!mounted) return;
    if (exito) {
      RisegFeedback.showSuccess(context, l10n.clientePortalCicloVidaCambiadoExito);
    } else {
      RisegFeedback.showError(context, l10n.clientePortalCicloVidaCambiadoError);
    }
  }

  Future<void> _reactivarClientePortal(ClientePortalData portal) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmado = await RisegDialog.showConfirmation(
      context: context,
      title: l10n.clientePortalConfirmarReactivarTitulo,
      message: l10n.clientePortalConfirmarReactivarMensaje,
      confirmLabel: l10n.sucursalConfirmarAceptar,
      cancelLabel: l10n.sucursalConfirmarCancelar,
    );
    if (!mounted || confirmado != true) return;

    final motivoReactivarPortal = await mostrarDialogoMotivo(
      context,
      titulo: l10n.clientePortalConfirmarReactivarTitulo,
      etiquetaMotivo: l10n.auditoriaCampoMotivo,
      confirmarLabel: l10n.sucursalConfirmarAceptar,
      cancelarLabel: l10n.sucursalConfirmarCancelar,
      errorMotivoRequerido: l10n.auditoriaErrorMotivoRequerido,
    );
    if (!mounted || motivoReactivarPortal == null) return;

    final exito = await _notifier.cambiarCicloVidaClientePortal(
      portal.id,
      CicloVidaRegistro.activo,
      motivo: motivoReactivarPortal,
    );
    if (!mounted) return;
    if (exito) {
      RisegFeedback.showSuccess(context, l10n.clientePortalCicloVidaCambiadoExito);
    } else {
      RisegFeedback.showError(context, l10n.clientePortalCicloVidaCambiadoError);
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
    final esMaestro = ref.watch(sesionControllerProvider)?.esMaestro ?? false;

    final entidadesActivas =
        datos.entidadesFiscales.where((e) => e.entidadFiscal.cicloVidaRegistro == CicloVidaRegistro.activo.name).toList();
    final razonSocialUnica = entidadesActivas.length == 1 ? entidadesActivas.first.entidadFiscal.razonSocial : null;
    final rfcUnico = entidadesActivas.length == 1 ? entidadesActivas.first.entidadFiscal.rfc : null;

    final resumenComercial = ref.watch(clienteComercialResumenProvider(widget.clienteId));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppBreakpoints.wide),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RisegSectionHeader(
                title: l10n.clienteExpedienteTitulo,
                primaryAction: esEdicion
                    ? RisegButton(
                        key: const Key('cliente_expediente_boton_guardar'),
                        label: l10n.clienteExpedienteBotonGuardar,
                        loading: state.guardando,
                        onPressed: _guardar,
                      )
                    : null,
                secondaryAction: esEdicion
                    ? RisegButton(
                        key: const Key('cliente_expediente_boton_cancelar'),
                        label: l10n.clienteExpedienteBotonCancelar,
                        variant: RisegButtonVariant.ghost,
                        onPressed: state.guardando ? null : () => _cancelar(state.tieneCambiosSinGuardar),
                      )
                    : null,
              ),
              const SizedBox(height: AppSpacing.md),
              _seccionFicha(
                context,
                l10n,
                cliente,
                RisegStatusBadge(label: _nombreEstatus(l10n, estatusActual), tone: _tonoEstatus(estatusActual)),
                razonSocialUnica,
                rfcUnico,
                esEdicion,
                esMaestro,
                estatusActual,
                state.cambiandoEstatus,
              ),
              const SizedBox(height: AppSpacing.lg),
              resumenComercial.when(
                data: (resumen) => ClienteIndicadoresComerciales(resumen: resumen),
                loading: () => const SizedBox(
                  height: 72,
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                ),
                error: (_, _) => const SizedBox.shrink(),
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
              const SizedBox(height: AppSpacing.xl),
              RisegCard(
                child: EntidadesFiscalesSection(
                  entidades: datos.entidadesFiscales,
                  deshabilitado: state.operandoEntidadFiscal,
                  onAgregar: () => _mostrarDialogoEntidadFiscal(),
                  onEditar: (entidad) => _mostrarDialogoEntidadFiscal(entidadExistente: entidad),
                  onEditarDomicilio: _mostrarDialogoDomicilioFiscal,
                  onArchivar: _archivarEntidadFiscal,
                  onReactivar: _reactivarEntidadFiscal,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              RisegCard(
                child: resumenComercial.when(
                  data: (resumen) => ClienteServiciosSection(servicios: resumen.servicios),
                  loading: () => const Padding(
                    padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                    child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
                  error: (_, _) => const ClienteServiciosSection(servicios: []),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              RisegCard(
                child: _DatosCobranzaSection(
                  clienteId: cliente.id,
                  contactos: datos.contactos,
                  portales: datos.portales,
                  deshabilitado: state.operandoClientePortal,
                  onAgregarPortal: () => _mostrarDialogoClientePortal(),
                  onEditarPortal: (portal) => _mostrarDialogoClientePortal(portalExistente: portal),
                  onArchivarPortal: _archivarClientePortal,
                  onReactivarPortal: _reactivarClientePortal,
                  documentosPendientes: resumenComercial.whenOrNull(data: (r) => r.documentosPendientes),
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

/// Sección "Datos de cobranza / Facturación" del expediente de Cliente
/// (Etapa 15) — reúne lo que antes se capturaba repetido en cada
/// Configuración de cobro de cada Servicio: los correos de contacto ya
/// registrados (solo lectura aquí; se editan desde la sección
/// Contactos, arriba, para no duplicar esa gestión) y los portales del
/// Cliente (CRUD completo, mismo patrón que `EntidadesFiscalesSection`).
class _DatosCobranzaSection extends StatelessWidget {
  const _DatosCobranzaSection({
    required this.clienteId,
    required this.contactos,
    required this.portales,
    required this.deshabilitado,
    required this.onAgregarPortal,
    required this.onEditarPortal,
    required this.onArchivarPortal,
    required this.onReactivarPortal,
    this.documentosPendientes,
  });

  final String clienteId;
  final List<ContactoData> contactos;
  final List<ClientePortalData> portales;
  final bool deshabilitado;
  final VoidCallback onAgregarPortal;
  final ValueChanged<ClientePortalData> onEditarPortal;
  final ValueChanged<ClientePortalData> onArchivarPortal;
  final ValueChanged<ClientePortalData> onReactivarPortal;

  /// Documentos por emitir de ESTE Cliente aún no resueltos
  /// (`DocumentoPorEmitir.clienteId`) — `null` mientras
  /// `clienteComercialResumenProvider` sigue cargando o falló; en ese
  /// caso, se omite el renglón por completo (nunca un `0` engañoso).
  final int? documentosPendientes;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;
    final contactosConCorreo = contactos.where((c) => c.correo != null && c.correo!.isNotEmpty).toList();

    return RisegFormSection(
      title: l10n.clienteCobranzaSeccionTitulo,
      children: [
        Text(l10n.clienteCobranzaCorreosSubtitulo, style: AppTypography.label.copyWith(color: colors.textMuted)),
        const SizedBox(height: AppSpacing.xs),
        if (contactosConCorreo.isEmpty)
          Text(l10n.clienteCobranzaSinCorreos, style: AppTypography.caption.copyWith(color: colors.textMuted))
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final contacto in contactosConCorreo)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
                  child: Text(
                    contacto.puesto == null || contacto.puesto!.isEmpty
                        ? '${contacto.nombre} — ${contacto.correo}'
                        : '${contacto.nombre} (${contacto.puesto}) — ${contacto.correo}',
                    style: AppTypography.body.copyWith(color: colors.textPrimary),
                  ),
                ),
            ],
          ),
        const SizedBox(height: AppSpacing.lg),
        ClientePortalesSection(
          portales: portales,
          deshabilitado: deshabilitado,
          onAgregar: onAgregarPortal,
          onEditar: onEditarPortal,
          onArchivar: onArchivarPortal,
          onReactivar: onReactivarPortal,
        ),
        if (documentosPendientes != null) ...[
          const SizedBox(height: AppSpacing.lg),
          Text(l10n.clienteCobranzaDocumentosSubtitulo, style: AppTypography.label.copyWith(color: colors.textMuted)),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.clienteCobranzaDocumentosPendientesCantidad(documentosPendientes!),
                  style: AppTypography.body.copyWith(color: colors.textPrimary),
                ),
              ),
              RisegButton(
                key: const Key('cliente_boton_ver_agenda'),
                label: l10n.clienteCobranzaBotonVerAgenda,
                variant: RisegButtonVariant.ghost,
                size: RisegButtonSize.compact,
                onPressed: () => context.push('/comercial/agenda'),
              ),
            ],
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        Text(l10n.clienteCobranzaFinanzasSubtitulo, style: AppTypography.label.copyWith(color: colors.textMuted)),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          children: [
            RisegButton(
              key: const Key('cliente_boton_ver_cuentas_por_cobrar'),
              label: l10n.clienteCobranzaBotonVerCuentasPorCobrar,
              variant: RisegButtonVariant.ghost,
              size: RisegButtonSize.compact,
              onPressed: () => context.push('/finanzas/cuentas-por-cobrar?clienteId=$clienteId'),
            ),
            RisegButton(
              key: const Key('cliente_boton_ver_pagos'),
              label: l10n.clienteCobranzaBotonVerPagos,
              variant: RisegButtonVariant.ghost,
              size: RisegButtonSize.compact,
              onPressed: () => context.push('/finanzas/pagos?clienteId=$clienteId'),
            ),
          ],
        ),
      ],
    );
  }
}
