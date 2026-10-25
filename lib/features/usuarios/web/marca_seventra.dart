import 'package:flutter/material.dart';

import '../../../app/theme/app_theme.dart';

/// La identidad de **SEVENTRA** para la entrada a la aplicación.
///
/// **Por qué existe, en una frase:** quien abre esta pantalla todavía no está dentro
/// de Administra — está entrando a SEVENTRA, y la puerta tiene que decir SEVENTRA.
/// Las cuatro pantallas de M3, ya dentro, usan el Design System del producto.
///
/// <b>Los colores son los MISMOS que las páginas de los correos</b>, copiados de su
/// hoja de estilo para que la puerta y el correo que la abrió no se contradigan:
///
/// ```
/// --tinta:#0F1B2D  --verde:#1E7F45  --fondo:#F7F6F2  --suave:#5A6675
/// ```
///
/// ⏳(D-28) <b>Lo que NO se copió: la tipografía.</b> Los correos usan `Archivo`, incrustada
/// en la propia página; todo el Design System usa `Segoe UI`. Traerla aquí dejaría el
/// login hablando una tipografía que ninguna otra pantalla usa — y la decisión
/// acordada fue que la puerta case con el interior.
///
/// **La unificación de verdad es una etapa propia y está anotada como PENDIENTE(D-28) ANTES
/// DEL PILOTO Y DE VENDER:** misma tipografía, paleta y logo en correos, Console,
/// Administra y Opera. Mientras eso no exista, este archivo es el único sitio donde
/// SEVENTRA se pinta dentro de Administra, y por eso los valores están aquí y no
/// repartidos por la pantalla.
abstract final class MarcaSeventra {
  /// El verde de marca. **El mismo que Console y que los correos**, y el único que
  /// aparece en los tres sitios hoy.
  static const Color verde = Color(0xFF1E7F45);

  static const Color tinta = Color(0xFF0F1B2D);
  static const Color fondo = Color(0xFFF7F6F2);
  static const Color suave = Color(0xFF5A6675);

  /// El borde de los correos: la tinta al 12 %.
  static const Color borde = Color(0x1F0F1B2D);

  static const Color rojo = Color(0xFF9A2B2B);

  static const String nombre = 'SEVENTRA';

  /// Lo que la puerta dice debajo del nombre.
  ///
  /// **No dice «RISEG ONE» ni «Administra»**: el usuario entra a la plataforma, y qué
  /// producto abre lo decide su acceso, no esta pantalla.
  static const String descripcion = 'Administración de personal y operación';

  /// El tema de la aplicación web.
  ///
  /// ⚠️ **ES `AppTheme.light()` Y NO UN `ThemeData` PROPIO, Y ESO NO ES ESTÉTICA: ES
  /// LO QUE IMPIDE UNA PANTALLA ROJA.**
  ///
  /// El Design System lee sus colores con
  /// `Theme.of(context).extension<AppColorScheme>()!` —el atajo `context.colors`—, y
  /// ese `!` es un **requisito duro**: un `ThemeData` que no instale la extensión
  /// `AppColorScheme` hace que la PRIMERA línea del `build` de cualquier pantalla del
  /// producto lance «Unexpected null value».
  ///
  /// Ocurrió de verdad el 17 de octubre de 2026: la primera versión de `main_web`
  /// construía un `ThemeData` a mano con sólo un `colorScheme`. El login entraba, la
  /// API respondía 200 en 11 ms… y Áreas reventaba en `context.colors`, con un error
  /// que no menciona ni el tema ni la extensión que falta.
  ///
  /// **La puerta no se descoloca por esto**, y es lo que permite compartir tema: el
  /// login, el selector y el portón pintan sus colores EXPLÍCITAMENTE desde
  /// [MarcaSeventra] —fondo, botón, bordes, textos—, así que no heredan nada del tema
  /// del producto. Lo que el tema aporta es exactamente lo que ellos no usan y las
  /// pantallas de dentro sí.
  static ThemeData tema() => AppTheme.light();
}

/// El logotipo de SEVENTRA: **el archivo real de la marca**, no una composición.
///
/// `assets/images/seventra-logo.png` ya vivía en este repositorio —1260×280, la
/// palabra en tinta con la **V convertida en palomita verde**—. La primera versión
/// de este widget componía el nombre con un cuadro verde y una «S» porque di por
/// hecho que no había logotipo; lo había, y una marca dibujada a mano al lado de la
/// de verdad se nota.
///
/// **NO SE COPIÓ NADA DE CONSOLE.** Sus `web/icons` son los de plantilla de Flutter:
/// comprobado por checksum, byte a byte iguales a los que Administra ya tenía. El
/// logotipo que sí es de marca estaba aquí desde el principio.
///
/// Se dimensiona por **altura**: el logotipo es muy apaisado y fijar el ancho lo
/// dejaría minúsculo o desbordado según la pantalla.
class LogotipoSeventra extends StatelessWidget {
  const LogotipoSeventra({this.alto = 34, super.key});

  final double alto;

  /// El logotipo completo con el nombre. El ícono suelto —la palomita— es
  /// `assets/images/seventra-icono.png`, y es el que va a la pestaña del navegador.
  static const String ruta = 'assets/images/seventra-logo.png';

  @override
  Widget build(BuildContext context) => Image.asset(
    ruta,
    height: alto,
    // `contain` y no `fill`: deformar un logotipo es de las pocas cosas que se ven
    // mal incluso sin saber por qué.
    fit: BoxFit.contain,
    // LO QUE SE VE SI EL ARCHIVO NO CARGA. Sin esto, un asset que falte pinta el
    // recuadro de error de Flutter —con su texto en inglés— en la primera pantalla
    // que alguien ve. El nombre en texto no es bonito, pero es correcto.
    errorBuilder: (context, error, stack) => Text(
      MarcaSeventra.nombre,
      style: TextStyle(
        color: MarcaSeventra.tinta,
        fontSize: alto * 0.72,
        fontWeight: FontWeight.w700,
        letterSpacing: alto * 0.045,
        height: 1,
      ),
    ),
    // Lo lee el lector de pantalla: para quien no ve la imagen, esto ES el nombre.
    semanticLabel: MarcaSeventra.nombre,
  );
}
