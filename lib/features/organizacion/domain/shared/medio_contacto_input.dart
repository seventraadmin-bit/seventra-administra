/// Medio de contacto ya validado y listo para persistir. La etiqueta no
/// es un campo aquí — cada llamador decide internamente qué etiqueta
/// usar (Empresa siempre usa `'principal'`, fijo, no editable en 4B).
class MedioContactoInput {
  const MedioContactoInput({this.telefono, this.correo, this.sitioWeb});

  final String? telefono;
  final String? correo;
  final String? sitioWeb;
}
