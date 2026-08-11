import 'package:riseg_one/core/database/app_database.dart';

import '../../data/tables/nomina_table.dart';
import '../usecases/calcular_periodo_nomina.dart';
import '../usecases/fila_nomina_generada.dart';

/// Repositorio del motor de Nómina (Etapa 6C). Los métodos de escritura
/// compuesta (`generar`/`guardarRenglon`/`cerrar`) son transaccionales y
/// registran su propio `NominaEvento` — ninguna validación de negocio
/// vive aquí (existencia, unicidad de periodo, bloqueo de cierre por
/// distribución pendiente, etc. viven en los casos de uso), mismo
/// criterio que el resto del proyecto.
abstract interface class NominaRepository {
  Future<NominaData?> obtenerPorId(String id);

  Future<NominaData?> obtenerPorPeriodo({required int anio, required int mes, required TipoPeriodoNomina tipo});

  Future<List<NominaData>> listar();

  Future<List<NominaEmpleadoData>> listarEmpleados(String nominaId);

  Future<NominaEmpleadoData?> obtenerEmpleado(String nominaEmpleadoId);

  Future<NominaEmpleadoData?> obtenerEmpleadoPorNominaYEmpleado({required String nominaId, required String empleadoId});

  Future<List<NominaEmpleadoTramoData>> listarTramos(String nominaEmpleadoId);

  Future<List<NominaEventoData>> listarEventos(String nominaId);

  /// Crea el encabezado de la Nómina y todos sus renglones/tramos
  /// iniciales en una sola transacción — registra el evento `generada`.
  Future<NominaData> generar({
    required String folio,
    required PeriodoNomina periodo,
    required List<FilaNominaGenerada> filas,
    String? actorUsuarioId,
  });

  /// Reemplaza el renglón (y sus tramos) de un Empleado dentro de una
  /// Nómina ya existente — usado por "Actualizar desde Personal" para
  /// los renglones que sí siguen teniendo días pagables. Los campos de
  /// movimientos manuales/distribución los decide el llamador (ya
  /// resueltos contra la fila anterior) y se pasan explícitos.
  Future<NominaEmpleadoData> guardarRenglon({
    required String nominaId,
    required FilaNominaGenerada datos,
    required int prestamo,
    required int tiempoExtra,
    required int bono,
    required bool bonoModificadoManualmente,
    required int faltas,
    required int otrosDescuentos,
    required String? observaciones,
    required int montoFiscal,
    required int montoNoFiscal,
    required bool distribucionModificadaManualmente,
    required bool distribucionPendienteRevision,
  });

  /// Elimina por completo un renglón (y sus tramos) — solo válido para
  /// un renglón que perdió todos sus días pagables **y** nunca tuvo
  /// movimientos manuales capturados (ver
  /// `ActualizarNominaDesdePersonalUseCase`).
  Future<void> eliminarRenglon(String nominaEmpleadoId);

  Future<NominaEmpleadoData> actualizarMovimientos({
    required String nominaEmpleadoId,
    required int prestamo,
    required int tiempoExtra,
    required int bono,
    required bool bonoModificadoManualmente,
    required int faltas,
    required int otrosDescuentos,
    required String? observaciones,
  });

  Future<NominaEmpleadoData> actualizarDistribucion({
    required String nominaEmpleadoId,
    required int montoFiscal,
    required int montoNoFiscal,
  });

  Future<NominaData> cerrar({required String nominaId, String? actorUsuarioId});

  Future<void> registrarEvento({
    required String nominaId,
    String? nominaEmpleadoId,
    required String tipoEvento,
    String? observacion,
    String? actorUsuarioId,
  });
}
