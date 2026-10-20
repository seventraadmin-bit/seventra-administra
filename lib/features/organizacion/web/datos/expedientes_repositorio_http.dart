import '../../../../core/api/api_client_autenticado.dart';
import '../../../../core/api/api_error_parser.dart';
import '../../../../core/api/api_respuesta.dart';
import '../../../../core/company/company_ruta.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/error/result.dart';
import '../modelos/expediente.dart';

/// Los dos expedientes —el de la empresa y el de una sucursal— contra la API.
///
/// **LOS DOS EN EL MISMO REPOSITORIO**, por la misma razón que sucursales y sus tipos
/// viven juntas: comparten la forma del domicilio, el contador de versión y las dos
/// respuestas de error que nadie más tiene. Separarlos duplicaría la traducción del
/// 409 y del 400 con campos, que es justo donde un descuido se vuelve invisible.
///
/// **Devuelve `Result`, nunca lanza.** La traducción general la hace [ApiErrorParser];
/// aquí se añaden sólo las dos cosas que esa clase no puede saber:
///
///  · el **409 `expediente_desactualizado`** se deja pasar con su `codigo` intacto,
///    para que la pantalla pueda recargar y avisar en vez de mostrar un error seco;
///  · el **400 con `fields`** se conserva en `extra`, porque es lo único que permite
///    señalar el campo exacto. El servidor «reúne todos los errores antes de fallar»
///    —es la regla del expediente en el producto local— y perder la lista obligaría a
///    la persona a descubrirlos de uno en uno.
class ExpedientesRepositorioHttp {
  const ExpedientesRepositorioHttp(this._api);

  final ApiClientAutenticado _api;

  /// La clave con la que viajan los campos señalados dentro de `extra`.
  ///
  /// Se conserva **sólo esta** y con forma conocida —`field` y `message`, los dos
  /// escritos por el servidor—, no el cuerpo entero: es la misma lista blanca que
  /// aplica el parser, por la misma razón que `AuditPayload` en el backend.
  static const String claveDeCampos = 'fields';

  /// El `code` del 409 del control optimista. **Se compara con esto y no con el 409
  /// pelado**: un 409 también puede ser un código repetido, y confundirlos mandaría a
  /// la persona a cambiar un dato cuando lo que pasó es que otra guardó antes.
  static const String codigoDesactualizado = 'expediente_desactualizado';

  // =========================================================================
  // Empresa
  // =========================================================================

  Future<Result<ExpedienteDeEmpresa>> leerDeEmpresa(String empresaId) async {
    final respuesta = await _api.get(CompanyRuta.de(empresaId, '/profile'));

    return _uno(respuesta, ExpedienteDeEmpresa.deJson, 'el expediente de la empresa');
  }

  /// Guarda el expediente completo.
  ///
  /// **`version` NO ES OPCIONAL Y NO LA INVENTA ESTE MÉTODO.** Es la que se leyó al
  /// abrir; mandarla es lo que permite al servidor negarse si alguien más guardó
  /// mientras tanto. Un valor «cualquiera para que pase» borraría el trabajo del otro,
  /// que es exactamente lo que el contador existe para impedir.
  ///
  /// **Los nulos se MANDAN**, no se omiten: este `PUT` reemplaza el expediente, así
  /// que un campo nulo significa «bórralo». Omitirlo dejaría imposible vaciar un dato.
  Future<Result<ExpedienteDeEmpresa>> guardarDeEmpresa({
    required String empresaId,
    required int version,
    String? razonSocial,
    String? rfc,
    String? representanteLegal,
    String? eslogan,
    String? regimenFiscal,
    Direccion? direccion,
    Contacto? contacto,
  }) async {
    final respuesta = await _api.put(
      CompanyRuta.de(empresaId, '/profile'),
      json: {
        'legalName': razonSocial,
        'taxId': rfc,
        'legalRep': representanteLegal,
        'slogan': eslogan,
        'fiscalRegimeCode': regimenFiscal,
        'address': direccion?.aJson(),
        'contact': contacto?.aJson(),
        'profileVersion': version,
      },
    );

    return _uno(respuesta, ExpedienteDeEmpresa.deJson, 'el expediente de la empresa');
  }

  // =========================================================================
  // Sucursal
  // =========================================================================

  Future<Result<ExpedienteDeSucursal>> leerDeSucursal({
    required String empresaId,
    required String sucursalId,
  }) async {
    final respuesta = await _api.get(
      CompanyRuta.de(empresaId, '/branches/$sucursalId/profile'),
    );

    return _uno(
      respuesta,
      ExpedienteDeSucursal.deJson,
      'el expediente de la sucursal',
    );
  }

  /// Guarda domicilio y horario **en una sola transacción**, como el escritorio:
  /// «reúne todos los errores de las tres secciones antes de fallar».
  ///
  /// **Un horario vacío BORRA el que había**, y es deliberado: una sucursal sin
  /// horario publicado es un estado legítimo, y tratar la lista vacía como «no
  /// cambies nada» haría imposible volver a él.
  Future<Result<ExpedienteDeSucursal>> guardarDeSucursal({
    required String empresaId,
    required String sucursalId,
    required int version,
    Direccion? direccion,
    List<TramoDeHorario> horario = const [],
  }) async {
    final respuesta = await _api.put(
      CompanyRuta.de(empresaId, '/branches/$sucursalId/profile'),
      json: {
        'address': direccion?.aJson(),
        'schedule': [for (final t in horario) t.aJson()],
        'profileVersion': version,
      },
    );

    return _uno(
      respuesta,
      ExpedienteDeSucursal.deJson,
      'el expediente de la sucursal',
    );
  }

  // =========================================================================
  // El catálogo del SAT
  // =========================================================================

  /// Los regímenes fiscales, **filtrados por el RFC si se manda**.
  ///
  /// **EL FILTRO AVISA, NO BLOQUEA.** Doce caracteres es persona moral y trece es
  /// persona física; cualquier otra longitud —incluido un RFC a medio escribir—
  /// devuelve el catálogo completo. Un filtro que vaciara la lista escondería un
  /// régimen legítimo y la persona no sabría por qué no aparece.
  Future<Result<List<RegimenFiscal>>> listarRegimenes({
    required String empresaId,
    String? rfc,
  }) async {
    final limpio = (rfc ?? '').trim();

    // EL RFC VA EN `query`, NO PEGADO A LA RUTA, y esto costó una prueba descubrirlo:
    // `ApiConfig.resolver` mete la cadena entera en el PATH de la URL, así que un
    // `'/fiscal-regimes?rfc=…'` se codifica y el `?` acaba siendo parte del camino.
    // La petición habría salido bien, el servidor habría devuelto el catálogo
    // completo, y el filtro **no se habría aplicado nunca sin que nada fallara**.
    final respuesta = await _api.get(
      CompanyRuta.de(empresaId, '/fiscal-regimes'),
      query: limpio.isEmpty ? null : {'rfc': limpio},
    );

    return respuesta.when(
      failure: Result.failure,
      ok: (r) {
        if (!r.esExitosa) return Result.failure(_interpretar(r));

        return r.decodificar().when(
          failure: Result.failure,
          ok: (json) {
            if (json is! List) {
              return const Result.failure(
                ApiJsonInvalidoFailure(
                  'El servidor no devolvió una lista de regímenes fiscales.',
                ),
              );
            }

            return Result.ok([
              for (final fila in json)
                RegimenFiscal.deJson(fila as Map<String, dynamic>),
            ]);
          },
        );
      },
    );
  }

  // =========================================================================
  // Lo compartido
  // =========================================================================

  Result<T> _uno<T>(
    Result<ApiRespuesta> respuesta,
    T Function(Map<String, dynamic>) leer,
    String queSeEsperaba,
  ) => respuesta.when(
    failure: Result.failure,
    ok: (r) {
      if (!r.esExitosa) return Result.failure(_interpretar(r));

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

  /// El fallo general, **más los campos señalados cuando vienen**.
  ///
  /// No reinterpreta nada de lo que [ApiErrorParser] ya decidió: toma su resultado y
  /// le añade la lista de campos, que el parser no conserva porque su lista blanca es
  /// de otra cosa.
  static ApiHttpFailure _interpretar(ApiRespuesta respuesta) {
    final base = ApiErrorParser.interpretar(respuesta);
    final campos = _camposDe(respuesta);

    if (campos.isEmpty) return base;

    return ApiHttpFailure(
      statusCode: base.statusCode,
      message: base.message,
      codigo: base.codigo,
      extra: {...base.extra, claveDeCampos: campos},
    );
  }

  /// `{'taxId': 'El RFC no tiene la forma…'}`, o vacío.
  ///
  /// **Tolera que no venga y que venga mal.** Un cuerpo sin `fields`, con `fields`
  /// que no es lista, o con filas sin `field` deja el mapa vacío y el mensaje general
  /// hace su trabajo — no se rompe la pantalla por un error al informar de un error.
  static Map<String, String> _camposDe(ApiRespuesta respuesta) {
    final cuerpo = respuesta.decodificar().when(
      ok: (valor) => valor,
      failure: (_) => null,
    );

    if (cuerpo is! Map<String, Object?>) return const {};

    final crudos = cuerpo[claveDeCampos];
    if (crudos is! List) return const {};

    final campos = <String, String>{};

    for (final fila in crudos) {
      if (fila is! Map<String, Object?>) continue;

      final campo = fila['field'];
      final mensaje = fila['message'];

      if (campo is String && campo.isNotEmpty && mensaje is String) {
        campos[campo] = mensaje;
      }
    }

    return campos;
  }

  /// Los campos señalados de un fallo, para la pantalla. Vacío si no había.
  static Map<String, String> camposDe(Failure fallo) {
    if (fallo is! ApiHttpFailure) return const {};

    final campos = fallo.extra[claveDeCampos];

    return campos is Map<String, String> ? campos : const {};
  }

  /// ¿Es el 409 del control optimista? La pantalla reacciona distinto: recarga y
  /// avisa, en vez de mostrar un error que la persona no puede arreglar.
  static bool esDesactualizado(Failure fallo) =>
      fallo is ApiHttpFailure &&
      fallo.statusCode == 409 &&
      fallo.codigo == codigoDesactualizado;
}
