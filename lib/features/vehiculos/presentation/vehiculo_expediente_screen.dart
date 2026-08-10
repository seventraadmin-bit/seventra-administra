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
import 'widgets/dar_de_baja_vehiculo_dialog.dart';
import 'widgets/gestionar_vehiculo_dialog.dart';

final _formatoFecha = DateFormat('dd/MM/yyyy');

/// Expediente de un Vehículo (Etapa 8A) — una sola pantalla desplazable
/// con secciones, sin pestañas internas (mismo criterio que
/// `ArticuloExpedienteScreen`/`EmpleadoExpedienteScreen`). Asignación
/// actual/Kilometraje/Documentos/Mantenimiento/Historial llegan en
/// etapas futuras (8B-8E).
class VehiculoExpedienteScreen extends ConsumerStatefulWidget {
  const VehiculoExpedienteScreen({required this.vehiculoId, super.key});

  final String vehiculoId;

  @override
  ConsumerState<VehiculoExpedienteScreen> createState() => _VehiculoExpedienteScreenState();
}

class _VehiculoExpedienteScreenState extends ConsumerState<VehiculoExpedienteScreen> {
  VehiculoData? _vehiculo;
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
    if (!mounted) return;
    setState(() {
      _vehiculo = vehiculo;
      _cargando = false;
    });
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
