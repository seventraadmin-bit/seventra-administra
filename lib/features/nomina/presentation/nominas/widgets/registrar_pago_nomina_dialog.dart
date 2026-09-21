import 'package:riseg_one/features/finanzas/presentation/mensaje_saldo_insuficiente.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/finanzas/domain/fuente_egreso.dart';
import 'package:riseg_one/features/finanzas/data/tables/pago_table.dart' show FormaPago;
import 'package:riseg_one/features/finanzas/finanzas_providers.dart';
import 'package:riseg_one/features/finanzas/presentation/pagos/pagos_list_screen.dart' show formaPagoLabel, formatoCentavosPago;
import 'package:riseg_one/features/nomina/domain/usecases/nomina_dispersion_pdf_data.dart';
import 'package:riseg_one/features/nomina/domain/usecases/registrar_pago_nomina_usecase.dart';

import '../nomina_detalle_screen.dart' show nominaEstatusPagoLabel;
import '../nominas_controller.dart';

final _formatoFecha = DateFormat('dd/MM/yyyy');

int? _centavosDesdeTexto(String texto) {
  final normalizado = texto.trim().replaceAll(',', '');
  if (normalizado.isEmpty) return null;
  final pesos = double.tryParse(normalizado);
  if (pesos == null) return null;
  return (pesos * 100).round();
}

enum _FiltroDispersion { todos, pendientes, pagados, requiereVerificacion }

/// Una fila de la tabla de dispersión — el renglón snapshot + su saldo
/// pendiente ya resuelto (`PagoNominaRepository.saldoPendientePago`,
/// nunca una columna cacheada) + el estado de captura local del
/// diálogo (seleccionado, modo pago parcial).
class _FilaDispersion {
  _FilaDispersion({required this.renglon, required this.saldoPendiente})
      : montoParcialCtrl = TextEditingController(text: (saldoPendiente / 100).toStringAsFixed(2));

  final NominaEmpleadoData renglon;
  final int saldoPendiente;
  final TextEditingController montoParcialCtrl;
  bool seleccionado = false;
  bool modoParcial = false;

  int get totalAplicadoPrevio => renglon.totalAPagar - saldoPendiente;
  bool get pagado => saldoPendiente <= 0;
  bool get requiereVerificacion => requiereVerificacionBancaria(
        bancoNombre: renglon.bancoNombre,
        numeroCuentaTarjeta: renglon.numeroCuentaTarjeta,
        clabe: renglon.clabe,
      );

  void dispose() => montoParcialCtrl.dispose();
}

/// "Registrar pago de nómina" (Etapa 15, rediseño como tabla
/// interactiva de dispersión) — un lote real de pago, nunca uno por
/// Nómina completa: el Maestro elige qué empleados cubre este lote,
/// trabajador por trabajador, pensado para minimizar errores de
/// cuenta al ir pagando en varias sesiones (Día 1: 8 de 14; Día 2: los
/// 6 restantes). Usa EXCLUSIVAMENTE el snapshot bancario de
/// `NominaEmpleado` (mismo criterio y mismo orden Banco→Nombre que el
/// PDF de dispersión — `ordenarRenglonesDispersion`/
/// `requiereVerificacionBancaria` son las mismas funciones puras que
/// usa `NominaDispersionPdfRenderer`).
///
/// El monto por empleado NUNCA es editable por defecto: se muestra el
/// pendiente real calculado. Solo si el Maestro pulsa explícitamente
/// "Pago parcial" en esa fila se habilita la captura de un monto
/// menor — nunca todos los importes editables a la vez (reduce el
/// riesgo de error humano al dispersar).

class RegistrarPagoNominaDialog extends ConsumerStatefulWidget {
  const RegistrarPagoNominaDialog({required this.nominaId, required this.renglones, super.key});

  final String nominaId;

  /// TODOS los renglones de la Nómina — incluidos los ya `pagado`, para
  /// que se muestren verdes y bloqueados en vez de desaparecer de la
  /// tabla (a diferencia del diseño anterior, que solo recibía
  /// pendientes/parciales).
  final List<NominaEmpleadoData> renglones;

  @override
  ConsumerState<RegistrarPagoNominaDialog> createState() => _RegistrarPagoNominaDialogState();
}

class _RegistrarPagoNominaDialogState extends ConsumerState<RegistrarPagoNominaDialog> {
  List<_FilaDispersion> _filas = const [];
  bool _cargando = true;
  bool _registrando = false;
  _FiltroDispersion _filtro = _FiltroDispersion.todos;
  String? _errorGeneral;

  DateTime? _fecha = DateTime.now();
  FormaPago _forma = FormaPago.transferencia;
  final _referenciaCtrl = TextEditingController();
  final _cuentaOrigenCtrl = TextEditingController();
  final _observacionesCtrl = TextEditingController();
  List<CuentaFinancieraData> _cuentasFinancieras = const [];
  String? _cuentaFinancieraId;

  /// Cuentas ADICIONALES cuando una sola no alcanza. Vacía en el
  /// caso normal: el 95% de los pagos sale de una cuenta y no debe
  /// notar que esto existe. Cada entrada es (cuentaId, importe en
  /// centavos capturado como texto).
  final List<({String? cuentaId, TextEditingController importe})> _fuentesExtra = [];

  Map<String, int> _saldosPorCuenta = const {};

  @override
  void initState() {
    super.initState();
    _cargar();
    Future.microtask(() async {
      final cuentas = await ref.read(cuentaFinancieraRepositoryProvider).listar(soloActivas: true);
      final saldos = cuentas.isEmpty
          ? <String, int>{}
          : await ref.read(cuentaFinancieraRepositoryProvider).calcularSaldos(cuentas.map((c) => c.id));
      if (mounted) {
        setState(() {
          _cuentasFinancieras = cuentas;
          _saldosPorCuenta = saldos;
        });
      }
    });
  }

  @override
  void dispose() {
    _referenciaCtrl.dispose();
    _cuentaOrigenCtrl.dispose();
    _observacionesCtrl.dispose();
    for (final f in _fuentesExtra) {
      f.importe.dispose();
    }
    for (final f in _filas) {
      f.dispose();
    }
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    final notifier = ref.read(nominasControllerProvider.notifier);
    final ordenados = ordenarRenglonesDispersion(widget.renglones);
    final filas = <_FilaDispersion>[];
    for (final r in ordenados) {
      final saldo = await notifier.saldoPendientePago(r.id);
      filas.add(_FilaDispersion(renglon: r, saldoPendiente: saldo));
    }
    if (!mounted) return;
    setState(() {
      _filas = filas;
      _cargando = false;
    });
  }

  List<_FilaDispersion> get _visibles {
    return switch (_filtro) {
      _FiltroDispersion.todos => _filas,
      _FiltroDispersion.pendientes => _filas.where((f) => !f.pagado).toList(),
      _FiltroDispersion.pagados => _filas.where((f) => f.pagado).toList(),
      _FiltroDispersion.requiereVerificacion => _filas.where((f) => f.requiereVerificacion).toList(),
    };
  }

  int get _totalGeneral => _filas.fold(0, (s, f) => s + f.renglon.totalAPagar);
  int get _totalDispersadoPrevio => _filas.fold(0, (s, f) => s + f.totalAplicadoPrevio);
  int get _totalPendienteGeneral => _totalGeneral - _totalDispersadoPrevio;
  int get _empleadosPagados => _filas.where((f) => f.pagado).length;
  double get _porcentajeDispersado => _totalGeneral == 0 ? 0 : (_totalDispersadoPrevio / _totalGeneral) * 100;

  List<_FilaDispersion> get _seleccionadas => _filas.where((f) => f.seleccionado).toList();

  int _montoFila(_FilaDispersion f) => f.modoParcial ? (_centavosDesdeTexto(f.montoParcialCtrl.text) ?? 0) : f.saldoPendiente;

  int get _totalSeleccionado => _seleccionadas.fold(0, (s, f) => s + _montoFila(f));

  void _seleccionarTodosPendientes() => setState(() {
        for (final f in _filas) {
          if (!f.pagado) f.seleccionado = true;
        }
      });

  void _deseleccionarTodos() => setState(() {
        for (final f in _filas) {
          f.seleccionado = false;
        }
      });

  Future<void> _onPressRegistrar() async {
    final l10n = AppLocalizations.of(context)!;

    if (_fecha == null) {
      setState(() => _errorGeneral = l10n.registrarPagoNominaCampoFecha);
      return;
    }
    if (_seleccionadas.isEmpty) {
      setState(() => _errorGeneral = l10n.registrarPagoNominaErrorListaVacia);
      return;
    }

    final aplicaciones = <({String nominaEmpleadoId, int monto})>[];
    for (final f in _seleccionadas) {
      final monto = _montoFila(f);
      if (monto <= 0 || monto > f.saldoPendiente) {
        setState(() => _errorGeneral = l10n.registrarPagoNominaErrorMontoInvalidoEmpleado(f.renglon.nombreCompleto));
        return;
      }
      aplicaciones.add((nominaEmpleadoId: f.renglon.id, monto: monto));
    }
    setState(() => _errorGeneral = null);

    final totalConfirmar = _totalSeleccionado;
    final confirmado = await RisegDialog.showConfirmation(
      context: context,
      title: l10n.registrarPagoNominaConfirmacionTitulo,
      message: l10n.registrarPagoNominaConfirmacionMensaje(
        _seleccionadas.length,
        formatoCentavosPago(totalConfirmar),
        _formatoFecha.format(_fecha!),
        formaPagoLabel(l10n, _forma.name),
      ),
      confirmLabel: l10n.registrarPagoNominaConfirmacionBotonConfirmar,
      cancelLabel: l10n.registrarPagoNominaBotonCancelar,
    );
    if (confirmado != true || !mounted) return;

    setState(() => _registrando = true);
    final resultado = await ref.read(nominasControllerProvider.notifier).registrarPago(
          nominaId: widget.nominaId,
          fechaPago: _fecha!,
          formaPago: _forma.name,
          referencia: _referenciaCtrl.text.trim().isEmpty ? null : _referenciaCtrl.text.trim(),
          cuentaBancariaOrigen: _cuentaOrigenCtrl.text.trim().isEmpty ? null : _cuentaOrigenCtrl.text.trim(),
          cuentaFinancieraId: _cuentaFinancieraId,
          fuentes: _fuentes(),
          observaciones: _observacionesCtrl.text.trim().isEmpty ? null : _observacionesCtrl.text.trim(),
          aplicaciones: aplicaciones,
        );
    if (!mounted) return;
    setState(() => _registrando = false);

    switch (resultado) {
      case RegistrarPagoNominaCuentaFinancieraRequerida():
        setState(() => _errorGeneral = l10n.registrarPagoNominaErrorCuentaRequerida);
      case RegistrarPagoNominaCuentaFinancieraInvalida():
        setState(() => _errorGeneral = l10n.registrarPagoNominaErrorCuentaInvalida);
      case RegistrarPagoNominaExitoso():
        RisegFeedback.showSuccess(context, l10n.registrarPagoNominaExito);
        Navigator.of(context).pop(true);
      case RegistrarPagoNominaListaVacia():
        setState(() => _errorGeneral = l10n.registrarPagoNominaErrorListaVacia);
      case RegistrarPagoNominaNominaNoCerrada():
      case RegistrarPagoNominaNominaNoExiste():
        setState(() => _errorGeneral = l10n.registrarPagoNominaErrorNominaNoCerrada);
      case RegistrarPagoNominaMontoInvalido():
        setState(() => _errorGeneral = l10n.registrarPagoNominaErrorMontoInvalido);
      case RegistrarPagoNominaSobrepago():
      case RegistrarPagoNominaRenglonNoPerteneceANomina():
        setState(() => _errorGeneral = l10n.registrarPagoNominaErrorSobrepago);
      // Los tres números que el usuario necesita para decidir:
      // cuánto hay, cuánto falta pagar y cuánto falta conseguir.
      // Mismo texto central que el resto de los orígenes. Nómina es
      // el único con multicuenta, así que es el único que sugiere
      // repartir el pago.
      case RegistrarPagoNominaSaldoInsuficiente(:final detalle):
        setState(
          () => _errorGeneral = mensajeDeVeredictoSaldo(l10n, detalle, soportaMulticuenta: true),
        );
      case RegistrarPagoNominaFechaAnteriorAlSaldoInicial(:final detalle):
        setState(() => _errorGeneral = mensajeDeVeredictoSaldo(l10n, detalle));
      case RegistrarPagoNominaDistribucionInvalida():
        setState(() => _errorGeneral = l10n.registrarPagoNominaErrorDistribucion);
      case RegistrarPagoNominaErrorInesperado():
        RisegFeedback.showError(context, l10n.registrarPagoNominaErrorInesperado);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;

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
                      child: Text(l10n.registrarPagoNominaDialogoTitulo, style: AppTypography.heading2.copyWith(color: colors.textPrimary)),
                    ),
                    IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop(false)),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.xl, AppSpacing.xl, AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _seccionDatosMovimiento(l10n),
                      const SizedBox(height: AppSpacing.lg),
                      _seccionProgreso(l10n, colors),
                      const SizedBox(height: AppSpacing.md),
                      _seccionFiltrosYAcciones(l10n),
                      const SizedBox(height: AppSpacing.sm),
                      if (_cargando)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else
                        _tablaDispersion(l10n, colors),
                      if (_errorGeneral != null) ...[
                        const SizedBox(height: AppSpacing.sm),
                        Text(_errorGeneral!, style: AppTypography.caption.copyWith(color: colors.error)),
                      ],
                    ],
                  ),
                ),
              ),
              _barraInferior(l10n, colors),
            ],
          ),
        ),
      ),
    );
  }

  Widget _seccionDatosMovimiento(AppLocalizations l10n) {
    return RisegCard(
      variant: RisegCardVariant.subtle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.registrarPagoNominaSeccionDatosMovimiento, style: AppTypography.label.copyWith(color: context.colors.textMuted)),
          const SizedBox(height: AppSpacing.sm),
          RisegFieldGrid(
            children: [
              RisegDateField(
                label: l10n.registrarPagoNominaCampoFecha,
                value: _fecha,
                onChanged: (valor) => setState(() => _fecha = valor),
              ),
              RisegSelect<FormaPago>(
                label: l10n.registrarPagoNominaCampoFormaPago,
                value: _forma,
                items: [for (final f in FormaPago.values) RisegSelectItem(value: f, label: formaPagoLabel(l10n, f.name))],
                onChanged: (valor) => setState(() => _forma = valor ?? _forma),
              ),
              RisegTextField(label: l10n.registrarPagoNominaCampoReferencia, controller: _referenciaCtrl),
              RisegTextField(label: l10n.registrarPagoNominaCampoCuentaOrigen, controller: _cuentaOrigenCtrl),
              RisegSelect<String?>(
                key: const Key('registrar_pago_nomina_campo_cuenta_financiera'),
                label: l10n.registrarPagoNominaCampoCuentaFinancieraObligatoria,
                value: _cuentaFinancieraId,
                items: [
                  // Sin opción "Sin asignar": un pago real siempre
                  // sale de algún lado. El hueco se llenaba con `null`
                  // y el Egreso nacía sin origen, sin descontar de
                  // ninguna cuenta.
                  RisegSelectItem(value: null, label: l10n.registrarPagoNominaPlaceholderCuenta),
                  for (final c in _cuentasFinancieras) RisegSelectItem(value: c.id, label: _etiquetaCuenta(c)),
                ],
                onChanged: (valor) => setState(() => _cuentaFinancieraId = valor),
              ),
              _seccionFuentes(l10n, context.colors),
              RisegTextField(label: l10n.registrarPagoNominaCampoObservaciones, controller: _observacionesCtrl),
            ],
          ),
        ],
      ),
    );
  }

  /// El saldo va en la propia opción: elegir de qué cuenta sale el
  /// pago sin ver cuánto hay es adivinar.
  String _etiquetaCuenta(CuentaFinancieraData c) =>
      '${c.nombre}    ${formatoCentavosPago(_saldosPorCuenta[c.id] ?? 0)}';

  /// Las cuentas ya comprometidas en otras filas del reparto.
  Set<String> _cuentasYaUsadas(int exceptoIndice) => {
        for (var j = 0; j < _fuentesExtra.length; j++)
          if (j != exceptoIndice && _fuentesExtra[j].cuentaId != null) _fuentesExtra[j].cuentaId!,
      };

  /// Qué impide confirmar, o `null` si todo cuadra.
  ///
  /// Es una compuerta de UI para no mandar al usuario a un rechazo
  /// evitable; la autoridad final sigue siendo la validación
  /// transaccional del embudo, que corre con el saldo del momento.
  String? _motivoParaNoConfirmar(AppLocalizations l10n) {
    if (_seleccionadas.isEmpty) return l10n.registrarPagoNominaErrorListaVacia;
    if (_cuentaFinancieraId == null) return l10n.registrarPagoNominaErrorCuentaRequerida;
    if (_fuentesExtra.isEmpty) return null;

    for (final f in _fuentesExtra) {
      if (f.cuentaId == null) return l10n.registrarPagoNominaErrorCuentaRequerida;
      final importe = _centavosDe(f.importe);
      if (importe == null || importe <= 0) return l10n.registrarPagoNominaErrorMontoInvalido;
    }
    if (_asignadoPrincipal <= 0) return l10n.registrarPagoNominaErrorMontoInvalido;
    // "Restante por asignar" tiene que llegar exactamente a cero.
    if (_asignadoPrincipal + _asignadoExtra != _totalSeleccionado) {
      return l10n.registrarPagoNominaErrorDistribucion;
    }
    return null;
  }

  int? _centavosDe(TextEditingController c) {
    final texto = c.text.trim().replaceAll(',', '');
    if (texto.isEmpty) return null;
    final pesos = double.tryParse(texto);
    return pesos == null ? null : (pesos * 100).round();
  }

  /// Lo ya asignado a las cuentas adicionales.
  int get _asignadoExtra =>
      _fuentesExtra.fold(0, (s, f) => s + (f.cuentaId == null ? 0 : (_centavosDe(f.importe) ?? 0)));

  /// Lo que le toca a la cuenta principal: el total menos lo que se
  /// repartió a las demás. Nunca se reparte solo — el usuario decide.
  int get _asignadoPrincipal => _totalSeleccionado - _asignadoExtra;

  /// `null` mientras no haya reparto: el caso normal de una sola
  /// cuenta sigue viajando por `cuentaFinancieraId`, sin fuentes.
  List<FuenteEgreso>? _fuentes() {
    if (_fuentesExtra.isEmpty) return null;
    final cuenta = _cuentaFinancieraId;
    if (cuenta == null) return null;
    return [
      FuenteEgreso(cuentaFinancieraId: cuenta, importe: _asignadoPrincipal),
      for (final f in _fuentesExtra)
        if (f.cuentaId != null)
          FuenteEgreso(cuentaFinancieraId: f.cuentaId!, importe: _centavosDe(f.importe) ?? 0),
    ];
  }

  Widget _seccionFuentes(AppLocalizations l10n, AppColorScheme colors) {
    final saldoPrincipal = _cuentaFinancieraId == null ? null : _saldosPorCuenta[_cuentaFinancieraId];
    final restante = _totalSeleccionado - _asignadoPrincipal - _asignadoExtra;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (saldoPrincipal != null)
          Text(
            l10n.transferirSaldoDisponible(formatoCentavosPago(saldoPrincipal)),
            style: AppTypography.caption.copyWith(color: colors.textMuted),
          ),
        for (var i = 0; i < _fuentesExtra.length; i++) ...[
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: RisegSelect<String?>(
                  label: l10n.registrarPagoNominaCampoCuentaFinancieraObligatoria,
                  value: _fuentesExtra[i].cuentaId,
                  items: [
                    RisegSelectItem(value: null, label: l10n.registrarPagoNominaPlaceholderCuenta),
                    for (final c in _cuentasFinancieras)
                      // Una cuenta ya usada no vuelve a ofrecerse: el
                      // dominio rechaza la repetición, y ofrecerla sería
                      // invitar a un error que después hay que explicar.
                      if (c.id != _cuentaFinancieraId && !_cuentasYaUsadas(i).contains(c.id))
                        RisegSelectItem(value: c.id, label: _etiquetaCuenta(c)),
                  ],
                  onChanged: (valor) => setState(
                    () => _fuentesExtra[i] = (cuentaId: valor, importe: _fuentesExtra[i].importe),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: RisegTextField(
                  label: l10n.transferirCampoImporte,
                  controller: _fuentesExtra[i].importe,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                ),
              ),
              IconButton(
                tooltip: l10n.transferirCancelar,
                icon: const Icon(Icons.close),
                onPressed: () => setState(() {
                  _fuentesExtra[i].importe.dispose();
                  _fuentesExtra.removeAt(i);
                }),
              ),
            ],
          ),
        ],
        const SizedBox(height: AppSpacing.xs),
        Row(
          children: [
            RisegButton(
              key: const Key('registrar_pago_nomina_agregar_cuenta'),
              label: l10n.registrarPagoNominaAgregarCuenta,
              variant: RisegButtonVariant.ghost,
              onPressed: _cuentasFinancieras.length < 2
                  ? null
                  : () => setState(
                        () => _fuentesExtra.add((cuentaId: null, importe: TextEditingController())),
                      ),
            ),
            const Spacer(),
            if (_fuentesExtra.isNotEmpty)
              Text(
                l10n.registrarPagoNominaRestantePorAsignar(formatoCentavosPago(restante)),
                key: const Key('registrar_pago_nomina_restante'),
                style: AppTypography.body.copyWith(
                  color: restante == 0 ? colors.success : colors.textMuted,
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _seccionProgreso(AppLocalizations l10n, AppColorScheme colors) {
    return RisegCard(
      variant: RisegCardVariant.subtle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.registrarPagoNominaSeccionDispersion, style: AppTypography.label.copyWith(color: colors.textMuted)),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.lg,
            runSpacing: AppSpacing.xxs,
            children: [
              Text(
                l10n.registrarPagoNominaProgresoEmpleados(_empleadosPagados, _filas.length),
                style: AppTypography.bodyStrong.copyWith(color: colors.textPrimary),
              ),
              Text(
                l10n.registrarPagoNominaProgresoMonto(formatoCentavosPago(_totalDispersadoPrevio), formatoCentavosPago(_totalGeneral)),
                style: AppTypography.body.copyWith(color: colors.textMuted),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          RisegProgressBar(porcentaje: _porcentajeDispersado, tone: RisegStatusTone.success),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            l10n.registrarPagoNominaProgresoPendiente(formatoCentavosPago(_totalPendienteGeneral)),
            style: AppTypography.caption.copyWith(color: colors.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _seccionFiltrosYAcciones(AppLocalizations l10n) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ChoiceChip(
          label: Text(l10n.registrarPagoNominaFiltroTodos),
          selected: _filtro == _FiltroDispersion.todos,
          onSelected: (_) => setState(() => _filtro = _FiltroDispersion.todos),
        ),
        ChoiceChip(
          label: Text(l10n.registrarPagoNominaFiltroPendientes),
          selected: _filtro == _FiltroDispersion.pendientes,
          onSelected: (_) => setState(() => _filtro = _FiltroDispersion.pendientes),
        ),
        ChoiceChip(
          label: Text(l10n.registrarPagoNominaFiltroPagados),
          selected: _filtro == _FiltroDispersion.pagados,
          onSelected: (_) => setState(() => _filtro = _FiltroDispersion.pagados),
        ),
        ChoiceChip(
          label: Text(l10n.registrarPagoNominaFiltroRequiereVerificacion),
          selected: _filtro == _FiltroDispersion.requiereVerificacion,
          onSelected: (_) => setState(() => _filtro = _FiltroDispersion.requiereVerificacion),
        ),
        const SizedBox(width: AppSpacing.md),
        RisegButton(
          key: const Key('registrar_pago_nomina_boton_seleccionar_pendientes'),
          label: l10n.registrarPagoNominaBotonSeleccionarPendientes,
          variant: RisegButtonVariant.ghost,
          size: RisegButtonSize.compact,
          onPressed: _seleccionarTodosPendientes,
        ),
        RisegButton(
          key: const Key('registrar_pago_nomina_boton_deseleccionar'),
          label: l10n.registrarPagoNominaBotonDeseleccionarTodos,
          variant: RisegButtonVariant.ghost,
          size: RisegButtonSize.compact,
          onPressed: _deseleccionarTodos,
        ),
      ],
    );
  }

  Widget _tablaDispersion(AppLocalizations l10n, AppColorScheme colors) {
    final visibles = _visibles;
    if (visibles.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
        child: Center(child: Text(l10n.registrarPagoNominaTablaVacia, style: AppTypography.body.copyWith(color: colors.textMuted))),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final ancho = constraints.maxWidth;
        if (ancho >= AppBreakpoints.medium) {
          return Column(
            children: [
              _encabezadoTablaAncha(l10n, colors),
              for (final f in visibles) _FilaDispersionAncha(fila: f, l10n: l10n, onChanged: () => setState(() {})),
            ],
          );
        }
        return Column(
          children: [for (final f in visibles) _FilaDispersionTarjeta(fila: f, l10n: l10n, onChanged: () => setState(() {}))],
        );
      },
    );
  }

  Widget _encabezadoTablaAncha(AppLocalizations l10n, AppColorScheme colors) {
    TextStyle style() => AppTypography.label.copyWith(color: colors.textMuted);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs, horizontal: AppSpacing.sm),
      child: Row(
        children: [
          const SizedBox(width: 40),
          SizedBox(width: 40, child: Text(l10n.registrarPagoNominaColumnaNumero, style: style())),
          const SizedBox(width: AppSpacing.sm),
          // Banco/Cuenta/CLABE ya no son columnas propias — se muestran
          // en una segunda línea bajo el nombre (`_datoBancario`), con
          // más espacio para mostrarse completas y copiarse (pedido
          // explícito de Marlon).
          Expanded(child: Text(l10n.registrarPagoNominaColumnaEmpleado, style: style())),
          SizedBox(width: 90, child: Text(l10n.registrarPagoNominaColumnaFiscal, style: style(), textAlign: TextAlign.right)),
          SizedBox(width: 90, child: Text(l10n.registrarPagoNominaColumnaNoFiscal, style: style(), textAlign: TextAlign.right)),
          SizedBox(width: 100, child: Text(l10n.registrarPagoNominaColumnaTotal, style: style(), textAlign: TextAlign.right)),
          SizedBox(width: 100, child: Text(l10n.registrarPagoNominaColumnaPagadoPrevio, style: style(), textAlign: TextAlign.right)),
          SizedBox(width: 100, child: Text(l10n.registrarPagoNominaColumnaPendiente, style: style(), textAlign: TextAlign.right)),
          SizedBox(width: 130, child: Text(l10n.registrarPagoNominaColumnaEstado, style: style())),
        ],
      ),
    );
  }

  Widget _barraInferior(AppLocalizations l10n, AppColorScheme colors) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.md),
      decoration: BoxDecoration(color: colors.surface, border: Border(top: BorderSide(color: colors.borderSubtle))),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: AppSpacing.md,
        runSpacing: AppSpacing.sm,
        children: [
          Text(
            l10n.registrarPagoNominaSeleccionResumen(_seleccionadas.length, formatoCentavosPago(_totalSeleccionado)),
            style: AppTypography.bodyStrong.copyWith(color: colors.textPrimary),
          ),
          Wrap(
            spacing: AppSpacing.sm,
            children: [
              RisegButton(
                label: l10n.registrarPagoNominaBotonCancelar,
                variant: RisegButtonVariant.ghost,
                onPressed: _registrando ? null : () => Navigator.of(context).pop(false),
              ),
              RisegButton(
                key: const Key('registrar_pago_nomina_boton_registrar'),
                label: l10n.registrarPagoNominaBotonConfirmar,
                loading: _registrando,
                onPressed: _motivoParaNoConfirmar(l10n) != null ? null : _onPressRegistrar,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String _estadoLabel(AppLocalizations l10n, _FilaDispersion f) {
  if (f.pagado) return nominaEstatusPagoLabel(l10n, 'pagado');
  if (f.seleccionado) return l10n.registrarPagoNominaEstadoSeleccionado;
  if (f.totalAplicadoPrevio > 0) return nominaEstatusPagoLabel(l10n, 'parcial');
  return nominaEstatusPagoLabel(l10n, 'pendiente');
}

RisegStatusTone _estadoTono(_FilaDispersion f) {
  if (f.pagado) return RisegStatusTone.success;
  if (f.seleccionado) return RisegStatusTone.info;
  if (f.totalAplicadoPrevio > 0) return RisegStatusTone.warning;
  return RisegStatusTone.neutral;
}

Color _fondoFila(AppColorScheme colors, _FilaDispersion f) {
  if (f.pagado) return colors.successBg;
  if (f.seleccionado) return colors.accentSoftBg;
  if (f.totalAplicadoPrevio > 0) return colors.warningBg;
  return Colors.transparent;
}

Future<void> _copiarDato(BuildContext context, AppLocalizations l10n, String valor) async {
  await Clipboard.setData(ClipboardData(text: valor));
  if (context.mounted) RisegFeedback.showSuccess(context, l10n.registrarPagoNominaDatoCopiado);
}

/// "Banco: X" (sin copiar — no es un número que se transcriba en una
/// transferencia) o "Etiqueta: número" CON un ícono de copiar — para
/// Cuenta/Tarjeta y CLABE, los dos datos que el Maestro típicamente
/// pega tal cual en el portal del banco al dispersar (pedido explícito
/// de Marlon, evita transcribir números largos a mano).
Widget _datoBancario(
  BuildContext context,
  AppLocalizations l10n, {
  required String etiqueta,
  required String? valor,
  bool copiable = false,
  Key? key,
}) {
  final colors = context.colors;
  final texto = '$etiqueta: ${valor ?? '—'}';
  final estiloTexto = AppTypography.caption.copyWith(color: colors.textMuted);
  if (!copiable || valor == null || valor.isEmpty) {
    return Text(texto, style: estiloTexto, overflow: TextOverflow.ellipsis);
  }
  return InkWell(
    key: key,
    onTap: () => _copiarDato(context, l10n, valor),
    borderRadius: AppRadius.smRadius,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs, vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(child: Text(texto, style: estiloTexto, overflow: TextOverflow.ellipsis)),
          const SizedBox(width: AppSpacing.xxs),
          Icon(Icons.copy_outlined, size: 14, color: colors.textMuted),
        ],
      ),
    ),
  );
}

/// Fila ancha (tabla real, >= `AppBreakpoints.medium`) — checkbox + No.
/// + Nombre + Fiscal + No fiscal + Total + Pagado previamente +
/// Pendiente + Estado en la línea principal; Banco/Cuenta/CLABE en una
/// segunda línea debajo del nombre (`_datoBancario`, con Cuenta/CLABE
/// copiables) — evita competir por ancho con las columnas monetarias,
/// que es lo que antes forzaba el número de cuenta a partirse en 2-3
/// líneas.
class _FilaDispersionAncha extends StatelessWidget {
  const _FilaDispersionAncha({required this.fila, required this.l10n, required this.onChanged});

  final _FilaDispersion fila;
  final AppLocalizations l10n;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final r = fila.renglon;

    return Container(
      decoration: BoxDecoration(color: _fondoFila(colors, fila), border: Border(bottom: BorderSide(color: colors.borderSubtle))),
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs, horizontal: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 40,
                child: Checkbox(
                  key: ValueKey('dispersion_checkbox_${r.id}'),
                  value: fila.pagado || fila.seleccionado,
                  onChanged: fila.pagado
                      ? null
                      : (v) {
                          fila.seleccionado = v ?? false;
                          onChanged();
                        },
                ),
              ),
              SizedBox(width: 40, child: Text('${r.numeroEmpleado}', style: AppTypography.body.copyWith(color: colors.textPrimary))),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: Text(r.nombreCompleto, style: AppTypography.bodyStrong.copyWith(color: colors.textPrimary))),
              SizedBox(width: 90, child: Text(formatoCentavosPago(r.montoFiscal), textAlign: TextAlign.right)),
              SizedBox(width: 90, child: Text(formatoCentavosPago(r.montoNoFiscal), textAlign: TextAlign.right)),
              SizedBox(width: 100, child: Text(formatoCentavosPago(r.totalAPagar), textAlign: TextAlign.right)),
              SizedBox(width: 100, child: Text(formatoCentavosPago(fila.totalAplicadoPrevio), textAlign: TextAlign.right)),
              SizedBox(
                width: 100,
                child: Text(formatoCentavosPago(fila.saldoPendiente), textAlign: TextAlign.right, style: AppTypography.bodyStrong),
              ),
              SizedBox(
                width: 130,
                child: RisegStatusBadge(label: _estadoLabel(l10n, fila), tone: _estadoTono(fila)),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxs),
          Padding(
            padding: const EdgeInsets.only(left: 80),
            child: Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.xxs,
              children: [
                _datoBancario(context, l10n, etiqueta: l10n.registrarPagoNominaColumnaBanco, valor: r.bancoNombre),
                _datoBancario(
                  context,
                  l10n,
                  key: ValueKey('dispersion_copiar_cuenta_${r.id}'),
                  etiqueta: l10n.registrarPagoNominaColumnaCuenta,
                  valor: r.numeroCuentaTarjeta,
                  copiable: true,
                ),
                _datoBancario(
                  context,
                  l10n,
                  key: ValueKey('dispersion_copiar_clabe_${r.id}'),
                  etiqueta: l10n.registrarPagoNominaColumnaClabe,
                  valor: r.clabe,
                  copiable: true,
                ),
              ],
            ),
          ),
          if (fila.requiereVerificacion) ...[
            const SizedBox(height: AppSpacing.xxs),
            Padding(
              padding: const EdgeInsets.only(left: 80),
              child: Text(
                l10n.registrarPagoNominaRequiereVerificacion,
                style: AppTypography.caption.copyWith(color: colors.warning, fontWeight: FontWeight.bold),
              ),
            ),
          ],
          if (fila.seleccionado && !fila.pagado) ...[
            const SizedBox(height: AppSpacing.xxs),
            Padding(padding: const EdgeInsets.only(left: 80), child: _accionPagoParcial(colors)),
          ],
        ],
      ),
    );
  }

  Widget _accionPagoParcial(AppColorScheme colors) {
    if (!fila.modoParcial) {
      return RisegButton(
        label: l10n.registrarPagoNominaBotonPagoParcial,
        variant: RisegButtonVariant.ghost,
        size: RisegButtonSize.compact,
        onPressed: () {
          fila.modoParcial = true;
          onChanged();
        },
      );
    }
    return SizedBox(
      width: 200,
      child: RisegTextField(
        label: l10n.registrarPagoNominaCampoMontoParcial,
        controller: fila.montoParcialCtrl,
        keyboardType: TextInputType.number,
        autofocus: true,
        onChanged: (_) => onChanged(),
      ),
    );
  }
}

/// Tarjeta compacta (< `AppBreakpoints.medium`) — mismo contenido que
/// la fila ancha, apilado verticalmente.
class _FilaDispersionTarjeta extends StatelessWidget {
  const _FilaDispersionTarjeta({required this.fila, required this.l10n, required this.onChanged});

  final _FilaDispersion fila;
  final AppLocalizations l10n;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final r = fila.renglon;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.xs),
      decoration: BoxDecoration(color: _fondoFila(colors, fila), borderRadius: AppRadius.mdRadius),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(
            key: ValueKey('dispersion_checkbox_${r.id}'),
            value: fila.pagado || fila.seleccionado,
            onChanged: fila.pagado
                ? null
                : (v) {
                    fila.seleccionado = v ?? false;
                    onChanged();
                  },
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${r.numeroEmpleado} · ${r.nombreCompleto}',
                        style: AppTypography.bodyStrong.copyWith(color: colors.textPrimary),
                      ),
                    ),
                    RisegStatusBadge(label: _estadoLabel(l10n, fila), tone: _estadoTono(fila)),
                  ],
                ),
                const SizedBox(height: AppSpacing.xxs),
                Wrap(
                  spacing: AppSpacing.md,
                  runSpacing: AppSpacing.xxs,
                  children: [
                    _datoBancario(context, l10n, etiqueta: l10n.registrarPagoNominaColumnaBanco, valor: r.bancoNombre),
                    _datoBancario(
                      context,
                      l10n,
                      key: ValueKey('dispersion_copiar_cuenta_${r.id}'),
                      etiqueta: l10n.registrarPagoNominaColumnaCuenta,
                      valor: r.numeroCuentaTarjeta,
                      copiable: true,
                    ),
                    _datoBancario(
                      context,
                      l10n,
                      key: ValueKey('dispersion_copiar_clabe_${r.id}'),
                      etiqueta: l10n.registrarPagoNominaColumnaClabe,
                      valor: r.clabe,
                      copiable: true,
                    ),
                  ],
                ),
                if (fila.requiereVerificacion)
                  Text(
                    l10n.registrarPagoNominaRequiereVerificacion,
                    style: AppTypography.caption.copyWith(color: colors.warning, fontWeight: FontWeight.bold),
                  ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  formatoCentavosPago(fila.saldoPendiente),
                  style: AppTypography.bodyStrong.copyWith(color: colors.textPrimary),
                ),
                if (fila.seleccionado && !fila.pagado)
                  fila.modoParcial
                      ? RisegTextField(
                          label: l10n.registrarPagoNominaCampoMontoParcial,
                          controller: fila.montoParcialCtrl,
                          keyboardType: TextInputType.number,
                          autofocus: true,
                          onChanged: (_) => onChanged(),
                        )
                      : RisegButton(
                          label: l10n.registrarPagoNominaBotonPagoParcial,
                          variant: RisegButtonVariant.ghost,
                          size: RisegButtonSize.compact,
                          onPressed: () {
                            fila.modoParcial = true;
                            onChanged();
                          },
                        ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
