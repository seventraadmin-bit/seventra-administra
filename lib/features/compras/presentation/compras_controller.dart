import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/permissions/authorization_service.dart';
import 'package:riseg_one/features/usuarios/usuarios_providers.dart';

import '../compras_providers.dart';
import '../domain/repositories/compra_repository.dart';
import '../domain/usecases/adjuntar_comprobante_compra_usecase.dart';
import '../domain/usecases/cancelar_compra_usecase.dart';
import '../domain/usecases/corregir_compra_usecase.dart';
import '../domain/usecases/registrar_compra_usecase.dart';
import 'compras_state.dart';

part 'compras_controller.g.dart';

/// Controlador de Compras (Etapa 10) — listado con filtros + todas las
/// operaciones de expediente, mismo criterio que `TelefoniaController`/
/// `EgresosController`.
@riverpod
class ComprasController extends _$ComprasController {
  @override
  ComprasState build() {
    Future.microtask(_cargar);
    return const ComprasState();
  }

  Future<void> _cargar() async {
    state = state.copyWith(cargando: true, errorCarga: null);
    try {
      final repo = ref.read(compraRepositoryProvider);
      final compras = await repo.listar(
        desde: state.desde,
        hasta: state.hasta,
        folio: state.folio,
        proveedor: state.proveedor,
        articuloId: state.articuloId,
        estatus: state.estatus,
      );
      final totalesPorCompra = await repo.calcularTotalesPorCompra(compras.map((c) => c.id));
      final totalRango = await repo.totalCompradoEnRango(desde: state.desde, hasta: state.hasta);
      state = state.copyWith(
        cargando: false,
        compras: compras,
        totalesPorCompra: totalesPorCompra,
        totalRango: totalRango,
        errorCarga: null,
      );
    } catch (e) {
      state = state.copyWith(cargando: false, errorCarga: e.toString());
    }
  }

  Future<void> reintentarCarga() => _cargar();

  Future<void> recargar() => _cargar();

  Future<void> aplicarFiltros({
    DateTime? desde,
    DateTime? hasta,
    String? folio,
    String? proveedor,
    String? articuloId,
    String? estatus,
    bool limpiarDesde = false,
    bool limpiarHasta = false,
    bool limpiarFolio = false,
    bool limpiarProveedor = false,
    bool limpiarArticuloId = false,
    bool limpiarEstatus = false,
  }) async {
    state = state.copyWith(
      desde: desde,
      hasta: hasta,
      folio: folio,
      proveedor: proveedor,
      articuloId: articuloId,
      estatus: estatus,
      limpiarDesde: limpiarDesde,
      limpiarHasta: limpiarHasta,
      limpiarFolio: limpiarFolio,
      limpiarProveedor: limpiarProveedor,
      limpiarArticuloId: limpiarArticuloId,
      limpiarEstatus: limpiarEstatus,
    );
    await _cargar();
  }

  Future<CompraData?> obtenerCompra(String compraId) {
    return ref.read(compraRepositoryProvider).obtenerPorId(compraId);
  }

  Future<List<CompraPartidaData>> obtenerPartidas(String compraId) {
    return ref.read(compraRepositoryProvider).listarPartidas(compraId);
  }

  Future<List<CompraEventoData>> obtenerEventos(String compraId) {
    return ref.read(compraRepositoryProvider).listarEventos(compraId);
  }

  Future<List<MovimientoInventarioData>> obtenerMovimientosGenerados(String compraId) {
    return ref.read(compraRepositoryProvider).listarMovimientosGenerados(compraId);
  }

  Future<RegistrarCompraResultado> registrarCompra({
    required DateTime fecha,
    String? proveedor,
    required String formaPago,
    String? formaPagoOtroDescripcion,
    String? observaciones,
    required List<PartidaCompraInput> partidas,
  }) async {
    final resultado = await autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'compras.crear',
      () => ref.read(registrarCompraUseCaseProvider).ejecutar(
            fecha: fecha,
            proveedor: proveedor,
            formaPago: formaPago,
            formaPagoOtroDescripcion: formaPagoOtroDescripcion,
            observaciones: observaciones,
            partidas: partidas,
          ),
      RegistrarCompraErrorInesperado.new,
    );
    if (resultado is RegistrarCompraExitosa) await _cargar();
    return resultado;
  }

  Future<CorregirCompraResultado> corregirCompra({
    required String compraId,
    String? proveedor,
    String? formaPago,
    String? formaPagoOtroDescripcion,
    String? observaciones,
    required String motivo,
  }) async {
    final resultado = await autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'compras.crear',
      () => ref.read(corregirCompraUseCaseProvider).ejecutar(
            compraId: compraId,
            proveedor: proveedor,
            formaPago: formaPago,
            formaPagoOtroDescripcion: formaPagoOtroDescripcion,
            observaciones: observaciones,
            motivo: motivo,
          ),
      CorregirCompraErrorInesperado.new,
    );
    if (resultado is CorregirCompraExitosa) await _cargar();
    return resultado;
  }

  Future<CancelarCompraResultado> cancelarCompra({required String compraId, required String motivo}) async {
    final resultado = await autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'compras.archivar',
      () => ref.read(cancelarCompraUseCaseProvider).ejecutar(compraId: compraId, motivo: motivo),
      CancelarCompraErrorInesperado.new,
    );
    if (resultado is CancelarCompraExitosa) await _cargar();
    return resultado;
  }

  Future<AdjuntarComprobanteCompraResultado> adjuntarComprobante({
    required String compraId,
    required String sourceFilePath,
    required String originalFileName,
    required String mimeType,
  }) {
    return ref.read(adjuntarComprobanteCompraUseCaseProvider).ejecutar(
          compraId: compraId,
          sourceFilePath: sourceFilePath,
          originalFileName: originalFileName,
          mimeType: mimeType,
        );
  }
}
