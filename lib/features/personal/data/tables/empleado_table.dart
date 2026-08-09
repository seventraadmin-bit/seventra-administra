import 'package:drift/drift.dart';

import '../../../../core/database/tables/attachment_table.dart';
import '../../../../core/database/tables/audit_columns.dart';
import '../../../organizacion/data/tables/empresa_table.dart';
import '../../../organizacion/data/tables/puesto_table.dart';
import '../../../organizacion/data/tables/sucursal_table.dart';

enum SexoEmpleado { masculino, femenino }

enum EstadoCivilEmpleado { soltero, casado, divorciado, viudo, unionLibre }

enum EstatusEmpleado { activo, baja }

enum NivelEstudiosEmpleado { sinEstudios, primaria, secundaria, bachillerato, tecnico, licenciatura, posgrado }

/// Tipos de evento del historial administrativo de un Empleado — mismo
/// criterio *append-only* que `PagoEvento`/`IngresoEvento`/
/// `ComplementoPagoEvento`. `corregido` cubre cualquier edición de
/// datos generales/contacto/laboral/escolaridad/experiencia en un solo
/// tipo — mismo criterio que el resto del proyecto (un Pago corregido
/// no distingue qué campo cambió a nivel de `tipoEvento`).
enum TipoEventoEmpleado {
  creado,
  corregido,
  cambioEstatus,
  domicilioActualizado,
  fotografiaActualizada,
  documentoAdjuntado,
  documentoArchivado,
}

/// Expediente del empleado (Etapa 5A) — la base sobre la que se
/// apoyarán Nómina, Inventario, Asignaciones y la Ficha técnica en
/// etapas futuras. Nace exclusivamente con información general,
/// contacto, información laboral, escolaridad y experiencia general en
/// seguridad privada — sin historial laboral estructurado por
/// empleador (Resolución explícita de Marlon: "no quiero obligar al
/// usuario a capturar todo el historial de empleadores... si en el
/// futuro construimos un módulo de Reclutamiento, ahí sí").
///
/// El domicilio **no** vive aquí — reutiliza `Direccion` (arco
/// exclusivo existente, extendido a 6 vías con `empleadoId`). La
/// documentación (INE, CURP, contrato, etc.) tampoco — usa
/// `EmpleadoAttachment`, la tabla puente de la infraestructura de
/// Attachments (Etapa 5A también migró `Attachment` a este patrón; ver
/// el doc comment de esa tabla).
///
/// `edad` deliberadamente **no** es una columna — se deriva de
/// `fechaNacimiento` en tiempo de consulta (`calcularEdad`), mismo
/// criterio que `estaVencida`/`calcularRangoAntiguedad` (4J.1) y
/// `complementoPendiente` (4J.3): nunca almacenar lo que se puede
/// derivar.
class Empleado extends Table with AuditColumns {
  TextColumn get codigoEmpleado => text().unique()();

  /// Puntero directo a *la* fotografía vigente — mismo patrón que
  /// `Empresa.logoAttachmentId`. La fotografía también existe como fila
  /// en `EmpleadoAttachment` (categoría `fotografia`); este puntero es
  /// solo para no tener que resolverla por consulta en cada listado.
  TextColumn get fotografiaAttachmentId =>
      text().nullable().references(Attachment, #id, onDelete: KeyAction.restrict)();

  // --- Información general ---

  TextColumn get nombres => text()();

  TextColumn get apellidoPaterno => text()();

  TextColumn get apellidoMaterno => text().nullable()();

  TextColumn get sexo => text()();

  DateTimeColumn get fechaNacimiento => dateTime()();

  TextColumn get curp => text()();

  TextColumn get rfc => text()();

  TextColumn get nss => text()();

  TextColumn get estadoCivil => text()();

  TextColumn get nacionalidad => text().withDefault(const Constant('Mexicana'))();

  // --- Contacto ---

  TextColumn get telefono => text().nullable()();

  TextColumn get correoElectronico => text().nullable()();

  TextColumn get contactoEmergenciaNombre => text().nullable()();

  TextColumn get telefonoEmergencia => text().nullable()();

  TextColumn get parentescoEmergencia => text().nullable()();

  // --- Información laboral ---

  DateTimeColumn get fechaIngreso => dateTime()();

  TextColumn get estatus => text().withDefault(const Constant('activo'))();

  TextColumn get puestoId => text().nullable().references(Puesto, #id, onDelete: KeyAction.restrict)();

  TextColumn get empresaId => text().nullable().references(Empresa, #id, onDelete: KeyAction.restrict)();

  TextColumn get sucursalId => text().nullable().references(Sucursal, #id, onDelete: KeyAction.restrict)();

  TextColumn get observaciones => text().nullable()();

  // --- Escolaridad ---

  TextColumn get nivelEstudios => text().nullable()();

  TextColumn get observacionesEscolaridad => text().nullable()();

  // --- Experiencia en seguridad privada (Resolución de Marlon: sin
  // historial estructurado por empleador) ---

  IntColumn get aniosExperienciaSeguridad => integer()();

  IntColumn get mesesExperienciaAdicionales => integer().nullable()();

  TextColumn get ultimoPuestoDesempenado => text().nullable()();

  TextColumn get resumenExperiencia => text().nullable()();

  TextColumn get observacionesExperiencia => text().nullable()();

  @override
  List<String> get customConstraints => [
        'CHECK (anios_experiencia_seguridad >= 0)',
        'CHECK (meses_experiencia_adicionales IS NULL OR '
            '(meses_experiencia_adicionales >= 0 AND meses_experiencia_adicionales <= 11))',
      ];
}

/// Historial administrativo de un Empleado — tabla de solo inserción,
/// mismo criterio exacto que `PagoEvento`/`IngresoEvento`.
class EmpleadoEvento extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get empleadoId => text().references(Empleado, #id, onDelete: KeyAction.cascade)();

  DateTimeColumn get fechaHora => dateTime()();

  TextColumn get tipoEvento => text()();

  TextColumn get estadoAnterior => text().nullable()();

  TextColumn get estadoNuevo => text().nullable()();

  TextColumn get observacion => text().nullable()();

  TextColumn get actor => text().nullable()();

  TextColumn get datosRelevantes => text().nullable()();
}
