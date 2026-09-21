/// Identidad visual de un Egreso a partir de su `concepto` (Etapa 17)
/// — reorganiza en primario/secundario el mismo texto que ya escriben
/// `CompraRepositoryImpl`/`PagoNominaRepositoryImpl` al generar el
/// Egreso automático (formatos estables, controlados por código, no
/// texto libre de usuario): nunca inventa ni pierde información, solo
/// cambia su jerarquía visual. Si el concepto no coincide con ninguno
/// de los dos formatos conocidos (Egreso manual, texto libre), se
/// muestra completo como primario, sin secundario.
class EgresoIdentidad {
  const EgresoIdentidad({required this.primario, this.secundario});

  final String primario;
  final String? secundario;
}

final _patronNomina = RegExp(r'^Pago de Nómina (\S+) \((\S+)\)$');
final _patronCompra = RegExp(r'^Compra (\S+)(?: · (.+))?$');
final _patronDeuda = RegExp(r'^Pago de deuda (\S+) · (.+)$');

EgresoIdentidad identidadEgreso(String concepto) {
  final nomina = _patronNomina.firstMatch(concepto);
  if (nomina != null) {
    return EgresoIdentidad(primario: 'Pago de nómina', secundario: '${nomina.group(1)} · ${nomina.group(2)}');
  }

  final compra = _patronCompra.firstMatch(concepto);
  if (compra != null) {
    final proveedor = compra.group(2);
    return EgresoIdentidad(
      primario: 'Compra',
      secundario: proveedor == null ? compra.group(1) : '${compra.group(1)} · $proveedor',
    );
  }

  final deuda = _patronDeuda.firstMatch(concepto);
  if (deuda != null) {
    return EgresoIdentidad(primario: 'Pago de deuda', secundario: '${deuda.group(1)} · ${deuda.group(2)}');
  }

  return EgresoIdentidad(primario: concepto);
}
