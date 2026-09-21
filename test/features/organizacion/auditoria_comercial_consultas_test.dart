// Auditoría central con los orígenes de Comercial: cero N+1.
//
// El riesgo real de agregar tres orígenes nuevos a la Auditoría central
// es que cada fila termine resolviendo su etiqueta —el nombre del
// Cliente, del Servicio— con su propia consulta. Con 200 eventos eso
// son 200 viajes a la base para pintar una lista.
//
// Medir tiempo no probaría nada: es ruidoso. Lo que prueba la propiedad
// arquitectónica es que el NÚMERO de consultas deje de crecer con el
// número de eventos.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/seed/seed_ids.dart';
import 'package:riseg_one/core/utils/clock.dart';
import 'package:riseg_one/features/organizacion/data/repositories/catalogo_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/cliente_portal_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/cliente_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/configuracion_cobro_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/entidad_fiscal_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_comercial_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/tables/cliente_table.dart';
import 'package:riseg_one/features/organizacion/data/tables/configuracion_cobro_etapa_table.dart';
import 'package:riseg_one/features/organizacion/data/tables/configuracion_cobro_vigencia_table.dart';
import 'package:riseg_one/features/organizacion/data/tables/contacto_table.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/agregar_contacto_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/cambiar_estatus_cliente_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/configuracion_cobro_etapa_validator.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/configuracion_cobro_validator.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/contacto_validator.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_configuracion_cobro_usecase.dart';
import 'package:riseg_one/features/personal/data/repositories/asignacion_servicio_repository_impl.dart';
import 'package:riseg_one/features/usuarios/data/repositories/auditoria_repository_impl.dart';
import 'package:riseg_one/features/usuarios/domain/usecases/buscar_auditoria_usecase.dart';

import '../../support/contador_de_consultas.dart';

const _actor = 'usuario-auditor';

class _RelojFijo implements Clock {
  _RelojFijo(this._fecha);
  final DateTime _fecha;

  @override
  DateTime now() => _fecha;
}

void main() {
  late ContadorDeConsultas contador;
  late AppDatabase db;
  late ClienteRepositoryImpl clienteRepo;
  late ServicioRepositoryImpl servicioRepo;
  late CambiarEstatusClienteUseCase cambiarEstatusCliente;
  late AgregarContactoUseCase agregarContacto;
  late CrearConfiguracionCobroUseCase crearConfiguracionCobro;
  var consecutivo = 0;

  Future<void> abrir() async {
    contador = ContadorDeConsultas(NativeDatabase.memory());
    db = AppDatabase(contador);
    await db.into(db.usuario).insert(
          UsuarioCompanion.insert(
            id: const Value(_actor),
            nombre: 'Auditor',
            nombreUsuario: 'auditor',
            passwordHash: 'x',
            esMaestro: const Value(true),
          ),
        );
    clienteRepo = ClienteRepositoryImpl(db);
    servicioRepo = ServicioRepositoryImpl(db, AsignacionServicioRepositoryImpl(db));
    cambiarEstatusCliente = CambiarEstatusClienteUseCase(clienteRepo);
    agregarContacto = AgregarContactoUseCase(clienteRepo);

    final clock = _RelojFijo(DateTime(2026, 8, 15));
    final catalogoRepo = CatalogoRepositoryImpl(db);
    final cobroRepo = ConfiguracionCobroRepositoryImpl(db, clock: clock);
    crearConfiguracionCobro = CrearConfiguracionCobroUseCase(
      cobroRepo,
      servicioRepo,
      ConfiguracionCobroValidator(
        servicioRepo,
        EntidadFiscalRepositoryImpl(db),
        catalogoRepo,
        ServicioComercialRepositoryImpl(db, clock: clock),
        ClientePortalRepositoryImpl(db),
      ),
      const ConfiguracionCobroEtapaValidator(),
    );
    // La secuencia de código se toca en la siembra, no en la medición.
    GenerarCodigoUseCase(CodigoSecuenciaService(db));
    consecutivo = 0;
  }

  /// Siembra [cantidad] Clientes, cada uno con un Servicio, y genera
  /// eventos de los TRES orígenes de Comercial: Cliente (estatus y
  /// contacto), Servicio y Configuración de cobro.
  Future<void> sembrar(int cantidad) async {
    for (var i = 0; i < cantidad; i++) {
      final n = (++consecutivo).toString().padLeft(6, '0');
      final cliente = await clienteRepo.crear(
        ClienteCompanion.insert(codigo: 'CLI-$n', nombreComercial: 'Cliente $n'),
      );
      final servicio = await servicioRepo.crear(
        codigoServicio: 'SRV-$n',
        clienteId: cliente.id,
        nombre: 'Servicio $n',
        tipoServicioId: SeedIds.tipoServicioVigilanciaFija,
        fechaInicio: DateTime(2026, 1, 1),
        codigoUbicacionRaiz: 'UBI-$n',
      );
      await cambiarEstatusCliente.ejecutar(
        clienteId: cliente.id,
        nuevo: EstatusCliente.activo,
        motivo: 'Contrato firmado $n',
        actorUsuarioId: _actor,
      );
      await agregarContacto.ejecutar(
        clienteId: cliente.id,
        borrador: ContactoBorrador(
          nombre: 'Contacto $n',
          tipo: TipoContacto.comercial,
          telefono: '55$n${n.substring(4)}',
          correo: 'contacto$n@empresa.com',
        ),
        actorUsuarioId: _actor,
      );
      await crearConfiguracionCobro.ejecutar(
        servicioId: servicio.id,
        borrador: ConfiguracionCobroBorrador(
          tipoDocumento: TipoDocumentoCobro.reciboDePago,
          frecuenciaId: SeedIds.frecuenciaCobroMensual,
          diaInicioPeriodo: 1,
          agrupacion: AgrupacionCobro.porServicio,
          metodo: MetodoPagoCobro.noAplica,
          requiereComplemento: false,
          fechaInicioVigencia: DateTime(2026, 4, 24),
        ),
        etapas: const [
          EtapaCobroBorrador(
            id: 'etapa-emision',
            tipoSistema: TipoEventoCobro.emision,
            orden: 0,
            tipoRegla: TipoReglaEvento.diaFijoDelMes,
            mesRelativo: MesRelativoCobro.actual,
            diaDelMes: 5,
          ),
        ],
        actorUsuarioId: _actor,
      );
    }
  }

  Future<int> consultasDeAuditoria(int cantidad) async {
    await abrir();
    await sembrar(cantidad);
    contador.reiniciar();
    final eventos = await BuscarAuditoriaUseCase(AuditoriaRepositoryImpl(db)).ejecutar(const FiltroAuditoria());
    final medidas = contador.selects;
    // Dos eventos de Cliente por siembra (estatus + contacto) y uno de
    // Configuración de cobro: los tres orígenes nuevos entran a la
    // medición, no sólo el más barato.
    expect(eventos.where((e) => e.modulo == 'clientes'), hasLength(cantidad * 2));
    expect(eventos.where((e) => e.modulo == 'configuracionCobro'), hasLength(cantidad));
    await db.close();
    return medidas;
  }

  test('1, 20 y 60 eventos de Comercial cuestan el mismo número de consultas', () async {
    final conUno = await consultasDeAuditoria(1);
    final conVeinte = await consultasDeAuditoria(20);
    final conSesenta = await consultasDeAuditoria(60);

    expect(conSesenta, conVeinte,
        reason: 'pasar de 20 a 60 eventos no puede costar ni una consulta más: 1=$conUno 20=$conVeinte 60=$conSesenta');
    expect(conVeinte, conUno, reason: '1=$conUno 20=$conVeinte');
  });

  test('las etiquetas de contexto se resuelven para todas las filas, en lote', () async {
    await abrir();
    await sembrar(40);

    final eventos = await BuscarAuditoriaUseCase(AuditoriaRepositoryImpl(db)).ejecutar(const FiltroAuditoria());
    final deClientes = eventos.where((e) => e.modulo == 'clientes').toList();

    expect(deClientes, hasLength(80));
    expect(
      deClientes.every((e) => (e.entidadEtiqueta ?? '').startsWith('Cliente ')),
      isTrue,
      reason: 'todas traen su etiqueta, y ninguna costó una consulta propia',
    );
    // La Configuración de cobro no tiene nombre propio: su contexto es
    // el Servicio, y también se resuelve en lote.
    final deCobro = eventos.where((e) => e.modulo == 'configuracionCobro').toList();
    expect(deCobro, hasLength(40));
    expect(deCobro.every((e) => (e.destinoId ?? '').isNotEmpty), isTrue);
    await db.close();
  });
}
