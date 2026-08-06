String _soloFechaIso(DateTime dt) =>
    '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

/// Clave determinista de generación (Etapa 4I.1) — protege la
/// idempotencia real cuando un documento agrupado puede depender de
/// varias vigencias de cobro a la vez, así que un `UNIQUE` simple sobre
/// una sola vigencia + periodo no alcanza. Calculada a partir de
/// exactamente los mismos insumos que determinan "es el mismo
/// documento": tipo de agrupación, Cliente, Entidad fiscal, el conjunto
/// ordenado de Servicios, el conjunto ordenado de vigencias de cobro,
/// el periodo y el tipo de documento — nunca del `id` de nada generado
/// (esos cambian cada vez).
///
/// Los conjuntos se ordenan antes de concatenar para que el mismo grupo
/// de Servicios/vigencias produzca la misma clave sin importar el orden
/// en que se hayan resuelto.
String calcularGenerationKey({
  required String agrupacion,
  required String tipoDocumento,
  required String clienteId,
  required List<String> servicioIds,
  required List<String> configuracionCobroVigenciaIds,
  required DateTime periodoInicio,
  required DateTime periodoFin,
  String? entidadFiscalId,
}) {
  final servicios = [...servicioIds]..sort();
  final vigencias = [...configuracionCobroVigenciaIds]..sort();

  return [
    agrupacion,
    clienteId,
    entidadFiscalId ?? '',
    servicios.join(','),
    vigencias.join(','),
    _soloFechaIso(periodoInicio),
    _soloFechaIso(periodoFin),
    tipoDocumento,
  ].join('|');
}
