import 'package:riseg_one/features/organizacion/domain/repositories/cliente_repository.dart';
import 'package:riseg_one/features/organizacion/domain/repositories/documento_por_emitir_repository.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/documento_por_emitir_requiere_accion.dart';

import 'resultado_notificacion.dart';

/// Documentos por emitir que ya corresponde generar — Etapa 14B.
/// Reutiliza `documentoPorEmitirRequiereAccion` (extraída de la Agenda
/// en esta misma etapa) — la misma regla, nunca duplicada.
class ObtenerNotificacionesDocumentosPorEmitirUseCase {
  ObtenerNotificacionesDocumentosPorEmitirUseCase(this._documentoRepository, this._clienteRepository);

  final DocumentoPorEmitirRepository _documentoRepository;
  final ClienteRepository _clienteRepository;

  Future<List<ResultadoNotificacion>> ejecutar({DateTime? hoy}) async {
    final referencia = hoy ?? DateTime.now();

    final pendientes = await _documentoRepository.listar(estatus: 'pendiente');
    final enPreparacion = await _documentoRepository.listar(estatus: 'enPreparacion');
    final candidatos = [...pendientes, ...enPreparacion]
        .where((documento) => documentoPorEmitirRequiereAccion(documento, referencia))
        .toList();

    if (candidatos.isEmpty) return const [];

    final clientes = await _clienteRepository.listarActivos();
    final nombrePorCliente = {for (final c in clientes) c.id: c.nombreComercial};

    return [
      for (final documento in candidatos)
        ResultadoNotificacion(
          id: documento.id,
          titulo: nombrePorCliente[documento.clienteId] ?? documento.clienteId,
          subtitulo: documento.codigo,
          ruta: '/comercial/agenda',
          urgente: true,
        ),
    ];
  }
}
