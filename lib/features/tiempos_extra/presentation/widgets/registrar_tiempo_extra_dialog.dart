import 'package:riseg_one/features/finanzas/presentation/mensaje_saldo_insuficiente.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/finanzas/data/tables/pago_table.dart' show FormaPago;
import 'package:riseg_one/features/finanzas/domain/usecases/calcular_fecha_tarjeta_usecase.dart';
import 'package:riseg_one/features/finanzas/finanzas_providers.dart';
import 'package:riseg_one/features/finanzas/presentation/deudas_credito/deudas_credito_list_screen.dart' show formatoCentavosDeuda;
import 'package:riseg_one/features/finanzas/presentation/pagos/pagos_list_screen.dart' show formaPagoLabel;
import 'package:riseg_one/features/organizacion/organizacion_providers.dart';
import 'package:riseg_one/features/personal/personal_providers.dart';
import 'package:riseg_one/features/personal/presentation/empleados/empleados_list_screen.dart' show empleadoNombreCompleto;

import '../../data/repositories/vacante_cobertura_reader.dart';
import '../../data/tables/tiempo_extra_table.dart';
import '../../tiempos_extra_providers.dart';
import '../../domain/repositories/tiempo_extra_repository.dart';
import '../../domain/usecases/corregir_tiempo_extra_usecase.dart';
import '../../domain/usecases/registrar_tiempo_extra_usecase.dart';
import '../../domain/usecases/tiempo_extra_validator.dart';
import '../tiempos_extra_controller.dart';
import 'tiempo_extra_labels.dart';

int? _centavosDesdeTexto(String texto) {
  final normalizado = texto.trim().replaceAll(',', '');
  if (normalizado.isEmpty) return null;
  final pesos = double.tryParse(normalizado);
  if (pesos == null) return null;
  return (pesos * 100).round();
}

class _CostoAdicionalCampos {
  _CostoAdicionalCampos({this.costoAdicionalId})
      : conceptoCtrl = TextEditingController(),
        montoCtrl = TextEditingController();
  final TextEditingController conceptoCtrl;
  final TextEditingController montoCtrl;

  /// `null` = costo nuevo (se agrega); no nulo = costo ya existente que
  /// se está corrigiendo (Etapa "corrección real de Tiempo Extra").
  final int? costoAdicionalId;

  /// Origen financiero PROPIO de este costo (Etapa "origen financiero
  /// unificado") — independiente del pago base y de cualquier otro
  /// costo, nunca fusionado.
  String formaPago = FormaPago.efectivo.name;
  String? cuentaFinancieraId;
  String? deudaIdTarjeta;

  void dispose() {
    conceptoCtrl.dispose();
    montoCtrl.dispose();
  }
}

enum _TipoCobertura { empleado, externo }

/// Traduce la invariante rota a algo accionable. `camposIncompatibles`
/// jamás debería llegar desde este diálogo (limpia al cambiar de
/// origen), pero se cubre por si el caso de uso se llama desde otro
/// lado.
String _errorOrigenTexto(AppLocalizations l10n, TiempoExtraOrigenValidacion validacion) {
  return switch (validacion) {
    TiempoExtraOrigenValidacion.faltaEmpleadoAusente => l10n.registrarTiempoExtraErrorEmpleadoAusenteRequerido,
    TiempoExtraOrigenValidacion.faltaMotivoAusencia => l10n.registrarTiempoExtraErrorMotivoAusenciaRequerido,
    TiempoExtraOrigenValidacion.faltaVacante => l10n.registrarTiempoExtraErrorVacanteRequerida,
    TiempoExtraOrigenValidacion.faltaDescripcionOrigen => l10n.registrarTiempoExtraErrorDescripcionOrigenRequerida,
    TiempoExtraOrigenValidacion.camposIncompatibles => l10n.registrarTiempoExtraErrorOrigenRequerido,
    TiempoExtraOrigenValidacion.valida => l10n.registrarTiempoExtraErrorOrigenRequerido,
  };
}

/// Selector dinámico de origen financiero (Etapa "origen financiero
/// unificado") — reutilizado tanto para el pago base como para cada
/// costo adicional, nunca reimplementado. `formaPago == tarjeta` pide
/// "Tarjeta utilizada" (solo TDC activas); cualquier otra forma pide
/// "Cuenta de origen" (CuentaFinanciera activa).
List<Widget> _camposOrigenFinanciero({
  required AppLocalizations l10n,
  Key? claveCuenta,
  Key? claveTarjeta,
  required String formaPago,
  required List<CuentaFinancieraData> cuentasFinancieras,
  required List<DeudaData> tarjetasActivas,
  required String? cuentaFinancieraId,
  required String? deudaIdTarjeta,
  required ValueChanged<String?> onCuentaCambiada,
  required ValueChanged<String?> onTarjetaCambiada,
}) {
  if (formaPago == FormaPago.tarjeta.name) {
    return [
      RisegSelect<String?>(
        key: claveTarjeta,
        label: l10n.registrarTiempoExtraCampoTarjetaUtilizada,
        value: deudaIdTarjeta,
        items: [
          for (final t in tarjetasActivas)
            RisegSelectItem(
              value: t.id,
              label: l10n.registrarTiempoExtraTarjetaOpcionEtiqueta(t.nombre, _disponibleTarjetaTexto(l10n, t)),
            ),
        ],
        onChanged: onTarjetaCambiada,
      ),
    ];
  }
  return [
    RisegSelect<String?>(
      key: claveCuenta,
      label: l10n.registrarTiempoExtraCampoCuentaOrigen,
      value: cuentaFinancieraId,
      items: [for (final c in cuentasFinancieras) RisegSelectItem(value: c.id, label: c.nombre)],
      onChanged: onCuentaCambiada,
    ),
  ];
}

String _disponibleTarjetaTexto(AppLocalizations l10n, DeudaData tarjeta) {
  final disponible = creditoDisponibleTarjeta(limiteCredito: tarjeta.tarjetaLimiteCredito, saldoActual: tarjeta.saldoActual);
  return disponible == null ? l10n.deudaTarjetaSinDato : formatoCentavosDeuda(disponible);
}

/// Resuelve `cuentaFinancieraId` de un ítem ya registrado a partir de
/// su `egresoId` — el ítem en sí nunca guarda la cuenta directamente,
/// solo el Egreso la conoce. `null` si el ítem se pagó con tarjeta (no
/// tiene Egreso) o si el Egreso no tiene cuenta especificada.
Future<String?> _resolverCuentaDesdeEgreso(WidgetRef ref, String? egresoId) async {
  if (egresoId == null) return null;
  final egreso = await ref.read(egresoRepositoryProvider).obtenerPorId(egresoId);
  return egreso?.cuentaFinancieraId;
}

/// Diálogo "Registrar tiempo extra" — reutilizado también para
/// "Editar" (Etapa "corrección real de Tiempo Extra"): con [existente]
/// no nulo, precarga todos los campos con los valores actuales
/// (incluyendo costos adicionales) y el botón confirma llama a
/// `corregir` en vez de `registrar`. Mismo estilo que
/// `registrar_descuento_programado_dialog.dart`.
Future<bool> mostrarDialogoRegistrarTiempoExtra(BuildContext context, WidgetRef ref, {TiempoExtraData? existente}) async {
  final l10n = AppLocalizations.of(context)!;
  final empleados = await ref.read(empleadoRepositoryProvider).listar(estatus: 'activo');
  final servicios = await ref.read(servicioRepositoryProvider).listar();
  final turnos = await ref.read(catalogoRepositoryProvider).listarModalidadesTurno();
  final cuentasFinancieras = await ref.read(cuentaFinancieraRepositoryProvider).listar(soloActivas: true);
  final tarjetasActivas = await ref.read(deudaRepositoryProvider).listarTarjetasActivas();

  DateTime fecha = existente?.fecha ?? DateTime.now();
  String? servicioId = existente?.servicioId;

  // Origen de la cobertura (Etapa "origen de cobertura"). Un alta nueva
  // arranca en "Ausencia de empleado": sigue siendo el caso dominante,
  // y así el formulario se ve igual que siempre para quien ya lo usaba.
  OrigenCoberturaTiempoExtra origenCobertura = existente == null
      ? OrigenCoberturaTiempoExtra.ausenciaEmpleado
      : (OrigenCoberturaTiempoExtra.values.asNameMap()[existente.origenCobertura] ??
          OrigenCoberturaTiempoExtra.ausenciaEmpleado);
  String? empleadoAusenteId = existente?.empleadoAusenteId;
  MotivoAusenciaTiempoExtra? motivoAusencia = existente?.motivoAusencia == null
      ? null
      : MotivoAusenciaTiempoExtra.values.byName(existente!.motivoAusencia!);
  String? vacanteOperativaId = existente?.vacanteOperativaId;
  final descripcionOrigenCtrl = TextEditingController(text: existente?.descripcionOrigen ?? '');

  // Vacantes elegibles del Servicio elegido. Se recargan al cambiar de
  // Servicio; la lista vacía es un estado legítimo (ese Servicio no
  // tiene plazas abiertas), nunca un error.
  var vacantesElegibles = const <VacanteCobertura>[];
  Future<void> recargarVacantes() async {
    final id = servicioId;
    vacantesElegibles = id == null
        ? const <VacanteCobertura>[]
        : await ref.read(vacanteCoberturaReaderProvider).elegiblesPorServicio(id);
  }

  // Al corregir, la vacante ya elegida puede haberse cubierto después:
  // se añade al catálogo del selector para no perderla de vista, aunque
  // no sería elegible para un alta nueva.
  if (existente?.vacanteOperativaId != null) {
    await recargarVacantes();
    final yaEsta = vacantesElegibles.any((v) => v.id == existente!.vacanteOperativaId);
    if (!yaEsta) {
      final actual = await ref.read(vacanteCoberturaReaderProvider).porId(existente!.vacanteOperativaId!);
      if (actual != null) vacantesElegibles = [actual, ...vacantesElegibles];
    }
  } else if (existente != null) {
    await recargarVacantes();
  }
  _TipoCobertura tipoCobertura =
      existente != null && existente.empleadoCubreId == null ? _TipoCobertura.externo : _TipoCobertura.empleado;
  String? empleadoCubreId = existente?.empleadoCubreId;
  final nombreExternoCtrl = TextEditingController(text: existente?.nombreExternoCubre ?? '');
  String? turnoId = existente?.turnoId;
  final montoCtrl = TextEditingController(text: existente == null ? '' : (existente.montoTiempoExtra / 100).toStringAsFixed(2));
  String formaPago = existente?.formaPago ?? FormaPago.efectivo.name;
  String? cuentaFinancieraId = existente == null ? null : await _resolverCuentaDesdeEgreso(ref, existente.egresoId);
  String? deudaIdTarjeta = existente?.deudaId;
  final observacionesCtrl = TextEditingController(text: existente?.observaciones ?? '');
  final motivoCorreccionCtrl = TextEditingController();
  final costos = <_CostoAdicionalCampos>[];
  final costosEliminados = <int>[];
  String? errorGeneral;

  if (existente != null) {
    final costosActuales = await ref.read(tiemposExtraControllerProvider.notifier).listarCostosAdicionales(existente.id);
    for (final costo in costosActuales) {
      final campos = _CostoAdicionalCampos(costoAdicionalId: costo.id)
        ..conceptoCtrl.text = costo.concepto
        ..montoCtrl.text = (costo.monto / 100).toStringAsFixed(2)
        ..formaPago = costo.formaPago ?? FormaPago.efectivo.name
        ..deudaIdTarjeta = costo.deudaId
        ..cuentaFinancieraId = await _resolverCuentaDesdeEgreso(ref, costo.egresoId);
      costos.add(campos);
    }
  }

  if (!context.mounted) return false;

  final resultado = await RisegDialog.showForm<bool>(
    context: context,
    title: existente == null ? l10n.registrarTiempoExtraDialogoTitulo : l10n.corregirTiempoExtraDialogoTitulo,
    confirmLabel: existente == null ? l10n.registrarTiempoExtraBotonConfirmar : l10n.corregirTiempoExtraBotonConfirmar,
    cancelLabel: l10n.compraBotonCancelarFormulario,
    contentBuilder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        return SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RisegDateField(
                  label: l10n.registrarTiempoExtraCampoFecha,
                  value: fecha,
                  onChanged: (valor) => setState(() => fecha = valor),
                ),
                const SizedBox(height: AppSpacing.md),
                RisegSelect<String?>(
                  key: const Key('tiempo_extra_campo_servicio'),
                  label: l10n.registrarTiempoExtraCampoServicio,
                  value: servicioId,
                  items: [
                    for (final s in servicios) RisegSelectItem(value: s.servicio.id, label: '${s.clienteNombre} · ${s.servicio.nombre}'),
                  ],
                  onChanged: (valor) async {
                    // Cambiar de Servicio invalida la vacante elegida si
                    // ya no pertenece al nuevo (§8).
                    servicioId = valor;
                    await recargarVacantes();
                    if (!vacantesElegibles.any((v) => v.id == vacanteOperativaId)) {
                      vacanteOperativaId = null;
                    }
                    setState(() {});
                  },
                ),
                const SizedBox(height: AppSpacing.md),
                // --- Origen de la cobertura -------------------------
                //
                // Controla qué campos siguen. Select compacto en vez de
                // tres radios en fila: a 500px una fila de tres
                // opciones no cabe sin desbordarse.
                RisegSelect<OrigenCoberturaTiempoExtra>(
                  key: const Key('tiempo_extra_campo_origen'),
                  label: l10n.origenCoberturaSeccion,
                  value: origenCobertura,
                  items: [
                    for (final o in OrigenCoberturaTiempoExtra.values)
                      RisegSelectItem(value: o, label: origenCoberturaTiempoExtraLabel(l10n, o)),
                  ],
                  onChanged: (valor) => setState(() {
                    origenCobertura = valor ?? origenCobertura;
                    // Se limpia lo que ya no aplica: el formulario no
                    // conserva campos visuales del origen anterior, y
                    // el dominio nunca recibe un residuo.
                    switch (origenCobertura) {
                      case OrigenCoberturaTiempoExtra.ausenciaEmpleado:
                        vacanteOperativaId = null;
                        descripcionOrigenCtrl.clear();
                      case OrigenCoberturaTiempoExtra.vacante:
                        empleadoAusenteId = null;
                        motivoAusencia = null;
                        descripcionOrigenCtrl.clear();
                      case OrigenCoberturaTiempoExtra.otro:
                        empleadoAusenteId = null;
                        motivoAusencia = null;
                        vacanteOperativaId = null;
                    }
                  }),
                ),
                const SizedBox(height: AppSpacing.md),
                if (origenCobertura == OrigenCoberturaTiempoExtra.ausenciaEmpleado) ...[
                  RisegSelect<String?>(
                    key: const Key('tiempo_extra_campo_empleado_ausente'),
                    label: l10n.registrarTiempoExtraCampoEmpleadoAusente,
                    value: empleadoAusenteId,
                    items: [for (final e in empleados) RisegSelectItem(value: e.id, label: empleadoNombreCompleto(e))],
                    onChanged: (valor) => setState(() => empleadoAusenteId = valor),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  RisegSelect<MotivoAusenciaTiempoExtra?>(
                    label: l10n.registrarTiempoExtraCampoMotivoAusencia,
                    value: motivoAusencia,
                    items: [
                      for (final m in MotivoAusenciaTiempoExtra.values)
                        RisegSelectItem(value: m, label: motivoAusenciaTiempoExtraLabel(l10n, m)),
                    ],
                    onChanged: (valor) => setState(() => motivoAusencia = valor),
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
                if (origenCobertura == OrigenCoberturaTiempoExtra.vacante) ...[
                  if (vacantesElegibles.isEmpty)
                    Text(
                      l10n.origenCoberturaVacanteSinOpciones,
                      style: AppTypography.caption.copyWith(color: context.colors.textMuted),
                    )
                  else
                    RisegSelect<String?>(
                      key: const Key('tiempo_extra_campo_vacante'),
                      label: l10n.origenCoberturaCampoVacante,
                      value: vacanteOperativaId,
                      items: [
                        for (final v in vacantesElegibles) RisegSelectItem(value: v.id, label: v.etiqueta),
                      ],
                      onChanged: (valor) => setState(() {
                        vacanteOperativaId = valor;
                        // El turno de la línea sirve de valor por
                        // defecto; nunca se impone si ya se eligió uno
                        // ni se inventa si la vacante no lo conoce.
                        final vacante = vacantesElegibles.where((v) => v.id == valor).firstOrNull;
                        turnoId ??= vacante?.modalidadTurnoId;
                      }),
                    ),
                  const SizedBox(height: AppSpacing.md),
                ],
                if (origenCobertura == OrigenCoberturaTiempoExtra.otro) ...[
                  RisegTextField(
                    key: const Key('tiempo_extra_campo_descripcion_origen'),
                    label: l10n.origenCoberturaCampoDescripcion,
                    controller: descripcionOrigenCtrl,
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
                Text(l10n.registrarTiempoExtraCampoQuienCubre, style: AppTypography.label),
                Row(
                  children: [
                    Radio<_TipoCobertura>(
                      key: const Key('tiempo_extra_cobertura_empleado'),
                      value: _TipoCobertura.empleado,
                      groupValue: tipoCobertura,
                      onChanged: (valor) => setState(() => tipoCobertura = valor ?? tipoCobertura),
                    ),
                    Text(l10n.registrarTiempoExtraCoberturaEmpleado),
                    const SizedBox(width: AppSpacing.md),
                    Radio<_TipoCobertura>(
                      key: const Key('tiempo_extra_cobertura_externo'),
                      value: _TipoCobertura.externo,
                      groupValue: tipoCobertura,
                      onChanged: (valor) => setState(() => tipoCobertura = valor ?? tipoCobertura),
                    ),
                    Text(l10n.registrarTiempoExtraCoberturaExterna),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                if (tipoCobertura == _TipoCobertura.empleado)
                  RisegSelect<String?>(
                    key: const Key('tiempo_extra_campo_empleado_cubre'),
                    label: l10n.registrarTiempoExtraCampoEmpleadoCubre,
                    value: empleadoCubreId,
                    items: [for (final e in empleados) RisegSelectItem(value: e.id, label: empleadoNombreCompleto(e))],
                    onChanged: (valor) => setState(() => empleadoCubreId = valor),
                  )
                else
                  RisegTextField(
                    key: const Key('tiempo_extra_campo_nombre_externo'),
                    label: l10n.registrarTiempoExtraCampoNombreExterno,
                    controller: nombreExternoCtrl,
                  ),
                const SizedBox(height: AppSpacing.md),
                RisegSelect<String?>(
                  key: const Key('tiempo_extra_campo_turno'),
                  label: l10n.registrarTiempoExtraCampoTurno,
                  value: turnoId,
                  items: [for (final t in turnos) RisegSelectItem(value: t.id, label: t.nombre)],
                  onChanged: (valor) => setState(() => turnoId = valor),
                ),
                const SizedBox(height: AppSpacing.md),
                RisegTextField(
                  key: const Key('tiempo_extra_campo_monto'),
                  label: l10n.registrarTiempoExtraCampoMontoTiempoExtra,
                  controller: montoCtrl,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: AppSpacing.md),
                RisegSelect<String>(
                  label: l10n.registrarTiempoExtraCampoFormaPago,
                  value: formaPago,
                  items: [for (final f in FormaPago.values) RisegSelectItem(value: f.name, label: formaPagoLabel(l10n, f.name))],
                  onChanged: (valor) => setState(() {
                    formaPago = valor ?? formaPago;
                    cuentaFinancieraId = null;
                    deudaIdTarjeta = null;
                  }),
                ),
                const SizedBox(height: AppSpacing.md),
                ..._camposOrigenFinanciero(
                  l10n: l10n,
                  claveCuenta: const Key('tiempo_extra_campo_cuenta_origen'),
                  claveTarjeta: const Key('tiempo_extra_campo_tarjeta'),
                  formaPago: formaPago,
                  cuentasFinancieras: cuentasFinancieras,
                  tarjetasActivas: tarjetasActivas,
                  cuentaFinancieraId: cuentaFinancieraId,
                  deudaIdTarjeta: deudaIdTarjeta,
                  onCuentaCambiada: (valor) => setState(() => cuentaFinancieraId = valor),
                  onTarjetaCambiada: (valor) => setState(() => deudaIdTarjeta = valor),
                ),
                const SizedBox(height: AppSpacing.md),
                RisegTextField(label: l10n.registrarTiempoExtraCampoObservaciones, controller: observacionesCtrl),
                const SizedBox(height: AppSpacing.lg),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        l10n.registrarTiempoExtraSeccionCostosAdicionales,
                        style: AppTypography.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    RisegButton(
                      key: const Key('tiempo_extra_boton_agregar_costo'),
                      label: l10n.registrarTiempoExtraBotonAgregarCosto,
                      variant: RisegButtonVariant.ghost,
                      icon: Icons.add,
                      onPressed: () => setState(() => costos.add(_CostoAdicionalCampos())),
                    ),
                  ],
                ),
                for (var i = 0; i < costos.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 2,
                              child: RisegTextField(
                                label: l10n.registrarTiempoExtraCampoConcepto,
                                controller: costos[i].conceptoCtrl,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: RisegTextField(
                                label: l10n.registrarTiempoExtraCampoMontoCosto,
                                controller: costos[i].montoCtrl,
                                keyboardType: TextInputType.number,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => setState(() {
                                if (costos[i].costoAdicionalId != null) {
                                  costosEliminados.add(costos[i].costoAdicionalId!);
                                }
                                costos[i].dispose();
                                costos.removeAt(i);
                              }),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        RisegSelect<String>(
                          label: l10n.registrarTiempoExtraCampoFormaPagoCosto,
                          value: costos[i].formaPago,
                          items: [for (final f in FormaPago.values) RisegSelectItem(value: f.name, label: formaPagoLabel(l10n, f.name))],
                          onChanged: (valor) => setState(() {
                            costos[i].formaPago = valor ?? costos[i].formaPago;
                            costos[i].cuentaFinancieraId = null;
                            costos[i].deudaIdTarjeta = null;
                          }),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        ..._camposOrigenFinanciero(
                          l10n: l10n,
                          formaPago: costos[i].formaPago,
                          cuentasFinancieras: cuentasFinancieras,
                          tarjetasActivas: tarjetasActivas,
                          cuentaFinancieraId: costos[i].cuentaFinancieraId,
                          deudaIdTarjeta: costos[i].deudaIdTarjeta,
                          onCuentaCambiada: (valor) => setState(() => costos[i].cuentaFinancieraId = valor),
                          onTarjetaCambiada: (valor) => setState(() => costos[i].deudaIdTarjeta = valor),
                        ),
                      ],
                    ),
                  ),
                if (existente != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  RisegTextField(label: l10n.corregirTiempoExtraCampoMotivo, controller: motivoCorreccionCtrl),
                ],
                if (errorGeneral != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(errorGeneral!, style: AppTypography.caption.copyWith(color: Theme.of(dialogContext).colorScheme.error)),
                ],
              ],
            ),
          ),
        );
      },
    ),
    onConfirm: () async {
      if (servicioId == null) {
        errorGeneral = l10n.registrarTiempoExtraErrorServicioRequerido;
        return null;
      }
      // Qué campos son obligatorios lo decide el ORIGEN, y lo decide
      // en un solo lugar: `TiempoExtraValidator.validarOrigen`, la
      // misma función que vuelve a aplicar el caso de uso. El diálogo
      // no repite la regla, sólo traduce su veredicto a un mensaje.
      final descripcionOrigen =
          descripcionOrigenCtrl.text.trim().isEmpty ? null : descripcionOrigenCtrl.text.trim();
      final validacionOrigen = TiempoExtraValidator.validarOrigen(
        origen: origenCobertura,
        empleadoAusenteId: empleadoAusenteId,
        motivoAusencia: motivoAusencia?.name,
        vacanteOperativaId: vacanteOperativaId,
        descripcionOrigen: descripcionOrigen,
      );
      if (validacionOrigen != TiempoExtraOrigenValidacion.valida) {
        errorGeneral = _errorOrigenTexto(l10n, validacionOrigen);
        return null;
      }
      final nombreExterno = nombreExternoCtrl.text.trim().isEmpty ? null : nombreExternoCtrl.text.trim();
      final validacion = TiempoExtraValidator.validarCobertura(
        empleadoCubreId: tipoCobertura == _TipoCobertura.empleado ? empleadoCubreId : null,
        nombreExternoCubre: tipoCobertura == _TipoCobertura.externo ? nombreExterno : null,
      );
      if (validacion != TiempoExtraCoberturaValidacion.valida) {
        errorGeneral = validacion == TiempoExtraCoberturaValidacion.faltaCobertura
            ? l10n.registrarTiempoExtraErrorCoberturaFaltante
            : l10n.registrarTiempoExtraErrorCoberturaAmbigua;
        return null;
      }
      if (turnoId == null) {
        errorGeneral = l10n.registrarTiempoExtraErrorTurnoRequerido;
        return null;
      }
      final monto = _centavosDesdeTexto(montoCtrl.text);
      if (monto == null || monto <= 0) {
        errorGeneral = l10n.registrarTiempoExtraErrorMontoInvalido;
        return null;
      }
      // Origen financiero del pago base — el diálogo real SIEMPRE lo
      // exige (Etapa "origen financiero unificado": "no obliga a
      // identificar de manera estructurada el origen"), aunque el
      // dominio lo acepte sin especificar para pruebas/fixtures que
      // nunca pasan por esta UI.
      if (formaPago == FormaPago.tarjeta.name ? deudaIdTarjeta == null : cuentaFinancieraId == null) {
        errorGeneral = l10n.registrarTiempoExtraErrorOrigenFinancieroRequerido(l10n.registrarTiempoExtraCampoMontoTiempoExtra);
        return null;
      }
      final costosAdicionales = <CostoAdicionalInput>[];
      for (final costo in costos) {
        final montoCosto = _centavosDesdeTexto(costo.montoCtrl.text);
        if (costo.conceptoCtrl.text.trim().isEmpty || montoCosto == null || montoCosto <= 0) {
          errorGeneral = l10n.registrarTiempoExtraErrorCostoAdicionalInvalido;
          return null;
        }
        if (costo.formaPago == FormaPago.tarjeta.name ? costo.deudaIdTarjeta == null : costo.cuentaFinancieraId == null) {
          errorGeneral = l10n.registrarTiempoExtraErrorOrigenFinancieroRequerido(costo.conceptoCtrl.text.trim());
          return null;
        }
        costosAdicionales.add(CostoAdicionalInput(
          concepto: costo.conceptoCtrl.text.trim(),
          monto: montoCosto,
          formaPago: costo.formaPago,
          cuentaFinancieraId: costo.cuentaFinancieraId,
          deudaIdTarjeta: costo.deudaIdTarjeta,
        ));
      }

      if (existente == null) {
        // Saldo insuficiente no es un "error inesperado": lo traduce el
        // mecanismo central y el formulario sigue abierto, con lo ya
        // capturado, para que el usuario elija otra cuenta.
        final resultado = await ejecutarMostrandoSaldoInsuficiente(
          context,
          l10n,
          () => ref.read(tiemposExtraControllerProvider.notifier).registrar(
              fecha: fecha,
              servicioId: servicioId!,
              origenCobertura: origenCobertura.name,
              empleadoAusenteId: empleadoAusenteId,
              motivoAusencia: motivoAusencia?.name,
              vacanteOperativaId: vacanteOperativaId,
              descripcionOrigen: descripcionOrigen,
              empleadoCubreId: tipoCobertura == _TipoCobertura.empleado ? empleadoCubreId : null,
              nombreExternoCubre: tipoCobertura == _TipoCobertura.externo ? nombreExterno : null,
              turnoId: turnoId!,
              montoTiempoExtra: monto,
              formaPago: formaPago,
              cuentaFinancieraId: cuentaFinancieraId,
              deudaIdTarjeta: deudaIdTarjeta,
              observaciones: observacionesCtrl.text.trim().isEmpty ? null : observacionesCtrl.text.trim(),
              costosAdicionales: costosAdicionales,
            ),
        );
        if (resultado == null) return null;
        if (!context.mounted) return false;

        switch (resultado) {
          case RegistrarTiempoExtraExitoso():
            RisegFeedback.showSuccess(context, l10n.registrarTiempoExtraExito);
            return true;
          case RegistrarTiempoExtraCoberturaInvalida(:final validacion):
            errorGeneral = validacion == TiempoExtraCoberturaValidacion.faltaCobertura
                ? l10n.registrarTiempoExtraErrorCoberturaFaltante
                : l10n.registrarTiempoExtraErrorCoberturaAmbigua;
            return null;
          case RegistrarTiempoExtraServicioNoExiste():
            errorGeneral = l10n.registrarTiempoExtraErrorServicioRequerido;
            return null;
          case RegistrarTiempoExtraEmpleadoAusenteNoExiste():
          case RegistrarTiempoExtraEmpleadoCubreNoExiste():
            errorGeneral = l10n.registrarTiempoExtraErrorEmpleadoAusenteRequerido;
            return null;
          case RegistrarTiempoExtraOrigenInvalido(:final validacion):
            errorGeneral = _errorOrigenTexto(l10n, validacion);
            return null;
          case RegistrarTiempoExtraDescripcionOrigenMuyLarga():
            errorGeneral = l10n.registrarTiempoExtraErrorDescripcionOrigenMuyLarga;
            return null;
          case RegistrarTiempoExtraAusenteYCubreSonElMismo():
            errorGeneral = l10n.registrarTiempoExtraErrorAusenteYCubreSonElMismo;
            return null;
          case RegistrarTiempoExtraVacanteNoExiste():
          case RegistrarTiempoExtraVacanteDeOtroServicio():
          case RegistrarTiempoExtraVacanteNoElegible():
            errorGeneral = l10n.registrarTiempoExtraErrorVacanteInvalida;
            return null;
          case RegistrarTiempoExtraMontoInvalido():
            errorGeneral = l10n.registrarTiempoExtraErrorMontoInvalido;
            return null;
          case RegistrarTiempoExtraOrigenFinancieroRequerido(:final item):
            errorGeneral = l10n.registrarTiempoExtraErrorOrigenFinancieroRequerido(item);
            return null;
          case RegistrarTiempoExtraTarjetaInvalida(:final item):
            errorGeneral = l10n.registrarTiempoExtraErrorTarjetaInvalida(item);
            return null;
          case RegistrarTiempoExtraTarjetaSinLimiteConfigurado(:final item):
            errorGeneral = l10n.registrarTiempoExtraErrorTarjetaSinLimiteConfigurado(item);
            return null;
          case RegistrarTiempoExtraTarjetaExcedeLimite(:final item, :final disponible):
            errorGeneral = l10n.registrarTiempoExtraErrorTarjetaExcedeLimite(item, formatoCentavosDeuda(disponible));
            return null;
          case RegistrarTiempoExtraErrorInesperado():
            RisegFeedback.showError(context, l10n.registrarTiempoExtraErrorInesperado);
            return false;
        }
      }

      final motivo = motivoCorreccionCtrl.text.trim();
      if (motivo.isEmpty) {
        errorGeneral = l10n.corregirTiempoExtraErrorMotivoRequerido;
        return null;
      }
      final cambiosCostos = <CorreccionCostoAdicional>[
        for (final costo in costos)
          if (costo.costoAdicionalId != null)
            CorreccionCostoAdicionalEditar(
              costoAdicionalId: costo.costoAdicionalId!,
              concepto: costo.conceptoCtrl.text.trim(),
              monto: _centavosDesdeTexto(costo.montoCtrl.text)!,
              formaPago: costo.formaPago,
              cuentaFinancieraId: costo.cuentaFinancieraId,
              deudaIdTarjeta: costo.deudaIdTarjeta,
            )
          else
            CorreccionCostoAdicionalAgregar(
              concepto: costo.conceptoCtrl.text.trim(),
              monto: _centavosDesdeTexto(costo.montoCtrl.text)!,
              formaPago: costo.formaPago,
              cuentaFinancieraId: costo.cuentaFinancieraId,
              deudaIdTarjeta: costo.deudaIdTarjeta,
            ),
        for (final id in costosEliminados) CorreccionCostoAdicionalQuitar(id),
      ];

      final resultadoCorreccion = await ref.read(tiemposExtraControllerProvider.notifier).corregir(
            tiempoExtraId: existente.id,
            fecha: fecha,
            servicioId: servicioId!,
            origenCobertura: origenCobertura.name,
            empleadoAusenteId: empleadoAusenteId,
            motivoAusencia: motivoAusencia?.name,
            vacanteOperativaId: vacanteOperativaId,
            descripcionOrigen: descripcionOrigen,
            empleadoCubreId: tipoCobertura == _TipoCobertura.empleado ? empleadoCubreId : null,
            nombreExternoCubre: tipoCobertura == _TipoCobertura.externo ? nombreExterno : null,
            turnoId: turnoId!,
            montoTiempoExtra: monto,
            formaPago: formaPago,
            cuentaFinancieraId: cuentaFinancieraId,
            deudaIdTarjeta: deudaIdTarjeta,
            observaciones: observacionesCtrl.text.trim().isEmpty ? null : observacionesCtrl.text.trim(),
            cambiosCostos: cambiosCostos,
            motivo: motivo,
          );
      if (!context.mounted) return false;

      switch (resultadoCorreccion) {
        case CorregirTiempoExtraExitoso():
          RisegFeedback.showSuccess(context, l10n.corregirTiempoExtraExito);
          return true;
        case CorregirTiempoExtraNoExiste():
          RisegFeedback.showError(context, l10n.tiempoExtraDetalleNoExiste);
          return false;
        case CorregirTiempoExtraYaCancelado():
          RisegFeedback.showError(context, l10n.corregirTiempoExtraErrorYaCancelado);
          return false;
        case CorregirTiempoExtraCoberturaInvalida(:final validacion):
          errorGeneral = validacion == TiempoExtraCoberturaValidacion.faltaCobertura
              ? l10n.registrarTiempoExtraErrorCoberturaFaltante
              : l10n.registrarTiempoExtraErrorCoberturaAmbigua;
          return null;
        case CorregirTiempoExtraServicioNoExiste():
          errorGeneral = l10n.registrarTiempoExtraErrorServicioRequerido;
          return null;
        case CorregirTiempoExtraEmpleadoAusenteNoExiste():
        case CorregirTiempoExtraEmpleadoCubreNoExiste():
          errorGeneral = l10n.registrarTiempoExtraErrorEmpleadoAusenteRequerido;
          return null;
        case CorregirTiempoExtraOrigenInvalido(:final validacion):
          errorGeneral = _errorOrigenTexto(l10n, validacion);
          return null;
        case CorregirTiempoExtraDescripcionOrigenMuyLarga():
          errorGeneral = l10n.registrarTiempoExtraErrorDescripcionOrigenMuyLarga;
          return null;
        case CorregirTiempoExtraAusenteYCubreSonElMismo():
          errorGeneral = l10n.registrarTiempoExtraErrorAusenteYCubreSonElMismo;
          return null;
        case CorregirTiempoExtraVacanteNoExiste():
        case CorregirTiempoExtraVacanteDeOtroServicio():
        case CorregirTiempoExtraVacanteNoElegible():
          errorGeneral = l10n.registrarTiempoExtraErrorVacanteInvalida;
          return null;
        case CorregirTiempoExtraMontoInvalido():
          errorGeneral = l10n.registrarTiempoExtraErrorMontoInvalido;
          return null;
        case CorregirTiempoExtraOrigenFinancieroRequerido(:final item):
          errorGeneral = l10n.registrarTiempoExtraErrorOrigenFinancieroRequerido(item);
          return null;
        case CorregirTiempoExtraTarjetaInvalida(:final item):
          errorGeneral = l10n.registrarTiempoExtraErrorTarjetaInvalida(item);
          return null;
        case CorregirTiempoExtraTarjetaSinLimiteConfigurado(:final item):
          errorGeneral = l10n.registrarTiempoExtraErrorTarjetaSinLimiteConfigurado(item);
          return null;
        case CorregirTiempoExtraTarjetaExcedeLimite(:final item, :final disponible):
          errorGeneral = l10n.registrarTiempoExtraErrorTarjetaExcedeLimite(item, formatoCentavosDeuda(disponible));
          return null;
        case CorregirTiempoExtraErrorInesperado():
          RisegFeedback.showError(context, l10n.registrarTiempoExtraErrorInesperado);
          return false;
      }
    },
  );

  // Los `TextEditingController` NO se destruyen aquí a propósito.
  //
  // `RisegDialog.showForm` resuelve su Future al INICIAR la transición
  // de salida: los `TextFormField` siguen montados un frame más. Un
  // `dispose()` síncrono en este punto estalla con "A
  // TextEditingController was used after being disposed" y puede
  // corromper el árbol de widgets — el mismo bug real ya documentado
  // en `_AltaSucursalForm` y en Finanzas → Categorías.
  //
  // Lo destapó la prueba de integración del botón Registrar
  // (`registrar_tiempo_extra_submit_test.dart`): es la primera vez que
  // alguien recorre este formulario de punta a punta.
  //
  // DEUDA: la corrección de fondo es que el contenido del diálogo sea
  // su propio `StatefulWidget`, dueño de sus controladores y quien los
  // destruya en su `dispose()`. Es un refactor del formulario
  // completo, fuera del alcance de esta corrección.

  return resultado ?? false;
}
