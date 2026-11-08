import 'dart:collection';
import 'dart:typed_data';

import 'clientes_repositorio_http.dart';

/// La caché de los logotipos del listado de clientes (**CP-20**).
///
/// ## Por qué existe, y qué problema resuelve de verdad
///
/// El listado pinta el logotipo de cada fila, y cada uno es **una petición HTTP
/// autenticada**: `Image.network` no sirve —el token no viaja en un `<img>` y la ruta
/// responde `Content-Disposition: attachment`—. Sin caché, volver a la pestaña, cambiar un
/// filtro o pulsar «Cargar más» volvería a bajar los mismos bytes.
///
/// ## La clave es el ARCHIVO, no el cliente
///
/// ⚠️ Esto es lo que la hace **correcta** y no sólo rápida. El contenido de un archivo es
/// inmutable y reemplazar el logotipo **estrena archivo**, así que el `logoFileId` que
/// publica el listado cambia. Si la clave fuera el id del CLIENTE, subir un logotipo nuevo
/// seguiría enseñando el viejo y parecería que no se guardó — la trampa que ya costó una
/// entrega en E1.
///
/// ## Una petición por archivo, aunque la pidan diez filas
///
/// Se guarda el `Future` en vuelo y no sólo el resultado. Dos filas que comparten logotipo
/// —o la misma fila repintada al desplazar— esperan **la misma** petición en lugar de
/// lanzar dos. Es la mitad que hace que «sólo las filas visibles» signifique algo: sin
/// ella, desplazar arriba y abajo volvería a pedir lo que ya se pidió.
///
/// ## Lo que NO hace
///
/// 🚫 **No es una caché entre sesiones.** Vive mientras vive la pantalla y se va con ella.
/// Guardarla en disco traería invalidación, cuota y datos de un cliente en el navegador, y
/// nada de eso lo pidió nadie.
class CacheDeLogotipos {
  CacheDeLogotipos({required this.repositorio, required this.empresaId, this.maximo = 200});

  final ClientesRepositorioHttp repositorio;
  final String empresaId;

  /// Cuántos logotipos se recuerdan. Con páginas de 50 y «Cargar más», doscientos son
  /// cuatro páginas: de sobra para desplazarse sin volver a pedir, y acotado para que la
  /// memoria no crezca sin techo si alguien pulsa veinte veces.
  final int maximo;

  /// `LinkedHashMap` porque **el orden de inserción es el criterio de desalojo**: el más
  /// antiguo se va primero. Un `Map` normal no garantiza ese orden.
  final LinkedHashMap<String, Uint8List?> _listos = LinkedHashMap<String, Uint8List?>();
  final Map<String, Future<Uint8List?>> _enVuelo = <String, Future<Uint8List?>>{};

  /// Lo que ya está en memoria para ese archivo, o nulo si todavía no se pidió.
  ///
  /// ⚠️ **Devolver nulo NO significa «no tiene logotipo».** Significa «no lo sé todavía»,
  /// y la pantalla pinta las iniciales en los dos casos — que es justo por lo que las
  /// iniciales no son un apaño provisional: son la respuesta mientras carga y la respuesta
  /// definitiva cuando no hay.
  Uint8List? enMemoria(String fileId) => _listos[fileId];

  bool yaSePidio(String fileId) => _listos.containsKey(fileId) || _enVuelo.containsKey(fileId);

  /// Pide los bytes **una vez** por archivo.
  ///
  /// Un fallo se guarda como nulo a propósito: la fila enseña sus iniciales y **no se
  /// reintenta en bucle**. Un listado que reintentara en cada repintado convertiría un
  /// servidor con problemas en una tormenta de peticiones, que es el escenario que CP-20
  /// existe para evitar.
  Future<Uint8List?> pedir({required String clienteId, required String fileId}) {
    if (_listos.containsKey(fileId)) return Future.value(_listos[fileId]);

    final enVuelo = _enVuelo[fileId];
    if (enVuelo != null) return enVuelo;

    final peticion = _traer(clienteId: clienteId, fileId: fileId);
    _enVuelo[fileId] = peticion;

    return peticion;
  }

  Future<Uint8List?> _traer({required String clienteId, required String fileId}) async {
    Uint8List? bytes;

    try {
      final resultado = await repositorio.leerLogotipo(
        empresaId: empresaId,
        clienteId: clienteId,
      );

      bytes = resultado.when(ok: (b) => b, failure: (_) => null);
    } finally {
      // EN UN `finally` para que una excepción no deje la entrada en vuelo para siempre:
      // esa fila no volvería a pedir nunca y se quedaría con las iniciales sin motivo.
      _enVuelo.remove(fileId);
    }

    _guardar(fileId, bytes);
    return bytes;
  }

  void _guardar(String fileId, Uint8List? bytes) {
    _listos[fileId] = bytes;

    while (_listos.length > maximo) {
      _listos.remove(_listos.keys.first);
    }
  }
}
