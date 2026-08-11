import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/tables/audit_columns.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/core/validation/direccion_validator.dart';
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
import 'package:riseg_one/features/organizacion/domain/usecases/configuracion_cobro_regla_evento_validator.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/configuracion_cobro_validator.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_configuracion_cobro_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_linea_comercial_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_direccion_operativa_servicio_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_sueldo_referencia_servicio_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/linea_comercial_con_vigencia.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/linea_comercial_validator.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/obtener_historial_configuracion_cobro_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/obtener_historial_linea_comercial_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/servicio_errors.dart';
import 'package:riseg_one/features/inventario/presentation/asignaciones/widgets/inventario_asignado_servicio_section.dart';
import 'package:riseg_one/features/telefonia/presentation/widgets/linea_telefonica_asignada_servicio_section.dart';
import 'package:riseg_one/features/vehiculos/presentation/widgets/vehiculo_asignado_servicio_section.dart';
import 'package:riseg_one/features/usuarios/usuarios_providers.dart';

import '../../organizacion_providers.dart';
import 'servicio_expediente_controller.dart';
import 'servicio_expediente_form_controllers.dart';
import 'servicio_expediente_state.dart';
import 'widgets/servicio_auditoria_section.dart';
import 'widgets/servicio_condiciones_personal_section.dart';
import 'widgets/servicio_configuracion_comercial_section.dart';
import 'widgets/servicio_configuracion_cobro_section.dart';
import 'widgets/servicio_personal_asignado_section.dart';
import 'widgets/servicio_datos_generales_section.dart';
import 'widgets/servicio_direccion_operativa_section.dart';
import 'widgets/servicio_historial_configuracion_cobro_dialog.dart';
import 'widgets/servicio_historial_linea_comercial_dialog.dart';
import 'widgets/servicio_referencias_section.dart';
import 'widgets/servicio_vinculaciones_section.dart';

final _formatoFecha = DateFormat('dd/MM/yyyy');

/// Mismo criterio de parseo/precarga que `_precioEnCentavos` (Etapa
/// 4G.1) — duplicado deliberadamente, no compartido entre diálogos
/// (mismo precedente que `centavosDesdeTexto` en Personal).
int? _centavosDesdeTexto(String texto) {
  final normalizado = texto.trim().replaceAll(',', '');
  if (normalizado.isEmpty) return null;
  final pesos = double.tryParse(normalizado);
  if (pesos == null) return null;
  return (pesos * 100).round();
}

String _pesosDesdeCentavosParaEditar(int? centavos) {
  if (centavos == null) return '';
  return (centavos / 100).toStringAsFixed(2);
}

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
      onConfirm: () {
        return _notifier.asignarEntidadFiscal(seleccionId);
      },
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

  Future<void> _editarCondicionesPersonal() async {
    final l10n = AppLocalizations.of(context)!;
    final datos = ref.read(servicioExpedienteControllerProvider(widget.servicioId)).datos!;

    final sueldoController = TextEditingController(
      text: _pesosDesdeCentavosParaEditar(datos.servicio.sueldoMensualReferenciaPersonal),
    );
    final bonoController = TextEditingController(
      text: _pesosDesdeCentavosParaEditar(datos.servicio.bonoMensualReferenciaPersonal),
    );
    String? errorSueldo;
    String? errorBono;

    final confirmado = await RisegDialog.showForm<bool>(
      context: context,
      title: l10n.servicioCondicionesPersonalDialogoTitulo,
      confirmLabel: l10n.servicioVinculacionDialogoBotonGuardar,
      cancelLabel: l10n.servicioVinculacionDialogoBotonCancelar,
      contentBuilder: (_) => StatefulBuilder(
        builder: (dialogContext, setState) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.servicioCondicionesPersonalAyuda,
                style: AppTypography.caption.copyWith(color: dialogContext.colors.textMuted),
              ),
              const SizedBox(height: AppSpacing.md),
              RisegTextField(
                label: l10n.servicioCampoSueldoReferencia,
                controller: sueldoController,
                errorText: errorSueldo,
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: AppSpacing.md),
              RisegTextField(
                label: l10n.servicioCampoBonoReferencia,
                controller: bonoController,
                errorText: errorBono,
                keyboardType: TextInputType.number,
              ),
            ],
          );
        },
      ),
      onConfirm: () async {
        // `RisegDialog.showForm` solo mantiene el diálogo abierto cuando
        // `onConfirm` devuelve `null` — mismo criterio ya corregido en
        // los diálogos de Asignar/Cambiar Servicio (Etapa 6B, ajuste
        // funcional final).
        final resultado = await _notifier.guardarSueldoReferencia(
          sueldoMensualReferenciaPersonal: _centavosDesdeTexto(sueldoController.text),
          bonoMensualReferenciaPersonal: _centavosDesdeTexto(bonoController.text),
        );
        switch (resultado) {
          case GuardarSueldoReferenciaServicioExitoso():
            return true;
          case GuardarSueldoReferenciaServicioSueldoInvalido():
            errorSueldo = l10n.servicioCondicionesPersonalErrorSueldoInvalido;
            return null;
          case GuardarSueldoReferenciaServicioBonoInvalido():
            errorBono = l10n.servicioCondicionesPersonalErrorBonoInvalido;
            return null;
          case GuardarSueldoReferenciaServicioNoExiste():
          case GuardarSueldoReferenciaServicioErrorInesperado():
          case null:
            return false;
        }
      },
    );

    // Deferred: el diálogo sigue montado unos instantes durante su
    // animación de salida — liberar los controllers de inmediato
    // reproduce el crash "A TextEditingController was used after being
    // disposed" ya documentado en `crear_empleado_dialog.dart` (Etapa
    // 5D.1). Mismo criterio, mismo remedio.
    unawaited(
      Future.delayed(const Duration(milliseconds: 300), () {
        sueldoController.dispose();
        bonoController.dispose();
      }),
    );

    if (!mounted) return;
    if (confirmado == true) {
      RisegFeedback.showSuccess(context, l10n.servicioCondicionesPersonalGuardadoExito);
    } else if (confirmado == false) {
      RisegFeedback.showError(context, l10n.servicioCondicionesPersonalErrorInesperado);
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
    var reglas = const <ReglaEventoBorrador>[];

    final resultado = await RisegDialog.showForm<CrearConfiguracionCobroResultado?>(
      context: context,
      title: l10n.servicioCobroDialogoAltaTitulo,
      confirmLabel: l10n.servicioVinculacionDialogoBotonGuardar,
      cancelLabel: l10n.servicioVinculacionDialogoBotonCancelar,
      contentBuilder: (_) => ServicioConfiguracionCobroForm(
        frecuencias: frecuencias,
        entidadesFiscales: entidades,
        onCambio: (nuevoBorrador, nuevasReglas) {
          borrador = nuevoBorrador;
          reglas = nuevasReglas;
        },
      ),
      onConfirm: () {
        return _notifier.agregarConfiguracionCobro(borrador, reglas: reglas);
      },
    );

    if (!mounted) return;
    switch (resultado) {
      case CrearConfiguracionCobroExitoso():
        RisegFeedback.showSuccess(context, l10n.servicioCobroGuardadoExito);
      case CrearConfiguracionCobroErroresValidacion():
        RisegFeedback.showError(context, l10n.servicioCobroErrorValidacion);
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

  Future<void> _nuevaVigenciaConfiguracionCobro() async {
    final l10n = AppLocalizations.of(context)!;
    final datos = ref.read(servicioExpedienteControllerProvider(widget.servicioId)).datos!;
    final configuracionCobro = datos.configuracionCobro!;

    final frecuencias = await ref.read(catalogoRepositoryProvider).listarFrecuenciasCobro();
    final entidades = (await ref.read(entidadFiscalRepositoryProvider).listarPorCliente(datos.cliente.id))
        .where((e) => e.entidadFiscal.cicloVidaRegistro == CicloVidaRegistro.activo.name)
        .map((e) => e.entidadFiscal)
        .toList();
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
      portalNombre: vigenciaActual?.portalNombre,
      portalUrl: vigenciaActual?.portalUrl,
      portalUsuario: vigenciaActual?.portalUsuario,
      portalContrasena: vigenciaActual?.portalContrasena,
      portalObservaciones: vigenciaActual?.portalObservaciones,
      cuentaBancaria: vigenciaActual?.cuentaBancaria,
      observaciones: vigenciaActual?.observaciones,
      correos: configuracionCobro.correos,
    );
    var reglas = const <ReglaEventoBorrador>[];

    final resultado = await RisegDialog.showForm<CambiarVigenciaConfiguracionCobroResultado?>(
      context: context,
      title: l10n.servicioCobroNuevaVigenciaDialogoTitulo,
      confirmLabel: l10n.servicioVinculacionDialogoBotonGuardar,
      cancelLabel: l10n.servicioVinculacionDialogoBotonCancelar,
      contentBuilder: (_) => ServicioConfiguracionCobroForm(
        frecuencias: frecuencias,
        entidadesFiscales: entidades,
        valoresIniciales: vigenciaActual,
        reglasIniciales: configuracionCobro.reglasEventos,
        onCambio: (nuevoBorrador, nuevasReglas) {
          borrador = nuevoBorrador;
          reglas = nuevasReglas;
        },
      ),
      onConfirm: () async {
        if (!await _confirmarSiEsRetroactiva(borrador.fechaInicioVigencia)) return null;
        if (!mounted) return null;
        return _notifier.cambiarVigenciaConfiguracionCobro(configuracionCobro.configuracion.id, borrador, reglas: reglas);
      },
    );

    if (!mounted) return;
    switch (resultado) {
      case CambiarVigenciaConfiguracionCobroExitoso():
        RisegFeedback.showSuccess(context, l10n.servicioCobroNuevaVigenciaExito);
      case CambiarVigenciaConfiguracionCobroErroresValidacion():
        RisegFeedback.showError(context, l10n.servicioCobroErrorValidacion);
      case CambiarVigenciaConfiguracionCobroServicioNoDisponible():
        RisegFeedback.showError(context, l10n.servicioCobroNuevaVigenciaErrorServicioNoDisponible);
      case CambiarVigenciaConfiguracionCobroNoExiste():
        RisegFeedback.showError(context, l10n.servicioCobroNuevaVigenciaErrorInesperado);
      case CambiarVigenciaConfiguracionCobroErrorInesperado():
        RisegFeedback.showError(context, l10n.servicioCobroNuevaVigenciaErrorInesperado);
      case null:
        break;
    }
  }

  Future<void> _cerrarConfiguracionCobro() async {
    final l10n = AppLocalizations.of(context)!;
    final configuracionCobro = ref.read(servicioExpedienteControllerProvider(widget.servicioId)).datos!.configuracionCobro!;

    var fechaEfectiva = DateTime.now();
    final resultado = await RisegDialog.showForm<CerrarConfiguracionCobroResultado?>(
      context: context,
      title: l10n.servicioCobroCerrarDialogoTitulo,
      confirmLabel: l10n.servicioCobroCerrarBotonConfirmar,
      cancelLabel: l10n.servicioVinculacionDialogoBotonCancelar,
      contentBuilder: (_) => ServicioCerrarConfiguracionCobroForm(onCambio: (valor) => fechaEfectiva = valor),
      onConfirm: () {
        return _notifier.cerrarConfiguracionCobro(configuracionCobro.configuracion.id, fechaEfectiva);
      },
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
    if (confirmado != true) return;

    final resultado = await _notifier.cancelarVigenciaProgramadaConfiguracionCobro(fila.vigencia.id);
    if (!mounted) return;
    switch (resultado) {
      case CancelarVigenciaProgramadaConfiguracionCobroExitoso():
        RisegFeedback.showSuccess(context, l10n.servicioCobroCancelarProgramadaExito);
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

  Future<void> _nuevaVigencia(LineaComercialConVigencia linea) async {
    final l10n = AppLocalizations.of(context)!;

    final puestos = await ref.read(puestoRepositoryProvider).listarActivos();
    final modalidades = await ref.read(catalogoRepositoryProvider).listarModalidadesTurno();
    if (!mounted) return;

    final vigenciaActual = linea.vigenciaActual;
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
    final resultado = await RisegDialog.showForm<CerrarLineaComercialResultado?>(
      context: context,
      title: l10n.servicioComercialCerrarLineaDialogoTitulo,
      confirmLabel: l10n.servicioComercialCerrarLineaBotonConfirmar,
      cancelLabel: l10n.servicioVinculacionDialogoBotonCancelar,
      contentBuilder: (_) => ServicioCerrarLineaForm(onCambio: (valor) => fechaEfectiva = valor),
      onConfirm: () {
        return _notifier.cerrarLineaComercial(linea.linea.id, fechaEfectiva);
      },
    );

    if (!mounted) return;
    switch (resultado) {
      case CerrarLineaComercialExitoso():
        RisegFeedback.showSuccess(context, l10n.servicioComercialCerrarLineaExito);
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
    if (confirmado != true) return;

    final resultado = await _notifier.cancelarVigenciaProgramada(fila.vigencia.id);
    if (!mounted) return;
    switch (resultado) {
      case CancelarVigenciaProgramadaExitoso():
        RisegFeedback.showSuccess(context, l10n.servicioComercialCancelarProgramadaExito);
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
                  elementosComercialesVigentes: datos.elementosComercialesVigentes,
                  elementosAutorizados: servicio.elementosAutorizados,
                  elementosDifierenDeAutorizados: datos.elementosDifierenDeAutorizados,
                  proximaFechaProgramada: datos.proximaFechaProgramada,
                  deshabilitado: state.operandoComercial,
                  onAgregarLinea: _agregarLineaComercial,
                  onNuevaVigencia: _nuevaVigencia,
                  onCerrarLinea: _cerrarLinea,
                  onVerHistorial: _verHistorial,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              RisegCard(
                child: ServicioConfiguracionCobroSection(
                  configuracionCobro: datos.configuracionCobro,
                  deshabilitado: state.operandoCobro,
                  onAgregar: _agregarConfiguracionCobro,
                  onNuevaVigencia: _nuevaVigenciaConfiguracionCobro,
                  onCerrar: _cerrarConfiguracionCobro,
                  onVerHistorial: _verHistorialConfiguracionCobro,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              RisegCard(
                child: ServicioCondicionesPersonalSection(
                  servicio: servicio,
                  deshabilitado: state.operandoRelacion,
                  onEditar: _editarCondicionesPersonal,
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
