// EL CONTRATO CON EL SERVIDOR, LEÍDO CON LOS MODELOS DE VERDAD.
//
// ===========================================================================
// POR QUÉ EXISTE, Y ES UNA PANTALLA ROTA DEL 11 DE NOVIEMBRE DE 2026
// ===========================================================================
//
// D-58 añadió `createdAt` a la FICHA de un cliente (`ClientResponse`) y **no a la FILA**
// (`ClientListItemResponse`). La web lee las dos con el **mismo** constructor —
// `ClienteEnLista.deJson` llama a `Cliente.deJson`— así que leer el listado **lanzaba**, y
// **Comercial → Clientes se quedaba cargando para siempre**. Lo encontró el dueño en
// pantalla.
//
// ===========================================================================
// 🚫 POR QUÉ NINGUNA DE LAS DOS SUITES PODÍA VERLO
// ===========================================================================
//
// Porque **se mienten por separado**. Las del servidor afirman sobre **sus** respuestas;
// éstas, sobre **JSON inventado a mano** — y el inventado sí traía `createdAt`, porque lo
// escribió quien sabía que hacía falta. Dos lados verdes y el contrato roto en medio.
// **Ningún número de pruebas de un lado cierra ese hueco**: hay que cruzar.
//
// ===========================================================================
// CÓMO SE CRUZA
// ===========================================================================
//
// La suite del BACKEND arma un escenario por HTTP, pide estas rutas, normaliza lo que
// varía —ids, fechas y horas, el valor y nunca la forma— y deja el cuerpo en
// `seventra-backend/docs/contrato-web/`. Esta prueba lo lee y lo parsea **con los modelos
// que usa la aplicación**. Si el servidor deja de mandar un campo que un modelo exige,
// falla aquí y no en una pantalla.
//
// ⚠️ **Y la frescura la vigila el otro lado**: la prueba del backend FALLA si la
// instantánea guardada está vieja, así que una captura que nadie regenera no puede
// quedarse mintiendo.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:riseg_one/features/comercial/web/modelos/cliente.dart';
import 'package:riseg_one/features/comercial/web/modelos/servicio.dart';
import 'package:riseg_one/features/personal/web/modelos/empleado_elegible.dart';

/// La raíz de este repositorio, subiendo hasta encontrar `pubspec.yaml`.
Directory _raiz() {
  var directorio = Directory.current;

  while (!File('${directorio.path}/pubspec.yaml').existsSync()) {
    final padre = directorio.parent;

    if (padre.path == directorio.path) {
      fail('No se encontró la raíz del repositorio (pubspec.yaml).');
    }

    directorio = padre;
  }

  return directorio;
}

void main() {
  final carpeta = Directory(
    '${_raiz().parent.path}/seventra-backend/docs/contrato-web',
  );

  /// Lee una instantánea, o salta diciéndolo.
  ///
  /// ⚠️ **SE SALTA Y LO DICE**, nunca pasa en silencio: un guardia que no encuentra lo
  /// que vigila y contesta «verde» enseña a confiar en una comprobación que no ocurrió.
  Object? instantanea(String archivo) {
    final f = File('${carpeta.path}/$archivo');

    if (!f.existsSync()) {
      markTestSkipped(
        'No se encontró «${f.path}». Las instantáneas del contrato las genera la suite '
        'del BACKEND (ContratoConLaWebTests), así que esto sólo se puede comprobar con '
        'los dos repositorios al lado.',
      );

      return null;
    }

    return jsonDecode(f.readAsStringSync());
  }

  group('el contrato con el servidor se lee con los modelos de la aplicación', () {
    test('el LISTADO de clientes — el que se rompió', () {
      final json = instantanea('clientes-listado.json');
      if (json == null) return;

      final pagina = PaginaDeClientes.deJson(json as Map<String, dynamic>);

      // ⚠️ **UNA FILA AL MENOS**, y no es un detalle: con `items` vacío esto parsearía
      // perfectamente sin leer un solo campo de un cliente, que es justo lo que había
      // que comprobar. Una instantánea vacía no vigila nada.
      expect(pagina.clientes, isNotEmpty);

      final cliente = pagina.clientes.first.cliente;

      // Y LAS DOS FECHAS, que es el campo concreto que faltaba (D-58 / D-74).
      expect(cliente.creadoEn, isA<DateTime>());
      expect(cliente.inicioDeLaRelacion, isNotNull);
      expect(cliente.codigo, isNotEmpty);
    });

    test('la FICHA de un cliente', () {
      final json = instantanea('clientes-ficha.json');
      if (json == null) return;

      final cliente = Cliente.deJson(json as Map<String, dynamic>);

      expect(cliente.creadoEn, isA<DateTime>());
      expect(cliente.actualizadoEn, isA<DateTime>());
      expect(cliente.estado, isNotNull);
    });

    test('los indicadores de un cliente', () {
      final json = instantanea('clientes-indicadores.json');
      if (json == null) return;

      final i = IndicadoresDeCliente.deJson(json as Map<String, dynamic>);

      expect(i.serviciosActivos, isNonNegative);
    });

    test('el LISTADO de servicios', () {
      final json = instantanea('servicios-listado.json');
      if (json == null) return;

      final pagina = PaginaDeServicios.deJson(json as Map<String, dynamic>);

      expect(pagina.servicios, isNotEmpty);

      final fila = pagina.servicios.first;

      expect(fila.clienteNombreComercial, isNotEmpty);

      // LA CONDICIÓN TEMPORAL TIENE QUE SER UNA QUE LA WEB RECONOZCA. Si el servidor
      // mandara un código nuevo, `deCodigo` devolvería nulo y la insignia desaparecería
      // sin que nada fallara — por eso se afirma aquí y no en la pantalla.
      expect(CondicionTemporal.deCodigo(fila.condicionTemporal), isNotNull);
      expect(EstatusDeServicio.deCodigo(fila.estatus), isNotNull);
    });

    test('la FICHA de un servicio', () {
      final json = instantanea('servicios-ficha.json');
      if (json == null) return;

      final servicio = Servicio.deJson(json as Map<String, dynamic>);

      expect(servicio.creadoEn, isA<DateTime>());
      expect(servicio.estado, isNotNull);
      expect(CondicionTemporal.deCodigo(servicio.condicionTemporal), isNotNull);
    });

    test('los indicadores de un servicio', () {
      final json = instantanea('servicios-indicadores.json');
      if (json == null) return;

      final i = IndicadoresDeServicio.deJson(json as Map<String, dynamic>);

      expect(i.antiguedadEnMeses, isNonNegative);
    });

    test('el supervisor de un servicio', () {
      final json = instantanea('servicios-supervisor.json');
      if (json == null) return;

      final s = SupervisorDelServicio.deJson(json as Map<String, dynamic>);

      expect(s.nombreCompleto, isNotEmpty);
      expect(s.numeroDeEmpleado, isPositive);
    });

    test('el catálogo de tipos de servicio', () {
      final json = instantanea('tipos-de-servicio.json');
      if (json == null) return;

      final tipos = [
        for (final t in json as List) TipoDeServicio.deJson(t as Map<String, dynamic>),
      ];

      expect(tipos, isNotEmpty);
      expect(tipos.first.codigo, isNotEmpty);
    });

    test('los empleados, que son de OTRO módulo y se leen igual', () {
      // El selector del supervisor lee `GET /employees`, que es de Personal y exige
      // `personal.read`. Su forma también es un contrato aunque Personal no esté mudado.
      final json = instantanea('empleados.json');
      if (json == null) return;

      final sobre = json as Map<String, dynamic>;
      final empleados = [
        for (final e in sobre['items'] as List)
          EmpleadoElegible.deJson(e as Map<String, dynamic>),
      ];

      expect(empleados, isNotEmpty);
      expect(empleados.first.nombreCompleto, isNotEmpty);
      expect(empleados.first.enPantalla, contains('·'));
    });
  });
}
