import 'package:riseg_one/features/finanzas/data/tables/complemento_pago_table.dart';

export 'package:riseg_one/core/validation/uuid_validator.dart' show esUuidFormatoValido;

/// Validación de tipo de archivo por categoría de un adjunto de
/// `ComplementoPago` — mismo criterio que
/// `tipoArchivoValidoParaCategoria` en Adjuntos de `DocumentoPorEmitir`,
/// sin categoría "otro": un Complemento real siempre trae exactamente
/// un PDF y un XML.
bool tipoArchivoValidoParaCategoriaComplemento(CategoriaAdjuntoComplementoPago categoria, String mimeType) {
  return switch (categoria) {
    CategoriaAdjuntoComplementoPago.pdf => mimeType == 'application/pdf',
    CategoriaAdjuntoComplementoPago.xml => mimeType == 'text/xml' || mimeType == 'application/xml',
  };
}
