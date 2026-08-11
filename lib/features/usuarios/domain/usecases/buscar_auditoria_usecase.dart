import '../repositories/auditoria_repository.dart';

/// Una fila unificada de la pantalla de Auditoría central (Etapa 11D)
/// — agrega los ~17 orígenes reales de eventos del proyecto (las
/// tablas `XxxEvento` de cada dominio + los ledgers append-only que ya
/// eran su propio evento, ej. `MovimientoInventario`/
/// `VehiculoKilometraje`, + `UsuarioEvento` + `EliminacionFisicaEvento`)
/// en una sola forma legible: Fecha/hora | Usuario | Módulo | Acción |
/// Registro | Motivo, tal como pidió Marlon. `detalleJson` solo se usa
/// para el panel de detalle bajo demanda — nunca se muestra crudo en
/// la tabla principal.
class EventoAuditoria {
  const EventoAuditoria({
    required this.fechaHora,
    required this.actorUsuarioId,
    required this.modulo,
    required this.accion,
    required this.registroId,
    this.motivo,
    this.detalleJson,
  });

  final DateTime fechaHora;
  final String? actorUsuarioId;

  /// Código de módulo (ej. `'compras'`, `'inventario'`) — mismo
  /// vocabulario que `modulos_permiso.dart`, para que el filtro de la
  /// pantalla pueda reutilizar las mismas etiquetas ya traducidas.
  final String modulo;

  /// Tipo de evento/movimiento crudo (ej. `'registrada'`, `'ajuste'`) —
  /// la UI lo traduce a una etiqueta legible por módulo, igual que ya
  /// hace cada diálogo de historial individual.
  final String accion;

  final String registroId;
  final String? motivo;
  final String? detalleJson;
}

class FiltroAuditoria {
  const FiltroAuditoria({this.actorUsuarioId, this.modulo, this.accion, this.desde, this.hasta});

  final String? actorUsuarioId;
  final String? modulo;
  final String? accion;
  final DateTime? desde;
  final DateTime? hasta;
}

/// Fachada de solo lectura de la Auditoría central (Etapa 11D) — mismo
/// criterio cross-domain que `BuscarInventarioUseCase` (7D): agrega
/// datos de varios dominios sin que ningún dominio dependa de otro.
class BuscarAuditoriaUseCase {
  BuscarAuditoriaUseCase(this._repository);

  final AuditoriaRepository _repository;

  Future<List<EventoAuditoria>> ejecutar(FiltroAuditoria filtro) => _repository.buscar(filtro);
}
