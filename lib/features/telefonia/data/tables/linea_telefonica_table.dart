import 'package:drift/drift.dart';

import '../../../../core/database/tables/audit_columns.dart';

/// Catálogo de operadores (Etapa 9A) — enum, no tabla administrable
/// (mínimo pedido por Marlon: "no quiero pantalla de administración si
/// no aporta valor"). `otro` exige `LineaTelefonica.operadorOtroNombre`
/// — mismo mecanismo que `VehiculoDocumento.tipoOtroDescripcion`.
enum OperadorTelefonico { telcel, att, movistar, otro }

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
