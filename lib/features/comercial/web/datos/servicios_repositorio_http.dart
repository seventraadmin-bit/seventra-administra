import '../../../../core/api/api_client_autenticado.dart';
import '../../../../core/api/api_error_parser.dart';
import '../../../../core/api/api_respuesta.dart';
import '../../../../core/company/company_ruta.dart';
import '../../../../core/direcciones/direccion.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/error/result.dart';
import '../../../../core/fechas/dia_de_negocio.dart';
import '../modelos/servicio.dart';

/// Los servicios de una empresa, contra la API.
///
/// **Devuelve `Result`, nunca lanza**, y la traducción de un fallo HTTP la hace
/// [ApiErrorParser] — no una interpretación propia de este archivo.
///
/// ## ⚠️ LOS FILTROS VAN AL SERVIDOR, y aquí no es sólo por coste
///
/// El listado **pagina por cursor**, así que filtrar en la pantalla sería directamente
/// **incorrecto**: filtrar una página no es filtrar la cartera. El buscador del servidor
/// mira **folio, nombre, cliente, tipo y observaciones**, los cinco del escritorio.
///
/// ## Los dos selectores de tipo NO son la misma lista
///
/// [tipos] con `usados: true` es lo que ofrece **el filtro del listado** —los tipos que
/// algún servicio usa, incluidos los retirados—; sin el parámetro trae todos y es lo que
/// necesita **el alta**, que se queda con los activos. Filtrar mira hacia atrás —qué hay—
/// y dar de alta mira hacia adelante —qué se puede elegir—, y el día que alguien unifique
/// los dos selectores una de las dos pantallas se rompería.
class ServiciosRepositorioHttp {
  const ServiciosRepositorioHttp(this._api);

  final ApiClientAutenticado _api;

  // =========================================================================
  // Listado y ficha
  // =========================================================================

  /// Una página del listado, filtrada **por el servidor**.
  ///
  /// Cada filtro es independiente y **nulo significa «no filtres por esto»**, no «filtra
  /// por el valor vacío».
  ///
  /// ⚠️ **UN CURSOR NO SE MEZCLA CON OTROS FILTROS.** El cursor que devolvió una búsqueda
  /// es la posición **dentro de ese** resultado, así que cambiar el texto, el estatus, el
  /// cliente o el tipo obliga a empezar de cero: continuar con el viejo saltaría filas sin
  /// avisar. Lo impone la pantalla, que descarta el cursor cada vez que toca un filtro.
  Future<Result<PaginaDeServicios>> listar(
    String empresaId, {
    String? clienteId,
    String? tipoId,
    EstatusDeServicio? estatus,
    String? texto,
    String? cursor,
    int? limite,
  }) async {
    final respuesta = await _api.get(
      CompanyRuta.de(empresaId, '/services'),
      query: {
        if (clienteId != null) 'clientId': clienteId,
        if (tipoId != null) 'serviceTypeId': tipoId,
        if (estatus != null) 'status': estatus.codigo,
        // EL TEXTO SE RECORTA Y SE OMITE SI QUEDA VACÍO: mandar `query=` haría que el
        // servidor buscara la cadena vacía, que casa con todo y le cuesta cinco `ILIKE`
        // por fila.
        if (texto != null && texto.trim().isNotEmpty) 'query': texto.trim(),
        if (cursor != null) 'cursor': cursor,
        if (limite != null) 'limit': limite.toString(),
      },
    );

    return respuesta.when(
      failure: Result.failure,
      ok: (r) {
        if (!r.esExitosa) return Result.failure(ApiErrorParser.interpretar(r));

        return r.decodificar().when(
          failure: Result.failure,
          ok: (json) {
            // SE EXIGE EL SOBRE, no una lista: aceptar las dos formas «por compatibilidad»
            // dejaría a la pantalla creyendo que nunca hay más páginas en lugar de fallar
            // a la vista. Es la misma exigencia que en Clientes y por la misma razón.
            if (json is! Map<String, dynamic> || json['items'] is! List) {
              return const Result.failure(
                ApiJsonInvalidoFailure(
                  'El servidor no devolvió una página de servicios.',
                ),
              );
            }

            return Result.ok(PaginaDeServicios.deJson(json));
          },
        );
      },
    );
  }

  /// Un servicio por su id.
  Future<Result<Servicio>> ver({
    required String empresaId,
    required String servicioId,
  }) async => _uno(
    await _api.get(CompanyRuta.de(empresaId, '/services/$servicioId')),
  );

  /// Los indicadores de la ficha: importe mensual y antigüedad.
  ///
  /// **Ruta propia** y no parte de la ficha, igual que los del cliente: quien sólo quiere
  /// el servicio no paga la consulta del importe.
  Future<Result<IndicadoresDeServicio>> indicadores({
    required String empresaId,
    required String servicioId,
  }) async {
    final respuesta = await _api.get(
      CompanyRuta.de(empresaId, '/services/$servicioId/indicators'),
    );

    return respuesta.when(
      failure: Result.failure,
      ok: (r) {
        if (!r.esExitosa) return Result.failure(ApiErrorParser.interpretar(r));

        return r.decodificar().when(
          failure: Result.failure,
          ok: (json) => json is Map<String, dynamic>
              ? Result.ok(IndicadoresDeServicio.deJson(json))
              : const Result.failure(
                  ApiJsonInvalidoFailure(
                    'El servidor no devolvió los indicadores del servicio.',
                  ),
                ),
        );
      },
    );
  }

  // =========================================================================
  // Alta y corrección
  // =========================================================================

  /// Da de alta un servicio **con su domicilio operativo en la misma petición**.
  ///
  /// ⚠️ **EL DOMICILIO NO ES OPCIONAL Y NO VA EN UN SEGUNDO PASO.** Desde la 0059 la base
  /// no admite un servicio sin él —lo exige un disparador diferido al cerrar la
  /// transacción—, así que el alta es un solo acto: un formulario a medias no deja un
  /// servicio a medias, deja un 400.
  ///
  /// **No recibe folio ni estatus**: el folio lo asigna el servidor y nace `active`.
  /// Tampoco pide motivo — el motivo es para corregir, no para crear.
  Future<Result<Servicio>> crear({
    required String empresaId,
    required String clienteId,
    required String nombre,
    required String tipoId,
    required DiaDeNegocio inicio,
    required Direccion domicilio,
    String? observaciones,
  }) async => _uno(
    await _api.post(
      CompanyRuta.de(empresaId, '/clients/$clienteId/services'),
      json: {
        'name': nombre,
        'serviceTypeId': tipoId,
        'startedOn': inicio.enTexto,
        'notes': observaciones,
        'address': domicilio.aJson(),
      },
    ),
  );

  /// Corrige nombre, tipo u observaciones, **con motivo** (R7).
  ///
  /// ## El motivo no es un campo más del formulario
  ///
  /// El servidor lo valida **antes que los campos** y responde `motivo_requerido` con su
  /// código propio, para que la pantalla señale ese cuadro. Va como parámetro obligatorio
  /// y no como un `String?` más: un motivo opcional sería un 400 esperando a que alguien
  /// lo olvide.
  ///
  /// ⚠️ **No acepta código, cliente ni fechas**, y no es que se ignoren: no existen en el
  /// contrato. Las fechas se mueven con sus propias operaciones, porque cada una tiene que
  /// comprobar que ninguna condición comercial quede fuera.
  Future<Result<Servicio>> corregir({
    required String empresaId,
    required String servicioId,
    required String motivo,
    String? nombre,
    String? tipoId,
    String? observaciones,
  }) async => _uno(
    await _api.patch(
      CompanyRuta.de(empresaId, '/services/$servicioId'),
      json: {
        'reason': motivo,
        // SÓLO VIAJA LO QUE CAMBIÓ: un nulo significa «no toques esto», no «ponlo en
        // nulo». Mandar los tres campos siempre haría que corregir el nombre pisara unas
        // observaciones que otro acababa de escribir.
        if (nombre != null) 'name': nombre,
        if (tipoId != null) 'serviceTypeId': tipoId,
        if (observaciones != null) 'notes': observaciones,
      },
    ),
  );

  // =========================================================================
  // Estado y vigencia
  // =========================================================================

  /// Cambia el estado del servicio, **con motivo** (R8).
  ///
  /// El escritorio lo justifica en su propio código y la razón se sostiene: «la decisión
  /// afecta directamente a la cobranza».
  ///
  /// ## La fecha de término, que es lo único enredado de esta ruta
  ///
  /// - **Al terminar**, [termino] es la fecha efectiva. Sin ella el servidor pone **hoy**.
  ///   No puede ser **futura** —terminar registra un hecho, y para una fecha futura está
  ///   [programarTermino]— ni anterior al inicio.
  /// - **Al reactivar** un servicio cuyo término **ya pasó**, hay que decidir: o
  ///   [retirarTermino] en `true` —se queda sin término— o [termino] con una fecha de hoy
  ///   en adelante. Sin ninguna de las dos, el servidor responde
  ///   `fecha_de_termino_requerida`.
  /// - **Al suspender**, ninguna de las dos tiene sentido y el servidor las rechaza.
  ///
  /// ⚠️ **[retirarTermino] existe porque el cable no distingue «nulo» de «no vino».** El
  /// diseño pedía que `endedOn: null` retirara la fecha y que el campo ausente fuera un
  /// error, y en JSON esas dos peticiones son idénticas. Así que retirar **se dice
  /// explícitamente**, y de paso queda del lado correcto de la norma: una ausencia nunca
  /// se lee como una decisión.
  Future<Result<Servicio>> cambiarEstado({
    required String empresaId,
    required String servicioId,
    required EstatusDeServicio estatus,
    required String motivo,
    DiaDeNegocio? termino,
    bool retirarTermino = false,
  }) async {
    // LAS DOS FORMAS A LA VEZ SON UNA CONTRADICCIÓN, no una preferencia: «retírala» y
    // «ponla el 31 de marzo» no se pueden cumplir las dos. El servidor responde 400, y
    // esto lo convierte en un fallo de programación visible en desarrollo en lugar de un
    // error que el usuario ve.
    assert(
      !(retirarTermino && termino != null),
      'Decide una: retirar la fecha de término o ponerle una. No las dos.',
    );

    return _uno(
      await _api.post(
        CompanyRuta.de(empresaId, '/services/$servicioId/status'),
        json: {
          'status': estatus.codigo,
          'reason': motivo,
          if (termino != null) 'endedOn': termino.enTexto,
          if (retirarTermino) 'clearEndedOn': true,
        },
      ),
    );
  }

  /// Programa o modifica la fecha de término, **sin terminar el servicio**.
  ///
  /// ⚠️ **Acepta hoy o después y rechaza el pasado**, esté el servicio activo o
  /// suspendido: programar es comprometerse a futuro, y para registrar un término que ya
  /// ocurrió está [cambiarEstado] con `terminated` y su fecha.
  Future<Result<Servicio>> programarTermino({
    required String empresaId,
    required String servicioId,
    required DiaDeNegocio termino,
  }) async => _uno(
    await _api.post(
      CompanyRuta.de(empresaId, '/services/$servicioId/schedule-end'),
      json: {'endedOn': termino.enTexto},
    ),
  );

  /// Retira la fecha de término programada. El servicio queda sin término.
  Future<Result<Servicio>> retirarTerminoProgramado({
    required String empresaId,
    required String servicioId,
  }) async => _uno(
    await _api.delete(
      CompanyRuta.de(empresaId, '/services/$servicioId/schedule-end'),
    ),
  );

  // =========================================================================
  // Domicilio operativo
  // =========================================================================

  /// El domicilio operativo. **404 significa que no lo tiene**, que desde la 0059 no
  /// debería pasar — se traduce a nulo y no a un fallo, para que la pantalla pueda pintar
  /// el hueco en lugar de un error.
  Future<Result<Direccion?>> domicilio({
    required String empresaId,
    required String servicioId,
  }) async {
    final respuesta = await _api.get(
      CompanyRuta.de(empresaId, '/services/$servicioId/address'),
    );

    return respuesta.when(
      failure: Result.failure,
      ok: (r) {
        if (r.statusCode == 404) return const Result.ok(null);
        if (!r.esExitosa) return Result.failure(ApiErrorParser.interpretar(r));

        return r.decodificar().when(
          failure: Result.failure,
          ok: (json) => json is Map<String, dynamic>
              ? Result.ok(Direccion.deJson(json))
              : const Result.failure(
                  ApiJsonInvalidoFailure(
                    'El servidor no devolvió un domicilio.',
                  ),
                ),
        );
      },
    );
  }

  /// Reemplaza el domicilio operativo **entero**.
  ///
  /// ⚠️ **Es `PUT` y no `PATCH` campo a campo**, igual que los otros domicilios del
  /// sistema: una dirección es una unidad, y cambiar la calle sin cambiar la colonia suele
  /// ser un error de captura, no una mudanza.
  ///
  /// **No pide motivo**, y es del contrato: el escritorio tampoco lo pide aquí.
  Future<Result<Direccion>> guardarDomicilio({
    required String empresaId,
    required String servicioId,
    required Direccion domicilio,
  }) async {
    final respuesta = await _api.put(
      CompanyRuta.de(empresaId, '/services/$servicioId/address'),
      json: domicilio.aJson(),
    );

    return respuesta.when(
      failure: Result.failure,
      ok: (r) {
        if (!r.esExitosa) return Result.failure(ApiErrorParser.interpretar(r));

        return r.decodificar().when(
          failure: Result.failure,
          ok: (json) => json is Map<String, dynamic>
              ? Result.ok(Direccion.deJson(json))
              : const Result.failure(
                  ApiJsonInvalidoFailure(
                    'El servidor no devolvió un domicilio.',
                  ),
                ),
        );
      },
    );
  }

  // =========================================================================
  // Vínculos
  // =========================================================================

  /// Asigna la entidad fiscal **a la que se le factura** este servicio.
  ///
  /// ⚠️ **El motivo es CONDICIONAL y lo decide el servidor leyendo lo que había**: la
  /// **primera** asignación no lo pide y cambiarla sí (R9). Por eso es `String?` y no
  /// obligatorio — y por eso la pantalla pregunta por el motivo sólo cuando ya hay una.
  Future<Result<Servicio>> asignarEntidadFiscal({
    required String empresaId,
    required String servicioId,
    required String entidadFiscalId,
    String? motivo,
  }) async => _uno(
    await _api.put(
      CompanyRuta.de(empresaId, '/services/$servicioId/fiscal-entity'),
      json: {'id': entidadFiscalId, if (motivo != null) 'reason': motivo},
    ),
  );

  /// Quita la entidad fiscal asignada (R10). **El motivo viaja en la cadena de consulta**,
  /// porque un cuerpo en un `DELETE` lo descartan algunos intermediarios.
  Future<Result<Servicio>> quitarEntidadFiscal({
    required String empresaId,
    required String servicioId,
    required String motivo,
  }) async => _uno(
    await _api.delete(
      CompanyRuta.de(empresaId, '/services/$servicioId/fiscal-entity'),
      query: {'reason': motivo},
    ),
  );

  /// Asigna el contacto **del cliente** que responde por este servicio. **No pide
  /// motivo**: no decide a quién se le factura.
  Future<Result<Servicio>> asignarContactoResponsable({
    required String empresaId,
    required String servicioId,
    required String contactoId,
  }) async => _uno(
    await _api.put(
      CompanyRuta.de(empresaId, '/services/$servicioId/responsible-contact'),
      json: {'id': contactoId},
    ),
  );

  Future<Result<Servicio>> quitarContactoResponsable({
    required String empresaId,
    required String servicioId,
  }) async => _uno(
    await _api.delete(
      CompanyRuta.de(empresaId, '/services/$servicioId/responsible-contact'),
    ),
  );

  /// Asigna la sucursal **propia** que administra el servicio.
  ///
  /// 🚫 **No es dónde se presta** —eso es el servicio mismo—: `Branch` es destino
  /// administrativo y `Service` el operativo. Es la regla fundamental de Personal vista
  /// desde el otro lado.
  Future<Result<Servicio>> asignarSucursalAdministrativa({
    required String empresaId,
    required String servicioId,
    required String sucursalId,
  }) async => _uno(
    await _api.put(
      CompanyRuta.de(empresaId, '/services/$servicioId/administrative-branch'),
      json: {'id': sucursalId},
    ),
  );

  Future<Result<Servicio>> quitarSucursalAdministrativa({
    required String empresaId,
    required String servicioId,
  }) async => _uno(
    await _api.delete(
      CompanyRuta.de(empresaId, '/services/$servicioId/administrative-branch'),
    ),
  );

  // =========================================================================
  // Supervisor responsable
  // =========================================================================

  /// El supervisor responsable, con su nombre y si sigue activo.
  ///
  /// **404 significa que el servicio no tiene supervisor** y se traduce a nulo: el
  /// servicio existe, el vínculo no. La pantalla sólo pregunta cuando la ficha dice que
  /// hay uno, así que un 404 aquí es una carrera —se lo quitaron entre las dos
  /// peticiones— y no un error que enseñar.
  ///
  /// ⚠️ **Esta ruta exige `clients_services.read`, no `personal.read`.** Quien tenga
  /// Comercial y no Personal **ve** el supervisor y **no se le ofrece el selector**, que
  /// es el que llama a Personal: no se enseña una puerta que va a responder 403.
  Future<Result<SupervisorDelServicio?>> supervisor({
    required String empresaId,
    required String servicioId,
  }) async {
    final respuesta = await _api.get(
      CompanyRuta.de(empresaId, '/services/$servicioId/supervisor'),
    );

    return respuesta.when(
      failure: Result.failure,
      ok: (r) {
        if (r.statusCode == 404) return const Result.ok(null);
        if (!r.esExitosa) return Result.failure(ApiErrorParser.interpretar(r));

        return r.decodificar().when(
          failure: Result.failure,
          ok: (json) => json is Map<String, dynamic>
              ? Result.ok(SupervisorDelServicio.deJson(json))
              : const Result.failure(
                  ApiJsonInvalidoFailure(
                    'El servidor no devolvió un supervisor.',
                  ),
                ),
        );
      },
    );
  }

  /// Nombra al supervisor responsable: un empleado **activo** de la empresa.
  ///
  /// **No pide motivo** y queda en la bitácora. Un empleado que no está activo se rechaza
  /// con `empleado_no_activo`; cualquier empleado activo sirve, **sin filtrar por puesto**.
  Future<Result<Servicio>> asignarSupervisor({
    required String empresaId,
    required String servicioId,
    required String empleadoId,
  }) async => _uno(
    await _api.put(
      CompanyRuta.de(empresaId, '/services/$servicioId/supervisor'),
      json: {'id': empleadoId},
    ),
  );

  Future<Result<Servicio>> quitarSupervisor({
    required String empresaId,
    required String servicioId,
  }) async => _uno(
    await _api.delete(
      CompanyRuta.de(empresaId, '/services/$servicioId/supervisor'),
    ),
  );

  // =========================================================================
  // Catálogo de tipos
  // =========================================================================

  /// Los tipos de servicio de la empresa.
  ///
  /// [usados] nulo trae **todos** —lo que necesita el alta, que se queda con los activos—
  /// y `true` trae **sólo los que algún servicio usa**, que es lo que ofrece el selector
  /// del filtro del listado. «Usado» es por **cualquier** servicio, sin mirar su estado:
  /// un tipo que sólo usan servicios terminados tiene que seguir ofreciéndose, porque el
  /// listado se puede estar mirando con el chip «Finalizados».
  ///
  /// ⚠️ **El parámetro no tiene valor por omisión, a propósito**: cada pantalla dice qué
  /// lista quiere. Un valor por omisión dejaría que la siguiente heredara una de las dos
  /// sin decidirlo.
  Future<Result<List<TipoDeServicio>>> tipos(
    String empresaId, {
    required bool? usados,
  }) async {
    return _catalogo(
      await _api.get(
        CompanyRuta.de(empresaId, '/service-types'),
        query: {if (usados != null) 'used': usados.toString()},
      ),
    );
  }

  /// Crea un tipo. El **código es la identidad** y no se podrá cambiar después.
  ///
  /// El servidor lo normaliza —recorta y pasa a mayúsculas— antes de validarlo, así que
  /// `intramuros` entra como `INTRAMUROS` en vez de rechazarse por estar en minúsculas.
  Future<Result<TipoDeServicio>> crearTipo({
    required String empresaId,
    required String codigo,
    required String nombre,
  }) async => _unTipo(
    await _api.post(
      CompanyRuta.de(empresaId, '/service-types'),
      json: {'code': codigo, 'name': nombre},
    ),
  );

  /// Renombra un tipo o lo activa/desactiva. **El código no se toca**: reclasificar es
  /// desactivar éste y crear otro.
  ///
  /// Cada campo **sólo viaja si cambió**: un nulo significa «no toques esto». Mandar los
  /// dos siempre haría que renombrar reactivara de paso un tipo que alguien acaba de
  /// retirar.
  Future<Result<TipoDeServicio>> modificarTipo({
    required String empresaId,
    required String tipoId,
    String? nombre,
    bool? activo,
  }) async => _unTipo(
    await _api.patch(
      CompanyRuta.de(empresaId, '/service-types/$tipoId'),
      json: {
        if (nombre != null) 'name': nombre,
        if (activo != null) 'status': activo ? 'activa' : 'inactiva',
      },
    ),
  );

  /// Agrega los tipos recomendados que falten y devuelve **el catálogo resultante**.
  ///
  /// ⚠️ **Lo que devuelve NO es lo que creó.** La ruta es idempotente y responde con el
  /// catálogo completo, así que al segundo clic trae los cuatro otra vez. Para decir
  /// cuántos se agregaron de verdad está [tiposDeServicioNuevos], que resta contra lo que
  /// la pantalla ya tenía cargado.
  Future<Result<List<TipoDeServicio>>> agregarTiposRecomendados(
    String empresaId,
  ) async => _catalogo(
    await _api.post(CompanyRuta.de(empresaId, '/service-types/recommended')),
  );

  /// La lectura de **una lista de tipos**, compartida por el listado y los recomendados:
  /// las dos rutas devuelven la misma forma, así que su interpretación también es una.
  Result<List<TipoDeServicio>> _catalogo(Result<ApiRespuesta> respuesta) =>
      respuesta.when(
        failure: Result.failure,
        ok: (r) {
          if (!r.esExitosa) return Result.failure(ApiErrorParser.interpretar(r));

          return r.decodificar().when(
            failure: Result.failure,
            ok: (json) {
              if (json is! List) {
                return const Result.failure(
                  ApiJsonInvalidoFailure(
                    'El servidor no devolvió los tipos de servicio.',
                  ),
                );
              }

              return Result.ok([
                for (final t in json)
                  TipoDeServicio.deJson(t as Map<String, dynamic>),
              ]);
            },
          );
        },
      );

  /// La lectura de **un** tipo: el alta y la modificación devuelven lo mismo.
  Result<TipoDeServicio> _unTipo(Result<ApiRespuesta> respuesta) =>
      respuesta.when(
        failure: Result.failure,
        ok: (r) {
          if (!r.esExitosa) return Result.failure(ApiErrorParser.interpretar(r));

          return r.decodificar().when(
            failure: Result.failure,
            ok: (json) {
              if (json is! Map<String, dynamic>) {
                return const Result.failure(
                  ApiJsonInvalidoFailure(
                    'El servidor no devolvió un tipo de servicio.',
                  ),
                );
              }

              return Result.ok(TipoDeServicio.deJson(json));
            },
          );
        },
      );

  // =========================================================================
  // Apoyo
  // =========================================================================

  /// La respuesta de todo lo que devuelve **un servicio**: la ficha, el alta y las nueve
  /// mutaciones.
  ///
  /// Existe para que ninguna de ellas pueda interpretar un fallo de otra manera: el
  /// contrato es uno, así que su lectura también.
  Result<Servicio> _uno(Result<ApiRespuesta> respuesta) => respuesta.when(
    failure: Result.failure,
    ok: (r) {
      if (!r.esExitosa) return Result.failure(ApiErrorParser.interpretar(r));

      return r.decodificar().when(
        failure: Result.failure,
        ok: (json) {
          if (json is! Map<String, dynamic>) {
            return const Result.failure(
              ApiJsonInvalidoFailure('El servidor no devolvió un servicio.'),
            );
          }

          return Result.ok(Servicio.deJson(json));
        },
      );
    },
  );
}
