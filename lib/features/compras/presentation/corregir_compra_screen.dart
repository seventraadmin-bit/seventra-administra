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
import '../domain/usecases/correccion_partida_compra.dart';
import '../domain/usecases/corregir_compra_usecase.dart';
import 'compras_controller.dart';

int? _centavosDesdeTexto(String texto) {
  final normalizado = texto.trim().replaceAll(',', '');
  if (normalizado.isEmpty) return null;
  final pesos = double.tryParse(normalizado);
  if (pesos == null) return null;
  return (pesos * 100).round();
}

/// Estado de edición de una `CompraPartida` que ya existía antes de
/// abrir la corrección — precargada con sus valores reales. Para
/// artículos serializados, el cambio de artículo/variante se bloquea
/// deliberadamente en esta tarjeta (ver `compraCorregirPartidaSerializadaAyuda`):
/// esa sustitución es la operación B ("otra unidad distinta"), que aquí
/// se resuelve como quitar la partida y agregar una nueva, nunca como
/// una edición in-place de esta tarjeta.
class _PartidaExistenteState {
  _PartidaExistenteState(this.original);

  final CompraPartidaData original;

  ArticuloData? articulo;
  bool manejaSerie = false;
  bool manejaVariante = false;
  List<ArticuloVarianteData> variantes = const [];
  String? articuloIdSeleccionado;
  String? varianteIdSeleccionada;

  List<ArticuloUnidadData> unidadesExistentes = const [];
  final Set<String> unidadesAEliminar = {};
  final List<TextEditingController> seriesNuevasCtrls = [];

  late final TextEditingController cantidadCtrl = TextEditingController(text: '${original.cantidad}');
  late final TextEditingController costoCtrl =
      TextEditingController(text: (original.costoUnitario / 100).toStringAsFixed(2));

  bool quitarCompleta = false;

  bool get esInventario => original.destino == DestinoCompraPartida.inventario.name;
  int get cantidad => int.tryParse(cantidadCtrl.text.trim()) ?? original.cantidad;
  int get costoUnitario => _centavosDesdeTexto(costoCtrl.text) ?? original.costoUnitario;

  void dispose() {
    cantidadCtrl.dispose();
    costoCtrl.dispose();
    for (final c in seriesNuevasCtrls) {
      c.dispose();
    }
  }
}

/// Estado de captura de una partida completamente nueva agregada
/// durante la corrección — misma forma que `_PartidaFormState` de
/// `RegistrarCompraScreen` (Etapa 10), duplicada deliberadamente: cada
/// pantalla es dueña de su propio estado de formulario, mismo criterio
/// que el resto del proyecto (ningún widget de formulario comparte
/// estado mutable entre pantallas).
class _PartidaNuevaState {
  String destino = DestinoCompraPartida.inventario.name;
  ArticuloData? articulo;
  List<ArticuloVarianteData> variantes = const [];
  String? varianteId;
  final cantidadCtrl = TextEditingController(text: '1');
  final costoCtrl = TextEditingController();
  final conceptoCtrl = TextEditingController();
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
    for (final c in seriesCtrls) {
      c.dispose();
    }
  }
}

/// Corregir una Compra ya registrada (Etapa 15, ampliación real de
/// "Corregir datos") — pantalla completa que reutiliza la estructura
/// de `RegistrarCompraScreen`: datos generales precargados, cada
/// partida existente editable dentro de límites seguros (artículo/
/// variante y cantidad/costo para fungibles; solo cantidad —vía alta/
/// baja de unidades— y costo para serializados), partidas nuevas
/// agregables, partidas existentes marcables para quitar. Antes de
/// guardar si hay cambios de partidas, se consulta
/// `obtenerResumenCorreccion` para bloquear correcciones inseguras y
/// mostrar el impacto real (nunca inventado) en un diálogo de
/// confirmación final.
class CorregirCompraScreen extends ConsumerStatefulWidget {
  const CorregirCompraScreen({required this.compraId, super.key});

  final String compraId;

  @override
  ConsumerState<CorregirCompraScreen> createState() => _CorregirCompraScreenState();
}

class _CorregirCompraScreenState extends ConsumerState<CorregirCompraScreen> {
  CompraData? _compra;
  bool _cargando = true;
  bool _guardando = false;
  String? _errorGeneral;

  late DateTime _fecha;
  final _proveedorCtrl = TextEditingController();
  String _formaPago = FormaPago.efectivo.name;
  final _formaPagoOtroCtrl = TextEditingController();
  final _observacionesCtrl = TextEditingController();
  final _motivoCtrl = TextEditingController();

  // Etapa 3 (corrección financiera Cuenta↔TDC): origen financiero real,
  // sin bloqueo artificial — mismo par de selectores condicionales que
  // `RegistrarCompraScreen` (Etapa 10/19B), precargados con el origen
  // vigente de la Compra.
  List<DeudaData> _tarjetas = const [];
  List<CuentaFinancieraData> _cuentasFinancieras = const [];
  String? _deudaIdSeleccionada;
  String? _cuentaFinancieraIdSeleccionada;
  String? _deudaIdAnterior;
  String? _cuentaFinancieraIdAnterior;
  String _origenActualLabel = '—';

  List<ArticuloData> _articulos = const [];
  final List<_PartidaExistenteState> _existentes = [];
  final List<_PartidaNuevaState> _nuevas = [];

  @override
  void initState() {
    super.initState();
    _fecha = DateTime.now();
    _cargar();
  }

  @override
  void dispose() {
    _proveedorCtrl.dispose();
    _formaPagoOtroCtrl.dispose();
    _observacionesCtrl.dispose();
    _motivoCtrl.dispose();
    for (final e in _existentes) {
      e.dispose();
    }
    for (final n in _nuevas) {
      n.dispose();
    }
    super.dispose();
  }

  Future<void> _cargar() async {
    final notifier = ref.read(comprasControllerProvider.notifier);
    final compra = await notifier.obtenerCompra(widget.compraId);
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    if (compra == null) {
      setState(() {
        _compra = null;
        _cargando = false;
      });
      return;
    }

    final partidas = await notifier.obtenerPartidas(widget.compraId);
    final articuloRepo = ref.read(articuloRepositoryProvider);
    final articulos = await articuloRepo.listar();
    final articulosPorId = {for (final a in articulos) a.id: a};

    final tarjetas = await ref.read(deudaRepositoryProvider).listarTarjetasActivas();
    final cuentas = await ref.read(cuentaFinancieraRepositoryProvider).listar(soloActivas: true);

    String? cuentaFinancieraIdAnterior;
    String origenActualLabel = l10n.compraCampoSinOrigenFinanciero;
    if (compra.deudaId != null) {
      final tarjeta = await ref.read(deudaRepositoryProvider).obtenerPorId(compra.deudaId!);
      origenActualLabel = tarjeta == null
          ? l10n.compraCampoTarjeta
          : l10n.compraTarjetaOpcionEtiquetaSimple(tarjeta.nombre, tarjeta.tarjetaUltimosDigitos ?? '----');
    } else if (compra.egresoId != null) {
      final egreso = await ref.read(egresoRepositoryProvider).obtenerPorId(compra.egresoId!);
      cuentaFinancieraIdAnterior = egreso?.cuentaFinancieraId;
      if (cuentaFinancieraIdAnterior != null) {
        final cuenta = await ref.read(cuentaFinancieraRepositoryProvider).obtenerPorId(cuentaFinancieraIdAnterior);
        origenActualLabel = cuenta?.nombre ?? l10n.movimientoCampoCuentaFinanciera;
      } else {
        origenActualLabel = l10n.egresoCampoSinAsignar;
      }
    }

    final existentes = <_PartidaExistenteState>[];
    for (final p in partidas) {
      final e = _PartidaExistenteState(p);
      if (p.destino == DestinoCompraPartida.inventario.name && p.articuloId != null) {
        e.articuloIdSeleccionado = p.articuloId;
        e.varianteIdSeleccionada = p.varianteId;
        final articulo = articulosPorId[p.articuloId] ?? await articuloRepo.obtenerPorId(p.articuloId!);
        e.articulo = articulo;
        e.manejaSerie = articulo?.manejaSerie ?? false;
        e.manejaVariante = articulo?.manejaVariante ?? false;
        if (e.manejaVariante) {
          e.variantes = await articuloRepo.listarVariantes(p.articuloId!);
        }
        if (e.manejaSerie) {
          e.unidadesExistentes = await notifier.obtenerUnidadesPorPartida(p.id);
        }
      }
      existentes.add(e);
    }

    if (!mounted) return;
    setState(() {
      _compra = compra;
      _fecha = compra.fecha;
      _proveedorCtrl.text = compra.proveedor ?? '';
      _formaPago = compra.formaPago;
      _formaPagoOtroCtrl.text = compra.formaPagoOtroDescripcion ?? '';
      _observacionesCtrl.text = compra.observaciones ?? '';
      _articulos = articulos;
      _tarjetas = tarjetas;
      _cuentasFinancieras = cuentas;
      _deudaIdSeleccionada = compra.deudaId;
      _deudaIdAnterior = compra.deudaId;
      _cuentaFinancieraIdSeleccionada = cuentaFinancieraIdAnterior;
      _cuentaFinancieraIdAnterior = cuentaFinancieraIdAnterior;
      _origenActualLabel = origenActualLabel;
      _existentes
        ..clear()
        ..addAll(existentes);
      _cargando = false;
    });
  }

  Future<void> _cambiarArticuloExistente(_PartidaExistenteState e, ArticuloData? articulo) async {
    setState(() {
      e.articulo = articulo;
      e.articuloIdSeleccionado = articulo?.id;
      e.varianteIdSeleccionada = null;
      e.variantes = const [];
      e.manejaVariante = articulo?.manejaVariante ?? false;
    });
    if (articulo != null && articulo.manejaVariante) {
      final variantes = await ref.read(articuloRepositoryProvider).listarVariantes(articulo.id);
      if (mounted) setState(() => e.variantes = variantes);
    }
  }

  void _agregarPartidaNueva() => setState(() => _nuevas.add(_PartidaNuevaState()));

  void _quitarPartidaNueva(int indice) {
    setState(() {
      _nuevas[indice].dispose();
      _nuevas.removeAt(indice);
    });
  }

  Future<void> _seleccionarArticuloNueva(_PartidaNuevaState n, ArticuloData? articulo) async {
    setState(() {
      n.articulo = articulo;
      n.varianteId = null;
      n.variantes = const [];
      n.ajustarSeries();
    });
    if (articulo != null && articulo.manejaVariante) {
      final variantes = await ref.read(articuloRepositoryProvider).listarVariantes(articulo.id);
      if (mounted) setState(() => n.variantes = variantes);
    }
  }

  String _descripcionArticulo(String? articuloId, String? varianteId, List<ArticuloVarianteData> variantes) {
    if (articuloId == null) return '—';
    final articulo = _articulos.where((a) => a.id == articuloId).firstOrNull;
    final nombre = articulo?.nombre ?? articuloId;
    if (varianteId == null) return nombre;
    final variante = variantes.where((v) => v.id == varianteId).firstOrNull;
    return variante == null ? nombre : '$nombre · ${variante.valor}';
  }

  String _descripcionPartidaExistente(_PartidaExistenteState e) {
    if (!e.esInventario) return e.original.concepto ?? '—';
    return _descripcionArticulo(e.original.articuloId, e.original.varianteId, e.variantes);
  }

  PartidaCompraInput _inputDesdeNueva(_PartidaNuevaState n) {
    final esInventario = n.destino == DestinoCompraPartida.inventario.name;
    return PartidaCompraInput(
      destino: n.destino,
      articuloId: esInventario ? n.articulo?.id : null,
      varianteId: esInventario ? n.varianteId : null,
      concepto: esInventario ? null : n.conceptoCtrl.text.trim(),
      cantidad: n.cantidad,
      costoUnitario: n.costoUnitario,
      numerosSerie:
          (esInventario && (n.articulo?.manejaSerie ?? false)) ? n.seriesCtrls.map((c) => c.text.trim()).toList() : null,
    );
  }

  List<CorreccionPartida> _construirCambios() {
    final cambios = <CorreccionPartida>[];

    for (final e in _existentes) {
      if (e.quitarCompleta) {
        cambios.add(CorreccionPartidaQuitar(compraPartidaId: e.original.id));
        continue;
      }

      if (!e.esInventario) {
        final huboCambioCantidadGasto = e.cantidad != e.original.cantidad;
        final huboCambioCostoGasto = e.costoUnitario != e.original.costoUnitario;
        if (huboCambioCantidadGasto || huboCambioCostoGasto) {
          cambios.add(
            CorreccionPartidaCantidadCosto(
              compraPartidaId: e.original.id,
              nuevaCantidad: huboCambioCantidadGasto ? e.cantidad : null,
              nuevoCostoUnitario: huboCambioCostoGasto ? e.costoUnitario : null,
            ),
          );
        }
        continue;
      }

      if (e.manejaSerie) {
        final huboCambioCosto = e.costoUnitario != e.original.costoUnitario;
        final huboCambioUnidades = e.unidadesAEliminar.isNotEmpty || e.seriesNuevasCtrls.isNotEmpty;
        if (huboCambioCosto || huboCambioUnidades) {
          cambios.add(
            CorreccionPartidaCantidadCosto(
              compraPartidaId: e.original.id,
              nuevoCostoUnitario: huboCambioCosto ? e.costoUnitario : null,
              numerosSerieNuevos: e.seriesNuevasCtrls.map((c) => c.text.trim()).toList(),
              unidadesIdAEliminar: e.unidadesAEliminar.toList(),
            ),
          );
        }
        continue;
      }

      final articuloCambio = e.articuloIdSeleccionado != null && e.articuloIdSeleccionado != e.original.articuloId;
      final varianteCambio = e.varianteIdSeleccionada != e.original.varianteId;
      final huboCambioCantidad = e.cantidad != e.original.cantidad;
      final huboCambioCosto = e.costoUnitario != e.original.costoUnitario;

      if (articuloCambio || varianteCambio) {
        cambios.add(
          CorreccionPartidaVariante(
            compraPartidaId: e.original.id,
            nuevoArticuloId: e.articuloIdSeleccionado ?? e.original.articuloId!,
            nuevaVarianteId: e.varianteIdSeleccionada,
            nuevaCantidad: huboCambioCantidad ? e.cantidad : null,
            nuevoCostoUnitario: huboCambioCosto ? e.costoUnitario : null,
          ),
        );
      } else if (huboCambioCantidad || huboCambioCosto) {
        cambios.add(
          CorreccionPartidaCantidadCosto(
            compraPartidaId: e.original.id,
            nuevaCantidad: huboCambioCantidad ? e.cantidad : null,
            nuevoCostoUnitario: huboCambioCosto ? e.costoUnitario : null,
          ),
        );
      }
    }

    for (final n in _nuevas) {
      cambios.add(CorreccionPartidaAgregar(input: _inputDesdeNueva(n)));
    }

    return cambios;
  }

  List<String> _lineasImpacto(AppLocalizations l10n, ResumenCorreccionCompra resumen) {
    final lineas = <String>[];
    if (resumen.totalAnterior != null && resumen.totalNuevo != null && resumen.totalAnterior != resumen.totalNuevo) {
      lineas.add(l10n.compraCorregirResumenTotalLinea(formatoCosto(resumen.totalAnterior!), formatoCosto(resumen.totalNuevo!)));
      if (_compra?.egresoId != null) {
        lineas.add(l10n.compraCorregirResumenEgresoLinea(formatoCosto(resumen.totalAnterior!), formatoCosto(resumen.totalNuevo!)));
      }
    }

    for (final e in _existentes) {
      if (e.quitarCompleta) continue;
      final nombreAnterior = _descripcionPartidaExistente(e);
      final cantidadAnterior = e.manejaSerie ? e.unidadesExistentes.length : e.original.cantidad;
      final cantidadNueva = e.manejaSerie
          ? e.unidadesExistentes.length - e.unidadesAEliminar.length + e.seriesNuevasCtrls.length
          : e.cantidad;
      final costoNuevo = e.costoUnitario;
      final huboCambioArticulo =
          e.esInventario && (e.articuloIdSeleccionado != e.original.articuloId || e.varianteIdSeleccionada != e.original.varianteId);
      if (cantidadAnterior == cantidadNueva && costoNuevo == e.original.costoUnitario && !huboCambioArticulo) {
        continue;
      }
      final nombreNuevo = (e.esInventario && !e.manejaSerie)
          ? _descripcionArticulo(e.articuloIdSeleccionado, e.varianteIdSeleccionada, e.variantes)
          : nombreAnterior;
      final etiquetaArticulo = nombreAnterior == nombreNuevo ? nombreNuevo : '$nombreAnterior → $nombreNuevo';
      lineas.add(
        l10n.compraCorregirResumenPartidaLinea(
          etiquetaArticulo,
          '$cantidadAnterior',
          '$cantidadNueva',
          formatoCosto(e.original.costoUnitario),
          formatoCosto(costoNuevo),
        ),
      );
    }

    for (final e in _existentes) {
      if (e.quitarCompleta) {
        lineas.add(l10n.compraCorregirResumenPartidaQuitadaLinea(_descripcionPartidaExistente(e)));
      }
    }

    for (final n in _nuevas) {
      if (n.destino != DestinoCompraPartida.inventario.name || n.articulo == null) continue;
      lineas.add(l10n.compraCorregirResumenPartidaNuevaLinea(n.articulo!.nombre, '${n.cantidad}'));
    }

    return lineas;
  }

  Future<bool> _confirmarImpacto(AppLocalizations l10n, ResumenCorreccionCompra resumen) async {
    final lineas = _lineasImpacto(l10n, resumen);
    if (lineas.isEmpty) return true;

    final confirmado = await RisegDialog.showForm<bool>(
      context: context,
      title: l10n.compraCorregirResumenImpactoTitulo,
      confirmLabel: l10n.compraCorregirBotonConfirmarImpacto,
      cancelLabel: l10n.compraBotonCancelarFormulario,
      contentBuilder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [for (final linea in lineas) Padding(padding: const EdgeInsets.only(bottom: AppSpacing.xs), child: Text('• $linea'))],
      ),
      onConfirm: () async => true,
    );
    return confirmado ?? false;
  }

  Future<void> _guardar() async {
    final l10n = AppLocalizations.of(context)!;
    if (_motivoCtrl.text.trim().isEmpty) {
      setState(() => _errorGeneral = l10n.compraCorregirErrorMotivoRequerido);
      return;
    }

    setState(() {
      _errorGeneral = null;
      _guardando = true;
    });

    final cambios = _construirCambios();

    if (cambios.isNotEmpty) {
      final resumen = await ref.read(comprasControllerProvider.notifier).obtenerResumenCorreccion(
            compraId: widget.compraId,
            cambiosPartidas: cambios,
          );
      if (!mounted) return;
      if (resumen.bloqueado) {
        setState(() {
          _errorGeneral = l10n.compraCorregirDependenciaBloqueada(resumen.detalleBloqueo!);
          _guardando = false;
        });
        return;
      }
      final continuar = await _confirmarImpacto(l10n, resumen);
      if (!mounted) return;
      if (!continuar) {
        setState(() => _guardando = false);
        return;
      }
    }

    final esTarjeta = _formaPago == FormaPago.tarjeta.name;
    final nuevaDeudaId = esTarjeta && _deudaIdSeleccionada != _deudaIdAnterior ? _deudaIdSeleccionada : null;
    final nuevaCuentaFinancieraId =
        !esTarjeta && _cuentaFinancieraIdSeleccionada != _cuentaFinancieraIdAnterior ? _cuentaFinancieraIdSeleccionada : null;

    final resultado = await ref.read(comprasControllerProvider.notifier).corregirCompra(
          compraId: widget.compraId,
          fecha: _fecha,
          proveedor: _proveedorCtrl.text,
          formaPago: _formaPago,
          formaPagoOtroDescripcion: _formaPagoOtroCtrl.text,
          observaciones: _observacionesCtrl.text,
          cambiosPartidas: cambios,
          motivo: _motivoCtrl.text.trim(),
          nuevaCuentaFinancieraId: nuevaCuentaFinancieraId,
          nuevaDeudaId: nuevaDeudaId,
        );
    if (!mounted) return;

    switch (resultado) {
      case CorregirCompraExitosa():
        RisegFeedback.showSuccess(context, l10n.compraCorregirExito);
        context.pop(true);
        return;
      case CorregirCompraNoExiste():
        _errorGeneral = l10n.compraCorregirNoExiste;
      case CorregirCompraCancelada():
        _errorGeneral = l10n.compraCorregirCancelada;
      case CorregirCompraOrigenAmbiguo():
        _errorGeneral = l10n.compraCorregirOrigenAmbiguo;
      case CorregirCompraTarjetaInvalida():
        _errorGeneral = l10n.compraErrorTarjetaInvalida;
      case CorregirCompraTarjetaExcedeLimite(:final disponible):
        _errorGeneral = l10n.compraErrorTarjetaExcedeLimite(formatoCosto(disponible));
      case CorregirCompraTarjetaSinLimiteConfigurado():
        _errorGeneral = l10n.compraErrorTarjetaSinLimiteConfigurado;
      case CorregirCompraPartidaInvalida(:final indice, :final motivo):
        _errorGeneral = l10n.compraCorregirPartidaInvalida(indice + 1, motivo);
      case CorregirCompraTieneDependencias(:final detalle):
        _errorGeneral = l10n.compraCorregirDependenciaBloqueada(detalle);
      case CorregirCompraErrorInesperado():
        _errorGeneral = l10n.compraErrorInesperado;
      case CorregirCompraMotivoRequerido():
        _errorGeneral = l10n.compraCorregirErrorMotivoRequerido;
    }
    setState(() => _guardando = false);
  }

  Widget _partidaExistenteCard(int indice) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;
    final e = _existentes[indice];

    if (e.quitarCompleta) {
      return RisegCard(
        child: Row(
          children: [
            Expanded(
              child: Text(
                l10n.compraCorregirResumenPartidaQuitadaLinea(_descripcionPartidaExistente(e)),
                style: AppTypography.body.copyWith(color: colors.textMuted, decoration: TextDecoration.lineThrough),
              ),
            ),
            RisegButton(
              label: l10n.compraCorregirBotonDeshacerQuitar,
              variant: RisegButtonVariant.ghost,
              onPressed: () => setState(() => e.quitarCompleta = false),
            ),
          ],
        ),
      );
    }

    return RisegCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(_descripcionPartidaExistente(e), style: AppTypography.label)),
              RisegButton(
                label: l10n.compraCorregirBotonQuitarPartidaCompleta,
                variant: RisegButtonVariant.ghost,
                onPressed: () => setState(() => e.quitarCompleta = true),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (!e.esInventario) ...[
            Row(
              children: [
                Expanded(child: RisegTextField(label: l10n.compraPartidaCampoCantidad, controller: e.cantidadCtrl, keyboardType: TextInputType.number)),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: RisegTextField(
                    label: l10n.compraPartidaCampoCostoUnitario,
                    controller: e.costoCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                ),
              ],
            ),
          ] else if (e.manejaSerie) ...[
            Text(l10n.compraCorregirPartidaSerializadaAyuda, style: AppTypography.caption.copyWith(color: colors.textMuted)),
            const SizedBox(height: AppSpacing.sm),
            RisegTextField(label: l10n.compraPartidaCampoCostoUnitario, controller: e.costoCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true)),
            const SizedBox(height: AppSpacing.sm),
            for (final u in e.unidadesExistentes)
              if (!e.unidadesAEliminar.contains(u.id))
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: Row(
                    children: [
                      Expanded(child: Text(l10n.compraCorregirUnidadExistente(u.codigo, u.numeroSerie))),
                      RisegButton(
                        label: l10n.compraCorregirBotonQuitarUnidad,
                        variant: RisegButtonVariant.ghost,
                        size: RisegButtonSize.compact,
                        onPressed: () => setState(() => e.unidadesAEliminar.add(u.id)),
                      ),
                    ],
                  ),
                ),
            for (var i = 0; i < e.seriesNuevasCtrls.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: RisegTextField(
                  label: '${l10n.compraCorregirCampoNumeroSerieNueva} #${i + 1}',
                  controller: e.seriesNuevasCtrls[i],
                ),
              ),
            RisegButton(
              label: l10n.compraCorregirBotonAgregarUnidad,
              variant: RisegButtonVariant.secondary,
              icon: Icons.add,
              onPressed: () => setState(() => e.seriesNuevasCtrls.add(TextEditingController())),
            ),
          ] else ...[
            RisegSelect<String?>(
              label: l10n.compraPartidaCampoArticulo,
              value: e.articuloIdSeleccionado,
              items: [for (final a in _articulos.where((a) => !a.manejaSerie)) RisegSelectItem(value: a.id, label: a.nombre)],
              onChanged: (valor) => _cambiarArticuloExistente(e, _articulos.where((a) => a.id == valor).firstOrNull),
            ),
            if (e.manejaVariante) ...[
              const SizedBox(height: AppSpacing.md),
              RisegSelect<String?>(
                label: l10n.compraPartidaCampoVariante,
                value: e.varianteIdSeleccionada,
                items: [for (final v in e.variantes) RisegSelectItem(value: v.id, label: v.valor)],
                onChanged: (valor) => setState(() => e.varianteIdSeleccionada = valor),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(child: RisegTextField(label: l10n.compraPartidaCampoCantidad, controller: e.cantidadCtrl, keyboardType: TextInputType.number)),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: RisegTextField(
                    label: l10n.compraPartidaCampoCostoUnitario,
                    controller: e.costoCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _partidaNuevaCard(int indice) {
    final l10n = AppLocalizations.of(context)!;
    final n = _nuevas[indice];
    final esInventario = n.destino == DestinoCompraPartida.inventario.name;

    return RisegCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: RisegSelect<String>(
                  label: l10n.compraPartidaCampoDestino,
                  value: n.destino,
                  items: [
                    RisegSelectItem(value: DestinoCompraPartida.inventario.name, label: l10n.compraPartidaOpcionInventario),
                    RisegSelectItem(value: DestinoCompraPartida.gastoDirecto.name, label: l10n.compraPartidaOpcionGastoDirecto),
                  ],
                  onChanged: (valor) => setState(() => n.destino = valor ?? n.destino),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              RisegButton(
                label: l10n.compraBotonQuitarPartida,
                variant: RisegButtonVariant.ghost,
                onPressed: () => _quitarPartidaNueva(indice),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (esInventario) ...[
            RisegSelect<String?>(
              label: l10n.compraPartidaCampoArticulo,
              value: n.articulo?.id,
              items: [for (final a in _articulos) RisegSelectItem(value: a.id, label: a.nombre)],
              onChanged: (valor) => _seleccionarArticuloNueva(n, _articulos.where((a) => a.id == valor).firstOrNull),
            ),
            if (n.articulo?.manejaVariante ?? false) ...[
              const SizedBox(height: AppSpacing.md),
              RisegSelect<String?>(
                label: l10n.compraPartidaCampoVariante,
                value: n.varianteId,
                items: [for (final v in n.variantes) RisegSelectItem(value: v.id, label: v.valor)],
                onChanged: (valor) => setState(() => n.varianteId = valor),
              ),
            ],
          ] else
            RisegTextField(label: l10n.compraPartidaCampoConcepto, controller: n.conceptoCtrl),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: RisegTextField(
                  label: l10n.compraPartidaCampoCantidad,
                  controller: n.cantidadCtrl,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(n.ajustarSeries),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: RisegTextField(
                  label: l10n.compraPartidaCampoCostoUnitario,
                  controller: n.costoCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          if (esInventario && (n.articulo?.manejaSerie ?? false)) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(l10n.compraPartidaAyudaSeries, style: AppTypography.caption.copyWith(color: context.colors.textMuted)),
            const SizedBox(height: AppSpacing.sm),
            for (var i = 0; i < n.seriesCtrls.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: RisegTextField(label: l10n.compraPartidaCampoNumeroSerie(i + 1), controller: n.seriesCtrls[i]),
              ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Text(l10n.compraPartidaSubtotal(formatoCosto(n.subtotal)), style: AppTypography.label.copyWith(color: context.colors.textMuted)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    if (_cargando) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final compra = _compra;
    if (compra == null) {
      return Scaffold(appBar: AppBar(), body: RisegEmptyState(title: l10n.compraExpedienteCargaErrorTitulo, message: ''));
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.compraCorregirScreenTitulo(compra.folioCompra))),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RisegCard(
                  child: RisegFormSection(
                    title: l10n.compraInformacionSeccionTitulo,
                    grid: true,
                    children: [
                      RisegDateField(label: l10n.compraCampoFecha, value: _fecha, onChanged: (valor) => setState(() => _fecha = valor)),
                      RisegTextField(label: l10n.compraCampoProveedor, controller: _proveedorCtrl),
                      RisegTextField(label: l10n.compraCampoObservaciones, controller: _observacionesCtrl),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                // Etapa 3 (corrección financiera Cuenta↔TDC): mismo par
                // de selectores condicionales que `RegistrarCompraScreen`
                // — sin bloqueo artificial. El caption muestra el origen
                // vigente para que la corrección sea explícita, nunca
                // implícita en el texto de la forma de pago.
                RisegCard(
                  child: RisegFormSection(
                    title: l10n.compraCorregirSeccionOrigen,
                    description: l10n.compraCorregirOrigenActual(_origenActualLabel),
                    grid: true,
                    children: [
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
                          value: _deudaIdSeleccionada,
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
                          onChanged: (valor) => setState(() => _deudaIdSeleccionada = valor),
                        ),
                      if (_formaPago != FormaPago.tarjeta.name)
                        RisegSelect<String?>(
                          label: l10n.movimientoCampoCuentaFinanciera,
                          value: _cuentaFinancieraIdSeleccionada,
                          items: [
                            RisegSelectItem(value: null, label: l10n.egresoCampoSinAsignar),
                            for (final c in _cuentasFinancieras) RisegSelectItem(value: c.id, label: c.nombre),
                          ],
                          onChanged: (valor) => setState(() => _cuentaFinancieraIdSeleccionada = valor),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                Text(l10n.compraCorregirSeccionPartidas, style: AppTypography.heading3),
                const SizedBox(height: AppSpacing.sm),
                for (var i = 0; i < _existentes.length; i++) ...[
                  _partidaExistenteCard(i),
                  const SizedBox(height: AppSpacing.md),
                ],
                for (var i = 0; i < _nuevas.length; i++) ...[
                  _partidaNuevaCard(i),
                  const SizedBox(height: AppSpacing.md),
                ],
                RisegButton(
                  label: l10n.compraBotonAgregarPartida,
                  variant: RisegButtonVariant.secondary,
                  icon: Icons.add,
                  onPressed: _agregarPartidaNueva,
                ),
                const SizedBox(height: AppSpacing.xl),
                RisegTextField(label: l10n.compraCorregirCampoMotivo, controller: _motivoCtrl),
                if (_errorGeneral != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(_errorGeneral!, style: AppTypography.caption.copyWith(color: Theme.of(context).colorScheme.error)),
                ],
                const SizedBox(height: AppSpacing.xl),
                RisegButton(label: l10n.compraCorregirBotonGuardar, onPressed: _guardando ? null : _guardar),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
