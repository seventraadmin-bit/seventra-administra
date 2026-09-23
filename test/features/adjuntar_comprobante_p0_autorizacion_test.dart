// Etapa 0 (auditoría de consistencia transversal — corrección de un
// hueco real de autorización): tres "adjuntar comprobante" de módulos
// distintos se invocaban desde su diálogo/controlador directo sobre el
// use case crudo, sin ningún `autorizarUseCase` en la cadena — mismo
// bug, tres sitios independientes:
//   1. Compras — `ComprasController.adjuntarComprobante` (compras.corregir)
//   2. Pago de Nómina — `NominasController.adjuntarComprobantePagoNomina`
//      (nomina.corregirPago)
//   3. Documento de Vehículo —
//      `adjuntarArchivoDocumentoVehiculoAutorizadoProvider` (vehiculos.operar)
// Etapa 1 (rediseño granular de permisos): los 3 códigos originales
// (compras.crear/nomina.pagar/vehiculos.crear) se dividieron — adjuntar
// comprobante ahora vive bajo la facultad de corrección/operación de
// cada subdominio, nunca bajo la de creación.
// Para cada uno: negativo (sin el permiso → `...ErrorInesperado`, cero
// `Attachment` nuevo) y positivo (con el permiso → éxito, un
// `Attachment` nuevo correctamente ligado).

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/attachments/attachment_storage.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/di/providers.dart';
import 'package:riseg_one/features/compras/compras_providers.dart';
import 'package:riseg_one/features/compras/data/tables/compra_partida_table.dart' show DestinoCompraPartida;
import 'package:riseg_one/features/compras/domain/repositories/compra_repository.dart' show PartidaCompraInput;
import 'package:riseg_one/features/compras/domain/usecases/adjuntar_comprobante_compra_usecase.dart';
import 'package:riseg_one/features/compras/domain/usecases/registrar_compra_usecase.dart';
import 'package:riseg_one/features/compras/presentation/compras_controller.dart';
import 'package:riseg_one/features/finanzas/data/tables/pago_table.dart' show FormaPago;
import 'package:riseg_one/features/nomina/data/tables/nomina_table.dart' show TipoPeriodoNomina;
import 'package:riseg_one/features/nomina/domain/usecases/adjuntar_comprobante_pago_nomina_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/generar_nomina_usecase.dart';
import 'package:riseg_one/features/nomina/domain/usecases/registrar_pago_nomina_usecase.dart';
import 'package:riseg_one/features/nomina/nomina_providers.dart';
import 'package:riseg_one/features/nomina/presentation/nominas/nominas_controller.dart';
import 'package:riseg_one/features/organizacion/organizacion_providers.dart' show attachmentRepositoryProvider, attachmentStorageProvider;
import 'package:riseg_one/features/personal/data/tables/empleado_table.dart';
import 'package:riseg_one/features/personal/domain/usecases/crear_empleado_usecase.dart';
import 'package:riseg_one/features/personal/personal_providers.dart' show crearEmpleadoUseCaseProvider;
import 'package:riseg_one/features/usuarios/domain/sesion_usuario.dart';
import 'package:riseg_one/features/usuarios/presentation/sesion_controller.dart';
import 'package:riseg_one/features/vehiculos/domain/usecases/adjuntar_archivo_documento_vehiculo_usecase.dart';
import 'package:riseg_one/features/vehiculos/domain/usecases/crear_vehiculo_usecase.dart';
import 'package:riseg_one/features/vehiculos/domain/usecases/registrar_documento_vehiculo_usecase.dart';
import 'package:riseg_one/features/vehiculos/vehiculos_providers.dart';
import '../support/sesion_en_base.dart';

class _SesionSinPermisos extends SesionController {
  @override
  SesionUsuario? build() {
    return const SesionUsuario(
      usuarioId: 'usuario-normal',
      nombre: 'Usuario normal',
      nombreUsuario: 'normal',
      esMaestro: false,
      // Ningún permiso de ninguno de los 3 módulos bajo prueba.
      permisos: {},
    );
  }
}

// Etapa 1 (rediseño granular de permisos): adjuntar comprobante de
// Compras/Nómina/Vehículo ahora vive bajo la facultad de corrección de
// cada subdominio (`compras.corregir`/`nomina.corregirPago`/
// `vehiculos.operar`), nunca bajo la de creación.
class _SesionComprasCorregir extends SesionController {
  @override
  SesionUsuario? build() {
    return const SesionUsuario(
      usuarioId: 'usuario-normal',
      nombre: 'Usuario normal',
      nombreUsuario: 'normal',
      esMaestro: false,
      permisos: {'compras.corregir'},
    );
  }
}

class _SesionNominaCorregirPago extends SesionController {
  @override
  SesionUsuario? build() {
    return const SesionUsuario(
      usuarioId: 'usuario-normal',
      nombre: 'Usuario normal',
      nombreUsuario: 'normal',
      esMaestro: false,
      permisos: {'nomina.corregirPago'},
    );
  }
}

class _SesionVehiculosOperar extends SesionController {
  @override
  SesionUsuario? build() {
    return const SesionUsuario(
      usuarioId: 'usuario-normal',
      nombre: 'Usuario normal',
      nombreUsuario: 'normal',
      esMaestro: false,
      permisos: {'vehiculos.operar'},
    );
  }
}

void main() {
  late AppDatabase db;
  late Directory tempDir;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    tempDir = Directory.systemTemp.createTempSync('riseg_adjuntar_comprobante_p0_test_');
  });

  tearDown(() {
    db.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Future<ProviderContainer> containerCon(SesionController Function() sesion) async {
    final container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      sesionControllerProvider.overrideWith(sesion),
      attachmentStorageProvider.overrideWithValue(AttachmentStorage(tempDir.path)),
    ]);
    // Etapa 3B: la autorización se revalida contra la base. Se
    // persiste la sesión que ESTA prueba va a usar, leída del
    // propio contenedor: el escenario sembrado y el inyectado no
    // pueden divergir, y una prueba negativa sigue sin permisos.
    final sesionDeLaPrueba = container.read(sesionControllerProvider);
    if (sesionDeLaPrueba != null) await sembrarSesionEnBase(db, sesionDeLaPrueba);
    return container;
  }

  group('Compras — ComprasController.adjuntarComprobante (compras.corregir)', () {
    late String compraId;

    setUp(() async {
      final seed = ProviderContainer(overrides: [appDatabaseProvider.overrideWithValue(db)]);
      final resultado = await seed.read(registrarCompraUseCaseProvider).ejecutar(
        fecha: DateTime(2026, 8, 10),
        formaPago: FormaPago.efectivo.name,
        partidas: [
          PartidaCompraInput(destino: DestinoCompraPartida.gastoDirecto.name, concepto: 'Papelería', cantidad: 1, costoUnitario: 45000),
        ],
      );
      compraId = (resultado as RegistrarCompraExitosa).compra.id;
      seed.dispose();
    });

    test('un usuario sin compras.corregir no puede adjuntar el comprobante', () async {
      final container = await containerCon(_SesionSinPermisos.new);
      addTearDown(container.dispose);

      final archivo = '${tempDir.path}/factura.pdf';
      File(archivo).writeAsStringSync('contenido factura');

      final resultado = await container.read(comprasControllerProvider.notifier).adjuntarComprobante(
            compraId: compraId,
            sourceFilePath: archivo,
            originalFileName: 'factura.pdf',
            mimeType: 'application/pdf',
          );

      expect(resultado, isA<AdjuntarComprobanteCompraErrorInesperado>());
      expect(
        await container.read(attachmentRepositoryProvider).listarActivosPorCompra(compraId),
        isEmpty,
        reason: 'ningún Attachment nuevo sin el permiso',
      );
    });

    test('un usuario con compras.corregir sí puede adjuntar el comprobante', () async {
      final container = await containerCon(_SesionComprasCorregir.new);
      addTearDown(container.dispose);

      final archivo = '${tempDir.path}/factura.pdf';
      File(archivo).writeAsStringSync('contenido factura');

      final resultado = await container.read(comprasControllerProvider.notifier).adjuntarComprobante(
            compraId: compraId,
            sourceFilePath: archivo,
            originalFileName: 'factura.pdf',
            mimeType: 'application/pdf',
          );

      expect(resultado, isA<AdjuntarComprobanteCompraExitoso>());
      final adjuntos = await container.read(attachmentRepositoryProvider).listarActivosPorCompra(compraId);
      expect(adjuntos, hasLength(1));
      expect(adjuntos.single.originalFileName, 'factura.pdf');
    });
  });

  group('Pago de Nómina — NominasController.adjuntarComprobantePagoNomina (nomina.corregirPago)', () {
    late String pagoNominaId;

    setUp(() async {
      final seed = ProviderContainer(overrides: [appDatabaseProvider.overrideWithValue(db)]);

      final empleado = await seed.read(crearEmpleadoUseCaseProvider).ejecutar(
        nombres: 'Empleado01',
        apellidoPaterno: 'Apellido01',
        sexo: SexoEmpleado.masculino,
        fechaNacimiento: DateTime(1990, 1, 1),
        curp: 'PEXJ900101HDFXXX01',
        rfc: 'PEXJ90010101',
        nss: '10000000001',
        estadoCivil: EstadoCivilEmpleado.soltero,
        fechaIngreso: DateTime(2025, 1, 1),
        aniosExperienciaSeguridad: 3,
        sueldoMensualAdministrativo: 1500000,
      );
      expect(empleado, isA<CrearEmpleadoExitoso>());

      final generado = await seed.read(generarNominaUseCaseProvider).ejecutar(anio: 2026, mes: 1, tipo: TipoPeriodoNomina.primera);
      final nominaId = (generado as GenerarNominaExitoso).nomina.id;
      await seed.read(cerrarNominaUseCaseProvider).ejecutar(nominaId: nominaId);

      final renglon = (await seed.read(nominaRepositoryProvider).listarEmpleados(nominaId)).single;

      final pago = await seed.read(registrarPagoNominaUseCaseProvider).ejecutar(
        nominaId: nominaId,
        fechaPago: DateTime(2026, 1, 20),
        formaPago: 'transferencia',
        cuentaFinancieraId: await _cuentaDePrueba(db),
        aplicaciones: [(nominaEmpleadoId: renglon.id, monto: renglon.totalAPagar)],
      );
      pagoNominaId = (pago as RegistrarPagoNominaExitoso).pagoNomina.id;
      seed.dispose();
    });

    test('un usuario sin nomina.corregirPago no puede adjuntar el comprobante', () async {
      final container = await containerCon(_SesionSinPermisos.new);
      addTearDown(container.dispose);

      final archivo = '${tempDir.path}/comprobante_pago.pdf';
      File(archivo).writeAsStringSync('contenido comprobante');

      final resultado = await container.read(nominasControllerProvider.notifier).adjuntarComprobantePagoNomina(
            pagoNominaId: pagoNominaId,
            sourceFilePath: archivo,
            originalFileName: 'comprobante_pago.pdf',
            mimeType: 'application/pdf',
          );

      expect(resultado, isA<AdjuntarComprobantePagoNominaErrorInesperado>());
      expect(
        await container.read(attachmentRepositoryProvider).listarActivosPorPagoNomina(pagoNominaId),
        isEmpty,
        reason: 'ningún Attachment nuevo sin el permiso',
      );
    });

    test('un usuario con nomina.corregirPago sí puede adjuntar el comprobante', () async {
      final container = await containerCon(_SesionNominaCorregirPago.new);
      addTearDown(container.dispose);

      final archivo = '${tempDir.path}/comprobante_pago.pdf';
      File(archivo).writeAsStringSync('contenido comprobante');

      final resultado = await container.read(nominasControllerProvider.notifier).adjuntarComprobantePagoNomina(
            pagoNominaId: pagoNominaId,
            sourceFilePath: archivo,
            originalFileName: 'comprobante_pago.pdf',
            mimeType: 'application/pdf',
          );

      expect(resultado, isA<AdjuntarComprobantePagoNominaExitoso>());
      final adjuntos = await container.read(attachmentRepositoryProvider).listarActivosPorPagoNomina(pagoNominaId);
      expect(adjuntos, hasLength(1));
      expect(adjuntos.single.originalFileName, 'comprobante_pago.pdf');
    });
  });

  group('Vehículo — adjuntarArchivoDocumentoVehiculoAutorizadoProvider (vehiculos.operar)', () {
    late String vehiculoDocumentoId;

    setUp(() async {
      final seed = ProviderContainer(overrides: [appDatabaseProvider.overrideWithValue(db)]);
      final vehiculo = await seed.read(crearVehiculoUseCaseProvider).ejecutar(marca: 'BMW', modelo: '320i', tipoVehiculo: 'sedan');
      final vehiculoId = (vehiculo as CrearVehiculoExitoso).vehiculo.id;

      final documento = await seed.read(registrarDocumentoVehiculoUseCaseProvider).ejecutar(vehiculoId: vehiculoId, tipo: 'poliza');
      vehiculoDocumentoId = (documento as RegistrarDocumentoVehiculoExitoso).documento.id;
      seed.dispose();
    });

    test('un usuario sin vehiculos.operar no puede adjuntar el archivo del documento', () async {
      final container = await containerCon(_SesionSinPermisos.new);
      addTearDown(container.dispose);

      final archivo = '${tempDir.path}/poliza.pdf';
      File(archivo).writeAsStringSync('contenido poliza');

      final resultado = await container.read(adjuntarArchivoDocumentoVehiculoAutorizadoProvider)(
        vehiculoDocumentoId: vehiculoDocumentoId,
        sourceFilePath: archivo,
        originalFileName: 'poliza.pdf',
        mimeType: 'application/pdf',
      );

      expect(resultado, isA<AdjuntarArchivoDocumentoVehiculoErrorInesperado>());
      expect(
        await container.read(attachmentRepositoryProvider).listarActivosPorVehiculoDocumento(vehiculoDocumentoId),
        isEmpty,
        reason: 'ningún Attachment nuevo sin el permiso',
      );
    });

    test('un usuario con vehiculos.operar sí puede adjuntar el archivo del documento', () async {
      final container = await containerCon(_SesionVehiculosOperar.new);
      addTearDown(container.dispose);

      final archivo = '${tempDir.path}/poliza.pdf';
      File(archivo).writeAsStringSync('contenido poliza');

      final resultado = await container.read(adjuntarArchivoDocumentoVehiculoAutorizadoProvider)(
        vehiculoDocumentoId: vehiculoDocumentoId,
        sourceFilePath: archivo,
        originalFileName: 'poliza.pdf',
        mimeType: 'application/pdf',
      );

      expect(resultado, isA<AdjuntarArchivoDocumentoVehiculoExitoso>());
      final adjuntos = await container.read(attachmentRepositoryProvider).listarActivosPorVehiculoDocumento(vehiculoDocumentoId);
      expect(adjuntos, hasLength(1));
      expect(adjuntos.single.originalFileName, 'poliza.pdf');
    });
  });
}

/// La cuenta de origen de los pagos de Nómina en esta prueba.
///
/// Reutiliza la primera que el archivo ya haya creado; sólo inventa una
/// si no hay ninguna. Desde la Etapa de integridad financiera, un pago
/// de Nómina con monto > 0 exige cuenta: sin ella el Egreso nacería sin
/// origen y ningún saldo bajaría.
Future<String> _cuentaDePrueba(AppDatabase db) async {
  final existentes = await db.select(db.cuentaFinanciera).get();
  if (existentes.isNotEmpty) return existentes.first.id;
  final cuenta = await db.into(db.cuentaFinanciera).insertReturning(
        CuentaFinancieraCompanion.insert(
          codigo: 'CF-NOMINA-PRUEBA',
          nombre: 'Cuenta de prueba',
          tipo: 'banco',
          saldoInicial: 100000000, // fondeada: la v91 rechaza salidas sin saldo
          fechaSaldoInicial: DateTime(2020, 1, 1),
        ),
      );
  return cuenta.id;
}
