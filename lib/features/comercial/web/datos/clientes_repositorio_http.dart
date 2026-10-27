import 'dart:typed_data';

import '../../../../core/api/api_client_autenticado.dart';
import '../../../../core/api/api_error_parser.dart';
import '../../../../core/api/api_respuesta.dart';
import '../../../../core/company/company_ruta.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/error/result.dart';
import '../../../../core/fechas/dia_de_negocio.dart';
import '../modelos/cliente.dart';

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
