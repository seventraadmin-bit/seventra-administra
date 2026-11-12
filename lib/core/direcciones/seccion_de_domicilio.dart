import 'package:flutter/material.dart';

import '../design_system/design_system_web.dart';
import 'campos_de_domicilio.dart';
import 'direccion.dart';

/// Los **diez campos de un domicilio**, con sus reglas dichas arriba.
///
/// ## EL MISMO WIDGET, NO UNA COPIA
///
/// Es la regla que el diseño de las pantallas de Clientes escribió para el domicilio de
/// referencia: «con los diez campos y las reglas de dirección que ya usa el expediente
/// de una sucursal — **el mismo widget, no una copia**». La razón no es ahorrar líneas:
/// son **cinco sitios por pantalla** los que tocan estos diez campos, y dos juegos
/// divergen en el quinto sin que nada falle.
///
/// ## Cada campo mide lo que se escribe en él
///
/// 🚫 Hasta el 11 de noviembre de 2026 esto pintaba `RisegFieldGrid`, que reparte **tres
/// columnas iguales**: un código postal medía lo mismo que una calle. El dueño lo leyó
/// como *«cajas grises iguales en tres columnas»*. Ahora va en [RisegCuadricula] y el
/// ancho de cada campo sale de la tabla —`CampoDeDomicilio.ancho`—, que es donde vive
/// todo lo demás del campo.
///
/// ## Lo que NO decide
///
/// **No valida.** Lo que falta por capturar lo calcula [CamposDeDomicilio.faltantes] y lo
/// decide la pantalla, que conoce su regla —en un servicio el domicilio es obligatorio y
/// en un cliente no—. Esto pinta, y pinta el error que le dan en el campo que le dicen.
///
/// **No decide si se puede escribir.** [habilitado] llega de fuera, porque la respuesta
/// es distinta en cada pantalla: en una sucursal manda el permiso del expediente; en un
/// cliente, el modo —consulta o edición— y el permiso de administrar.
class SeccionDeDomicilio extends StatelessWidget {
  const SeccionDeDomicilio({
    required this.campos,
    required this.habilitado,
    required this.erroresPorCampo,
    required this.descripcion,
    this.titulo = 'Domicilio',
    this.focos,
    super.key,
  });

  final CamposDeDomicilio campos;
  final bool habilitado;

  /// Los errores por campo, **por clave del servidor**: `address.street`.
  final Map<String, String> erroresPorCampo;

  /// La letra chica de la sección. **Es un parámetro y no un texto fijo** porque la
  /// regla no es la misma en todas partes: en una sucursal el domicilio se puede dejar
  /// entero vacío, y en un cliente que ya tiene uno **no se puede quitar desde la web**.
  final String descripcion;

  final String titulo;

  /// Los nodos de foco, para llevar la vista al primer campo con error. Opcional: una
  /// pantalla sin esa función no tiene por qué fabricarlos.
  final RisegFocosDeFormulario? focos;

  @override
  Widget build(BuildContext context) {
    // ⚠️ **SIN TÍTULO NO SE PINTA ENCABEZADO**, y lo destapó una captura: dentro de una
    // tarjeta que ya se llama «Domicilio operativo», el encabezado de la sección salía
    // **debajo** de la nota de la tarjeta, así que se leía la letra chica antes que el
    // título. Quien ya nombra la sección pasa `titulo: ''`.
    if (titulo.isEmpty) return _campos();

    return RisegFormSection(
      title: titulo,
      description: descripcion,
      children: [_campos()],
    );
  }

  Widget _campos() => RisegCuadricula(
        celdas: [
          for (final campo in camposDeDomicilio)
            RisegCelda(
              RisegTextField(
                label: campo.etiqueta,
                controller: campos[campo.clave],
                focusNode: focos?[campo.clave],
                enabled: habilitado,
                errorText: erroresPorCampo[campo.clave],
                helperText: campo.ayuda,
                keyboardType: campo.soloDigitos
                    ? TextInputType.number
                    : null,
              ),
              ancho: campo.ancho,
            ),
        ],
      );
}

/// Un domicilio **en modo vista: como texto, nunca como diez cuadros apagados**.
///
/// 🚫 **ES LA MITAD QUE FALTABA DEL ESTILO B.** Consultar un expediente enseñaba los diez
/// `RisegTextField` con `enabled: false`, y el dueño lo dijo así: *«la vista se ve casi
/// igual que la edición»*. Diez cuadros grises con texto apagado parecen campos que no te
/// dejan tocar.
///
/// **Y agrupa lo que se lee junto:** calle y números en una línea —«Circuito Centro
/// Comercial 40, int. 3B»—, porque nadie lee un domicilio campo por campo. Los diez
/// siguen estando; lo que cambia es que se leen en seis renglones.
///
/// **Lo opcional vacío no se enseña.** Un «No registrado» en Ciudad, País y Referencias
/// son tres renglones que no dicen nada; los obligatorios sí se enseñan vacíos, porque
/// ahí la ausencia **es** la noticia.
class DomicilioEnTexto extends StatelessWidget {
  const DomicilioEnTexto({required this.direccion, super.key});

  /// El domicilio cargado, o nulo si no hay.
  final Direccion? direccion;

  @override
  Widget build(BuildContext context) {
    final d = direccion;

    if (d == null) {
      return const RisegDatoEnLinea(
        etiqueta: 'Domicilio',
        valor: null,
        vacioDice: 'Sin domicilio registrado',
      );
    }

    final interior = (d.numeroInterior ?? '').trim();
    final calleYNumero = [
      d.calle,
      d.numeroExterior,
      if (interior.isNotEmpty) 'int. $interior',
    ].where((t) => t.trim().isNotEmpty).join(' ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RisegDatoEnLinea(etiqueta: 'Calle y número', valor: calleYNumero),
        RisegDatoEnLinea(etiqueta: 'Colonia', valor: d.colonia),
        RisegDatoEnLinea(etiqueta: 'Municipio o alcaldía', valor: d.municipio),
        RisegDatoEnLinea(etiqueta: 'Estado', valor: d.estado),
        RisegDatoEnLinea(etiqueta: 'Código postal', valor: d.codigoPostal),
        if ((d.ciudad ?? '').trim().isNotEmpty)
          RisegDatoEnLinea(etiqueta: 'Ciudad', valor: d.ciudad),
        if ((d.pais ?? '').trim().isNotEmpty)
          RisegDatoEnLinea(etiqueta: 'País', valor: d.pais),
        if ((d.referencias ?? '').trim().isNotEmpty)
          RisegDatoEnLinea(etiqueta: 'Referencias', valor: d.referencias),
      ],
    );
  }
}
