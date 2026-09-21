import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:riseg_one/features/organizacion/organizacion_providers.dart';
import 'package:riseg_one/features/personal/data/tables/empleado_table.dart' show MotivoBajaEmpleado;
import 'package:riseg_one/features/personal/domain/usecases/analitica_bajas.dart';
import 'package:riseg_one/features/personal/domain/usecases/construir_eventos_baja.dart';

import '../../personal_providers.dart';
import 'bajas_state.dart';

part 'bajas_controller.g.dart';

/// Controlador de "BAJAS DE PERSONAL" (Etapa 15) — carga TODOS los
/// Empleados + TODOS sus periodos archivados una sola vez y construye
/// los eventos con `construirEventosBaja`; periodo/filtros de tabla se
/// aplican después, en memoria (ver `BajasState`).
@riverpod
class BajasController extends _$BajasController {
  @override
  BajasState build() {
    Future.microtask(_cargar);
    return const BajasState();
  }

  Future<void> _cargar() async {
    state = state.copyWith(cargando: true, errorCarga: null);
    try {
      final empleadoRepo = ref.read(empleadoRepositoryProvider);
      final servicioRepo = ref.read(servicioRepositoryProvider);
      final puestoRepo = ref.read(puestoRepositoryProvider);

      final empleados = await empleadoRepo.listar();
      final periodosPorEmpleado = await empleadoRepo.listarPeriodosLaboralesArchivadosPorEmpleados(
        [for (final e in empleados) e.id],
      );
      final eventos = construirEventosBaja(empleados, periodosPorEmpleado);

      final servicios = await servicioRepo.listar();
      final puestos = await puestoRepo.listarActivos();

      // Fotografía vigente del Empleado (Etapa 16, evolución visual) —
      // `empleados` ya está cargado completo arriba, así que esto es
      // una sola consulta en lote extra, nunca una por evento/renglón.
      final fotografiaIds = [
        for (final e in empleados)
          if (e.fotografiaAttachmentId != null) e.fotografiaAttachmentId!,
      ];
      final fotografias = await ref.read(attachmentRepositoryProvider).obtenerPorIds(fotografiaIds);
      final fotografiaPorAttachmentId = {for (final f in fotografias) f.id: f.path};
      final fotografiaPathPorEmpleadoId = {
        for (final e in empleados)
          if (e.fotografiaAttachmentId != null && fotografiaPorAttachmentId.containsKey(e.fotografiaAttachmentId))
            e.id: fotografiaPorAttachmentId[e.fotografiaAttachmentId]!,
      };

      state = state.copyWith(
        cargando: false,
        eventos: eventos,
        servicios: servicios,
        puestos: puestos,
        fotografiaPathPorEmpleadoId: fotografiaPathPorEmpleadoId,
        errorCarga: null,
      );
    } catch (e) {
      state = state.copyWith(cargando: false, errorCarga: e.toString());
    }
  }

  Future<void> reintentarCarga() => _cargar();

  Future<void> recargar() => _cargar();

  void cambiarPeriodo(PeriodoAnaliticaBajas periodo, {DateTime? inicioPersonalizado, DateTime? finPersonalizado}) {
    state = state.copyWith(periodo: periodo, inicioPersonalizado: inicioPersonalizado, finPersonalizado: finPersonalizado);
  }

  void aplicarFiltros({
    String? texto,
    String? servicioFiltro,
    String? puestoFiltro,
    MotivoBajaEmpleado? motivoFiltro,
    SegmentoPermanencia? segmentoFiltro,
    bool limpiarTexto = false,
    bool limpiarServicioFiltro = false,
    bool limpiarPuestoFiltro = false,
    bool limpiarMotivoFiltro = false,
    bool limpiarSegmentoFiltro = false,
  }) {
    state = state.copyWith(
      texto: texto,
      servicioFiltro: servicioFiltro,
      puestoFiltro: puestoFiltro,
      motivoFiltro: motivoFiltro,
      segmentoFiltro: segmentoFiltro,
      limpiarTexto: limpiarTexto,
      limpiarServicioFiltro: limpiarServicioFiltro,
      limpiarPuestoFiltro: limpiarPuestoFiltro,
      limpiarMotivoFiltro: limpiarMotivoFiltro,
      limpiarSegmentoFiltro: limpiarSegmentoFiltro,
    );
  }

  void cambiarOrden(OrdenBajas orden) => state = state.copyWith(orden: orden);

  void limpiarTodosLosFiltros() {
    state = state.copyWith(
      limpiarTexto: true,
      limpiarServicioFiltro: true,
      limpiarPuestoFiltro: true,
      limpiarMotivoFiltro: true,
      limpiarSegmentoFiltro: true,
    );
  }
}
