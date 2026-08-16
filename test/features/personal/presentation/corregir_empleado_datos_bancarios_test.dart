// Etapa 15 — hallazgo real reportado: "Corregir empleado" fallaba con
// "No se pudo corregir el Empleado. Intenta de nuevo." al agregar
// datos bancarios. Diagnóstico confirmado por inspección directa de la
// base de datos real del usuario: el proceso en ejecución seguía
// conectado a una base de datos en `schemaVersion 47` (sin la columna
// `banco_otro_descripcion` agregada en la migración v48) — la lógica
// de `CorregirEmpleadoUseCase`/`EmpleadoRepositoryImpl` en sí ya estaba
// correcta y probada (ver `empleado_test.dart`). Esta prueba ejercita
// el FLUJO REAL vía `corregirEmpleadoAutorizadoProvider` — el mismo
// punto de entrada que usa `corregir_empleado_dialog.dart`, no
// solamente el repositorio aislado — sobre una base de datos ya
// correctamente migrada, reproduciendo exactamente los escenarios que
// Marlon pidió verificar.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/seed/seed_ids.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/personal/domain/usecases/corregir_empleado_usecase.dart';
import 'package:riseg_one/features/personal/personal_providers.dart';
import 'package:riseg_one/features/personal/presentation/empleados/widgets/crear_empleado_dialog.dart'
    show mensajeErrorTecnicoEmpleado;
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';

class _SesionMaestroDePrueba extends SesionController {
  @override
  SesionUsuario? build() {
    return const SesionUsuario(
      usuarioId: 'usuario-maestro',
      nombre: 'Maestro de prueba',
      nombreUsuario: 'maestro',
      esMaestro: true,
      permisos: {},
    );
  }
}

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late String empleadoId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sesionControllerProvider.overrideWith(_SesionMaestroDePrueba.new),
      ],
    );
    addTearDown(container.dispose);

    // `EmpleadoEvento.actorUsuarioId` es una FK real hacia `Usuario` —
    // debe existir de antemano o la corrección falla con
    // `CorregirEmpleadoErrorInesperado` (mismo hallazgo real ya
    // documentado en otras pruebas de esta etapa).
    await db.into(db.usuario).insert(
          UsuarioCompanion.insert(
            id: const Value('usuario-maestro'),
            nombre: 'Maestro de prueba',
            nombreUsuario: 'maestro',
            passwordHash: 'x',
            esMaestro: const Value(true),
          ),
        );

    final empleado = await db.into(db.empleado).insertReturning(
          EmpleadoCompanion.insert(
            numeroEmpleado: 1,
            nombres: 'Juan',
            apellidoPaterno: 'Pérez',
            telefono: const Value('5555555555'),
            sexo: 'masculino',
            fechaNacimiento: DateTime(1990, 1, 1),
            curp: 'PEXJ900101HDFXXX01',
            rfc: 'PEXJ900101AB1',
            nss: '12345678901',
            estadoCivil: 'soltero',
            fechaIngreso: DateTime(2026, 1, 1),
            aniosExperienciaSeguridad: 3,
          ),
        );
    empleadoId = empleado.id;
  });

  tearDown(() => db.close());

  test('1. Empleado sin banco: agregar BBVA + número, mismo flujo real del diálogo (provider)', () async {
    final resultado = await container.read(corregirEmpleadoAutorizadoProvider)(
      empleadoId: empleadoId,
      bancoId: SeedIds.bancoBbva,
      limpiarBanco: false,
      bancoOtroDescripcion: null,
      limpiarBancoOtroDescripcion: true,
      numeroCuentaTarjeta: '1234567890123456',
      limpiarNumeroCuentaTarjeta: false,
      clabe: '',
      limpiarClabe: true,
      limpiarPuesto: false,
      limpiarSucursal: false,
      limpiarSueldoMensualAdministrativo: false,
      limpiarBonoMensualAdministrativo: false,
      motivo: 'Captura de datos bancarios',
    );

    expect(resultado, isA<CorregirEmpleadoExitoso>());
    final actualizado = (resultado as CorregirEmpleadoExitoso).empleado;
    expect(actualizado.bancoId, SeedIds.bancoBbva);
    expect(actualizado.numeroCuentaTarjeta, '1234567890123456');
    expect(actualizado.bancoOtroDescripcion, isNull);
    // Otros datos del empleado nunca deben perderse al corregir solo
    // información bancaria.
    expect(actualizado.telefono, '5555555555', reason: 'campos no relacionados con banco no deben perderse');
    expect(actualizado.nombres, 'Juan');
  });

  test('2. Cambiar BBVA → Santander conservando el número de cuenta/tarjeta', () async {
    await container.read(corregirEmpleadoAutorizadoProvider)(
      empleadoId: empleadoId,
      bancoId: SeedIds.bancoBbva,
      limpiarBancoOtroDescripcion: true,
      numeroCuentaTarjeta: '1234567890123456',
      limpiarClabe: true,
      limpiarPuesto: false,
      limpiarSucursal: false,
      limpiarSueldoMensualAdministrativo: false,
      limpiarBonoMensualAdministrativo: false,
      motivo: 'x',
    );

    final resultado = await container.read(corregirEmpleadoAutorizadoProvider)(
      empleadoId: empleadoId,
      bancoId: SeedIds.bancoSantander,
      limpiarBancoOtroDescripcion: true,
      numeroCuentaTarjeta: '1234567890123456',
      limpiarClabe: true,
      limpiarPuesto: false,
      limpiarSucursal: false,
      limpiarSueldoMensualAdministrativo: false,
      limpiarBonoMensualAdministrativo: false,
      motivo: 'Cambio de banco',
    );

    expect(resultado, isA<CorregirEmpleadoExitoso>());
    final actualizado = (resultado as CorregirEmpleadoExitoso).empleado;
    expect(actualizado.bancoId, SeedIds.bancoSantander);
    expect(actualizado.numeroCuentaTarjeta, '1234567890123456');
  });

  test('3. Seleccionar "Otro": capturar nombre del banco + número, guardar', () async {
    final resultado = await container.read(corregirEmpleadoAutorizadoProvider)(
      empleadoId: empleadoId,
      bancoId: SeedIds.bancoOtro,
      bancoOtroDescripcion: 'Banco Regional XYZ',
      limpiarBancoOtroDescripcion: false,
      numeroCuentaTarjeta: '1234567890123456',
      limpiarClabe: true,
      limpiarPuesto: false,
      limpiarSucursal: false,
      limpiarSueldoMensualAdministrativo: false,
      limpiarBonoMensualAdministrativo: false,
      motivo: 'Banco fuera de catálogo',
    );

    expect(resultado, isA<CorregirEmpleadoExitoso>());
    final actualizado = (resultado as CorregirEmpleadoExitoso).empleado;
    expect(actualizado.bancoId, SeedIds.bancoOtro);
    expect(actualizado.bancoOtroDescripcion, 'Banco Regional XYZ');
  });

  test('4. Cambiar de "Otro" a un banco de catálogo deja bancoOtroDescripcion limpio', () async {
    await container.read(corregirEmpleadoAutorizadoProvider)(
      empleadoId: empleadoId,
      bancoId: SeedIds.bancoOtro,
      bancoOtroDescripcion: 'Banco Regional XYZ',
      limpiarBancoOtroDescripcion: false,
      numeroCuentaTarjeta: '1234567890123456',
      limpiarClabe: true,
      limpiarPuesto: false,
      limpiarSucursal: false,
      limpiarSueldoMensualAdministrativo: false,
      limpiarBonoMensualAdministrativo: false,
      motivo: 'x',
    );

    final resultado = await container.read(corregirEmpleadoAutorizadoProvider)(
      empleadoId: empleadoId,
      bancoId: SeedIds.bancoBbva,
      limpiarBancoOtroDescripcion: true,
      numeroCuentaTarjeta: '1234567890123456',
      limpiarClabe: true,
      limpiarPuesto: false,
      limpiarSucursal: false,
      limpiarSueldoMensualAdministrativo: false,
      limpiarBonoMensualAdministrativo: false,
      motivo: 'Corrige a banco real',
    );

    expect(resultado, isA<CorregirEmpleadoExitoso>());
    final actualizado = (resultado as CorregirEmpleadoExitoso).empleado;
    expect(actualizado.bancoId, SeedIds.bancoBbva);
    expect(actualizado.bancoOtroDescripcion, isNull);
  });

  test('5. Dejar datos bancarios vacíos (opcionales) no bloquea la corrección', () async {
    final resultado = await container.read(corregirEmpleadoAutorizadoProvider)(
      empleadoId: empleadoId,
      limpiarBanco: true,
      limpiarBancoOtroDescripcion: true,
      limpiarNumeroCuentaTarjeta: true,
      limpiarClabe: true,
      telefono: '5551112233',
      limpiarPuesto: false,
      limpiarSucursal: false,
      limpiarSueldoMensualAdministrativo: false,
      limpiarBonoMensualAdministrativo: false,
      motivo: 'Actualiza solo teléfono, sin datos bancarios',
    );

    expect(resultado, isA<CorregirEmpleadoExitoso>());
    final actualizado = (resultado as CorregirEmpleadoExitoso).empleado;
    expect(actualizado.bancoId, isNull);
    expect(actualizado.numeroCuentaTarjeta, isNull);
    expect(actualizado.telefono, '5551112233');
  });

  group('mensajeErrorTecnicoEmpleado', () {
    late AppLocalizations l10n;

    setUp(() async {
      l10n = await AppLocalizations.delegate.load(const Locale('es'));
    });

    test('reconoce el patrón real de SQLite para una columna faltante (base de datos sin migrar)', () {
      expect(
        mensajeErrorTecnicoEmpleado(l10n, 'SqliteException(1): no such column: banco_otro_descripcion', 'generico'),
        l10n.empleadoErrorBaseDatosDesactualizada,
      );
      expect(
        mensajeErrorTecnicoEmpleado(l10n, 'table empleado has no column named banco_otro_descripcion', 'generico'),
        l10n.empleadoErrorBaseDatosDesactualizada,
      );
    });

    test('cualquier otro error cae al mensaje genérico — nunca se expone el texto técnico crudo', () {
      expect(
        mensajeErrorTecnicoEmpleado(l10n, 'UNIQUE constraint failed: empleado.numero_empleado', 'generico'),
        'generico',
      );
    });
  });
}
