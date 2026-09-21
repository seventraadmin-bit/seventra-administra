import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/dashboard/presentation/dashboard_controller.dart';
import 'package:riseg_one/features/finanzas/presentation/cuentas_financieras/cuentas_financieras_controller.dart';
import 'package:riseg_one/features/finanzas/presentation/deudas_credito/deudas_credito_controller.dart';
import 'package:riseg_one/features/finanzas/presentation/egresos/egresos_controller.dart';
import 'package:riseg_one/features/finanzas/presentation/planeacion/planeacion_financiera_controller.dart';
import 'package:riseg_one/features/finanzas/presentation/resumen/resumen_financiero_controller.dart';
import 'package:riseg_one/features/organizacion/organizacion_providers.dart';
import 'package:riseg_one/features/personal/personal_providers.dart';
import 'package:riseg_one/features/personal/presentation/empleados/empleados_list_screen.dart' show empleadoNombreCompleto;

import '../domain/repositories/tiempo_extra_repository.dart';
import '../domain/usecases/cancelar_tiempo_extra_usecase.dart';
import '../domain/usecases/corregir_tiempo_extra_usecase.dart';
import '../domain/usecases/eliminar_tiempo_extra_fisicamente_usecase.dart';
import '../domain/usecases/registrar_tiempo_extra_usecase.dart';
import '../tiempos_extra_providers.dart';
import 'tiempos_extra_state.dart';

part 'tiempos_extra_controller.g.dart';

/// Controlador de la pantalla global "Tiempos Extra" (cobertura
/// operativa por ausencia) — mismo diseño que `DescuentosPersonalController`.
@riverpod
class TiemposExtraController extends _$TiemposExtraController {
  @override
  TiemposExtraState build() {
    Future.microtask(_cargar);
    return const TiemposExtraState();
  }

  Future<void> _cargar() async {
    state = state.copyWith(cargando: true, errorCarga: null);
    try {
      final repo = ref.read(tiempoExtraRepositoryProvider);
      final registros = await repo.listar(
        rangoInicio: state.rangoInicio,
        rangoFin: state.rangoFin,
        servicioId: state.servicioId,
        estatus: state.estatus,
      );

      final empleadoRepo = ref.read(empleadoRepositoryProvider);
      final servicioRepo = ref.read(servicioRepositoryProvider);
      final catalogoRepo = ref.read(catalogoRepositoryProvider);

      final empleadosCache = <String, EmpleadoData>{};
      Future<EmpleadoData?> obtenerEmpleado(String id) async {
        return empleadosCache[id] ??= (await empleadoRepo.obtenerPorId(id))!;
      }

      final serviciosCache = <String, String>{};
      final turnos = {for (final t in await catalogoRepo.listarModalidadesTurno()) t.id: t.nombre};
      final costosPorRegistro = await repo.totalCostosAdicionalesPorTiempoExtra([for (final r in registros) r.id]);
      // Lote, nunca una consulta por renglón — mismo criterio que el
      // resto de la pantalla (turnos, costos).
      final vacantes = await ref.read(vacanteCoberturaReaderProvider).porIds(
            [for (final r in registros) if (r.vacanteOperativaId != null) r.vacanteOperativaId!],
          );

      final resumenes = <TiempoExtraResumen>[];
      for (final registro in registros) {
        var servicioNombre = serviciosCache[registro.servicioId];
        if (servicioNombre == null) {
          final servicio = await servicioRepo.obtenerPorId(registro.servicioId);
          servicioNombre = servicio?.nombre ?? '—';
          serviciosCache[registro.servicioId] = servicioNombre;
        }

        final empleadoAusenteId = registro.empleadoAusenteId;
        final empleadoAusente = empleadoAusenteId == null ? null : await obtenerEmpleado(empleadoAusenteId);
        final nombreCubre = registro.empleadoCubreId != null
            ? empleadoNombreCompleto((await obtenerEmpleado(registro.empleadoCubreId!))!)
            : (registro.nombreExternoCubre ?? '—');

        resumenes.add(TiempoExtraResumen(
          tiempoExtra: registro,
          servicioNombre: servicioNombre,
          empleadoAusenteNombre: empleadoAusente == null ? null : empleadoNombreCompleto(empleadoAusente),
          vacanteEtiqueta: vacantes[registro.vacanteOperativaId]?.etiqueta,
          nombreCubre: nombreCubre,
          turnoNombre: turnos[registro.turnoId] ?? '—',
          montoTotal: registro.montoTiempoExtra + (costosPorRegistro[registro.id] ?? 0),
        ));
      }

      final resumen = await ref.read(obtenerResumenTiemposExtraUseCaseProvider).ejecutar(
            rangoInicio: state.rangoInicio,
            rangoFin: state.rangoFin,
          );

      state = state.copyWith(cargando: false, registros: resumenes, resumen: resumen, errorCarga: null);
    } catch (e) {
      state = state.copyWith(cargando: false, errorCarga: e.toString());
    }
  }

  Future<void> reintentarCarga() => _cargar();

  Future<void> aplicarFiltros({
    String? servicioId,
    String? estatus,
    DateTime? rangoInicio,
    DateTime? rangoFin,
    bool limpiarServicioId = false,
    bool limpiarEstatus = false,
    bool limpiarRango = false,
  }) async {
    state = state.copyWith(
      servicioId: servicioId,
      estatus: estatus,
      rangoInicio: rangoInicio,
      rangoFin: rangoFin,
      limpiarServicioId: limpiarServicioId,
      limpiarEstatus: limpiarEstatus,
      limpiarRango: limpiarRango,
    );
    await _cargar();
  }

  Future<TiempoExtraData?> obtenerPorId(String id) {
    return ref.read(tiempoExtraRepositoryProvider).obtenerPorId(id);
  }

  Future<List<TiempoExtraCostoAdicionalData>> listarCostosAdicionales(String tiempoExtraId) {
    return ref.read(tiempoExtraRepositoryProvider).listarCostosAdicionales(tiempoExtraId);
  }

  Future<List<TiempoExtraEventoData>> listarEventos(String tiempoExtraId) {
    return ref.read(tiempoExtraRepositoryProvider).listarEventos(tiempoExtraId);
  }

  Future<RegistrarTiempoExtraResultado> registrar({
    required DateTime fecha,
    required String servicioId,
    required String origenCobertura,
    String? empleadoAusenteId,
    String? motivoAusencia,
    String? vacanteOperativaId,
    String? descripcionOrigen,
    String? empleadoCubreId,
    String? nombreExternoCubre,
    required String turnoId,
    required int montoTiempoExtra,
    required String formaPago,
    String? cuentaFinancieraId,
    String? deudaIdTarjeta,
    String? observaciones,
    List<CostoAdicionalInput> costosAdicionales = const [],
  }) async {
    final resultado = await ref.read(registrarTiempoExtraAutorizadoProvider)(
      fecha: fecha,
      servicioId: servicioId,
      origenCobertura: origenCobertura,
      empleadoAusenteId: empleadoAusenteId,
      motivoAusencia: motivoAusencia,
      vacanteOperativaId: vacanteOperativaId,
      descripcionOrigen: descripcionOrigen,
      empleadoCubreId: empleadoCubreId,
      nombreExternoCubre: nombreExternoCubre,
      turnoId: turnoId,
      montoTiempoExtra: montoTiempoExtra,
      formaPago: formaPago,
      cuentaFinancieraId: cuentaFinancieraId,
      deudaIdTarjeta: deudaIdTarjeta,
      observaciones: observaciones,
      costosAdicionales: costosAdicionales,
    );
    if (resultado is RegistrarTiempoExtraExitoso) {
      await _cargar();
      // El Egreso automático generado afecta Egresos/Resumen
      // financiero/Planeación — mismo criterio que `ComprasController.
      // registrarCompra`. La Nómina del Empleado ausente solo se
      // actualiza cuando esa Nómina se (re)calcula explícitamente
      // ("Actualizar desde Personal"/generar) — nunca automáticamente
      // desde aquí, mismo criterio de snapshot que el resto de Nómina.
      ref.invalidate(egresosControllerProvider);
      ref.invalidate(dashboardControllerProvider);
      ref.invalidate(resumenFinancieroControllerProvider);
      ref.invalidate(planeacionFinancieraControllerProvider);
      // Etapa "origen financiero unificado" — el pago base y cada costo
      // adicional pueden salir de una CuentaFinanciera o cargarse a una
      // Deuda (TDC) de forma independiente. Mismo criterio que
      // `ComprasController.registrarCompra`: invalidar solo el módulo
      // realmente afectado, según el origen de CUALQUIER ítem.
      if (cuentaFinancieraId != null || costosAdicionales.any((c) => c.cuentaFinancieraId != null)) {
        ref.invalidate(cuentasFinancierasControllerProvider);
      }
      if (deudaIdTarjeta != null || costosAdicionales.any((c) => c.deudaIdTarjeta != null)) {
        ref.invalidate(deudasCreditoControllerProvider);
      }
    }
    return resultado;
  }

  Future<CancelarTiempoExtraResultado> cancelar({required String tiempoExtraId, required String motivo}) async {
    final resultado = await ref.read(cancelarTiempoExtraAutorizadoProvider)(tiempoExtraId: tiempoExtraId, motivo: motivo);
    if (resultado is CancelarTiempoExtraExitoso) {
      await _cargar();
      ref.invalidate(egresosControllerProvider);
      ref.invalidate(dashboardControllerProvider);
      ref.invalidate(resumenFinancieroControllerProvider);
      ref.invalidate(planeacionFinancieraControllerProvider);
      // Cancelar revierte el pago base y cada costo adicional, sin
      // importar su origen (CuentaFinanciera o TDC) — se invalidan
      // ambas vistas incondicionalmente, mismo criterio que
      // `ComprasController.cancelarCompra` para `cuentasFinancierasControllerProvider`.
      ref.invalidate(cuentasFinancierasControllerProvider);
      ref.invalidate(deudasCreditoControllerProvider);
    }
    return resultado;
  }

  Future<CorregirTiempoExtraResultado> corregir({
    required String tiempoExtraId,
    required DateTime fecha,
    required String servicioId,
    required String origenCobertura,
    String? empleadoAusenteId,
    String? motivoAusencia,
    String? vacanteOperativaId,
    String? descripcionOrigen,
    String? empleadoCubreId,
    String? nombreExternoCubre,
    required String turnoId,
    required int montoTiempoExtra,
    required String formaPago,
    String? cuentaFinancieraId,
    String? deudaIdTarjeta,
    String? observaciones,
    List<CorreccionCostoAdicional> cambiosCostos = const [],
    required String motivo,
  }) async {
    final resultado = await ref.read(corregirTiempoExtraAutorizadoProvider)(
      tiempoExtraId: tiempoExtraId,
      fecha: fecha,
      servicioId: servicioId,
      origenCobertura: origenCobertura,
      empleadoAusenteId: empleadoAusenteId,
      motivoAusencia: motivoAusencia,
      vacanteOperativaId: vacanteOperativaId,
      descripcionOrigen: descripcionOrigen,
      empleadoCubreId: empleadoCubreId,
      nombreExternoCubre: nombreExternoCubre,
      turnoId: turnoId,
      montoTiempoExtra: montoTiempoExtra,
      formaPago: formaPago,
      cuentaFinancieraId: cuentaFinancieraId,
      deudaIdTarjeta: deudaIdTarjeta,
      observaciones: observaciones,
      cambiosCostos: cambiosCostos,
      motivo: motivo,
    );
    if (resultado is CorregirTiempoExtraExitoso) {
      await _cargar();
      // Una corrección puede tocar el/los Egreso(s) vinculados y/o
      // cargos de tarjeta, sin importar qué origen tenían ANTES —
      // mismo criterio incondicional que `cancelar` para
      // Cuentas financieras/Deudas y crédito (una corrección puede
      // cambiar de origen por completo).
      ref.invalidate(egresosControllerProvider);
      ref.invalidate(dashboardControllerProvider);
      ref.invalidate(resumenFinancieroControllerProvider);
      ref.invalidate(planeacionFinancieraControllerProvider);
      ref.invalidate(cuentasFinancierasControllerProvider);
      ref.invalidate(deudasCreditoControllerProvider);
    }
    return resultado;
  }

  Future<ResumenEliminacionTiempoExtra> obtenerResumenEliminacionFisica(String tiempoExtraId) {
    return ref.read(eliminarTiempoExtraFisicamenteUseCaseProvider).obtenerResumen(tiempoExtraId);
  }

  Future<EliminarTiempoExtraFisicamenteResultado> eliminarFisicamente({
    required String tiempoExtraId,
    required MotivoEliminacionFisicaTiempoExtra motivo,
    String? detalle,
  }) async {
    final resultado = await ref.read(eliminarTiempoExtraFisicamenteAutorizadoProvider)(
      tiempoExtraId: tiempoExtraId,
      motivo: motivo,
      detalle: detalle,
    );
    if (resultado is EliminarTiempoExtraFisicamenteExitoso) {
      await _cargar();
      ref.invalidate(egresosControllerProvider);
      ref.invalidate(dashboardControllerProvider);
      ref.invalidate(resumenFinancieroControllerProvider);
      ref.invalidate(planeacionFinancieraControllerProvider);
      ref.invalidate(cuentasFinancierasControllerProvider);
      ref.invalidate(deudasCreditoControllerProvider);
    }
    return resultado;
  }
}
