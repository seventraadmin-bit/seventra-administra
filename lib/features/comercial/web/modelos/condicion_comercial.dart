/// Las líneas comerciales de un servicio, sus condiciones versionadas y el sueldo de
/// referencia con el que se ofrece el puesto.
///
/// ## Qué es una línea, y por qué su identidad es estable
///
/// Una **línea comercial** es una cosa que se cobra dentro de un servicio: «12 guardias
/// 24×24» es una línea, «1 supervisor» es otra. Su identidad **sobrevive a todo cambio de
/// precio, plazas, puesto, turno y horario**, porque esos cambios abren una **condición**
/// nueva y no tocan la línea. Si la línea llevara el precio, subirlo obligaría a recrearla
/// y se perdería la continuidad de lo que se le cobra al cliente.
///
/// ## Las DOS líneas de tiempo, que es lo que C3 añadió
///
/// Sobre la misma línea corren dos vigencias independientes:
///
///  · **la condición** —precio, IVA, plazas, puesto, turno y horario—, que se negocia con
///    el cliente;
///  · **el sueldo de referencia** —lo que se ofrece al reclutar—, que lo mueve el mercado
///    laboral.
///
/// ⚠️ **Están separadas a propósito** (migración 0065): antes el sueldo vivía dentro de la
/// condición, así que subirlo donde hay rotación obligaba a **recapturar el contrato del
/// cliente**. Lo que se quería mover era una cifra interna; lo que el modelo obligaba a
/// mover era el precio.
///
/// 🚫 **Y el sueldo de referencia NO es el sueldo de nadie.** Pre-llena el formulario al
/// asignar personal; el sueldo real de cada persona vive en su asignación. Cambiarlo aquí no
/// le cambia el sueldo a ningún empleado.
///
/// Modelos planos y propios de la web, igual que `Servicio`: aquí no hay Drift.
library;

import '../../../../core/fechas/dia_de_negocio.dart';

/// Una modalidad de turno del catálogo de la empresa.
///
/// 🚫 **Es una etiqueta, no un horario.** De «24×24» no se deriva ninguna hora: el horario
/// vive en los bloques de la condición. Lo que la modalidad aporta es el nombre con el que
/// se habla del rol y, desde la 0064, **la explicación que se lee al elegirlo**.
class ModalidadDeTurno {
  const ModalidadDeTurno({
    required this.id,
    required this.codigo,
    required this.nombre,
    required this.explicacion,
    required this.pidePeriodo,
    required this.capturaDelHorario,
    required this.minutosDelTurno,
    required this.estatus,
  });

  factory ModalidadDeTurno.deJson(Map<String, dynamic> json) => ModalidadDeTurno(
    id: json['id'] as String,
    codigo: json['code'] as String,
    nombre: json['name'] as String,
    explicacion: json['description'] as String?,
    pidePeriodo: json['requiresPeriod'] as bool? ?? false,
    capturaDelHorario: CapturaDelHorario.deCodigo(json['scheduleStyle'] as String?),
    minutosDelTurno: json['shiftMinutes'] as int?,
    estatus: json['status'] as String,
  );

  final String id;
  final String codigo;
  final String nombre;

  /// La explicación que se enseña al elegir el turno, con **cuántas personas hacen falta
  /// para cubrir un puesto 24/7**.
  ///
  /// Es **editable en el catálogo** por decisión del dueño: esa cuenta cambia con la ley y
  /// con la costumbre, y corregirla no puede costar un despliegue. Puede ser nula —una
  /// modalidad propia que nadie explicó todavía—, y entonces la pantalla no inventa nada.
  final String? explicacion;

  /// ¿Hay que decir si la plaza es **diurna o nocturna**?
  ///
  /// ⚠️ **Lo decide la modalidad, NO su nombre.** «12×24» cubre el día completo rotando, así
  /// que el periodo no significaría nada; «12×12» sí lo necesita, porque una plaza es de día
  /// o de noche y **se cobra distinto**. Deducirlo de una lista de códigos en la pantalla
  /// sería una regla de negocio que ninguna empresa podría corregir.
  final bool pidePeriodo;

  /// **Cómo se captura el horario** de una condición con esta modalidad (0066).
  ///
  /// ⚠️ **Es lo que decide QUÉ PREGUNTA ve quien captura**, y sale del catálogo —no de una
  /// lista de códigos en la pantalla—: con [CapturaDelHorario.horaDeCambio] se pide **una
  /// sola hora** y la rejilla no aparece; con las dos formas semanales se pide la rejilla y
  /// la hora no aparece.
  final CapturaDelHorario capturaDelHorario;

  /// Cuánto dura un turno de esta modalidad, en minutos. `720` son 12 h y `1440` son 24 h.
  ///
  /// Existe **si y sólo si** el horario se captura por hora de cambio: con él y esa hora se
  /// derivan las horas que se enseñan, y sin él no se podría decir «08:00 a 20:00».
  final int? minutosDelTurno;

  /// ¿Se pide una sola hora en lugar de la rejilla semanal?
  bool get pideHoraDeCambio => capturaDelHorario == CapturaDelHorario.horaDeCambio;

  /// ¿La rejilla nace con lunes a viernes puesto?
  bool get rejillaPrecargada =>
      capturaDelHorario == CapturaDelHorario.semanalPrecargada;

  /// Las horas del turno, derivadas de la hora de cambio: `08:00 a 20:00`.
  ///
  /// 🚫 **Derivado y nunca capturado dos veces.** Con un periodo nocturno la plaza empieza
  /// cuando acaba la diurna, así que la misma hora de cambio describe las dos.
  String? ventanaDelTurno(int? horaDeCambioMinuto, {bool nocturno = false}) {
    if (!pideHoraDeCambio) return null;
    if (horaDeCambioMinuto == null || minutosDelTurno == null) return null;

    final duracion = minutosDelTurno!;
    final entrada = nocturno
        ? (horaDeCambioMinuto + duracion) % 1440
        : horaDeCambioMinuto;

    final salida = (entrada + duracion) % 1440;

    return '${BloqueHorario.reloj(entrada)} a ${BloqueHorario.reloj(salida)}'
        '${duracion >= 1440 ? ' del día siguiente' : ''}';
  }

  /// `24 h` o `12 h 30 min`: cuánto dura un turno de esta modalidad.
  String? get duracionDelTurnoEnPantalla {
    if (minutosDelTurno case final m?) {
      final horas = m ~/ 60;
      final minutos = m % 60;

      return minutos == 0 ? '$horas h' : '$horas h $minutos min';
    }

    return null;
  }

  /// Lo que se LEE del horario de una condición con esta modalidad:
  /// `Cambio de turno 08:00 · turnos de 24 h (08:00 a 08:00 del día siguiente)`.
  ///
  /// 🚫 **Existe porque la tarjeta decía «Sin horario semanal fijo» en un 24×24**, y era
  /// falso de la peor manera: un turno rotativo **sí** tiene horario —entra a una hora y dura
  /// lo que dura—, lo que no tiene es **rejilla semanal**, porque su ciclo no es periódico en
  /// siete días. Lo encontró el dueño en su prueba en pantalla del 19-nov-2026.
  ///
  /// Devuelve nulo cuando esta modalidad no se captura por hora de cambio, o cuando la
  /// condición no trae hora: entonces no hay nada derivado que decir y quien lee la tarjeta
  /// ve la frase de la rejilla vacía, que ahí **sí** es cierta.
  String? horarioDerivado(int? horaDeCambioMinuto, {bool nocturno = false}) {
    final ventana = ventanaDelTurno(horaDeCambioMinuto, nocturno: nocturno);

    if (ventana == null || horaDeCambioMinuto == null) return null;

    final duracion = duracionDelTurnoEnPantalla;

    return 'Cambio de turno ${BloqueHorario.reloj(horaDeCambioMinuto)}'
        '${duracion == null ? '' : ' · turnos de $duracion'}'
        ' ($ventana)';
  }

  // 🚫 AQUÍ VIVÍA `personasSugeridas`, Y EL DUEÑO LO QUITÓ el 14 de noviembre de 2026, el
  // mismo día que lo pidió. Prellenaba **la cantidad que se cobra** al elegir el turno, y ese
  // campo es **dinero** —el importe mensual es cantidad × precio—: las personas que un rol
  // necesita son una referencia de operación, no la cantidad facturada.
  //
  // Ahora el número vive **sólo dentro de [explicacion]**, que la empresa puede corregir, y
  // se lee junto al turno. Un campo aparte lo habría puesto en dos sitios —uno editable y
  // otro no— y la pantalla se contradiría sola.

  /// `activa` o `inactiva`. Una modalidad **retirada** no se elige para una condición nueva,
  /// pero las condiciones que ya la usan **la conservan**: son dos preguntas distintas.
  final String estatus;

  bool get estaActiva => estatus == 'activa';
}

/// Cómo se captura el horario de una condición. **Lista cerrada de tres** (0066), y su
/// `switch` va sin comodín.
///
/// 🚫 **POR QUÉ UN TURNO ROTATIVO NO LLEVA REJILLA SEMANAL, y no es una preferencia de
/// pantalla:** el ciclo de un 24×24 vuelve a la misma hora cada **48** horas y el de un
/// 12×24 cada 36, así que **no caben en una semana**. Lo que sí se puede capturar es **una
/// hora**: cuándo entra el turno diurno. Lo demás se deriva con la duración del turno.
enum CapturaDelHorario {
  /// Una sola hora —la entrada del turno diurno— y **ningún** bloque semanal.
  horaDeCambio('hora_de_cambio'),

  /// Rejilla de siete días que **nace con lunes a viernes puesto**, y es editable.
  semanalPrecargada('semanal_precargada'),

  /// Rejilla de siete días en blanco.
  semanalVacia('semanal_vacia');

  const CapturaDelHorario(this.codigo);

  final String codigo;

  /// Un código desconocido —o ausente— se lee como [semanalVacia], que es la forma que **no
  /// asume nada**: pide la rejilla en blanco y no inventa ninguna hora.
  static CapturaDelHorario deCodigo(String? codigo) {
    for (final c in values) {
      if (c.codigo == codigo) return c;
    }

    return semanalVacia;
  }
}

/// Qué se cobra en una línea comercial. **Lista cerrada de dos** (0066).
///
/// Decisión del dueño del 18 de noviembre de 2026: una línea puede no ser de personal. El
/// material y el equipo se cobran **sin puesto, sin turno y sin horario**.
enum TipoDeLinea {
  personal('personal', 'Personal'),
  concepto('concepto', 'Concepto');

  const TipoDeLinea(this.codigo, this.nombre);

  final String codigo;
  final String nombre;

  bool get esPersonal => this == TipoDeLinea.personal;

  /// Ausente o desconocido se lee como [personal], que es lo que toda línea era antes de la
  /// 0066.
  static TipoDeLinea deCodigo(String? codigo) {
    for (final t in values) {
      if (t.codigo == codigo) return t;
    }

    return personal;
  }
}

/// Cómo se cotizó una línea. **Lista cerrada de dos** (0066).
///
/// 🚫 **El total NO se guarda como unitario dividido:** $100 000 entre 3 personas no es
/// representable en centavos, así que guardar el unitario redondeado **cambiaría lo que se
/// cobra**.
enum ModoDeCotizacion {
  /// Importe mensual = cantidad × precio por persona.
  porPersona('por_persona', 'Por persona × cantidad'),

  /// Importe mensual = el total capturado. La cantidad **no multiplica**.
  totalMensual('total_mensual', 'Precio total mensual');

  const ModoDeCotizacion(this.codigo, this.nombre);

  final String codigo;
  final String nombre;

  bool get esPorPersona => this == ModoDeCotizacion.porPersona;

  static ModoDeCotizacion deCodigo(String? codigo) {
    for (final m in values) {
      if (m.codigo == codigo) return m;
    }

    return porPersona;
  }
}

/// El periodo del día de un turno. **Lista cerrada de dos**, y sólo aparece cuando la
/// modalidad lo pide.
///
/// 🚫 **No se convierte en horas.** «Nocturno» no significa 20:00–08:00; quien quiera esas
/// horas las captura como bloque horario. Esto es lo que distingue dos plazas de la misma
/// modalidad que **se cobran distinto**.
enum PeriodoDeTurno {
  diurno('diurno', 'Diurno'),
  nocturno('nocturno', 'Nocturno');

  const PeriodoDeTurno(this.codigo, this.nombre);

  final String codigo;
  final String nombre;

  static PeriodoDeTurno? deCodigo(String? codigo) {
    if (codigo == null) return null;

    for (final p in values) {
      if (p.codigo == codigo) return p;
    }

    return null;
  }
}

/// Cómo se cobra el IVA de una línea.
///
/// ⚠️ **`noAplica` existe porque NO TODOS LOS SERVICIOS SE FACTURAN**, y eso lo dijo el
/// dueño: hay servicios que se cobran sin documento fiscal. Tratar el IVA como obligatorio
/// obligaría a elegir una respuesta falsa.
enum TratamientoDeIva {
  masIva('mas_iva', 'Más IVA'),
  ivaIncluido('iva_incluido', 'IVA incluido'),
  noAplica('no_aplica', 'No aplica');

  const TratamientoDeIva(this.codigo, this.nombre);

  final String codigo;
  final String nombre;

  static TratamientoDeIva? deCodigo(String? codigo) {
    if (codigo == null) return null;

    for (final t in values) {
      if (t.codigo == codigo) return t;
    }

    return null;
  }
}

/// Dónde cae una vigencia respecto de hoy. **La deriva el servidor**, no la pantalla.
///
/// ⚠️ El servidor usa **el día del negocio** —el de México— y el navegador tiene otro reloj
/// y otra zona. Derivarla aquí haría que a las 18:00 una condición que empieza mañana se
/// pintara como vigente, y eso es dinero.
enum TemporalidadDeCondicion {
  /// Ya terminó. **No se corrige nunca.**
  historica('historical', 'Histórica'),

  /// La que está cobrando hoy.
  vigente('current', 'Vigente'),

  /// Programada: todavía no empieza. Se corrige y se cancela.
  futura('future', 'Programada');

  const TemporalidadDeCondicion(this.codigo, this.nombre);

  final String codigo;
  final String nombre;

  static TemporalidadDeCondicion? deCodigo(String? codigo) {
    if (codigo == null) return null;

    for (final t in values) {
      if (t.codigo == codigo) return t;
    }

    return null;
  }
}

/// El estatus de una línea comercial.
///
/// ⚠️ **`retirada` NO significa «dejó de cobrar».** Retirar una línea impide abrirle
/// condiciones nuevas y **deja su condición abierta**, así que para la facturación sigue
/// valiendo dinero. Lo que deja de cobrar es **cerrar la condición vigente**, que es otra
/// acción con su propia fecha y su propio motivo.
enum EstatusDeLinea {
  activa('active', 'Activa'),
  retirada('retired', 'Retirada');

  const EstatusDeLinea(this.codigo, this.nombre);

  final String codigo;
  final String nombre;

  static EstatusDeLinea? deCodigo(String? codigo) {
    if (codigo == null) return null;

    for (final e in values) {
      if (e.codigo == codigo) return e;
    }

    return null;
  }
}

/// La identidad estable de una línea comercial dentro del servicio.
class LineaComercial {
  const LineaComercial({
    required this.id,
    required this.servicioId,
    required this.nombre,
    required this.tipo,
    required this.estatus,
    required this.actualizadoEn,
  });

  factory LineaComercial.deJson(Map<String, dynamic> json) => LineaComercial(
    id: json['id'] as String,
    servicioId: json['serviceId'] as String,
    nombre: json['name'] as String,
    tipo: TipoDeLinea.deCodigo(json['kind'] as String?),
    estatus: json['status'] as String,
    actualizadoEn: DateTime.parse(json['updatedAt'] as String),
  );

  final String id;
  final String servicioId;
  final String nombre;

  /// Personal o concepto. **No cambia en la vida de la línea**: el servidor lo ata con una
  /// clave compuesta, así que una condición no puede contradecir a su línea.
  final TipoDeLinea tipo;

  final String estatus;
  final DateTime actualizadoEn;

  EstatusDeLinea? get estado => EstatusDeLinea.deCodigo(estatus);

  bool get estaActiva => estatus == EstatusDeLinea.activa.codigo;
}

/// Lo que devuelve el alta: **la línea y su primera condición**, creadas juntas.
///
/// ⚠️ **[condicion] puede ser nula** —una línea creada sin ella— y la pantalla tiene que
/// distinguir eso de «todavía no cargó»: fue justo el defecto que el dueño encontró
/// probando, una tarjeta diciendo «Leyendo sus condiciones…» para siempre.
class LineaCreada {
  const LineaCreada({required this.linea, required this.condicion});

  factory LineaCreada.deJson(Map<String, dynamic> json) => LineaCreada(
    linea: LineaComercial.deJson(json['line'] as Map<String, dynamic>),
    condicion: json['term'] == null
        ? null
        : CondicionComercial.deJson(json['term'] as Map<String, dynamic>),
  );

  final LineaComercial linea;
  final CondicionComercial? condicion;
}

/// Una línea **retirada** y la condición que se cerró con ella, en la misma transacción
/// (19-nov-2026).
///
/// 🚫 **LAS DOS VIAJAN JUNTAS A PROPÓSITO:** la tarjeta tiene que poder decir «cobra hasta
/// el …» sin volver a preguntar, y lo que acaba de cambiar son las dos. [condicionCerrada] es
/// nula cuando la línea **no cobraba nada**, que es un caso legítimo.
class LineaRetirada {
  const LineaRetirada({required this.linea, required this.condicionCerrada});

  factory LineaRetirada.deJson(Map<String, dynamic> json) => LineaRetirada(
    linea: LineaComercial.deJson(json['line'] as Map<String, dynamic>),
    condicionCerrada: json['closedTerm'] == null
        ? null
        : CondicionComercial.deJson(json['closedTerm'] as Map<String, dynamic>),
  );

  final LineaComercial linea;
  final CondicionComercial? condicionCerrada;
}

/// Un bloque horario de un día de la semana.
///
/// `dia` en ISO: **1 = lunes … 7 = domingo**. La duración y el cruce de medianoche **los
/// deriva el servidor** y viajan calculados: si cada cliente los derivara por su cuenta,
/// tarde o temprano uno leería `08:00 → 08:00` como cero minutos en lugar de 24 horas.
///
/// Un **día de descanso es la AUSENCIA de bloque**, no un bloque de cero minutos.
class BloqueHorario {
  const BloqueHorario({
    required this.id,
    required this.dia,
    required this.inicioMinuto,
    required this.finMinuto,
    required this.duracionMinutos,
    required this.cruzaMedianoche,
  });

  factory BloqueHorario.deJson(Map<String, dynamic> json) => BloqueHorario(
    id: json['id'] as String,
    dia: json['dayOfWeek'] as int,
    inicioMinuto: json['startMinute'] as int,
    finMinuto: json['endMinute'] as int,
    duracionMinutos: json['durationMinutes'] as int,
    cruzaMedianoche: json['spansNextDay'] as bool? ?? false,
  );

  final String id;
  final int dia;

  /// `0..1439`.
  final int inicioMinuto;

  /// `1..1440`. **1440 es la medianoche como FINAL del día**; no existen valores mayores.
  final int finMinuto;

  final int duracionMinutos;
  final bool cruzaMedianoche;

  /// El nombre del día, para la pantalla.
  String get nombreDelDia => switch (dia) {
    1 => 'Lunes',
    2 => 'Martes',
    3 => 'Miércoles',
    4 => 'Jueves',
    5 => 'Viernes',
    6 => 'Sábado',
    7 => 'Domingo',
    // Un día fuera de 1..7 no lo puede producir el servidor —hay un `CHECK`—, así que esto
    // es la rama imposible. Se enseña el número en lugar de reventar la pantalla: un
    // expediente que no abre es peor que un día raro en una celda.
    _ => 'Día $dia',
  };

  /// `08:00` a partir del minuto.
  static String reloj(int minuto) {
    final horas = (minuto ~/ 60).toString().padLeft(2, '0');
    final minutos = (minuto % 60).toString().padLeft(2, '0');

    return '$horas:$minutos';
  }

  /// `08:00 → 20:00`, y con el cruce dicho: `20:00 → 08:00 (+1)`.
  String get enPantalla =>
      '${reloj(inicioMinuto)} → ${reloj(finMinuto)}${cruzaMedianoche ? ' (+1)' : ''}';

  /// `12 h` o `12 h 30 min`.
  String get duracionEnPantalla {
    final horas = duracionMinutos ~/ 60;
    final minutos = duracionMinutos % 60;

    if (minutos == 0) return '$horas h';

    return '$horas h $minutos min';
  }
}

/// El aviso de **cupo rebasado**: hay más gente asignada que plazas declaradas.
///
/// 🚫 **NO ES UN ERROR, y la pantalla no lo pinta como tal.** La condición **se guardó**. Es
/// un aviso porque **el servidor no saca a nadie de su puesto** por un cambio comercial:
/// quien decide a quién mover es una persona.
class AvisoDeCupo {
  const AvisoDeCupo({required this.asignadas, required this.plazas});

  static const String codigo = 'cupo_rebasado';

  /// Devuelve `null` cuando no hay aviso, que es el caso normal.
  static AvisoDeCupo? deJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    if (json['code'] != codigo) return null;

    return AvisoDeCupo(
      asignadas: json['assigned'] as int,
      plazas: json['headcount'] as int,
    );
  }

  /// Cuántas **personas distintas** están asignadas hoy a la línea.
  final int asignadas;

  /// Cuántas plazas declara la condición.
  final int plazas;

  String get enPantalla =>
      'Hay $asignadas ${asignadas == 1 ? 'persona' : 'personas'} asignada'
      '${asignadas == 1 ? '' : 's'} y la condición declara $plazas '
      '${plazas == 1 ? 'plaza' : 'plazas'}. No se movió a nadie.';
}

/// Una condición comercial: lo que se le cobra al cliente durante una vigencia.
class CondicionComercial {
  const CondicionComercial({
    required this.id,
    required this.lineaId,
    required this.temporalidad,
    required this.inicio,
    required this.termino,
    required this.tipo,
    required this.puestoId,
    required this.modalidadId,
    required this.periodo,
    required this.horaDeCambioMinuto,
    required this.plazas,
    required this.modo,
    required this.precioUnitarioMenores,
    required this.totalMensualMenores,
    required this.importeMensualMenores,
    required this.moneda,
    required this.iva,
    required this.descripcion,
    required this.observaciones,
    required this.version,
    required this.horarios,
    required this.actualizadoEn,
    this.continuaALaCondicionId,
    this.aviso,
  });

  factory CondicionComercial.deJson(Map<String, dynamic> json) => CondicionComercial(
    id: json['id'] as String,
    lineaId: json['commercialLineId'] as String,
    temporalidad: json['temporality'] as String,
    inicio: DiaDeNegocio.deTexto(json['startsOn'] as String?),
    termino: DiaDeNegocio.deTexto(json['endsOn'] as String?),
    tipo: TipoDeLinea.deCodigo(json['kind'] as String?),
    puestoId: json['positionId'] as String?,
    modalidadId: json['shiftModalityId'] as String?,
    periodo: json['shiftPeriod'] as String?,
    horaDeCambioMinuto: json['shiftChangeMinute'] as int?,
    plazas: json['headcount'] as int,
    modo: ModoDeCotizacion.deCodigo(json['pricingMode'] as String?),
    precioUnitarioMenores: json['unitPriceMinor'] as int?,
    totalMensualMenores: json['monthlyTotalMinor'] as int?,
    // ⚠️ **EL IMPORTE LO DERIVA EL SERVIDOR** y la pantalla no lo recalcula: con dos modos
    // de cotización, dejar que cada cliente multiplique garantiza que algún día uno
    // multiplique el total.
    importeMensualMenores: json['monthlyAmountMinor'] as int? ?? 0,
    moneda: json['currency'] as String,
    iva: json['taxTreatment'] as String,
    descripcion: json['description'] as String?,
    observaciones: json['observations'] as String?,
    version: json['version'] as int,
    horarios: [
      for (final h in (json['schedules'] as List? ?? const []))
        BloqueHorario.deJson(h as Map<String, dynamic>),
    ],
    actualizadoEn: DateTime.parse(json['updatedAt'] as String),
    // AUSENTE SE LEE COMO NULO: el campo es aditivo, y sin él la pantalla se comporta
    // como antes de D-84 —no pregunta— en lugar de no pintar nada.
    continuaALaCondicionId: json['closedTermId'] as String?,
    aviso: AvisoDeCupo.deJson(json['warning'] as Map<String, dynamic>?),
  );

  final String id;
  final String lineaId;

  /// El código tal como lo manda el servidor. [estado] lo traduce.
  final String temporalidad;

  /// **Inclusivo por los dos extremos**: `termino` es el último día que cobra, igual que en
  /// un periodo laboral. Encadenar es `anterior.termino = siguiente.inicio - 1 día`.
  ///
  /// Son [DiaDeNegocio] y no `DateTime` a propósito, igual que las del servicio: un
  /// `DateTime` arrastra hora y zona, y una fecha de vigencia **no tiene ninguna de las
  /// dos**. Mezclarlas es cómo una condición que empieza mañana se pinta vigente a las
  /// 18:00.
  final DiaDeNegocio? inicio;
  final DiaDeNegocio? termino;

  /// Personal o concepto, copiado de su línea.
  final TipoDeLinea tipo;

  /// Nulo en una línea **de concepto**: el material no ocupa una plaza.
  final String? puestoId;

  /// Obligatoria en una línea de personal desde la 0066; nula en un concepto.
  final String? modalidadId;

  /// `diurno` o `nocturno`, y **sólo** cuando la modalidad lo pide.
  final String? periodo;

  /// El minuto del día en que **entra el turno diurno**, cuando la modalidad se captura así.
  ///
  /// De aquí y de la duración del turno salen las horas que se enseñan: **derivadas, nunca
  /// capturadas dos veces**.
  final int? horaDeCambioMinuto;

  /// La **cantidad que se cobra**: puestos o elementos, según cómo se cotizó.
  ///
  /// ⚠️ Multiplica el precio **sólo** cuando el modo es por persona. Con un total mensual
  /// sigue siendo un dato de la condición —la operación necesita saber cuántos— pero **no
  /// multiplica**.
  final int plazas;

  /// Cómo se cotizó: por persona o con un total mensual.
  final ModoDeCotizacion modo;

  /// En unidades **menores** —centavos—. Nulo cuando se cotizó con un total mensual.
  final int? precioUnitarioMenores;

  /// El total mensual pactado, en centavos. Nulo cuando se cotizó por persona.
  final int? totalMensualMenores;

  /// Lo que esta condición cobra al mes, en centavos. **Lo deriva el servidor.**
  final int importeMensualMenores;

  final String moneda;
  final String iva;
  final String? descripcion;

  /// El segundo texto libre de la condición, que RISEG ONE siempre tuvo y aquí faltaba.
  final String? observaciones;

  /// El contador del candado: se manda al corregir para que el servidor pueda negarse si
  /// alguien más guardó mientras tanto.
  ///
  /// ⚠️ **No se inventa.** Es el que se leyó al abrir el formulario; un valor «cualquiera
  /// para que pase» borraría el trabajo del otro, que es exactamente lo que el contador
  /// existe para impedir.
  final int version;

  final List<BloqueHorario> horarios;
  final DateTime actualizadoEn;

  /// La condición a la que **ésta continúa** —empieza el día siguiente a su último día de
  /// cobro—, o nulo si no continúa a ninguna.
  ///
  /// 🚫 **DECIDE SI CANCELARLA PREGUNTA ALGO** (D-84): si la línea queda continua, cancelar
  /// la deja **parando** en esa fecha, así que el diálogo ofrece las **tres salidas**. Si es
  /// nulo, ya había un hueco que esta programación no creó y **no hay nada que decidir**.
  ///
  /// ⚠️ **Lo manda el servidor y la pantalla NO lo deduce de las fechas**, aunque podría: la
  /// regla vive en un solo sitio, y dos sitios que la calculen acabarán discrepando. El
  /// servidor la exige igual con 400 y 422.
  final String? continuaALaCondicionId;

  /// Si cancelar esta condición programada **tiene que preguntar** qué pasa con la vigente.
  bool get continuaALaVigente => continuaALaCondicionId != null;

  /// El aviso que vino con la respuesta, si lo hubo. **Sólo llega en una mutación**: una
  /// lectura nunca lo trae.
  final AvisoDeCupo? aviso;

  TemporalidadDeCondicion? get estado => TemporalidadDeCondicion.deCodigo(temporalidad);

  PeriodoDeTurno? get periodoDelTurno => PeriodoDeTurno.deCodigo(periodo);

  TratamientoDeIva? get tratamientoDeIva => TratamientoDeIva.deCodigo(iva);

  /// El importe de la línea al mes, **tal como lo mandó el servidor**.
  ///
  /// ⚠️ **SIN IVA, y eso es deliberado.** El servidor suma los importes sin impuesto en los
  /// indicadores, y calcularlo aquí con IVA daría dos cifras distintas en dos pantallas sin
  /// que nada fallara. El impuesto es de Facturación.
  ///
  /// 🚫 **Y YA NO SE MULTIPLICA AQUÍ** (0066): era `precio × plazas`, y con un total mensual
  /// eso habría multiplicado el total por la cantidad de personas. Lo deriva el servidor, en
  /// un solo sitio, y la pantalla lo enseña.
  int get importeMenores => importeMensualMenores;

  /// El precio **en la forma en que esta condición se cotizó**: el unitario si se cobra por
  /// persona, y el total mensual si se pactó un total.
  ///
  /// ⚠️ **Es el que se enseña y el que se edita al renovar**, porque es el que se negoció. Y
  /// el servidor garantiza que uno de los dos está —la 0066 lo impone con una restricción—,
  /// así que el cero del final es para el compilador y no un caso real.
  int get precioQueSeEdita =>
      modo.esPorPersona ? (precioUnitarioMenores ?? 0) : (totalMensualMenores ?? 0);
}

/// El sueldo de referencia **para ofrecer el puesto** de una línea, con su vigencia.
///
/// 🚫 **No es el sueldo de nadie.** Lo dice su nombre en pantalla y vale repetirlo aquí: es
/// lo que se ofrece al reclutar, y el sueldo real de cada persona vive en su asignación.
class SueldoDeReferencia {
  const SueldoDeReferencia({
    required this.id,
    required this.lineaId,
    required this.temporalidad,
    required this.inicio,
    required this.termino,
    required this.sueldoMenores,
    required this.bonoMenores,
    required this.moneda,
    required this.actualizadoEn,
  });

  factory SueldoDeReferencia.deJson(Map<String, dynamic> json) => SueldoDeReferencia(
    id: json['id'] as String,
    lineaId: json['commercialLineId'] as String,
    temporalidad: json['temporality'] as String,
    inicio: DiaDeNegocio.deTexto(json['startsOn'] as String?),
    termino: DiaDeNegocio.deTexto(json['endsOn'] as String?),
    sueldoMenores: json['salaryMinor'] as int,
    bonoMenores: json['bonusMinor'] as int?,
    moneda: json['currency'] as String,
    actualizadoEn: DateTime.parse(json['updatedAt'] as String),
  );

  final String id;
  final String lineaId;
  final String temporalidad;

  /// Mismo criterio que en la condición: [DiaDeNegocio], no `DateTime`. Y `termino` es
  /// **inclusivo**.
  final DiaDeNegocio? inicio;
  final DiaDeNegocio? termino;

  /// En unidades menores. **Siempre mayor que cero**: una referencia de cero pesos no es una
  /// referencia, es no tener ninguna, y eso se dice **no guardando la fila**.
  final int sueldoMenores;

  /// El bono **sí admite cero** —«este puesto no lleva bono» es una respuesta— y puede ser
  /// nulo, que es «no se capturó».
  final int? bonoMenores;

  final String moneda;
  final DateTime actualizadoEn;

  TemporalidadDeCondicion? get estado => TemporalidadDeCondicion.deCodigo(temporalidad);
}
