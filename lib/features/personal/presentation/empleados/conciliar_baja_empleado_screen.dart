import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/inventario/inventario_providers.dart'
    show articuloRepositoryProvider, asignacionRepositoryProvider;
import 'package:riseg_one/features/telefonia/telefonia_providers.dart' show asignacionLineaTelefonicaRepositoryProvider;
import 'package:riseg_one/features/vehiculos/vehiculos_providers.dart'
    show asignacionVehiculoRepositoryProvider, vehiculoRepositoryProvider;

import '../../data/tables/conciliacion_baja_table.dart';
import '../../data/tables/empleado_table.dart';
import '../../domain/usecases/conciliar_baja_empleado_usecase.dart';
import '../../personal_providers.dart';
import 'empleados_list_screen.dart' show empleadoNombreCompleto;

String _pesos(int centavos) => NumberFormat.currency(locale: 'es_MX', symbol: r'$').format(centavos / 100);

/// Un bien cargado por FK, con su borrador de resolución.
class _Renglon {
  _Renglon({required this.etiqueta, this.asignacionId, this.asignacionVehiculoId});

  final String etiqueta;
  final String? asignacionId;
  final String? asignacionVehiculoId;

  ResolucionResguardoBaja? resolucion;
  CondicionDevolucionResguardo? condicion;
  DestinoDevolucionResguardo? destino;
  MotivoNoEntregaResguardo? motivoNoEntrega;
  final motivoOtroCtrl = TextEditingController();
  String? autorizadorEmpleadoId;
  String? receptorEmpleadoId;
  bool generaDescuento = false;
  final importeCtrl = TextEditingController();
  final conceptoCtrl = TextEditingController();
  final motivoNoCobroCtrl = TextEditingController();

  bool get esVehiculo => asignacionVehiculoId != null;
  bool get resuelto => resolucion != null;

  int? get importeCentavos {
    final texto = importeCtrl.text.trim().replaceAll(',', '');
    if (texto.isEmpty) return null;
    final pesos = double.tryParse(texto);
    return pesos == null ? null : (pesos * 100).round();
  }

  void dispose() {
    motivoOtroCtrl.dispose();
    importeCtrl.dispose();
    conceptoCtrl.dispose();
    motivoNoCobroCtrl.dispose();
  }

  ResolucionResguardo aResolucion() {
    return ResolucionResguardo(
      asignacionId: asignacionId,
      asignacionVehiculoId: asignacionVehiculoId,
      resolucion: resolucion!,
      condicion: condicion,
      destino: esVehiculo ? null : destino,
      motivoNoEntrega: motivoNoEntrega,
      motivoNoEntregaOtro: motivoOtroCtrl.text.trim().isEmpty ? null : motivoOtroCtrl.text.trim(),
      autorizadorEmpleadoId: autorizadorEmpleadoId,
      receptorEmpleadoId: receptorEmpleadoId,
      generaDescuento: generaDescuento,
      importeDescuento: importeCentavos,
      conceptoDescuento: conceptoCtrl.text.trim().isEmpty ? null : conceptoCtrl.text.trim(),
      motivoNoCobro: motivoNoCobroCtrl.text.trim().isEmpty ? null : motivoNoCobroCtrl.text.trim(),
    );
  }
}

/// Baja laboral con conciliación obligatoria de resguardos
/// (schemaVersion 83).
///
/// Pantalla completa y no un diálogo: la baja dejó de ser "fecha +
/// motivo" para volverse la operación que cierra todo lo que la persona
/// tenía bajo su responsabilidad. Sigue el patrón de formulario amplio
/// que el proyecto ya usa para Compras, en vez de inventar un
/// componente de wizard que no existe en el design system.
///
/// Las secciones son los pasos de §19 — Datos, Relaciones, Resguardo
/// físico, Vehículos, Cargos y Resumen — pero recorribles de un
/// vistazo: el operador necesita ver el total de obligaciones mientras
/// ajusta un renglón, no navegar hacia atrás para comprobarlo.
class ConciliarBajaEmpleadoScreen extends ConsumerStatefulWidget {
  const ConciliarBajaEmpleadoScreen({required this.empleadoId, super.key});

  final String empleadoId;

  @override
  ConsumerState<ConciliarBajaEmpleadoScreen> createState() => _ConciliarBajaEmpleadoScreenState();
}

class _ConciliarBajaEmpleadoScreenState extends ConsumerState<ConciliarBajaEmpleadoScreen> {
  EmpleadoData? _empleado;
  DateTime _fechaBaja = DateTime.now();
  MotivoBajaEmpleado _motivo = MotivoBajaEmpleado.renuncia;
  final _observacionesCtrl = TextEditingController();

  List<_Renglon> _renglones = const [];
  String? _servicioVigente;
  List<String> _lineasVigentes = const [];
  bool _cargando = true;
  bool _guardando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _observacionesCtrl.dispose();
    for (final r in _renglones) {
      r.dispose();
    }
    super.dispose();
  }

  /// §2 — todo por FK desde las asignaciones vigentes. Nunca se le pide
  /// al usuario recordar qué tiene la persona.
  Future<void> _cargar() async {
    final empleado = await ref.read(empleadoRepositoryProvider).obtenerPorId(widget.empleadoId);
    final asignaciones = await ref.read(asignacionRepositoryProvider).listarActivasPorEmpleado(widget.empleadoId);
    final vehiculos =
        await ref.read(asignacionVehiculoRepositoryProvider).listarActivasPorEmpleado(widget.empleadoId);
    final servicio = await ref.read(asignacionServicioRepositoryProvider).obtenerActivaPorEmpleado(widget.empleadoId);
    final linea = await ref.read(asignacionLineaTelefonicaRepositoryProvider).obtenerActivaPorEmpleado(widget.empleadoId);

    final articuloRepo = ref.read(articuloRepositoryProvider);
    final vehiculoRepo = ref.read(vehiculoRepositoryProvider);
    final renglones = <_Renglon>[];
    for (final a in asignaciones) {
      final articulo = await articuloRepo.obtenerPorId(a.articuloId);
      renglones.add(_Renglon(etiqueta: articulo?.nombre ?? a.articuloId, asignacionId: a.id));
    }
    for (final v in vehiculos) {
      final vehiculo = await vehiculoRepo.obtenerPorId(v.vehiculoId);
      renglones.add(_Renglon(
        etiqueta: vehiculo == null ? v.vehiculoId : '${vehiculo.marca} ${vehiculo.modelo} (${vehiculo.codigo})',
        asignacionVehiculoId: v.id,
      ));
    }

    if (!mounted) return;
    setState(() {
      _empleado = empleado;
      _renglones = renglones;
      _servicioVigente = servicio?.servicioId;
      _lineasVigentes = linea == null ? const [] : [linea.lineaTelefonicaId];
      _cargando = false;
    });
  }

  /// §16 — el botón se mantiene bloqueado mientras exista un bien sin
  /// resolución. No exige que todo esté devuelto: exige saber qué pasó.
  bool get _puedeConfirmar => _renglones.every((r) => r.resuelto);

  int get _totalObligaciones =>
      _renglones.where((r) => r.generaDescuento).fold<int>(0, (s, r) => s + (r.importeCentavos ?? 0));

  Future<void> _confirmar() async {
    setState(() {
      _guardando = true;
      _error = null;
    });
    final l10n = AppLocalizations.of(context)!;
    final resultado = await ref.read(conciliarBajaEmpleadoAutorizadoProvider)(
      empleadoId: widget.empleadoId,
      fechaBaja: _fechaBaja,
      motivo: _motivo,
      observaciones: _observacionesCtrl.text,
      resoluciones: [for (final r in _renglones) r.aResolucion()],
    );
    if (!mounted) return;
    setState(() => _guardando = false);

    switch (resultado) {
      case ConciliarBajaEmpleadoExitoso():
        RisegFeedback.showSuccess(context, l10n.conciliacionBajaExito);
        Navigator.of(context).pop(true);
      case ConciliarBajaEmpleadoResguardosSinResolver():
        setState(() => _error = l10n.conciliacionBajaErrorSinResolver);
      case ConciliarBajaEmpleadoResolucionInvalida(:final detalle):
        setState(() => _error = detalle);
      case ConciliarBajaEmpleadoAutorizadorInvalido():
        setState(() => _error = l10n.conciliacionBajaErrorAutorizadorInvalido);
      case ConciliarBajaEmpleadoBajaRechazada():
      case ConciliarBajaEmpleadoErrorInesperado():
        setState(() => _error = l10n.conciliacionBajaErrorInesperado);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;
    final empleado = _empleado;

    if (_cargando || empleado == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final administrativos = ref.watch(personalAdministrativoActivoProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.conciliacionBajaTitulo)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(empleadoNombreCompleto(empleado), style: AppTypography.heading2),
                const SizedBox(height: AppSpacing.lg),

                // --- Paso 1: datos de la baja ---
                RisegCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      RisegSectionHeader(title: l10n.conciliacionBajaPasoDatos),
                      const SizedBox(height: AppSpacing.sm),
                      RisegDateField(
                        label: l10n.empleadoCampoFechaBaja,
                        value: _fechaBaja,
                        onChanged: (valor) => setState(() => _fechaBaja = valor),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      RisegSelect<MotivoBajaEmpleado>(
                        label: l10n.empleadoCampoMotivoBaja,
                        value: _motivo,
                        items: [
                          for (final m in MotivoBajaEmpleado.values) RisegSelectItem(value: m, label: m.name),
                        ],
                        onChanged: (valor) => setState(() => _motivo = valor ?? _motivo),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      RisegTextField(
                        label: l10n.empleadoCampoObservacionesBaja,
                        controller: _observacionesCtrl,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),

                // --- Paso 2: relaciones lógicas ---
                RisegCard(
                  key: const Key('conciliacion_relaciones'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      RisegSectionHeader(title: l10n.conciliacionBajaPasoRelaciones),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        l10n.conciliacionBajaRelacionesAyuda,
                        style: AppTypography.caption.copyWith(color: colors.textMuted),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      if (_servicioVigente == null && _lineasVigentes.isEmpty)
                        Text(l10n.conciliacionBajaSinRelaciones, style: AppTypography.body)
                      else ...[
                        if (_servicioVigente != null) Text('• ${l10n.conciliacionBajaRelacionServicio}'),
                        for (final _ in _lineasVigentes) Text('• ${l10n.conciliacionBajaRelacionLinea}'),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),

                // --- Pasos 3 y 4: bienes físicos y vehículos ---
                RisegCard(
                  key: const Key('conciliacion_resguardos'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      RisegSectionHeader(title: l10n.conciliacionBajaPasoResguardos),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        l10n.conciliacionBajaResguardosAyuda,
                        style: AppTypography.caption.copyWith(color: colors.textMuted),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      if (_renglones.isEmpty)
                        Text(l10n.conciliacionBajaSinResguardos, style: AppTypography.body)
                      else
                        for (final renglon in _renglones)
                          _RenglonEditor(
                            renglon: renglon,
                            administrativos: administrativos.valueOrNull ?? const [],
                            onCambio: () => setState(() {}),
                          ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),

                // --- Pasos 5 y 6: cargos y resumen ---
                RisegCard(
                  key: const Key('conciliacion_resumen'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      RisegSectionHeader(title: l10n.conciliacionBajaPasoResumen),
                      const SizedBox(height: AppSpacing.sm),
                      for (final r in _renglones)
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
                          child: Text(
                            '${r.etiqueta} — ${r.resolucion?.name ?? l10n.conciliacionBajaSinResolver}'
                            '${r.generaDescuento && r.importeCentavos != null ? ' · ${_pesos(r.importeCentavos!)}' : ''}',
                            style: AppTypography.caption,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        l10n.conciliacionBajaTotalObligaciones(_pesos(_totalObligaciones)),
                        style: AppTypography.label,
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          _error!,
                          key: const Key('conciliacion_error'),
                          style: AppTypography.caption.copyWith(color: Theme.of(context).colorScheme.error),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.md),
                      Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.sm,
                        children: [
                          RisegButton(
                            key: const Key('conciliacion_confirmar'),
                            label: l10n.conciliacionBajaBotonConfirmar,
                            // §16 — bloqueado mientras falte explicar
                            // qué pasó con algún bien.
                            onPressed: (_puedeConfirmar && !_guardando) ? _confirmar : null,
                          ),
                          RisegButton(
                            label: l10n.bajaLaboralEmpleadoBotonCancelar,
                            variant: RisegButtonVariant.ghost,
                            onPressed: () => Navigator.of(context).pop(false),
                          ),
                        ],
                      ),
                      if (!_puedeConfirmar) ...[
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          l10n.conciliacionBajaBloqueadoAyuda,
                          style: AppTypography.caption.copyWith(color: colors.textMuted),
                        ),
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
}

/// El editor de UN bien. Muestra solo lo que su resolución exige — un
/// bien devuelto no pregunta por qué no se entregó.
class _RenglonEditor extends StatelessWidget {
  const _RenglonEditor({required this.renglon, required this.administrativos, required this.onCambio});

  final _Renglon renglon;
  final List<({EmpleadoData empleado, String? puesto})> administrativos;
  final VoidCallback onCambio;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final r = renglon;
    final opciones = ResolucionResguardoBaja.values.where((v) => !r.esVehiculo || v.aplicaAVehiculo);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(r.etiqueta, style: AppTypography.label, overflow: TextOverflow.ellipsis),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.sm,
            children: [
              SizedBox(
                width: 220,
                child: RisegSelect<ResolucionResguardoBaja>(
                  key: Key('resolucion_${r.asignacionId ?? r.asignacionVehiculoId}'),
                  label: l10n.conciliacionBajaCampoResolucion,
                  value: r.resolucion,
                  items: [for (final v in opciones) RisegSelectItem(value: v, label: v.name)],
                  onChanged: (valor) {
                    r.resolucion = valor;
                    onCambio();
                  },
                ),
              ),
              if (r.resolucion?.exigeCondicionYDestino ?? false) ...[
                SizedBox(
                  width: 180,
                  child: RisegSelect<CondicionDevolucionResguardo>(
                    label: l10n.conciliacionBajaCampoCondicion,
                    value: r.condicion,
                    items: [
                      for (final v in CondicionDevolucionResguardo.values) RisegSelectItem(value: v, label: v.name),
                    ],
                    onChanged: (valor) {
                      r.condicion = valor;
                      onCambio();
                    },
                  ),
                ),
                if (!r.esVehiculo)
                  SizedBox(
                    width: 200,
                    child: RisegSelect<DestinoDevolucionResguardo>(
                      label: l10n.conciliacionBajaCampoDestino,
                      value: r.destino,
                      items: [
                        for (final v in DestinoDevolucionResguardo.values) RisegSelectItem(value: v, label: v.name),
                      ],
                      onChanged: (valor) {
                        r.destino = valor;
                        onCambio();
                      },
                    ),
                  ),
                SizedBox(
                  width: 240,
                  child: _SelectorAdministrativo(
                    label: l10n.conciliacionBajaCampoReceptor,
                    valor: r.receptorEmpleadoId,
                    administrativos: administrativos,
                    onChanged: (valor) {
                      r.receptorEmpleadoId = valor;
                      onCambio();
                    },
                  ),
                ),
              ],
              if (r.resolucion?.exigeMotivoNoEntrega ?? false) ...[
                SizedBox(
                  width: 240,
                  child: RisegSelect<MotivoNoEntregaResguardo>(
                    label: l10n.conciliacionBajaCampoMotivoNoEntrega,
                    value: r.motivoNoEntrega,
                    items: [
                      for (final v in MotivoNoEntregaResguardo.values) RisegSelectItem(value: v, label: v.name),
                    ],
                    onChanged: (valor) {
                      r.motivoNoEntrega = valor;
                      onCambio();
                    },
                  ),
                ),
                if (r.motivoNoEntrega?.requiereTexto ?? false)
                  SizedBox(
                    width: 260,
                    child: RisegTextField(
                      label: l10n.conciliacionBajaCampoMotivoOtro,
                      controller: r.motivoOtroCtrl,
                    ),
                  ),
              ],
              SizedBox(
                width: 220,
                child: RisegSelect<bool>(
                  label: l10n.conciliacionBajaCampoGeneraDescuento,
                  value: r.generaDescuento,
                  items: [
                    RisegSelectItem(value: false, label: l10n.conciliacionBajaNo),
                    RisegSelectItem(value: true, label: l10n.conciliacionBajaSi),
                  ],
                  onChanged: (valor) {
                    r.generaDescuento = valor ?? false;
                    onCambio();
                  },
                ),
              ),
              if (r.generaDescuento) ...[
                SizedBox(
                  width: 160,
                  child: RisegTextField(
                    key: Key('importe_${r.asignacionId ?? r.asignacionVehiculoId}'),
                    label: l10n.conciliacionBajaCampoImporte,
                    controller: r.importeCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => onCambio(),
                  ),
                ),
                SizedBox(
                  width: 240,
                  child: RisegTextField(
                    label: l10n.conciliacionBajaCampoConcepto,
                    controller: r.conceptoCtrl,
                  ),
                ),
              ] else ...[
                // §11 — no cobrar nunca es un "No" barato.
                SizedBox(
                  width: 260,
                  child: RisegTextField(
                    label: l10n.conciliacionBajaCampoMotivoNoCobro,
                    controller: r.motivoNoCobroCtrl,
                  ),
                ),
                SizedBox(
                  width: 240,
                  child: _SelectorAdministrativo(
                    label: l10n.conciliacionBajaCampoAutorizador,
                    valor: r.autorizadorEmpleadoId,
                    administrativos: administrativos,
                    onChanged: (valor) {
                      r.autorizadorEmpleadoId = valor;
                      onCambio();
                    },
                  ),
                ),
              ],
            ],
          ),
          const Divider(height: AppSpacing.lg),
        ],
      ),
    );
  }
}

/// §9/§14 — solo personal administrativo ACTIVO, mostrado como
/// "Juan Cruz — Operaciones" y guardado por FK.
class _SelectorAdministrativo extends StatelessWidget {
  const _SelectorAdministrativo({
    required this.label,
    required this.valor,
    required this.administrativos,
    required this.onChanged,
  });

  final String label;
  final String? valor;
  final List<({EmpleadoData empleado, String? puesto})> administrativos;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return RisegSelect<String?>(
      label: label,
      value: valor,
      items: [
        for (final a in administrativos)
          RisegSelectItem(
            value: a.empleado.id,
            label: a.puesto == null
                ? empleadoNombreCompleto(a.empleado)
                : '${empleadoNombreCompleto(a.empleado)} — ${a.puesto}',
          ),
      ],
      onChanged: onChanged,
    );
  }
}
