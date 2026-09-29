/// LA ÚNICA FRONTERA entre el vocabulario de permisos del backend SaaS y el que
/// consume Seventra Administra.
///
/// ## Por qué hace falta
///
/// El producto pregunta `hasCode('deudas.cancelarPago')` en sesenta y un
/// archivos. El backend guarda `deudas.cancelar_pago`, porque su esquema exige
/// minúsculas y guion bajo (`CHECK (code ~ '^[a-z][a-z0-9_]*…')`). Son el mismo
/// permiso escrito en dos convenciones, y alguien tiene que traducir.
///
/// ## Por qué UNA sola frontera
///
/// La traducción ocurre **exactamente una vez**, al construir la sesión desde
/// `CompanyContext.effectivePermissions`. A partir de ahí el producto entero
/// habla su vocabulario de siempre y no sabe que existe otro.
///
/// La alternativa —convertir en cada pantalla, o en cada `hasCode`— es la que
/// produce el fallo caro: basta que un sitio olvide convertir para que un
/// permiso concedido se lea como denegado, y eso no se nota hasta que alguien no
/// puede hacer su trabajo.
///
/// ## Las cinco equivalencias
///
/// Cinco facultades del producto ya existían en el backend con otro nombre desde
/// 5D.4. **No se duplicaron**: no puede haber dos códigos para una misma
/// capacidad, porque entonces hay dos autoridades y conceder una sin la otra
/// produce un permiso a medias que nadie entiende. Se traducen aquí, y la
/// traducción está probada en las dos direcciones.
///
/// ## Lo que esto NO es
///
/// No es autorización ni una capa de compatibilidad: no decide nada, no tiene
/// estado y no consulta nada. Es un diccionario. La autorización la decide el
/// servidor, y `restricted` la aplica `AuthorizationService`.
library;

import 'modulos_permiso.dart';

/// Las cinco facultades que el backend ya nombraba de otra forma.
///
/// Clave: el código del producto. Valor: el del backend.
const equivalenciasSaaS = <String, String>{
  'personal.ver': 'personal.read',
  'nomina.ver': 'payroll.read',
  'nomina.cerrar': 'payroll.close',
  'comercial.ver': 'clients_services.read',
  'auditoria.ver': 'company.audit.read',
};

/// El código del backend que corresponde a un código del producto.
///
/// Determinista y total: todo código del catálogo local tiene uno.
String codigoSaaSDe(String codigoLocal) {
  final equivalente = equivalenciasSaaS[codigoLocal];
  if (equivalente != null) return equivalente;

  // Los dos segmentos se convierten igual: `cuentasFinancieras.cambiarEstatus`
  // → `cuentas_financieras.cambiar_estatus`. Un único mecanismo para módulo y
  // acción evita la tentación de mantener dos listas que se desincronizan.
  return codigoLocal.split('.').map(_aSnake).join('.');
}

/// El diccionario completo, construido UNA vez a partir del catálogo del
/// producto —nunca escrito a mano—.
///
/// Derivarlo de `modulosPermiso` es lo que garantiza que no pueda quedarse
/// corto: un permiso nuevo en el catálogo aparece aquí solo, y si su nombre no
/// tuviera traducción posible la prueba de exhaustividad lo diría.
final Map<String, String> _localASaaS = {
  for (final codigo in todosLosCodigosDePermiso()) codigo: codigoSaaSDe(codigo),
};

/// El inverso. Es el que se usa de verdad: lo que llega del servidor son códigos
/// SaaS y lo que el producto pregunta son códigos suyos.
final Map<String, String> _saaSALocal = {
  for (final entrada in _localASaaS.entries) entrada.value: entrada.key,
};

/// Todos los códigos del producto, con su equivalente del backend.
Map<String, String> get diccionarioDePermisos => Map.unmodifiable(_localASaaS);

/// Traduce el conjunto que manda el servidor al vocabulario del producto.
///
/// **Descarta en silencio lo que no reconoce, y es lo correcto.** El backend
/// tiene códigos propios que gobiernan SUS rutas —`personal.manage`,
/// `clients_services.manage`, `company.logo`— y que el producto local no
/// consulta. Traerlos como si fueran facultades de la interfaz no concedería
/// nada (nadie pregunta por ellos) pero sí ensuciaría la sesión con permisos que
/// no significan lo que parecen.
///
/// Lo que jamás hace es INVENTAR: un código que el servidor no mandó no aparece
/// aquí por ninguna vía.
Set<String> permisosDelProducto(Set<String> efectivosSaaS) {
  final traducidos = <String>{};

  for (final codigo in efectivosSaaS) {
    final local = _saaSALocal[codigo];
    if (local != null) traducidos.add(local);
  }

  return traducidos;
}

/// `cancelarPago` → `cancelar_pago`. Sin dependencias y sin expresiones
/// regulares costosas: se recorre una vez.
String _aSnake(String segmento) {
  final salida = StringBuffer();

  for (var i = 0; i < segmento.length; i++) {
    final caracter = segmento[i];
    final codigo = caracter.codeUnitAt(0);
    final esMayuscula = codigo >= 65 && codigo <= 90;

    if (esMayuscula) {
      if (i > 0) salida.write('_');
      salida.write(caracter.toLowerCase());
    } else {
      salida.write(caracter);
    }
  }

  return salida.toString();
}

/// ¿Este código del producto es una LECTURA?
///
/// Es la regla que el propio catálogo ya codificaba: `ver` es consultar y todo
/// lo demás cambia algo. Vive aquí, junto al vocabulario, porque es una
/// propiedad del código y no de quien lo pregunta — y porque `restricted`
/// necesita exactamente esta distinción para dejar leer y no dejar escribir.
bool esLectura(String codigoLocal) => codigoLocal.endsWith('.ver');
