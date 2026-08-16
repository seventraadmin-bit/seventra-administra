import 'package:riseg_one/core/database/app_database.dart';

import '../../data/tables/configuracion_cobro_vigencia_table.dart';
import 'documento_por_emitir_detalle.dart';

const _tratamientoIvaLabel = {
  'masIva': 'Más IVA',
  'ivaIncluido': 'IVA incluido',
  'noAplica': 'No aplica',
};

const _metodoLabel = {'pue': 'PUE', 'ppd': 'PPD'};

/// Reúne y traduce todos los datos del recibo a partir del expediente
/// ya cargado — función pura, sin E/S, separada del use case
/// orquestador (`GenerarReciboPagoPdfUseCase`) exactamente por lo mismo
/// que `construirFichaTecnicaData`: probable de forma aislada, sin
/// necesitar una base de datos real ni generar un PDF de verdad. Nunca
/// calcula un monto de IVA en pesos (el sistema no guarda una tasa real
/// en ningún lado) — solo traduce la clasificación de cada línea.
ReciboPagoPdfData construirReciboPagoPdfData({
  required DocumentoPorEmitirDetalle detalle,
  required ClienteData? cliente,
  required List<String> servicios,
  required EmpresaData empresa,
  MedioContactoData? contacto,
}) {
  final documento = detalle.documento;
  final metodo = MetodoPagoCobro.values.byName(documento.metodo);

  return ReciboPagoPdfData(
    folio: documento.codigo,
    fechaEmision: documento.fechaEmisionReal ?? documento.fechaEmisionProgramada ?? DateTime.now(),
    empresaNombreComercial: empresa.nombreComercial,
    empresaRfc: empresa.rfc,
    empresaTelefono: contacto?.telefono,
    empresaCorreo: contacto?.correo,
    empresaSitioWeb: contacto?.sitioWeb,
    // Guion simple, nunca em-dash: el Helvetica base del paquete `pdf`
    // no tiene ese glifo (Etapa 15, hallazgo real).
    clienteCodigo: cliente?.codigo ?? '-',
    clienteNombreComercial: cliente?.nombreComercial ?? '-',
    servicios: servicios,
    periodoInicio: documento.periodoInicio,
    periodoFin: documento.periodoFin,
    lineas: [
      for (final l in detalle.lineas)
        ReciboPagoPdfLinea(
          puestoNombre: l.puestoNombre,
          modalidadTurnoNombre: l.modalidadTurnoNombre,
          cantidadElementos: l.cantidadElementos,
          precioUnitario: l.precioUnitario,
          tratamientoIvaLabel: _tratamientoIvaLabel[l.tratamientoIva] ?? l.tratamientoIva,
          subtotalProporcional: l.subtotalProporcional,
        ),
    ],
    importeBaseEsperado: documento.importeBaseEsperado,
    ajusteManual: documento.ajusteManual,
    importeFinalEsperado: documento.importeFinalEsperado,
    metodoLabel: metodo == MetodoPagoCobro.noAplica ? null : _metodoLabel[documento.metodo],
    observaciones: documento.observaciones,
  );
}

/// Una línea comercial ya snapshot en el `DocumentoPorEmitir` — lista
/// para imprimir, sin volver a resolver nada contra la BD (Etapa 15).
class ReciboPagoPdfLinea {
  const ReciboPagoPdfLinea({
    required this.puestoNombre,
    required this.modalidadTurnoNombre,
    required this.cantidadElementos,
    required this.precioUnitario,
    required this.tratamientoIvaLabel,
    required this.subtotalProporcional,
  });

  final String puestoNombre;
  final String modalidadTurnoNombre;
  final int cantidadElementos;
  final int precioUnitario;

  /// Ya traducido a texto legible (`+IVA`/`IVA incluido`/`No aplica`) —
  /// el renderer nunca decide esa traducción por sí mismo. No se
  /// calcula ningún monto de IVA en pesos: el sistema nunca ha guardado
  /// una tasa ni un importe de IVA como dato real, así que mostrarlo
  /// sería inventarlo — solo se imprime la clasificación.
  final String tratamientoIvaLabel;
  final int subtotalProporcional;
}

/// Todos los datos, ya reunidos y traducidos, para imprimir el recibo
/// de pago administrativo de un `DocumentoPorEmitir` con `tipoDocumento
/// == reciboDePago` (Etapa 15) — puro respecto a E/S, igual criterio
/// que `FichaTecnicaData`: el use case orquestador reúne todo esto
/// antes de invocar al renderer, que nunca lee de BD ni de disco por sí
/// mismo (salvo los bytes ya resueltos de imágenes).
class ReciboPagoPdfData {
  const ReciboPagoPdfData({
    required this.folio,
    required this.fechaEmision,
    required this.empresaNombreComercial,
    required this.clienteCodigo,
    required this.clienteNombreComercial,
    required this.servicios,
    required this.periodoInicio,
    required this.periodoFin,
    required this.lineas,
    required this.importeBaseEsperado,
    required this.ajusteManual,
    required this.importeFinalEsperado,
    this.empresaRfc,
    this.empresaTelefono,
    this.empresaCorreo,
    this.empresaSitioWeb,
    this.metodoLabel,
    this.observaciones,
  });

  final String folio;
  final DateTime fechaEmision;

  final String empresaNombreComercial;

  /// Solo si corresponde — el RFC de Empresa es opcional en el sistema
  /// (nunca se inventa uno para completar el encabezado).
  final String? empresaRfc;
  final String? empresaTelefono;
  final String? empresaCorreo;
  final String? empresaSitioWeb;

  final String clienteCodigo;
  final String clienteNombreComercial;

  /// `"código - nombre"` (guion simple, no em-dash — ver el hallazgo de
  /// fuente en el use case orquestador) por cada Servicio incluido — ya
  /// resueltos contra `ServicioRepository`, nunca ids crudos.
  final List<String> servicios;

  final DateTime periodoInicio;
  final DateTime periodoFin;

  final List<ReciboPagoPdfLinea> lineas;

  final int importeBaseEsperado;
  final int? ajusteManual;
  final int importeFinalEsperado;

  /// Ya traducido; `null` cuando el método es `noAplica` (el caso
  /// normal de un recibo) — "método de pago cuando aplique", nunca una
  /// fila vacía.
  final String? metodoLabel;

  final String? observaciones;
}
