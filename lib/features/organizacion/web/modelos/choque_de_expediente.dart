/// Qué hacer cuando dos personas guardaron el mismo expediente.
///
/// ## Por qué hacen falta TRES versiones y no dos
///
/// Con sólo «lo mío» y «lo del servidor» no se puede distinguir un choque real de un
/// campo que yo nunca toqué. Si la otra persona cambió el teléfono y yo no, mostrarlo
/// como conflicto obligaría a decidir sobre algo que no decidí — y con quince campos,
/// a decidir quince veces.
///
/// La tercera versión es **la base**: lo que el formulario cargó al abrirse. Con ella:
///
///  · lo que **sólo yo** cambié → se queda lo mío, sin preguntar;
///  · lo que **sólo la otra persona** cambió → se toma lo suyo, sin preguntar;
///  · lo que **cambiamos los dos a cosas distintas** → **eso es el choque**, y es lo
///    único que se pregunta.
///
/// Así el aviso enseña dos campos en vez de quince, y los dos que enseña son
/// decisiones de verdad.
///
/// ## Lo que esta clase NO hace
///
/// No decide nada por su cuenta ni guarda: calcula. Quien elige es la persona, y quien
/// guarda es la pantalla con la versión nueva que el 409 trajo.
library;

/// En qué situación quedó un campo al comparar las tres versiones.
enum EstadoDelCampo {
  /// Nadie lo tocó.
  igual,

  /// Sólo yo. **Se conserva lo mío sin preguntar.**
  soloMio,

  /// Sólo la otra persona. **Se toma lo suyo sin preguntar**, porque yo no expresé
  /// ninguna intención sobre este campo.
  soloSuyo,

  /// Los dos, **a lo mismo**. No es un choque: el resultado es el que los dos
  /// queríamos.
  losDosIgual,

  /// Los dos, **a cosas distintas**. Esto es el choque, y es lo único que se pregunta.
  choque,
}

/// Un campo comparado entre las tres versiones.
class CampoComparado {
  const CampoComparado({
    required this.campo,
    required this.etiqueta,
    required this.base,
    required this.mio,
    required this.suyo,
    this.comoSeLee,
  });

  /// El nombre técnico, el mismo que usa el servidor para señalar errores.
  final String campo;

  /// Cómo se llama en pantalla. **No se deriva del nombre técnico**: `legalName` no se
  /// le muestra a nadie.
  final String etiqueta;

  /// Lo que había al abrir el formulario.
  final String? base;

  /// Lo que hay en el formulario ahora.
  final String? mio;

  /// Lo que el servidor tiene ahora, del cuerpo del 409.
  final String? suyo;

  /// Cómo se **lee** un valor en pantalla, cuando no es el valor mismo.
  ///
  /// **SE COMPARA UNA COSA Y SE MUESTRA OTRA, y hace falta.** El tipo de sucursal se
  /// compara por su id —dos tipos pueden llamarse igual, y el id es lo que se guarda—
  /// pero un UUID en el aviso no le dice nada a nadie. Y el horario se compara por su
  /// contenido entero y se lee como «Lunes 09:00 – 18:00».
  ///
  /// Nulo cuando el valor ya se lee solo, que es lo normal.
  final String Function(String? valor)? comoSeLee;

  /// El valor tal como se enseña. **Pasa por [comoSeLee] si lo hay**, y el nulo llega
  /// ahí sin convertir: «sin tipo» no es lo mismo que «(vacío)», y quien sabe
  /// traducirlo es quien puso la función.
  String? leer(String? valor) =>
      comoSeLee == null ? valor : comoSeLee!(valor);

  /// **LA TABLA ENTERA, EN UN SOLO SITIO.** Repartirla en condiciones por pantalla es
  /// cómo dos formularios acaban resolviendo el mismo choque de dos maneras.
  EstadoDelCampo get estado {
    final cambieYo = !_igual(mio, base);
    final cambioElOtro = !_igual(suyo, base);

    if (!cambieYo && !cambioElOtro) return EstadoDelCampo.igual;
    if (cambieYo && !cambioElOtro) return EstadoDelCampo.soloMio;
    if (!cambieYo && cambioElOtro) return EstadoDelCampo.soloSuyo;

    return _igual(mio, suyo)
        ? EstadoDelCampo.losDosIgual
        : EstadoDelCampo.choque;
  }

  /// ¿Hay que preguntar por este campo?
  bool get esChoque => estado == EstadoDelCampo.choque;

  /// Con qué valor se queda si nadie elige nada.
  ///
  /// **Para un choque devuelve LO MÍO**, y es deliberado: si la persona cierra el aviso
  /// sin decidir, lo que escribió sigue en el formulario. Perder su trabajo por no
  /// contestar sería exactamente lo que este aviso viene a evitar.
  String? get porOmision => switch (estado) {
    EstadoDelCampo.igual => base,
    EstadoDelCampo.soloMio => mio,
    EstadoDelCampo.soloSuyo => suyo,
    EstadoDelCampo.losDosIgual => mio,
    EstadoDelCampo.choque => mio,
  };

  /// **Vacío y nulo son lo mismo al comparar.** Un campo que el servidor manda nulo y
  /// uno que el formulario tiene en blanco representan la misma ausencia, y tratarlos
  /// como distintos inventaría un choque en cada campo opcional sin llenar.
  static bool _igual(String? a, String? b) =>
      (a ?? '').trim() == (b ?? '').trim();
}

/// El resultado de comparar un expediente completo.
class ChoqueDeExpediente {
  const ChoqueDeExpediente(this.campos);

  final List<CampoComparado> campos;

  /// Sólo los que hay que preguntar.
  List<CampoComparado> get choques =>
      [for (final c in campos) if (c.esChoque) c];

  /// Lo que la otra persona cambió y yo no. **Se informa, no se pregunta**: la persona
  /// merece saber qué entró de fuera, aunque no tenga que decidirlo.
  List<CampoComparado> get suyosSinChoque =>
      [for (final c in campos) if (c.estado == EstadoDelCampo.soloSuyo) c];

  bool get hayChoque => choques.isNotEmpty;

  /// ¿Se puede reintentar sin preguntar nada?
  ///
  /// **Es el caso frecuente de verdad**: dos personas editando secciones distintas del
  /// mismo expediente. Sin esto, el aviso saldría igual y las dos tendrían que
  /// confirmar algo que no chocaba.
  bool get seResuelveSolo => !hayChoque;

  /// ¿Se queda la versión de la otra persona en este campo?
  ///
  /// **Es la misma tabla que [CampoComparado.porOmision], dicha como decisión y no
  /// como valor**, y hace falta para lo que no es texto: el horario es una lista de
  /// tramos, así que [resolver] sólo puede devolver su resumen legible y la pantalla
  /// necesita saber **a quién hacer caso** para quedarse con los objetos de verdad.
  ///
  /// Un campo que no está en la comparación devuelve `false` —se queda lo mío—,
  /// porque es lo que no pierde el trabajo de nadie.
  bool seQuedaLoSuyo(String campo, Map<String, bool> elegidos) {
    if (elegidos.containsKey(campo)) return elegidos[campo]!;

    for (final c in campos) {
      if (c.campo == campo) return c.estado == EstadoDelCampo.soloSuyo;
    }

    return false;
  }

  /// El expediente resultante de aplicar lo de arriba, con las elecciones que la
  /// persona haya hecho.
  ///
  /// `elegidos` lleva, por campo, `true` si se queda lo suyo y `false` si lo mío. Un
  /// campo que no esté en el mapa usa [CampoComparado.porOmision].
  Map<String, String?> resolver(Map<String, bool> elegidos) => {
    for (final c in campos)
      c.campo: elegidos.containsKey(c.campo)
          ? (elegidos[c.campo]! ? c.suyo : c.mio)
          : c.porOmision,
  };
}
