// `characters` LLEGA CON `material.dart`, y se usa a propósito: `substring(0, 1)`
// partiría por la mitad un emoji o una letra compuesta, y el nombre de una empresa —o de
// un cliente— puede empezar por cualquiera de las dos.
import 'package:flutter/material.dart';

import '../tokens/app_colors.dart';
import '../tokens/app_typography.dart';

/// Dos letras sobre un color, para identificar una fila **mientras no hay imagen**.
///
/// ## Por qué vive en el sistema de diseño
///
/// Nació como una clase privada de la tarjeta de empresa, y en C1 el listado de
/// Clientes necesitó lo mismo: el folio debajo del nombre y, a la izquierda, el
/// logotipo o las iniciales. Copiarla habría dejado dos reglas de iniciales y dos
/// formas de elegir el color, y la segunda se nota: dos pantallas que identifican lo
/// mismo de dos maneras parecen dos productos.
///
/// ⚠️ **NO ES `RisegEntityIdentity`**, que hace esto mismo **y además lee la imagen del
/// disco con `dart:io`**: un solo import suyo rompe la build web sin que nada parezca
/// estar mal, y por eso el barrel de la web no lo exporta (deuda D-44). Esto es la
/// mitad que sí compila en el navegador.
///
/// ## El color sale del ID, nunca del nombre
///
/// Es lo que hace que renombrar una empresa —o un cliente— **no le cambie el color** que
/// la vuelve reconocible de un vistazo.
///
/// ## ⚠️ HAY OTRA REGLA DE INICIALES EN EL PRODUCTO, y no es un descuido de aquí
///
/// `riseg_entity_identity.dart` tiene una `inicialesDe` de nivel superior con un
/// criterio **distinto**: una sola palabra le da **una** letra —«Sportium» → `S`— y un
/// nombre vacío le da la cadena vacía. La de aquí da dos y `?`.
///
/// No se unifican hoy, y conviene decir por qué: la del escritorio la usan sus pantallas
/// desde la Etapa 16 y la de aquí es lo que las tarjetas de empresa de la web ya enseñan
/// —probado en pantalla con el dueño en E1-B—, así que unificarlas cambia algo visible en
/// uno de los dos productos sin que nadie lo haya pedido. **Lo que sí se evita es la
/// tercera copia**, que es lo que iba a nacer con el listado de Clientes.
class RisegIniciales extends StatelessWidget {
  const RisegIniciales({
    required this.id,
    required this.nombre,
    required this.lado,
    super.key,
  });

  /// De quién son estas iniciales. **Sólo decide el color**, y por eso vale cualquier
  /// identificador estable: el de una empresa o el de un cliente.
  final String id;

  final String nombre;
  final double lado;

  /// Las dos primeras letras de las dos primeras palabras: «RISEG Servicios» → `RS`.
  /// Con una sola palabra, sus dos primeras letras: «Administración» → `AD`.
  static String inicialesDe(String nombre) {
    final palabras = nombre
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();

    if (palabras.isEmpty) return '?';

    if (palabras.length == 1) {
      final una = palabras.single;

      return (una.length == 1 ? una : una.substring(0, 2)).toUpperCase();
    }

    return (palabras[0].characters.first + palabras[1].characters.first)
        .toUpperCase();
  }

  /// El color, derivado del id. **`hashCode` de la cadena no sirve**: en Dart no está
  /// garantizado estable entre ejecuciones, así que el color podría cambiar al recargar
  /// la página. Se suman los códigos de los caracteres, que es aritmética y no una
  /// promesa de la plataforma.
  static Color colorDe(String id, List<Color> paleta) {
    var suma = 0;
    for (final unidad in id.codeUnits) {
      suma = (suma + unidad) % 1000003;
    }

    return paleta[suma % paleta.length];
  }

  @override
  Widget build(BuildContext context) {
    final oscuro = Theme.of(context).brightness == Brightness.dark;
    final paleta = oscuro ? AppColors.categoricaDark : AppColors.categoricaLight;

    return ColoredBox(
      color: colorDe(id, paleta),
      child: Center(
        child: Text(
          inicialesDe(nombre),
          style: AppTypography.caption.copyWith(
            // BLANCO SOBRE LA PALETA CLARA, TINTA SOBRE LA OSCURA: la paleta de tema
            // oscuro es clara por definición —tiene que verse sobre un lienzo
            // oscuro—, así que ahí el texto blanco desaparecería.
            color: oscuro ? AppColors.tinta : Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: lado <= 34 ? 12 : 14,
          ),
        ),
      ),
    );
  }
}
