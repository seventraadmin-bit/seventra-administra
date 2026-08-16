/// Formato UUID estándar (8-4-4-4-12 hexadecimal) — deliberadamente
/// sin exigir versión ni variante específicas (Resolución de Marlon:
/// "no quiero acoplar el sistema a una versión específica del UUID
/// emitido por el PAC"). Solo valida forma y longitud; la unicidad se
/// valida aparte, contra la base de datos.
///
/// Compartido entre `ComplementoPago.uuid` (Etapa 4J.3) y
/// `DocumentoPorEmitir.uuid` (Etapa 15, corrección estructural CFDI
/// real) — mismo dato fiscal, misma validación, extraído aquí para no
/// duplicar el regex entre ambos dominios.
final RegExp _formatoUuid = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

bool esUuidFormatoValido(String valor) => _formatoUuid.hasMatch(valor);
