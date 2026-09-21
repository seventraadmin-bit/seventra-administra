import 'package:riseg_one/features/finanzas/presentation/mensaje_saldo_insuficiente.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/finanzas/data/tables/pago_table.dart' show FormaPago;
import 'package:riseg_one/features/finanzas/finanzas_providers.dart';
import 'package:riseg_one/features/finanzas/presentation/pagos/pagos_list_screen.dart'
    show formaPagoLabel, formatoCentavosPago;
import 'package:riseg_one/features/organizacion/organizacion_providers.dart';
import 'package:riseg_one/features/personal/data/tables/empleado_table.dart' show EstatusEmpleado;
import 'package:riseg_one/features/personal/personal_providers.dart';
import 'package:riseg_one/features/personal/presentation/empleados/empleados_list_screen.dart'
    show empleadoNombreCompleto;

import 'package:riseg_one/features/organizacion/data/tables/configuracion_cobro_vigencia_table.dart'
    show MetodoPagoCobro;

import '../../data/tables/servicio_eventual_table.dart';
import 'package:riseg_one/features/organizacion/domain/repositories/entidad_fiscal_repository.dart';

import '../../domain/receptor_fiscal_eventual.dart';
import '../../domain/repositories/servicio_eventual_repository.dart';
import '../../domain/totales_venta_eventual.dart';
import '../../domain/usecases/agregar_cobertura_servicio_eventual_usecase.dart';
import '../../domain/usecases/agregar_costo_servicio_eventual_usecase.dart';
import '../../domain/usecases/agregar_participante_servicio_eventual_usecase.dart';
import '../../domain/usecases/corregir_cobertura_servicio_eventual_usecase.dart';
import '../../domain/usecases/corregir_costo_servicio_eventual_usecase.dart';
import '../../domain/usecases/corregir_servicio_eventual_usecase.dart';
import '../../domain/usecases/crear_servicio_eventual_usecase.dart';
import '../../domain/usecases/pagar_cobertura_servicio_eventual_usecase.dart';
import '../../domain/usecases/pagar_costo_servicio_eventual_usecase.dart';
import '../servicios_eventuales_controller.dart';

/// `"1,250.50"` → `125050`. `null` si no es un número — nunca se
/// asume cero: un importe vacío es un error de captura, no un evento
/// gratis.
int? centavosDesdeTexto(String texto) {
  final normalizado = texto.trim().replaceAll(',', '');
  if (normalizado.isEmpty) return null;
  final pesos = double.tryParse(normalizado);
  if (pesos == null) return null;
  return (pesos * 100).round();
}

String _pesosDesdeCentavos(int centavos) => (centavos / 100).toStringAsFixed(2);

// Una GlobalKey por formulario: es como el pie del diálogo alcanza el
// `guardar()` del State sin que el formulario dibuje su propio botón.
// Mismo patrón que `registrar_deuda_dialog.dart`.
final _claveEventual = GlobalKey<_FormularioServicioEventualState>();
final _claveParticipante = GlobalKey<_FormularioParticipanteState>();
final _claveCobertura = GlobalKey<_FormularioCoberturaState>();
final _claveCosto = GlobalKey<_FormularioCostoState>();
final _clavePago = GlobalKey<_FormularioPagoState>();

// ==================================================================
// Alta y corrección del eventual
// ==================================================================

/// Devuelve `true` si se guardó algo. [existente] activa el modo
/// corrección, que pide motivo y ya no deja mover al solicitante.
Future<bool> mostrarDialogoServicioEventual(
  BuildContext context,
  WidgetRef ref, {
  ServicioEventualData? existente,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final clientes = await ref.read(clienteRepositoryProvider).listarActivos();
  if (!context.mounted) return false;
  // Sólo hacen falta para el cobro inmediato, que vive en esta misma
  // alta: pedirlas después obligaría a un segundo diálogo.
  final cuentas = await ref.read(cuentaFinancieraRepositoryProvider).listar(soloActivas: true);
  if (!context.mounted) return false;

  final resultado = await RisegDialog.showForm<bool>(
    context: context,
    title: existente == null
        ? l10n.servicioEventualDialogoCrearTitulo
        : l10n.servicioEventualDialogoCorregirTitulo,
    confirmLabel: existente == null
        ? l10n.servicioEventualBotonRegistrarEventual
        : l10n.servicioEventualBotonGuardarCambios,
    cancelLabel: l10n.compraBotonCancelarFormulario,
    contentBuilder: (_) => _FormularioServicioEventual(
      key: _claveEventual,
      existente: existente,
      clientes: clientes,
      cuentas: cuentas,
    ),
    onConfirm: () async => _claveEventual.currentState?.guardar(),
  );
  return resultado ?? false;
}

class _FormularioServicioEventual extends ConsumerStatefulWidget {
  const _FormularioServicioEventual({
    super.key,
    required this.existente,
    required this.clientes,
    required this.cuentas,
  });

  final ServicioEventualData? existente;
  final List<ClienteData> clientes;
  final List<CuentaFinancieraData> cuentas;

  @override
  ConsumerState<_FormularioServicioEventual> createState() => _FormularioServicioEventualState();
}

class _FormularioServicioEventualState extends ConsumerState<_FormularioServicioEventual> {
  // Los controladores viven aquí y mueren en `dispose()`. Crearlos en
  // la función que abre el diálogo y destruirlos tras el `await` es un
  // bug real y ya documentado de este proyecto: la transición de
  // salida mantiene los campos montados un frame más.
  late final TextEditingController _nombreCtrl;
  late final TextEditingController _ubicacionCtrl;
  late final TextEditingController _notasCtrl;
  late final TextEditingController _importeCtrl;
  late final TextEditingController _solicitanteCtrl;
  late final TextEditingController _contactoCtrl;
  late final TextEditingController _telefonoCtrl;
  late final TextEditingController _correoCtrl;
  late final TextEditingController _motivoCtrl;

  late TipoSolicitanteServicioEventual _tipoSolicitante;
  String? _clienteId;
  late DateTime _inicio;
  late DateTime _fin;
  late bool _requiereFactura;

  /// Receptor fiscal. Quién pide el servicio y a nombre de quién se
  /// factura son dos datos distintos: el primero puede ser "Juan del
  /// comité" y el segundo "Administradora Bosques S.A. de C.V.".
  String? _entidadFiscalId;
  late final TextEditingController _razonSocialCtrl;
  late final TextEditingController _rfcCtrl;
  late final TextEditingController _cpFiscalCtrl;

  /// Entidades fiscales del Cliente elegido. Se cargan sólo cuando
  /// hacen falta —Cliente + factura—, nunca al abrir el formulario.
  var _entidades = const <EntidadFiscalConDomicilio>[];
  var _cargandoEntidades = false;

  /// Cómo se acordó el precio — decide qué significa el importe
  /// capturado y, por tanto, cuánto se le cobrará al cliente.
  late TratamientoIva _tratamientoIva;

  /// Se acuerda al VENDER, no al facturar: es lo que decide si la
  /// cobranza del evento exigirá Complemento de pago.
  var _metodoCobro = MetodoPagoCobro.pue;
  DateTime? _fechaVencimiento;

  var _cobrarAhora = false;

  /// El usuario cambió el monto a mano (cobro parcial real). Desde ese
  /// momento el campo deja de seguir al total: nunca se le pisa una
  /// cifra que escribió él.
  var _montoCobroEditado = false;
  late final TextEditingController _montoCobroCtrl;
  late final TextEditingController _referenciaCtrl;
  String? _cuentaCobroId;
  var _formaPagoCobro = FormaPago.transferencia.name;

  String? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.existente;
    _nombreCtrl = TextEditingController(text: e?.nombre ?? '');
    _ubicacionCtrl = TextEditingController(text: e?.ubicacion ?? '');
    _notasCtrl = TextEditingController(text: e?.notas ?? '');
    _importeCtrl = TextEditingController(text: e == null ? '' : _pesosDesdeCentavos(e.importeAcordado));
    _solicitanteCtrl = TextEditingController(text: e?.solicitanteNombre ?? '');
    _contactoCtrl = TextEditingController(text: e?.solicitanteContacto ?? '');
    _telefonoCtrl = TextEditingController(text: e?.solicitanteTelefono ?? '');
    _correoCtrl = TextEditingController(text: e?.solicitanteCorreo ?? '');
    _motivoCtrl = TextEditingController();
    _montoCobroCtrl = TextEditingController();
    _referenciaCtrl = TextEditingController();
    _razonSocialCtrl = TextEditingController(text: e?.solicitanteRazonSocial ?? '');
    _rfcCtrl = TextEditingController(text: e?.solicitanteRfc ?? '');
    _cpFiscalCtrl = TextEditingController(text: e?.solicitanteCodigoPostalFiscal ?? '');
    _entidadFiscalId = e?.entidadFiscalId;
    _tipoSolicitante = e == null
        ? TipoSolicitanteServicioEventual.cliente
        : TipoSolicitanteServicioEventual.values.firstWhere((t) => t.name == e.tipoSolicitante);
    _clienteId = e?.clienteId;
    final ahora = DateTime.now();
    _inicio = e?.fechaHoraInicio ?? DateTime(ahora.year, ahora.month, ahora.day, 8);
    _fin = e?.fechaHoraFin ?? DateTime(ahora.year, ahora.month, ahora.day, 20);
    _requiereFactura = e?.requiereFactura ?? false;
    _tratamientoIva =
        e == null ? TratamientoIva.noAplica : TratamientoIva.values.byName(e.tratamientoIva);
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _ubicacionCtrl.dispose();
    _notasCtrl.dispose();
    _importeCtrl.dispose();
    _solicitanteCtrl.dispose();
    _contactoCtrl.dispose();
    _telefonoCtrl.dispose();
    _correoCtrl.dispose();
    _motivoCtrl.dispose();
    _montoCobroCtrl.dispose();
    _referenciaCtrl.dispose();
    _razonSocialCtrl.dispose();
    _rfcCtrl.dispose();
    _cpFiscalCtrl.dispose();
    super.dispose();
  }

  /// Trae las entidades fiscales del Cliente elegido. Se llama al
  /// elegir Cliente y al marcar "requiere factura": antes no hacen
  /// falta, y pedirlas siempre sería una consulta por diálogo abierto.
  Future<void> _cargarEntidadesFiscales() async {
    final id = _clienteId;
    if (id == null || !_requiereFactura) {
      setState(() => _entidades = const []);
      return;
    }
    setState(() => _cargandoEntidades = true);
    final entidades = await ref.read(entidadFiscalRepositoryProvider).listarPorCliente(id);
    if (!mounted) return;
    setState(() {
      _entidades = entidades;
      _cargandoEntidades = false;
      // Si la que estaba elegida ya no pertenece a este Cliente, se
      // suelta: nunca se factura a nombre de un tercero por inercia.
      if (!entidades.any((e) => e.entidadFiscal.id == _entidadFiscalId)) _entidadFiscalId = null;
    });
  }

  /// Lo que se le va a cobrar al cliente — **nunca** el importe
  /// capturado. Con "Más IVA" son números distintos, y precargar el
  /// capturado es justo lo que inducía a registrar sólo el subtotal.
  int? get _totalVenta {
    final importe = centavosDesdeTexto(_importeCtrl.text);
    if (importe == null || importe <= 0) return null;
    return totalVentaEventual(importeAcordado: importe, tratamientoIva: _tratamientoIva);
  }

  /// Mantiene el monto del cobro pegado al total mientras el usuario no
  /// lo haya tocado: si cambia el importe o el tratamiento de IVA, el
  /// cobro inmediato tiene que seguirlos.
  void _sincronizarMontoCobro() {
    if (!_cobrarAhora || _montoCobroEditado) return;
    final total = _totalVenta;
    _montoCobroCtrl.text = total == null ? '' : _pesosDesdeCentavos(total);
  }

  /// `true` si guardó (el marco cierra), `null` si hay que
  /// corregir algo (el marco se queda abierto con el error a la vista).
  Future<bool?> guardar() async {
    final l10n = AppLocalizations.of(context)!;
    final notifier = ref.read(serviciosEventualesControllerProvider.notifier);
    final importe = centavosDesdeTexto(_importeCtrl.text);
    setState(() => _error = null);

    final Object resultado;
    if (widget.existente == null) {
      resultado = await notifier.crear(
        nombre: _nombreCtrl.text,
        fechaHoraInicio: _inicio,
        fechaHoraFin: _fin,
        ubicacion: _ubicacionCtrl.text,
        notas: _notasCtrl.text,
        importeAcordado: importe ?? 0,
        tipoSolicitante: _tipoSolicitante,
        clienteId: _clienteId,
        solicitanteNombre: _solicitanteCtrl.text,
        solicitanteContacto: _contactoCtrl.text,
        solicitanteTelefono: _telefonoCtrl.text,
        solicitanteCorreo: _correoCtrl.text,
        requiereFactura: _requiereFactura,
        // Exactamente un lado, igual que el solicitante.
        entidadFiscalId: _tipoSolicitante == TipoSolicitanteServicioEventual.cliente
            ? _entidadFiscalId
            : null,
        solicitanteRazonSocial: _tipoSolicitante == TipoSolicitanteServicioEventual.cliente
            ? null
            : _razonSocialCtrl.text,
        solicitanteRfc:
            _tipoSolicitante == TipoSolicitanteServicioEventual.cliente ? null : _rfcCtrl.text,
        solicitanteCodigoPostalFiscal:
            _tipoSolicitante == TipoSolicitanteServicioEventual.cliente ? null : _cpFiscalCtrl.text,
        tratamientoIva: _tratamientoIva,
        // Sin factura no hay método fiscal que valga: el dominio
        // rechaza cualquier otra combinación.
        metodoCobro: _requiereFactura ? _metodoCobro : MetodoPagoCobro.noAplica,
        fechaVencimiento: _fechaVencimiento,
        cobroInmediato: !_cobrarAhora
            ? null
            : CobroInmediatoServicioEventual(
                monto: centavosDesdeTexto(_montoCobroCtrl.text) ?? _totalVenta ?? 0,
                fechaPago: DateTime.now(),
                formaPago: _formaPagoCobro,
                cuentaFinancieraId: _cuentaCobroId,
                referencia: _referenciaCtrl.text.trim().isEmpty ? null : _referenciaCtrl.text.trim(),
              ),
      );
    } else {
      resultado = await notifier.corregir(
        servicioEventualId: widget.existente!.id,
        nombre: _nombreCtrl.text,
        fechaHoraInicio: _inicio,
        fechaHoraFin: _fin,
        ubicacion: _ubicacionCtrl.text,
        notas: _notasCtrl.text,
        importeAcordado: importe ?? 0,
        tratamientoIva: _tratamientoIva,
        requiereFactura: _requiereFactura,
        motivo: _motivoCtrl.text,
      );
    }

    if (!mounted) return null;
    final mensaje = _mensajeDeResultado(l10n, resultado);
    if (mensaje == null) return true;
    setState(() => _error = mensaje);
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final esCliente = _tipoSolicitante == TipoSolicitanteServicioEventual.cliente;

    return SizedBox(
      width: 560,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RisegTextField(
              key: const Key('servicio_eventual_campo_nombre'),
              label: l10n.servicioEventualCampoNombre,
              controller: _nombreCtrl,
            ),
            const SizedBox(height: AppSpacing.md),
            if (widget.existente == null) ...[
              RisegSelect<TipoSolicitanteServicioEventual>(
                key: const Key('servicio_eventual_campo_tipo_solicitante'),
                label: l10n.servicioEventualCampoTipoSolicitante,
                value: _tipoSolicitante,
                items: [
                  RisegSelectItem(
                    value: TipoSolicitanteServicioEventual.cliente,
                    label: l10n.servicioEventualTipoSolicitanteCliente,
                  ),
                  RisegSelectItem(
                    value: TipoSolicitanteServicioEventual.eventual,
                    label: l10n.servicioEventualTipoSolicitanteExterno,
                  ),
                ],
                onChanged: (valor) => setState(() {
                  _tipoSolicitante = valor ?? TipoSolicitanteServicioEventual.cliente;
                  // Cambiar de lado limpia el otro: el esquema exige
                  // exactamente uno, no los dos a medias.
                  _clienteId = null;
                  _solicitanteCtrl.clear();
                }),
              ),
              const SizedBox(height: AppSpacing.md),
              if (esCliente)
                RisegSelect<String?>(
                  key: const Key('servicio_eventual_campo_cliente'),
                  label: l10n.servicioEventualCampoCliente,
                  value: _clienteId,
                  items: [
                    for (final c in widget.clientes) RisegSelectItem(value: c.id, label: c.nombreComercial),
                  ],
                  onChanged: (valor) {
                    setState(() => _clienteId = valor);
                    _cargarEntidadesFiscales();
                  },
                )
              else ...[
                RisegTextField(
                  key: const Key('servicio_eventual_campo_solicitante'),
                  label: l10n.servicioEventualCampoSolicitanteNombre,
                  controller: _solicitanteCtrl,
                ),
                const SizedBox(height: AppSpacing.md),
                RisegTextField(label: l10n.servicioEventualCampoContacto, controller: _contactoCtrl),
                const SizedBox(height: AppSpacing.md),
                RisegTextField(label: l10n.servicioEventualCampoTelefono, controller: _telefonoCtrl),
                const SizedBox(height: AppSpacing.md),
                RisegTextField(label: l10n.servicioEventualCampoCorreo, controller: _correoCtrl),
              ],
              const SizedBox(height: AppSpacing.md),
            ],
            RisegDateField(
              label: l10n.servicioEventualCampoInicio,
              value: _inicio,
              onChanged: (valor) => setState(() => _inicio = _conHoraDe(valor, _inicio)),
            ),
            const SizedBox(height: AppSpacing.md),
            RisegDateField(
              label: l10n.servicioEventualCampoFin,
              value: _fin,
              onChanged: (valor) => setState(() => _fin = _conHoraDe(valor, _fin)),
            ),
            const SizedBox(height: AppSpacing.md),
            RisegTextField(
              key: const Key('servicio_eventual_campo_importe'),
              label: l10n.servicioEventualCampoImporte,
              controller: _importeCtrl,
              keyboardType: TextInputType.number,
              // El desglose de abajo y el cobro inmediato dependen de
              // este número.
              onChanged: (_) => setState(_sincronizarMontoCobro),
            ),
            const SizedBox(height: AppSpacing.md),
            RisegSelect<TratamientoIva>(
              key: const Key('servicio_eventual_campo_tratamiento_iva'),
              label: l10n.servicioEventualCampoTratamientoIva,
              value: _tratamientoIva,
              items: [
                RisegSelectItem(
                  value: TratamientoIva.noAplica,
                  label: l10n.servicioComercialTratamientoIvaNoAplica,
                ),
                RisegSelectItem(
                  value: TratamientoIva.masIva,
                  label: l10n.servicioComercialTratamientoIvaMasIva,
                ),
                RisegSelectItem(
                  value: TratamientoIva.ivaIncluido,
                  label: l10n.servicioComercialTratamientoIvaIvaIncluido,
                ),
              ],
              onChanged: (valor) => setState(() {
                _tratamientoIva = valor ?? TratamientoIva.noAplica;
                _sincronizarMontoCobro();
              }),
            ),
            const SizedBox(height: AppSpacing.sm),
            // Una línea, no una tarjeta: el usuario tiene que ver
            // cuánto se le va a cobrar al cliente ANTES de guardar.
            _DesgloseVenta(importeTexto: _importeCtrl.text, tratamientoIva: _tratamientoIva),
            const SizedBox(height: AppSpacing.md),
            RisegTextField(label: l10n.servicioEventualCampoUbicacion, controller: _ubicacionCtrl),
            const SizedBox(height: AppSpacing.md),
            RisegTextField(label: l10n.servicioEventualCampoNotas, controller: _notasCtrl),
            const SizedBox(height: AppSpacing.sm),
            RisegCheckbox(
              key: const Key('servicio_eventual_campo_requiere_factura'),
              label: l10n.servicioEventualCampoRequiereFactura,
              value: _requiereFactura,
              onChanged: (valor) {
                setState(() => _requiereFactura = valor);
                _cargarEntidadesFiscales();
              },
            ),
            // §1 — a nombre de quién se emite. Sólo con factura: pedir
            // RFC para un evento que se cobra con recibo sería un
            // trámite inventado.
            //
            // Sólo en el ALTA: corregir el receptor fiscal de una venta
            // ya hecha es otra operación (y el CFDI ya emitido no
            // cambiaría de todas formas). Mostrarlo aquí al corregir
            // daría la impresión de que se puede, y `corregir` lo
            // ignoraría en silencio.
            if (_requiereFactura && widget.existente == null) ...[
              const SizedBox(height: AppSpacing.md),
              RisegSectionHeader(title: l10n.servicioEventualSeccionReceptorFiscal),
              const SizedBox(height: AppSpacing.xs),
              Text(
                l10n.servicioEventualAyudaReceptorFiscal,
                style: AppTypography.caption.copyWith(color: context.colors.textMuted),
              ),
              const SizedBox(height: AppSpacing.sm),
              if (esCliente)
                // Camino de Cliente: se apunta a su Entidad fiscal, no
                // se recaptura nada que él ya tiene registrado.
                RisegSelect<String?>(
                  key: const Key('servicio_eventual_campo_entidad_fiscal'),
                  label: l10n.servicioEventualCampoEntidadFiscal,
                  value: _entidadFiscalId,
                  enabled: !_cargandoEntidades,
                  items: [
                    for (final e in _entidades)
                      RisegSelectItem(
                        value: e.entidadFiscal.id,
                        label: e.entidadFiscal.razonSocial + ' - ' + e.entidadFiscal.rfc,
                      ),
                  ],
                  onChanged: (valor) => setState(() => _entidadFiscalId = valor),
                )
              else ...[
                RisegTextField(
                  key: const Key('servicio_eventual_campo_razon_social'),
                  label: l10n.servicioEventualCampoRazonSocial,
                  controller: _razonSocialCtrl,
                ),
                const SizedBox(height: AppSpacing.md),
                RisegTextField(
                  key: const Key('servicio_eventual_campo_rfc'),
                  label: l10n.servicioEventualCampoRfc,
                  controller: _rfcCtrl,
                ),
                const SizedBox(height: AppSpacing.md),
                RisegTextField(
                  key: const Key('servicio_eventual_campo_cp_fiscal'),
                  label: l10n.servicioEventualCampoCodigoPostalFiscal,
                  controller: _cpFiscalCtrl,
                  keyboardType: TextInputType.number,
                ),
              ],
            ],
            if (widget.existente == null) ...[
              if (_requiereFactura) ...[
                const SizedBox(height: AppSpacing.md),
                RisegSelect<MetodoPagoCobro>(
                  key: const Key('servicio_eventual_campo_metodo_cobro'),
                  label: l10n.servicioEventualCampoMetodoCobro,
                  value: _metodoCobro,
                  items: [
                    RisegSelectItem(value: MetodoPagoCobro.pue, label: l10n.servicioEventualMetodoPue),
                    RisegSelectItem(value: MetodoPagoCobro.ppd, label: l10n.servicioEventualMetodoPpd),
                  ],
                  onChanged: (valor) => setState(() => _metodoCobro = valor ?? MetodoPagoCobro.pue),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              RisegDateField(
                label: l10n.servicioEventualCampoFechaVencimiento,
                value: _fechaVencimiento,
                onChanged: (valor) => setState(() => _fechaVencimiento = valor),
              ),
              const SizedBox(height: AppSpacing.sm),
              RisegCheckbox(
                key: const Key('servicio_eventual_campo_cobrar_ahora'),
                label: l10n.servicioEventualCampoCobrarAhora,
                value: _cobrarAhora,
                onChanged: (valor) => setState(() {
                  _cobrarAhora = valor;
                  // Por defecto se cobra TODO lo que el cliente debe —
                  // el total con IVA, no el importe capturado.
                  if (valor) _sincronizarMontoCobro();
                }),
              ),
              if (_cobrarAhora) ...[
                const SizedBox(height: AppSpacing.md),
                RisegTextField(
                  key: const Key('servicio_eventual_campo_monto_cobro'),
                  label: l10n.servicioEventualCampoMontoCobro,
                  controller: _montoCobroCtrl,
                  keyboardType: TextInputType.number,
                  // Se puede bajar a mano: un cobro parcial real es
                  // legítimo. Lo que no puede es venir mal por defecto.
                  onChanged: (_) => setState(() => _montoCobroEditado = true),
                ),
                if (_totalVenta != null) ...[
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    l10n.servicioEventualCobroTotalACobrar(formatoCentavosPago(_totalVenta!)),
                    key: const Key('servicio_eventual_cobro_total'),
                    style: AppTypography.caption.copyWith(color: context.colors.textMuted),
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                RisegSelect<String?>(
                  label: l10n.servicioEventualCampoFormaPago,
                  value: _formaPagoCobro,
                  items: [
                    for (final forma in FormaPago.values)
                      RisegSelectItem(value: forma.name, label: formaPagoLabel(l10n, forma.name)),
                  ],
                  onChanged: (valor) =>
                      setState(() => _formaPagoCobro = valor ?? FormaPago.transferencia.name),
                ),
                const SizedBox(height: AppSpacing.md),
                RisegSelect<String?>(
                  key: const Key('servicio_eventual_campo_cuenta_cobro'),
                  label: l10n.servicioEventualCampoCuentaDestino,
                  value: _cuentaCobroId,
                  items: [for (final c in widget.cuentas) RisegSelectItem(value: c.id, label: c.nombre)],
                  onChanged: (valor) => setState(() => _cuentaCobroId = valor),
                ),
                const SizedBox(height: AppSpacing.md),
                RisegTextField(label: l10n.servicioEventualCampoReferencia, controller: _referenciaCtrl),
              ],
            ],
            if (widget.existente != null) ...[
              const SizedBox(height: AppSpacing.md),
              RisegTextField(
                key: const Key('servicio_eventual_campo_motivo'),
                label: l10n.servicioEventualCampoMotivo,
                controller: _motivoCtrl,
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(_error!, style: AppTypography.caption.copyWith(color: context.colors.error)),
            ],
          ],
        ),
      ),
    );
  }
}

/// El selector de fecha no trae hora; se conserva la que ya tenía el
/// campo para no mover el horario del evento al corregir el día.
DateTime _conHoraDe(DateTime? nueva, DateTime anterior) {
  if (nueva == null) return anterior;
  return DateTime(nueva.year, nueva.month, nueva.day, anterior.hour, anterior.minute);
}

/// `null` = todo bien. Traduce el resultado sellado a algo accionable —
/// un `switch` por tipo, nunca por texto del error.
String? _mensajeDeResultado(AppLocalizations l10n, Object resultado) {
  return switch (resultado) {
    CrearServicioEventualExitoso() ||
    CorregirServicioEventualExitoso() ||
    AgregarParticipanteServicioEventualExitoso() ||
    AgregarCoberturaServicioEventualExitoso() ||
    CorregirCoberturaServicioEventualExitoso() ||
    AgregarCostoServicioEventualExitoso() ||
    CorregirCostoServicioEventualExitoso() ||
    PagarCoberturaServicioEventualExitoso() ||
    PagarCostoServicioEventualExitoso() =>
      null,
    CrearServicioEventualNombreRequerido() ||
    CorregirServicioEventualNombreRequerido() =>
      l10n.servicioEventualErrorNombreRequerido,
    CrearServicioEventualRangoInvalido() ||
    CorregirServicioEventualRangoInvalido() =>
      l10n.servicioEventualErrorRangoInvalido,
    CrearServicioEventualImporteInvalido() ||
    CorregirServicioEventualImporteInvalido() =>
      l10n.servicioEventualErrorImporteInvalido,
    CrearServicioEventualSolicitanteIncompleto() => l10n.servicioEventualErrorSolicitanteIncompleto,
    CrearServicioEventualClienteNoExiste() => l10n.servicioEventualErrorClienteNoExiste,
    CrearServicioEventualMetodoIncoherente() => l10n.servicioEventualErrorMetodoIncoherente,
    CrearServicioEventualCobroInvalido() => l10n.servicioEventualErrorCobroInvalido,
    CrearServicioEventualEntidadFiscalRequerida() => l10n.servicioEventualErrorEntidadFiscalRequerida,
    CrearServicioEventualEntidadFiscalInvalida() => l10n.servicioEventualErrorEntidadFiscalInvalida,
    CrearServicioEventualEntidadFiscalSinDomicilio(razonSocial: final razon) =>
      l10n.servicioEventualErrorEntidadFiscalSinDomicilio(razon),
    CrearServicioEventualReceptorFiscalInvalido(motivo: final motivo) => switch (motivo) {
        ErrorReceptorFiscalEventual.razonSocialRequerida =>
          l10n.servicioEventualErrorRazonSocialRequerida,
        ErrorReceptorFiscalEventual.rfcRequerido => l10n.servicioEventualErrorRfcRequerido,
        ErrorReceptorFiscalEventual.rfcInvalido => l10n.servicioEventualErrorRfcInvalido,
        ErrorReceptorFiscalEventual.codigoPostalRequerido =>
          l10n.servicioEventualErrorCodigoPostalRequerido,
        ErrorReceptorFiscalEventual.codigoPostalInvalido =>
          l10n.servicioEventualErrorCodigoPostalInvalido,
      },
    CorregirServicioEventualImporteBloqueadoPorPago() =>
      l10n.servicioEventualErrorImporteBloqueadoPorPago,
    CorregirServicioEventualMotivoRequerido() ||
    CorregirCoberturaServicioEventualMotivoRequerido() ||
    CorregirCostoServicioEventualMotivoRequerido() =>
      l10n.servicioEventualErrorMotivoRequerido,
    CorregirServicioEventualCancelado() ||
    AgregarParticipanteServicioEventualCancelado() ||
    AgregarCoberturaServicioEventualCancelado() ||
    AgregarCostoServicioEventualCancelado() =>
      l10n.servicioEventualErrorCancelado,
    AgregarParticipanteServicioEventualIdentidadInvalida() =>
      l10n.servicioEventualErrorIdentidadParticipante,
    AgregarParticipanteServicioEventualEmpleadoNoExiste() => l10n.servicioEventualErrorEmpleadoNoExiste,
    AgregarParticipanteServicioEventualDuplicado() => l10n.servicioEventualErrorParticipanteDuplicado,
    AgregarCoberturaServicioEventualParticipanteInvalido() =>
      l10n.servicioEventualErrorIdentidadParticipante,
    AgregarCoberturaServicioEventualHorarioInvalido() ||
    CorregirCoberturaServicioEventualHorarioInvalido() =>
      l10n.servicioEventualErrorHorarioInvalido,
    AgregarCoberturaServicioEventualImporteInvalido() ||
    CorregirCoberturaServicioEventualImporteInvalido() ||
    AgregarCostoServicioEventualMontoInvalido() ||
    CorregirCostoServicioEventualMontoInvalido() =>
      l10n.servicioEventualErrorMontoInvalido,
    AgregarCostoServicioEventualConceptoRequerido() ||
    CorregirCostoServicioEventualConceptoRequerido() =>
      l10n.servicioEventualErrorConceptoRequerido,
    CorregirCoberturaServicioEventualPagada() ||
    CorregirCostoServicioEventualPagado() =>
      l10n.servicioEventualErrorPagadaNoEditable,
    PagarCoberturaServicioEventualYaPagada() || PagarCostoServicioEventualYaPagado() =>
      l10n.servicioEventualErrorYaPagada,
    PagarCoberturaServicioEventualOrigenFinancieroRequerido() ||
    PagarCostoServicioEventualOrigenFinancieroRequerido() =>
      l10n.servicioEventualErrorOrigenRequerido,
    PagarCoberturaServicioEventualOrigenFinancieroAmbiguo() ||
    PagarCostoServicioEventualOrigenFinancieroAmbiguo() =>
      l10n.servicioEventualErrorOrigenAmbiguo,
    PagarCoberturaServicioEventualTarjetaInvalida() || PagarCostoServicioEventualTarjetaInvalida() =>
      l10n.servicioEventualErrorTarjetaInvalida,
    PagarCoberturaServicioEventualTarjetaSinLimiteConfigurado() ||
    PagarCostoServicioEventualTarjetaSinLimiteConfigurado() =>
      l10n.servicioEventualErrorTarjetaSinLimite,
    PagarCoberturaServicioEventualTarjetaExcedeLimite(:final disponible) =>
      l10n.servicioEventualErrorTarjetaExcedeLimite(formatoCentavosPago(disponible)),
    PagarCostoServicioEventualTarjetaExcedeLimite(:final disponible) =>
      l10n.servicioEventualErrorTarjetaExcedeLimite(formatoCentavosPago(disponible)),
    // Un fallo técnico NO es un problema de permisos: mandarlo al
    // mismo mensaje escondía la causa real y mandaba al usuario a
    // revisar su cuenta por algo que no tenía que ver.
    CrearServicioEventualErrorInesperado(:final mensaje) ||
    CorregirServicioEventualErrorInesperado(:final mensaje) =>
      l10n.servicioEventualErrorInesperado(mensaje),
    _ => l10n.servicioEventualErrorPermiso,
  };
}

// ==================================================================
// Participante
// ==================================================================

Future<bool> mostrarDialogoParticipante(
  BuildContext context,
  WidgetRef ref, {
  required String servicioEventualId,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final empleados = await ref.read(empleadoRepositoryProvider).listar(estatus: EstatusEmpleado.activo.name);
  if (!context.mounted) return false;

  final resultado = await RisegDialog.showForm<bool>(
    context: context,
    title: l10n.servicioEventualDialogoParticipanteTitulo,
    confirmLabel: l10n.servicioEventualBotonAgregarParticipanteAccion,
    cancelLabel: l10n.compraBotonCancelarFormulario,
    contentBuilder: (_) => _FormularioParticipante(
      key: _claveParticipante,
      servicioEventualId: servicioEventualId,
      empleados: empleados,
    ),
    onConfirm: () async => _claveParticipante.currentState?.guardar(),
  );
  return resultado ?? false;
}

class _FormularioParticipante extends ConsumerStatefulWidget {
  const _FormularioParticipante({super.key, required this.servicioEventualId, required this.empleados});

  final String servicioEventualId;
  final List<EmpleadoData> empleados;

  @override
  ConsumerState<_FormularioParticipante> createState() => _FormularioParticipanteState();
}

class _FormularioParticipanteState extends ConsumerState<_FormularioParticipante> {
  final _nombreCtrl = TextEditingController();
  final _telefonoCtrl = TextEditingController();
  final _observacionesCtrl = TextEditingController();

  var _esEmpleado = true;
  String? _empleadoId;
  String? _error;

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _telefonoCtrl.dispose();
    _observacionesCtrl.dispose();
    super.dispose();
  }

  /// `true` si guardó (el marco cierra), `null` si hay que
  /// corregir algo (el marco se queda abierto con el error a la vista).
  Future<bool?> guardar() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _error = null);
    final resultado = await ref.read(serviciosEventualesControllerProvider.notifier).agregarParticipante(
          servicioEventualId: widget.servicioEventualId,
          empleadoId: _esEmpleado ? _empleadoId : null,
          nombreExterno: _esEmpleado ? null : _nombreCtrl.text,
          telefonoExterno: _esEmpleado ? null : _telefonoCtrl.text,
          observaciones: _observacionesCtrl.text,
        );
    if (!mounted) return null;
    final mensaje = _mensajeDeResultado(l10n, resultado);
    if (mensaje == null) return true;
    setState(() => _error = mensaje);
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RisegSelect<bool>(
              label: l10n.servicioEventualCampoTipoParticipante,
              value: _esEmpleado,
              items: [
                RisegSelectItem(value: true, label: l10n.servicioEventualTipoParticipanteEmpleado),
                RisegSelectItem(value: false, label: l10n.servicioEventualTipoParticipanteExterno),
              ],
              onChanged: (valor) => setState(() {
                _esEmpleado = valor ?? true;
                _empleadoId = null;
                _nombreCtrl.clear();
              }),
            ),
            const SizedBox(height: AppSpacing.md),
            if (_esEmpleado)
              RisegSearchSelect<String>(
                key: const Key('servicio_eventual_campo_empleado'),
                label: l10n.servicioEventualCampoEmpleado,
                hint: l10n.servicioEventualCampoEmpleado,
                textoSinResultados: l10n.serviciosEventualesVacioTitulo,
                value: _empleadoId,
                opciones: [
                  for (final e in widget.empleados)
                    RisegSearchOption(value: e.id, etiqueta: empleadoNombreCompleto(e)),
                ],
                onChanged: (valor) => setState(() => _empleadoId = valor),
              )
            else ...[
              RisegTextField(
                key: const Key('servicio_eventual_campo_nombre_externo'),
                label: l10n.servicioEventualCampoNombreExterno,
                controller: _nombreCtrl,
              ),
              const SizedBox(height: AppSpacing.md),
              RisegTextField(label: l10n.servicioEventualCampoTelefono, controller: _telefonoCtrl),
            ],
            const SizedBox(height: AppSpacing.md),
            RisegTextField(label: l10n.servicioEventualCampoObservaciones, controller: _observacionesCtrl),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(_error!, style: AppTypography.caption.copyWith(color: context.colors.error)),
            ],
          ],
        ),
      ),
    );
  }
}

// ==================================================================
// Cobertura
// ==================================================================

Future<bool> mostrarDialogoCobertura(
  BuildContext context,
  WidgetRef ref, {
  required String servicioEventualId,
  required List<ServicioEventualParticipanteData> participantes,
  required Map<String, String> nombresParticipante,
  ServicioEventualCoberturaData? existente,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final resultado = await RisegDialog.showForm<bool>(
    context: context,
    title: existente == null
        ? l10n.servicioEventualDialogoCoberturaTitulo
        : l10n.servicioEventualDialogoCoberturaCorregirTitulo,
    confirmLabel: existente == null
        ? l10n.servicioEventualBotonAgregarCoberturaAccion
        : l10n.servicioEventualBotonGuardarCambios,
    cancelLabel: l10n.compraBotonCancelarFormulario,
    contentBuilder: (_) => _FormularioCobertura(
      key: _claveCobertura,
      servicioEventualId: servicioEventualId,
      participantes: participantes,
      nombresParticipante: nombresParticipante,
      existente: existente,
    ),
    onConfirm: () async => _claveCobertura.currentState?.guardar(),
  );
  return resultado ?? false;
}

class _FormularioCobertura extends ConsumerStatefulWidget {
  const _FormularioCobertura({
    super.key,
    required this.servicioEventualId,
    required this.participantes,
    required this.nombresParticipante,
    required this.existente,
  });

  final String servicioEventualId;
  final List<ServicioEventualParticipanteData> participantes;
  final Map<String, String> nombresParticipante;
  final ServicioEventualCoberturaData? existente;

  @override
  ConsumerState<_FormularioCobertura> createState() => _FormularioCoberturaState();
}

class _FormularioCoberturaState extends ConsumerState<_FormularioCobertura> {
  late final TextEditingController _importeCtrl;
  late final TextEditingController _descripcionCtrl;
  final _motivoCtrl = TextEditingController();

  String? _participanteId;
  late DateTime _fecha;
  late TimeOfDay _horaInicio;
  late TimeOfDay _horaFin;
  String? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.existente;
    _importeCtrl = TextEditingController(text: e == null ? '' : _pesosDesdeCentavos(e.importeAcordado));
    _descripcionCtrl = TextEditingController(text: e?.descripcionHorario ?? '');
    _participanteId = e?.participanteId ?? widget.participantes.firstOrNull?.id;
    _fecha = e?.fecha ?? DateTime.now();
    _horaInicio = _desdeMinutos(e?.horaInicioMinutos ?? 8 * 60);
    _horaFin = _desdeMinutos(e?.horaFinMinutos ?? 20 * 60);
  }

  @override
  void dispose() {
    _importeCtrl.dispose();
    _descripcionCtrl.dispose();
    _motivoCtrl.dispose();
    super.dispose();
  }

  /// `true` si guardó (el marco cierra), `null` si hay que
  /// corregir algo (el marco se queda abierto con el error a la vista).
  Future<bool?> guardar() async {
    final l10n = AppLocalizations.of(context)!;
    final notifier = ref.read(serviciosEventualesControllerProvider.notifier);
    setState(() => _error = null);

    final Object resultado;
    if (widget.existente == null) {
      resultado = await notifier.agregarCobertura(
        servicioEventualId: widget.servicioEventualId,
        participanteId: _participanteId ?? '',
        fecha: _fecha,
        horaInicioMinutos: _enMinutos(_horaInicio),
        horaFinMinutos: _enMinutos(_horaFin),
        descripcionHorario: _descripcionCtrl.text,
        importeAcordado: centavosDesdeTexto(_importeCtrl.text) ?? 0,
      );
    } else {
      resultado = await notifier.corregirCobertura(
        coberturaId: widget.existente!.id,
        fecha: _fecha,
        horaInicioMinutos: _enMinutos(_horaInicio),
        horaFinMinutos: _enMinutos(_horaFin),
        descripcionHorario: _descripcionCtrl.text,
        importeAcordado: centavosDesdeTexto(_importeCtrl.text),
        motivo: _motivoCtrl.text,
      );
    }

    if (!mounted) return null;
    final mensaje = _mensajeDeResultado(l10n, resultado);
    if (mensaje == null) return true;
    setState(() => _error = mensaje);
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.existente == null) ...[
              RisegSelect<String?>(
                key: const Key('servicio_eventual_campo_participante'),
                label: l10n.servicioEventualColumnaParticipante,
                value: _participanteId,
                items: [
                  for (final p in widget.participantes)
                    RisegSelectItem(value: p.id, label: widget.nombresParticipante[p.id] ?? p.id),
                ],
                onChanged: (valor) => setState(() => _participanteId = valor),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            RisegDateField(
              label: l10n.servicioEventualColumnaFecha,
              value: _fecha,
              onChanged: (valor) => setState(() => _fecha = valor),
            ),
            const SizedBox(height: AppSpacing.md),
            RisegTimeField(
              label: l10n.servicioEventualCampoHoraInicio,
              value: _horaInicio,
              onChanged: (valor) => setState(() => _horaInicio = valor),
            ),
            const SizedBox(height: AppSpacing.md),
            RisegTimeField(
              label: l10n.servicioEventualCampoHoraFin,
              value: _horaFin,
              // Un turno que termina antes de la hora en que empieza
              // cruza la medianoche: es lo normal en seguridad, no un
              // error.
              helperText: _enMinutos(_horaFin) <= _enMinutos(_horaInicio)
                  ? l10n.servicioEventualHorarioCruzaMedianoche
                  : null,
              onChanged: (valor) => setState(() => _horaFin = valor),
            ),
            const SizedBox(height: AppSpacing.md),
            RisegTextField(
              key: const Key('servicio_eventual_campo_importe_cobertura'),
              label: l10n.servicioEventualColumnaImporte,
              controller: _importeCtrl,
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: AppSpacing.md),
            RisegTextField(
              label: l10n.servicioEventualCampoDescripcionHorario,
              controller: _descripcionCtrl,
            ),
            if (widget.existente != null) ...[
              const SizedBox(height: AppSpacing.md),
              RisegTextField(label: l10n.servicioEventualCampoMotivo, controller: _motivoCtrl),
            ],
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(_error!, style: AppTypography.caption.copyWith(color: context.colors.error)),
            ],
          ],
        ),
      ),
    );
  }
}

TimeOfDay _desdeMinutos(int minutos) => TimeOfDay(hour: minutos ~/ 60, minute: minutos % 60);

int _enMinutos(TimeOfDay hora) => hora.hour * 60 + hora.minute;

// ==================================================================
// Costo adicional
// ==================================================================

Future<bool> mostrarDialogoCosto(
  BuildContext context,
  WidgetRef ref, {
  required String servicioEventualId,
  ServicioEventualCostoData? existente,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final resultado = await RisegDialog.showForm<bool>(
    context: context,
    title: existente == null
        ? l10n.servicioEventualDialogoCostoTitulo
        : l10n.servicioEventualDialogoCostoCorregirTitulo,
    confirmLabel: existente == null
        ? l10n.servicioEventualBotonAgregarCostoAccion
        : l10n.servicioEventualBotonGuardarCambios,
    cancelLabel: l10n.compraBotonCancelarFormulario,
    contentBuilder: (_) => _FormularioCosto(
      key: _claveCosto,
      servicioEventualId: servicioEventualId,
      existente: existente,
    ),
    onConfirm: () async => _claveCosto.currentState?.guardar(),
  );
  return resultado ?? false;
}

class _FormularioCosto extends ConsumerStatefulWidget {
  const _FormularioCosto({super.key, required this.servicioEventualId, required this.existente});

  final String servicioEventualId;
  final ServicioEventualCostoData? existente;

  @override
  ConsumerState<_FormularioCosto> createState() => _FormularioCostoState();
}

class _FormularioCostoState extends ConsumerState<_FormularioCosto> {
  late final TextEditingController _conceptoCtrl;
  late final TextEditingController _montoCtrl;
  late final TextEditingController _observacionesCtrl;
  final _motivoCtrl = TextEditingController();

  late DateTime _fecha;
  String? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.existente;
    _conceptoCtrl = TextEditingController(text: e?.concepto ?? '');
    _montoCtrl = TextEditingController(text: e == null ? '' : _pesosDesdeCentavos(e.monto));
    _observacionesCtrl = TextEditingController(text: e?.observaciones ?? '');
    _fecha = e?.fecha ?? DateTime.now();
  }

  @override
  void dispose() {
    _conceptoCtrl.dispose();
    _montoCtrl.dispose();
    _observacionesCtrl.dispose();
    _motivoCtrl.dispose();
    super.dispose();
  }

  /// `true` si guardó (el marco cierra), `null` si hay que
  /// corregir algo (el marco se queda abierto con el error a la vista).
  Future<bool?> guardar() async {
    final l10n = AppLocalizations.of(context)!;
    final notifier = ref.read(serviciosEventualesControllerProvider.notifier);
    setState(() => _error = null);

    final Object resultado;
    if (widget.existente == null) {
      resultado = await notifier.agregarCosto(
        servicioEventualId: widget.servicioEventualId,
        concepto: _conceptoCtrl.text,
        monto: centavosDesdeTexto(_montoCtrl.text) ?? 0,
        fecha: _fecha,
        observaciones: _observacionesCtrl.text,
      );
    } else {
      resultado = await notifier.corregirCosto(
        costoId: widget.existente!.id,
        concepto: _conceptoCtrl.text,
        monto: centavosDesdeTexto(_montoCtrl.text),
        fecha: _fecha,
        observaciones: _observacionesCtrl.text,
        motivo: _motivoCtrl.text,
      );
    }

    if (!mounted) return null;
    final mensaje = _mensajeDeResultado(l10n, resultado);
    if (mensaje == null) return true;
    setState(() => _error = mensaje);
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RisegTextField(
              key: const Key('servicio_eventual_campo_concepto'),
              label: l10n.servicioEventualCampoConcepto,
              controller: _conceptoCtrl,
            ),
            const SizedBox(height: AppSpacing.md),
            RisegTextField(
              key: const Key('servicio_eventual_campo_monto'),
              label: l10n.servicioEventualCampoMonto,
              controller: _montoCtrl,
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: AppSpacing.md),
            RisegDateField(
              label: l10n.servicioEventualColumnaFecha,
              value: _fecha,
              onChanged: (valor) => setState(() => _fecha = valor),
            ),
            const SizedBox(height: AppSpacing.md),
            RisegTextField(label: l10n.servicioEventualCampoObservaciones, controller: _observacionesCtrl),
            if (widget.existente != null) ...[
              const SizedBox(height: AppSpacing.md),
              RisegTextField(label: l10n.servicioEventualCampoMotivo, controller: _motivoCtrl),
            ],
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(_error!, style: AppTypography.caption.copyWith(color: context.colors.error)),
            ],
          ],
        ),
      ),
    );
  }
}

// ==================================================================
// Pago — el único diálogo de este módulo que mueve dinero
// ==================================================================

/// Un solo formulario para pagar una cobertura o un costo: la decisión
/// financiera es idéntica, así que la pantalla también. Quien llama
/// pasa [onPagar], que ya sabe a cuál de los dos casos de uso ir.
Future<bool> mostrarDialogoPagarGastoEventual(
  BuildContext context,
  WidgetRef ref, {
  required int monto,
  required Future<Object> Function({
    required String formaPago,
    String? cuentaFinancieraId,
    String? deudaIdTarjeta,
  }) onPagar,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final cuentas = await ref.read(cuentaFinancieraRepositoryProvider).listar(soloActivas: true);
  if (!context.mounted) return false;
  final tarjetas = await ref.read(deudaRepositoryProvider).listarTarjetasActivas();
  if (!context.mounted) return false;

  final resultado = await RisegDialog.showForm<bool>(
    context: context,
    title: l10n.servicioEventualDialogoPagarTitulo,
    confirmLabel: l10n.servicioEventualBotonRegistrarPago,
    cancelLabel: l10n.compraBotonCancelarFormulario,
    contentBuilder: (_) => _FormularioPago(
      key: _clavePago,
      monto: monto,
      cuentas: cuentas,
      tarjetas: tarjetas,
      onPagar: onPagar,
    ),
    onConfirm: () async => _clavePago.currentState?.guardar(),
  );
  return resultado ?? false;
}

class _FormularioPago extends ConsumerStatefulWidget {
  const _FormularioPago({
    super.key,
    required this.monto,
    required this.cuentas,
    required this.tarjetas,
    required this.onPagar,
  });

  final int monto;
  final List<CuentaFinancieraData> cuentas;
  final List<DeudaData> tarjetas;
  final Future<Object> Function({
    required String formaPago,
    String? cuentaFinancieraId,
    String? deudaIdTarjeta,
  }) onPagar;

  @override
  ConsumerState<_FormularioPago> createState() => _FormularioPagoState();
}

class _FormularioPagoState extends ConsumerState<_FormularioPago> {
  String _formaPago = FormaPago.transferencia.name;
  String? _cuentaFinancieraId;
  String? _deudaIdTarjeta;
  String? _error;

  bool get _esTarjeta => _formaPago == FormaPago.tarjeta.name;

  /// `true` si guardó (el marco cierra), `null` si hay que
  /// corregir algo (el marco se queda abierto con el error a la vista).
  Future<bool?> guardar() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _error = null);
    // Saldo insuficiente no es un "error inesperado": lo traduce el
    // mecanismo central y el formulario sigue abierto, con lo ya
    // capturado, para que el usuario elija otra cuenta.
    final resultado = await ejecutarMostrandoSaldoInsuficiente(
      context,
      l10n,
      () => widget.onPagar(
        formaPago: _formaPago,
        cuentaFinancieraId: _esTarjeta ? null : _cuentaFinancieraId,
        deudaIdTarjeta: _esTarjeta ? _deudaIdTarjeta : null,
      ),
    );
    if (!mounted || resultado == null) return null;
    final mensaje = _mensajeDeResultado(l10n, resultado);
    if (mensaje == null) return true;
    setState(() => _error = mensaje);
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;

    return SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              formatoCentavosPago(widget.monto),
              style: AppTypography.heading3.copyWith(color: colors.textPrimary),
            ),
            const SizedBox(height: AppSpacing.md),
            RisegSelect<String?>(
              key: const Key('servicio_eventual_campo_forma_pago'),
              label: l10n.servicioEventualCampoFormaPago,
              value: _formaPago,
              items: [
                for (final forma in FormaPago.values)
                  RisegSelectItem(value: forma.name, label: formaPagoLabel(l10n, forma.name)),
              ],
              onChanged: (valor) => setState(() {
                _formaPago = valor ?? FormaPago.transferencia.name;
                // Cambiar de forma de pago limpia el otro origen: el
                // dominio rechaza cuenta y tarjeta a la vez.
                _cuentaFinancieraId = null;
                _deudaIdTarjeta = null;
              }),
            ),
            const SizedBox(height: AppSpacing.md),
            if (_esTarjeta) ...[
              RisegSelect<String?>(
                key: const Key('servicio_eventual_campo_tarjeta'),
                label: l10n.registrarTiempoExtraCampoTarjetaUtilizada,
                value: _deudaIdTarjeta,
                items: [for (final t in widget.tarjetas) RisegSelectItem(value: t.id, label: t.nombre)],
                onChanged: (valor) => setState(() => _deudaIdTarjeta = valor),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                l10n.servicioEventualPagoNotaTarjeta,
                style: AppTypography.caption.copyWith(color: colors.textMuted),
              ),
            ] else
              RisegSelect<String?>(
                key: const Key('servicio_eventual_campo_cuenta'),
                label: l10n.registrarTiempoExtraCampoCuentaOrigen,
                value: _cuentaFinancieraId,
                items: [for (final c in widget.cuentas) RisegSelectItem(value: c.id, label: c.nombre)],
                onChanged: (valor) => setState(() => _cuentaFinancieraId = valor),
              ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(_error!, style: AppTypography.caption.copyWith(color: colors.error)),
            ],
          ],
        ),
      ),
    );
  }
}
/// Subtotal · IVA · Total en una sola línea.
///
/// Es puro: no recalcula nada por su cuenta, sólo muestra lo que
/// `calcularTotalesVentaEventual` deriva — la misma tasa y el mismo
/// redondeo que usa la cobranza recurrente. Cero 0.16 escrito aquí.
class _DesgloseVenta extends StatelessWidget {
  const _DesgloseVenta({required this.importeTexto, required this.tratamientoIva});

  final String importeTexto;
  final TratamientoIva tratamientoIva;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;
    final importe = centavosDesdeTexto(importeTexto);
    if (importe == null || importe <= 0) return const SizedBox.shrink();

    final totales = calcularTotalesVentaEventual(importeAcordado: importe, tratamientoIva: tratamientoIva);
    final partes = [
      '${l10n.servicioEventualDesgloseSubtotal} ${formatoCentavosPago(totales.subtotal)}',
      if (totales.iva > 0) '${l10n.servicioEventualDesgloseIva} ${formatoCentavosPago(totales.iva)}',
      '${l10n.servicioEventualDesgloseTotal} ${formatoCentavosPago(totales.total)}',
    ];

    return Text(
      partes.join(' · '),
      key: const Key('servicio_eventual_desglose_venta'),
      style: AppTypography.caption.copyWith(color: colors.textMuted),
    );
  }
}

