import 'package:riseg_one/features/organizacion/data/tables/documento_por_emitir_table.dart';

String _soloFechaIso(DateTime dt) =>
    '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

/// Clave determinista de generación (Etapa 4I.1) — protege la
/// idempotencia real cuando un documento agrupado puede depender de
/// varias vigencias de cobro a la vez, así que un `UNIQUE` simple sobre
/// una sola vigencia + periodo no alcanza. Calculada a partir de
/// exactamente los mismos insumos que determinan "es el mismo
/// documento": tipo de agrupación, Cliente, Entidad fiscal, el conjunto
/// ordenado de Servicios, el conjunto ordenado de vigencias de cobro,
/// el periodo y el tipo de documento — nunca del `id` de nada generado
/// (esos cambian cada vez).
///
/// Los conjuntos se ordenan antes de concatenar para que el mismo grupo
/// de Servicios/vigencias produzca la misma clave sin importar el orden
/// en que se hayan resuelto.
/// Posición del segmento de vigencias dentro de la `generationKey`.
const _indiceVigencias = 4;

/// La identidad **comercial** de un documento: la misma clave técnica
/// sin el segmento de vigencias.
///
/// Dos documentos con la misma clave comercial representan el mismo
/// hecho de negocio —este cliente, esta entidad fiscal, estos
/// servicios, este periodo, este tipo y esta agrupación— aunque los
/// haya originado una configuración de cobro distinta.
///
/// Existe por un caso real: crear una vigencia retroactiva cambia la
/// `generationKey` de periodos que YA se facturaron, así que la
/// idempotencia técnica no los reconocía y la Agenda volvía a pedir
/// emitir agosto (Morgan, DOC-000040 duplicando a DOC-000035). La
/// clave técnica sigue sirviendo para lo suyo —no repetir dentro de la
/// misma configuración—; ésta responde una pregunta distinta: ¿este
/// periodo comercial ya está materializado?
///
/// Se deriva de la clave en vez de recomponerse para que nunca puedan
/// divergir: si mañana se agrega una dimensión a [calcularGenerationKey],
/// entra sola en la identidad comercial.
String claveComercialDeGenerationKey(String generationKey) {
  final partes = generationKey.split('|');
  if (partes.length <= _indiceVigencias) return generationKey;
  return (partes..removeAt(_indiceVigencias)).join('|');
}

/// `true` si un documento en ese estatus deja libre su periodo
/// comercial, de modo que pueda volver a agendarse o capturarse.
///
/// Qué bloquea y qué no, según lo que el estatus significa:
///
///  * `pendiente`/`enPreparacion` -> ya está agendado; otro igual
///    sería pedir dos veces lo mismo.
///  * `emitido`/`enviado`/`procesadoAceptado` -> ya se materializó;
///    puede tener una Cuenta por cobrar real detrás.
///  * `cancelado`/`noRequerido` -> NO bloquean: cancelar una
///    programación equivocada es precisamente lo que abre la puerta a
///    que después exista la correcta.
bool liberaElPeriodoComercial(String estatus) {
  final valor = EstatusDocumentoPorEmitir.values.where((e) => e.name == estatus).firstOrNull;
  return valor == EstatusDocumentoPorEmitir.cancelado ||
      valor == EstatusDocumentoPorEmitir.noRequerido;
}

String calcularGenerationKey({
  required String agrupacion,
  required String tipoDocumento,
  required String clienteId,
  required List<String> servicioIds,
  required List<String> configuracionCobroVigenciaIds,
  required DateTime periodoInicio,
  required DateTime periodoFin,
  String? entidadFiscalId,
}) {
  final servicios = [...servicioIds]..sort();
  final vigencias = [...configuracionCobroVigenciaIds]..sort();

  return [
    agrupacion,
    clienteId,
    entidadFiscalId ?? '',
    servicios.join(','),
    vigencias.join(','),
    _soloFechaIso(periodoInicio),
    _soloFechaIso(periodoFin),
    tipoDocumento,
  ].join('|');
}
