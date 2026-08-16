DateTime _soloFecha(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

/// Un Servicio con la vigencia de cobro que le aplica para un periodo
/// dado — el insumo mínimo que la agrupación necesita para decidir si
/// puede juntarse con otro en un mismo `DocumentoPorEmitir`. Deliberada-
/// mente sin depender de las clases `Data` generadas por Drift: esta
/// función es pura y se prueba con valores simples, sin base de datos.
class CandidatoDocumentoPorEmitir {
  const CandidatoDocumentoPorEmitir({
    required this.servicioId,
    required this.clienteId,
    required this.tipoDocumento,
    required this.metodo,
    required this.requiereComplemento,
    required this.periodoInicio,
    required this.periodoFin,
    required this.configuracionCobroVigenciaId,
    this.entidadFiscalId,
    this.clientePortalId,
  });

  final String servicioId;
  final String clienteId;
  final String? entidadFiscalId;

  /// Qué `ClientePortal` usa la vigencia de este candidato — nunca es
  /// criterio de compatibilidad de agrupación (a diferencia de Entidad
  /// fiscal): dos Servicios con portales distintos se agrupan igual si
  /// cumplen el resto de las condiciones; el documento resultante solo
  /// hereda el portal del primer candidato del grupo, mismo criterio que
  /// `entidadFiscalId` cuando `tipoDocumento != cfdi`.
  final String? clientePortalId;
  final String tipoDocumento;
  final String metodo;
  final bool requiereComplemento;
  final DateTime periodoInicio;
  final DateTime periodoFin;
  final String configuracionCobroVigenciaId;
}

/// Compatibilidad de agrupación (Etapa 4I.1, requisito explícito de
/// Marlon) — dos Servicios solo pueden compartir un documento si
/// coinciden en: Cliente, tipo de documento, Entidad fiscal (cuando es
/// CFDI), periodoInicio, periodoFin, método y condición de complemento.
/// Nunca se agrupa solo porque comparten Cliente o Entidad fiscal —
/// compartir esos dos campos es necesario pero no suficiente.
bool sonCompatiblesParaAgrupar(CandidatoDocumentoPorEmitir a, CandidatoDocumentoPorEmitir b) {
  if (a.clienteId != b.clienteId) return false;
  if (a.tipoDocumento != b.tipoDocumento) return false;
  if (a.tipoDocumento == 'cfdi' && a.entidadFiscalId != b.entidadFiscalId) return false;
  if (_soloFecha(a.periodoInicio) != _soloFecha(b.periodoInicio)) return false;
  if (_soloFecha(a.periodoFin) != _soloFecha(b.periodoFin)) return false;
  if (a.metodo != b.metodo) return false;
  if (a.requiereComplemento != b.requiereComplemento) return false;
  return true;
}

/// Agrupa una lista de candidatos (ya filtrados a una sola combinación
/// agrupación×Cliente/Entidad fiscal×rango de búsqueda) en los grupos
/// compatibles más grandes posibles — nunca mezcla condiciones
/// distintas en un solo grupo, aunque eso signifique más de un
/// documento para el mismo Cliente/Entidad fiscal en el mismo periodo.
List<List<CandidatoDocumentoPorEmitir>> agruparCompatibles(List<CandidatoDocumentoPorEmitir> candidatos) {
  final grupos = <List<CandidatoDocumentoPorEmitir>>[];

  for (final candidato in candidatos) {
    List<CandidatoDocumentoPorEmitir>? grupoCompatible;
    for (final grupo in grupos) {
      if (sonCompatiblesParaAgrupar(grupo.first, candidato)) {
        grupoCompatible = grupo;
        break;
      }
    }
    if (grupoCompatible != null) {
      grupoCompatible.add(candidato);
    } else {
      grupos.add([candidato]);
    }
  }

  return grupos;
}
