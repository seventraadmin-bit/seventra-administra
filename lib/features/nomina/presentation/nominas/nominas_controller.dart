
import 'package:riseg_one/features/finanzas/domain/fuente_egreso.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/dashboard/dashboard_providers.dart';
import 'package:riseg_one/features/dashboard/presentation/dashboard_controller.dart';
import 'package:riseg_one/features/descuentos_personal/presentation/descuentos_personal_controller.dart';
import 'package:riseg_one/features/finanzas/presentation/cuentas_financieras/cuentas_financieras_controller.dart';
import 'package:riseg_one/features/finanzas/presentation/egresos/egresos_controller.dart';
import 'package:riseg_one/features/finanzas/presentation/planeacion/planeacion_financiera_controller.dart';
import 'package:riseg_one/features/finanzas/presentation/resumen/resumen_financiero_controller.dart';
import 'package:riseg_one/features/nomina/data/tables/nomina_table.dart';
import 'package:riseg_one/features/nomina/domain/repositories/nomina_repository.dart' show NominaEmpleadoReporteRow;
import 'package:riseg_one/features/nomina/domain/usecases/actualizar_nomina_desde_personal_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/actualizar_renglon_nomina_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/adjuntar_comprobante_pago_nomina_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/cancelar_nomina_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/cancelar_pago_nomina_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/cerrar_nomina_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/corregir_pago_nomina_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/corregir_renglon_nomina_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/generar_nomina_dispersion_pdf_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/generar_nomina_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/registrar_pago_nomina_usecase.dart';
import 'package:riseg_one/core/permissions/authorization_service.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';
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

  /// Usuario autenticado que ejecuta la operación (Etapa 11D) — mismo
  /// criterio que `UsuariosController._actorUsuarioId`.
  String? get _actorUsuarioId => ref.read(sesionControllerProvider)?.usuarioId;

  /// Etapa 0 (auditoría de consistencia transversal): el router solo
  /// exige `personal.ver` para entrar a `/personal/**` — un usuario con
  /// `personal.ver` pero sin `nomina.ver` podía navegar directo a
  /// `/personal/nomina` (o abrir un renglón por su ruta) y este
  /// controller cargaba los datos igual, sin volver a preguntar. Ocultar
  /// la pestaña en `PersonalShellScreen` es solo la capa cosmética; esta
  /// es la barrera real (mismo criterio que
  /// `ReportesPersonalNominaController.tieneNomina`) — ninguno de los
  /// métodos de este controller debe tocar un repositorio de Nómina sin
  /// pasar por aquí primero.
  bool get tieneNomina => ref.read(permissionServiceProvider).hasCode('nomina.ver');

  Future<void> _cargar() async {
    if (!tieneNomina) {
      state = const NominasState(cargando: false);
      return;
    }
    state = state.copyWith(cargando: true, errorCarga: null);
    try {
      final repo = ref.read(nominaRepositoryProvider);
      final nominas = await repo.listar();
      // Etapa 17: una sola consulta para TODOS los renglones de TODAS
      // las Nóminas (`listarRenglonesEnRango` sin rango — ya existía
      // para Reportes, Etapa 12B), agrupados en memoria por
      // `nominaId` — antes era un `listarEmpleados` por Nómina dentro
      // del ciclo (N+1 real, una consulta por fila del listado).
      final renglones = await repo.listarRenglonesEnRango();
      final renglonesPorNomina = <String, List<NominaEmpleadoReporteRow>>{};
      for (final r in renglones) {
        (renglonesPorNomina[r.nominaId] ??= []).add(r);
      }
      final resumenes = [
        for (final nomina in nominas)
          NominaResumen(
            nomina: nomina,
            totalEmpleados: renglonesPorNomina[nomina.id]?.length ?? 0,
            totalAPagar: renglonesPorNomina[nomina.id]?.fold<int>(0, (s, r) => s + r.totalAPagar) ?? 0,
            empleadosPagados: renglonesPorNomina[nomina.id]?.where((r) => r.estatusPago == 'pagado').length ?? 0,
          ),
      ];

      // Etapa 16, evolución visual: mismo `ObtenerProximaNominaUseCase`
      // que ya usa el Dashboard (una Nómina `cerrada`, nunca inventada) —
      // el resumen ya calculado arriba evita una segunda consulta.
      final proxima = await ref.read(obtenerProximaNominaUseCaseProvider).ejecutar();
      NominaResumen? proximaResumen;
      if (proxima != null) {
        for (final r in resumenes) {
          if (r.nomina.id == proxima.id) {
            proximaResumen = r;
            break;
          }
        }
      }

      state = state.copyWith(
        cargando: false,
        nominas: resumenes,
        proximaNomina: proximaResumen,
        limpiarProximaNomina: proximaResumen == null,
        errorCarga: null,
      );
    } catch (e) {
      state = state.copyWith(cargando: false, errorCarga: e.toString());
    }
  }

  Future<void> reintentarCarga() => _cargar();

  Future<void> recargar() => _cargar();

  void aplicarFiltros({int? anio, String? estatus, bool limpiarAnio = false, bool limpiarEstatus = false}) {
    state = state.copyWith(
      anioFiltro: anio,
      estatusFiltro: estatus,
      limpiarAnioFiltro: limpiarAnio,
      limpiarEstatusFiltro: limpiarEstatus,
    );
  }

  void limpiarTodosLosFiltros() {
    state = state.copyWith(limpiarAnioFiltro: true, limpiarEstatusFiltro: true);
  }

  Future<GenerarNominaResultado> generar({required int anio, required int mes, required TipoPeriodoNomina tipo}) async {
    final resultado = await autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'nomina.crear',
      () => ref.read(generarNominaUseCaseProvider).ejecutar(anio: anio, mes: mes, tipo: tipo, actorUsuarioId: _actorUsuarioId),
      GenerarNominaErrorInesperado.new,
    );
    if (resultado is GenerarNominaExitoso) {
      await _cargar();
      // Generar reserva cuotas de préstamos/botas elegibles (Etapa 15).
      ref.invalidate(descuentosPersonalControllerProvider);
    }
    return resultado;
  }

  Future<NominaData?> obtenerPorId(String nominaId) {
    if (!tieneNomina) return Future.value(null);
    return ref.read(nominaRepositoryProvider).obtenerPorId(nominaId);
  }

  Future<List<NominaEmpleadoData>> listarEmpleados(String nominaId) {
    if (!tieneNomina) return Future.value(const []);
    return ref.read(nominaRepositoryProvider).listarEmpleados(nominaId);
  }

  Future<List<NominaEmpleadoTramoData>> listarTramos(String nominaEmpleadoId) {
    return ref.read(nominaRepositoryProvider).listarTramos(nominaEmpleadoId);
  }

  Future<ActualizarNominaDesdePersonalResultado> actualizarDesdePersonal(String nominaId) async {
    final resultado = await autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'nomina.modificar',
      () => ref.read(actualizarNominaDesdePersonalUseCaseProvider).ejecutar(nominaId: nominaId, actorUsuarioId: _actorUsuarioId),
      ActualizarNominaDesdePersonalErrorInesperado.new,
    );
    if (resultado is ActualizarNominaDesdePersonalExitoso) {
      ref.invalidate(descuentosPersonalControllerProvider);
    }
    return resultado;
  }

  Future<CerrarNominaResultado> cerrar(String nominaId) async {
    final resultado = await autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'nomina.cerrar',
      () => ref.read(cerrarNominaUseCaseProvider).ejecutar(nominaId: nominaId, actorUsuarioId: _actorUsuarioId),
      CerrarNominaErrorInesperado.new,
    );
    if (resultado is CerrarNominaExitoso) {
      await _cargar();
      ref.invalidate(descuentosPersonalControllerProvider);
      // Etapa 4 (hallazgo real de auditoría): cerrar es EXACTAMENTE la
      // transición que hace elegible a esta Nómina como "Próxima
      // nómina" (`ObtenerProximaNominaUseCase` solo lee `estatus ==
      // cerrada`) — sin esto, el Dashboard seguía mostrando la cifra
      // vieja hasta que algo AJENO lo invalidara.
      ref.invalidate(dashboardControllerProvider);
    }
    return resultado;
  }

  Future<List<NominaEmpleadoData>> renglonesQueRequierenRevision(String nominaId) {
    if (!tieneNomina) return Future.value(const []);
    return ref.read(evaluarRenglonesRequierenRevisionUseCaseProvider).ejecutar(nominaId);
  }

  /// Movimientos manuales y (opcionalmente) distribución Fiscal/No
  /// fiscal en una sola operación atómica (Etapa 15, calculadora
  /// auditable) — [distribucionManual] `null` conserva el
  /// comportamiento automático de siempre.
  Future<ActualizarRenglonNominaResultado> actualizarRenglon({
    required String nominaEmpleadoId,
    int? prestamo,
    int? tiempoExtra,
    int? bono,
    int? faltas,
    int? otrosDescuentos,
    String? observaciones,
    bool limpiarObservaciones = false,
    ({int montoFiscal, int montoNoFiscal})? distribucionManual,
  }) {
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'nomina.modificar',
      () => ref.read(actualizarRenglonNominaUseCaseProvider).ejecutar(
            nominaEmpleadoId: nominaEmpleadoId,
            prestamo: prestamo,
            tiempoExtra: tiempoExtra,
            bono: bono,
            faltas: faltas,
            otrosDescuentos: otrosDescuentos,
            observaciones: observaciones,
            limpiarObservaciones: limpiarObservaciones,
            distribucionManual: distribucionManual,
            actorUsuarioId: _actorUsuarioId,
          ),
      ActualizarRenglonNominaErrorInesperado.new,
    );
  }

  /// Corrección de un renglón de una Nómina ya `cerrada`/`pagada`
  /// (Etapa 4) — a diferencia de [actualizarRenglon] (Borrador,
  /// `nomina.modificar`), exige motivo y usa `nomina.corregir`
  /// (facultad distinta, nunca la comparte con "modificar borrador").
  Future<CorregirRenglonNominaResultado> corregirRenglon({
    required String nominaEmpleadoId,
    int? prestamo,
    int? tiempoExtra,
    int? bono,
    int? faltas,
    int? otrosDescuentos,
    String? observaciones,
    bool limpiarObservaciones = false,
    ({int montoFiscal, int montoNoFiscal})? distribucionManual,
    required String motivo,
  }) async {
    final resultado = await autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'nomina.corregir',
      () => ref.read(corregirRenglonNominaUseCaseProvider).ejecutar(
            nominaEmpleadoId: nominaEmpleadoId,
            prestamo: prestamo,
            tiempoExtra: tiempoExtra,
            bono: bono,
            faltas: faltas,
            otrosDescuentos: otrosDescuentos,
            observaciones: observaciones,
            limpiarObservaciones: limpiarObservaciones,
            distribucionManual: distribucionManual,
            motivo: motivo,
            actorUsuarioId: _actorUsuarioId,
          ),
      CorregirRenglonNominaErrorInesperado.new,
    );
    if (resultado is CorregirRenglonNominaExitoso) {
      await _cargar();
      // La corrección pudo haber cruzado un renglón a/desde `pagado`
      // (recalculando `estatusPago`) y, con ello, demover la Nómina
      // de `pagada` a `cerrada` — mismos consumidores ajenos que ya
      // invalida `cancelarPago` para el mismo tipo de transición.
      ref.invalidate(dashboardControllerProvider);
      ref.invalidate(descuentosPersonalControllerProvider);
    }
    return resultado;
  }

  /// Cancelación de la Nómina completa (Etapa 4) — solo Borrador o
  /// Cerrada-sin-pagos (`CancelarNominaUseCase` ya lo valida).
  Future<CancelarNominaResultado> cancelarNomina({
    required String nominaId,
    required MotivoCancelacionNomina motivo,
    String? detalle,
    String? observaciones,
  }) async {
    final resultado = await autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'nomina.cancelar',
      () => ref.read(cancelarNominaUseCaseProvider).ejecutar(
            nominaId: nominaId,
            motivo: motivo,
            detalle: detalle,
            observaciones: observaciones,
            actorUsuarioId: _actorUsuarioId,
          ),
      CancelarNominaErrorInesperado.new,
    );
    if (resultado is CancelarNominaExitoso) {
      await _cargar();
      ref.invalidate(descuentosPersonalControllerProvider);
      ref.invalidate(dashboardControllerProvider);
    }
    return resultado;
  }

  // --- Etapa 6D — Pagos de Nómina ---

  Future<PagoNominaData?> obtenerPagoPorId(String pagoNominaId) {
    return ref.read(pagoNominaRepositoryProvider).obtenerPorId(pagoNominaId);
  }

  Future<List<PagoNominaData>> listarPagos(String nominaId) {
    if (!tieneNomina) return Future.value(const []);
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
    String? cuentaFinancieraId,

    /// Reparto entre varias cuentas cuando una sola no alcanza: un solo
    /// PagoNomina y un solo Egreso, repartido entre N cuentas.
    List<FuenteEgreso>? fuentes,
    String? observaciones,
    required List<({String nominaEmpleadoId, int monto})> aplicaciones,
  }) async {
    final resultado = await autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'nomina.registrarPago',
      () => ref.read(registrarPagoNominaUseCaseProvider).ejecutar(
            nominaId: nominaId,
            fechaPago: fechaPago,
            formaPago: formaPago,
            referencia: referencia,
            cuentaBancariaOrigen: cuentaBancariaOrigen,
            cuentaFinancieraId: cuentaFinancieraId,
            fuentes: fuentes,
            observaciones: observaciones,
            aplicaciones: aplicaciones,
            actorUsuarioId: _actorUsuarioId,
          ),
      RegistrarPagoNominaErrorInesperado.new,
    );
    if (resultado is RegistrarPagoNominaExitoso) {
      await _cargar();
      ref.invalidate(dashboardControllerProvider);
      // Pagar es el único punto donde una cuota `reservada` pasa a
      // `aplicada` (Etapa 15) — el módulo Descuentos debe refrescarse.
      ref.invalidate(descuentosPersonalControllerProvider);
    }
    return resultado;
  }

  Future<CancelarPagoNominaResultado> cancelarPago({required String pagoNominaId, required String motivo}) async {
    final resultado = await autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'nomina.cancelarPago',
      () => ref
          .read(cancelarPagoNominaUseCaseProvider)
          .ejecutar(pagoNominaId: pagoNominaId, motivo: motivo, actorUsuarioId: _actorUsuarioId),
      CancelarPagoNominaErrorInesperado.new,
    );
    if (resultado is CancelarPagoNominaExitoso) {
      await _cargar();
      ref.invalidate(dashboardControllerProvider);
      ref.invalidate(descuentosPersonalControllerProvider);
      // Auditoría integral 19A-19D: cancelar un pago de Nómina cancela
      // en cascada el Egreso ligado (ver el doc comment de
      // `PagoNominaDetalleDialog`) — Egresos/Cuentas financieras/
      // Resumen/Planeación son providers ajenos que nunca se enteraban,
      // asimetría directa con `registrarPago`, que sí los invalida (en
      // `nomina_detalle_screen.dart._abrirRegistrarPago`).
      ref.invalidate(egresosControllerProvider);
      ref.invalidate(cuentasFinancierasControllerProvider);
      ref.invalidate(resumenFinancieroControllerProvider);
      ref.invalidate(planeacionFinancieraControllerProvider);
    }
    return resultado;
  }

  Future<CorregirPagoNominaResultado> corregirPago({
    required String pagoNominaId,
    DateTime? fechaPago,
    String? formaPago,
    String? referencia,
    String? cuentaBancariaOrigen,
    String? cuentaFinancieraId,
    String? observaciones,
    required String motivo,
  }) {
    // Auditoría integral 19A-19D: a diferencia de `registrarPago`/
    // `cancelarPago` en este mismo archivo, esta llamada invocaba el
    // use case crudo sin `autorizarUseCase` — no está cableada a ningún
    // widget todavía, pero deja el hueco listo para colarse en cuanto
    // alguien construya esa pantalla. Mismo código de permiso que el
    // resto de operaciones de pago de Nómina.
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'nomina.corregirPago',
      () => ref.read(corregirPagoNominaUseCaseProvider).ejecutar(
            pagoNominaId: pagoNominaId,
            fechaPago: fechaPago,
            formaPago: formaPago,
            referencia: referencia,
            cuentaBancariaOrigen: cuentaBancariaOrigen,
            cuentaFinancieraId: cuentaFinancieraId,
            observaciones: observaciones,
            motivo: motivo,
            actorUsuarioId: _actorUsuarioId,
          ),
      CorregirPagoNominaErrorInesperado.new,
    );
  }

  Future<AdjuntarComprobantePagoNominaResultado> adjuntarComprobantePagoNomina({
    required String pagoNominaId,
    required String sourceFilePath,
    required String originalFileName,
    required String mimeType,
  }) {
    // Etapa 0 (auditoría de consistencia transversal — corrección de un
    // hueco real de autorización): antes llamaba al use case crudo, sin
    // ningún `autorizarUseCase`. Mismo código que registrar/cancelar/
    // corregir pago de Nómina.
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'nomina.corregirPago',
      () => ref.read(adjuntarComprobantePagoNominaUseCaseProvider).ejecutar(
            pagoNominaId: pagoNominaId,
            sourceFilePath: sourceFilePath,
            originalFileName: originalFileName,
            mimeType: mimeType,
          ),
      AdjuntarComprobantePagoNominaErrorInesperado.new,
    );
  }

  /// Genera el PDF de control de dispersión y lo abre — a diferencia de
  /// "Generar recibo PDF" (que no pasa por `autorizarUseCase`, mismo
  /// criterio que las exportaciones de Reportes), este documento
  /// concentra banco/cuenta/CLABE completos de TODOS los renglones de
  /// la Nómina en un solo archivo — más exposición que cualquier
  /// pantalla individual de hoy (`RenglonNominaDetalleDialog` solo
  /// muestra un Empleado a la vez). Se gatea con el mismo permiso que
  /// "Registrar pago" (`nomina.registrarPago`): quien puede ejecutar el
  /// dinero puede generar la hoja para dispersarlo.
  ///
  /// Etapa 5B.2: ya no recibe ningún logotipo. El use case lo resuelve desde
  /// la Empresa.
  Future<GenerarNominaDispersionPdfResultado> generarDispersionPdf(String nominaId) {
    return autorizarUseCase(
      ref.read(authorizationServiceProvider),
      'nomina.registrarPago',
      () => ref.read(generarNominaDispersionPdfUseCaseProvider).ejecutar(nominaId: nominaId),
      GenerarNominaDispersionPdfErrorInesperado.new,
    );
  }
}
