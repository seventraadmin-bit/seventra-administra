import '../../../../core/api/api_client_autenticado.dart';
import '../../../../core/api/api_error_parser.dart';
import '../../../../core/api/api_respuesta.dart';
import '../../../../core/company/company_ruta.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/error/result.dart';
import '../modelos/puesto.dart';

/// Los puestos de una empresa, contra la API.
///
/// **NO trae las áreas**, y es deliberado: las áreas tienen su propia pestaña y su
/// propio repositorio ya probado, `AreasRepositorioHttp`. La pantalla de Puestos
/// recibe los dos. Es distinto del caso de Sucursales, donde los tipos **sólo existen
/// para** las sucursales y por eso van juntos.
///
/// **Devuelve `Result`, nunca lanza**, y la traducción de un fallo HTTP la hace
/// [ApiErrorParser] — no una interpretación propia de este archivo. Lo único que se
/// añade es el **código** cuando hay choque, porque es el único error que el usuario
/// puede arreglar solo y necesita saber cuál repitió.
class PuestosRepositorioHttp {
  const PuestosRepositorioHttp(this._api);

  final ApiClientAutenticado _api;

  /// Todos, activos e inactivos. **El filtro es de la pantalla**, igual que en Áreas.
  Future<Result<List<Puesto>>> listar(String empresaId) async {
    final respuesta = await _api.get(CompanyRuta.de(empresaId, '/positions'));

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
                  'El servidor no devolvió una lista de puestos.',
                ),
              );
            }

            return Result.ok([
              for (final fila in json) Puesto.deJson(fila as Map<String, dynamic>),
            ]);
          },
        );
      },
    );
  }

  /// Da de alta un puesto.
  ///
  /// **`areaId`, `tipo` y `nivel` son OBLIGATORIOS aquí y no se inventan.** El
  /// servidor los exige al crear —y el nivel con un mensaje que explica la escala—
  /// precisamente para que nadie dé de alta un puesto a medias. Al modificar son
  /// opcionales, que es lo que permite corregir el nombre de un puesto viejo sin
  /// inventarle un nivel.
  Future<Result<Puesto>> crear({
    required String empresaId,
    required String areaId,
    required String codigo,
    required String nombre,
    required String tipo,
    required int nivel,
    String? descripcion,
  }) async {
    final respuesta = await _api.post(
      CompanyRuta.de(empresaId, '/positions'),
      json: {
        'areaId': areaId,
        'code': codigo,
        'name': nombre,
        'kind': tipo,
        'hierarchyLevel': nivel,
        if (descripcion != null && descripcion.trim().isNotEmpty)
          'description': descripcion.trim(),
      },
    );

    return _unPuesto(respuesta, codigo: codigo);
  }

  /// Renombra, cambia el nivel o la descripción, activa o desactiva.
  ///
  /// ⚠️ **NO TOCA EL CÓDIGO, EL ÁREA NI EL TIPO**, y no es que esta clase los omita:
  /// *«no existen en el contrato»*, y **la base lo respalda con un disparador**. Son
  /// identidad y configuración estable de una fila que la historia laboral referencia.
  /// **Reclasificar es desactivar y crear otro.**
  Future<Result<Puesto>> modificar({
    required String empresaId,
    required String puestoId,
    String? nombre,
    int? nivel,
    String? descripcion,
    bool? activo,
  }) async {
    final respuesta = await _api.patch(
      CompanyRuta.de(empresaId, '/positions/$puestoId'),
      json: {
        if (nombre != null) 'name': nombre,
        if (nivel != null) 'hierarchyLevel': nivel,
        if (descripcion != null) 'description': descripcion,
        if (activo != null) 'status': activo ? 'activa' : 'inactiva',
      },
    );

    return _unPuesto(respuesta);
  }

  /// Elimina físicamente un puesto que nunca se usó. **Sólo Maestro, con motivo.**
  ///
  /// El servidor rechaza con 409 `estructura_en_uso` si tiene **asignaciones de
  /// personal** —vigentes o cerradas, da igual: borrar es definitivo— o **vigencias
  /// comerciales**, y dice cuántas de cada una.
  ///
  /// No se confunde con desactivar: desactivar sólo mira a quien está ACTIVO hoy, y
  /// por eso un puesto puede desactivarse y aun así no poderse borrar.
  Future<Result<Puesto>> eliminar({
    required String empresaId,
    required String puestoId,
    required String motivo,
  }) async {
    final respuesta = await _api.delete(
      CompanyRuta.de(empresaId, '/positions/$puestoId'),
      json: {'reason': motivo},
    );

    return _unPuesto(respuesta);
  }

  Result<Puesto> _unPuesto(Result<ApiRespuesta> respuesta, {String? codigo}) =>
      respuesta.when(
        failure: Result.failure,
        ok: (r) {
          if (!r.esExitosa) {
            final fallo = ApiErrorParser.interpretar(r);

            // SE MIRA EL CÓDIGO DEL SERVIDOR, NO SÓLO EL 409. Hasta M3 el único 409
            // posible era el código duplicado; ahora el servidor contesta 409 también
            // con `desactivacion_bloqueada` y `estructura_en_uso`, y sin esta condición
            // la pantalla diría «ya existe ese código» a quien lo que tiene es gente
            // activa en el puesto.
            if (fallo.codigo == 'code_conflict' && codigo != null) {
              return Result.failure(
                ApiHttpFailure(
                  statusCode: 409,
                  message:
                      'Ya existe un puesto con el código $codigo. Los códigos no se '
                      'repiten dentro de una empresa.',
                  codigo: fallo.codigo,
                ),
              );
            }

            return Result.failure(fallo);
          }

          return r.decodificar().when(
            failure: Result.failure,
            ok: (json) {
              if (json is! Map<String, dynamic>) {
                return const Result.failure(
                  ApiJsonInvalidoFailure('El servidor no devolvió un puesto.'),
                );
              }

              return Result.ok(Puesto.deJson(json));
            },
          );
        },
      );
}
