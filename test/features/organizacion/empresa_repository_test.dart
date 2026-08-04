import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/tables/audit_columns.dart';
import 'package:riseg_one/features/organizacion/data/repositories/empresa_repository_impl.dart';
import 'package:riseg_one/features/organizacion/domain/shared/direccion_input.dart';
import 'package:riseg_one/features/organizacion/domain/shared/medio_contacto_input.dart';

void main() {
  late AppDatabase db;
  late EmpresaRepositoryImpl repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = EmpresaRepositoryImpl(db);
  });

  tearDown(() => db.close());

  test('obtenerActiva devuelve la RSG-01 sembrada', () async {
    final activa = await repo.obtenerActiva();
    expect(activa.codigo, 'RSG-01');
    expect(activa.nombreComercial, 'Seguridad Privada RISEG');
    expect(activa.razonSocial, isNull);
    expect(activa.rfc, isNull);
  });

  test('el índice único parcial impide una segunda empresa activa', () async {
    await expectLater(
      db.into(db.empresa).insert(
            EmpresaCompanion.insert(codigo: 'RSG-02', nombreComercial: 'Otra empresa'),
          ),
      throwsA(anything),
    );
  });

  test('actualizarDatosGenerales aplica los cambios sobre la activa', () async {
    await repo.actualizarDatosGenerales(
      const EmpresaCompanion(razonSocial: Value('Seguridad Privada RISEG S.A. de C.V.')),
    );

    final activa = await repo.obtenerActiva();
    expect(activa.razonSocial, 'Seguridad Privada RISEG S.A. de C.V.');
  });

  test('archivar la única empresa activa lanza StateError', () async {
    final activa = await repo.obtenerActiva();
    await expectLater(() => repo.archivar(activa.id), throwsStateError);
  });

  test('guardarExpediente dos veces actualiza la misma Dirección fiscal, no la duplica', () async {
    final activa = await repo.obtenerActiva();
    const direccion1 = DireccionInput(
      calle: 'Calle Uno',
      numeroExterior: '1',
      colonia: 'Colonia Uno',
      municipioAlcaldia: 'Municipio Uno',
      estado: 'Estado Uno',
      codigoPostal: '11111',
    );
    const direccion2 = DireccionInput(
      calle: 'Calle Dos',
      numeroExterior: '2',
      colonia: 'Colonia Dos',
      municipioAlcaldia: 'Municipio Dos',
      estado: 'Estado Dos',
      codigoPostal: '22222',
    );

    await repo.guardarExpediente(
      empresaId: activa.id,
      datosGenerales: const EmpresaCompanion(),
      direccionFiscal: direccion1,
      medioContacto: null,
    );
    await repo.guardarExpediente(
      empresaId: activa.id,
      datosGenerales: const EmpresaCompanion(),
      direccionFiscal: direccion2,
      medioContacto: null,
    );

    final todasLasDirecciones =
        await (db.select(db.direccion)..where((t) => t.empresaId.equals(activa.id))).get();
    expect(todasLasDirecciones, hasLength(1));
    expect(todasLasDirecciones.single.calle, 'Calle Dos');
  });

  test('guardarExpediente dos veces actualiza el mismo MedioContacto principal, no lo duplica', () async {
    final activa = await repo.obtenerActiva();

    await repo.guardarExpediente(
      empresaId: activa.id,
      datosGenerales: const EmpresaCompanion(),
      direccionFiscal: null,
      medioContacto: const MedioContactoInput(telefono: '111'),
    );
    await repo.guardarExpediente(
      empresaId: activa.id,
      datosGenerales: const EmpresaCompanion(),
      direccionFiscal: null,
      medioContacto: const MedioContactoInput(telefono: '222'),
    );

    final todosLosContactos =
        await (db.select(db.medioContacto)..where((t) => t.empresaId.equals(activa.id))).get();
    expect(todosLosContactos, hasLength(1));
    expect(todosLosContactos.single.telefono, '222');
  });

  test('dirección/contacto vacíos tras existir uno previo lo archivan, no lo borran', () async {
    final activa = await repo.obtenerActiva();

    await repo.guardarExpediente(
      empresaId: activa.id,
      datosGenerales: const EmpresaCompanion(),
      direccionFiscal: const DireccionInput(
        calle: 'Calle',
        numeroExterior: '1',
        colonia: 'Colonia',
        municipioAlcaldia: 'Municipio',
        estado: 'Estado',
        codigoPostal: '11111',
      ),
      medioContacto: const MedioContactoInput(telefono: '111'),
    );

    await repo.guardarExpediente(
      empresaId: activa.id,
      datosGenerales: const EmpresaCompanion(),
      direccionFiscal: null,
      medioContacto: null,
    );

    expect(await repo.obtenerDireccionFiscal(activa.id), isNull);
    expect(await repo.obtenerMedioContactoPrincipal(activa.id), isNull);

    final direccionesFisicas =
        await (db.select(db.direccion)..where((t) => t.empresaId.equals(activa.id))).get();
    expect(direccionesFisicas, hasLength(1));
    expect(direccionesFisicas.single.cicloVidaRegistro, CicloVidaRegistro.archivado.name);

    final contactosFisicos =
        await (db.select(db.medioContacto)..where((t) => t.empresaId.equals(activa.id))).get();
    expect(contactosFisicos, hasLength(1));
    expect(contactosFisicos.single.cicloVidaRegistro, CicloVidaRegistro.archivado.name);
  });

  test('recapturar una Dirección después de archivarla no revienta contra el índice único', () async {
    final activa = await repo.obtenerActiva();
    const direccionInicial = DireccionInput(
      calle: 'Calle Inicial',
      numeroExterior: '1',
      colonia: 'Colonia',
      municipioAlcaldia: 'Municipio',
      estado: 'Estado',
      codigoPostal: '11111',
    );
    const direccionRecapturada = DireccionInput(
      calle: 'Calle Recapturada',
      numeroExterior: '2',
      colonia: 'Colonia Nueva',
      municipioAlcaldia: 'Municipio Nuevo',
      estado: 'Estado Nuevo',
      codigoPostal: '22222',
    );

    await repo.guardarExpediente(
      empresaId: activa.id,
      datosGenerales: const EmpresaCompanion(),
      direccionFiscal: direccionInicial,
      medioContacto: null,
    );
    // Vaciarla la archiva (fila con `empresaId` único ya ocupado).
    await repo.guardarExpediente(
      empresaId: activa.id,
      datosGenerales: const EmpresaCompanion(),
      direccionFiscal: null,
      medioContacto: null,
    );
    // Recapturarla no debe intentar un segundo INSERT contra ese mismo
    // `empresaId` — debe reactivar y actualizar la fila archivada.
    await repo.guardarExpediente(
      empresaId: activa.id,
      datosGenerales: const EmpresaCompanion(),
      direccionFiscal: direccionRecapturada,
      medioContacto: null,
    );

    final direccion = await repo.obtenerDireccionFiscal(activa.id);
    expect(direccion, isNotNull);
    expect(direccion!.calle, 'Calle Recapturada');

    final todasLasDirecciones =
        await (db.select(db.direccion)..where((t) => t.empresaId.equals(activa.id))).get();
    expect(todasLasDirecciones, hasLength(1));
  });

  test('una falla al guardar el MedioContacto revierte también Empresa y Dirección', () async {
    final activa = await repo.obtenerActiva();

    // Provoca una anomalía de datos a propósito (dos medios "principal"
    // activos para la misma Empresa), insertando directo sin pasar por
    // el repositorio: guardarExpediente fallará al intentar leer "el"
    // principal, porque encontrará más de una fila.
    await db.into(db.medioContacto).insert(
          MedioContactoCompanion.insert(empresaId: Value(activa.id), etiqueta: const Value('principal')),
        );
    await db.into(db.medioContacto).insert(
          MedioContactoCompanion.insert(empresaId: Value(activa.id), etiqueta: const Value('principal')),
        );

    await expectLater(
      () => repo.guardarExpediente(
        empresaId: activa.id,
        datosGenerales: const EmpresaCompanion(nombreComercial: Value('Nombre que no debe persistir')),
        direccionFiscal: const DireccionInput(
          calle: 'Calle que no debe persistir',
          numeroExterior: '1',
          colonia: 'Colonia',
          municipioAlcaldia: 'Municipio',
          estado: 'Estado',
          codigoPostal: '11111',
        ),
        medioContacto: const MedioContactoInput(telefono: '123'),
      ),
      throwsA(anything),
    );

    final empresaTrasFalla = await repo.obtenerActiva();
    expect(empresaTrasFalla.nombreComercial, isNot('Nombre que no debe persistir'));
    expect(await repo.obtenerDireccionFiscal(activa.id), isNull);
  });
}
