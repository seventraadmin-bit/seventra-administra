import '../../../../core/api/api_client_autenticado.dart';
import '../../../../core/api/api_error_parser.dart';
import '../../../../core/company/autoridad_de_organizacion.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/error/result.dart';
import '../modelos/empresa_administrada.dart';

/// E2 · La administración de empresas de una Organization, contra la API.
///
/// ## Por qué no va en el repositorio de expedientes
///
/// Son **otro plano y otra puerta**. El de expedientes trabaja sobre
/// `/companies/{id}/…` con la autoridad de Company; éste sobre
/// `/organizations/{id}/companies/…` con la autoridad de **Organization**
/// —`companies.manage`, y Owner para el borrado—. Juntarlos habría dejado un archivo
/// donde la mitad de los métodos exigen una cosa y la otra mitad otra.
///
/// ## Los códigos que esta pantalla necesita distinguir
///
/// Cinco, y ninguno es «error»: los cinco son respuestas de negocio con arreglos
/// distintos, y colapsarlos dejaría a quien los lee sin saber qué hacer.
class EmpresasRepositorioHttp {
  const EmpresasRepositorioHttp(this._api);

  final ApiClientAutenticado _api;

  /// `409` · es la única empresa activa de la organización.
  static const String codigoUltimaActiva = 'ultima_empresa_activa';

  /// `409` · ya estaba en ese estado. Se mira para no asustar: no hay nada que arreglar.
  static const String codigoSinCambio = 'sin_cambio';

  /// `409` · tiene datos de negocio, así que no se puede **descartar**.
  static const String codigoConDatos = 'empresa_con_datos';

  /// `409` · está descartada, y desde Administra eso no se revierte.
  ///
  /// **No se colapsa con «sin cambio»**: eso invitaría a reintentar, y aquí no hay
  /// reintento posible. Recuperarla será cosa de SEVENTRA, desde Console.
  static const String codigoDescartada = 'empresa_descartada';

  /// `409` · la capacidad contratada no alcanza.
  static const String codigoSinCapacidad = 'capacity_exceeded';

  /// `403` · pertenece a la organización y no tiene autoridad para esto.
  static const String codigoSinAutoridad = 'autoridad_insuficiente';

  // =========================================================================
  // La autoridad propia
  // =========================================================================

  /// Qué es esta persona en la Organization.
  ///
  /// **Se pregunta y no se deduce del contexto de la empresa activa**: son dos planos
  /// distintos, y un Maestro puede no ser miembro de la Organization.
  ///
  /// ⚠️ **Un `404` significa «no eres miembro», y NO es un fallo que la pantalla deba
  /// gritar.** Es el caso de la mayoría: un Maestro que administra su empresa y no
  /// gobierna la organización. Devuelve `null`, y quien llama no enseña la pestaña.
  Future<Result<AutoridadDeOrganizacion?>> leerAutoridad(
    String organizationId,
  ) async {
    final respuesta = await _api.get('/organizations/$organizationId/membership');

    return respuesta.when(
      failure: Result.failure,
      ok: (r) {
        if (r.statusCode == 404) return const Result.ok(null);

        if (!r.esExitosa) return Result.failure(ApiErrorParser.interpretar(r));

        return r.decodificar().when(
          failure: Result.failure,
          ok: (json) => json is Map<String, Object?>
              ? AutoridadDeOrganizacion.desdeJson(organizationId, json).when(
                  ok: Result<AutoridadDeOrganizacion?>.ok,
                  failure: Result<AutoridadDeOrganizacion?>.failure,
                )
              : const Result.failure(
                  ApiJsonInvalidoFailure(
                    'El servidor no devolvió una membresía.',
                  ),
                ),
        );
      },
    );
  }

  // =========================================================================
  // Las empresas
  // =========================================================================

  /// Todas las empresas de la Organization, **incluidas las inactivas**.
  ///
  /// La otra lista —la de empresas accesibles— filtra por activas, así que sin ésta una
  /// empresa desactivada sería inalcanzable: desaparecería de la lista y del autorizador
  /// a la vez, y nadie podría reactivarla.
  Future<Result<List<EmpresaAdministrada>>> listar(String organizationId) async {
    final respuesta = await _api.get(
      '/organizations/$organizationId/companies/administration',
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
                  'El servidor no devolvió una lista de empresas.',
                ),
              );
            }

            final empresas = <EmpresaAdministrada>[];

            // UNA FILA MAL FORMADA DETIENE LA LISTA ENTERA, y no se omite en silencio:
            // una lista de administración a la que le falte una empresa invita a decidir
            // sobre lo que no está — por ejemplo, a desactivar la última activa creyendo
            // que hay otra.
            for (final fila in json) {
              if (fila is! Map<String, Object?>) {
                return const Result.failure(
                  ApiJsonInvalidoFailure('Una fila de la lista no es un objeto.'),
                );
              }

              final fallo = EmpresaAdministrada.desdeJson(fila).when(
                ok: (empresa) {
                  empresas.add(empresa);
                  return null;
                },
                failure: (f) => f,
              );

              if (fallo != null) return Result.failure(fallo);
            }

            return Result.ok(empresas);
          },
        );
      },
    );
  }

  /// Da de alta una empresa.
  ///
  /// **`maestroIdentityId` puede ir nulo, y entonces el Maestro es quien crea.** Es lo
  /// que el servidor hace cuando no se le indica, y hoy es lo único que la interfaz
  /// puede ofrecer: elegir a otra persona exigiría resolver su identidad, y Administra
  /// no tiene ninguna ruta que convierta un correo en un `identityId`.
  ///
  /// No es un atajo que esconda nada: la pantalla lo dice —«tú serás su Maestro»— y dar
  /// acceso a otras personas se hace después, desde Usuarios.
  Future<Result<void>> crear({
    required String organizationId,
    required String nombre,
    String? maestroIdentityId,
    String? razonSocial,
  }) async {
    final respuesta = await _api.post(
      '/organizations/$organizationId/companies',
      json: {
        'name': nombre,
        if (maestroIdentityId != null) 'maestroIdentityId': maestroIdentityId,
        if (razonSocial != null && razonSocial.trim().isNotEmpty)
          'legalName': razonSocial.trim(),
      },
    );

    return _sinCuerpo(respuesta);
  }

  /// Desactiva una empresa. **El motivo es obligatorio** y va a la auditoría.
  Future<Result<void>> desactivar({
    required String organizationId,
    required String companyId,
    required String motivo,
  }) async {
    final respuesta = await _api.post(
      '/organizations/$organizationId/companies/$companyId/deactivation',
      json: {'reason': motivo},
    );

    return _sinCuerpo(respuesta);
  }

  /// Reactiva una empresa. **Vuelve a pedir capacidad**, así que puede fallar con
  /// cifras: desactivar liberó plaza, licencias y cuenta de empleados.
  Future<Result<void>> reactivar({
    required String organizationId,
    required String companyId,
  }) async {
    final respuesta = await _api.delete(
      '/organizations/$organizationId/companies/$companyId/deactivation',
    );

    return _sinCuerpo(respuesta);
  }

  /// **Descarta** una empresa sin datos. **Sólo el Owner**, con motivo.
  ///
  /// 🚫 **NO ES UN BORRADO.** La fila se queda con estado `descartada` y desaparece de
  /// todas las listas; el borrado físico no existe porque la traza de auditoría de la
  /// empresa la retiene, y conservarla es el punto.
  ///
  /// Es un `POST` y no un `DELETE` **a propósito**: lo que ocurre es que se escribe un
  /// estado, y un verbo que dijera «borrar» prometería algo que no pasa.
  Future<Result<void>> descartar({
    required String organizationId,
    required String companyId,
    required String motivo,
  }) async {
    final respuesta = await _api.post(
      '/organizations/$organizationId/companies/$companyId/discard',
      json: {'reason': motivo},
    );

    return _sinCuerpo(respuesta);
  }

  Future<Result<void>> _sinCuerpo(Result<dynamic> respuesta) async =>
      respuesta.when(
        failure: Result.failure,
        ok: (r) => r.esExitosa
            ? const Result.ok(null)
            : Result.failure(ApiErrorParser.interpretar(r)),
      );
}
