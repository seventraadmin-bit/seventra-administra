/// Un permiso del catálogo, tal como lo devuelve
/// `GET /companies/{id}/permissions`.
///
/// **El catálogo lo manda el servidor y no se replica en el cliente.** Una lista de
/// permisos escrita aquí quedaría desfasada en cuanto el backend sembrara uno nuevo,
/// y el síntoma sería una casilla que no aparece —o peor, una que aparece y no
/// existe—.
class PermisoDeEmpresa {
  const PermisoDeEmpresa({
    required this.codigo,
    required this.nombre,
    required this.modulo,
    required this.protegido,
  });

  factory PermisoDeEmpresa.deJson(Map<String, dynamic> json) => PermisoDeEmpresa(
    codigo: json['code'] as String,
    nombre: json['name'] as String,
    modulo: json['moduleCode'] as String?,
    // ⚠️ `protegido` es la NEGACIÓN de `maestroAutoGrant`, y conviene decirlo aquí
    // porque es fácil leerlo al revés: un permiso que el Maestro NO recibe solo es
    // precisamente el que hay que conceder a mano.
    protegido: json['maestroAutoGrant'] == false,
  );

  final String codigo;

  /// El nombre en lenguaje de negocio, del catálogo. **No se traduce en el cliente**:
  /// el servidor es el dueño del texto, y dos redacciones acabarían discrepando.
  final String nombre;

  /// El módulo al que pertenece, o `null` si es **del núcleo**.
  ///
  /// Los del núcleo —configurar la empresa, auditoría, usuarios, estructura,
  /// reportes— no dependen de ningún módulo contratado: existen siempre.
  final String? modulo;

  /// ¿Ni el Maestro lo recibe por su rol?
  ///
  /// Son **seis** hoy: ver y cambiar sueldo, leer y gestionar el expediente sensible,
  /// y los dos de portales de cliente. Se conceden uno por uno y con aviso, nunca de
  /// paquete: una plantilla que los marcara convertiría una decisión deliberada en un
  /// efecto colateral de elegir un puesto.
  final bool protegido;

  /// ¿Es del núcleo, sin módulo detrás?
  bool get esDelNucleo => modulo == null;
}
