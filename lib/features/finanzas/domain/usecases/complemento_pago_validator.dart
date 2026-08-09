import 'package:riseg_one/features/finanzas/data/tables/complemento_pago_table.dart';

/// Formato UUID estándar (8-4-4-4-12 hexadecimal) — deliberadamente
/// sin exigir versión ni variante específicas (Resolución de Marlon:
/// "no quiero acoplar el sistema a una versión específica del UUID
/// emitido por el PAC"). Solo valida forma y longitud; la unicidad se
/// valida aparte, contra la base de datos.
final RegExp _formatoUuid = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

bool esUuidFormatoValido(String valor) => _formatoUuid.hasMatch(valor);

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
