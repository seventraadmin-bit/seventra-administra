import '../../../../core/api/api_client_autenticado.dart';
import '../../../../core/api/api_error_parser.dart';
import '../../../../core/api/api_respuesta.dart';
import '../../../../core/api/lectura_del_contrato.dart';
import '../../../../core/company/company_ruta.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/error/result.dart';
import '../../../../core/fechas/dia_de_negocio.dart';
import '../modelos/condicion_comercial.dart';

/// Las líneas comerciales de un servicio, sus condiciones y el sueldo de referencia, contra
/// la API.
///
/// **Devuelve `Result`, nunca lanza**, y la traducción general de un fallo HTTP la hace
/// [ApiErrorParser] — no una interpretación propia de este archivo.
///
/// ## ⚠️ NO HAY UN `PUT` GENÉRICO DE CONDICIÓN, Y ESO NO ES UNA OMISIÓN
///
/// Crear la primera, programar la siguiente, corregir y cancelar son **cuatro actos con
/// cuatro reglas distintas**, y el servidor los separa a propósito: un CRUD cómodo
/// permitiría reescribir un precio que ya se facturó. Este repositorio **respeta esa
/// separación** en vez de ofrecer un `guardar` que decida solo cuál usar — la pantalla sabe
/// qué está haciendo y el repositorio no tiene por qué adivinarlo.
///
/// ## Lo que este repositorio añade sobre el parser
///
/// Dos cosas que [ApiErrorParser] no puede saber:
///
///  · el **409 `condicion_desactualizada`** se deja pasar con su `codigo` intacto y con
///    `current` conservado, para que la pantalla pueda enseñar qué chocó **sin tirar lo que
///    la persona escribió**;
///  · el **aviso `cupo_rebasado`**, que viaja dentro de una respuesta **de éxito** y por eso
///    no pasa por el parser en absoluto. 🚫 Un aviso tratado como error diría «no se guardó»
///    de algo que sí se guardó.
///
/// ## El sueldo de referencia pide un permiso de OTRO módulo
///
/// Leer el historial exige **`personal.sueldo.ver`**, y cambiarlo
/// **`clients_services.pricing.manage`**. Así que la pantalla tiene que poder enseñar la
/// condición **sin** el sueldo: un 403 ahí no es un fallo del expediente, es «esta sesión no
/// ve sueldos».
class CondicionesRepositorioHttp {
  const CondicionesRepositorioHttp(this._api);

  final ApiClientAutenticado _api;

  /// El `code` del 409 del candado de versión.
  ///
  /// **Se compara con esto y no con el 409 pelado**: un 409 también puede ser «esa línea ya
  /// tiene una condición programada» o «la vigente tiene historia detrás», y confundirlos
  /// mandaría a la persona a recargar cuando lo que tiene que hacer es cancelar la
  /// programada.
  static const String codigoDesactualizada = 'condicion_desactualizada';

  /// El `code` del 409 de «la vigente tiene más de una condición detrás».
  ///
  /// Tiene código propio porque **la salida es otra**: aquí lo que procede es programar la
  /// siguiente, y la pantalla puede ofrecer ese botón.
  static const String codigoConHistoria = 'condicion_con_historia';

  /// La clave con la que el 409 trae **la condición que el servidor tiene ahora**.
  static const String claveDeActual = 'current';

  // =========================================================================
  // Líneas
  // =========================================================================

  /// Las líneas comerciales del servicio. **No pagina**: un servicio tiene unas pocas.
  Future<Result<List<LineaComercial>>> lineas({
    required String empresaId,
    required String servicioId,
  }) async => _lista(
    await _api.get(_lineasDe(empresaId, servicioId)),
    'las líneas comerciales',
    LineaComercial.deJson,
  );

  /// Crea una línea. **Nace sin condiciones y por tanto sin cobrar nada**, que es por lo que
  /// esto sólo pide `clients_services.manage` y no el permiso de precios.
  /// Da de alta una línea **con su primera condición**, en una sola petición.
  ///
  /// 🚫 **UN SOLO FORMULARIO, decisión del dueño del 18-nov-2026.** Antes eran dos pasos
  /// —crear la línea y luego «Poner su condición»— y entre los dos quedaba una línea que
  /// **no cobra nada**: fue el defecto que apareció en su prueba en pantalla. El servidor lo
  /// escribe todo en **una transacción**: si la condición falla, la línea no queda creada.
  ///
  /// ⚠️ **Pide los DOS permisos**, `manage` y `pricing.manage`, porque pone un precio. Sin el
  /// de precios responde **403** y la pantalla no ofrece el botón.
  Future<Result<LineaCreada>> crearLinea({
    required String empresaId,
    required String servicioId,
    required String nombre,
    required TipoDeLinea tipo,
    required CondicionEnviada condicion,
    int? sueldoDeReferenciaMenores,
    int? bonoDeReferenciaMenores,
  }) async => _uno(
    await _api.post(
      _lineasDe(empresaId, servicioId),
      json: {
        'name': nombre,
        'kind': tipo.codigo,
        'firstTerm': {
          ...condicion.aJson(),
          if (sueldoDeReferenciaMenores != null)
            'salaryReferenceMinor': sueldoDeReferenciaMenores,
          if (bonoDeReferenciaMenores != null)
            'salaryBonusMinor': bonoDeReferenciaMenores,
        },
      },
    ),
    'la línea comercial',
    LineaCreada.deJson,
  );

  /// Renombra una línea. **Sólo el nombre**: su identidad no cambia nunca.
  Future<Result<LineaComercial>> renombrarLinea({
    required String empresaId,
    required String servicioId,
    required String lineaId,
    required String nombre,
  }) async => _unaLinea(
    await _api.patch(
      '${_lineasDe(empresaId, servicioId)}/$lineaId',
      json: {'name': nombre},
    ),
  );

  /// Retira una línea **y cierra su condición vigente el último día que cobra**, en una sola
  /// petición y una sola transacción (19-nov-2026).
  ///
  /// 🚫 **CAMBIÓ DE SIGNIFICADO, por decisión del dueño:** hasta el 19-nov-2026 retirar
  /// dejaba la condición **abierta** y la línea seguía facturando. Era coherente y confundía
  /// —se lo encontró en su propia prueba en pantalla—, así que ahora retirar **es** dejar de
  /// cobrar. [cerrarVigente] sigue existiendo para quien cierra un precio y va a poner otro.
  ///
  /// [ultimoDiaQueCobra] es **inclusivo** y se manda **sólo si la línea cobra algo**: sin
  /// condición vigente el servidor responde 422, porque quien capturó la fecha cree que esa
  /// línea deja de cobrar ese día. El motivo es obligatorio siempre.
  Future<Result<LineaRetirada>> retirarLinea({
    required String empresaId,
    required String servicioId,
    required String lineaId,
    required String motivo,
    DiaDeNegocio? ultimoDiaQueCobra,
  }) async => _uno(
    await _api.post(
      '${_lineasDe(empresaId, servicioId)}/$lineaId/retire',
      json: {
        'reason': motivo,
        if (ultimoDiaQueCobra != null) 'endsOn': ultimoDiaQueCobra.enTexto,
      },
    ),
    'la línea retirada',
    LineaRetirada.deJson,
  );

  Future<Result<LineaComercial>> reactivarLinea({
    required String empresaId,
    required String servicioId,
    required String lineaId,
  }) async => _unaLinea(
    await _api.post('${_lineasDe(empresaId, servicioId)}/$lineaId/reactivate'),
  );

  // =========================================================================
  // Condiciones
  // =========================================================================

  /// El historial completo de condiciones de una línea, **de la más reciente a la más
  /// antigua**, como lo ordena el servidor.
  Future<Result<List<CondicionComercial>>> historial({
    required String empresaId,
    required String servicioId,
    required String lineaId,
  }) async => _lista(
    await _api.get('${_lineasDe(empresaId, servicioId)}/$lineaId/terms'),
    'el historial de condiciones',
    CondicionComercial.deJson,
  );

  /// Crea la **PRIMERA** condición de la línea, con sus horarios y —si se captura— el
  /// sueldo de referencia de arranque.
  ///
  /// ⚠️ **El sueldo de referencia SÓLO viaja aquí.** En [programarSiguiente] y en [corregir]
  /// el servidor lo rechaza con 422, y es deliberado: si subir el precio arrastrara el
  /// sueldo, volveríamos al problema que la migración 0065 resolvió.
  Future<Result<CondicionComercial>> crearPrimera({
    required String empresaId,
    required String servicioId,
    required String lineaId,
    required CondicionEnviada condicion,
    int? sueldoDeReferenciaMenores,
    int? bonoDeReferenciaMenores,
  }) async => _unaCondicion(
    await _api.post(
      '${_lineasDe(empresaId, servicioId)}/$lineaId/terms',
      json: {
        ...condicion.aJson(),
        if (sueldoDeReferenciaMenores != null)
          'salaryReferenceMinor': sueldoDeReferenciaMenores,
        if (bonoDeReferenciaMenores != null)
          'salaryBonusMinor': bonoDeReferenciaMenores,
      },
    ),
  );

  /// Programa la siguiente condición: **cierra la vigente el día anterior** y abre la nueva,
  /// todo en una transacción del servidor.
  ///
  /// Una sola condición futura pendiente por línea: con otra ya programada responde
  /// **409 `ya_existe_condicion_futura`**, y entonces lo que procede es corregir esa o
  /// cancelarla.
  Future<Result<CondicionComercial>> programarSiguiente({
    required String empresaId,
    required String servicioId,
    required String lineaId,
    required CondicionEnviada condicion,
  }) async => _unaCondicion(
    await _api.post(
      '${_lineasDe(empresaId, servicioId)}/$lineaId/terms/schedule-next',
      json: condicion.aJson(),
    ),
  );

  /// Corrige una condición **programada** —o **la vigente si es la única de la línea**, y
  /// entonces el motivo es obligatorio.
  ///
  /// ⚠️ **`version` no se inventa.** Es la que se leyó al abrir el formulario; mandarla es lo
  /// que permite al servidor negarse si alguien más guardó mientras tanto. Si se omite, el
  /// candado **no actúa** —es aditivo— y la última escritura se lleva la anterior sin avisar.
  Future<Result<CondicionComercial>> corregir({
    required String empresaId,
    required String servicioId,
    required String lineaId,
    required String condicionId,
    required CondicionEnviada condicion,
    required int version,
    String? motivo,
  }) async => _unaCondicion(
    await _api.patch(
      '${_lineasDe(empresaId, servicioId)}/$lineaId/terms/$condicionId',
      json: {
        ...condicion.aJson(),
        'expectedVersion': version,
        if (motivo != null && motivo.trim().isNotEmpty) 'reason': motivo.trim(),
      },
    ),
  );

  /// Cancela una condición **programada** que nunca estuvo en vigor — **y decide qué pasa
  /// con la vigente que esa programación cerró** (D-84, 24-nov-2026).
  ///
  /// Es el único borrado del dominio. Sobre una vigente o una histórica responde
  /// **409 `condicion_no_corregible`**: la historia comercial no se borra.
  ///
  /// 🚫 **ES UN `POST` CON CUERPO Y ANTES ERA UN `DELETE` PELADO**, porque cancelar mueve
  /// dinero: programar cierra la vigente el día anterior, así que cancelar sin decidir
  /// dejaría la línea **sin cobrar desde ese día sin que nadie lo eligiera**.
  ///
  /// [salida] es `sin_termino`, `misma_fecha` u `otra_fecha`; va **nula** cuando esa
  /// programación no cerró ninguna condición —y entonces mandarla responde **422**—. Sin
  /// ella, una programada que sí cerró responde **400 `decision_de_la_vigente_requerida`**.
  Future<Result<void>> cancelarProgramada({
    required String empresaId,
    required String servicioId,
    required String lineaId,
    required String condicionId,
    String? salida,
    DiaDeNegocio? termino,
    String? motivo,
  }) async {
    final respuesta = await _api.post(
      '${_lineasDe(empresaId, servicioId)}/$lineaId/terms/$condicionId/cancel',
      json: {
        if (salida != null) 'salida': salida,
        if (termino != null) 'endsOn': termino.enTexto,
        if (motivo != null && motivo.trim().isNotEmpty) 'reason': motivo.trim(),
      },
    );

    return respuesta.when(
      failure: Result.failure,
      ok: (r) => r.esExitosa
          ? const Result.ok(null)
          : Result.failure(ApiErrorParser.interpretar(r)),
    );
  }

  /// **PONE** el último día de cobro a la condición vigente: la línea deja de cobrar desde el
  /// día siguiente a [termino].
  ///
  /// 🚫 **La fecha no se asume hoy y el motivo no es opcional.** Cerrar con el día
  /// equivocado es facturar un mes de más o de menos, y el día en que algo dejó de operar lo
  /// sabe quien lo cierra, no el reloj del servidor.
  ///
  /// Con una condición **programada pendiente** responde 409: hay que cancelarla primero, y
  /// el mensaje del servidor lo dice.
  ///
  /// 🚫 **Y si la condición YA tiene último día, responde 409 `term_ya_tiene_termino`**
  /// (19-nov-2026): mover la fecha es otro acto, [cambiarTerminoVigente]. Hasta ese día esta
  /// ruta la aceptaba y **movía la fecha en silencio**.
  Future<Result<CondicionComercial>> cerrarVigente({
    required String empresaId,
    required String servicioId,
    required String lineaId,
    required DiaDeNegocio termino,
    required String motivo,
  }) async => _unaCondicion(
    await _api.post(
      '${_lineasDe(empresaId, servicioId)}/$lineaId/terms/current/close',
      json: {'endsOn': termino.enTexto, 'reason': motivo.trim()},
    ),
  );

  /// **CAMBIA** el último día de cobro de una condición que **ya lo tiene**: corrige una baja
  /// ya decidida, con su propio motivo.
  ///
  /// 🚫 **Es un acto distinto de [cerrarVigente], y por eso es otra ruta.** Poner cierra algo
  /// que cobraba sin fin; cambiar corrige una fecha que ya se eligió, y la bitácora tiene que
  /// poder distinguirlas: dos actos con el mismo nombre dejan la historia sin decir cuándo se
  /// decidió qué.
  ///
  /// ⚠️ **Admite alargar la fecha** mientras quepa en la vida del servicio. Lo que no admite
  /// es **quitarla** —eso es volver a cobrar sin fin, o sea reactivar la línea— ni alcanzar
  /// una condición cuya fecha **ya pasó**, que es historia: entonces responde que no hay
  /// condición vigente.
  Future<Result<CondicionComercial>> cambiarTerminoVigente({
    required String empresaId,
    required String servicioId,
    required String lineaId,
    required DiaDeNegocio termino,
    required String motivo,
  }) async => _unaCondicion(
    await _api.post(
      '${_lineasDe(empresaId, servicioId)}/$lineaId/terms/current/change-end',
      json: {'endsOn': termino.enTexto, 'reason': motivo.trim()},
    ),
  );

  // =========================================================================
  // Sueldo de referencia
  // =========================================================================

  /// El historial del sueldo de referencia, del más reciente al más antiguo.
  ///
  /// ⚠️ **Pide `personal.sueldo.ver`**, que es de otro módulo. Un 403 aquí no es un fallo del
  /// expediente: es que esta sesión no ve sueldos, y la pantalla tiene que seguir enseñando
  /// todo lo demás.
  Future<Result<List<SueldoDeReferencia>>> sueldosDeReferencia({
    required String empresaId,
    required String servicioId,
    required String lineaId,
  }) async => _lista(
    await _api.get('${_lineasDe(empresaId, servicioId)}/$lineaId/salary-references'),
    'el sueldo de referencia',
    SueldoDeReferencia.deJson,
  );

  /// Mueve el sueldo de referencia desde una fecha, con motivo. **No toca el precio.**
  ///
  /// El servidor cierra el tramo anterior el día previo; si [desde] coincide con el inicio
  /// del tramo abierto, lo **corrige en su sitio** en lugar de apilar otro.
  ///
  /// 🚫 **Un sueldo de cero no es una referencia**, es no tener ninguna: eso se dice no
  /// llamando a este método.
  Future<Result<SueldoDeReferencia>> moverSueldoDeReferencia({
    required String empresaId,
    required String servicioId,
    required String lineaId,
    required DiaDeNegocio desde,
    required int sueldoMenores,
    required String moneda,
    required String motivo,
    int? bonoMenores,
  }) async => _unSueldo(
    await _api.post(
      '${_lineasDe(empresaId, servicioId)}/$lineaId/salary-references',
      json: {
        'startsOn': desde.enTexto,
        'salaryMinor': sueldoMenores,
        if (bonoMenores != null) 'bonusMinor': bonoMenores,
        'currency': moneda,
        'reason': motivo.trim(),
      },
    ),
  );

  // =========================================================================
  // Modalidades de turno
  // =========================================================================

  /// El catálogo de modalidades de la empresa.
  ///
  /// Trae **la explicación y si pide periodo**, que es lo que el formulario necesita para
  /// enseñar o esconder el desplegable de Diurno/Nocturno. Deducirlo de los códigos en la
  /// pantalla sería una regla que ninguna empresa podría corregir.
  Future<Result<List<ModalidadDeTurno>>> modalidades(String empresaId) async => _lista(
    await _api.get(CompanyRuta.de(empresaId, '/shift-modalities')),
    'las modalidades de turno',
    ModalidadDeTurno.deJson,
  );

  /// Agrega las modalidades recomendadas que falten y devuelve **el catálogo resultante**.
  ///
  /// ⚠️ **Lo que devuelve NO es lo que creó.** La ruta es idempotente, así que al segundo
  /// clic trae todas otra vez. Para decir cuántas se agregaron de verdad se resta contra lo
  /// que la pantalla ya tenía, igual que con los tipos de servicio.
  Future<Result<List<ModalidadDeTurno>>> agregarModalidadesRecomendadas(
    String empresaId,
  ) async => _lista(
    await _api.post(CompanyRuta.de(empresaId, '/shift-modalities/recommended')),
    'las modalidades de turno',
    ModalidadDeTurno.deJson,
  );

  /// Cambia una modalidad. **Lo que no se manda no se toca**; para vaciar la explicación se
  /// manda la cadena vacía, no un nulo.
  /// Da de alta una modalidad propia de la empresa.
  ///
  /// ⚠️ **La duración del turno va si y sólo si se captura por hora de cambio** (0066): el
  /// servidor rechaza una duración en una captura semanal, y rechaza su ausencia en la otra.
  Future<Result<ModalidadDeTurno>> crearModalidad({
    required String empresaId,
    required String codigo,
    required String nombre,
    required String explicacion,
    required bool pidePeriodo,
    required CapturaDelHorario captura,
    int? minutosDelTurno,
  }) async => _unaModalidad(
    await _api.post(
      CompanyRuta.de(empresaId, '/shift-modalities'),
      json: {
        'code': codigo,
        'name': nombre,
        'description': explicacion,
        'requiresPeriod': pidePeriodo,
        'scheduleStyle': captura.codigo,
        'shiftMinutes': minutosDelTurno,
      },
    ),
  );

  Future<Result<ModalidadDeTurno>> modificarModalidad({
    required String empresaId,
    required String modalidadId,
    String? nombre,
    String? explicacion,
    bool? pidePeriodo,
    bool? activa,
    CapturaDelHorario? captura,
    int? minutosDelTurno,
    String? estatus,
  }) async => _unaModalidad(
    await _api.patch(
      CompanyRuta.de(empresaId, '/shift-modalities/$modalidadId'),
      json: {
        if (nombre != null) 'name': nombre,
        if (explicacion != null) 'description': explicacion,
        if (pidePeriodo != null) 'requiresPeriod': pidePeriodo,
        if (activa != null) 'status': activa ? 'activa' : 'inactiva',
        if (estatus != null) 'status': estatus,
        if (captura != null) 'scheduleStyle': captura.codigo,
        // ⚠️ **CERO VACÍA LA DURACIÓN**, y por eso se manda tal cual en lugar de omitirse:
        // un nulo significa «no la toques», y pasar de un turno rotativo a una captura
        // semanal tiene que poder QUITARLA.
        if (minutosDelTurno != null) 'shiftMinutes': minutosDelTurno,
      },
    ),
  );

  // =========================================================================
  // Apoyo
  // =========================================================================

  /// La condición que el 409 del candado trajo, ya leída.
  ///
  /// Nulo si el fallo no era ese 409 o si el servidor no la mandó, y entonces la pantalla no
  /// puede comparar: le queda recargar y avisar.
  static CondicionComercial? actualDe(Failure fallo) {
    if (fallo is! ApiHttpFailure) return null;

    final actual = fallo.extra[claveDeActual];
    if (actual is! Map<String, dynamic>) return null;

    return leyendo(
      'la condición que el servidor tiene ahora',
      () => CondicionComercial.deJson(actual),
    ).when(ok: (c) => c, failure: (_) => null);
  }

  static String _lineasDe(String empresaId, String servicioId) =>
      CompanyRuta.de(empresaId, '/services/$servicioId/commercial-lines');

  /// Añade al fallo del parser **la condición actual** cuando el 409 la trae.
  ///
  /// No reinterpreta nada de lo que [ApiErrorParser] ya decidió: toma su resultado y le
  /// añade lo único que ese parser no conserva, porque su lista blanca es de otra cosa.
  static ApiHttpFailure _interpretar(ApiRespuesta respuesta) {
    final base = ApiErrorParser.interpretar(respuesta);

    final cuerpo = respuesta.decodificar().when(
      ok: (valor) => valor,
      failure: (_) => null,
    );

    if (cuerpo is! Map<String, Object?>) return base;

    final actual = cuerpo[claveDeActual];
    if (actual is! Map<String, dynamic>) return base;

    return ApiHttpFailure(
      statusCode: base.statusCode,
      message: base.message,
      codigo: base.codigo,
      extra: {...base.extra, claveDeActual: actual},
    );
  }

  Result<List<T>> _lista<T>(
    Result<ApiRespuesta> respuesta,
    String que,
    T Function(Map<String, dynamic>) leer,
  ) => respuesta.when(
    failure: Result.failure,
    ok: (r) {
      if (!r.esExitosa) return Result.failure(ApiErrorParser.interpretar(r));

      return r.decodificar().when(
        failure: Result.failure,
        ok: (json) {
          if (json is! List) {
            return Result.failure(
              ApiJsonInvalidoFailure('El servidor no devolvió $que.'),
            );
          }

          return leyendo(que, () => [
            for (final fila in json) leer(fila as Map<String, dynamic>),
          ]);
        },
      );
    },
  );

  Result<T> _uno<T>(
    Result<ApiRespuesta> respuesta,
    String que,
    T Function(Map<String, dynamic>) leer,
  ) => respuesta.when(
    failure: Result.failure,
    ok: (r) {
      // ⚠️ AQUÍ VA `_interpretar` Y NO EL PARSER A SECAS, y es la mitad útil del 409 del
      // candado: sin esto la pantalla sólo podría decir «recarga» y la persona perdería lo
      // que escribió.
      if (!r.esExitosa) return Result.failure(_interpretar(r));

      return r.decodificar().when(
        failure: Result.failure,
        ok: (json) {
          if (json is! Map<String, dynamic>) {
            return Result.failure(
              ApiJsonInvalidoFailure('El servidor no devolvió $que.'),
            );
          }

          return leyendo(que, () => leer(json));
        },
      );
    },
  );

  Result<LineaComercial> _unaLinea(Result<ApiRespuesta> respuesta) =>
      _uno(respuesta, 'una línea comercial', LineaComercial.deJson);

  Result<CondicionComercial> _unaCondicion(Result<ApiRespuesta> respuesta) =>
      _uno(respuesta, 'una condición comercial', CondicionComercial.deJson);

  Result<SueldoDeReferencia> _unSueldo(Result<ApiRespuesta> respuesta) =>
      _uno(respuesta, 'el sueldo de referencia', SueldoDeReferencia.deJson);

  Result<ModalidadDeTurno> _unaModalidad(Result<ApiRespuesta> respuesta) =>
      _uno(respuesta, 'una modalidad de turno', ModalidadDeTurno.deJson);
}

/// Lo que la pantalla manda al crear, programar o corregir una condición.
///
/// **Un solo tipo para las tres rutas** porque el cuerpo es el mismo: separarlos dejaría
/// tres sitios donde añadir un campo nuevo, y el día que se olvidara uno el formulario
/// dejaría de guardarlo **sin que nada fallara**.
class CondicionEnviada {
  const CondicionEnviada({
    required this.inicio,
    required this.termino,
    required this.puestoId,
    required this.modalidadId,
    required this.periodo,
    required this.plazas,
    required this.moneda,
    required this.iva,
    required this.descripcion,
    required this.horarios,
    this.modo = ModoDeCotizacion.porPersona,
    this.precioUnitarioMenores,
    this.totalMensualMenores,
    this.horaDeCambioMinuto,
    this.observaciones,
  });

  final DiaDeNegocio inicio;

  /// Nulo es **«sin fecha de término»**, que es lo normal: una condición abierta cobra
  /// hasta que se programe la siguiente o se cierre.
  final DiaDeNegocio? termino;

  /// Nulo **sólo** en una línea de concepto: el material no ocupa una plaza.
  final String? puestoId;

  /// **Obligatoria en una línea de personal** desde la 0066. Sin ella el servidor responde
  /// **400 `modalidad_de_turno_requerida`**, y en un concepto mandarla responde **422**.
  final String? modalidadId;

  /// Sólo cuando la modalidad lo pide. Mandarlo cuando no corresponde responde **422**, y
  /// no mandarlo cuando sí corresponde responde **400**: el servidor no adivina.
  final PeriodoDeTurno? periodo;

  /// La **cantidad que se cobra**. Con [ModoDeCotizacion.porPersona] multiplica el precio;
  /// con un total mensual **no multiplica** y es sólo un dato de la operación.
  final int plazas;

  /// Cómo se cotizó. De aquí depende **cuál de los dos precios viaja**.
  final ModoDeCotizacion modo;

  /// En centavos. Va **si y sólo si** el modo es por persona.
  final int? precioUnitarioMenores;

  /// En centavos. Va **si y sólo si** el modo es total mensual.
  ///
  /// 🚫 **No se divide entre las personas para sacar un unitario:** $100 000 entre 3 no es
  /// representable en centavos, y el redondeo cambiaría lo que se cobra.
  final int? totalMensualMenores;

  /// El minuto en que **entra el turno diurno**. Va sólo cuando la modalidad se captura así;
  /// en otro caso el servidor responde **422 `hora_de_cambio_no_aplica`**.
  final int? horaDeCambioMinuto;

  final String moneda;
  final TratamientoDeIva iva;
  final String? descripcion;

  /// El segundo texto libre, que RISEG ONE siempre tuvo.
  final String? observaciones;

  /// **Viajan completos y se reemplazan en bloque.** Una lista vacía significa «sin horario
  /// semanal estructurado», que es válido y no incompleto: un servicio por disponibilidad no
  /// tiene rejilla.
  final List<HorarioEnviado> horarios;

  Map<String, dynamic> aJson() => {
    'startsOn': inicio.enTexto,
    'endsOn': termino?.enTexto,
    'positionId': puestoId,
    'shiftModalityId': modalidadId,
    'shiftPeriod': periodo?.codigo,
    'shiftChangeMinute': horaDeCambioMinuto,
    'headcount': plazas,
    'pricingMode': modo.codigo,
    // ⚠️ **UNO DE LOS DOS, NUNCA LOS DOS.** Mandarlos juntos responde
    // **422 `cotizacion_contradictoria`**, y es correcto que responda: son dos verdades
    // sobre lo mismo.
    'unitPriceMinor': modo.esPorPersona ? precioUnitarioMenores : null,
    'monthlyTotalMinor': modo.esPorPersona ? null : totalMensualMenores,
    'currency': moneda,
    'taxTreatment': iva.codigo,
    'description': descripcion,
    'observations': observaciones,
    'schedules': [for (final h in horarios) h.aJson()],
  };
}

/// Un bloque horario tal como se manda.
class HorarioEnviado {
  const HorarioEnviado({
    required this.dia,
    required this.inicioMinuto,
    required this.finMinuto,
  });

  /// ISO: 1 = lunes … 7 = domingo.
  final int dia;

  /// `0..1439`.
  final int inicioMinuto;

  /// `1..1440`. **1440 es la medianoche como FINAL del día.** No existen minutos mayores, y
  /// `inicio == fin` significa 24 horas — con lo que un bloque de duración cero es
  /// inexpresable.
  final int finMinuto;

  Map<String, dynamic> aJson() => {
    'dayOfWeek': dia,
    'startMinute': inicioMinuto,
    'endMinute': finMinuto,
  };
}
