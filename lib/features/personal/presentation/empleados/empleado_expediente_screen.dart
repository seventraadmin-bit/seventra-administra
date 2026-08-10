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
import 'package:riseg_one/features/personal/domain/usecases/alerta_recontratacion_empleado.dart';
import 'package:riseg_one/features/personal/domain/usecases/asignacion_sueldo_con_vigencia.dart';
import 'package:riseg_one/features/personal/domain/usecases/calcular_ciclo_laboral_empleado.dart';
import 'package:riseg_one/features/personal/domain/usecases/calcular_edad.dart';

import '../../../organizacion/organizacion_providers.dart';
import '../../personal_providers.dart';
import 'empleados_list_controller.dart';
import 'empleados_list_screen.dart';
import 'widgets/actualizar_sueldo_asignacion_dialog.dart';
import 'widgets/adjuntar_documento_empleado_dialog.dart';
import 'widgets/antidoping_empleado_dialog.dart';
import 'widgets/asignar_servicio_empleado_dialog.dart';
import 'widgets/baja_laboral_empleado_dialog.dart';
import 'widgets/cambiar_servicio_empleado_dialog.dart';
import 'widgets/corregir_empleado_dialog.dart';
import 'widgets/crear_empleado_dialog.dart';
import 'widgets/domicilio_empleado_dialog.dart';
import 'widgets/estudio_socioeconomico_empleado_dialog.dart';
import 'widgets/generar_ficha_tecnica_empleado_dialog.dart';
import 'widgets/perfil_psicologico_empleado_dialog.dart';
import 'widgets/reingreso_empleado_dialog.dart';
import 'widgets/retirar_servicio_empleado_dialog.dart';

final _formatoFecha = DateFormat('dd/MM/yyyy');
final _formatoFechaHora = DateFormat('dd/MM/yyyy HH:mm');
final _formatoMonedaEmpleado = NumberFormat.currency(locale: 'es_MX', symbol: r'$');

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
  List<EmpleadoPeriodoLaboralData> _periodosArchivados = const [];
  AsignacionServicioData? _asignacionVigente;
  AsignacionServicioSueldoVigenciaData? _sueldoVigente;
  List<AsignacionServicioData> _historialAsignaciones = const [];
  Map<String, String> _serviciosPorId = const {};
  Map<String, String> _turnosPorId = const {};
  PuestoData? _puesto;
  EmpresaData? _empresa;
  SucursalData? _sucursal;
  String? _bancoNombre;
  List<FichaTecnicaEmpleadoData> _fichasTecnicas = const [];
  Map<String, String> _fichaTecnicaRutasPorAttachmentId = const {};
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
    // La fotografía y la Ficha técnica son Attachments más (categorías
    // `fotografia`/`fichaTecnica`, fuera de `CategoriaDocumentoEmpleado`)
    // pero cada una se muestra en su propia sección — nunca deben
    // listarse aquí como si fueran documentos del expediente.
    final documentos = (await ref.read(attachmentRepositoryProvider).listarActivosPorEmpleado(widget.empleadoId))
        .where((d) => d.categoria != 'fotografia' && d.categoria != 'fichaTecnica')
        .toList();
    final eventos = await empleadoRepo.listarEventos(widget.empleadoId);
    final periodosArchivados = await empleadoRepo.listarPeriodosLaboralesArchivados(widget.empleadoId);
    final fichasTecnicas = await ref.read(fichaTecnicaEmpleadoRepositoryProvider).listarPorEmpleado(widget.empleadoId);
    final fichaTecnicaRutasPorAttachmentId = <String, String>{};
    for (final ficha in fichasTecnicas) {
      final adjunto = await ref.read(attachmentRepositoryProvider).obtenerPorId(ficha.attachmentId);
      if (adjunto != null) fichaTecnicaRutasPorAttachmentId[ficha.attachmentId] = adjunto.path;
    }

    // Asignación a Servicio (Etapa 5D) — solo consulta desde aquí, nunca
    // duplica nombre de Servicio/Turno: se resuelve contra sus propios
    // repositorios.
    final asignacionRepo = ref.read(asignacionServicioRepositoryProvider);
    final asignacionVigente = await asignacionRepo.obtenerActivaPorEmpleado(widget.empleadoId);
    final historialAsignaciones = await asignacionRepo.listarPorEmpleado(widget.empleadoId);
    // Sueldo/bono acordado de la asignación vigente (Etapa 6B, ajuste
    // funcional final) — se muestra tal cual junto con Servicio/Turno,
    // nunca duplicado en Empleado.
    AsignacionServicioSueldoVigenciaData? sueldoVigente;
    if (asignacionVigente != null) {
      final vigenciasSueldo = await asignacionRepo.listarVigenciasSueldoActivas(asignacionVigente.id);
      sueldoVigente = clasificarVigenciasSueldo(vigenciasSueldo, DateTime.now()).vigente;
    }

    final serviciosPorId = <String, String>{};
    for (final servicioId in historialAsignaciones.map((a) => a.servicioId).toSet()) {
      final servicio = await ref.read(servicioRepositoryProvider).obtenerPorId(servicioId);
      if (servicio != null) serviciosPorId[servicioId] = servicio.nombre;
    }
    final turnosPorId = <String, String>{};
    final turnoIds = historialAsignaciones.map((a) => a.turnoId).whereType<String>().toSet();
    if (turnoIds.isNotEmpty) {
      final modalidades = await ref.read(catalogoRepositoryProvider).listarModalidadesTurno();
      for (final m in modalidades) {
        if (turnoIds.contains(m.id)) turnosPorId[m.id] = m.nombre;
      }
    }

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
    String? bancoNombre;
    if (empleado?.bancoId != null) {
      final bancos = await ref.read(catalogoRepositoryProvider).listarBancos();
      for (final b in bancos) {
        if (b.id == empleado!.bancoId) bancoNombre = b.nombre;
      }
    }

    if (!mounted) return;
    setState(() {
      _empleado = empleado;
      _domicilio = domicilio;
      _documentos = documentos;
      _eventos = eventos;
      _periodosArchivados = periodosArchivados;
      _asignacionVigente = asignacionVigente;
      _sueldoVigente = sueldoVigente;
      _historialAsignaciones = historialAsignaciones;
      _serviciosPorId = serviciosPorId;
      _turnosPorId = turnosPorId;
      _puesto = puesto;
      _empresa = empresa;
      _sucursal = sucursal;
      _bancoNombre = bancoNombre;
      _fichasTecnicas = fichasTecnicas;
      _fichaTecnicaRutasPorAttachmentId = fichaTecnicaRutasPorAttachmentId;
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
      TipoEventoEmpleado.bajaLaboral => l10n.empleadoDetalleHistorialEventoBajaLaboral,
      TipoEventoEmpleado.reingreso => l10n.empleadoDetalleHistorialEventoReingreso,
      TipoEventoEmpleado.asignacionServicio => l10n.empleadoDetalleHistorialEventoAsignacionServicio,
      TipoEventoEmpleado.cambioServicio => l10n.empleadoDetalleHistorialEventoCambioServicio,
      TipoEventoEmpleado.retiroServicio => l10n.empleadoDetalleHistorialEventoRetiroServicio,
      TipoEventoEmpleado.fichaTecnicaGenerada => l10n.empleadoDetalleHistorialEventoFichaTecnicaGenerada,
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

  Future<void> _generarFichaTecnica() async {
    final generada = await mostrarDialogoGenerarFichaTecnicaEmpleado(
      context,
      ref,
      empleado: _empleado!,
      domicilio: _domicilio,
      asignacionVigente: _asignacionVigente,
    );
    if (generada) await _cargar();
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

  Future<void> _registrarBajaLaboral() async {
    final actualizo = await mostrarDialogoBajaLaboralEmpleado(context, ref, _empleado!);
    if (actualizo) {
      await _cargar();
      ref.read(empleadosListControllerProvider.notifier).recargar();
    }
  }

  Future<void> _registrarReingreso() async {
    final alerta = calcularAlertaRecontratacion(_empleado!, _periodosArchivados);
    final actualizo = await mostrarDialogoReingresoEmpleado(context, ref, _empleado!, alerta);
    if (actualizo) {
      await _cargar();
      ref.read(empleadosListControllerProvider.notifier).recargar();
    }
  }

  Future<void> _asignarServicio() async {
    final actualizo = await mostrarDialogoAsignarServicioEmpleado(context, ref, _empleado!);
    if (actualizo) await _cargar();
  }

  Future<void> _cambiarServicio() async {
    final actualizo = await mostrarDialogoCambiarServicioEmpleado(context, ref, _empleado!, _asignacionVigente!.servicioId);
    if (actualizo) await _cargar();
  }

  Future<void> _retirarServicio() async {
    final actualizo = await mostrarDialogoRetirarServicioEmpleado(context, ref, _empleado!);
    if (actualizo) await _cargar();
  }

  Future<void> _actualizarSueldoAsignacion() async {
    final actualizo = await mostrarDialogoActualizarSueldoAsignacion(context, ref, _asignacionVigente!);
    if (actualizo) await _cargar();
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
    final cicloLaboral = calcularCicloLaboralEmpleado(empleado);

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
                          Text(
                            l10n.empleadoDetalleNumeroEmpleado(empleado.numeroEmpleado),
                            style: AppTypography.body.copyWith(color: colors.textMuted),
                          ),
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
                    if (cancelado)
                      RisegButton(
                        label: l10n.empleadoDetalleBotonRegistrarReingreso,
                        variant: RisegButtonVariant.primary,
                        onPressed: _registrarReingreso,
                      )
                    else
                      RisegButton(
                        label: l10n.empleadoDetalleBotonDarDeBaja,
                        variant: RisegButtonVariant.danger,
                        onPressed: _registrarBajaLaboral,
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
                      CampoConsulta(label: l10n.empleadoCampoCodigoPostalFiscal, value: empleado.codigoPostalFiscal),
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
                      Text(l10n.empleadoSeccionDatosBancarios, style: AppTypography.heading3.copyWith(color: colors.textPrimary)),
                      const SizedBox(height: AppSpacing.sm),
                      CampoConsulta(label: l10n.empleadoCampoBanco, value: _bancoNombre),
                      const SizedBox(height: AppSpacing.sm),
                      CampoConsulta(label: l10n.empleadoCampoNumeroCuentaTarjeta, value: empleado.numeroCuentaTarjeta),
                      const SizedBox(height: AppSpacing.sm),
                      CampoConsulta(label: l10n.empleadoCampoClabe, value: empleado.clabe),
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
                      // Sueldo/bono administrativo — solo tienen sentido
                      // sin AsignacionServicio vigente (ver doc comment
                      // de `Empleado.sueldoMensualAdministrativo`); con
                      // asignación vigente, esos datos vienen de ahí
                      // (Etapa 6B, expediente de esa asignación).
                      if (_asignacionVigente == null) ...[
                        const SizedBox(height: AppSpacing.sm),
                        CampoConsulta(
                          label: l10n.empleadoCampoSueldoMensualAdministrativo,
                          value: empleado.sueldoMensualAdministrativo == null
                              ? null
                              : _formatoMonedaEmpleado.format(empleado.sueldoMensualAdministrativo! / 100),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        CampoConsulta(
                          label: l10n.empleadoCampoBonoMensualAdministrativo,
                          value: empleado.bonoMensualAdministrativo == null
                              ? null
                              : _formatoMonedaEmpleado.format(empleado.bonoMensualAdministrativo! / 100),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.sm),
                      CampoConsulta(label: l10n.empleadoCampoObservaciones, value: empleado.observaciones),
                      const SizedBox(height: AppSpacing.sm),
                      Row(
                        children: [
                          Expanded(
                            child: CampoConsulta(
                              label: l10n.empleadoCampoAntiguedad,
                              value: l10n.empleadoDetalleAntiguedadAniosMeses(cicloLaboral.antiguedadAnios, cicloLaboral.antiguedadMeses),
                            ),
                          ),
                          Expanded(
                            child: CampoConsulta(
                              label: l10n.empleadoCampoDiasLaborados,
                              value: l10n.empleadoDetalleDiasLaborados(cicloLaboral.diasLaborados),
                            ),
                          ),
                        ],
                      ),
                      if (cicloLaboral.fechaProximoAniversario != null) ...[
                        const SizedBox(height: AppSpacing.sm),
                        CampoConsulta(
                          label: l10n.empleadoCampoProximoAniversario,
                          value: _formatoFecha.format(cicloLaboral.fechaProximoAniversario!),
                        ),
                      ],
                      if (cancelado) ...[
                        const SizedBox(height: AppSpacing.sm),
                        CampoConsulta(label: l10n.empleadoCampoFechaBaja, value: _formatoFecha.format(empleado.fechaBaja!)),
                        const SizedBox(height: AppSpacing.sm),
                        CampoConsulta(
                          label: l10n.empleadoCampoMotivoBaja,
                          value: motivoBajaEmpleadoLabel(l10n, empleado.motivoBaja!),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        CampoConsulta(label: l10n.empleadoCampoObservacionesBaja, value: empleado.observacionesBaja),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                RisegCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.empleadoSeccionHistorialLaboral, style: AppTypography.heading3.copyWith(color: colors.textPrimary)),
                      const SizedBox(height: AppSpacing.xs),
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${_formatoFecha.format(empleado.fechaIngreso)} — '
                                '${cancelado ? _formatoFecha.format(empleado.fechaBaja!) : l10n.empleadoHistorialLaboralActivo}',
                              ),
                            ),
                            if (cancelado) Text(motivoBajaEmpleadoLabel(l10n, empleado.motivoBaja!), style: AppTypography.caption.copyWith(color: colors.textMuted)),
                          ],
                        ),
                      ),
                      for (final periodo in _periodosArchivados)
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text('${_formatoFecha.format(periodo.fechaIngreso)} — ${_formatoFecha.format(periodo.fechaBaja)}'),
                              ),
                              Text(motivoBajaEmpleadoLabel(l10n, periodo.motivoBaja), style: AppTypography.caption.copyWith(color: colors.textMuted)),
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
                      Row(
                        children: [
                          Expanded(
                            child: Text(l10n.empleadoSeccionAsignacionServicio, style: AppTypography.heading3.copyWith(color: colors.textPrimary)),
                          ),
                          if (_asignacionVigente == null)
                            RisegButton(
                              label: l10n.empleadoBotonAsignarServicio,
                              variant: RisegButtonVariant.ghost,
                              onPressed: _asignarServicio,
                            )
                          else
                            Wrap(
                              spacing: AppSpacing.xs,
                              children: [
                                RisegButton(
                                  label: l10n.empleadoBotonActualizarSueldo,
                                  variant: RisegButtonVariant.ghost,
                                  onPressed: _actualizarSueldoAsignacion,
                                ),
                                RisegButton(
                                  label: l10n.empleadoBotonCambiarServicio,
                                  variant: RisegButtonVariant.ghost,
                                  onPressed: _cambiarServicio,
                                ),
                                RisegButton(
                                  label: l10n.empleadoBotonRetirarServicio,
                                  variant: RisegButtonVariant.ghost,
                                  onPressed: _retirarServicio,
                                ),
                              ],
                            ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      if (_asignacionVigente == null)
                        Text(l10n.empleadoSinServicioAsignado, style: AppTypography.body.copyWith(color: colors.textMuted))
                      else ...[
                        Text(
                          _serviciosPorId[_asignacionVigente!.servicioId] ?? _asignacionVigente!.servicioId,
                          style: AppTypography.label,
                        ),
                        Text(
                          l10n.empleadoAsignacionDesde(_formatoFecha.format(_asignacionVigente!.fechaInicio)),
                          style: AppTypography.body.copyWith(color: colors.textMuted),
                        ),
                        if (_asignacionVigente!.turnoId != null)
                          Text(
                            _turnosPorId[_asignacionVigente!.turnoId] ?? _asignacionVigente!.turnoId!,
                            style: AppTypography.caption.copyWith(color: colors.textMuted),
                          ),
                        if (_sueldoVigente != null)
                          Text(
                            l10n.empleadoAsignacionSueldoBono(
                              _formatoMonedaEmpleado.format(_sueldoVigente!.sueldoMensual / 100),
                              _formatoMonedaEmpleado.format(_sueldoVigente!.bonoMensual / 100),
                            ),
                            style: AppTypography.caption.copyWith(color: colors.textMuted),
                          ),
                      ],
                      if (_historialAsignaciones.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.md),
                        Text(l10n.empleadoSeccionHistorialAsignaciones, style: AppTypography.label),
                        const SizedBox(height: AppSpacing.xs),
                        for (final asignacion in _historialAsignaciones)
                          Padding(
                            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                            child: Text(
                              '${_serviciosPorId[asignacion.servicioId] ?? asignacion.servicioId} — '
                              '${_formatoFecha.format(asignacion.fechaInicio)} '
                              '${asignacion.fechaTermino == null ? l10n.empleadoAsignacionActual : 'al ${_formatoFecha.format(asignacion.fechaTermino!)}'}',
                              style: AppTypography.body.copyWith(color: colors.textMuted),
                            ),
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
                      Row(
                        children: [
                          Expanded(
                            child: Text(l10n.fichaTecnicaSeccionTitulo, style: AppTypography.heading3.copyWith(color: colors.textPrimary)),
                          ),
                          RisegButton(
                            label: l10n.fichaTecnicaBotonGenerar,
                            variant: RisegButtonVariant.ghost,
                            onPressed: _procesando ? null : _generarFichaTecnica,
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      if (_fichasTecnicas.isEmpty)
                        Text(l10n.fichaTecnicaSinFichas, style: AppTypography.body.copyWith(color: colors.textMuted))
                      else
                        for (final ficha in _fichasTecnicas)
                          Padding(
                            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text('${ficha.folio} · ${_formatoFechaHora.format(ficha.createdAt)}'),
                                ),
                                RisegButton(
                                  label: l10n.agendaAdjuntoBotonAbrir,
                                  variant: RisegButtonVariant.ghost,
                                  onPressed: () {
                                    final ruta = _fichaTecnicaRutasPorAttachmentId[ficha.attachmentId];
                                    if (ruta != null) ref.read(attachmentStorageProvider).abrir(ruta);
                                  },
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
