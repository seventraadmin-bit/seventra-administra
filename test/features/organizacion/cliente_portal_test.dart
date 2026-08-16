// Etapa 15 (ClientePortal) — pruebas de dominio que no requieren
// pantalla: CRUD completo, contraseña siempre cifrada (nunca en texto
// plano), eliminación física bloqueada por referencias reales,
// edición posterior de un portal sin romper un Documento por emitir ya
// generado, y generación de Agenda propagando `clientePortalId` como
// referencia (nunca snapshot) sin tocar los correos. Los escenarios de
// interacción real de UI (0/1/varios portales, selector de correos)
// viven en `presentation/cliente_portal_configuracion_cobro_widget_test.dart`
// y `presentation/cliente_portal_expediente_widget_test.dart`.

import 'package:drift/drift.dart' show Value, Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/seed/seed_ids.dart';
import 'package:riseg_one/core/database/tables/audit_columns.dart';
import 'package:riseg_one/core/security/credential_cipher.dart';
import 'package:riseg_one/features/organizacion/data/repositories/catalogo_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/cliente_portal_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/cliente_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/configuracion_cobro_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/entidad_fiscal_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_comercial_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/tables/cliente_portal_table.dart';
import 'package:riseg_one/features/organizacion/data/tables/configuracion_cobro_etapa_table.dart';
import 'package:riseg_one/features/organizacion/data/tables/configuracion_cobro_vigencia_table.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/actualizar_cliente_portal_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/cambiar_ciclo_vida_cliente_portal_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/cliente_portal_validator.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/configuracion_cobro_etapa_validator.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/configuracion_cobro_validator.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_cliente_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_cliente_portal_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_configuracion_cobro_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_documento_manual_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_servicio_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/eliminar_cliente_portal_fisicamente_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/ensamblar_documento_por_emitir_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/generar_agenda_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_cliente_portal_resultado.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_servicio_resultado.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/servicio_validator.dart';
import 'package:riseg_one/features/organizacion/data/repositories/documento_por_emitir_repository_impl.dart';
import 'package:riseg_one/core/attachments/attachment_repository.dart';
import 'package:riseg_one/features/finanzas/data/repositories/cuenta_por_cobrar_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/asignacion_servicio_repository_impl.dart';

class _AlmacenClaveCifradoEnMemoria implements AlmacenClaveCifrado {
  String? _clave;

  @override
  Future<String?> leer() async => _clave;

  @override
  Future<void> escribir(String valor) async => _clave = valor;
}

void main() {
  late AppDatabase db;
  late ClientePortalRepositoryImpl portalRepo;
  late CredentialCipher cipher;
  late CrearClientePortalUseCase crearPortal;
  late ActualizarClientePortalUseCase actualizarPortal;
  late CambiarCicloVidaClientePortalUseCase cambiarCicloVidaPortal;
  late EliminarClientePortalFisicamenteUseCase eliminarPortalFisicamente;
  late ClienteRepositoryImpl clienteRepo;
  late ServicioRepositoryImpl servicioRepo;
  late ServicioComercialRepositoryImpl comercialRepo;
  late ConfiguracionCobroRepositoryImpl configuracionCobroRepo;
  late DocumentoPorEmitirRepositoryImpl documentoRepo;
  late CrearServicioUseCase crearServicio;
  late CrearConfiguracionCobroUseCase crearConfiguracionCobro;
  late GenerarAgendaUseCase generarAgenda;
  late CrearDocumentoManualUseCase crearManual;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    portalRepo = ClientePortalRepositoryImpl(db);
    cipher = CredentialCipher(almacen: _AlmacenClaveCifradoEnMemoria());
    clienteRepo = ClienteRepositoryImpl(db);
    servicioRepo = ServicioRepositoryImpl(db, AsignacionServicioRepositoryImpl(db));
    final catalogoRepo = CatalogoRepositoryImpl(db);
    final entidadFiscalRepo = EntidadFiscalRepositoryImpl(db);
    comercialRepo = ServicioComercialRepositoryImpl(db);
    configuracionCobroRepo = ConfiguracionCobroRepositoryImpl(db);
    documentoRepo = DocumentoPorEmitirRepositoryImpl(db, AttachmentRepository(db), CuentaPorCobrarRepositoryImpl(db));

    final validator = ClientePortalValidator(clienteRepo);
    crearPortal = CrearClientePortalUseCase(portalRepo, validator, cipher);
    actualizarPortal = ActualizarClientePortalUseCase(portalRepo, validator, cipher);
    cambiarCicloVidaPortal = CambiarCicloVidaClientePortalUseCase(portalRepo);
    eliminarPortalFisicamente = EliminarClientePortalFisicamenteUseCase(portalRepo);

    final servicioValidator = ServicioValidator(clienteRepo, catalogoRepo);
    final configuracionCobroValidator =
        ConfiguracionCobroValidator(servicioRepo, entidadFiscalRepo, catalogoRepo, comercialRepo, portalRepo);
    crearServicio = CrearServicioUseCase(servicioRepo, GenerarCodigoUseCase(CodigoSecuenciaService(db)), servicioValidator);
    crearConfiguracionCobro = CrearConfiguracionCobroUseCase(
      configuracionCobroRepo,
      servicioRepo,
      configuracionCobroValidator,
      const ConfiguracionCobroEtapaValidator(),
    );

    final ensamblar = EnsamblarDocumentoPorEmitirUseCase(comercialRepo, configuracionCobroRepo);
    final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));
    generarAgenda = GenerarAgendaUseCase(documentoRepo, configuracionCobroRepo, servicioRepo, ensamblar, generarCodigo);
    crearManual = CrearDocumentoManualUseCase(documentoRepo, configuracionCobroRepo, ensamblar, generarCodigo);
  });

  tearDown(() => db.close());

  Future<String> crearClienteDePrueba() async {
    final resultado = await CrearClienteUseCase(clienteRepo, GenerarCodigoUseCase(CodigoSecuenciaService(db)))
        .ejecutar(nombreComercial: 'Sportium');
    return resultado.when(ok: (c) => c.id, failure: (_) => throw StateError('no debería fallar'));
  }

  group('CRUD básico', () {
    test('crear un portal exitosamente', () async {
      final clienteId = await crearClienteDePrueba();
      final resultado = await crearPortal.ejecutar(
        clienteId: clienteId,
        borrador: const ClientePortalBorrador(nombre: 'Portal Facturación', tipo: TipoPortalCliente.facturacion),
      );
      expect(resultado, isA<GuardarClientePortalExitoso>());
      final portal = (resultado as GuardarClientePortalExitoso).portal;
      expect(portal.nombre, 'Portal Facturación');
      expect(portal.tipo, TipoPortalCliente.facturacion.name);
      expect(portal.cicloVidaRegistro, CicloVidaRegistro.activo.name);
    });

    test('nombre vacío es rechazado', () async {
      final clienteId = await crearClienteDePrueba();
      final resultado = await crearPortal.ejecutar(
        clienteId: clienteId,
        borrador: const ClientePortalBorrador(nombre: '  ', tipo: TipoPortalCliente.otro),
      );
      expect(resultado, isA<GuardarClientePortalErroresValidacion>());
    });

    test('archivar y reactivar siempre están permitidos', () async {
      final clienteId = await crearClienteDePrueba();
      final creado = (await crearPortal.ejecutar(
        clienteId: clienteId,
        borrador: const ClientePortalBorrador(nombre: 'Portal', tipo: TipoPortalCliente.otro),
      )) as GuardarClientePortalExitoso;

      final archivado = await cambiarCicloVidaPortal.ejecutar(clientePortalId: creado.portal.id, nuevo: CicloVidaRegistro.archivado);
      expect(archivado, isA<CambiarCicloVidaClientePortalExitoso>());

      final reactivado = await cambiarCicloVidaPortal.ejecutar(clientePortalId: creado.portal.id, nuevo: CicloVidaRegistro.activo);
      expect(reactivado, isA<CambiarCicloVidaClientePortalExitoso>());
    });

    test('un portal archivado es de solo consulta — actualizar lo rechaza', () async {
      final clienteId = await crearClienteDePrueba();
      final creado = (await crearPortal.ejecutar(
        clienteId: clienteId,
        borrador: const ClientePortalBorrador(nombre: 'Portal', tipo: TipoPortalCliente.otro),
      )) as GuardarClientePortalExitoso;
      await cambiarCicloVidaPortal.ejecutar(clientePortalId: creado.portal.id, nuevo: CicloVidaRegistro.archivado);

      final resultado = await actualizarPortal.ejecutar(
        id: creado.portal.id,
        borrador: const ClientePortalBorrador(nombre: 'Portal renombrado', tipo: TipoPortalCliente.otro),
      );
      expect(resultado, isA<GuardarClientePortalArchivado>());
    });
  });

  group('Contraseña — siempre cifrada, nunca en texto plano (Marlon: "nunca en claro en BD")', () {
    test('al crear con contraseña, la fila en BD nunca contiene el texto plano', () async {
      final clienteId = await crearClienteDePrueba();
      const plano = 'Sup3rSecreta!2026';
      final creado = (await crearPortal.ejecutar(
        clienteId: clienteId,
        borrador: const ClientePortalBorrador(nombre: 'Portal', tipo: TipoPortalCliente.otro, contrasenaNueva: plano),
      )) as GuardarClientePortalExitoso;

      final filaCruda = await db
          .customSelect('SELECT contrasena_cifrada FROM cliente_portal WHERE id = ?', variables: [Variable(creado.portal.id)])
          .getSingle();
      final cifrado = filaCruda.data['contrasena_cifrada'] as String;

      expect(cifrado, isNot(equals(plano)));
      expect(cifrado.contains(plano), isFalse);
      expect(cifrado, startsWith('aesgcm\$1\$'));
      expect(await cipher.descifrar(cifrado), plano);
    });

    test('editar sin capturar una contraseña nueva conserva el cifrado existente intacto', () async {
      final clienteId = await crearClienteDePrueba();
      final creado = (await crearPortal.ejecutar(
        clienteId: clienteId,
        borrador: const ClientePortalBorrador(nombre: 'Portal', tipo: TipoPortalCliente.otro, contrasenaNueva: 'Original123'),
      )) as GuardarClientePortalExitoso;
      final cifradoOriginal = creado.portal.contrasenaCifrada;

      final actualizado = (await actualizarPortal.ejecutar(
        id: creado.portal.id,
        borrador: const ClientePortalBorrador(nombre: 'Portal renombrado', tipo: TipoPortalCliente.otro),
      )) as GuardarClientePortalExitoso;

      expect(actualizado.portal.contrasenaCifrada, cifradoOriginal);
      expect(await cipher.descifrar(actualizado.portal.contrasenaCifrada!), 'Original123');
    });

    test('editar con una contraseña nueva la reemplaza (nunca conserva la anterior)', () async {
      final clienteId = await crearClienteDePrueba();
      final creado = (await crearPortal.ejecutar(
        clienteId: clienteId,
        borrador: const ClientePortalBorrador(nombre: 'Portal', tipo: TipoPortalCliente.otro, contrasenaNueva: 'Original123'),
      )) as GuardarClientePortalExitoso;

      final actualizado = (await actualizarPortal.ejecutar(
        id: creado.portal.id,
        borrador: const ClientePortalBorrador(nombre: 'Portal', tipo: TipoPortalCliente.otro, contrasenaNueva: 'Nueva456'),
      )) as GuardarClientePortalExitoso;

      expect(actualizado.portal.contrasenaCifrada, isNot(equals(creado.portal.contrasenaCifrada)));
      expect(await cipher.descifrar(actualizado.portal.contrasenaCifrada!), 'Nueva456');
    });
  });

  group('Eliminación física — bloqueada si hay referencias reales', () {
    Future<({String servicioId, String vigenciaId})> crearServicioConPortalReferenciado(String clienteId, String portalId) async {
      final creado = await crearServicio.ejecutar(
        clienteId: clienteId,
        borrador: ServicioBorrador(
          nombre: 'Club Sportium',
          tipoServicioId: SeedIds.tipoServicioVigilanciaFija,
          fechaInicio: DateTime(2026, 1, 1),
        ),
      );
      final servicioId = (creado as GuardarServicioExitoso).servicio.id;

      final resultado = await crearConfiguracionCobro.ejecutar(
        servicioId: servicioId,
        borrador: ConfiguracionCobroBorrador(
          tipoDocumento: TipoDocumentoCobro.reciboDePago,
          frecuenciaId: SeedIds.frecuenciaCobroMensual,
          diaInicioPeriodo: 1,
          agrupacion: AgrupacionCobro.porServicio,
          metodo: MetodoPagoCobro.noAplica,
          requiereComplemento: false,
          fechaInicioVigencia: DateTime(2026, 1, 1),
          clientePortalId: portalId,
        ),
        etapas: const [],
      );
      final vigenciaId =
          (resultado as CrearConfiguracionCobroExitoso).vigencia.id;
      return (servicioId: servicioId, vigenciaId: vigenciaId);
    }

    test('rechazada cuando una ConfiguracionCobroVigencia lo referencia', () async {
      final clienteId = await crearClienteDePrueba();
      final creado = (await crearPortal.ejecutar(
        clienteId: clienteId,
        borrador: const ClientePortalBorrador(nombre: 'Portal', tipo: TipoPortalCliente.otro),
      )) as GuardarClientePortalExitoso;
      await crearServicioConPortalReferenciado(clienteId, creado.portal.id);

      final resultado = await eliminarPortalFisicamente.ejecutar(clientePortalId: creado.portal.id, motivo: 'prueba');
      expect(resultado, isA<EliminarClientePortalFisicamenteTieneDependencias>());

      // Sigue existiendo — el rechazo no tuvo efectos secundarios.
      expect(await portalRepo.obtenerPorId(creado.portal.id), isNotNull);
    });

    test('permitida cuando no hay ninguna referencia', () async {
      final clienteId = await crearClienteDePrueba();
      final creado = (await crearPortal.ejecutar(
        clienteId: clienteId,
        borrador: const ClientePortalBorrador(nombre: 'Portal sin uso', tipo: TipoPortalCliente.otro),
      )) as GuardarClientePortalExitoso;

      final resultado = await eliminarPortalFisicamente.ejecutar(clientePortalId: creado.portal.id, motivo: 'prueba');
      expect(resultado, isA<EliminarClientePortalFisicamenteExitoso>());
      expect(await portalRepo.obtenerPorId(creado.portal.id), isNull);
    });

    test('archivar un portal referenciado sí está permitido — el histórico sigue resolviendo el nombre', () async {
      final clienteId = await crearClienteDePrueba();
      final creado = (await crearPortal.ejecutar(
        clienteId: clienteId,
        borrador: const ClientePortalBorrador(nombre: 'Portal SIPOT', tipo: TipoPortalCliente.otro),
      )) as GuardarClientePortalExitoso;
      final servicio = await crearServicioConPortalReferenciado(clienteId, creado.portal.id);

      final archivado = await cambiarCicloVidaPortal.ejecutar(clientePortalId: creado.portal.id, nuevo: CicloVidaRegistro.archivado);
      expect(archivado, isA<CambiarCicloVidaClientePortalExitoso>());

      final vigenciaConDetalle = await configuracionCobroRepo.obtenerConfiguracion(servicio.servicioId);
      expect(vigenciaConDetalle!.clientePortalNombre, 'Portal SIPOT');
    });
  });

  test(
    'editar un portal (nombre y URL) después de generar un Documento no rompe la referencia — el Documento sigue '
    'resolviendo el portal, ya con los datos actualizados (referencia, nunca snapshot)',
    () async {
      final clienteId = await crearClienteDePrueba();
      final creado = (await crearPortal.ejecutar(
        clienteId: clienteId,
        borrador: const ClientePortalBorrador(nombre: 'Portal viejo', tipo: TipoPortalCliente.otro, url: 'https://viejo.example.com'),
      )) as GuardarClientePortalExitoso;

      final creadoServicio = await crearServicio.ejecutar(
        clienteId: clienteId,
        borrador: ServicioBorrador(
          nombre: 'Club Sportium',
          tipoServicioId: SeedIds.tipoServicioVigilanciaFija,
          fechaInicio: DateTime(2026, 1, 1),
        ),
      );
      final servicioId = (creadoServicio as GuardarServicioExitoso).servicio.id;
      await crearConfiguracionCobro.ejecutar(
        servicioId: servicioId,
        borrador: ConfiguracionCobroBorrador(
          tipoDocumento: TipoDocumentoCobro.reciboDePago,
          frecuenciaId: SeedIds.frecuenciaCobroMensual,
          diaInicioPeriodo: 1,
          agrupacion: AgrupacionCobro.porServicio,
          metodo: MetodoPagoCobro.noAplica,
          requiereComplemento: false,
          fechaInicioVigencia: DateTime(2026, 1, 1),
          clientePortalId: creado.portal.id,
        ),
        etapas: const [],
      );

      final documentoResultado = await crearManual.ejecutar(
        clienteId: clienteId,
        servicioIds: [servicioId],
        periodoInicio: DateTime(2026, 1, 1),
        periodoFin: DateTime(2026, 1, 31),
      );
      expect(documentoResultado, isA<CrearDocumentoManualExitoso>());
      final documento = (documentoResultado as CrearDocumentoManualExitoso).documento;
      expect(documento.clientePortalId, creado.portal.id);

      // Se edita el portal después de que el Documento ya existe.
      await actualizarPortal.ejecutar(
        id: creado.portal.id,
        borrador: const ClientePortalBorrador(nombre: 'Portal nuevo', tipo: TipoPortalCliente.otro, url: 'https://nuevo.example.com'),
      );

      // El Documento sigue apuntando al mismo id — nunca se rompió la
      // referencia — y al resolverla ve el valor actual del portal.
      final documentoReleido = await documentoRepo.obtenerPorId(documento.id);
      expect(documentoReleido!.clientePortalId, creado.portal.id);
      final portalActual = await portalRepo.obtenerPorId(documentoReleido.clientePortalId!);
      expect(portalActual!.nombre, 'Portal nuevo');
      expect(portalActual.url, 'https://nuevo.example.com');
    },
  );

  test(
    'Agenda: el Documento generado hereda clientePortalId de la vigencia usada, sin tocar los correos capturados',
    () async {
      final clienteId = await crearClienteDePrueba();
      final creadoPortal = (await crearPortal.ejecutar(
        clienteId: clienteId,
        borrador: const ClientePortalBorrador(nombre: 'Portal Sportium', tipo: TipoPortalCliente.facturacion),
      )) as GuardarClientePortalExitoso;

      final creadoServicio = await crearServicio.ejecutar(
        clienteId: clienteId,
        borrador: ServicioBorrador(
          nombre: 'Club Sportium',
          tipoServicioId: SeedIds.tipoServicioVigilanciaFija,
          fechaInicio: DateTime(2026, 1, 1),
        ),
      );
      final servicioId = (creadoServicio as GuardarServicioExitoso).servicio.id;

      await crearConfiguracionCobro.ejecutar(
        servicioId: servicioId,
        borrador: ConfiguracionCobroBorrador(
          tipoDocumento: TipoDocumentoCobro.reciboDePago,
          frecuenciaId: SeedIds.frecuenciaCobroMensual,
          diaInicioPeriodo: 1,
          agrupacion: AgrupacionCobro.porServicio,
          metodo: MetodoPagoCobro.noAplica,
          requiereComplemento: false,
          fechaInicioVigencia: DateTime(2026, 1, 1),
          clientePortalId: creadoPortal.portal.id,
          correos: const ['facturacion@sportium.mx', 'ana.ruiz@sportium.mx'],
        ),
        etapas: const [
          EtapaCobroBorrador(
            id: 'etapa-emision',
            tipoSistema: TipoEventoCobro.emision,
            orden: 0,
            tipoRegla: TipoReglaEvento.diaFijoDelMes,
            mesRelativo: MesRelativoCobro.actual,
            diaDelMes: 1,
          ),
        ],
      );

      final resultado = await generarAgenda.ejecutar(rangoInicio: DateTime(2026, 1, 1), rangoFin: DateTime(2026, 1, 31));
      expect(resultado.creados, hasLength(1));
      final documento = resultado.creados.single;

      expect(documento.clientePortalId, creadoPortal.portal.id);
      final detalle = await documentoRepo.obtenerDetalle(documento.id);
      expect(detalle!.correos, unorderedEquals(['facturacion@sportium.mx', 'ana.ruiz@sportium.mx']));
    },
  );

  test(
    'Cadena completa: Cliente → Contactos + ClientePortal → Servicio → Configuración de cobro → Agenda → '
    'DocumentoPorEmitir — varios correos existentes + uno extraordinario, portal seleccionado, contraseña '
    'cifrada, clientePortalId propagado como referencia, correos exactos, contraseña nunca en ningún snapshot',
    () async {
      const contrasenaPlano = 'AccesoSIPOT-2026!';

      // 1. Cliente.
      final clienteId = await crearClienteDePrueba();

      // 2. Contactos — 2 con correo (uno de ellos con puesto), 1 sin
      // correo (nunca debe aparecer en el resultado).
      final contactoFacturacion = await clienteRepo.agregarContacto(
        ContactoCompanion.insert(
          clienteId: clienteId,
          nombre: 'Ana Ruiz',
          tipo: 'comercial',
          puesto: const Value('Contadora'),
          correo: const Value('facturacion@sportium.mx'),
        ),
      );
      final contactoOperaciones = await clienteRepo.agregarContacto(
        ContactoCompanion.insert(clienteId: clienteId, nombre: 'Luis Pérez', tipo: 'operativo', correo: const Value('ops@sportium.mx')),
      );
      await clienteRepo.agregarContacto(
        ContactoCompanion.insert(clienteId: clienteId, nombre: 'Sin correo', tipo: 'comercial'),
      );

      // 3. ClientePortal, con contraseña — cifrada por el propio caso
      // de uso, nunca a mano.
      final creadoPortal = (await crearPortal.ejecutar(
        clienteId: clienteId,
        borrador: const ClientePortalBorrador(
          nombre: 'Portal SIPOT',
          tipo: TipoPortalCliente.facturacion,
          url: 'https://sipot.sportium.mx',
          usuario: 'sportium_admin',
          contrasenaNueva: contrasenaPlano,
        ),
      )) as GuardarClientePortalExitoso;

      // La contraseña ya quedó cifrada en BD — nunca el texto plano —
      // antes incluso de tocar Servicio/Configuración de cobro/Agenda.
      final filaPortalCruda = await db
          .customSelect('SELECT contrasena_cifrada FROM cliente_portal WHERE id = ?', variables: [Variable(creadoPortal.portal.id)])
          .getSingle();
      final contrasenaCifradaEnBd = filaPortalCruda.data['contrasena_cifrada'] as String;
      expect(contrasenaCifradaEnBd, isNot(equals(contrasenaPlano)));
      expect(contrasenaCifradaEnBd.contains(contrasenaPlano), isFalse);
      expect(await cipher.descifrar(contrasenaCifradaEnBd), contrasenaPlano);

      // 4. Servicio.
      final creadoServicio = await crearServicio.ejecutar(
        clienteId: clienteId,
        borrador: ServicioBorrador(
          nombre: 'Club Sportium Coyoacán',
          tipoServicioId: SeedIds.tipoServicioVigilanciaFija,
          fechaInicio: DateTime(2026, 1, 1),
        ),
      );
      final servicioId = (creadoServicio as GuardarServicioExitoso).servicio.id;

      // 5. Configuración de cobro: selecciona los 2 correos de Contacto
      // ya existentes + 1 correo extraordinario que no pertenece a
      // ningún Contacto (mismo criterio que el selector múltiple +
      // "Agregar otro correo" de la UI real — a nivel de dominio,
      // ambos orígenes son indistinguibles: una lista de strings), y
      // referencia el `ClientePortal` recién creado.
      const correoExtraordinario = 'urgencias-facturacion@externo.mx';
      final resultadoConfiguracion = await crearConfiguracionCobro.ejecutar(
        servicioId: servicioId,
        borrador: ConfiguracionCobroBorrador(
          tipoDocumento: TipoDocumentoCobro.reciboDePago,
          frecuenciaId: SeedIds.frecuenciaCobroMensual,
          diaInicioPeriodo: 1,
          agrupacion: AgrupacionCobro.porServicio,
          metodo: MetodoPagoCobro.noAplica,
          requiereComplemento: false,
          fechaInicioVigencia: DateTime(2026, 1, 1),
          clientePortalId: creadoPortal.portal.id,
          correos: [contactoFacturacion.correo!, contactoOperaciones.correo!, correoExtraordinario],
        ),
        etapas: const [
          EtapaCobroBorrador(
            id: 'etapa-emision-cadena',
            tipoSistema: TipoEventoCobro.emision,
            orden: 0,
            tipoRegla: TipoReglaEvento.diaFijoDelMes,
            mesRelativo: MesRelativoCobro.actual,
            diaDelMes: 1,
          ),
        ],
      );
      expect(resultadoConfiguracion, isA<CrearConfiguracionCobroExitoso>());
      final vigenciaGuardada = (resultadoConfiguracion as CrearConfiguracionCobroExitoso).vigencia;

      // Configuración guarda la referencia — nunca los datos del portal.
      expect(vigenciaGuardada.clientePortalId, creadoPortal.portal.id);

      // 6. Agenda genera el DocumentoPorEmitir.
      final resultadoAgenda = await generarAgenda.ejecutar(rangoInicio: DateTime(2026, 1, 1), rangoFin: DateTime(2026, 1, 31));
      expect(resultadoAgenda.creados, hasLength(1));
      final documento = resultadoAgenda.creados.single;

      // El Documento hereda exactamente el mismo clientePortalId — una
      // referencia, nunca un snapshot de los datos del portal.
      expect(documento.clientePortalId, creadoPortal.portal.id);

      // DocumentoPorEmitirCorreo contiene exactamente los 3 correos
      // configurados — ni de más ni de menos.
      final detalle = await documentoRepo.obtenerDetalle(documento.id);
      expect(
        detalle!.correos,
        unorderedEquals([contactoFacturacion.correo, contactoOperaciones.correo, correoExtraordinario]),
      );

      // La contraseña nunca aparece en ningún snapshot de Agenda:
      // recorre todos los valores de texto de la fila principal, sus
      // correos y sus hitos, buscando el texto plano.
      bool contieneContrasena(Object? valor) => valor is String && valor.contains(contrasenaPlano);

      final filaDocumento =
          await db.customSelect('SELECT * FROM documento_por_emitir WHERE id = ?', variables: [Variable(documento.id)]).getSingle();
      expect(filaDocumento.data.values.any(contieneContrasena), isFalse, reason: 'DocumentoPorEmitir nunca contiene la contraseña');

      final filasCorreo = await db
          .customSelect('SELECT * FROM documento_por_emitir_correo WHERE documento_por_emitir_id = ?', variables: [Variable(documento.id)])
          .get();
      for (final fila in filasCorreo) {
        expect(fila.data.values.any(contieneContrasena), isFalse, reason: 'DocumentoPorEmitirCorreo nunca contiene la contraseña');
      }

      final filasHito = await db
          .customSelect('SELECT * FROM documento_por_emitir_hito WHERE documento_por_emitir_id = ?', variables: [Variable(documento.id)])
          .get();
      for (final fila in filasHito) {
        expect(fila.data.values.any(contieneContrasena), isFalse, reason: 'DocumentoPorEmitirHito nunca contiene la contraseña');
      }

      // Tampoco en las columnas legacy de la propia vigencia usada —
      // esta configuración nueva nunca las escribió.
      final filaVigencia = await db
          .customSelect('SELECT portal_nombre, portal_url, portal_usuario, portal_contrasena, portal_observaciones FROM configuracion_cobro_vigencia WHERE id = ?', variables: [Variable(vigenciaGuardada.id)])
          .getSingle();
      expect(filaVigencia.data.values.every((v) => v == null), isTrue, reason: 'ningún flujo nuevo escribe las columnas legacy');
    },
  );
}
