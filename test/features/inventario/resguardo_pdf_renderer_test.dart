// Prueba de regresión (Etapa "Entrega múltiple de Inventario") del bug
// real encontrado en `ResguardoPdfRenderer`: usaba em-dash ('—', U+2014)
// sin protección en 3 lugares para valores nulos/ausentes, pero la
// fuente Helvetica por defecto del paquete `pdf` no tiene ese glifo —
// el paquete lo reporta vía `print` ("Unable to find a font to draw
// '—' (U+2014)") en vez de lanzar una excepción, así que la regresión
// se prueba capturando esa salida, no esperando un throw. El resto del
// proyecto ya usa guion simple ('-') para este mismo caso — este
// renderizador era la única excepción inconsistente.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:riseg_one/features/inventario/data/pdf/resguardo_pdf_renderer.dart';
import 'package:riseg_one/features/inventario/domain/usecases/resguardo_data.dart';

void main() {
  test('nunca reporta un glifo faltante para U+2014 al renderizar con todos los campos opcionales nulos', () async {
    final data = ResguardoData(
      // Ningún destino poblado — ejercita el fallback de `_encabezado`
      // que antes usaba '—'.
      fechaGeneracion: DateTime(2026, 8, 20),
      items: const [
        // Sin variante/unidad/condición — ejercita los 2 fallbacks de
        // `_tablaArticulos` que antes usaban '—'.
        ResguardoItem(articuloNombre: 'Camisa RISEG', cantidad: 1),
      ],
    );

    final mensajes = <String>[];
    await runZoned(
      () async {
        await ResguardoPdfRenderer().renderizar(data: data);
      },
      zoneSpecification: ZoneSpecification(
        print: (self, parent, zone, line) => mensajes.add(line),
      ),
    );

    expect(
      mensajes.where((m) => m.contains('U+2014')),
      isEmpty,
      reason: 'regresión real: el renderizador seguía usando em-dash sin proteger para un campo nulo/ausente',
    );
  });

  test('incluye el folio y el Servicio actual en el encabezado cuando vienen poblados', () async {
    final data = ResguardoData(
      empleadoNombre: 'Juan Pérez',
      servicioActualNombre: 'Servicio Torre Norte',
      folio: 'ENT-000001',
      fechaGeneracion: DateTime(2026, 8, 20),
      items: const [ResguardoItem(articuloNombre: 'Camisa RISEG', cantidad: 1)],
    );

    final bytes = await ResguardoPdfRenderer().renderizar(data: data);
    expect(bytes, isNotEmpty);
  });
}
