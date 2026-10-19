import '../../../../core/api/api_client_autenticado.dart';
import '../../../../core/api/api_error_parser.dart';
import '../../../../core/api/api_respuesta.dart';
import '../../../../core/company/company_ruta.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/error/result.dart';
import '../modelos/sucursal.dart';
import '../modelos/tipo_de_sucursal.dart';

/// Las sucursales de una empresa y su catálogo de tipos, contra la API.
///
/// **LOS DOS VIVEN EN EL MISMO REPOSITORIO Y ES DELIBERADO.** No se pueden separar sin
/// mentir: dar de alta una sucursal **exige** un tipo, así que la pantalla de
/// sucursales necesita el catálogo para pintar su selector, y el catálogo sólo existe
/// para ellas. Dos repositorios obligarían a que la pantalla compusiera lo que el
/// dominio ya tiene junto.
///
/// **Devuelve `Result`, nunca lanza**, y la traducción de un fallo HTTP la hace
/// [ApiErrorParser] — no una interpretación propia de este archivo. Lo único que se
/// añade es el **código** cuando hay choque, porque es el único error que el usuario
/// puede arreglar solo y necesita saber cuál repitió.
class SucursalesRepositorioHttp {
  const SucursalesRepositorioHttp(this._api);

  final ApiClientAutenticado _api;

  // =========================================================================
  // Sucursales
  // =========================================================================

  /// Todas, activas e inactivas. **El filtro es de la pantalla**, igual que en Áreas.
  Future<Result<List<Sucursal>>> listar(String empresaId) =>
      _lista(empresaId, '/branches', Sucursal.deJson, 'una lista de sucursales');

  /// Da de alta una sucursal.
  ///
  /// **`tipoId` ES OBLIGATORIO Y NO LO INVENTA ESTE MÉTODO.** El servidor lo exige al
  /// crear —la misma regla que el nivel de un puesto—, así que si no hay ningún tipo
  /// dado de alta, la pantalla tiene que mandar a crear uno primero. Pasar un tipo
  /// cualquiera «para que pase» pondría a todas las sucursales en el mismo cajón.
  Future<Result<Sucursal>> crear({
    required String empresaId,
    required String codigo,
    required String nombre,
    required String tipoId,
  }) async {
    final respuesta = await _api.post(
      CompanyRuta.de(empresaId, '/branches'),
      json: {'code': codigo, 'name': nombre, 'branchTypeId': tipoId},
    );

    return _una(respuesta, Sucursal.deJson, 'una sucursal', codigo: codigo);
  }

  /// Renombra, cambia de tipo, abre o cierra, activa o desactiva.
  ///
  /// **El código no se cambia** —es la identidad de la sucursal— y la ruta no lo
  /// recibe. `cerrada` y `activa` son dos cosas distintas: una sucursal activa puede
  /// estar cerrada por ahora, y una inactiva ya no se usa en absoluto.
  Future<Result<Sucursal>> modificar({
    required String empresaId,
    required String sucursalId,
    String? nombre,
    String? tipoId,
    bool? activa,
    bool? cerradaTemporalmente,
  }) async {
    final respuesta = await _api.patch(
      CompanyRuta.de(empresaId, '/branches/$sucursalId'),
      json: {
        if (nombre != null) 'name': nombre,
        if (tipoId != null) 'branchTypeId': tipoId,
        if (activa != null) 'status': activa ? 'activa' : 'inactiva',
        if (cerradaTemporalmente != null)
          'operationalStatus': cerradaTemporalmente
              ? 'cerrada_temporalmente'
              : 'operando',
      },
    );

    return _una(respuesta, Sucursal.deJson, 'una sucursal');
  }

  // =========================================================================
  // Tipos de sucursal
  // =========================================================================

  Future<Result<List<TipoDeSucursal>>> listarTipos(String empresaId) => _lista(
    empresaId,
    '/branch-types',
    TipoDeSucursal.deJson,
    'una lista de tipos de sucursal',
  );

  Future<Result<TipoDeSucursal>> crearTipo({
    required String empresaId,
    required String codigo,
    required String nombre,
  }) async {
    final respuesta = await _api.post(
      CompanyRuta.de(empresaId, '/branch-types'),
      json: {'code': codigo, 'name': nombre},
    );

    return _una(
      respuesta,
      TipoDeSucursal.deJson,
      'un tipo de sucursal',
      codigo: codigo,
    );
  }

  Future<Result<TipoDeSucursal>> modificarTipo({
    required String empresaId,
    required String tipoId,
    String? nombre,
    bool? activo,
  }) async {
    final respuesta = await _api.patch(
      CompanyRuta.de(empresaId, '/branch-types/$tipoId'),
      json: {
        if (nombre != null) 'name': nombre,
        if (activo != null) 'status': activo ? 'activa' : 'inactiva',
      },
    );

    return _una(respuesta, TipoDeSucursal.deJson, 'un tipo de sucursal');
  }

  /// Agrega de una vez el juego de tipos que el servidor recomienda.
  ///
  /// ⚠️ **DEVUELVE EL CONJUNTO RESULTANTE, NO LO QUE ACABA DE CREAR.** Este comentario
  /// decía lo contrario y era falso; lo midió `BranchTypeTests` del backend:
  ///
  /// ```csharp
  /// var segunda = await AddRecommendedBranchTypesAsync(contexto, Ct);
  /// Assert.Equal(3, segunda.Value!.Count);   // tres, no cero
  /// ```
  ///
  /// Y con un tipo propio preexistente devuelve los tres **incluyendo el suyo con su
  /// nombre original**: el botón no pisa nada.
  ///
  /// **Es idempotente de verdad** —llamarlo dos veces no duplica una sola fila— pero
  /// la respuesta **no dice cuántos se crearon**. Para eso está [tiposNuevos], que
  /// resta contra lo que la pantalla ya tenía cargado; creerle a `length` produce un
  /// «Se agregaron 3» al segundo clic.
  Future<Result<List<TipoDeSucursal>>> agregarTiposRecomendados(
    String empresaId,
  ) async {
    final respuesta = await _api.post(
      CompanyRuta.de(empresaId, '/branch-types/recommended'),
      json: const <String, Object?>{},
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
                  'El servidor no devolvió los tipos que agregó.',
                ),
              );
            }

            return Result.ok([
              for (final fila in json)
                TipoDeSucursal.deJson(fila as Map<String, dynamic>),
            ]);
          },
        );
      },
    );
  }

  // =========================================================================
  // Lo compartido
  // =========================================================================

  /// UNA sola forma de leer una lista. Cuatro `switch` copiados serían cuatro sitios
  /// donde uno puede dejar de traducir el fallo.
  Future<Result<List<T>>> _lista<T>(
    String empresaId,
    String ruta,
    T Function(Map<String, dynamic>) leer,
    String queSeEsperaba,
  ) async {
    final respuesta = await _api.get(CompanyRuta.de(empresaId, ruta));

    return respuesta.when(
      failure: Result.failure,
      ok: (r) {
        if (!r.esExitosa) return Result.failure(ApiErrorParser.interpretar(r));

        return r.decodificar().when(
          failure: Result.failure,
          ok: (json) {
            if (json is! List) {
              return Result.failure(
                ApiJsonInvalidoFailure('El servidor no devolvió $queSeEsperaba.'),
              );
            }

            return Result.ok([
              for (final fila in json) leer(fila as Map<String, dynamic>),
            ]);
          },
        );
      },
    );
  }

  Result<T> _una<T>(
    Result<ApiRespuesta> respuesta,
    T Function(Map<String, dynamic>) leer,
    String queSeEsperaba, {
    String? codigo,
  }) => respuesta.when(
    failure: Result.failure,
    ok: (r) {
      if (!r.esExitosa) {
        final fallo = ApiErrorParser.interpretar(r);

        // EL 409 ES EL ÚNICO QUE EL USUARIO PUEDE ARREGLAR SOLO, y para eso necesita
        // saber qué código repitió. El parser no puede saberlo.
        if (fallo.statusCode == 409 && codigo != null) {
          return Result.failure(
            ApiHttpFailure(
              statusCode: 409,
              message:
                  'Ya existe algo con el código $codigo. Los códigos no se repiten '
                  'dentro de una empresa.',
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
            return Result.failure(
              ApiJsonInvalidoFailure('El servidor no devolvió $queSeEsperaba.'),
            );
          }

          return Result.ok(leer(json));
        },
      );
    },
  );
}
