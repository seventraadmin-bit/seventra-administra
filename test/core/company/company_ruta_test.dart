// Integration Foundation IF-3 — el constructor de rutas con Company.
//
// Es una pieza minúscula con una responsabilidad grande: que el prefijo dinámico
// `/companies/{companyId}` tenga UN dueño. Si cada repositorio lo interpolara a
// mano, bastaría una barra de más para producir un 404 indistinguible de «no tienes
// acceso a esa empresa», y ese 404 se depura muy mal.

import 'package:flutter_test/flutter_test.dart';
import 'package:riseg_one/core/company/company_ruta.dart';

void main() {
  const companyId = '0193f0a0-0000-7000-8000-000000000001';

  group('Composición', () {
    test('compone la ruta con la empresa y sin barra doble', () {
      expect(
        CompanyRuta.de(companyId, '/context'),
        '/companies/$companyId/context',
      );
      expect(
        CompanyRuta.de(companyId, '/employees'),
        '/companies/$companyId/employees',
      );
    });

    test('conserva subrutas con varios segmentos', () {
      expect(
        CompanyRuta.de(companyId, '/clients/abc/contracts'),
        '/companies/$companyId/clients/abc/contracts',
      );
    });

    test('es RELATIVA: el prefijo de versión no es suyo', () {
      // `/api/v1` sigue siendo de `ApiConfig`. Dos prefijos, dos dueños, cada uno
      // en su capa.
      expect(CompanyRuta.de(companyId, '/context'), startsWith('/companies/'));
      expect(CompanyRuta.de(companyId, '/context'), isNot(contains('/api/')));
    });

    test('la colección NO es scoped y se expone aparte', () {
      // `GET /companies` es la lista de empresas que hay, no una operación dentro
      // de una: pedirle a este constructor una ruta sin empresa sería forzarlo a
      // representar algo que no es.
      expect(CompanyRuta.coleccion, '/companies');
    });
  });

  group('Un companyId que no es un identificador se rechaza', () {
    void esRechazado(String id, {required String porque}) => expect(
      () => CompanyRuta.de(id, '/context'),
      throwsArgumentError,
      reason: porque,
    );

    test('vacío', () => esRechazado('', porque: 'no hay empresa'));

    test(
      'no es un GUID',
      () => esRechazado('empresa-uno', porque: 'el backend restringe a :guid'),
    );

    test('con barra dentro', () {
      // Sin esta comprobación, `de('a/b', '/context')` inyectaría un segmento.
      esRechazado('$companyId/otra', porque: 'inyectaría un segmento de ruta');
    });

    test('con espacios o salto de línea', () {
      esRechazado(' $companyId ', porque: 'no está normalizado');
      esRechazado('$companyId\n', porque: 'no está normalizado');
    });

    test('con consulta pegada', () {
      esRechazado('$companyId?x=1', porque: 'la consulta no va en el id');
    });

    test('un GUID truncado', () {
      esRechazado('0193f0a0-0000-7000-8000', porque: 'GUID incompleto');
    });

    test('acepta mayúsculas: un GUID es un GUID', () {
      expect(
        CompanyRuta.de(companyId.toUpperCase(), '/context'),
        '/companies/${companyId.toUpperCase()}/context',
      );
    });
  });

  group('Una ruta mal formada se rechaza', () {
    test('sin barra inicial', () {
      expect(() => CompanyRuta.de(companyId, 'context'), throwsArgumentError);
    });

    test('vacía', () {
      expect(() => CompanyRuta.de(companyId, ''), throwsArgumentError);
    });

    test('con el prefijo de empresa ya puesto', () {
      // `de(id, '/companies/x')` produciría `/companies/{id}/companies/x`. Es el
      // mismo tropiezo que el prefijo de versión, con el mismo remedio: rechazarlo
      // aquí en vez de depurar el 404.
      expect(
        () => CompanyRuta.de(companyId, '/companies/otra'),
        throwsArgumentError,
      );
      expect(
        () => CompanyRuta.de(companyId, '/companies'),
        throwsArgumentError,
      );
    });
  });

  test('NO existe ningún encabezado de empresa', () {
    // La empresa viaja en la RUTA. El backend lo dice en su propio código: no hay
    // `currentCompanyId` en el servidor, y dos peticiones simultáneas pueden
    // trabajar empresas distintas porque cada una trae la suya.
    expect(CompanyRuta.de(companyId, '/context'), contains(companyId));
  });
}
