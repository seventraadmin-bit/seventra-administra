// Trazabilidad de Comercial — Tajada 2: Configuración comercial
// (líneas y vigencias), Configuración de cobro y Contactos.
//
// Hueco que cierra: la Tajada 1 dejó auditados Cliente, Entidad fiscal
// y el encabezado del Servicio, pero LO QUE SE COBRA seguía pudiendo
// cambiar sin rastro — precio, cantidad de elementos, turno,
// tratamiento de IVA, frecuencia de facturación, método de pago y las
// reglas temporales de emisión/pago. Y los Contactos del Cliente, que
// son con quién se trata el Servicio, tampoco dejaban huella.
//
// Lo que estas pruebas protegen:
//   1. NUEVA VIGENCIA ≠ CORRECCIÓN. Abrir una vigencia nueva jamás se
//      registra como corrección, y una corrección jamás abre vigencia.
//      Un mismo hecho no genera dos eventos.
//   2. La vigencia anterior conserva sus condiciones económicas
//      intactas: el relevo sólo le pone fecha de fin.
//   3. El diff de una corrección trae SÓLO los campos que cambiaron.
//   4. `EtapaCobroBorrador.id` es correlación de lote, NUNCA clave
//      primaria persistida — la regresión del caso MORGAN.
//   5. PUE nunca exige Complemento; PPD sí, con la regla ya vigente.
//   6. En Auditoría central, teléfono y correo de Contacto aparecen
//      enmascarados: la bitácora no es un segundo directorio.

import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/auditoria/enmascarar_identificador.dart';
import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/seed/seed_ids.dart';
import 'package:riseg_one/core/database/tables/audit_columns.dart';
import 'package:riseg_one/core/utils/clock.dart';
import 'package:riseg_one/features/organizacion/data/repositories/catalogo_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/cliente_portal_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/cliente_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/configuracion_cobro_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/entidad_fiscal_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/puesto_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_comercial_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/tables/comercial_evento_table.dart';
import 'package:riseg_one/features/organizacion/data/tables/configuracion_cobro_etapa_table.dart';
import 'package:riseg_one/features/organizacion/data/tables/configuracion_cobro_vigencia_table.dart';
import 'package:riseg_one/features/organizacion/data/tables/contacto_table.dart';
import 'package:riseg_one/features/organizacion/data/tables/servicio_linea_comercial_vigencia_table.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/actualizar_contacto_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/agregar_contacto_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/archivar_contacto_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/asignar_entidad_fiscal_a_servicio_usecase.dart';
import 'package:riseg_one/core/security/credential_cipher.dart';
import 'package:riseg_one/features/organizacion/data/tables/cliente_portal_table.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/actualizar_cliente_portal_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/cambiar_ciclo_vida_cliente_portal_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/cambiar_vigencia_configuracion_cobro_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/cliente_portal_validator.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_cliente_portal_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_cliente_portal_resultado.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/cambiar_vigencia_linea_comercial_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/cancelar_vigencia_programada_configuracion_cobro_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/cancelar_vigencia_programada_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/cerrar_configuracion_cobro_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/cerrar_linea_comercial_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/configuracion_cobro_etapa_validator.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/configuracion_cobro_validator.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/contacto_validator.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/corregir_configuracion_cobro_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/corregir_linea_comercial_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_configuracion_cobro_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_entidad_fiscal_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_linea_comercial_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_servicio_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/entidad_fiscal_validator.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_contacto_resultado.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_entidad_fiscal_resultado.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_servicio_resultado.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/linea_comercial_validator.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/servicio_validator.dart';
import 'package:riseg_one/features/personal/data/repositories/asignacion_servicio_repository_impl.dart';
import 'package:riseg_one/features/usuarios/data/repositories/auditoria_repository_impl.dart';
import 'package:riseg_one/app/shell/shell_permissions.dart';
import 'package:riseg_one/features/usuarios/domain/usecases/buscar_auditoria_usecase.dart';
import 'package:riseg_one/features/usuarios/domain/usecases/destino_auditoria.dart';

const _actor = 'usuario-auditor';

class _AlmacenClaveCifradoEnMemoria implements AlmacenClaveCifrado {
  String? _clave;

  @override
  Future<String?> leer() async => _clave;

  @override
  Future<void> escribir(String valor) async => _clave = valor;
}

class _RelojFijo implements Clock {
  _RelojFijo(this._fecha);
  final DateTime _fecha;

  @override
  DateTime now() => _fecha;
}

void main() {
  late AppDatabase db;
  late ClienteRepositoryImpl clienteRepo;
  late ServicioRepositoryImpl servicioRepo;
  late PuestoRepositoryImpl puestoRepo;
  late CatalogoRepositoryImpl catalogoRepo;
  late ServicioComercialRepositoryImpl comercialRepo;
  late ConfiguracionCobroRepositoryImpl cobroRepo;
  late EntidadFiscalRepositoryImpl entidadFiscalRepo;
  late AuditoriaRepositoryImpl auditoriaRepo;

  late CrearServicioUseCase crearServicio;
  late CrearLineaComercialUseCase crearLinea;
  late CambiarVigenciaLineaComercialUseCase cambiarVigenciaLinea;
  late CorregirLineaComercialUseCase corregirLinea;
  late CerrarLineaComercialUseCase cerrarLinea;
  late CancelarVigenciaProgramadaUseCase cancelarProgramadaLinea;

  late CrearConfiguracionCobroUseCase crearCobro;
  late CambiarVigenciaConfiguracionCobroUseCase cambiarVigenciaCobro;
  late CorregirConfiguracionCobroUseCase corregirCobro;
  late CerrarConfiguracionCobroUseCase cerrarCobro;
  late CancelarVigenciaProgramadaConfiguracionCobroUseCase cancelarProgramadaCobro;

  late AgregarContactoUseCase agregarContacto;
  late ActualizarContactoUseCase actualizarContacto;
  late ArchivarContactoUseCase archivarContacto;

  late CrearEntidadFiscalUseCase crearEntidadFiscal;

  late CrearClientePortalUseCase crearPortal;
  late ActualizarClientePortalUseCase actualizarPortal;
  late CambiarCicloVidaClientePortalUseCase cambiarCicloVidaPortal;

  // "Hoy" fijo: 15 de agosto de 2026 — nada depende del reloj real.
  final hoy = DateTime(2026, 8, 15);
  var consecutivo = 0;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.into(db.usuario).insert(
          UsuarioCompanion.insert(
            id: const Value(_actor),
            nombre: 'Auditor de prueba',
            nombreUsuario: 'auditor',
            passwordHash: 'x',
            esMaestro: const Value(true),
          ),
        );

    final clock = _RelojFijo(hoy);
    clienteRepo = ClienteRepositoryImpl(db);
    servicioRepo = ServicioRepositoryImpl(db, AsignacionServicioRepositoryImpl(db));
    puestoRepo = PuestoRepositoryImpl(db);
    catalogoRepo = CatalogoRepositoryImpl(db);
    comercialRepo = ServicioComercialRepositoryImpl(db, clock: clock);
    cobroRepo = ConfiguracionCobroRepositoryImpl(db, clock: clock);
    entidadFiscalRepo = EntidadFiscalRepositoryImpl(db);
    auditoriaRepo = AuditoriaRepositoryImpl(db);

    final generarCodigo = GenerarCodigoUseCase(CodigoSecuenciaService(db));
    final servicioValidator = ServicioValidator(clienteRepo, catalogoRepo);
    final lineaValidator = LineaComercialValidator(puestoRepo, catalogoRepo, servicioRepo, cobroRepo);
    final cobroValidator = ConfiguracionCobroValidator(
      servicioRepo,
      entidadFiscalRepo,
      catalogoRepo,
      comercialRepo,
      ClientePortalRepositoryImpl(db),
    );
    const etapaValidator = ConfiguracionCobroEtapaValidator();

    crearServicio = CrearServicioUseCase(servicioRepo, generarCodigo, servicioValidator);
    crearLinea = CrearLineaComercialUseCase(comercialRepo, servicioRepo, lineaValidator);
    cambiarVigenciaLinea = CambiarVigenciaLineaComercialUseCase(comercialRepo, servicioRepo, lineaValidator);
    corregirLinea = CorregirLineaComercialUseCase(comercialRepo, lineaValidator);
    cerrarLinea = CerrarLineaComercialUseCase(comercialRepo, clock);
    cancelarProgramadaLinea = CancelarVigenciaProgramadaUseCase(comercialRepo, clock);

    crearCobro = CrearConfiguracionCobroUseCase(cobroRepo, servicioRepo, cobroValidator, etapaValidator);
    cambiarVigenciaCobro =
        CambiarVigenciaConfiguracionCobroUseCase(cobroRepo, servicioRepo, cobroValidator, etapaValidator);
    corregirCobro = CorregirConfiguracionCobroUseCase(cobroRepo, cobroValidator, etapaValidator);
    cerrarCobro = CerrarConfiguracionCobroUseCase(cobroRepo, clock);
    cancelarProgramadaCobro = CancelarVigenciaProgramadaConfiguracionCobroUseCase(cobroRepo, clock);

    agregarContacto = AgregarContactoUseCase(clienteRepo);
    actualizarContacto = ActualizarContactoUseCase(clienteRepo);
    archivarContacto = ArchivarContactoUseCase(clienteRepo);

    crearEntidadFiscal = CrearEntidadFiscalUseCase(
      entidadFiscalRepo,
      generarCodigo,
      EntidadFiscalValidator(clienteRepo, entidadFiscalRepo),
    );
    final portalRepo = ClientePortalRepositoryImpl(db);
    final cipher = CredentialCipher(almacen: _AlmacenClaveCifradoEnMemoria());
    final portalValidator = ClientePortalValidator(clienteRepo);
    crearPortal = CrearClientePortalUseCase(portalRepo, portalValidator, cipher);
    actualizarPortal = ActualizarClientePortalUseCase(portalRepo, portalValidator, cipher);
    cambiarCicloVidaPortal = CambiarCicloVidaClientePortalUseCase(portalRepo);

    consecutivo = 0;
  });

  tearDown(() => db.close());

  // ---------------------------------------------------------------
  // Andamiaje
  // ---------------------------------------------------------------

  Future<ClienteData> crearCliente({String nombre = 'Sportium'}) {
    final n = (++consecutivo).toString().padLeft(6, '0');
    return clienteRepo.crear(ClienteCompanion.insert(codigo: 'CLI-$n', nombreComercial: nombre));
  }

  Future<ServicioData> crearServicioDe(String clienteId) async {
    final creado = await crearServicio.ejecutar(
      clienteId: clienteId,
      borrador: ServicioBorrador(
        nombre: 'Vigilancia Satélite',
        tipoServicioId: SeedIds.tipoServicioVigilanciaFija,
        fechaInicio: DateTime(2026, 1, 1),
      ),
    );
    return (creado as GuardarServicioExitoso).servicio;
  }

  Future<PuestoData> crearPuesto({String codigo = 'PUE-0001', String nombre = 'Guardia'}) {
    return puestoRepo.crear(
      PuestoCompanion.insert(
        codigo: codigo,
        nombre: nombre,
        areaId: SeedIds.areaOperaciones,
        tipo: 'operativo',
        nivelJerarquico: 5,
      ),
    );
  }

  Future<List<ServicioEventoData>> eventosDeServicio(String servicioId) {
    return (db.select(db.servicioEvento)..where((t) => t.servicioId.equals(servicioId))).get();
  }

  Future<List<ServicioEventoData>> eventosDeServicioDeTipo(String servicioId, TipoEventoServicio tipo) async {
    final todos = await eventosDeServicio(servicioId);
    return todos.where((e) => e.tipoEvento == tipo.name).toList();
  }

  Future<List<ConfiguracionCobroEventoData>> eventosDeCobro(String configuracionId) {
    return (db.select(db.configuracionCobroEvento)
          ..where((t) => t.configuracionCobroId.equals(configuracionId)))
        .get();
  }

  Future<List<ClienteEventoData>> eventosDeCliente(String clienteId) {
    return (db.select(db.clienteEvento)..where((t) => t.clienteId.equals(clienteId))).get();
  }

  Map<String, dynamic> json(String? texto) => jsonDecode(texto!) as Map<String, dynamic>;

  LineaComercialBorrador borradorLinea({
    required String puestoId,
    String? modalidadTurnoId,
    int cantidad = 2,
    int precio = 1500000,
    TratamientoIva iva = TratamientoIva.masIva,
    DateTime? desde,
  }) {
    return LineaComercialBorrador(
      puestoId: puestoId,
      modalidadTurnoId: modalidadTurnoId ?? SeedIds.modalidadTurno24x24,
      cantidadElementos: cantidad,
      precioUnitario: precio,
      tratamientoIva: iva,
      fechaInicioVigencia: desde ?? DateTime(2026, 1, 1),
    );
  }

  Future<({ServicioData servicio, String lineaId, PuestoData puesto})> servicioConLinea() async {
    final cliente = await crearCliente();
    final servicio = await crearServicioDe(cliente.id);
    final puesto = await crearPuesto();
    final creada = await crearLinea.ejecutar(
      servicioId: servicio.id,
      borrador: borradorLinea(puestoId: puesto.id),
      actorUsuarioId: _actor,
    ) as CrearLineaComercialExitoso;
    return (servicio: servicio, lineaId: creada.linea.id, puesto: puesto);
  }

  ConfiguracionCobroBorrador borradorCobro({
    DateTime? desde,
    TipoDocumentoCobro tipo = TipoDocumentoCobro.reciboDePago,
    MetodoPagoCobro metodo = MetodoPagoCobro.noAplica,
    bool requiereComplemento = false,
    String? entidadFiscalId,
    int diaInicioPeriodo = 1,
    AgrupacionCobro agrupacion = AgrupacionCobro.porServicio,
    String? frecuenciaId,
  }) {
    return ConfiguracionCobroBorrador(
      tipoDocumento: tipo,
      frecuenciaId: frecuenciaId ?? SeedIds.frecuenciaCobroMensual,
      diaInicioPeriodo: diaInicioPeriodo,
      agrupacion: agrupacion,
      metodo: metodo,
      requiereComplemento: requiereComplemento,
      fechaInicioVigencia: desde ?? DateTime(2026, 4, 24),
      entidadFiscalId: entidadFiscalId,
    );
  }

  /// Las dos etapas del caso real: emisión el día 5 del mes del periodo
  /// y pago esperado el 10 del mes siguiente. Los `id` son del LOTE.
  const etapasDeLote = <EtapaCobroBorrador>[
    EtapaCobroBorrador(
      id: 'etapa-emision',
      tipoSistema: TipoEventoCobro.emision,
      orden: 0,
      tipoRegla: TipoReglaEvento.diaFijoDelMes,
      mesRelativo: MesRelativoCobro.actual,
      diaDelMes: 5,
    ),
    EtapaCobroBorrador(
      id: 'etapa-pago',
      tipoSistema: TipoEventoCobro.pagoEsperado,
      orden: 1,
      tipoRegla: TipoReglaEvento.diaFijoDelMes,
      mesRelativo: MesRelativoCobro.siguiente,
      diaDelMes: 10,
    ),
  ];

  Future<({String servicioId, String configuracionId})> servicioConCobro({
    List<EtapaCobroBorrador> etapas = etapasDeLote,
    ConfiguracionCobroBorrador? borrador,
  }) async {
    final cliente = await crearCliente();
    final servicio = await crearServicioDe(cliente.id);
    final creada = await crearCobro.ejecutar(
      servicioId: servicio.id,
      borrador: borrador ?? borradorCobro(),
      etapas: etapas,
      actorUsuarioId: _actor,
    );
    expect(
      creada,
      isA<CrearConfiguracionCobroExitoso>(),
      reason: creada is CrearConfiguracionCobroErroresValidacion ? 'errores: ${creada.errores}' : '$creada',
    );
    return (
      servicioId: servicio.id,
      configuracionId: (creada as CrearConfiguracionCobroExitoso).configuracion.id,
    );
  }

  /// Lo que arma la pantalla al abrir "Nueva vigencia"/"Corregir":
  /// precarga las etapas de la vigencia vigente CONSERVANDO su id real.
  Future<List<EtapaCobroBorrador>> etapasPrecargadas(
    String servicioId, {
    int diaEmision = 3,
    int diaPago = 10,
  }) async {
    final detalle = await cobroRepo.obtenerConfiguracion(servicioId);
    final previas = detalle!.etapas;
    return [
      EtapaCobroBorrador(
        id: previas.firstWhere((e) => e.tipoSistema == TipoEventoCobro.emision.name).id,
        tipoSistema: TipoEventoCobro.emision,
        orden: 0,
        tipoRegla: TipoReglaEvento.diaFijoDelMes,
        mesRelativo: MesRelativoCobro.actual,
        diaDelMes: diaEmision,
      ),
      EtapaCobroBorrador(
        id: previas.firstWhere((e) => e.tipoSistema == TipoEventoCobro.pagoEsperado.name).id,
        tipoSistema: TipoEventoCobro.pagoEsperado,
        orden: 1,
        tipoRegla: TipoReglaEvento.diaFijoDelMes,
        mesRelativo: MesRelativoCobro.siguiente,
        diaDelMes: diaPago,
      ),
    ];
  }

  // ===============================================================
  // §16 — CONFIGURACIÓN COMERCIAL
  // ===============================================================
  group('Configuración comercial', () {
    test('A. crear la primera vigencia deja UN evento de alta, con actor y sin motivo', () async {
      final ctx = await servicioConLinea();

      final eventos = await eventosDeServicio(ctx.servicio.id);
      expect(eventos, hasLength(1), reason: 'un alta = un evento');

      final evento = eventos.single;
      expect(evento.tipoEvento, TipoEventoServicio.lineaComercialCreada.name);
      expect(evento.actorUsuarioId, _actor);
      expect(evento.observacion, isNull, reason: 'un alta no justifica nada: todavía no había nada que cambiar');
      expect(evento.estadoAnterior, isNull);

      final datos = json(evento.datosRelevantes);
      expect(datos['lineaComercialId'], ctx.lineaId);
      expect(datos['precioUnitario'], 1500000);
      expect(datos['cantidadElementos'], 2);
      expect(datos['puestoId'], ctx.puesto.id);
      expect(datos['tratamientoIva'], TratamientoIva.masIva.name);
    });

    test('B. NUEVA VIGENCIA se registra como vigencia abierta, NUNCA como corrección', () async {
      final ctx = await servicioConLinea();

      final resultado = await cambiarVigenciaLinea.ejecutar(
        lineaComercialId: ctx.lineaId,
        borrador: borradorLinea(puestoId: ctx.puesto.id, precio: 1650000, desde: DateTime(2027, 1, 1)),
        observacion: 'Incremento anual pactado',
        actorUsuarioId: _actor,
      );
      expect(resultado, isA<CambiarVigenciaLineaComercialExitoso>());

      final abiertas = await eventosDeServicioDeTipo(
        ctx.servicio.id,
        TipoEventoServicio.vigenciaComercialAbierta,
      );
      final corregidas = await eventosDeServicioDeTipo(
        ctx.servicio.id,
        TipoEventoServicio.vigenciaComercialCorregida,
      );

      expect(abiertas, hasLength(1));
      expect(
        corregidas,
        isEmpty,
        reason: 'abrir una vigencia nueva JAMÁS es una corrección: es un hecho comercial nuevo',
      );

      final evento = abiertas.single;
      expect(evento.actorUsuarioId, _actor, reason: 'el actor es obligatorio también aquí');
      expect(evento.observacion, 'Incremento anual pactado', reason: 'observación, no "motivo"');
      expect(
        evento.estadoAnterior,
        isNull,
        reason: 'no hay "antes": la vigencia anterior no se modificó retrospectivamente',
      );

      final datos = json(evento.datosRelevantes);
      expect(datos['vigenciaAnteriorId'], isNotNull, reason: 'queda la traza de a quién releva');
      expect(datos['precioUnitario'], 1650000);
    });

    test('C. CORREGIR deja un evento de corrección con motivo y SÓLO los campos cambiados', () async {
      final ctx = await servicioConLinea();

      final resultado = await corregirLinea.ejecutar(
        lineaComercialId: ctx.lineaId,
        borrador: borradorLinea(puestoId: ctx.puesto.id, cantidad: 3),
        motivo: 'Se capturaron 2 elementos por error; el contrato dice 3',
        actorUsuarioId: _actor,
      );
      expect(resultado, isA<CorregirLineaComercialExitoso>());

      final corregidas = await eventosDeServicioDeTipo(
        ctx.servicio.id,
        TipoEventoServicio.vigenciaComercialCorregida,
      );
      final abiertas = await eventosDeServicioDeTipo(
        ctx.servicio.id,
        TipoEventoServicio.vigenciaComercialAbierta,
      );

      expect(corregidas, hasLength(1));
      expect(abiertas, isEmpty, reason: 'una corrección jamás abre una vigencia nueva');

      final evento = corregidas.single;
      expect(evento.actorUsuarioId, _actor);
      expect(evento.observacion, 'Se capturaron 2 elementos por error; el contrato dice 3');
      expect(json(evento.estadoAnterior), {'cantidadElementos': 2});
      expect(json(evento.estadoNuevo), {'cantidadElementos': 3});
      expect(
        json(evento.estadoNuevo).keys,
        hasLength(1),
        reason: 'el diff trae SÓLO lo que cambió, nunca un snapshot del registro',
      );

      // La línea sigue teniendo UNA sola vigencia: corregir no versiona.
      expect(await comercialRepo.listarHistorial(ctx.lineaId), hasLength(1));
    });

    test('C2. corregir sin motivo no cambia nada y no deja evento', () async {
      final ctx = await servicioConLinea();

      final resultado = await corregirLinea.ejecutar(
        lineaComercialId: ctx.lineaId,
        borrador: borradorLinea(puestoId: ctx.puesto.id, cantidad: 9),
        motivo: '   ',
        actorUsuarioId: _actor,
      );

      expect(resultado, isA<CorregirLineaComercialMotivoRequerido>());
      expect(
        await eventosDeServicioDeTipo(ctx.servicio.id, TipoEventoServicio.vigenciaComercialCorregida),
        isEmpty,
      );
      final vigencia = (await comercialRepo.listarHistorial(ctx.lineaId)).single;
      expect(vigencia.cantidadElementos, 2, reason: 'ni se persistió el cambio');
    });

    test('D. CANCELAR una vigencia programada deja evento con motivo y la vigencia restaurada', () async {
      final ctx = await servicioConLinea();
      await cambiarVigenciaLinea.ejecutar(
        lineaComercialId: ctx.lineaId,
        borrador: borradorLinea(puestoId: ctx.puesto.id, precio: 1650000, desde: DateTime(2027, 1, 1)),
        actorUsuarioId: _actor,
      );
      final programada = (await comercialRepo.listarHistorial(ctx.lineaId))
          .firstWhere((v) => v.fechaInicioVigencia == DateTime(2027, 1, 1));

      final resultado = await cancelarProgramadaLinea.ejecutar(
        vigenciaId: programada.id,
        motivo: 'El cliente retiró el incremento antes de que entrara en vigor',
        actorUsuarioId: _actor,
      );
      expect(resultado, isA<CancelarVigenciaProgramadaExitoso>());

      final canceladas = await eventosDeServicioDeTipo(
        ctx.servicio.id,
        TipoEventoServicio.vigenciaComercialCancelada,
      );
      expect(canceladas, hasLength(1));
      expect(canceladas.single.observacion, 'El cliente retiró el incremento antes de que entrara en vigor');
      expect(canceladas.single.actorUsuarioId, _actor);
      expect(json(canceladas.single.datosRelevantes)['vigenciaRestauradaId'], isNotNull);
    });

    test('E. el PRECIO cambiado aparece en el diff de la corrección', () async {
      final ctx = await servicioConLinea();
      await corregirLinea.ejecutar(
        lineaComercialId: ctx.lineaId,
        borrador: borradorLinea(puestoId: ctx.puesto.id, precio: 1800000),
        motivo: 'Precio mal capturado',
        actorUsuarioId: _actor,
      );

      final evento =
          (await eventosDeServicioDeTipo(ctx.servicio.id, TipoEventoServicio.vigenciaComercialCorregida)).single;
      expect(json(evento.estadoAnterior)['precioUnitario'], 1500000);
      expect(json(evento.estadoNuevo)['precioUnitario'], 1800000);
    });

    test('F. la CANTIDAD DE ELEMENTOS cambiada aparece en el diff', () async {
      final ctx = await servicioConLinea();
      await corregirLinea.ejecutar(
        lineaComercialId: ctx.lineaId,
        borrador: borradorLinea(puestoId: ctx.puesto.id, cantidad: 5),
        motivo: 'Eran 5 elementos',
        actorUsuarioId: _actor,
      );

      final evento =
          (await eventosDeServicioDeTipo(ctx.servicio.id, TipoEventoServicio.vigenciaComercialCorregida)).single;
      expect(json(evento.estadoAnterior)['cantidadElementos'], 2);
      expect(json(evento.estadoNuevo)['cantidadElementos'], 5);
    });

    test('G. el TURNO/MODALIDAD cambiado aparece en el diff', () async {
      final ctx = await servicioConLinea();
      await corregirLinea.ejecutar(
        lineaComercialId: ctx.lineaId,
        borrador: borradorLinea(
          puestoId: ctx.puesto.id,
          modalidadTurnoId: SeedIds.modalidadTurno12x12,
        ),
        motivo: 'El turno pactado es 12x12',
        actorUsuarioId: _actor,
      );

      final evento =
          (await eventosDeServicioDeTipo(ctx.servicio.id, TipoEventoServicio.vigenciaComercialCorregida)).single;
      expect(json(evento.estadoAnterior)['modalidadTurnoId'], SeedIds.modalidadTurno24x24);
      expect(json(evento.estadoNuevo)['modalidadTurnoId'], SeedIds.modalidadTurno12x12);
    });

    test('H. el TRATAMIENTO DE IVA cambiado aparece en el diff', () async {
      final ctx = await servicioConLinea();
      await corregirLinea.ejecutar(
        lineaComercialId: ctx.lineaId,
        borrador: borradorLinea(puestoId: ctx.puesto.id, iva: TratamientoIva.ivaIncluido),
        motivo: 'El precio pactado ya incluye IVA',
        actorUsuarioId: _actor,
      );

      final evento =
          (await eventosDeServicioDeTipo(ctx.servicio.id, TipoEventoServicio.vigenciaComercialCorregida)).single;
      expect(json(evento.estadoAnterior)['tratamientoIva'], TratamientoIva.masIva.name);
      expect(json(evento.estadoNuevo)['tratamientoIva'], TratamientoIva.ivaIncluido.name);
    });

    test('I. la vigencia ANTERIOR conserva intactas sus condiciones económicas', () async {
      final ctx = await servicioConLinea();
      final antes = (await comercialRepo.listarHistorial(ctx.lineaId)).single;

      await cambiarVigenciaLinea.ejecutar(
        lineaComercialId: ctx.lineaId,
        borrador: borradorLinea(
          puestoId: ctx.puesto.id,
          precio: 1650000,
          cantidad: 4,
          iva: TratamientoIva.ivaIncluido,
          desde: DateTime(2027, 1, 1),
        ),
        actorUsuarioId: _actor,
      );

      final historial = await comercialRepo.listarHistorial(ctx.lineaId);
      expect(historial, hasLength(2));
      final anterior = historial.firstWhere((v) => v.id == antes.id);

      expect(anterior.precioUnitario, antes.precioUnitario);
      expect(anterior.cantidadElementos, antes.cantidadElementos);
      expect(anterior.puestoId, antes.puestoId);
      expect(anterior.modalidadTurnoId, antes.modalidadTurnoId);
      expect(anterior.tratamientoIva, antes.tratamientoIva);
      expect(anterior.fechaInicioVigencia, antes.fechaInicioVigencia);
      expect(
        anterior.fechaFinVigencia,
        DateTime(2026, 12, 31),
        reason: 'lo ÚNICO que cambia del pasado es hasta cuándo aplicó — el relevo, no las condiciones',
      );
    });

    test('J. CERO DUPLICADOS: cada acción deja exactamente un evento y nada más', () async {
      final ctx = await servicioConLinea();

      // Cuatro acciones distintas sobre la misma línea, en orden real:
      // abrir vigencia nueva, cancelarla antes de que entre en vigor y
      // cerrar la línea. Cada una deja SU evento, ninguna deja dos.
      await cambiarVigenciaLinea.ejecutar(
        lineaComercialId: ctx.lineaId,
        borrador: borradorLinea(puestoId: ctx.puesto.id, precio: 1650000, desde: DateTime(2027, 1, 1)),
        actorUsuarioId: _actor,
      );
      final programada = (await comercialRepo.listarHistorial(ctx.lineaId))
          .firstWhere((v) => v.fechaInicioVigencia == DateTime(2027, 1, 1));
      expect(
        await cancelarProgramadaLinea.ejecutar(
          vigenciaId: programada.id,
          motivo: 'Se retiró el incremento',
          actorUsuarioId: _actor,
        ),
        isA<CancelarVigenciaProgramadaExitoso>(),
      );
      expect(
        await cerrarLinea.ejecutar(
          lineaComercialId: ctx.lineaId,
          fechaEfectiva: DateTime(2026, 8, 31),
          motivo: 'El cliente canceló el perfil',
          actorUsuarioId: _actor,
        ),
        isA<CerrarLineaComercialExitoso>(),
      );

      final eventos = await eventosDeServicio(ctx.servicio.id);
      final porTipo = <String, int>{};
      for (final e in eventos) {
        porTipo[e.tipoEvento] = (porTipo[e.tipoEvento] ?? 0) + 1;
      }

      expect(porTipo[TipoEventoServicio.lineaComercialCreada.name], 1);
      expect(porTipo[TipoEventoServicio.vigenciaComercialAbierta.name], 1);
      expect(porTipo[TipoEventoServicio.vigenciaComercialCancelada.name], 1);
      expect(porTipo[TipoEventoServicio.lineaComercialCerrada.name], 1);
      expect(
        porTipo[TipoEventoServicio.vigenciaComercialCorregida.name],
        isNull,
        reason: 'ninguna de las cuatro acciones es una corrección',
      );
      expect(eventos, hasLength(4), reason: 'cuatro hechos, cuatro eventos: ni uno de más');
      expect(eventos.map((e) => e.id).toSet(), hasLength(eventos.length));
    });

    test('J2. una corrección que no cambia nada NO genera evento', () async {
      final ctx = await servicioConLinea();

      final resultado = await corregirLinea.ejecutar(
        lineaComercialId: ctx.lineaId,
        borrador: borradorLinea(puestoId: ctx.puesto.id),
        motivo: 'Revisión sin cambios',
        actorUsuarioId: _actor,
      );
      expect(resultado, isA<CorregirLineaComercialExitoso>());

      expect(
        await eventosDeServicioDeTipo(ctx.servicio.id, TipoEventoServicio.vigenciaComercialCorregida),
        isEmpty,
        reason: 'sin cambios reales no hay nada que auditar',
      );
    });
  });

  // ===============================================================
  // §17 — CONFIGURACIÓN DE COBRO
  // ===============================================================
  group('Configuración de cobro', () {
    test('A. crear deja un evento de alta con las reglas y las etapas', () async {
      final ctx = await servicioConCobro();

      final eventos = await eventosDeCobro(ctx.configuracionId);
      expect(eventos, hasLength(1));

      final evento = eventos.single;
      expect(evento.tipoEvento, TipoEventoConfiguracionCobro.creada.name);
      expect(evento.actorUsuarioId, _actor);
      expect(evento.observacion, isNull);

      final datos = json(evento.datosRelevantes);
      expect(datos['frecuenciaId'], SeedIds.frecuenciaCobroMensual);
      expect(datos['tipoDocumento'], TipoDocumentoCobro.reciboDePago.name);
      expect(datos['fechaInicioVigencia'], DateTime(2026, 4, 24).toIso8601String());

      final etapas = (datos['etapas'] as List).cast<Map<String, dynamic>>();
      expect(etapas, hasLength(2));
      expect(
        etapas.map((e) => e['tipoSistema']),
        containsAll([TipoEventoCobro.emision.name, TipoEventoCobro.pagoEsperado.name]),
      );
    });

    test('B. NUEVA VIGENCIA se registra como vigencia abierta, NUNCA como corrección', () async {
      final ctx = await servicioConCobro();

      final resultado = await cambiarVigenciaCobro.ejecutar(
        configuracionCobroId: ctx.configuracionId,
        borrador: borradorCobro(desde: DateTime(2026, 9, 1), diaInicioPeriodo: 16),
        etapas: await etapasPrecargadas(ctx.servicioId),
        observacion: 'El cliente cambió el corte al día 16',
        actorUsuarioId: _actor,
      );
      expect(
        resultado,
        isA<CambiarVigenciaConfiguracionCobroExitoso>(),
        reason:
            resultado is CambiarVigenciaConfiguracionCobroErroresValidacion ? '${resultado.errores}' : '$resultado',
      );

      final eventos = await eventosDeCobro(ctx.configuracionId);
      final abiertas =
          eventos.where((e) => e.tipoEvento == TipoEventoConfiguracionCobro.vigenciaAbierta.name).toList();
      final corregidas =
          eventos.where((e) => e.tipoEvento == TipoEventoConfiguracionCobro.corregida.name).toList();

      expect(abiertas, hasLength(1));
      expect(corregidas, isEmpty, reason: 'nueva vigencia ≠ corrección de vigencia');
      expect(abiertas.single.observacion, 'El cliente cambió el corte al día 16');
      expect(abiertas.single.actorUsuarioId, _actor);
      expect(abiertas.single.estadoAnterior, isNull);
      expect(json(abiertas.single.datosRelevantes)['vigenciaAnteriorId'], isNotNull);
    });

    test('C. CORREGIR deja evento de corrección con motivo y sólo los campos cambiados', () async {
      final ctx = await servicioConCobro();

      final resultado = await corregirCobro.ejecutar(
        configuracionCobroId: ctx.configuracionId,
        borrador: borradorCobro(diaInicioPeriodo: 16),
        etapas: await etapasPrecargadas(ctx.servicioId, diaEmision: 5),
        motivo: 'El corte se capturó el día 1 por error',
        actorUsuarioId: _actor,
      );
      expect(resultado, isA<CorregirConfiguracionCobroExitoso>());

      final corregidas = (await eventosDeCobro(ctx.configuracionId))
          .where((e) => e.tipoEvento == TipoEventoConfiguracionCobro.corregida.name)
          .toList();
      expect(corregidas, hasLength(1));

      final evento = corregidas.single;
      expect(evento.observacion, 'El corte se capturó el día 1 por error');
      expect(evento.actorUsuarioId, _actor);
      expect(json(evento.estadoAnterior), {'diaInicioPeriodo': 1});
      expect(json(evento.estadoNuevo), {'diaInicioPeriodo': 16});

      // Sigue habiendo UNA sola vigencia: corregir no versiona.
      expect(await cobroRepo.listarHistorial(ctx.configuracionId), hasLength(1));
    });

    test('C2. corregir sin motivo no cambia nada y no deja evento', () async {
      final ctx = await servicioConCobro();

      final resultado = await corregirCobro.ejecutar(
        configuracionCobroId: ctx.configuracionId,
        borrador: borradorCobro(diaInicioPeriodo: 16),
        etapas: await etapasPrecargadas(ctx.servicioId, diaEmision: 5),
        motivo: '',
        actorUsuarioId: _actor,
      );

      expect(resultado, isA<CorregirConfiguracionCobroMotivoRequerido>());
      expect(
        (await eventosDeCobro(ctx.configuracionId))
            .where((e) => e.tipoEvento == TipoEventoConfiguracionCobro.corregida.name),
        isEmpty,
      );
      expect((await cobroRepo.listarHistorial(ctx.configuracionId)).single.diaInicioPeriodo, 1);
    });

    test('D. PUE nunca exige complemento — ni en la vigencia ni en el evento', () async {
      final cliente = await crearCliente();
      final servicio = await crearServicioDe(cliente.id);
      final entidad = (await crearEntidadFiscal.ejecutar(
        clienteId: cliente.id,
        borrador: const EntidadFiscalBorrador(razonSocial: 'Sportium SA de CV', rfc: 'SPO010101AB1'),
        actorUsuarioId: _actor,
      ) as GuardarEntidadFiscalExitoso)
          .entidadFiscal;

      final creada = await crearCobro.ejecutar(
        servicioId: servicio.id,
        borrador: borradorCobro(
          tipo: TipoDocumentoCobro.cfdi,
          metodo: MetodoPagoCobro.pue,
          // Aunque alguien lo mande en `true`, PUE lo normaliza a falso.
          requiereComplemento: true,
          entidadFiscalId: entidad.id,
        ),
        etapas: etapasDeLote,
        actorUsuarioId: _actor,
      );
      expect(
        creada,
        isA<CrearConfiguracionCobroExitoso>(),
        reason: creada is CrearConfiguracionCobroErroresValidacion ? '${creada.errores}' : '$creada',
      );
      final configuracionId = (creada as CrearConfiguracionCobroExitoso).configuracion.id;

      final vigencia = (await cobroRepo.listarHistorial(configuracionId)).single;
      expect(vigencia.metodo, MetodoPagoCobro.pue.name);
      expect(vigencia.requiereComplemento, isFalse, reason: 'PUE → requiereComplemento = false, sin excepción');

      final evento = (await eventosDeCobro(configuracionId)).single;
      expect(json(evento.datosRelevantes)['requiereComplemento'], false);
    });

    test('E. PPD exige complemento según la regla vigente — y el evento lo refleja', () async {
      final cliente = await crearCliente();
      final servicio = await crearServicioDe(cliente.id);
      final entidad = (await crearEntidadFiscal.ejecutar(
        clienteId: cliente.id,
        borrador: const EntidadFiscalBorrador(razonSocial: 'Sportium SA de CV', rfc: 'SPO010101AB1'),
        actorUsuarioId: _actor,
      ) as GuardarEntidadFiscalExitoso)
          .entidadFiscal;

      // PPD sin complemento es inválido: la regla vigente no cambia.
      final invalida = await crearCobro.ejecutar(
        servicioId: servicio.id,
        borrador: borradorCobro(
          tipo: TipoDocumentoCobro.cfdi,
          metodo: MetodoPagoCobro.ppd,
          requiereComplemento: false,
          entidadFiscalId: entidad.id,
        ),
        etapas: etapasDeLote,
        actorUsuarioId: _actor,
      );
      expect(invalida, isA<CrearConfiguracionCobroErroresValidacion>());

      final creada = await crearCobro.ejecutar(
        servicioId: servicio.id,
        borrador: borradorCobro(
          tipo: TipoDocumentoCobro.cfdi,
          metodo: MetodoPagoCobro.ppd,
          requiereComplemento: true,
          entidadFiscalId: entidad.id,
        ),
        etapas: etapasDeLote,
        actorUsuarioId: _actor,
      );
      expect(creada, isA<CrearConfiguracionCobroExitoso>());
      final configuracionId = (creada as CrearConfiguracionCobroExitoso).configuracion.id;

      expect((await cobroRepo.listarHistorial(configuracionId)).single.requiereComplemento, isTrue);
      final evento = (await eventosDeCobro(configuracionId)).single;
      expect(json(evento.datosRelevantes)['requiereComplemento'], true);
      expect(json(evento.datosRelevantes)['metodo'], MetodoPagoCobro.ppd.name);
    });

    test('F. cambiar de PPD a PUE queda en el diff, y el Complemento deja de exigirse', () async {
      final cliente = await crearCliente();
      final servicio = await crearServicioDe(cliente.id);
      final entidad = (await crearEntidadFiscal.ejecutar(
        clienteId: cliente.id,
        borrador: const EntidadFiscalBorrador(razonSocial: 'Sportium SA de CV', rfc: 'SPO010101AB1'),
        actorUsuarioId: _actor,
      ) as GuardarEntidadFiscalExitoso)
          .entidadFiscal;

      final creada = await crearCobro.ejecutar(
        servicioId: servicio.id,
        borrador: borradorCobro(
          tipo: TipoDocumentoCobro.cfdi,
          metodo: MetodoPagoCobro.ppd,
          requiereComplemento: true,
          entidadFiscalId: entidad.id,
        ),
        etapas: etapasDeLote,
        actorUsuarioId: _actor,
      ) as CrearConfiguracionCobroExitoso;

      final resultado = await corregirCobro.ejecutar(
        configuracionCobroId: creada.configuracion.id,
        borrador: borradorCobro(
          tipo: TipoDocumentoCobro.cfdi,
          metodo: MetodoPagoCobro.pue,
          requiereComplemento: true,
          entidadFiscalId: entidad.id,
        ),
        etapas: await etapasPrecargadas(servicio.id, diaEmision: 5),
        motivo: 'El cliente paga de contado: el método correcto es PUE',
        actorUsuarioId: _actor,
      );
      expect(resultado, isA<CorregirConfiguracionCobroExitoso>());

      final evento = (await eventosDeCobro(creada.configuracion.id))
          .firstWhere((e) => e.tipoEvento == TipoEventoConfiguracionCobro.corregida.name);
      expect(json(evento.estadoAnterior)['metodo'], MetodoPagoCobro.ppd.name);
      expect(json(evento.estadoNuevo)['metodo'], MetodoPagoCobro.pue.name);
      expect(json(evento.estadoAnterior)['requiereComplemento'], true);
      expect(
        json(evento.estadoNuevo)['requiereComplemento'],
        false,
        reason: 'la normalización PUE→sin complemento también queda auditada',
      );
    });

    test('G. las ETAPAS de la nueva vigencia quedan registradas en su evento', () async {
      final ctx = await servicioConCobro();

      await cambiarVigenciaCobro.ejecutar(
        configuracionCobroId: ctx.configuracionId,
        borrador: borradorCobro(desde: DateTime(2026, 9, 1)),
        etapas: await etapasPrecargadas(ctx.servicioId, diaEmision: 3, diaPago: 12),
        actorUsuarioId: _actor,
      );

      final evento = (await eventosDeCobro(ctx.configuracionId))
          .firstWhere((e) => e.tipoEvento == TipoEventoConfiguracionCobro.vigenciaAbierta.name);
      final etapas = (json(evento.datosRelevantes)['etapas'] as List).cast<Map<String, dynamic>>();

      expect(etapas, hasLength(2));
      final emision = etapas.firstWhere((e) => e['tipoSistema'] == TipoEventoCobro.emision.name);
      final pago = etapas.firstWhere((e) => e['tipoSistema'] == TipoEventoCobro.pagoEsperado.name);
      expect(emision['diaDelMes'], 3);
      expect(pago['diaDelMes'], 12);
      expect(pago['mesRelativo'], MesRelativoCobro.siguiente.name);
    });

    test('H. una etapa que REFERENCIA a otra guarda la referencia ya remapeada', () async {
      final cliente = await crearCliente();
      final servicio = await crearServicioDe(cliente.id);

      final creada = await crearCobro.ejecutar(
        servicioId: servicio.id,
        borrador: borradorCobro(),
        etapas: const [
          EtapaCobroBorrador(
            id: 'lote-emision',
            tipoSistema: TipoEventoCobro.emision,
            orden: 0,
            tipoRegla: TipoReglaEvento.diaFijoDelMes,
            mesRelativo: MesRelativoCobro.actual,
            diaDelMes: 5,
          ),
          EtapaCobroBorrador(
            id: 'lote-pago',
            tipoSistema: TipoEventoCobro.pagoEsperado,
            orden: 1,
            tipoRegla: TipoReglaEvento.diasCalendarioDespuesDe,
            offsetDias: 30,
            // Apunta a una HERMANA DEL MISMO LOTE que todavía no existe
            // como fila: ese es el motivo de que el id sea del lote.
            etapaReferenciaId: 'lote-emision',
          ),
        ],
        actorUsuarioId: _actor,
      );
      expect(
        creada,
        isA<CrearConfiguracionCobroExitoso>(),
        reason: creada is CrearConfiguracionCobroErroresValidacion ? '${creada.errores}' : '$creada',
      );
      final configuracionId = (creada as CrearConfiguracionCobroExitoso).configuracion.id;

      final vigencia = (await cobroRepo.listarHistorial(configuracionId)).single;
      final persistidas = await cobroRepo.listarEtapas(vigencia.id);
      final emisionPersistida = persistidas.firstWhere((e) => e.tipoSistema == TipoEventoCobro.emision.name);
      final pagoPersistida = persistidas.firstWhere((e) => e.tipoSistema == TipoEventoCobro.pagoEsperado.name);

      expect(
        pagoPersistida.etapaReferenciaId,
        emisionPersistida.id,
        reason: 'la referencia apunta al id REAL de la hermana, no al del lote',
      );

      final etapasDelEvento =
          ((json((await eventosDeCobro(configuracionId)).single.datosRelevantes)['etapas']) as List)
              .cast<Map<String, dynamic>>();
      final pagoEnEvento =
          etapasDelEvento.firstWhere((e) => e['tipoSistema'] == TipoEventoCobro.pagoEsperado.name);
      expect(pagoEnEvento['etapaReferenciaId'], emisionPersistida.id);
      expect(pagoEnEvento['etapaReferenciaId'], isNot('lote-emision'));
    });

    test('I. la vigencia ANTERIOR conserva intactas sus reglas y sus etapas', () async {
      final ctx = await servicioConCobro();
      final antes = (await cobroRepo.listarHistorial(ctx.configuracionId)).single;
      final etapasAntes = await cobroRepo.listarEtapas(antes.id);

      await cambiarVigenciaCobro.ejecutar(
        configuracionCobroId: ctx.configuracionId,
        borrador: borradorCobro(desde: DateTime(2026, 9, 1), diaInicioPeriodo: 16),
        etapas: await etapasPrecargadas(ctx.servicioId, diaEmision: 3, diaPago: 12),
        actorUsuarioId: _actor,
      );

      final anterior =
          (await cobroRepo.listarHistorial(ctx.configuracionId)).firstWhere((v) => v.id == antes.id);
      expect(anterior.diaInicioPeriodo, antes.diaInicioPeriodo);
      expect(anterior.frecuenciaId, antes.frecuenciaId);
      expect(anterior.tipoDocumento, antes.tipoDocumento);
      expect(anterior.metodo, antes.metodo);
      expect(anterior.fechaInicioVigencia, antes.fechaInicioVigencia);
      expect(anterior.fechaFinVigencia, DateTime(2026, 8, 31), reason: 'sólo cambia hasta cuándo aplicó');

      final etapasDespues = await cobroRepo.listarEtapas(antes.id);
      expect(etapasDespues.map((e) => e.id).toSet(), etapasAntes.map((e) => e.id).toSet());
      expect(
        etapasDespues.firstWhere((e) => e.tipoSistema == TipoEventoCobro.emision.name).diaDelMes,
        etapasAntes.firstWhere((e) => e.tipoSistema == TipoEventoCobro.emision.name).diaDelMes,
        reason: 'las reglas del pasado no se reescriben',
      );
    });

    test('J. cada etapa persistida recibe un id NUEVO, distinto del id del lote', () async {
      final ctx = await servicioConCobro();
      final vigencia = (await cobroRepo.listarHistorial(ctx.configuracionId)).single;
      final persistidas = await cobroRepo.listarEtapas(vigencia.id);

      expect(persistidas, hasLength(2));
      for (final etapa in persistidas) {
        expect(
          etapa.id,
          isNot(anyOf('etapa-emision', 'etapa-pago')),
          reason: 'el id del borrador es correlación del lote, nunca la clave primaria',
        );
      }
      expect(persistidas.map((e) => e.id).toSet(), hasLength(2), reason: 'y son distintos entre sí');
    });

    test(
      'K. REGRESIÓN (caso MORGAN): nueva vigencia precargada con los ids reales de las etapas no colisiona',
      () async {
        final ctx = await servicioConCobro();

        // El formulario de "Nueva vigencia" se precarga con las etapas
        // de la vigencia vigente CONSERVANDO su id persistido. Si el
        // repositorio volviera a usar ese id como PK, aquí reventaría
        // con `UNIQUE constraint failed: configuracion_cobro_etapa.id`
        // y la transacción revertiría TODO: la anterior seguiría
        // vigente y la nueva no existiría.
        final precargadas = await etapasPrecargadas(ctx.servicioId, diaEmision: 3, diaPago: 12);
        final idsReutilizados = precargadas.map((e) => e.id).toSet();

        final resultado = await cambiarVigenciaCobro.ejecutar(
          configuracionCobroId: ctx.configuracionId,
          borrador: borradorCobro(desde: DateTime(2026, 9, 1)),
          etapas: precargadas,
          actorUsuarioId: _actor,
        );
        expect(
          resultado,
          isA<CambiarVigenciaConfiguracionCobroExitoso>(),
          reason: resultado is CambiarVigenciaConfiguracionCobroErrorInesperado
              ? 'falló con: ${resultado.mensaje}'
              : '$resultado',
        );

        final historial = await cobroRepo.listarHistorial(ctx.configuracionId);
        expect(historial, hasLength(2), reason: 'la nueva vigencia existe y la anterior no se perdió');

        final nueva = historial.firstWhere((v) => v.fechaInicioVigencia == DateTime(2026, 9, 1));
        final etapasNuevas = await cobroRepo.listarEtapas(nueva.id);
        expect(etapasNuevas, hasLength(2));
        for (final etapa in etapasNuevas) {
          expect(
            idsReutilizados,
            isNot(contains(etapa.id)),
            reason: 'cada etapa persistida recibe UUID nuevo; los ids del borrador jamás se reusan como PK',
          );
        }

        // Y las filas de la vigencia anterior siguen ahí, intactas.
        final anterior = historial.firstWhere((v) => v.id != nueva.id);
        final etapasAnteriores = await cobroRepo.listarEtapas(anterior.id);
        expect(etapasAnteriores.map((e) => e.id).toSet(), idsReutilizados);
      },
    );

    test('M. Auditoría central proyecta la Configuración de cobro y navega a SU Servicio', () async {
      final ctx = await servicioConCobro();

      final eventos = await BuscarAuditoriaUseCase(auditoriaRepo).ejecutar(const FiltroAuditoria());
      final delCobro = eventos.firstWhere((e) => e.modulo == 'configuracionCobro');

      expect(delCobro.accion, TipoEventoConfiguracionCobro.creada.name);
      expect(delCobro.registroId, ctx.configuracionId);
      expect(delCobro.actorUsuarioId, _actor);

      // La Configuración de cobro no tiene pantalla propia por id: vive
      // dentro del expediente de su Servicio, y ahí navega.
      final destino = destinoDeEvento(delCobro);
      expect(destino, isNotNull);
      expect(destino!.ruta, '/comercial/servicios/${ctx.servicioId}');
      expect(destino.exigeMaestro, isFalse);

      // `auditoria.ver` deja ver QUE pasó; abrir el expediente lo sigue
      // decidiendo el permiso del módulo de origen.
      expect(permisosQueAbrenRuta(destino.ruta), ['comercial.ver']);
    });

    test('L. cerrar y cancelar dejan su propio evento, con motivo y actor', () async {
      final ctx = await servicioConCobro();

      await cambiarVigenciaCobro.ejecutar(
        configuracionCobroId: ctx.configuracionId,
        borrador: borradorCobro(desde: DateTime(2026, 9, 1)),
        etapas: await etapasPrecargadas(ctx.servicioId),
        actorUsuarioId: _actor,
      );
      final programada = (await cobroRepo.listarHistorial(ctx.configuracionId))
          .firstWhere((v) => v.fechaInicioVigencia == DateTime(2026, 9, 1));

      final cancelada = await cancelarProgramadaCobro.ejecutar(
        vigenciaId: programada.id,
        motivo: 'El cambio de corte se pospuso',
        actorUsuarioId: _actor,
      );
      expect(cancelada, isA<CancelarVigenciaProgramadaConfiguracionCobroExitoso>());

      final cerrada = await cerrarCobro.ejecutar(
        configuracionCobroId: ctx.configuracionId,
        fechaEfectiva: DateTime(2026, 8, 31),
        motivo: 'El Servicio dejó de facturarse',
        actorUsuarioId: _actor,
      );
      expect(cerrada, isA<CerrarConfiguracionCobroExitoso>());

      final eventos = await eventosDeCobro(ctx.configuracionId);
      final cancelaciones =
          eventos.where((e) => e.tipoEvento == TipoEventoConfiguracionCobro.vigenciaCancelada.name).toList();
      final cierres = eventos.where((e) => e.tipoEvento == TipoEventoConfiguracionCobro.cerrada.name).toList();

      expect(cancelaciones, hasLength(1));
      expect(cancelaciones.single.observacion, 'El cambio de corte se pospuso');
      expect(cancelaciones.single.actorUsuarioId, _actor);

      expect(cierres, hasLength(1));
      expect(cierres.single.observacion, 'El Servicio dejó de facturarse');
      expect(json(cierres.single.estadoNuevo)['fechaFinVigencia'], isNotNull);
    });
  });

  // ===============================================================
  // Vinculaciones del Servicio (hueco encontrado en esta etapa)
  // ===============================================================
  group('Vinculaciones del Servicio', () {
    // Regla acordada: la PRIMERA asignación es configuración inicial
    // normal y no exige motivo. Sustituir o retirar una Entidad fiscal
    // vigente sí, porque puede mover a quién se le factura.
    Future<({ServicioData servicio, EntidadFiscalData a, EntidadFiscalData b})> servicioConDosEntidades() async {
      final cliente = await crearCliente();
      final servicio = await crearServicioDe(cliente.id);
      final a = (await crearEntidadFiscal.ejecutar(
        clienteId: cliente.id,
        borrador: const EntidadFiscalBorrador(razonSocial: 'Sportium SA de CV', rfc: 'SPO010101AB1'),
        actorUsuarioId: _actor,
      ) as GuardarEntidadFiscalExitoso)
          .entidadFiscal;
      final b = (await crearEntidadFiscal.ejecutar(
        clienteId: cliente.id,
        borrador: const EntidadFiscalBorrador(razonSocial: 'Sportium Norte SA de CV', rfc: 'SNO020202CD2'),
        actorUsuarioId: _actor,
      ) as GuardarEntidadFiscalExitoso)
          .entidadFiscal;
      return (servicio: servicio, a: a, b: b);
    }

    test('null→A: la primera asignación NO pide motivo y deja evento propio con actor y diff', () async {
      final ctx = await servicioConDosEntidades();
      final asignar = AsignarEntidadFiscalAServicioUseCase(servicioRepo, entidadFiscalRepo);

      expect(
        exigeMotivoAsignacionEntidadFiscal(anterior: null, nueva: ctx.a.id),
        isFalse,
        reason: 'la primera asignación es configuración inicial normal',
      );

      final resultado = await asignar.ejecutar(
        servicioId: ctx.servicio.id,
        entidadFiscalId: ctx.a.id,
        actorUsuarioId: _actor,
      );
      expect(resultado, isA<AsignarEntidadFiscalAServicioExitoso>());

      // A quién se le factura es un hecho con nombre propio: no se
      // mezcla con "el Servicio se corrigió".
      final eventos = await eventosDeServicioDeTipo(
        ctx.servicio.id,
        TipoEventoServicio.entidadFiscalAsignada,
      );
      expect(eventos, hasLength(1));
      expect(eventos.single.actorUsuarioId, _actor);
      expect(eventos.single.observacion, isNull, reason: 'sin motivo: no había nada que justificar');
      expect(json(eventos.single.estadoAnterior), {'entidadFiscalId': null});
      expect(json(eventos.single.estadoNuevo), {'entidadFiscalId': ctx.a.id});
      expect(
        await eventosDeServicioDeTipo(ctx.servicio.id, TipoEventoServicio.corregido),
        isEmpty,
        reason: 'una vinculación no es una corrección de datos generales',
      );
    });

    test('A→B SIN motivo se rechaza: no cambia la Entidad fiscal ni deja evento', () async {
      final ctx = await servicioConDosEntidades();
      final asignar = AsignarEntidadFiscalAServicioUseCase(servicioRepo, entidadFiscalRepo);
      await asignar.ejecutar(servicioId: ctx.servicio.id, entidadFiscalId: ctx.a.id, actorUsuarioId: _actor);

      final resultado = await asignar.ejecutar(
        servicioId: ctx.servicio.id,
        entidadFiscalId: ctx.b.id,
        motivo: '   ',
        actorUsuarioId: _actor,
      );

      expect(resultado, isA<AsignarEntidadFiscalAServicioMotivoRequerido>());
      expect(
        (await servicioRepo.obtenerPorId(ctx.servicio.id))!.entidadFiscalId,
        ctx.a.id,
        reason: 'ni se persistió el cambio',
      );
      expect(
        await eventosDeServicioDeTipo(ctx.servicio.id, TipoEventoServicio.entidadFiscalAsignada),
        hasLength(1),
        reason: 'sólo el evento de la primera asignación',
      );
    });

    test('A→B CON motivo funciona y deja UN SOLO evento, con actor, diff y motivo', () async {
      final ctx = await servicioConDosEntidades();
      final asignar = AsignarEntidadFiscalAServicioUseCase(servicioRepo, entidadFiscalRepo);
      await asignar.ejecutar(servicioId: ctx.servicio.id, entidadFiscalId: ctx.a.id, actorUsuarioId: _actor);

      final resultado = await asignar.ejecutar(
        servicioId: ctx.servicio.id,
        entidadFiscalId: ctx.b.id,
        motivo: 'El contrato se firmó con la razón social del norte',
        actorUsuarioId: _actor,
      );
      expect(resultado, isA<AsignarEntidadFiscalAServicioExitoso>());

      final eventos = await eventosDeServicioDeTipo(
        ctx.servicio.id,
        TipoEventoServicio.entidadFiscalAsignada,
      );
      expect(eventos, hasLength(2), reason: 'la asignación inicial y el cambio: un evento por hecho');

      // UN solo evento para el cambio: el mismo lleva actor, diff y
      // motivo. No se emite otro sólo para justificarlo.
      final cambio = eventos.last;
      expect(cambio.actorUsuarioId, _actor);
      expect(cambio.observacion, 'El contrato se firmó con la razón social del norte');
      expect(json(cambio.estadoAnterior), {'entidadFiscalId': ctx.a.id});
      expect(json(cambio.estadoNuevo), {'entidadFiscalId': ctx.b.id});
      expect(
        await eventosDeServicio(ctx.servicio.id),
        hasLength(2),
        reason: 'ningún evento adicional de otro tipo para el mismo hecho',
      );
    });

    test('A→null SIN motivo se rechaza: la Entidad fiscal sigue asignada', () async {
      final ctx = await servicioConDosEntidades();
      final asignar = AsignarEntidadFiscalAServicioUseCase(servicioRepo, entidadFiscalRepo);
      await asignar.ejecutar(servicioId: ctx.servicio.id, entidadFiscalId: ctx.a.id, actorUsuarioId: _actor);

      final resultado = await asignar.ejecutar(
        servicioId: ctx.servicio.id,
        entidadFiscalId: null,
        actorUsuarioId: _actor,
      );

      expect(resultado, isA<AsignarEntidadFiscalAServicioMotivoRequerido>());
      expect((await servicioRepo.obtenerPorId(ctx.servicio.id))!.entidadFiscalId, ctx.a.id);
      expect(
        await eventosDeServicioDeTipo(ctx.servicio.id, TipoEventoServicio.entidadFiscalAsignada),
        hasLength(1),
      );
    });

    test('A→null CON motivo funciona, y reasignar el mismo valor no inventa evento', () async {
      final ctx = await servicioConDosEntidades();
      final asignar = AsignarEntidadFiscalAServicioUseCase(servicioRepo, entidadFiscalRepo);

      await asignar.ejecutar(servicioId: ctx.servicio.id, entidadFiscalId: ctx.a.id, actorUsuarioId: _actor);
      // Reasignar exactamente la misma: no cambió nada, y tampoco pide
      // motivo porque no hay transición que justificar.
      final sinCambio = await asignar.ejecutar(
        servicioId: ctx.servicio.id,
        entidadFiscalId: ctx.a.id,
        actorUsuarioId: _actor,
      );
      expect(sinCambio, isA<AsignarEntidadFiscalAServicioExitoso>());

      final retiro = await asignar.ejecutar(
        servicioId: ctx.servicio.id,
        entidadFiscalId: null,
        motivo: 'El Servicio dejó de facturarse a esa razón social',
        actorUsuarioId: _actor,
      );
      expect(retiro, isA<AsignarEntidadFiscalAServicioExitoso>());

      final eventos = await eventosDeServicioDeTipo(
        ctx.servicio.id,
        TipoEventoServicio.entidadFiscalAsignada,
      );
      expect(eventos, hasLength(2), reason: 'asignar y quitar: dos hechos, no tres');
      expect(eventos.last.observacion, 'El Servicio dejó de facturarse a esa razón social');
      expect(json(eventos.last.estadoAnterior), {'entidadFiscalId': ctx.a.id});
      expect(json(eventos.last.estadoNuevo), {'entidadFiscalId': null});
    });

    test('responsable del Cliente, Sucursal administrativa y responsable interno dejan su propio evento', () async {
      final cliente = await crearCliente();
      final servicio = await crearServicioDe(cliente.id);
      final contacto = (await agregarContacto.ejecutar(
        clienteId: cliente.id,
        borrador: const ContactoBorrador(
          nombre: 'Marlon Ríos',
          tipo: TipoContacto.comercial,
          telefono: '5544332211',
        ),
        actorUsuarioId: _actor,
      ) as GuardarContactoExitoso)
          .contacto;

      await servicioRepo.asignarResponsableCliente(
        servicioId: servicio.id,
        contactoId: contacto.id,
        actorUsuarioId: _actor,
      );
      final sucursal = await db.into(db.sucursal).insertReturning(
            SucursalCompanion.insert(
              codigo: 'SUC-000001',
              nombre: 'Corporativo',
              tipoSucursalId: SeedIds.tipoSucursalOficinaAdministrativa,
            ),
          );
      await servicioRepo.asignarSucursalAdministrativa(
        servicioId: servicio.id,
        sucursalId: sucursal.id,
        actorUsuarioId: _actor,
      );
      await servicioRepo.guardarResponsableInterno(
        servicioId: servicio.id,
        texto: 'Coordinación Zona Norte',
        actorUsuarioId: _actor,
      );

      final responsable =
          (await eventosDeServicioDeTipo(servicio.id, TipoEventoServicio.responsableClienteAsignado)).single;
      expect(responsable.actorUsuarioId, _actor);
      expect(json(responsable.estadoNuevo), {'responsableClienteContactoId': contacto.id});

      final eventoSucursal = (await eventosDeServicioDeTipo(
        servicio.id,
        TipoEventoServicio.sucursalAdministrativaAsignada,
      ))
          .single;
      expect(json(eventoSucursal.estadoNuevo), {'sucursalAdministrativaId': sucursal.id});

      final interno = (await eventosDeServicioDeTipo(
        servicio.id,
        TipoEventoServicio.responsableInternoActualizado,
      ))
          .single;
      expect(json(interno.estadoAnterior), {'responsableInterno': null});
      expect(json(interno.estadoNuevo), {'responsableInterno': 'Coordinación Zona Norte'});

      // Estas tres NO exigen motivo: son asignaciones operativas, no
      // cambian a quién se le factura. Se ejecutaron sin pasar ninguno
      // y quedaron registradas igual.
      for (final evento in [responsable, eventoSucursal, interno]) {
        expect(evento.observacion, isNull);
        expect(evento.actorUsuarioId, _actor);
      }

      // Y siguen aceptando un segundo cambio sin motivo.
      await servicioRepo.guardarResponsableInterno(
        servicioId: servicio.id,
        texto: 'Coordinación Zona Sur',
        actorUsuarioId: _actor,
      );
      expect(
        await eventosDeServicioDeTipo(servicio.id, TipoEventoServicio.responsableInternoActualizado),
        hasLength(2),
      );
    });
  });

  // ===============================================================
  // Portales del Cliente (hueco encontrado en esta etapa)
  // ===============================================================
  group('Portales del Cliente', () {
    Future<ClientePortalData> crearPortalDe(String clienteId, {String? contrasena}) async {
      final resultado = await crearPortal.ejecutar(
        clienteId: clienteId,
        borrador: ClientePortalBorrador(
          nombre: 'Portal SIPOT',
          tipo: TipoPortalCliente.facturacion,
          url: 'https://sipot.example.com',
          usuario: 'riseg',
          contrasenaNueva: contrasena,
        ),
        actorUsuarioId: _actor,
      );
      return (resultado as GuardarClientePortalExitoso).portal;
    }

    test('el alta deja actor y los datos del portal, pero JAMÁS la contraseña', () async {
      final cliente = await crearCliente();
      final portal = await crearPortalDe(cliente.id, contrasena: 'Secreta123');

      final evento = (await eventosDeCliente(cliente.id)).single;
      expect(evento.tipoEvento, TipoEventoCliente.clientePortalCreado.name);
      expect(evento.actorUsuarioId, _actor);
      expect(evento.observacion, isNull);

      final datos = json(evento.datosRelevantes);
      expect(datos['clientePortalId'], portal.id);
      expect(datos['nombre'], 'Portal SIPOT');
      expect(datos['url'], 'https://sipot.example.com');
      expect(datos['usuario'], 'riseg');
      expect(datos['tieneContrasena'], true, reason: 'se registra QUE hay contraseña, nunca cuál');

      // Ni en claro ni cifrada: el secreto no vive en la bitácora.
      expect(evento.datosRelevantes, isNot(contains('Secreta123')));
      expect(evento.datosRelevantes, isNot(contains(portal.contrasenaCifrada)));
      expect(evento.datosRelevantes, isNot(contains('aesgcm')));
    });

    test('corregir exige motivo y deja sólo los campos cambiados', () async {
      final cliente = await crearCliente();
      final portal = await crearPortalDe(cliente.id);

      final sinMotivo = await actualizarPortal.ejecutar(
        id: portal.id,
        borrador: const ClientePortalBorrador(nombre: 'Otro', tipo: TipoPortalCliente.facturacion),
        motivo: '  ',
        actorUsuarioId: _actor,
      );
      expect(sinMotivo, isA<GuardarClientePortalMotivoRequerido>());

      final resultado = await actualizarPortal.ejecutar(
        id: portal.id,
        borrador: const ClientePortalBorrador(
          nombre: 'Portal SIPOT',
          tipo: TipoPortalCliente.facturacion,
          url: 'https://sipot-nuevo.example.com',
          usuario: 'riseg',
        ),
        motivo: 'El cliente migró el portal a otro dominio',
        actorUsuarioId: _actor,
      );
      expect(resultado, isA<GuardarClientePortalExitoso>());

      final evento = (await eventosDeCliente(cliente.id))
          .firstWhere((e) => e.tipoEvento == TipoEventoCliente.clientePortalCorregido.name);
      expect(evento.observacion, 'El cliente migró el portal a otro dominio');
      expect(evento.actorUsuarioId, _actor);
      expect(json(evento.estadoAnterior), {'url': 'https://sipot.example.com'});
      expect(json(evento.estadoNuevo), {'url': 'https://sipot-nuevo.example.com'});
    });

    test('cambiar la contraseña se audita como HECHO, nunca con su valor', () async {
      final cliente = await crearCliente();
      final portal = await crearPortalDe(cliente.id, contrasena: 'Original123');

      await actualizarPortal.ejecutar(
        id: portal.id,
        borrador: const ClientePortalBorrador(
          nombre: 'Portal SIPOT',
          tipo: TipoPortalCliente.facturacion,
          url: 'https://sipot.example.com',
          usuario: 'riseg',
          contrasenaNueva: 'Nueva456',
        ),
        motivo: 'Rotación de credenciales',
        actorUsuarioId: _actor,
      );

      final evento = (await eventosDeCliente(cliente.id))
          .firstWhere((e) => e.tipoEvento == TipoEventoCliente.clientePortalCorregido.name);
      expect(json(evento.estadoAnterior), {'contrasena': 'sin cambios'});
      expect(json(evento.estadoNuevo), {'contrasena': 'actualizada'});
      expect(evento.estadoAnterior, isNot(contains('Original123')));
      expect(evento.estadoNuevo, isNot(contains('Nueva456')));
      expect(evento.estadoNuevo, isNot(contains('aesgcm')));
    });

    test('archivar y reactivar exigen motivo y dejan su propio evento', () async {
      final cliente = await crearCliente();
      final portal = await crearPortalDe(cliente.id);

      expect(
        await cambiarCicloVidaPortal.ejecutar(
          clientePortalId: portal.id,
          nuevo: CicloVidaRegistro.archivado,
          motivo: ' ',
          actorUsuarioId: _actor,
        ),
        isA<CambiarCicloVidaClientePortalMotivoRequerido>(),
      );

      await cambiarCicloVidaPortal.ejecutar(
        clientePortalId: portal.id,
        nuevo: CicloVidaRegistro.archivado,
        motivo: 'El cliente dejó de usar este portal',
        actorUsuarioId: _actor,
      );
      await cambiarCicloVidaPortal.ejecutar(
        clientePortalId: portal.id,
        nuevo: CicloVidaRegistro.activo,
        motivo: 'Lo volvieron a habilitar',
        actorUsuarioId: _actor,
      );

      final eventos = (await eventosDeCliente(cliente.id))
          .where((e) => e.tipoEvento == TipoEventoCliente.clientePortalCicloVidaCambiado.name)
          .toList();
      expect(eventos, hasLength(2));
      expect(json(eventos.first.estadoNuevo)['cicloVidaRegistro'], CicloVidaRegistro.archivado.name);
      expect(eventos.first.observacion, 'El cliente dejó de usar este portal');
      expect(json(eventos.last.estadoNuevo)['cicloVidaRegistro'], CicloVidaRegistro.activo.name);
      expect(eventos.last.observacion, 'Lo volvieron a habilitar');
    });

    test('AUDITORÍA CENTRAL nunca devuelve la contraseña del portal', () async {
      final cliente = await crearCliente();
      final portal = await crearPortalDe(cliente.id, contrasena: 'Original123');
      await actualizarPortal.ejecutar(
        id: portal.id,
        borrador: const ClientePortalBorrador(
          nombre: 'Portal SIPOT',
          tipo: TipoPortalCliente.facturacion,
          usuario: 'riseg',
          contrasenaNueva: 'Nueva456',
        ),
        motivo: 'Rotación de credenciales',
        actorUsuarioId: _actor,
      );

      final eventos = await BuscarAuditoriaUseCase(auditoriaRepo).ejecutar(const FiltroAuditoria());
      final serializado = jsonEncode([
        for (final e in eventos)
          {
            'detalle': e.detalleJson,
            'cambios': [
              for (final c in e.cambios) {'campo': c.campo, 'antes': c.antes, 'despues': c.despues},
            ],
          },
      ]);

      expect(serializado, isNot(contains('Original123')));
      expect(serializado, isNot(contains('Nueva456')));
      expect(serializado, isNot(contains('aesgcm')));

      // Pero sí se ve QUE la contraseña se rotó, y quién lo hizo.
      final correccion =
          eventos.firstWhere((e) => e.accion == TipoEventoCliente.clientePortalCorregido.name);
      expect(correccion.cambios.map((c) => c.campo), contains('contrasena'));
      expect(correccion.actorUsuarioId, _actor);
    });
  });

  // ===============================================================
  // §18 — CONTACTOS
  // ===============================================================
  group('Contactos', () {
    const telefono = '5544332211';
    const correo = 'marlon.rios@empresa.com';

    Future<ContactoData> agregar(String clienteId) async {
      final resultado = await agregarContacto.ejecutar(
        clienteId: clienteId,
        borrador: const ContactoBorrador(
          nombre: 'Marlon Ríos',
          tipo: TipoContacto.comercial,
          puesto: 'Gerente de compras',
          telefono: telefono,
          correo: correo,
        ),
        actorUsuarioId: _actor,
      );
      return (resultado as GuardarContactoExitoso).contacto;
    }

    test('el alta deja actor, SIN motivo, y con teléfono/correo enmascarados', () async {
      final cliente = await crearCliente();
      final contacto = await agregar(cliente.id);

      final evento = (await eventosDeCliente(cliente.id)).single;
      expect(evento.tipoEvento, TipoEventoCliente.contactoAgregado.name);
      expect(evento.actorUsuarioId, _actor);
      expect(evento.observacion, isNull);

      final datos = json(evento.datosRelevantes);
      expect(datos['contactoId'], contacto.id);
      expect(datos['nombre'], 'Marlon Ríos', reason: 'el nombre identifica a la persona: no se oculta');
      expect(datos['puesto'], 'Gerente de compras');
      expect(datos['telefono'], enmascararIdentificador(telefono));
      expect(datos['correo'], enmascararCorreo(correo));
      expect(datos['telefono'], isNot(contains('5544')), reason: 'el número completo no vive en la bitácora');
      expect(datos['correo'], isNot(contains('marlon.rios')));
    });

    test('la corrección exige motivo y deja SÓLO los campos cambiados', () async {
      final cliente = await crearCliente();
      final contacto = await agregar(cliente.id);

      final resultado = await actualizarContacto.ejecutar(
        id: contacto.id,
        borrador: const ContactoBorrador(
          nombre: 'Marlon Ríos',
          tipo: TipoContacto.comercial,
          puesto: 'Director de compras',
          telefono: telefono,
          correo: correo,
        ),
        motivo: 'Ascendió de gerente a director',
        actorUsuarioId: _actor,
      );
      expect(resultado, isA<GuardarContactoExitoso>());

      final evento = (await eventosDeCliente(cliente.id))
          .firstWhere((e) => e.tipoEvento == TipoEventoCliente.contactoCorregido.name);
      expect(evento.observacion, 'Ascendió de gerente a director');
      expect(evento.actorUsuarioId, _actor);
      expect(json(evento.estadoAnterior), {'puesto': 'Gerente de compras'});
      expect(json(evento.estadoNuevo), {'puesto': 'Director de compras'});
    });

    test('sin motivo no se corrige el contacto ni queda evento', () async {
      final cliente = await crearCliente();
      final contacto = await agregar(cliente.id);

      final resultado = await actualizarContacto.ejecutar(
        id: contacto.id,
        borrador: const ContactoBorrador(
          nombre: 'Otro nombre',
          tipo: TipoContacto.comercial,
          telefono: telefono,
        ),
        motivo: '  ',
        actorUsuarioId: _actor,
      );

      expect(resultado, isA<GuardarContactoMotivoRequerido>());
      expect(
        (await eventosDeCliente(cliente.id))
            .where((e) => e.tipoEvento == TipoEventoCliente.contactoCorregido.name),
        isEmpty,
      );
      final recargado = await (db.select(db.contacto)..where((t) => t.id.equals(contacto.id))).getSingle();
      expect(recargado.nombre, 'Marlon Ríos', reason: 'ni se persistió el cambio');
    });

    test('cambiar el teléfono queda auditado ENMASCARADO en ambos lados del diff', () async {
      final cliente = await crearCliente();
      final contacto = await agregar(cliente.id);

      const telefonoNuevo = '5599887766';
      await actualizarContacto.ejecutar(
        id: contacto.id,
        borrador: const ContactoBorrador(
          nombre: 'Marlon Ríos',
          tipo: TipoContacto.comercial,
          puesto: 'Gerente de compras',
          telefono: telefonoNuevo,
          correo: correo,
        ),
        motivo: 'Cambió de número',
        actorUsuarioId: _actor,
      );

      final evento = (await eventosDeCliente(cliente.id))
          .firstWhere((e) => e.tipoEvento == TipoEventoCliente.contactoCorregido.name);
      final antes = json(evento.estadoAnterior);
      final despues = json(evento.estadoNuevo);

      expect(antes.keys, ['telefono'], reason: 'se ve QUE cambió el teléfono, y nada más');
      expect(antes['telefono'], enmascararIdentificador(telefono));
      expect(despues['telefono'], enmascararIdentificador(telefonoNuevo));
      expect(antes['telefono'], isNot(telefono));
      expect(despues['telefono'], isNot(telefonoNuevo));

      // Y el dato REAL sigue completo en su fuente: Comercial lo muestra
      // normalmente conforme a permisos.
      final recargado = await (db.select(db.contacto)..where((t) => t.id.equals(contacto.id))).getSingle();
      expect(recargado.telefono, telefonoNuevo);
    });

    test('cambiar el correo queda auditado ENMASCARADO en ambos lados del diff', () async {
      final cliente = await crearCliente();
      final contacto = await agregar(cliente.id);

      const correoNuevo = 'compras@empresa.com';
      await actualizarContacto.ejecutar(
        id: contacto.id,
        borrador: const ContactoBorrador(
          nombre: 'Marlon Ríos',
          tipo: TipoContacto.comercial,
          puesto: 'Gerente de compras',
          telefono: telefono,
          correo: correoNuevo,
        ),
        motivo: 'Ahora usa el buzón del área',
        actorUsuarioId: _actor,
      );

      final evento = (await eventosDeCliente(cliente.id))
          .firstWhere((e) => e.tipoEvento == TipoEventoCliente.contactoCorregido.name);
      expect(json(evento.estadoAnterior)['correo'], enmascararCorreo(correo));
      expect(json(evento.estadoNuevo)['correo'], enmascararCorreo(correoNuevo));
      expect(json(evento.estadoNuevo)['correo'], isNot(correoNuevo));
      expect(
        json(evento.estadoNuevo)['correo'],
        contains('@empresa.com'),
        reason: 'el dominio se conserva: distingue un cambio de buzón de un cambio de empresa',
      );

      final recargado = await (db.select(db.contacto)..where((t) => t.id.equals(contacto.id))).getSingle();
      expect(recargado.correo, correoNuevo);
    });

    test('archivar exige motivo y deja su propio evento', () async {
      final cliente = await crearCliente();
      final contacto = await agregar(cliente.id);

      final sinMotivo = await archivarContacto.ejecutar(contacto.id, motivo: ' ', actorUsuarioId: _actor);
      expect(sinMotivo, isA<ArchivarContactoMotivoRequerido>());
      expect(
        (await eventosDeCliente(cliente.id))
            .where((e) => e.tipoEvento == TipoEventoCliente.contactoArchivado.name),
        isEmpty,
      );

      final resultado = await archivarContacto.ejecutar(
        contacto.id,
        motivo: 'Dejó la empresa',
        actorUsuarioId: _actor,
      );
      expect(resultado, isA<ArchivarContactoExitoso>());

      final evento = (await eventosDeCliente(cliente.id))
          .firstWhere((e) => e.tipoEvento == TipoEventoCliente.contactoArchivado.name);
      expect(evento.observacion, 'Dejó la empresa');
      expect(evento.actorUsuarioId, _actor);
      expect(json(evento.estadoAnterior)['cicloVidaRegistro'], CicloVidaRegistro.activo.name);
      expect(json(evento.estadoNuevo)['cicloVidaRegistro'], CicloVidaRegistro.archivado.name);
      expect(json(evento.datosRelevantes)['nombre'], 'Marlon Ríos');
    });

    test('AUDITORÍA CENTRAL nunca devuelve el teléfono ni el correo completos', () async {
      final cliente = await crearCliente();
      final contacto = await agregar(cliente.id);
      await actualizarContacto.ejecutar(
        id: contacto.id,
        borrador: const ContactoBorrador(
          nombre: 'Marlon Ríos',
          tipo: TipoContacto.comercial,
          puesto: 'Gerente de compras',
          telefono: '5599887766',
          correo: 'compras@empresa.com',
        ),
        motivo: 'Cambió de número y de buzón',
        actorUsuarioId: _actor,
      );

      final eventos = await BuscarAuditoriaUseCase(auditoriaRepo).ejecutar(const FiltroAuditoria());
      final serializado = jsonEncode([
        for (final e in eventos)
          {
            'detalle': e.detalleJson,
            'cambios': [
              for (final c in e.cambios) {'campo': c.campo, 'antes': c.antes, 'despues': c.despues},
            ],
          },
      ]);

      expect(serializado, isNot(contains(telefono)));
      expect(serializado, isNot(contains('5599887766')));
      expect(serializado, isNot(contains(correo)));
      expect(serializado, isNot(contains('compras@empresa.com')));

      // Pero SÍ se ve que esos campos cambiaron.
      final correccion = eventos.firstWhere((e) => e.accion == TipoEventoCliente.contactoCorregido.name);
      expect(correccion.cambios.map((c) => c.campo), containsAll(['telefono', 'correo']));
      expect(correccion.motivo, 'Cambió de número y de buzón');
      expect(correccion.actorUsuarioId, _actor);
    });
  });
}
