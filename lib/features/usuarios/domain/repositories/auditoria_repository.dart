import '../usecases/buscar_auditoria_usecase.dart';

abstract interface class AuditoriaRepository {
  Future<List<EventoAuditoria>> buscar(FiltroAuditoria filtro);
}
