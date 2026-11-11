/// Un empleado **tal como lo ve un selector de otro módulo**.
///
/// ## Por qué existe un modelo tan pequeño, y por qué vive aquí
///
/// Personal todavía **no está mudado a la web**: no hay listado, ni expediente, ni
/// repositorio. Lo único que C2 necesita de Personal es poder **nombrar a un empleado
/// activo** para el supervisor responsable de un servicio, y eso son cuatro campos.
///
/// 🚫 **No es «el modelo de Empleado» a medias**, y la distinción importa: cuando Personal
/// se mude traerá el suyo, completo, con su expediente y su ciclo laboral. Éste nombra lo
/// que un selector puede enseñar y nada más — por eso no tiene periodo, ni puesto, ni
/// foto, ni un solo campo del expediente sensible. Si alguien necesita más, lo que toca
/// es mudar Personal, no engordar esto.
class EmpleadoElegible {
  const EmpleadoElegible({
    required this.id,
    required this.numero,
    required this.nombreCompleto,
    required this.estaActivo,
  });

  factory EmpleadoElegible.deJson(Map<String, dynamic> json) => EmpleadoElegible(
    id: json['id'] as String,
    numero: json['employeeNumber'] as int,
    nombreCompleto: json['fullName'] as String,
    estaActivo: json['isActive'] as bool,
  );

  final String id;

  /// El folio humano, que es como la operación lo llama.
  final int numero;

  final String nombreCompleto;

  /// ⚠️ **Se DERIVA en el servidor de un periodo laboral abierto, no es una columna de
  /// estado.** Aquí llega ya resuelto, y esta pantalla no lo recalcula ni lo adivina.
  final bool estaActivo;

  /// «1024 · Juan Pérez García», que es como se lee en un selector.
  String get enPantalla => '$numero · $nombreCompleto';
}
