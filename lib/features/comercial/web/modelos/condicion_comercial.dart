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
    required this.estatus,
  });

  factory ModalidadDeTurno.deJson(Map<String, dynamic> json) => ModalidadDeTurno(
    id: json['id'] as String,
    codigo: json['code'] as String,
    nombre: json['name'] as String,
    explicacion: json['description'] as String?,
    pidePeriodo: json['requiresPeriod'] as bool? ?? false,
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

  /// `activa` o `inactiva`. Una modalidad **retirada** no se elige para una condición nueva,
  /// pero las condiciones que ya la usan **la conservan**: son dos preguntas distintas.
  final String estatus;

  bool get estaActiva => estatus == 'activa';
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
    required this.estatus,
    required this.actualizadoEn,
  });

  factory LineaComercial.deJson(Map<String, dynamic> json) => LineaComercial(
    id: json['id'] as String,
    servicioId: json['serviceId'] as String,
    nombre: json['name'] as String,
    estatus: json['status'] as String,
    actualizadoEn: DateTime.parse(json['updatedAt'] as String),
  );

  final String id;
  final String servicioId;
  final String nombre;
  final String estatus;
  final DateTime actualizadoEn;

  EstatusDeLinea? get estado => EstatusDeLinea.deCodigo(estatus);

  bool get estaActiva => estatus == EstatusDeLinea.activa.codigo;
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
    required this.puestoId,
    required this.modalidadId,
    required this.periodo,
    required this.plazas,
    required this.precioUnitarioMenores,
    required this.moneda,
    required this.iva,
    required this.descripcion,
    required this.version,
    required this.horarios,
    required this.actualizadoEn,
    this.aviso,
  });

  factory CondicionComercial.deJson(Map<String, dynamic> json) => CondicionComercial(
    id: json['id'] as String,
    lineaId: json['commercialLineId'] as String,
    temporalidad: json['temporality'] as String,
    inicio: DiaDeNegocio.deTexto(json['startsOn'] as String?),
    termino: DiaDeNegocio.deTexto(json['endsOn'] as String?),
    puestoId: json['positionId'] as String,
    modalidadId: json['shiftModalityId'] as String?,
    periodo: json['shiftPeriod'] as String?,
    plazas: json['headcount'] as int,
    precioUnitarioMenores: json['unitPriceMinor'] as int,
    moneda: json['currency'] as String,
    iva: json['taxTreatment'] as String,
    descripcion: json['description'] as String?,
    version: json['version'] as int,
    horarios: [
      for (final h in (json['schedules'] as List? ?? const []))
        BloqueHorario.deJson(h as Map<String, dynamic>),
    ],
    actualizadoEn: DateTime.parse(json['updatedAt'] as String),
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

  final String puestoId;
  final String? modalidadId;

  /// `diurno` o `nocturno`, y **sólo** cuando la modalidad lo pide.
  final String? periodo;

  final int plazas;

  /// En unidades **menores** —centavos—, como todo el dinero del producto.
  final int precioUnitarioMenores;

  final String moneda;
  final String iva;
  final String? descripcion;

  /// El contador del candado: se manda al corregir para que el servidor pueda negarse si
  /// alguien más guardó mientras tanto.
  ///
  /// ⚠️ **No se inventa.** Es el que se leyó al abrir el formulario; un valor «cualquiera
  /// para que pase» borraría el trabajo del otro, que es exactamente lo que el contador
  /// existe para impedir.
  final int version;

  final List<BloqueHorario> horarios;
  final DateTime actualizadoEn;

  /// El aviso que vino con la respuesta, si lo hubo. **Sólo llega en una mutación**: una
  /// lectura nunca lo trae.
  final AvisoDeCupo? aviso;

  TemporalidadDeCondicion? get estado => TemporalidadDeCondicion.deCodigo(temporalidad);

  PeriodoDeTurno? get periodoDelTurno => PeriodoDeTurno.deCodigo(periodo);

  TratamientoDeIva? get tratamientoDeIva => TratamientoDeIva.deCodigo(iva);

  /// El importe de la línea: precio por plazas.
  ///
  /// ⚠️ **SIN IVA, y eso es deliberado.** El servidor suma los importes sin impuesto en los
  /// indicadores, y calcularlo aquí con IVA daría dos cifras distintas en dos pantallas sin
  /// que nada fallara. El impuesto es de Facturación.
  int get importeMenores => precioUnitarioMenores * plazas;
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
