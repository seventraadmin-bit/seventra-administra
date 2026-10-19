import '../../../../core/api/api_client_autenticado.dart';
import '../../../../core/api/api_error_parser.dart';
import '../../../../core/api/api_respuesta.dart';
import '../../../../core/company/company_ruta.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/error/result.dart';
import '../modelos/capacidad_de_accesos.dart';
import '../modelos/evento_de_auditoria.dart';
import '../modelos/miembro_de_empresa.dart';
import '../modelos/permiso_de_empresa.dart';

/// Los usuarios de una empresa y sus permisos, contra la API.
///
/// **Devuelve `Result`, nunca lanza.** El cliente ya traduce todo fallo de
/// transporte; lo que falta es convertir una respuesta HTTP no exitosa en un fallo, y
/// eso lo hace [ApiErrorParser] —**no una interpretación propia de este archivo**—.
///
/// TODAS LAS RUTAS SON **SÓLO MAESTRO**, y eso no se comprueba aquí: lo impone el
/// servidor y responde 403. Repetir la comprobación en el cliente daría una segunda
/// fuente de verdad sobre quién administra, y el día que discreparan ganaría la
/// equivocada —porque la pantalla se vería bien y la petición fallaría—.
class UsuariosRepositorioHttp {
  const UsuariosRepositorioHttp(this._api);

  final ApiClientAutenticado _api;

  /// Quién tiene acceso activo a la empresa.
  ///
  /// El servidor ya los entrega **ordenados: Maestros primero, luego por correo**, y
  /// aquí no se reordena. Hacerlo duplicaría una decisión ya tomada.
  Future<Result<List<MiembroDeEmpresa>>> listarMiembros(String empresaId) async {
    final respuesta = await _api.get(CompanyRuta.de(empresaId, '/access'));

    return respuesta.when(
      failure: Result.failure,
      ok: (r) {
        if (!r.esExitosa) return Result.failure(ApiErrorParser.interpretar(r));

        return r.decodificar().when(
          failure: Result.failure,
          ok: (json) {
            if (json is! List) {
              return const Result.failure(
                ApiJsonInvalidoFailure(
                  'El servidor no devolvió una lista de usuarios.',
                ),
              );
            }

            return Result.ok([
              for (final fila in json)
                MiembroDeEmpresa.deJson(fila as Map<String, dynamic>),
            ]);
          },
        );
      },
    );
  }

  /// Cuántos accesos del plan se usan, **en toda la organización**.
  ///
  /// Va por la ruta de EMPRESA y no por la de Organization porque un Maestro no puede
  /// leer aquélla: exige membresía de Organization, y un Maestro tiene acceso a una
  /// empresa. Son dos autoridades distintas a propósito.
  ///
  /// **Un fallo aquí no debe tumbar la pantalla.** Quien llama lo trata como un dato
  /// que puede faltar —la lista de personas sigue siendo útil sin el contador—, y
  /// sobre todo **no lo convierte en un cero**: «0 de 0 accesos» diría que el plan no
  /// incluye ninguno, que es lo contrario de «no se pudo averiguar».
  Future<Result<CapacidadDeAccesos>> capacidadDeAccesos(String empresaId) async {
    final respuesta = await _api.get(CompanyRuta.de(empresaId, '/access-capacity'));

    return respuesta.when(
      failure: Result.failure,
      ok: (r) {
        if (!r.esExitosa) return Result.failure(ApiErrorParser.interpretar(r));

        return r.decodificar().when(
          failure: Result.failure,
          ok: (json) {
            if (json is! Map<String, dynamic>) {
              return const Result.failure(
                ApiJsonInvalidoFailure(
                  'El servidor no devolvió la capacidad de accesos.',
                ),
              );
            }

            return Result.ok(CapacidadDeAccesos.deJson(json));
          },
        );
      },
    );
  }

  /// El catálogo completo de permisos.
  ///
  /// **Requiere acceso, no ser Maestro** —así lo expone el servidor—, pero la
  /// pantalla que lo usa sí es de Maestro. Se pide entero y se agrupa en el cliente:
  /// son ciento y pico filas que no cambian durante una sesión, y pedirlo por módulo
  /// serían ocho viajes para pintar una sola pantalla.
  Future<Result<List<PermisoDeEmpresa>>> listarCatalogo(String empresaId) async {
    final respuesta = await _api.get(CompanyRuta.de(empresaId, '/permissions'));

    return respuesta.when(
      failure: Result.failure,
      ok: (r) {
        if (!r.esExitosa) return Result.failure(ApiErrorParser.interpretar(r));

        return r.decodificar().when(
          failure: Result.failure,
          ok: (json) {
            if (json is! List) {
              return const Result.failure(
                ApiJsonInvalidoFailure(
                  'El servidor no devolvió el catálogo de permisos.',
                ),
              );
            }

            return Result.ok([
              for (final fila in json)
                PermisoDeEmpresa.deJson(fila as Map<String, dynamic>),
            ]);
          },
        );
      },
    );
  }

  /// Una página de la auditoría de la empresa.
  ///
  /// **Exige `company.audit.read`**, que NO es un permiso de Maestro: un Maestro lo
  /// tiene por su rol, y a cualquier otro se le puede conceder. Por eso esta llamada
  /// no vive en una pantalla de Maestro por obligación —aunque hoy la use una—.
  ///
  /// El `cursor` es **opaco**: se manda tal como vino y no se interpreta. Nulo pide la
  /// primera página.
  Future<Result<PaginaDeAuditoria>> auditoria(
    String empresaId, {
    String? cursor,
  }) async {
    // EL CURSOR VA CODIFICADO. Es opaco, así que puede traer cualquier carácter; sin
    // codificar, uno con `&` o `=` partiría la consulta y el servidor recibiría otro.
    final consulta = cursor == null
        ? '/audit'
        : '/audit?cursor=${Uri.encodeQueryComponent(cursor)}';

    final respuesta = await _api.get(CompanyRuta.de(empresaId, consulta));

    return respuesta.when(
      failure: Result.failure,
      ok: (r) {
        if (!r.esExitosa) return Result.failure(ApiErrorParser.interpretar(r));

        return r.decodificar().when(
          failure: Result.failure,
          ok: (json) {
            if (json is! Map<String, dynamic> || json['items'] is! List) {
              return const Result.failure(
                ApiJsonInvalidoFailure(
                  'El servidor no devolvió una página de auditoría.',
                ),
              );
            }

            return Result.ok(PaginaDeAuditoria.deJson(json));
          },
        );
      },
    );
  }

  /// Los permisos concedidos a un **periodo de acceso**.
  Future<Result<Set<String>>> permisosDe(String empresaId, String accesoId) async {
    final respuesta = await _api.get(
      CompanyRuta.de(empresaId, '/access/$accesoId/permissions'),
    );

    return respuesta.when(
      failure: Result.failure,
      ok: (r) {
        if (!r.esExitosa) return Result.failure(ApiErrorParser.interpretar(r));

        return r.decodificar().when(
          failure: Result.failure,
          ok: (json) {
            if (json is! List) {
              return const Result.failure(
                ApiJsonInvalidoFailure(
                  'El servidor no devolvió la lista de permisos.',
                ),
              );
            }

            return Result.ok({for (final c in json) c as String});
          },
        );
      },
    );
  }

  /// Concede un permiso. **Idempotente en el servidor**: concederlo dos veces no
  /// falla ni crea dos filas.
  Future<Result<void>> conceder({
    required String empresaId,
    required String accesoId,
    required String permiso,
  }) => _sinCuerpo(
    _api.put(CompanyRuta.de(empresaId, '/access/$accesoId/permissions/$permiso')),
  );

  /// Retira un permiso. **Idempotente**, y **borra la fila**: no hay revocación
  /// fechada en esta tabla.
  Future<Result<void>> retirar({
    required String empresaId,
    required String accesoId,
    required String permiso,
  }) => _sinCuerpo(
    _api.delete(CompanyRuta.de(empresaId, '/access/$accesoId/permissions/$permiso')),
  );

  /// UNA sola forma de leer una respuesta que no trae cuerpo útil.
  ///
  /// Conceder y retirar se diferencian en el verbo y en nada más, así que repetir el
  /// `switch` en los dos sería invitar a que uno de ellos deje de traducir el fallo.
  static Future<Result<void>> _sinCuerpo(
    Future<Result<ApiRespuesta>> peticion,
  ) async {
    final respuesta = await peticion;

    return respuesta.when(
      failure: Result.failure,
      ok: (r) => r.esExitosa
          ? const Result<void>.ok(null)
          : Result.failure(ApiErrorParser.interpretar(r)),
    );
  }
}
