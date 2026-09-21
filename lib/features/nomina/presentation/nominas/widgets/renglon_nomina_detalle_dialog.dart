import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/descuentos_personal/descuentos_personal_providers.dart';
import 'package:riseg_one/features/finanzas/presentation/pagos/pagos_list_screen.dart' show formatoCentavosPago;
import 'package:riseg_one/features/inventario/inventario_providers.dart';
import 'package:riseg_one/features/nomina/data/tables/nomina_empleado_table.dart';
import 'package:riseg_one/features/nomina/domain/usecases/actualizar_renglon_nomina_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/calcular_totales_renglon_nomina.dart';
import 'package:riseg_one/features/nomina/domain/usecases/corregir_renglon_nomina_usecase.dart';
import 'package:riseg_one/features/organizacion/presentation/shared/campo_consulta.dart';
import 'package:riseg_one/features/tiempos_extra/data/tables/tiempo_extra_table.dart';
import 'package:riseg_one/features/tiempos_extra/presentation/widgets/tiempo_extra_labels.dart';
import 'package:riseg_one/features/usuarios/usuarios_providers.dart' show permissionServiceProvider;

import '../../../nomina_providers.dart';
import '../nominas_controller.dart';
import '../nominas_list_screen.dart' show nominaEstatusLabel;

final _formatoFecha = DateFormat('dd/MM/yyyy');

String _fuenteSueldoLabel(AppLocalizations l10n, String valor) {
  return switch (FuenteSueldoNomina.values.byName(valor)) {
    FuenteSueldoNomina.servicio => l10n.nominaFuenteSueldoServicio,
    FuenteSueldoNomina.administrativo => l10n.nominaFuenteSueldoAdministrativo,
  };
}

/// Modo de captura de la sección Asistencia (Etapa 15, calculadora
/// auditable) — solo uno de los dos es editable a la vez, el otro
/// siempre se deriva de `diasPagables − el capturado`, así que nunca
/// existe un estado donde ambos se hayan capturado independientemente
/// (imposible por construcción llegar a "laborados + faltas > periodo").
enum _ModoAsistencia { diasLaborados, faltas }

/// Detalle de un renglón de Nómina (Etapa 6C, rediseñado en Etapa 15
/// como calculadora auditable) — banco/cuenta/CLABE, cálculo del
/// periodo, asistencia, percepciones/deducciones, neto, distribución
/// Fiscal/No fiscal e historial de pagos.
///
/// Todo lo que se ve mientras se edita es un espejo LOCAL de solo
/// lectura (`calcularTotalesRenglonNomina`, la misma función pura que
/// usa el repositorio) — nunca una fórmula distinta calculada aquí; el
/// valor persistido solo cambia al presionar "Guardar cambios"
/// (`NominasController.actualizarRenglon`, una sola escritura
/// transaccional que reemplaza los antiguos "Guardar movimientos" +
/// "Guardar distribución"). Cancelar (la X) nunca llama a ningún caso
/// de uso.
///
/// Devuelve `true` (al cerrarse) si algo cambió, para que el listado se
/// recargue.
class RenglonNominaDetalleDialog extends ConsumerStatefulWidget {
  const RenglonNominaDetalleDialog({required this.nominaEmpleadoId, required this.nominaCerrada, super.key});

  final String nominaEmpleadoId;
  final bool nominaCerrada;

  @override
  ConsumerState<RenglonNominaDetalleDialog> createState() => _RenglonNominaDetalleDialogState();
}

class _RenglonNominaDetalleDialogState extends ConsumerState<RenglonNominaDetalleDialog> {
  NominaEmpleadoData? _renglon;
  NominaData? _nomina;
  List<NominaEmpleadoTramoData> _tramos = const [];
  List<AplicacionPagoNominaData> _aplicacionesPago = const [];
  List<({DescuentoInventarioData descuento, String articuloNombre})> _descuentosInventario = const [];
  List<NominaEmpleadoAusenciaData> _ausencias = const [];
  List<({DescuentoProgramadoCuotaData cuota, DescuentoProgramadoEmpleadoData descuento, int totalCuotas})>
      _descuentosProgramadosRenglon = const [];
  bool _cargando = true;
  bool _guardando = false;
  bool _huboCambios = false;

  _ModoAsistencia _modoAsistencia = _ModoAsistencia.faltas;
  bool _distribucionTocada = false;

  late final TextEditingController _diasLaboradosCtrl;
  late final TextEditingController _prestamoCtrl;
  late final TextEditingController _tiempoExtraCtrl;
  late final TextEditingController _bonoCtrl;
  late final TextEditingController _faltasCtrl;
  late final TextEditingController _otrosDescuentosCtrl;
  late final TextEditingController _observacionesCtrl;
  late final TextEditingController _montoFiscalCtrl;
  late final TextEditingController _montoNoFiscalCtrl;
  late final TextEditingController _motivoCorreccionCtrl;

  @override
  void initState() {
    super.initState();
    _diasLaboradosCtrl = TextEditingController();
    _prestamoCtrl = TextEditingController();
    _tiempoExtraCtrl = TextEditingController();
    _bonoCtrl = TextEditingController();
    _faltasCtrl = TextEditingController();
    _otrosDescuentosCtrl = TextEditingController();
    _observacionesCtrl = TextEditingController();
    _montoFiscalCtrl = TextEditingController();
    _montoNoFiscalCtrl = TextEditingController();
    _motivoCorreccionCtrl = TextEditingController();
    _cargar();
  }

  @override
  void dispose() {
    _diasLaboradosCtrl.dispose();
    _prestamoCtrl.dispose();
    _tiempoExtraCtrl.dispose();
    _bonoCtrl.dispose();
    _faltasCtrl.dispose();
    _otrosDescuentosCtrl.dispose();
    _observacionesCtrl.dispose();
    _montoFiscalCtrl.dispose();
    _montoNoFiscalCtrl.dispose();
    _motivoCorreccionCtrl.dispose();
    super.dispose();
  }

  /// Etapa 4 — Nómina ya `cerrada`/`pagada` (nunca `cancelada`,
  /// bloqueado explícitamente) SÍ puede corregirse con `nomina.corregir`
  /// y motivo obligatorio. Solo decide si el formulario se muestra
  /// editable — `NominasController.corregirRenglon` ya vuelve a exigir
  /// el permiso real por su cuenta, esto es puramente de presentación.
  bool get _puedeCorregirNominaCerrada =>
      widget.nominaCerrada &&
      _nomina?.estatus != 'cancelada' &&
      ref.read(permissionServiceProvider).hasCode('nomina.corregir');

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    final notifier = ref.read(nominasControllerProvider.notifier);
    final tramos = await notifier.listarTramos(widget.nominaEmpleadoId);
    final renglon = await ref.read(nominaRepositoryProvider).obtenerEmpleado(widget.nominaEmpleadoId);
    final nomina = renglon == null ? null : await ref.read(nominaRepositoryProvider).obtenerPorId(renglon.nominaId);
    final aplicacionesPago = await notifier.listarAplicacionesPorRenglon(widget.nominaEmpleadoId);

    // Descuentos por daño/pérdida de inventario aplicados a este
    // renglón (Etapa 15) — desglose identificable, resuelto vía la
    // Asignación de origen (nunca por texto).
    final asignacionRepo = ref.read(asignacionRepositoryProvider);
    final articuloRepo = ref.read(articuloRepositoryProvider);
    final descuentosCrudos = await asignacionRepo.listarDescuentosPorNominaEmpleado(widget.nominaEmpleadoId);
    final descuentosInventario = <({DescuentoInventarioData descuento, String articuloNombre})>[];
    for (final descuento in descuentosCrudos) {
      final asignacion = await asignacionRepo.obtenerPorId(descuento.asignacionId);
      final articulo = asignacion == null ? null : await articuloRepo.obtenerPorId(asignacion.articuloId);
      descuentosInventario.add((descuento: descuento, articuloNombre: articulo?.nombre ?? '—'));
    }

    // Cuotas de préstamo/botas ligadas a este renglón (Etapa 15) — TODAS
    // sin importar estatus (`reservada` en Borrador/Cerrada, `aplicada`
    // en Pagada), mismo criterio que el desglose de Inventario arriba.
    final descuentoProgramadoRepo = ref.read(descuentoProgramadoRepositoryProvider);
    final cuotasRenglon = await descuentoProgramadoRepo.listarCuotasPorRenglon(widget.nominaEmpleadoId);
    final descuentosProgramadosRenglon =
        <({DescuentoProgramadoCuotaData cuota, DescuentoProgramadoEmpleadoData descuento, int totalCuotas})>[];
    for (final cuota in cuotasRenglon) {
      final descuentoProgramado = await descuentoProgramadoRepo.obtenerPorId(cuota.descuentoProgramadoId);
      if (descuentoProgramado == null) continue;
      final todasLasCuotas = await descuentoProgramadoRepo.listarCuotas(descuentoProgramado.id);
      final totalCuotas = todasLasCuotas.where((c) => c.estatus != 'cancelada').length;
      descuentosProgramadosRenglon.add((cuota: cuota, descuento: descuentoProgramado, totalCuotas: totalCuotas));
    }

    // Ausencias del periodo (Etapa Tiempos Extra, pedido explícito de
    // Marlon: "para quien hace los cálculos lo tome en cuenta") —
    // puramente informativa, auto-derivada por `guardarRenglon`, nunca
    // editada aquí.
    final ausencias = await ref.read(nominaRepositoryProvider).listarAusencias(widget.nominaEmpleadoId);

    if (!mounted) return;
    setState(() {
      _renglon = renglon;
      _nomina = nomina;
      _tramos = tramos;
      _aplicacionesPago = aplicacionesPago;
      _descuentosInventario = descuentosInventario;
      _descuentosProgramadosRenglon = descuentosProgramadosRenglon;
      _ausencias = ausencias;
      _cargando = false;
      _modoAsistencia = _ModoAsistencia.faltas;
      _distribucionTocada = false;
      if (renglon != null) {
        _faltasCtrl.text = renglon.faltas.toString();
        _diasLaboradosCtrl.text = (renglon.diasPagables - renglon.faltas).toString();
        _prestamoCtrl.text = _pesos(renglon.prestamo);
        _tiempoExtraCtrl.text = _pesos(renglon.tiempoExtra);
        _bonoCtrl.text = _pesos(renglon.bono);
        _otrosDescuentosCtrl.text = _pesos(renglon.otrosDescuentos);
        _observacionesCtrl.text = renglon.observaciones ?? '';
        _montoFiscalCtrl.text = _pesos(renglon.montoFiscal);
        _montoNoFiscalCtrl.text = _pesos(renglon.montoNoFiscal);
      }
    });
  }

  String _pesos(int centavos) => (centavos / 100).toStringAsFixed(2);

  int? _centavos(String texto) {
    final normalizado = texto.trim().replaceAll(',', '');
    if (normalizado.isEmpty) return 0;
    final pesos = double.tryParse(normalizado);
    if (pesos == null) return null;
    return (pesos * 100).round();
  }

  int _entero(String texto) => int.tryParse(texto.trim()) ?? 0;

  int get _diasPagables => _renglon?.diasPagables ?? 0;

  /// Faltas EFECTIVAS del formulario en este momento — sin importar el
  /// modo activo, siempre acotadas a `[0, diasPagables]` por
  /// construcción (una siempre se deriva de la otra, nunca se capturan
  /// ambas independientemente).
  int get _faltasEfectivas {
    if (_modoAsistencia == _ModoAsistencia.faltas) {
      return _entero(_faltasCtrl.text).clamp(0, _diasPagables);
    }
    return _diasPagables - _entero(_diasLaboradosCtrl.text).clamp(0, _diasPagables);
  }

  void _onCambiarModoAsistencia(_ModoAsistencia modo) {
    if (modo == _modoAsistencia) return;
    setState(() => _modoAsistencia = modo);
  }

  void _onDiasLaboradosChanged(String texto) {
    final laborados = _entero(texto).clamp(0, _diasPagables);
    setState(() {
      if (laborados.toString() != texto.trim()) _diasLaboradosCtrl.text = laborados.toString();
      _faltasCtrl.text = (_diasPagables - laborados).toString();
    });
  }

  void _onFaltasChanged(String texto) {
    final faltas = _entero(texto).clamp(0, _diasPagables);
    setState(() {
      if (faltas.toString() != texto.trim()) _faltasCtrl.text = faltas.toString();
      _diasLaboradosCtrl.text = (_diasPagables - faltas).toString();
    });
  }

  /// Espejo LOCAL de solo lectura — misma función pura que usa el
  /// repositorio (`calcularTotalesRenglonNomina`), nunca una fórmula
  /// paralela. Se recalcula en cada `setState`, pero no persiste nada.
  TotalesRenglonNomina _previsualizar() {
    final r = _renglon!;
    return calcularTotalesRenglonNomina(
      importeBase: r.importeBase,
      pagoPorDia: r.pagoPorDia,
      bono: _centavos(_bonoCtrl.text) ?? 0,
      tiempoExtra: _centavos(_tiempoExtraCtrl.text) ?? 0,
      prestamo: _centavos(_prestamoCtrl.text) ?? 0,
      faltas: _faltasEfectivas,
      otrosDescuentos: _centavos(_otrosDescuentosCtrl.text) ?? 0,
      descuentosInventario: r.descuentosInventario,
      descuentosProgramados: r.descuentosProgramados,
    );
  }

  Future<void> _guardarCambios() async {
    final l10n = AppLocalizations.of(context)!;
    final prestamo = _centavos(_prestamoCtrl.text);
    final tiempoExtra = _centavos(_tiempoExtraCtrl.text);
    final bono = _centavos(_bonoCtrl.text);
    final otrosDescuentos = _centavos(_otrosDescuentosCtrl.text);
    final montoFiscal = _centavos(_montoFiscalCtrl.text);
    final montoNoFiscal = _centavos(_montoNoFiscalCtrl.text);

    if (prestamo == null || tiempoExtra == null || bono == null || otrosDescuentos == null) {
      RisegFeedback.showError(context, l10n.renglonNominaDetalleErrorValorInvalido);
      return;
    }
    if (_distribucionTocada && (montoFiscal == null || montoNoFiscal == null)) {
      RisegFeedback.showError(context, l10n.renglonNominaDetalleErrorValorInvalido);
      return;
    }

    final corrigiendoCerrada = _puedeCorregirNominaCerrada;
    if (corrigiendoCerrada && _motivoCorreccionCtrl.text.trim().isEmpty) {
      RisegFeedback.showError(context, l10n.renglonNominaDetalleErrorMotivoRequerido);
      return;
    }

    setState(() => _guardando = true);

    if (corrigiendoCerrada) {
      final resultado = await ref.read(nominasControllerProvider.notifier).corregirRenglon(
            nominaEmpleadoId: widget.nominaEmpleadoId,
            prestamo: prestamo,
            tiempoExtra: tiempoExtra,
            bono: bono,
            faltas: _faltasEfectivas,
            otrosDescuentos: otrosDescuentos,
            observaciones: _observacionesCtrl.text.trim().isEmpty ? null : _observacionesCtrl.text.trim(),
            limpiarObservaciones: _observacionesCtrl.text.trim().isEmpty,
            distribucionManual: _distribucionTocada ? (montoFiscal: montoFiscal!, montoNoFiscal: montoNoFiscal!) : null,
            motivo: _motivoCorreccionCtrl.text.trim(),
          );
      if (!mounted) return;
      setState(() => _guardando = false);

      switch (resultado) {
        case CorregirRenglonNominaExitoso():
          RisegFeedback.showSuccess(context, l10n.renglonNominaDetalleCambiosExito);
          _huboCambios = true;
          _motivoCorreccionCtrl.clear();
          await _cargar();
        case CorregirRenglonNominaNoBalancea():
          RisegFeedback.showError(context, l10n.renglonNominaDetalleErrorDistribucionNoBalancea);
        case CorregirRenglonNominaTotalNegativo():
          RisegFeedback.showError(context, l10n.renglonNominaDetalleErrorTotalNegativo);
        case CorregirRenglonNominaValorInvalido():
          RisegFeedback.showError(context, l10n.renglonNominaDetalleErrorValorInvalido);
        case CorregirRenglonNominaMotivoRequerido():
          RisegFeedback.showError(context, l10n.renglonNominaDetalleErrorMotivoRequerido);
        case CorregirRenglonNominaExcedeLoPagado(:final totalPagadoHistorico):
          final preview = _previsualizar();
          RisegFeedback.showError(
            context,
            l10n.renglonNominaDetalleErrorExcedeLoPagado(
              formatoCentavosPago(preview.totalAPagar),
              formatoCentavosPago(totalPagadoHistorico),
            ),
          );
        case CorregirRenglonNominaNoExiste():
        case CorregirRenglonNominaNominaBorrador():
        case CorregirRenglonNominaNominaCancelada():
        case CorregirRenglonNominaErrorInesperado():
          RisegFeedback.showError(context, l10n.renglonNominaDetalleNominaCerrada);
      }
      return;
    }

    final resultado = await ref.read(nominasControllerProvider.notifier).actualizarRenglon(
          nominaEmpleadoId: widget.nominaEmpleadoId,
          prestamo: prestamo,
          tiempoExtra: tiempoExtra,
          bono: bono,
          faltas: _faltasEfectivas,
          otrosDescuentos: otrosDescuentos,
          observaciones: _observacionesCtrl.text.trim().isEmpty ? null : _observacionesCtrl.text.trim(),
          limpiarObservaciones: _observacionesCtrl.text.trim().isEmpty,
          distribucionManual: _distribucionTocada ? (montoFiscal: montoFiscal!, montoNoFiscal: montoNoFiscal!) : null,
        );
    if (!mounted) return;
    setState(() => _guardando = false);

    switch (resultado) {
      case ActualizarRenglonNominaExitoso():
        RisegFeedback.showSuccess(context, l10n.renglonNominaDetalleCambiosExito);
        _huboCambios = true;
        await _cargar();
      case ActualizarRenglonNominaNoBalancea():
        RisegFeedback.showError(context, l10n.renglonNominaDetalleErrorDistribucionNoBalancea);
      case ActualizarRenglonNominaTotalNegativo():
        RisegFeedback.showError(context, l10n.renglonNominaDetalleErrorTotalNegativo);
      case ActualizarRenglonNominaValorInvalido():
        RisegFeedback.showError(context, l10n.renglonNominaDetalleErrorValorInvalido);
      case ActualizarRenglonNominaNoExiste():
      case ActualizarRenglonNominaNominaCerrada():
      case ActualizarRenglonNominaErrorInesperado():
        RisegFeedback.showError(context, l10n.renglonNominaDetalleNominaCerrada);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;

    Widget body;
    if (_cargando) {
      body = const SizedBox(height: 240, child: Center(child: CircularProgressIndicator()));
    } else if (_renglon == null) {
      body = Padding(padding: const EdgeInsets.all(AppSpacing.xl), child: Text(l10n.nominaDetalleCargaErrorMensaje));
    } else {
      final r = _renglon!;
      final corrigiendoCerrada = _puedeCorregirNominaCerrada;
      final soloLectura = widget.nominaCerrada && !corrigiendoCerrada;
      final preview = _previsualizar();

      body = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.xl, AppSpacing.xl, AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _seccionEncabezado(l10n, colors, r),
                  if (corrigiendoCerrada) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      l10n.renglonNominaDetalleAvisoCorreccion(nominaEstatusLabel(l10n, _nomina!.estatus)),
                      style: AppTypography.caption.copyWith(color: colors.warning),
                    ),
                  ],
                  if (r.descuentosInventarioPendienteRevision) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      l10n.renglonNominaDetalleDescuentosInventarioPendienteAviso,
                      style: AppTypography.caption.copyWith(color: colors.error),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  _seccionCalculoPeriodo(l10n, colors, r),
                  if (_tramos.length > 1) ...[
                    const SizedBox(height: AppSpacing.sm),
                    _seccionTramos(l10n, colors),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  _seccionAsistencia(l10n, colors, r, soloLectura),
                  if (_ausencias.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.lg),
                    _seccionAusencias(l10n, colors),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  _seccionPercepcionesYDeducciones(l10n, colors, r, preview, soloLectura),
                  const SizedBox(height: AppSpacing.lg),
                  _seccionResumen(l10n, colors, preview),
                  const SizedBox(height: AppSpacing.lg),
                  _seccionDistribucion(l10n, colors, r, preview, soloLectura),
                  const SizedBox(height: AppSpacing.lg),
                  RisegTextField(
                    label: l10n.renglonNominaDetalleCampoObservaciones,
                    controller: _observacionesCtrl,
                    enabled: !soloLectura,
                  ),
                  if (corrigiendoCerrada) ...[
                    const SizedBox(height: AppSpacing.md),
                    RisegTextField(
                      label: l10n.renglonNominaDetalleCampoMotivoCorreccion,
                      controller: _motivoCorreccionCtrl,
                    ),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  _seccionHistorialPagos(l10n, colors),
                ],
              ),
            ),
          ),
          _barraInferior(l10n, colors, preview, soloLectura),
        ],
      );
    }

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {},
      child: Dialog(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: AppBreakpoints.wide, maxHeight: MediaQuery.of(context).size.height * 0.9),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.xl, AppSpacing.xl, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(l10n.renglonNominaDetalleDialogoTitulo, style: AppTypography.heading2.copyWith(color: colors.textPrimary)),
                    ),
                    IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop(_huboCambios)),
                  ],
                ),
              ),
              Flexible(child: body),
            ],
          ),
        ),
      ),
    );
  }

  Widget _seccionEncabezado(AppLocalizations l10n, AppColorScheme colors, NominaEmpleadoData r) {
    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.xxs,
      crossAxisAlignment: WrapCrossAlignment.end,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(r.nombreCompleto, style: AppTypography.heading3.copyWith(color: colors.textPrimary)),
            if (r.servicioNombre != null)
              Text(r.servicioNombre!, style: AppTypography.body.copyWith(color: colors.textMuted)),
            // Navegación cruzada Nómina → Empleado (Etapa 17):
            // `empleadoId` es un FK real, nunca inferido por nombre.
            InkWell(
              key: const Key('renglon_nomina_boton_ver_empleado'),
              onTap: () {
                Navigator.of(context).pop();
                context.push('/personal/empleados/${r.empleadoId}');
              },
              child: Text(
                l10n.renglonNominaDetalleBotonVerEmpleado,
                style: AppTypography.caption.copyWith(color: colors.accentText, decoration: TextDecoration.underline),
              ),
            ),
          ],
        ),
        if (_nomina != null)
          Text(
            '${l10n.renglonNominaDetalleCampoPeriodo(_formatoFecha.format(_nomina!.fechaInicioPeriodo), _formatoFecha.format(_nomina!.fechaFinPeriodo))} · '
            '${l10n.nominaDetalleCampoFechaPago(_formatoFecha.format(_nomina!.fechaPagoOrdinaria))}',
            style: AppTypography.caption.copyWith(color: colors.textMuted),
          ),
        Wrap(
          spacing: AppSpacing.md,
          children: [
            _CampoCorto(label: l10n.renglonNominaDetalleCampoBanco, value: r.bancoNombre),
            _CampoCorto(label: l10n.renglonNominaDetalleCampoCuenta, value: r.numeroCuentaTarjeta),
            _CampoCorto(label: l10n.renglonNominaDetalleCampoClabe, value: r.clabe),
          ],
        ),
      ],
    );
  }

  Widget _seccionCalculoPeriodo(AppLocalizations l10n, AppColorScheme colors, NominaEmpleadoData r) {
    return RisegCard(
      variant: RisegCardVariant.subtle,
      child: Wrap(
        spacing: AppSpacing.xl,
        runSpacing: AppSpacing.md,
        children: [
          _CampoCorto(label: l10n.renglonNominaDetalleCampoSueldoMensual, value: formatoCentavosPago(r.sueldoMensualUtilizado)),
          _CampoCorto(label: l10n.renglonNominaDetalleCampoSalarioDiario, value: formatoCentavosPago(r.pagoPorDia)),
          _CampoCorto(label: l10n.renglonNominaDetalleCampoDias, value: '${r.diasPagables}'),
          _CampoCorto(label: l10n.renglonNominaDetalleCampoFuente, value: _fuenteSueldoLabel(l10n, r.fuenteSueldoUtilizada)),
        ],
      ),
    );
  }

  /// Desglose por tramos — solo cuando hay más de uno (cambio de
  /// Servicio/sueldo o hueco laboral dentro del periodo); con un solo
  /// tramo, la tarjeta "Cálculo del periodo" ya lo representa por
  /// completo, mostrarlo de nuevo aquí sería ruido.
  Widget _seccionTramos(AppLocalizations l10n, AppColorScheme colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.renglonNominaDetalleSeccionTramos, style: AppTypography.caption.copyWith(color: colors.textMuted)),
        const SizedBox(height: AppSpacing.xxs),
        for (final t in _tramos)
          Text(
            '${_formatoFecha.format(t.fechaInicio)} – ${_formatoFecha.format(t.fechaFin)} · '
            '${t.servicioNombre ?? _fuenteSueldoLabel(l10n, t.fuenteSueldo)} · '
            '${t.diasReales}d · ${formatoCentavosPago(t.importeTramo)}',
            style: AppTypography.caption.copyWith(color: colors.textMuted),
          ),
      ],
    );
  }

  /// Ausencias del periodo (Etapa Tiempos Extra) — puramente
  /// informativa, distinta del campo libre `observaciones` (que sigue
  /// siendo texto manual, intacto). Nunca modifica `faltas`/montos de
  /// este renglón.
  Widget _seccionAusencias(AppLocalizations l10n, AppColorScheme colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.renglonNominaDetalleSeccionAusencias, style: AppTypography.label.copyWith(color: colors.textMuted)),
        const SizedBox(height: AppSpacing.xs),
        RisegCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final ausencia in _ausencias)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
                  child: Text(
                    l10n.renglonNominaDetalleAusenciaLinea(
                      motivoAusenciaTiempoExtraLabel(l10n, MotivoAusenciaTiempoExtra.values.byName(ausencia.motivoAusencia)),
                      _formatoFecha.format(ausencia.fecha),
                      ausencia.servicioNombre,
                      ausencia.nombreEmpleadoCubrio,
                    ),
                    style: AppTypography.body,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _seccionAsistencia(AppLocalizations l10n, AppColorScheme colors, NominaEmpleadoData r, bool soloLectura) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.renglonNominaDetalleSeccionAsistencia, style: AppTypography.label.copyWith(color: colors.textMuted)),
        const SizedBox(height: AppSpacing.xs),
        if (soloLectura)
          RisegFieldGrid(
            children: [
              CampoConsulta(label: l10n.renglonNominaDetalleCampoDiasLaborados, value: '${r.diasPagables - r.faltas}'),
              CampoConsulta(label: l10n.renglonNominaDetalleCampoFaltas, value: '${r.faltas}'),
            ],
          )
        else ...[
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(l10n.renglonNominaDetalleAsistenciaCapturarPor, style: AppTypography.body.copyWith(color: colors.textMuted)),
              _SelectorModoAsistencia(
                modo: _modoAsistencia,
                labelDiasLaborados: l10n.renglonNominaDetalleAsistenciaTabDiasLaborados,
                labelFaltas: l10n.renglonNominaDetalleAsistenciaTabFaltas,
                onChanged: _onCambiarModoAsistencia,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          RisegFieldGrid(
            children: [
              RisegTextField(
                label: l10n.renglonNominaDetalleCampoDiasLaborados,
                controller: _diasLaboradosCtrl,
                enabled: _modoAsistencia == _ModoAsistencia.diasLaborados,
                keyboardType: TextInputType.number,
                helperText: l10n.renglonNominaDetalleAsistenciaMaximo(_diasPagables.toString()),
                onChanged: _onDiasLaboradosChanged,
              ),
              RisegTextField(
                label: l10n.renglonNominaDetalleCampoFaltas,
                controller: _faltasCtrl,
                enabled: _modoAsistencia == _ModoAsistencia.faltas,
                keyboardType: TextInputType.number,
                helperText: l10n.renglonNominaDetalleAsistenciaMaximo(_diasPagables.toString()),
                onChanged: _onFaltasChanged,
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _seccionPercepcionesYDeducciones(
    AppLocalizations l10n,
    AppColorScheme colors,
    NominaEmpleadoData r,
    TotalesRenglonNomina preview,
    bool soloLectura,
  ) {
    final percepciones = _panelPercepciones(l10n, colors, r, soloLectura);
    final deducciones = _panelDeducciones(l10n, colors, r, preview, soloLectura);

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= AppBreakpoints.medium) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: percepciones),
              const SizedBox(width: AppSpacing.xl),
              Expanded(child: deducciones),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [percepciones, const SizedBox(height: AppSpacing.lg), deducciones],
        );
      },
    );
  }

  Widget _panelPercepciones(AppLocalizations l10n, AppColorScheme colors, NominaEmpleadoData r, bool soloLectura) {
    final bonoValor = _centavos(_bonoCtrl.text) ?? r.bono;
    final tieneFaltas = _faltasEfectivas > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.renglonNominaDetalleSeccionPercepciones, style: AppTypography.label.copyWith(color: colors.success)),
        const SizedBox(height: AppSpacing.xs),
        _LineaMontoSoloLectura(label: l10n.renglonNominaDetalleCampoSueldoPeriodo, monto: r.importeBase, color: colors.success),
        const SizedBox(height: AppSpacing.sm),
        RisegTextField(
          label: l10n.renglonNominaDetalleCampoBono,
          controller: _bonoCtrl,
          enabled: !soloLectura,
          keyboardType: TextInputType.number,
          onChanged: (_) => setState(() {}),
        ),
        if (tieneFaltas && bonoValor > 0) ...[
          const SizedBox(height: AppSpacing.xxs),
          Text(
            l10n.renglonNominaDetalleAvisoBonoConFaltas,
            style: AppTypography.caption.copyWith(color: colors.warning),
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        RisegTextField(
          label: l10n.renglonNominaDetalleCampoTiempoExtra,
          controller: _tiempoExtraCtrl,
          enabled: !soloLectura,
          keyboardType: TextInputType.number,
          onChanged: (_) => setState(() {}),
        ),
      ],
    );
  }

  Widget _panelDeducciones(
    AppLocalizations l10n,
    AppColorScheme colors,
    NominaEmpleadoData r,
    TotalesRenglonNomina preview,
    bool soloLectura,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.renglonNominaDetalleSeccionDeducciones, style: AppTypography.label.copyWith(color: colors.error)),
        const SizedBox(height: AppSpacing.xs),
        _LineaMontoSoloLectura(label: l10n.renglonNominaDetalleCampoFaltas, monto: preview.descuentoPorFaltas, color: colors.error),
        if (r.descuentosInventario > 0) ...[
          const SizedBox(height: AppSpacing.sm),
          _LineaMontoSoloLectura(label: l10n.renglonNominaDetalleCampoInventario, monto: r.descuentosInventario, color: colors.error),
          if (_descuentosInventario.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xxs),
            for (final item in _descuentosInventario)
              Padding(
                padding: const EdgeInsets.only(left: AppSpacing.sm, top: AppSpacing.xxs),
                child: Text(
                  l10n.renglonNominaDetalleDescuentoInventarioLinea(item.articuloNombre, formatoCentavosPago(item.descuento.importe)),
                  style: AppTypography.caption.copyWith(color: colors.textMuted),
                ),
              ),
          ],
        ],
        if (_descuentosProgramadosRenglon.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          _LineaMontoSoloLectura(
            label: l10n.renglonNominaDetalleCampoDescuentosProgramados,
            monto: r.descuentosProgramados,
            color: colors.error,
          ),
          const SizedBox(height: AppSpacing.xxs),
          for (final item in _descuentosProgramadosRenglon)
            Padding(
              padding: const EdgeInsets.only(left: AppSpacing.sm, top: AppSpacing.xxs),
              child: Text(
                l10n.renglonNominaDetalleDescuentoProgramadoLinea(
                  item.descuento.folio,
                  item.cuota.numeroCuota,
                  item.totalCuotas,
                  formatoCentavosPago(item.cuota.importeProgramado),
                ),
                style: AppTypography.caption.copyWith(color: colors.textMuted),
              ),
            ),
        ],
        // Etapa 15 — el préstamo manual se retira de la captura normal
        // (ahora vive en el módulo Descuentos al Personal); un renglón
        // histórico con `prestamo > 0` se conserva de solo lectura, sin
        // migrar/inventar datos nuevos.
        if (r.prestamo > 0) ...[
          const SizedBox(height: AppSpacing.sm),
          _LineaMontoSoloLectura(
            label: l10n.renglonNominaDetalleCampoPrestamoManualHistorico,
            monto: r.prestamo,
            color: colors.error,
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        RisegTextField(
          label: l10n.renglonNominaDetalleCampoOtrosDescuentos,
          controller: _otrosDescuentosCtrl,
          enabled: !soloLectura,
          keyboardType: TextInputType.number,
          onChanged: (_) => setState(() {}),
        ),
      ],
    );
  }

  Widget _seccionResumen(AppLocalizations l10n, AppColorScheme colors, TotalesRenglonNomina preview) {
    return RisegCard(
      variant: RisegCardVariant.subtle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.renglonNominaDetalleSeccionResumen, style: AppTypography.label.copyWith(color: colors.textMuted)),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            formatoCentavosPago(preview.totalAPagar),
            style: AppTypography.heading1.copyWith(color: colors.accentText, fontSize: 34),
          ),
        ],
      ),
    );
  }

  Widget _seccionDistribucion(
    AppLocalizations l10n,
    AppColorScheme colors,
    NominaEmpleadoData r,
    TotalesRenglonNomina preview,
    bool soloLectura,
  ) {
    final totalDistribuido = (_centavos(_montoFiscalCtrl.text) ?? 0) + (_centavos(_montoNoFiscalCtrl.text) ?? 0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.renglonNominaDetalleSeccionDistribucion, style: AppTypography.label.copyWith(color: colors.textMuted)),
        if (r.distribucionPendienteRevision) ...[
          const SizedBox(height: AppSpacing.xxs),
          Text(l10n.renglonNominaDetalleDistribucionPendienteAviso, style: AppTypography.caption.copyWith(color: colors.error)),
        ],
        const SizedBox(height: AppSpacing.xs),
        RisegFieldGrid(
          children: [
            RisegTextField(
              label: l10n.renglonNominaDetalleCampoMontoFiscal,
              controller: _montoFiscalCtrl,
              enabled: !soloLectura,
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() => _distribucionTocada = true),
            ),
            RisegTextField(
              label: l10n.renglonNominaDetalleCampoMontoNoFiscal,
              controller: _montoNoFiscalCtrl,
              enabled: !soloLectura,
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() => _distribucionTocada = true),
            ),
            CampoConsulta(label: l10n.renglonNominaDetalleCampoTotalDistribuido, value: formatoCentavosPago(totalDistribuido)),
          ],
        ),
      ],
    );
  }

  Widget _seccionHistorialPagos(AppLocalizations l10n, AppColorScheme colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.renglonNominaDetalleSeccionHistorialPagos, style: AppTypography.label.copyWith(color: colors.textMuted)),
        const SizedBox(height: AppSpacing.xs),
        if (_aplicacionesPago.isEmpty)
          Text(l10n.renglonNominaDetalleHistorialPagosVacio, style: AppTypography.body.copyWith(color: colors.textMuted))
        else
          for (final ap in _aplicacionesPago)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
              child: Text(
                '${_formatoFecha.format(ap.createdAt)} · ${formatoCentavosPago(ap.monto)}'
                '${ap.estatus == 'cancelada' ? ' (${l10n.pagoNominaEstatusCancelado})' : ''}',
                style: AppTypography.body.copyWith(color: colors.textPrimary),
              ),
            ),
      ],
    );
  }

  Widget _barraInferior(AppLocalizations l10n, AppColorScheme colors, TotalesRenglonNomina preview, bool soloLectura) {
    // `Wrap` (no `Row`) por el mismo motivo que `RisegSectionHeader`: el
    // grupo de botones nunca debe desbordar — en ancho reducido baja a
    // su propia línea completa, nunca se recorta ni se encima con el
    // neto.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.md),
      decoration: BoxDecoration(color: colors.surface, border: Border(top: BorderSide(color: colors.borderSubtle))),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: AppSpacing.md,
        runSpacing: AppSpacing.sm,
        children: [
          Text.rich(
            TextSpan(
              children: [
                TextSpan(text: '${l10n.renglonNominaDetalleCampoTotal}  ', style: AppTypography.body.copyWith(color: colors.textMuted)),
                TextSpan(
                  text: formatoCentavosPago(preview.totalAPagar),
                  style: AppTypography.heading3.copyWith(color: colors.accentText),
                ),
              ],
            ),
          ),
          Wrap(
            spacing: AppSpacing.sm,
            children: [
              RisegButton(
                label: MaterialLocalizations.of(context).cancelButtonLabel,
                variant: RisegButtonVariant.ghost,
                onPressed: () => Navigator.of(context).pop(_huboCambios),
              ),
              if (!soloLectura)
                RisegButton(
                  label: l10n.renglonNominaDetalleBotonGuardarCambios,
                  loading: _guardando,
                  onPressed: _guardarCambios,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Par etiqueta/valor compacto para el encabezado y la tarjeta "Cálculo
/// del periodo" — como `CampoConsulta`, pero en línea (etiqueta y valor
/// comparten el ancho mínimo necesario), pensado para `Wrap`.
class _CampoCorto extends StatelessWidget {
  const _CampoCorto({required this.label, required this.value});

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: AppTypography.label.copyWith(color: colors.textMuted)),
        const SizedBox(height: AppSpacing.xxs),
        Text(value?.isNotEmpty == true ? value! : '—', style: AppTypography.bodyStrong.copyWith(color: colors.textPrimary)),
      ],
    );
  }
}

/// Línea de solo lectura para un monto ya resuelto (percepción o
/// deducción) — color semántico moderado: solo estos totales derivados
/// y el neto usan color, nunca los campos editables.
class _LineaMontoSoloLectura extends StatelessWidget {
  const _LineaMontoSoloLectura({required this.label, required this.monto, required this.color});

  final String label;
  final int monto;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      children: [
        Expanded(child: Text(label, style: AppTypography.body.copyWith(color: colors.textMuted))),
        const SizedBox(width: AppSpacing.sm),
        Text(formatoCentavosPago(monto), style: AppTypography.bodyStrong.copyWith(color: color)),
      ],
    );
  }
}

/// Selector "Capturar por: Días laborados / Faltas" — dos botones tipo
/// segmento, no una franja de navegación (`RisegTabs` está pensado para
/// cambiar de pantalla, no para elegir un modo de captura dentro de un
/// formulario).
class _SelectorModoAsistencia extends StatelessWidget {
  const _SelectorModoAsistencia({
    required this.modo,
    required this.labelDiasLaborados,
    required this.labelFaltas,
    required this.onChanged,
  });

  final _ModoAsistencia modo;
  final String labelDiasLaborados;
  final String labelFaltas;
  final ValueChanged<_ModoAsistencia> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.xs,
      children: [
        RisegButton(
          label: labelDiasLaborados,
          size: RisegButtonSize.compact,
          variant: modo == _ModoAsistencia.diasLaborados ? RisegButtonVariant.primary : RisegButtonVariant.secondary,
          onPressed: () => onChanged(_ModoAsistencia.diasLaborados),
        ),
        RisegButton(
          label: labelFaltas,
          size: RisegButtonSize.compact,
          variant: modo == _ModoAsistencia.faltas ? RisegButtonVariant.primary : RisegButtonVariant.secondary,
          onPressed: () => onChanged(_ModoAsistencia.faltas),
        ),
      ],
    );
  }
}
