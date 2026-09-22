import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/organizacion/data/tables/documento_por_emitir_table.dart';

import '../usecases/documento_por_emitir_armado.dart';
import '../usecases/documento_por_emitir_detalle.dart';
import '../usecases/eliminar_documento_por_emitir_fisicamente_usecase.dart';

/// Agenda de documentos por emitir (Etapa 4I.1, ciclo administrativo
/// completo desde la 4I.2.1) — obligaciones administrativas de
/// preparar/emitir/enviar un CFDI/recibo, nunca el timbrado real ni una
/// Cuenta por cobrar.
abstract interface class DocumentoPorEmitirRepository {
  /// `null` si ningún documento existe todavía con esa
  /// `generationKey` — usado por la generación para omitir duplicados
  /// con un mensaje comprensible antes de intentar insertar (el índice
  /// único de la tabla es la protección real contra concurrencia).
  Future<DocumentoPorEmitirData?> obtenerPorGenerationKey(String generationKey);

  /// Documentos que representan el MISMO hecho comercial que
  /// [claveComercial] —mismo cliente, entidad fiscal, servicios,
  /// periodo, tipo y agrupación— sin importar qué vigencia de la
  /// configuración de cobro los originó.
  ///
  /// La generación lo consulta para no volver a pedir un periodo que
  /// ya está materializado cuando una vigencia retroactiva cambia la
  /// `generationKey`. Ver `claveComercialDeGenerationKey`.
  Future<List<DocumentoPorEmitirData>> listarPorClaveComercial(String claveComercial);

  Future<DocumentoPorEmitirData?> obtenerPorId(String documentoPorEmitirId);

  /// Inserta el documento y sus tablas hijas, y el primer evento de
  /// historial (`creadoAutomatico`/`creadoManual`, según corresponda),
  /// todo en una sola transacción.
  /// [actorUsuarioId] es quien PULSÓ la acción, también cuando el documento
  /// lo arma el generador: "automático" describe cómo se calculó el
  /// contenido, no que nadie lo haya pedido. Sólo queda nulo cuando la
  /// creación no nace de una sesión (arranque, herramientas, pruebas).
  Future<DocumentoPorEmitirData> crearDocumento({
    required String codigo,
    required DocumentoPorEmitirArmado armado,
    required TipoEventoDocumentoPorEmitir tipoEventoCreacion,
    String? actorUsuarioId,
  });

  Future<DocumentoPorEmitirDetalle?> obtenerDetalle(String documentoPorEmitirId);

  /// Hitos planeados del documento (Etapa 15), ordenados por `orden` —
  /// ver el doc comment de `DocumentoPorEmitirDetalle.hitos`.
  Future<List<DocumentoPorEmitirHitoData>> listarHitos(String documentoPorEmitirId);

  /// Servicios cubiertos por cada documento de [ids], en UNA consulta.
  ///
  /// La relación es N:M real (un mismo documento puede facturar varios
  /// Servicios), asi que la llave apunta a una lista y no a un id
  /// suelto. Existe para que Reportes resuelva el Servicio de cientos
  /// de Cuentas por cobrar sin consultar documento por documento.
  Future<Map<String, List<String>>> listarServicioIdsPorDocumento(Iterable<String> ids);

  /// Documentos por id, en una sola consulta — resuelve la Entidad
  /// fiscal (y el resto del snapshot) de un lote de Cuentas por cobrar.
  Future<Map<String, DocumentoPorEmitirData>> listarPorIds(Iterable<String> ids);

  Future<List<DocumentoPorEmitirData>> listar({
    DateTime? rangoInicio,
    DateTime? rangoFin,
    String? clienteId,
    String? servicioId,
    String? tipoDocumento,
    String? estatus,
  });

  /// Cambia el estatus — el caso de uso ya validó la transición y que
  /// `motivo` esté presente cuando la transición lo exige. Registra el
  /// evento de historial correspondiente en la misma transacción.
  Future<DocumentoPorEmitirData> cambiarEstatus({
    required String documentoPorEmitirId,
    required String nuevoEstatus,
    String? motivo,
    required TipoEventoDocumentoPorEmitir tipoEvento,
    String? actorUsuarioId,
  });

  /// Registra los datos definitivos y transiciona a `emitido` — el
  /// caso de uso ya validó la transición y los campos permitidos según
  /// `tipoDocumento`. Registra el evento `emisionRegistrada`.
  Future<DocumentoPorEmitirData> registrarEmision({
    required String documentoPorEmitirId,
    required String folioDocumento,
    String? uuid,
    required DateTime fechaEmisionReal,
    required int importeEmitido,
    String? observacionesEmision,
    String? actorUsuarioId,
  });

  /// Corrige uno o más datos definitivos ya registrados, sin cambiar el
  /// estatus — el caso de uso ya validó que el documento está en
  /// `emitido`/`enviado` (nunca `procesadoAceptado`) y que `motivo` no
  /// esté vacío. Registra el evento `correccionDatosEmision` con los
  /// valores anteriores en `datosRelevantes`. `null` en un campo aquí
  /// significa "no tocar ese campo", nunca "bórralo" — mismo criterio
  /// que `actualizarObservaciones` en Configuración de cobro.
  Future<DocumentoPorEmitirData> corregirDatosEmision({
    required String documentoPorEmitirId,
    required String motivo,
    String? folioDocumento,
    String? uuid,
    DateTime? fechaEmisionReal,
    int? importeEmitido,
    String? observacionesEmision,
    String? actorUsuarioId,
  });

  /// Registra el envío y transiciona a `enviado` — reconstruye
  /// completa la lista de correos utilizados (borrar e insertar, mismo
  /// criterio que `DocumentoPorEmitirCorreo`). Registra el evento
  /// `envioRegistrado` con los correos utilizados en `datosRelevantes`.
  Future<DocumentoPorEmitirData> registrarEnvio({
    required String documentoPorEmitirId,
    required DateTime fechaEnvio,
    required List<String> correos,
    String? observacionesEnvio,
    String? actorUsuarioId,
  });

  /// El modelo existe desde la Etapa 4I.1; la interfaz de captura llega
  /// en la 4I.2.1. Nunca toca el snapshot de líneas. Registra el
  /// evento `ajusteRegistrado` con el ajuste/motivo anterior y nuevo.
  Future<DocumentoPorEmitirData> actualizarAjusteManual({
    required String documentoPorEmitirId,
    int? ajusteManual,
    String? motivoAjuste,
    String? actorUsuarioId,
  });

  /// Corrige el ajuste comercial de un documento ya emitido (Maestro).
  ///
  /// Escribe exactamente los mismos tres campos que
  /// `actualizarAjusteManual` y ni uno más: nunca el importe emitido, el
  /// folio, el UUID ni nada de cobranza. Registra
  /// `correccionAjusteHistorico` con el antes y el después completos,
  /// incluyendo el motivo administrativo de la corrección.
  Future<DocumentoPorEmitirData> corregirAjusteHistorico({
    required String documentoPorEmitirId,
    required String motivoCorreccion,
    int? ajusteManual,
    String? motivoAjuste,
    String? actorUsuarioId,
  });

  /// Líneas de varios documentos en UNA sola consulta, agrupadas por
  /// documento.
  ///
  /// Existe porque la Agenda necesita el tratamiento fiscal de cada línea
  /// para calcular el total esperado de cada renglón, y pedirlas documento
  /// por documento sería un N+1 en la pantalla más poblada del módulo.
  /// Devuelve sólo los documentos que tienen líneas: uno sin ninguna
  /// simplemente no aparece en el mapa.
  Future<Map<String, List<DocumentoPorEmitirLineaData>>> lineasPorDocumentos(List<String> documentoIds);

  /// Correos realmente utilizados en el envío vigente — vacío si nunca
  /// se ha registrado un envío.
  Future<List<String>> listarCorreosEnvio(String documentoPorEmitirId);

  /// Historial administrativo completo, en orden cronológico.
  Future<List<DocumentoPorEmitirEventoData>> listarEventos(String documentoPorEmitirId);

  /// Inserta el nuevo `Attachment` y registra el evento
  /// `archivoAdjuntado` en la misma transacción — el caso de uso ya
  /// validó la categoría, el tipo de archivo y ya guardó el archivo
  /// físico (el `path`/`storedFileName` aquí son el resultado de eso,
  /// nunca se calculan en el repositorio).
  Future<AttachmentData> adjuntarArchivo({
    required String documentoPorEmitirId,
    required String categoria,
    required String originalFileName,
    required String storedFileName,
    required String path,
    required String mimeType,
    required int sizeBytes,
    String? actorUsuarioId,
  });

  /// Inserta el `Attachment` nuevo, archiva el anterior
  /// (`estado = archivado`, nunca lo borra) y registra el evento
  /// `archivoReemplazado` con ambos ids/nombres y el motivo (si lo
  /// hay) en `datosRelevantes` — todo en una sola transacción.
  Future<AttachmentData> reemplazarArchivo({
    required String documentoPorEmitirId,
    required String attachmentAnteriorId,
    required String categoria,
    required String originalFileName,
    required String storedFileName,
    required String path,
    required String mimeType,
    required int sizeBytes,
    String? motivo,
    String? actorUsuarioId,
  });

  /// Resumen de solo lectura para el mensaje de confirmación dinámico
  /// de la UI antes de pedir el motivo — ver el doc comment de
  /// `ResumenEliminacionDocumentoPorEmitir`.
  Future<ResumenEliminacionDocumentoPorEmitir> obtenerResumenEliminacionFisica(String documentoPorEmitirId);

  /// Eliminación física extraordinaria (Etapa 15, ampliada) — ver el
  /// doc comment de la implementación para las condiciones exactas de
  /// elegibilidad (único bloqueador real: `AplicacionPago` existente).
  Future<EliminarDocumentoPorEmitirFisicamenteResultado> eliminarFisicamente({
    required String documentoPorEmitirId,
    required String motivo,
    String? actorUsuarioId,
  });
}
