// Etapa "Complemento de pago dependiente del Pago real" — §13
// (notificaciones vivas) por la VÍA DE PROVIDERS.
//
// Existe aparte de `complemento_pendiente_derivado_test.dart` por una
// razón concreta: un ciclo de dependencias de Riverpod es invisible
// para cualquier prueba que construya los repositorios a mano. Aquí
// Notificaciones depende de Finanzas y Finanzas invalida
// Notificaciones — exactamente la forma que produjo un
// `CircularDependencyError` real en una etapa anterior.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/attachments/attachment_storage.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/organizacion/organizacion_providers.dart';
import 'package:riseg_one/features/finanzas/finanzas_providers.dart';
import 'package:riseg_one/features/notificaciones/notificaciones_providers.dart';
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';

class _SesionFinanzas extends SesionController {
  @override
  SesionUsuario? build() => const SesionUsuario(
        usuarioId: 'u1',
        nombre: 'TESORERA',
        nombreUsuario: 'tesorera',
        esMaestro: false,
        permisos: {'finanzas.ver', 'pagos.registrar'},
      );
}

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late String clienteId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sesionControllerProvider.overrideWith(_SesionFinanzas.new),
        // El repositorio de Documentos por emitir depende del
        // almacenamiento de adjuntos, y este de `appPathsProvider`,
        // que exige `path_provider` (no disponible bajo `flutter
        // test`) — mismo override que ya usa
        // `notificaciones_screen_test`.
        attachmentStorageProvider.overrideWithValue(AttachmentStorage('.')),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(db.close);

    final cliente = await db.into(db.cliente).insertReturning(
          ClienteCompanion.insert(codigo: 'CLI-000040', nombreComercial: 'MORGAN'),
        );
    clienteId = cliente.id;
  });

  Future<CuentaPorCobrarData> crearCuentaPpd() async {
    await db.into(db.documentoPorEmitir).insert(
          DocumentoPorEmitirCompanion.insert(
            id: const Value('doc-n1'),
            codigo: 'DPE-N1',
            generationKey: 'gk-n1',
            clienteId: clienteId,
            tipoDocumento: 'cfdi',
            metodo: 'ppd',
            requiereComplemento: const Value(true),
            periodoInicio: DateTime(2026, 9, 1),
            periodoFin: DateTime(2026, 9, 30),
            agrupacion: 'porServicio',
            importeBaseEsperado: 10000000,
            importeFinalEsperado: 10000000,
          ),
        );
    return container.read(cuentaPorCobrarRepositoryProvider).crear(
          documentoPorEmitirId: 'doc-n1',
          clienteId: clienteId,
          tipoDocumento: 'cfdi',
          metodo: 'ppd',
          requiereComplemento: true,
          folioDocumento: 'MORGAN-SEP',
          fechaEmisionReal: DateTime(2026, 9, 3),
          importeEmitido: 10000000,
        );
  }

  test('el grafo de providers se construye: Notificaciones ← Finanzas, sin ciclo', () {
    // Si `obtenerComplementosPendientesUseCaseProvider` (Finanzas) y
    // `obtenerNotificacionesComplementosUseCaseProvider`
    // (Notificaciones) se referenciaran mutuamente, esta sola línea
    // lanzaría `CircularDependencyError`.
    expect(() => container.read(obtenerNotificacionesUseCaseProvider), returnsNormally);
    expect(() => container.read(obtenerComplementosPendientesUseCaseProvider), returnsNormally);
  });

  test('la notificación aparece al registrar el Pago y desaparece al registrar el Complemento', () async {
    final cuenta = await crearCuentaPpd();

    // Sin Pago: nada.
    var resultados = await container.read(obtenerNotificacionesUseCaseProvider).ejecutar(
          incluirVehiculos: false,
          incluirComercial: false,
          incluirFinanzas: true,
        );
    expect(resultados.complementosPendientes, isEmpty);

    // Llega el dinero.
    final pago = await container.read(pagoRepositoryProvider).crear(
          folioPago: 'PAG-000100',
          clienteId: clienteId,
          montoTotal: 10000000,
          fechaPago: DateTime(2026, 10, 12),
          formaPago: 'transferencia',
        );
    await container.read(pagoRepositoryProvider).aplicar(
          pagoId: pago.id,
          cuentaPorCobrarId: cuenta.id,
          monto: 10000000,
        );

    resultados = await container.read(obtenerNotificacionesUseCaseProvider).ejecutar(
          incluirVehiculos: false,
          incluirComercial: false,
          incluirFinanzas: true,
        );
    expect(resultados.complementosPendientes, hasLength(1));
    final fila = resultados.complementosPendientes!.single;
    expect(fila.titulo, 'MORGAN');
    expect(fila.subtitulo, contains('PAG-000100'));
    expect(fila.subtitulo, contains('12/10/2026'), reason: 'la fecha del Pago REAL, no la esperada');
    expect(fila.ruta, '/finanzas/complementos', reason: 'lleva al contexto fiscal, no a la etapa comercial');
    expect(fila.urgente, isFalse, reason: 'sin regla de plazo no hay forma honesta de marcar urgencia');
    expect(resultados.total, greaterThanOrEqualTo(1));

    // Se timbra.
    await container.read(registrarComplementoPagoUseCaseProvider).ejecutar(
          pagoId: pago.id,
          uuid: 'cccccccc-1111-2222-3333-444444444444',
          fechaTimbrado: DateTime(2026, 10, 15),
          montoTotal: 10000000,
        );

    resultados = await container.read(obtenerNotificacionesUseCaseProvider).ejecutar(
          incluirVehiculos: false,
          incluirComercial: false,
          incluirFinanzas: true,
        );
    expect(resultados.complementosPendientes, isEmpty);
  });

  test('sin finanzas.ver la categoría ni siquiera se calcula (null, no lista vacía)', () async {
    final cuenta = await crearCuentaPpd();
    final pago = await container.read(pagoRepositoryProvider).crear(
          folioPago: 'PAG-000101',
          clienteId: clienteId,
          montoTotal: 10000000,
          fechaPago: DateTime(2026, 10, 12),
          formaPago: 'transferencia',
        );
    await container.read(pagoRepositoryProvider).aplicar(
          pagoId: pago.id,
          cuentaPorCobrarId: cuenta.id,
          monto: 10000000,
        );

    final resultados = await container.read(obtenerNotificacionesUseCaseProvider).ejecutar(
          incluirVehiculos: false,
          incluirComercial: false,
          incluirFinanzas: false,
        );

    expect(resultados.complementosPendientes, isNull, reason: 'mismo criterio null-vs-vacío del resto del centro');
    expect(resultados.total, 0);
  });
}
