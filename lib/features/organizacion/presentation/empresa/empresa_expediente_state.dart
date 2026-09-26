import 'package:riseg_one/features/organizacion/domain/usecases/empresa_expediente_data.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/empresa_expediente_errors.dart';

enum EmpresaExpedienteModo { consulta, edicion }

/// Estado de la pantalla de expediente de Empresa.
///
/// Guarda datos y estado, no objetos de UI: los `TextEditingController`
/// viven en el widget de edición, con su propio ciclo de vida — este
/// estado solo sabe *que* hay cambios sin guardar (`tieneCambiosSinGuardar`),
/// nunca el contenido de los campos.
class EmpresaExpedienteState {
  const EmpresaExpedienteState({
    this.cargando = true,
    this.guardando = false,
    this.tieneCambiosSinGuardar = false,
    this.modo = EmpresaExpedienteModo.consulta,
    this.datos,
    this.logoPath,
    this.errorCarga,
    this.erroresGuardado = const [],
    this.errorGuardadoGeneral = false,
  });

  final bool cargando;
  final bool guardando;
  final bool tieneCambiosSinGuardar;
  final EmpresaExpedienteModo modo;
  final EmpresaExpedienteData? datos;

  /// Ruta en disco del logotipo vigente de la Empresa (Etapa 5B.2), resuelta
  /// desde `Empresa.logoAttachmentId`. `null` significa "sin logotipo", y la
  /// ficha lo resuelve con iniciales — nunca con el escudo del producto.
  final String? logoPath;

  /// No nulo solo si la carga inicial falló — un caso casi imposible
  /// tras la Etapa 4A (singleton garantizado), pero se maneja de todos
  /// modos con una acción de reintentar.
  final String? errorCarga;

  /// Errores estructurados de la última validación fallida — la
  /// pantalla los asocia a cada campo por [ErrorCampoExpediente.campo],
  /// nunca analizando texto.
  final List<ErrorCampoExpediente> erroresGuardado;

  /// `true` solo cuando el guardado falló por algo que no es un error de
  /// validación de campo (ej. un problema de persistencia) — la pantalla
  /// lo usa para decidir si muestra el mensaje de error general.
  final bool errorGuardadoGeneral;

  EmpresaExpedienteState copyWith({
    bool? cargando,
    bool? guardando,
    bool? tieneCambiosSinGuardar,
    EmpresaExpedienteModo? modo,
    EmpresaExpedienteData? datos,
    String? logoPath,
    bool limpiarLogo = false,
    String? errorCarga,
    List<ErrorCampoExpediente>? erroresGuardado,
    bool? errorGuardadoGeneral,
  }) {
    return EmpresaExpedienteState(
      cargando: cargando ?? this.cargando,
      guardando: guardando ?? this.guardando,
      tieneCambiosSinGuardar: tieneCambiosSinGuardar ?? this.tieneCambiosSinGuardar,
      modo: modo ?? this.modo,
      datos: datos ?? this.datos,
      // `limpiarLogo` hace falta porque `null` en un `copyWith` significa
      // "no lo toques": sin él, quitar el logotipo no podría representarse.
      logoPath: limpiarLogo ? null : (logoPath ?? this.logoPath),
      errorCarga: errorCarga,
      erroresGuardado: erroresGuardado ?? this.erroresGuardado,
      errorGuardadoGeneral: errorGuardadoGeneral ?? this.errorGuardadoGeneral,
    );
  }
}
