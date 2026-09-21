import 'package:riseg_one/core/database/app_database.dart';

/// Lectura de `Entrega` (cabecera documental de "Entregar equipo") —
/// solo lectura en esta etapa: la única escritura vive en
/// `EntregarEquipoUseCase`, que inserta la fila directamente dentro de
/// la misma transacción que crea sus Asignaciones (ver el doc comment
/// de ese caso de uso para el porqué de no pasar por aquí).
abstract interface class EntregaRepository {
  Future<EntregaData?> obtenerPorId(String id);

  Future<List<EntregaData>> listarPorEmpleado(String empleadoId);

  Future<List<EntregaData>> listarPorServicio(String servicioId);
}
