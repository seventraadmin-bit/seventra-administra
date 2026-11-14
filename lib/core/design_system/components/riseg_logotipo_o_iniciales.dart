import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../tokens/app_radius.dart';
import '../tokens/app_spacing.dart';
import 'riseg_iniciales.dart';

/// **El avatar de una entidad en la cabecera de su expediente:** su logotipo si lo tiene,
/// y sus iniciales con color si no.
///
/// ## Por qué es un componente y no dos copias
///
/// Nació como una clase privada del expediente de un cliente. El 13 de noviembre de 2026
/// el dueño vio que la cabecera del expediente de un **servicio** enseñaba otra cosa —las
/// iniciales del servicio, en un cuadrito del tamaño de sus dos letras— y pidió que se
/// viera **igual que la del cliente**. La forma de garantizar «igual» no es copiar el
/// widget: es que sea **el mismo**.
///
/// Es la misma lección que [RisegIniciales] escribió al subir aquí: dos pantallas que
/// identifican lo mismo de dos maneras parecen dos productos.
///
/// ## Lo que decide, y por qué así
///
///  · **`contain` y fondo blanco** para el logotipo: recortarlo para llenar el cuadro
///    perdería parte de la marca, que es lo único que esa imagen tiene que hacer bien;
///  · **las iniciales también cuando la imagen no se puede decodificar**, en vez de un
///    hueco roto: un archivo ilegible no tiene por qué estropear una ficha;
///  · **el color sale del `id`**, nunca del nombre, así que renombrar no cambia el color
///    que vuelve a alguien reconocible de un vistazo.
class RisegLogotipoOIniciales extends StatelessWidget {
  const RisegLogotipoOIniciales({
    required this.id,
    required this.nombre,
    required this.logotipo,
    this.lado = 48,
    super.key,
  });

  /// De quién es. **Sólo decide el color** de las iniciales.
  final String id;

  /// El nombre del que salen las iniciales.
  final String nombre;

  /// Los bytes del logotipo, o **nulo si no tiene o no se pudieron leer**. Las dos cosas
  /// se pintan igual: con las iniciales.
  final Uint8List? logotipo;

  /// El lado del cuadro. **48 es el de la cabecera de un expediente**, y es el valor por
  /// omisión para que dos expedientes no puedan discrepar por olvido.
  final double lado;

  @override
  Widget build(BuildContext context) {
    final bytes = logotipo;

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: SizedBox.square(
        dimension: lado,
        child: bytes == null
            ? RisegIniciales(id: id, nombre: nombre, lado: lado)
            : ColoredBox(
                color: Colors.white,
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.xxs),
                  child: Image.memory(
                    bytes,
                    fit: BoxFit.contain,
                    // ⚠️ **AQUÍ NO HACE FALTA `key`, y conviene decir por qué:** la
                    // trampa 3 de IF-5 —la imagen vieja pegada al reemplazar el
                    // logotipo— aparece cuando se reusa **el mismo arreglo de bytes**.
                    // Reemplazar un logotipo trae bytes nuevos, y `MemoryImage` compara
                    // su arreglo por identidad, así que la imagen se vuelve a decodificar
                    // sola. Lo que sí la necesita es el logotipo de la empresa, donde la
                    // caché puede devolver el mismo arreglo.
                    //
                    // UN ARCHIVO QUE NO SE PUEDE DECODIFICAR NO REVIENTA LA FICHA.
                    errorBuilder: (_, _, _) =>
                        RisegIniciales(id: id, nombre: nombre, lado: lado),
                  ),
                ),
              ),
      ),
    );
  }
}
