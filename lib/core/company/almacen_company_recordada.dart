import 'package:shared_preferences/shared_preferences.dart';

/// Dónde se recuerda la última Company elegida.
///
/// GUARDA UN IDENTIFICADOR Y NADA MÁS. No el nombre, no la Organization, no los
/// módulos, no los permisos, no `restricted`, no el contexto: todo eso es autoridad
/// del servidor y cachearlo como verdad produciría una interfaz que muestra
/// permisos de ayer. Lo único que se persiste es **qué empresa abrir primero**, y
/// eso se vuelve a validar siempre contra la lista real (ver `GestorDeCompany`).
///
/// NO ES SECURE STORAGE, y la razón es conceptual antes que práctica: un
/// `companyId` no es una credencial. Guardarlo en DPAPI junto al token de refresco
/// lo vestiría de secreto y ataría una preferencia de interfaz al ciclo de vida de
/// la sesión, cuando debe sobrevivir a un cierre de sesión igual que el tema claro
/// u oscuro.
///
/// **No se indexa por Identity** aunque `shared_preferences` sea por MÁQUINA y dos
/// personas puedan usar el mismo equipo. No hace falta y no se gana nada: el id
/// recordado sólo se usa si aparece en la lista de Companies de la Identity actual,
/// y esa lista la da el servidor. Un id dejado por otra persona simplemente no
/// está en la lista y se descarta. Indexarlo por correo, en cambio, metería un dato
/// personal en un archivo en claro.
abstract interface class AlmacenCompanyRecordada {
  Future<String?> leer();

  Future<void> escribir(String companyId);

  Future<void> borrar();
}

/// Implementación real — `shared_preferences`, con la convención de clave que ya
/// usa el proyecto (`riseg_one.theme_mode`).
///
/// Deliberadamente separado de Drift, que se reserva para datos de negocio: la
/// empresa que alguien abrió la última vez en este equipo es una preferencia de
/// interfaz, y meterla en la base la incluiría en los respaldos y viajaría a otra
/// instalación al restaurarlos.
class AlmacenCompanyRecordadaPreferencias implements AlmacenCompanyRecordada {
  const AlmacenCompanyRecordadaPreferencias();

  static const String nombreClave = 'riseg_one.company_activa';

  @override
  Future<String?> leer() async {
    final prefs = await SharedPreferences.getInstance();
    final guardado = prefs.getString(nombreClave);

    if (guardado == null) return null;

    final limpio = guardado.trim();
    return limpio.isEmpty ? null : limpio;
  }

  @override
  Future<void> escribir(String companyId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(nombreClave, companyId);
  }

  @override
  Future<void> borrar() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(nombreClave);
  }
}
