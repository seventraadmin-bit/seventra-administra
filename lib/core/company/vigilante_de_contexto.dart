import 'dart:typed_data';

import '../api/api_client_autenticado.dart';
import '../api/api_respuesta.dart';
import '../error/result.dart';

/// Un decorador del cliente autenticado que detecta **que el contexto de la empresa
/// que tiene el navegador se quedó viejo**, y avisa.
///
/// ## El problema que resuelve, dicho con precisión
///
/// Los permisos efectivos y los módulos habilitados viajan en el contexto que el
/// cliente pidió **al entrar** —`GET /companies/{id}/context`—, y de ahí sale qué
/// apartados, pestañas y botones se pintan.
///
/// **El servidor NO tiene ese problema**: autoriza contra la base en cada petición y
/// su consulta exige `company_access.status`, `company.status` y
/// `organization.status` en `activa`. Medido el 22 de octubre de 2026: no hay caché.
/// Así que retirar un permiso, revocar un acceso o desactivar una empresa surten
/// efecto **en la petición siguiente**.
///
/// Lo que se queda viejo es **la copia del navegador**, y eso no es un agujero: es una
/// interfaz que miente. Ofrece un botón que el servidor va a rechazar, y quien lo pulsa
/// recibe un «no tienes permiso» que su Maestro ya había quitado hace rato.
///
/// ## Por qué vive aquí y no en `core/api/`
///
/// Porque **qué significa un 403 es autorización, no transporte**.
/// `ApiClientAutenticado` lo dice de sí mismo y con razón: «no interpreta el 402, ni
/// el 403 … Eso es autorización, no autenticación … Decidirlas aquí las escondería en
/// el transporte». Esta pieza es de la capa de Company, que es la dueña del contexto,
/// y el cliente desnudo sigue sin saber qué es un permiso.
///
/// ## 🚫 Lo que NO hace
///
/// **No autoriza y no decide nada.** Observa, y llama a [alDetectar]. Quien reacciona
/// es `GestorDeCompany`, que es el único que puede volver a pedir el contexto.
///
/// **No reacciona a un 404.** Es una decisión escrita en `revalidar()` y se respeta:
/// «un 404 de negocio puede significar simplemente que ese empleado no existe, y
/// engancharlo aquí cerraría empresas por errores ajenos». El 404 de `/context` sí es
/// autoritativo, pero ése lo ve el gestor por su cuenta.
///
/// **No reacciona al 402.** Una suscripción restringida no cambia los permisos: los
/// conserva y rechaza las mutaciones. Volver a pedir el contexto no traería nada nuevo.
class VigilanteDeContexto implements ApiClientAutenticado {
  const VigilanteDeContexto({
    required ApiClientAutenticado cliente,
    required void Function() alDetectar,
  }) : _cliente = cliente,
       _alDetectar = alDetectar;

  final ApiClientAutenticado _cliente;
  final void Function() _alDetectar;

  /// Los dos códigos que significan «tu copia del contexto ya no vale».
  ///
  /// Los dos son **403** y los dos salen de datos que viajan en el contexto: la lista
  /// de permisos efectivos y la de módulos habilitados. Si el servidor rechaza por uno
  /// de ellos, la copia del navegador discrepa de la base.
  ///
  /// ⚠️ **Los otros 403 NO entran, y la diferencia importa.**
  /// `autoridad_insuficiente` es del plano de Organization —no viaja en este
  /// contexto—, y `self_grant_prohibido` o `permiso_protegido_no_poseido` son reglas
  /// de la operación, no estados que hayan cambiado: volver a pedir el contexto
  /// devolvería exactamente lo mismo y la petición sería puro ruido.
  static const Set<String> codigosDeContextoViejo = {
    'permission_missing',
    'module_disabled',
  };

  /// ¿Esta respuesta dice que el contexto se quedó viejo?
  ///
  /// Pública para que una prueba pueda afirmarlo sin montar un cliente: es la regla,
  /// y conviene que se pueda leer y comprobar sola.
  static bool diceQueElContextoEsViejo(ApiRespuesta respuesta) {
    if (respuesta.statusCode != 403) return false;

    // EL CÓDIGO SE BUSCA EN EL CUERPO SIN DESERIALIZAR NADA, y es a propósito: este
    // decorador envuelve TODAS las peticiones, incluidas las de bytes, y un cuerpo
    // binario no es JSON. Un `contains` sobre un cuerpo de error —que siempre es un
    // objeto pequeño— no se equivoca en la dirección peligrosa: lo más que puede pasar
    // es pedir el contexto una vez de más.
    return codigosDeContextoViejo.any(respuesta.cuerpo.contains);
  }

  Future<Result<ApiRespuesta>> _vigilar(
    Future<Result<ApiRespuesta>> peticion,
  ) async {
    final resultado = await peticion;

    resultado.when(
      ok: (respuesta) {
        if (diceQueElContextoEsViejo(respuesta)) _alDetectar();
      },
      // UN FALLO DE TRANSPORTE NO DICE NADA DEL CONTEXTO. Sin respuesta no hay código
      // que leer, y pedir el contexto porque la red falló sólo añadiría una petición
      // que también va a fallar.
      failure: (_) {},
    );

    return resultado;
  }

  @override
  Future<Result<ApiRespuesta>> get(
    String ruta, {
    Map<String, String>? query,
    Map<String, String>? headers,
    Duration? timeout,
  }) => _vigilar(
    _cliente.get(ruta, query: query, headers: headers, timeout: timeout),
  );

  @override
  Future<Result<ApiRespuesta>> post(
    String ruta, {
    Object? json,
    Map<String, String>? query,
    Map<String, String>? headers,
    Duration? timeout,
  }) => _vigilar(
    _cliente.post(
      ruta,
      json: json,
      query: query,
      headers: headers,
      timeout: timeout,
    ),
  );

  @override
  Future<Result<ApiRespuesta>> put(
    String ruta, {
    Object? json,
    Map<String, String>? query,
    Map<String, String>? headers,
    Duration? timeout,
  }) => _vigilar(
    _cliente.put(
      ruta,
      json: json,
      query: query,
      headers: headers,
      timeout: timeout,
    ),
  );

  @override
  Future<Result<ApiRespuesta>> patch(
    String ruta, {
    Object? json,
    Map<String, String>? query,
    Map<String, String>? headers,
    Duration? timeout,
  }) => _vigilar(
    _cliente.patch(
      ruta,
      json: json,
      query: query,
      headers: headers,
      timeout: timeout,
    ),
  );

  @override
  Future<Result<ApiRespuesta>> delete(
    String ruta, {
    Object? json,
    Map<String, String>? query,
    Map<String, String>? headers,
    Duration? timeout,
  }) => _vigilar(
    _cliente.delete(
      ruta,
      json: json,
      query: query,
      headers: headers,
      timeout: timeout,
    ),
  );

  @override
  Future<Result<ApiRespuesta>> getBytes(
    String ruta, {
    Map<String, String>? query,
    Map<String, String>? headers,
    Duration? timeout,
  }) => _vigilar(
    _cliente.getBytes(ruta, query: query, headers: headers, timeout: timeout),
  );

  @override
  Future<Result<ApiRespuesta>> postMultipart(
    String ruta, {
    required String campo,
    required String nombreDeArchivo,
    required Uint8List bytes,
    Map<String, String>? headers,
    Duration? timeout,
  }) => _vigilar(
    _cliente.postMultipart(
      ruta,
      campo: campo,
      nombreDeArchivo: nombreDeArchivo,
      bytes: bytes,
      headers: headers,
      timeout: timeout,
    ),
  );

  /// El logotipo de un cliente, que va por `PUT` porque es un recurso singular.
  ///
  /// ⚠️ **TENÍA QUE ESTAR, Y EL COMPILADOR LO EXIGIÓ.** Este vigilante implementa el
  /// contrato entero de [ApiClientAutenticado], así que un verbo nuevo allí sin su
  /// envoltorio aquí **no compila** — y eso es exactamente lo que se quiere: una subida
  /// que se saltara el vigilante no pediría el contexto al recibir un 403, y la pantalla
  /// seguiría ofreciendo un botón que ya no autoriza nadie.
  @override
  Future<Result<ApiRespuesta>> putMultipart(
    String ruta, {
    required String campo,
    required String nombreDeArchivo,
    required Uint8List bytes,
    Map<String, String>? headers,
    Duration? timeout,
  }) => _vigilar(
    _cliente.putMultipart(
      ruta,
      campo: campo,
      nombreDeArchivo: nombreDeArchivo,
      bytes: bytes,
      headers: headers,
      timeout: timeout,
    ),
  );
}
