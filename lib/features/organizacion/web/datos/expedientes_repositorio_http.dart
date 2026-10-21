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

  /// La clave con la que el 409 trae **el expediente que el servidor tiene ahora**.
  ///
  /// Sin esto el 409 sólo podía decir «recarga y vuelve a escribir lo tuyo», que es
  /// pedirle a la persona que repita su trabajo. Con el expediente del servidor, el
  /// que se cargó al abrir y el que está en el formulario, la pantalla puede comparar
  /// las tres versiones y preguntar **sólo por los campos que de verdad chocan**.
  static const String claveDeActual = 'current';

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
  ///
  /// ⚠️ **EL NOMBRE COMERCIAL ES LA EXCEPCIÓN, y es la contraria.** `nombre` sólo viaja
  /// si se manda, y **nulo significa «no lo toques»**: la columna es `NOT NULL` con
  /// `CHECK (length(btrim(name)) > 0)`, así que una empresa sin nombre no es un estado
  /// al que se pueda llegar. Quien no edita el nombre —porque está en la ficha, o
  /// porque no tiene el permiso— no lo manda.
  ///
  /// **Se puede cambiar desde el 21 de octubre de 2026.** Antes no había ninguna ruta
  /// que renombrara una empresa, así que era una función del escritorio perdida: allá
  /// el nombre comercial es un campo del expediente.
  Future<Result<ExpedienteDeEmpresa>> guardarDeEmpresa({
    required String empresaId,
    required int version,
    String? nombre,
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
        // SÓLO SI SE MANDA, al contrario que los demás: aquí la ausencia es «no lo
        // toques», no «bórralo».
        if (nombre != null) 'name': nombre,
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

  /// Guarda **nombre, tipo, domicilio y horario en una sola transacción**, como el
  /// escritorio: «reúne todos los errores de las tres secciones antes de fallar».
  ///
  /// **EL NOMBRE Y EL TIPO SE GUARDAN AQUÍ desde el 21 de octubre de 2026.** Antes
  /// vivían en el `PATCH` de la sucursal, así que corregir el domicilio y renombrar
  /// eran dos peticiones para una sola intención, y la segunda podía fallar dejando la
  /// primera aplicada. (Y el `PUT` ya declaraba los dos campos en su contrato
  /// **descartándolos en silencio**: se mandaba un nombre nuevo, se recibía 200, y el
  /// nombre seguía igual.)
  ///
  /// **NULO SIGNIFICA «NO LO TOQUES»** en el nombre y el tipo, no «bórralo»: quien no
  /// tiene permiso para modificar la estructura no los manda, y eso no puede vaciarlos.
  /// Cada campo exige el permiso de lo que es —nombre y tipo son
  /// `organizacion.modificar`; domicilio y horario, `company.settings.manage`— y el
  /// servidor sólo exige el de lo que cambia de verdad.
  ///
  /// **Un horario vacío BORRA el que había**, y es deliberado: una sucursal sin
  /// horario publicado es un estado legítimo, y tratar la lista vacía como «no
  /// cambies nada» haría imposible volver a él.
  Future<Result<ExpedienteDeSucursal>> guardarDeSucursal({
    required String empresaId,
    required String sucursalId,
    required int version,
    String? nombre,
    String? tipoId,
    Direccion? direccion,
    List<TramoDeHorario> horario = const [],
  }) async {
    final respuesta = await _api.put(
      CompanyRuta.de(empresaId, '/branches/$sucursalId/profile'),
      json: {
        if (nombre != null) 'name': nombre,
        if (tipoId != null) 'branchTypeId': tipoId,
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

  /// El fallo general, **más los campos señalados y el expediente actual cuando
  /// vienen**.
  ///
  /// No reinterpreta nada de lo que [ApiErrorParser] ya decidió: toma su resultado y
  /// le añade las dos cosas que el parser no conserva porque su lista blanca es de
  /// otra cosa.
  static ApiHttpFailure _interpretar(ApiRespuesta respuesta) {
    final base = ApiErrorParser.interpretar(respuesta);
    final campos = _camposDe(respuesta);
    final actual = _actualDe(respuesta);

    if (campos.isEmpty && actual == null) return base;

    return ApiHttpFailure(
      statusCode: base.statusCode,
      message: base.message,
      codigo: base.codigo,
      extra: {
        ...base.extra,
        if (campos.isNotEmpty) claveDeCampos: campos,
        if (actual != null) claveDeActual: actual,
      },
    );
  }

  /// El expediente que el servidor tiene ahora, **sin leerlo todavía**.
  ///
  /// Se conserva el mapa crudo y no un modelo: los dos expedientes —empresa y
  /// sucursal— llegan por aquí y tienen forma distinta, así que leerlo obligaría a
  /// este método a saber en qué ruta está. Lo lee [actualDe], que sí lo sabe.
  ///
  /// **Tolera que no venga.** El 409 de una LECTURA sale sin cuerpo, y un servidor
  /// viejo tampoco lo manda: entonces el aviso sale con su mensaje y la pantalla
  /// recarga, que es lo que hacía antes.
  static Map<String, dynamic>? _actualDe(ApiRespuesta respuesta) {
    final cuerpo = respuesta.decodificar().when(
      ok: (valor) => valor,
      failure: (_) => null,
    );

    if (cuerpo is! Map<String, Object?>) return null;

    final actual = cuerpo[claveDeActual];

    return actual is Map<String, dynamic> ? actual : null;
  }

  /// El expediente que el 409 trajo, leído con la fábrica que le corresponda.
  ///
  /// Nulo si el fallo no era ese 409 o si el servidor no lo mandó, y entonces la
  /// pantalla no puede comparar: le queda recargar y avisar.
  static T? actualDe<T>(Failure fallo, T Function(Map<String, dynamic>) leer) {
    if (fallo is! ApiHttpFailure) return null;

    final actual = fallo.extra[claveDeActual];

    return actual is Map<String, dynamic> ? leer(actual) : null;
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
