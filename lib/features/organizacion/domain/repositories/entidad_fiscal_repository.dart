import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/tables/audit_columns.dart';

import '../shared/direccion_input.dart';

/// Entidad fiscal junto con su domicilio fiscal, si existe — lo que
/// necesita la sección "Entidades fiscales" del expediente de Cliente
/// para decidir si mostrar "Datos fiscales incompletos" (mismo patrón
/// compuesto que `ClienteExpedienteData`).
class EntidadFiscalConDomicilio {
  const EntidadFiscalConDomicilio({required this.entidadFiscal, this.domicilioFiscal});

  final EntidadFiscalData entidadFiscal;
  final DireccionData? domicilioFiscal;

  /// Condición derivada, nunca almacenada: incompleta si no hay
  /// domicilio fiscal activo. `DireccionValidator` ya impide que exista
  /// un domicilio con campos mínimos faltantes, así que en la práctica
  /// esto se reduce a "¿existe?".
  bool get datosFiscalesCompletos => domicilioFiscal != null;
}

abstract interface class EntidadFiscalRepository {
  Future<EntidadFiscalData> crear(EntidadFiscalCompanion datos, {String? actorUsuarioId});

  Future<EntidadFiscalData?> obtenerPorId(String id);

  /// Todas las Entidades fiscales del Cliente — activas **y**
  /// archivadas: una archivada debe seguir siendo encontrable para
  /// reactivarla.
  Future<List<EntidadFiscalConDomicilio>> listarPorCliente(String clienteId);

  /// Entidades fiscales por id, en una sola consulta — mismo criterio
  /// de lote que ClienteRepository.listarPorIds.
  Future<Map<String, EntidadFiscalData>> listarPorIds(Iterable<String> ids);

  /// / alimentan la bitácora del Cliente dueño:
  /// RFC y razón social son datos fiscales, y corregirlos sin explicar
  /// por qué era el hueco más grave del área.
  Future<EntidadFiscalData> actualizar({
    required String id,
    required EntidadFiscalCompanion cambios,
    String? motivo,
    String? actorUsuarioId,
  });

  Future<EntidadFiscalData> cambiarCicloVida({
    required String id,
    required CicloVidaRegistro nuevo,
    String? motivo,
    String? actorUsuarioId,
  });

  /// [rfcNormalizado] ya debe venir en mayúsculas y sin espacios — este
  /// repositorio no normaliza, eso es responsabilidad del validador.
  /// [excluirId], si se da, ignora esa fila (para permitir "guardar sin
  /// cambiar el RFC propio" al actualizar).
  Future<bool> existeRfc(String rfcNormalizado, {String? excluirId});

  Future<DireccionData?> obtenerDomicilioFiscal(String entidadFiscalId);

  Future<DireccionData?> guardarDomicilioFiscal(String entidadFiscalId, DireccionInput? input);
}
