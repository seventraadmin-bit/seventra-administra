import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/tables/audit_columns.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/core/validation/direccion_validator.dart';
import 'package:riseg_one/features/dashboard/presentation/dashboard_controller.dart';
import 'package:riseg_one/features/organizacion/data/tables/configuracion_cobro_vigencia_table.dart';
import 'package:riseg_one/features/organizacion/data/tables/servicio_linea_comercial_vigencia_table.dart';
import 'package:riseg_one/features/organizacion/data/tables/servicio_table.dart';
import 'package:riseg_one/features/organizacion/domain/repositories/catalogo_repository.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/actualizar_observaciones_configuracion_cobro_vigencia_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/asignar_entidad_fiscal_a_servicio_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/asignar_responsable_cliente_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/actualizar_anotaciones_vigencia_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/asignar_sucursal_administrativa_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/cambiar_estatus_servicio_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/cambiar_vigencia_configuracion_cobro_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/cambiar_vigencia_linea_comercial_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/cancelar_vigencia_programada_configuracion_cobro_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/cancelar_vigencia_programada_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/cerrar_configuracion_cobro_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/cerrar_linea_comercial_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/configuracion_cobro_errors.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/configuracion_cobro_etapa_validator.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/configuracion_cobro_validator.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/corregir_configuracion_cobro_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/corregir_linea_comercial_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_configuracion_cobro_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_linea_comercial_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_direccion_operativa_servicio_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/linea_comercial_con_vigencia.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/linea_comercial_validator.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/obtener_historial_configuracion_cobro_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/obtener_historial_linea_comercial_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/servicio_errors.dart';
import 'package:riseg_one/features/inventario/presentation/asignaciones/widgets/inventario_asignado_servicio_section.dart';
import 'package:riseg_one/features/telefonia/presentation/widgets/linea_telefonica_asignada_servicio_section.dart';
import 'package:riseg_one/features/vehiculos/presentation/widgets/vehiculo_asignado_servicio_section.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';
import 'package:riseg_one/features/usuarios/usuarios_providers.dart';

import '../../organizacion_providers.dart';
import 'servicio_expediente_controller.dart';
import 'servicio_expediente_form_controllers.dart';
import 'servicio_expediente_state.dart';
import 'widgets/servicio_auditoria_section.dart';
import 'widgets/servicio_configuracion_comercial_section.dart';
import 'widgets/decision_cierre_nueva_vigencia_cobro.dart';
import 'widgets/servicio_configuracion_cobro_section.dart';
import 'widgets/servicio_personal_asignado_section.dart';
import 'widgets/servicio_datos_generales_section.dart';
import 'widgets/servicio_direccion_operativa_section.dart';
import 'widgets/servicio_ficha_header.dart';
import 'widgets/servicio_indicadores_operacionales.dart';
import 'widgets/eliminar_linea_comercial_fisicamente_dialog.dart';
import 'widgets/eliminar_servicio_fisicamente_dialog.dart';
import 'widgets/servicio_historial_configuracion_cobro_dialog.dart';
import 'widgets/servicio_historial_linea_comercial_dialog.dart';
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

  /// Logo del Cliente dueño + catálogo de Modalidades de turno (Etapa
  /// 16, ficha operacional) — un único detalle por Servicio (no una
  /// lista de muchas filas) más una tabla de referencia pequeña que no
  /// escala con datos, así que combinarlas aquí no es el mismo riesgo
  /// de N+1 que en un listado.
  Future<({AttachmentData? logo, List<CatalogoItem> turnos})> _cargarDatosFicha(ClienteData cliente) async {
    final resultados = await Future.wait([
      cliente.logoAttachmentId == null
          ? Future.value(null)
          : ref.read(attachmentRepositoryProvider).obtenerPorId(cliente.logoAttachmentId!),
      ref.read(catalogoRepositoryProvider).listarModalidadesTurno(),
    ]);
    return (logo: resultados[0] as AttachmentData?, turnos: resultados[1] as List<CatalogoItem>);
  }

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
    final motivo = await mostrarDialogoMotivo(
      context,
      titulo: l10n.servicioGuardarMotivoTitulo,
      etiquetaMotivo: l10n.auditoriaCampoMotivo,
      confirmarLabel: l10n.servicioTerminarBotonConfirmar,
      cancelarLabel: l10n.servicioTerminarBotonCancelar,
      errorMotivoRequerido: l10n.auditoriaErrorMotivoRequerido,
    );
    if (!mounted || motivo == null) return;

    final exito = await _notifier.guardar(_datosGenerales.capturar(), motivo: motivo);
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

  /// Pide el motivo de un cambio de estatus y lo aplica.
  ///
  /// Suspender, reactivar o terminar un Servicio afecta a la cobranza:
  /// el motivo es obligatorio y viaja a la bitácora. Un solo punto,
  /// para que las tres acciones no lo pidan de tres formas distintas.
  Future<void> _cambiarEstatusConMotivo(
    EstatusServicio nuevo, {
    DateTime? fechaTerminoEfectiva,
    required String titulo,
    required String confirmarLabel,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final motivo = await mostrarDialogoMotivo(
      context,
      titulo: titulo,
      etiquetaMotivo: l10n.auditoriaCampoMotivo,
      confirmarLabel: confirmarLabel,
      cancelarLabel: l10n.servicioTerminarBotonCancelar,
      errorMotivoRequerido: l10n.auditoriaErrorMotivoRequerido,
    );
    if (!mounted || motivo == null) return;

    final resultado = await _notifier.cambiarEstatus(
      nuevo,
      fechaTerminoEfectiva: fechaTerminoEfectiva,
      motivo: motivo,
    );
    if (!mounted) return;
    _mostrarResultadoCambioEstatus(resultado);
  }

  void _mostrarResultadoCambioEstatus(CambiarEstatusServicioResultado? resultado) {
    final l10n = AppLocalizations.of(context)!;
    switch (resultado) {
      case CambiarEstatusServicioExitoso():
        RisegFeedback.showSuccess(context, l10n.servicioCambiarEstatusExito);
        // Un Servicio activo/suspendido/terminado entra o sale del
        // conjunto que cuenta para Cobertura operativa/Servicios
        // activos del Dashboard (Etapa 15, rediseño gerencial).
        ref.invalidate(dashboardControllerProvider);
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
      case CambiarEstatusServicioMotivoRequerido():
        RisegFeedback.showError(context, l10n.auditoriaErrorMotivoRequerido);
      case CambiarEstatusServicioErrorInesperado():
        RisegFeedback.showError(context, l10n.servicioCambiarEstatusErrorInesperado);
      case null:
        break;
    }
  }

  Future<void> _eliminarFisicamente() async {
    final eliminado = await mostrarDialogoEliminarServicioFisicamente(context, ref, widget.servicioId);
    if (eliminado) {
      ref.invalidate(dashboardControllerProvider);
      if (mounted) context.pop();
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

    await _cambiarEstatusConMotivo(
      EstatusServicio.activo,
      titulo: esReactivar ? l10n.servicioConfirmarReactivarTitulo : l10n.servicioBotonActivar,
      confirmarLabel: esReactivar ? l10n.servicioBotonReactivar : l10n.servicioBotonActivar,
    );
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

    await _cambiarEstatusConMotivo(
      EstatusServicio.suspendido,
      titulo: l10n.servicioConfirmarSuspenderTitulo,
      confirmarLabel: l10n.servicioBotonSuspender,
    );
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

      await _cambiarEstatusConMotivo(
        EstatusServicio.terminado,
        titulo: l10n.servicioTerminarDialogoTitulo,
        confirmarLabel: l10n.servicioTerminarBotonConfirmar,
      );
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

    await _cambiarEstatusConMotivo(
      EstatusServicio.terminado,
      fechaTerminoEfectiva: fechaEfectiva,
      titulo: l10n.servicioTerminarDialogoTitulo,
      confirmarLabel: l10n.servicioTerminarBotonConfirmar,
    );
  }

  Future<void> _asignarEntidadFiscal() async {
    final l10n = AppLocalizations.of(context)!;
    final datos = ref.read(servicioExpedienteControllerProvider(widget.servicioId)).datos!;

    final entidades = (await ref.read(entidadFiscalRepositoryProvider).listarPorCliente(datos.cliente.id))
        .where((e) => e.entidadFiscal.cicloVidaRegistro == CicloVidaRegistro.activo.name)
        .toList();
    if (!mounted) return;

    final entidadAnterior = datos.entidadFiscal?.id;
    var seleccionId = entidadAnterior;
    final confirmadoEntidadFiscal = await RisegDialog.showForm<bool>(
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
      onConfirm: () async => true,
    );

    if (!mounted || confirmadoEntidadFiscal != true) return;

    // Sustituir la Entidad fiscal vigente mueve a quién se le factura:
    // ahí sí se pide motivo. La primera asignación, no.
    String? motivoEntidadFiscal;
    if (exigeMotivoAsignacionEntidadFiscal(anterior: entidadAnterior, nueva: seleccionId)) {
      motivoEntidadFiscal = await mostrarDialogoMotivo(
        context,
        titulo: l10n.servicioEntidadFiscalMotivoCambioTitulo,
        etiquetaMotivo: l10n.auditoriaCampoMotivo,
        confirmarLabel: l10n.servicioVinculacionDialogoBotonGuardar,
        cancelarLabel: l10n.servicioVinculacionDialogoBotonCancelar,
        errorMotivoRequerido: l10n.auditoriaErrorMotivoRequerido,
      );
      if (!mounted || motivoEntidadFiscal == null) return;
    }

    final resultado = await _notifier.asignarEntidadFiscal(seleccionId, motivo: motivoEntidadFiscal);

    if (!mounted) return;
    switch (resultado) {
      case AsignarEntidadFiscalAServicioExitoso():
        RisegFeedback.showSuccess(context, l10n.servicioAsignarEntidadFiscalExito);
      case AsignarEntidadFiscalAServicioMotivoRequerido():
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

    // Retirar la Entidad fiscal deja al Servicio sin a quién facturarle:
    // exige motivo, igual que sustituirla.
    final motivoRetiro = await mostrarDialogoMotivo(
      context,
      titulo: l10n.servicioEntidadFiscalMotivoRetiroTitulo,
      etiquetaMotivo: l10n.auditoriaCampoMotivo,
      confirmarLabel: l10n.servicioVinculacionDialogoBotonGuardar,
      cancelarLabel: l10n.servicioVinculacionDialogoBotonCancelar,
      errorMotivoRequerido: l10n.auditoriaErrorMotivoRequerido,
    );
    if (!mounted || motivoRetiro == null) return;

    final resultado = await _notifier.asignarEntidadFiscal(null, motivo: motivoRetiro);
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
      onConfirm: () {
        return _notifier.asignarResponsableCliente(seleccionId);
      },
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
      onConfirm: () {
        return _notifier.asignarSucursalAdministrativa(seleccionId);
      },
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
      onConfirm: () {
        return _notifier.guardarResponsableInterno(texto);
      },
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
      onConfirm: () {
        return _notifier.guardarDireccionOperativa(borrador);
      },
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
      onConfirm: () {
        return _notifier.agregarLineaComercial(borrador);
      },
    );

    if (!mounted) return;
    switch (resultado) {
      case CrearLineaComercialExitoso():
        RisegFeedback.showSuccess(context, l10n.servicioComercialGuardadoExito);
        // La cantidad requerida por línea alimenta directamente
        // Cobertura operativa del Dashboard (Etapa 15).
        ref.invalidate(dashboardControllerProvider);
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

  Future<void> _agregarConfiguracionCobro() async {
    final l10n = AppLocalizations.of(context)!;
    final datos = ref.read(servicioExpedienteControllerProvider(widget.servicioId)).datos!;

    final frecuencias = await ref.read(catalogoRepositoryProvider).listarFrecuenciasCobro();
    final entidades = (await ref.read(entidadFiscalRepositoryProvider).listarPorCliente(datos.cliente.id))
        .where((e) => e.entidadFiscal.cicloVidaRegistro == CicloVidaRegistro.activo.name)
        .map((e) => e.entidadFiscal)
        .toList();
    final contactos = await ref.read(clienteRepositoryProvider).obtenerContactos(datos.cliente.id);
    final portales = await ref.read(clientePortalRepositoryProvider).listarPorCliente(datos.cliente.id);
    if (!mounted) return;

    var borrador = const ConfiguracionCobroBorrador(
      tipoDocumento: null,
      frecuenciaId: '',
      diaInicioPeriodo: null,
      agrupacion: null,
      metodo: null,
      requiereComplemento: false,
      fechaInicioVigencia: null,
    );
    var etapas = const <EtapaCobroBorrador>[];
    // Etapa 15: errores del intento anterior — `onConfirm` devuelve
    // `null` cuando son de validación (el diálogo permanece abierto,
    // `contentBuilder` se vuelve a invocar y el formulario ya puede
    // mostrar el `errorText` específico de cada campo, en vez del
    // mensaje genérico único que se mostraba antes).
    var errores = const <ErrorConfiguracionCobro>[];

    final resultado = await RisegDialog.showForm<CrearConfiguracionCobroResultado?>(
      context: context,
      title: l10n.servicioCobroDialogoAltaTitulo,
      confirmLabel: l10n.servicioVinculacionDialogoBotonGuardar,
      cancelLabel: l10n.servicioVinculacionDialogoBotonCancelar,
      contentBuilder: (_) => ServicioConfiguracionCobroForm(
        frecuencias: frecuencias,
        entidadesFiscales: entidades,
        contactos: contactos,
        portales: portales,
        errores: errores,
        onCambio: (nuevoBorrador, nuevasEtapas) {
          borrador = nuevoBorrador;
          etapas = nuevasEtapas;
        },
      ),
      onConfirm: () async {
        final r = await _notifier.agregarConfiguracionCobro(borrador, etapas: etapas);
        if (r is CrearConfiguracionCobroErroresValidacion) {
          errores = r.errores;
          if (r.erroresEtapas.isNotEmpty && mounted) {
            RisegFeedback.showError(context, l10n.servicioCobroErrorReglasEvento);
          }
          return null;
        }
        return r;
      },
    );

    if (!mounted) return;
    switch (resultado) {
      case CrearConfiguracionCobroExitoso():
        RisegFeedback.showSuccess(context, l10n.servicioCobroGuardadoExito);
      case CrearConfiguracionCobroErroresValidacion():
        break; // Ya se mostró inline; el diálogo nunca cierra con este caso.
      case CrearConfiguracionCobroServicioNoDisponible():
        RisegFeedback.showError(context, l10n.servicioCobroErrorServicioNoDisponible);
      case CrearConfiguracionCobroYaExiste():
        RisegFeedback.showError(context, l10n.servicioCobroErrorYaExiste);
      case CrearConfiguracionCobroErrorInesperado():
        RisegFeedback.showError(context, l10n.servicioCobroErrorInesperado);
      case null:
        break;
    }
  }

  Future<void> _corregirConfiguracionCobro() async {
    final l10n = AppLocalizations.of(context)!;
    final datos = ref.read(servicioExpedienteControllerProvider(widget.servicioId)).datos!;
    final configuracionCobro = datos.configuracionCobro!;

    final frecuencias = await ref.read(catalogoRepositoryProvider).listarFrecuenciasCobro();
    final entidades = (await ref.read(entidadFiscalRepositoryProvider).listarPorCliente(datos.cliente.id))
        .where((e) => e.entidadFiscal.cicloVidaRegistro == CicloVidaRegistro.activo.name)
        .map((e) => e.entidadFiscal)
        .toList();
    final contactos = await ref.read(clienteRepositoryProvider).obtenerContactos(datos.cliente.id);
    final portales = await ref.read(clientePortalRepositoryProvider).listarPorCliente(datos.cliente.id);
    if (!mounted) return;

    final vigenciaActual = configuracionCobro.vigenciaActual;
    var borrador = ConfiguracionCobroBorrador(
      tipoDocumento: vigenciaActual == null ? null : TipoDocumentoCobro.values.byName(vigenciaActual.tipoDocumento),
      frecuenciaId: vigenciaActual?.frecuenciaId ?? '',
      diaInicioPeriodo: vigenciaActual?.diaInicioPeriodo,
      agrupacion: vigenciaActual == null ? null : AgrupacionCobro.values.byName(vigenciaActual.agrupacion),
      metodo: vigenciaActual == null ? null : MetodoPagoCobro.values.byName(vigenciaActual.metodo),
      requiereComplemento: vigenciaActual?.requiereComplemento ?? false,
      fechaInicioVigencia: vigenciaActual?.fechaInicioVigencia,
      entidadFiscalId: vigenciaActual?.entidadFiscalId,
      clientePortalId: vigenciaActual?.clientePortalId,
      cuentaBancaria: vigenciaActual?.cuentaBancaria,
      observaciones: vigenciaActual?.observaciones,
      correos: configuracionCobro.correos,
    );
    var etapas = const <EtapaCobroBorrador>[];
    var errores = const <ErrorConfiguracionCobro>[];

    final resultado = await RisegDialog.showForm<CorregirConfiguracionCobroResultado?>(
      context: context,
      title: l10n.servicioCobroCorregirDialogoTitulo,
      confirmLabel: l10n.servicioVinculacionDialogoBotonGuardar,
      cancelLabel: l10n.servicioVinculacionDialogoBotonCancelar,
      contentBuilder: (_) => ServicioConfiguracionCobroForm(
        frecuencias: frecuencias,
        entidadesFiscales: entidades,
        contactos: contactos,
        portales: portales,
        valoresIniciales: vigenciaActual,
        etapasIniciales: configuracionCobro.etapas,
        errores: errores,
        onCambio: (nuevoBorrador, nuevasEtapas) {
          borrador = nuevoBorrador;
          etapas = nuevasEtapas;
        },
      ),
      onConfirm: () async {
        // Corregir CÓMO y CUÁNDO se cobra exige motivo: el diálogo común
        // se abre antes de tocar nada.
        final motivo = await mostrarDialogoMotivo(
          context,
          titulo: l10n.configuracionCobroMotivoCorreccionTitulo,
          etiquetaMotivo: l10n.auditoriaCampoMotivo,
          confirmarLabel: l10n.servicioVinculacionDialogoBotonGuardar,
          cancelarLabel: l10n.servicioVinculacionDialogoBotonCancelar,
          errorMotivoRequerido: l10n.auditoriaErrorMotivoRequerido,
        );
        if (motivo == null) return null;
        final r = await _notifier.corregirConfiguracionCobro(
          configuracionCobro.configuracion.id,
          borrador,
          etapas: etapas,
          motivo: motivo,
        );
        if (r is CorregirConfiguracionCobroErroresValidacion) {
          errores = r.errores;
          if (r.erroresEtapas.isNotEmpty && mounted) {
            RisegFeedback.showError(context, l10n.servicioCobroErrorReglasEvento);
          }
          return null;
        }
        return r;
      },
    );

    if (!mounted) return;
    switch (resultado) {
      case CorregirConfiguracionCobroExitoso():
        RisegFeedback.showSuccess(context, l10n.servicioCobroCorregirExito);
      case CorregirConfiguracionCobroTieneHistoria():
        RisegFeedback.showError(context, l10n.servicioCobroCorregirErrorTieneHistoria);
      case CorregirConfiguracionCobroMotivoRequerido():
      case CorregirConfiguracionCobroNoExiste():
        RisegFeedback.showError(context, l10n.servicioCobroNuevaVigenciaErrorInesperado);
      case CorregirConfiguracionCobroErroresValidacion():
        break; // Ya se mostró inline; el diálogo nunca cierra con este caso.
      case CorregirConfiguracionCobroErrorInesperado():
        RisegFeedback.showError(context, l10n.servicioCobroNuevaVigenciaErrorInesperado);
      case null:
        break;
    }
  }

  Future<void> _nuevaVigenciaConfiguracionCobro() async {
    final l10n = AppLocalizations.of(context)!;
    final datos = ref.read(servicioExpedienteControllerProvider(widget.servicioId)).datos!;
    final configuracionCobro = datos.configuracionCobro!;

    final frecuencias = await ref.read(catalogoRepositoryProvider).listarFrecuenciasCobro();
    final entidades = (await ref.read(entidadFiscalRepositoryProvider).listarPorCliente(datos.cliente.id))
        .where((e) => e.entidadFiscal.cicloVidaRegistro == CicloVidaRegistro.activo.name)
        .map((e) => e.entidadFiscal)
        .toList();
    final contactos = await ref.read(clienteRepositoryProvider).obtenerContactos(datos.cliente.id);
    final portales = await ref.read(clientePortalRepositoryProvider).listarPorCliente(datos.cliente.id);
    if (!mounted) return;

    final vigenciaActual = configuracionCobro.vigenciaActual;
    var borrador = ConfiguracionCobroBorrador(
      tipoDocumento: vigenciaActual == null ? null : TipoDocumentoCobro.values.byName(vigenciaActual.tipoDocumento),
      frecuenciaId: vigenciaActual?.frecuenciaId ?? '',
      diaInicioPeriodo: vigenciaActual?.diaInicioPeriodo,
      agrupacion: vigenciaActual == null ? null : AgrupacionCobro.values.byName(vigenciaActual.agrupacion),
      metodo: vigenciaActual == null ? null : MetodoPagoCobro.values.byName(vigenciaActual.metodo),
      requiereComplemento: vigenciaActual?.requiereComplemento ?? false,
      fechaInicioVigencia: null,
      entidadFiscalId: vigenciaActual?.entidadFiscalId,
      clientePortalId: vigenciaActual?.clientePortalId,
      cuentaBancaria: vigenciaActual?.cuentaBancaria,
      observaciones: vigenciaActual?.observaciones,
      correos: configuracionCobro.correos,
    );
    var etapas = const <EtapaCobroBorrador>[];
    var errores = const <ErrorConfiguracionCobro>[];
    String? errorGeneral;

    final resultado = await RisegDialog.showForm<CambiarVigenciaConfiguracionCobroResultado?>(
      context: context,
      title: l10n.servicioCobroNuevaVigenciaDialogoTitulo,
      confirmLabel: l10n.servicioVinculacionDialogoBotonGuardar,
      cancelLabel: l10n.servicioVinculacionDialogoBotonCancelar,
      contentBuilder: (_) => ServicioConfiguracionCobroForm(
        frecuencias: frecuencias,
        entidadesFiscales: entidades,
        contactos: contactos,
        portales: portales,
        valoresIniciales: vigenciaActual,
        etapasIniciales: configuracionCobro.etapas,
        errores: errores,
        errorGeneral: errorGeneral,
        onCambio: (nuevoBorrador, nuevasEtapas) {
          borrador = nuevoBorrador;
          etapas = nuevasEtapas;
        },
      ),
      onConfirm: () async {
        if (!await _confirmarSiEsRetroactiva(borrador.fechaInicioVigencia)) return null;
        if (!mounted) return null;
        errores = const [];
        errorGeneral = null;
        final r = await _notifier.cambiarVigenciaConfiguracionCobro(configuracionCobro.configuracion.id, borrador, etapas: etapas);

        final decision = decidirCierreNuevaVigenciaCobro(r, mensajeReglasEtapas: l10n.servicioCobroErrorReglasEvento);
        errores = decision.errores;
        errorGeneral = decision.errorGeneral;
        // `null` mantiene el diálogo abierto (convenio de
        // `RisegDialog.showForm`) con toda la captura intacta.
        return decision.cierraElDialogo ? r : null;
      },
    );

    if (!mounted) return;
    switch (resultado) {
      case CambiarVigenciaConfiguracionCobroExitoso():
        RisegFeedback.showSuccess(context, l10n.servicioCobroNuevaVigenciaExito);
      case CambiarVigenciaConfiguracionCobroErroresValidacion():
      case CambiarVigenciaConfiguracionCobroErrorInesperado():
        break; // Se muestran dentro del formulario; nunca cierran el diálogo.
      case CambiarVigenciaConfiguracionCobroServicioNoDisponible():
        // El Servicio está terminado: no hay nada que corregir en el
        // formulario, así que aquí sí tiene sentido cerrar.
        RisegFeedback.showError(context, l10n.servicioCobroNuevaVigenciaErrorServicioNoDisponible);
      case CambiarVigenciaConfiguracionCobroNoExiste():
        RisegFeedback.showError(context, l10n.servicioCobroNuevaVigenciaErrorInesperado);
      case null:
        break;
    }
  }

  Future<void> _cerrarConfiguracionCobro() async {
    final l10n = AppLocalizations.of(context)!;
    final configuracionCobro = ref.read(servicioExpedienteControllerProvider(widget.servicioId)).datos!.configuracionCobro!;

    var fechaEfectiva = DateTime.now();
    final confirmadoCierreCobro = await RisegDialog.showForm<bool>(
      context: context,
      title: l10n.servicioCobroCerrarDialogoTitulo,
      confirmLabel: l10n.servicioCobroCerrarBotonConfirmar,
      cancelLabel: l10n.servicioVinculacionDialogoBotonCancelar,
      contentBuilder: (_) => ServicioCerrarConfiguracionCobroForm(onCambio: (valor) => fechaEfectiva = valor),
      onConfirm: () async => true,
    );

    if (!mounted || confirmadoCierreCobro != true) return;

    // El motivo se pide con el formulario ya cerrado — mismo orden que
    // "Cerrar línea comercial". Pedirlo dentro de `onConfirm` dejaría al
    // diálogo anfitrión girando en "guardando" mientras el usuario
    // escribe, y no hay validación inline que obligue a mantenerlo
    // abierto.
    final motivoCierreCobro = await mostrarDialogoMotivo(
      context,
      titulo: l10n.configuracionCobroMotivoCierreTitulo,
      etiquetaMotivo: l10n.auditoriaCampoMotivo,
      confirmarLabel: l10n.servicioVinculacionDialogoBotonGuardar,
      cancelarLabel: l10n.servicioVinculacionDialogoBotonCancelar,
      errorMotivoRequerido: l10n.auditoriaErrorMotivoRequerido,
    );
    if (!mounted || motivoCierreCobro == null) return;

    final resultado = await _notifier.cerrarConfiguracionCobro(
      configuracionCobro.configuracion.id,
      fechaEfectiva,
      motivo: motivoCierreCobro,
    );

    if (!mounted) return;
    switch (resultado) {
      case CerrarConfiguracionCobroExitoso():
        RisegFeedback.showSuccess(context, l10n.servicioCobroCerrarExito);
      case CerrarConfiguracionCobroSinCondicionVigente():
        RisegFeedback.showError(context, l10n.servicioCobroCerrarErrorSinCondicionVigente);
      case CerrarConfiguracionCobroTieneVigenciaProgramada():
        RisegFeedback.showError(context, l10n.servicioCobroCerrarErrorTieneProgramada);
      case CerrarConfiguracionCobroFechaAnteriorInicio():
        RisegFeedback.showError(context, l10n.servicioCobroCerrarErrorFechaAnterior);
      case CerrarConfiguracionCobroMotivoRequerido():
      case CerrarConfiguracionCobroNoExiste():
        RisegFeedback.showError(context, l10n.servicioCobroCerrarErrorInesperado);
      case CerrarConfiguracionCobroErrorInesperado():
        RisegFeedback.showError(context, l10n.servicioCobroCerrarErrorInesperado);
      case null:
        break;
    }
  }

  Future<void> _editarObservacionesConfiguracionCobroVigencia(VigenciaHistorialCobro fila) async {
    final l10n = AppLocalizations.of(context)!;

    String? observaciones = fila.vigencia.observaciones;
    final resultado = await RisegDialog.showForm<ActualizarObservacionesConfiguracionCobroVigenciaResultado?>(
      context: context,
      title: l10n.servicioCobroObservacionesDialogoTitulo,
      confirmLabel: l10n.servicioVinculacionDialogoBotonGuardar,
      cancelLabel: l10n.servicioVinculacionDialogoBotonCancelar,
      contentBuilder: (_) => ServicioObservacionesConfiguracionCobroForm(
        vigencia: fila,
        onCambio: (nuevo) => observaciones = nuevo,
      ),
      onConfirm: () {
        return _notifier.actualizarObservacionesConfiguracionCobroVigencia(
          vigenciaId: fila.vigencia.id,
          observaciones: observaciones,
        );
      },
    );

    if (!mounted) return;
    switch (resultado) {
      case ActualizarObservacionesConfiguracionCobroVigenciaExitoso():
        RisegFeedback.showSuccess(context, l10n.servicioCobroObservacionesGuardadoExito);
      case ActualizarObservacionesConfiguracionCobroVigenciaNoEditable():
        RisegFeedback.showError(context, l10n.servicioCobroObservacionesErrorNoEditable);
      case ActualizarObservacionesConfiguracionCobroVigenciaNoExiste():
        RisegFeedback.showError(context, l10n.servicioCobroObservacionesErrorInesperado);
      case ActualizarObservacionesConfiguracionCobroVigenciaErrorInesperado():
        RisegFeedback.showError(context, l10n.servicioCobroObservacionesErrorInesperado);
      case null:
        break;
    }
  }

  Future<void> _cancelarVigenciaProgramadaConfiguracionCobro(VigenciaHistorialCobro fila) async {
    final l10n = AppLocalizations.of(context)!;

    final confirmado = await RisegDialog.showConfirmation(
      context: context,
      title: l10n.servicioCobroCancelarProgramadaConfirmacionTitulo,
      message: l10n.servicioCobroCancelarProgramadaConfirmacionMensaje,
      confirmLabel: l10n.servicioCobroCancelarProgramadaConfirmacionConfirmar,
      cancelLabel: l10n.servicioCobroCancelarProgramadaConfirmacionCancelar,
      destructive: true,
    );
    if (!mounted || confirmado != true) return;

    final motivoCancelacionCobro = await mostrarDialogoMotivo(
      context,
      titulo: l10n.configuracionCobroMotivoCancelacionTitulo,
      etiquetaMotivo: l10n.auditoriaCampoMotivo,
      confirmarLabel: l10n.servicioCobroCancelarProgramadaConfirmacionConfirmar,
      cancelarLabel: l10n.servicioCobroCancelarProgramadaConfirmacionCancelar,
      errorMotivoRequerido: l10n.auditoriaErrorMotivoRequerido,
    );
    if (!mounted || motivoCancelacionCobro == null) return;

    final resultado = await _notifier.cancelarVigenciaProgramadaConfiguracionCobro(
      fila.vigencia.id,
      motivo: motivoCancelacionCobro,
    );
    if (!mounted) return;
    switch (resultado) {
      case CancelarVigenciaProgramadaConfiguracionCobroExitoso():
        RisegFeedback.showSuccess(context, l10n.servicioCobroCancelarProgramadaExito);
      case CancelarVigenciaProgramadaConfiguracionCobroMotivoRequerido():
      case CancelarVigenciaProgramadaConfiguracionCobroNoEsProgramada():
        RisegFeedback.showError(context, l10n.servicioCobroCancelarProgramadaErrorNoEsProgramada);
      case CancelarVigenciaProgramadaConfiguracionCobroNoExiste():
        RisegFeedback.showError(context, l10n.servicioCobroCancelarProgramadaErrorInesperado);
      case CancelarVigenciaProgramadaConfiguracionCobroErrorInesperado():
        RisegFeedback.showError(context, l10n.servicioCobroCancelarProgramadaErrorInesperado);
      case null:
        break;
    }
  }

  Future<void> _verHistorialConfiguracionCobro() async {
    final l10n = AppLocalizations.of(context)!;
    final configuracionCobroId =
        ref.read(servicioExpedienteControllerProvider(widget.servicioId)).datos!.configuracionCobro!.configuracion.id;
    final historial = await ref.read(obtenerHistorialConfiguracionCobroUseCaseProvider).ejecutar(configuracionCobroId);
    if (!mounted) return;

    await RisegDialog.showForm<void>(
      context: context,
      title: l10n.servicioCobroHistorialDialogoTitulo,
      confirmLabel: l10n.servicioCobroHistorialBotonCerrar,
      cancelLabel: l10n.servicioVinculacionDialogoBotonCancelar,
      contentBuilder: (dialogContext) => ServicioHistorialConfiguracionCobroContent(
        historial: historial,
        onEditarObservaciones: (fila) async {
          Navigator.of(dialogContext).pop();
          await _editarObservacionesConfiguracionCobroVigencia(fila);
          if (!mounted) return;
          await _verHistorialConfiguracionCobro();
        },
        onCancelarProgramada: (fila) async {
          Navigator.of(dialogContext).pop();
          await _cancelarVigenciaProgramadaConfiguracionCobro(fila);
          if (!mounted) return;
          await _verHistorialConfiguracionCobro();
        },
      ),
    );
  }

  /// `true` si el usuario confirma continuar — usado antes de registrar
  /// una vigencia retroactiva (Etapa 4G.2, Resolución H: permitido, pero
  /// solo con confirmación explícita; nunca bloqueado desde el dominio
  /// mientras no exista Configuración de cobro/Facturación).
  Future<bool> _confirmarSiEsRetroactiva(DateTime? fechaInicioVigencia) async {
    if (fechaInicioVigencia == null) return true;
    if (!soloFecha(fechaInicioVigencia).isBefore(soloFecha(DateTime.now()))) return true;

    final l10n = AppLocalizations.of(context)!;
    final confirmado = await RisegDialog.showConfirmation(
      context: context,
      title: l10n.servicioComercialRetroactivoConfirmacionTitulo,
      message: l10n.servicioComercialRetroactivoConfirmacionMensaje,
      confirmLabel: l10n.servicioComercialRetroactivoConfirmacionConfirmar,
      cancelLabel: l10n.servicioComercialRetroactivoConfirmacionCancelar,
    );
    return confirmado == true;
  }

  Future<void> _corregirLinea(LineaComercialConVigencia linea) async {
    final l10n = AppLocalizations.of(context)!;

    final puestos = await ref.read(puestoRepositoryProvider).listarActivos();
    final modalidades = await ref.read(catalogoRepositoryProvider).listarModalidadesTurno();
    if (!mounted) return;

    final vigenciaActual = linea.vigenciaActual ?? (linea.vigenciasProgramadas.isEmpty ? null : linea.vigenciasProgramadas.first);
    final horarioInicial = vigenciaActual == null
        ? const <ServicioLineaComercialVigenciaHorarioData>[]
        : await ref.read(servicioComercialRepositoryProvider).obtenerHorario(vigenciaActual.id);
    if (!mounted) return;
    var borrador = LineaComercialBorrador(
      puestoId: vigenciaActual?.puestoId ?? '',
      modalidadTurnoId: vigenciaActual?.modalidadTurnoId ?? '',
      cantidadElementos: vigenciaActual?.cantidadElementos,
      precioUnitario: vigenciaActual?.precioUnitario,
      tratamientoIva: vigenciaActual == null ? null : TratamientoIva.values.byName(vigenciaActual.tratamientoIva),
      fechaInicioVigencia: vigenciaActual?.fechaInicioVigencia,
      descripcion: vigenciaActual?.descripcion,
      observaciones: vigenciaActual?.observaciones,
    );

    final confirmadoCorreccion = await RisegDialog.showForm<bool>(
      context: context,
      title: l10n.servicioComercialCorregirDialogoTitulo,
      confirmLabel: l10n.servicioVinculacionDialogoBotonGuardar,
      cancelLabel: l10n.servicioVinculacionDialogoBotonCancelar,
      contentBuilder: (_) => ServicioLineaComercialForm(
        puestos: puestos,
        modalidadesTurno: modalidades,
        valoresIniciales: vigenciaActual,
        precargarFechas: true,
        horarioInicial: horarioInicial,
        onCambio: (nuevo) => borrador = nuevo,
      ),
      onConfirm: () async => true,
    );

    if (!mounted || confirmadoCorreccion != true) return;

    // Corregir una vigencia EXISTENTE cambia lo que se cobra: el motivo
    // es obligatorio y viaja a la bitácora del Servicio.
    final motivoCorreccion = await mostrarDialogoMotivo(
      context,
      titulo: l10n.lineaComercialMotivoCorreccionTitulo,
      etiquetaMotivo: l10n.auditoriaCampoMotivo,
      confirmarLabel: l10n.servicioTerminarBotonConfirmar,
      cancelarLabel: l10n.servicioTerminarBotonCancelar,
      errorMotivoRequerido: l10n.auditoriaErrorMotivoRequerido,
    );
    if (!mounted || motivoCorreccion == null) return;
    final resultado = await _notifier.corregirLinea(linea.linea.id, borrador, motivo: motivoCorreccion);

    if (!mounted) return;
    switch (resultado) {
      case CorregirLineaComercialExitoso():
        RisegFeedback.showSuccess(context, l10n.servicioComercialCorregirExito);
        ref.invalidate(dashboardControllerProvider);
      case CorregirLineaComercialMotivoRequerido():
      case CorregirLineaComercialTieneHistoria():
        RisegFeedback.showError(context, l10n.servicioComercialCorregirErrorTieneHistoria);
      case CorregirLineaComercialNoExiste():
        RisegFeedback.showError(context, l10n.servicioComercialNuevaVigenciaErrorInesperado);
      case CorregirLineaComercialErroresValidacion():
        RisegFeedback.showError(context, l10n.servicioComercialErrorValidacion);
      case CorregirLineaComercialErrorInesperado():
        RisegFeedback.showError(context, l10n.servicioComercialNuevaVigenciaErrorInesperado);
      case null:
        break;
    }
  }

  Future<void> _eliminarLineaFisicamente(LineaComercialConVigencia linea) async {
    final eliminado = await mostrarDialogoEliminarLineaComercialFisicamente(context, ref, linea.linea.id);
    if (eliminado && mounted) {
      await _notifier.reintentarCarga();
      ref.invalidate(dashboardControllerProvider);
    }
  }

  Future<void> _nuevaVigencia(LineaComercialConVigencia linea) async {
    final l10n = AppLocalizations.of(context)!;

    final puestos = await ref.read(puestoRepositoryProvider).listarActivos();
    final modalidades = await ref.read(catalogoRepositoryProvider).listarModalidadesTurno();
    if (!mounted) return;

    final vigenciaActual = linea.vigenciaActual;
    // "Nueva vigencia" copia el horario de la vigencia anterior como
    // punto de partida editable — nunca la muta: `ServicioLineaComercialForm`
    // solo la usa para precargar controles nuevos, y `cambiarVigencia`
    // siempre inserta una fila de horario nueva, ligada a la vigencia
    // nueva (la vigencia histórica y su propio horario quedan intactos).
    final horarioInicial = vigenciaActual == null
        ? const <ServicioLineaComercialVigenciaHorarioData>[]
        : await ref.read(servicioComercialRepositoryProvider).obtenerHorario(vigenciaActual.id);
    if (!mounted) return;
    var borrador = LineaComercialBorrador(
      puestoId: vigenciaActual?.puestoId ?? '',
      modalidadTurnoId: vigenciaActual?.modalidadTurnoId ?? '',
      cantidadElementos: vigenciaActual?.cantidadElementos,
      precioUnitario: vigenciaActual?.precioUnitario,
      tratamientoIva: vigenciaActual == null ? null : TratamientoIva.values.byName(vigenciaActual.tratamientoIva),
      fechaInicioVigencia: null,
      descripcion: vigenciaActual?.descripcion,
      observaciones: vigenciaActual?.observaciones,
    );

    final resultado = await RisegDialog.showForm<CambiarVigenciaLineaComercialResultado?>(
      context: context,
      title: l10n.servicioComercialNuevaVigenciaDialogoTitulo,
      confirmLabel: l10n.servicioVinculacionDialogoBotonGuardar,
      cancelLabel: l10n.servicioVinculacionDialogoBotonCancelar,
      contentBuilder: (_) => ServicioLineaComercialForm(
        puestos: puestos,
        modalidadesTurno: modalidades,
        valoresIniciales: vigenciaActual,
        horarioInicial: horarioInicial,
        onCambio: (nuevo) => borrador = nuevo,
      ),
      onConfirm: () async {
        if (!await _confirmarSiEsRetroactiva(borrador.fechaInicioVigencia)) return null;
        if (!mounted) return null;
        return _notifier.cambiarVigenciaLinea(linea.linea.id, borrador);
      },
    );

    if (!mounted) return;
    switch (resultado) {
      case CambiarVigenciaLineaComercialExitoso():
        RisegFeedback.showSuccess(context, l10n.servicioComercialNuevaVigenciaExito);
        ref.invalidate(dashboardControllerProvider);
      case CambiarVigenciaLineaComercialErroresValidacion():
        RisegFeedback.showError(context, l10n.servicioComercialErrorValidacion);
      case CambiarVigenciaLineaComercialServicioNoDisponible():
        RisegFeedback.showError(context, l10n.servicioComercialNuevaVigenciaErrorServicioNoDisponible);
      case CambiarVigenciaLineaComercialLineaNoExiste():
        RisegFeedback.showError(context, l10n.servicioComercialNuevaVigenciaErrorInesperado);
      case CambiarVigenciaLineaComercialErrorInesperado():
        RisegFeedback.showError(context, l10n.servicioComercialNuevaVigenciaErrorInesperado);
      case null:
        break;
    }
  }

  Future<void> _cerrarLinea(LineaComercialConVigencia linea) async {
    final l10n = AppLocalizations.of(context)!;

    var fechaEfectiva = DateTime.now();
    final confirmadoCierre = await RisegDialog.showForm<bool>(
      context: context,
      title: l10n.servicioComercialCerrarLineaDialogoTitulo,
      confirmLabel: l10n.servicioComercialCerrarLineaBotonConfirmar,
      cancelLabel: l10n.servicioVinculacionDialogoBotonCancelar,
      contentBuilder: (_) => ServicioCerrarLineaForm(onCambio: (valor) => fechaEfectiva = valor),
      onConfirm: () async => true,
    );

    if (!mounted || confirmadoCierre != true) return;

    final motivoCierre = await mostrarDialogoMotivo(
      context,
      titulo: l10n.lineaComercialMotivoCierreTitulo,
      etiquetaMotivo: l10n.auditoriaCampoMotivo,
      confirmarLabel: l10n.servicioTerminarBotonConfirmar,
      cancelarLabel: l10n.servicioTerminarBotonCancelar,
      errorMotivoRequerido: l10n.auditoriaErrorMotivoRequerido,
    );
    if (!mounted || motivoCierre == null) return;
    final resultado = await _notifier.cerrarLineaComercial(linea.linea.id, fechaEfectiva, motivo: motivoCierre);

    if (!mounted) return;
    switch (resultado) {
      case CerrarLineaComercialExitoso():
        RisegFeedback.showSuccess(context, l10n.servicioComercialCerrarLineaExito);
        ref.invalidate(dashboardControllerProvider);
      case CerrarLineaComercialMotivoRequerido():
      case CerrarLineaComercialSinCondicionVigente():
        RisegFeedback.showError(context, l10n.servicioComercialCerrarLineaErrorSinCondicionVigente);
      case CerrarLineaComercialTieneVigenciaProgramada():
        RisegFeedback.showError(context, l10n.servicioComercialCerrarLineaErrorTieneProgramada);
      case CerrarLineaComercialFechaAnteriorInicio():
        RisegFeedback.showError(context, l10n.servicioComercialCerrarLineaErrorFechaAnterior);
      case CerrarLineaComercialLineaNoExiste():
        RisegFeedback.showError(context, l10n.servicioComercialCerrarLineaErrorInesperado);
      case CerrarLineaComercialErrorInesperado():
        RisegFeedback.showError(context, l10n.servicioComercialCerrarLineaErrorInesperado);
      case null:
        break;
    }
  }

  Future<void> _editarAnotacionesVigencia(VigenciaHistorial fila) async {
    final l10n = AppLocalizations.of(context)!;

    String? descripcion = fila.vigencia.descripcion;
    String? observaciones = fila.vigencia.observaciones;
    final resultado = await RisegDialog.showForm<ActualizarAnotacionesVigenciaResultado?>(
      context: context,
      title: l10n.servicioComercialAnotacionesDialogoTitulo,
      confirmLabel: l10n.servicioVinculacionDialogoBotonGuardar,
      cancelLabel: l10n.servicioVinculacionDialogoBotonCancelar,
      contentBuilder: (_) => ServicioAnotacionesForm(
        vigencia: fila,
        onCambio: (nuevaDescripcion, nuevasObservaciones) {
          descripcion = nuevaDescripcion;
          observaciones = nuevasObservaciones;
        },
      ),
      onConfirm: () {
        return _notifier.actualizarAnotacionesVigencia(
          vigenciaId: fila.vigencia.id,
          descripcion: descripcion,
          observaciones: observaciones,
        );
      },
    );

    if (!mounted) return;
    switch (resultado) {
      case ActualizarAnotacionesVigenciaExitoso():
        RisegFeedback.showSuccess(context, l10n.servicioComercialAnotacionesGuardadoExito);
      case ActualizarAnotacionesVigenciaNoEditable():
        RisegFeedback.showError(context, l10n.servicioComercialAnotacionesErrorNoEditable);
      case ActualizarAnotacionesVigenciaNoExiste():
        RisegFeedback.showError(context, l10n.servicioComercialAnotacionesErrorInesperado);
      case ActualizarAnotacionesVigenciaErrorInesperado():
        RisegFeedback.showError(context, l10n.servicioComercialAnotacionesErrorInesperado);
      case null:
        break;
    }
  }

  Future<void> _cancelarVigenciaProgramada(VigenciaHistorial fila) async {
    final l10n = AppLocalizations.of(context)!;

    final confirmado = await RisegDialog.showConfirmation(
      context: context,
      title: l10n.servicioComercialCancelarProgramadaConfirmacionTitulo,
      message: l10n.servicioComercialCancelarProgramadaConfirmacionMensaje,
      confirmLabel: l10n.servicioComercialCancelarProgramadaConfirmacionConfirmar,
      cancelLabel: l10n.servicioComercialCancelarProgramadaConfirmacionCancelar,
      destructive: true,
    );
    if (!mounted || confirmado != true) return;

    final motivoCancelacion = await mostrarDialogoMotivo(
      context,
      titulo: l10n.lineaComercialMotivoCancelacionTitulo,
      etiquetaMotivo: l10n.auditoriaCampoMotivo,
      confirmarLabel: l10n.servicioTerminarBotonConfirmar,
      cancelarLabel: l10n.servicioTerminarBotonCancelar,
      errorMotivoRequerido: l10n.auditoriaErrorMotivoRequerido,
    );
    if (!mounted || motivoCancelacion == null) return;

    final resultado = await _notifier.cancelarVigenciaProgramada(fila.vigencia.id, motivo: motivoCancelacion);
    if (!mounted) return;
    switch (resultado) {
      case CancelarVigenciaProgramadaExitoso():
        RisegFeedback.showSuccess(context, l10n.servicioComercialCancelarProgramadaExito);
        ref.invalidate(dashboardControllerProvider);
      case CancelarVigenciaProgramadaMotivoRequerido():
      case CancelarVigenciaProgramadaNoEsProgramada():
        RisegFeedback.showError(context, l10n.servicioComercialCancelarProgramadaErrorNoEsProgramada);
      case CancelarVigenciaProgramadaNoExiste():
        RisegFeedback.showError(context, l10n.servicioComercialCancelarProgramadaErrorInesperado);
      case CancelarVigenciaProgramadaErrorInesperado():
        RisegFeedback.showError(context, l10n.servicioComercialCancelarProgramadaErrorInesperado);
      case null:
        break;
    }
  }

  Future<void> _verHistorial(LineaComercialConVigencia linea) async {
    final l10n = AppLocalizations.of(context)!;
    final historial = await ref.read(obtenerHistorialLineaComercialUseCaseProvider).ejecutar(linea.linea.id);
    if (!mounted) return;

    await RisegDialog.showForm<void>(
      context: context,
      title: l10n.servicioComercialHistorialDialogoTitulo,
      confirmLabel: l10n.servicioComercialHistorialBotonCerrar,
      cancelLabel: l10n.servicioVinculacionDialogoBotonCancelar,
      contentBuilder: (dialogContext) => ServicioHistorialLineaComercialContent(
        historial: historial,
        onEditarAnotaciones: (fila) async {
          Navigator.of(dialogContext).pop();
          await _editarAnotacionesVigencia(fila);
          if (!mounted) return;
          await _verHistorial(linea);
        },
        onCancelarProgramada: (fila) async {
          Navigator.of(dialogContext).pop();
          await _cancelarVigenciaProgramada(fila);
          if (!mounted) return;
          await _verHistorial(linea);
        },
      ),
    );
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
    final esMaestro = ref.watch(sesionControllerProvider)?.esMaestro ?? false;

    final direccionOperativa = datos.direccionOperativa;
    final ubicacionTexto =
        direccionOperativa == null ? null : '${direccionOperativa.municipioAlcaldia}, ${direccionOperativa.estado}';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppBreakpoints.wide),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RisegSectionHeader(
                title: l10n.servicioExpedienteTitulo,
                primaryAction: esEdicion
                    ? RisegButton(
                        key: const Key('servicio_expediente_boton_guardar'),
                        label: l10n.servicioExpedienteBotonGuardar,
                        loading: state.guardando,
                        onPressed: _guardar,
                      )
                    : null,
                secondaryAction: esEdicion
                    ? RisegButton(
                        key: const Key('servicio_expediente_boton_cancelar'),
                        label: l10n.servicioExpedienteBotonCancelar,
                        variant: RisegButtonVariant.ghost,
                        onPressed: state.guardando ? null : () => _cancelar(state.tieneCambiosSinGuardar),
                      )
                    : null,
              ),
              const SizedBox(height: AppSpacing.md),
              FutureBuilder<({AttachmentData? logo, List<CatalogoItem> turnos})>(
                future: _cargarDatosFicha(datos.cliente),
                builder: (context, snapshot) {
                  final nombrePorTurnoId = {for (final t in snapshot.data?.turnos ?? const []) t.id: t.nombre};
                  final turnosDistintos = <String>{};
                  for (final p in datos.personalVigente) {
                    final nombre = p.asignacion.turnoId == null ? null : nombrePorTurnoId[p.asignacion.turnoId];
                    if (nombre != null) turnosDistintos.add(nombre);
                  }
                  final coberturaTurnos = turnosDistintos.isEmpty ? null : (turnosDistintos.toList()..sort()).join(' / ');

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ServicioFichaHeader(
                        servicio: servicio,
                        clienteNombre: datos.cliente.nombreComercial,
                        logoPath: snapshot.data?.logo?.path,
                        ubicacion: ubicacionTexto,
                        estatusBadge: RisegStatusBadge(label: _nombreEstatus(l10n, estatusActual), tone: _tonoEstatus(estatusActual)),
                        onTapCliente: esEdicion ? null : () => context.push('/comercial/clientes/${servicio.clienteId}'),
                        acciones: esEdicion
                            ? null
                            : Wrap(
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: AppSpacing.sm,
                                runSpacing: AppSpacing.xs,
                                children: [
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
                                  RisegButton(
                                    key: const Key('servicio_expediente_boton_editar'),
                                    label: l10n.servicioExpedienteBotonEditar,
                                    size: RisegButtonSize.compact,
                                    onPressed: () => _iniciarEdicion(servicio),
                                  ),
                                  if (esMaestro)
                                    RisegActionsMenu(
                                      menuKey: const Key('servicio_menu_acciones'),
                                      actions: [
                                        RisegMenuAction(
                                          key: const Key('servicio_accion_eliminar_fisicamente'),
                                          label: l10n.eliminacionFisicaAccionMenu,
                                          icon: Icons.delete_forever_outlined,
                                          destructive: true,
                                          onTap: _eliminarFisicamente,
                                        ),
                                      ],
                                    ),
                                ],
                              ),
                      ),
                      if (mostrarActivar && !datos.tieneDireccionOperativaActiva) ...[
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          l10n.servicioBotonActivarAyudaSinDireccion,
                          style: AppTypography.caption.copyWith(color: Theme.of(context).colorScheme.outline),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.lg),
                      ServicioIndicadoresOperacionales(
                        personalAsignado: datos.personalVigente.length,
                        coberturaTurnos: coberturaTurnos,
                        importeMensual: datos.subtotalComercial,
                        antiguedad: formatearAntiguedadServicio(l10n, calcularAntiguedadServicioEnMeses(servicio.fechaInicio)),
                      ),
                    ],
                  );
                },
              ),
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
                  elementosComercialesVigentes: datos.elementosComercialesVigentes,
                  elementosAutorizados: servicio.elementosAutorizados,
                  elementosDifierenDeAutorizados: datos.elementosDifierenDeAutorizados,
                  proximaFechaProgramada: datos.proximaFechaProgramada,
                  deshabilitado: state.operandoComercial,
                  esMaestro: esMaestro,
                  onAgregarLinea: _agregarLineaComercial,
                  onCorregir: _corregirLinea,
                  onNuevaVigencia: _nuevaVigencia,
                  onCerrarLinea: _cerrarLinea,
                  onVerHistorial: _verHistorial,
                  onEliminarFisicamente: _eliminarLineaFisicamente,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              RisegCard(
                child: ServicioConfiguracionCobroSection(
                  configuracionCobro: datos.configuracionCobro,
                  deshabilitado: state.operandoCobro,
                  onAgregar: _agregarConfiguracionCobro,
                  onCorregir: _corregirConfiguracionCobro,
                  onNuevaVigencia: _nuevaVigenciaConfiguracionCobro,
                  onCerrar: _cerrarConfiguracionCobro,
                  onVerHistorial: _verHistorialConfiguracionCobro,
                ),
              ),
              // Secciones de otro dominio embebidas aquí (Etapa 11C, frontera
              // de lecturas protegidas) — mismo criterio que
              // `empleado_expediente_screen.dart`: cada una respeta su propio
              // `modulo.ver` aunque el usuario sí tenga acceso a Comercial.
              if (ref.watch(permissionServiceProvider).hasCode('personal.ver')) ...[
                const SizedBox(height: AppSpacing.xl),
                ServicioPersonalAsignadoSection(
                  personalVigente: datos.personalVigente,
                  historialPersonal: datos.personalAsignado,
                ),
              ],
              if (ref.watch(permissionServiceProvider).hasCode('inventario.ver')) ...[
                const SizedBox(height: AppSpacing.xl),
                RisegCard(child: InventarioAsignadoServicioSection(servicioId: widget.servicioId)),
              ],
              if (ref.watch(permissionServiceProvider).hasCode('vehiculos.ver')) ...[
                const SizedBox(height: AppSpacing.xl),
                RisegCard(child: VehiculoAsignadoServicioSection(servicioId: widget.servicioId)),
              ],
              if (ref.watch(permissionServiceProvider).hasCode('telefonia.ver')) ...[
                const SizedBox(height: AppSpacing.xl),
                RisegCard(child: LineaTelefonicaAsignadaServicioSection(servicioId: widget.servicioId)),
              ],
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
