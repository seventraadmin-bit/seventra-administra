import 'package:riseg_one/core/database/tables/attachment_table.dart';
import 'package:riseg_one/features/organizacion/data/tables/configuracion_cobro_vigencia_table.dart';

/// Compatibilidad categoría↔tipo de documento (Etapa 4I.2.2) — `cfdiPdf`/
/// `cfdiXml` solo para CFDI, `reciboPdf` solo para recibo, `otroSoporte`
/// siempre permitido (Resolución 7 de Marlon: sin restricciones). Nunca
/// se valida solo en la interfaz — el dominio la exige siempre.
bool categoriaCompatibleConTipoDocumento(
  CategoriaAdjuntoDocumentoPorEmitir categoria,
  TipoDocumentoCobro tipoDocumento,
) {
  return switch (categoria) {
    CategoriaAdjuntoDocumentoPorEmitir.cfdiPdf ||
    CategoriaAdjuntoDocumentoPorEmitir.cfdiXml =>
      tipoDocumento == TipoDocumentoCobro.cfdi,
    CategoriaAdjuntoDocumentoPorEmitir.reciboPdf => tipoDocumento == TipoDocumentoCobro.reciboDePago,
    CategoriaAdjuntoDocumentoPorEmitir.otroSoporte => true,
  };
}

/// Validación de tipo de archivo por categoría — `cfdiPdf`/`reciboPdf`
/// exigen PDF, `cfdiXml` exige XML, `otroSoporte` acepta cualquier
/// formato (Resolución 7 de Marlon: nunca una lista cerrada).
bool tipoArchivoValidoParaCategoria(CategoriaAdjuntoDocumentoPorEmitir categoria, String mimeType) {
  return switch (categoria) {
    CategoriaAdjuntoDocumentoPorEmitir.cfdiPdf ||
    CategoriaAdjuntoDocumentoPorEmitir.reciboPdf =>
      mimeType == 'application/pdf',
    CategoriaAdjuntoDocumentoPorEmitir.cfdiXml => mimeType == 'text/xml' || mimeType == 'application/xml',
    CategoriaAdjuntoDocumentoPorEmitir.otroSoporte => true,
  };
}
