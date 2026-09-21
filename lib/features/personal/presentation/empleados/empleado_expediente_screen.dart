import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/seed/seed_ids.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/dashboard/presentation/dashboard_controller.dart';
import 'package:riseg_one/features/descuentos_personal/descuentos_personal_providers.dart';
import 'package:riseg_one/features/descuentos_personal/presentation/descuentos_personal_list_screen.dart' show descuentoProgramadoTipoLabel;
import 'package:riseg_one/features/descuentos_personal/presentation/widgets/registrar_descuento_programado_dialog.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';
import 'package:riseg_one/features/inventario/data/tables/asignacion_table.dart';
import 'package:riseg_one/features/inventario/data/tables/descuento_inventario_table.dart' show EstatusDescuentoInventario;
import 'package:riseg_one/features/inventario/inventario_providers.dart';
import 'package:riseg_one/features/inventario/presentation/asignaciones/widgets/adjuntar_resguardo_firmado_dialog.dart';
import 'package:riseg_one/features/inventario/presentation/asignaciones/widgets/asignar_articulo_dialog.dart';
import 'package:riseg_one/features/inventario/presentation/asignaciones/widgets/cerrar_asignacion_dialog.dart';
import 'package:riseg_one/features/inventario/presentation/asignaciones/widgets/entregar_equipo_dialog.dart';
import 'package:riseg_one/features/inventario/presentation/asignaciones/widgets/generar_resguardo_dialog.dart';
import 'package:riseg_one/features/inventario/presentation/asignaciones/widgets/historial_unidad_dialog.dart' show estatusAsignacionLabel, estatusAsignacionTono;
import 'package:riseg_one/features/inventario/presentation/asignaciones/widgets/reemplazar_asignacion_dialog.dart';
import 'package:riseg_one/features/nomina/nomina_providers.dart';
import 'package:riseg_one/features/telefonia/presentation/widgets/linea_telefonica_asignada_empleado_section.dart';
import 'package:riseg_one/features/vehiculos/presentation/widgets/vehiculo_asignado_empleado_section.dart';
import 'package:riseg_one/features/vehiculos/vehiculos_providers.dart' show asignacionVehiculoRepositoryProvider;
import 'package:riseg_one/features/organizacion/presentation/shared/campo_consulta.dart';
import 'package:riseg_one/features/usuarios/usuarios_providers.dart';
import 'package:riseg_one/features/personal/data/tables/empleado_table.dart';
import 'package:riseg_one/features/personal/domain/usecases/actualizar_fotografia_empleado_usecase.dart';
import 'package:riseg_one/features/personal/domain/usecases/alerta_recontratacion_empleado.dart';
import 'package:riseg_one/features/personal/domain/usecases/asignacion_sueldo_con_vigencia.dart';
import 'package:riseg_one/features/personal/domain/usecases/calcular_ciclo_laboral_empleado.dart';
import 'package:riseg_one/features/personal/domain/usecases/calcular_edad.dart';

import '../../../organizacion/organizacion_providers.dart';
import '../../personal_providers.dart';
import 'antiguedad_texto.dart';
import 'bajas_controller.dart';
import 'personal_activo_controller.dart';
import 'empleados_list_screen.dart';
import 'widgets/actualizar_sueldo_asignacion_dialog.dart';
import 'widgets/motivo_baja_empleado_labels.dart';
import 'widgets/empleado_ficha_header.dart';
import 'widgets/adjuntar_documento_empleado_dialog.dart';
import 'widgets/antidoping_empleado_dialog.dart';
import 'widgets/asignar_servicio_empleado_dialog.dart';
import 'widgets/cambiar_servicio_empleado_dialog.dart';
import 'widgets/corregir_empleado_dialog.dart';
import 'widgets/crear_empleado_dialog.dart';
import 'widgets/domicilio_empleado_dialog.dart';
import 'widgets/eliminar_empleado_fisicamente_dialog.dart';
import 'widgets/estudio_socioeconomico_empleado_dialog.dart';
import 'widgets/generar_ficha_tecnica_empleado_dialog.dart';
import 'widgets/perfil_psicologico_empleado_dialog.dart';
import 'widgets/reingreso_empleado_dialog.dart';
import 'widgets/regularizar_perfil_asignacion_dialog.dart';
import 'widgets/retirar_servicio_empleado_dialog.dart';

final _formatoFecha = DateFormat('dd/MM/yyyy');
final _formatoFechaHora = DateFormat('dd/MM/yyyy HH:mm');
final _formatoMonedaEmpleado = NumberFormat.currency(locale: 'es_MX', symbol: r'$');

/// Expediente del Empleado (Etapa 5A) — información general, contacto,
/// domicilio, laboral, escolaridad, experiencia en seguridad privada,
/// documentación e historial administrativo. Cada sección se corrige
/// vía su propio diálogo — sin el mecanismo de "modo edición" de página
/// completa que usan Cliente/Servicio/Sucursal (deliberado para esta
/// etapa de fundamentos: mantiene la pantalla simple).
class EmpleadoExpedienteScreen extends ConsumerStatefulWidget {
  const EmpleadoExpedienteScreen({required this.empleadoId, super.key});

  final String empleadoId;

  @override
  ConsumerState<EmpleadoExpedienteScreen> createState() => _EmpleadoExpedienteScreenState();
}

class _EmpleadoExpedienteScreenState extends ConsumerState<EmpleadoExpedienteScreen> {
  EmpleadoData? _empleado;
  DireccionData? _domicilio;
  List<AttachmentData> _documentos = const [];
  List<EmpleadoEventoData> _eventos = const [];
  List<EmpleadoPeriodoLaboralData> _periodosArchivados = const [];
  AsignacionServicioData? _asignacionVigente;
  AsignacionServicioSueldoVigenciaData? _sueldoVigente;
  List<AsignacionServicioData> _historialAsignaciones = const [];
  Map<String, String> _serviciosPorId = const {};
  Map<String, String> _turnosPorId = const {};
  PuestoData? _puesto;
  EmpresaData? _empresa;
  SucursalData? _sucursal;
  String? _bancoNombre;
  AttachmentData? _fotografia;
  List<FichaTecnicaEmpleadoData> _fichasTecnicas = const [];
  Map<String, String> _fichaTecnicaRutasPorAttachmentId = const {};
  List<AsignacionData> _inventarioAsignado = const [];

  /// Bienes que la persona NO ha devuelto tras su baja laboral
  /// (schemaVersion 82). Se muestran en su propia sección, separados de
  /// "actualmente asignado": un empleado de baja no es usuario
  /// operativo del activo, pero sí su último responsable pendiente.
  List<AsignacionData> _inventarioPendiente = const [];
  List<AsignacionVehiculoData> _vehiculosPendientes = const [];
  Map<String, ArticuloData> _articulosInventarioPorId = const {};
  Map<String, String> _variantesInventarioPorId = const {};
  Map<String, String> _unidadesInventarioPorId = const {};
  List<AttachmentData> _resguardos = const [];
  // Etapa "Entrega múltiple de Inventario" — cabecera documental que
  // agrupa varias Asignacion de un mismo acto de entrega (ver el doc
  // comment de `Entrega`). `_historialInventario` (TODAS, no solo
  // activas) es lo que arma cada tarjeta de Entrega, para que una
  // entrega ya cerrada por completo siga siendo historial visible —
  // `_inventarioAsignado` (solo activas) sigue siendo lo que arma el
  // grupo "Asignaciones individuales" (legacy, sin Entrega).
  List<EntregaData> _entregas = const [];
  List<AsignacionData> _historialInventario = const [];
  Map<String, List<AttachmentData>> _resguardosPorAsignacionId = const {};
  List<DescuentoInventarioData> _descuentos = const [];
  Map<String, String> _foliosNominaPorDescuento = const {};
  // Etapa 15 — "Descuentos / Préstamos": tarjeta APARTE de `_descuentos`
  // (esa es daño/pérdida de Inventario, nunca se mezclan).
  List<DescuentoProgramadoEmpleadoData> _descuentosProgramados = const [];
  DescuentoProgramadoCuotaData? _proximoDescuentoGlobal;
  bool _cargando = true;
  bool _procesando = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    final empleadoRepo = ref.read(empleadoRepositoryProvider);
    final empleado = await empleadoRepo.obtenerPorId(widget.empleadoId);
    final domicilio = await empleadoRepo.obtenerDomicilio(widget.empleadoId);
    // La fotografía y la Ficha técnica son Attachments más (categorías
    // `fotografia`/`fichaTecnica`, fuera de `CategoriaDocumentoEmpleado`)
    // pero cada una se muestra en su propia sección — nunca deben
    // listarse aquí como si fueran documentos del expediente.
    final documentos = (await ref.read(attachmentRepositoryProvider).listarActivosPorEmpleado(widget.empleadoId))
        .where((d) => d.categoria != 'fotografia' && d.categoria != 'fichaTecnica')
        .toList();
    // Fotografía vigente (Etapa 15) — puntero directo
    // `Empleado.fotografiaAttachmentId`, misma fuente de verdad que
    // guarda `ActualizarFotografiaEmpleadoUseCase`, nunca duplicada.
    AttachmentData? fotografia;
    if (empleado?.fotografiaAttachmentId != null) {
      fotografia = await ref.read(attachmentRepositoryProvider).obtenerPorId(empleado!.fotografiaAttachmentId!);
    }
    final eventos = await empleadoRepo.listarEventos(widget.empleadoId);
    final periodosArchivados = await empleadoRepo.listarPeriodosLaboralesArchivados(widget.empleadoId);
    final fichasTecnicas = await ref.read(fichaTecnicaEmpleadoRepositoryProvider).listarPorEmpleado(widget.empleadoId);
    final fichaTecnicaRutasPorAttachmentId = <String, String>{};
    for (final ficha in fichasTecnicas) {
      final adjunto = await ref.read(attachmentRepositoryProvider).obtenerPorId(ficha.attachmentId);
      if (adjunto != null) fichaTecnicaRutasPorAttachmentId[ficha.attachmentId] = adjunto.path;
    }

    // Asignación a Servicio (Etapa 5D) — solo consulta desde aquí, nunca
    // duplica nombre de Servicio/Turno: se resuelve contra sus propios
    // repositorios.
    final asignacionRepo = ref.read(asignacionServicioRepositoryProvider);
    final asignacionVigente = await asignacionRepo.obtenerActivaPorEmpleado(widget.empleadoId);
    final historialAsignaciones = await asignacionRepo.listarPorEmpleado(widget.empleadoId);
    // Sueldo/bono acordado de la asignación vigente (Etapa 6B, ajuste
    // funcional final) — se muestra tal cual junto con Servicio/Turno,
    // nunca duplicado en Empleado.
    AsignacionServicioSueldoVigenciaData? sueldoVigente;
    if (asignacionVigente != null) {
      final vigenciasSueldo = await asignacionRepo.listarVigenciasSueldoActivas(asignacionVigente.id);
      sueldoVigente = clasificarVigenciasSueldo(vigenciasSueldo, DateTime.now()).vigente;
    }

    final serviciosPorId = <String, String>{};
    for (final servicioId in historialAsignaciones.map((a) => a.servicioId).toSet()) {
      final servicio = await ref.read(servicioRepositoryProvider).obtenerPorId(servicioId);
      if (servicio != null) serviciosPorId[servicioId] = servicio.nombre;
    }
    final turnosPorId = <String, String>{};
    final turnoIds = historialAsignaciones.map((a) => a.turnoId).whereType<String>().toSet();
    if (turnoIds.isNotEmpty) {
      final modalidades = await ref.read(catalogoRepositoryProvider).listarModalidadesTurno();
      for (final m in modalidades) {
        if (turnoIds.contains(m.id)) turnosPorId[m.id] = m.nombre;
      }
    }

    PuestoData? puesto;
    if (empleado?.puestoId != null) {
      puesto = await ref.read(puestoRepositoryProvider).obtenerPorId(empleado!.puestoId!);
    }
    EmpresaData? empresa;
    if (empleado?.empresaId != null) {
      final activa = await ref.read(empresaRepositoryProvider).obtenerActiva();
      empresa = activa.id == empleado!.empresaId ? activa : null;
    }
    SucursalData? sucursal;
    if (empleado?.sucursalId != null) {
      sucursal = await ref.read(sucursalRepositoryProvider).obtenerPorId(empleado!.sucursalId!);
    }
    String? bancoNombre;
    if (empleado?.bancoId != null) {
      final bancos = await ref.read(catalogoRepositoryProvider).listarBancos();
      for (final b in bancos) {
        if (b.id == empleado!.bancoId) bancoNombre = b.nombre;
      }
    }

    // Inventario asignado (Etapa 7B) — solo consulta, nunca duplica
    // nombre de Artículo/talla/serie: se resuelve contra sus propios
    // repositorios, mismo criterio que Servicio/Turno arriba.
    final inventarioRepoAsignacion = ref.read(asignacionRepositoryProvider);
    final inventarioActivas = await inventarioRepoAsignacion.listarActivasPorEmpleado(widget.empleadoId);
    // Los pendientes de recuperación siguen siendo técnicamente
    // "activas" (el bien está con la persona), pero NO son asignaciones
    // normales: se separan aquí para no mezclarlos en la sección de
    // equipo asignado.
    final inventarioPendiente = inventarioActivas.where((a) => a.pendienteRecuperacionDesde != null).toList();
    final inventarioAsignado = inventarioActivas.where((a) => a.pendienteRecuperacionDesde == null).toList();
    final vehiculosPendientes =
        await ref.read(asignacionVehiculoRepositoryProvider).listarPendientesRecuperacionPorEmpleado(widget.empleadoId);
    // Historial completo (Etapa "Entrega múltiple de Inventario") —
    // superset de `inventarioAsignado` (sin filtro de estatus), cargado
    // ANTES de armar los mapas de resolución de nombre de abajo: una
    // Asignacion ya cerrada (devuelta/dañada/perdida) también necesita
    // resolver su Artículo/variante/unidad al renderizar su tarjeta de
    // Entrega como historial, no solo las activas.
    final historialInventario = await ref.read(asignacionRepositoryProvider).listarHistorialPorEmpleado(widget.empleadoId);
    final articuloRepo = ref.read(articuloRepositoryProvider);
    final articulosInventarioPorId = <String, ArticuloData>{};
    for (final articuloId in historialInventario.map((a) => a.articuloId).toSet()) {
      final articulo = await articuloRepo.obtenerPorId(articuloId);
      if (articulo != null) articulosInventarioPorId[articuloId] = articulo;
    }
    final variantesInventarioPorId = <String, String>{};
    for (final varianteId in historialInventario.map((a) => a.varianteId).whereType<String>().toSet()) {
      final articuloId = historialInventario.firstWhere((a) => a.varianteId == varianteId).articuloId;
      final variantes = await articuloRepo.listarVariantes(articuloId, soloActivas: false);
      final variante = variantes.where((v) => v.id == varianteId).firstOrNull;
      if (variante != null) variantesInventarioPorId[varianteId] = variante.valor;
    }
    final unidadesInventarioPorId = <String, String>{};
    for (final unidadId in historialInventario.map((a) => a.unidadId).whereType<String>().toSet()) {
      final unidad = await ref.read(inventarioRepositoryProvider).obtenerUnidadPorId(unidadId);
      if (unidad != null) unidadesInventarioPorId[unidadId] = '${unidad.codigo} · ${unidad.numeroSerie}';
    }

    // Entregas (Etapa "Entrega múltiple de Inventario") — cabecera
    // documental que agrupa varias Asignaciones de un mismo acto.
    final entregas = await ref.read(entregaRepositoryProvider).listarPorEmpleado(widget.empleadoId);

    // Resguardos (Etapa 7C) — un mismo documento puede cubrir varias
    // Asignaciones y sigue siendo consultable aunque ya no estén
    // activas, así que se agrega sobre el historial completo,
    // deduplicando por Attachment. Se conserva también por-Asignacion
    // (`resguardosPorAsignacionId`) para derivar el badge Pendiente/
    // Firmado de cada tarjeta de Entrega sin una consulta aparte.
    final resguardosPorId = <String, AttachmentData>{};
    final resguardosPorAsignacionId = <String, List<AttachmentData>>{};
    for (final asignacion in historialInventario) {
      final adjuntos = await ref.read(attachmentRepositoryProvider).listarActivosPorAsignacion(asignacion.id);
      resguardosPorAsignacionId[asignacion.id] = adjuntos;
      for (final adjunto in adjuntos) {
        resguardosPorId[adjunto.id] = adjunto;
      }
    }
    final resguardos = resguardosPorId.values.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    // Etapa 15 (integración real con Nómina): historial completo, no
    // solo pendientes — un descuento `aplicado` conserva su monto +
    // folio de Nómina + fecha, para trazabilidad auditable.
    final descuentos = await ref.read(asignacionRepositoryProvider).listarDescuentosPorEmpleado(widget.empleadoId);
    final foliosNominaPorDescuento = <String, String>{};
    for (final descuento in descuentos) {
      final nominaEmpleadoId = descuento.nominaEmpleadoId;
      if (nominaEmpleadoId == null) continue;
      final nominaEmpleado = await ref.read(nominaRepositoryProvider).obtenerEmpleado(nominaEmpleadoId);
      if (nominaEmpleado == null) continue;
      final nomina = await ref.read(nominaRepositoryProvider).obtenerPorId(nominaEmpleado.nominaId);
      if (nomina != null) foliosNominaPorDescuento[descuento.id] = nomina.folio;
    }

    // Etapa 15 — préstamos/botas (fuente de verdad del COBRO, aparte de
    // Inventario) — se lista completo (activo/liquidado/cancelado), la
    // tarjeta filtra qué mostrar.
    final descuentosProgramados = await ref.read(descuentoProgramadoRepositoryProvider).listarPorEmpleado(widget.empleadoId);
    DescuentoProgramadoCuotaData? proximoDescuentoGlobal;
    for (final d in descuentosProgramados) {
      if (d.estatus != 'activo') continue;
      final cuotas = await ref.read(descuentoProgramadoRepositoryProvider).listarCuotas(d.id);
      for (final c in cuotas) {
        if (c.estatus != 'pendiente' && c.estatus != 'reservada') continue;
        if (proximoDescuentoGlobal == null || c.fechaProgramada.isBefore(proximoDescuentoGlobal.fechaProgramada)) {
          proximoDescuentoGlobal = c;
        }
      }
    }

    if (!mounted) return;
    setState(() {
      _empleado = empleado;
      _domicilio = domicilio;
      _documentos = documentos;
      _eventos = eventos;
      _periodosArchivados = periodosArchivados;
      _asignacionVigente = asignacionVigente;
      _sueldoVigente = sueldoVigente;
      _historialAsignaciones = historialAsignaciones;
      _serviciosPorId = serviciosPorId;
      _turnosPorId = turnosPorId;
      _puesto = puesto;
      _empresa = empresa;
      _sucursal = sucursal;
      _bancoNombre = bancoNombre;
      _fotografia = fotografia;
      _fichasTecnicas = fichasTecnicas;
      _fichaTecnicaRutasPorAttachmentId = fichaTecnicaRutasPorAttachmentId;
      _inventarioAsignado = inventarioAsignado;
      _inventarioPendiente = inventarioPendiente;
      _vehiculosPendientes = vehiculosPendientes;
      _articulosInventarioPorId = articulosInventarioPorId;
      _variantesInventarioPorId = variantesInventarioPorId;
      _unidadesInventarioPorId = unidadesInventarioPorId;
      _entregas = entregas;
      _historialInventario = historialInventario;
      _resguardosPorAsignacionId = resguardosPorAsignacionId;
      _resguardos = resguardos;
      _descuentos = descuentos;
      _foliosNominaPorDescuento = foliosNominaPorDescuento;
      _descuentosProgramados = descuentosProgramados;
      _proximoDescuentoGlobal = proximoDescuentoGlobal;
      _cargando = false;
    });
  }

  String _eventoLabel(AppLocalizations l10n, String tipoEvento) {
    return switch (TipoEventoEmpleado.values.byName(tipoEvento)) {
      TipoEventoEmpleado.creado => l10n.empleadoDetalleHistorialEventoCreado,
      TipoEventoEmpleado.corregido => l10n.empleadoDetalleHistorialEventoCorregido,
      TipoEventoEmpleado.cambioEstatus => l10n.empleadoDetalleHistorialEventoCambioEstatus,
      TipoEventoEmpleado.domicilioActualizado => l10n.empleadoDetalleHistorialEventoDomicilioActualizado,
      TipoEventoEmpleado.fotografiaActualizada => l10n.empleadoDetalleHistorialEventoFotografiaActualizada,
      TipoEventoEmpleado.documentoAdjuntado => l10n.empleadoDetalleHistorialEventoDocumentoAdjuntado,
      TipoEventoEmpleado.documentoArchivado => l10n.empleadoDetalleHistorialEventoDocumentoArchivado,
      TipoEventoEmpleado.perfilPsicologicoActualizado => l10n.empleadoDetalleHistorialEventoPerfilPsicologicoActualizado,
      TipoEventoEmpleado.estudioSocioeconomicoActualizado => l10n.empleadoDetalleHistorialEventoEstudioSocioeconomicoActualizado,
      TipoEventoEmpleado.antidopingActualizado => l10n.empleadoDetalleHistorialEventoAntidopingActualizado,
      TipoEventoEmpleado.bajaLaboral => l10n.empleadoDetalleHistorialEventoBajaLaboral,
      TipoEventoEmpleado.reingreso => l10n.empleadoDetalleHistorialEventoReingreso,
      TipoEventoEmpleado.asignacionServicio => l10n.empleadoDetalleHistorialEventoAsignacionServicio,
      TipoEventoEmpleado.cambioServicio => l10n.empleadoDetalleHistorialEventoCambioServicio,
      TipoEventoEmpleado.retiroServicio => l10n.empleadoDetalleHistorialEventoRetiroServicio,
      TipoEventoEmpleado.fichaTecnicaGenerada => l10n.empleadoDetalleHistorialEventoFichaTecnicaGenerada,
      TipoEventoEmpleado.regularizacionPerfilAsignacion => l10n.empleadoDetalleHistorialEventoRegularizacionPerfilAsignacion,
    };
  }

  Future<void> _corregir() async {
    final actualizo = await mostrarDialogoCorregirEmpleado(context, ref, _empleado!);
    if (actualizo) await _cargar();
  }

  Future<void> _editarDomicilio() async {
    final actualizo = await mostrarDialogoDomicilioEmpleado(context, ref, empleadoId: widget.empleadoId, domicilioActual: _domicilio);
    if (actualizo) await _cargar();
  }

  Future<void> _generarFichaTecnica() async {
    final generada = await mostrarDialogoGenerarFichaTecnicaEmpleado(
      context,
      ref,
      empleado: _empleado!,
      domicilio: _domicilio,
      asignacionVigente: _asignacionVigente,
    );
    if (generada) await _cargar();
  }

  Future<void> _adjuntarDocumento() async {
    final adjunto = await mostrarDialogoAdjuntarDocumentoEmpleado(context, ref, widget.empleadoId);
    if (adjunto) await _cargar();
  }

  Future<void> _registrarPerfilPsicologico() async {
    final actualizo = await mostrarDialogoPerfilPsicologicoEmpleado(context, ref, _empleado!);
    if (actualizo) await _cargar();
  }

  Future<void> _registrarEstudioSocioeconomico() async {
    final actualizo = await mostrarDialogoEstudioSocioeconomicoEmpleado(context, ref, _empleado!);
    if (actualizo) await _cargar();
  }

  Future<void> _registrarAntidoping() async {
    final actualizo = await mostrarDialogoAntidopingEmpleado(context, ref, _empleado!);
    if (actualizo) await _cargar();
  }

  Future<void> _actualizarFotografia() async {
    final l10n = AppLocalizations.of(context)!;
    final seleccion = await FilePicker.platform.pickFiles(type: FileType.image);
    final archivo = seleccion?.files.singleOrNull;
    if (archivo?.path == null) return;
    if (!mounted) return;

    setState(() => _procesando = true);
    final resultado = await ref.read(actualizarFotografiaEmpleadoAutorizadoProvider)(
          empleadoId: widget.empleadoId,
          sourceFilePath: archivo!.path!,
          originalFileName: archivo.name,
          mimeType: 'image/${archivo.extension ?? 'jpeg'}',
        );
    if (!mounted) return;
    setState(() => _procesando = false);

    switch (resultado) {
      case ActualizarFotografiaEmpleadoExitoso():
        await _cargar();
      case ActualizarFotografiaEmpleadoNoExiste():
      case ActualizarFotografiaEmpleadoErrorInesperado():
        RisegFeedback.showError(context, l10n.actualizarFotografiaEmpleadoErrorInesperado);
    }
  }

  Future<void> _eliminarFisicamente() async {
    final eliminado = await mostrarDialogoEliminarEmpleadoFisicamente(context, ref, widget.empleadoId);
    if (!eliminado) return;
    ref.invalidate(personalActivoControllerProvider);
    ref.invalidate(bajasControllerProvider);
    // Etapa 20 (hueco real encontrado): el Empleado eliminado puede
    // haber estado en `alertas.empleadosBajaConPendiente` del
    // Dashboard — sin esto, seguía apareciendo ahí tras eliminarse.
    ref.invalidate(dashboardControllerProvider);
    if (mounted) context.pop();
  }

  Future<void> _registrarBajaLaboral() async {
    // La baja dejó de caber en un diálogo: ahora es la pantalla que
    // concilia TODO lo que la persona tiene bajo su responsabilidad.
    // El diálogo antiguo se retiró — era la puerta trasera que marcaba
    // todos los bienes como pendientes sin que nadie decidiera nada.
    final actualizo = await context.push<bool>('/personal/empleados/${widget.empleadoId}/baja') ?? false;
    if (actualizo) {
      await _cargar();
      // El Empleado desaparece de Personal activo y aparece de
      // inmediato en Bajas (Etapa 15, rediseño de Personal/Bajas) —
      // sin esta invalidación, ambas pantallas quedarían obsoletas
      // hasta cambiar de pestaña.
      ref.invalidate(personalActivoControllerProvider);
      ref.invalidate(bajasControllerProvider);
      // Un Empleado dado de baja con Inventario todavía pendiente
      // alimenta "Requiere atención" del Dashboard.
      ref.invalidate(dashboardControllerProvider);
    }
  }

  Future<void> _registrarReingreso() async {
    final alerta = calcularAlertaRecontratacion(_empleado!, _periodosArchivados);
    final actualizo = await mostrarDialogoReingresoEmpleado(context, ref, _empleado!, alerta);
    if (actualizo) {
      await _cargar();
      // El Empleado vuelve a Personal activo; Bajas conserva el evento
      // recién archivado en su historial (nunca lo destruye) — ambas
      // vistas deben refrescarse de inmediato.
      ref.invalidate(personalActivoControllerProvider);
      ref.invalidate(bajasControllerProvider);
      // Etapa 20 (hueco real encontrado): el reingreso cambia
      // `totalActivos`/`reingresosEnPeriodo` que lee el Dashboard
      // (Personal y KPIs).
      ref.invalidate(dashboardControllerProvider);
    }
  }

  Future<void> _asignarServicio() async {
    final actualizo = await mostrarDialogoAsignarServicioEmpleado(context, ref, _empleado!);
    if (actualizo) {
      await _cargar();
      // Asignar/cambiar/retirar un Servicio reconcilia VacanteOperativa
      // (Etapa 15, rediseño gerencial) — la Cobertura/Vacantes del
      // Dashboard quedarían obsoletas sin esta invalidación; Personal
      // activo también muestra Servicio/Turno/asignado-sin-asignar.
      ref.invalidate(dashboardControllerProvider);
      ref.invalidate(personalActivoControllerProvider);
    }
  }

  Future<void> _cambiarServicio() async {
    final actualizo = await mostrarDialogoCambiarServicioEmpleado(context, ref, _empleado!, _asignacionVigente!.servicioId);
    if (actualizo) {
      await _cargar();
      ref.invalidate(dashboardControllerProvider);
      ref.invalidate(personalActivoControllerProvider);
    }
  }

  Future<void> _retirarServicio() async {
    final actualizo = await mostrarDialogoRetirarServicioEmpleado(context, ref, _empleado!);
    if (actualizo) {
      await _cargar();
      ref.invalidate(dashboardControllerProvider);
      ref.invalidate(personalActivoControllerProvider);
    }
  }

  Future<void> _regularizarPerfilAsignacion() async {
    final actualizo = await mostrarDialogoRegularizarPerfilAsignacion(context, ref, _asignacionVigente!);
    if (actualizo) {
      await _cargar();
      // Regularizar el perfil de una asignación histórica cambia su
      // atribución de cobertura (línea comercial) — el Dashboard debe
      // reflejarlo de inmediato, sin cambiar de pestaña ni reabrir la app.
      ref.invalidate(dashboardControllerProvider);
    }
  }

  Future<void> _actualizarSueldoAsignacion() async {
    final actualizo = await mostrarDialogoActualizarSueldoAsignacion(context, ref, _asignacionVigente!);
    if (actualizo) await _cargar();
  }

  Future<void> _asignarInventario() async {
    final asignado = await mostrarDialogoAsignarArticulo(context, ref, empleadoId: widget.empleadoId);
    if (asignado) await _cargar();
  }

  Future<void> _entregarEquipo() async {
    final entregado = await mostrarDialogoEntregarEquipo(
      context,
      ref,
      empleadoId: widget.empleadoId,
      empleadoNombre: empleadoNombreCompleto(_empleado!),
    );
    if (entregado) await _cargar();
  }

  Future<void> _devolverInventario(AsignacionData asignacion) async {
    final l10n = AppLocalizations.of(context)!;
    final cerrado = await mostrarDialogoCerrarAsignacion(
      context,
      ref,
      asignacion: asignacion,
      titulo: l10n.cerrarAsignacionDialogoTituloDevolver,
      motivosDisponibles: const [
        MotivoCierreAsignacion.desgaste,
        MotivoCierreAsignacion.cambioTalla,
        MotivoCierreAsignacion.defecto,
        MotivoCierreAsignacion.otro,
      ],
    );
    if (cerrado) await _cargar();
  }

  Future<void> _reportarDanoPerdidaInventario(AsignacionData asignacion) async {
    final l10n = AppLocalizations.of(context)!;
    final cerrado = await mostrarDialogoCerrarAsignacion(
      context,
      ref,
      asignacion: asignacion,
      titulo: l10n.cerrarAsignacionDialogoTituloDanoPerdida,
      motivosDisponibles: const [MotivoCierreAsignacion.dano, MotivoCierreAsignacion.perdida],
    );
    if (cerrado) await _cargar();
  }

  Future<void> _reemplazarInventario(AsignacionData asignacion) async {
    final reemplazado = await mostrarDialogoReemplazarAsignacion(context, ref, asignacion: asignacion);
    if (reemplazado) await _cargar();
  }

  // Acotado a [asignaciones] (una Entrega o el bucket legacy), nunca a
  // todo el inventario del empleado — ver el doc comment de
  // `_inventarioGrupoCard`.
  Future<void> _generarResguardo(List<AsignacionData> asignaciones) async {
    await mostrarDialogoGenerarResguardo(context, ref, asignaciones: asignaciones, detalleBuilder: _inventarioDetalle);
  }

  Future<void> _adjuntarResguardoFirmado(List<AsignacionData> asignaciones) async {
    final adjunto = await mostrarDialogoAdjuntarResguardoFirmado(
      context,
      ref,
      asignaciones: asignaciones,
      detalleBuilder: _inventarioDetalle,
    );
    if (adjunto) await _cargar();
  }

  String _inventarioDetalle(AsignacionData asignacion) {
    final articulo = _articulosInventarioPorId[asignacion.articuloId];
    final nombre = articulo?.nombre ?? asignacion.articuloId;
    final variante = asignacion.varianteId == null ? null : _variantesInventarioPorId[asignacion.varianteId];
    final unidad = asignacion.unidadId == null ? null : _unidadesInventarioPorId[asignacion.unidadId];
    if (unidad != null) return '$nombre · $unidad';
    if (variante != null) return '${asignacion.cantidad} × $nombre ($variante)';
    return '${asignacion.cantidad} × $nombre';
  }

  /// Una tarjeta de grupo de "Equipo asignado" — una Entrega (folio +
  /// fecha) o el bucket legacy "Asignaciones individuales" (sin
  /// Entrega). Acciones de resguardo acotadas a [asignaciones] (nunca
  /// globales a todo el empleado — Etapa "Entrega múltiple de
  /// Inventario"): antes del rediseño, "Generar resguardo"/"Adjuntar
  /// resguardo firmado" cubrían el inventario completo del empleado,
  /// sin distinción; ahora cada tarjeta genera/adjunta solo sobre sus
  /// propias líneas.
  Widget _inventarioGrupoCard({
    required String titulo,
    String? subtitulo,
    required List<AsignacionData> asignaciones,
    required Future<void> Function(List<AsignacionData>) onGenerarResguardo,
    required Future<void> Function(List<AsignacionData>) onAdjuntarResguardo,
  }) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;
    final activas = asignaciones.where((a) => a.estatus == EstatusAsignacion.activa.name).toList();
    final cerradas = asignaciones.where((a) => a.estatus != EstatusAsignacion.activa.name).toList();
    // Firmado si CUALQUIER línea del grupo ya tiene un resguardo activo
    // adjunto — un mismo documento puede cubrir varias Asignaciones
    // (Etapa 7C), así que basta con encontrar una.
    final firmado = asignaciones.any((a) => (_resguardosPorAsignacionId[a.id] ?? const []).isNotEmpty);
    // Derivado, nunca persistido (decisión confirmada: badge de 2
    // estados) — una tarjeta donde ya no queda ninguna línea activa se
    // muestra atenuada, mismo criterio que el resto del proyecto usa
    // `RisegCardVariant.subtle` para contenido secundario.
    final todoCerrado = asignaciones.isNotEmpty && activas.isEmpty;

    return RisegCard(
      variant: todoCerrado ? RisegCardVariant.subtle : RisegCardVariant.standard,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RisegSectionHeader(
            title: titulo,
            description: subtitulo,
            primaryAction: Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                RisegStatusBadge(
                  label: firmado ? l10n.empleadoInventarioBadgeFirmado : l10n.empleadoInventarioBadgePendiente,
                  tone: firmado ? RisegStatusTone.success : RisegStatusTone.warning,
                ),
                RisegButton(
                  label: l10n.generarResguardoDialogoTitulo,
                  variant: RisegButtonVariant.secondary,
                  size: RisegButtonSize.compact,
                  onPressed: () => onGenerarResguardo(asignaciones),
                ),
                RisegButton(
                  label: l10n.adjuntarResguardoDialogoTitulo,
                  variant: RisegButtonVariant.secondary,
                  size: RisegButtonSize.compact,
                  onPressed: () => onAdjuntarResguardo(asignaciones),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          for (final asignacion in activas)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Row(
                children: [
                  Expanded(child: Text(_inventarioDetalle(asignacion), style: AppTypography.body)),
                  RisegActionsMenu(
                    actions: [
                      RisegMenuAction(
                        label: l10n.asignacionBotonDevolver,
                        icon: Icons.assignment_return_outlined,
                        onTap: () => _devolverInventario(asignacion),
                      ),
                      RisegMenuAction(
                        label: l10n.asignacionBotonReemplazar,
                        icon: Icons.swap_horiz_outlined,
                        onTap: () => _reemplazarInventario(asignacion),
                      ),
                      RisegMenuAction(
                        label: l10n.asignacionBotonReportarDanoPerdida,
                        icon: Icons.report_problem_outlined,
                        destructive: true,
                        onTap: () => _reportarDanoPerdidaInventario(asignacion),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          for (final asignacion in cerradas)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Row(
                children: [
                  Expanded(
                    child: Text(_inventarioDetalle(asignacion), style: AppTypography.body.copyWith(color: colors.textMuted)),
                  ),
                  RisegStatusBadge(label: estatusAsignacionLabel(l10n, asignacion.estatus), tone: estatusAsignacionTono(asignacion.estatus)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;

    if (_cargando) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.empleadoExpedienteTitulo)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final empleado = _empleado;
    if (empleado == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.empleadoExpedienteTitulo)),
        body: RisegEmptyState(
          icon: Icons.error_outline,
          title: l10n.empleadosListadoCargaErrorTitulo,
          message: l10n.empleadosListadoCargaErrorMensaje,
        ),
      );
    }

    final cancelado = EstatusEmpleado.values.byName(empleado.estatus) == EstatusEmpleado.baja;
    final cicloLaboral = calcularCicloLaboralEmpleado(empleado);
    final esMaestro = ref.watch(sesionControllerProvider)?.esMaestro ?? false;
    final fotografia = _fotografia;

    // Agrupamiento en memoria por Entrega (Etapa "Entrega múltiple de
    // Inventario") — armado a mano igual que el resto de agrupamientos
    // de esta pantalla, sin controller nuevo. `_historialInventario`
    // (todas, no solo activas) alimenta cada tarjeta de Entrega para
    // que una entrega ya cerrada por completo siga siendo historial
    // visible; el bucket "Asignaciones individuales" (legacy, sin
    // Entrega) conserva el comportamiento previo — solo activas.
    final historialPorEntregaId = <String, List<AsignacionData>>{};
    for (final asignacion in _historialInventario) {
      final entregaId = asignacion.entregaId;
      if (entregaId != null) (historialPorEntregaId[entregaId] ??= []).add(asignacion);
    }
    final entregasOrdenadas = [..._entregas]..sort((a, b) => b.fechaEntrega.compareTo(a.fechaEntrega));
    final individuales = _inventarioAsignado.where((a) => a.entregaId == null).toList();
    final hayEquipoAsignado = individuales.isNotEmpty || historialPorEntregaId.values.any((lineas) => lineas.isNotEmpty);

    return Scaffold(
      appBar: AppBar(title: Text(empleadoNombreCompleto(empleado))),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                EmpleadoFichaHeader(
                  nombreCompleto: empleadoNombreCompleto(empleado),
                  subtitulo: _puesto == null
                      ? l10n.personalActivoNumeroEmpleado(empleado.numeroEmpleado)
                      : l10n.empleadoFichaSubtituloConPuesto(empleado.numeroEmpleado, _puesto!.nombre),
                  servicioActual: _asignacionVigente == null ? null : _serviciosPorId[_asignacionVigente!.servicioId],
                  estatusBadge: RisegStatusBadge(
                    label: empleadoEstatusLabel(l10n, empleado.estatus),
                    tone: empleadoEstatusTono(empleado.estatus),
                  ),
                  ingresoAntiguedad: l10n.empleadoFichaIngresoAntiguedad(
                    _formatoFecha.format(empleado.fechaIngreso),
                    antiguedadTexto(l10n, empleado),
                  ),
                  fotografiaPath: fotografia?.path,
                  onTapFoto: _procesando ? null : _actualizarFotografia,
                  acciones: Wrap(
                    spacing: AppSpacing.xs,
                    children: [
                      RisegButton(label: l10n.empleadoDetalleBotonCorregir, variant: RisegButtonVariant.secondary, onPressed: _corregir),
                      RisegActionsMenu(
                        menuKey: const Key('empleado_expediente_menu_acciones'),
                        actions: [
                          if (cancelado)
                            RisegMenuAction(
                              label: l10n.empleadoDetalleBotonRegistrarReingreso,
                              icon: Icons.replay_outlined,
                              onTap: _registrarReingreso,
                            )
                          else
                            RisegMenuAction(
                              label: l10n.empleadoDetalleBotonDarDeBaja,
                              icon: Icons.person_off_outlined,
                              destructive: true,
                              onTap: _registrarBajaLaboral,
                            ),
                          // Facultad extraordinaria Maestro-only (Etapa
                          // 15) — antes un botón rojo permanente junto a
                          // "Dar de baja"; Etapa 17 la mueve al menú ⋯,
                          // misma llamada/autorización exacta.
                          if (esMaestro)
                            RisegMenuAction(
                              key: const Key('empleado_expediente_boton_eliminar_fisicamente'),
                              label: l10n.empleadoDetalleBotonEliminarFisicamente,
                              icon: Icons.delete_forever_outlined,
                              destructive: true,
                              onTap: _eliminarFisicamente,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (cancelado && _inventarioAsignado.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(color: colors.errorBg, borderRadius: AppRadius.mdRadius),
                    child: Row(
                      children: [
                        Icon(Icons.warning_amber_outlined, color: colors.error, size: AppSizes.iconSm),
                        const SizedBox(width: AppSpacing.xs),
                        Expanded(
                          child: Text(l10n.asignacionAvisoPendientesBaja, style: AppTypography.body.copyWith(color: colors.error)),
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
                      Text(
                        l10n.empleadoSeccionInformacionPersonalContacto,
                        style: AppTypography.heading2.copyWith(color: colors.textPrimary),
                      ),
                      RisegFormSection(
                        title: l10n.empleadoSeccionGeneral,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              CampoConsulta(label: l10n.empleadoCampoSexo, value: empleadoSexoLabelDetalle(l10n, empleado.sexo)),
                              const SizedBox(height: AppSpacing.sm),
                              Row(
                                children: [
                                  Expanded(
                                    child: CampoConsulta(
                                      label: l10n.empleadoCampoFechaNacimiento,
                                      value: _formatoFecha.format(empleado.fechaNacimiento),
                                    ),
                                  ),
                                  Expanded(
                                    child: CampoConsulta(
                                      label: l10n.empleadoDetalleCampoEdad,
                                      value: l10n.empleadoDetalleEdadAnios(calcularEdad(empleado.fechaNacimiento)),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              CampoConsulta(label: l10n.empleadoCampoCurp, value: empleado.curp),
                              const SizedBox(height: AppSpacing.sm),
                              CampoConsulta(label: l10n.empleadoCampoRfc, value: empleado.rfc),
                              const SizedBox(height: AppSpacing.sm),
                              CampoConsulta(label: l10n.empleadoCampoCodigoPostalFiscal, value: empleado.codigoPostalFiscal),
                              const SizedBox(height: AppSpacing.sm),
                              CampoConsulta(label: l10n.empleadoCampoNss, value: empleado.nss),
                              const SizedBox(height: AppSpacing.sm),
                              CampoConsulta(
                                label: l10n.empleadoCampoEstadoCivil,
                                value: empleadoEstadoCivilLabelDetalle(l10n, empleado.estadoCivil),
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              CampoConsulta(label: l10n.empleadoCampoNacionalidad, value: empleado.nacionalidad),
                            ],
                          ),
                        ],
                      ),
                      RisegFormSection(
                        title: l10n.empleadoSeccionContacto,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              CampoConsulta(label: l10n.empleadoCampoTelefono, value: empleado.telefono),
                              const SizedBox(height: AppSpacing.sm),
                              CampoConsulta(label: l10n.empleadoCampoCorreoElectronico, value: empleado.correoElectronico),
                              const SizedBox(height: AppSpacing.sm),
                              CampoConsulta(label: l10n.empleadoCampoContactoEmergenciaNombre, value: empleado.contactoEmergenciaNombre),
                              const SizedBox(height: AppSpacing.sm),
                              CampoConsulta(label: l10n.empleadoCampoTelefonoEmergencia, value: empleado.telefonoEmergencia),
                              const SizedBox(height: AppSpacing.sm),
                              CampoConsulta(label: l10n.empleadoCampoParentescoEmergencia, value: empleado.parentescoEmergencia),
                            ],
                          ),
                        ],
                      ),
                      RisegFormSection(
                        title: l10n.empleadoSeccionDatosBancarios,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              CampoConsulta(
                                label: l10n.empleadoCampoBanco,
                                value: empleado.bancoId == SeedIds.bancoOtro && empleado.bancoOtroDescripcion != null
                                    ? '$_bancoNombre · ${empleado.bancoOtroDescripcion}'
                                    : _bancoNombre,
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              CampoConsulta(label: l10n.empleadoCampoNumeroCuentaTarjeta, value: empleado.numeroCuentaTarjeta),
                              const SizedBox(height: AppSpacing.sm),
                              CampoConsulta(label: l10n.empleadoCampoClabe, value: empleado.clabe),
                            ],
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
                      Row(
                        children: [
                          Expanded(
                            child: Text(l10n.empleadoSeccionDomicilio, style: AppTypography.heading3.copyWith(color: colors.textPrimary)),
                          ),
                          RisegButton(label: l10n.empleadoDetalleBotonEditar, variant: RisegButtonVariant.ghost, onPressed: _editarDomicilio),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      if (_domicilio == null)
                        Text(l10n.empleadoDetalleDomicilioSinCapturar, style: AppTypography.body.copyWith(color: colors.textMuted))
                      else ...[
                        CampoConsulta(
                          label: l10n.domicilioEmpleadoCampoCalle,
                          value: '${_domicilio!.calle} ${_domicilio!.numeroExterior}',
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        CampoConsulta(label: l10n.domicilioEmpleadoCampoColonia, value: _domicilio!.colonia),
                        const SizedBox(height: AppSpacing.sm),
                        CampoConsulta(
                          label: l10n.domicilioEmpleadoCampoMunicipio,
                          value: '${_domicilio!.municipioAlcaldia}, ${_domicilio!.estado} ${_domicilio!.codigoPostal}',
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
                      Text(l10n.empleadoSeccionLaboral, style: AppTypography.heading2.copyWith(color: colors.textPrimary)),
                      RisegFormSection(
                        title: l10n.empleadoSeccionDatosLaborales,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              CampoConsulta(label: l10n.empleadoCampoFechaIngreso, value: _formatoFecha.format(empleado.fechaIngreso)),
                              const SizedBox(height: AppSpacing.sm),
                              CampoConsulta(label: l10n.empleadoCampoPuesto, value: _puesto?.nombre),
                              const SizedBox(height: AppSpacing.sm),
                              CampoConsulta(label: l10n.empleadoCampoEmpresa, value: _empresa?.nombreComercial),
                              const SizedBox(height: AppSpacing.sm),
                              CampoConsulta(label: l10n.empleadoCampoSucursal, value: _sucursal?.nombre),
                              // Sueldo/bono administrativo — solo tienen sentido
                              // sin AsignacionServicio vigente (ver doc comment
                              // de `Empleado.sueldoMensualAdministrativo`); con
                              // asignación vigente, esos datos vienen de ahí
                              // (Etapa 6B, expediente de esa asignación).
                              if (_asignacionVigente == null) ...[
                                const SizedBox(height: AppSpacing.sm),
                                CampoConsulta(
                                  label: l10n.empleadoCampoSueldoMensualAdministrativo,
                                  value: empleado.sueldoMensualAdministrativo == null
                                      ? null
                                      : _formatoMonedaEmpleado.format(empleado.sueldoMensualAdministrativo! / 100),
                                ),
                                const SizedBox(height: AppSpacing.sm),
                                CampoConsulta(
                                  label: l10n.empleadoCampoBonoMensualAdministrativo,
                                  value: empleado.bonoMensualAdministrativo == null
                                      ? null
                                      : _formatoMonedaEmpleado.format(empleado.bonoMensualAdministrativo! / 100),
                                ),
                              ],
                              const SizedBox(height: AppSpacing.sm),
                              CampoConsulta(label: l10n.empleadoCampoObservaciones, value: empleado.observaciones),
                              const SizedBox(height: AppSpacing.sm),
                              Row(
                                children: [
                                  Expanded(
                                    child: CampoConsulta(
                                      label: l10n.empleadoCampoAntiguedad,
                                      value: l10n.empleadoDetalleAntiguedadAniosMeses(cicloLaboral.antiguedadAnios, cicloLaboral.antiguedadMeses),
                                    ),
                                  ),
                                  Expanded(
                                    child: CampoConsulta(
                                      label: l10n.empleadoCampoDiasLaborados,
                                      value: l10n.empleadoDetalleDiasLaborados(cicloLaboral.diasLaborados),
                                    ),
                                  ),
                                ],
                              ),
                              if (cicloLaboral.fechaProximoAniversario != null) ...[
                                const SizedBox(height: AppSpacing.sm),
                                CampoConsulta(
                                  label: l10n.empleadoCampoProximoAniversario,
                                  value: _formatoFecha.format(cicloLaboral.fechaProximoAniversario!),
                                ),
                              ],
                              if (cancelado) ...[
                                const SizedBox(height: AppSpacing.sm),
                                CampoConsulta(label: l10n.empleadoCampoFechaBaja, value: _formatoFecha.format(empleado.fechaBaja!)),
                                const SizedBox(height: AppSpacing.sm),
                                CampoConsulta(
                                  label: l10n.empleadoCampoMotivoBaja,
                                  value: motivoBajaEmpleadoLabel(l10n, empleado.motivoBaja!),
                                ),
                                const SizedBox(height: AppSpacing.sm),
                                CampoConsulta(label: l10n.empleadoCampoObservacionesBaja, value: empleado.observacionesBaja),
                              ],
                            ],
                          ),
                        ],
                      ),
                      RisegFormSection(
                        title: l10n.empleadoSeccionHistorialLaboral,
                        children: [
                          Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${_formatoFecha.format(empleado.fechaIngreso)} — '
                                    '${cancelado ? _formatoFecha.format(empleado.fechaBaja!) : l10n.empleadoHistorialLaboralActivo}',
                                  ),
                                ),
                                if (cancelado) Text(motivoBajaEmpleadoLabel(l10n, empleado.motivoBaja!), style: AppTypography.caption.copyWith(color: colors.textMuted)),
                              ],
                            ),
                            if (cancelado &&
                                lineaPuestoServicioTurno(
                                      puesto: empleado.puestoNombreBaja,
                                      servicio: empleado.servicioNombreBaja,
                                      turno: empleado.turnoNombreBaja,
                                    ) !=
                                    null)
                              Text(
                                lineaPuestoServicioTurno(
                                  puesto: empleado.puestoNombreBaja,
                                  servicio: empleado.servicioNombreBaja,
                                  turno: empleado.turnoNombreBaja,
                                )!,
                                style: AppTypography.caption.copyWith(color: colors.textMuted),
                              ),
                          ],
                        ),
                      ),
                      for (final periodo in _periodosArchivados)
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text('${_formatoFecha.format(periodo.fechaIngreso)} — ${_formatoFecha.format(periodo.fechaBaja)}'),
                                  ),
                                  Text(motivoBajaEmpleadoLabel(l10n, periodo.motivoBaja), style: AppTypography.caption.copyWith(color: colors.textMuted)),
                                ],
                              ),
                              if (lineaPuestoServicioTurno(puesto: periodo.puestoNombre, servicio: periodo.servicioNombre, turno: periodo.turnoNombre) !=
                                  null)
                                Text(
                                  lineaPuestoServicioTurno(
                                    puesto: periodo.puestoNombre,
                                    servicio: periodo.servicioNombre,
                                    turno: periodo.turnoNombre,
                                  )!,
                                  style: AppTypography.caption.copyWith(color: colors.textMuted),
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
                      // Etapa "Entrega múltiple de Inventario" (corrección de
                      // regresión bloqueante): este encabezado usaba un
                      // `Row([Expanded(Text), Wrap(botones)])` crudo — el
                      // mismo patrón que `RisegSectionHeader` (Etapa 9D) fue
                      // creado para eliminar en todo el proyecto ("solo el
                      // título puede encogerse con `Expanded`, nunca las
                      // acciones"; con el grupo de acciones ancho, el
                      // `Expanded` colapsaba a casi cero y el título se
                      // envolvía letra por letra). Se migra al mismo patrón
                      // ya usado 100 líneas más abajo por "Inventario
                      // asignado", en vez de un ancho fijo/mágico.
                      RisegSectionHeader(
                        title: l10n.empleadoSeccionAsignacionServicio,
                        primaryAction: _asignacionVigente == null
                            ? RisegButton(
                                label: l10n.empleadoBotonAsignarServicio,
                                variant: RisegButtonVariant.ghost,
                                onPressed: _asignarServicio,
                              )
                            : Wrap(
                                spacing: AppSpacing.xs,
                                runSpacing: AppSpacing.xs,
                                children: [
                                  RisegButton(
                                    key: const Key('empleado_boton_ver_servicio'),
                                    label: l10n.empleadoAsignacionVerServicio,
                                    variant: RisegButtonVariant.ghost,
                                    onPressed: () => context.push('/comercial/servicios/${_asignacionVigente!.servicioId}'),
                                  ),
                                  RisegButton(
                                    label: l10n.empleadoBotonActualizarSueldo,
                                    variant: RisegButtonVariant.ghost,
                                    onPressed: _actualizarSueldoAsignacion,
                                  ),
                                  RisegButton(
                                    label: l10n.empleadoBotonCambiarServicio,
                                    variant: RisegButtonVariant.ghost,
                                    onPressed: _cambiarServicio,
                                  ),
                                  RisegButton(
                                    label: l10n.empleadoBotonRetirarServicio,
                                    variant: RisegButtonVariant.ghost,
                                    onPressed: _retirarServicio,
                                  ),
                                  if (esMaestro && _asignacionVigente!.lineaComercialId == null)
                                    RisegButton(
                                      label: l10n.empleadoBotonRegularizarPerfil,
                                      variant: RisegButtonVariant.ghost,
                                      onPressed: _regularizarPerfilAsignacion,
                                    ),
                                ],
                              ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      if (_asignacionVigente == null)
                        Text(l10n.empleadoSinServicioAsignado, style: AppTypography.body.copyWith(color: colors.textMuted))
                      else ...[
                        Text(
                          _serviciosPorId[_asignacionVigente!.servicioId] ?? _asignacionVigente!.servicioId,
                          style: AppTypography.label,
                        ),
                        Text(
                          l10n.empleadoAsignacionDesde(_formatoFecha.format(_asignacionVigente!.fechaInicio)),
                          style: AppTypography.body.copyWith(color: colors.textMuted),
                        ),
                        if (_asignacionVigente!.turnoId != null)
                          Text(
                            _turnosPorId[_asignacionVigente!.turnoId] ?? _asignacionVigente!.turnoId!,
                            style: AppTypography.caption.copyWith(color: colors.textMuted),
                          ),
                        if (_asignacionVigente!.lineaComercialId == null)
                          Text(
                            l10n.empleadoAsignacionSinPerfil,
                            style: AppTypography.caption.copyWith(color: colors.warning),
                          ),
                        if (_sueldoVigente != null)
                          Text(
                            l10n.empleadoAsignacionSueldoBono(
                              _formatoMonedaEmpleado.format(_sueldoVigente!.sueldoMensual / 100),
                              _formatoMonedaEmpleado.format(_sueldoVigente!.bonoMensual / 100),
                            ),
                            style: AppTypography.caption.copyWith(color: colors.textMuted),
                          ),
                      ],
                      if (_historialAsignaciones.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.md),
                        Text(l10n.empleadoSeccionHistorialAsignaciones, style: AppTypography.label),
                        const SizedBox(height: AppSpacing.xs),
                        for (final asignacion in _historialAsignaciones)
                          Padding(
                            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                            child: Text(
                              '${_serviciosPorId[asignacion.servicioId] ?? asignacion.servicioId} — '
                              '${_formatoFecha.format(asignacion.fechaInicio)} '
                              '${asignacion.fechaTermino == null ? l10n.empleadoAsignacionActual : 'al ${_formatoFecha.format(asignacion.fechaTermino!)}'}',
                              style: AppTypography.body.copyWith(color: colors.textMuted),
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
                // Fachada pública de Inventario embebida en Personal (Etapa
                // 11C, frontera de lecturas protegidas) — mismo criterio que
                // Vehículos/Telefonía más abajo.
                if (ref.watch(permissionServiceProvider).hasCode('inventario.ver')) ...[
                  const SizedBox(height: AppSpacing.xl),
                  RisegCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        RisegSectionHeader(
                          title: l10n.asignacionSeccionTitulo,
                          primaryAction: RisegButton(
                            label: l10n.entregarEquipoDialogoTitulo,
                            variant: RisegButtonVariant.secondary,
                            size: RisegButtonSize.compact,
                            onPressed: _entregarEquipo,
                          ),
                          secondaryAction: RisegButton(
                            label: l10n.asignacionBotonAsignar,
                            variant: RisegButtonVariant.ghost,
                            size: RisegButtonSize.compact,
                            onPressed: _asignarInventario,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        if (!hayEquipoAsignado)
                          Text(l10n.asignacionSeccionVacio, style: AppTypography.body.copyWith(color: colors.textMuted))
                        else ...[
                          for (final entrega in entregasOrdenadas)
                            if ((historialPorEntregaId[entrega.id] ?? const <AsignacionData>[]).isNotEmpty) ...[
                              _inventarioGrupoCard(
                                titulo: entrega.folio,
                                subtitulo: l10n.empleadoInventarioEntregaResumen(
                                  _formatoFecha.format(entrega.fechaEntrega),
                                  historialPorEntregaId[entrega.id]!.fold<int>(0, (acc, a) => acc + a.cantidad),
                                  historialPorEntregaId[entrega.id]!.length,
                                ),
                                asignaciones: historialPorEntregaId[entrega.id]!,
                                onGenerarResguardo: _generarResguardo,
                                onAdjuntarResguardo: _adjuntarResguardoFirmado,
                              ),
                              const SizedBox(height: AppSpacing.sm),
                            ],
                          if (individuales.isNotEmpty)
                            _inventarioGrupoCard(
                              titulo: l10n.empleadoInventarioAsignacionesIndividuales,
                              asignaciones: individuales,
                              onGenerarResguardo: _generarResguardo,
                              onAdjuntarResguardo: _adjuntarResguardoFirmado,
                            ),
                        ],
                        if (_resguardos.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.md),
                          Text(l10n.resguardoSeccionTitulo, style: AppTypography.label),
                          const SizedBox(height: AppSpacing.xs),
                          for (final resguardo in _resguardos)
                            Padding(
                              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      _formatoFechaHora.format(resguardo.createdAt),
                                      style: AppTypography.body.copyWith(color: colors.textMuted),
                                    ),
                                  ),
                                  RisegButton(
                                    label: l10n.resguardoBotonAbrir,
                                    variant: RisegButtonVariant.ghost,
                                    size: RisegButtonSize.compact,
                                    onPressed: () => ref.read(attachmentStorageProvider).abrir(resguardo.path),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),
                ],
                // Secciones de otro dominio embebidas aquí (Etapa 11C, frontera
                // de lecturas protegidas) — Vehículos/Telefonía son fachadas
                // públicas que muestran datos reales de esos módulos, así que
                // respetan su propio `modulo.ver` aunque el usuario sí tenga
                // acceso a Personal; a diferencia de una lectura interna de
                // composición (ej. Compras leyendo Artículos), esto es
                // información mostrada directo al usuario.
                // Pendientes de recuperación (schemaVersion 82) — sección
                // propia, nunca mezclada con "equipo asignado": dar de baja
                // a alguien no devuelve su radio.
                if (_inventarioPendiente.isNotEmpty || _vehiculosPendientes.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xl),
                  RisegCard(
                    key: const Key('empleado_pendientes_recuperacion'),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        RisegSectionHeader(title: l10n.empleadoPendientesRecuperacionTitulo),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          l10n.empleadoPendientesRecuperacionAyuda,
                          style: AppTypography.caption.copyWith(color: colors.textMuted),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        for (final asignacion in _inventarioPendiente)
                          Padding(
                            padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    _articulosInventarioPorId[asignacion.articuloId]?.nombre ?? asignacion.articuloId,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                RisegStatusBadge(
                                  label: l10n.empleadoPendienteRecuperacionDesde(
                                    _formatoFecha.format(asignacion.pendienteRecuperacionDesde!),
                                  ),
                                  tone: RisegStatusTone.warning,
                                ),
                              ],
                            ),
                          ),
                        for (final asignacion in _vehiculosPendientes)
                          Padding(
                            padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    l10n.empleadoPendienteRecuperacionVehiculo,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                RisegStatusBadge(
                                  label: l10n.empleadoPendienteRecuperacionDesde(
                                    _formatoFecha.format(asignacion.pendienteRecuperacionDesde!),
                                  ),
                                  tone: RisegStatusTone.warning,
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
                if (ref.watch(permissionServiceProvider).hasCode('vehiculos.ver')) ...[
                  const SizedBox(height: AppSpacing.xl),
                  RisegCard(child: VehiculoAsignadoEmpleadoSection(empleadoId: widget.empleadoId)),
                ],
                if (ref.watch(permissionServiceProvider).hasCode('telefonia.ver')) ...[
                  const SizedBox(height: AppSpacing.xl),
                  RisegCard(child: LineaTelefonicaAsignadaEmpleadoSection(empleadoId: widget.empleadoId)),
                ],
                if (_descuentos.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xl),
                  RisegCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l10n.descuentosPendientesSeccionTitulo, style: AppTypography.heading3.copyWith(color: colors.textPrimary)),
                        const SizedBox(height: AppSpacing.xs),
                        for (final descuento in _descuentos)
                          Padding(
                            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(_formatoMonedaEmpleado.format(descuento.importe / 100), style: AppTypography.label),
                                      Text(
                                        descuento.estatus == EstatusDescuentoInventario.aplicado.name
                                            ? l10n.descuentosPendientesAplicadoDetalle(
                                                _foliosNominaPorDescuento[descuento.id] ?? '—',
                                                descuento.fechaAplicacion != null
                                                    ? _formatoFecha.format(descuento.fechaAplicacion!)
                                                    : '—',
                                              )
                                            : descuento.observaciones ?? l10n.descuentosPendientesAvisoNoAplicado,
                                        style: AppTypography.caption.copyWith(color: colors.textMuted),
                                      ),
                                    ],
                                  ),
                                ),
                                RisegStatusBadge(
                                  label: switch (EstatusDescuentoInventario.values.byName(descuento.estatus)) {
                                    EstatusDescuentoInventario.pendiente => l10n.descuentosPendientesEstadoPendiente,
                                    EstatusDescuentoInventario.aplicado => l10n.descuentosPendientesEstadoAplicado,
                                    EstatusDescuentoInventario.cancelado => l10n.descuentosPendientesEstadoCancelado,
                                  },
                                  tone: switch (EstatusDescuentoInventario.values.byName(descuento.estatus)) {
                                    EstatusDescuentoInventario.pendiente => RisegStatusTone.warning,
                                    EstatusDescuentoInventario.aplicado => RisegStatusTone.success,
                                    EstatusDescuentoInventario.cancelado => RisegStatusTone.neutral,
                                  },
                                ),
                              ],
                            ),
                          ),
                        if (_descuentos.any((d) => d.estatus == EstatusDescuentoInventario.pendiente.name)) ...[
                          const Divider(),
                          Text(
                            l10n.descuentosPendientesTotalPendiente(
                              _formatoMonedaEmpleado.format(
                                _descuentos
                                        .where((d) => d.estatus == EstatusDescuentoInventario.pendiente.name)
                                        .fold<int>(0, (s, d) => s + d.importe) /
                                    100,
                              ),
                            ),
                            style: AppTypography.label.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
                if (ref.watch(permissionServiceProvider).hasCode('descuentos.ver') &&
                    (_descuentosProgramados.isNotEmpty || empleado.estatus == 'baja')) ...[
                  const SizedBox(height: AppSpacing.xl),
                  RisegCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                l10n.empleadoDescuentosCardTitulo,
                                style: AppTypography.heading3.copyWith(color: colors.textPrimary),
                              ),
                            ),
                            RisegButton(
                              label: l10n.empleadoDescuentosBotonRegistrar,
                              variant: RisegButtonVariant.ghost,
                              size: RisegButtonSize.compact,
                              onPressed: () async {
                                final ok = await mostrarDialogoRegistrarDescuentoProgramado(
                                  context,
                                  ref,
                                  empleadoIdPreseleccionado: widget.empleadoId,
                                );
                                if (ok) await _cargar();
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        if (empleado.estatus == 'baja' &&
                            _descuentosProgramados.any((d) => d.estatus == 'activo' && d.saldoPendiente > 0))
                          Padding(
                            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                            child: Container(
                              padding: const EdgeInsets.all(AppSpacing.sm),
                              decoration: BoxDecoration(color: colors.errorBg, borderRadius: AppRadius.mdRadius),
                              child: Row(
                                children: [
                                  Icon(Icons.warning_amber_outlined, color: colors.error, size: AppSizes.iconSm),
                                  const SizedBox(width: AppSpacing.xs),
                                  Expanded(
                                    child: Text(
                                      l10n.empleadoDescuentosAvisoBajaConSaldo,
                                      style: AppTypography.body.copyWith(color: colors.error),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        CampoConsulta(
                          label: l10n.empleadoDescuentosSaldoPendiente,
                          value: _formatoMonedaEmpleado.format(
                            _descuentosProgramados
                                    .where((d) => d.estatus == 'activo')
                                    .fold<int>(0, (s, d) => s + d.saldoPendiente) /
                                100,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        CampoConsulta(
                          label: l10n.empleadoDescuentosProximoDescuento,
                          value: _proximoDescuentoGlobal == null
                              ? l10n.empleadoDescuentosSinActivos
                              : l10n.empleadoDescuentosProximoDescuentoDetalle(
                                  _formatoMonedaEmpleado.format(_proximoDescuentoGlobal!.importeProgramado / 100),
                                  _formatoFecha.format(_proximoDescuentoGlobal!.fechaProgramada),
                                ),
                        ),
                        if (_descuentosProgramados.any((d) => d.estatus == 'activo')) ...[
                          const SizedBox(height: AppSpacing.sm),
                          for (final d in _descuentosProgramados.where((d) => d.estatus == 'activo'))
                            Padding(
                              padding: const EdgeInsets.only(top: AppSpacing.xxs),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${d.folio} · ${descuentoProgramadoTipoLabel(l10n, d.tipo)}',
                                      style: AppTypography.body,
                                    ),
                                  ),
                                  Text(_formatoMonedaEmpleado.format(d.saldoPendiente / 100), style: AppTypography.body),
                                ],
                              ),
                            ),
                        ],
                        const SizedBox(height: AppSpacing.sm),
                        RisegButton(
                          label: l10n.empleadoDescuentosBotonVerHistorial,
                          variant: RisegButtonVariant.ghost,
                          size: RisegButtonSize.compact,
                          onPressed: () => context.go('/personal/descuentos'),
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
                      Text(l10n.empleadoSeccionEscolaridad, style: AppTypography.heading3.copyWith(color: colors.textPrimary)),
                      const SizedBox(height: AppSpacing.sm),
                      CampoConsulta(
                        label: l10n.empleadoCampoNivelEstudios,
                        value: empleado.nivelEstudios == null ? null : empleadoNivelEstudiosLabel(l10n, empleado.nivelEstudios!),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      CampoConsulta(label: l10n.empleadoCampoObservacionesEscolaridad, value: empleado.observacionesEscolaridad),
                      const SizedBox(height: AppSpacing.lg),
                      Text(l10n.empleadoSeccionExperiencia, style: AppTypography.heading3.copyWith(color: colors.textPrimary)),
                      const SizedBox(height: AppSpacing.sm),
                      CampoConsulta(
                        label: l10n.empleadoDetalleCampoExperiencia,
                        value: empleado.mesesExperienciaAdicionales == null
                            ? l10n.empleadoDetalleExperienciaAnios(empleado.aniosExperienciaSeguridad)
                            : l10n.empleadoDetalleExperienciaAniosMeses(
                                empleado.aniosExperienciaSeguridad,
                                empleado.mesesExperienciaAdicionales!,
                              ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      CampoConsulta(label: l10n.empleadoCampoUltimoPuesto, value: empleado.ultimoPuestoDesempenado),
                      const SizedBox(height: AppSpacing.sm),
                      CampoConsulta(label: l10n.empleadoCampoResumenExperiencia, value: empleado.resumenExperiencia),
                      const SizedBox(height: AppSpacing.sm),
                      CampoConsulta(label: l10n.empleadoCampoObservacionesExperiencia, value: empleado.observacionesExperiencia),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                RisegCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.empleadoSeccionEvaluaciones, style: AppTypography.heading3.copyWith(color: colors.textPrimary)),
                      const SizedBox(height: AppSpacing.md),
                      Row(
                        children: [
                          Expanded(
                            child: Text(l10n.empleadoSeccionPerfilPsicologico, style: AppTypography.label),
                          ),
                          RisegButton(
                            label: empleado.fechaEvaluacionPsicologica == null
                                ? l10n.evaluacionEmpleadoBotonRegistrar
                                : l10n.empleadoDetalleBotonEditar,
                            variant: RisegButtonVariant.ghost,
                            onPressed: _registrarPerfilPsicologico,
                          ),
                        ],
                      ),
                      if (empleado.fechaEvaluacionPsicologica == null)
                        RisegStatusBadge(label: l10n.evaluacionEmpleadoPendiente, tone: RisegStatusTone.warning)
                      else ...[
                        CampoConsulta(
                          label: l10n.evaluacionEmpleadoCampoFecha,
                          value: _formatoFecha.format(empleado.fechaEvaluacionPsicologica!),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        CampoConsulta(label: l10n.perfilPsicologicoEmpleadoCampoResumen, value: empleado.resumenPsicologico),
                        const SizedBox(height: AppSpacing.sm),
                        CampoConsulta(label: l10n.evaluacionEmpleadoCampoObservaciones, value: empleado.observacionesPsicologico),
                      ],
                      const SizedBox(height: AppSpacing.lg),
                      Row(
                        children: [
                          Expanded(
                            child: Text(l10n.empleadoSeccionEstudioSocioeconomico, style: AppTypography.label),
                          ),
                          RisegButton(
                            label: empleado.fechaEstudioSocioeconomico == null
                                ? l10n.evaluacionEmpleadoBotonRegistrar
                                : l10n.empleadoDetalleBotonEditar,
                            variant: RisegButtonVariant.ghost,
                            onPressed: _registrarEstudioSocioeconomico,
                          ),
                        ],
                      ),
                      if (empleado.fechaEstudioSocioeconomico == null)
                        RisegStatusBadge(label: l10n.evaluacionEmpleadoPendiente, tone: RisegStatusTone.warning)
                      else ...[
                        CampoConsulta(
                          label: l10n.evaluacionEmpleadoCampoFecha,
                          value: _formatoFecha.format(empleado.fechaEstudioSocioeconomico!),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        CampoConsulta(
                          label: l10n.estudioSocioeconomicoEmpleadoCampoResumen,
                          value: empleado.resumenEstudioSocioeconomico,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        CampoConsulta(
                          label: l10n.evaluacionEmpleadoCampoObservaciones,
                          value: empleado.observacionesEstudioSocioeconomico,
                        ),
                      ],
                      const SizedBox(height: AppSpacing.lg),
                      Row(
                        children: [
                          Expanded(
                            child: Text(l10n.empleadoSeccionAntidoping, style: AppTypography.label),
                          ),
                          RisegButton(
                            label: empleado.fechaAntidoping == null
                                ? l10n.evaluacionEmpleadoBotonRegistrar
                                : l10n.empleadoDetalleBotonEditar,
                            variant: RisegButtonVariant.ghost,
                            onPressed: _registrarAntidoping,
                          ),
                        ],
                      ),
                      if (empleado.fechaAntidoping == null)
                        RisegStatusBadge(label: l10n.evaluacionEmpleadoPendiente, tone: RisegStatusTone.warning)
                      else ...[
                        CampoConsulta(
                          label: l10n.evaluacionEmpleadoCampoFecha,
                          value: _formatoFecha.format(empleado.fechaAntidoping!),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Wrap(
                          spacing: AppSpacing.xs,
                          runSpacing: AppSpacing.xs,
                          children: [
                            if (empleado.resultadoAmp != null)
                              RisegStatusBadge(
                                label: '${l10n.antidopingEmpleadoCampoAmp}: ${resultadoSustanciaAntidopingLabel(l10n, empleado.resultadoAmp!)}',
                                tone: resultadoSustanciaAntidopingTono(empleado.resultadoAmp!),
                              ),
                            if (empleado.resultadoBzd != null)
                              RisegStatusBadge(
                                label: '${l10n.antidopingEmpleadoCampoBzd}: ${resultadoSustanciaAntidopingLabel(l10n, empleado.resultadoBzd!)}',
                                tone: resultadoSustanciaAntidopingTono(empleado.resultadoBzd!),
                              ),
                            if (empleado.resultadoCoc != null)
                              RisegStatusBadge(
                                label: '${l10n.antidopingEmpleadoCampoCoc}: ${resultadoSustanciaAntidopingLabel(l10n, empleado.resultadoCoc!)}',
                                tone: resultadoSustanciaAntidopingTono(empleado.resultadoCoc!),
                              ),
                            if (empleado.resultadoMet != null)
                              RisegStatusBadge(
                                label: '${l10n.antidopingEmpleadoCampoMet}: ${resultadoSustanciaAntidopingLabel(l10n, empleado.resultadoMet!)}',
                                tone: resultadoSustanciaAntidopingTono(empleado.resultadoMet!),
                              ),
                            if (empleado.resultadoOpi != null)
                              RisegStatusBadge(
                                label: '${l10n.antidopingEmpleadoCampoOpi}: ${resultadoSustanciaAntidopingLabel(l10n, empleado.resultadoOpi!)}',
                                tone: resultadoSustanciaAntidopingTono(empleado.resultadoOpi!),
                              ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        CampoConsulta(label: l10n.evaluacionEmpleadoCampoObservaciones, value: empleado.observacionesAntidoping),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                RisegCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(l10n.empleadoSeccionDocumentacion, style: AppTypography.heading3.copyWith(color: colors.textPrimary)),
                          ),
                          RisegButton(label: l10n.empleadoDetalleBotonAdjuntar, variant: RisegButtonVariant.ghost, onPressed: _adjuntarDocumento),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      if (_documentos.isEmpty)
                        Text(l10n.empleadoDetalleDocumentosSinDocumentos, style: AppTypography.body.copyWith(color: colors.textMuted))
                      else
                        for (final documento in _documentos)
                          Padding(
                            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${categoriaDocumentoEmpleadoLabel(l10n, documento.categoria ?? 'otro')} · ${documento.originalFileName}',
                                  ),
                                ),
                                RisegButton(
                                  label: l10n.agendaAdjuntoBotonAbrir,
                                  variant: RisegButtonVariant.ghost,
                                  onPressed: () => ref.read(attachmentStorageProvider).abrir(documento.path),
                                ),
                              ],
                            ),
                          ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                RisegCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(l10n.fichaTecnicaSeccionTitulo, style: AppTypography.heading3.copyWith(color: colors.textPrimary)),
                          ),
                          RisegButton(
                            label: l10n.fichaTecnicaBotonGenerar,
                            variant: RisegButtonVariant.ghost,
                            onPressed: _procesando ? null : _generarFichaTecnica,
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      if (_fichasTecnicas.isEmpty)
                        Text(l10n.fichaTecnicaSinFichas, style: AppTypography.body.copyWith(color: colors.textMuted))
                      else
                        for (final ficha in _fichasTecnicas)
                          Padding(
                            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text('${ficha.folio} · ${_formatoFechaHora.format(ficha.createdAt)}'),
                                ),
                                RisegButton(
                                  label: l10n.agendaAdjuntoBotonAbrir,
                                  variant: RisegButtonVariant.ghost,
                                  onPressed: () {
                                    final ruta = _fichaTecnicaRutasPorAttachmentId[ficha.attachmentId];
                                    if (ruta != null) ref.read(attachmentStorageProvider).abrir(ruta);
                                  },
                                ),
                              ],
                            ),
                          ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                RisegCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.empleadoSeccionHistorial, style: AppTypography.heading3.copyWith(color: colors.textPrimary)),
                      const SizedBox(height: AppSpacing.xs),
                      if (_eventos.isEmpty)
                        Text(l10n.complementoDetalleHistorialSinEventos, style: AppTypography.body.copyWith(color: colors.textMuted))
                      else
                        for (final evento in _eventos)
                          Padding(
                            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Hallazgo real (prueba responsive de la Etapa
                                // "Entrega múltiple de Inventario"): un `Row`
                                // crudo con 2 `Text` desbordaba en anchos
                                // angostos cuando fecha+etiqueta no cabían
                                // juntos — mismo criterio que el resto de esta
                                // pantalla, `Wrap` en vez de `Row` crudo.
                                Wrap(
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  spacing: AppSpacing.xs,
                                  children: [
                                    Text(_formatoFechaHora.format(evento.fechaHora), style: AppTypography.caption.copyWith(color: colors.textMuted)),
                                    Text(_eventoLabel(l10n, evento.tipoEvento), style: AppTypography.label),
                                  ],
                                ),
                                if (evento.observacion != null && evento.observacion!.trim().isNotEmpty)
                                  Text(evento.observacion!, style: AppTypography.body.copyWith(color: colors.textMuted)),
                              ],
                            ),
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
}

String empleadoSexoLabelDetalle(AppLocalizations l10n, String valor) => empleadoSexoLabel(l10n, valor);

String empleadoEstadoCivilLabelDetalle(AppLocalizations l10n, String valor) => empleadoEstadoCivilLabel(l10n, valor);
