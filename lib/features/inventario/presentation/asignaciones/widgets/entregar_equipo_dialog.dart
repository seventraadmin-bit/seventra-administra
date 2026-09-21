import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/dashboard/presentation/dashboard_controller.dart';
import 'package:riseg_one/features/inventario/domain/repositories/articulo_repository.dart';
import 'package:riseg_one/features/inventario/domain/repositories/asignacion_repository.dart';
import 'package:riseg_one/features/inventario/domain/repositories/inventario_repository.dart';
import 'package:riseg_one/features/inventario/domain/usecases/entregar_equipo_usecase.dart';
import 'package:riseg_one/features/inventario/inventario_providers.dart';
import 'package:riseg_one/features/inventario/presentation/articulos/articulos_controller.dart';

/// Una línea del carrito de "Entregar equipo" — nunca persistida hasta
/// confirmar, solo estado local del diálogo. [cantidad] es mutable
/// para poder consolidar dos altas sucesivas del mismo artículo+
/// variante fungible en una sola línea (nunca para unidades
/// serializadas: cada una es siempre su propia línea con `cantidad`
/// fija en 1).
class _LineaCarrito {
  _LineaCarrito({
    required this.articuloId,
    required this.articuloNombre,
    this.varianteId,
    this.varianteLabel,
    this.unidadId,
    this.unidadLabel,
    required this.cantidad,
  });

  final String articuloId;
  final String articuloNombre;
  final String? varianteId;
  final String? varianteLabel;
  final String? unidadId;
  final String? unidadLabel;
  int cantidad;

  String get detalle {
    if (unidadId != null) return '$articuloNombre · $unidadLabel';
    if (varianteId != null) return '$cantidad × $articuloNombre ($varianteLabel)';
    return '$cantidad × $articuloNombre';
  }
}

String _motivoLineaTexto(AppLocalizations l10n, EntregarEquipoMotivoLinea motivo, int? disponible) {
  return switch (motivo) {
    // La UI del carrito ya impide construir estas dos líneas (artículo
    // siempre viene del catálogo, unidad siempre de la lista vigente
    // de disponibles) — si de todos modos ocurren es una condición de
    // carrera genuina (ver el doc comment del caso de uso), mismo
    // mensaje genérico que el resto del diálogo usa para lo inesperado.
    EntregarEquipoMotivoLinea.articuloNoExiste => l10n.entregarEquipoErrorInesperado,
    EntregarEquipoMotivoLinea.cantidadInvalida => l10n.asignarArticuloErrorCantidadInvalida,
    EntregarEquipoMotivoLinea.varianteInvalida => l10n.asignarArticuloErrorVarianteInvalida,
    EntregarEquipoMotivoLinea.unidadInvalida => l10n.asignarArticuloErrorUnidadInvalida,
    EntregarEquipoMotivoLinea.unidadNoDisponible => l10n.asignarArticuloErrorUnidadNoDisponible,
    EntregarEquipoMotivoLinea.sobrepasaDisponible =>
      disponible == null ? l10n.asignarArticuloErrorSobrepasaDisponible : l10n.entregarEquipoErrorLineaSobrepasaDisponible(disponible),
    EntregarEquipoMotivoLinea.unidadDuplicadaEnElCarrito => l10n.entregarEquipoErrorLineaUnidadDuplicada,
  };
}

/// Diálogo "Entregar equipo" (Etapa "Entrega múltiple de Inventario a
/// Personal") — entrega VARIOS artículos a un Empleado en un solo
/// acto atómico (`EntregarEquipoUseCase`), generando una `Entrega`
/// (cabecera documental) más una `Asignacion` independiente por cada
/// línea del carrito. El diálogo individual "Asignar artículo" sigue
/// existiendo sin cambios para altas sueltas — este es un flujo nuevo,
/// no un reemplazo.
Future<bool> mostrarDialogoEntregarEquipo(
  BuildContext context,
  WidgetRef ref, {
  required String empleadoId,
  required String empleadoNombre,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final articuloRepo = ref.read(articuloRepositoryProvider);
  final inventarioRepo = ref.read(inventarioRepositoryProvider);
  final entregarEquipo = ref.read(entregarEquipoAutorizadoProvider);

  final articulos = await articuloRepo.listar();
  if (!context.mounted) return false;

  var carritoActual = <_LineaCarrito>[];
  DateTime? fechaEntrega = DateTime.now();
  var condicionActual = '';
  var observacionesActual = '';
  String? errorGeneral;

  final resultado = await RisegDialog.showForm<bool>(
    context: context,
    title: l10n.entregarEquipoDialogoTitulo,
    confirmLabel: l10n.entregarEquipoBotonConfirmar,
    cancelLabel: l10n.asignarArticuloBotonCancelar,
    contentBuilder: (_) => _EntregarEquipoForm(
      empleadoNombre: empleadoNombre,
      articulos: articulos,
      articuloRepo: articuloRepo,
      inventarioRepo: inventarioRepo,
      fechaInicial: fechaEntrega,
      errorGeneral: errorGeneral,
      onCarritoChanged: (valor) => carritoActual = valor,
      onFechaChanged: (valor) => fechaEntrega = valor,
      onCondicionChanged: (valor) => condicionActual = valor,
      onObservacionesChanged: (valor) => observacionesActual = valor,
    ),
    onConfirm: () async {
      if (carritoActual.isEmpty) {
        errorGeneral = l10n.entregarEquipoErrorSinLineas;
        return null;
      }
      if (condicionActual.trim().isEmpty) {
        errorGeneral = l10n.entregarEquipoErrorCondicionRequerida;
        return null;
      }

      final resultado = await entregarEquipo(
        lineas: [
          for (final linea in carritoActual)
            AsignacionLineaInput(
              articuloId: linea.articuloId,
              varianteId: linea.varianteId,
              unidadId: linea.unidadId,
              cantidad: linea.cantidad,
            ),
        ],
        empleadoId: empleadoId,
        fechaEntrega: fechaEntrega ?? DateTime.now(),
        condicionEntrega: condicionActual.trim(),
        observaciones: observacionesActual.trim().isEmpty ? null : observacionesActual.trim(),
      );
      if (!context.mounted) return false;
      switch (resultado) {
        case EntregarEquipoExitoso():
          // Mismo hallazgo que `asignar_articulo_dialog.dart`: el
          // listado general de Inventario y el Dashboard cachean su
          // estado entre visitas.
          ref.invalidate(articulosControllerProvider);
          ref.invalidate(dashboardControllerProvider);
          RisegFeedback.showSuccess(context, l10n.asignarArticuloExito);
          return true;
        case EntregarEquipoLineaInvalida(:final indice, :final motivo, :final disponible):
          final concepto = indice < carritoActual.length ? carritoActual[indice].articuloNombre : '';
          errorGeneral = l10n.entregarEquipoErrorLinea(indice + 1, concepto, _motivoLineaTexto(l10n, motivo, disponible));
          return null;
        case EntregarEquipoSinLineas():
          errorGeneral = l10n.entregarEquipoErrorSinLineas;
          return null;
        case EntregarEquipoDestinoInvalido():
        case EntregarEquipoErrorInesperado():
          RisegFeedback.showError(context, l10n.entregarEquipoErrorInesperado);
          return false;
      }
    },
  );

  return resultado ?? false;
}

class _EntregarEquipoForm extends StatefulWidget {
  const _EntregarEquipoForm({
    required this.empleadoNombre,
    required this.articulos,
    required this.articuloRepo,
    required this.inventarioRepo,
    required this.fechaInicial,
    required this.onCarritoChanged,
    required this.onFechaChanged,
    required this.onCondicionChanged,
    required this.onObservacionesChanged,
    this.errorGeneral,
  });

  final String empleadoNombre;
  final List<ArticuloData> articulos;
  final ArticuloRepository articuloRepo;
  final InventarioRepository inventarioRepo;
  final DateTime? fechaInicial;
  final ValueChanged<List<_LineaCarrito>> onCarritoChanged;
  final ValueChanged<DateTime?> onFechaChanged;
  final ValueChanged<String> onCondicionChanged;
  final ValueChanged<String> onObservacionesChanged;
  final String? errorGeneral;

  @override
  State<_EntregarEquipoForm> createState() => _EntregarEquipoFormState();
}

class _EntregarEquipoFormState extends State<_EntregarEquipoForm> {
  final _cantidadCtrl = TextEditingController(text: '1');
  final _condicionCtrl = TextEditingController();
  final _observacionesCtrl = TextEditingController();

  late DateTime? _fechaEntrega = widget.fechaInicial;
  final _carrito = <_LineaCarrito>[];

  ArticuloData? _articuloSeleccionado;
  List<ArticuloVarianteData> _variantes = const [];
  List<ArticuloUnidadData> _unidadesDisponibles = const [];
  String? _varianteId;
  int? _disponible;
  String? _errorAgregar;

  @override
  void dispose() {
    _cantidadCtrl.dispose();
    _condicionCtrl.dispose();
    _observacionesCtrl.dispose();
    super.dispose();
  }

  int _comprometidoEnCarrito(String articuloId, String? varianteId) {
    var total = 0;
    for (final linea in _carrito) {
      if (linea.unidadId == null && linea.articuloId == articuloId && linea.varianteId == varianteId) {
        total += linea.cantidad;
      }
    }
    return total;
  }

  Future<void> _onArticuloCambiado(ArticuloData? nuevo) async {
    setState(() {
      _articuloSeleccionado = nuevo;
      _varianteId = null;
      _variantes = const [];
      _unidadesDisponibles = const [];
      _disponible = null;
      _errorAgregar = null;
    });
    if (nuevo == null) return;
    if (nuevo.manejaVariante) {
      final v = await widget.articuloRepo.listarVariantes(nuevo.id);
      if (mounted) setState(() => _variantes = v);
    } else if (nuevo.manejaSerie) {
      final u = await widget.inventarioRepo.listarUnidades(nuevo.id, estatus: 'disponible');
      if (mounted) setState(() => _unidadesDisponibles = u);
    } else {
      await _actualizarDisponible();
    }
  }

  Future<void> _onVarianteCambiada(String? varianteId) async {
    setState(() => _varianteId = varianteId);
    await _actualizarDisponible();
  }

  Future<void> _actualizarDisponible() async {
    final articulo = _articuloSeleccionado;
    if (articulo == null || articulo.manejaSerie) return;
    if (articulo.manejaVariante && _varianteId == null) {
      setState(() => _disponible = null);
      return;
    }
    final existencia = await widget.inventarioRepo.calcularExistencia(articuloId: articulo.id, varianteId: _varianteId);
    if (!mounted) return;
    final comprometido = _comprometidoEnCarrito(articulo.id, _varianteId);
    setState(() => _disponible = existencia.disponible - comprometido);
  }

  void _reportarCarrito() => widget.onCarritoChanged(List.unmodifiable(_carrito));

  void _agregarSerializada(ArticuloUnidadData unidad) {
    setState(() {
      _carrito.add(
        _LineaCarrito(
          articuloId: _articuloSeleccionado!.id,
          articuloNombre: _articuloSeleccionado!.nombre,
          unidadId: unidad.id,
          unidadLabel: '${unidad.codigo} · ${unidad.numeroSerie}',
          cantidad: 1,
        ),
      );
      _unidadesDisponibles = _unidadesDisponibles.where((u) => u.id != unidad.id).toList();
    });
    _reportarCarrito();
  }

  void _agregarFungible(AppLocalizations l10n) {
    final articulo = _articuloSeleccionado;
    if (articulo == null) return;
    if (articulo.manejaVariante && _varianteId == null) {
      setState(() => _errorAgregar = l10n.asignarArticuloErrorVarianteInvalida);
      return;
    }
    final cantidad = int.tryParse(_cantidadCtrl.text.trim());
    if (cantidad == null || cantidad <= 0) {
      setState(() => _errorAgregar = l10n.asignarArticuloErrorCantidadInvalida);
      return;
    }
    final disponible = _disponible;
    if (disponible != null && cantidad > disponible) {
      setState(() => _errorAgregar = l10n.asignarArticuloErrorSobrepasaDisponible);
      return;
    }

    final varianteLabel = _varianteId == null ? null : _variantes.where((v) => v.id == _varianteId).firstOrNull?.valor;
    setState(() {
      final existente = _carrito.where((l) => l.unidadId == null && l.articuloId == articulo.id && l.varianteId == _varianteId).firstOrNull;
      if (existente != null) {
        existente.cantidad += cantidad;
      } else {
        _carrito.add(
          _LineaCarrito(
            articuloId: articulo.id,
            articuloNombre: articulo.nombre,
            varianteId: _varianteId,
            varianteLabel: varianteLabel,
            cantidad: cantidad,
          ),
        );
      }
      _errorAgregar = null;
      _cantidadCtrl.text = '1';
    });
    _actualizarDisponible();
    _reportarCarrito();
  }

  void _quitarLinea(_LineaCarrito linea) {
    setState(() => _carrito.remove(linea));
    _actualizarDisponible();
    _reportarCarrito();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;
    final articulo = _articuloSeleccionado;
    final totalUnidades = _carrito.fold<int>(0, (acc, l) => acc + l.cantidad);

    return SizedBox(
      width: 640,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RisegDateField(
            label: l10n.asignarArticuloCampoFecha,
            value: _fechaEntrega,
            onChanged: (valor) {
              setState(() => _fechaEntrega = valor);
              widget.onFechaChanged(valor);
            },
          ),
          const SizedBox(height: AppSpacing.md),
          if (_carrito.isNotEmpty) ...[
            for (final linea in _carrito)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: Row(
                  children: [
                    Expanded(child: Text(linea.detalle, style: AppTypography.body)),
                    RisegButton(
                      label: l10n.entregarEquipoBotonQuitar,
                      variant: RisegButtonVariant.ghost,
                      size: RisegButtonSize.compact,
                      onPressed: () => _quitarLinea(linea),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: AppSpacing.sm),
            const Divider(),
            const SizedBox(height: AppSpacing.sm),
          ],
          RisegSelect<ArticuloData?>(
            label: l10n.asignarArticuloCampoArticulo,
            value: articulo,
            items: [for (final a in widget.articulos) RisegSelectItem(value: a, label: a.nombre)],
            onChanged: _onArticuloCambiado,
          ),
          if (articulo != null) ...[
            const SizedBox(height: AppSpacing.md),
            if (articulo.manejaSerie) ...[
              if (_unidadesDisponibles.isEmpty)
                Text(l10n.asignarArticuloSinUnidadesDisponibles, style: AppTypography.body)
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final u in _unidadesDisponibles)
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        dense: true,
                        value: false,
                        title: Text('${u.codigo} · ${u.numeroSerie}', style: AppTypography.body),
                        onChanged: (_) => _agregarSerializada(u),
                      ),
                  ],
                ),
            ] else ...[
              if (articulo.manejaVariante) ...[
                RisegSelect<String?>(
                  label: l10n.asignarArticuloCampoVariante,
                  value: _varianteId,
                  items: [for (final v in _variantes) RisegSelectItem(value: v.id, label: v.valor)],
                  onChanged: _onVarianteCambiada,
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: RisegTextField(label: l10n.asignarArticuloCampoCantidad, controller: _cantidadCtrl, keyboardType: TextInputType.number)),
                  const SizedBox(width: AppSpacing.sm),
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.sm),
                    child: RisegButton(
                      label: l10n.entregarEquipoBotonAgregar,
                      variant: RisegButtonVariant.secondary,
                      onPressed: () => _agregarFungible(l10n),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                _disponible == null
                    ? ''
                    : (_disponible! <= 0 ? l10n.entregarEquipoSinExistencia : l10n.entregarEquipoDisponible(_disponible!)),
                style: AppTypography.caption.copyWith(color: (_disponible ?? 1) <= 0 ? colors.error : colors.textMuted),
              ),
              if (_errorAgregar != null)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xxs),
                  child: Text(_errorAgregar!, style: AppTypography.caption.copyWith(color: colors.error)),
                ),
            ],
          ],
          const SizedBox(height: AppSpacing.md),
          RisegTextField(
            label: l10n.asignarArticuloCampoCondicion,
            controller: _condicionCtrl,
            onChanged: widget.onCondicionChanged,
          ),
          const SizedBox(height: AppSpacing.md),
          RisegTextField(
            label: l10n.asignarArticuloCampoObservaciones,
            controller: _observacionesCtrl,
            onChanged: widget.onObservacionesChanged,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            _carrito.isEmpty
                ? l10n.entregarEquipoCarritoVacio
                : l10n.entregarEquipoResumen(totalUnidades, _carrito.length, widget.empleadoNombre),
            style: AppTypography.label,
          ),
          if (widget.errorGeneral != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(widget.errorGeneral!, style: AppTypography.caption.copyWith(color: colors.error)),
          ],
        ],
      ),
    );
  }
}
