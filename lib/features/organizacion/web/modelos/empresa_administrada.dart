import '../../../../core/error/failure.dart';
import '../../../../core/error/result.dart';

/// Una empresa vista desde la **administración** de la Organization (E2).
///
/// Es otra pregunta que «¿a qué empresas puedo entrar?», y por eso es otro modelo:
///
///  · **trae las inactivas**, que la lista de empresas accesibles nunca devuelve;
///  · **trae la razón social**, que vive en el expediente y no en Tenancy;
///  · y **trae el número de accesos activos**, que no es un atributo de la fila sino un
///    conteo — y es lo que permite decir, antes de desactivar, a cuánta gente se va a
///    dejar fuera. Sin ese número la pantalla pediría confirmar a ciegas.
class EmpresaAdministrada {
  const EmpresaAdministrada({
    required this.companyId,
    required this.nombre,
    required this.estado,
    required this.accesos,
    required this.creada,
    this.razonSocial,
  });

  final String companyId;
  final String nombre;

  /// `activa` o `inactiva`. **Aquí sí puede ser cualquiera de las dos**, al contrario
  /// que en la lista de empresas accesibles.
  final String estado;

  /// Cuántos accesos ACTIVOS tiene. Cuenta a quien se quedaría fuera al desactivarla.
  final int accesos;

  final DateTime creada;

  /// Nula cuando la empresa no tiene expediente todavía. **Ausencia nunca es cero:** la
  /// tarjeta enseña una línea menos, nunca un «sin registrar» de relleno.
  final String? razonSocial;

  bool get estaActiva => estado == 'activa';

  static Result<EmpresaAdministrada> desdeJson(Map<String, Object?> json) {
    final companyId = _texto(json['companyId']);
    final nombre = _texto(json['name']);
    final estado = _texto(json['status']);
    final creada = _texto(json['createdAt']);

    // EL CONTEO ES OBLIGATORIO Y NO SE SUPONE CERO. Si el servidor no lo manda, la
    // pantalla enseñaría «0 accesos» en una empresa con gente dentro, y alguien
    // desactivaría creyendo que no afecta a nadie. **Ausencia nunca es cero.**
    final accesos = json['accessCount'];

    final faltantes = <String>[
      if (companyId == null) 'companyId',
      if (nombre == null) 'name',
      if (estado == null) 'status',
      if (creada == null) 'createdAt',
      if (accesos is! int) 'accessCount',
    ];

    if (faltantes.isNotEmpty) {
      return Result.failure(
        ApiRespuestaInesperadaFailure(
          'La lista de empresas no trae: ${faltantes.join(', ')}.',
        ),
      );
    }

    final fecha = DateTime.tryParse(creada!);

    if (fecha == null) {
      return Result.failure(
        ApiRespuestaInesperadaFailure('La fecha de alta no se entiende: «$creada».'),
      );
    }

    return Result.ok(
      EmpresaAdministrada(
        companyId: companyId!,
        nombre: nombre!,
        estado: estado!,
        accesos: accesos as int,
        creada: fecha,
        // NO ESTÁ EN `faltantes`: el servidor la manda NULA cuando la empresa no tiene
        // expediente, y un servidor anterior a E1-B no manda el campo. Las dos cosas
        // significan lo mismo para la pantalla.
        razonSocial: _texto(json['legalName']),
      ),
    );
  }

  @override
  String toString() => 'EmpresaAdministrada($companyId, $nombre, $estado)';
}

String? _texto(Object? valor) {
  if (valor is! String) return null;

  final limpio = valor.trim();
  return limpio.isEmpty ? null : limpio;
}
