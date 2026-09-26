import 'package:flutter/material.dart';

/// Identidad visual del **producto** — Seventra Administra (Etapa 5B.1).
///
/// Existe para separar dos cosas que hasta ahora compartían un archivo:
///
///  * la **marca del producto**, que es lo que se ve en el shell, el inicio
///    de sesión y el alta del primer Maestro;
///  * la **identidad de la Empresa** administrada, que es su logotipo, su
///    razón social y sus datos, y que aparece en sus documentos.
///
/// Hasta esta etapa las cuatro superficies del producto dibujaban
/// `assets/images/logo.png`, que es el escudo corporativo de RISEG. Con una
/// sola Empresa la confusión no se notaba; con varias, el producto habría
/// llevado el logotipo de uno de sus clientes.
///
/// `logo.png` **no se toca aquí**. Desde la Etapa 5B.2 el logotipo es un
/// adjunto de la Empresa y este asset sólo sobrevive para que las
/// instalaciones anteriores lo adopten una vez; desde 5B.3 ningún documento
/// ni pantalla nombra por su cuenta a una empresa concreta.
abstract final class MarcaProducto {
  /// Logotipo completo `SEVENTRA Administra`, 1715×280 (≈6.1:1).
  ///
  /// La proporción importa: el escudo anterior era cuadrado (2048×2048) y
  /// se podía dibujar dando sólo una altura. Éste no — a 56 px de alto
  /// mediría 343 px de ancho y se saldría del sidebar, que mide 224. Por eso
  /// [logotipo] se dimensiona por **ancho**, nunca por alto.
  static const _wordmarkClaro = 'assets/images/seventra-administra.png';
  static const _wordmarkOscuro = 'assets/images/seventra-administra-blanco.png';

  /// Marca compacta: cuadrado azul oscuro con la palomita. Se basta a sí
  /// misma sobre cualquier fondo, así que no tiene variante por tema.
  static const icono = 'assets/images/seventra-icono.png';

  /// El archivo correcto según el fondo sobre el que se va a dibujar.
  ///
  /// [sobreFondoOscuro] se pasa explícitamente cuando la superficie no
  /// depende del tema —el panel de identidad del inicio de sesión siempre
  /// es un degradado azul, tanto en claro como en oscuro—; si no se pasa,
  /// se decide por el brillo del tema.
  static String wordmark(BuildContext context, {bool? sobreFondoOscuro}) {
    final oscuro = sobreFondoOscuro ?? Theme.of(context).brightness == Brightness.dark;
    return oscuro ? _wordmarkOscuro : _wordmarkClaro;
  }
}

/// El logotipo del producto, dimensionado por ancho.
///
/// Se dibuja con `BoxFit.contain` y una relación de aspecto fija, de modo
/// que la tipografía nunca se deforma por mucho que se estreche la ventana.
class LogotipoProducto extends StatelessWidget {
  const LogotipoProducto({this.ancho, this.sobreFondoOscuro, super.key});

  /// Ancho máximo. Si es `null` ocupa el que le dé su padre, que es lo que
  /// hace falta en el sidebar: el logotipo se adapta al ancho disponible.
  final double? ancho;

  /// Fuerza la variante clara u oscura. Ver [MarcaProducto.wordmark].
  final bool? sobreFondoOscuro;

  /// 1715 × 280 del archivo original.
  static const relacionAspecto = 1715 / 280;

  @override
  Widget build(BuildContext context) {
    final imagen = Image.asset(
      MarcaProducto.wordmark(context, sobreFondoOscuro: sobreFondoOscuro),
      fit: BoxFit.contain,
      // El logotipo no es decorativo: es cómo se llama el producto.
      semanticLabel: 'Seventra Administra',
    );

    if (ancho == null) return imagen;
    return SizedBox(width: ancho, height: ancho! / relacionAspecto, child: imagen);
  }
}

/// La marca compacta, cuadrada, para donde no cabe el logotipo completo.
class IconoProducto extends StatelessWidget {
  const IconoProducto({this.lado = 40, super.key});

  final double lado;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      MarcaProducto.icono,
      width: lado,
      height: lado,
      fit: BoxFit.contain,
      semanticLabel: 'Seventra Administra',
    );
  }
}
