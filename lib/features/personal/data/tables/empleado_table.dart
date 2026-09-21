import 'package:drift/drift.dart';

import '../../../../core/database/tables/attachment_table.dart';
import '../../../../core/database/tables/audit_columns.dart';
import '../../../../core/database/tables/catalogos_tables.dart';
import '../../../organizacion/data/tables/empresa_table.dart';
import '../../../organizacion/data/tables/puesto_table.dart';
import '../../../organizacion/data/tables/sucursal_table.dart';
import '../../../usuarios/data/tables/usuario_table.dart';

enum SexoEmpleado { masculino, femenino }

enum EstadoCivilEmpleado { soltero, casado, divorciado, viudo, unionLibre }

enum EstatusEmpleado { activo, baja }

/// Motivo de baja laboral (Etapa 5C) — enum enriquecido a propósito:
/// `generaAdvertenciaRecontratacion`/`requiereObservaciones` viven como
/// propiedad de cada valor, no como una lista codificada aparte dentro
/// de `calcularAlertaRecontratacion` (Resolución explícita de Marlon:
/// "quiero dejar preparada la arquitectura para que posteriormente cada
/// motivo de baja pueda definir si genera o no una advertencia"). El
/// día que esto se vuelva un catálogo administrable, el reemplazo es
/// una consulta a esa tabla en vez de esta propiedad — ningún llamador
/// de `calcularAlertaRecontratacion` cambia.
enum MotivoBajaEmpleado {
  abandonoServicio(generaAdvertenciaRecontratacion: true),
  robo(generaAdvertenciaRecontratacion: true),
  malaConducta(generaAdvertenciaRecontratacion: true),
  inasistencias(generaAdvertenciaRecontratacion: true),
  incumplimientoConsignas(generaAdvertenciaRecontratacion: true),
  noAproboCapacitacion(generaAdvertenciaRecontratacion: true),
  renuncia(generaAdvertenciaRecontratacion: false),
  finContrato(generaAdvertenciaRecontratacion: false),
  reduccionPersonal(generaAdvertenciaRecontratacion: false),
  otro(generaAdvertenciaRecontratacion: true, requiereObservaciones: true);

  const MotivoBajaEmpleado({required this.generaAdvertenciaRecontratacion, this.requiereObservaciones = false});

  final bool generaAdvertenciaRecontratacion;
  final bool requiereObservaciones;
}

enum NivelEstudiosEmpleado { sinEstudios, primaria, secundaria, bachillerato, tecnico, licenciatura, posgrado }

/// Resultado de una sustancia evaluada en un Antidoping (Etapa 5B) —
/// `noAplica` significa que esa sustancia no se incluyó en la prueba,
/// nunca "no realizado" a nivel de todo el Antidoping (ese estado ya
/// no existe: si nunca se captura un Antidoping, el Empleado
/// simplemente queda "pendiente" — ver `EmpleadoAlertas`). Deliberado
/// así para adaptarse a distintos paneles comerciales de laboratorio
/// sin complicar el modelo (Resolución explícita de Marlon).
enum ResultadoSustanciaAntidoping { negativo, positivo, noAplica }

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
  perfilPsicologicoActualizado,
  estudioSocioeconomicoActualizado,
  antidopingActualizado,
  bajaLaboral,
  reingreso,
  asignacionServicio,
  cambioServicio,
  retiroServicio,
  fichaTecnicaGenerada,

  /// Regularización de perfil de una `AsignacionServicio` histórica
  /// (Etapa 15, corrección de atribución histórica) — completa un
  /// `lineaComercialId` que había quedado `NULL` (dato pre-Etapa 15),
  /// sin crear una asignación nueva ni tocar fecha/sueldo/historial.
  regularizacionPerfilAsignacion,
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
/// derivar. `antigüedad` (Etapa 5C) sigue el mismo criterio —
/// `calcularCicloLaboralEmpleado` la deriva de `fechaIngreso`/`estatus`/
/// `fechaBaja`, nunca se almacena.
///
/// `fechaIngreso`/`estatus`/`puestoId`/`empresaId`/`sucursalId`
/// representan siempre el **periodo laboral vigente** (Etapa 5C) —
/// `fechaBaja`/`motivoBaja`/`observacionesBaja` lo completan cuando ese
/// periodo está cerrado (`estatus == baja`), null mientras está activo.
/// Un Reingreso (`RegistrarReingresoUseCase`) archiva ese periodo
/// cerrado en `EmpleadoPeriodoLaboral` y resetea estos 8 campos al
/// nuevo periodo — nunca crea un Empleado nuevo, nunca acumula
/// antigüedad entre periodos. `EmpleadoPeriodoLaboral` por diseño solo
/// contiene periodos ya cerrados y superados: el periodo vigente jamás
/// tiene una fila ahí, vive únicamente aquí. Esto evita cualquier
/// duplicación entre las dos tablas (Resolución explícita de Marlon).
///
/// Perfil psicológico, Estudio socioeconómico y Antidoping (Etapa 5B)
/// también viven aquí como columnas directas — mismo criterio que
/// Escolaridad/Experiencia: solo el valor vigente, nunca un historial
/// de evaluaciones repetidas.
class Empleado extends Table with AuditColumns {
  /// Identificador visible del empleado (Etapa 6A) — entero simple,
  /// consecutivo desde 1, **nunca** con prefijo ni relleno de ceros
  /// (Resolución explícita de Marlon: reemplaza el antiguo
  /// `codigoEmpleado` tipo `EMP-000001`). Se asigna una sola vez, al
  /// alta, vía `CodigoSecuenciaService.siguienteNumero('empleado')` —
  /// el mismo contador atómico/transaccional/nunca-reutilizado que ya
  /// usa `siguienteCodigo`, no un `MAX(numero_empleado) + 1`. Un
  /// reingreso (`RegistrarReingresoUseCase`) nunca vuelve a tocar esta
  /// columna — el mismo empleado conserva siempre el mismo número.
  IntColumn get numeroEmpleado => integer().unique()();

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

  /// Código postal de la Constancia de Situación Fiscal (Etapa 5D) —
  /// deliberadamente independiente del código postal del domicilio
  /// (vive en `Direccion`, arco exclusivo existente): son dos datos
  /// distintos que pueden no coincidir. Único dato fiscal adicional que
  /// se agrega en esta etapa — tiene un consumidor claro (Nómina, a
  /// futuro), no se agregan otros campos fiscales sin ese mismo criterio.
  TextColumn get codigoPostalFiscal => text().nullable()();

  TextColumn get nss => text()();

  TextColumn get estadoCivil => text()();

  TextColumn get nacionalidad => text().withDefault(const Constant('Mexicana'))();

  // --- Contacto ---

  TextColumn get telefono => text().nullable()();

  TextColumn get correoElectronico => text().nullable()();

  TextColumn get contactoEmergenciaNombre => text().nullable()();

  TextColumn get telefonoEmergencia => text().nullable()();

  TextColumn get parentescoEmergencia => text().nullable()();

  // --- Datos bancarios (Etapa 6A) — pertenecen a Personal; Nómina
  // solo los consulta, nunca los vuelve a capturar. Todo el bloque es
  // opcional; si se captura algo, `bancoId` es obligatorio y se
  // necesita al menos uno de `numeroCuentaTarjeta`/`clabe` (validado en
  // `EmpleadoValidator`, no como `CHECK` — es una regla condicional
  // entre columnas, no un invariante estructural simple). ---

  TextColumn get bancoId => text().nullable().references(Banco, #id, onDelete: KeyAction.restrict)();

  /// Nombre del banco cuando `bancoId` apunta al catálogo `'OTRO'`
  /// (Etapa 15) — la fila `Banco` "Otro" no tiene forma de guardar cuál
  /// banco es en realidad; este campo captura ese detalle. Solo tiene
  /// sentido cuando `bancoId == SeedIds.bancoOtro`, validado en
  /// `EmpleadoValidator`, no como `CHECK` (misma razón que el resto del
  /// bloque de datos bancarios: es una regla condicional entre
  /// columnas, no un invariante estructural simple). Mismo criterio ya
  /// usado por `Compra.formaPagoOtroDescripcion`.
  TextColumn get bancoOtroDescripcion => text().nullable()();

  TextColumn get numeroCuentaTarjeta => text().nullable()();

  TextColumn get clabe => text().nullable()();

  // --- Información laboral ---

  DateTimeColumn get fechaIngreso => dateTime()();

  TextColumn get estatus => text().withDefault(const Constant('activo'))();

  TextColumn get puestoId => text().nullable().references(Puesto, #id, onDelete: KeyAction.restrict)();

  TextColumn get empresaId => text().nullable().references(Empresa, #id, onDelete: KeyAction.restrict)();

  TextColumn get sucursalId => text().nullable().references(Sucursal, #id, onDelete: KeyAction.restrict)();

  /// Condición laboral administrativa (Etapa 6A) — fuente de sueldo/
  /// bono **únicamente** para empleados sin ninguna `AsignacionServicio`
  /// (adscritos a Sucursal, sin Servicio operativo asignado). Un
  /// empleado con `AsignacionServicio` obtiene su sueldo/bono de ahí
  /// (`AsignacionServicioSueldoVigencia`, Etapa 6B) — estos dos campos
  /// se ignoran en ese caso, nunca se combinan con la asignación. Sin
  /// vigencia/historial propio (Resolución explícita de Marlon: "no
  /// quiero crear una estructura de vigencias de Sucursal solo para
  /// esto") — el valor vigente vive aquí; el histórico protegido lo da
  /// el snapshot de cada Nómina ya generada, no esta tabla.
  IntColumn get sueldoMensualAdministrativo => integer().nullable()();

  IntColumn get bonoMensualAdministrativo => integer().nullable()();

  TextColumn get observaciones => text().nullable()();

  // --- Baja del periodo laboral vigente (Etapa 5C) — null mientras
  // `estatus == activo`. Ver el doc comment de la clase para el
  // criterio completo "vigente vs. archivado". ---

  DateTimeColumn get fechaBaja => dateTime().nullable()();

  TextColumn get motivoBaja => text().nullable()();

  TextColumn get observacionesBaja => text().nullable()();

  // --- Snapshot de baja (Etapa 15, rediseño de Personal/Bajas) — puro
  // texto de despliegue, capturado en el momento EXACTO de
  // `RegistrarBajaLaboralUseCase` (nunca resuelto en vivo después):
  // `puestoId` es el mismo puntero "vigente" que un Reingreso
  // sobrescribe, y `Servicio`/`Puesto` pueden corregirse de nombre más
  // adelante — sin este snapshot, "el puesto/servicio/turno al momento
  // de salir" se pierde o se reescribe silenciosamente. `null` mientras
  // `estatus == activo`, igual que el resto del bloque de baja.
  // `servicioNombreBaja`/`turnoNombreBaja` quedan `null` si el Empleado
  // no tenía ninguna `AsignacionServicio` vigente al momento de la baja
  // (nunca se inventa un Servicio que no existía).
  TextColumn get puestoNombreBaja => text().nullable()();

  TextColumn get servicioNombreBaja => text().nullable()();

  TextColumn get turnoNombreBaja => text().nullable()();

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

  // --- Perfil psicológico (Etapa 5B) — solo el valor vigente, sin
  // historial de evaluaciones (Resolución explícita de Marlon: "no
  // quiero tablas satélite ni historiales de evaluaciones en esta
  // etapa"). El PDF opcional vive en `EmpleadoAttachment` (categoría
  // `perfilPsicologico`), no aquí. ---

  DateTimeColumn get fechaEvaluacionPsicologica => dateTime().nullable()();

  TextColumn get resumenPsicologico => text().nullable()();

  TextColumn get observacionesPsicologico => text().nullable()();

  // --- Estudio socioeconómico (Etapa 5B) — mismo criterio que Perfil
  // psicológico: solo el valor vigente. ---

  DateTimeColumn get fechaEstudioSocioeconomico => dateTime().nullable()();

  TextColumn get resumenEstudioSocioeconomico => text().nullable()();

  TextColumn get observacionesEstudioSocioeconomico => text().nullable()();

  // --- Antidoping (Etapa 5B) — un resultado por sustancia evaluada,
  // no un resultado único general (Resolución explícita de Marlon).
  // `fechaAntidoping == null` es la señal de "pendiente" — ver
  // `EmpleadoAlertas`. ---

  DateTimeColumn get fechaAntidoping => dateTime().nullable()();

  TextColumn get resultadoAmp => text().nullable()();

  TextColumn get resultadoBzd => text().nullable()();

  TextColumn get resultadoCoc => text().nullable()();

  TextColumn get resultadoMet => text().nullable()();

  TextColumn get resultadoOpi => text().nullable()();

  TextColumn get observacionesAntidoping => text().nullable()();

  @override
  List<String> get customConstraints => [
        'CHECK (anios_experiencia_seguridad >= 0)',
        'CHECK (meses_experiencia_adicionales IS NULL OR '
            '(meses_experiencia_adicionales >= 0 AND meses_experiencia_adicionales <= 11))',
        'CHECK (sueldo_mensual_administrativo IS NULL OR sueldo_mensual_administrativo > 0)',
        'CHECK (bono_mensual_administrativo IS NULL OR bono_mensual_administrativo >= 0)',
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

  /// **Legacy (Etapa 11D)** — nunca se pobló con un valor real; se
  /// conserva la columna físicamente por seguridad de migración pero
  /// ningún código desde 11D en adelante la lee ni la escribe. La única
  /// fuente funcional de "quién" es `actorUsuarioId`.
  TextColumn get actor => text().nullable()();

  TextColumn get actorUsuarioId => text().nullable().references(Usuario, #id, onDelete: KeyAction.setNull)();

  TextColumn get datosRelevantes => text().nullable()();
}

/// Historial de periodos laborales **cerrados** de un Empleado (Etapa
/// 5C) — solo se inserta una fila aquí al momento de un Reingreso, para
/// archivar el periodo que se está cerrando (ver el doc comment de
/// `Empleado`). El periodo vigente nunca tiene fila aquí; se lee
/// directamente de `Empleado`. Tabla de solo inserción, inmutable —
/// mismo criterio que `EmpleadoEvento`.
class EmpleadoPeriodoLaboral extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get empleadoId => text().references(Empleado, #id, onDelete: KeyAction.cascade)();

  DateTimeColumn get fechaIngreso => dateTime()();

  DateTimeColumn get fechaBaja => dateTime()();

  TextColumn get motivoBaja => text()();

  TextColumn get observacionesBaja => text().nullable()();

  // --- Snapshot de baja (Etapa 15) — copiado tal cual desde
  // `Empleado.puestoNombreBaja`/`servicioNombreBaja`/`turnoNombreBaja`
  // en el momento exacto en que `RegistrarReingresoUseCase` archiva
  // este periodo (esos 3 campos ya estaban capturados desde la baja,
  // sin resolver nada de nuevo aquí). `null` en periodos archivados
  // antes de que este snapshot existiera — nunca inventado
  // retroactivamente. ---
  TextColumn get puestoNombre => text().nullable()();

  TextColumn get servicioNombre => text().nullable()();

  TextColumn get turnoNombre => text().nullable()();

  @override
  List<String> get customConstraints => ['CHECK (fecha_baja >= fecha_ingreso)'];
}
