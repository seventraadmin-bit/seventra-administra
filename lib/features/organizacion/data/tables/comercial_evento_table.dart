import 'package:drift/drift.dart';

import 'package:riseg_one/features/usuarios/data/tables/usuario_table.dart';

import 'cliente_table.dart';
import 'configuracion_cobro_table.dart';
import 'servicio_table.dart';

/// Qué ocurrió con un Cliente o con uno de sus sub-registros.
///
/// El Cliente es el agregado: Entidad fiscal y Contacto no tienen dueño
/// propio —el catálogo de permisos ya lo dice así, `clientes.*` los
/// cubre a los tres—, así que sus eventos cuelgan del Cliente y el
/// sub-registro concreto viaja en `datosRelevantes`. Un solo lugar al
/// que navegar, un solo permiso que respetar.
enum TipoEventoCliente {
  creado,
  corregido,
  estatusCambiado,

  entidadFiscalCreada,
  entidadFiscalCorregida,
  entidadFiscalCicloVidaCambiado,

  clientePortalCreado,
  clientePortalCorregido,
  clientePortalCicloVidaCambiado,

  contactoAgregado,
  contactoCorregido,
  contactoArchivado,
}

/// Qué ocurrió con un Servicio o con su configuración comercial.
///
/// `ServicioLineaComercial` (precio, cantidad de elementos, turno, IVA,
/// agrupación) vive DENTRO de un Servicio y comparte su permiso
/// `servicios.*`. Su vigencia, en cambio, no se corrige: se abre una
/// nueva. Por eso hay dos tipos distintos y nunca se confunden — abrir
/// una vigencia es un hecho de negocio, no la enmienda de un error.
enum TipoEventoServicio {
  creado,
  corregido,
  estatusCambiado,

  // Vinculaciones del Servicio. Se registran aparte de `corregido`
  // porque cada una responde una pregunta distinta: a quién se le
  // factura, con quién se trata, desde qué Sucursal se administra y
  // quién responde por dentro.
  entidadFiscalAsignada,
  responsableClienteAsignado,
  sucursalAdministrativaAsignada,
  responsableInternoActualizado,

  lineaComercialCreada,
  lineaComercialCorregida,

  /// Se abrió una vigencia NUEVA. La anterior queda intacta, cerrada en
  /// su fecha. Nunca se registra como corrección.
  vigenciaComercialAbierta,

  /// Se corrigió una vigencia YA EXISTENTE (un dato mal capturado en
  /// ella), sin abrir ninguna nueva.
  vigenciaComercialCorregida,

  vigenciaComercialCancelada,
  lineaComercialCerrada,
}

/// Qué ocurrió con la Configuración de cobro de un Servicio.
///
/// Módulo propio (`configuracionCobro.*`) porque decidir CÓMO se cobra
/// puede ser facultad de un rol distinto al que opera el Servicio. Misma
/// distinción que arriba entre abrir vigencia y corregir una existente.
enum TipoEventoConfiguracionCobro {
  creada,
  corregida,
  vigenciaAbierta,
  vigenciaCorregida,
  vigenciaCancelada,
  cerrada,
}

/// Bitácora del agregado Cliente (Etapa "Trazabilidad Comercial").
///
/// Misma forma que `EmpleadoEvento`/`VehiculoEvento`: quién, cuándo,
/// qué tipo, motivo, y el diff campo a campo en `datosRelevantes` —
/// jamás un snapshot completo del registro.
class ClienteEvento extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get clienteId => text().references(Cliente, #id, onDelete: KeyAction.cascade)();

  DateTimeColumn get fechaHora => dateTime()();

  TextColumn get tipoEvento => text()();

  /// Motivo de la operación. Obligatorio en correcciones y cambios de
  /// estatus; ausente en altas, donde no hay nada que justificar.
  TextColumn get observacion => text().nullable()();

  TextColumn get actorUsuarioId => text().nullable().references(Usuario, #id, onDelete: KeyAction.setNull)();

  TextColumn get estadoAnterior => text().nullable()();

  TextColumn get estadoNuevo => text().nullable()();

  /// `DiffEvento` — sólo los campos REALMENTE modificados, más el id
  /// del sub-registro (`entidadFiscalId`/`contactoId`) cuando el evento
  /// no es del Cliente en sí.
  TextColumn get datosRelevantes => text().nullable()();
}

/// Bitácora del Servicio y de su configuración comercial.
class ServicioEvento extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get servicioId => text().references(Servicio, #id, onDelete: KeyAction.cascade)();

  DateTimeColumn get fechaHora => dateTime()();

  TextColumn get tipoEvento => text()();

  TextColumn get observacion => text().nullable()();

  TextColumn get actorUsuarioId => text().nullable().references(Usuario, #id, onDelete: KeyAction.setNull)();

  TextColumn get estadoAnterior => text().nullable()();

  TextColumn get estadoNuevo => text().nullable()();

  TextColumn get datosRelevantes => text().nullable()();
}

/// Bitácora de la Configuración de cobro.
class ConfiguracionCobroEvento extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get configuracionCobroId =>
      text().references(ConfiguracionCobro, #id, onDelete: KeyAction.cascade)();

  DateTimeColumn get fechaHora => dateTime()();

  TextColumn get tipoEvento => text()();

  TextColumn get observacion => text().nullable()();

  TextColumn get actorUsuarioId => text().nullable().references(Usuario, #id, onDelete: KeyAction.setNull)();

  TextColumn get estadoAnterior => text().nullable()();

  TextColumn get estadoNuevo => text().nullable()();

  TextColumn get datosRelevantes => text().nullable()();
}
