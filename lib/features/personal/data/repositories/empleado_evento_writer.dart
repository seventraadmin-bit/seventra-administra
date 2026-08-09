import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/personal/data/tables/empleado_table.dart';

/// Inserta una fila en el historial administrativo de un Empleado —
/// extraído de `EmpleadoRepositoryImpl._registrarEvento` (Etapa 5D) para
/// que `AsignacionServicioRepositoryImpl` también pueda registrar
/// eventos de Asignación/Cambio/Retiro de Servicio sin depender de
/// `EmpleadoRepositoryImpl` (evita una llamada entre repositorios para
/// algo tan simple como un `INSERT`; ambos ya comparten el mismo `db`
/// dentro de la misma transacción).
Future<void> registrarEventoEmpleado(
  AppDatabase db, {
  required String empleadoId,
  required TipoEventoEmpleado tipoEvento,
  String? estadoAnterior,
  String? estadoNuevo,
  String? observacion,
  String? actor,
  Map<String, dynamic>? datosRelevantes,
}) {
  return db.into(db.empleadoEvento).insert(
        EmpleadoEventoCompanion.insert(
          empleadoId: empleadoId,
          fechaHora: DateTime.now(),
          tipoEvento: tipoEvento.name,
          estadoAnterior: Value(estadoAnterior),
          estadoNuevo: Value(estadoNuevo),
          observacion: Value(observacion),
          actor: Value(actor),
          datosRelevantes: Value(datosRelevantes == null ? null : jsonEncode(datosRelevantes)),
        ),
      );
}
