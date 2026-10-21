import 'dart:typed_data';

import '../../../../core/api/api_client_autenticado.dart';
import '../../../../core/api/api_error_parser.dart';
import '../../../../core/company/company_ruta.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/error/result.dart';

/// El logotipo de la empresa contra la API: leerlo, subirlo y quitarlo.
///
/// ## Las tres cosas que este repositorio NO decide
///
/// **1 · Si el archivo es una imagen.** Lo decide el servidor leyendo los **bytes
/// mágicos** —`FileValidation.DetectContentType`— y comparando el tipo REAL contra los
/// que el uso admite. La pantalla comprueba la firma también, pero como **aviso
/// temprano**: «un archivo puede llamarse `.png` sin serlo», y quien manda es quien
/// autoriza.
///
/// **2 · Si cabe.** La capacidad de almacenamiento es **de la Organization**, no de la
/// Company, y la mide el servidor. Un 409 `storage_capacity_exceeded` llega **con las
/// dos cifras** para que la pantalla pueda decir cuánto hay y cuánto se usa.
///
/// **3 · Qué pasa con el anterior.** El `POST` es una llamada y tres pasos internos, y
/// su garantía es del servidor: «el logotipo anterior sigue vigente hasta que el nuevo
/// está validado, así que un fallo nunca deja a la Company sin logotipo». **La pantalla
/// no tiene que quitar antes de subir**, y hacerlo abriría justo el hueco que esa
/// garantía cierra.
class LogotipoRepositorioHttp {
  const LogotipoRepositorioHttp(this._api);

  final ApiClientAutenticado _api;

  /// El `code` del 404 cuando la empresa no tiene logotipo.
  ///
  /// **NO ES UN ERROR Y LA PANTALLA NO LO TRATA COMO TAL:** «sin logotipo» es un estado
  /// legítimo —la presentación es tipográfica— y decirlo como fallo haría pensar que el
  /// logotipo se perdió.
  static const String codigoSinLogotipo = 'logo_missing';

  /// El `code` del 409 de capacidad, que llega **con cifras**.
  static const String codigoSinCapacidad = 'storage_capacity_exceeded';

  /// Lee el logotipo vigente.
  ///
  /// Devuelve **nulo** cuando no hay ninguno, que es distinto de un fallo: la pantalla
  /// pinta las iniciales en vez de un aviso. Cualquier otro problema sí es un fallo, y
  /// entonces la pantalla ofrece reintentar — confundir los dos haría pensar que una
  /// empresa con logotipo no lo tiene.
  Future<Result<Uint8List?>> leer(String empresaId) async {
    final respuesta = await _api.getBytes(
      CompanyRuta.de(empresaId, '/logo'),
    );

    return respuesta.when(
      failure: Result.failure,
      ok: (r) {
        if (r.esExitosa) {
          // LOS BYTES TIENEN QUE VENIR. Un 200 sin cuerpo sería una respuesta que no
          // se puede pintar, y devolver `null` lo confundiría con «no hay logotipo».
          return r.bytes == null
              ? const Result.failure(
                  ApiJsonInvalidoFailure(
                    'El servidor devolvió el logotipo sin contenido.',
                  ),
                )
              : Result.ok(r.bytes);
        }

        final fallo = ApiErrorParser.interpretar(r);

        // SIN LOGOTIPO NO ES FALLO.
        if (fallo.codigo == codigoSinLogotipo) return const Result.ok(null);

        return Result.failure(fallo);
      },
    );
  }

  /// Sube o reemplaza el logotipo.
  ///
  /// **Devuelve los MISMOS bytes que se subieron**, y es deliberado: el `POST` responde
  /// con la metadata del archivo —id, tamaño, `sha256`— pero **no con su contenido**,
  /// así que pintar el logotipo nuevo exigiría una descarga más. Los bytes locales son
  /// los mismos que el servidor acaba de guardar —no los reescribe— y vienen en una
  /// **instancia nueva**, que es lo que hace que la imagen de la pantalla se repinte.
  Future<Result<Uint8List>> subir({
    required String empresaId,
    required String nombreDeArchivo,
    required Uint8List bytes,
  }) async {
    final respuesta = await _api.postMultipart(
      CompanyRuta.de(empresaId, '/logo'),
      campo: 'file',
      nombreDeArchivo: nombreDeArchivo,
      bytes: bytes,
    );

    return respuesta.when(
      failure: Result.failure,
      ok: (r) => r.esExitosa
          ? Result.ok(bytes)
          // LAS CIFRAS DEL 409 YA VIENEN: `ApiErrorParser` tiene `usedBytes` y
          // `capacityBytes` en su lista blanca, así que aquí no hay nada que añadir.
          // Las lee [capacidadDe].
          : Result.failure(ApiErrorParser.interpretar(r)),
    );
  }

  /// Quita el logotipo.
  ///
  /// **El 404 de la segunda vez se trata como éxito**, y el servidor lo contesta a
  /// propósito: «el recurso logotipo deja de existir, y decirlo es más útil que fingir
  /// que se borró algo». Para quien pulsó «Quitar», que ya no hubiera nada que quitar
  /// no es un problema que pueda resolver.
  ///
  /// **Y lo que libera es CAPACIDAD, no espacio físico.** El archivo sigue guardado
  /// hasta la purga, pero la capacidad contractual queda libre en el acto. El texto de
  /// la pantalla dice eso y no «se borró».
  Future<Result<void>> quitar(String empresaId) async {
    final respuesta = await _api.delete(CompanyRuta.de(empresaId, '/logo'));

    return respuesta.when(
      failure: Result.failure,
      ok: (r) {
        if (r.esExitosa) return const Result.ok(null);

        final fallo = ApiErrorParser.interpretar(r);

        return fallo.codigo == codigoSinLogotipo
            ? const Result.ok(null)
            : Result.failure(fallo);
      },
    );
  }

  /// Las dos cifras del 409 de capacidad, o nulas si no venían.
  ///
  /// ⚠️ **SON DE LA ORGANIZATION, NO DE LA EMPRESA.** El mensaje no puede decir «tu
  /// empresa se quedó sin espacio»: en una Organization con varias empresas, la que se
  /// quedó sin espacio es la organización entera.
  static ({int usados, int capacidad})? capacidadDe(Failure fallo) {
    if (fallo is! ApiHttpFailure) return null;
    if (fallo.codigo != codigoSinCapacidad) return null;

    final usados = fallo.extra['usedBytes'];
    final capacidad = fallo.extra['capacityBytes'];

    return usados is int && capacidad is int
        ? (usados: usados, capacidad: capacidad)
        : null;
  }
}
