import 'package:riseg_one/core/database/app_database.dart';

import '../../domain/usecases/calcular_totales_esperados_usecase.dart';

/// El total esperado de un documento tal como lo muestra la Agenda: el
/// importe que comercialmente esperamos cobrar, ya con el ajuste y con el
/// IVA que corresponda. `null` cuando no existe un total fiscalmente
/// comparable, que es distinto de cero.
///
/// Es una sola línea de pegamento entre los snapshots persistidos y
/// `totalesEsperadosDeDocumento`, pero vive aquí —y no dentro del
/// controlador— para que la prueba pueda ejercitar exactamente el mismo
/// camino que la pantalla, en vez de reproducirlo y quedarse pasando si la
/// pantalla cambia.
int? totalEsperadoDeDocumento(DocumentoPorEmitirData documento, List<DocumentoPorEmitirLineaData> lineas) {
  return totalesEsperadosDeDocumento(
    importeBaseEsperado: documento.importeBaseEsperado,
    ajusteManual: documento.ajusteManual,
    lineas: [
      for (final l in lineas) (subtotalCentavos: l.subtotalProporcional, tratamientoIva: l.tratamientoIva),
    ],
  ).totales?.totalEsperado;
}
