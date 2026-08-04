import 'package:riseg_one/core/database/app_database.dart';

import '../shared/direccion_input.dart';
import '../shared/medio_contacto_input.dart';

/// Acceso a la Empresa operadora de RISEG ONE.
///
/// Encapsula el invariante de singleton: [obtenerActiva] siempre espera
/// exactamente una fila con `cicloVidaRegistro = activo` (garantizado a
/// nivel de base por un índice único parcial) — si no hay ninguna o hay
/// más de una, es una violación del invariante y debe fallar de forma
/// ruidosa, nunca elegir en silencio.
abstract interface class EmpresaRepository {
  Future<EmpresaData> obtenerActiva();

  Future<void> actualizarDatosGenerales(EmpresaCompanion cambios);

  /// Impide archivar la única Empresa activa — no existe todavía una
  /// operación administrativa que permita reemplazarla, así que esta es
  /// la única forma de dar de baja una Empresa en esta etapa.
  Future<void> archivar(String id);

  /// Dirección con `tipoDireccion = fiscal` de esta Empresa, si existe y
  /// sigue activa (`cicloVidaRegistro = activo`). Una fila archivada no
  /// se devuelve — para la pantalla, equivale a "sin dirección".
  Future<DireccionData?> obtenerDireccionFiscal(String empresaId);

  /// El `MedioContacto` con `etiqueta = 'principal'` de esta Empresa, si
  /// existe y sigue activo. Esa etiqueta es la convención determinista
  /// que identifica "el" medio de contacto que administra 4B — nunca "la
  /// primera fila encontrada".
  Future<MedioContactoData?> obtenerMedioContactoPrincipal(String empresaId);

  /// Guarda el expediente completo en una sola transacción: actualiza
  /// [datosGenerales], y crea/actualiza/archiva la Dirección fiscal y el
  /// Medio de contacto principal. Si cualquier escritura falla, ninguna
  /// se aplica.
  ///
  /// [direccionFiscal] y [medioContacto] en `null` significan
  /// "esa sección llegó vacía": si existía una fila activa previa, se
  /// archiva (nunca se borra físicamente); si no existía, no se crea
  /// nada. No hay un tercer estado de "no tocar esta sección" — 4B
  /// siempre guarda el expediente completo de una vez.
  Future<EmpresaExpedienteRaw> guardarExpediente({
    required String empresaId,
    required EmpresaCompanion datosGenerales,
    required DireccionInput? direccionFiscal,
    required MedioContactoInput? medioContacto,
  });
}

/// Resultado crudo de [EmpresaRepository.guardarExpediente] — las tres
/// filas de Drift resultantes, sin envolver todavía en el tipo de
/// dominio `EmpresaExpedienteData` (eso lo arma el caso de uso).
class EmpresaExpedienteRaw {
  const EmpresaExpedienteRaw({required this.empresa, this.direccionFiscal, this.medioContacto});

  final EmpresaData empresa;
  final DireccionData? direccionFiscal;
  final MedioContactoData? medioContacto;
}
