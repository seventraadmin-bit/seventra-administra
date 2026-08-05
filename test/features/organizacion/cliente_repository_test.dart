import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/tables/direccion_table.dart';
import 'package:riseg_one/features/organizacion/data/repositories/cliente_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/tables/cliente_table.dart';
import 'package:riseg_one/features/organizacion/domain/shared/direccion_input.dart';

const _direccionDemo = DireccionInput(
  calle: 'Av. Reforma',
  numeroExterior: '100',
  colonia: 'Juárez',
  municipioAlcaldia: 'Cuauhtémoc',
  estado: 'CDMX',
  codigoPostal: '06600',
);

void main() {
  late AppDatabase db;
  late ClienteRepositoryImpl repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = ClienteRepositoryImpl(db);
  });

  tearDown(() => db.close());

  Future<ClienteData> crearClienteDePrueba() {
    return repo.crear(ClienteCompanion.insert(codigo: 'CLI-000001', nombreComercial: 'Sportium'));
  }

  test('cambiarEstatus actualiza el estatus comercial sin tocar cicloVidaRegistro', () async {
    final cliente = await crearClienteDePrueba();
    final actualizado = await repo.cambiarEstatus(id: cliente.id, nuevo: EstatusCliente.activo);

    expect(actualizado.estatus, 'activo');
    expect(actualizado.cicloVidaRegistro, 'activo');
  });

  test('guardarExpediente persiste datos generales y crea la dirección de referencia', () async {
    final cliente = await crearClienteDePrueba();

    final resultado = await repo.guardarExpediente(
      clienteId: cliente.id,
      datosGenerales: const ClienteCompanion(nombreComercial: Value('Sportium Renombrado')),
      direccionReferencia: _direccionDemo,
    );

    expect(resultado.cliente.nombreComercial, 'Sportium Renombrado');
    expect(resultado.direccionReferencia, isNotNull);
    expect(resultado.direccionReferencia!.calle, 'Av. Reforma');
    expect(resultado.direccionReferencia!.tipoDireccion, TipoDireccion.referencia.name);
  });

  test('guardarExpediente reactiva y actualiza una dirección de referencia archivada en vez de duplicarla', () async {
    final cliente = await crearClienteDePrueba();

    await repo.guardarExpediente(
      clienteId: cliente.id,
      datosGenerales: const ClienteCompanion(nombreComercial: Value('Sportium')),
      direccionReferencia: _direccionDemo,
    );
    // Vacía la sección: la dirección debe archivarse, no borrarse.
    await repo.guardarExpediente(
      clienteId: cliente.id,
      datosGenerales: const ClienteCompanion(nombreComercial: Value('Sportium')),
      direccionReferencia: null,
    );

    final archivada = await repo.obtenerDireccionReferencia(cliente.id);
    expect(archivada, isNull, reason: 'obtenerDireccionReferencia solo devuelve direcciones activas');

    // Recapturarla no debe intentar un segundo INSERT.
    final resultado = await repo.guardarExpediente(
      clienteId: cliente.id,
      datosGenerales: const ClienteCompanion(nombreComercial: Value('Sportium')),
      direccionReferencia: _direccionDemo,
    );
    expect(resultado.direccionReferencia, isNotNull);

    final todasLasDirecciones = await db.select(db.direccion).get();
    expect(todasLasDirecciones, hasLength(1), reason: 'nunca debe quedar una segunda fila de dirección');
  });

  test('agregarContacto con esPrincipal retira el principal anterior del mismo tipo', () async {
    final cliente = await crearClienteDePrueba();

    final primero = await repo.agregarContacto(
      ContactoCompanion.insert(
        clienteId: cliente.id,
        nombre: 'Juan Pérez',
        tipo: 'comercial',
        esPrincipal: const Value(true),
      ),
    );
    final segundo = await repo.agregarContacto(
      ContactoCompanion.insert(
        clienteId: cliente.id,
        nombre: 'Ana López',
        tipo: 'comercial',
        esPrincipal: const Value(true),
      ),
    );

    final contactos = await repo.obtenerContactos(cliente.id);
    final primeroActualizado = contactos.firstWhere((c) => c.id == primero.id);
    final segundoActualizado = contactos.firstWhere((c) => c.id == segundo.id);

    expect(primeroActualizado.esPrincipal, isFalse);
    expect(segundoActualizado.esPrincipal, isTrue);
  });

  test('agregarContacto con esPrincipal no afecta al principal de un tipo distinto', () async {
    final cliente = await crearClienteDePrueba();

    final comercial = await repo.agregarContacto(
      ContactoCompanion.insert(
        clienteId: cliente.id,
        nombre: 'Juan Pérez',
        tipo: 'comercial',
        esPrincipal: const Value(true),
      ),
    );
    await repo.agregarContacto(
      ContactoCompanion.insert(
        clienteId: cliente.id,
        nombre: 'Rosa Díaz',
        tipo: 'operativo',
        esPrincipal: const Value(true),
      ),
    );

    final contactos = await repo.obtenerContactos(cliente.id);
    expect(contactos.firstWhere((c) => c.id == comercial.id).esPrincipal, isTrue);
  });

  test('actualizarContacto con esPrincipal retira el principal anterior del mismo tipo', () async {
    final cliente = await crearClienteDePrueba();

    final principal = await repo.agregarContacto(
      ContactoCompanion.insert(
        clienteId: cliente.id,
        nombre: 'Juan Pérez',
        tipo: 'comercial',
        esPrincipal: const Value(true),
      ),
    );
    final otro = await repo.agregarContacto(
      ContactoCompanion.insert(clienteId: cliente.id, nombre: 'Ana López', tipo: 'comercial'),
    );

    await repo.actualizarContacto(
      id: otro.id,
      cambios: const ContactoCompanion(esPrincipal: Value(true)),
    );

    final contactos = await repo.obtenerContactos(cliente.id);
    expect(contactos.firstWhere((c) => c.id == principal.id).esPrincipal, isFalse);
    expect(contactos.firstWhere((c) => c.id == otro.id).esPrincipal, isTrue);
  });

  test('archivarContacto lo saca del listado de activos sin borrarlo', () async {
    final cliente = await crearClienteDePrueba();
    final contacto = await repo.agregarContacto(
      ContactoCompanion.insert(clienteId: cliente.id, nombre: 'Juan Pérez', tipo: 'comercial'),
    );

    await repo.archivarContacto(contacto.id);

    final activos = await repo.obtenerContactos(cliente.id);
    expect(activos, isEmpty);

    final todos = await db.select(db.contacto).get();
    expect(todos, hasLength(1), reason: 'archivar nunca es un hard delete');
    expect(todos.single.cicloVidaRegistro, 'archivado');
  });

  test('un contacto archivado no bloquea que otro tome su lugar como principal del mismo tipo', () async {
    final cliente = await crearClienteDePrueba();
    final archivado = await repo.agregarContacto(
      ContactoCompanion.insert(
        clienteId: cliente.id,
        nombre: 'Contacto viejo',
        tipo: 'comercial',
        esPrincipal: const Value(true),
      ),
    );
    await repo.archivarContacto(archivado.id);

    // No debe lanzar — el índice único solo considera contactos activos.
    final nuevo = await repo.agregarContacto(
      ContactoCompanion.insert(
        clienteId: cliente.id,
        nombre: 'Contacto nuevo',
        tipo: 'comercial',
        esPrincipal: const Value(true),
      ),
    );
    expect(nuevo.esPrincipal, isTrue);
  });
}
