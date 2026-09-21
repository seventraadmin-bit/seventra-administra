import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/inventario/presentation/articulos/articulos_list_screen.dart' show formatoCosto;
import 'package:riseg_one/features/telefonia/data/tables/linea_telefonica_table.dart' show MotivoBajaLineaTelefonica;
import 'package:riseg_one/features/telefonia/domain/coherencia_linea_equipo.dart';
import 'widgets/coherencia_linea_equipo_mensajes.dart';
import 'widgets/resolver_inconsistencia_linea_equipo_dialog.dart';
import 'package:riseg_one/features/telefonia/domain/usecases/cambiar_estatus_linea_telefonica_usecase.dart';
import 'package:riseg_one/features/telefonia/domain/usecases/obtener_equipos_disponibles_linea_telefonica_usecase.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';

import 'equipos_telefonicos_controller.dart';
import 'linea_telefonica_labels.dart';
import 'telefonia_controller.dart';
import '../telefonia_providers.dart';
import 'widgets/asignar_linea_telefonica_dialog.dart';
import 'widgets/asociar_equipo_linea_telefonica_dialog.dart';
import 'widgets/cambiar_asignacion_linea_telefonica_dialog.dart';
import 'widgets/cambiar_equipo_linea_telefonica_dialog.dart';
import 'widgets/dar_de_baja_linea_telefonica_dialog.dart';
import 'widgets/eliminar_linea_telefonica_fisicamente_dialog.dart';
import 'widgets/gestionar_linea_telefonica_dialog.dart';
import 'package:riseg_one/features/telefonia/data/tables/recarga_linea_telefonica_table.dart';
import 'widgets/gestionar_recarga_linea_telefonica_dialogs.dart';
import 'widgets/registrar_recarga_linea_telefonica_dialog.dart';
import 'widgets/retirar_asignacion_linea_telefonica_dialog.dart';
import 'widgets/retirar_equipo_linea_telefonica_dialog.dart';
import 'package:riseg_one/features/finanzas/presentation/egresos/widgets/egreso_detalle_dialog.dart';
import 'package:riseg_one/features/finanzas/finanzas_providers.dart';
import 'package:riseg_one/features/usuarios/usuarios_providers.dart';
import 'package:riseg_one/features/dashboard/presentation/dashboard_controller.dart';
import 'package:riseg_one/features/finanzas/presentation/cuentas_financieras/cuentas_financieras_controller.dart';
import 'package:riseg_one/features/finanzas/presentation/deudas_credito/deudas_credito_controller.dart';
import 'package:riseg_one/features/finanzas/presentation/egresos/egresos_controller.dart';
import 'package:riseg_one/features/finanzas/presentation/planeacion/planeacion_financiera_controller.dart';
import 'package:riseg_one/features/finanzas/presentation/resumen/resumen_financiero_controller.dart';

final _formatoFecha = DateFormat('dd/MM/yyyy');

/// Expediente de una línea telefónica (Etapa 9B) — una sola pantalla
/// desplazable con secciones, sin pestañas internas (mismo criterio que
/// `VehiculoExpedienteScreen`). Documentos llega en la Etapa 9C.
class LineaTelefonicaExpedienteScreen extends ConsumerStatefulWidget {
  const LineaTelefonicaExpedienteScreen({required this.lineaTelefonicaId, super.key});

  final String lineaTelefonicaId;

  @override
  ConsumerState<LineaTelefonicaExpedienteScreen> createState() => _LineaTelefonicaExpedienteScreenState();
}

class _LineaTelefonicaExpedienteScreenState extends ConsumerState<LineaTelefonicaExpedienteScreen> {
  LineaTelefonicaData? _linea;
  RecargaLineaTelefonicaData? _ultimaRecarga;
  int _totalRecargas = 0;
  List<RecargaLineaTelefonicaData> _historialRecargas = const [];
  AsignacionLineaTelefonicaData? _asignacionVigente;
  List<AsignacionLineaTelefonicaData> _historialAsignaciones = const [];
  Map<String, String> _empleadosPorId = const {};
  Map<String, String> _serviciosPorId = const {};
  LineaTelefonicaEquipoData? _equipoVigente;
  List<LineaTelefonicaEquipoData> _historialEquipos = const [];
  Map<String, EquipoOpcionLineaTelefonica> _equipoInfoPorUnidadId = const {};
  /// `recargaId` → nombre de la cuenta o de la tarjeta de la que salió
  /// el dinero. Resuelto una sola vez al cargar; las legacy sin origen
  /// no aparecen aquí y se muestran como "no registrado" — jamás se les
  /// inventa una cuenta.
  Map<String, String> _origenFinancieroPorRecarga = const {};
  CoherenciaLineaEquipo _coherencia = const CoherenciaLineaEquipo(
    estado: EstadoCoherenciaLineaEquipo.sinEquipo,
  );
  bool _cargando = true;
  bool _procesando = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    final linea = await ref.read(telefoniaControllerProvider.notifier).obtenerLinea(widget.lineaTelefonicaId);

    final recargaRepo = ref.read(recargaLineaTelefonicaRepositoryProvider);
    final historialRecargas = await recargaRepo.listarPorLinea(widget.lineaTelefonicaId);
    final ultimaRecarga = historialRecargas.isEmpty ? null : historialRecargas.first;
    final totalRecargas = await recargaRepo.totalPorLinea(widget.lineaTelefonicaId);

    // Origen financiero legible de cada recarga: una consulta por
    // recarga con Egreso, más una sola para todas las tarjetas.
    final origenFinancieroPorRecarga = <String, String>{};
    final deudaRepo = ref.read(deudaRepositoryProvider);
    final tarjetas = {for (final d in await deudaRepo.listar()) d.id: d.nombre};
    for (final r in historialRecargas) {
      if (r.deudaId != null) {
        final nombre = tarjetas[r.deudaId];
        if (nombre != null) origenFinancieroPorRecarga[r.id] = nombre;
      } else if (r.egresoId != null) {
        final nombre = await recargaRepo.nombreCuentaDeEgreso(r.egresoId!);
        if (nombre != null) origenFinancieroPorRecarga[r.id] = nombre;
      }
    }

    final asignacionRepo = ref.read(asignacionLineaTelefonicaRepositoryProvider);
    final asignacionVigente = await asignacionRepo.obtenerActivaPorLinea(widget.lineaTelefonicaId);
    final historialAsignaciones = await asignacionRepo.listarPorLinea(widget.lineaTelefonicaId);
    final opciones = ref.read(obtenerOpcionesAsignacionLineaTelefonicaUseCaseProvider);
    final empleados = await opciones.obtenerEmpleados();
    final servicios = await opciones.obtenerServicios();

    final equipoRepo = ref.read(lineaTelefonicaEquipoRepositoryProvider);
    final equipoVigente = await equipoRepo.obtenerActualPorLinea(widget.lineaTelefonicaId);
    final historialEquipos = await equipoRepo.listarPorLinea(widget.lineaTelefonicaId);
    final equiposUseCase = ref.read(obtenerEquiposDisponiblesLineaTelefonicaUseCaseProvider);
    final equipoInfoPorUnidadId = <String, EquipoOpcionLineaTelefonica>{};
    for (final unidadId in historialEquipos.map((e) => e.unidadId).toSet()) {
      final info = await equiposUseCase.obtenerInfo(unidadId);
      if (info != null) equipoInfoPorUnidadId[unidadId] = info;
    }
    final custodiaInventario =
        equipoVigente == null ? null : await equipoRepo.obtenerCustodiaInventarioActual(equipoVigente.unidadId);

    if (!mounted) return;
    setState(() {
      _linea = linea;
      _ultimaRecarga = ultimaRecarga;
      _totalRecargas = totalRecargas;
      _historialRecargas = historialRecargas;
      _origenFinancieroPorRecarga = origenFinancieroPorRecarga;
      _asignacionVigente = asignacionVigente;
      _historialAsignaciones = historialAsignaciones;
      _empleadosPorId = {for (final e in empleados) e.id: e.nombre};
      _serviciosPorId = {for (final s in servicios) s.id: s.nombre};
      _equipoVigente = equipoVigente;
      _historialEquipos = historialEquipos;
      _equipoInfoPorUnidadId = equipoInfoPorUnidadId;
      // La custodia no se guarda en el estado: sólo entra en la regla.
      // La MISMA regla que usan los casos de uso para rechazar — la
      // pantalla no tiene una opinión propia sobre qué es coherente.
      _coherencia = evaluarCoherenciaLineaEquipo(
        unidadId: equipoVigente?.unidadId,
        destinoLinea: destinoDeAsignacionLinea(asignacionVigente),
        destinoEquipo: destinoDeCustodia(custodiaInventario),
      );
      _cargando = false;
    });
  }

  String _destinoAsignacion(AsignacionLineaTelefonicaData asignacion) {
    return destinoAsignacionLineaTelefonicaLabel(asignacion, empleadosPorId: _empleadosPorId, serviciosPorId: _serviciosPorId);
  }

  Future<void> _editar() async {
    final editado = await mostrarDialogoGestionarLineaTelefonica(context, ref, linea: _linea);
    if (editado) await _cargar();
  }

  Future<void> _cambiarEstatus(String estatus) async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _procesando = true);
    final resultado = await ref
        .read(telefoniaControllerProvider.notifier)
        .cambiarEstatus(lineaTelefonicaId: widget.lineaTelefonicaId, estatus: estatus);
    if (!mounted) return;
    setState(() => _procesando = false);
    switch (resultado) {
      case CambiarEstatusLineaTelefonicaExitoso():
        RisegFeedback.showSuccess(context, l10n.lineaTelefonicaExpedienteEstatusActualizado);
        await _cargar();
      case CambiarEstatusLineaTelefonicaNoExiste():
      case CambiarEstatusLineaTelefonicaDestinoInvalido():
      case CambiarEstatusLineaTelefonicaYaDeBaja():
      case CambiarEstatusLineaTelefonicaErrorInesperado():
        RisegFeedback.showError(context, l10n.lineaTelefonicaErrorInesperado);
    }
  }

  Future<void> _darDeBaja() async {
    final linea = _linea!;
    final dada = await mostrarDialogoDarDeBajaLineaTelefonica(context, ref, linea);
    if (dada) await _cargar();
  }

  Future<void> _eliminarFisicamente() async {
    final eliminado = await mostrarDialogoEliminarLineaTelefonicaFisicamente(context, ref, widget.lineaTelefonicaId);
    if (!eliminado) return;
    ref.invalidate(telefoniaControllerProvider);
    ref.invalidate(equiposTelefonicosControllerProvider);
    if (mounted) context.pop();
  }

  bool _anulada(RecargaLineaTelefonicaData r) =>
      r.estatus == EstatusRecargaLineaTelefonica.cancelada.name;

  /// Desde la Rebanada 1 una recarga MUEVE dinero: crea, corrige o
  /// cancela un Egreso, o carga/revierte una TDC. Las pantallas que
  /// derivan de eso quedaban desactualizadas hasta reiniciar.
  ///
  /// Misma lista que `EgresosController._invalidarConsumidoresFinancieros`
  /// — el mismo hecho tiene que refrescar lo mismo, venga de Finanzas o
  /// de Telefonía.
  void _invalidarPorRecarga() {
    ref.invalidate(telefoniaControllerProvider);
    ref.invalidate(egresosControllerProvider);
    ref.invalidate(dashboardControllerProvider);
    ref.invalidate(resumenFinancieroControllerProvider);
    ref.invalidate(planeacionFinancieraControllerProvider);
    ref.invalidate(cuentasFinancierasControllerProvider);
    ref.invalidate(deudasCreditoControllerProvider);
  }

  Future<void> _corregirRecarga(RecargaLineaTelefonicaData recarga) async {
    final corregida = await mostrarDialogoCorregirRecargaLineaTelefonica(context, ref, recarga);
    if (corregida && mounted) {
      await _cargar();
      _invalidarPorRecarga();
    }
  }

  Future<void> _anularRecarga(RecargaLineaTelefonicaData recarga) async {
    final anulada = await mostrarDialogoAnularRecargaLineaTelefonica(context, ref, recarga);
    if (anulada && mounted) {
      await _cargar();
      _invalidarPorRecarga();
    }
  }

  Future<void> _registrarRecarga() async {
    final registrada = await mostrarDialogoRegistrarRecargaLineaTelefonica(context, ref, widget.lineaTelefonicaId);
    if (registrada) {
      await _cargar();
      _invalidarPorRecarga();
    }
  }

  Future<void> _asignar() async {
    final asignado = await mostrarDialogoAsignarLineaTelefonica(
      context,
      ref,
      widget.lineaTelefonicaId,
    );
    if (asignado) {
      await _cargar();
      // Puede haber creado la asignación de línea alineándola con la
      // custodia del equipo — el listado la muestra.
      ref.invalidate(telefoniaControllerProvider);
      ref.invalidate(equiposTelefonicosControllerProvider);
    }
  }

  Future<void> _cambiarAsignacion() async {
    final cambiado = await mostrarDialogoCambiarAsignacionLineaTelefonica(
      context,
      ref,
      _asignacionVigente!,
    );
    if (cambiado) {
      await _cargar();
      ref.invalidate(telefoniaControllerProvider);
      ref.invalidate(equiposTelefonicosControllerProvider);
    }
  }

  Future<void> _retirarAsignacion() async {
    final retirado = await mostrarDialogoRetirarAsignacionLineaTelefonica(
      context,
      ref,
      _asignacionVigente!,
    );
    if (retirado) {
      await _cargar();
      ref.invalidate(telefoniaControllerProvider);
      ref.invalidate(equiposTelefonicosControllerProvider);
    }
  }

  Future<void> _asociarEquipo() async {
    final asociado = await mostrarDialogoAsociarEquipoLineaTelefonica(context, ref, widget.lineaTelefonicaId);
    if (asociado) {
      await _cargar();
      // Escribe directo en `LineaTelefonicaEquipo` — cambia "Línea
      // actual" en Equipos y "Equipo asociado" en Líneas al mismo
      // tiempo.
      ref.invalidate(telefoniaControllerProvider);
      ref.invalidate(equiposTelefonicosControllerProvider);
    }
  }

  Future<void> _cambiarEquipo() async {
    final cambiado = await mostrarDialogoCambiarEquipoLineaTelefonica(context, ref, widget.lineaTelefonicaId);
    if (cambiado) {
      await _cargar();
      ref.invalidate(telefoniaControllerProvider);
      ref.invalidate(equiposTelefonicosControllerProvider);
    }
  }

  Future<void> _retirarEquipo() async {
    final retirado = await mostrarDialogoRetirarEquipoLineaTelefonica(context, ref, widget.lineaTelefonicaId);
    if (retirado) {
      await _cargar();
      ref.invalidate(telefoniaControllerProvider);
      ref.invalidate(equiposTelefonicosControllerProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;
    // Navegar a Finanzas exige poder ver Finanzas: el permiso no se
    // hereda por estar parado en Telefonía.
    final puedeVerFinanzas = ref.watch(permissionServiceProvider).hasCode('finanzas.ver');

    if (_cargando) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final linea = _linea;
    if (linea == null) {
      return Scaffold(appBar: AppBar(), body: RisegEmptyState(title: l10n.telefoniaListadoCargaErrorTitulo, message: ''));
    }

    final esBaja = linea.estatus == 'baja';
    final esMaestro = ref.watch(sesionControllerProvider)?.esMaestro ?? false;

    return Scaffold(
      appBar: AppBar(title: Text(linea.numero ?? linea.codigo)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(linea.numero ?? '—', style: AppTypography.heading2.copyWith(color: colors.textPrimary)),
                          Text(linea.codigo, style: AppTypography.body.copyWith(color: colors.textMuted)),
                        ],
                      ),
                    ),
                    RisegStatusBadge(
                      label: estatusLineaTelefonicaLabel(l10n, linea.estatus),
                      tone: estatusLineaTelefonicaTono(linea.estatus),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                // §13 — sólo Editar queda como acción visible. Suspender,
                // Dar de baja y Eliminar físicamente son excepcionales o
                // irreversibles: viven en el menú de ⋯, como en el resto
                // de RISEG ONE. Permisos y confirmaciones no cambian.
                Row(
                  children: [
                    RisegButton(
                      label: l10n.lineaTelefonicaExpedienteBotonEditar,
                      variant: RisegButtonVariant.secondary,
                      onPressed: esBaja || _procesando ? null : _editar,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    RisegActionsMenu(
                      menuKey: const Key('linea_acciones_cabecera'),
                      actions: [
                        if (!esBaja && linea.estatus != 'suspendida')
                          RisegMenuAction(
                            key: const Key('linea_accion_suspender'),
                            label: l10n.lineaTelefonicaExpedienteBotonSuspender,
                            icon: Icons.pause_circle_outline,
                            onTap: _procesando ? null : () => _cambiarEstatus('suspendida'),
                          ),
                        if (!esBaja && linea.estatus != 'activa')
                          RisegMenuAction(
                            key: const Key('linea_accion_activar'),
                            label: l10n.lineaTelefonicaExpedienteBotonActivar,
                            icon: Icons.play_circle_outline,
                            onTap: _procesando ? null : () => _cambiarEstatus('activa'),
                          ),
                        if (!esBaja)
                          RisegMenuAction(
                            key: const Key('linea_accion_dar_de_baja'),
                            label: l10n.lineaTelefonicaExpedienteBotonDarDeBaja,
                            icon: Icons.block,
                            destructive: true,
                            onTap: _procesando ? null : _darDeBaja,
                          ),
                        if (esMaestro)
                          RisegMenuAction(
                            key: const Key('linea_accion_eliminar_fisicamente'),
                            label: l10n.eliminacionFisicaAccionMenu,
                            icon: Icons.delete_forever_outlined,
                            destructive: true,
                            onTap: _eliminarFisicamente,
                          ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xl),
                // §6 — lo que hay que poder responder de un vistazo:
                // quién la usa, qué aparato trae y cuándo se recargó por
                // última vez. El estatus ya está en la cabecera. Lo
                // demás sigue abajo, en su sección.
                RisegCard(
                  child: RisegFieldGrid(
                    children: [
                      _campo(
                        l10n.lineaTelefonicaAsignacionLineaAsignadaA,
                        _asignacionVigente == null ? '—' : _destinoAsignacion(_asignacionVigente!),
                      ),
                      _campo(
                        l10n.telefoniaColumnaEquipoAsociado,
                        _equipoVigente == null ? '—' : _equipoLabel(_equipoVigente!.unidadId),
                      ),
                      _campo(
                        l10n.lineaTelefonicaRecargaCampoUltima,
                        _ultimaRecarga == null
                            ? '—'
                            : '${_formatoFecha.format(_ultimaRecarga!.fecha)} — ${formatoCosto(_ultimaRecarga!.importe)}',
                      ),
                      _campo(l10n.lineaTelefonicaRecargaCampoTotal, formatoCosto(_totalRecargas)),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                RisegCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.lineaTelefonicaExpedienteSeccionDatos, style: AppTypography.heading3),
                      const SizedBox(height: AppSpacing.sm),
                      _campo(l10n.lineaTelefonicaCampoOperador, operadorLineaTelefonicaLabel(l10n, linea)),
                      _campo(l10n.lineaTelefonicaCampoModalidadSim, modalidadSimLabel(l10n, linea.modalidadSim)),
                      _campo(l10n.lineaTelefonicaCampoIccid, linea.iccid ?? '—'),
                      _campo(
                        l10n.lineaTelefonicaCampoFechaActivacion,
                        linea.fechaActivacion == null ? '—' : _formatoFecha.format(linea.fechaActivacion!),
                      ),
                      _campo(l10n.lineaTelefonicaCampoObservaciones, linea.observaciones ?? '—'),
                      if (esBaja) ...[
                        const Divider(height: AppSpacing.xl),
                        _campo(l10n.lineaTelefonicaBajaCampoFecha, _formatoFecha.format(linea.fechaBaja!)),
                        _campo(
                          l10n.lineaTelefonicaBajaCampoMotivo,
                          linea.motivoBaja == null
                              ? '—'
                              : motivoBajaLineaTelefonicaLabel(l10n, MotivoBajaLineaTelefonica.values.byName(linea.motivoBaja!)),
                        ),
                        _campo(l10n.lineaTelefonicaBajaCampoObservaciones, linea.observacionesBaja ?? '—'),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                RisegCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      RisegSectionHeader(
                        title: l10n.lineaTelefonicaRecargaSeccionTitulo,
                        primaryAction: esBaja
                            ? null
                            : RisegButton(
                                label: l10n.lineaTelefonicaBotonRegistrarRecarga,
                                variant: RisegButtonVariant.secondary,
                                size: RisegButtonSize.compact,
                                onPressed: _registrarRecarga,
                              ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      if (_ultimaRecarga == null)
                        Text(l10n.lineaTelefonicaRecargaVacio, style: AppTypography.body.copyWith(color: colors.textMuted))
                      else ...[
                        _campo(
                          l10n.lineaTelefonicaRecargaCampoUltima,
                          '${_formatoFecha.format(_ultimaRecarga!.fecha)} — ${formatoCosto(_ultimaRecarga!.importe)}',
                        ),
                        _campo(l10n.lineaTelefonicaRecargaCampoTotal, formatoCosto(_totalRecargas)),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                RisegCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.lineaTelefonicaRecargaHistorialTitulo, style: AppTypography.heading3),
                      const SizedBox(height: AppSpacing.sm),
                      // §12 — vacío: una línea. Con registros: tabla densa.
                      if ((_historialRecargas).isEmpty)
                        Text(l10n.lineaTelefonicaRecargaHistorialVacio, style: AppTypography.body.copyWith(color: colors.textMuted))
                      else
                      RisegTableBase<RecargaLineaTelefonicaData>(
                        rows: _historialRecargas,
                        emptyState: RisegEmptyState(title: l10n.lineaTelefonicaRecargaHistorialVacio, message: ''),
                        columns: [
                          RisegColumn<RecargaLineaTelefonicaData>(
                            label: l10n.lineaTelefonicaRecargaColumnaFecha,
                            width: 110,
                            cellBuilder: (r) => Text(_formatoFecha.format(r.fecha)),
                          ),
                          RisegColumn<RecargaLineaTelefonicaData>(
                            label: l10n.lineaTelefonicaRecargaColumnaEstatus,
                            width: 110,
                            cellBuilder: (r) => RisegStatusBadge(
                              label: _anulada(r) ? l10n.recargaEstatusCancelada : l10n.recargaEstatusVigente,
                              tone: _anulada(r) ? RisegStatusTone.neutral : RisegStatusTone.success,
                            ),
                          ),
                          RisegColumn<RecargaLineaTelefonicaData>(
                            label: l10n.lineaTelefonicaRecargaColumnaImporte,
                            width: 110,
                            alignment: TextAlign.right,
                            // Una recarga anulada se tacha: sigue en el
                            // historial como evidencia, pero ya no suma.
                            cellBuilder: (r) => Text(
                              formatoCosto(r.importe),
                              style: _anulada(r)
                                  ? AppTypography.body.copyWith(
                                      decoration: TextDecoration.lineThrough,
                                      color: colors.textMuted,
                                    )
                                  : null,
                            ),
                          ),
                          RisegColumn<RecargaLineaTelefonicaData>(
                            label: l10n.lineaTelefonicaRecargaColumnaOrigenFinanciero,
                            width: 180,
                            cellBuilder: (r) => Text(
                              _origenFinancieroPorRecarga[r.id] ?? l10n.lineaTelefonicaRecargaOrigenNoRegistrado,
                              overflow: TextOverflow.ellipsis,
                              style: _origenFinancieroPorRecarga.containsKey(r.id)
                                  ? null
                                  : AppTypography.body.copyWith(color: colors.textMuted),
                            ),
                          ),
                          RisegColumn<RecargaLineaTelefonicaData>(
                            label: l10n.lineaTelefonicaRecargaColumnaObservaciones,
                            // El motivo de la anulación vive aquí desde la
                            // Rebanada 3: la columna de acciones dejó de ser
                            // el sitio donde se leía por qué se anuló.
                            cellBuilder: (r) => Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(r.observaciones ?? '—', overflow: TextOverflow.ellipsis),
                                if (_anulada(r))
                                  Text(
                                    l10n.recargaAnuladaMotivo(r.motivoCancelacion ?? ''),
                                    style: AppTypography.caption.copyWith(color: colors.textMuted),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                              ],
                            ),
                          ),
                          // Corregir y Anular (schemaVersion 81) — el gap
                          // operativo del módulo. Menú y no dos botones
                          // sueltos: no caben en una celda a 500 px.
                          RisegColumn<RecargaLineaTelefonicaData>(
                            label: l10n.recargaColumnaAcciones,
                            width: 150,
                            cellBuilder: (r) => RisegActionsMenu(
                              menuKey: Key('recarga_acciones_${r.id}'),
                              actions: [
                                // Una recarga anulada conserva su
                                // trazabilidad financiera: se puede
                                // seguir viendo a dónde fue el dinero
                                // (y su reverso), aunque ya no se
                                // corrija ni se vuelva a anular.
                                if (!_anulada(r)) ...[
                                  RisegMenuAction(
                                    key: Key('recarga_corregir_${r.id}'),
                                    label: l10n.recargaBotonCorregir,
                                    icon: Icons.edit_outlined,
                                    onTap: () => _corregirRecarga(r),
                                  ),
                                  RisegMenuAction(
                                    key: Key('recarga_anular_${r.id}'),
                                    label: l10n.recargaBotonAnular,
                                    icon: Icons.block,
                                    destructive: true,
                                    onTap: () => _anularRecarga(r),
                                  ),
                                ],
                                if (puedeVerFinanzas && r.egresoId != null)
                                  RisegMenuAction(
                                    key: Key('recarga_ver_egreso_${r.id}'),
                                    label: l10n.recargaBotonVerEgreso,
                                    icon: Icons.receipt_long_outlined,
                                    onTap: () => _verEgresoDeRecarga(r.egresoId!),
                                  ),
                                if (puedeVerFinanzas && r.deudaId != null)
                                  RisegMenuAction(
                                    key: Key('recarga_ver_tarjeta_${r.id}'),
                                    label: l10n.recargaBotonVerTarjeta,
                                    icon: Icons.credit_card_outlined,
                                    onTap: () => context.push('/finanzas/deudas-y-credito/${r.deudaId}'),
                                  ),
                              ],
                            ),
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
                      RisegSectionHeader(
                        title: l10n.lineaTelefonicaAsignacionSeccionTitulo,
                        primaryAction: esBaja
                            ? null
                            : (_asignacionVigente == null
                                ? RisegButton(
                                    label: l10n.lineaTelefonicaBotonAsignar,
                                    variant: RisegButtonVariant.secondary,
                                    size: RisegButtonSize.compact,
                                    onPressed: _asignar,
                                  )
                                : null),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      if (_asignacionVigente == null)
                        Text(l10n.lineaTelefonicaAsignacionVacio, style: AppTypography.body.copyWith(color: colors.textMuted))
                      else ...[
                        _campo(l10n.lineaTelefonicaAsignacionLineaAsignadaA, _destinoAsignacion(_asignacionVigente!)),
                        _campo(l10n.lineaTelefonicaAsignacionDesde, _formatoFecha.format(_asignacionVigente!.fechaInicio)),
                        const SizedBox(height: AppSpacing.sm),
                        Wrap(
                          spacing: AppSpacing.xs,
                          runSpacing: AppSpacing.xs,
                          children: [
                            RisegButton(
                              label: l10n.lineaTelefonicaBotonCambiarAsignacion,
                              variant: RisegButtonVariant.ghost,
                              size: RisegButtonSize.compact,
                              onPressed: _cambiarAsignacion,
                            ),
                            RisegButton(
                              label: l10n.lineaTelefonicaBotonRetirarAsignacion,
                              variant: RisegButtonVariant.ghost,
                              size: RisegButtonSize.compact,
                              onPressed: _retirarAsignacion,
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                RisegCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      RisegSectionHeader(
                        title: l10n.lineaTelefonicaEquipoSeccionTitulo,
                        primaryAction: esBaja
                            ? null
                            : (_equipoVigente == null
                                ? RisegButton(
                                    label: l10n.lineaTelefonicaBotonAsociarEquipo,
                                    variant: RisegButtonVariant.secondary,
                                    size: RisegButtonSize.compact,
                                    onPressed: _asociarEquipo,
                                  )
                                : null),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      if (_equipoVigente == null)
                        Text(l10n.lineaTelefonicaEquipoVacio, style: AppTypography.body.copyWith(color: colors.textMuted))
                      else ...[
                        _campo(l10n.lineaTelefonicaColumnaEquipo, _equipoLabel(_equipoVigente!.unidadId)),
                        _campo(l10n.lineaTelefonicaEquipoDesde, _formatoFecha.format(_equipoVigente!.fechaInicio)),
                        if (_divergenciaEquipo() case final advertencia?) ...[
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            advertencia,
                            // Un pendiente de recuperación es información
                            // esperada, no un error: no puede pintarse
                            // del mismo color que una contradicción real.
                            style: AppTypography.caption.copyWith(
                              color: _coherencia.esPendienteRecuperacion ? colors.textMuted : colors.error,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          if (_coherencia.esPendienteRecuperacion)
                            RisegButton(
                              key: const Key('linea_boton_ver_recuperacion'),
                              label: l10n.lineaTelefonicaCoherenciaVerRecuperacion,
                              variant: RisegButtonVariant.ghost,
                              size: RisegButtonSize.compact,
                              onPressed: () => context.go('/telefonia/equipos/${_equipoVigente!.unidadId}'),
                            )
                          else
                            RisegButton(
                              key: const Key('linea_boton_resolver_inconsistencia'),
                              label: l10n.lineaTelefonicaResolverInconsistenciaBoton,
                              variant: RisegButtonVariant.secondary,
                              size: RisegButtonSize.compact,
                              onPressed: _resolverInconsistencia,
                            ),
                        ],
                        const SizedBox(height: AppSpacing.sm),
                        Wrap(
                          spacing: AppSpacing.xs,
                          runSpacing: AppSpacing.xs,
                          children: [
                            RisegButton(
                              label: l10n.lineaTelefonicaEquipoBotonVerEquipo,
                              variant: RisegButtonVariant.ghost,
                              size: RisegButtonSize.compact,
                              onPressed: () => context.go('/telefonia/equipos/${_equipoVigente!.unidadId}'),
                            ),
                            RisegButton(
                              label: l10n.lineaTelefonicaBotonCambiarEquipo,
                              variant: RisegButtonVariant.ghost,
                              size: RisegButtonSize.compact,
                              onPressed: _cambiarEquipo,
                            ),
                            RisegButton(
                              label: l10n.lineaTelefonicaBotonRetirarEquipo,
                              variant: RisegButtonVariant.ghost,
                              size: RisegButtonSize.compact,
                              onPressed: _retirarEquipo,
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                RisegCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.lineaTelefonicaHistorialAsignacionesTitulo, style: AppTypography.heading3),
                      const SizedBox(height: AppSpacing.sm),
                      // §12 — vacío: una línea. Con registros: tabla densa.
                      if ((_historialAsignaciones).isEmpty)
                        Text(l10n.lineaTelefonicaHistorialAsignacionesVacio, style: AppTypography.body.copyWith(color: colors.textMuted))
                      else
                      RisegTableBase<AsignacionLineaTelefonicaData>(
                        rows: _historialAsignaciones,
                        emptyState: RisegEmptyState(title: l10n.lineaTelefonicaHistorialAsignacionesVacio, message: ''),
                        columns: [
                          RisegColumn<AsignacionLineaTelefonicaData>(
                            label: l10n.lineaTelefonicaColumnaDestino,
                            cellBuilder: (a) => Text(_destinoAsignacion(a)),
                          ),
                          RisegColumn<AsignacionLineaTelefonicaData>(
                            label: l10n.lineaTelefonicaColumnaFechaInicio,
                            width: 110,
                            cellBuilder: (a) => Text(_formatoFecha.format(a.fechaInicio)),
                          ),
                          RisegColumn<AsignacionLineaTelefonicaData>(
                            label: l10n.lineaTelefonicaColumnaFechaTermino,
                            width: 110,
                            cellBuilder: (a) => Text(a.fechaTermino == null ? '—' : _formatoFecha.format(a.fechaTermino!)),
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
                      Text(l10n.lineaTelefonicaHistorialEquiposTitulo, style: AppTypography.heading3),
                      const SizedBox(height: AppSpacing.sm),
                      // §12 — vacío: una línea. Con registros: tabla densa.
                      if ((_historialEquipos).isEmpty)
                        Text(l10n.lineaTelefonicaHistorialEquiposVacio, style: AppTypography.body.copyWith(color: colors.textMuted))
                      else
                      RisegTableBase<LineaTelefonicaEquipoData>(
                        rows: _historialEquipos,
                        emptyState: RisegEmptyState(title: l10n.lineaTelefonicaHistorialEquiposVacio, message: ''),
                        columns: [
                          RisegColumn<LineaTelefonicaEquipoData>(
                            label: l10n.lineaTelefonicaColumnaEquipo,
                            cellBuilder: (e) => Text(_equipoLabel(e.unidadId)),
                          ),
                          RisegColumn<LineaTelefonicaEquipoData>(
                            label: l10n.lineaTelefonicaColumnaFechaInicio,
                            width: 110,
                            cellBuilder: (e) => Text(_formatoFecha.format(e.fechaInicio)),
                          ),
                          RisegColumn<LineaTelefonicaEquipoData>(
                            label: l10n.lineaTelefonicaColumnaFechaTermino,
                            width: 110,
                            cellBuilder: (e) => Text(e.fechaFin == null ? '—' : _formatoFecha.format(e.fechaFin!)),
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
      ),
    );
  }

  String _equipoLabel(String unidadId) {
    final info = _equipoInfoPorUnidadId[unidadId];
    if (info == null) return unidadId;
    return '${info.codigo} · ${info.descripcion}';
  }

  /// Advertencia de divergencia (Etapa 9B, punto 5) — `null` si no hay
  /// nada que advertir (sin equipo, o la custodia real en Inventario
  /// coincide con la asignación vigente de la línea). Nunca corrige
  /// nada automáticamente, solo informa.
  NombresDestinoTelefonia get _nombres => NombresDestinoTelefonia(_empleadosPorId, _serviciosPorId);

  String? _divergenciaEquipo() {
    return mensajeIncoherenciaLineaEquipo(AppLocalizations.of(context)!, _coherencia, _nombres);
  }

  /// §21 — la advertencia deja de ser sólo un aviso: ofrece la salida
  /// que corresponde al estado real. Nunca modifica Inventario.
  /// El detalle de Egreso de Finanzas, reutilizado tal cual — ni se
  /// duplica la pantalla ni se navega a un listado donde haya que
  /// buscarlo a mano. El vínculo es `RecargaLineaTelefonica.egresoId`.
  Future<void> _verEgresoDeRecarga(String egresoId) async {
    await showDialog<void>(context: context, builder: (_) => EgresoDetalleDialog(egresoId: egresoId));
    if (mounted) await _cargar();
  }

  Future<void> _resolverInconsistencia() async {
    final resultado = await mostrarDialogoResolverInconsistenciaLineaEquipo(
      context,
      ref,
      lineaTelefonicaId: widget.lineaTelefonicaId,
      asignacionVigente: _asignacionVigente,
      coherencia: _coherencia,
      nombres: _nombres,
    );
    if (!mounted) return;
    switch (resultado) {
      case ResultadoResolucionInconsistencia.resuelto:
        await _cargar();
        ref.invalidate(telefoniaControllerProvider);
        ref.invalidate(equiposTelefonicosControllerProvider);
      case ResultadoResolucionInconsistencia.irAlEquipo:
        if (_equipoVigente != null) context.go('/telefonia/equipos/${_equipoVigente!.unidadId}');
      case ResultadoResolucionInconsistencia.cancelado:
        break;
    }
  }

  Widget _campo(String etiqueta, String valor) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 180, child: Text(etiqueta, style: AppTypography.label.copyWith(color: colors.textMuted))),
          Expanded(child: Text(valor, style: AppTypography.body)),
        ],
      ),
    );
  }
}
