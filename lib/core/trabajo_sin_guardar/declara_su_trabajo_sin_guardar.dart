/// Lo que un formulario tiene que hacer para que su trabajo no se tire (D-56).
///
/// ## La regla permanente que esto implementa
///
/// > **Toda pantalla con «Guardar» se registra en el guardia.**
///
/// Decidida por el dueño el 26 de octubre de 2026, y con candado:
/// `guardia_cubre_los_formularios_test.dart` pone la suite roja si un formulario de
/// guardado no participa. **Clientes, Servicios y lo que venga nacen así.**
///
/// ## Por qué un mixin y no «que cada pantalla se acuerde»
///
/// Porque el registro a mano tiene **una trampa que compila igual y no avisa**, y la pisé
/// yo mismo escribiendo el expediente de la sucursal:
///
/// ```dart
/// guardia.registrar(() => _hayCambios, …);   // una lambda
/// guardia.liberar(() => _hayCambios);        // OTRA lambda: no es la misma función
/// ```
///
/// `liberar` compara por identidad, y Dart sólo garantiza la igualdad entre **dos
/// referencias al mismo método del mismo objeto**. Con lambdas, el `dispose` no suelta
/// nada y el registro queda **pegado**: cada navegación preguntaría por un formulario que
/// ya no existe, y eso parece un cuelgue del producto, no un descuido.
///
/// El mixin se queda con las dos referencias, así que el error deja de ser posible. Y de
/// paso el `initState`/`dispose` de cada formulario pierden tres líneas que eran siempre
/// las mismas.
///
/// ## Cómo se usa
///
/// ```dart
/// class _MiFormularioState extends State<MiFormulario>
///     with DeclaraSuTrabajoSinGuardar<MiFormulario> {
///   @override
///   GuardiaDeSalida get guardia => widget.guardia;
///
///   @override
///   bool get hayCambiosSinGuardar => _nombre.text.trim() != _cargado.nombre;
///
///   @override
///   String get queSePierde => 'el expediente de la sucursal ${_cargado.nombre}';
/// }
/// ```
///
/// ⚠️ **`hayCambiosSinGuardar` se compara contra LO CARGADO, nunca contra un «se tocó
/// algo».** Escribir una letra y borrarla no es un cambio, y una pregunta que sale por eso
/// enseña a contestar el diálogo sin leerlo — y entonces el día que haya algo de verdad
/// que perder, también se contestará sin leer.
///
/// ⚠️ **`queSePierde` completa la frase y no la empieza:** «el expediente de la empresa»,
/// «la nueva sucursal». Quien pregunta la monta —«Tienes cambios sin guardar en …»— así
/// que un título aquí dejaría una frase rota.
library;

import 'package:flutter/widgets.dart';

import 'guardia_de_salida.dart';

mixin DeclaraSuTrabajoSinGuardar<T extends StatefulWidget> on State<T> {
  /// Dónde se registra. **Se recibe, no se crea**: es uno por sesión.
  GuardiaDeSalida get guardia;

  /// ¿Hay algo escrito que se perdería al salir?
  bool get hayCambiosSinGuardar;

  /// Qué es, para que la pregunta lo nombre.
  String get queSePierde;

  @override
  void initState() {
    super.initState();

    guardia.registrar(_hayCambios, queSePierde: _comoSeLlama);
  }

  @override
  void dispose() {
    // SE SUELTA CON LA MISMA REFERENCIA con la que se registró, que es todo el punto de
    // este mixin. Y se suelta ANTES de `super.dispose()` por costumbre, no por
    // necesidad: `liberar` no llama a la pregunta, así que el orden no puede dejar al
    // guardia consultando un estado a medio desmontar.
    guardia.liberar(_hayCambios);

    super.dispose();
  }

  bool _hayCambios() => hayCambiosSinGuardar;

  String _comoSeLlama() => queSePierde;
}
