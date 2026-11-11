import '../../../../core/api/api_client_autenticado.dart';
import '../../../../core/api/api_error_parser.dart';
import '../../../../core/company/company_ruta.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/error/result.dart';
import '../modelos/empleado_elegible.dart';

/// Los empleados de una empresa, **sólo para nombrarlos en un selector de otro módulo**.
///
/// ## Qué es esto y qué NO es
///
/// Personal no está mudado a la web. Lo que C2 necesita de Personal es elegir a quién
/// RESPONDE por un servicio, y para eso hace falta una lista de empleados activos con su
/// nombre. Eso es todo lo que hay aquí: **una lectura**.
///
/// 🚫 **No es el repositorio de Personal.** Cuando Personal se mude traerá el suyo, con el
/// expediente, el ciclo laboral y el expediente sensible —que tiene permisos propios y
/// rutas propias—. Si alguien empieza a colgar escrituras de aquí, lo que está haciendo es
/// mudar Personal por la puerta de atrás.
///
/// ## El permiso es de PERSONAL, no de Comercial
///
/// `GET /employees` exige **`personal.read`**, y es correcto que así sea: son datos de
/// Personal aunque los pida una pantalla de Comercial. La consecuencia visible es que
/// alguien puede ver un servicio y **no** poder elegirle supervisor — y la pantalla lo
/// dice en lugar de enseñar un selector que responde 403.
class EmpleadosRepositorioHttp {
  const EmpleadosRepositorioHttp(this._api);

  final ApiClientAutenticado _api;

  /// Los empleados **activos**, para el selector del supervisor responsable.
  ///
  /// [texto] busca por nombre o folio en el servidor. ⚠️ **No se filtra aquí**: el listado
  /// pagina por cursor, así que filtrar una página no es filtrar la plantilla — la misma
  /// regla que el listado de servicios.
  ///
  /// **Sin filtrar por puesto, y es una decisión del dueño**: puede ser supervisor
  /// cualquier empleado activo de la empresa. Si un día se limita por puesto será una
  /// decisión aparte, y entonces este método recibirá el filtro.
  ///
  /// Devuelve **sólo la primera página**: un selector no pagina. Quien no aparezca se
  /// encuentra escribiendo, que es para lo que está [texto].
  Future<Result<List<EmpleadoElegible>>> activos(
    String empresaId, {
    String? texto,
    int limite = 50,
  }) async {
    final respuesta = await _api.get(
      CompanyRuta.de(empresaId, '/employees'),
      query: {
        'status': 'active',
        if (texto != null && texto.trim().isNotEmpty) 'query': texto.trim(),
        'limit': limite.toString(),
      },
    );

    return respuesta.when(
      failure: Result.failure,
      ok: (r) {
        if (!r.esExitosa) return Result.failure(ApiErrorParser.interpretar(r));

        return r.decodificar().when(
          failure: Result.failure,
          ok: (json) {
            // EL SOBRE ES OBLIGATORIO. `GET /employees` pagina por cursor, así que su
            // respuesta es `{items, nextCursor}` y nunca una lista desnuda: aceptar las
            // dos formas sería aceptar un contrato que no existe.
            if (json is! Map<String, dynamic> || json['items'] is! List) {
              return const Result.failure(
                ApiJsonInvalidoFailure('El servidor no devolvió los empleados.'),
              );
            }

            return Result.ok([
              for (final e in json['items'] as List)
                EmpleadoElegible.deJson(e as Map<String, dynamic>),
            ]);
          },
        );
      },
    );
  }
}
