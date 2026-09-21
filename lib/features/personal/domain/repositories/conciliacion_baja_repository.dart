import 'package:riseg_one/core/database/app_database.dart';

import '../usecases/conciliar_baja_empleado_usecase.dart';

/// Persistencia de la conciliación de resguardos de una baja
/// (schemaVersion 83).
///
/// Escritura cruda, sin reglas de negocio: qué exige cada resolución y
/// qué operación dispara en Inventario/Vehículos/Descuentos vive en
/// `ConciliarBajaEmpleadoUseCase`. Aquí solo se guarda lo que ningún
/// otro dominio sabía registrar.
abstract interface class ConciliacionBajaRepository {
  /// Ejecuta [operacion] dentro de UNA transacción (§17).
  ///
  /// La conciliación es una sola operación de negocio: baja laboral +
  /// cierres + movimientos de inventario + descuentos. Si algo falla a
  /// la mitad, no puede quedar el empleado de baja con el inventario a
  /// medias. El use case no conoce la base de datos, así que la unidad
  /// transaccional se expone aquí — mismo seam que ya usan los
  /// repositorios que componen a otros repositorios.
  Future<T> enTransaccion<T>(Future<T> Function() operacion);

  /// Cabecera. Devuelve su id.
  Future<String> crear({
    required String empleadoId,
    required DateTime fechaBaja,
    String? observaciones,
    String? actorUsuarioId,
  });

  /// Un bien conciliado. [descuentoProgramadoId] es la obligación real
  /// creada por este renglón, si la hubo.
  Future<void> agregarRenglon({
    required String conciliacionBajaId,
    required ResolucionResguardo resolucion,
    String? descuentoProgramadoId,
  });

  /// TODAS las conciliaciones, opcionalmente acotadas por fecha de
  /// baja — una sola consulta.
  ///
  /// Existe para Reportes: reconstruir el panorama patrimonial
  /// preguntando conciliación por conciliación sería una consulta por
  /// ex empleado.
  Future<List<ConciliacionBajaData>> listar({DateTime? desde, DateTime? hasta});

  /// Los renglones de varias conciliaciones a la vez, agrupados por
  /// su conciliación. Version en lote de [listarRenglones].
  Future<Map<String, List<ConciliacionBajaRenglonData>>> listarRenglonesPorConciliaciones(Iterable<String> ids);

  Future<ConciliacionBajaData?> obtenerPorEmpleado(String empleadoId);

  /// Renglones de una conciliación, para reconstruir "qué pasó en la
  /// baja de Juan" como una sola operación.
  Future<List<ConciliacionBajaRenglonData>> listarRenglones(String conciliacionBajaId);
}
