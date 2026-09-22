/// Último recurso para que NINGÚN identificador técnico llegue a la
/// pantalla tal cual.
///
/// Los valores de `accion` son heterogéneos a propósito (tipos de evento,
/// tipos de movimiento, orígenes de kilometraje…) y cada dominio traduce
/// los suyos con su propio catálogo. Esto NO sustituye esos catálogos: se
/// aplica sólo cuando ninguno reconoció el valor, para que un tipo nuevo o
/// heredado se lea como texto y no como `correccionDatosEmision`.
///
/// Deliberadamente mecánico: separa palabras y pone mayúscula inicial. No
/// inventa nombres de negocio —convertir `emisionRegistrada` en "Emisión
/// registrada" es cierto; convertirlo en "Factura timbrada" sería una
/// afirmación que nadie escribió—.
///
/// El valor persistido no cambia nunca: esto es presentación.
String humanizarAccionAuditoria(String accion) {
  if (accion.isEmpty) return accion;

  // Un valor compuesto (`eliminacionFisica:documentoPorEmitir`) se humaniza
  // por partes para que tampoco asome el tipo técnico de la derecha.
  if (accion.contains(':')) {
    final partes = accion.split(':');
    return partes.map(humanizarAccionAuditoria).join(' — ');
  }

  final conEspacios = accion
      .replaceAll('_', ' ')
      .replaceAllMapped(RegExp(r'([a-z0-9])([A-Z])'), (m) => '${m[1]} ${m[2]}')
      .trim();
  if (conEspacios.isEmpty) return accion;

  // Sólo la primera en mayúscula: el resto son palabras corrientes, y
  // capitalizarlas todas produciría el "Título De Cada Palabra" que no usa
  // ninguna otra pantalla del proyecto.
  final minusculas = conEspacios[0].toUpperCase() + conEspacios.substring(1).toLowerCase();
  return minusculas;
}

/// Nombres de negocio de los eventos de un `DocumentoPorEmitir`.
///
/// Existen como catálogo y no confiando en [humanizarAccionAuditoria] por
/// una razón concreta: el valor persistido no lleva acentos ni orden
/// natural, así que humanizarlo da "Correccion datos emision". El catálogo
/// dice lo que la operación ES; el humanizador sólo evita que un valor
/// desconocido se vea como código.
///
/// Las claves son los valores YA persistidos (`TipoEventoDocumentoPorEmitir`),
/// que no se tocan: esto es presentación.
const _accionesComercial = <String, String>{
  'creadoAutomatico': 'Generado automáticamente',
  'creadoManual': 'Creado manualmente',
  'marcadoEnPreparacion': 'Marcado en preparación',
  'ajusteRegistrado': 'Ajuste de facturación registrado',
  'correccionAjusteHistorico': 'Ajuste histórico corregido',
  'emisionRegistrada': 'Emisión registrada',
  'correccionDatosEmision': 'Datos de emisión corregidos',
  'archivoAdjuntado': 'Archivo adjuntado',
  'archivoReemplazado': 'Archivo reemplazado',
  'envioRegistrado': 'Envío registrado',
  'correccionEnviadoAEmitido': 'Corregido de Enviado a Emitido',
  'procesadoAceptado': 'Procesado/Aceptado',
  'cancelado': 'Cancelado',
  'marcadoNoRequerido': 'Marcado como no requerido',
  'edicionObservaciones': 'Observaciones editadas',
};

/// Etiqueta de una acción del módulo Comercial, o `null` si no es una de
/// las suyas — el llamador sigue con su propia cadena de catálogos.
String? accionComercialLabel(String accion) => _accionesComercial[accion];
