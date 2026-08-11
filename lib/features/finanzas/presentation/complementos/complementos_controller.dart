import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/finanzas/data/tables/complemento_pago_table.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/adjuntar_archivo_complemento_pago_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/cancelar_complemento_pago_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/corregir_complemento_pago_usecase.dart';
import 'package:riseg_one/core/permissions/authorization_service.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';
import 'package:riseg_one/features/usuarios/usuarios_providers.dart';

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

  Future<void> _cargar() async {
    state = state.copyWith(cargando: true, errorCarga: null);
    try {
      final complementos = await ref.read(complementoPagoRepositoryProvider).listar(
            clienteId: state.clienteId,
            estatus: state.estatus,
          );
      state = state.copyWith(cargando: false, complementos: complementos, errorCarga: null);
    } catch (e) {
      state = state.copyWith(cargando: false, errorCarga: e.toString());
    }
  }

  Future<void> reintentarCarga() => _cargar();

  Future<void> aplicarFiltros({
    String? clienteId,
    String? estatus,
    bool limpiarClienteId = false,
    bool limpiarEstatus = false,
  }) async {
    state = state.copyWith(
      clienteId: clienteId,
      estatus: estatus,
      limpiarClienteId: limpiarClienteId,
      limpiarEstatus: limpiarEstatus,
    );
    await _cargar();
  }

  Future<ComplementoPagoData?> obtenerPorId(String complementoPagoId) {
    return ref.read(complementoPagoRepositoryProvider).obtenerPorId(complementoPagoId);
  }

  Future<ComplementoPagoData?> obtenerPorPagoId(String pagoId) {
    return ref.read(complementoPagoRepositoryProvider).obtenerPorPagoId(pagoId);
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
      'finanzas.modificar',
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
      'finanzas.archivar',
      () => ref.read(cancelarComplementoPagoUseCaseProvider).ejecutar(
            complementoPagoId: complementoPagoId,
            motivo: motivo,
            actorUsuarioId: _actorUsuarioId,
          ),
      CancelarComplementoPagoErrorInesperado.new,
    );
    if (resultado is CancelarComplementoPagoExitoso) {
      await _cargar();
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
    return ref.read(adjuntarArchivoComplementoPagoUseCaseProvider).ejecutar(
          complementoPagoId: complementoPagoId,
          categoria: categoria,
          sourceFilePath: sourceFilePath,
          originalFileName: originalFileName,
          mimeType: mimeType,
        );
  }
}
