// Etapa 17 — reorganización visual del `concepto` de un Egreso en
// primario/secundario. Los formatos "Pago de Nómina X (Y)"/"Compra X ·
// Y" son escritos por código (`PagoNominaRepositoryImpl`/
// `CompraRepositoryImpl`), no texto libre — la información se
// reorganiza visualmente, nunca se pierde ni se inventa.

import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/features/finanzas/presentation/egresos/widgets/egreso_identidad.dart';

void main() {
  test('Egreso automático de Nómina: separa "Pago de nómina" del folio de PagoNómina y de Nómina', () {
    final identidad = identidadEgreso('Pago de Nómina PAGN-000002 (NOM-000008)');

    expect(identidad.primario, 'Pago de nómina');
    expect(identidad.secundario, 'PAGN-000002 · NOM-000008');
  });

  test('Egreso automático de Compra con proveedor: separa "Compra" del folio y el proveedor', () {
    final identidad = identidadEgreso('Compra COM-000024 · ML');

    expect(identidad.primario, 'Compra');
    expect(identidad.secundario, 'COM-000024 · ML');
  });

  test('Egreso automático de Compra sin proveedor: solo el folio como secundario', () {
    final identidad = identidadEgreso('Compra COM-000024');

    expect(identidad.primario, 'Compra');
    expect(identidad.secundario, 'COM-000024');
  });

  test('Egreso manual (texto libre que no coincide con ningún formato conocido): se muestra completo, sin secundario', () {
    final identidad = identidadEgreso('Pago de renta de la oficina de agosto');

    expect(identidad.primario, 'Pago de renta de la oficina de agosto');
    expect(identidad.secundario, isNull);
  });
}
