import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/permissions/authorization_service.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';
import 'package:riseg_one/features/usuarios/usuarios_providers.dart';

import 'package:riseg_one/features/dashboard/presentation/dashboard_controller.dart';
import 'package:riseg_one/features/finanzas/finanzas_providers.dart';
import 'package:riseg_one/features/finanzas/presentation/cuentas_financieras/cuentas_financieras_controller.dart';
import 'package:riseg_one/features/finanzas/presentation/deudas_credito/deudas_credito_controller.dart';
import 'package:riseg_one/features/finanzas/presentation/egresos/egresos_controller.dart';
import 'package:riseg_one/features/finanzas/presentation/planeacion/planeacion_financiera_controller.dart';
import 'package:riseg_one/features/finanzas/presentation/resumen/resumen_financiero_controller.dart';
import 'package:riseg_one/features/inventario/presentation/articulos/articulos_controller.dart';

import '../compras_providers.dart';
import '../domain/repositories/compra_repository.dart';
import '../domain/usecases/adjuntar_comprobante_compra_usecase.dart';
import '../domain/usecases/cancelar_compra_usecase.dart';
import '../domain/usecases/correccion_partida_compra.dart';
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

  /// Usuario autenticado que ejecuta la operación (Etapa 11D) — mismo
  /// criterio que `UsuariosController._actorUsuarioId`.
  String? get _actorUsuarioId => ref.read(sesionControllerProvider)?.usuarioId;

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
        formaPago: state.formaPago,
      );
      final ids = compras.map((c) => c.id);
      final totalesPorCompra = await repo.calcularTotalesPorCompra(ids);
      final articulosPorCompra = await repo.listarArticulosPorCompra(ids);

      // Etapa 19B: resuelve la tarjeta de cada Compra financiada en una
      // sola consulta (`listarPorIds`) — nunca N+1 por fila.
      final deudaIds = {for (final c in compras) if (c.deudaId != null) c.deudaId!};
      final tarjetasPorId = await ref.read(deudaRepositoryProvider).listarPorIds(deudaIds);
      final tarjetaPorCompra = <String, TarjetaCompra>{
        for (final c in compras)
          if (c.deudaId != null && tarjetasPorId[c.deudaId] != null)
            c.id: (
              deudaId: c.deudaId!,
              nombre: tarjetasPorId[c.deudaId]!.nombre,
              ultimosDigitos: tarjetasPorId[c.deudaId]!.tarjetaUltimosDigitos,
            ),
      };

      state = state.copyWith(
        cargando: false,
        compras: compras,
        totalesPorCompra: totalesPorCompra,
        articulosPorCompra: articulosPorCompra,
        tarjetaPorCompra: tarjetaPorCompra,
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
    String? formaPago,
    bool limpiarDesde = false,
    bool limpiarHasta = false,
    bool limpiarFolio = false,
    bool limpiarProveedor = false,
    bool limpiarArticuloId = false,
    bool limpiarEstatus = false,
    bool limpiarFormaPago = false,
  }) async {
    state = state.copyWith(
      desde: desde,
      hasta: hasta,
      folio: folio,
      proveedor: proveedor,
      articuloId: articuloId,
      estatus: estatus,
      formaPago: formaPago,
      limpiarDesde: limpiarDesde,
      limpiarHasta: limpiarHasta,
      limpiarFolio: limpiarFolio,
      limpiarProveedor: limpiarProveedor,
      limpiarArticuloId: limpiarArticuloId,
      limpiarEstatus: limpiarEstatus,
      limpiarFormaPago: limpiarFormaPago,
    );
    await _cargar();
  }

  /// Limpia todos los filtros combinables a la vez (Etapa 19) — mismo
  /// criterio que `ArticulosController.limpiarTodosLosFiltros`.
  Future<void> limpiarTodosLosFiltros() async {
    state = state.copyWith(
      limpiarDesde: true,
      limpiarHasta: true,
      limpiarFolio: true,
      limpiarProveedor: true,
      limpiarArticuloId: true,
      limpiarEstatus: true,
      limpiarFormaPago: true,
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

  Future<List<ArticuloUnidadData>> obtenerUnidadesPorPartida(String compraPartidaId) {
    return ref.read(compraRepositoryProvider).listarUnidadesPorPartida(compraPartidaId);
  }

  Future<ResumenCorreccionCompra> obtenerResumenCorreccion({
    required String compraId,
    List<CorreccionPartida> cambiosPartidas = const [],
  }) {
    return ref.read(corregirCompraUseCaseProvider).obtenerResumen(compraId: compraId, cambiosPartidas: cambiosPartidas);
  }

  Future<RegistrarCompraResultado> registrarCompra({
    required DateTime fecha,
    String? proveedor,
    required String formaPago,
    String? formaPagoOtroDescripcion,
    String? observaciones,
    required List<PartidaCompraInput> partidas,
    String? deudaId,
    String? cuentaFinancieraId,
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
            deudaId: deudaId,
            cuentaFinancieraId: cuentaFinancieraId,
            actorUsuarioId: _actorUsuarioId,
          ),
      RegistrarCompraErrorInesperado.new,
    );
    if (resultado is RegistrarCompraExitosa) {
      await _cargar();
      // Toda Compra genera un Egreso automático (Etapa 10); si su
      // destino es Inventario, también genera un `MovimientoInventario`
      // — ambos módulos son ajenos a `ComprasController` y nunca se
      // enteran de este cambio si no se invalidan explícitamente
      // (Etapa 15, mismo patrón cruzado ya usado en `cancelarCompra`).
      ref.invalidate(egresosControllerProvider);
      ref.invalidate(articulosControllerProvider);
      ref.invalidate(dashboardControllerProvider);
      // Toda Compra afecta el Resumen financiero (gasto operativo,
      // vía Egreso o vía cargo a tarjeta) — bug de invalidación
      // preexistente, expuesto ahora que el Resumen también depende
      // de `cuentaFinancieraId` (Etapa 19C): antes solo se invalidaba
      // en la rama de tarjeta.
      ref.invalidate(resumenFinancieroControllerProvider);
      ref.invalidate(planeacionFinancieraControllerProvider);
      if (deudaId != null) {
        ref.invalidate(deudasCreditoControllerProvider);
      }
      // Etapa 19C: si la Compra se vinculó a una Cuenta financiera
      // (ramas efectivo/transferencia/cheque), su saldo derivado
      // cambió — nunca se entera sin invalidar aquí.
      if (cuentaFinancieraId != null) {
        ref.invalidate(cuentasFinancierasControllerProvider);
      }
    }
    return resultado;
  }

  Future<CorregirCompraResultado> corregirCompra({
    required String compraId,
    DateTime? fecha,
    String? proveedor,
    String? formaPago,
    String? formaPagoOtroDescripcion,
    String? observaciones,
    List<CorreccionPartida> cambiosPartidas = const [],
    String? nuevaCuentaFinancieraId,
    String? nuevaDeudaId,
    required String motivo,
  }) async {
    final resultado = await autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'compras.corregir',
      () => ref.read(corregirCompraUseCaseProvider).ejecutar(
            compraId: compraId,
            fecha: fecha,
            proveedor: proveedor,
            formaPago: formaPago,
            formaPagoOtroDescripcion: formaPagoOtroDescripcion,
            observaciones: observaciones,
            cambiosPartidas: cambiosPartidas,
            nuevaCuentaFinancieraId: nuevaCuentaFinancieraId,
            nuevaDeudaId: nuevaDeudaId,
            motivo: motivo,
            actorUsuarioId: _actorUsuarioId,
          ),
      CorregirCompraErrorInesperado.new,
    );
    if (resultado is CorregirCompraExitosa) {
      await _cargar();
      // Etapa 3 (Compras — corrección financiera Cuenta↔TDC): antes
      // esto solo se disparaba `if (cambiosPartidas.isNotEmpty)` — un
      // cambio de origen financiero (sin tocar partidas) nunca
      // invalidaba nada. También se corrige la asimetría real
      // encontrada en la auditoría: `deudasCreditoControllerProvider`
      // solo se invalidaba si la Compra QUEDABA en TDC, nunca si
      // dejaba de estarlo (ej. TDC→Cuenta) — se invalida siempre que
      // se pidió CUALQUIER cambio de origen, sin importar el sentido.
      final tocaOrigen = nuevaCuentaFinancieraId != null || nuevaDeudaId != null;
      if (cambiosPartidas.isNotEmpty || tocaOrigen) {
        ref.invalidate(egresosControllerProvider);
        ref.invalidate(deudasCreditoControllerProvider);
        ref.invalidate(cuentasFinancierasControllerProvider);
        ref.invalidate(articulosControllerProvider);
        ref.invalidate(dashboardControllerProvider);
        ref.invalidate(resumenFinancieroControllerProvider);
        ref.invalidate(planeacionFinancieraControllerProvider);
      }
    }
    return resultado;
  }

  Future<CancelarCompraResultado> cancelarCompra({
    required String compraId,
    required MotivoCancelacionCompra motivo,
    String? detalle,
    String? observaciones,
  }) async {
    final resultado = await autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'compras.cancelar',
      () => ref.read(cancelarCompraUseCaseProvider).ejecutar(
            compraId: compraId,
            motivo: motivo,
            detalle: detalle,
            observaciones: observaciones,
            actorUsuarioId: _actorUsuarioId,
          ),
      CancelarCompraErrorInesperado.new,
    );
    if (resultado is CancelarCompraExitosa) {
      await _cargar();
      // `CompraRepositoryImpl.cancelar` ya cancela el Egreso asociado en
      // la misma transacción (Etapa 10) — lo que faltaba era avisarle al
      // módulo de Finanzas: `egresosControllerProvider` es un provider
      // de otra feature que nunca se enteraba de este cambio, y su
      // listado seguía mostrando "Registrado" hasta que su `autoDispose`
      // se disparaba por otro motivo (Etapa 15, mismo patrón real ya
      // corregido en Clientes/Agenda/Cuentas por cobrar — aquí cruzando
      // de módulo, Compras → Finanzas).
      ref.invalidate(egresosControllerProvider);
      // Si la Compra tenía destino Inventario, `cancelar` revierte esa
      // entrada con un movimiento de baja en la misma transacción — sin
      // esto, Existencia seguía mostrando el valor previo hasta cambiar
      // de pestaña.
      ref.invalidate(articulosControllerProvider);
      ref.invalidate(dashboardControllerProvider);
      // Auditoría integral 19A-19D: cancelar afecta el Resumen/Planeación
      // financieros sin importar si la Compra está financiada por
      // tarjeta (revierte el cargo) o por Egreso (lo cancela) — antes
      // solo se invalidaba en la rama de tarjeta, dejando stale el caso
      // mayoritario (efectivo/transferencia/cheque).
      ref.invalidate(resumenFinancieroControllerProvider);
      ref.invalidate(planeacionFinancieraControllerProvider);
      ref.invalidate(cuentasFinancierasControllerProvider);
      if (resultado.compra.deudaId != null) {
        ref.invalidate(deudasCreditoControllerProvider);
      }
    }
    return resultado;
  }

  Future<AdjuntarComprobanteCompraResultado> adjuntarComprobante({
    required String compraId,
    required String sourceFilePath,
    required String originalFileName,
    required String mimeType,
  }) {
    // Etapa 0 (auditoría de consistencia transversal — corrección de un
    // hueco real de autorización): antes llamaba al use case crudo, sin
    // ningún `autorizarUseCase`. Mismo código que registrar/corregir.
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'compras.corregir',
      () => ref.read(adjuntarComprobanteCompraUseCaseProvider).ejecutar(
            compraId: compraId,
            sourceFilePath: sourceFilePath,
            originalFileName: originalFileName,
            mimeType: mimeType,
          ),
      AdjuntarComprobanteCompraErrorInesperado.new,
    );
  }
}
