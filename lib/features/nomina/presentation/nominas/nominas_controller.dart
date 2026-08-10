import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/nomina/data/tables/nomina_table.dart';
import 'package:riseg_one/features/nomina/domain/usecases/actualizar_distribucion_nomina_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/actualizar_movimientos_nomina_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/actualizar_nomina_desde_personal_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/cerrar_nomina_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/generar_nomina_usecase.dart';

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
    final resultado = await ref.read(generarNominaUseCaseProvider).ejecutar(anio: anio, mes: mes, tipo: tipo);
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
    return ref.read(actualizarNominaDesdePersonalUseCaseProvider).ejecutar(nominaId: nominaId);
  }

  Future<CerrarNominaResultado> cerrar(String nominaId) async {
    final resultado = await ref.read(cerrarNominaUseCaseProvider).ejecutar(nominaId: nominaId);
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
    return ref.read(actualizarMovimientosNominaUseCaseProvider).ejecutar(
          nominaEmpleadoId: nominaEmpleadoId,
          prestamo: prestamo,
          tiempoExtra: tiempoExtra,
          bono: bono,
          faltas: faltas,
          otrosDescuentos: otrosDescuentos,
          observaciones: observaciones,
          limpiarObservaciones: limpiarObservaciones,
        );
  }

  Future<ActualizarDistribucionNominaResultado> actualizarDistribucion({
    required String nominaEmpleadoId,
    required int montoFiscal,
    required int montoNoFiscal,
  }) {
    return ref.read(actualizarDistribucionNominaUseCaseProvider).ejecutar(
          nominaEmpleadoId: nominaEmpleadoId,
          montoFiscal: montoFiscal,
          montoNoFiscal: montoNoFiscal,
        );
  }
}
