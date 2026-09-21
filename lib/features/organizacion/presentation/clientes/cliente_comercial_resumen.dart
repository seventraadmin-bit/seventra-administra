import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/organizacion/data/tables/documento_por_emitir_table.dart' show EstatusDocumentoPorEmitir;
import 'package:riseg_one/features/organizacion/data/tables/servicio_table.dart' show EstatusServicio;
import 'package:riseg_one/features/organizacion/domain/repositories/servicio_repository.dart';
import 'package:riseg_one/features/personal/personal_providers.dart';

import '../../organizacion_providers.dart';

/// Resumen comercial de UN Servicio dentro del expediente de su Cliente
/// (Etapa 16) — Personal asignado e importe mensual, ambos ya
/// resueltos sin consultas adicionales por fila (ver
/// [clienteComercialResumenProvider]).
class ServicioResumenCliente {
  const ServicioResumenCliente({
    required this.item,
    required this.personalAsignado,
    required this.importeMensual,
  });

  final ServicioListItem item;
  final int personalAsignado;
  final int importeMensual;
}

/// Resumen comercial completo de un Cliente (Etapa 16, expediente
/// comercial) — sus propios Servicios (cada uno con Personal asignado
/// e importe mensual ya resueltos) y sus propios Documentos por emitir
/// (`DocumentoPorEmitir.clienteId`, relación real ya usada por los
/// filtros de Agenda).
class ClienteComercialResumen {
  const ClienteComercialResumen({required this.servicios, this.documentos = const []});

  final List<ServicioResumenCliente> servicios;
  final List<DocumentoPorEmitirData> documentos;

  int get serviciosActivos =>
      servicios.where((s) => s.item.servicio.estatus == EstatusServicio.activo.name).length;

  /// Suma de Personal por Servicio — segura sin doble conteo porque un
  /// Empleado solo puede tener UNA asignación vigente a la vez
  /// (`AsignacionServicio`), por lo que nunca aparece en dos Servicios
  /// de este mismo Cliente simultáneamente.
  int get personalTotal => servicios.fold(0, (acc, s) => acc + s.personalAsignado);

  int get importeMensualTotal => servicios.fold(0, (acc, s) => acc + s.importeMensual);

  /// Documentos aún no resueltos administrativamente — únicamente los
  /// dos estatus reales que representan trabajo pendiente
  /// (`pendiente`/`enPreparacion`); nunca se inventa un estatus
  /// "vencido" que no existe en el modelo.
  int get documentosPendientes => documentos
      .where(
        (d) =>
            d.estatus == EstatusDocumentoPorEmitir.pendiente.name ||
            d.estatus == EstatusDocumentoPorEmitir.enPreparacion.name,
      )
      .length;
}

/// Carga, en un solo golpe por Cliente, sus propios Servicios más
/// Personal asignado e importe mensual contratado (Etapa 16, ficha
/// comercial del Cliente) — independiente de `ClienteExpedienteController`
/// para no arriesgar su ciclo de edición/guardado existente.
///
/// Costo: dos consultas en lote (Servicio, AsignacionServicio — ambas
/// ya usadas por el listado de Clientes) más una consulta de líneas
/// comerciales POR CADA Servicio de ESTE Cliente únicamente — acotado
/// al tamaño real de la cartera de un solo Cliente, nunca al listado
/// completo (mismo criterio ya usado para agregaciones propias de una
/// sola entidad en otros expedientes de esta etapa).
final clienteComercialResumenProvider = FutureProvider.family<ClienteComercialResumen, String>((ref, clienteId) async {
  final servicioRepo = ref.watch(servicioRepositoryProvider);
  final asignacionRepo = ref.watch(asignacionServicioRepositoryProvider);
  final comercialRepo = ref.watch(servicioComercialRepositoryProvider);
  final documentoRepo = ref.watch(documentoPorEmitirRepositoryProvider);

  final todosServicios = await servicioRepo.listar();
  final serviciosCliente = todosServicios.where((s) => s.servicio.clienteId == clienteId).toList();

  final asignacionesActivas = await asignacionRepo.listarTodasActivas();
  final personalPorServicio = <String, int>{};
  for (final a in asignacionesActivas) {
    personalPorServicio[a.servicioId] = (personalPorServicio[a.servicioId] ?? 0) + 1;
  }

  final resumen = <ServicioResumenCliente>[];
  for (final item in serviciosCliente) {
    final lineas = await comercialRepo.listarLineas(item.servicio.id);
    final importeMensual = lineas.fold(0, (acc, l) => acc + l.subtotal);
    resumen.add(
      ServicioResumenCliente(
        item: item,
        personalAsignado: personalPorServicio[item.servicio.id] ?? 0,
        importeMensual: importeMensual,
      ),
    );
  }

  final documentos = await documentoRepo.listar(clienteId: clienteId);

  return ClienteComercialResumen(servicios: resumen, documentos: documentos);
});
