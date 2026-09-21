import 'package:drift/drift.dart';
import '../../../usuarios/data/tables/usuario_table.dart';

import '../../../../core/database/tables/audit_columns.dart';

/// Catálogo de operadores (Etapa 9A) — enum, no tabla administrable
/// (mínimo pedido por Marlon: "no quiero pantalla de administración si
/// no aporta valor"). `otro` exige `LineaTelefonica.operadorOtroNombre`
/// — mismo mecanismo que `VehiculoDocumento.tipoOtroDescripcion`.
/// `bait` se añadió en la Rebanada 3: en la base real aparecía tres
/// veces como `otro` + texto libre ("BAIT", "Bait"), que es justo la
/// variante accidental que un enum evita. Añadir un valor a una columna
/// de texto no necesita migración. Las filas históricas NO se
/// reescribieron: cambiarlas es una corrección con su diff auditado,
/// desde Editar línea.
enum OperadorTelefonico { telcel, att, movistar, bait, otro }

/// SIM física o eSIM (Etapa 9A) — un único campo `iccid` (nullable)
/// cubre ambas modalidades, sin `eid` ni otros campos técnicos que no
/// aportan valor operativo (instrucción explícita de Marlon).
enum ModalidadSim { fisica, esim }

/// Condición operativa de una línea (Etapa 9A) — deliberadamente sin
/// `disponible`: a diferencia de `Vehiculo` (donde `disponible` gatea si
/// se puede asignar), una línea puede estar `activa` con o sin
/// asignación simultáneamente (una línea sin asignar es una condición
/// normal, no una restricción de estatus) — asignación y estatus son
/// ejes independientes aquí.
enum EstatusLineaTelefonica { activa, suspendida, baja }

/// Motivo de baja (Etapa 9A) — enum enriquecido, mismo mecanismo que
/// `MotivoBajaVehiculo`.
enum MotivoBajaLineaTelefonica {
  cancelacion(requiereObservaciones: false),
  cambioOperador(requiereObservaciones: false),
  perdidaDelNumero(requiereObservaciones: true),
  otro(requiereObservaciones: true);

  const MotivoBajaLineaTelefonica({required this.requiereObservaciones});

  final bool requiereObservaciones;
}

/// Una línea telefónica de RISEG (Etapa 9A) — el control operativo/
/// contractual de la línea en sí, nunca del equipo físico (ese ya vive
/// en `ArticuloUnidad`/`ArticuloUnidadTelefono` de Inventario; Telefonía
/// solo lo referencia, ver `LineaTelefonicaEquipo` en la Etapa 9B).
///
/// `numero` es opcional (una SIM en trámite puede no tener número
/// asignado todavía) pero único cuando se captura — mismo mecanismo que
/// `Vehiculo.placas`/`Vehiculo.vin` (índice único parcial, ver la
/// migración dedicada). `codigo` es el identificador estable siempre
/// presente, generado (`CodigoSecuenciaService`, prefijo `TEL`).
///
/// Plan/costo vive en `LineaTelefonicaPlan` (tabla separada, Etapa 9A) —
/// nunca una columna aquí, para poder conservar el histórico de cambios
/// de precio sin editar esta fila.
///
/// `fechaBaja`/`motivoBaja`/`observacionesBaja` viven directamente en
/// esta fila (no una tabla de periodos) — mismo criterio que `Vehiculo`:
/// nada en el alcance pide un ciclo de reingreso para una línea dada de
/// baja.
@TableIndex.sql(
  'CREATE UNIQUE INDEX idx_linea_telefonica_numero_unico '
  'ON linea_telefonica (numero) WHERE numero IS NOT NULL',
)
class LineaTelefonica extends Table with AuditColumns {
  TextColumn get codigo => text().unique()();

  TextColumn get numero => text().nullable()();

  TextColumn get operador => text()();

  /// Solo aplica cuando `operador == otro`. Obligatorio en ese caso
  /// (validado en `CrearLineaTelefonicaUseCase`/`CorregirLineaTelefonicaUseCase`,
  /// no por `CHECK` — mismo criterio que el resto del proyecto para
  /// reglas que dependen del valor de otra columna tipo-enum).
  TextColumn get operadorOtroNombre => text().nullable()();

  TextColumn get modalidadSim => text()();

  TextColumn get iccid => text().nullable()();

  DateTimeColumn get fechaActivacion => dateTime().nullable()();

  TextColumn get estatus => text().withDefault(const Constant('activa'))();

  TextColumn get observaciones => text().nullable()();

  DateTimeColumn get fechaBaja => dateTime().nullable()();

  TextColumn get motivoBaja => text().nullable()();

  TextColumn get observacionesBaja => text().nullable()();

  @override
  List<String> get customConstraints => [
        "CHECK ((estatus = 'baja' AND fecha_baja IS NOT NULL) OR "
            "(estatus != 'baja' AND fecha_baja IS NULL))",
      ];
}

/// Tipos de evento del historial de una línea telefónica
/// (schemaVersion 81).
///
/// Una sola tabla cubre la línea Y sus recargas — mismo criterio exacto
/// que `VehiculoEvento`, que ya cubre el vehículo y su mantenimiento:
/// una recarga no tiene vida propia fuera de su línea, y separar en dos
/// tablas obligaría a leer dos historiales para responder "qué pasó con
/// esta línea".
///
/// **`recargaRegistrada` no existe a propósito**: el alta de una recarga
/// YA es auditable por la propia fila de `RecargaLineaTelefonica`
/// (fecha, importe, actor), que la Auditoría central proyecta desde la
/// Etapa 11D. Emitir además un evento sería exactamente la duplicación
/// que esta etapa debe evitar — y dejaría fuera a las recargas
/// históricas, que no tendrían evento. Lo que la fila NO puede expresar
/// —corregirse o anularse— sí lleva evento.
enum TipoEventoLineaTelefonica {
  creada,
  corregida,
  estatusCambiado,
  dadaDeBaja,
  recargaCorregida,
  recargaCancelada,

  /// Corrección administrativa de una incoherencia histórica entre la
  /// asignación de la línea y la custodia del equipo que la trae
  /// (Rebanada 2). La fila de `AsignacionLineaTelefonica` registra el
  /// actor y el periodo, pero no puede expresar "venía roto así y
  /// quedó así" ni el motivo — por eso el evento no es decorativo.
  incoherenciaResuelta,

  /// La asignación de la línea cambió **como consecuencia** de una
  /// operación autorizada de Inventario sobre la custodia del aparato
  /// (§1B de la Rebanada 3), no porque alguien la haya editado en
  /// Telefonía.
  ///
  /// La fila de `AsignacionLineaTelefonica` sola no puede decirlo: no
  /// tiene dónde guardar el origen, el antes/después ni el aparato
  /// involucrado. Por eso el evento no es decorativo — es lo único que
  /// permite distinguir en la bitácora un cambio MANUAL de una
  /// consecuencia sistémica.
  ///
  /// **No implica permiso**: quien hizo la operación tenía autorización
  /// de Inventario, nunca `telefonia.modificar`.
  asignacionSincronizadaPorInventario,
}

/// Historial append-only de una línea telefónica (schemaVersion 81) —
/// mismo molde que `VehiculoEvento`/`TiempoExtraEvento`:
/// `estadoAnterior`/`estadoNuevo` guardan SOLO los campos que
/// realmente cambiaron (vía `DiffEvento`), nunca un snapshot completo.
///
/// PRIVACIDAD: `numero` e `iccid` son identificadores sensibles. El
/// diff los registra **enmascarados** (`ICCID ····3456`), no en claro —
/// ver `enmascararIdentificador`. Así el auditor puede verificar QUE
/// cambiaron y distinguir un valor de otro, sin que la pantalla de
/// Auditoría se convierta en un directorio de SIMs.
class LineaTelefonicaEvento extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get lineaTelefonicaId => text().references(LineaTelefonica, #id, onDelete: KeyAction.cascade)();

  /// Poblado solo en los eventos de recarga — nunca en los de la línea.
  TextColumn get recargaId => text().nullable()();

  DateTimeColumn get fechaHora => dateTime()();

  TextColumn get tipoEvento => text()();

  /// El motivo, cuando el dominio lo exige (corrección, cancelación).
  /// `null` en un alta: no todo evento tiene motivo, y nunca se inventa.
  TextColumn get observacion => text().nullable()();

  TextColumn get actorUsuarioId => text().nullable().references(Usuario, #id, onDelete: KeyAction.setNull)();

  TextColumn get estadoAnterior => text().nullable()();

  TextColumn get estadoNuevo => text().nullable()();
}
