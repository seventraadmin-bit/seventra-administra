import 'dart:typed_data';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/tables/attachment_table.dart';
import 'package:riseg_one/core/permissions/authorization_service.dart';
import 'package:riseg_one/features/dashboard/presentation/dashboard_controller.dart';
import 'package:riseg_one/features/finanzas/presentation/cuentas_por_cobrar/cuentas_por_cobrar_controller.dart';
import 'package:riseg_one/features/finanzas/presentation/planeacion/planeacion_financiera_controller.dart';
import 'package:riseg_one/features/finanzas/presentation/resumen/resumen_financiero_controller.dart';
import 'package:riseg_one/features/organizacion/data/tables/documento_por_emitir_table.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/corregir_ajuste_historico_documento_por_emitir_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/actualizar_ajuste_manual_documento_por_emitir_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/adjuntar_archivo_documento_por_emitir_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/cambiar_estatus_documento_por_emitir_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/corregir_datos_emision_documento_por_emitir_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_documento_manual_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/documento_por_emitir_detalle.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/documento_por_emitir_requiere_accion.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/generar_agenda_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/generar_recibo_pago_pdf_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/registrar_emision_documento_por_emitir_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/registrar_envio_documento_por_emitir_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/reemplazar_archivo_documento_por_emitir_usecase.dart';
import 'package:riseg_one/features/usuarios/usuarios_providers.dart';

import '../../organizacion_providers.dart';
import 'agenda_state.dart';
import 'invalidacion_documentos_por_emitir.dart';
import 'total_esperado_documento.dart';

part 'agenda_controller.g.dart';

/// Controlador de la Agenda de documentos por emitir (Etapa 4I.1) —
/// mismo diseño que `ServiciosListController`, con acciones propias de
/// generación y ciclo de vida.
@riverpod
class AgendaController extends _$AgendaController {
  @override
  AgendaState build() {
    Future.microtask(_cargar);
    return const AgendaState();
  }

  Future<void> _cargar() async {
    state = state.copyWith(cargando: true, errorCarga: null);
    try {
      final documentos = state.modoPendientes ? await _cargarPendientes() : await _cargarDelMes();
      // UNA consulta más para todas las líneas, no una por documento: el
      // total esperado necesita el tratamiento fiscal de cada línea.
      final lineasPorDocumento = await ref.read(documentoPorEmitirRepositoryProvider).lineasPorDocumentos(
            [for (final d in documentos) d.id],
          );

      // Derivado en cada carga desde los snapshots ya guardados: no se
      // persiste, no se recalcula historia, no se completa nada por
      // inferencia. Un documento sin total comparable sencillamente no
      // entra al mapa.
      final totales = <String, int>{};
      for (final documento in documentos) {
        final total = totalEsperadoDeDocumento(
          documento,
          lineasPorDocumento[documento.id] ?? const <DocumentoPorEmitirLineaData>[],
        );
        if (total != null) totales[documento.id] = total;
      }

      state = state.copyWith(
        cargando: false,
        documentos: documentos,
        totalEsperadoPorDocumento: totales,
        errorCarga: null,
      );
    } catch (e) {
      state = state.copyWith(cargando: false, errorCarga: e.toString());
    }
  }

  Future<List<DocumentoPorEmitirData>> _cargarDelMes() {
    return ref.read(documentoPorEmitirRepositoryProvider).listar(
          rangoInicio: state.rangoInicio,
          rangoFin: state.rangoFin,
          clienteId: state.clienteId,
          servicioId: state.servicioId,
          tipoDocumento: state.tipoDocumento,
          estatus: state.estatus,
        );
  }

  /// El conjunto accionable, sin ventana de fechas.
  ///
  /// Reutiliza `documentoPorEmitirRequiereAccion` —la MISMA regla que
  /// alimentan la alerta del Dashboard y el Centro de notificaciones— en vez
  /// de reinventar "pendiente" con una condición propia. Por eso entrar
  /// desde la alerta muestra exactamente los documentos que la alerta
  /// contaba, incluidos los de meses anteriores, y NO los pendientes cuya
  /// fecha programada todavía no llega: ésos siguen siendo asunto de la
  /// vista mensual.
  ///
  /// Dos consultas, no una por documento: mismo criterio que
  /// `ObtenerNotificacionesDocumentosPorEmitirUseCase`.
  Future<List<DocumentoPorEmitirData>> _cargarPendientes() async {
    final repo = ref.read(documentoPorEmitirRepositoryProvider);
    final accionables = <DocumentoPorEmitirData>[];
    for (final estatus in [
      EstatusDocumentoPorEmitir.pendiente.name,
      EstatusDocumentoPorEmitir.enPreparacion.name,
    ]) {
      accionables.addAll(await repo.listar(
        estatus: estatus,
        clienteId: state.clienteId,
        servicioId: state.servicioId,
        tipoDocumento: state.tipoDocumento,
      ));
    }

    final hoy = DateTime.now();
    final resultado = accionables.where((d) => documentoPorEmitirRequiereAccion(d, hoy)).toList();

    // Lo más atrasado primero: es el orden en el que se trabaja una lista
    // de pendientes, no el orden de captura.
    resultado.sort((a, b) => a.fechaEmisionProgramada!.compareTo(b.fechaEmisionProgramada!));
    return resultado;
  }

  /// Entra al modo Pendientes. El estatus se limpia: en este conjunto un
  /// filtro por "Procesado/Aceptado" no puede dar nada, y ofrecerlo sería
  /// prometer una combinación imposible.
  Future<void> activarModoPendientes() async {
    if (state.modoPendientes) return;
    state = state.copyWith(modoPendientes: true, limpiarEstatus: true);
    await _cargar();
  }

  /// Vuelve a la vista mensual, al mes que estuviera seleccionado.
  Future<void> volverAVistaMensual() async {
    if (!state.modoPendientes) return;
    state = state.copyWith(modoPendientes: false);
    await _cargar();
  }

  Future<void> reintentarCarga() => _cargar();

  Future<void> aplicarFiltros({
    DateTime? rangoInicio,
    DateTime? rangoFin,
    String? clienteId,
    String? servicioId,
    String? tipoDocumento,
    String? estatus,
    bool limpiarClienteId = false,
    bool limpiarServicioId = false,
    bool limpiarTipoDocumento = false,
    bool limpiarEstatus = false,
  }) async {
    state = state.copyWith(
      rangoInicio: rangoInicio,
      rangoFin: rangoFin,
      clienteId: clienteId,
      servicioId: servicioId,
      tipoDocumento: tipoDocumento,
      estatus: estatus,
      limpiarClienteId: limpiarClienteId,
      limpiarServicioId: limpiarServicioId,
      limpiarTipoDocumento: limpiarTipoDocumento,
      limpiarEstatus: limpiarEstatus,
    );
    await _cargar();
  }

  /// Genera los documentos del periodo. Crea pendientes nuevos, así que el
  /// Dashboard y Notificaciones tienen más que contar en cuanto termina.
  Future<GenerarAgendaResultado?> generar({String? servicioId, String? clienteId}) async {
    if (state.generando) return null;
    state = state.copyWith(generando: true);

    // `GenerarAgendaResultado` no es un tipo sellado (nunca falla por
    // reglas de negocio, siempre informa creados/ya existían) — la
    // frontera de autorización usa `null` como su propio "no
    // autorizado", mismo criterio que `ArchivarContactoUseCase`.
    final resultado = await autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'agendaComercial.crear',
      () => ref.read(generarAgendaUseCaseProvider).ejecutar(
            rangoInicio: state.rangoInicio,
            rangoFin: state.rangoFin,
            servicioId: servicioId,
            clienteId: clienteId,
          ),
      (mensaje) => null,
    );

    await _cargar();
    ref.invalidarConsumidoresDeDocumentosPorEmitir();
    state = state.copyWith(generando: false);
    return resultado;
  }

  Future<CrearDocumentoManualResultado?> crearManual({
    required String clienteId,
    required List<String> servicioIds,
    required DateTime periodoInicio,
    required DateTime periodoFin,
    String? entidadFiscalId,
  }) async {
    if (state.generando) return null;
    state = state.copyWith(generando: true);

    final resultado = await autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'agendaComercial.crear',
      () => ref.read(crearDocumentoManualUseCaseProvider).ejecutar(
            clienteId: clienteId,
            servicioIds: servicioIds,
            periodoInicio: periodoInicio,
            periodoFin: periodoFin,
            entidadFiscalId: entidadFiscalId,
          ),
      CrearDocumentoManualErrorInesperado.new,
    );

    if (resultado is CrearDocumentoManualExitoso) {
      await _cargar();
      // Un documento manual nace pendiente: entra al conteo del Dashboard
      // y del Centro de notificaciones desde este mismo instante.
      ref.invalidarConsumidoresDeDocumentosPorEmitir();
    }
    state = state.copyWith(generando: false);
    return resultado;
  }

  Future<CambiarEstatusDocumentoPorEmitirResultado?> cambiarEstatus({
    required String documentoPorEmitirId,
    required EstatusDocumentoPorEmitir nuevo,
    String? motivo,
  }) async {
    final resultado = await autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'agendaComercial.corregir',
      () => ref.read(cambiarEstatusDocumentoPorEmitirUseCaseProvider).ejecutar(
            documentoPorEmitirId: documentoPorEmitirId,
            nuevo: nuevo,
            motivo: motivo,
          ),
      CambiarEstatusDocumentoPorEmitirErrorInesperado.new,
    );
    if (resultado is CambiarEstatusDocumentoPorEmitirExitoso) {
      await _cargar();
      // Cualquier transición puede sacar (o meter) el documento del
      // conjunto accionable: a `emitido`, `cancelado` o `noRequerido` deja
      // de contar; volver a `enPreparacion` vuelve a contar.
      ref.invalidarConsumidoresDeDocumentosPorEmitir();
      // La transición a `procesadoAceptado` crea la Cuenta por cobrar
      // en la misma transacción (Etapa 4J.1, Resolución A) —
      // `cuentasPorCobrarControllerProvider` es un provider ajeno a
      // Agenda que nunca se enteraba de esta CxC nueva, y el listado
      // de Finanzas → Cuentas por cobrar no la mostraba hasta cambiar
      // de pestaña (Etapa 15, hallazgo real). Ninguna otra transición
      // de estatus toca `CuentaPorCobrar`, así que la invalidación se
      // limita a este caso — nunca una recarga global.
      if (nuevo == EstatusDocumentoPorEmitir.procesadoAceptado) {
        ref.invalidate(cuentasPorCobrarControllerProvider);
        // Etapa 19C/19D: la CxC nueva también cambia "Por cobrar"/
        // "Próximos compromisos" del Resumen financiero y el
        // calendario de Planeación — mismos providers ajenos, mismo
        // criterio.
        ref.invalidate(resumenFinancieroControllerProvider);
        ref.invalidate(planeacionFinancieraControllerProvider);
        // Etapa 20 (hueco real encontrado): el Dashboard lee la misma
        // CuentaPorCobrar para Cobranza/"Requiere atención" — sin esto
        // quedaba stale hasta un cambio de pestaña ajeno.
        ref.invalidate(dashboardControllerProvider);
      }
    }
    return resultado;
  }

  Future<ActualizarAjusteManualDocumentoPorEmitirResultado?> actualizarAjusteManual({
    required String documentoPorEmitirId,
    int? ajusteManual,
    String? motivoAjuste,
  }) async {
    final resultado = await autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'agendaComercial.corregir',
      () => ref.read(actualizarAjusteManualDocumentoPorEmitirUseCaseProvider).ejecutar(
            documentoPorEmitirId: documentoPorEmitirId,
            ajusteManual: ajusteManual,
            motivoAjuste: motivoAjuste,
          ),
      ActualizarAjusteManualDocumentoPorEmitirErrorInesperado.new,
    );
    if (resultado is ActualizarAjusteManualDocumentoPorEmitirExitoso) {
      await _cargar();
    }
    return resultado;
  }

  /// Corrección Maestro del ajuste de un documento ya emitido. Recarga la
  /// Agenda igual que el ajuste normal: el importe esperado del renglón y
  /// el resumen del periodo se derivan de este mismo estado.
  Future<CorregirAjusteHistoricoDocumentoPorEmitirResultado?> corregirAjusteHistorico({
    required String documentoPorEmitirId,
    required String motivoCorreccion,
    int? ajusteManual,
    String? motivoAjuste,
  }) async {
    final resultado = await ref.read(corregirAjusteHistoricoDocumentoPorEmitirAutorizadoProvider)(
      documentoPorEmitirId: documentoPorEmitirId,
      motivoCorreccion: motivoCorreccion,
      ajusteManual: ajusteManual,
      motivoAjuste: motivoAjuste,
    );
    if (resultado is CorregirAjusteHistoricoDocumentoPorEmitirExitoso) {
      await _cargar();
    }
    return resultado;
  }

  Future<DocumentoPorEmitirDetalle?> obtenerDetalle(String documentoPorEmitirId) {
    return ref.read(documentoPorEmitirRepositoryProvider).obtenerDetalle(documentoPorEmitirId);
  }

  Future<RegistrarEmisionDocumentoPorEmitirResultado?> registrarEmision({
    required String documentoPorEmitirId,
    required String folioDocumento,
    String? uuid,
    required DateTime fechaEmisionReal,
    required int importeEmitido,
    String? observacionesEmision,
  }) async {
    final resultado = await autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'agendaComercial.corregir',
      () => ref.read(registrarEmisionDocumentoPorEmitirUseCaseProvider).ejecutar(
            documentoPorEmitirId: documentoPorEmitirId,
            folioDocumento: folioDocumento,
            uuid: uuid,
            fechaEmisionReal: fechaEmisionReal,
            importeEmitido: importeEmitido,
            observacionesEmision: observacionesEmision,
          ),
      RegistrarEmisionDocumentoPorEmitirErrorInesperado.new,
    );
    if (resultado is RegistrarEmisionDocumentoPorEmitirExitoso) {
      await _cargar();
      // El caso del hallazgo: emitir es justo lo que saca al documento de
      // "Documentos por emitir pendientes", y era la única transición que
      // no avisaba a nadie fuera de la Agenda.
      ref.invalidarConsumidoresDeDocumentosPorEmitir();
    }
    return resultado;
  }

  Future<CorregirDatosEmisionDocumentoPorEmitirResultado?> corregirDatosEmision({
    required String documentoPorEmitirId,
    required String motivo,
    String? folioDocumento,
    String? uuid,
    DateTime? fechaEmisionReal,
    int? importeEmitido,
    String? observacionesEmision,
  }) async {
    final resultado = await autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'agendaComercial.corregir',
      () => ref.read(corregirDatosEmisionDocumentoPorEmitirUseCaseProvider).ejecutar(
            documentoPorEmitirId: documentoPorEmitirId,
            motivo: motivo,
            folioDocumento: folioDocumento,
            uuid: uuid,
            fechaEmisionReal: fechaEmisionReal,
            importeEmitido: importeEmitido,
            observacionesEmision: observacionesEmision,
          ),
      CorregirDatosEmisionDocumentoPorEmitirErrorInesperado.new,
    );
    if (resultado is CorregirDatosEmisionDocumentoPorEmitirExitoso) {
      await _cargar();
    }
    return resultado;
  }

  Future<RegistrarEnvioDocumentoPorEmitirResultado?> registrarEnvio({
    required String documentoPorEmitirId,
    required DateTime fechaEnvio,
    List<String> correos = const [],
    String? observacionesEnvio,
  }) async {
    final resultado = await autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'agendaComercial.corregir',
      () => ref.read(registrarEnvioDocumentoPorEmitirUseCaseProvider).ejecutar(
            documentoPorEmitirId: documentoPorEmitirId,
            fechaEnvio: fechaEnvio,
            correos: correos,
            observacionesEnvio: observacionesEnvio,
          ),
      RegistrarEnvioDocumentoPorEmitirErrorInesperado.new,
    );
    if (resultado is RegistrarEnvioDocumentoPorEmitirExitoso) {
      await _cargar();
    }
    return resultado;
  }

  /// Correos ya utilizados en un envío previo, o el snapshot de la
  /// Configuración de cobro al generar si nunca se ha enviado — insumo
  /// para prellenar el formulario de envío (Resolución 8 de Marlon:
  /// precargados pero editables).
  Future<List<String>> obtenerCorreosSugeridosParaEnvio(String documentoPorEmitirId) async {
    final repo = ref.read(documentoPorEmitirRepositoryProvider);
    final correosEnvio = await repo.listarCorreosEnvio(documentoPorEmitirId);
    if (correosEnvio.isNotEmpty) return correosEnvio;

    final detalle = await repo.obtenerDetalle(documentoPorEmitirId);
    return detalle?.correos ?? const [];
  }

  Future<AdjuntarArchivoDocumentoPorEmitirResultado> adjuntarArchivo({
    required String documentoPorEmitirId,
    required CategoriaAdjuntoDocumentoPorEmitir categoria,
    required String sourceFilePath,
    required String originalFileName,
    required String mimeType,
  }) async {
    final resultado = await autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'agendaComercial.corregir',
      () => ref.read(adjuntarArchivoDocumentoPorEmitirUseCaseProvider).ejecutar(
            documentoPorEmitirId: documentoPorEmitirId,
            categoria: categoria,
            sourceFilePath: sourceFilePath,
            originalFileName: originalFileName,
            mimeType: mimeType,
          ),
      AdjuntarArchivoDocumentoPorEmitirErrorInesperado.new,
    );
    if (resultado is AdjuntarArchivoDocumentoPorEmitirExitoso) {
      await _cargar();
    }
    return resultado;
  }

  Future<ReemplazarArchivoDocumentoPorEmitirResultado> reemplazarArchivo({
    required String documentoPorEmitirId,
    required String attachmentAnteriorId,
    required CategoriaAdjuntoDocumentoPorEmitir categoria,
    required String sourceFilePath,
    required String originalFileName,
    required String mimeType,
    String? motivo,
  }) async {
    final resultado = await autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'agendaComercial.corregir',
      () => ref.read(reemplazarArchivoDocumentoPorEmitirUseCaseProvider).ejecutar(
            documentoPorEmitirId: documentoPorEmitirId,
            attachmentAnteriorId: attachmentAnteriorId,
            categoria: categoria,
            sourceFilePath: sourceFilePath,
            originalFileName: originalFileName,
            mimeType: mimeType,
            motivo: motivo,
          ),
      ReemplazarArchivoDocumentoPorEmitirErrorInesperado.new,
    );
    if (resultado is ReemplazarArchivoDocumentoPorEmitirExitoso) {
      await _cargar();
    }
    return resultado;
  }

  Future<List<AttachmentData>> listarAdjuntosActivos(String documentoPorEmitirId, {String? categoria}) {
    return ref
        .read(attachmentRepositoryProvider)
        .listarActivosPorDocumentoPorEmitir(documentoPorEmitirId, categoria: categoria);
  }

  /// Versiones anteriores archivadas — solo se consultan explícitamente
  /// desde el historial (Resolución 6 de Marlon), nunca en el listado
  /// normal de adjuntos.
  Future<List<AttachmentData>> listarAdjuntosArchivados(String documentoPorEmitirId) {
    return ref.read(attachmentRepositoryProvider).listarArchivadosPorDocumentoPorEmitir(documentoPorEmitirId);
  }

  Future<void> abrirArchivo(String path) {
    return ref.read(attachmentStorageProvider).abrir(path);
  }

  /// Genera el PDF administrativo del Recibo de pago y lo abre — acción
  /// de solo lectura sobre datos ya visibles en el detalle, sin nueva
  /// frontera de autorización (mismo criterio que las exportaciones de
  /// Reportes, que tampoco pasan por `autorizarUseCase`). `logoFallbackBytes`
  /// ya viene resuelto por la UI (`rootBundle.load`, Etapa 15) — este
  /// controlador no importa Flutter, solo lo reenvía.
  Future<GenerarReciboPagoPdfResultado> generarReciboPagoPdf(
    String documentoPorEmitirId, {
    Uint8List? logoFallbackBytes,
  }) {
    return ref.read(generarReciboPagoPdfUseCaseProvider).ejecutar(
          documentoPorEmitirId: documentoPorEmitirId,
          logoFallbackBytes: logoFallbackBytes,
        );
  }
}
