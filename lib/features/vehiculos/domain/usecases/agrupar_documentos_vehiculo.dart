import 'package:riseg_one/core/database/app_database.dart';

/// Agrupa una lista de `VehiculoDocumento` (ya ordenada descendente por
/// `fechaEmision`/`createdAt`, ver `VehiculoDocumentoRepository`) por
/// `tipo`, quedándose con el primero de cada grupo — "el documento
/// vigente de ese tipo" (ver el doc comment de `VehiculoDocumento`).
/// Usado tanto por el expediente del Vehículo (lista compacta) como
/// por la pantalla de Alertas — una sola función, nunca dos criterios
/// de "cuál es el vigente" divergiendo entre pantallas.
List<VehiculoDocumentoData> documentosVigentesPorTipo(List<VehiculoDocumentoData> documentosOrdenados) {
  final vistos = <String>{};
  final vigentes = <VehiculoDocumentoData>[];
  for (final documento in documentosOrdenados) {
    if (vistos.add(documento.tipo)) vigentes.add(documento);
  }
  return vigentes;
}
