import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/finanzas/data/tables/complemento_pago_table.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/adjuntar_archivo_complemento_pago_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/cancelar_complemento_pago_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/corregir_complemento_pago_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/obtener_complementos_pendientes_usecase.dart';
import 'package:riseg_one/core/permissions/authorization_service.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';
import 'package:riseg_one/features/usuarios/usuarios_providers.dart';

import '../../../notificaciones/presentation/notificaciones_controller.dart';
import '../../../organizacion/organizacion_providers.dart';
import '../../finanzas_providers.dart';
import 'complementos_state.dart';

part 'complementos_controller.g.dart';

/// Controlador del listado de Complementos de pago (Etapa 4J.3) —
/// mismo diseño que `PagosController`.
@riverpod
class ComplementosController extends _$ComplementosController {
  @override
  ComplementosState build() {
    Future.microtask(_cargar);
    return const ComplementosState();
  }

  /// Usuario autenticado que ejecuta la operación (Etapa 11D) — mismo
  /// criterio que `UsuariosController._actorUsuarioId`.
  String? get _actorUsuarioId => ref.read(sesionControllerProvider)?.usuarioId;

  /// Una sola proyección alimenta las cuatro vistas — pendientes y
  /// registrados salen del mismo barrido en lote
  /// (`ObtenerComplementosPendientesUseCase`), que a su vez reutiliza
  /// `complemento_pago_derivado.dart`. La pantalla nunca reimplementa
  /// la fórmula de "pendiente", ni guarda un booleano cacheado.
  Future<void> _cargar() async {
    state = state.copyWith(cargando: true, errorCarga: null);
    try {
      final proyeccion = await ref.read(obtenerComplementosPendientesUseCaseProvider).ejecutar(
            clienteId: state.clienteId,
          );

      final clientes = await ref.read(clienteRepositoryProvider).listarActivos();
      final nombrePorCliente = {for (final c in clientes) c.id: c.nombreComercial};

      final visibles = switch (state.vista) {
        VistaComplementos.pendientes => const <ComplementoConContexto>[],
        VistaComplementos.registrados => proyeccion.registrados
            .where((c) => EstatusComplementoPago.values.byName(c.complemento.estatus) == EstatusComplementoPago.registrado)
            .toList(),
        VistaComplementos.cancelados => proyeccion.registrados
            .where((c) => EstatusComplementoPago.values.byName(c.complemento.estatus) == EstatusComplementoPago.cancelado)
            .toList(),
        VistaComplementos.todos => proyeccion.registrados,
      };

      state = state.copyWith(
        cargando: false,
        complementos: visibles,
        // El contador de pendientes se mantiene correcto en cualquier
        // vista: es la pregunta que la pantalla debe poder responder
        // siempre.
        pendientes: proyeccion.pendientes,
        contextoPorComplemento: {for (final c in proyeccion.registrados) c.complemento.id: c},
        nombrePorCliente: nombrePorCliente,
        nombres: await ref.read(resolverNombresContraparteUseCaseProvider).paraPagos([
          for (final p in proyeccion.pendientes) p.pago,
          for (final c in proyeccion.registrados) if (c.pago != null) c.pago!,
        ]),
        errorCarga: null,
      );
    } catch (e) {
      state = state.copyWith(cargando: false, errorCarga: e.toString());
    }
  }

  /// El contador de la campana muestra "Complemento pendiente" desde
  /// esta misma proyección — cancelar uno hace reaparecer la obligación
  /// y debe verse SIN reiniciar la app. El panel se recarga solo al
  /// abrirse; esto mantiene correcto también el badge cerrado.
  ///
  /// Es `invalidate`, no una lectura: no crea dependencia de Finanzas
  /// hacia Notificaciones (que sí depende de Finanzas) — el ciclo que
  /// rompería Riverpod nunca se forma.
  void _invalidarNotificaciones() => ref.invalidate(notificacionesControllerProvider);

  Future<void> reintentarCarga() => _cargar();

  Future<void> cambiarVista(VistaComplementos vista) async {
    state = state.copyWith(vista: vista);
    await _cargar();
  }

  Future<void> aplicarFiltros({String? clienteId, bool limpiarClienteId = false}) async {
    state = state.copyWith(clienteId: clienteId, limpiarClienteId: limpiarClienteId);
    await _cargar();
  }

  Future<ComplementoPagoData?> obtenerPorId(String complementoPagoId) {
    return ref.read(complementoPagoRepositoryProvider).obtenerPorId(complementoPagoId);
  }

  /// El Complemento VIGENTE de un Pago — `null` si la obligación sigue
  /// pendiente (nunca hubo uno, o el que hubo se canceló).
  Future<ComplementoPagoData?> obtenerVigentePorPagoId(String pagoId) {
    return ref.read(complementoPagoRepositoryProvider).obtenerVigentePorPagoId(pagoId);
  }

  /// El histórico completo de un Pago, vigentes y cancelados.
  Future<List<ComplementoPagoData>> listarPorPagoId(String pagoId) {
    return ref.read(complementoPagoRepositoryProvider).listarPorPagoId(pagoId);
  }

  Future<List<ComplementoPagoEventoData>> listarEventos(String complementoPagoId) {
    return ref.read(complementoPagoRepositoryProvider).listarEventos(complementoPagoId);
  }

  Future<List<AttachmentData>> listarArchivos(String complementoPagoId) {
    return ref.read(attachmentRepositoryProvider).listarActivosPorComplementoPago(complementoPagoId);
  }

  Future<void> abrirArchivo(String path) {
    return ref.read(attachmentStorageProvider).abrir(path);
  }

  Future<CorregirComplementoPagoResultado> corregir({
    required String complementoPagoId,
    String? serieFiscal,
    String? folioFiscal,
    DateTime? fechaTimbrado,
    String? observaciones,
    required String motivo,
  }) async {
    final resultado = await autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'pagos.corregir',
      () => ref.read(corregirComplementoPagoUseCaseProvider).ejecutar(
            complementoPagoId: complementoPagoId,
            serieFiscal: serieFiscal,
            folioFiscal: folioFiscal,
            fechaTimbrado: fechaTimbrado,
            observaciones: observaciones,
            motivo: motivo,
            actorUsuarioId: _actorUsuarioId,
          ),
      CorregirComplementoPagoErrorInesperado.new,
    );
    if (resultado is CorregirComplementoPagoExitoso) {
      await _cargar();
    }
    return resultado;
  }

  Future<CancelarComplementoPagoResultado> cancelar({required String complementoPagoId, required String motivo}) async {
    final resultado = await autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'pagos.cancelar',
      () => ref.read(cancelarComplementoPagoUseCaseProvider).ejecutar(
            complementoPagoId: complementoPagoId,
            motivo: motivo,
            actorUsuarioId: _actorUsuarioId,
          ),
      CancelarComplementoPagoErrorInesperado.new,
    );
    if (resultado is CancelarComplementoPagoExitoso) {
      await _cargar();
      _invalidarNotificaciones();
    }
    return resultado;
  }

  Future<AdjuntarArchivoComplementoPagoResultado> adjuntarArchivo({
    required String complementoPagoId,
    required CategoriaAdjuntoComplementoPago categoria,
    required String sourceFilePath,
    required String originalFileName,
    required String mimeType,
  }) {
    // Etapa 0 (auditoría de consistencia transversal — corrección de un
    // hueco real de autorización): antes llamaba al use case crudo, sin
    // ningún `autorizarUseCase`. Mismo código que corregir.
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'pagos.corregir',
      () => ref.read(adjuntarArchivoComplementoPagoUseCaseProvider).ejecutar(
            complementoPagoId: complementoPagoId,
            categoria: categoria,
            sourceFilePath: sourceFilePath,
            originalFileName: originalFileName,
            mimeType: mimeType,
          ),
      AdjuntarArchivoComplementoPagoErrorInesperado.new,
    );
  }
}
