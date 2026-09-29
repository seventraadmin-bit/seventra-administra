/// El constructor de rutas con Company. **Dueño único del prefijo dinámico
/// `/companies/{companyId}`.**
///
/// POR QUÉ EXISTE, que es lo mismo que pasó con `/api/v1` en IF-1: si cada
/// repositorio escribiera `'/companies/$companyId/employees'` a mano, el día que
/// el backend mueva el plano operativo habría que tocar doscientos archivos, y
/// bastaría una interpolación con una barra de más para producir un 404 que nadie
/// sabe explicar. Aquí se compone en un solo sitio y se valida.
///
/// LO QUE ESTA CLASE **NO** ES: un contexto implícito. No guarda ninguna Company y
/// no la lee de ningún estado global — el `companyId` se pasa en cada llamada, y
/// eso es deliberado. El backend lo dice en su propio código: «LA COMPANY VIENE DE
/// LA RUTA, nunca de la sesión. No existe ningún `currentCompanyId` en el
/// servidor». Un helper que resolviera la Company por su cuenta reintroduciría
/// exactamente ese estado compartido que el diseño evita, y haría posible que una
/// petición saliera con la Company equivocada sin que nada en el punto de llamada
/// lo delatara.
///
/// LA COLECCIÓN NO ES SCOPED. `GET /companies` —las Companies que esta Identity
/// puede abrir— no lleva `companyId` y no pasa por aquí: pedirle a este
/// constructor una ruta sin Company sería forzarlo a representar algo que no es.
/// Por eso [coleccion] se expone como constante y `CompanyApi` la usa directamente.
class CompanyRuta {
  const CompanyRuta._();

  /// La colección de Companies accesibles. **Sin Company**: es la lista de las
  /// que hay, no una operación dentro de una.
  static const String coleccion = '/companies';

  /// Cómo tiene que verse un `companyId`.
  ///
  /// Se valida en el cliente aunque el servidor ya restrinja la ruta a `:guid`,
  /// y la razón es el diagnóstico: un id mal formado que llega al servidor
  /// devuelve un 404 indistinguible de «no tienes acceso a esa empresa», y esa
  /// confusión se depura mal. Aquí salta en el punto de llamada, que es donde
  /// está el error.
  static final RegExp _formaDeGuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  /// Compone una ruta dentro de una Company.
  ///
  /// ```dart
  /// CompanyRuta.de(companyId, '/context')    // /companies/{id}/context
  /// CompanyRuta.de(companyId, '/employees')  // /companies/{id}/employees
  /// ```
  ///
  /// El resultado es **relativo**: sin el prefijo de versión, que sigue siendo de
  /// `ApiConfig`. Dos dueños para dos prefijos distintos, cada uno en su capa.
  ///
  /// Lanza [ArgumentError] —y no devuelve un `Result`— porque las tres cosas que
  /// comprueba son errores de PROGRAMACIÓN, no estados del sistema: un id que no
  /// es un GUID, una ruta sin barra inicial o una ruta que ya trae el prefijo. Es
  /// el mismo criterio de `ApiConfig.resolver`, y quien llama a través de
  /// `ApiClient` lo recibe convertido en `ApiConfigFailure` sin que escape.
  static String de(String companyId, String ruta) {
    if (!_formaDeGuid.hasMatch(companyId)) {
      // El id NO va en el mensaje completo si es un texto arbitrario: podría
      // traer lo que sea. Se dice qué se esperaba.
      throw ArgumentError.value(
        companyId,
        'companyId',
        'No tiene la forma de un identificador de empresa',
      );
    }

    if (!ruta.startsWith('/')) {
      throw ArgumentError.value(
        ruta,
        'ruta',
        'Una ruta dentro de la empresa empieza por «/»',
      );
    }

    if (ruta.startsWith(coleccion)) {
      // `CompanyRuta.de(id, '/companies/x')` produciría
      // `/companies/{id}/companies/x`. Es el mismo tropiezo que el prefijo de
      // versión, con el mismo remedio: rechazarlo aquí en vez de depurar el 404.
      throw ArgumentError.value(
        ruta,
        'ruta',
        'El prefijo de empresa lo pone esta clase; la ruta no debe traerlo',
      );
    }

    return '$coleccion/$companyId$ruta';
  }
}
