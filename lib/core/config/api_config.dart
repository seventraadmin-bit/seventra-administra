import '../error/failure.dart';
import '../error/result.dart';

/// La dirección del backend SaaS y el dueño ÚNICO del prefijo de versión.
///
/// Se resuelve en tiempo de compilación mediante
/// `--dart-define=SEVENTRA_API_BASE_URL=http://localhost:5199`, igual que
/// [Env] resuelve `APP_ENV`.
///
/// LA VARIABLE ES EL SERVIDOR, NO LA RUTA DE LA API. El operador escribe
/// `http://localhost:5199` y nunca `/api/v1`: ese prefijo lo pone el cliente,
/// y es lo que permite que el día que exista `/api/v2` no haya que reconfigurar
/// ninguna instalación ni tocar doscientos repositorios.
///
/// SIN VALOR POR OMISIÓN ÚTIL, y aquí no se puede imitar el `defaultValue:
/// 'prod'` de [Env]: no existe una URL «segura por omisión». Poner `localhost`
/// como omisión haría que una compilación de producción mal empaquetada
/// apuntara a la máquina del propio usuario y pareciera funcionar. Vacío
/// significa *no configurado*, y eso falla al arrancar.
class ApiConfig {
  const ApiConfig._(this.baseUrl);

  /// El prefijo de versión de la API, y **el único literal `/api/v1` de todo
  /// `lib/`**.
  ///
  /// Que sea uno solo no es estética: es lo que hace que migrar a `v2` sea
  /// cambiar esta línea. Hay una prueba que cuenta las apariciones del literal
  /// en el árbol para que nadie lo reintroduzca en un repositorio.
  static const String rutaDeVersion = '/api/v1';

  static const String _raw = String.fromEnvironment('SEVENTRA_API_BASE_URL');

  /// La base canónica: esquema, host y puerto. Sin barra final, sin ruta, sin
  /// query y sin fragmento.
  final Uri baseUrl;

  /// Resuelve la configuración, o devuelve el motivo exacto por el que no es
  /// válida.
  ///
  /// Se llama en `bootstrap`, ANTES de `runApp`: una URL mal configurada tiene
  /// que impedir el arranque con un mensaje legible, no dejar que la aplicación
  /// abra y falle en la primera petición, cuando el usuario ya está dentro y el
  /// síntoma no se parece a su causa.
  ///
  /// [raw] existe para las pruebas; en producción llega de `--dart-define`.
  static Result<ApiConfig> resolve({String? raw}) {
    final texto = (raw ?? _raw).trim();

    if (texto.isEmpty) {
      return const Result.failure(
        ApiConfigFailure(
          'Falta la dirección del servidor. Compila con '
          '--dart-define=SEVENTRA_API_BASE_URL=https://tu-servidor',
        ),
      );
    }

    final uri = Uri.tryParse(texto);

    if (uri == null) {
      return Result.failure(
        ApiConfigFailure('La dirección «$texto» no es una URL válida.'),
      );
    }

    // Sin esquema explícito, `Uri.tryParse('localhost:5199')` interpreta
    // `localhost` COMO el esquema y deja el host vacío. Es exactamente la clase
    // de sorpresa silenciosa que conviene cortar aquí: se exige que el esquema
    // sea uno de los dos que entendemos.
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return Result.failure(
        ApiConfigFailure(
          'La dirección debe empezar por http:// o https://, y «$texto» no lo hace.',
        ),
      );
    }

    if (uri.host.isEmpty) {
      return Result.failure(
        ApiConfigFailure('La dirección «$texto» no indica ningún servidor.'),
      );
    }

    // Credenciales en la URL: nunca. Viajarían en cada registro y en cada
    // mensaje de error, y no hay ningún caso legítimo en este producto.
    if (uri.userInfo.isNotEmpty) {
      return const Result.failure(
        ApiConfigFailure('La dirección no puede llevar usuario ni contraseña.'),
      );
    }

    // La ruta base se RECHAZA en IF-1, y es una decisión, no un olvido:
    // aceptarla permitiría montar la API detrás de un prefijo —un despliegue
    // legítimo— pero abre la puerta a `/api/v1` duplicado y a barras dobles, y
    // hoy no hay ningún despliegue que lo necesite. Si aparece, se admite con su
    // regla explícita y su prueba. Falla ahora con un mensaje claro.
    if (uri.path.isNotEmpty && uri.path != '/') {
      return Result.failure(
        ApiConfigFailure(
          'La dirección debe ser sólo el servidor, sin ninguna ruta: sobra «${uri.path}». '
          'El prefijo /api/v1 lo pone la aplicación.',
        ),
      );
    }

    if (uri.hasQuery) {
      return const Result.failure(
        ApiConfigFailure(
          'La dirección no puede llevar parámetros de consulta.',
        ),
      );
    }

    if (uri.hasFragment) {
      return const Result.failure(
        ApiConfigFailure('La dirección no puede llevar un fragmento (#).'),
      );
    }

    if (uri.scheme == 'http' && !esMaquinaLocal(uri.host)) {
      return Result.failure(
        ApiConfigFailure(
          'Sin cifrado sólo se admite la máquina local. «${uri.host}» exige https://.',
        ),
      );
    }

    // La forma canónica: se conserva esquema, host y puerto, y se descarta todo
    // lo demás. Así la base nunca tiene barra final y no puede producir `//` al
    // componer una ruta.
    return Result.ok(
      ApiConfig._(
        Uri(
          scheme: uri.scheme,
          host: uri.host,
          port: uri.hasPort ? uri.port : null,
        ),
      ),
    );
  }

  /// ¿Es la máquina donde corre la aplicación?
  ///
  /// LA LISTA ES CERRADA Y COMPLETA: `localhost`, `127.0.0.1` y `::1`. Nada de
  /// heurísticas por rango privado — `192.168.x.x` es la RED, no esta máquina, y
  /// tratarla como local es exactamente cómo un despliegue de oficina acaba
  /// enviando tokens de sesión en claro por el cableado.
  static bool esMaquinaLocal(String host) {
    final normalizado = host.toLowerCase();

    return normalizado == 'localhost' ||
        normalizado == '127.0.0.1' ||
        normalizado == '::1';
  }

  /// Compone una ruta RELATIVA del producto contra la base versionada.
  ///
  /// ```
  /// resolver('/companies/$id/employees')
  ///   → http://localhost:5199/api/v1/companies/.../employees
  /// ```
  ///
  /// Rechaza que el llamador traiga el prefijo: sin esta comprobación, un
  /// repositorio que pasara `/api/v1/companies` produciría
  /// `/api/v1/api/v1/companies` y un 404 que nadie sabría explicar. La ruta es
  /// dato del programa, así que un valor mal formado es un error de
  /// programación y se trata como tal.
  Uri resolver(String rutaRelativa, [Map<String, String>? query]) {
    if (!rutaRelativa.startsWith('/')) {
      throw ArgumentError.value(
        rutaRelativa,
        'rutaRelativa',
        'Una ruta del producto empieza por «/».',
      );
    }

    if (rutaRelativa == rutaDeVersion ||
        rutaRelativa.startsWith('$rutaDeVersion/')) {
      throw ArgumentError.value(
        rutaRelativa,
        'rutaRelativa',
        'La ruta no lleva el prefijo de versión: lo añade ApiConfig.',
      );
    }

    return baseUrl.replace(
      path: '$rutaDeVersion$rutaRelativa',
      queryParameters: (query == null || query.isEmpty) ? null : query,
    );
  }

  @override
  String toString() => 'ApiConfig($baseUrl$rutaDeVersion)';
}
