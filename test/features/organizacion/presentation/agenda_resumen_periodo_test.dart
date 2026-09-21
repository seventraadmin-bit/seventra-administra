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
    final resumen = calcularResumenPeriodoAgenda([
      _doc(estatus: 'pendiente', importeFinalEsperado: 100000),
      _doc(estatus: 'cancelado', importeFinalEsperado: 999999),
      _doc(estatus: 'noRequerido', importeFinalEsperado: 999999),
      _doc(estatus: 'procesadoAceptado', importeFinalEsperado: 50000),
    ], hoy);

    expect(resumen.importeEsperado, 150000);
  });

  test('lista vacía produce un resumen en ceros, nunca un error', () {
    final resumen = calcularResumenPeriodoAgenda([], hoy);

    expect(resumen.porEmitir, 0);
    expect(resumen.porVencerHoy, 0);
    expect(resumen.enviados, 0);
    expect(resumen.procesados, 0);
    expect(resumen.importeEsperado, 0);
  });
}
