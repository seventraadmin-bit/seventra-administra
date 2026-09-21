import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:riseg_one/features/reportes/domain/analitica/comparacion_periodo.dart';

import 'package:riseg_one/features/finanzas/finanzas_providers.dart';
import 'package:riseg_one/features/personal/personal_providers.dart';
import 'package:riseg_one/features/reportes/reportes_providers.dart';
import 'package:riseg_one/features/tiempos_extra/tiempos_extra_providers.dart';
import 'package:riseg_one/features/usuarios/usuarios_providers.dart';

import '../dashboard_providers.dart';
import '../domain/periodo_dashboard.dart';
import 'dashboard_state.dart';

part 'dashboard_controller.g.dart';

/// Controlador del Dashboard (Etapa 13, rediseño gerencial Etapa 15) —
/// pantalla inicial dinámica por permisos. Cada bloque verifica su
/// propio `hasCode('xxx.ver')` **antes** de invocar el use case
/// correspondiente; si falta el permiso, ese use case nunca se ejecuta
/// (mismo patrón que cada controller de Reportes, nunca "se consulta y
/// se oculta después").
///
/// Reutiliza directamente los 6 use cases de Reportes 12A–12D
/// (`obtenerResumenGeneralUseCaseProvider` y análogos) — nunca
/// redefine una consulta que Reportes ya resuelve. Los nuevos bloques
/// (cobertura, cobranza, próxima Nómina, personal operativo) componen
/// repositorios/use cases ya existentes — ver el doc comment de cada
/// uno en `domain/usecases/`.
///
/// [PeriodoDashboard] es la única fuente de verdad del rango
/// seleccionado (Parte B) — `cambiarPeriodo` es la única forma de
/// modificarlo, siempre desde la cabecera.
@riverpod
class DashboardController extends _$DashboardController {
  @override
  DashboardState build() {
    final periodoInicial = PeriodoDashboard.mes(DateTime.now());
    Future.microtask(() => _cargar(periodoInicial));
    return DashboardState(periodo: periodoInicial);
  }

  Future<void> cambiarPeriodo(PeriodoDashboard periodo) => _cargar(periodo);

  Future<void> recargar() => _cargar(state.periodo ?? PeriodoDashboard.mes(DateTime.now()));

  Future<void> _cargar(PeriodoDashboard periodo) async {
    state = state.copyWith(cargando: true, errorCarga: null, periodo: periodo);
    try {
      final permissionService = ref.read(permissionServiceProvider);
      bool tiene(String codigo) => permissionService.hasCode(codigo);

      final incluirFinanzas = tiene('finanzas.ver');
      final incluirCompras = tiene('compras.ver');
      final incluirNomina = tiene('nomina.ver');
      final incluirComercial = tiene('comercial.ver');
      final incluirPersonal = tiene('personal.ver');
      final incluirInventario = tiene('inventario.ver');
      final incluirVehiculos = tiene('vehiculos.ver');
      final incluirTelefonia = tiene('telefonia.ver');

      final hoy = DateTime.now();

      final resumenGeneral = await ref.read(obtenerResumenGeneralUseCaseProvider).ejecutar(
            rango: RangoPeriodo(inicio: periodo.inicio, fin: periodo.finConHora),
            incluirFinanzas: incluirFinanzas,
            incluirCompras: incluirCompras,
            incluirNomina: incluirNomina,
            // Personal activo se toma de resumenPersonal.totalActivos —
            // nunca se pide dos veces la misma cuenta.
            incluirPersonal: false,
            incluirComercial: incluirComercial,
            // El Dashboard no pinta comparación de periodo ni antigüedad de
            // cartera: pedirlas sería pagar dos barridos que nadie ve.
            incluirComparacion: false,
            incluirCartera: false,
          );

      final resumenPersonal = incluirPersonal
          ? await ref.read(obtenerResumenPersonalUseCaseProvider).ejecutar(rangoInicio: periodo.inicio, rangoFin: periodo.finConHora)
          : null;

      final resumenNomina = incluirNomina
          ? await ref.read(obtenerResumenNominaUseCaseProvider).ejecutar(rangoInicio: periodo.inicio, rangoFin: periodo.finConHora)
          : null;

      final resumenInventario = incluirInventario
          ? await ref.read(obtenerResumenInventarioUseCaseProvider).ejecutar(rangoInicio: periodo.inicio, rangoFin: periodo.finConHora)
          : null;

      final resumenVehiculos = incluirVehiculos
          ? await ref.read(obtenerResumenVehiculosUseCaseProvider).ejecutar(rangoInicio: periodo.inicio, rangoFin: periodo.finConHora)
          : null;

      final resumenTelefonia = incluirTelefonia
          ? await ref.read(obtenerResumenTelefoniaUseCaseProvider).ejecutar(rangoInicio: periodo.inicio, rangoFin: periodo.finConHora)
          : null;

      // Tiempos Extra (cobertura operativa por ausencia, pedido
      // explícito de Marlon) — mismo use case que ya usa la propia
      // pantalla "Tiempos Extra" para sus KPIs, nunca una segunda
      // lógica de agregación.
      final resumenTiemposExtra = incluirPersonal
          ? await ref.read(obtenerResumenTiemposExtraUseCaseProvider).ejecutar(rangoInicio: periodo.inicio, rangoFin: periodo.finConHora)
          : null;

      // Cobertura operativa: SIEMPRE estado actual real, nunca afectado
      // por el periodo elegido (Parte B: "el periodo no debe falsear
      // la cobertura actual").
      final resumenCobertura =
          incluirComercial ? await ref.read(obtenerCoberturaOperativaUseCaseProvider).ejecutar(hoy: hoy) : null;

      final resumenCobranza =
          incluirFinanzas ? await ref.read(obtenerResumenCobranzaUseCaseProvider).ejecutar(hoy: hoy) : null;

      // Saldo disponible de caja (Etapa 20, 5º KPI ejecutivo) — SIEMPRE
      // estado actual real, nunca afectado por el periodo elegido
      // (mismo criterio que Cobertura operativa).
      final posicionCaja = incluirFinanzas ? await ref.read(obtenerPosicionDeCajaUseCaseProvider).ejecutar() : null;

      // Crédito disponible de TDC (Etapa "Dashboard: posición
      // financiera", 6º KPI ejecutivo) — mismo gate y mismo criterio de
      // snapshot actual que `posicionCaja`, nunca sumado con ella.
      final creditoDisponibleTarjetas =
          incluirFinanzas ? await ref.read(obtenerCreditoDisponibleTarjetasUseCaseProvider).ejecutar() : null;

      final serieFinanciera = incluirFinanzas
          ? await ref.read(obtenerSerieFinancieraUseCaseProvider).ejecutar(rangoInicio: periodo.inicio, rangoFin: periodo.fin)
          : null;

      PersonalOperativoDashboard? personalOperativo;
      if (incluirPersonal) {
        // Fuente de verdad ÚNICA: aquí NO se clasifica a nadie. Antes
        // este bloque comparaba "empleados con Servicio" contra "todos
        // los activos" y por eso un administrativo bien adscrito
        // hundía el porcentaje (bug real del 94%).
        final plantilla = await ref.read(obtenerPlantillaPersonalUseCaseProvider).ejecutar();
        final promedioDiasCobertura = await ref.read(vacanteOperativaRepositoryProvider).promedioDuracionCobertura();
        // Rotación: métrica de PERIODO, así que sí usa el rango
        // seleccionado — a diferencia de los conteos de arriba, que son
        // snapshot de hoy.
        final rotacion = await ref.read(obtenerRotacionPersonalUseCaseProvider).ejecutarOperativa(
              rangoInicio: periodo.inicio,
              rangoFin: periodo.fin,
            );
        personalOperativo = PersonalOperativoDashboard(
          totalActivos: plantilla.totalActivos,
          operativa: plantilla.operativa,
          administrativa: plantilla.administrativa,
          sinAsignacion: plantilla.sinAsignacion.length,
          inconsistentes: plantilla.inconsistentes.length,
          vacantesAbiertas: resumenCobertura?.totalVacantes ?? 0,
          promedioDiasCobertura: promedioDiasCobertura,
          rotacionOperativa: rotacion.porcentaje,
        );
      }

      final proximaNominaUseCase = ref.read(obtenerProximaNominaUseCaseProvider);
      final proximaNomina = incluirNomina ? await proximaNominaUseCase.ejecutar() : null;
      final proximaNominaTotal = proximaNomina != null ? await proximaNominaUseCase.calcularTotal(proximaNomina.id) : null;

      final alertas = await ref.read(obtenerAlertasDashboardUseCaseProvider).ejecutar(
            incluirCxC: incluirFinanzas,
            incluirEmpleadosBajaConPendiente: incluirPersonal && incluirInventario,
            incluirTarjetas: incluirFinanzas,
            incluirDocumentosPorEmitir: incluirComercial,
            hoy: hoy,
          );

      final actividad = await ref.read(obtenerActividadRecienteUseCaseProvider).ejecutar(
            incluirCompras: incluirCompras,
            incluirPagos: incluirFinanzas,
            incluirInventario: incluirInventario,
            incluirTelefonia: incluirTelefonia,
            incluirComercial: incluirComercial,
            rangoInicio: periodo.inicio,
            rangoFin: periodo.finConHora,
          );

      state = DashboardState(
        cargando: false,
        periodo: periodo,
        resumenGeneral: resumenGeneral,
        resumenPersonal: resumenPersonal,
        resumenNomina: resumenNomina,
        resumenInventario: resumenInventario,
        resumenVehiculos: resumenVehiculos,
        resumenTelefonia: resumenTelefonia,
        resumenTiemposExtra: resumenTiemposExtra,
        resumenCobertura: resumenCobertura,
        resumenCobranza: resumenCobranza,
        posicionCaja: posicionCaja,
        creditoDisponibleTarjetas: creditoDisponibleTarjetas,
        personalOperativo: personalOperativo,
        proximaNomina: proximaNomina,
        proximaNominaTotal: proximaNominaTotal,
        serieFinanciera: serieFinanciera,
        alertas: alertas,
        actividad: actividad,
      );
    } catch (e) {
      state = state.copyWith(cargando: false, errorCarga: e.toString());
    }
  }
}
