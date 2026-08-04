import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/validation/direccion_validator.dart';

void main() {
  test('dirección completamente vacía es válida y no crea nada', () {
    final r = DireccionValidator.validar(const DireccionBorrador());
    expect(r.resultado, isNull);
    expect(r.errores, isEmpty);
  });

  test('dirección completa válida se normaliza (recorte, país)', () {
    final r = DireccionValidator.validar(
      const DireccionBorrador(
        calle: '  Reforma  ',
        numeroExterior: '123',
        colonia: 'Centro',
        municipioAlcaldia: 'Cuauhtémoc',
        estado: 'CDMX',
        codigoPostal: '06000',
      ),
    );
    expect(r.errores, isEmpty);
    expect(r.resultado!.calle, 'Reforma');
    expect(r.resultado!.pais, 'México');
  });

  test('dirección parcial reporta todos los campos requeridos faltantes de una vez', () {
    final r = DireccionValidator.validar(const DireccionBorrador(colonia: 'Centro'));
    expect(r.resultado, isNull);
    final campos = r.errores.map((e) => e.campo).toSet();
    expect(
      campos,
      containsAll({
        CampoDireccion.calle,
        CampoDireccion.numeroExterior,
        CampoDireccion.municipioAlcaldia,
        CampoDireccion.estado,
        CampoDireccion.codigoPostal,
      }),
    );
  });

  test('código postal mexicano debe tener exactamente 5 dígitos', () {
    final r = DireccionValidator.validar(
      const DireccionBorrador(
        calle: 'Reforma',
        numeroExterior: '123',
        colonia: 'Centro',
        municipioAlcaldia: 'Cuauhtémoc',
        estado: 'CDMX',
        codigoPostal: '123',
      ),
    );
    expect(r.resultado, isNull);
    expect(
      r.errores,
      contains(
        predicate<ErrorCampoDireccion>(
          (e) => e.campo == CampoDireccion.codigoPostal && e.codigo == CodigoErrorCampoDireccion.formatoInvalido,
        ),
      ),
    );
  });

  test('la regla de 5 dígitos no aplica si el país no es México', () {
    final r = DireccionValidator.validar(
      const DireccionBorrador(
        calle: 'Main St',
        numeroExterior: '1',
        colonia: 'Centro',
        municipioAlcaldia: 'Austin',
        estado: 'TX',
        codigoPostal: '123',
        pais: 'Estados Unidos',
      ),
    );
    expect(r.errores, isEmpty);
    expect(r.resultado!.codigoPostal, '123');
  });

  test('errorParaCampoDireccion encuentra el error del campo pedido', () {
    final r = DireccionValidator.validar(const DireccionBorrador(colonia: 'Centro'));
    final error = errorParaCampoDireccion(r.errores, CampoDireccion.calle);
    expect(error, isNotNull);
    expect(error!.codigo, CodigoErrorCampoDireccion.requerido);
    expect(errorParaCampoDireccion(r.errores, CampoDireccion.colonia), isNull);
  });
}
