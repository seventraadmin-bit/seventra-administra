import 'tarjeta_fiscal_data.dart';

/// Texto plano de "Copiar datos" (Etapa 16) — función pura, misma
/// fuente que arma la previsualización. Nunca incluye un bloque cuyo
/// valor esté vacío (ej. sin correo capturado, no aparece "Correo:"
/// en absoluto).
String textoCopiarTarjetaFiscal(TarjetaFiscalData data) {
  final bloques = <String>['DATOS PARA FACTURACION', '', 'Razon social:', data.razonSocial, '', 'RFC:', data.rfc];

  if (data.domicilioLineas.isNotEmpty) {
    bloques.addAll(['', 'Domicilio fiscal:', ...data.domicilioLineas]);
  }
  if (data.correo != null) {
    bloques.addAll(['', 'Correo:', data.correo!]);
  }
  if (data.telefono != null) {
    bloques.addAll(['', 'Telefono:', data.telefono!]);
  }
  if (data.sitioWeb != null) {
    bloques.addAll(['', 'Sitio web:', data.sitioWeb!]);
  }

  return bloques.join('\n');
}
