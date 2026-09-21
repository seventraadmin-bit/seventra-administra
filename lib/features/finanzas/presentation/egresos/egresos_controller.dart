import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/adjuntar_comprobante_egreso_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/cancelar_egreso_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/corregir_egreso_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/registrar_egreso_usecase.dart';
import 'package:riseg_one/core/permissions/authorization_service.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';
import 'package:riseg_one/features/usuarios/usuarios_providers.dart';

import 'package:riseg_one/features/reportes/reportes_providers.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/obtener_origen_automatico_egreso_usecase.dart';

import 'package:riseg_one/features/finanzas/domain/origen_financiero_gasto.dart';

import '../../../organizacion/organizacion_providers.dart';
import '../../finanzas_providers.dart';
import '../invalidacion_financiera.dart';
import '../../domain/usecases/corregir_origen_financiero_egreso_usecase.dart';
import 'egresos_state.dart';

part 'egresos_controller.g.dart';

/// Controlador del listado de Egresos (Etapa 4K.1) — mismo diseño que
/// `IngresosController`.
@riverpod
class EgresosController extends _$EgresosController {
  @override
  EgresosState build() {
    Future.microtask(_cargar);
    return const EgresosState();
  }

  /// Usuario autenticado que ejecuta la operación (Etapa 11D) — mismo
  /// criterio que `UsuariosController._actorUsuarioId`.
  String? get _actorUsuarioId => ref.read(sesionControllerProvider)?.usuarioId;

  Future<void> _cargar() async {
    state = state.copyWith(cargando: true, errorCarga: null);
    try {
      final egresos = await ref.read(egresoRepositoryProvider).listar(
            estatus: state.estatus,
            servicioId: state.servicioId,
            categoriaFinancieraId: state.categoriaFinancieraId,
            rangoInicio: state.rangoInicio,
            rangoFin: state.rangoFin,
          );

      // Origen real por Egreso (Nómina/Compra/Manual) — una sola
      // llamada a `ClasificarEgresosPorOrigenUseCase` (ya usada en
      // Reportes), nunca una consulta nueva por fila. Mismo rango que
      // el listado, para que el desglose coincida exactamente con lo
      // que se ve en pantalla.
      final clasificados = await ref
          .read(clasificarEgresosPorOrigenUseCaseProvider)
          .ejecutar(rangoInicio: state.rangoInicio, rangoFin: state.rangoFin);
      final origenPorEgreso = {for (final ec in clasificados.detalle) ec.egreso.id: ec.origen};

      // Etapa 19B — informativo (ver el doc comment de `EgresosState
      // .totalCargadoTarjeta`), mismo rango que el listado.
      final totalCargadoTarjeta =
          await ref.read(deudaRepositoryProvider).totalCargadoEnRango(rangoInicio: state.rangoInicio, rangoFin: state.rangoFin);

      state = state.copyWith(
        cargando: false,
        egresos: egresos,
        origenPorEgreso: origenPorEgreso,
        totalNomina: clasificados.totalNomina,
        totalCompra: clasificados.totalCompra,
        totalTiempoExtra: clasificados.totalTiempoExtra,
        totalDeuda: clasificados.totalDeuda,
        totalDescuentoProgramado: clasificados.totalDescuentoProgramado,
        totalManual: clasificados.totalManual,
        totalCargadoTarjeta: totalCargadoTarjeta,
        errorCarga: null,
      );
    } catch (e) {
      state = state.copyWith(cargando: false, errorCarga: e.toString());
    }
  }

  Future<void> reintentarCarga() => _cargar();

  Future<void> aplicarFiltros({
    String? estatus,
    String? servicioId,
    String? categoriaFinancieraId,
    DateTime? rangoInicio,
    DateTime? rangoFin,
    bool limpiarEstatus = false,
    bool limpiarServicioId = false,
    bool limpiarCategoria = false,
    bool limpiarRango = false,
  }) async {
    state = state.copyWith(
      estatus: estatus,
      servicioId: servicioId,
      categoriaFinancieraId: categoriaFinancieraId,
      rangoInicio: rangoInicio,
      rangoFin: rangoFin,
      limpiarEstatus: limpiarEstatus,
      limpiarServicioId: limpiarServicioId,
      limpiarCategoria: limpiarCategoria,
      limpiarRango: limpiarRango,
    );
    await _cargar();
  }

  /// Origen/Forma de pago (Etapa 17) — filtros en memoria, nunca
  /// recargan desde el repositorio (ver doc de `EgresosState`).
  void aplicarFiltrosLocales({FiltroOrigenEgreso? origen, String? formaPago, bool limpiarFormaPago = false}) {
    state = state.copyWith(origen: origen, formaPago: formaPago, limpiarFormaPago: limpiarFormaPago);
  }

  Future<void> recargar() => _cargar();

  Future<EgresoData?> obtenerPorId(String egresoId) {
    return ref.read(egresoRepositoryProvider).obtenerPorId(egresoId);
  }

  Future<List<EgresoEventoData>> listarEventos(String egresoId) {
    return ref.read(egresoRepositoryProvider).listarEventos(egresoId);
  }

  Future<List<AttachmentData>> listarComprobantes(String egresoId) {
    return ref.read(attachmentRepositoryProvider).listarActivosPorEgreso(egresoId);
  }

  Future<void> abrirArchivo(String path) {
    return ref.read(attachmentStorageProvider).abrir(path);
  }

  Future<RegistrarEgresoResultado> registrar({
    required int monto,
    required DateTime fecha,
    String? categoriaFinancieraId,
    String? servicioId,
    String? sucursalId,
    String? areaId,
    OrigenFinancieroGasto? origen,
    required String formaPago,
    String? beneficiario,
    required String concepto,
    String? observaciones,
  }) async {
    final resultado = await autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'egresos.crear',
      () => ref.read(registrarEgresoUseCaseProvider).ejecutar(
            monto: monto,
            fecha: fecha,
            categoriaFinancieraId: categoriaFinancieraId,
            servicioId: servicioId,
            sucursalId: sucursalId,
            areaId: areaId,
            origen: origen,
            formaPago: formaPago,
            beneficiario: beneficiario,
            concepto: concepto,
            observaciones: observaciones,
            actorUsuarioId: _actorUsuarioId,
          ),
      RegistrarEgresoErrorInesperado.new,
    );
    if (resultado is RegistrarEgresoExitoso) {
      await _cargar();
      _invalidarConsumidoresFinancieros();
    }
    return resultado;
  }

  Future<CorregirEgresoResultado> corregir({
    required String egresoId,
    int? monto,
    DateTime? fecha,
    String? categoriaFinancieraId,
    String? servicioId,
    String? sucursalId,
    String? areaId,
    String? cuentaCaja,
    OrigenFinancieroGasto? origen,
    bool limpiarOrigen = false,
    String? formaPago,
    String? beneficiario,
    String? concepto,
    String? observaciones,
    required String motivo,
  }) async {
    final resultado = await autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'egresos.corregir',
      () => ref.read(corregirEgresoUseCaseProvider).ejecutar(
            egresoId: egresoId,
            monto: monto,
            fecha: fecha,
            categoriaFinancieraId: categoriaFinancieraId,
            servicioId: servicioId,
            sucursalId: sucursalId,
            areaId: areaId,
            cuentaCaja: cuentaCaja,
            origen: origen,
            limpiarOrigen: limpiarOrigen,
            formaPago: formaPago,
            beneficiario: beneficiario,
            concepto: concepto,
            observaciones: observaciones,
            motivo: motivo,
            actorUsuarioId: _actorUsuarioId,
          ),
      CorregirEgresoErrorInesperado.new,
    );
    if (resultado is CorregirEgresoExitoso) {
      await _cargar();
      _invalidarConsumidoresFinancieros();
    }
    return resultado;
  }

  Future<CancelarEgresoResultado> cancelar({required String egresoId, required String motivo}) async {
    final resultado = await autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'egresos.cancelar',
      () => ref
          .read(cancelarEgresoUseCaseProvider)
          .ejecutar(egresoId: egresoId, motivo: motivo, actorUsuarioId: _actorUsuarioId),
      CancelarEgresoErrorInesperado.new,
    );
    if (resultado is CancelarEgresoExitoso) {
      await _cargar();
      _invalidarConsumidoresFinancieros();
    }
    return resultado;
  }

  /// Contingencia del Maestro: corregir de qué cuenta salió un Egreso.
  ///
  /// Vive aquí —y no en el diálogo— por reactividad: mover un Egreso de
  /// `null` a una cuenta, o de una cuenta a otra, cambia el saldo
  /// derivado de esas cuentas y por lo tanto "Caja y bancos" del
  /// Dashboard. Llamar al provider autorizado desde la pantalla dejaba
  /// esos consumidores con el valor viejo hasta reiniciar la app.
  ///
  /// La autorización real sigue siendo `exigirMaestro` dentro del
  /// provider — aquí no se reimplementa ningún permiso.
  Future<CorregirOrigenFinancieroEgresoResultado> corregirOrigenFinanciero({
    required String egresoId,
    required String? cuentaFinancieraId,
    required String motivo,
  }) async {
    final resultado = await ref.read(corregirOrigenFinancieroEgresoAutorizadoProvider)(
      egresoId: egresoId,
      cuentaFinancieraId: cuentaFinancieraId,
      motivo: motivo,
    );
    if (resultado is CorregirOrigenFinancieroEgresoExitoso) {
      await _cargar();
      _invalidarConsumidoresFinancieros();
    }
    return resultado;
  }

  /// Consumidores reales de un alta/corrección/cancelación de gasto
  /// manual — una sola lista, nunca tres copias que se desincronizan
  /// (era exactamente lo que pasaba: los tres métodos invalidaban solo
  /// Dashboard/Resumen/Planeación).
  ///
  /// Etapa "Origen financiero de Egresos manuales" agrega los dos que
  /// faltaban y que ahora sí pueden cambiar en la misma operación:
  /// Cuentas financieras (su saldo se deriva de los Egresos, y una
  /// transición Cuenta→TDC se lo devuelve) y Deudas y crédito (el
  /// `MovimientoDeuda` del cargo cambia saldo y crédito disponible de
  /// la tarjeta). Compras/Tiempos Extra NO se invalidan: esta pantalla
  /// nunca puede cambiar una Compra ni una cobertura.
  /// Delegado al helper compartido (`InvalidacionFinanciera`): la
  /// lista vivía aquí y duplicada en otros dos controladores, y cada
  /// copia se desviaba un poco. `tocaDeudas` va en `true` porque un
  /// Egreso puede estar financiado con TDC y mover un
  /// `MovimientoDeuda`.
  void _invalidarConsumidoresFinancieros() {
    ref.invalidarConsumidoresFinancieros(tocaDeudas: true, omitir: {egresosControllerProvider});
  }

  /// `null` si [egresoId] es manual — insumo de "Generado por: X" / "Ver
  /// origen" en el expediente (nunca inferido por concepto/texto).
  Future<OrigenAutomaticoEgreso?> obtenerOrigenAutomatico(String egresoId) {
    return ref.read(obtenerOrigenAutomaticoEgresoUseCaseProvider).ejecutar(egresoId);
  }

  Future<AdjuntarComprobanteEgresoResultado> adjuntarComprobante({
    required String egresoId,
    required String sourceFilePath,
    required String originalFileName,
    required String mimeType,
  }) {
    // Etapa 0 (auditoría de consistencia transversal — corrección de un
    // hueco real de autorización): antes llamaba al use case crudo, sin
    // ningún `autorizarUseCase`. Mismo código que corregir.
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'egresos.corregir',
      () => ref.read(adjuntarComprobanteEgresoUseCaseProvider).ejecutar(
            egresoId: egresoId,
            sourceFilePath: sourceFilePath,
            originalFileName: originalFileName,
            mimeType: mimeType,
          ),
      AdjuntarComprobanteEgresoErrorInesperado.new,
    );
  }
}

