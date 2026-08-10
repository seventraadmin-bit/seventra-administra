import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/inventario/presentation/articulos/articulos_list_screen.dart' show formatoCosto;
import 'package:riseg_one/features/vehiculos/data/tables/vehiculo_table.dart' show MotivoBajaVehiculo;
import 'package:riseg_one/features/vehiculos/domain/usecases/actualizar_fotografia_vehiculo_usecase.dart';
import 'package:riseg_one/features/vehiculos/domain/usecases/cambiar_estatus_vehiculo_usecase.dart';

import 'vehiculo_labels.dart';
import 'vehiculos_controller.dart';
import '../vehiculos_providers.dart';
import 'widgets/asignar_vehiculo_dialog.dart';
import 'widgets/cambiar_asignacion_vehiculo_dialog.dart';
import 'widgets/dar_de_baja_vehiculo_dialog.dart';
import 'widgets/gestionar_vehiculo_dialog.dart';
import 'widgets/registrar_kilometraje_vehiculo_dialog.dart';
import 'widgets/retirar_asignacion_vehiculo_dialog.dart';

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

    final asignacionVigente = await asignacionRepo.obtenerActivaPorVehiculo(widget.vehiculoId);
    final historialAsignaciones = await asignacionRepo.listarPorVehiculo(widget.vehiculoId);
    final empleados = await opciones.obtenerEmpleados();
    final servicios = await opciones.obtenerServicios();
    final kilometrajeActual = await kilometrajeRepo.obtenerActual(widget.vehiculoId);
    final historialKilometraje = await kilometrajeRepo.listarPorVehiculo(widget.vehiculoId);

    if (!mounted) return;
    setState(() {
      _vehiculo = vehiculo;
      _asignacionVigente = asignacionVigente;
      _historialAsignaciones = historialAsignaciones;
      _empleadosPorId = {for (final e in empleados) e.id: e.nombre};
      _serviciosPorId = {for (final s in servicios) s.id: s.nombre};
      _kilometrajeActual = kilometrajeActual;
      _historialKilometraje = historialKilometraje;
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

  Future<void> _cambiarFotografia() async {
    final l10n = AppLocalizations.of(context)!;
    final seleccion = await FilePicker.platform.pickFiles(type: FileType.image);
    final archivo = seleccion?.files.singleOrNull;
    if (archivo?.path == null) return;
    if (!mounted) return;

    setState(() => _procesando = true);
    final resultado = await ref.read(vehiculosControllerProvider.notifier).actualizarFotografia(
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
      return Scaffold(appBar: AppBar(), body: RisegEmptyState(title: l10n.vehiculosListadoCargaErrorTitulo, message: ''));
    }

    final esBaja = vehiculo.estatus == 'baja';

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
                          Text('${vehiculo.marca} ${vehiculo.modelo}', style: AppTypography.heading2.copyWith(color: colors.textPrimary)),
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
                    if (!esBaja && vehiculo.estatus != 'disponible')
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
                        primaryAction: esBaja
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
                        primaryAction: esBaja
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
                            cellBuilder: (a) => Text(a.fechaTermino == null ? '—' : _formatoFecha.format(a.fechaTermino!)),
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
