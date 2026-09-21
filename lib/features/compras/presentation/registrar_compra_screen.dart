import 'package:riseg_one/features/finanzas/presentation/mensaje_saldo_insuficiente.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/finanzas/data/tables/pago_table.dart' show FormaPago;
import 'package:riseg_one/features/finanzas/domain/usecases/calcular_fecha_tarjeta_usecase.dart';
import 'package:riseg_one/features/finanzas/finanzas_providers.dart';
import 'package:riseg_one/features/finanzas/presentation/deudas_credito/deudas_credito_list_screen.dart' show formatoCentavosDeuda;
import 'package:riseg_one/features/finanzas/presentation/pagos/pagos_list_screen.dart' show formaPagoLabel;
import 'package:riseg_one/features/inventario/inventario_providers.dart';
import 'package:riseg_one/features/inventario/presentation/articulos/articulos_list_screen.dart' show formatoCosto;

import '../data/tables/compra_partida_table.dart' show DestinoCompraPartida;
import '../domain/repositories/compra_repository.dart';
import '../domain/usecases/registrar_compra_usecase.dart';
import 'compras_controller.dart';

int? _centavosDesdeTexto(String texto) {
  final normalizado = texto.trim().replaceAll(',', '');
  if (normalizado.isEmpty) return null;
  final pesos = double.tryParse(normalizado);
  if (pesos == null) return null;
  return (pesos * 100).round();
}

class _PartidaFormState {
  String destino = DestinoCompraPartida.inventario.name;
  ArticuloData? articulo;
  List<ArticuloVarianteData> variantes = const [];
  String? varianteId;
  final cantidadCtrl = TextEditingController(text: '1');
  final costoCtrl = TextEditingController();
  final conceptoCtrl = TextEditingController();
  final marcaCtrl = TextEditingController();
  final modeloCtrl = TextEditingController();
  List<TextEditingController> seriesCtrls = [];

  int get cantidad => int.tryParse(cantidadCtrl.text.trim()) ?? 0;
  int get costoUnitario => _centavosDesdeTexto(costoCtrl.text) ?? 0;
  int get subtotal => cantidad * costoUnitario;

  void ajustarSeries() {
    final requeridas = (articulo?.manejaSerie ?? false) ? cantidad.clamp(0, 500) : 0;
    while (seriesCtrls.length < requeridas) {
      seriesCtrls.add(TextEditingController());
    }
    while (seriesCtrls.length > requeridas) {
      seriesCtrls.removeLast().dispose();
    }
  }

  void dispose() {
    cantidadCtrl.dispose();
    costoCtrl.dispose();
    conceptoCtrl.dispose();
    marcaCtrl.dispose();
    modeloCtrl.dispose();
    for (final c in seriesCtrls) {
      c.dispose();
    }
  }
}

/// Registrar una Compra (Etapa 10) — pantalla completa, no diálogo
/// modal: el volumen potencial de partidas y la captura de números de
/// serie no caben cómodo en un `RisegDialog` pequeño. Cada partida
/// tiene destino independiente (Inventario/Gasto directo); el resumen
/// (total, cuántas partidas van a Inventario, el Egreso que se
/// generará) se muestra siempre visible antes del botón final —
/// "antes de confirmar definitivamente" del pedido original, sin un
/// paso de doble confirmación separado. Devuelve `true` por
/// `context.pop` si la Compra se registró.
class RegistrarCompraScreen extends ConsumerStatefulWidget {
  const RegistrarCompraScreen({super.key});

  @override
  ConsumerState<RegistrarCompraScreen> createState() => _RegistrarCompraScreenState();
}

class _RegistrarCompraScreenState extends ConsumerState<RegistrarCompraScreen> {
  DateTime _fecha = DateTime.now();
  final _proveedorCtrl = TextEditingController();
  String _formaPago = FormaPago.efectivo.name;
  final _formaPagoOtroCtrl = TextEditingController();
  final _observacionesCtrl = TextEditingController();
  final List<_PartidaFormState> _partidas = [_PartidaFormState()];
  String? _comprobantePath;
  String? _comprobanteNombre;
  List<ArticuloData> _articulos = const [];
  List<DeudaData> _tarjetas = const [];
  List<CuentaFinancieraData> _cuentasFinancieras = const [];
  String? _deudaId;
  String? _cuentaFinancieraId;
  String? _errorGeneral;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      final articulos = await ref.read(articuloRepositoryProvider).listar();
      if (mounted) setState(() => _articulos = articulos);
    });
    Future.microtask(() async {
      final tarjetas = await ref.read(deudaRepositoryProvider).listarTarjetasActivas();
      if (mounted) setState(() => _tarjetas = tarjetas);
    });
    Future.microtask(() async {
      final cuentas = await ref.read(cuentaFinancieraRepositoryProvider).listar(soloActivas: true);
      if (mounted) setState(() => _cuentasFinancieras = cuentas);
    });
  }

  @override
  void dispose() {
    _proveedorCtrl.dispose();
    _formaPagoOtroCtrl.dispose();
    _observacionesCtrl.dispose();
    for (final p in _partidas) {
      p.dispose();
    }
    super.dispose();
  }

  int get _totalGeneral => _partidas.fold<int>(0, (s, p) => s + p.subtotal);

  int get _partidasInventarioCount =>
      _partidas.where((p) => p.destino == DestinoCompraPartida.inventario.name).length;

  void _agregarPartida() {
    setState(() => _partidas.add(_PartidaFormState()));
  }

  void _quitarPartida(int indice) {
    setState(() {
      _partidas[indice].dispose();
      _partidas.removeAt(indice);
    });
  }

  Future<void> _seleccionarArticulo(_PartidaFormState p, ArticuloData? articulo) async {
    setState(() {
      p.articulo = articulo;
      p.varianteId = null;
      p.variantes = const [];
      p.ajustarSeries();
    });
    if (articulo != null && articulo.manejaVariante) {
      final variantes = await ref.read(articuloRepositoryProvider).listarVariantes(articulo.id);
      if (mounted) setState(() => p.variantes = variantes);
    }
  }

  Future<void> _seleccionarComprobante() async {
    final seleccion = await FilePicker.platform.pickFiles(allowedExtensions: ['pdf'], type: FileType.custom);
    final archivo = seleccion?.files.singleOrNull;
    if (archivo?.path == null) return;
    setState(() {
      _comprobantePath = archivo!.path;
      _comprobanteNombre = archivo.name;
    });
  }

  PartidaCompraInput _aInput(_PartidaFormState p) {
    final esInventario = p.destino == DestinoCompraPartida.inventario.name;
    return PartidaCompraInput(
      destino: p.destino,
      articuloId: esInventario ? p.articulo?.id : null,
      varianteId: esInventario ? p.varianteId : null,
      concepto: esInventario ? null : p.conceptoCtrl.text.trim(),
      cantidad: p.cantidad,
      costoUnitario: p.costoUnitario,
      numerosSerie: (esInventario && (p.articulo?.manejaSerie ?? false))
          ? p.seriesCtrls.map((c) => c.text.trim()).toList()
          : null,
      marca: p.marcaCtrl.text.trim().isEmpty ? null : p.marcaCtrl.text.trim(),
      modelo: p.modeloCtrl.text.trim().isEmpty ? null : p.modeloCtrl.text.trim(),
    );
  }

  Future<void> _confirmar() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _errorGeneral = null;
      _guardando = true;
    });

    // Saldo insuficiente no es un "error inesperado": lo traduce el
    // mecanismo central y el formulario sigue abierto, con lo ya
    // capturado, para que el usuario elija otra cuenta.
    final resultado = await ejecutarMostrandoSaldoInsuficiente(
      context,
      l10n,
      () => ref.read(comprasControllerProvider.notifier).registrarCompra(
          fecha: _fecha,
          proveedor: _proveedorCtrl.text,
          formaPago: _formaPago,
          formaPagoOtroDescripcion: _formaPagoOtroCtrl.text,
          observaciones: _observacionesCtrl.text,
          partidas: _partidas.map(_aInput).toList(),
          deudaId: _formaPago == FormaPago.tarjeta.name ? _deudaId : null,
          cuentaFinancieraId: _formaPago == FormaPago.tarjeta.name ? null : _cuentaFinancieraId,
        ),
    );
    if (!mounted || resultado == null) return;

    switch (resultado) {
      case RegistrarCompraExitosa(:final compra):
        if (_comprobantePath != null) {
          await ref.read(comprasControllerProvider.notifier).adjuntarComprobante(
                compraId: compra.id,
                sourceFilePath: _comprobantePath!,
                originalFileName: _comprobanteNombre!,
                mimeType: 'application/pdf',
              );
        }
        if (!mounted) return;
        RisegFeedback.showSuccess(context, l10n.compraGuardadaExito);
        context.pop(true);
        return;
      case RegistrarCompraListaVacia():
        _errorGeneral = l10n.compraErrorListaVacia;
      case RegistrarCompraFormaPagoInvalida():
        _errorGeneral = l10n.compraErrorFormaPagoInvalida;
      case RegistrarCompraFormaPagoOtroDescripcionRequerida():
        _errorGeneral = l10n.compraErrorFormaPagoOtroDescripcionRequerida;
      case RegistrarCompraPartidaDestinoInvalido(:final indice):
        _errorGeneral = l10n.compraErrorPartidaDestinoInvalido(indice + 1);
      case RegistrarCompraPartidaArticuloNoExiste(:final indice):
        _errorGeneral = l10n.compraErrorPartidaArticuloNoExiste(indice + 1);
      case RegistrarCompraPartidaVarianteInvalida(:final indice):
        _errorGeneral = l10n.compraErrorPartidaVarianteInvalida(indice + 1);
      case RegistrarCompraPartidaConceptoRequerido(:final indice):
        _errorGeneral = l10n.compraErrorPartidaConceptoRequerido(indice + 1);
      case RegistrarCompraPartidaCantidadInvalida(:final indice):
        _errorGeneral = l10n.compraErrorPartidaCantidadInvalida(indice + 1);
      case RegistrarCompraPartidaCostoInvalido(:final indice):
        _errorGeneral = l10n.compraErrorPartidaCostoInvalido(indice + 1);
      case RegistrarCompraPartidaNumerosSerieInvalidos(:final indice):
        _errorGeneral = l10n.compraErrorPartidaNumerosSerieInvalidos(_partidas[indice].cantidad, indice + 1);
      case RegistrarCompraPartidaNumeroSerieDuplicado():
        _errorGeneral = l10n.compraErrorPartidaNumeroSerieDuplicado;
      case RegistrarCompraTarjetaRequerida():
        _errorGeneral = l10n.compraErrorTarjetaRequerida;
      case RegistrarCompraTarjetaInvalida():
        _errorGeneral = l10n.compraErrorTarjetaInvalida;
      case RegistrarCompraTarjetaExcedeLimite(:final disponible):
        _errorGeneral = l10n.compraErrorTarjetaExcedeLimite(formatoCentavosDeuda(disponible));
      case RegistrarCompraTarjetaSinLimiteConfigurado():
        _errorGeneral = l10n.compraErrorTarjetaSinLimiteConfigurado;
      case RegistrarCompraErrorInesperado():
        _errorGeneral = l10n.compraErrorInesperado;
    }
    setState(() => _guardando = false);
  }

  Widget _partidaCard(int indice) {
    final l10n = AppLocalizations.of(context)!;
    final p = _partidas[indice];
    final esInventario = p.destino == DestinoCompraPartida.inventario.name;

    return RisegCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: RisegSelect<String>(
                  label: l10n.compraPartidaCampoDestino,
                  value: p.destino,
                  items: [
                    RisegSelectItem(value: DestinoCompraPartida.inventario.name, label: l10n.compraPartidaOpcionInventario),
                    RisegSelectItem(value: DestinoCompraPartida.gastoDirecto.name, label: l10n.compraPartidaOpcionGastoDirecto),
                  ],
                  onChanged: (valor) => setState(() => p.destino = valor ?? p.destino),
                ),
              ),
              if (_partidas.length > 1) ...[
                const SizedBox(width: AppSpacing.sm),
                RisegButton(
                  label: l10n.compraBotonQuitarPartida,
                  variant: RisegButtonVariant.ghost,
                  onPressed: () => _quitarPartida(indice),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (esInventario) ...[
            RisegSelect<String?>(
              label: l10n.compraPartidaCampoArticulo,
              value: p.articulo?.id,
              items: [for (final a in _articulos) RisegSelectItem(value: a.id, label: a.nombre)],
              onChanged: (valor) => _seleccionarArticulo(p, _articulos.where((a) => a.id == valor).firstOrNull),
            ),
            if (p.articulo?.manejaVariante ?? false) ...[
              const SizedBox(height: AppSpacing.md),
              RisegSelect<String?>(
                label: l10n.compraPartidaCampoVariante,
                value: p.varianteId,
                items: [for (final v in p.variantes) RisegSelectItem(value: v.id, label: v.valor)],
                onChanged: (valor) => setState(() => p.varianteId = valor),
              ),
            ],
          ] else
            RisegTextField(label: l10n.compraPartidaCampoConcepto, controller: p.conceptoCtrl),
          const SizedBox(height: AppSpacing.md),
          RisegFieldGrid(
            children: [
              RisegTextField(
                label: l10n.compraPartidaCampoCantidad,
                controller: p.cantidadCtrl,
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(p.ajustarSeries),
              ),
              RisegTextField(
                label: l10n.compraPartidaCampoCostoUnitario,
                controller: p.costoCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
              ),
            ],
          ),
          if (esInventario && (p.articulo?.manejaSerie ?? false)) ...[
            const SizedBox(height: AppSpacing.md),
            RisegFieldGrid(
              children: [
                RisegTextField(label: l10n.compraPartidaCampoMarca, controller: p.marcaCtrl),
                RisegTextField(label: l10n.compraPartidaCampoModelo, controller: p.modeloCtrl),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(l10n.compraPartidaAyudaSeries, style: AppTypography.caption.copyWith(color: context.colors.textMuted)),
            const SizedBox(height: AppSpacing.sm),
            for (var i = 0; i < p.seriesCtrls.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: RisegTextField(
                  label: l10n.compraPartidaCampoNumeroSerie(i + 1),
                  controller: p.seriesCtrls[i],
                ),
              ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Text(
            l10n.compraPartidaSubtotal(formatoCosto(p.subtotal)),
            style: AppTypography.label.copyWith(color: context.colors.textMuted),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.compraRegistrarDialogoTitulo)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Etapa 19: Fecha/Proveedor/Forma de pago comparten una
                // sola sección "Información de compra" con
                // `RisegFieldGrid` (responsive: 1 columna en anchos
                // reducidos) — antes eran dos `RisegCard` separadas con
                // `Row`+`Expanded` fijos, sin adaptarse por debajo de
                // ~600px.
                RisegCard(
                  child: RisegFormSection(
                    title: l10n.compraInformacionSeccionTitulo,
                    grid: true,
                    children: [
                      RisegDateField(
                        label: l10n.compraCampoFecha,
                        value: _fecha,
                        onChanged: (valor) => setState(() => _fecha = valor),
                      ),
                      RisegTextField(label: l10n.compraCampoProveedor, controller: _proveedorCtrl),
                      RisegSelect<String>(
                        label: l10n.compraCampoFormaPago,
                        value: _formaPago,
                        items: [
                          for (final f in FormaPago.values) RisegSelectItem(value: f.name, label: formaPagoLabel(l10n, f.name)),
                        ],
                        onChanged: (valor) => setState(() => _formaPago = valor ?? _formaPago),
                      ),
                      if (_formaPago == FormaPago.otro.name)
                        RisegTextField(label: l10n.compraCampoFormaPagoOtroDescripcion, controller: _formaPagoOtroCtrl),
                      if (_formaPago == FormaPago.tarjeta.name)
                        RisegSelect<String?>(
                          label: l10n.compraCampoTarjeta,
                          value: _deudaId,
                          items: [
                            for (final t in _tarjetas)
                              RisegSelectItem(
                                value: t.id,
                                label: l10n.compraTarjetaOpcionEtiqueta(
                                  t.nombre,
                                  t.tarjetaUltimosDigitos ?? '----',
                                  () {
                                    final disponible = creditoDisponibleTarjeta(limiteCredito: t.tarjetaLimiteCredito, saldoActual: t.saldoActual);
                                    return disponible == null ? l10n.deudaTarjetaSinDato : formatoCentavosDeuda(disponible);
                                  }(),
                                ),
                              ),
                          ],
                          onChanged: (valor) => setState(() => _deudaId = valor),
                        ),
                      if (_formaPago != FormaPago.tarjeta.name)
                        RisegSelect<String?>(
                          label: l10n.movimientoCampoCuentaFinanciera,
                          value: _cuentaFinancieraId,
                          items: [
                            RisegSelectItem(value: null, label: l10n.egresoCampoSinAsignar),
                            for (final c in _cuentasFinancieras) RisegSelectItem(value: c.id, label: c.nombre),
                          ],
                          onChanged: (valor) => setState(() => _cuentaFinancieraId = valor),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                Text(l10n.compraPartidasSeccionTitulo, style: AppTypography.heading3),
                const SizedBox(height: AppSpacing.sm),
                for (var i = 0; i < _partidas.length; i++) ...[
                  _partidaCard(i),
                  const SizedBox(height: AppSpacing.md),
                ],
                RisegButton(
                  label: l10n.compraBotonAgregarPartida,
                  variant: RisegButtonVariant.secondary,
                  icon: Icons.add,
                  onPressed: _agregarPartida,
                ),
                const SizedBox(height: AppSpacing.xl),
                RisegCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      RisegTextField(label: l10n.compraCampoObservaciones, controller: _observacionesCtrl),
                      const SizedBox(height: AppSpacing.md),
                      Text(l10n.compraCampoComprobante, style: AppTypography.label),
                      const SizedBox(height: AppSpacing.xs),
                      if (_comprobantePath == null)
                        RisegButton(
                          label: l10n.compraBotonSeleccionarComprobante,
                          variant: RisegButtonVariant.secondary,
                          icon: Icons.attach_file,
                          onPressed: _seleccionarComprobante,
                        )
                      else
                        Row(
                          children: [
                            Expanded(child: Text(_comprobanteNombre ?? '', overflow: TextOverflow.ellipsis)),
                            RisegButton(
                              label: l10n.crearEmpleadoBotonQuitar,
                              variant: RisegButtonVariant.ghost,
                              onPressed: () => setState(() {
                                _comprobantePath = null;
                                _comprobanteNombre = null;
                              }),
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
                      Text(l10n.compraResumenTitulo, style: AppTypography.heading3),
                      const SizedBox(height: AppSpacing.sm),
                      Text(l10n.compraTotalGeneral(formatoCosto(_totalGeneral)), style: AppTypography.body),
                      if (_partidasInventarioCount > 0)
                        Text(l10n.compraResumenPartidasInventario(_partidasInventarioCount), style: AppTypography.body),
                      Text(l10n.compraResumenEgreso(formatoCosto(_totalGeneral)), style: AppTypography.body),
                    ],
                  ),
                ),
                if (_errorGeneral != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(_errorGeneral!, style: AppTypography.caption.copyWith(color: Theme.of(context).colorScheme.error)),
                ],
                const SizedBox(height: AppSpacing.xl),
                RisegButton(
                  label: l10n.compraBotonGuardar,
                  onPressed: _guardando ? null : _confirmar,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
