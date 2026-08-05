import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/tables/audit_columns.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/core/validation/direccion_validator.dart';
import 'package:riseg_one/features/organizacion/data/tables/servicio_table.dart';
import 'package:riseg_one/features/organizacion/domain/repositories/catalogo_repository.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/asignar_entidad_fiscal_a_servicio_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/asignar_responsable_cliente_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/asignar_sucursal_administrativa_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/cambiar_estatus_servicio_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_linea_comercial_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_direccion_operativa_servicio_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/linea_comercial_validator.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/servicio_errors.dart';

import '../../organizacion_providers.dart';
import 'servicio_expediente_controller.dart';
import 'servicio_expediente_form_controllers.dart';
import 'servicio_expediente_state.dart';
import 'widgets/servicio_auditoria_section.dart';
import 'widgets/servicio_configuracion_comercial_section.dart';
import 'widgets/servicio_datos_generales_section.dart';
import 'widgets/servicio_direccion_operativa_section.dart';
import 'widgets/servicio_referencias_section.dart';
import 'widgets/servicio_vinculaciones_section.dart';

final _formatoFecha = DateFormat('dd/MM/yyyy');

/// Pantalla de expediente de Servicio — mismo patrón consulta/edición
/// que Cliente/Puesto/Sucursal; se apila (`push`) sobre el listado.
/// Desde la Etapa 4F.2 administra el expediente completo: Datos
/// generales + Referencias (un solo ciclo de Editar/Guardar), Dirección
/// operativa, Vinculaciones (Entidad fiscal/Responsable del Cliente/
/// Responsable interno/Sucursal administrativa) y Auditoría — cada
/// sección vive en su propio widget (`widgets/servicio_*_section.dart`)
/// para que el expediente pueda seguir creciendo (Configuración
/// comercial, Coberturas, Documentos, etc.) sin reestructurar lo ya
/// construido.
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

  Future<void> _asignarEntidadFiscal() async {
    final l10n = AppLocalizations.of(context)!;
    final datos = ref.read(servicioExpedienteControllerProvider(widget.servicioId)).datos!;

    final entidades = (await ref.read(entidadFiscalRepositoryProvider).listarPorCliente(datos.cliente.id))
        .where((e) => e.entidadFiscal.cicloVidaRegistro == CicloVidaRegistro.activo.name)
        .toList();
    if (!mounted) return;

    var seleccionId = datos.entidadFiscal?.id;
    final resultado = await RisegDialog.showForm<AsignarEntidadFiscalAServicioResultado?>(
      context: context,
      title: l10n.servicioAsignarEntidadFiscalTitulo,
      confirmLabel: l10n.servicioVinculacionDialogoBotonGuardar,
      cancelLabel: l10n.servicioVinculacionDialogoBotonCancelar,
      contentBuilder: (_) => _SelectorForm(
        label: l10n.servicioVinculacionEntidadFiscal,
        valorInicial: seleccionId,
        items: [for (final e in entidades) RisegSelectItem(value: e.entidadFiscal.id, label: e.entidadFiscal.razonSocial)],
        onCambio: (valor) => seleccionId = valor,
      ),
      onConfirm: () => _notifier.asignarEntidadFiscal(seleccionId),
    );

    if (!mounted) return;
    switch (resultado) {
      case AsignarEntidadFiscalAServicioExitoso():
        RisegFeedback.showSuccess(context, l10n.servicioAsignarEntidadFiscalExito);
      case AsignarEntidadFiscalAServicioNoPerteneceAlCliente():
        RisegFeedback.showError(context, l10n.servicioAsignarEntidadFiscalErrorNoPertenece);
      case AsignarEntidadFiscalAServicioNoDisponible():
        RisegFeedback.showError(context, l10n.servicioAsignarEntidadFiscalErrorNoDisponible);
      case AsignarEntidadFiscalAServicioErrorInesperado():
        RisegFeedback.showError(context, l10n.servicioAsignarEntidadFiscalErrorInesperado);
      case null:
        break;
    }
  }

  Future<void> _quitarEntidadFiscal() async {
    final l10n = AppLocalizations.of(context)!;
    final resultado = await _notifier.asignarEntidadFiscal(null);
    if (!mounted) return;
    if (resultado is AsignarEntidadFiscalAServicioExitoso) {
      RisegFeedback.showSuccess(context, l10n.servicioQuitarEntidadFiscalExito);
    } else {
      RisegFeedback.showError(context, l10n.servicioAsignarEntidadFiscalErrorInesperado);
    }
  }

  Future<void> _asignarResponsableCliente() async {
    final l10n = AppLocalizations.of(context)!;
    final datos = ref.read(servicioExpedienteControllerProvider(widget.servicioId)).datos!;

    final contactos = await ref.read(clienteRepositoryProvider).obtenerContactos(datos.cliente.id);
    if (!mounted) return;

    var seleccionId = datos.responsableCliente?.id;
    final resultado = await RisegDialog.showForm<AsignarResponsableClienteResultado?>(
      context: context,
      title: l10n.servicioAsignarResponsableClienteTitulo,
      confirmLabel: l10n.servicioVinculacionDialogoBotonGuardar,
      cancelLabel: l10n.servicioVinculacionDialogoBotonCancelar,
      contentBuilder: (_) => _SelectorForm(
        label: l10n.servicioVinculacionResponsableCliente,
        valorInicial: seleccionId,
        items: [for (final c in contactos) RisegSelectItem(value: c.id, label: c.nombre)],
        onCambio: (valor) => seleccionId = valor,
      ),
      onConfirm: () => _notifier.asignarResponsableCliente(seleccionId),
    );

    if (!mounted) return;
    switch (resultado) {
      case AsignarResponsableClienteExitoso():
        RisegFeedback.showSuccess(context, l10n.servicioAsignarResponsableClienteExito);
      case AsignarResponsableClienteNoPerteneceAlCliente():
        RisegFeedback.showError(context, l10n.servicioAsignarResponsableClienteErrorNoPertenece);
      case AsignarResponsableClienteNoDisponible():
        RisegFeedback.showError(context, l10n.servicioAsignarResponsableClienteErrorNoDisponible);
      case AsignarResponsableClienteErrorInesperado():
        RisegFeedback.showError(context, l10n.servicioAsignarResponsableClienteErrorInesperado);
      case null:
        break;
    }
  }

  Future<void> _quitarResponsableCliente() async {
    final l10n = AppLocalizations.of(context)!;
    final resultado = await _notifier.asignarResponsableCliente(null);
    if (!mounted) return;
    if (resultado is AsignarResponsableClienteExitoso) {
      RisegFeedback.showSuccess(context, l10n.servicioQuitarResponsableClienteExito);
    } else {
      RisegFeedback.showError(context, l10n.servicioAsignarResponsableClienteErrorInesperado);
    }
  }

  Future<void> _asignarSucursalAdministrativa() async {
    final l10n = AppLocalizations.of(context)!;
    final datos = ref.read(servicioExpedienteControllerProvider(widget.servicioId)).datos!;

    final sucursales = await ref.read(sucursalRepositoryProvider).listarActivas();
    if (!mounted) return;

    var seleccionId = datos.sucursalAdministrativa?.id;
    final resultado = await RisegDialog.showForm<AsignarSucursalAdministrativaResultado?>(
      context: context,
      title: l10n.servicioAsignarSucursalAdministrativaTitulo,
      confirmLabel: l10n.servicioVinculacionDialogoBotonGuardar,
      cancelLabel: l10n.servicioVinculacionDialogoBotonCancelar,
      contentBuilder: (_) => _SelectorForm(
        label: l10n.servicioVinculacionSucursalAdministrativa,
        valorInicial: seleccionId,
        items: [for (final s in sucursales) RisegSelectItem(value: s.id, label: s.nombre)],
        onCambio: (valor) => seleccionId = valor,
      ),
      onConfirm: () => _notifier.asignarSucursalAdministrativa(seleccionId),
    );

    if (!mounted) return;
    switch (resultado) {
      case AsignarSucursalAdministrativaExitoso():
        RisegFeedback.showSuccess(context, l10n.servicioAsignarSucursalAdministrativaExito);
      case AsignarSucursalAdministrativaNoExiste():
        RisegFeedback.showError(context, l10n.servicioAsignarSucursalAdministrativaErrorNoExiste);
      case AsignarSucursalAdministrativaNoDisponible():
        RisegFeedback.showError(context, l10n.servicioAsignarSucursalAdministrativaErrorNoDisponible);
      case AsignarSucursalAdministrativaErrorInesperado():
        RisegFeedback.showError(context, l10n.servicioAsignarSucursalAdministrativaErrorInesperado);
      case null:
        break;
    }
  }

  Future<void> _quitarSucursalAdministrativa() async {
    final l10n = AppLocalizations.of(context)!;
    final resultado = await _notifier.asignarSucursalAdministrativa(null);
    if (!mounted) return;
    if (resultado is AsignarSucursalAdministrativaExitoso) {
      RisegFeedback.showSuccess(context, l10n.servicioQuitarSucursalAdministrativaExito);
    } else {
      RisegFeedback.showError(context, l10n.servicioAsignarSucursalAdministrativaErrorInesperado);
    }
  }

  Future<void> _editarResponsableInterno() async {
    final l10n = AppLocalizations.of(context)!;
    final datos = ref.read(servicioExpedienteControllerProvider(widget.servicioId)).datos!;

    var texto = datos.servicio.responsableInterno ?? '';
    final confirmado = await RisegDialog.showForm<bool>(
      context: context,
      title: l10n.servicioResponsableInternoDialogoTitulo,
      confirmLabel: l10n.servicioVinculacionDialogoBotonGuardar,
      cancelLabel: l10n.servicioVinculacionDialogoBotonCancelar,
      contentBuilder: (_) => _ResponsableInternoForm(
        valorInicial: texto,
        onCambio: (valor) => texto = valor,
      ),
      onConfirm: () => _notifier.guardarResponsableInterno(texto),
    );

    if (!mounted) return;
    if (confirmado == true) {
      RisegFeedback.showSuccess(context, l10n.servicioResponsableInternoGuardadoExito);
    } else if (confirmado == false) {
      RisegFeedback.showError(context, l10n.servicioResponsableInternoGuardadoError);
    }
  }

  Future<void> _editarDireccionOperativa(DireccionData? direccionActual) async {
    final l10n = AppLocalizations.of(context)!;

    var borrador = DireccionBorrador(
      calle: direccionActual?.calle ?? '',
      numeroExterior: direccionActual?.numeroExterior ?? '',
      numeroInterior: direccionActual?.numeroInterior,
      colonia: direccionActual?.colonia ?? '',
      municipioAlcaldia: direccionActual?.municipioAlcaldia ?? '',
      ciudadLocalidad: direccionActual?.ciudadLocalidad,
      estado: direccionActual?.estado ?? '',
      codigoPostal: direccionActual?.codigoPostal ?? '',
      pais: direccionActual?.pais ?? 'México',
      referencias: direccionActual?.referencias,
    );

    final resultado = await RisegDialog.showForm<GuardarDireccionOperativaServicioResultado?>(
      context: context,
      title: l10n.servicioDireccionOperativaDialogoTitulo,
      confirmLabel: l10n.servicioVinculacionDialogoBotonGuardar,
      cancelLabel: l10n.servicioVinculacionDialogoBotonCancelar,
      contentBuilder: (_) => ServicioDireccionOperativaForm(
        direccionInicial: direccionActual,
        onCambio: (nuevo) => borrador = nuevo,
      ),
      onConfirm: () => _notifier.guardarDireccionOperativa(borrador),
    );

    if (!mounted) return;
    switch (resultado) {
      case GuardarDireccionOperativaServicioExitoso():
        RisegFeedback.showSuccess(context, l10n.servicioDireccionOperativaGuardadoExito);
      case GuardarDireccionOperativaServicioErroresValidacion():
      case GuardarDireccionOperativaServicioErrorInesperado():
        RisegFeedback.showError(context, l10n.servicioDireccionOperativaGuardadoError);
      case null:
        break;
    }
  }

  Future<void> _agregarLineaComercial() async {
    final l10n = AppLocalizations.of(context)!;

    final puestos = await ref.read(puestoRepositoryProvider).listarActivos();
    final modalidades = await ref.read(catalogoRepositoryProvider).listarModalidadesTurno();
    if (!mounted) return;

    var borrador = const LineaComercialBorrador(
      puestoId: '',
      modalidadTurnoId: '',
      cantidadElementos: null,
      precioUnitario: null,
      tratamientoIva: null,
      fechaInicioVigencia: null,
    );

    final resultado = await RisegDialog.showForm<CrearLineaComercialResultado?>(
      context: context,
      title: l10n.servicioComercialDialogoAltaTitulo,
      confirmLabel: l10n.servicioVinculacionDialogoBotonGuardar,
      cancelLabel: l10n.servicioVinculacionDialogoBotonCancelar,
      contentBuilder: (_) => ServicioLineaComercialForm(
        puestos: puestos,
        modalidadesTurno: modalidades,
        onCambio: (nuevo) => borrador = nuevo,
      ),
      onConfirm: () => _notifier.agregarLineaComercial(borrador),
    );

    if (!mounted) return;
    switch (resultado) {
      case CrearLineaComercialExitoso():
        RisegFeedback.showSuccess(context, l10n.servicioComercialGuardadoExito);
      case CrearLineaComercialErroresValidacion():
        RisegFeedback.showError(context, l10n.servicioComercialErrorValidacion);
      case CrearLineaComercialServicioNoDisponible():
        RisegFeedback.showError(context, l10n.servicioComercialErrorServicioNoDisponible);
      case CrearLineaComercialErrorInesperado():
        RisegFeedback.showError(context, l10n.servicioComercialErrorInesperado);
      case null:
        break;
    }
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
              const SizedBox(height: AppSpacing.xl),
              RisegCard(
                child: ServicioReferenciasSection(
                  modo: state.modo,
                  servicio: servicio,
                  controllers: _datosGenerales,
                  habilitado: habilitado,
                  onCampoModificado: _notifier.marcarCambiosSinGuardar,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              RisegCard(
                child: ServicioDireccionOperativaSection(
                  direccion: datos.direccionOperativa,
                  deshabilitado: state.operandoRelacion,
                  onEditar: () => _editarDireccionOperativa(datos.direccionOperativa),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              RisegCard(
                child: ServicioVinculacionesSection(
                  datos: datos,
                  deshabilitado: state.operandoRelacion,
                  onAsignarEntidadFiscal: _asignarEntidadFiscal,
                  onQuitarEntidadFiscal: _quitarEntidadFiscal,
                  onAsignarResponsableCliente: _asignarResponsableCliente,
                  onQuitarResponsableCliente: _quitarResponsableCliente,
                  onEditarResponsableInterno: _editarResponsableInterno,
                  onAsignarSucursalAdministrativa: _asignarSucursalAdministrativa,
                  onQuitarSucursalAdministrativa: _quitarSucursalAdministrativa,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              RisegCard(
                child: ServicioConfiguracionComercialSection(
                  lineas: datos.lineasComerciales,
                  subtotalComercial: datos.subtotalComercial,
                  ivaVariaPorLinea: datos.ivaVariaPorLinea,
                  deshabilitado: state.operandoComercial,
                  onAgregarLinea: _agregarLineaComercial,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              RisegCard(child: ServicioAuditoriaSection(servicio: servicio)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Selector genérico de un `String` (id) — reutilizado por los 3
/// diálogos de asignación de vinculación (Entidad fiscal, Responsable
/// del Cliente, Sucursal administrativa). `StatefulWidget` propio para
/// que el diálogo se redibuje con la selección (mismo motivo que
/// `_CambiarEstatusForm` en Cliente).
class _SelectorForm extends StatefulWidget {
  const _SelectorForm({
    required this.label,
    required this.items,
    required this.onCambio,
    this.valorInicial,
  });

  final String label;
  final List<RisegSelectItem<String>> items;
  final String? valorInicial;
  final ValueChanged<String?> onCambio;

  @override
  State<_SelectorForm> createState() => _SelectorFormState();
}

class _SelectorFormState extends State<_SelectorForm> {
  late String? _valor = widget.valorInicial;

  @override
  Widget build(BuildContext context) {
    return RisegSelect<String>(
      label: widget.label,
      value: _valor,
      items: widget.items,
      onChanged: (valor) {
        setState(() => _valor = valor);
        widget.onCambio(valor);
      },
    );
  }
}

/// Contenido del diálogo de "Responsable interno" — texto libre
/// transitorio (ver `Servicio.responsableInterno`).
class _ResponsableInternoForm extends StatefulWidget {
  const _ResponsableInternoForm({required this.valorInicial, required this.onCambio});

  final String valorInicial;
  final ValueChanged<String> onCambio;

  @override
  State<_ResponsableInternoForm> createState() => _ResponsableInternoFormState();
}

class _ResponsableInternoFormState extends State<_ResponsableInternoForm> {
  late final _controller = TextEditingController(text: widget.valorInicial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RisegTextField(
          label: l10n.servicioResponsableInternoCampoTexto,
          controller: _controller,
          autofocus: true,
          helperText: l10n.servicioResponsableInternoAyuda,
          onChanged: (valor) => widget.onCambio(valor),
        ),
      ],
    );
  }
}
