import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/finanzas/finanzas_providers.dart'
    show cuentaFinancieraRepositoryProvider, deudaRepositoryProvider, egresoRepositoryProvider;
import 'package:riseg_one/features/finanzas/presentation/widgets/origen_financiero_select.dart';
import 'package:riseg_one/features/vehiculos/data/tables/vehiculo_mantenimiento_table.dart';
import 'package:riseg_one/features/vehiculos/domain/usecases/corregir_mantenimiento_vehiculo_usecase.dart';

import '../vehiculo_labels.dart';
import '../../vehiculos_providers.dart';

int? _centavosDesdeTexto(String texto) {
  final normalizado = texto.trim().replaceAll(',', '');
  if (normalizado.isEmpty) return null;
  final pesos = double.tryParse(normalizado);
  if (pesos == null) return null;
  return (pesos * 100).round();
}

String _pesosDesdeCentavos(int? centavos) =>
    centavos == null ? '' : (centavos / 100).toStringAsFixed(2);

/// Diálogo "Corregir mantenimiento" (schemaVersion 80) — el que faltaba
/// para que un error de captura no obligue a borrar historial.
///
/// Presenta el registro **precargado** con lo que hay hoy, incluido su
/// origen financiero vigente: así el usuario ve de dónde salió el dinero
/// y puede moverlo a otra cuenta o a una tarjeta sin adivinar. Las 8
/// transiciones de origen (cuenta↔cuenta, cuenta↔TDC, misma TDC, cambio
/// de monto…) las resuelve `CorregirMantenimientoVehiculoUseCase` por un
/// único camino; esta pantalla solo entrega la selección.
///
/// El `motivo` es obligatorio y no se puede saltar: sin él, la
/// corrección no queda registrada en el historial del vehículo y
/// volveríamos exactamente al gap que esta etapa cierra.
///
/// Devuelve `true` si tuvo éxito.
Future<bool> mostrarDialogoCorregirMantenimientoVehiculo(
  BuildContext context,
  WidgetRef ref,
  VehiculoMantenimientoData registro,
) async {
  final l10n = AppLocalizations.of(context)!;

  final cuentas = await ref.read(cuentaFinancieraRepositoryProvider).listar(soloActivas: true);
  final tarjetas = await ref.read(deudaRepositoryProvider).listarTarjetasActivas();
  if (!context.mounted) return false;

  // Precarga del origen vigente: si el gasto salió de una cuenta, se
  // resuelve por el Egreso; si se cargó a una tarjeta, por la Deuda.
  // Un registro histórico sin origen (el legacy de la v79) simplemente
  // llega en null — y el caso de uso exigirá elegir uno si hay costo.
  // Cuando hay Egreso, la clave se deriva con `claveOrigenDeEgreso`, la
  // MISMA función que usa Egresos manuales — nunca una segunda forma de
  // construir la clave del selector.
  ClaveOrigenFinanciero? claveOrigen;
  if (registro.deudaId != null) {
    claveOrigen = claveOrigenDe(deudaId: registro.deudaId);
  } else if (registro.egresoId != null) {
    final egreso = await ref.read(egresoRepositoryProvider).obtenerPorId(registro.egresoId!);
    if (egreso != null) claveOrigen = claveOrigenDeEgreso(egreso);
  }
  if (!context.mounted) return false;

  DateTime fecha = registro.fecha;
  TipoMantenimientoVehiculo tipo = TipoMantenimientoVehiculo.values.byName(registro.tipo);
  final descripcionCtrl = TextEditingController(text: registro.descripcion);
  final tallerCtrl = TextEditingController(text: registro.tallerProveedor ?? '');
  final costoCtrl = TextEditingController(text: _pesosDesdeCentavos(registro.costo));
  DateTime? proximoFecha = registro.proximoMantenimientoFecha;
  final proximoKilometrajeCtrl =
      TextEditingController(text: registro.proximoMantenimientoKilometraje?.toString() ?? '');
  final observacionesCtrl = TextEditingController(text: registro.observaciones ?? '');
  final motivoCtrl = TextEditingController();
  String? errorGeneral;

  final resultado = await RisegDialog.showForm<bool>(
    context: context,
    title: l10n.vehiculoMantenimientoDialogoCorregirTitulo,
    confirmLabel: l10n.vehiculoMantenimientoBotonGuardar,
    cancelLabel: l10n.vehiculoBotonCancelar,
    contentBuilder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        return SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RisegDateField(
                label: l10n.vehiculoMantenimientoCampoFecha,
                value: fecha,
                onChanged: (valor) => setState(() => fecha = valor),
              ),
              const SizedBox(height: AppSpacing.md),
              RisegSelect<TipoMantenimientoVehiculo>(
                label: l10n.vehiculoMantenimientoCampoTipo,
                value: tipo,
                items: [
                  for (final t in TipoMantenimientoVehiculo.values)
                    RisegSelectItem(value: t, label: tipoMantenimientoVehiculoLabel(l10n, t.name)),
                ],
                onChanged: (valor) => setState(() => tipo = valor ?? tipo),
              ),
              const SizedBox(height: AppSpacing.md),
              RisegTextField(
                label: l10n.vehiculoMantenimientoCampoDescripcion,
                controller: descripcionCtrl,
              ),
              const SizedBox(height: AppSpacing.md),
              RisegTextField(label: l10n.vehiculoMantenimientoCampoTallerProveedor, controller: tallerCtrl),
              const SizedBox(height: AppSpacing.md),
              RisegTextField(
                key: const Key('vehiculo_mantenimiento_corregir_costo'),
                label: l10n.vehiculoMantenimientoCampoCosto,
                controller: costoCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
              ),
              if ((_centavosDesdeTexto(costoCtrl.text) ?? 0) > 0) ...[
                const SizedBox(height: AppSpacing.md),
                RisegOrigenFinancieroSelect(
                  key: const Key('vehiculo_mantenimiento_corregir_origen'),
                  cuentas: cuentas,
                  tarjetas: tarjetas,
                  value: claveOrigen,
                  onChanged: (valor) => setState(() => claveOrigen = valor),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              RisegDateField(
                label: l10n.vehiculoMantenimientoCampoProximoFecha,
                value: proximoFecha,
                onChanged: (valor) => setState(() => proximoFecha = valor),
              ),
              const SizedBox(height: AppSpacing.md),
              RisegTextField(
                label: l10n.vehiculoMantenimientoCampoProximoKilometraje,
                controller: proximoKilometrajeCtrl,
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: AppSpacing.md),
              RisegTextField(label: l10n.vehiculoMantenimientoCampoObservaciones, controller: observacionesCtrl),
              const SizedBox(height: AppSpacing.md),
              RisegTextField(
                key: const Key('vehiculo_mantenimiento_corregir_motivo'),
                label: l10n.vehiculoMantenimientoCampoMotivoCorreccion,
                controller: motivoCtrl,
                autofocus: true,
              ),
              if (errorGeneral != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  errorGeneral!,
                  style: AppTypography.caption.copyWith(color: Theme.of(dialogContext).colorScheme.error),
                ),
              ],
            ],
          ),
        );
      },
    ),
    onConfirm: () async {
      final proximoKilometraje =
          proximoKilometrajeCtrl.text.trim().isEmpty ? null : int.tryParse(proximoKilometrajeCtrl.text.trim());
      final costo = _centavosDesdeTexto(costoCtrl.text);

      final corregido = await ref.read(corregirMantenimientoVehiculoAutorizadoProvider)(
            vehiculoMantenimientoId: registro.id,
            fecha: fecha,
            tipo: tipo.name,
            descripcion: descripcionCtrl.text,
            tallerProveedor: tallerCtrl.text,
            costo: costo,
            // Vaciar el campo significa "este registro no costó nada":
            // el origen vigente se revierte, nunca queda huérfano.
            limpiarCosto: costo == null,
            proximoMantenimientoFecha: proximoFecha,
            proximoMantenimientoKilometraje: proximoKilometraje,
            observaciones: observacionesCtrl.text,
            origen: origenDesdeClave(claveOrigen),
            motivo: motivoCtrl.text,
          );
      if (!context.mounted) return false;

      switch (corregido) {
        case CorregirMantenimientoVehiculoMotivoRequerido():
          errorGeneral = l10n.vehiculoMantenimientoErrorMotivoRequerido;
          return null;
        case CorregirMantenimientoVehiculoDescripcionRequerida():
          errorGeneral = l10n.vehiculoMantenimientoErrorDescripcionRequerida;
          return null;
        case CorregirMantenimientoVehiculoCostoInvalido():
          errorGeneral = l10n.vehiculoMantenimientoErrorCostoInvalido;
          return null;
        case CorregirMantenimientoVehiculoOrigenFinancieroRequerido():
          errorGeneral = l10n.vehiculoMantenimientoErrorOrigenRequerido;
          return null;
        case CorregirMantenimientoVehiculoTarjetaInvalida(:final error, :final disponible):
          errorGeneral = mensajeErrorOrigenTarjeta(l10n, error, disponible);
          return null;
        case CorregirMantenimientoVehiculoCancelado():
          errorGeneral = l10n.vehiculoMantenimientoErrorCorregirCancelado;
          return null;
        case CorregirMantenimientoVehiculoNoExiste():
        case CorregirMantenimientoVehiculoErrorInesperado():
          RisegFeedback.showError(context, l10n.vehiculoMantenimientoErrorInesperado);
          return false;
        case CorregirMantenimientoVehiculoExitoso():
          RisegFeedback.showSuccess(context, l10n.vehiculoMantenimientoCorregidoExito);
          return true;
      }
    },
  );

  WidgetsBinding.instance.addPostFrameCallback((_) {
    descripcionCtrl.dispose();
    tallerCtrl.dispose();
    costoCtrl.dispose();
    proximoKilometrajeCtrl.dispose();
    observacionesCtrl.dispose();
    motivoCtrl.dispose();
  });
  return resultado ?? false;
}
