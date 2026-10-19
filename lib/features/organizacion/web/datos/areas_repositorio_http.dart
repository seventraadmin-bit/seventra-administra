import '../../../../core/api/api_client_autenticado.dart';
import '../../../../core/api/api_error_parser.dart';
import '../../../../core/api/api_respuesta.dart';
import '../../../../core/company/company_ruta.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/error/result.dart';
import '../modelos/area.dart';

/// Las áreas de una empresa, contra la API.
///
/// **No implementa `AreaRepository`**, y no es un descuido: esa interfaz habla
/// `AreaData`, una clase generada por Drift cuyo archivo importa `dart:io`.
/// Implementarla desde la web rompería la build. Ver el doc de [Area].
///
/// **Devuelve `Result`, nunca lanza.** El cliente ya traduce todo fallo de transporte;
/// lo que falta es convertir una respuesta HTTP no exitosa en un fallo, y eso lo hace
/// [ApiErrorParser] — **no una interpretación propia de este archivo**. Que existiera
/// una traducción por módulo es justo lo que ese parser vino a evitar.
///
/// Lo único que este repositorio añade al mensaje del parser es el **código del área**
/// cuando hay choque, porque es el único error que el usuario puede arreglar solo y
/// necesita saber cuál repitió.
class AreasRepositorioHttp {
  const AreasRepositorioHttp(this._api);

  final ApiClientAutenticado _api;

  /// Todas las áreas, activas e inactivas.
  ///
  /// **La pantalla oculta las inactivas por omisión, pero el filtro es de la
  /// PANTALLA, no de aquí.** Pedirle al servidor sólo las activas obligaría a una
  /// segunda petición al encender «Mostrar inactivas», y a tener dos listas que
  /// pueden discrepar.
  Future<Result<List<Area>>> listar(String empresaId) async {
    final respuesta = await _api.get(CompanyRuta.de(empresaId, '/areas'));

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
                  'El servidor no devolvió una lista de áreas.',
                ),
              );
            }

            return Result.ok([
              for (final fila in json) Area.deJson(fila as Map<String, dynamic>),
            ]);
          },
        );
      },
    );
  }

  Future<Result<Area>> crear({
    required String empresaId,
    required String codigo,
    required String nombre,
  }) async {
    final respuesta = await _api.post(
      CompanyRuta.de(empresaId, '/areas'),
      json: {'code': codigo, 'name': nombre},
    );

    return _unaArea(respuesta, codigo: codigo);
  }

  /// Renombra, activa o desactiva.
  ///
  /// **Los tres son el mismo `PATCH`**, y el contrato no acepta nada más: el código
  /// de un área no se cambia —es su identidad— y la ruta no lo recibe.
  Future<Result<Area>> modificar({
    required String empresaId,
    required String areaId,
    String? nombre,
    bool? activa,
  }) async {
    final respuesta = await _api.patch(
      CompanyRuta.de(empresaId, '/areas/$areaId'),
      json: {
        if (nombre != null) 'name': nombre,
        if (activa != null) 'status': activa ? 'activa' : 'inactiva',
      },
    );

    return _unaArea(respuesta);
  }

  /// Elimina físicamente un área que nunca se usó. **Sólo Maestro, con motivo.**
  ///
  /// **El motivo viaja en el cuerpo y no en la URL**, y es una decisión de privacidad
  /// del contrato: una URL acaba en los registros de acceso, en el historial del
  /// navegador y en la barra de direcciones de quien comparte su pantalla, y el motivo
  /// de un borrado puede nombrar a una persona.
  ///
  /// Si el área ya se usó, el servidor contesta 409 `estructura_en_uso` **con el
  /// conteo de puestos** y la salida es desactivarla. Ese mensaje se muestra tal cual:
  /// no se reinterpreta aquí.
  Future<Result<Area>> eliminar({
    required String empresaId,
    required String areaId,
    required String motivo,
  }) async {
    final respuesta = await _api.delete(
      CompanyRuta.de(empresaId, '/areas/$areaId'),
      json: {'reason': motivo},
    );

    return _unaArea(respuesta);
  }

  Result<Area> _unaArea(Result<ApiRespuesta> respuesta, {String? codigo}) =>
      respuesta.when(
        failure: Result.failure,
        ok: (r) {
          if (!r.esExitosa) {
            final fallo = ApiErrorParser.interpretar(r);

            // SE MIRA EL CÓDIGO DEL SERVIDOR, NO SÓLO EL 409, y esto estuvo a punto de
            // ser un error de verdad: hasta M3 el único 409 posible era el código
            // duplicado, así que bastaba con el número. Ahora el servidor contesta 409
            // también con `desactivacion_bloqueada` y `estructura_en_uso`, y sin esta
            // condición la pantalla diría «Ya existe un área con el código OPERACIONES»
            // a quien lo que tiene es tres puestos activos dentro. Un mensaje así manda
            // a la persona a arreglar algo que no está roto.
            if (fallo.codigo == 'code_conflict' && codigo != null) {
              return Result.failure(
                ApiHttpFailure(
                  statusCode: 409,
                  message:
                      'Ya existe un área con el código $codigo. Los códigos no se '
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
                  ApiJsonInvalidoFailure('El servidor no devolvió un área.'),
                );
              }

              return Result.ok(Area.deJson(json));
            },
          );
        },
      );
}
