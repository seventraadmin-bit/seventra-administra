import 'dart:typed_data';

/// Los logotipos de las empresas a las que se tiene acceso, **pedidos una vez**.
///
/// ## Para qué existe, y por qué aquí
///
/// La pantalla de elegir empresa y el menú de la barra inferior enseñan una tarjeta por
/// empresa con su logotipo, y los dos los pintan **antes de entrar en ninguna**. Eso se
/// puede hacer porque `GET /companies/{id}/logo` se autoriza **por acceso y no por
/// permiso de módulo** —su propio código lo argumenta: «es visual, no un dato
/// reservado»—, así que cualquier empresa de la lista es consultable.
///
/// Vive en `core/company/` y **no bajo `features/`** por una razón concreta: el guardia
/// de arquitectura exige que sólo las features nombradas toquen el cliente HTTP, y los
/// archivos del portón —login, selector, marco— no están nombrados a propósito. Reciben
/// lo que necesitan por constructor, y quien arma la capa HTTP es el arranque.
///
/// ## Lo que NO hace
///
/// **No decide a qué empresa se entra, y no conoce la activa.** Es un diccionario de
/// `companyId` a bytes. La pertenencia la manda el `company_id` real de cada fila, y
/// una caché de imágenes no participa en eso.
///
/// **No vuelve a pedir lo que ya preguntó**, ni siquiera cuando la respuesta fue «no
/// tiene logotipo»: abrir el menú de la barra cinco veces serían cinco rondas de
/// descargas para enseñar lo mismo.
class LogotiposDeEmpresa {
  LogotiposDeEmpresa(this._leer);

  /// Cómo se lee un logotipo. **Una función y no el repositorio**, para que esta clase
  /// de `core/` no dependa de un archivo de `features/` — sería al revés de como van
  /// las capas. El arranque pasa `LogotipoRepositorioHttp.leer`.
  ///
  /// Devuelve nulo cuando la empresa **no tiene** logotipo, que no es un fallo.
  final Future<Uint8List?> Function(String companyId) _leer;

  /// Lo ya resuelto. **Un `companyId` presente con valor nulo significa «se preguntó y
  /// no tiene»**, que es distinto de ausente —«no se ha preguntado»—. Sin esa
  /// distinción, una empresa sin logotipo se volvería a pedir cada vez que se pinta.
  final Map<String, Uint8List?> _resueltos = <String, Uint8List?>{};

  /// Las peticiones en vuelo, para que dos tarjetas de la misma empresa —la del menú y
  /// la de la pantalla— no provoquen dos descargas.
  final Map<String, Future<Uint8List?>> _enVuelo = <String, Future<Uint8List?>>{};

  /// Lo que ya se sabe de esta empresa, **sin pedir nada**.
  ///
  /// Para que una tarjeta pueda nacer con el logotipo puesto cuando ya se descargó, en
  /// vez de enseñar las iniciales y cambiar un instante después.
  ({Uint8List? bytes})? yaResuelto(String companyId) =>
      _resueltos.containsKey(companyId) ? (bytes: _resueltos[companyId]) : null;

  /// El logotipo de una empresa, o nulo si no tiene.
  ///
  /// **Un fallo de red también devuelve nulo**, y es deliberado: la tarjeta enseña las
  /// iniciales, que es exactamente lo que enseñaría una empresa sin logotipo. Convertir
  /// un bache de red en un aviso en la pantalla de bienvenida molestaría sin ofrecer
  /// nada que hacer — y lo que de verdad importa ahí es poder elegir empresa.
  ///
  /// Eso sí: **un fallo NO se guarda en la caché**, así que el siguiente intento vuelve
  /// a pedirlo. Recordar un fallo dejaría la empresa con iniciales para toda la sesión
  /// por un segundo malo.
  Future<Uint8List?> leer(String companyId) {
    if (_resueltos.containsKey(companyId)) {
      return Future<Uint8List?>.value(_resueltos[companyId]);
    }

    final enVuelo = _enVuelo[companyId];
    if (enVuelo != null) return enVuelo;

    final futuro = _pedir(companyId);
    _enVuelo[companyId] = futuro;

    return futuro;
  }

  Future<Uint8List?> _pedir(String companyId) async {
    try {
      final bytes = await _leer(companyId);
      _resueltos[companyId] = bytes;

      return bytes;
    } catch (_) {
      // NO SE GUARDA EL FALLO. Y se devuelve nulo en vez de propagar: quien pinta una
      // tarjeta no tiene nada mejor que hacer con una excepción que enseñar las
      // iniciales, y propagarla obligaría a cada sitio a envolver la llamada.
      return null;
    } finally {
      _enVuelo.remove(companyId);
    }
  }

  /// Olvida todo. Al cerrar sesión, porque la lista de empresas de la siguiente persona
  /// no tiene por qué parecerse a la de ésta.
  void olvidar() {
    _resueltos.clear();
    _enVuelo.clear();
  }
}
