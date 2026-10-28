import 'dart:typed_data';

import '../../../../core/api/api_client_autenticado.dart';
import '../../../../core/api/api_error_parser.dart';
import '../../../../core/api/api_respuesta.dart';
import '../../../../core/company/company_ruta.dart';
import '../../../../core/direcciones/direccion.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/error/result.dart';
import '../../../../core/fechas/dia_de_negocio.dart';
import '../../../../core/fiscal/regimen_fiscal.dart';
import '../modelos/cliente.dart';
import '../modelos/contacto.dart';
import '../modelos/entidad_fiscal.dart';

/// Los clientes de una empresa, contra la API.
///
/// **Devuelve `Result`, nunca lanza**, y la traducción de un fallo HTTP la hace
/// [ApiErrorParser] — no una interpretación propia de este archivo.
///
/// ## ⚠️ LOS FILTROS VAN AL SERVIDOR, y no es una preferencia de estilo
///
/// El escritorio filtra en memoria porque tiene la cartera entera en SQLite. Aquí
/// **Clientes no tiene paginación** —es una deuda conocida del backend— así que filtrar
/// en la pantalla obligaría a traerse la cartera completa para enseñar tres filas, y
/// además habría que traerla otra vez en cuanto alguien escribiera una letra. El día que
/// haya paginación, el filtro ya está donde tiene que estar.
///
/// El buscador del servidor mira **folio, nombre comercial y observaciones**, los mismos
/// tres del escritorio.
class ClientesRepositorioHttp {
  const ClientesRepositorioHttp(this._api);

  final ApiClientAutenticado _api;

  /// La cartera, filtrada **por el servidor**.
  ///
  /// Los tres filtros son independientes y **nulo significa «no filtres por esto»**, no
  /// «filtra por el valor vacío». Es la diferencia entre «todos los estatus» y «los que
  /// no tienen estatus», que no existen.
  ///
  /// `conServicios` es el filtro de tres estados del escritorio: nulo es «Todos», `true`
  /// es **al menos un servicio activo** y `false` es ninguno.
  Future<Result<List<ClienteEnLista>>> listar(
    String empresaId, {
    EstatusDeCliente? estatus,
    String? texto,
    bool? conServicios,
  }) async {
    final respuesta = await _api.get(
      CompanyRuta.de(empresaId, '/clients'),
      query: {
        if (estatus != null) 'status': estatus.codigo,
        // EL TEXTO SE RECORTA Y SE OMITE SI QUEDA VACÍO: mandar `query=` haría que el
        // servidor buscara la cadena vacía, que casa con todo y además le cuesta tres
        // `ILIKE` por fila.
        if (texto != null && texto.trim().isNotEmpty) 'query': texto.trim(),
        if (conServicios != null) 'withServices': conServicios.toString(),
      },
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
                  'El servidor no devolvió una lista de clientes.',
                ),
              );
            }

            return Result.ok([
              for (final fila in json)
                ClienteEnLista.deJson(fila as Map<String, dynamic>),
            ]);
          },
        );
      },
    );
  }

  /// Un cliente por su id.
  Future<Result<Cliente>> ver({
    required String empresaId,
    required String clienteId,
  }) async {
    final respuesta = await _api.get(
      CompanyRuta.de(empresaId, '/clients/$clienteId'),
    );

    return _uno(respuesta);
  }

  /// Da de alta un cliente.
  ///
  /// **No recibe el folio** —lo asigna el servidor con el contador de la Company— y
  /// **no recibe el estatus**: nace `active`. Tampoco pide motivo, y eso es del
  /// contrato: el motivo es para corregir, no para crear.
  ///
  /// [inicio] es obligatorio porque **el servidor lo exige**: «desde cuándo es cliente»
  /// es un dato del negocio, y el backend se niega a rellenarlo con la fecha de captura
  /// —«convertiría una laguna en un hecho falso que después nadie distingue del real»—.
  /// La pantalla lo propone con el día de negocio de hoy y se puede cambiar.
  Future<Result<Cliente>> crear({
    required String empresaId,
    required String nombreComercial,
    required DiaDeNegocio inicio,
    String? observaciones,
  }) async {
    final respuesta = await _api.post(
      CompanyRuta.de(empresaId, '/clients'),
      json: {
        'commercialName': nombreComercial,
        'startedOn': inicio.enTexto,
        'notes': observaciones,
      },
    );

    return _uno(respuesta);
  }

  /// Corrige el cliente **o cambia su estatus**, con motivo.
  ///
  /// ## El motivo no es un campo más del formulario
  ///
  /// Es **R1 de los actos que piden motivo** y el servidor lo valida **antes que los
  /// campos**: no es un dato del cliente, es la condición para corregirlo. Por eso va
  /// como parámetro obligatorio y no como un `String?` más — un motivo opcional sería un
  /// 400 esperando a que alguien lo olvide.
  ///
  /// ## Sólo viaja lo que cambió
  ///
  /// ⚠️ **Y NO ES UNA OPTIMIZACIÓN: el servidor rechaza una petición que no cambia
  /// nada** —«No hay nada que modificar»—, así que mandar el cuerpo completo haría que
  /// pulsar «Guardar» sin tocar nada respondiera un 400 en vez de no hacer nada. Es la
  /// misma regla que ya aprendió el `PATCH` de un área por el otro lado: mandar un campo
  /// que no se tocó le costaba un 403 a quien no tenía su permiso.
  Future<Result<Cliente>> modificar({
    required String empresaId,
    required String clienteId,
    required String motivo,
    String? nombreComercial,
    DiaDeNegocio? inicio,
    String? observaciones,
    bool observacionesSeVacian = false,
    EstatusDeCliente? estatus,
  }) async {
    final respuesta = await _api.patch(
      CompanyRuta.de(empresaId, '/clients/$clienteId'),
      json: {
        'reason': motivo,
        if (nombreComercial != null) 'commercialName': nombreComercial,
        if (inicio != null) 'startedOn': inicio.enTexto,
        // ⚠️ VACIAR LAS OBSERVACIONES Y NO TOCARLAS SON LO MISMO EN JSON —las dos son
        // `notes` ausente o nulo— así que hace falta decir cuál es. Con un solo
        // `String?` no se puede: nulo significaría «no las toques» y entonces no habría
        // forma de borrarlas, o significaría «bórralas» y guardar el nombre las
        // borraría de paso.
        if (observacionesSeVacian) 'notes': null,
        if (!observacionesSeVacian && observaciones != null) 'notes': observaciones,
        if (estatus != null) 'status': estatus.codigo,
      },
    );

    return _uno(respuesta);
  }

  /// El domicilio de referencia, **o nulo si el cliente no tiene ninguno**.
  ///
  /// Nulo **no es un fallo**: «sin domicilio de referencia» es un estado legítimo y el
  /// servidor lo dice con un 404 que esta función traduce. Confundirlos haría que un
  /// cliente sin domicilio apareciera como un error de red.
  Future<Result<Direccion?>> verDomicilio({
    required String empresaId,
    required String clienteId,
  }) async {
    final respuesta = await _api.get(
      CompanyRuta.de(empresaId, '/clients/$clienteId/address'),
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

  /// Crea o reemplaza el domicilio de referencia. **Sin motivo**: el servidor no lo pide
  /// aquí, y publicar un campo que se ignora es peor que no tenerlo.
  ///
  /// ⚠️ **NO HAY FORMA DE QUITARLO, Y ES LA DECISIÓN D-59.** El servidor no tiene
  /// `DELETE` de domicilio y su `PUT` exige los seis obligatorios, así que un domicilio
  /// vacío responde «Falta la calle.». En el escritorio vaciarlo lo archivaba; aquí, una
  /// vez capturado, **se corrige y no se borra** —no hay caso de negocio para dejar a un
  /// cliente sin domicilio—. La pantalla lo dice en su letra chica en lugar de dejar que
  /// se descubra con un error.
  Future<Result<Direccion>> guardarDomicilio({
    required String empresaId,
    required String clienteId,
    required Direccion direccion,
  }) async {
    final respuesta = await _api.put(
      CompanyRuta.de(empresaId, '/clients/$clienteId/address'),
      json: direccion.aJson(),
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
                    'El servidor no devolvió el domicilio que guardó.',
                  ),
                ),
        );
      },
    );
  }

  /// Los indicadores de la ficha. **Ruta propia y no dentro del cliente**: la ficha los
  /// pide al abrirse, y quien sólo quiere los datos del cliente no paga dos consultas
  /// más.
  Future<Result<IndicadoresDeCliente>> verIndicadores({
    required String empresaId,
    required String clienteId,
  }) async {
    final respuesta = await _api.get(
      CompanyRuta.de(empresaId, '/clients/$clienteId/indicators'),
    );

    return respuesta.when(
      failure: Result.failure,
      ok: (r) {
        if (!r.esExitosa) return Result.failure(ApiErrorParser.interpretar(r));

        return r.decodificar().when(
          failure: Result.failure,
          ok: (json) => json is Map<String, dynamic>
              ? Result.ok(IndicadoresDeCliente.deJson(json))
              : const Result.failure(
                  ApiJsonInvalidoFailure(
                    'El servidor no devolvió los indicadores del cliente.',
                  ),
                ),
        );
      },
    );
  }

  /// Las razones sociales del cliente, **incluidas las archivadas**.
  ///
  /// El servidor no filtra y es lo correcto: una archivada no se borra —con ella se
  /// emitieron facturas— y esconderla haría pensar que desapareció. Quien decide qué
  /// hacer con cada una es la pantalla.
  Future<Result<List<EntidadFiscal>>> listarEntidadesFiscales({
    required String empresaId,
    required String clienteId,
  }) async {
    final respuesta = await _api.get(
      CompanyRuta.de(empresaId, '/clients/$clienteId/fiscal-entities'),
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
                  'El servidor no devolvió las entidades fiscales.',
                ),
              );
            }

            return Result.ok([
              for (final fila in json)
                EntidadFiscal.deJson(fila as Map<String, dynamic>),
            ]);
          },
        );
      },
    );
  }

  /// Los bytes del logotipo vigente, **o nulo si el cliente no tiene**.
  ///
  /// ⚠️ **ES `…/logo/content` Y NO `…/logo`**, al contrario que el de la empresa: aquí
  /// `GET /logo` devuelve la **metadata** del archivo —id, tamaño, `sha256`— y los bytes
  /// están en su propia ruta. Pedir la equivocada devuelve un JSON que no se puede
  /// pintar, y nada falla hasta que la imagen sale vacía.
  ///
  /// Nulo no es un fallo: «sin logotipo» es un estado legítimo y la pantalla pinta las
  /// iniciales, que es lo mismo que pintaría mientras carga.
  Future<Result<Uint8List?>> leerLogotipo({
    required String empresaId,
    required String clienteId,
  }) async {
    final respuesta = await _api.getBytes(
      CompanyRuta.de(empresaId, '/clients/$clienteId/logo/content'),
    );

    return respuesta.when(
      failure: Result.failure,
      ok: (r) {
        if (r.statusCode == 404) return const Result.ok(null);

        if (r.esExitosa) {
          return r.bytes == null
              ? const Result.failure(
                  ApiJsonInvalidoFailure(
                    'El servidor devolvió el logotipo sin contenido.',
                  ),
                )
              : Result.ok(r.bytes);
        }

        return Result.failure(ApiErrorParser.interpretar(r));
      },
    );
  }

  /// Quita el logotipo vigente.
  ///
  /// **El 404 de la segunda vez se trata como éxito**: para quien pulsó «Quitar», que ya
  /// no hubiera nada que quitar no es un problema que pueda resolver.
  ///
  /// **Y lo que libera es CAPACIDAD, no espacio físico.** El archivo sigue guardado hasta
  /// la purga; la capacidad contractual queda libre en el acto.
  Future<Result<void>> quitarLogotipo({
    required String empresaId,
    required String clienteId,
  }) async {
    final respuesta = await _api.delete(
      CompanyRuta.de(empresaId, '/clients/$clienteId/logo'),
    );

    return respuesta.when(
      failure: Result.failure,
      ok: (r) => r.esExitosa || r.statusCode == 404
          ? const Result.ok(null)
          : Result.failure(ApiErrorParser.interpretar(r)),
    );
  }

  /// Sube o reemplaza el logotipo de un cliente.
  ///
  /// ⚠️ **ES `PUT` Y NO `POST`**, al contrario que el de la empresa: el logotipo es un
  /// recurso **singular**, así que subir y reemplazar son el mismo acto, y la ruta del
  /// servidor sólo admite ese verbo. Un `POST` responde 405 — un fallo que no se parece
  /// a su causa.
  ///
  /// **Devuelve los mismos bytes que se subieron**, por lo mismo que el de la empresa:
  /// la respuesta trae la metadata del archivo —id, tamaño, `sha256`— y no su contenido,
  /// así que pintar el logotipo nuevo exigiría una descarga más.
  Future<Result<Uint8List>> subirLogotipo({
    required String empresaId,
    required String clienteId,
    required String nombreDeArchivo,
    required Uint8List bytes,
  }) async {
    final respuesta = await _api.putMultipart(
      CompanyRuta.de(empresaId, '/clients/$clienteId/logo'),
      campo: 'file',
      nombreDeArchivo: nombreDeArchivo,
      bytes: bytes,
    );

    return respuesta.when(
      failure: Result.failure,
      ok: (r) => r.esExitosa
          ? Result.ok(bytes)
          : Result.failure(ApiErrorParser.interpretar(r)),
    );
  }

  // =========================================================================
  // Contactos
  // =========================================================================

  /// Los contactos del cliente, **el principal primero**. El orden lo pone el servidor.
  Future<Result<List<ContactoDeCliente>>> listarContactos({
    required String empresaId,
    required String clienteId,
  }) => _lista(
    CompanyRuta.de(empresaId, '/clients/$clienteId/contacts'),
    ContactoDeCliente.deJson,
    'los contactos del cliente',
  );

  /// Añade un contacto. **Nace como NO principal**, y sin motivo: el motivo es para
  /// corregir, no para crear.
  ///
  /// El servidor exige nombre, tipo y **al menos un teléfono o un correo** —un contacto
  /// sin ninguna vía no sirve de nada—.
  Future<Result<ContactoDeCliente>> crearContacto({
    required String empresaId,
    required String clienteId,
    required String nombre,
    required TipoDeContacto tipo,
    String? puesto,
    String? telefono,
    String? correo,
    String? observaciones,
  }) async {
    final respuesta = await _api.post(
      CompanyRuta.de(empresaId, '/clients/$clienteId/contacts'),
      json: {
        'name': nombre,
        'kind': tipo.codigo,
        'role': puesto,
        'phone': telefono,
        'email': correo,
        'notes': observaciones,
      },
    );

    return _unoDe(respuesta, ContactoDeCliente.deJson, 'un contacto');
  }

  /// Corrige un contacto, **con motivo**.
  ///
  /// ⚠️ **`isPrimary` NO VIAJA AQUÍ**, y no es que se ignore: no existe en el contrato.
  /// Designar al principal **tiene su propia ruta** para que la designación quede en la
  /// traza como el acto que es y no como el efecto colateral de una edición.
  ///
  /// **Lo que no se manda no se toca**, así que cada campo viaja sólo si cambió. Vaciar un
  /// opcional —quitar el puesto— pide mandarlo como cadena vacía, que el servidor recorta
  /// a nulo; con `null` no lo tocaría.
  Future<Result<ContactoDeCliente>> modificarContacto({
    required String empresaId,
    required String clienteId,
    required String contactoId,
    required String motivo,
    String? nombre,
    TipoDeContacto? tipo,
    String? puesto,
    String? telefono,
    String? correo,
    String? observaciones,
  }) async {
    final respuesta = await _api.patch(
      CompanyRuta.de(empresaId, '/clients/$clienteId/contacts/$contactoId'),
      json: {
        'reason': motivo,
        if (nombre != null) 'name': nombre,
        if (tipo != null) 'kind': tipo.codigo,
        if (puesto != null) 'role': puesto,
        if (telefono != null) 'phone': telefono,
        if (correo != null) 'email': correo,
        if (observaciones != null) 'notes': observaciones,
      },
    );

    return _unoDe(respuesta, ContactoDeCliente.deJson, 'un contacto');
  }

  /// Designa al contacto principal **de su tipo**, y desmarca al anterior.
  ///
  /// **Sin cuerpo y sin motivo**: el destino lo dice la ruta, y el servidor pone el motivo
  /// solo. Es un acto con nombre, no una edición.
  Future<Result<ContactoDeCliente>> designarPrincipal({
    required String empresaId,
    required String clienteId,
    required String contactoId,
  }) async {
    final respuesta = await _api.post(
      CompanyRuta.de(
        empresaId,
        '/clients/$clienteId/contacts/$contactoId/primary',
      ),
    );

    return _unoDe(respuesta, ContactoDeCliente.deJson, 'un contacto');
  }

  /// Le **quita** la marca de principal, y deja ese tipo sin principal. **R14.**
  ///
  /// ⚠️ **CON MOTIVO, al contrario que designar**, y la asimetría es del contrato: la
  /// primera asignación no pide motivo, **quitarla sí** —es una corrección de algo que
  /// alguien decidió—. Es la misma regla que la entidad fiscal de un servicio.
  ///
  /// El motivo va en la cadena de consulta porque un cuerpo en un `DELETE` lo descartan
  /// algunos intermediarios, igual que al eliminar un contacto.
  Future<Result<ContactoDeCliente>> quitarPrincipal({
    required String empresaId,
    required String clienteId,
    required String contactoId,
    required String motivo,
  }) async {
    final respuesta = await _api.delete(
      CompanyRuta.de(
        empresaId,
        '/clients/$clienteId/contacts/$contactoId/primary',
      ),
      query: {'reason': motivo},
    );

    return _unoDe(respuesta, ContactoDeCliente.deJson, 'un contacto');
  }

  /// Elimina un contacto, **con motivo**.
  ///
  /// ## Dos cosas que no son obvias
  ///
  /// ⚠️ **EL MOTIVO VIAJA EN LA CADENA DE CONSULTA** —`?reason=`— y no en un cuerpo: un
  /// cuerpo en un `DELETE` lo descartan algunos intermediarios. Un motivo no es un
  /// secreto, así que la cadena de consulta no estorba.
  ///
  /// ⚠️ **SE BORRA DE VERDAD, Y NO SE ARCHIVA.** El escritorio lo archiva; aquí la fila se
  /// va, así que **el evento de la bitácora es lo único que queda** —con el nombre, el
  /// tipo, si era principal y las vías **enmascaradas**— y el motivo es lo único que dice
  /// por qué dejó de existir.
  ///
  /// Si es **responsable de un servicio**, el servidor responde 409 `recurso_en_uso`
  /// **nombrando el servicio**: «Este contacto es responsable del servicio SRV-0001 Torre
  /// Norte. Cambia el responsable antes de eliminarlo.»
  Future<Result<void>> eliminarContacto({
    required String empresaId,
    required String clienteId,
    required String contactoId,
    required String motivo,
  }) async {
    final respuesta = await _api.delete(
      CompanyRuta.de(empresaId, '/clients/$clienteId/contacts/$contactoId'),
      query: {'reason': motivo},
    );

    return respuesta.when(
      failure: Result.failure,
      ok: (r) => r.esExitosa
          ? const Result.ok(null)
          : Result.failure(ApiErrorParser.interpretar(r)),
    );
  }

  // =========================================================================
  // Entidades fiscales
  // =========================================================================

  /// Añade una razón social. **Sin motivo**, y devuelve el **aviso de RFC repetido** si lo
  /// hay: ver [EntidadFiscalGuardada].
  Future<Result<EntidadFiscalGuardada>> crearEntidadFiscal({
    required String empresaId,
    required String clienteId,
    required String razonSocial,
    String? rfc,
    String? regimenFiscal,
    String? observaciones,
  }) async {
    final respuesta = await _api.post(
      CompanyRuta.de(empresaId, '/clients/$clienteId/fiscal-entities'),
      json: {
        'legalName': razonSocial,
        'taxId': rfc,
        'fiscalRegimeCode': regimenFiscal,
        'notes': observaciones,
      },
    );

    return _unoDe(
      respuesta,
      EntidadFiscalGuardada.deJson,
      'una entidad fiscal',
    );
  }

  /// Corrige **o archiva** una razón social, con motivo.
  ///
  /// `estatus` es `active` o `archived`: una entidad fiscal **no se borra** —con ella se
  /// emitieron facturas— y retirarla de circulación es archivarla. El servidor rechaza con
  /// 409 `entidad_fiscal_archivada` cualquier corrección de una archivada, así que
  /// reactivarla es lo primero.
  Future<Result<EntidadFiscalGuardada>> modificarEntidadFiscal({
    required String empresaId,
    required String clienteId,
    required String entidadId,
    required String motivo,
    String? razonSocial,
    String? rfc,
    String? regimenFiscal,
    String? observaciones,
    String? estatus,
  }) async {
    final respuesta = await _api.patch(
      CompanyRuta.de(
        empresaId,
        '/clients/$clienteId/fiscal-entities/$entidadId',
      ),
      json: {
        'reason': motivo,
        if (razonSocial != null) 'legalName': razonSocial,
        if (rfc != null) 'taxId': rfc,
        if (regimenFiscal != null) 'fiscalRegimeCode': regimenFiscal,
        if (observaciones != null) 'notes': observaciones,
        if (estatus != null) 'status': estatus,
      },
    );

    return _unoDe(
      respuesta,
      EntidadFiscalGuardada.deJson,
      'una entidad fiscal',
    );
  }

  /// El domicilio fiscal de una razón social, **o nulo si no tiene**.
  ///
  /// Mismos diez campos y mismas reglas que el de referencia; **lo que no se comparte es
  /// la tabla**, que es donde estaba el problema del producto local.
  Future<Result<Direccion?>> verDomicilioFiscal({
    required String empresaId,
    required String clienteId,
    required String entidadId,
  }) async {
    final respuesta = await _api.get(
      CompanyRuta.de(
        empresaId,
        '/clients/$clienteId/fiscal-entities/$entidadId/address',
      ),
    );

    return _direccionOpcional(respuesta);
  }

  /// Crea o reemplaza el domicilio fiscal. **Sin motivo**: el servidor no lo pide aquí.
  ///
  /// Y por lo mismo que el de referencia (D-59): **no hay forma de quitarlo**. El servidor
  /// no tiene `DELETE` y su `PUT` exige los seis obligatorios.
  Future<Result<Direccion>> guardarDomicilioFiscal({
    required String empresaId,
    required String clienteId,
    required String entidadId,
    required Direccion direccion,
  }) async {
    final respuesta = await _api.put(
      CompanyRuta.de(
        empresaId,
        '/clients/$clienteId/fiscal-entities/$entidadId/address',
      ),
      json: direccion.aJson(),
    );

    return _direccion(respuesta);
  }

  // =========================================================================
  // El catálogo del SAT
  // =========================================================================

  /// Los regímenes fiscales, **filtrados por el RFC si se manda**.
  ///
  /// ## Por qué esta lectura vive también aquí
  ///
  /// La misma ruta la lee `ExpedientesRepositorioHttp` para el expediente fiscal de la
  /// empresa. **No es una segunda fuente de verdad** —la fuente es la ruta, y el modelo es
  /// uno solo en `core/fiscal/`— sino dos consumidores: cada repositorio traduce sus
  /// fallos a su pantalla, y hacer que Comercial pidiera el catálogo a través del
  /// repositorio de Organización la haría depender de otra feature para leer un catálogo
  /// del SAT.
  ///
  /// ⚠️ **SU PERMISO CAMBIÓ EN C1 Y HACÍA FALTA:** exigía `company.settings.read`, así que
  /// quien administra clientes sin el permiso del expediente recibía **403** y se quedaba
  /// sin selector, viendo un formulario que no podía llenar. Ahora **basta uno de los dos**
  /// —`company.settings.read` o `clients_services.read`—, porque el catálogo del SAT es un
  /// dato público de plataforma y no un dato de la empresa.
  ///
  /// **EL FILTRO AVISA, NO BLOQUEA.** Doce caracteres es persona moral y trece persona
  /// física; cualquier otra longitud —incluido un RFC a medio escribir— devuelve el
  /// catálogo completo. Un filtro que vaciara la lista escondería un régimen legítimo y la
  /// persona no sabría por qué no aparece.
  Future<Result<List<RegimenFiscal>>> listarRegimenes({
    required String empresaId,
    String? rfc,
  }) async {
    final limpio = (rfc ?? '').trim();

    // EL RFC VA EN `query`, NO PEGADO A LA RUTA, y esto ya costó una prueba descubrirlo en
    // el otro repositorio: `ApiConfig.resolver` mete la cadena entera en el PATH, así que
    // un `'/fiscal-regimes?rfc=…'` se codifica y el `?` acaba siendo parte del camino. La
    // petición saldría bien, el servidor devolvería el catálogo completo, y **el filtro no
    // se aplicaría nunca sin que nada fallara**.
    final respuesta = await _api.get(
      CompanyRuta.de(empresaId, '/fiscal-regimes'),
      query: limpio.isEmpty ? null : {'rfc': limpio},
    );

    return _leerLista(
      respuesta,
      RegimenFiscal.deJson,
      'una lista de regímenes fiscales',
    );
  }

  // =========================================================================
  // Lo compartido
  // =========================================================================

  /// Un `GET` de lista. Cinco `switch` copiados serían cinco sitios donde uno puede dejar
  /// de traducir el fallo.
  Future<Result<List<T>>> _lista<T>(
    String ruta,
    T Function(Map<String, dynamic>) leer,
    String queSeEsperaba,
  ) async => _leerLista(await _api.get(ruta), leer, queSeEsperaba);

  Result<List<T>> _leerLista<T>(
    Result<ApiRespuesta> respuesta,
    T Function(Map<String, dynamic>) leer,
    String queSeEsperaba,
  ) => respuesta.when(
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

  /// Un domicilio que **puede no existir**: el 404 del servidor es «no tiene», no un
  /// fallo. Confundirlos haría que una entidad sin domicilio fiscal apareciera como un
  /// error de red.
  Result<Direccion?> _direccionOpcional(Result<ApiRespuesta> respuesta) =>
      respuesta.when(
        failure: Result.failure,
        ok: (r) {
          if (r.statusCode == 404) return const Result.ok(null);

          return _direccion(Result.ok(r));
        },
      );

  Result<Direccion> _direccion(Result<ApiRespuesta> respuesta) =>
      _unoDe(respuesta, Direccion.deJson, 'un domicilio');

  /// UNA sola forma de leer **un objeto** de una respuesta.
  Result<T> _unoDe<T>(
    Result<ApiRespuesta> respuesta,
    T Function(Map<String, dynamic>) leer,
    String queSeEsperaba,
  ) => respuesta.when(
    failure: Result.failure,
    ok: (r) {
      if (!r.esExitosa) return Result.failure(ApiErrorParser.interpretar(r));

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

  /// UNA sola forma de leer un cliente. Tres `switch` copiados serían tres sitios donde
  /// uno puede dejar de traducir el fallo.
  Result<Cliente> _uno(Result<ApiRespuesta> respuesta) => respuesta.when(
    failure: Result.failure,
    ok: (r) {
      if (!r.esExitosa) return Result.failure(ApiErrorParser.interpretar(r));

      return r.decodificar().when(
        failure: Result.failure,
        ok: (json) {
          if (json is! Map<String, dynamic>) {
            return const Result.failure(
              ApiJsonInvalidoFailure('El servidor no devolvió un cliente.'),
            );
          }

          return Result.ok(Cliente.deJson(json));
        },
      );
    },
  );
}
