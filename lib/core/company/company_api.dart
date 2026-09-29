import '../api/api_client_autenticado.dart';
import '../api/api_error_parser.dart';
import '../api/api_respuesta.dart';
import '../api/json_api.dart';
import '../error/failure.dart';
import '../error/result.dart';
import 'company_remota.dart';
import 'company_ruta.dart';

/// Las dos llamadas de Company del backend SaaS, y ninguna más.
///
/// USA [ApiClientAutenticado] —el decorador de IF-2, no el cliente desnudo— y esa
/// es la diferencia con `AuthApi`: aquí ya hay sesión, así que el token, su
/// refresco preventivo y el reintento tras un 401 están resueltos antes de llegar.
/// Este archivo sólo ve 200, 402, 404 y fallos de transporte.
///
/// LAS DOS RUTAS SON DE NATURALEZA DISTINTA, y el código lo refleja:
///
///  · `GET /companies` es una **colección no scoped**: la lista de Companies que
///    esta Identity puede abrir. No lleva `companyId` y por tanto no pasa por
///    [CompanyRuta.de] — usa [CompanyRuta.coleccion] directamente, porque pedirle
///    al constructor de rutas con Company una ruta sin Company sería forzarlo a
///    representar algo que no es.
///  · `GET /companies/{companyId}/context` sí es **scoped**, y se compone con
///    [CompanyRuta.de], que es el dueño único de ese prefijo.
///
/// NO DECIDE NADA. No interpreta `restricted`, no aplica permisos, no cierra
/// sesión y no elige Company: traduce respuestas. Quién queda activa lo decide
/// `GestorDeCompany`, y qué puede hacer esa persona lo decidirá IF-4.
class CompanyApi {
  const CompanyApi(this._cliente);

  final ApiClientAutenticado _cliente;

  /// Las Companies que esta Identity puede abrir, de **todas** sus Organizations.
  ///
  /// El servidor ya las entrega filtradas —sólo acceso, Company y Organization
  /// activos— y **ordenadas por Organization y luego por nombre**, así que aquí no
  /// se reordena: hacerlo duplicaría una decisión que ya está tomada y podría
  /// divergir de ella.
  ///
  /// Sin paginación, porque el endpoint no la tiene. Queda anotado como deuda del
  /// backend, no como algo que el cliente pueda simular.
  Future<Result<List<CompanyDisponible>>> listarAccesibles() async {
    final respuesta = await _cliente.get(CompanyRuta.coleccion);

    switch (respuesta) {
      case Err<ApiRespuesta>(:final failure):
        return Result.failure(failure);

      case Ok<ApiRespuesta>(:final value):
        if (!value.esExitosa) {
          return Result.failure(ApiErrorParser.interpretar(value));
        }

        return value.comoLista().when(ok: _leerLista, failure: Result.failure);
    }
  }

  /// El contexto de una Company concreta.
  ///
  /// Los tres desenlaces que importan, y los tres son distintos:
  ///
  ///  · **200** → el contexto, con sus diez campos;
  ///  · **404 `empresa_no_disponible`** → AUTORITATIVO. La Company no existe, se
  ///    desactivó, su Organization se desactivó o el acceso se revocó. El backend
  ///    responde 404 y no 403 a propósito: un 403 confirmaría que la Company
  ///    existe y permitiría descubrir el mapa de empresas de otros clientes
  ///    probando identificadores;
  ///  · **402 `subscription_restricted`** → la suscripción no permite ni leer.
  ///    **No es una revocación**: el acceso sigue siendo válido y la Company sigue
  ///    estando en la lista.
  ///
  /// Los tres llegan con su `statusCode` y su `codigo` dentro del
  /// [ApiHttpFailure], que es lo que permite a quien llame distinguirlos sin que
  /// esta clase decida por él.
  Future<Result<CompanyContext>> contexto(String companyId) async {
    final String ruta;

    try {
      ruta = CompanyRuta.de(companyId, '/context');
    } on ArgumentError catch (error) {
      // Un `companyId` mal formado es un error de programación. Se devuelve como
      // fallo de configuración en vez de dejar escapar el `ArgumentError`, para
      // que el contrato público de esta clase siga siendo `Result`.
      return Result.failure(
        ApiConfigFailure('Empresa inválida: ${error.message}'),
      );
    }

    final respuesta = await _cliente.get(ruta);

    switch (respuesta) {
      case Err<ApiRespuesta>(:final failure):
        return Result.failure(failure);

      case Ok<ApiRespuesta>(:final value):
        if (!value.esExitosa) {
          return Result.failure(ApiErrorParser.interpretar(value));
        }

        return value.comoObjeto().when(
          ok: CompanyContext.desdeJson,
          failure: Result.failure,
        );
    }
  }

  /// El código con el que el backend dice «esta empresa ya no está disponible
  /// para ti». Vive aquí, junto a quien lo recibe, y no repetido en cada `if`.
  static const String codigoEmpresaNoDisponible = 'empresa_no_disponible';

  /// El código de la restricción comercial. **No** significa revocación.
  static const String codigoSuscripcionRestringida = 'subscription_restricted';

  /// Si un fallo es el 404 autoritativo: la Company dejó de estar disponible.
  ///
  /// Se exige el status **y** el código. Sólo el status sería frágil —un 404 de un
  /// proxy no dice nada sobre el acceso— y sólo el código sería confiar en un texto
  /// sin su contexto HTTP.
  static bool esEmpresaNoDisponible(Failure failure) =>
      failure is ApiHttpFailure &&
      failure.statusCode == 404 &&
      failure.codigo == codigoEmpresaNoDisponible;

  /// Si un fallo es la restricción comercial que impide incluso leer el contexto.
  static bool esSuscripcionRestringida(Failure failure) =>
      failure is ApiHttpFailure && failure.statusCode == 402;

  static Result<List<CompanyDisponible>> _leerLista(List<Object?> crudo) {
    return JsonApi.objetos(crudo).when(
      ok: (objetos) {
        final companies = <CompanyDisponible>[];

        for (final objeto in objetos) {
          final leida = CompanyDisponible.desdeJson(objeto);

          // Una sola empresa ilegible invalida la lista entera, y es lo correcto:
          // seguir con las que sí se entendieron dejaría al usuario eligiendo
          // entre un subconjunto silencioso de sus empresas.
          switch (leida) {
            case Err<CompanyDisponible>(:final failure):
              return Result.failure(failure);
            case Ok<CompanyDisponible>(:final value):
              companies.add(value);
          }
        }

        return Result.ok(companies);
      },
      failure: Result.failure,
    );
  }
}
