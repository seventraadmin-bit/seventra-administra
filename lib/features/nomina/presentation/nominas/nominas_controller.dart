import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/nomina/data/tables/nomina_table.dart';
import 'package:riseg_one/features/nomina/domain/usecases/actualizar_distribucion_nomina_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/actualizar_movimientos_nomina_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/actualizar_nomina_desde_personal_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/adjuntar_comprobante_pago_nomina_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/cancelar_pago_nomina_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/cerrar_nomina_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/corregir_pago_nomina_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/generar_nomina_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/registrar_pago_nomina_usecase.dart';
import 'package:riseg_one/core/permissions/authorization_service.dart';
import 'package:riseg_one/features/usuarios/usuarios_providers.dart';

import '../../../organizacion/organizacion_providers.dart';
import '../../nomina_providers.dart';
import 'nominas_state.dart';

part 'nominas_controller.g.dart';

/// Controlador del listado de Nóminas (Etapa 6C) — mismo diseño que
/// `IngresosController`/`PagosController`.
@riverpod
class NominasController extends _$NominasController {
  @override
  NominasState build() {
    Future.microtask(_cargar);
    return const NominasState();
  }

  Future<void> _cargar() async {
    state = state.copyWith(cargando: true, errorCarga: null);
    try {
      final repo = ref.read(nominaRepositoryProvider);
      final nominas = await repo.listar();
      final resumenes = <NominaResumen>[];
      for (final nomina in nominas) {
        final renglones = await repo.listarEmpleados(nomina.id);
        final total = renglones.fold<int>(0, (s, r) => s + r.totalAPagar);
        resumenes.add(NominaResumen(nomina: nomina, totalEmpleados: renglones.length, totalAPagar: total));
      }
      state = state.copyWith(cargando: false, nominas: resumenes, errorCarga: null);
    } catch (e) {
      state = state.copyWith(cargando: false, errorCarga: e.toString());
    }
  }

  Future<void> reintentarCarga() => _cargar();

  Future<void> recargar() => _cargar();

  Future<GenerarNominaResultado> generar({required int anio, required int mes, required TipoPeriodoNomina tipo}) async {
    final resultado = await autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'nomina.crear',
      () => ref.read(generarNominaUseCaseProvider).ejecutar(anio: anio, mes: mes, tipo: tipo),
      GenerarNominaErrorInesperado.new,
    );
    if (resultado is GenerarNominaExitoso) await _cargar();
    return resultado;
  }

  Future<NominaData?> obtenerPorId(String nominaId) {
    return ref.read(nominaRepositoryProvider).obtenerPorId(nominaId);
  }

  Future<List<NominaEmpleadoData>> listarEmpleados(String nominaId) {
    return ref.read(nominaRepositoryProvider).listarEmpleados(nominaId);
  }

  Future<List<NominaEmpleadoTramoData>> listarTramos(String nominaEmpleadoId) {
    return ref.read(nominaRepositoryProvider).listarTramos(nominaEmpleadoId);
  }

  Future<ActualizarNominaDesdePersonalResultado> actualizarDesdePersonal(String nominaId) {
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'nomina.modificar',
      () => ref.read(actualizarNominaDesdePersonalUseCaseProvider).ejecutar(nominaId: nominaId),
      ActualizarNominaDesdePersonalErrorInesperado.new,
    );
  }

  Future<CerrarNominaResultado> cerrar(String nominaId) async {
    final resultado = await autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'nomina.cerrar',
      () => ref.read(cerrarNominaUseCaseProvider).ejecutar(nominaId: nominaId),
      CerrarNominaErrorInesperado.new,
    );
    if (resultado is CerrarNominaExitoso) await _cargar();
    return resultado;
  }

  Future<List<NominaEmpleadoData>> renglonesQueRequierenRevision(String nominaId) {
    return ref.read(evaluarRenglonesRequierenRevisionUseCaseProvider).ejecutar(nominaId);
  }

  Future<ActualizarMovimientosNominaResultado> actualizarMovimientos({
    required String nominaEmpleadoId,
    int? prestamo,
    int? tiempoExtra,
    int? bono,
    int? faltas,
    int? otrosDescuentos,
    String? observaciones,
    bool limpiarObservaciones = false,
  }) {
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'nomina.modificar',
      () => ref.read(actualizarMovimientosNominaUseCaseProvider).ejecutar(
            nominaEmpleadoId: nominaEmpleadoId,
            prestamo: prestamo,
            tiempoExtra: tiempoExtra,
            bono: bono,
            faltas: faltas,
            otrosDescuentos: otrosDescuentos,
            observaciones: observaciones,
            limpiarObservaciones: limpiarObservaciones,
          ),
      ActualizarMovimientosNominaErrorInesperado.new,
    );
  }

  Future<ActualizarDistribucionNominaResultado> actualizarDistribucion({
    required String nominaEmpleadoId,
    required int montoFiscal,
    required int montoNoFiscal,
  }) {
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'nomina.modificar',
      () => ref.read(actualizarDistribucionNominaUseCaseProvider).ejecutar(
            nominaEmpleadoId: nominaEmpleadoId,
            montoFiscal: montoFiscal,
            montoNoFiscal: montoNoFiscal,
          ),
      ActualizarDistribucionNominaErrorInesperado.new,
    );
  }

  // --- Etapa 6D — Pagos de Nómina ---

  Future<PagoNominaData?> obtenerPagoPorId(String pagoNominaId) {
    return ref.read(pagoNominaRepositoryProvider).obtenerPorId(pagoNominaId);
  }

  Future<List<PagoNominaData>> listarPagos(String nominaId) {
    return ref.read(pagoNominaRepositoryProvider).listarPorNomina(nominaId);
  }

  Future<List<AplicacionPagoNominaData>> listarAplicacionesPorRenglon(String nominaEmpleadoId) {
    return ref.read(pagoNominaRepositoryProvider).listarAplicacionesPorRenglon(nominaEmpleadoId);
  }

  Future<List<AplicacionPagoNominaData>> listarAplicacionesPorPagoNomina(String pagoNominaId) {
    return ref.read(pagoNominaRepositoryProvider).listarAplicacionesPorPagoNomina(pagoNominaId);
  }

  Future<NominaEmpleadoData?> obtenerRenglon(String nominaEmpleadoId) {
    return ref.read(nominaRepositoryProvider).obtenerEmpleado(nominaEmpleadoId);
  }

  Future<int> saldoPendientePago(String nominaEmpleadoId) {
    return ref.read(pagoNominaRepositoryProvider).saldoPendientePago(nominaEmpleadoId);
  }

  Future<List<AttachmentData>> listarComprobantesPagoNomina(String pagoNominaId) {
    return ref.read(attachmentRepositoryProvider).listarActivosPorPagoNomina(pagoNominaId);
  }

  Future<void> abrirArchivo(String path) {
    return ref.read(attachmentStorageProvider).abrir(path);
  }

  Future<RegistrarPagoNominaResultado> registrarPago({
    required String nominaId,
    required DateTime fechaPago,
    required String formaPago,
    String? referencia,
    String? cuentaBancariaOrigen,
    String? observaciones,
    required List<({String nominaEmpleadoId, int monto})> aplicaciones,
  }) async {
    final resultado = await autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'nomina.pagar',
      () => ref.read(registrarPagoNominaUseCaseProvider).ejecutar(
            nominaId: nominaId,
            fechaPago: fechaPago,
            formaPago: formaPago,
            referencia: referencia,
            cuentaBancariaOrigen: cuentaBancariaOrigen,
            observaciones: observaciones,
            aplicaciones: aplicaciones,
          ),
      RegistrarPagoNominaErrorInesperado.new,
    );
    if (resultado is RegistrarPagoNominaExitoso) await _cargar();
    return resultado;
  }

  Future<CancelarPagoNominaResultado> cancelarPago({required String pagoNominaId, required String motivo}) async {
    final resultado = await autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'nomina.pagar',
      () => ref.read(cancelarPagoNominaUseCaseProvider).ejecutar(pagoNominaId: pagoNominaId, motivo: motivo),
      CancelarPagoNominaErrorInesperado.new,
    );
    if (resultado is CancelarPagoNominaExitoso) await _cargar();
    return resultado;
  }

  Future<CorregirPagoNominaResultado> corregirPago({
    required String pagoNominaId,
    DateTime? fechaPago,
    String? formaPago,
    String? referencia,
    String? cuentaBancariaOrigen,
    String? observaciones,
    required String motivo,
  }) {
    return ref.read(corregirPagoNominaUseCaseProvider).ejecutar(
          pagoNominaId: pagoNominaId,
          fechaPago: fechaPago,
          formaPago: formaPago,
          referencia: referencia,
          cuentaBancariaOrigen: cuentaBancariaOrigen,
          observaciones: observaciones,
          motivo: motivo,
        );
  }

  Future<AdjuntarComprobantePagoNominaResultado> adjuntarComprobantePagoNomina({
    required String pagoNominaId,
    required String sourceFilePath,
    required String originalFileName,
    required String mimeType,
  }) {
    return ref.read(adjuntarComprobantePagoNominaUseCaseProvider).ejecutar(
          pagoNominaId: pagoNominaId,
          sourceFilePath: sourceFilePath,
          originalFileName: originalFileName,
          mimeType: mimeType,
        );
  }
}
