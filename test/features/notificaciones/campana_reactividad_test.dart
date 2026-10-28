// Barrido transversal de reactividad — el contador de la campana.
//
// El badge del Centro de notificaciones está SIEMPRE a la vista y se
// recalculaba únicamente al abrir la campana (`NotificationBell._alternar`
// llama a `recargar()`). Es decir: abrir el panel era el mecanismo de
// sincronización, justo lo que esta auditoría persigue.
//
// Aquí se prueban las dos familias de mutación que alimentaban categorías de
// la campana sin avisarle: Cuentas por cobrar y Pagos. (Documentos por emitir
// y Complementos ya estaban cubiertos.)

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/attachments/attachment_storage.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/cancelar_cuenta_por_cobrar_usecase.dart';
import 'package:riseg_one/features/finanzas/presentation/cuentas_por_cobrar/cuentas_por_cobrar_controller.dart';
import 'package:riseg_one/features/notificaciones/presentation/notificaciones_controller.dart';
import 'package:riseg_one/features/organizacion/organizacion_providers.dart' show attachmentStorageProvider;
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';
import '../../support/sesion_en_base.dart';

class _SesionMaestroDePrueba extends SesionController {
  @override
  SesionUsuario? build() {
    return const SesionUsuario(
      usuarioId: 'usuario-prueba',
      nombre: 'Usuario de prueba',
      nombreUsuario: 'prueba',
      esMaestro: true,
      permisos: {},
    );
  }
}

Future<void> _esperarHasta(bool Function() condicion, {int intentos = 200}) async {
  for (var i = 0; i < intentos && !condicion(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late String cuentaId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.into(db.usuario).insert(
          UsuarioCompanion.insert(
            id: const Value('usuario-prueba'),
            nombre: 'Usuario de prueba',
            nombreUsuario: 'prueba',
            passwordHash: 'x',
          ),
        );
    final cliente = await db.into(db.cliente).insertReturning(
          ClienteCompanion.insert(codigo: 'CLI-000001', nombreComercial: 'SPORTIUM'),
        );

    // Vencida hace tiempo: cae con seguridad en la categoría "CxC vencidas"
    // de la campana, sin depender de la fecha de hoy.
    // Una CxC pertenece siempre a un Documento por emitir o a un Servicio
    // eventual (CHECK de la tabla): se crea el documento de origen.
    final documento = await db.into(db.documentoPorEmitir).insertReturning(
      DocumentoPorEmitirCompanion.insert(
        codigo: 'DOC-000001',
        clienteId: cliente.id,
        tipoDocumento: 'reciboDePago',
        agrupacion: 'porServicio',
        metodo: 'noAplica',
        periodoInicio: DateTime.now().subtract(const Duration(days: 120)),
        periodoFin: DateTime.now().subtract(const Duration(days: 90)),
        generationKey: 'GK-1',
        importeBaseEsperado: 500000,
        importeFinalEsperado: 500000,
        estatus: const Value('procesadoAceptado'),
      ),
    );

    final cuenta = await db.into(db.cuentaPorCobrar).insertReturning(
          CuentaPorCobrarCompanion.insert(

            documentoPorEmitirId: Value(documento.id),
            clienteId: Value(cliente.id),
            tipoDocumento: 'reciboDePago',
            metodo: 'noAplica',
            fechaEmisionReal: DateTime.now().subtract(const Duration(days: 90)),
            importeEmitido: 500000,
            saldoOriginal: 500000,
            saldoPendiente: 500000,
            fechaVencimiento: Value(DateTime.now().subtract(const Duration(days: 60))),
          ),
        );
    cuentaId = cuenta.id;

    container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      sesionControllerProvider.overrideWith(_SesionMaestroDePrueba.new),
      attachmentStorageProvider.overrideWithValue(AttachmentStorage('.')),
    ]);
    // Etapa 3B: autorizar revalida contra la base, así que la
    // sesión de esta prueba tiene que corresponder a una cuenta real.
    await sembrarSesionEnBase(db, const SesionUsuario( usuarioId: 'usuario-prueba', nombre: 'Usuario de prueba', nombreUsuario: 'prueba', esMaestro: true, permisos: {}, ));
  });

  tearDown(() {
    container.dispose();
    db.close();
  });

  int enLaCampana() {
    final r = container.read(notificacionesControllerProvider).resultados;
    return (r?.cxcVencidas?.length ?? 0) + (r?.cxcProximasAVencer?.length ?? 0);
  }

  test('cancelar una Cuenta por cobrar baja el contador de la campana sin abrirla', () async {
    // Mantener vivos los dos: el badge y el listado. Que sigan escuchados es
    // lo que impide que autoDispose los reconstruya "por casualidad".
    container.listen(notificacionesControllerProvider, (_, _) {});
    container.listen(cuentasPorCobrarControllerProvider, (_, _) {});

    await _esperarHasta(() => enLaCampana() == 1);
    expect(enLaCampana(), 1, reason: 'si arranca en 0, la prueba no probaría nada');

    final resultado = await container.read(cuentasPorCobrarControllerProvider.notifier).cancelar(
          cuentaPorCobrarId: cuentaId,
          motivo: 'Se acordó no cobrar este periodo',
        );
    expect(resultado, isA<CancelarCuentaPorCobrarExitoso>());

    await _esperarHasta(() => enLaCampana() == 0);

    expect(
      enLaCampana(),
      0,
      reason: 'antes el número seguía igual hasta que alguien abriera la campana',
    );
  });

  test('reprogramar el cobro recalcula la campana en el acto', () async {
    container.listen(notificacionesControllerProvider, (_, _) {});
    container.listen(cuentasPorCobrarControllerProvider, (_, _) {});
    await _esperarHasta(() => enLaCampana() == 1);

    // Se mueve el vencimiento muy hacia adelante: deja de estar vencida y de
    // estar próxima a vencer.
    await container.read(cuentasPorCobrarControllerProvider.notifier).reprogramarCobro(
          cuentaPorCobrarId: cuentaId,
          fechaCobroReprogramada: DateTime.now().add(const Duration(days: 365)),
          motivo: 'El cliente pidió prórroga',
        );

    await _esperarHasta(() => enLaCampana() == 0);
    expect(enLaCampana(), 0);
  });
}
