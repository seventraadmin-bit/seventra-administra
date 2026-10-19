/// Un tipo de sucursal —oficina, bodega, caseta—, tal como lo devuelve
/// `GET /companies/{id}/branch-types`.
///
/// **Es un catálogo del cliente, no de la plataforma.** Cada empresa define los
/// suyos; lo que el servidor ofrece es un **juego recomendado** que se puede agregar
/// de una vez, y a partir de ahí son filas suyas que puede renombrar o apagar.
class TipoDeSucursal {
  const TipoDeSucursal({
    required this.id,
    required this.codigo,
    required this.nombre,
    required this.activo,
  });

  factory TipoDeSucursal.deJson(Map<String, dynamic> json) => TipoDeSucursal(
    id: json['id'] as String,
    codigo: json['code'] as String,
    nombre: json['name'] as String,
    activo: json['status'] == 'activa',
  );

  final String id;

  /// El código —`OFI`—, que el cliente escribe y reconoce. **No se puede cambiar**:
  /// el servidor no lo acepta en la modificación, porque es la identidad del tipo.
  final String codigo;

  final String nombre;

  /// ¿Se puede elegir al dar de alta una sucursal? Uno inactivo desaparece de los
  /// selectores **pero no de las sucursales que ya lo usan**.
  final bool activo;
}

/// Cuáles de [despues] no estaban en [antes], comparando por **código**.
///
/// ## Por qué hace falta, que es lo que no se debe volver a suponer
///
/// `POST …/branch-types/recommended` **devuelve el conjunto RESULTANTE, no lo que
/// acaba de crear**. Al segundo clic devuelve los tres otra vez, y con un tipo propio
/// preexistente devuelve los tres incluyendo el suyo **con su nombre original**. Las
/// dos cosas están medidas en `BranchTypeTests` del backend:
///
/// ```csharp
/// var segunda = await AddRecommendedBranchTypesAsync(contexto, Ct);
/// Assert.Equal(3, segunda.Value!.Count);   // tres, no cero
/// ```
///
/// Así que **la respuesta no dice cuántos se crearon**, y creerlo produce un «Se
/// agregaron 3 tipos recomendados» al pulsar el botón por segunda vez: la base queda
/// bien —el endpoint es idempotente de verdad— pero la pantalla miente.
///
/// La cuenta exacta sale de restar: lo que hay después, menos lo que ya se tenía
/// cargado. Y eso la pantalla ya lo sabe sin pedir nada.
///
/// **Se compara por código y no por id** porque el código es la identidad que el
/// servidor usa para saltarse los que ya existen.
List<TipoDeSucursal> tiposNuevos({
  required List<TipoDeSucursal> antes,
  required List<TipoDeSucursal> despues,
}) {
  final yaEstaban = {for (final t in antes) t.codigo};

  return [
    for (final t in despues)
      if (!yaEstaban.contains(t.codigo)) t,
  ];
}
