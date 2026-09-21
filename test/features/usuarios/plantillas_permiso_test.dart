// Etapa "Usuarios, permisos y UX de seguridad" — punto 12: plantillas
// de permisos EN CÓDIGO, sin entidad nueva (decisión de producto de
// Marlon).
//
// Lo que estas pruebas fijan no es "qué trae cada plantilla" (eso es
// negocio y puede cambiar), sino las reglas que ninguna plantilla puede
// romper por más que evolucione: no conceden gobierno, no conceden
// secretos, no contienen códigos muertos, y no se persisten como rol.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/core/permissions/modulos_permiso.dart';
import 'package:riseg_one/core/permissions/plantillas_permiso.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';
import 'package:riseg_one/features/usuarios/presentation/usuarios_controller.dart';

class _SesionMaestro extends SesionController {
  @override
  SesionUsuario? build() => const SesionUsuario(
        usuarioId: 'maestro',
        nombre: 'MARLON',
        nombreUsuario: 'marlon',
        esMaestro: true,
        permisos: {},
      );
}

void main() {
  group('Reglas invariantes de las plantillas', () {
    test('ningún código de plantilla está fuera del catálogo', () {
      final catalogo = todosLosCodigosDePermiso().toSet();
      for (final plantilla in plantillasPermiso) {
        for (final codigo in plantilla.codigos) {
          expect(
            catalogo,
            contains(codigo),
            reason: 'la plantilla "${plantilla.codigo}" trae "$codigo", que no existe: '
                'concedería nada, en silencio',
          );
        }
      }
    });

    test('ninguna plantilla concede facultades de gobierno', () {
      // Administrar cuentas, otorgar permisos, resetear contraseñas y
      // leer la auditoría se conceden a mano — nunca "de paquete" por el
      // puesto de alguien.
      for (final plantilla in plantillasPermiso) {
        final codigos = codigosDePlantilla(plantilla.codigo);
        expect(codigos.where((c) => c.startsWith('usuarios.')), isEmpty, reason: plantilla.codigo);
        expect(codigos, isNot(contains('auditoria.ver')), reason: plantilla.codigo);
      }
    });

    test('ninguna plantilla concede acceso a credenciales guardadas', () {
      for (final plantilla in plantillasPermiso) {
        expect(
          codigosDePlantilla(plantilla.codigo),
          isNot(contains('telefonia.verCredenciales')),
          reason: '${plantilla.codigo}: son secretos cifrados, del mismo orden que la Bóveda',
        );
      }
    });

    test('ninguna plantilla alcanza Respaldo ni Bóveda: no tienen código que otorgar', () {
      for (final plantilla in plantillasPermiso) {
        final codigos = codigosDePlantilla(plantilla.codigo);
        expect(codigos.where((c) => c.startsWith('respaldo') || c.startsWith('boveda')), isEmpty);
      }
    });

    test('los códigos que aplica una plantilla ya vienen normalizados', () {
      for (final plantilla in plantillasPermiso) {
        final codigos = codigosDePlantilla(plantilla.codigo);
        expect(
          codigos,
          normalizarPermisos(codigos),
          reason: '${plantilla.codigo}: una acción nunca llega sin el `ver` de su módulo',
        );
      }
    });

    test('cada plantilla tiene identificador único y contenido', () {
      final codigos = plantillasPermiso.map((p) => p.codigo).toList();
      expect(codigos.toSet(), hasLength(codigos.length), reason: 'identificadores duplicados');
      for (final plantilla in plantillasPermiso) {
        expect(plantilla.codigos, isNotEmpty, reason: '${plantilla.codigo} no precargaría nada');
      }
    });

    test('una plantilla inexistente no concede nada (nunca lanza)', () {
      expect(codigosDePlantilla('no-existe'), isEmpty);
    });
  });

  group('Contenido de negocio de las plantillas', () {
    test('"Solo consulta" no trae NINGUNA facultad de mutación', () {
      final consulta = codigosDePlantilla('consulta');
      expect(consulta, isNotEmpty);
      for (final codigo in consulta) {
        expect(codigo.endsWith('.ver'), isTrue, reason: '$codigo no es una lectura');
      }
    });

    test('"Solo consulta" cubre todo el catálogo de lectura salvo la auditoría', () {
      final consulta = codigosDePlantilla('consulta');
      final lecturas = todosLosCodigosDePermiso().where((c) => c.endsWith('.ver'));
      expect(consulta, containsAll(lecturas.where((c) => c != 'auditoria.ver')));
      expect(consulta, isNot(contains('auditoria.ver')));
    });

    test('Nómina arma y cierra, pero NO dispersa: pagar vive en Tesorería', () {
      final nomina = codigosDePlantilla('nomina');
      expect(nomina, containsAll({'nomina.crear', 'nomina.cerrar'}));
      for (final pago in ['nomina.registrarPago', 'nomina.corregirPago', 'nomina.cancelarPago']) {
        expect(nomina, isNot(contains(pago)), reason: 'cerrar una Nómina no es ejecutar su dinero');
      }
      expect(codigosDePlantilla('tesoreria'), containsAll({'nomina.registrarPago', 'nomina.cancelarPago'}));
    });

    test('Recursos Humanos no cambia sueldos por el solo hecho de llevar expedientes', () {
      expect(codigosDePlantilla('recursosHumanos'), isNot(contains('personal.cambiarSueldo')));
    });

    test('Tesorería no ve expedientes de Personal, ni RH ve Finanzas', () {
      final tesoreria = codigosDePlantilla('tesoreria');
      final rh = codigosDePlantilla('recursosHumanos');

      expect(tesoreria, isNot(contains('personal.ver')), reason: 'mínima información: mover dinero no exige el expediente');
      expect(rh, isNot(contains('finanzas.ver')));
      expect(rh.where((c) => c.startsWith('egresos.')), isEmpty);
    });
  });

  group('Una plantilla NO es un rol', () {
    late AppDatabase db;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      await db.into(db.usuario).insert(
            UsuarioCompanion.insert(
              id: const Value('maestro'),
              nombre: 'MARLON',
              nombreUsuario: 'marlon',
              passwordHash: r'pbkdf2$1$c2FsdA==$aGFzaA==',
              esMaestro: const Value(true),
            ),
          );
    });

    tearDown(() => db.close());

    test('aplicar una plantilla guarda códigos individuales, sin rastro de la plantilla', () async {
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          sesionControllerProvider.overrideWith(_SesionMaestro.new),
        ],
      );
      addTearDown(container.dispose);

      var puestos = await db.select(db.puesto).get();
      if (puestos.isEmpty) {
        await db.into(db.puesto).insert(
              PuestoCompanion.insert(
                codigo: 'PUE-COM',
                nombre: 'Ejecutivo comercial',
                areaId: (await db.select(db.area).get()).first.id,
                tipo: 'administrativo',
                nivelJerarquico: 5,
              ),
            );
        puestos = await db.select(db.puesto).get();
      }
      final puestoId = puestos.first.id;
      final plantilla = codigosDePlantilla('comercial');

      await container.read(usuariosControllerProvider.notifier).crear(
            nombre: 'JAVIER RIOS',
            nombreUsuario: 'javier',
            password: 'contrasenaLarga1',
            puestoId: puestoId,
            permisosIniciales: plantilla,
          );

      final filas = await db.select(db.permisoUsuario).get();
      expect(
        filas.map((f) => f.codigo).toSet(),
        plantilla,
        reason: 'se guarda exactamente el conjunto resultante, código por código',
      );

      // No existe columna, tabla ni referencia que diga "esta cuenta es
      // Comercial": si la plantilla cambia mañana, esta cuenta no cambia.
      final columnas = db.permisoUsuario.$columns.map((c) => c.name).toList();
      expect(columnas.where((c) => c.toLowerCase().contains('plantilla')), isEmpty);
      final columnasUsuario = db.usuario.$columns.map((c) => c.name).toList();
      expect(columnasUsuario.where((c) => c.toLowerCase().contains('plantilla')), isEmpty);
    });
  });
}
