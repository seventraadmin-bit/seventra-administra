/// Escritores de las tres bitácoras de Comercial.
///
/// Mismo criterio que `registrarEventoEmpleado` (Personal, el dominio
/// más maduro): funciones sueltas que reciben la `AppDatabase` para
/// poder componerse DENTRO de la transacción del repositorio que las
/// llama. Un evento nunca se escribe fuera de la transacción del cambio
/// que describe: o quedan los dos, o no queda ninguno.
library;

import 'dart:convert';
import 'package:drift/drift.dart' show Value;

import 'package:riseg_one/core/database/app_database.dart';

import '../tables/comercial_evento_table.dart';

Future<void> registrarEventoCliente(
  AppDatabase db, {
  required String clienteId,
  required TipoEventoCliente tipoEvento,
  String? estadoAnterior,
  String? estadoNuevo,
  String? observacion,
  String? actorUsuarioId,
  Map<String, dynamic>? datosRelevantes,
}) {
  return db.into(db.clienteEvento).insert(
        ClienteEventoCompanion.insert(
          clienteId: clienteId,
          fechaHora: DateTime.now(),
          tipoEvento: tipoEvento.name,
          estadoAnterior: Value(estadoAnterior),
          estadoNuevo: Value(estadoNuevo),
          observacion: Value(observacion),
          actorUsuarioId: Value(actorUsuarioId),
          datosRelevantes: Value(datosRelevantes == null ? null : jsonEncode(datosRelevantes)),
        ),
      );
}

Future<void> registrarEventoServicio(
  AppDatabase db, {
  required String servicioId,
  required TipoEventoServicio tipoEvento,
  String? estadoAnterior,
  String? estadoNuevo,
  String? observacion,
  String? actorUsuarioId,
  Map<String, dynamic>? datosRelevantes,
}) {
  return db.into(db.servicioEvento).insert(
        ServicioEventoCompanion.insert(
          servicioId: servicioId,
          fechaHora: DateTime.now(),
          tipoEvento: tipoEvento.name,
          estadoAnterior: Value(estadoAnterior),
          estadoNuevo: Value(estadoNuevo),
          observacion: Value(observacion),
          actorUsuarioId: Value(actorUsuarioId),
          datosRelevantes: Value(datosRelevantes == null ? null : jsonEncode(datosRelevantes)),
        ),
      );
}

Future<void> registrarEventoConfiguracionCobro(
  AppDatabase db, {
  required String configuracionCobroId,
  required TipoEventoConfiguracionCobro tipoEvento,
  String? estadoAnterior,
  String? estadoNuevo,
  String? observacion,
  String? actorUsuarioId,
  Map<String, dynamic>? datosRelevantes,
}) {
  return db.into(db.configuracionCobroEvento).insert(
        ConfiguracionCobroEventoCompanion.insert(
          configuracionCobroId: configuracionCobroId,
          fechaHora: DateTime.now(),
          tipoEvento: tipoEvento.name,
          estadoAnterior: Value(estadoAnterior),
          estadoNuevo: Value(estadoNuevo),
          observacion: Value(observacion),
          actorUsuarioId: Value(actorUsuarioId),
          datosRelevantes: Value(datosRelevantes == null ? null : jsonEncode(datosRelevantes)),
        ),
      );
}
