import 'empresa_expediente_data.dart';

/// Campo indispensable para generar la Tarjeta fiscal (Etapa 16) — la
/// lista completa de qué se considera "indispensable" vive únicamente
/// aquí, nunca duplicada en la UI. `regimenFiscal`/`usoCfdi` NO
/// aparecen: ninguno de los dos existe hoy como dato estructurado en
/// `Empresa` (auditado antes de implementar), así que nunca pueden ser
/// requeridos — la tarjeta simplemente los omite cuando faltan (ver
/// `construirTarjetaFiscalData`).
enum CampoFiscalFaltante { razonSocial, rfc, domicilioFiscal }

/// Determina qué campos indispensables faltan para generar una Tarjeta
/// fiscal creíble — función pura, sin BD. Vacía significa "se puede
/// generar". Nunca se exigen campos meramente decorativos (correo/
/// teléfono/sitio web son de contacto, no fiscales: la tarjeta los
/// muestra si existen, pero su ausencia no bloquea nada).
List<CampoFiscalFaltante> validarDatosFiscalesTarjeta(EmpresaExpedienteData datos) {
  final faltantes = <CampoFiscalFaltante>[];
  if ((datos.empresa.razonSocial ?? '').trim().isEmpty) faltantes.add(CampoFiscalFaltante.razonSocial);
  if ((datos.empresa.rfc ?? '').trim().isEmpty) faltantes.add(CampoFiscalFaltante.rfc);
  if (datos.direccionFiscal == null) faltantes.add(CampoFiscalFaltante.domicilioFiscal);
  return faltantes;
}
