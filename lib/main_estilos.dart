/// **El escaparate de estilos de C2, para elegir el diseño.**
///
/// No es el producto: es una pantalla con datos inventados, sin repositorios y sin
/// sesión, que existe para comparar dos estilos y que el dueño elija uno. Lo que decida
/// se aplica después a las pantallas de verdad.
///
/// ```
/// flutter run -d chrome --web-port=5310 --target lib/main_estilos.dart
/// ```
///
/// La razón de que sea un punto de entrada propio y no una ruta del producto: **una ruta
/// la puede abrir alguien**. Esto no tiene que poder abrirse en el ensayo ni en
/// producción, y un `--target` distinto es la frontera que lo garantiza sin un `if`.
library;

import 'package:flutter/material.dart';

import 'app/theme/app_theme.dart';
import 'features/usuarios/web/marca_seventra.dart';
import 'prototipos/estilos_c2.dart';

void main() => runApp(const AppDeEstilos());

class AppDeEstilos extends StatelessWidget {
  const AppDeEstilos({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Estilos de Clientes y Servicios',
    debugShowCheckedModeBanner: false,
    theme: MarcaSeventra.tema(),
    // EL TEMA OSCURO TAMBIÉN, porque la propuesta tiene que verse en los dos: un estilo
    // que sólo funcione en claro no se puede aplicar.
    darkTheme: AppTheme.dark(),
    home: const EscaparateDeEstilos(),
  );
}
