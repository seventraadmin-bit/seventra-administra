import 'package:drift/drift.dart';

import '../../../../core/database/tables/audit_columns.dart';
import '../../../finanzas/data/tables/cuenta_financiera_table.dart';
import '../../../finanzas/data/tables/deuda_table.dart';
import '../../../finanzas/data/tables/egreso_table.dart';
import '../../../organizacion/data/tables/cliente_table.dart';
import '../../../organizacion/data/tables/entidad_fiscal_table.dart';
import '../../../personal/data/tables/empleado_table.dart';
import '../../../usuarios/data/tables/usuario_table.dart';

/// Quién contrató el evento. Deliberadamente NO es un `Cliente` falso ni
/// un `Servicio` permanente: un eventual es una operación puntual, y un
/// solicitante que quizá nunca vuelva no debe ensuciar Comercial.
enum TipoSolicitanteServicioEventual { cliente, eventual }

/// Ciclo operativo del evento — **nunca** su estado de cobro, que vive
/// en la Cuenta por cobrar. `enCurso` NO se persiste: se deriva de
/// `fechaHoraInicio`/`fechaHoraFin` contra el reloj (mismo criterio que
/// `estaVencida` en Cuentas por cobrar: ningún proceso en segundo plano
/// existe sólo para mantener un estado al día).
enum EstatusServicioEventual { programado, finalizado, cancelado }

/// Tipos de evento del historial de un Servicio Eventual — append-only,
/// mismo molde que `LineaTelefonicaEvento`.
///
/// Los hechos puramente financieros (el Egreso, el cargo a la tarjeta)
/// NO se duplican aquí: ya tienen su propia bitácora. Lo que estos
/// eventos registran es el hecho OPERATIVO ("se pagó la cobertura de
/// Juan"), con referencia al origen cuando corresponde.
enum TipoEventoServicioEventual {
  creado,
  corregido,
  finalizado,
  cancelado,
  participanteAgregado,
  participanteCorregido,
  participanteRetirado,
  coberturaAgregada,
  coberturaCorregida,
  coberturaCancelada,
  coberturaPagada,
  coberturaPagoRevertido,
  costoAgregado,
  costoCorregido,
  costoCancelado,
  costoPagado,
  costoPagoRevertido,
  // schemaVersion 88 — cobranza eventual. La CxC, el Pago y el
  // Complemento conservan CADA UNO su propia bitácora; aquí sólo se
  // registra el hecho comercial desde la perspectiva del eventual, para
  // no duplicar el asiento financiero en dos historiales.
  cuentaPorCobrarCreada,
  cuentaPorCobrarSincronizada,
  documentoFiscalRegistrado,
  documentoFiscalCorregido,
  documentoFiscalCancelado,
  // schemaVersion 90 — cancelar el evento anula la venta. El Pago y la
  // Cuenta por cobrar conservan CADA UNO su bitácora; aquí queda el
  // hecho comercial ("esta venta se anuló y esto se revirtió").
  ventaAnulada,
  cobroRevertido,
}

/// Un servicio de seguridad puntual vendido por RISEG (Rebanada 1 de
/// Servicios Eventuales, schemaVersion 87) — un evento de un día, una
/// cobertura especial, un apoyo extraordinario.
///
/// **No es un `Servicio`.** Un `Servicio` representa una relación
/// operativa/comercial persistente con Configuración Comercial y de
/// Cobro recurrentes; esto es una venta de una sola ocasión. Nunca se
/// modeló como `Servicio.esEventual` precisamente para que ninguna de
/// esas mecánicas (vigencias, calendario, documentos por emitir) se
/// aplique aquí por accidente.
///
/// **Nada derivable se persiste**: ni utilidad, ni costo total, ni
/// cobrado, ni pendiente, ni "en curso". Todo eso se calcula sobre
/// coberturas/costos y la Cuenta por cobrar.
///
/// **Sin `condicionCobro`**: "contado" y "pendiente" no son un atributo
/// del evento sino el estado del dinero, que se lee de la Cuenta por
/// cobrar. En la captura es una decisión ("¿registrar el cobro
/// ahora?"), no una columna.
class ServicioEventual extends Table with AuditColumns {
  /// `EVT-000001`, vía `CodigoSecuencia` — nunca capturado a mano y
  /// nunca usado como relación: las FK siempre van por `id`.
  TextColumn get folio => text().unique()();

  TextColumn get nombre => text()();

  DateTimeColumn get fechaHoraInicio => dateTime()();

  DateTimeColumn get fechaHoraFin => dateTime()();

  TextColumn get ubicacion => text().nullable()();

  TextColumn get notas => text().nullable()();

  IntColumn get importeAcordado => integer()();

  TextColumn get estatus => text().withDefault(const Constant('programado'))();

  TextColumn get tipoSolicitante => text()();

  /// Poblado sólo cuando `tipoSolicitante == cliente`. FK real: no se
  /// copia el nombre del Cliente aquí.
  TextColumn get clienteId => text().nullable().references(Cliente, #id, onDelete: KeyAction.restrict)();

  /// Snapshot mínimo del solicitante ocasional — poblado sólo cuando
  /// `tipoSolicitante == eventual`. No crea Cliente ni EntidadFiscal.
  TextColumn get solicitanteNombre => text().nullable()();

  TextColumn get solicitanteContacto => text().nullable()();

  TextColumn get solicitanteTelefono => text().nullable()();

  TextColumn get solicitanteCorreo => text().nullable()();

  /// A quién se le factura, cuando el solicitante es un **Cliente**
  /// (schemaVersion 90). FK real a la `EntidadFiscal` que él ya tiene
  /// registrada: aquí no se recaptura razón social ni RFC, se apunta a
  /// la que es. El snapshot congelado se toma de ella al registrar el
  /// CFDI, no antes.
  ///
  /// Nullable porque un eventual sin factura no necesita receptor
  /// fiscal, y porque el histórico anterior a la v90 no lo tiene.
  TextColumn get entidadFiscalId =>
      text().nullable().references(EntidadFiscal, #id, onDelete: KeyAction.restrict)();

  /// Receptor fiscal de un solicitante **ocasional** (schemaVersion
  /// 90) — quien pide el servicio y a nombre de quién se factura no
  /// son el mismo dato, y asumir que sí era el hueco real: "Juan del
  /// comité" no es "Administradora Bosques S.A. de C.V.".
  ///
  /// Sigue siendo un **snapshot**, nunca un `Cliente` ni una
  /// `EntidadFiscal` permanente: facturarle una vez a alguien no lo
  /// convierte en cartera.
  TextColumn get solicitanteRazonSocial => text().nullable()();

  TextColumn get solicitanteRfc => text().nullable()();

  /// CP del domicilio fiscal — obligatorio en un CFDI 4.0 y por eso
  /// parte del mínimo, no un extra. Mismo formato que el de
  /// `Empleado.codigoPostalFiscal`, validado por el mismo
  /// `CodigoPostalFiscalValidator`.
  TextColumn get solicitanteCodigoPostalFiscal => text().nullable()();

  /// Independiente por completo del estado del dinero (§16 del pedido):
  /// "con factura" no significa pendiente, ni "sin factura" contado.
  /// Cómo se acordó el precio (schemaVersion 89) — `masIva`,
  /// `ivaIncluido` o `noAplica`. Reutiliza `TratamientoIva` de
  /// Comercial, nunca un enum paralelo.
  ///
  /// **Se guarda sólo este dato comercial**: subtotal, IVA y total se
  /// derivan de él y de [importeAcordado] con
  /// `calcularTotalesVentaEventual`. Guardar los tres números sería
  /// invitar a que un día no cuadren entre sí.
  ///
  /// Es independiente de [requiereFactura]: un evento sin factura puede
  /// acordarse "más IVA" igual, y uno con factura puede ser `noAplica`
  /// si la operación está exenta. Nunca se deriva uno del otro.
  ///
  /// El default reproduce el comportamiento de la schemaVersion 88, en
  /// la que [importeAcordado] era directamente el total.
  TextColumn get tratamientoIva => text().withDefault(const Constant('noAplica'))();

  BoolColumn get requiereFactura => boolean().withDefault(const Constant(false))();

  TextColumn get motivoCancelacion => text().nullable()();

  TextColumn get actorUsuarioId => text().nullable().references(Usuario, #id, onDelete: KeyAction.setNull)();

  @override
  List<String> get customConstraints => [
        'CHECK (importe_acordado > 0)',
        'CHECK (fecha_hora_fin >= fecha_hora_inicio)',
        // Las dos formas de solicitante son excluyentes y completas: un
        // Cliente nunca lleva nombre paralelo, y un solicitante
        // ocasional siempre tiene al menos nombre.
        'CHECK ((tipo_solicitante = \'cliente\' AND cliente_id IS NOT NULL AND solicitante_nombre IS NULL) OR '
            '(tipo_solicitante = \'eventual\' AND cliente_id IS NULL AND solicitante_nombre IS NOT NULL))',
      ];
}

/// Quién trabajó en el evento — **hijo del eventual**, nunca un
/// catálogo global ni un expediente de RH.
///
/// Existe como fila propia (y no como snapshot repetido en cada
/// cobertura) por una razón concreta: en un evento de tres días el
/// mismo externo tiene tres coberturas, y repetir su nombre y teléfono
/// tres veces es una fuente de divergencia. Un participante, N
/// coberturas.
///
/// **No se deduplica entre eventuales**: el mismo "Juan" de dos eventos
/// distintos son dos filas. Deduplicarlo exigiría una identidad que no
/// tenemos y convertiría esto en el catálogo que no queremos.
class ServicioEventualParticipante extends Table with AuditColumns {
  TextColumn get servicioEventualId =>
      text().references(ServicioEventual, #id, onDelete: KeyAction.cascade)();

  /// Empleado RISEG — FK real, sin copiar su expediente.
  TextColumn get empleadoId => text().nullable().references(Empleado, #id, onDelete: KeyAction.restrict)();

  /// Externo contratado sólo para esta cobertura. Snapshot mínimo:
  /// nunca se crea un `Empleado`.
  TextColumn get nombreExterno => text().nullable()();

  TextColumn get telefonoExterno => text().nullable()();

  TextColumn get observaciones => text().nullable()();

  TextColumn get actorUsuarioId => text().nullable().references(Usuario, #id, onDelete: KeyAction.setNull)();

  @override
  List<String> get customConstraints => [
        'CHECK ((empleado_id IS NOT NULL AND nombre_externo IS NULL) OR '
            '(empleado_id IS NULL AND nombre_externo IS NOT NULL))',
      ];
}

/// Estado de una cobertura o de un costo adicional. Mismo vocabulario
/// en ambos a propósito: son el mismo modelo mental —algo que se
/// compromete y después se paga—, y un solo juego de nombres evita que
/// la UI tenga que traducir.
enum EstatusEjecucionServicioEventual { programada, pagada, cancelada }

/// Una persona cubriendo un turno del evento (Rebanada 1).
///
/// **Programar una cobertura NO mueve dinero.** Es un costo
/// comprometido. El efecto financiero nace en la operación explícita
/// "Pagar cobertura", y sólo entonces se pueblan `egresoId` ∥ `deudaId`.
/// Esa separación es la que permite derivar por separado el costo
/// comprometido y el costo efectivamente pagado.
///
/// **No es un Tiempo Extra.** Un TEX es una cobertura extraordinaria
/// DENTRO de un Servicio permanente, causada por una ausencia o una
/// vacante; aquí no hay empleado ausente ni motivo de cobertura: hay una
/// persona contratada para ejecutar el trabajo puntual vendido.
class ServicioEventualCobertura extends Table with AuditColumns {
  TextColumn get servicioEventualId =>
      text().references(ServicioEventual, #id, onDelete: KeyAction.cascade)();

  TextColumn get participanteId =>
      text().references(ServicioEventualParticipante, #id, onDelete: KeyAction.restrict)();

  DateTimeColumn get fecha => dateTime()();

  /// Horario real, no una FK a `TipoModalidadTurno`: un eventual puede
  /// tener horarios que no corresponden a ninguna modalidad del
  /// catálogo operativo.
  ///
  /// Se guardan como minutos desde medianoche (0–1439). Un turno
  /// nocturno cruza medianoche y entonces `horaFinMinutos <=
  /// horaInicioMinutos` — eso es válido y NO significa duración
  /// negativa: la duración se calcula sumando 24 h cuando cruza (ver
  /// `duracionCoberturaMinutos`). Por eso NO hay un CHECK
  /// `fin > inicio`, que sería exactamente el error que se quiere
  /// evitar.
  IntColumn get horaInicioMinutos => integer()();

  IntColumn get horaFinMinutos => integer()();

  TextColumn get descripcionHorario => text().nullable()();

  IntColumn get importeAcordado => integer()();

  TextColumn get estatus => text().withDefault(const Constant('programada'))();

  /// Poblados sólo al pagar. Mutuamente excluyentes, mismo patrón dual
  /// que `TiempoExtra.egresoId`/`deudaId`.
  TextColumn get formaPago => text().nullable()();

  TextColumn get egresoId => text().nullable().unique().references(Egreso, #id, onDelete: KeyAction.restrict)();

  TextColumn get deudaId => text().nullable().references(Deuda, #id, onDelete: KeyAction.restrict)();

  /// Sólo informativo del pago (de qué cuenta salió) — la verdad del
  /// dinero vive en el `Egreso`.
  TextColumn get cuentaFinancieraId =>
      text().nullable().references(CuentaFinanciera, #id, onDelete: KeyAction.restrict)();

  TextColumn get motivoCancelacion => text().nullable()();

  TextColumn get actorUsuarioId => text().nullable().references(Usuario, #id, onDelete: KeyAction.setNull)();

  @override
  List<String> get customConstraints => [
        'CHECK (importe_acordado > 0)',
        'CHECK (hora_inicio_minutos >= 0 AND hora_inicio_minutos < 1440)',
        'CHECK (hora_fin_minutos >= 0 AND hora_fin_minutos < 1440)',
        'CHECK (NOT (egreso_id IS NOT NULL AND deuda_id IS NOT NULL))',
        // La invariante que hace imposible "pagada" sin dinero real
        // detrás, a nivel de base de datos y no sólo de dominio.
        'CHECK (estatus <> \'pagada\' OR egreso_id IS NOT NULL OR deuda_id IS NOT NULL)',
      ];
}

/// Otros costos del evento — casetas, estacionamiento, alimentos,
/// transporte, material. `concepto` es texto libre (el formulario
/// sugiere, nunca cierra un catálogo), mismo criterio exacto que
/// `TiempoExtraCostoAdicional`.
///
/// Cada costo lleva su PROPIO origen financiero: nunca se fusionan dos
/// costos en un solo Egreso combinado, ni siquiera si comparten cuenta,
/// para no perder trazabilidad por ítem.
class ServicioEventualCosto extends Table with AuditColumns {
  TextColumn get servicioEventualId =>
      text().references(ServicioEventual, #id, onDelete: KeyAction.cascade)();

  TextColumn get concepto => text()();

  IntColumn get monto => integer()();

  DateTimeColumn get fecha => dateTime()();

  TextColumn get estatus => text().withDefault(const Constant('programada'))();

  TextColumn get formaPago => text().nullable()();

  TextColumn get egresoId => text().nullable().unique().references(Egreso, #id, onDelete: KeyAction.restrict)();

  TextColumn get deudaId => text().nullable().references(Deuda, #id, onDelete: KeyAction.restrict)();

  TextColumn get cuentaFinancieraId =>
      text().nullable().references(CuentaFinanciera, #id, onDelete: KeyAction.restrict)();

  TextColumn get observaciones => text().nullable()();

  TextColumn get motivoCancelacion => text().nullable()();

  TextColumn get actorUsuarioId => text().nullable().references(Usuario, #id, onDelete: KeyAction.setNull)();

  @override
  List<String> get customConstraints => [
        'CHECK (monto > 0)',
        'CHECK (NOT (egreso_id IS NOT NULL AND deuda_id IS NOT NULL))',
        'CHECK (estatus <> \'pagada\' OR egreso_id IS NOT NULL OR deuda_id IS NOT NULL)',
      ];
}

/// Historial append-only del eventual — nunca se actualiza ni se
/// elimina una fila existente.
class ServicioEventualEvento extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get servicioEventualId =>
      text().references(ServicioEventual, #id, onDelete: KeyAction.cascade)();

  DateTimeColumn get fechaHora => dateTime()();

  TextColumn get tipoEvento => text()();

  /// La cobertura o el costo al que se refiere el hecho, cuando aplica
  /// — por id real, nunca por texto.
  TextColumn get coberturaId => text().nullable()();

  TextColumn get costoId => text().nullable()();

  TextColumn get participanteId => text().nullable()();

  TextColumn get estadoAnterior => text().nullable()();

  TextColumn get estadoNuevo => text().nullable()();

  TextColumn get observacion => text().nullable()();

  TextColumn get actorUsuarioId => text().nullable().references(Usuario, #id, onDelete: KeyAction.setNull)();
}

/// Duración real de una cobertura en minutos. Un turno nocturno cruza
/// medianoche (ej. 22:00 → 06:00): ahí `fin <= inicio` y la duración es
/// `1440 - inicio + fin`. Nunca negativa.
int duracionCoberturaMinutos({required int horaInicioMinutos, required int horaFinMinutos}) {
  final directa = horaFinMinutos - horaInicioMinutos;
  return directa > 0 ? directa : directa + 1440;
}
