import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/compras/domain/repositories/compra_repository.dart' show OrigenCompra;
import 'package:riseg_one/features/dashboard/presentation/dashboard_controller.dart';
import 'package:riseg_one/features/inventario/data/tables/asignacion_table.dart' show MotivoCierreAsignacion;
import 'package:riseg_one/features/inventario/inventario_providers.dart';
import 'package:riseg_one/features/inventario/presentation/articulos/articulos_controller.dart';
import 'package:riseg_one/features/inventario/presentation/articulos/articulos_list_screen.dart' show formatoCosto;
import 'package:riseg_one/features/inventario/presentation/asignaciones/widgets/cerrar_asignacion_dialog.dart';
import 'package:riseg_one/features/inventario/presentation/asignaciones/widgets/historial_unidad_dialog.dart'
    show estatusAsignacionLabel, estatusAsignacionTono;
import 'package:riseg_one/features/inventario/presentation/asignaciones/widgets/cambiar_responsable_asignacion_dialog.dart';
import 'package:riseg_one/features/telefonia/domain/usecases/obtener_historia_equipo_telefonico_usecase.dart';
import 'package:riseg_one/features/telefonia/domain/usecases/revelar_credencial_equipo_telefonico_usecase.dart';
import 'package:riseg_one/features/organizacion/organizacion_providers.dart' show attachmentRepositoryProvider, attachmentStorageProvider;
import 'package:riseg_one/features/usuarios/usuarios_providers.dart';

import 'equipo_telefonico_labels.dart';
import 'linea_telefonica_labels.dart';
import 'package:riseg_one/features/inventario/presentation/articulos/widgets/corregir_identidad_unidad_dialog.dart';

import 'widgets/actualizar_correo_equipo_telefonico_dialog.dart';
import 'widgets/asignar_equipo_telefonico_dialog.dart';
import 'widgets/cambiar_contrasena_equipo_telefonico_dialog.dart';
import 'widgets/configurar_equipo_telefonico_dialog.dart';
import 'equipos_telefonicos_controller.dart';
import '../telefonia_providers.dart';
import 'package:riseg_one/features/telefonia/domain/coherencia_linea_equipo.dart';
import 'widgets/coherencia_linea_equipo_mensajes.dart';

final _formatoFecha = DateFormat('dd/MM/yyyy');
final _formatoFechaHora = DateFormat('dd/MM/yyyy HH:mm');

/// Expediente de un equipo telefónico (Etapa 9D) — nunca una tabla de
/// identidad propia: ensambla `ArticuloUnidad`/`ArticuloUnidadTelefono`
/// (Inventario), `LineaTelefonicaEquipo`/`Asignacion` (Telefonía/
/// Inventario) y la credencial/bitácora nuevas de esta etapa. Mismo
/// molde que `VehiculoExpedienteScreen`/`LineaTelefonicaExpedienteScreen`
/// (una sola pantalla desplazable con secciones, sin pestañas internas).
class EquipoTelefonicoExpedienteScreen extends ConsumerStatefulWidget {
  const EquipoTelefonicoExpedienteScreen({required this.unidadId, super.key});

  final String unidadId;

  @override
  ConsumerState<EquipoTelefonicoExpedienteScreen> createState() => _EquipoTelefonicoExpedienteScreenState();
}

class _EquipoTelefonicoExpedienteScreenState extends ConsumerState<EquipoTelefonicoExpedienteScreen> {
  ArticuloUnidadData? _unidad;
  ArticuloUnidadTelefonoData? _telefono;
  EquipoTelefonicoCredencialData? _credencial;
  LineaTelefonicaEquipoData? _equipoLineaVigente;
  LineaTelefonicaData? _lineaVigente;
  AsignacionLineaTelefonicaData? _asignacionLineaVigente;
  RecargaLineaTelefonicaData? _ultimaRecargaLinea;
  int _totalRecargasLinea = 0;
  AsignacionData? _asignacionVigente;
  AttachmentData? _resguardoVigente;
  HistoriaEquipoTelefonico? _historia;
  OrigenCompra? _origenCompra;
  Map<String, String> _empleadosPorId = const {};
  Map<String, String> _serviciosPorId = const {};
  Map<String, String> _usuariosPorId = const {};

  bool _cargando = true;
  bool _mostrandoContrasena = false;
  String? _contrasenaVisible;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);

    final inventarioRepo = ref.read(inventarioRepositoryProvider);
    final equipoRepo = ref.read(equipoTelefonicoRepositoryProvider);
    final lineaEquipoRepo = ref.read(lineaTelefonicaEquipoRepositoryProvider);
    final lineaRepo = ref.read(lineaTelefonicaRepositoryProvider);
    final recargaRepo = ref.read(recargaLineaTelefonicaRepositoryProvider);
    final asignacionLineaRepo = ref.read(asignacionLineaTelefonicaRepositoryProvider);
    final asignacionRepo = ref.read(asignacionRepositoryProvider);
    final attachmentRepo = ref.read(attachmentRepositoryProvider);
    final opciones = ref.read(obtenerOpcionesAsignacionLineaTelefonicaUseCaseProvider);
    final historiaUseCase = ref.read(obtenerHistoriaEquipoTelefonicoUseCaseProvider);
    final usuarioRepo = ref.read(usuarioRepositoryProvider);

    final unidad = await inventarioRepo.obtenerUnidadPorId(widget.unidadId);
    final telefono = await inventarioRepo.obtenerTelefono(widget.unidadId);
    final credencial = await equipoRepo.obtenerCredencial(widget.unidadId);

    final equipoLineaVigente = await lineaEquipoRepo.obtenerActualPorUnidad(widget.unidadId);
    LineaTelefonicaData? lineaVigente;
    AsignacionLineaTelefonicaData? asignacionLineaVigente;
    RecargaLineaTelefonicaData? ultimaRecargaLinea;
    var totalRecargasLinea = 0;
    if (equipoLineaVigente != null) {
      lineaVigente = await lineaRepo.obtenerPorId(equipoLineaVigente.lineaTelefonicaId);
      if (lineaVigente != null) {
        asignacionLineaVigente = await asignacionLineaRepo.obtenerActivaPorLinea(lineaVigente.id);
        final historialRecargas = await recargaRepo.listarPorLinea(lineaVigente.id);
        ultimaRecargaLinea = historialRecargas.isEmpty ? null : historialRecargas.first;
        totalRecargasLinea = await recargaRepo.totalPorLinea(lineaVigente.id);
      }
    }

    final asignacionVigente = await asignacionRepo.obtenerActivaPorUnidad(widget.unidadId);
    AttachmentData? resguardoVigente;
    if (asignacionVigente != null) {
      final adjuntos = await attachmentRepo.listarActivosPorAsignacion(asignacionVigente.id);
      if (adjuntos.isNotEmpty) resguardoVigente = adjuntos.first;
    }

    final empleados = await opciones.obtenerEmpleados();
    final servicios = await opciones.obtenerServicios();
    final usuarios = await usuarioRepo.listar();
    final historia = await historiaUseCase.ejecutar(widget.unidadId);

    OrigenCompra? origenCompra;
    if (historia.movimientoAdquisicion != null) {
      origenCompra = await ref
          .read(obtenerOrigenCompraUseCaseProvider)
          .obtenerParaMovimientos([historia.movimientoAdquisicion!.id])
          .then((mapa) => mapa[historia.movimientoAdquisicion!.id]);
    }

    if (!mounted) return;
    setState(() {
      _unidad = unidad;
      _telefono = telefono;
      _credencial = credencial;
      _equipoLineaVigente = equipoLineaVigente;
      _lineaVigente = lineaVigente;
      _asignacionLineaVigente = asignacionLineaVigente;
      _ultimaRecargaLinea = ultimaRecargaLinea;
      _totalRecargasLinea = totalRecargasLinea;
      _asignacionVigente = asignacionVigente;
      _resguardoVigente = resguardoVigente;
      _historia = historia;
      _origenCompra = origenCompra;
      _empleadosPorId = {for (final e in empleados) e.id: e.nombre};
      _serviciosPorId = {for (final s in servicios) s.id: s.nombre};
      _usuariosPorId = {for (final u in usuarios) u.id: u.nombre};
      _mostrandoContrasena = false;
      _contrasenaVisible = null;
      _cargando = false;
    });
  }

  /// La MISMA regla que usa el expediente de la línea y que aplican los
  /// casos de uso al rechazar — no una segunda opinión (§4). Esta
  /// pantalla sólo informa: la resolución vive en el expediente de la
  /// línea, porque lo que se corrige es la asignación de la línea.
  String? _divergenciaEquipo() {
    if (_lineaVigente == null) return null;
    final coherencia = evaluarCoherenciaLineaEquipo(
      unidadId: widget.unidadId,
      destinoLinea: destinoDeAsignacionLinea(_asignacionLineaVigente),
      destinoEquipo: destinoDe(
        empleadoId: _asignacionVigente?.empleadoId,
        servicioId: _asignacionVigente?.servicioId,
      ),
    );
    return mensajeIncoherenciaLineaEquipo(
      AppLocalizations.of(context)!,
      coherencia,
      NombresDestinoTelefonia(_empleadosPorId, _serviciosPorId),
    );
  }

  Future<void> _editarImei() async {
    final resultado = await mostrarDialogoConfigurarEquipoTelefonico(
      context,
      ref,
      unidadId: widget.unidadId,
      imeiActual: _telefono?.imei,
      imei2Actual: _telefono?.imei2,
    );
    if (resultado != null && resultado.isNotEmpty) {
      await _cargar();
      // El listado de Equipos muestra el IMEI 1 en su propia columna —
      // sin esta invalidación quedaba obsoleto hasta cambiar de pestaña
      // (hallazgo real reportado, corrección de invalidación Etapa 9D).
      ref.invalidate(equiposTelefonicosControllerProvider);
    }
  }

  /// Distinto de "Editar IMEI" (arriba): esa es alta/edición rápida sin
  /// motivo, para uso operativo diario. "Corregir identificación"
  /// (Etapa 9D, tercer ajuste posterior) es la corrección sensible —
  /// exige motivo y también permite corregir número de serie/marca/
  /// modelo, no solo IMEI. Vive en Inventario
  /// (`CorregirIdentidadUnidadUseCase`) — este expediente solo ofrece
  /// el mismo acceso desde Telefonía.
  Future<void> _corregirIdentidad() async {
    final unidad = _unidad;
    if (unidad == null) return;
    final corregida = await mostrarDialogoCorregirIdentidadUnidad(context, ref, unidad: unidad, telefono: _telefono);
    if (corregida) {
      await _cargar();
      // Marca/modelo (y el propio IMEI si se corrigió aquí) también se
      // muestran en el listado de Equipos.
      ref.invalidate(equiposTelefonicosControllerProvider);
    }
  }

  Future<void> _editarCorreo() async {
    final actualizo = await mostrarDialogoActualizarCorreoEquipoTelefonico(
      context,
      ref,
      unidadId: widget.unidadId,
      correoActual: _credencial?.correo,
      observacionesActuales: _credencial?.observaciones,
    );
    if (actualizo) await _cargar();
  }

  Future<void> _cambiarContrasena() async {
    final cambio = await mostrarDialogoCambiarContrasenaEquipoTelefonico(context, ref, unidadId: widget.unidadId);
    if (cambio) await _cargar();
  }

  Future<void> _mostrarContrasena() async {
    final l10n = AppLocalizations.of(context)!;
    if (_mostrandoContrasena) {
      setState(() {
        _mostrandoContrasena = false;
        _contrasenaVisible = null;
      });
      return;
    }
    final revelar = ref.read(revelarCredencialEquipoTelefonicoAutorizadoProvider);
    final resultado = await revelar(unidadId: widget.unidadId, accion: AccionRevelacionCredencial.mostrar);
    if (!mounted) return;
    switch (resultado) {
      case RevelarCredencialEquipoTelefonicoExitoso(:final contrasena):
        setState(() {
          _mostrandoContrasena = true;
          _contrasenaVisible = contrasena;
        });
      case RevelarCredencialEquipoTelefonicoClaveNoDisponible():
        RisegFeedback.showError(context, l10n.credencialClaveNoDisponible);
      case RevelarCredencialEquipoTelefonicoSinContrasena():
        RisegFeedback.showError(context, l10n.equipoTelefonicoCredencialSinContrasena);
      case RevelarCredencialEquipoTelefonicoErrorInesperado():
        RisegFeedback.showError(context, l10n.equipoTelefonicoConfigurarErrorInesperado);
    }
  }

  Future<void> _copiarContrasena() async {
    final l10n = AppLocalizations.of(context)!;
    final revelar = ref.read(revelarCredencialEquipoTelefonicoAutorizadoProvider);
    final resultado = await revelar(unidadId: widget.unidadId, accion: AccionRevelacionCredencial.copiar);
    if (!mounted) return;
    switch (resultado) {
      case RevelarCredencialEquipoTelefonicoExitoso(:final contrasena):
        await Clipboard.setData(ClipboardData(text: contrasena));
        if (!mounted) return;
        RisegFeedback.showSuccess(context, l10n.equipoTelefonicoCredencialCopiadaExito);
      case RevelarCredencialEquipoTelefonicoClaveNoDisponible():
        RisegFeedback.showError(context, l10n.credencialClaveNoDisponible);
      case RevelarCredencialEquipoTelefonicoSinContrasena():
        RisegFeedback.showError(context, l10n.equipoTelefonicoCredencialSinContrasena);
      case RevelarCredencialEquipoTelefonicoErrorInesperado():
        RisegFeedback.showError(context, l10n.equipoTelefonicoConfigurarErrorInesperado);
    }
  }

  Future<void> _asignar() async {
    final unidad = _unidad!;
    final asignado = await mostrarDialogoAsignarEquipoTelefonico(
      context,
      ref,
      articuloId: unidad.articuloId,
      unidadId: unidad.id,
    );
    if (asignado) {
      await _cargar();
      // El listado de Equipos muestra "Asignado a". La unidad también
      // cambia de "disponible" a "asignada" en Inventario/Dashboard —
      // ninguno de los dos se enteraba antes de esta corrección.
      ref.invalidate(equiposTelefonicosControllerProvider);
      ref.invalidate(articulosControllerProvider);
      ref.invalidate(dashboardControllerProvider);
    }
  }

  Future<void> _retirarAsignacion() async {
    final l10n = AppLocalizations.of(context)!;
    final cerrado = await mostrarDialogoCerrarAsignacion(
      context,
      ref,
      asignacion: _asignacionVigente!,
      titulo: l10n.cerrarAsignacionDialogoTituloDevolver,
      motivosDisponibles: const [MotivoCierreAsignacion.desgaste, MotivoCierreAsignacion.defecto, MotivoCierreAsignacion.otro],
    );
    if (cerrado) {
      await _cargar();
      // La unidad vuelve a "disponible" en Inventario/Dashboard.
      ref.invalidate(equiposTelefonicosControllerProvider);
      ref.invalidate(articulosControllerProvider);
      ref.invalidate(dashboardControllerProvider);
    }
  }

  /// "Cambiar responsable" (Etapa 9D, ajuste aprobado por Marlon tras
  /// el cierre inicial) — distinto de "Reemplazar" (que cambia el
  /// bien): el mismo teléfono se queda, solo cambia quién es
  /// responsable de él. Vive en Inventario
  /// (`CambiarResponsableAsignacionUseCase`) porque `Asignacion` sigue
  /// siendo la única fuente de verdad de la custodia — este expediente
  /// solo la consume.
  Future<void> _cambiarResponsable() async {
    final cambiado = await mostrarDialogoCambiarResponsableAsignacion(context, ref, asignacion: _asignacionVigente!);
    if (cambiado) {
      await _cargar();
      // Inventario muestra "asignado a" en el detalle de la unidad.
      ref.invalidate(equiposTelefonicosControllerProvider);
      ref.invalidate(articulosControllerProvider);
    }
  }

  Future<void> _reportarDanoPerdida() async {
    final l10n = AppLocalizations.of(context)!;
    final cerrado = await mostrarDialogoCerrarAsignacion(
      context,
      ref,
      asignacion: _asignacionVigente!,
      titulo: l10n.cerrarAsignacionDialogoTituloDanoPerdida,
      motivosDisponibles: const [MotivoCierreAsignacion.dano, MotivoCierreAsignacion.perdida],
    );
    if (cerrado) {
      await _cargar();
      // El daño/pérdida cambia el estatus de la unidad, mostrado en la
      // columna "Estatus" del listado — también visible en Inventario y
      // en el resumen del Dashboard.
      ref.invalidate(equiposTelefonicosControllerProvider);
      ref.invalidate(articulosControllerProvider);
      ref.invalidate(dashboardControllerProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;

    if (_cargando) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final unidad = _unidad;
    if (unidad == null) {
      return Scaffold(appBar: AppBar(), body: RisegEmptyState(title: l10n.equiposTelefonicosListadoCargaErrorTitulo, message: ''));
    }

    final descripcion = [unidad.marca, unidad.modelo].whereType<String>().where((p) => p.trim().isNotEmpty).join(' ');
    final puedeModificar = ref.watch(permissionServiceProvider).hasCode('telefonia.modificar');
    final puedeVerCredenciales = ref.watch(permissionServiceProvider).hasCode('telefonia.verCredenciales');

    return Scaffold(
      appBar: AppBar(title: Text(descripcion.isEmpty ? unidad.codigo : descripcion)),
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
                          Text(descripcion.isEmpty ? '—' : descripcion, style: AppTypography.heading2.copyWith(color: colors.textPrimary)),
                          Text(unidad.codigo, style: AppTypography.body.copyWith(color: colors.textMuted)),
                        ],
                      ),
                    ),
                    RisegStatusBadge(
                      label: estatusEquipoTelefonicoLabel(l10n, unidad.estatus),
                      tone: estatusEquipoTelefonicoTono(unidad.estatus),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xl),

                // 1. Identificación
                RisegCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      RisegSectionHeader(
                        title: l10n.equipoTelefonicoSeccionIdentificacion,
                        secondaryAction: puedeModificar
                            ? RisegButton(
                                label: l10n.corregirIdentidadUnidadBotonAccion,
                                variant: RisegButtonVariant.ghost,
                                size: RisegButtonSize.compact,
                                onPressed: _corregirIdentidad,
                              )
                            : null,
                        primaryAction: puedeModificar
                            ? RisegButton(
                                label: l10n.equipoTelefonicoBotonEditarImei,
                                variant: RisegButtonVariant.secondary,
                                size: RisegButtonSize.compact,
                                onPressed: _editarImei,
                              )
                            : null,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      _campo(l10n.equipoTelefonicoCampoCodigo, unidad.codigo),
                      _campo(l10n.equipoTelefonicoCampoMarca, unidad.marca ?? '—'),
                      _campo(l10n.equipoTelefonicoCampoModelo, unidad.modelo ?? '—'),
                      _campo(l10n.equipoTelefonicoCampoImei1, _telefono?.imei ?? '—'),
                      _campo(l10n.equipoTelefonicoCampoImei2, _telefono?.imei2 ?? '—'),
                      _campo(l10n.equipoTelefonicoCampoNumeroSerie, unidad.numeroSerie),
                      _campo(
                        l10n.equipoTelefonicoCampoFechaCompra,
                        _historia?.movimientoAdquisicion == null ? '—' : _formatoFecha.format(_historia!.movimientoAdquisicion!.fecha),
                      ),
                      _campo(
                        l10n.equipoTelefonicoCampoPrecioAdquisicion,
                        _historia?.movimientoAdquisicion?.costoUnitario == null
                            ? '—'
                            : formatoCosto(_historia!.movimientoAdquisicion!.costoUnitario!),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 180,
                              child: Text(l10n.equipoTelefonicoCampoOrigen, style: AppTypography.label.copyWith(color: colors.textMuted)),
                            ),
                            if (_origenCompra != null)
                              RisegButton(
                                label: l10n.inventarioMovimientoOrigenCompra(_origenCompra!.folioCompra),
                                variant: RisegButtonVariant.ghost,
                                size: RisegButtonSize.compact,
                                onPressed: () => context.go('/compras/${_origenCompra!.compraId}'),
                              )
                            else
                              Text(l10n.equipoTelefonicoOrigenEntradaManual, style: AppTypography.body),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),

                // 2. Credencial
                RisegCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.equipoTelefonicoCredencialSeccionTitulo, style: AppTypography.heading3),
                      const SizedBox(height: AppSpacing.sm),
                      _campo(l10n.equipoTelefonicoCredencialCampoCorreo, _credencial?.correo ?? '—'),
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 180,
                              child: Text(l10n.equipoTelefonicoCredencialCampoContrasena, style: AppTypography.label.copyWith(color: colors.textMuted)),
                            ),
                            Expanded(
                              child: Text(
                                _credencial?.contrasenaCifrada == null
                                    ? '—'
                                    : (_mostrandoContrasena ? (_contrasenaVisible ?? '') : '••••••••'),
                                style: AppTypography.body,
                              ),
                            ),
                            if (puedeVerCredenciales && _credencial?.contrasenaCifrada != null) ...[
                              RisegButton(
                                label: _mostrandoContrasena ? l10n.equipoTelefonicoCredencialBotonOcultar : l10n.equipoTelefonicoCredencialBotonMostrar,
                                variant: RisegButtonVariant.ghost,
                                size: RisegButtonSize.compact,
                                onPressed: _mostrarContrasena,
                              ),
                              RisegButton(
                                label: l10n.equipoTelefonicoCredencialBotonCopiar,
                                variant: RisegButtonVariant.ghost,
                                size: RisegButtonSize.compact,
                                onPressed: _copiarContrasena,
                              ),
                            ],
                          ],
                        ),
                      ),
                      _campo(
                        l10n.equipoTelefonicoCredencialCampoUltimaActualizacion,
                        _credencial?.fechaActualizacionContrasena == null ? '—' : _formatoFecha.format(_credencial!.fechaActualizacionContrasena!),
                      ),
                      _campo(l10n.equipoTelefonicoCredencialCampoObservaciones, _credencial?.observaciones ?? '—'),
                      if (puedeModificar) ...[
                        const SizedBox(height: AppSpacing.sm),
                        Wrap(
                          spacing: AppSpacing.xs,
                          runSpacing: AppSpacing.xs,
                          children: [
                            RisegButton(
                              label: l10n.equipoTelefonicoCredencialBotonEditarCorreo,
                              variant: RisegButtonVariant.ghost,
                              size: RisegButtonSize.compact,
                              onPressed: _editarCorreo,
                            ),
                            RisegButton(
                              label: l10n.equipoTelefonicoCredencialBotonCambiarContrasena,
                              variant: RisegButtonVariant.ghost,
                              size: RisegButtonSize.compact,
                              onPressed: _cambiarContrasena,
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),

                // 3. Línea asociada
                RisegCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.equipoTelefonicoLineaSeccionTitulo, style: AppTypography.heading3),
                      const SizedBox(height: AppSpacing.sm),
                      if (_lineaVigente == null)
                        Text(l10n.equipoTelefonicoLineaVacio, style: AppTypography.body.copyWith(color: colors.textMuted))
                      else ...[
                        _campo(l10n.equipoTelefonicoLineaCampoNumero, _lineaVigente!.numero ?? '—'),
                        _campo(l10n.equipoTelefonicoLineaCampoOperador, operadorLineaTelefonicaLabel(l10n, _lineaVigente!)),
                        _campo(l10n.equipoTelefonicoLineaCampoModalidadSim, modalidadSimLabel(l10n, _lineaVigente!.modalidadSim)),
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 180,
                                child: Text(l10n.equipoTelefonicoLineaCampoEstatus, style: AppTypography.label.copyWith(color: colors.textMuted)),
                              ),
                              RisegStatusBadge(
                                label: estatusLineaTelefonicaLabel(l10n, _lineaVigente!.estatus),
                                tone: estatusLineaTelefonicaTono(_lineaVigente!.estatus),
                              ),
                            ],
                          ),
                        ),
                        _campo(l10n.equipoTelefonicoLineaCampoDesde, _formatoFecha.format(_equipoLineaVigente!.fechaInicio)),
                        _campo(
                          l10n.equipoTelefonicoLineaCampoUltimaRecarga,
                          _ultimaRecargaLinea == null ? '—' : '${_formatoFecha.format(_ultimaRecargaLinea!.fecha)} — ${formatoCosto(_ultimaRecargaLinea!.importe)}',
                        ),
                        _campo(l10n.equipoTelefonicoLineaCampoTotalRecargas, formatoCosto(_totalRecargasLinea)),
                        if (_divergenciaEquipo() case final advertencia?) ...[
                          const SizedBox(height: AppSpacing.xs),
                          Text(advertencia, style: AppTypography.caption.copyWith(color: colors.error)),
                        ],
                        const SizedBox(height: AppSpacing.sm),
                        RisegButton(
                          label: l10n.equipoTelefonicoLineaBotonVerLinea,
                          variant: RisegButtonVariant.ghost,
                          size: RisegButtonSize.compact,
                          onPressed: () => context.go('/telefonia/lineas/${_lineaVigente!.id}'),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),

                // 4. Asignación / custodia — deliberadamente sin
                // "Sucursal derivada": si el destino es un Servicio, el
                // Servicio ya da el contexto operativo; si es un
                // Empleado, derivar una Sucursal es ambiguo (operativo
                // vs. administrativo) y ninguna fuente de lectura de
                // Inventario/Personal la resuelve hoy sin ambigüedad
                // (mismo criterio que `VehiculoExpedienteScreen`, que
                // tampoco la deriva). Decisión de Marlon al cerrar la
                // Etapa 9D — no es un vacío accidental.
                RisegCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      RisegSectionHeader(
                        title: l10n.equipoTelefonicoAsignacionSeccionTitulo,
                        primaryAction: puedeModificar && _asignacionVigente == null
                            ? RisegButton(
                                label: l10n.equipoTelefonicoAsignacionBotonAsignar,
                                variant: RisegButtonVariant.secondary,
                                size: RisegButtonSize.compact,
                                onPressed: unidad.estatus == 'disponible' ? _asignar : null,
                              )
                            : null,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      if (_asignacionVigente == null)
                        Text(l10n.equipoTelefonicoAsignacionVacio, style: AppTypography.body.copyWith(color: colors.textMuted))
                      else ...[
                        _campo(
                          l10n.equipoTelefonicoAsignacionCampoDestino,
                          destinoAsignacionEquipoTelefonicoLabel(_asignacionVigente!, empleadosPorId: _empleadosPorId, serviciosPorId: _serviciosPorId),
                        ),
                        _campo(l10n.equipoTelefonicoAsignacionCampoDesde, _formatoFecha.format(_asignacionVigente!.fechaEntrega)),
                        const SizedBox(height: AppSpacing.sm),
                        Wrap(
                          spacing: AppSpacing.xs,
                          runSpacing: AppSpacing.xs,
                          children: [
                            if (_resguardoVigente != null)
                              RisegButton(
                                label: l10n.resguardoBotonVer,
                                variant: RisegButtonVariant.ghost,
                                size: RisegButtonSize.compact,
                                onPressed: () => ref.read(attachmentStorageProvider).abrir(_resguardoVigente!.path),
                              ),
                            if (puedeModificar) ...[
                              RisegButton(
                                label: l10n.cambiarResponsableAsignacionDialogoTitulo,
                                variant: RisegButtonVariant.ghost,
                                size: RisegButtonSize.compact,
                                onPressed: _cambiarResponsable,
                              ),
                              RisegButton(
                                label: l10n.equipoTelefonicoAsignacionBotonRetirar,
                                variant: RisegButtonVariant.ghost,
                                size: RisegButtonSize.compact,
                                onPressed: _retirarAsignacion,
                              ),
                            ],
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),

                // 5. Estado
                RisegCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.equipoTelefonicoEstadoSeccionTitulo, style: AppTypography.heading3),
                      const SizedBox(height: AppSpacing.sm),
                      // `Wrap` y no `Row` + `Spacer`: a 500 px el badge y
                      // el botón de daño/pérdida no caben en una línea y
                      // se desbordaban 39 px (§21).
                      Wrap(
                        spacing: AppSpacing.xs,
                        runSpacing: AppSpacing.xs,
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          RisegStatusBadge(label: estatusEquipoTelefonicoLabel(l10n, unidad.estatus), tone: estatusEquipoTelefonicoTono(unidad.estatus)),
                          if (puedeModificar)
                            RisegButton(
                              label: l10n.equipoTelefonicoEstadoBotonReportarDanoPerdida,
                              variant: RisegButtonVariant.danger,
                              size: RisegButtonSize.compact,
                              onPressed: _asignacionVigente == null ? null : _reportarDanoPerdida,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),

                // 6. Historial de asignaciones
                RisegCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.equipoTelefonicoHistorialAsignacionesTitulo, style: AppTypography.heading3),
                      const SizedBox(height: AppSpacing.sm),
                      // §12 — vacío: una línea. Con registros: tabla densa.
                      if ((_historia?.asignaciones ?? const []).isEmpty)
                        Text(l10n.equipoTelefonicoHistorialAsignacionesVacio, style: AppTypography.body.copyWith(color: colors.textMuted))
                      else
                      RisegTableBase<AsignacionData>(
                        rows: _historia?.asignaciones ?? const [],
                        emptyState: RisegEmptyState(title: l10n.equipoTelefonicoHistorialAsignacionesVacio, message: ''),
                        columns: [
                          RisegColumn<AsignacionData>(
                            label: l10n.equipoTelefonicoColumnaDestino,
                            cellBuilder: (a) => Text(destinoAsignacionEquipoTelefonicoLabel(a, empleadosPorId: _empleadosPorId, serviciosPorId: _serviciosPorId)),
                          ),
                          RisegColumn<AsignacionData>(
                            label: l10n.equipoTelefonicoColumnaFechaInicio,
                            width: 110,
                            cellBuilder: (a) => Text(_formatoFecha.format(a.fechaEntrega)),
                          ),
                          RisegColumn<AsignacionData>(
                            label: l10n.equipoTelefonicoColumnaFechaTermino,
                            width: 110,
                            cellBuilder: (a) => Text(a.fechaCierre == null ? '—' : _formatoFecha.format(a.fechaCierre!)),
                          ),
                          RisegColumn<AsignacionData>(
                            label: l10n.equipoTelefonicoColumnaEstatus,
                            width: 110,
                            cellBuilder: (a) => RisegStatusBadge(label: estatusAsignacionLabel(l10n, a.estatus), tone: estatusAsignacionTono(a.estatus)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),

                // 7. Historia (períodos de línea + descuentos + eventos)
                _buildSeccionPeriodosLinea(l10n, colors),
                const SizedBox(height: AppSpacing.xl),
                _buildSeccionDescuentos(l10n, colors),
                const SizedBox(height: AppSpacing.xl),
                _buildSeccionEventos(l10n, colors),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSeccionPeriodosLinea(AppLocalizations l10n, AppColorScheme colors) {
    final periodos = _historia?.periodosLinea ?? const [];
    return RisegCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.equipoTelefonicoHistoriaPeriodosLineaTitulo, style: AppTypography.heading3),
          const SizedBox(height: AppSpacing.sm),
          if (periodos.isEmpty)
            Text(l10n.equipoTelefonicoHistoriaPeriodosLineaVacio, style: AppTypography.body.copyWith(color: colors.textMuted))
          else
            for (final periodoConRecargas in periodos)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${periodoConRecargas.linea.numero ?? periodoConRecargas.linea.codigo} · '
                            '${_formatoFecha.format(periodoConRecargas.periodo.fechaInicio)} – '
                            '${periodoConRecargas.periodo.fechaFin == null ? l10n.equipoTelefonicoHistoriaPeriodoActual : _formatoFecha.format(periodoConRecargas.periodo.fechaFin!)}',
                            style: AppTypography.body,
                          ),
                        ),
                      ],
                    ),
                    if (periodoConRecargas.recargas.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(left: AppSpacing.md, top: AppSpacing.xxs),
                        child: Text(l10n.lineaTelefonicaRecargaHistorialVacio, style: AppTypography.caption.copyWith(color: colors.textMuted)),
                      )
                    else
                      for (final recarga in periodoConRecargas.recargas)
                        Padding(
                          padding: const EdgeInsets.only(left: AppSpacing.md, top: AppSpacing.xxs),
                          child: Text(
                            '${_formatoFecha.format(recarga.fecha)} — ${formatoCosto(recarga.importe)}',
                            style: AppTypography.caption.copyWith(color: colors.textMuted),
                          ),
                        ),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  Widget _buildSeccionDescuentos(AppLocalizations l10n, AppColorScheme colors) {
    final descuentos = _historia?.descuentos ?? const [];
    return RisegCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.equipoTelefonicoHistoriaDescuentosTitulo, style: AppTypography.heading3),
          const SizedBox(height: AppSpacing.sm),
          if (descuentos.isEmpty)
            Text(l10n.equipoTelefonicoHistoriaDescuentosVacio, style: AppTypography.body.copyWith(color: colors.textMuted))
          else
            RisegTableBase<DescuentoInventarioData>(
              rows: descuentos,
              columns: [
                RisegColumn<DescuentoInventarioData>(
                  label: l10n.equipoTelefonicoColumnaFecha,
                  width: 110,
                  cellBuilder: (d) => Text(_formatoFecha.format(d.createdAt)),
                ),
                RisegColumn<DescuentoInventarioData>(
                  label: l10n.equipoTelefonicoDescuentoColumnaImporte,
                  width: 110,
                  alignment: TextAlign.right,
                  cellBuilder: (d) => Text(formatoCosto(d.importe)),
                ),
                RisegColumn<DescuentoInventarioData>(
                  label: l10n.equipoTelefonicoColumnaEstatus,
                  width: 120,
                  cellBuilder: (d) => Text(estatusDescuentoEquipoTelefonicoLabel(l10n, d.estatus)),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildSeccionEventos(AppLocalizations l10n, AppColorScheme colors) {
    final eventos = _historia?.eventosConfiguracion ?? const [];
    return RisegCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.equipoTelefonicoHistoriaEventosTitulo, style: AppTypography.heading3),
          const SizedBox(height: AppSpacing.sm),
          if (eventos.isEmpty)
            Text(l10n.equipoTelefonicoHistoriaEventosVacio, style: AppTypography.body.copyWith(color: colors.textMuted))
          else
            for (final evento in eventos)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(_formatoFechaHora.format(evento.fechaHora), style: AppTypography.caption.copyWith(color: colors.textMuted)),
                        const SizedBox(width: AppSpacing.xs),
                        Text(tipoEventoEquipoTelefonicoLabel(l10n, evento.tipoEvento), style: AppTypography.label),
                      ],
                    ),
                    if (evento.actorUsuarioId != null)
                      Text(
                        '${l10n.equipoTelefonicoHistoriaCampoActor}: ${_usuariosPorId[evento.actorUsuarioId] ?? evento.actorUsuarioId}',
                        style: AppTypography.caption.copyWith(color: colors.textMuted),
                      ),
                    if (evento.observacion != null && evento.observacion!.trim().isNotEmpty)
                      Text(evento.observacion!, style: AppTypography.body.copyWith(color: colors.textMuted)),
                  ],
                ),
              ),
        ],
      ),
    );
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
