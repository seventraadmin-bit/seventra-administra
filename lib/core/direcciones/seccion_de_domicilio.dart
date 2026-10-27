import 'package:flutter/material.dart';

import '../design_system/design_system_web.dart';
import 'campos_de_domicilio.dart';

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
/// ## Lo que NO decide
///
/// **No valida.** Quien impone los seis obligatorios y el código postal de cinco
/// dígitos es el servidor, y su mensaje nombra el campo que falta. Esto pinta, y pinta
/// el error que le dan en el campo que le dicen.
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

  /// Los errores del servidor, **por clave del servidor**: `address.street`.
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
  Widget build(BuildContext context) => RisegFormSection(
    title: titulo,
    description: descripcion,
    grid: true,
    children: [
      for (final campo in camposDeDomicilio)
        RisegTextField(
          label: campo.etiqueta,
          controller: campos[campo.clave],
          focusNode: focos?[campo.clave],
          enabled: habilitado,
          errorText: erroresPorCampo[campo.clave],
          helperText: campo.ayuda,
          keyboardType: campo.soloDigitos ? TextInputType.number : null,
        ),
    ],
  );
}
