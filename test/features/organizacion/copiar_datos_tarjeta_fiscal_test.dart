// Etapa 16 — "Copiar datos" de la Tarjeta fiscal: función pura, nunca
// incluye un bloque cuyo valor esté vacío.

import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/features/organizacion/domain/usecases/copiar_datos_tarjeta_fiscal.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/tarjeta_fiscal_data.dart';

TarjetaFiscalData _data({
  List<String> domicilioLineas = const [],
  String? correo,
  String? telefono,
  String? sitioWeb,
}) {
  return TarjetaFiscalData(
    nombreComercial: 'Seguridad Privada RISEG',
    razonSocial: 'CORPORATIVO DE SEGURIDAD PRIVADA RIZEG SAS DE CV',
    rfc: 'CSP123456AB1',
    domicilioLineas: domicilioLineas,
    correo: correo,
    telefono: telefono,
    sitioWeb: sitioWeb,
    generadoEn: DateTime(2026, 8, 21),
  );
}

void main() {
  test('siempre incluye razón social y RFC', () {
    final texto = textoCopiarTarjetaFiscal(_data());
    expect(texto, contains('Razon social:'));
    expect(texto, contains('CORPORATIVO DE SEGURIDAD PRIVADA RIZEG SAS DE CV'));
    expect(texto, contains('RFC:'));
    expect(texto, contains('CSP123456AB1'));
  });

  test('sin domicilio, sin correo, sin teléfono, sin sitio web: ninguno de esos bloques aparece', () {
    final texto = textoCopiarTarjetaFiscal(_data());
    expect(texto, isNot(contains('Domicilio fiscal:')));
    expect(texto, isNot(contains('Correo:')));
    expect(texto, isNot(contains('Telefono:')));
    expect(texto, isNot(contains('Sitio web:')));
  });

  test('con domicilio, correo, teléfono y sitio web: los 4 bloques aparecen con su valor real', () {
    final texto = textoCopiarTarjetaFiscal(
      _data(
        domicilioLineas: const ['Valle de los Reyes 2', 'Valle del Nevado', 'Calimaya, Estado de México', 'C.P. 52224', 'México'],
        correo: 'facturacion@riseg.mx',
        telefono: '5555555555',
        sitioWeb: 'https://riseg.mx',
      ),
    );

    expect(texto, contains('Domicilio fiscal:'));
    expect(texto, contains('C.P. 52224'));
    expect(texto, contains('Correo:\nfacturacion@riseg.mx'));
    expect(texto, contains('Telefono:\n5555555555'));
    expect(texto, contains('Sitio web:\nhttps://riseg.mx'));
  });

  test('solo correo capturado (sin teléfono ni sitio web): únicamente ese bloque aparece', () {
    final texto = textoCopiarTarjetaFiscal(_data(correo: 'facturacion@riseg.mx'));

    expect(texto, contains('Correo:'));
    expect(texto, isNot(contains('Telefono:')));
    expect(texto, isNot(contains('Sitio web:')));
  });
}
