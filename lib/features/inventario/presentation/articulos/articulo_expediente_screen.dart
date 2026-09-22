import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/compras/domain/repositories/compra_repository.dart' show OrigenCompra;
import 'package:riseg_one/features/inventario/domain/usecases/archivar_articulo_usecase.dart';
import 'package:riseg_one/features/inventario/domain/usecases/existencia_articulo.dart';
import 'package:riseg_one/features/organizacion/organizacion_providers.dart' show servicioRepositoryProvider;
import 'package:riseg_one/features/personal/personal_providers.dart' show empleadoRepositoryProvider;
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';

import '../asignaciones/widgets/historial_unidad_dialog.dart';
import '../movimiento_tipo_label.dart';
import '../../inventario_providers.dart'
    show asignacionRepositoryProvider, inventarioRepositoryProvider, obtenerOrigenCompraUseCaseProvider;
import 'articulos_controller.dart';
import 'articulos_list_screen.dart';
import 'widgets/corregir_identidad_unidad_dialog.dart';
import 'widgets/crear_variante_dialog.dart';
import 'widgets/eliminar_articulo_fisicamente_dialog.dart';
import 'widgets/gestionar_articulo_dialog.dart';
import 'widgets/registrar_ajuste_dialog.dart';
import 'widgets/registrar_baja_dialog.dart';
import 'widgets/registrar_entrada_dialog.dart';

final _formatoFecha = DateFormat('dd/MM/yyyy');

/// Expediente de un Artículo (Etapa 7A) — existencia derivada,
/// tallas/variantes o unidades serializadas (según
/// `articulo.manejaVariante`/`manejaSerie`), historial de movimientos,
/// y las acciones que los generan. Un solo controlador con el listado
/// (`ArticulosController`), igual que `NominaDetalleScreen`.
class ArticuloExpedienteScreen extends ConsumerStatefulWidget {
  const ArticuloExpedienteScreen({required this.articuloId, super.key});

  final String articuloId;

  @override
  ConsumerState<ArticuloExpedienteScreen> createState() => _ArticuloExpedienteScreenState();
}

class _ArticuloExpedienteScreenState extends ConsumerState<ArticuloExpedienteScreen> {
  bool _cargando = true;
  String? _errorCarga;
  ArticuloData? _articulo;
  String _categoriaNombre = '';
  ExistenciaArticulo? _existencia;
  List<ArticuloVarianteData> _variantes = const [];
  Map<String, ExistenciaArticulo> _existenciaPorVariante = const {};
  List<ArticuloUnidadData> _unidades = const [];
  List<MovimientoInventarioData> _movimientos = const [];
  Map<String, OrigenCompra> _origenesPorMovimiento = const {};

  /// Solo tiene sentido para artículos sin variante (mismo criterio ya
  /// establecido en `ReportesController` — un solo número no
  /// representaría bien costos que pueden diferir por talla). `null`
  /// cuando ninguna entrada real capturó costo todavía; nunca 0.
  int? _costoPromedio;
  List<AsignacionData> _asignacionesVigentes = const [];
  Map<String, String> _empleadosPorId = const {};
  Map<String, String> _serviciosPorId = const {};

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  ArticulosController get _notifier => ref.read(articulosControllerProvider.notifier);

  Future<void> _corregirIdentidad(ArticuloUnidadData unidad) async {
    final telefono = await ref.read(inventarioRepositoryProvider).obtenerTelefono(unidad.id);
    if (!mounted) return;
    final corregida = await mostrarDialogoCorregirIdentidadUnidad(context, ref, unidad: unidad, telefono: telefono);
    if (corregida) await _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _errorCarga = null;
    });
    try {
      final articulo = await _notifier.obtenerArticulo(widget.articuloId);
      if (articulo == null) {
        setState(() {
          _cargando = false;
          _errorCarga = 'no_existe';
        });
        return;
      }

      final categoriaNombre = await _notifier.obtenerCategoriaNombre(articulo.categoriaId);
      final existencia = articulo.manejaSerie
          ? await _notifier.calcularExistenciaUnidades(articulo.id)
          : await _notifier.calcularExistencia(articuloId: articulo.id);
      final variantes = articulo.manejaVariante ? await _notifier.listarVariantes(articulo.id) : const <ArticuloVarianteData>[];
      // Derivado de los mismos movimientos que ya usa `calcularExistencia`
      // general — una llamada por variante (fuente de verdad única,
      // nunca un contador duplicado), reutilizando el mismo cálculo ya
      // corregido para el resumen global. El total general siempre
      // coincide con la suma de las variantes: cada movimiento de un
      // artículo con variante trae `varianteId` no nulo, así que ambos
      // cálculos particionan exactamente el mismo conjunto de filas.
      final existenciaPorVariante = <String, ExistenciaArticulo>{
        for (final v in variantes) v.id: await _notifier.calcularExistencia(articuloId: articulo.id, varianteId: v.id),
      };
      final unidades = articulo.manejaSerie ? await _notifier.listarUnidades(articulo.id) : const <ArticuloUnidadData>[];
      final movimientos = await _notifier.listarMovimientos(articulo.id);
      final origenesPorMovimiento =
          await ref.read(obtenerOrigenCompraUseCaseProvider).obtenerParaMovimientos(movimientos.map((m) => m.id));

      // Costo promedio (Etapa 18) — mismo criterio ya usado por
      // Reportes: se suprime para artículos con variante, un solo
      // número no representaría bien costos que pueden diferir por
      // talla. Una sola llamada, sobre este artículo puntual — sin
      // riesgo de N+1 (no es un loop sobre el catálogo).
      final costoPromedio = articulo.manejaVariante
          ? null
          : await ref.read(inventarioRepositoryProvider).calcularCostoPromedio(articuloId: articulo.id);

      // Asignaciones vigentes (Etapa 18, sección nueva) — una sola
      // consulta acotada a este Artículo, más una resolución en bloque
      // de nombres de Empleado/Servicio (nunca un `obtenerPorId` por
      // fila).
      final asignacionesVigentes = await ref.read(asignacionRepositoryProvider).listarActivasPorArticulo(articulo.id);
      final empleadoIds = {for (final a in asignacionesVigentes) if (a.empleadoId != null) a.empleadoId!}.toList();
      final empleados = empleadoIds.isEmpty
          ? const <EmpleadoData>[]
          : await ref.read(empleadoRepositoryProvider).listarPorIds(empleadoIds);
      final empleadosPorId = <String, String>{
        for (final e in empleados) e.id: [e.nombres, e.apellidoPaterno, e.apellidoMaterno].whereType<String>().join(' '),
      };
      final necesitaServicios = asignacionesVigentes.any((a) => a.servicioId != null);
      final servicios = necesitaServicios ? await ref.read(servicioRepositoryProvider).listar() : const [];
      final serviciosPorId = <String, String>{for (final s in servicios) s.servicio.id: s.servicio.nombre};

      if (!mounted) return;
      setState(() {
        _cargando = false;
        _articulo = articulo;
        _categoriaNombre = categoriaNombre ?? '';
        _existencia = existencia;
        _variantes = variantes;
        _existenciaPorVariante = existenciaPorVariante;
        _unidades = unidades;
        _movimientos = movimientos;
        _origenesPorMovimiento = origenesPorMovimiento;
        _costoPromedio = costoPromedio;
        _asignacionesVigentes = asignacionesVigentes;
        _empleadosPorId = empleadosPorId;
        _serviciosPorId = serviciosPorId;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _errorCarga = e.toString();
      });
    }
  }

  Future<void> _editar() async {
    final exito = await mostrarDialogoGestionarArticulo(context, ref, articulo: _articulo);
    if (exito) await _cargar();
  }

  Future<void> _archivar() async {
    final l10n = AppLocalizations.of(context)!;
    final confirmado = await RisegDialog.showConfirmation(
      context: context,
      title: l10n.articuloConfirmarArchivarTitulo,
      message: l10n.articuloConfirmarArchivarMensaje,
      confirmLabel: l10n.articuloConfirmarAceptar,
      cancelLabel: l10n.articuloConfirmarCancelar,
      destructive: true,
    );
    if (confirmado != true) return;

    final resultado = await _notifier.archivarArticulo(widget.articuloId);
    if (!mounted) return;
    switch (resultado) {
      case ArchivarArticuloExitoso():
        RisegFeedback.showSuccess(context, l10n.articuloArchivadoExito);
        await _cargar();
      case ArchivarArticuloNoExiste():
      case ArchivarArticuloErrorInesperado():
        RisegFeedback.showError(context, l10n.articuloErrorInesperado);
    }
  }

  Future<void> _nuevaVariante() async {
    final exito = await mostrarDialogoCrearVariante(context, ref, articuloId: widget.articuloId);
    if (exito) await _cargar();
  }

  Future<void> _registrarEntrada() async {
    final articulo = _articulo!;
    final exito = await mostrarDialogoRegistrarEntrada(context, ref, articulo: articulo, variantes: _variantes);
    if (exito) await _cargar();
  }

  Future<void> _registrarBaja() async {
    final articulo = _articulo!;
    final unidadesDisponibles = _unidades.where((u) => u.estatus == 'disponible').toList();
    final exito = await mostrarDialogoRegistrarBaja(
      context,
      ref,
      articulo: articulo,
      variantes: _variantes,
      unidadesDisponibles: unidadesDisponibles,
    );
    if (exito) await _cargar();
  }

  Future<void> _registrarAjuste() async {
    final articulo = _articulo!;
    final exito = await mostrarDialogoRegistrarAjuste(
      context,
      ref,
      articuloId: articulo.id,
      manejaVariante: articulo.manejaVariante,
      variantes: _variantes,
    );
    if (exito) await _cargar();
  }

  Future<void> _eliminarFisicamente() async {
    final eliminado = await mostrarDialogoEliminarArticuloFisicamente(context, ref, widget.articuloId);
    if (!eliminado) return;
    // La eliminacion fisica no pasa por ningun controlador: sin esto el
    // renglon sobrevive en el Catalogo de articulos hasta que algo ajeno (cambiar de
    // pestana) reconstruya el provider. Navegar no es refrescar.
    ref.invalidate(articulosControllerProvider);
    if (mounted) context.pop();
  }

  // --- Asignaciones vigentes (Etapa 18) ---

  String _destinoAsignacion(AsignacionData a) {
    if (a.empleadoId != null) return _empleadosPorId[a.empleadoId] ?? a.empleadoId!;
    if (a.servicioId != null) return _serviciosPorId[a.servicioId] ?? a.servicioId!;
    return '—';
  }

  String _cantidadUnidadAsignacion(AsignacionData a) {
    if (a.unidadId != null) {
      final unidad = _unidades.where((u) => u.id == a.unidadId).firstOrNull;
      return unidad?.codigo ?? a.unidadId!;
    }
    return '${a.cantidad}';
  }

  void _irADestinoAsignacion(AsignacionData a) {
    if (a.empleadoId != null) {
      context.push('/personal/empleados/${a.empleadoId}');
    } else if (a.servicioId != null) {
      context.push('/comercial/servicios/${a.servicioId}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(title: Text(_articulo?.nombre ?? l10n.inventarioListadoTitulo)),
      body: _buildBody(context, l10n),
    );
  }

  Widget _buildBody(BuildContext context, AppLocalizations l10n) {
    if (_errorCarga != null && _articulo == null) {
      return RisegEmptyState(
        icon: Icons.error_outline,
        title: l10n.articuloExpedienteCargaErrorTitulo,
        message: l10n.articuloExpedienteCargaErrorMensaje,
        primaryAction: RisegButton(
          key: const Key('articulo_expediente_boton_reintentar'),
          label: l10n.inventarioListadoBotonReintentar,
          onPressed: _cargar,
        ),
      );
    }

    if (_cargando && _articulo == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final articulo = _articulo!;
    final existencia = _existencia!;
    final activo = articulo.cicloVidaRegistro == 'activo';
    final esMaestro = ref.watch(sesionControllerProvider)?.esMaestro ?? false;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RisegSectionHeader(
                title: articulo.nombre,
                description: '${articulo.folio} · $_categoriaNombre · ${articuloTipoLabelDe(l10n, articulo.manejaSerie)}',
                primaryAction: RisegButton(
                  key: const Key('articulo_expediente_boton_editar'),
                  label: l10n.articuloExpedienteBotonEditar,
                  onPressed: _editar,
                ),
                // Etapa 18: Archivar/Eliminar físicamente (secundarias y
                // destructivas, nunca la operación más frecuente) se
                // mueven a un menú ⋯ — antes convivían como botones
                // sueltos junto a "Editar", con "Eliminar físicamente"
                // permanentemente rojo en la cabecera.
                secondaryAction: activo || esMaestro
                    ? RisegActionsMenu(
                        menuKey: const Key('articulo_expediente_menu_acciones'),
                        actions: [
                          if (activo)
                            RisegMenuAction(
                              key: const Key('articulo_expediente_boton_archivar'),
                              label: l10n.articuloBotonArchivar,
                              icon: Icons.archive_outlined,
                              onTap: _archivar,
                            ),
                          if (esMaestro)
                            RisegMenuAction(
                              key: const Key('articulo_expediente_boton_eliminar_fisicamente'),
                              label: l10n.eliminacionFisicaAccionMenu,
                              icon: Icons.delete_forever_outlined,
                              destructive: true,
                              onTap: _eliminarFisicamente,
                            ),
                        ],
                      )
                    : null,
              ),
              const SizedBox(height: AppSpacing.sm),
              RisegStatusBadge(
                label: activo ? l10n.articuloEstatusActivo : l10n.articuloEstatusArchivado,
                tone: activo ? RisegStatusTone.success : RisegStatusTone.neutral,
              ),
              const SizedBox(height: AppSpacing.xl),
              RisegCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // `Wrap` en vez de `Row`+`Expanded`: con hasta 3 botones
                    // (Registrar entrada/Registrar baja/Registrar ajuste)
                    // un `Row` fijo no cabe por debajo de ~880px de ancho
                    // de contenido — `Expanded` solo puede encoger el
                    // título, nunca los botones (bug real encontrado
                    // probando "Corregir identificación"). `WrapAlignment.
                    // spaceBetween` conserva el look "título a la
                    // izquierda, acciones a la derecha" cuando ambos caben
                    // en la misma línea, y baja el grupo de acciones a una
                    // segunda línea completa (nunca lo trunca ni lo
                    // esconde) cuando no cabe.
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.xs,
                      children: [
                        Text(
                          l10n.articuloExpedienteSeccionExistencia,
                          style: AppTypography.heading3,
                        ),
                        Wrap(
                          spacing: AppSpacing.xs,
                          runSpacing: AppSpacing.xs,
                          children: [
                            RisegButton(
                              key: const Key('articulo_expediente_boton_entrada'),
                              label: l10n.articuloExpedienteBotonRegistrarEntrada,
                              size: RisegButtonSize.compact,
                              onPressed: _registrarEntrada,
                            ),
                            RisegButton(
                              key: const Key('articulo_expediente_boton_baja'),
                              label: l10n.articuloExpedienteBotonRegistrarBaja,
                              variant: RisegButtonVariant.secondary,
                              size: RisegButtonSize.compact,
                              onPressed: _registrarBaja,
                            ),
                            if (!articulo.manejaSerie)
                              RisegButton(
                                key: const Key('articulo_expediente_boton_ajuste'),
                                label: l10n.articuloExpedienteBotonRegistrarAjuste,
                                variant: RisegButtonVariant.ghost,
                                size: RisegButtonSize.compact,
                                onPressed: _registrarAjuste,
                              ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      children: [
                        _ExistenciaDato(label: l10n.articuloExpedienteCampoTotal, texto: '${existencia.total}'),
                        _ExistenciaDato(label: l10n.articuloExpedienteCampoDisponible, texto: '${existencia.disponible}'),
                        _ExistenciaDato(label: l10n.articuloExpedienteCampoAsignado, texto: '${existencia.asignado}'),
                        _ExistenciaDato(label: l10n.articuloExpedienteCampoDanado, texto: '${existencia.danado}'),
                        _ExistenciaDato(label: l10n.articuloExpedienteCampoPerdido, texto: '${existencia.perdido}'),
                        // Sin esta celda el desglose dejaría de sumar el
                        // Total en cuanto una unidad entre a lavandería o
                        // reparación, y el usuario vería un hueco sin
                        // explicación.
                        _ExistenciaDato(label: l10n.articuloExpedienteCampoEnProceso, texto: '${existencia.enProceso}'),
                        // Etapa 18: solo cuando existe un costo real
                        // capturado (nunca 0 inventado) y el artículo no
                        // maneja variante (mismo criterio que Reportes).
                        if (_costoPromedio != null)
                          _ExistenciaDato(
                            label: l10n.articuloExpedienteCampoCostoPromedio,
                            texto: formatoCosto(_costoPromedio!),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              if (articulo.manejaVariante) ...[
                const SizedBox(height: AppSpacing.xl),
                RisegCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      RisegSectionHeader(
                        title: l10n.articuloExpedienteSeccionVariantes,
                        primaryAction: RisegButton(
                          key: const Key('articulo_expediente_boton_nueva_variante'),
                          label: l10n.articuloExpedienteBotonNuevaVariante,
                          variant: RisegButtonVariant.secondary,
                          size: RisegButtonSize.compact,
                          onPressed: _nuevaVariante,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      if (_variantes.isEmpty)
                        Text(l10n.articuloExpedienteVariantesVacio, style: AppTypography.body)
                      else ...[
                        // Vistazo rápido — reemplaza los chips CH/EXG/G/M/XXG
                        // que antes solo informaban qué tallas existen, sin
                        // decir nada de su inventario.
                        Text(
                          _variantes
                              .map(
                                (v) => l10n.articuloExpedienteExistenciaVarianteResumen(
                                  v.valor,
                                  _existenciaPorVariante[v.id]?.disponible ?? 0,
                                ),
                              )
                              .join(' · '),
                          style: AppTypography.body,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        RisegTableBase<ArticuloVarianteData>(
                          rows: _variantes,
                          emptyState: const RisegEmptyState(title: '', message: ''),
                          columns: [
                            RisegColumn<ArticuloVarianteData>(
                              label: l10n.articuloExpedienteColumnaTalla,
                              cellBuilder: (v) => Text(v.valor),
                            ),
                            RisegColumn<ArticuloVarianteData>(
                              label: l10n.articuloExpedienteCampoTotal,
                              width: 90,
                              alignment: TextAlign.right,
                              cellBuilder: (v) => Text('${_existenciaPorVariante[v.id]?.total ?? 0}'),
                            ),
                            RisegColumn<ArticuloVarianteData>(
                              label: l10n.articuloExpedienteCampoDisponible,
                              width: 90,
                              alignment: TextAlign.right,
                              cellBuilder: (v) => Text('${_existenciaPorVariante[v.id]?.disponible ?? 0}'),
                            ),
                            RisegColumn<ArticuloVarianteData>(
                              label: l10n.articuloExpedienteCampoAsignado,
                              width: 90,
                              alignment: TextAlign.right,
                              cellBuilder: (v) => Text('${_existenciaPorVariante[v.id]?.asignado ?? 0}'),
                            ),
                            RisegColumn<ArticuloVarianteData>(
                              label: l10n.articuloExpedienteCampoDanado,
                              width: 90,
                              alignment: TextAlign.right,
                              cellBuilder: (v) => Text('${_existenciaPorVariante[v.id]?.danado ?? 0}'),
                            ),
                            RisegColumn<ArticuloVarianteData>(
                              label: l10n.articuloExpedienteCampoPerdido,
                              width: 90,
                              alignment: TextAlign.right,
                              cellBuilder: (v) => Text('${_existenciaPorVariante[v.id]?.perdido ?? 0}'),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              if (articulo.manejaSerie) ...[
                const SizedBox(height: AppSpacing.xl),
                RisegCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.articuloExpedienteSeccionUnidades, style: AppTypography.heading3),
                      const SizedBox(height: AppSpacing.sm),
                      RisegTableBase<ArticuloUnidadData>(
                        rows: _unidades,
                        emptyState: RisegEmptyState(
                          title: l10n.articuloExpedienteUnidadesVacio,
                          message: '',
                        ),
                        // Menú de acciones (⋮) en vez de botones de texto en
                        // fila: con 2 acciones ("Corregir identificación" +
                        // "Historial") un `Row` de botones ya desbordaba el
                        // ancho fijo de la columna de acciones en ventanas
                        // angostas — un menú compacto no vuelve a romperse
                        // el día que se agregue una tercera acción.
                        actionsWidth: 56,
                        rowActionsBuilder: (u) => PopupMenuButton<void>(
                          key: Key('unidad_acciones_${u.id}'),
                          tooltip: l10n.articuloExpedienteUnidadAccionesTooltip,
                          icon: const Icon(Icons.more_vert),
                          itemBuilder: (menuContext) => [
                            PopupMenuItem<void>(
                              key: Key('unidad_corregir_identidad_${u.id}'),
                              onTap: () => _corregirIdentidad(u),
                              child: Text(l10n.corregirIdentidadUnidadBotonAccion),
                            ),
                            PopupMenuItem<void>(
                              key: Key('unidad_historial_${u.id}'),
                              onTap: () => mostrarDialogoHistorialUnidad(context, ref, u),
                              child: Text(l10n.asignacionSeccionHistorial),
                            ),
                          ],
                        ),
                        columns: [
                          RisegColumn<ArticuloUnidadData>(
                            label: l10n.articuloExpedienteColumnaCodigo,
                            width: 120,
                            cellBuilder: (u) => Text(u.codigo),
                          ),
                          RisegColumn<ArticuloUnidadData>(
                            label: l10n.articuloExpedienteColumnaSerie,
                            cellBuilder: (u) => Text(u.numeroSerie),
                          ),
                          RisegColumn<ArticuloUnidadData>(
                            label: l10n.articuloExpedienteColumnaMarcaModelo,
                            cellBuilder: (u) => Text([u.marca, u.modelo].whereType<String>().join(' / ')),
                          ),
                          RisegColumn<ArticuloUnidadData>(
                            label: l10n.articuloExpedienteColumnaEstatus,
                            // 150, no 130: "Disponible" (el más largo de
                            // los 5 posibles) desbordaba por ~10px el
                            // padding interno de RisegStatusBadge a 130 —
                            // encontrado por la prueba de regresión del
                            // menú de acciones. El espacio de sobra viene
                            // de reducir `actionsWidth` (96 → 56) al pasar
                            // a menú compacto, así que ninguna columna de
                            // datos pierde espacio neto.
                            width: 150,
                            cellBuilder: (u) => RisegStatusBadge(
                              label: _estatusUnidadLabel(l10n, u.estatus),
                              tone: _estatusUnidadTono(u.estatus),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.xl),
              RisegCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.articuloExpedienteSeccionAsignaciones, style: AppTypography.heading3),
                    const SizedBox(height: AppSpacing.sm),
                    RisegTableBase<AsignacionData>(
                      rows: _asignacionesVigentes,
                      onRowTap: _irADestinoAsignacion,
                      emptyState: RisegEmptyState(title: l10n.articuloExpedienteAsignacionesVacio, message: ''),
                      hoverColor: context.colors.accentSoftBg,
                      rowActionsBuilder: (_) => Icon(Icons.chevron_right, size: AppSizes.iconMd, color: context.colors.textMuted),
                      actionsWidth: 40,
                      columns: [
                        RisegColumn<AsignacionData>(
                          label: l10n.articuloExpedienteColumnaDestino,
                          cellBuilder: (a) => Text(_destinoAsignacion(a)),
                        ),
                        RisegColumn<AsignacionData>(
                          label: l10n.articuloExpedienteColumnaEntrega,
                          width: 110,
                          cellBuilder: (a) => Text(_formatoFecha.format(a.fechaEntrega)),
                        ),
                        RisegColumn<AsignacionData>(
                          label: l10n.articuloExpedienteColumnaCantidadUnidad,
                          width: 150,
                          cellBuilder: (a) => Text(_cantidadUnidadAsignacion(a)),
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
                    Text(l10n.articuloExpedienteSeccionMovimientos, style: AppTypography.heading3),
                    const SizedBox(height: AppSpacing.sm),
                    RisegTableBase<MovimientoInventarioData>(
                      rows: _movimientos,
                      emptyState: RisegEmptyState(
                        title: l10n.articuloExpedienteMovimientosVacio,
                        message: '',
                      ),
                      columns: [
                        RisegColumn<MovimientoInventarioData>(
                          label: l10n.articuloExpedienteColumnaFecha,
                          width: 100,
                          cellBuilder: (m) => Text(_formatoFecha.format(m.fecha)),
                        ),
                        RisegColumn<MovimientoInventarioData>(
                          label: l10n.articuloExpedienteColumnaTipoMovimiento,
                          width: 140,
                          cellBuilder: (m) => Text(movimientoTipoLabel(l10n, m.tipoMovimiento)),
                        ),
                        RisegColumn<MovimientoInventarioData>(
                          label: l10n.articuloExpedienteColumnaVarianteUnidad,
                          cellBuilder: (m) => Text(_varianteUnidadLabel(m)),
                        ),
                        RisegColumn<MovimientoInventarioData>(
                          label: l10n.articuloExpedienteColumnaCantidad,
                          width: 90,
                          alignment: TextAlign.right,
                          cellBuilder: (m) => Text(m.cantidad.toString()),
                        ),
                        RisegColumn<MovimientoInventarioData>(
                          label: l10n.articuloExpedienteColumnaCosto,
                          width: 110,
                          alignment: TextAlign.right,
                          cellBuilder: (m) => Text(m.costoUnitario == null ? '—' : formatoCosto(m.costoUnitario!)),
                        ),
                        RisegColumn<MovimientoInventarioData>(
                          label: l10n.articuloExpedienteColumnaOrigen,
                          width: 150,
                          cellBuilder: (m) {
                            final origen = _origenesPorMovimiento[m.id];
                            if (origen == null) return const Text('—');
                            return RisegButton(
                              label: l10n.inventarioMovimientoOrigenCompra(origen.folioCompra),
                              variant: RisegButtonVariant.ghost,
                              size: RisegButtonSize.compact,
                              onPressed: () => context.go('/compras/${origen.compraId}'),
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _varianteUnidadLabel(MovimientoInventarioData m) {
    if (m.unidadId != null) {
      final unidad = _unidades.where((u) => u.id == m.unidadId).firstOrNull;
      return unidad?.codigo ?? '—';
    }
    if (m.varianteId != null) {
      final variante = _variantes.where((v) => v.id == m.varianteId).firstOrNull;
      return variante?.valor ?? '—';
    }
    return '—';
  }

  String _estatusUnidadLabel(AppLocalizations l10n, String estatus) {
    return switch (estatus) {
      'disponible' => l10n.estatusArticuloUnidadDisponible,
      'asignado' => l10n.estatusArticuloUnidadAsignado,
      'danado' => l10n.estatusArticuloUnidadDanado,
      'perdido' => l10n.estatusArticuloUnidadPerdido,
      'baja' => l10n.estatusArticuloUnidadBaja,
      _ => estatus,
    };
  }

  RisegStatusTone _estatusUnidadTono(String estatus) {
    return switch (estatus) {
      'disponible' => RisegStatusTone.success,
      'asignado' => RisegStatusTone.info,
      'danado' => RisegStatusTone.warning,
      'perdido' => RisegStatusTone.error,
      'baja' => RisegStatusTone.neutral,
      _ => RisegStatusTone.neutral,
    };
  }
}

class _ExistenciaDato extends StatelessWidget {
  const _ExistenciaDato({required this.label, required this.texto});

  final String label;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTypography.label),
          const SizedBox(height: AppSpacing.xxs),
          Text(texto, style: AppTypography.heading2),
        ],
      ),
    );
  }
}
