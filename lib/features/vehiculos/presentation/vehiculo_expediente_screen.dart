import 'package:riseg_one/features/notificaciones/presentation/notificaciones_controller.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/inventario/presentation/articulos/articulos_list_screen.dart' show formatoCosto;
import 'package:riseg_one/features/organizacion/organizacion_providers.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';
import 'package:riseg_one/features/usuarios/usuarios_providers.dart' show permissionServiceProvider;
import 'package:riseg_one/features/vehiculos/data/tables/vehiculo_documento_table.dart';
import 'package:riseg_one/features/vehiculos/data/tables/vehiculo_mantenimiento_table.dart';
import 'package:riseg_one/features/finanzas/finanzas_providers.dart'
    show cuentaFinancieraRepositoryProvider, deudaRepositoryProvider, egresoRepositoryProvider;
import 'package:riseg_one/features/vehiculos/data/tables/vehiculo_table.dart' show MotivoBajaVehiculo;
import 'package:riseg_one/features/vehiculos/domain/usecases/actualizar_fotografia_vehiculo_usecase.dart';
import 'package:riseg_one/features/vehiculos/domain/usecases/agrupar_documentos_vehiculo.dart';
import 'package:riseg_one/features/vehiculos/domain/usecases/calcular_costos_vehiculo.dart';
import 'package:riseg_one/features/vehiculos/domain/usecases/calcular_estado_vigencia_documento.dart';
import 'package:riseg_one/features/vehiculos/domain/usecases/calcular_proximo_mantenimiento.dart';
import 'package:riseg_one/features/vehiculos/domain/usecases/cambiar_estatus_vehiculo_usecase.dart';
import 'package:riseg_one/features/vehiculos/domain/usecases/finalizar_mantenimiento_vehiculo_usecase.dart';

import 'vehiculo_labels.dart';
import 'vehiculos_controller.dart';
import '../vehiculos_providers.dart';
import 'widgets/asignar_vehiculo_dialog.dart';
import 'widgets/cambiar_asignacion_vehiculo_dialog.dart';
import 'widgets/dar_de_baja_vehiculo_dialog.dart';
import 'widgets/eliminar_vehiculo_fisicamente_dialog.dart';
import 'widgets/gestionar_vehiculo_dialog.dart';
import 'widgets/historial_documento_vehiculo_dialog.dart';
import 'widgets/registrar_documento_vehiculo_dialog.dart';
import 'widgets/registrar_kilometraje_vehiculo_dialog.dart';
import 'widgets/anular_mantenimiento_vehiculo_dialog.dart';
import 'widgets/corregir_documento_vehiculo_dialog.dart';
import 'widgets/corregir_mantenimiento_vehiculo_dialog.dart';
import 'widgets/registrar_mantenimiento_vehiculo_dialog.dart';
import 'widgets/retirar_asignacion_vehiculo_dialog.dart';

enum _FiltroMantenimiento { todos, mantenimiento, incidencias }

final _formatoFecha = DateFormat('dd/MM/yyyy');

/// Expediente de un Vehículo (Etapa 8B) — una sola pantalla desplazable
/// con secciones, sin pestañas internas (mismo criterio que
/// `ArticuloExpedienteScreen`/`EmpleadoExpedienteScreen`). Documentos/
/// Mantenimiento/Historial de costos llegan en etapas futuras (8C-8E).
class VehiculoExpedienteScreen extends ConsumerStatefulWidget {
  const VehiculoExpedienteScreen({required this.vehiculoId, super.key});

  final String vehiculoId;

  @override
  ConsumerState<VehiculoExpedienteScreen> createState() => _VehiculoExpedienteScreenState();
}

class _VehiculoExpedienteScreenState extends ConsumerState<VehiculoExpedienteScreen> {
  VehiculoData? _vehiculo;
  AsignacionVehiculoData? _asignacionVigente;
  List<AsignacionVehiculoData> _historialAsignaciones = const [];
  Map<String, String> _empleadosPorId = const {};
  Map<String, String> _serviciosPorId = const {};
  VehiculoKilometrajeData? _kilometrajeActual;
  List<VehiculoKilometrajeData> _historialKilometraje = const [];
  List<VehiculoDocumentoData> _documentos = const [];
  Map<String, AttachmentData> _adjuntoPorDocumento = const {};
  List<VehiculoMantenimientoData> _mantenimientos = const [];
  Map<String, AttachmentData> _comprobantePorMantenimiento = const {};

  /// Nombre legible del origen financiero de cada mantenimiento con
  /// costo (schemaVersion 80) — "BBVA Empresarial", "TDC Konfío".
  /// Se resuelve aquí, una sola vez por carga, en vez de por celda:
  /// la tabla del expediente no debe disparar consultas al pintar.
  Map<String, String> _origenPorMantenimiento = const {};
  _FiltroMantenimiento _filtroMantenimiento = _FiltroMantenimiento.todos;
  bool _cargando = true;
  bool _procesando = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    final vehiculo = await ref.read(vehiculosControllerProvider.notifier).obtenerVehiculo(widget.vehiculoId);

    final asignacionRepo = ref.read(asignacionVehiculoRepositoryProvider);
    final kilometrajeRepo = ref.read(vehiculoKilometrajeRepositoryProvider);
    final opciones = ref.read(obtenerOpcionesAsignacionVehiculoUseCaseProvider);
    final documentoRepo = ref.read(vehiculoDocumentoRepositoryProvider);
    final attachmentRepo = ref.read(attachmentRepositoryProvider);
    final mantenimientoRepo = ref.read(vehiculoMantenimientoRepositoryProvider);

    final asignacionVigente = await asignacionRepo.obtenerActivaPorVehiculo(widget.vehiculoId);
    final historialAsignaciones = await asignacionRepo.listarPorVehiculo(widget.vehiculoId);
    final empleados = await opciones.obtenerEmpleados();
    final servicios = await opciones.obtenerServicios();
    final kilometrajeActual = await kilometrajeRepo.obtenerActual(widget.vehiculoId);
    final historialKilometraje = await kilometrajeRepo.listarPorVehiculo(widget.vehiculoId);
    final documentos = await documentoRepo.listarPorVehiculo(widget.vehiculoId);
    final mantenimientos = await mantenimientoRepo.listarPorVehiculo(widget.vehiculoId);

    final adjuntoPorDocumento = <String, AttachmentData>{};
    for (final documento in documentosVigentesPorTipo(documentos)) {
      final adjuntos = await attachmentRepo.listarActivosPorVehiculoDocumento(documento.id);
      if (adjuntos.isNotEmpty) adjuntoPorDocumento[documento.id] = adjuntos.first;
    }

    // Catálogos de origen, leídos una vez: el nombre de la cuenta o de
    // la tarjeta de la que salió cada gasto.
    final cuentas = await ref.read(cuentaFinancieraRepositoryProvider).listar();
    final tarjetas = await ref.read(deudaRepositoryProvider).listarTarjetasActivas();
    final egresoRepo = ref.read(egresoRepositoryProvider);
    final nombreCuenta = {for (final c in cuentas) c.id: c.nombre};
    final nombreTarjeta = {for (final t in tarjetas) t.id: t.nombre};

    final origenPorMantenimiento = <String, String>{};
    for (final registro in mantenimientos) {
      if (registro.deudaId != null) {
        origenPorMantenimiento[registro.id] = nombreTarjeta[registro.deudaId] ?? registro.deudaId!;
      } else if (registro.egresoId != null) {
        final egreso = await egresoRepo.obtenerPorId(registro.egresoId!);
        final cuentaId = egreso?.cuentaFinancieraId;
        if (cuentaId != null) origenPorMantenimiento[registro.id] = nombreCuenta[cuentaId] ?? cuentaId;
      }
    }

    final comprobantePorMantenimiento = <String, AttachmentData>{};
    for (final registro in mantenimientos) {
      final adjuntos = await attachmentRepo.listarActivosPorVehiculoMantenimiento(registro.id);
      if (adjuntos.isNotEmpty) comprobantePorMantenimiento[registro.id] = adjuntos.first;
    }

    if (!mounted) return;
    setState(() {
      _vehiculo = vehiculo;
      _asignacionVigente = asignacionVigente;
      _historialAsignaciones = historialAsignaciones;
      _empleadosPorId = {for (final e in empleados) e.id: e.nombre};
      _serviciosPorId = {for (final s in servicios) s.id: s.nombre};
      _kilometrajeActual = kilometrajeActual;
      _historialKilometraje = historialKilometraje;
      _documentos = documentos;
      _adjuntoPorDocumento = adjuntoPorDocumento;
      _mantenimientos = mantenimientos;
      _comprobantePorMantenimiento = comprobantePorMantenimiento;
      _origenPorMantenimiento = origenPorMantenimiento;
      _cargando = false;
    });
  }

  String _destino(AsignacionVehiculoData asignacion) {
    return destinoAsignacionVehiculoLabel(asignacion, empleadosPorId: _empleadosPorId, serviciosPorId: _serviciosPorId);
  }

  Future<void> _asignar() async {
    final asignado = await mostrarDialogoAsignarVehiculo(context, ref, widget.vehiculoId);
    if (asignado) await _cargar();
  }

  Future<void> _cambiarAsignacion() async {
    final cambiado = await mostrarDialogoCambiarAsignacionVehiculo(context, ref, _asignacionVigente!);
    if (cambiado) await _cargar();
  }

  Future<void> _retirarAsignacion() async {
    final retirado = await mostrarDialogoRetirarAsignacionVehiculo(context, ref, _asignacionVigente!);
    if (retirado) await _cargar();
  }

  Future<void> _registrarKilometraje() async {
    final registrado = await mostrarDialogoRegistrarKilometrajeVehiculo(context, ref, widget.vehiculoId);
    if (registrado) await _cargar();
  }

  Future<void> _agregarDocumento() async {
    final registrado = await mostrarDialogoRegistrarDocumentoVehiculo(context, ref, widget.vehiculoId);
    if (!registrado) return;
    await _cargar();
    _avisarALaCampana();
  }

  /// Verificación y tenencia/refrendo del Centro de notificaciones salen
  /// de estos documentos. Su contador está siempre a la vista y sólo se
  /// recalculaba al abrir la campana: registrar o corregir un documento
  /// que vence pronto no movía el número.
  void _avisarALaCampana() => ref.invalidate(notificacionesControllerProvider);

  Future<void> _renovarDocumento(VehiculoDocumentoData documento) async {
    final registrado = await mostrarDialogoRegistrarDocumentoVehiculo(
      context,
      ref,
      widget.vehiculoId,
      tipoPreseleccionado: TipoDocumentoVehiculo.values.byName(documento.tipo),
    );
    if (registrado) await _cargar();
  }

  Future<void> _corregirDocumento(VehiculoDocumentoData documento) async {
    final corregido = await mostrarDialogoCorregirDocumentoVehiculo(context, ref, documento);
    if (!corregido || !mounted) return;
    await _cargar();
    _avisarALaCampana();
  }

  Future<void> _verHistorialDocumento(String tipo) async {
    final documentosDelTipo = _documentos.where((d) => d.tipo == tipo).toList();
    await mostrarDialogoHistorialDocumentoVehiculo(context, ref, documentosDelTipo);
  }

  bool _estaAnulado(VehiculoMantenimientoData m) => m.estatus == EstatusMantenimientoVehiculo.cancelado.name;

  Future<void> _corregirMantenimiento(VehiculoMantenimientoData registro) async {
    final corregido = await mostrarDialogoCorregirMantenimientoVehiculo(context, ref, registro);
    if (corregido && mounted) await _cargar();
  }

  Future<void> _anularMantenimiento(VehiculoMantenimientoData registro) async {
    final anulado = await mostrarDialogoAnularMantenimientoVehiculo(context, ref, registro);
    if (anulado && mounted) await _cargar();
  }

  Future<void> _registrarMantenimiento() async {
    final registrado = await mostrarDialogoRegistrarMantenimientoVehiculo(context, ref, widget.vehiculoId);
    if (registrado) await _cargar();
  }

  Future<void> _finalizarMantenimiento() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _procesando = true);
    final resultado = await ref
        .read(vehiculosControllerProvider.notifier)
        .finalizarMantenimiento(vehiculoId: widget.vehiculoId);
    if (!mounted) return;
    setState(() => _procesando = false);
    switch (resultado) {
      case FinalizarMantenimientoVehiculoExitoso():
        RisegFeedback.showSuccess(context, l10n.vehiculoExpedienteEstatusActualizado);
        await _cargar();
      case FinalizarMantenimientoVehiculoNoExiste():
      case FinalizarMantenimientoVehiculoNoEstaEnMantenimiento():
      case FinalizarMantenimientoVehiculoErrorInesperado():
        RisegFeedback.showError(context, l10n.vehiculoErrorInesperado);
    }
  }

  Future<void> _editar() async {
    final editado = await mostrarDialogoGestionarVehiculo(context, ref, vehiculo: _vehiculo);
    if (editado) await _cargar();
  }

  Future<void> _cambiarEstatus(String estatus) async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _procesando = true);
    final resultado = await ref
        .read(vehiculosControllerProvider.notifier)
        .cambiarEstatus(vehiculoId: widget.vehiculoId, estatus: estatus);
    if (!mounted) return;
    setState(() => _procesando = false);
    switch (resultado) {
      case CambiarEstatusVehiculoExitoso():
        RisegFeedback.showSuccess(context, l10n.vehiculoExpedienteEstatusActualizado);
        await _cargar();
      case CambiarEstatusVehiculoNoExiste():
      case CambiarEstatusVehiculoDestinoInvalido():
      case CambiarEstatusVehiculoYaDeBaja():
      case CambiarEstatusVehiculoErrorInesperado():
        RisegFeedback.showError(context, l10n.vehiculoErrorInesperado);
    }
  }

  Future<void> _darDeBaja() async {
    final vehiculo = _vehiculo!;
    final dado = await mostrarDialogoDarDeBajaVehiculo(context, ref, vehiculo);
    if (dado) await _cargar();
  }

  Future<void> _eliminarFisicamente() async {
    final eliminado = await mostrarDialogoEliminarVehiculoFisicamente(context, ref, widget.vehiculoId);
    if (!eliminado) return;
    // La eliminacion fisica no pasa por ningun controlador: sin esto el
    // renglon sobrevive en el listado de Vehiculos hasta que algo ajeno (cambiar de
    // pestana) reconstruya el provider. Navegar no es refrescar.
    ref.invalidate(vehiculosControllerProvider);
    if (mounted) context.pop();
  }

  Future<void> _cambiarFotografia() async {
    final l10n = AppLocalizations.of(context)!;
    final seleccion = await FilePicker.platform.pickFiles(type: FileType.image);
    final archivo = seleccion?.files.singleOrNull;
    if (archivo?.path == null) return;
    if (!mounted) return;

    setState(() => _procesando = true);
    final resultado = await ref
        .read(vehiculosControllerProvider.notifier)
        .actualizarFotografia(
          vehiculoId: widget.vehiculoId,
          sourceFilePath: archivo!.path!,
          originalFileName: archivo.name,
          mimeType: 'image/${archivo.extension ?? 'jpeg'}',
        );
    if (!mounted) return;
    setState(() => _procesando = false);

    switch (resultado) {
      case ActualizarFotografiaVehiculoExitoso():
        RisegFeedback.showSuccess(context, l10n.vehiculoExpedienteFotografiaActualizada);
        await _cargar();
      case ActualizarFotografiaVehiculoNoExiste():
      case ActualizarFotografiaVehiculoErrorInesperado():
        RisegFeedback.showError(context, l10n.vehiculoErrorInesperado);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;

    if (_cargando) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final vehiculo = _vehiculo;
    if (vehiculo == null) {
      return Scaffold(
        appBar: AppBar(),
        body: RisegEmptyState(title: l10n.vehiculosListadoCargaErrorTitulo, message: ''),
      );
    }

    final esBaja = vehiculo.estatus == 'baja';
    final esMaestro = ref.watch(sesionControllerProvider)?.esMaestro ?? false;

    return Scaffold(
      appBar: AppBar(title: Text('${vehiculo.marca} ${vehiculo.modelo}')),
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
                      onTap: _procesando || esBaja ? null : _cambiarFotografia,
                      child: CircleAvatar(
                        radius: 32,
                        backgroundColor: colors.surfaceSunken,
                        child: const Icon(Icons.directions_car_outlined, size: 32),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${vehiculo.marca} ${vehiculo.modelo}',
                            style: AppTypography.heading2.copyWith(color: colors.textPrimary),
                          ),
                          Text(vehiculo.codigo, style: AppTypography.body.copyWith(color: colors.textMuted)),
                        ],
                      ),
                    ),
                    RisegStatusBadge(
                      label: estatusVehiculoLabel(l10n, vehiculo.estatus),
                      tone: estatusVehiculoTono(vehiculo.estatus),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  children: [
                    RisegButton(
                      label: l10n.vehiculoExpedienteBotonEditar,
                      variant: RisegButtonVariant.secondary,
                      onPressed: esBaja ? null : _editar,
                    ),
                    if (!esBaja && vehiculo.estatus != 'enMantenimiento')
                      RisegButton(
                        label: l10n.vehiculoExpedienteBotonEnMantenimiento,
                        variant: RisegButtonVariant.ghost,
                        onPressed: () => _cambiarEstatus('enMantenimiento'),
                      ),
                    if (!esBaja && vehiculo.estatus != 'fueraDeServicio')
                      RisegButton(
                        label: l10n.vehiculoExpedienteBotonFueraDeServicio,
                        variant: RisegButtonVariant.ghost,
                        onPressed: () => _cambiarEstatus('fueraDeServicio'),
                      ),
                    // Al salir de mantenimiento, el destino se calcula
                    // (asignado si hay una AsignacionVehiculo vigente,
                    // disponible si no) en vez de un botón crudo "marcar
                    // disponible" — ver el doc comment de
                    // `FinalizarMantenimientoVehiculoUseCase` (punto 3,
                    // Etapa 8D: "no quiero que los estados queden
                    // inconsistentes").
                    if (!esBaja && vehiculo.estatus == 'enMantenimiento')
                      RisegButton(
                        label: l10n.vehiculoExpedienteBotonFinalizarMantenimiento,
                        variant: RisegButtonVariant.ghost,
                        onPressed: _finalizarMantenimiento,
                      )
                    else if (!esBaja && vehiculo.estatus != 'disponible')
                      RisegButton(
                        label: l10n.vehiculoExpedienteBotonDisponible,
                        variant: RisegButtonVariant.ghost,
                        onPressed: () => _cambiarEstatus('disponible'),
                      ),
                    if (!esBaja)
                      RisegButton(
                        label: l10n.vehiculoExpedienteBotonDarDeBaja,
                        variant: RisegButtonVariant.danger,
                        onPressed: _darDeBaja,
                      ),
                    if (esMaestro)
                      RisegButton(
                        label: l10n.eliminacionFisicaAccionMenu,
                        variant: RisegButtonVariant.danger,
                        onPressed: _eliminarFisicamente,
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xl),
                RisegCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.vehiculoExpedienteSeccionDatosGenerales, style: AppTypography.heading3),
                      const SizedBox(height: AppSpacing.sm),
                      _campo(l10n.vehiculoCampoTipoVehiculo, tipoVehiculoLabel(l10n, vehiculo.tipoVehiculo)),
                      _campo(l10n.vehiculoCampoAnio, vehiculo.anio?.toString() ?? '—'),
                      _campo(l10n.vehiculoCampoColor, vehiculo.color ?? '—'),
                      _campo(l10n.vehiculoCampoPlacas, vehiculo.placas ?? '—'),
                      _campo(l10n.vehiculoCampoVin, vehiculo.vin ?? '—'),
                      _campo(l10n.vehiculoCampoNumeroMotor, vehiculo.numeroMotor ?? '—'),
                      _campo(
                        l10n.vehiculoCampoFechaAdquisicion,
                        vehiculo.fechaAdquisicion == null ? '—' : _formatoFecha.format(vehiculo.fechaAdquisicion!),
                      ),
                      _campo(
                        l10n.vehiculoCampoCostoAdquisicion,
                        vehiculo.costoAdquisicion == null ? '—' : formatoCosto(vehiculo.costoAdquisicion!),
                      ),
                      _campo(l10n.vehiculoCampoObservaciones, vehiculo.observaciones ?? '—'),
                      if (esBaja) ...[
                        const Divider(height: AppSpacing.xl),
                        _campo(l10n.vehiculoBajaCampoFecha, _formatoFecha.format(vehiculo.fechaBaja!)),
                        _campo(
                          l10n.vehiculoBajaCampoMotivo,
                          vehiculo.motivoBaja == null
                              ? '—'
                              : motivoBajaVehiculoLabel(l10n, MotivoBajaVehiculo.values.byName(vehiculo.motivoBaja!)),
                        ),
                        _campo(l10n.vehiculoBajaCampoObservaciones, vehiculo.observacionesBaja ?? '—'),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                RisegCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      RisegSectionHeader(
                        title: l10n.vehiculoAsignacionSeccionTitulo,
                        primaryAction:
                            esBaja
                                ? null
                                : (_asignacionVigente == null
                                    ? RisegButton(
                                      label: l10n.vehiculoBotonAsignar,
                                      variant: RisegButtonVariant.secondary,
                                      size: RisegButtonSize.compact,
                                      onPressed: vehiculo.estatus == 'disponible' ? _asignar : null,
                                    )
                                    : null),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      if (_asignacionVigente == null)
                        Text(l10n.vehiculoAsignacionVacio, style: AppTypography.body.copyWith(color: colors.textMuted))
                      else ...[
                        _campo(l10n.vehiculoAsignacionDestino, _destino(_asignacionVigente!)),
                        _campo(l10n.vehiculoAsignacionDesde, _formatoFecha.format(_asignacionVigente!.fechaInicio)),
                        const SizedBox(height: AppSpacing.sm),
                        Wrap(
                          spacing: AppSpacing.xs,
                          runSpacing: AppSpacing.xs,
                          children: [
                            RisegButton(
                              label: l10n.vehiculoBotonCambiarAsignacion,
                              variant: RisegButtonVariant.ghost,
                              size: RisegButtonSize.compact,
                              onPressed: _cambiarAsignacion,
                            ),
                            RisegButton(
                              label: l10n.vehiculoBotonRetirarAsignacion,
                              variant: RisegButtonVariant.ghost,
                              size: RisegButtonSize.compact,
                              onPressed: _retirarAsignacion,
                            ),
                          ],
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
                      RisegSectionHeader(
                        title: l10n.vehiculoKilometrajeSeccionTitulo,
                        primaryAction:
                            esBaja
                                ? null
                                : RisegButton(
                                  label: l10n.vehiculoBotonRegistrarKilometraje,
                                  variant: RisegButtonVariant.secondary,
                                  size: RisegButtonSize.compact,
                                  onPressed: _registrarKilometraje,
                                ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      if (_kilometrajeActual == null)
                        Text(l10n.vehiculoKilometrajeVacio, style: AppTypography.body.copyWith(color: colors.textMuted))
                      else
                        Text(
                          '${_kilometrajeActual!.kilometraje} km',
                          style: AppTypography.heading2.copyWith(color: colors.textPrimary),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                RisegCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      RisegSectionHeader(
                        title: l10n.vehiculoDocumentosSeccionTitulo,
                        primaryAction:
                            esBaja
                                ? null
                                : RisegButton(
                                  label: l10n.vehiculoBotonAgregarDocumento,
                                  variant: RisegButtonVariant.secondary,
                                  size: RisegButtonSize.compact,
                                  onPressed: _agregarDocumento,
                                ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      if (documentosVigentesPorTipo(_documentos).isEmpty)
                        Text(l10n.vehiculoDocumentosVacio, style: AppTypography.body.copyWith(color: colors.textMuted))
                      else
                        for (final documento in documentosVigentesPorTipo(_documentos))
                          Padding(
                            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(tipoDocumentoVehiculoLabel(l10n, documento), style: AppTypography.body),
                                      Builder(
                                        builder: (_) {
                                          final estado = calcularEstadoVigenciaDocumento(documento.fechaVencimiento);
                                          final detalle = detalleVigenciaDocumentoLabel(
                                            l10n,
                                            estado,
                                            documento.fechaVencimiento,
                                          );
                                          return Wrap(
                                            crossAxisAlignment: WrapCrossAlignment.center,
                                            spacing: AppSpacing.xs,
                                            children: [
                                              RisegStatusBadge(
                                                label: estadoVigenciaDocumentoLabel(l10n, estado),
                                                tone: estadoVigenciaDocumentoTono(estado),
                                              ),
                                              if (detalle.isNotEmpty)
                                                Text(
                                                  detalle,
                                                  style: AppTypography.caption.copyWith(color: colors.textMuted),
                                                ),
                                            ],
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                                // `Flexible` y no un `Wrap` suelto: sin
                                // el límite de ancho, el Wrap toma su
                                // tamaño natural y desborda el Row a
                                // 500 px (lo encontró la prueba
                                // responsive de esta etapa al sumarse
                                // el botón "Corregir"). Con Flexible el
                                // Wrap parte los botones en renglones.
                                Flexible(
                                  child: Wrap(
                                    spacing: AppSpacing.xs,
                                    alignment: WrapAlignment.end,
                                    children: [
                                      if (_adjuntoPorDocumento.containsKey(documento.id))
                                        RisegButton(
                                          label: l10n.vehiculoDocumentoBotonAbrir,
                                          variant: RisegButtonVariant.ghost,
                                          size: RisegButtonSize.compact,
                                          onPressed:
                                              () => ref
                                                  .read(attachmentStorageProvider)
                                                  .abrir(_adjuntoPorDocumento[documento.id]!.path),
                                        ),
                                      RisegButton(
                                        label: l10n.vehiculoBotonRenovarDocumento,
                                        variant: RisegButtonVariant.ghost,
                                        size: RisegButtonSize.compact,
                                        onPressed: esBaja ? null : () => _renovarDocumento(documento),
                                      ),
                                      // Corregir NO es renovar (v80): esto
                                      // arregla la captura de esta misma
                                      // vigencia, sin inventar una nueva.
                                      RisegButton(
                                        key: Key('vehiculo_documento_corregir_${documento.id}'),
                                        label: l10n.vehiculoBotonCorregirDocumento,
                                        variant: RisegButtonVariant.ghost,
                                        size: RisegButtonSize.compact,
                                        onPressed: esBaja ? null : () => _corregirDocumento(documento),
                                      ),
                                      RisegButton(
                                        label: l10n.vehiculoBotonVerHistorialDocumento,
                                        variant: RisegButtonVariant.ghost,
                                        size: RisegButtonSize.compact,
                                        onPressed: () => _verHistorialDocumento(documento.tipo),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                _buildSeccionMantenimiento(l10n, colors, esBaja),
                const SizedBox(height: AppSpacing.xl),
                _buildSeccionProximoMantenimiento(l10n, colors),
                const SizedBox(height: AppSpacing.xl),
                _buildSeccionCostos(l10n, colors, vehiculo),
                const SizedBox(height: AppSpacing.xl),
                RisegCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.vehiculoHistorialAsignacionesTitulo, style: AppTypography.heading3),
                      const SizedBox(height: AppSpacing.sm),
                      RisegTableBase<AsignacionVehiculoData>(
                        rows: _historialAsignaciones,
                        emptyState: RisegEmptyState(title: l10n.vehiculoHistorialAsignacionesVacio, message: ''),
                        columns: [
                          RisegColumn<AsignacionVehiculoData>(
                            label: l10n.vehiculoColumnaDestino,
                            cellBuilder: (a) => Text(_destino(a)),
                          ),
                          RisegColumn<AsignacionVehiculoData>(
                            label: l10n.vehiculoColumnaFechaInicio,
                            width: 110,
                            cellBuilder: (a) => Text(_formatoFecha.format(a.fechaInicio)),
                          ),
                          RisegColumn<AsignacionVehiculoData>(
                            label: l10n.vehiculoColumnaFechaTermino,
                            width: 110,
                            cellBuilder:
                                (a) => Text(a.fechaTermino == null ? '—' : _formatoFecha.format(a.fechaTermino!)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                RisegCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.vehiculoHistorialKilometrajeTitulo, style: AppTypography.heading3),
                      const SizedBox(height: AppSpacing.sm),
                      RisegTableBase<VehiculoKilometrajeData>(
                        rows: _historialKilometraje,
                        emptyState: RisegEmptyState(title: l10n.vehiculoKilometrajeVacio, message: ''),
                        columns: [
                          RisegColumn<VehiculoKilometrajeData>(
                            label: l10n.vehiculoColumnaFecha,
                            width: 110,
                            cellBuilder: (k) => Text(_formatoFecha.format(k.fecha)),
                          ),
                          RisegColumn<VehiculoKilometrajeData>(
                            label: l10n.vehiculoColumnaKilometraje,
                            width: 110,
                            alignment: TextAlign.right,
                            cellBuilder: (k) => Text('${k.kilometraje} km'),
                          ),
                          RisegColumn<VehiculoKilometrajeData>(
                            label: l10n.vehiculoColumnaOrigen,
                            width: 140,
                            cellBuilder: (k) => Text(origenKilometrajeLabel(l10n, k.origen)),
                          ),
                        ],
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

  /// Historial combinado de Mantenimiento e Incidencias (Etapa 8D,
  /// punto 9: "un solo historial con filtros" en vez de dos pantallas
  /// separadas) — el filtro Todos/Mantenimiento/Incidencias es estado
  /// local de la pantalla, no una consulta distinta.
  Widget _buildSeccionMantenimiento(AppLocalizations l10n, AppColorScheme colors, bool esBaja) {
    final puedeAnular = ref.watch(permissionServiceProvider).hasCode('vehiculos.cancelar');
    final filtrados = switch (_filtroMantenimiento) {
      _FiltroMantenimiento.todos => _mantenimientos,
      _FiltroMantenimiento.mantenimiento =>
        _mantenimientos.where((m) => !TipoMantenimientoVehiculo.values.byName(m.tipo).esIncidencia).toList(),
      _FiltroMantenimiento.incidencias =>
        _mantenimientos.where((m) => TipoMantenimientoVehiculo.values.byName(m.tipo).esIncidencia).toList(),
    };

    return RisegCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RisegSectionHeader(
            title: l10n.vehiculoMantenimientoSeccionTitulo,
            primaryAction:
                esBaja
                    ? null
                    : RisegButton(
                      label: l10n.vehiculoBotonRegistrarMantenimiento,
                      variant: RisegButtonVariant.secondary,
                      size: RisegButtonSize.compact,
                      onPressed: _registrarMantenimiento,
                    ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.xs,
            children: [
              for (final filtro in _FiltroMantenimiento.values)
                RisegButton(
                  label: switch (filtro) {
                    _FiltroMantenimiento.todos => l10n.vehiculoMantenimientoFiltroTodos,
                    _FiltroMantenimiento.mantenimiento => l10n.vehiculoMantenimientoFiltroMantenimiento,
                    _FiltroMantenimiento.incidencias => l10n.vehiculoMantenimientoFiltroIncidencias,
                  },
                  variant: _filtroMantenimiento == filtro ? RisegButtonVariant.secondary : RisegButtonVariant.ghost,
                  size: RisegButtonSize.compact,
                  onPressed: () => setState(() => _filtroMantenimiento = filtro),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          RisegTableBase<VehiculoMantenimientoData>(
            rows: filtrados,
            emptyState: RisegEmptyState(title: l10n.vehiculoMantenimientoVacio, message: ''),
            columns: [
              RisegColumn<VehiculoMantenimientoData>(
                label: l10n.vehiculoMantenimientoColumnaFecha,
                width: 100,
                cellBuilder: (m) => Text(_formatoFecha.format(m.fecha)),
              ),
              RisegColumn<VehiculoMantenimientoData>(
                label: l10n.vehiculoMantenimientoColumnaTipo,
                width: 170,
                cellBuilder: (m) {
                  final esIncidencia = TipoMantenimientoVehiculo.values.byName(m.tipo).esIncidencia;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tipoMantenimientoVehiculoLabel(l10n, m.tipo)),
                      RisegStatusBadge(
                        label: categoriaMantenimientoVehiculoLabel(l10n, esIncidencia: esIncidencia),
                        tone: categoriaMantenimientoVehiculoTono(esIncidencia: esIncidencia),
                      ),
                      // Un registro anulado NO desaparece del historial:
                      // se marca. Su costo ya no pesa en los totales
                      // (calcularCostosVehiculo lo salta) y su efecto
                      // financiero ya fue revertido.
                      if (_estaAnulado(m))
                        RisegStatusBadge(
                          label: l10n.vehiculoMantenimientoEstatusCancelado,
                          tone: RisegStatusTone.error,
                        ),
                    ],
                  );
                },
              ),
              RisegColumn<VehiculoMantenimientoData>(
                label: l10n.vehiculoMantenimientoColumnaDescripcion,
                cellBuilder: (m) => Text(m.descripcion),
              ),
              RisegColumn<VehiculoMantenimientoData>(
                label: l10n.vehiculoMantenimientoColumnaCosto,
                width: 100,
                alignment: TextAlign.right,
                cellBuilder:
                    (m) => Text(
                      m.costo == null ? '—' : formatoCosto(m.costo!),
                      style:
                          _estaAnulado(m)
                              ? AppTypography.body.copyWith(
                                decoration: TextDecoration.lineThrough,
                                color: colors.textMuted,
                              )
                              : null,
                    ),
              ),
              // De donde salio el dinero (schemaVersion 80). Un gasto
              // historico anterior a esta etapa se muestra como "Sin
              // especificar" — nunca se le inventa una cuenta.
              RisegColumn<VehiculoMantenimientoData>(
                label: l10n.vehiculoMantenimientoColumnaOrigen,
                width: 150,
                cellBuilder:
                    (m) => Text(
                      (m.costo ?? 0) == 0
                          ? '—'
                          : _origenPorMantenimiento[m.id] ?? l10n.vehiculoMantenimientoOrigenSinEspecificar,
                      overflow: TextOverflow.ellipsis,
                    ),
              ),
              RisegColumn<VehiculoMantenimientoData>(
                label: l10n.vehiculoMantenimientoColumnaComprobante,
                width: 90,
                cellBuilder:
                    (m) =>
                        _comprobantePorMantenimiento.containsKey(m.id)
                            ? RisegButton(
                              label: l10n.vehiculoMantenimientoBotonAbrirComprobante,
                              variant: RisegButtonVariant.ghost,
                              size: RisegButtonSize.compact,
                              onPressed:
                                  () => ref
                                      .read(attachmentStorageProvider)
                                      .abrir(_comprobantePorMantenimiento[m.id]!.path),
                            )
                            : const Text('—'),
              ),
              // Corregir y Anular (schemaVersion 80) — el gap que hacia
              // que un error de captura obligara a borrar historial.
              // Un vehiculo dado de baja o un registro ya anulado no
              // ofrecen acciones: no hay nada que corregir ahi.
              // Menú ⋮ y no dos botones sueltos: "Corregir" y
              // "Anular" juntos no caben en una celda de tabla a 500 px
              // (lo encontró la prueba responsive de esta etapa, con un
              // overflow real de RenderFlex). `RisegActionsMenu` existe
              // exactamente para consolidar acciones en filas angostas.
              if (!esBaja)
                RisegColumn<VehiculoMantenimientoData>(
                  label: l10n.vehiculoMantenimientoColumnaAcciones,
                  width: 150,
                  cellBuilder:
                      (m) =>
                          _estaAnulado(m)
                              ? Text(
                                l10n.vehiculoMantenimientoAnuladoMotivo(m.motivoCancelacion ?? ''),
                                style: AppTypography.caption.copyWith(color: colors.textMuted),
                                overflow: TextOverflow.ellipsis,
                              )
                              : RisegActionsMenu(
                                menuKey: Key('vehiculo_mantenimiento_acciones_${m.id}'),
                                actions: [
                                  RisegMenuAction(
                                    key: Key('vehiculo_mantenimiento_corregir_${m.id}'),
                                    label: l10n.vehiculoMantenimientoBotonCorregir,
                                    icon: Icons.edit_outlined,
                                    onTap: () => _corregirMantenimiento(m),
                                  ),
                                  // "Anular" solo se ofrece con
                                  // `vehiculos.cancelar`: es la acción
                                  // que revierte dinero real. Esto es
                                  // cortesía de UI — la compuerta que
                                  // manda vive en
                                  // `cancelarMantenimientoVehiculoAutorizadoProvider`.
                                  if (puedeAnular)
                                    RisegMenuAction(
                                      key: Key('vehiculo_mantenimiento_anular_${m.id}'),
                                      label: l10n.vehiculoMantenimientoBotonAnular,
                                      icon: Icons.block,
                                      destructive: true,
                                      onTap: () => _anularMantenimiento(m),
                                    ),
                                ],
                              ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSeccionProximoMantenimiento(AppLocalizations l10n, AppColorScheme colors) {
    final proximo = calcularProximoMantenimiento(_mantenimientos, _kilometrajeActual?.kilometraje);
    return RisegCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.vehiculoProximoMantenimientoSeccionTitulo, style: AppTypography.heading3),
          const SizedBox(height: AppSpacing.sm),
          if (proximo == null)
            Text(l10n.vehiculoProximoMantenimientoVacio, style: AppTypography.body.copyWith(color: colors.textMuted))
          else ...[
            if (proximo.fecha != null)
              Text(
                l10n.vehiculoProximoMantenimientoFecha(_formatoFecha.format(proximo.fecha!)),
                style: AppTypography.body,
              ),
            if (proximo.kilometraje != null)
              Text(l10n.vehiculoProximoMantenimientoKilometraje(proximo.kilometraje!), style: AppTypography.body),
            const SizedBox(height: AppSpacing.xs),
            RisegStatusBadge(
              label: estadoProximoMantenimientoLabel(l10n, proximo.estado),
              tone: estadoProximoMantenimientoTono(proximo.estado),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSeccionCostos(AppLocalizations l10n, AppColorScheme colors, VehiculoData vehiculo) {
    final costos = calcularCostosVehiculo(vehiculo, _mantenimientos);
    return RisegCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.vehiculoCostosSeccionTitulo, style: AppTypography.heading3),
          const SizedBox(height: AppSpacing.sm),
          _campo(
            l10n.vehiculoCampoCostoAdquisicion,
            costos.costoAdquisicion == null ? '—' : formatoCosto(costos.costoAdquisicion!),
          ),
          _campo(l10n.vehiculoCostoTotalMantenimientos, formatoCosto(costos.totalMantenimientos)),
          _campo(l10n.vehiculoCostoTotalIncidencias, formatoCosto(costos.totalIncidencias)),
          _campo(l10n.vehiculoCostoOperativoAcumulado, formatoCosto(costos.costoOperativoAcumulado)),
        ],
      ),
    );
  }

  Widget _campo(String etiqueta, String valor) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 180, child: Text(etiqueta, style: AppTypography.label.copyWith(color: colors.textMuted))),
          Expanded(child: Text(valor, style: AppTypography.body)),
        ],
      ),
    );
  }
}
