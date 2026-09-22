// Etapa 16 — resumen del periodo en la Agenda (KPIs: Por emitir | Por
// vencer/para hoy | Enviados | Procesados | Importe esperado), función
// pura agregada en memoria sobre `AgendaState.documentos` ya cargado.

import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/organizacion/presentation/agenda/agenda_resumen_periodo.dart';

DocumentoPorEmitirData _doc({
  required String estatus,
  DateTime? fechaEmisionProgramada,
  int importeFinalEsperado = 100000,
}) {
  final ahora = DateTime(2026, 8, 1);
  return DocumentoPorEmitirData(
    id: 'doc-${estatus}_${fechaEmisionProgramada?.millisecondsSinceEpoch}_$importeFinalEsperado',
    createdAt: ahora,
    updatedAt: ahora,
    cicloVidaRegistro: 'activo',
    codigo: 'DOC-0001',
    clienteId: 'cliente-1',
    tipoDocumento: 'cfdi',
    agrupacion: 'porServicio',
    metodo: 'pue',
    requiereComplemento: false,
    periodoInicio: DateTime(2026, 8, 1),
    periodoFin: DateTime(2026, 8, 31),
    fechaEmisionProgramada: fechaEmisionProgramada,
    generationKey: 'gen-${estatus}_${fechaEmisionProgramada?.millisecondsSinceEpoch}_$importeFinalEsperado',
    importeBaseEsperado: importeFinalEsperado,
    importeFinalEsperado: importeFinalEsperado,
    estatus: estatus,
  );
}

void main() {
  final hoy = DateTime(2026, 8, 20);

  test('cuenta pendiente/enPreparacion como "por emitir"', () {
    final resumen = calcularResumenPeriodoAgenda([
      _doc(estatus: 'pendiente'),
      _doc(estatus: 'enPreparacion', importeFinalEsperado: 50000),
      _doc(estatus: 'emitido'),
    ], hoy);

    expect(resumen.porEmitir, 2);
  });

  test('"por vencer/para hoy" incluye hoy y fechas pasadas, nunca futuras', () {
    final resumen = calcularResumenPeriodoAgenda([
      _doc(estatus: 'pendiente', fechaEmisionProgramada: hoy),
      _doc(estatus: 'pendiente', fechaEmisionProgramada: hoy.subtract(const Duration(days: 3))),
      _doc(estatus: 'pendiente', fechaEmisionProgramada: hoy.add(const Duration(days: 3))),
      _doc(estatus: 'pendiente'),
    ], hoy);

    expect(resumen.porVencerHoy, 2);
  });

  test('un documento emitido con fecha pasada no cuenta como "por vencer" (ya no es accionable)', () {
    final resumen = calcularResumenPeriodoAgenda([
      _doc(estatus: 'emitido', fechaEmisionProgramada: hoy.subtract(const Duration(days: 10))),
    ], hoy);

    expect(resumen.porVencerHoy, 0);
  });

  test('cuenta enviados y procesados por separado', () {
    final resumen = calcularResumenPeriodoAgenda([
      _doc(estatus: 'enviado'),
      _doc(estatus: 'enviado'),
      _doc(estatus: 'procesadoAceptado'),
    ], hoy);

    expect(resumen.enviados, 2);
    expect(resumen.procesados, 1);
  });

  test('importe esperado excluye cancelado y noRequerido', () {
    final pendiente = _doc(estatus: 'pendiente', importeFinalEsperado: 100000);
    final cancelado = _doc(estatus: 'cancelado', importeFinalEsperado: 999999);
    final noRequerido = _doc(estatus: 'noRequerido', importeFinalEsperado: 999999);
    final procesado = _doc(estatus: 'procesadoAceptado', importeFinalEsperado: 50000);

    // El KPI suma TOTALES esperados (ya con su IVA), no el facturable: por
    // eso recibe el mapa que el controlador calculó con la decisión fiscal
    // única, en vez de leer `importeFinalEsperado` de cada documento.
    final resumen = calcularResumenPeriodoAgenda(
      [pendiente, cancelado, noRequerido, procesado],
      hoy,
      totalEsperadoPorDocumento: {
        pendiente.id: 116000,
        cancelado.id: 999999,
        noRequerido.id: 999999,
        procesado.id: 58000,
      },
    );

    expect(resumen.importeEsperado, 174000);
    expect(resumen.documentosSinTotalCalculable, 0);
  });

  test('un documento sin total comparable no se suma y se reporta aparte', () {
    final calculable = _doc(estatus: 'pendiente', importeFinalEsperado: 100000);
    final ambiguo = _doc(estatus: 'pendiente', importeFinalEsperado: 999999, fechaEmisionProgramada: hoy);

    final resumen = calcularResumenPeriodoAgenda(
      [calculable, ambiguo],
      hoy,
      // `ambiguo` no está en el mapa: es un mixto con ajuste, cuyo total no
      // es fiscalmente atribuible.
      totalEsperadoPorDocumento: {calculable.id: 116000},
    );

    expect(resumen.importeEsperado, 116000, reason: 'nunca se estima el faltante');
    expect(resumen.documentosSinTotalCalculable, 1);
  });

  test('los cancelados no cuentan como no calculables: sencillamente no se cobran', () {
    final cancelado = _doc(estatus: 'cancelado');

    final resumen = calcularResumenPeriodoAgenda([cancelado], hoy);

    expect(resumen.importeEsperado, 0);
    expect(resumen.documentosSinTotalCalculable, 0);
  });

  test('lista vacía produce un resumen en ceros, nunca un error', () {
    final resumen = calcularResumenPeriodoAgenda([], hoy);

    expect(resumen.porEmitir, 0);
    expect(resumen.porVencerHoy, 0);
    expect(resumen.enviados, 0);
    expect(resumen.procesados, 0);
    expect(resumen.importeEsperado, 0);
    expect(resumen.documentosSinTotalCalculable, 0);
  });
}
