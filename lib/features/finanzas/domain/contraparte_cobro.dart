import 'package:riseg_one/core/database/app_database.dart';

/// De quién se cobra. Tipo + FK, **nunca el nombre mostrado** — misma
/// disciplina exacta que `DestinoTelefonia` en Telefonía.
enum TipoContraparteCobro { cliente, servicioEventual }

/// La contraparte de una obligación de cobro (schemaVersion 87).
///
/// Sustituye la comparación literal `cuenta.clienteId == pago.clienteId`
/// que se repartía por el dominio. Existe **una sola** definición de
/// "misma contraparte" en todo el proyecto, y vive aquí.
class ContraparteCobro {
  const ContraparteCobro.cliente(this.id) : tipo = TipoContraparteCobro.cliente;
  const ContraparteCobro.servicioEventual(this.id) : tipo = TipoContraparteCobro.servicioEventual;

  final TipoContraparteCobro tipo;
  final String id;

  @override
  bool operator ==(Object other) =>
      other is ContraparteCobro && other.tipo == tipo && other.id == id;

  @override
  int get hashCode => Object.hash(tipo, id);

  @override
  String toString() => '${tipo.name}:$id';
}

/// **El Cliente gana cuando existe.**
///
/// Un Servicio Eventual de un Cliente real es, para efectos de cobro,
/// ese Cliente: su Pago convive con el resto de su cobranza sin ninguna
/// regla especial, y sus Cuentas por cobrar siguen apareciendo en los
/// filtros y notificaciones de siempre. El `servicioEventualId` de esas
/// filas es el ORIGEN (de qué venta nacieron), no la contraparte.
///
/// Por eso los dos campos no pueden contradecirse: `clienteId` nunca se
/// captura por separado — se deriva del eventual al crear la Cuenta, y
/// el Pago lo deriva de la Cuenta.
///
/// `null` sólo si ambos vienen vacíos, algo que los `CHECK` de
/// `cuenta_por_cobrar`/`pago` impiden a nivel de base de datos.
ContraparteCobro? contraparteDe({String? clienteId, String? servicioEventualId}) {
  if ((clienteId ?? '').isNotEmpty) return ContraparteCobro.cliente(clienteId!);
  if ((servicioEventualId ?? '').isNotEmpty) return ContraparteCobro.servicioEventual(servicioEventualId!);
  return null;
}

ContraparteCobro? contraparteDeCuenta(CuentaPorCobrarData cuenta) =>
    contraparteDe(clienteId: cuenta.clienteId, servicioEventualId: cuenta.servicioEventualId);

ContraparteCobro? contraparteDePago(PagoData pago) =>
    contraparteDe(clienteId: pago.clienteId, servicioEventualId: pago.servicioEventualId);

/// De dónde nació una Cuenta por cobrar. Se deriva de las dos FK, sin
/// ningún enum `tipoOrigen` persistido — el `CHECK` XOR garantiza que
/// exactamente una esté poblada.
enum OrigenCuentaPorCobrar { documentoPorEmitir, servicioEventual }

OrigenCuentaPorCobrar origenDeCuenta(CuentaPorCobrarData cuenta) =>
    cuenta.documentoPorEmitirId != null
        ? OrigenCuentaPorCobrar.documentoPorEmitir
        : OrigenCuentaPorCobrar.servicioEventual;

/// Nombre legible de una contraparte, resuelto contra catálogos ya
/// cargados en lote. Existe para que ningún consumidor tenga que
/// escribir su propio `?? clienteId` ni su propio `if (eventual)`: hay
/// un solo sitio que decide qué se muestra.
///
/// En la Rebanada 1 [nombresServicioEventual] llega vacío en producción
/// —todavía no existe ninguna Cuenta por cobrar de eventual—, pero el
/// camino está construido y probado para la Rebanada 2.
String nombreContraparte(
  ContraparteCobro? contraparte, {
  required Map<String, String> nombresCliente,
  Map<String, String> nombresServicioEventual = const {},
  String desconocido = '—',
}) {
  if (contraparte == null) return desconocido;
  final nombre = switch (contraparte.tipo) {
    TipoContraparteCobro.cliente => nombresCliente[contraparte.id],
    TipoContraparteCobro.servicioEventual => nombresServicioEventual[contraparte.id],
  };
  // Nunca se filtra el UUID a la pantalla: si el catálogo no lo tiene,
  // se dice que no se conoce.
  return nombre ?? desconocido;
}

/// Clave estable para agrupar por contraparte (Dashboard, reportes) —
/// incluye el tipo, así que un Cliente y un eventual con el mismo id
/// jamás colisionan.
String claveContraparte(ContraparteCobro? contraparte) => contraparte?.toString() ?? 'sin-contraparte';
