import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/dashboard/presentation/dashboard_controller.dart';
import 'package:riseg_one/features/finanzas/presentation/cuentas_financieras/cuentas_financieras_controller.dart';
import 'package:riseg_one/features/finanzas/presentation/planeacion/planeacion_financiera_controller.dart';
import 'package:riseg_one/features/finanzas/presentation/resumen/resumen_financiero_controller.dart';
import 'package:riseg_one/features/organizacion/organizacion_providers.dart';
import 'package:riseg_one/features/personal/personal_providers.dart';
import 'package:riseg_one/features/personal/presentation/empleados/empleados_list_screen.dart'
    show empleadoNombreCompleto;
import 'package:riseg_one/features/usuarios/usuarios_providers.dart';

import '../descuentos_personal_providers.dart';
import '../domain/usecases/cancelar_saldo_descuento_programado_usecase.dart';
import '../domain/usecases/corregir_descuento_programado_usecase.dart';
import '../domain/usecases/registrar_descuento_programado_usecase.dart';
import '../domain/usecases/reprogramar_cuotas_pendientes_usecase.dart';
import 'descuentos_personal_state.dart';

part 'descuentos_personal_controller.g.dart';

/// Controlador de la pantalla global "Descuentos al Personal" (Etapa
/// 15) — mismo diseño que `NominasController`.
@riverpod
class DescuentosPersonalController extends _$DescuentosPersonalController {
  @override
  DescuentosPersonalState build() {
    Future.microtask(_cargar);
    return const DescuentosPersonalState();
  }

  /// Etapa 1 (rediseño del catálogo de permisos): el antiguo
  /// `personal.gestionarDescuentos` cubría lectura y escritura a la
  /// vez; al dividirse en `descuentos.crear`/`corregir`/`cancelar` se
  /// abrió el mismo hueco de visibilidad que tenía Nómina antes de su
  /// corrección (ver `NominasController.tieneNomina`) — el router solo
  /// exige `personal.ver` para entrar a `/personal/**`, así que un
  /// usuario con `personal.ver` pero sin `descuentos.ver` podía
  /// navegar directo a la pantalla de Descuentos (u obtener un
  /// descuento por su ruta) y este controller cargaba los datos igual,
  /// sin volver a preguntar. Ocultar la pestaña/entrada en la UI es
  /// solo la capa cosmética; esta es la barrera real — ninguno de los
  /// métodos de este controller debe tocar
  /// `descuentoProgramadoRepositoryProvider` sin pasar por aquí primero.
  bool get tieneDescuentos => ref.read(permissionServiceProvider).hasCode('descuentos.ver');

  Future<void> _cargar() async {
    if (!tieneDescuentos) {
      state = const DescuentosPersonalState(cargando: false);
      return;
    }
    state = state.copyWith(cargando: true, errorCarga: null);
    try {
      final repo = ref.read(descuentoProgramadoRepositoryProvider);
      final empleadoRepo = ref.read(empleadoRepositoryProvider);
      final descuentos = await repo.listarTodos();

      final resumenes = <DescuentoProgramadoResumen>[];
      final empleadosCache = <String, EmpleadoData>{};
      var saldoPendienteTotal = 0;
      var prestamosActivos = 0;
      var cobrosProximos = 0;
      final empleadosConSaldo = <String>{};
      final horizonte = DateTime.now().add(const Duration(days: 15));

      for (final descuento in descuentos) {
        var empleado = empleadosCache[descuento.empleadoId];
        if (empleado == null) {
          final encontrado = await empleadoRepo.obtenerPorId(
            descuento.empleadoId,
          );
          if (encontrado != null) {
            empleado = encontrado;
            empleadosCache[descuento.empleadoId] = encontrado;
          }
        }
        final nombre =
            empleado == null ? '—' : empleadoNombreCompleto(empleado);

        final cuotas = await repo.listarCuotas(descuento.id);
        final pendientesOrdenadas =
            cuotas
                .where(
                  (c) => c.estatus == 'pendiente' || c.estatus == 'reservada',
                )
                .toList()
              ..sort((a, b) => a.fechaProgramada.compareTo(b.fechaProgramada));
        final proxima =
            pendientesOrdenadas.isEmpty ? null : pendientesOrdenadas.first;

        resumenes.add(
          DescuentoProgramadoResumen(
            descuento: descuento,
            empleadoNombre: nombre,
            numeroEmpleado: empleado?.numeroEmpleado,
            proximaCuota: proxima,
          ),
        );

        if (descuento.estatus == 'activo') {
          saldoPendienteTotal += descuento.saldoPendiente;
          if (descuento.tipo == 'prestamo') prestamosActivos++;
          if (descuento.saldoPendiente > 0) {
            empleadosConSaldo.add(descuento.empleadoId);
          }
          if (proxima != null && !proxima.fechaProgramada.isAfter(horizonte)) {
            cobrosProximos++;
          }
        }
      }

      resumenes.sort(
        (a, b) =>
            b.descuento.fechaRegistro.compareTo(a.descuento.fechaRegistro),
      );

      // Fotografía vigente del Empleado (Etapa 16, evolución visual) —
      // una sola consulta en lote sobre los Empleados ya obtenidos
      // arriba, nunca una por renglón.
      final fotografiaIds = [
        for (final e in empleadosCache.values)
          if (e.fotografiaAttachmentId != null) e.fotografiaAttachmentId!,
      ];
      final fotografias = await ref
          .read(attachmentRepositoryProvider)
          .obtenerPorIds(fotografiaIds);
      final fotografiaPorAttachmentId = {
        for (final f in fotografias) f.id: f.path,
      };
      final fotografiaPathPorEmpleadoId = {
        for (final e in empleadosCache.values)
          if (e.fotografiaAttachmentId != null &&
              fotografiaPorAttachmentId.containsKey(e.fotografiaAttachmentId))
            e.id: fotografiaPorAttachmentId[e.fotografiaAttachmentId]!,
      };

      state = state.copyWith(
        cargando: false,
        descuentos: resumenes,
        kpis: DescuentosPersonalKpis(
          saldoPendienteTotal: saldoPendienteTotal,
          prestamosActivos: prestamosActivos,
          cobrosProximos: cobrosProximos,
          empleadosConSaldo: empleadosConSaldo.length,
        ),
        fotografiaPathPorEmpleadoId: fotografiaPathPorEmpleadoId,
        errorCarga: null,
      );
    } catch (e) {
      state = state.copyWith(cargando: false, errorCarga: e.toString());
    }
  }

  Future<void> reintentarCarga() => _cargar();

  Future<void> recargar() => _cargar();

  void cambiarFiltro(DescuentosPersonalFiltro filtro) =>
      state = state.copyWith(filtro: filtro);

  void cambiarGrupo(GrupoEstadoDescuento grupo) =>
      state = state.copyWith(grupo: grupo);

  Future<DescuentoProgramadoEmpleadoData?> obtenerPorId(String id) {
    if (!tieneDescuentos) return Future.value(null);
    return ref.read(descuentoProgramadoRepositoryProvider).obtenerPorId(id);
  }

  Future<List<DescuentoProgramadoCuotaData>> listarCuotas(
    String descuentoProgramadoId,
  ) {
    if (!tieneDescuentos) return Future.value(const []);
    return ref
        .read(descuentoProgramadoRepositoryProvider)
        .listarCuotas(descuentoProgramadoId);
  }

  Future<List<DescuentoProgramadoMovimientoData>> listarMovimientos(
    String descuentoProgramadoId,
  ) {
    if (!tieneDescuentos) return Future.value(const []);
    return ref
        .read(descuentoProgramadoRepositoryProvider)
        .listarMovimientos(descuentoProgramadoId);
  }

  Future<List<DescuentoProgramadoEmpleadoData>> listarPorEmpleado(
    String empleadoId,
  ) {
    if (!tieneDescuentos) return Future.value(const []);
    return ref
        .read(descuentoProgramadoRepositoryProvider)
        .listarPorEmpleado(empleadoId);
  }

  Future<List<DescuentoProgramadoCuotaData>> listarCuotasPendientesPorEmpleado(
    String empleadoId,
  ) {
    if (!tieneDescuentos) return Future.value(const []);
    return ref
        .read(descuentoProgramadoRepositoryProvider)
        .listarCuotasPendientesPorEmpleado(empleadoId);
  }

  Future<RegistrarDescuentoProgramadoResultado> registrar({
    required String empleadoId,
    required String tipo,
    required DateTime fechaRegistro,
    required int importeOriginal,
    required int numeroCuotas,
    required DateTime fechaPrimeraCuota,
    String? descripcion,
    String? asignacionOrigenId,
    String? observaciones,
    bool esEntregaDinero = false,
    String? cuentaFinancieraId,
    String? formaPagoEgreso,
  }) async {
    final resultado = await ref.read(
      registrarDescuentoProgramadoAutorizadoProvider,
    )(
      empleadoId: empleadoId,
      tipo: tipo,
      fechaRegistro: fechaRegistro,
      importeOriginal: importeOriginal,
      numeroCuotas: numeroCuotas,
      fechaPrimeraCuota: fechaPrimeraCuota,
      descripcion: descripcion,
      asignacionOrigenId: asignacionOrigenId,
      observaciones: observaciones,
      esEntregaDinero: esEntregaDinero,
      cuentaFinancieraId: cuentaFinancieraId,
      formaPagoEgreso: formaPagoEgreso,
    );
    if (resultado is RegistrarDescuentoProgramadoExitoso) {
      await _cargar();
      // Un préstamo con `cuentaFinancieraId` genera un Egreso real —
      // invalidar Finanzas solo cuando realmente hubo desembolso (una
      // "recuperación de concepto", ej. botas, nunca toca Finanzas).
      if (cuentaFinancieraId != null) {
        ref.invalidate(dashboardControllerProvider);
        ref.invalidate(resumenFinancieroControllerProvider);
        ref.invalidate(planeacionFinancieraControllerProvider);
        ref.invalidate(cuentasFinancierasControllerProvider);
      }
    }
    return resultado;
  }

  Future<ReprogramarCuotasPendientesResultado> reprogramar({
    required String descuentoProgramadoId,
    required int numeroCuotas,
    required DateTime fechaPrimeraCuota,
    required String motivo,
  }) async {
    final resultado = await ref.read(
      reprogramarCuotasPendientesAutorizadoProvider,
    )(
      descuentoProgramadoId: descuentoProgramadoId,
      numeroCuotas: numeroCuotas,
      fechaPrimeraCuota: fechaPrimeraCuota,
      motivo: motivo,
    );
    if (resultado is ReprogramarCuotasPendientesExitoso) await _cargar();
    return resultado;
  }

  /// Corrección completa (Etapa 5) — administrativa y/o de monto total,
  /// distinta de [reprogramar] (que solo mueve el plan futuro sin tocar
  /// el monto total ni ningún campo administrativo). Invalida Finanzas
  /// SOLO cuando la corrección pudo tocar el Egreso de un desembolso
  /// real (cambio de importe y/o de cuenta) — una corrección puramente
  /// administrativa (fecha, observaciones, tipo) nunca produce ningún
  /// `Ingreso`/`Egreso`/`MovimientoDeuda` nuevo (Etapa "Cierre del
  /// ciclo financiero de Descuentos Programados").
  Future<CorregirDescuentoProgramadoResultado> corregir({
    required String descuentoProgramadoId,
    String? tipo,
    String? descripcion,
    bool limpiarDescripcion = false,
    String? observaciones,
    bool limpiarObservaciones = false,
    DateTime? fechaRegistro,
    int? importeOriginal,
    int? numeroCuotas,
    DateTime? fechaPrimeraCuota,
    String? cuentaFinancieraId,
    bool limpiarCuentaFinancieraId = false,
    required String motivo,
  }) async {
    final resultado = await ref.read(corregirDescuentoProgramadoAutorizadoProvider)(
      descuentoProgramadoId: descuentoProgramadoId,
      tipo: tipo,
      descripcion: descripcion,
      limpiarDescripcion: limpiarDescripcion,
      observaciones: observaciones,
      limpiarObservaciones: limpiarObservaciones,
      fechaRegistro: fechaRegistro,
      importeOriginal: importeOriginal,
      numeroCuotas: numeroCuotas,
      fechaPrimeraCuota: fechaPrimeraCuota,
      cuentaFinancieraId: cuentaFinancieraId,
      limpiarCuentaFinancieraId: limpiarCuentaFinancieraId,
      motivo: motivo,
    );
    if (resultado is CorregirDescuentoProgramadoExitoso) {
      await _cargar();
      if (importeOriginal != null || cuentaFinancieraId != null || limpiarCuentaFinancieraId) {
        ref.invalidate(dashboardControllerProvider);
        ref.invalidate(resumenFinancieroControllerProvider);
        ref.invalidate(planeacionFinancieraControllerProvider);
        ref.invalidate(cuentasFinancierasControllerProvider);
      }
    }
    return resultado;
  }

  /// Puede revertir el Egreso de un desembolso que nunca llegó a
  /// recuperarse (ver el doc comment de `DescuentoProgramadoRepository.
  /// cancelarSaldo`) — se invalida Finanzas incondicionalmente en éxito
  /// porque, sin releer, no se puede saber barato si esa reversión
  /// ocurrió.
  Future<CancelarSaldoDescuentoProgramadoResultado> cancelarSaldo({
    required String descuentoProgramadoId,
    required String motivo,
  }) async {
    final resultado = await ref.read(
      cancelarSaldoDescuentoProgramadoAutorizadoProvider,
    )(descuentoProgramadoId: descuentoProgramadoId, motivo: motivo);
    if (resultado is CancelarSaldoDescuentoProgramadoExitoso) {
      await _cargar();
      ref.invalidate(dashboardControllerProvider);
      ref.invalidate(resumenFinancieroControllerProvider);
      ref.invalidate(planeacionFinancieraControllerProvider);
      ref.invalidate(cuentasFinancierasControllerProvider);
    }
    return resultado;
  }
}
