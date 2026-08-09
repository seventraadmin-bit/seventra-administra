import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/organizacion/presentation/shared/campo_consulta.dart';
import 'package:riseg_one/features/personal/data/tables/empleado_table.dart';
import 'package:riseg_one/features/personal/domain/usecases/actualizar_fotografia_empleado_usecase.dart';
import 'package:riseg_one/features/personal/domain/usecases/calcular_edad.dart';
import 'package:riseg_one/features/personal/domain/usecases/cambiar_estatus_empleado_usecase.dart';

import '../../../organizacion/organizacion_providers.dart';
import '../../personal_providers.dart';
import 'empleados_list_controller.dart';
import 'empleados_list_screen.dart';
import 'widgets/adjuntar_documento_empleado_dialog.dart';
import 'widgets/antidoping_empleado_dialog.dart';
import 'widgets/corregir_empleado_dialog.dart';
import 'widgets/crear_empleado_dialog.dart';
import 'widgets/domicilio_empleado_dialog.dart';
import 'widgets/estudio_socioeconomico_empleado_dialog.dart';
import 'widgets/perfil_psicologico_empleado_dialog.dart';

final _formatoFecha = DateFormat('dd/MM/yyyy');
final _formatoFechaHora = DateFormat('dd/MM/yyyy HH:mm');

/// Expediente del Empleado (Etapa 5A) — información general, contacto,
/// domicilio, laboral, escolaridad, experiencia en seguridad privada,
/// documentación e historial administrativo. Cada sección se corrige
/// vía su propio diálogo — sin el mecanismo de "modo edición" de página
/// completa que usan Cliente/Servicio/Sucursal (deliberado para esta
/// etapa de fundamentos: mantiene la pantalla simple).
class EmpleadoExpedienteScreen extends ConsumerStatefulWidget {
  const EmpleadoExpedienteScreen({required this.empleadoId, super.key});

  final String empleadoId;

  @override
  ConsumerState<EmpleadoExpedienteScreen> createState() => _EmpleadoExpedienteScreenState();
}

class _EmpleadoExpedienteScreenState extends ConsumerState<EmpleadoExpedienteScreen> {
  EmpleadoData? _empleado;
  DireccionData? _domicilio;
  List<AttachmentData> _documentos = const [];
  List<EmpleadoEventoData> _eventos = const [];
  PuestoData? _puesto;
  EmpresaData? _empresa;
  SucursalData? _sucursal;
  bool _cargando = true;
  bool _procesando = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    final empleadoRepo = ref.read(empleadoRepositoryProvider);
    final empleado = await empleadoRepo.obtenerPorId(widget.empleadoId);
    final domicilio = await empleadoRepo.obtenerDomicilio(widget.empleadoId);
    final documentos = await ref.read(attachmentRepositoryProvider).listarActivosPorEmpleado(widget.empleadoId);
    final eventos = await empleadoRepo.listarEventos(widget.empleadoId);

    PuestoData? puesto;
    if (empleado?.puestoId != null) {
      puesto = await ref.read(puestoRepositoryProvider).obtenerPorId(empleado!.puestoId!);
    }
    EmpresaData? empresa;
    if (empleado?.empresaId != null) {
      final activa = await ref.read(empresaRepositoryProvider).obtenerActiva();
      empresa = activa.id == empleado!.empresaId ? activa : null;
    }
    SucursalData? sucursal;
    if (empleado?.sucursalId != null) {
      sucursal = await ref.read(sucursalRepositoryProvider).obtenerPorId(empleado!.sucursalId!);
    }

    if (!mounted) return;
    setState(() {
      _empleado = empleado;
      _domicilio = domicilio;
      _documentos = documentos;
      _eventos = eventos;
      _puesto = puesto;
      _empresa = empresa;
      _sucursal = sucursal;
      _cargando = false;
    });
  }

  String _eventoLabel(AppLocalizations l10n, String tipoEvento) {
    return switch (TipoEventoEmpleado.values.byName(tipoEvento)) {
      TipoEventoEmpleado.creado => l10n.empleadoDetalleHistorialEventoCreado,
      TipoEventoEmpleado.corregido => l10n.empleadoDetalleHistorialEventoCorregido,
      TipoEventoEmpleado.cambioEstatus => l10n.empleadoDetalleHistorialEventoCambioEstatus,
      TipoEventoEmpleado.domicilioActualizado => l10n.empleadoDetalleHistorialEventoDomicilioActualizado,
      TipoEventoEmpleado.fotografiaActualizada => l10n.empleadoDetalleHistorialEventoFotografiaActualizada,
      TipoEventoEmpleado.documentoAdjuntado => l10n.empleadoDetalleHistorialEventoDocumentoAdjuntado,
      TipoEventoEmpleado.documentoArchivado => l10n.empleadoDetalleHistorialEventoDocumentoArchivado,
      TipoEventoEmpleado.perfilPsicologicoActualizado => l10n.empleadoDetalleHistorialEventoPerfilPsicologicoActualizado,
      TipoEventoEmpleado.estudioSocioeconomicoActualizado => l10n.empleadoDetalleHistorialEventoEstudioSocioeconomicoActualizado,
      TipoEventoEmpleado.antidopingActualizado => l10n.empleadoDetalleHistorialEventoAntidopingActualizado,
    };
  }

  Future<void> _corregir() async {
    final actualizo = await mostrarDialogoCorregirEmpleado(context, ref, _empleado!);
    if (actualizo) await _cargar();
  }

  Future<void> _editarDomicilio() async {
    final actualizo = await mostrarDialogoDomicilioEmpleado(context, ref, empleadoId: widget.empleadoId, domicilioActual: _domicilio);
    if (actualizo) await _cargar();
  }

  Future<void> _adjuntarDocumento() async {
    final adjunto = await mostrarDialogoAdjuntarDocumentoEmpleado(context, ref, widget.empleadoId);
    if (adjunto) await _cargar();
  }

  Future<void> _registrarPerfilPsicologico() async {
    final actualizo = await mostrarDialogoPerfilPsicologicoEmpleado(context, ref, _empleado!);
    if (actualizo) await _cargar();
  }

  Future<void> _registrarEstudioSocioeconomico() async {
    final actualizo = await mostrarDialogoEstudioSocioeconomicoEmpleado(context, ref, _empleado!);
    if (actualizo) await _cargar();
  }

  Future<void> _registrarAntidoping() async {
    final actualizo = await mostrarDialogoAntidopingEmpleado(context, ref, _empleado!);
    if (actualizo) await _cargar();
  }

  Future<void> _actualizarFotografia() async {
    final l10n = AppLocalizations.of(context)!;
    final seleccion = await FilePicker.platform.pickFiles(type: FileType.image);
    final archivo = seleccion?.files.singleOrNull;
    if (archivo?.path == null) return;
    if (!mounted) return;

    setState(() => _procesando = true);
    final resultado = await ref.read(actualizarFotografiaEmpleadoUseCaseProvider).ejecutar(
          empleadoId: widget.empleadoId,
          sourceFilePath: archivo!.path!,
          originalFileName: archivo.name,
          mimeType: 'image/${archivo.extension ?? 'jpeg'}',
        );
    if (!mounted) return;
    setState(() => _procesando = false);

    switch (resultado) {
      case ActualizarFotografiaEmpleadoExitoso():
        await _cargar();
      case ActualizarFotografiaEmpleadoNoExiste():
      case ActualizarFotografiaEmpleadoErrorInesperado():
        RisegFeedback.showError(context, l10n.actualizarFotografiaEmpleadoErrorInesperado);
    }
  }

  Future<void> _cambiarEstatus(EstatusEmpleado nuevo) async {
    final l10n = AppLocalizations.of(context)!;
    final motivoController = TextEditingController();
    final confirmado = await RisegDialog.showForm<bool>(
      context: context,
      title: l10n.cambiarEstatusEmpleadoDialogoTitulo,
      confirmLabel: l10n.cambiarEstatusEmpleadoBotonConfirmar,
      cancelLabel: l10n.cambiarEstatusEmpleadoBotonCancelar,
      contentBuilder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            nuevo == EstatusEmpleado.baja
                ? l10n.cambiarEstatusEmpleadoMensajeBaja
                : l10n.cambiarEstatusEmpleadoMensajeActivo,
            style: AppTypography.body,
          ),
          const SizedBox(height: AppSpacing.md),
          RisegTextField(label: l10n.cambiarEstatusEmpleadoCampoMotivo, controller: motivoController, autofocus: true),
        ],
      ),
      onConfirm: () async => true,
    );
    if (confirmado != true) {
      motivoController.dispose();
      return;
    }
    final motivo = motivoController.text.trim();
    motivoController.dispose();
    if (!mounted) return;

    setState(() => _procesando = true);
    final resultado = await ref
        .read(cambiarEstatusEmpleadoUseCaseProvider)
        .ejecutar(empleadoId: widget.empleadoId, nuevo: nuevo, motivo: motivo.isEmpty ? null : motivo);
    if (!mounted) return;
    setState(() => _procesando = false);

    switch (resultado) {
      case CambiarEstatusEmpleadoExitoso():
        RisegFeedback.showSuccess(context, l10n.cambiarEstatusEmpleadoExito);
        await _cargar();
        ref.read(empleadosListControllerProvider.notifier).recargar();
      case CambiarEstatusEmpleadoNoExiste():
      case CambiarEstatusEmpleadoYaEnEseEstatus():
      case CambiarEstatusEmpleadoErrorInesperado():
        RisegFeedback.showError(context, l10n.cambiarEstatusEmpleadoErrorInesperado);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;

    if (_cargando) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.empleadoExpedienteTitulo)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final empleado = _empleado;
    if (empleado == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.empleadoExpedienteTitulo)),
        body: RisegEmptyState(
          icon: Icons.error_outline,
          title: l10n.empleadosListadoCargaErrorTitulo,
          message: l10n.empleadosListadoCargaErrorMensaje,
        ),
      );
    }

    final cancelado = EstatusEmpleado.values.byName(empleado.estatus) == EstatusEmpleado.baja;

    return Scaffold(
      appBar: AppBar(title: Text(empleadoNombreCompleto(empleado))),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    GestureDetector(
                      onTap: _procesando ? null : _actualizarFotografia,
                      child: CircleAvatar(radius: 32, backgroundColor: colors.surfaceSunken, child: const Icon(Icons.person, size: 32)),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(empleadoNombreCompleto(empleado), style: AppTypography.heading2.copyWith(color: colors.textPrimary)),
                          Text(empleado.codigoEmpleado, style: AppTypography.body.copyWith(color: colors.textMuted)),
                        ],
                      ),
                    ),
                    RisegStatusBadge(
                      label: empleadoEstatusLabel(l10n, empleado.estatus),
                      tone: empleadoEstatusTono(empleado.estatus),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  spacing: AppSpacing.xs,
                  children: [
                    RisegButton(label: l10n.empleadoDetalleBotonCorregir, variant: RisegButtonVariant.secondary, onPressed: _corregir),
                    RisegButton(
                      label: cancelado ? l10n.empleadoDetalleBotonReactivar : l10n.empleadoDetalleBotonDarDeBaja,
                      variant: RisegButtonVariant.danger,
                      loading: _procesando,
                      onPressed: () => _cambiarEstatus(cancelado ? EstatusEmpleado.activo : EstatusEmpleado.baja),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xl),
                RisegCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.empleadoSeccionGeneral, style: AppTypography.heading3.copyWith(color: colors.textPrimary)),
                      const SizedBox(height: AppSpacing.sm),
                      CampoConsulta(label: l10n.empleadoCampoSexo, value: empleadoSexoLabelDetalle(l10n, empleado.sexo)),
                      const SizedBox(height: AppSpacing.sm),
                      Row(
                        children: [
                          Expanded(
                            child: CampoConsulta(
                              label: l10n.empleadoCampoFechaNacimiento,
                              value: _formatoFecha.format(empleado.fechaNacimiento),
                            ),
                          ),
                          Expanded(
                            child: CampoConsulta(
                              label: l10n.empleadoDetalleCampoEdad,
                              value: l10n.empleadoDetalleEdadAnios(calcularEdad(empleado.fechaNacimiento)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      CampoConsulta(label: l10n.empleadoCampoCurp, value: empleado.curp),
                      const SizedBox(height: AppSpacing.sm),
                      CampoConsulta(label: l10n.empleadoCampoRfc, value: empleado.rfc),
                      const SizedBox(height: AppSpacing.sm),
                      CampoConsulta(label: l10n.empleadoCampoNss, value: empleado.nss),
                      const SizedBox(height: AppSpacing.sm),
                      CampoConsulta(
                        label: l10n.empleadoCampoEstadoCivil,
                        value: empleadoEstadoCivilLabelDetalle(l10n, empleado.estadoCivil),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      CampoConsulta(label: l10n.empleadoCampoNacionalidad, value: empleado.nacionalidad),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                RisegCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.empleadoSeccionContacto, style: AppTypography.heading3.copyWith(color: colors.textPrimary)),
                      const SizedBox(height: AppSpacing.sm),
                      CampoConsulta(label: l10n.empleadoCampoTelefono, value: empleado.telefono),
                      const SizedBox(height: AppSpacing.sm),
                      CampoConsulta(label: l10n.empleadoCampoCorreoElectronico, value: empleado.correoElectronico),
                      const SizedBox(height: AppSpacing.sm),
                      CampoConsulta(label: l10n.empleadoCampoContactoEmergenciaNombre, value: empleado.contactoEmergenciaNombre),
                      const SizedBox(height: AppSpacing.sm),
                      CampoConsulta(label: l10n.empleadoCampoTelefonoEmergencia, value: empleado.telefonoEmergencia),
                      const SizedBox(height: AppSpacing.sm),
                      CampoConsulta(label: l10n.empleadoCampoParentescoEmergencia, value: empleado.parentescoEmergencia),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                RisegCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(l10n.empleadoSeccionDomicilio, style: AppTypography.heading3.copyWith(color: colors.textPrimary)),
                          ),
                          RisegButton(label: l10n.empleadoDetalleBotonEditar, variant: RisegButtonVariant.ghost, onPressed: _editarDomicilio),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      if (_domicilio == null)
                        Text(l10n.empleadoDetalleDomicilioSinCapturar, style: AppTypography.body.copyWith(color: colors.textMuted))
                      else ...[
                        CampoConsulta(
                          label: l10n.domicilioEmpleadoCampoCalle,
                          value: '${_domicilio!.calle} ${_domicilio!.numeroExterior}',
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        CampoConsulta(label: l10n.domicilioEmpleadoCampoColonia, value: _domicilio!.colonia),
                        const SizedBox(height: AppSpacing.sm),
                        CampoConsulta(
                          label: l10n.domicilioEmpleadoCampoMunicipio,
                          value: '${_domicilio!.municipioAlcaldia}, ${_domicilio!.estado} ${_domicilio!.codigoPostal}',
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                RisegCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.empleadoSeccionLaboral, style: AppTypography.heading3.copyWith(color: colors.textPrimary)),
                      const SizedBox(height: AppSpacing.sm),
                      CampoConsulta(label: l10n.empleadoCampoFechaIngreso, value: _formatoFecha.format(empleado.fechaIngreso)),
                      const SizedBox(height: AppSpacing.sm),
                      CampoConsulta(label: l10n.empleadoCampoPuesto, value: _puesto?.nombre),
                      const SizedBox(height: AppSpacing.sm),
                      CampoConsulta(label: l10n.empleadoCampoEmpresa, value: _empresa?.nombreComercial),
                      const SizedBox(height: AppSpacing.sm),
                      CampoConsulta(label: l10n.empleadoCampoSucursal, value: _sucursal?.nombre),
                      const SizedBox(height: AppSpacing.sm),
                      CampoConsulta(label: l10n.empleadoCampoObservaciones, value: empleado.observaciones),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                RisegCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.empleadoSeccionEscolaridad, style: AppTypography.heading3.copyWith(color: colors.textPrimary)),
                      const SizedBox(height: AppSpacing.sm),
                      CampoConsulta(
                        label: l10n.empleadoCampoNivelEstudios,
                        value: empleado.nivelEstudios == null ? null : empleadoNivelEstudiosLabel(l10n, empleado.nivelEstudios!),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      CampoConsulta(label: l10n.empleadoCampoObservacionesEscolaridad, value: empleado.observacionesEscolaridad),
                      const SizedBox(height: AppSpacing.lg),
                      Text(l10n.empleadoSeccionExperiencia, style: AppTypography.heading3.copyWith(color: colors.textPrimary)),
                      const SizedBox(height: AppSpacing.sm),
                      CampoConsulta(
                        label: l10n.empleadoDetalleCampoExperiencia,
                        value: empleado.mesesExperienciaAdicionales == null
                            ? l10n.empleadoDetalleExperienciaAnios(empleado.aniosExperienciaSeguridad)
                            : l10n.empleadoDetalleExperienciaAniosMeses(
                                empleado.aniosExperienciaSeguridad,
                                empleado.mesesExperienciaAdicionales!,
                              ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      CampoConsulta(label: l10n.empleadoCampoUltimoPuesto, value: empleado.ultimoPuestoDesempenado),
                      const SizedBox(height: AppSpacing.sm),
                      CampoConsulta(label: l10n.empleadoCampoResumenExperiencia, value: empleado.resumenExperiencia),
                      const SizedBox(height: AppSpacing.sm),
                      CampoConsulta(label: l10n.empleadoCampoObservacionesExperiencia, value: empleado.observacionesExperiencia),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                RisegCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.empleadoSeccionEvaluaciones, style: AppTypography.heading3.copyWith(color: colors.textPrimary)),
                      const SizedBox(height: AppSpacing.md),
                      Row(
                        children: [
                          Expanded(
                            child: Text(l10n.empleadoSeccionPerfilPsicologico, style: AppTypography.label),
                          ),
                          RisegButton(
                            label: empleado.fechaEvaluacionPsicologica == null
                                ? l10n.evaluacionEmpleadoBotonRegistrar
                                : l10n.empleadoDetalleBotonEditar,
                            variant: RisegButtonVariant.ghost,
                            onPressed: _registrarPerfilPsicologico,
                          ),
                        ],
                      ),
                      if (empleado.fechaEvaluacionPsicologica == null)
                        RisegStatusBadge(label: l10n.evaluacionEmpleadoPendiente, tone: RisegStatusTone.warning)
                      else ...[
                        CampoConsulta(
                          label: l10n.evaluacionEmpleadoCampoFecha,
                          value: _formatoFecha.format(empleado.fechaEvaluacionPsicologica!),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        CampoConsulta(label: l10n.perfilPsicologicoEmpleadoCampoResumen, value: empleado.resumenPsicologico),
                        const SizedBox(height: AppSpacing.sm),
                        CampoConsulta(label: l10n.evaluacionEmpleadoCampoObservaciones, value: empleado.observacionesPsicologico),
                      ],
                      const SizedBox(height: AppSpacing.lg),
                      Row(
                        children: [
                          Expanded(
                            child: Text(l10n.empleadoSeccionEstudioSocioeconomico, style: AppTypography.label),
                          ),
                          RisegButton(
                            label: empleado.fechaEstudioSocioeconomico == null
                                ? l10n.evaluacionEmpleadoBotonRegistrar
                                : l10n.empleadoDetalleBotonEditar,
                            variant: RisegButtonVariant.ghost,
                            onPressed: _registrarEstudioSocioeconomico,
                          ),
                        ],
                      ),
                      if (empleado.fechaEstudioSocioeconomico == null)
                        RisegStatusBadge(label: l10n.evaluacionEmpleadoPendiente, tone: RisegStatusTone.warning)
                      else ...[
                        CampoConsulta(
                          label: l10n.evaluacionEmpleadoCampoFecha,
                          value: _formatoFecha.format(empleado.fechaEstudioSocioeconomico!),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        CampoConsulta(
                          label: l10n.estudioSocioeconomicoEmpleadoCampoResumen,
                          value: empleado.resumenEstudioSocioeconomico,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        CampoConsulta(
                          label: l10n.evaluacionEmpleadoCampoObservaciones,
                          value: empleado.observacionesEstudioSocioeconomico,
                        ),
                      ],
                      const SizedBox(height: AppSpacing.lg),
                      Row(
                        children: [
                          Expanded(
                            child: Text(l10n.empleadoSeccionAntidoping, style: AppTypography.label),
                          ),
                          RisegButton(
                            label: empleado.fechaAntidoping == null
                                ? l10n.evaluacionEmpleadoBotonRegistrar
                                : l10n.empleadoDetalleBotonEditar,
                            variant: RisegButtonVariant.ghost,
                            onPressed: _registrarAntidoping,
                          ),
                        ],
                      ),
                      if (empleado.fechaAntidoping == null)
                        RisegStatusBadge(label: l10n.evaluacionEmpleadoPendiente, tone: RisegStatusTone.warning)
                      else ...[
                        CampoConsulta(
                          label: l10n.evaluacionEmpleadoCampoFecha,
                          value: _formatoFecha.format(empleado.fechaAntidoping!),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Wrap(
                          spacing: AppSpacing.xs,
                          runSpacing: AppSpacing.xs,
                          children: [
                            if (empleado.resultadoAmp != null)
                              RisegStatusBadge(
                                label: '${l10n.antidopingEmpleadoCampoAmp}: ${resultadoSustanciaAntidopingLabel(l10n, empleado.resultadoAmp!)}',
                                tone: resultadoSustanciaAntidopingTono(empleado.resultadoAmp!),
                              ),
                            if (empleado.resultadoBzd != null)
                              RisegStatusBadge(
                                label: '${l10n.antidopingEmpleadoCampoBzd}: ${resultadoSustanciaAntidopingLabel(l10n, empleado.resultadoBzd!)}',
                                tone: resultadoSustanciaAntidopingTono(empleado.resultadoBzd!),
                              ),
                            if (empleado.resultadoCoc != null)
                              RisegStatusBadge(
                                label: '${l10n.antidopingEmpleadoCampoCoc}: ${resultadoSustanciaAntidopingLabel(l10n, empleado.resultadoCoc!)}',
                                tone: resultadoSustanciaAntidopingTono(empleado.resultadoCoc!),
                              ),
                            if (empleado.resultadoMet != null)
                              RisegStatusBadge(
                                label: '${l10n.antidopingEmpleadoCampoMet}: ${resultadoSustanciaAntidopingLabel(l10n, empleado.resultadoMet!)}',
                                tone: resultadoSustanciaAntidopingTono(empleado.resultadoMet!),
                              ),
                            if (empleado.resultadoOpi != null)
                              RisegStatusBadge(
                                label: '${l10n.antidopingEmpleadoCampoOpi}: ${resultadoSustanciaAntidopingLabel(l10n, empleado.resultadoOpi!)}',
                                tone: resultadoSustanciaAntidopingTono(empleado.resultadoOpi!),
                              ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        CampoConsulta(label: l10n.evaluacionEmpleadoCampoObservaciones, value: empleado.observacionesAntidoping),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                RisegCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(l10n.empleadoSeccionDocumentacion, style: AppTypography.heading3.copyWith(color: colors.textPrimary)),
                          ),
                          RisegButton(label: l10n.empleadoDetalleBotonAdjuntar, variant: RisegButtonVariant.ghost, onPressed: _adjuntarDocumento),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      if (_documentos.isEmpty)
                        Text(l10n.empleadoDetalleDocumentosSinDocumentos, style: AppTypography.body.copyWith(color: colors.textMuted))
                      else
                        for (final documento in _documentos)
                          Padding(
                            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${categoriaDocumentoEmpleadoLabel(l10n, documento.categoria ?? 'otro')} · ${documento.originalFileName}',
                                  ),
                                ),
                                RisegButton(
                                  label: l10n.agendaAdjuntoBotonAbrir,
                                  variant: RisegButtonVariant.ghost,
                                  onPressed: () => ref.read(attachmentStorageProvider).abrir(documento.path),
                                ),
                              ],
                            ),
                          ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                RisegCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.empleadoSeccionHistorial, style: AppTypography.heading3.copyWith(color: colors.textPrimary)),
                      const SizedBox(height: AppSpacing.xs),
                      if (_eventos.isEmpty)
                        Text(l10n.complementoDetalleHistorialSinEventos, style: AppTypography.body.copyWith(color: colors.textMuted))
                      else
                        for (final evento in _eventos)
                          Padding(
                            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(_formatoFechaHora.format(evento.fechaHora), style: AppTypography.caption.copyWith(color: colors.textMuted)),
                                    const SizedBox(width: AppSpacing.xs),
                                    Text(_eventoLabel(l10n, evento.tipoEvento), style: AppTypography.label),
                                  ],
                                ),
                                if (evento.observacion != null && evento.observacion!.trim().isNotEmpty)
                                  Text(evento.observacion!, style: AppTypography.body.copyWith(color: colors.textMuted)),
                              ],
                            ),
                          ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String empleadoSexoLabelDetalle(AppLocalizations l10n, String valor) => empleadoSexoLabel(l10n, valor);

String empleadoEstadoCivilLabelDetalle(AppLocalizations l10n, String valor) => empleadoEstadoCivilLabel(l10n, valor);
