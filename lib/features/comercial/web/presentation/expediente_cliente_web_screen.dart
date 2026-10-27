import 'dart:typed_data';

import 'package:flutter/material.dart';

// LAS CAPACIDADES VIENEN DEL SHELL, no del catálogo de permisos: esta feature no puede
// importar `PermisoCompany` —hay un guardia que lo impide— y no le hace falta.
import '../../../../app/shell/apartados_web.dart' show CapacidadesDeModulo;
import '../../../../core/archivos/elegir_logotipo.dart';
import '../../../../core/design_system/design_system_web.dart';
import '../../../../core/direcciones/campos_de_domicilio.dart';
import '../../../../core/direcciones/direccion.dart';
import '../../../../core/direcciones/seccion_de_domicilio.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/error/mensajes_humanos.dart';
import '../../../../core/error/rechazo_del_servidor.dart';
import '../../../../core/fechas/fecha_en_pantalla.dart';
import '../../../../core/trabajo_sin_guardar/declara_su_trabajo_sin_guardar.dart';
import '../../../../core/trabajo_sin_guardar/guardia_de_salida.dart';
import '../datos/clientes_repositorio_http.dart';
import '../modelos/cliente.dart';
import '../modelos/entidad_fiscal.dart';
import 'seccion_de_contactos.dart';
import 'seccion_de_entidades_fiscales.dart';

/// Dónde pinta la ficha la razón social y el RFC de la **única** entidad fiscal activa.
///
/// Existe porque desde que la sección de entidades fiscales vive en esta misma pantalla,
/// la razón social **sale dos veces**, y una prueba que buscara el texto a secas no podría
/// distinguir «la ficha la muestra» —que es la regla: sólo con una activa— de «la lista la
/// lista», que es siempre.
const claveDeLaEntidadDeLaFicha = Key('ficha_entidad_fiscal_unica');

/// **Cuanto hay de un cliente, en un solo sitio**: su ficha, sus indicadores, sus datos
/// generales y su domicilio de referencia.
///
/// ## Consultar y editar son DOS DIRECCIONES
///
/// `/comercial/clientes/<id>` y `/comercial/clientes/<id>/editar`, igual que la pestaña
/// de Empresa y por la misma razón: **consultar no es cambiar**. Así «atrás» devuelve de
/// la edición a la consulta, el enlace de un cliente se puede pegar sin abrir un
/// formulario, y el `onExit` de la ruta de edición es el que pregunta por el trabajo sin
/// guardar (D-56).
///
/// ## Guardar son hasta DOS peticiones, y el servidor no las junta
///
/// El cliente va por `PATCH /clients/{id}` **con motivo**, y el domicilio por
/// `PUT /clients/{id}/address` **sin él**: son dos rutas y no hay una que escriba las
/// dos cosas en una transacción, al contrario que el expediente de una sucursal. De eso
/// salen tres reglas que esta pantalla implementa y conviene no reinterpretar:
///
///  1. **sólo viaja lo que cambió.** El servidor rechaza un `PATCH` que no cambia nada
///     —«No hay nada que modificar»— así que mandar el cuerpo completo haría que pulsar
///     «Guardar» sin tocar nada respondiera un 400;
///  2. **si una de las dos falla, la otra ya ocurrió**, y se dice qué quedó guardado. No
///     se intenta deshacer: deshacer una corrección es otra corrección, con su motivo y
///     su rastro en la auditoría;
///  3. **el domicilio se CORRIGE y no se borra, y es una decisión del dueño** (D-59), no
///     una limitación que haya que arreglar: no hay caso de negocio para dejar a un
///     cliente sin domicilio una vez capturado. El escritorio permitía vaciarlo —y
///     vaciarlo lo archivaba—. El servidor ya lo imponía: no hay `DELETE` y su `PUT`
///     exige los seis obligatorios. **Capturarlo sigue siendo opcional**; lo que no se
///     puede es quitarlo después, y la letra chica lo dice en lugar de dejar que se
///     descubra con un «Falta la calle.».
///
/// <b>Importa `design_system_web.dart`, NUNCA el barrel completo.</b> El completo
/// exporta un componente que lee del disco con `dart:io` y rompería la build web.
class ExpedienteClienteWebScreen extends StatefulWidget {
  const ExpedienteClienteWebScreen({
    required this.repositorio,
    required this.empresaId,
    required this.clienteId,
    required this.capacidades,
    required this.guardia,
    required this.editando,
    required this.alIrADentro,
    required this.alVolver,
    required this.alConocerElNombre,
    this.elegirUnLogotipo = elegirLogotipo,
    super.key,
  });

  final ClientesRepositorioHttp repositorio;
  final String empresaId;

  /// **El id de la URL**, y de la URL sale sólo esto: dónde estás. Lo que se puede hacer
  /// sigue saliendo del contexto que confirmó el servidor.
  final String clienteId;

  final CapacidadesDeModulo capacidades;

  /// D-56 · dónde se registra que hay trabajo sin guardar. **Esta pantalla SÍ lo usa**:
  /// es un formulario con «Guardar».
  final GuardiaDeSalida guardia;

  /// Si la dirección dice que se está editando. **No es estado de la pantalla** (D-39).
  final bool editando;

  /// Pide cambiar de modo. `null` vuelve a la consulta, `'editar'` abre la edición.
  ///
  /// **La pantalla pide, no navega:** quien conoce la ruta del apartado es el portón.
  final void Function(String? aDonde) alIrADentro;

  /// Vuelve al listado.
  final VoidCallback alVolver;

  /// Publica cómo se llama el cliente, **para el rastro**.
  ///
  /// Sale de la fila cargada y **nunca de la URL**: en la URL quedaría viejo en cuanto
  /// alguien renombrara al cliente. Es la misma regla que el expediente de una sucursal.
  final void Function(String id, String nombre) alConocerElNombre;

  /// Cómo se elige un logotipo. Por omisión, el selector de verdad; se recibe para que
  /// las pruebas puedan ejercitar lo que pasa **después** de elegir.
  final SelectorDeLogotipo elegirUnLogotipo;

  @override
  State<ExpedienteClienteWebScreen> createState() =>
      _ExpedienteClienteWebScreenState();
}

class _ExpedienteClienteWebScreenState extends State<ExpedienteClienteWebScreen>
    with DeclaraSuTrabajoSinGuardar<ExpedienteClienteWebScreen> {
  @override
  GuardiaDeSalida get guardia => widget.guardia;

  /// Lo que el servidor devolvió la última vez que esta pantalla y él coincidieron.
  /// **Es la base de la comparación de cambios**, no una copia de cortesía.
  Cliente? _cliente;
  IndicadoresDeCliente? _indicadores;
  Direccion? _domicilioCargado;
  List<EntidadFiscal> _entidades = const [];
  Uint8List? _logotipo;

  Failure? _fallo;
  bool _cargando = true;
  bool _guardando = false;

  final _nombre = TextEditingController();
  final _observaciones = TextEditingController();
  final _domicilio = CamposDeDomicilio();

  /// Los tres de **sólo lectura**.
  ///
  /// ⚠️ **SON CAMPOS DEL ESTADO Y NO SE CREAN EN EL `build`**, que es lo que tenía
  /// escrito y es un error de los que no fallan: un `TextEditingController` nuevo en cada
  /// repintado se queda sin liberar, y en esta pantalla hay un repintado por tecla. El
  /// proyecto ya pagó una vez por un controller sin liberar.
  final _folio = TextEditingController();
  final _inicio = TextEditingController();
  final _actualizado = TextEditingController();

  String? _errorDeNombre;

  @override
  void initState() {
    super.initState();
    // D-56 · el registro en el guardia lo pone el mixin, en el `super.initState()`.
    _cargar();
  }

  @override
  void dispose() {
    for (final c in [_nombre, _observaciones, _folio, _inicio, _actualizado]) {
      c.dispose();
    }

    // Los diez del domicilio los libera su juego, que es su dueño.
    _domicilio.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(ExpedienteClienteWebScreen anterior) {
    super.didUpdateWidget(anterior);

    // ⚠️ **CAMBIAR DE CLIENTE SIN DESMONTAR LA PANTALLA PASA DE VERDAD**: las dos
    // direcciones son la misma ruta con otro `<id>`, así que go_router reutiliza este
    // `State`. Sin esto, el expediente seguiría enseñando el cliente anterior con la URL
    // del nuevo. Es el mismo caso que el expediente de una sucursal resolvió en D-39.
    if (anterior.clienteId != widget.clienteId) _cargar();

    // SALIR DE LA EDICIÓN SIN GUARDAR DEVUELVE LO CARGADO. La pregunta la hizo ya el
    // `onExit` de la ruta; si llegó aquí, es que se eligió salir.
    if (anterior.editando && !widget.editando) _volcar();
  }

  // =========================================================================
  // Cargar
  // =========================================================================

  /// Las cinco lecturas de la ficha, **en paralelo**.
  ///
  /// Son cinco rutas porque el servidor las separó a propósito —los indicadores tienen
  /// la suya «para que quien sólo quiere los datos del cliente no pague dos consultas
  /// más»—, y aquí la ficha necesita las cinco. En serie serían cinco viajes seguidos.
  ///
  /// ⚠️ **SÓLO EL CLIENTE PUEDE IMPEDIR PINTAR.** Si fallan los indicadores, las
  /// entidades o el logotipo, la ficha sale con lo que hay y lo que falta se dice en su
  /// sitio: un cliente que no se puede consultar porque su logotipo no bajó sería una
  /// pantalla inútil por un adorno.
  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _fallo = null;
    });

    final id = widget.clienteId;

    final (cliente, indicadores, domicilio, entidades, logotipo) = await (
      widget.repositorio.ver(empresaId: widget.empresaId, clienteId: id),
      widget.repositorio.verIndicadores(
        empresaId: widget.empresaId,
        clienteId: id,
      ),
      widget.repositorio.verDomicilio(
        empresaId: widget.empresaId,
        clienteId: id,
      ),
      widget.repositorio.listarEntidadesFiscales(
        empresaId: widget.empresaId,
        clienteId: id,
      ),
      widget.repositorio.leerLogotipo(
        empresaId: widget.empresaId,
        clienteId: id,
      ),
    ).wait;

    // LA RESPUESTA DE OTRO CLIENTE SE DESCARTA: entre que se pidió y que llegó, la
    // dirección puede haber cambiado a otro id.
    if (!mounted || widget.clienteId != id) return;

    cliente.when(
      failure: (f) => setState(() {
        _fallo = f;
        _cargando = false;
      }),
      ok: (c) {
        setState(() {
          _cliente = c;
          _indicadores = indicadores.when(ok: (i) => i, failure: (_) => null);
          _domicilioCargado = domicilio.when(
            ok: (d) => d,
            failure: (_) => null,
          );
          _entidades = entidades.when(ok: (e) => e, failure: (_) => const []);
          _logotipo = logotipo.when(ok: (b) => b, failure: (_) => null);
          _cargando = false;
          _volcar();
        });

        // EL RASTRO SE ENTERA DEL NOMBRE, de la fila cargada y nunca de la URL.
        widget.alConocerElNombre(c.id, '${c.codigo} ${c.nombreComercial}');
      },
    );
  }

  /// Pone lo cargado en el formulario. **Un solo sitio**, para que cargar, guardar y
  /// cancelar no puedan discrepar.
  void _volcar() {
    final c = _cliente;

    _nombre.text = c?.nombreComercial ?? '';
    _observaciones.text = c?.observaciones ?? '';
    _domicilio.volcar(_domicilioCargado);

    _folio.text = c?.codigo ?? '';
    _inicio.text = switch (c?.inicioDeLaRelacion) {
      // SIN FECHA SE DICE. No puede pasar con un servidor sano —la exige al crear— y
      // callarlo dejaría un campo vacío que se lee como un dato perdido.
      null => 'Sin fecha',
      final dia => fechaDeNegocioCorta(dia),
    };
    _actualizado.text = c == null ? '' : fechaYHora(c.actualizadoEn);

    _errorDeNombre = null;
  }

  // =========================================================================
  // D-56 · qué se perdería
  // =========================================================================

  /// **Sólo en edición hay algo que perder**: en consulta los campos no se pueden tocar,
  /// así que una diferencia sólo podría venir de un volcado a medias — y preguntar por
  /// eso sería preguntar por nada.
  @override
  bool get hayCambiosSinGuardar {
    if (!widget.editando) return false;

    final c = _cliente;
    if (c == null) return false;

    if (_nombre.text.trim() != c.nombreComercial) return true;
    if (_observacionesEscritas != c.observaciones) return true;

    return !_domicilio.igualA(_domicilioCargado);
  }

  /// Lo escrito en observaciones, **con el vacío como ausencia**: unas observaciones de
  /// cero caracteres no son unas observaciones, y el servidor guarda nulo.
  String? get _observacionesEscritas {
    final texto = _observaciones.text.trim();

    return texto.isEmpty ? null : texto;
  }

  /// **El nombre GUARDADO y no el del campo**: a quien está renombrando, la pregunta le
  /// hablaría de algo que todavía no existe con ese nombre.
  @override
  String get queSePierde =>
      'el expediente del cliente ${_cliente?.nombreComercial ?? ''}'.trimRight();

  // =========================================================================
  // Pintar
  // =========================================================================

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Scaffold(
      backgroundColor: colors.surface,
      body: SafeArea(
        child: _cargando
            ? const Center(child: CircularProgressIndicator())
            : _cuerpo(),
      ),
    );
  }

  Widget _cuerpo() {
    if (_fallo case final f?) {
      return RisegEmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'No se pudo cargar el cliente',
        message: f.message,
        primaryAction: RisegButton(
          label: 'Intentar de nuevo',
          onPressed: _cargar,
        ),
        secondaryAction: RisegButton(
          label: 'Volver a Clientes',
          variant: RisegButtonVariant.secondary,
          onPressed: widget.alVolver,
        ),
      );
    }

    final cliente = _cliente;
    if (cliente == null) return const SizedBox.shrink();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Volver(onPressed: widget.alVolver),
          const SizedBox(height: AppSpacing.md),

          _Cabecera(
            cliente: cliente,
            logotipo: _logotipo,
            // LA RAZÓN SOCIAL Y EL RFC SÓLO CON **UNA** ENTIDAD FISCAL ACTIVA: con 0 o
            // 2+ sería ambiguo, y es la regla del escritorio. La ficha no elige una.
            unicaEntidadActiva: _unicaEntidadActiva,
            editando: widget.editando,
            puedeAdministrar: widget.capacidades.puedeModificar,
            ocupado: _guardando,
            onEditar: () => widget.alIrADentro('editar'),
            onEditarLogotipo: _editarLogotipo,
            onCambiarEstatus: _cambiarEstatus,
          ),
          const SizedBox(height: AppSpacing.lg),

          _Indicadores(indicadores: _indicadores),
          const SizedBox(height: AppSpacing.lg),

          _datosGenerales(cliente),
          const SizedBox(height: AppSpacing.lg),

          SeccionDeDomicilio(
            campos: _domicilio,
            habilitado: _sePuedeEscribir,
            // ⚠️ **VACÍO, Y NO ES UN HUECO SIN LLENAR.** El `PUT` del domicilio de un
            // cliente responde **un mensaje** —«Falta la colonia.»— y no una lista de
            // campos señalados, al contrario que el `PUT` del expediente de una
            // sucursal, que sí la manda y por eso su pantalla la pinta. Así que el
            // mensaje del servidor sale completo arriba, donde se lee.
            //
            // Tenía aquí un lector de `fallo.extra['fields']` que **nunca se llenaba**:
            // `ApiErrorParser` sólo conserva `usedBytes` y `capacityBytes`. Un mapa que
            // siempre está vacío es peor que no tenerlo, porque parece que el caso está
            // cubierto. El día que el servidor mande los campos, aquí es donde entran.
            erroresPorCampo: const {},
            titulo: 'Domicilio de referencia',
            // LA LETRA CHICA DICE LAS DOS REGLAS, y la segunda es de esta pantalla: el
            // servidor no tiene `DELETE` de domicilio, así que una vez registrado sólo
            // se corrige. Callarlo dejaría que se descubriera con un «Falta la calle.».
            descripcion: _domicilioCargado == null
                ? 'Opcional. Si escribes cualquier dato, hacen falta calle, número '
                      'exterior, colonia, municipio, estado y código postal. Si los '
                      'dejas todos vacíos, no se guarda domicilio.'
                : 'Hacen falta calle, número exterior, colonia, municipio, estado y '
                      'código postal. Una vez registrado, el domicilio se corrige: '
                      'no se puede quitar desde aquí.',
          ),
          const SizedBox(height: AppSpacing.lg),

          SeccionDeContactos(
            repositorio: widget.repositorio,
            empresaId: widget.empresaId,
            clienteId: widget.clienteId,
            puedeAdministrar: widget.capacidades.puedeModificar,
            guardia: widget.guardia,
          ),
          const SizedBox(height: AppSpacing.lg),

          SeccionDeEntidadesFiscales(
            repositorio: widget.repositorio,
            empresaId: widget.empresaId,
            clienteId: widget.clienteId,
            puedeAdministrar: widget.capacidades.puedeModificar,
            guardia: widget.guardia,
            // LA CABECERA SE ENTERA, y hace falta: la razón social y el RFC de arriba
            // sólo se muestran con **una** entidad activa, así que añadir, archivar o
            // reactivar una puede hacerlos aparecer o desaparecer.
            alCambiar: _recargarLasEntidades,
          ),
          const SizedBox(height: AppSpacing.lg),
          const _LlegaDespues(
            titulo: 'Servicios del cliente',
            mensaje:
                'Los servicios contratados llegan con la subetapa de Servicios, que '
                'es la siguiente del módulo.',
            icono: Icons.design_services_outlined,
          ),
          const SizedBox(height: AppSpacing.md),
          const _LlegaDespues(
            titulo: 'Portales',
            mensaje:
                'Los portales del cliente llegan con su propia subetapa, y exigen un '
                'permiso aparte que el Maestro no hereda.',
            icono: Icons.vpn_key_outlined,
          ),

          if (widget.editando) ...[
            const SizedBox(height: AppSpacing.lg),
            _Acciones(
              guardando: _guardando,
              onCancelar: () => widget.alIrADentro(null),
              onGuardar: _guardar,
            ),
          ],
        ],
      ),
    );
  }

  /// Vuelve a leer las entidades fiscales, **para la cabecera**.
  ///
  /// No recarga la ficha entera: lo único que depende de ellas arriba es la razón social
  /// y el RFC, y volver a pedir el cliente, los indicadores, el domicilio y el logotipo
  /// por haber archivado una razón social serían cuatro peticiones de más.
  Future<void> _recargarLasEntidades() async {
    final id = widget.clienteId;

    final resultado = await widget.repositorio.listarEntidadesFiscales(
      empresaId: widget.empresaId,
      clienteId: id,
    );

    if (!mounted || widget.clienteId != id) return;

    resultado.when(
      ok: (lista) => setState(() => _entidades = lista),
      // UN FALLO AQUÍ NO CAMBIA NADA: la cabecera sigue con lo que tenía, que es lo
      // último que el servidor confirmó. Enseñar un error por esto molestaría sin
      // ofrecer nada que hacer — la sección de abajo ya dice si no pudo cargar.
      failure: (_) {},
    );
  }

  /// La única entidad fiscal **activa**, o nula si hay cero o más de una.
  EntidadFiscal? get _unicaEntidadActiva {
    final activas = [
      for (final e in _entidades)
        if (e.estaActiva) e,
    ];

    return activas.length == 1 ? activas.single : null;
  }

  /// Si los campos se pueden tocar: **en edición y con permiso**.
  bool get _sePuedeEscribir =>
      widget.editando && widget.capacidades.puedeModificar && !_guardando;

  Widget _datosGenerales(Cliente cliente) => RisegFormSection(
    title: 'Datos generales',
    grid: true,
    children: [
      // EL FOLIO NO SE EDITA NUNCA, y el campo lo dice en lugar de aceptarlo y
      // descartarlo en silencio: lo asigna el servidor y **no viaja en ningún cuerpo**.
      RisegTextField(
        label: 'Folio',
        controller: _folio,
        enabled: false,
        helperText: 'Lo asigna el sistema y no cambia.',
      ),
      RisegTextField(
        label: 'Nombre comercial',
        controller: _nombre,
        enabled: _sePuedeEscribir,
        errorText: _errorDeNombre,
        helperText: 'La marca. La razón social va en sus entidades fiscales.',
      ),
      RisegTextField(
        label: 'Inicio de la relación',
        controller: _inicio,
        // ⏳(D-58) NO SE EDITA TODAVÍA, y no es que no se pueda: el servidor acepta
        // `startedOn` en el `PATCH`. Falta un selector de fecha en esta sección, y
        // mientras tanto el campo dice el dato en vez de esconderlo.
        enabled: false,
      ),
      RisegTextField(
        label: 'Última actualización',
        controller: _actualizado,
        enabled: false,
        // ⏳(D-58) LA FECHA DE CREACIÓN NO ESTÁ EN EL CONTRATO: `ClientResponse` sólo
        // trae `updatedAt`. No se sustituye por el inicio de la relación, que es otra
        // cosa —cuándo empezó el negocio, no cuándo se capturó la fila—.
        helperText: 'En tu hora local.',
      ),
      RisegTextField(
        label: 'Observaciones',
        controller: _observaciones,
        enabled: _sePuedeEscribir,
        maxLines: 3,
        helperText: 'El buscador del listado también mira aquí.',
      ),
    ],
  );

  // =========================================================================
  // Guardar
  // =========================================================================

  /// Guarda lo que cambió, **y nada más**.
  ///
  /// El motivo se pide **antes** de mandar nada, por lo mismo que el servidor lo valida
  /// primero: no es un campo del formulario, es la condición para corregir. Cancelar el
  /// diálogo del motivo no guarda nada y no pierde lo escrito.
  Future<void> _guardar() async {
    final cliente = _cliente;
    if (cliente == null) return;

    final nombre = _nombre.text.trim();

    // EL NOMBRE VACÍO SE PARA AQUÍ: el servidor también lo rechaza, pero con el campo en
    // blanco no hace falta ir a preguntarlo.
    if (nombre.isEmpty) {
      setState(() => _errorDeNombre = 'Falta el nombre comercial.');

      return;
    }

    final cambioElNombre = nombre != cliente.nombreComercial;
    final cambiaronLasObservaciones =
        _observacionesEscritas != cliente.observaciones;

    final cambioElCliente = cambioElNombre || cambiaronLasObservaciones;
    final cambioElDomicilio = !_domicilio.igualA(_domicilioCargado);

    // NADA QUE GUARDAR NO ES UN ERROR: se vuelve a la consulta, que es lo que esa
    // persona quería. Mandar el `PATCH` igual respondería «No hay nada que modificar».
    if (!cambioElCliente && !cambioElDomicilio) {
      widget.alIrADentro(null);

      return;
    }

    final motivo = await _pedirElMotivo();
    if (motivo == null || !mounted) return;

    setState(() {
      _guardando = true;
      _errorDeNombre = null;
    });

    // ⚠️ **EL CLIENTE PRIMERO Y EL DOMICILIO DESPUÉS**, y el orden importa: si falla el
    // primero no se ha tocado nada, y si falla el segundo lo que quedó guardado es una
    // corrección con su motivo en la auditoría — algo que se puede leer y rehacer.
    var guardadoElCliente = false;

    if (cambioElCliente) {
      final resultado = await widget.repositorio.modificar(
        empresaId: widget.empresaId,
        clienteId: cliente.id,
        motivo: motivo,
        // ⚠️ **CADA CAMPO VIAJA SÓLO SI CAMBIÓ**, y lo midió una prueba: mandando las
        // observaciones «porque están ahí», un cambio de nombre arrastraba un `notes`
        // que nadie tocó. El servidor compara contra la fila, así que no fallaría — y
        // el evento de la auditoría diría que se cambiaron las observaciones.
        nombreComercial: cambioElNombre ? nombre : null,
        observaciones: cambiaronLasObservaciones ? _observacionesEscritas : null,
        observacionesSeVacian:
            cambiaronLasObservaciones && _observacionesEscritas == null,
      );

      if (!mounted) return;

      final siguio = resultado.when(
        ok: (c) {
          setState(() => _cliente = c);
          widget.alConocerElNombre(c.id, '${c.codigo} ${c.nombreComercial}');

          return true;
        },
        failure: (f) {
          setState(() => _guardando = false);
          mostrarRechazoDelServidor(context, f);

          return false;
        },
      );

      if (!siguio) return;

      guardadoElCliente = true;
    }

    if (cambioElDomicilio) {
      final direccion = _domicilio.direccion;

      // VACIARLO NO SE MANDA: el servidor no puede borrarlo y su `PUT` contestaría
      // «Falta la calle.», que es cierto y no explica qué pasa. Se dice aquí.
      if (direccion == null) {
        setState(() => _guardando = false);

        RisegFeedback.showError(
          context,
          guardadoElCliente
              ? 'Se guardaron los datos del cliente. El domicilio no se puede quitar '
                    'desde aquí: corrígelo o vuelve a escribirlo como estaba.'
              : 'El domicilio no se puede quitar desde aquí: corrígelo o vuelve a '
                    'escribirlo como estaba.',
        );

        return;
      }

      final resultado = await widget.repositorio.guardarDomicilio(
        empresaId: widget.empresaId,
        clienteId: cliente.id,
        direccion: direccion,
      );

      if (!mounted) return;

      final siguio = resultado.when(
        ok: (d) {
          setState(() => _domicilioCargado = d);

          return true;
        },
        failure: (f) {
          setState(() => _guardando = false);

          // SE DICE QUÉ SÍ QUEDÓ GUARDADO. Sin eso, quien lea «Falta la colonia.»
          // pensaría que no se guardó nada y volvería a escribir el nombre.
          RisegFeedback.showError(
            context,
            guardadoElCliente
                ? 'Se guardaron los datos del cliente, pero el domicilio no: '
                      '${MensajesHumanos.deMutacion(f)}'
                : MensajesHumanos.deMutacion(f),
          );

          return false;
        },
      );

      if (!siguio) return;
    }

    setState(() => _guardando = false);

    RisegFeedback.showSuccess(context, 'Se guardó el expediente del cliente.');
    widget.alIrADentro(null);
  }

  Future<String?> _pedirElMotivo() => mostrarDialogoMotivo(
    context,
    titulo: 'Corregir el cliente',
    etiquetaMotivo: 'Motivo de la corrección',
    confirmarLabel: 'Guardar',
    cancelarLabel: 'Seguir editando',
    errorMotivoRequerido:
        'Falta el motivo. Queda en la bitácora y es lo que explica por qué cambió '
        'este dato.',
  );

  // =========================================================================
  // El estatus y el logotipo
  // =========================================================================

  /// Cambia el estatus, **con motivo**, desde un diálogo.
  ///
  /// ⚠️ **TERMINAR LA RELACIÓN NO BORRA NADA Y TIENE CONSECUENCIAS**: un cliente que no
  /// está activo no admite servicios nuevos. El diálogo lo dice antes de confirmar, no
  /// después.
  Future<void> _cambiarEstatus() async {
    final cliente = _cliente;
    if (cliente == null) return;

    final elegido = await showDialog<EstatusDeCliente>(
      context: context,
      builder: (_) => _DialogoDeEstatus(actual: cliente.estado),
    );

    if (elegido == null || !mounted) return;

    final motivo = await mostrarDialogoMotivo(
      context,
      titulo: 'Cambiar el estatus a ${elegido.nombre}',
      etiquetaMotivo: 'Motivo del cambio',
      confirmarLabel: 'Cambiar el estatus',
      cancelarLabel: 'Cancelar',
      errorMotivoRequerido:
          'Falta el motivo. Queda en la bitácora con el estatus anterior y el nuevo.',
      advertencia: elegido == EstatusDeCliente.activo
          ? null
          : 'Mientras el cliente no esté activo no se le pueden crear servicios '
                'nuevos ni editar los que tiene.',
    );

    if (motivo == null || !mounted) return;

    setState(() => _guardando = true);

    final resultado = await widget.repositorio.modificar(
      empresaId: widget.empresaId,
      clienteId: cliente.id,
      motivo: motivo,
      estatus: elegido,
    );

    if (!mounted) return;

    resultado.when(
      ok: (c) {
        setState(() {
          _cliente = c;
          _guardando = false;
        });

        RisegFeedback.showSuccess(
          context,
          'El cliente quedó en ${elegido.nombre.toLowerCase()}.',
        );
      },
      failure: (f) {
        setState(() => _guardando = false);
        mostrarRechazoDelServidor(context, f);
      },
    );
  }

  /// Elige un logotipo nuevo y lo sube, o quita el que hay.
  Future<void> _editarLogotipo() async {
    final cliente = _cliente;
    if (cliente == null) return;

    final elegido = await widget.elegirUnLogotipo(
      context,
      donde: 'la ficha del cliente',
      // AQUÍ SÍ PUEDE HABER UNO ANTERIOR —el cliente ya existe— y sólo se avisa cuando
      // de verdad hay algo que reemplazar.
      queReemplaza: _logotipo == null
          ? null
          : 'Este cliente ya tiene logotipo, y éste lo reemplaza.',
    );

    if (elegido == null || !mounted) return;

    setState(() => _guardando = true);

    final resultado = await widget.repositorio.subirLogotipo(
      empresaId: widget.empresaId,
      clienteId: cliente.id,
      nombreDeArchivo: elegido.nombre,
      bytes: elegido.bytes,
    );

    if (!mounted) return;

    resultado.when(
      ok: (bytes) {
        setState(() {
          _logotipo = bytes;
          _guardando = false;
        });

        RisegFeedback.showSuccess(context, 'Se actualizó el logotipo.');
      },
      failure: (f) {
        setState(() => _guardando = false);
        mostrarRechazoDelServidor(context, f);
      },
    );
  }
}

// ===========================================================================
// La cabecera
// ===========================================================================

class _Volver extends StatelessWidget {
  const _Volver({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return InkWell(
      onTap: onPressed,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.arrow_back, size: 18, color: colors.textMuted),
            const SizedBox(width: AppSpacing.xs),
            Text(
              'Clientes',
              style: AppTypography.body.copyWith(color: colors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _Cabecera extends StatelessWidget {
  const _Cabecera({
    required this.cliente,
    required this.logotipo,
    required this.unicaEntidadActiva,
    required this.editando,
    required this.puedeAdministrar,
    required this.ocupado,
    required this.onEditar,
    required this.onEditarLogotipo,
    required this.onCambiarEstatus,
  });

  final Cliente cliente;
  final Uint8List? logotipo;

  /// La razón social y el RFC **sólo si hay exactamente una activa**. Con 0 o 2+ sería
  /// ambiguo: la ficha no elige una, y enseñar «la primera» sería inventar un dato.
  final EntidadFiscal? unicaEntidadActiva;

  final bool editando;
  final bool puedeAdministrar;
  final bool ocupado;
  final VoidCallback onEditar;
  final VoidCallback onEditarLogotipo;
  final VoidCallback onCambiarEstatus;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final bytes = logotipo;

    return RisegCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: SizedBox(
              width: 64,
              height: 64,
              child: bytes == null
                  ? RisegIniciales(
                      id: cliente.id,
                      nombre: cliente.nombreComercial,
                      lado: 64,
                    )
                  : ColoredBox(
                      color: Colors.white,
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.xxs),
                        child: Image.memory(
                          bytes,
                          fit: BoxFit.contain,
                          // UN PNG QUE NO SE PUEDE DECODIFICAR NO REVIENTA LA FICHA.
                          errorBuilder: (_, _, _) => RisegIniciales(
                            id: cliente.id,
                            nombre: cliente.nombreComercial,
                            lado: 64,
                          ),
                        ),
                      ),
                    ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(cliente.nombreComercial, style: AppTypography.heading1),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  cliente.codigo,
                  style: AppTypography.caption.copyWith(color: colors.textMuted),
                ),
                if (unicaEntidadActiva case final e?) ...[
                  const SizedBox(height: AppSpacing.sm),
                  // LA LLAVE ES PARA LAS PRUEBAS, y hace falta de verdad: desde que la
                  // sección de entidades fiscales está abajo, la razón social sale **dos
                  // veces** en la pantalla, y una prueba que buscara el texto a secas no
                  // podría distinguir «la ficha la muestra» de «la lista la lista».
                  Column(
                    key: claveDeLaEntidadDeLaFicha,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(e.razonSocial, style: AppTypography.body),
                      Text(
                        // SIN RFC SE DICE, porque es opcional al dar de alta la entidad
                        // y **obligatorio para facturar**: un hueco en blanco no
                        // avisaría.
                        e.rfc ?? 'Sin RFC registrado',
                        style: AppTypography.caption.copyWith(
                          color: e.rfc == null ? colors.warning : colors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _InsigniaDeEstatusDeLaFicha(cliente: cliente),

              // LOS BOTONES SÓLO EN CONSULTA: en edición, lo que hay es Guardar y
              // Cancelar. Y sólo con permiso: lo que no se puede hacer no se muestra.
              if (!editando && puedeAdministrar) ...[
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  children: [
                    RisegButton(
                      label: 'Editar logotipo',
                      icon: Icons.image_outlined,
                      variant: RisegButtonVariant.secondary,
                      size: RisegButtonSize.compact,
                      onPressed: ocupado ? null : onEditarLogotipo,
                    ),
                    RisegButton(
                      label: 'Cambiar estatus',
                      icon: Icons.swap_horiz,
                      variant: RisegButtonVariant.secondary,
                      size: RisegButtonSize.compact,
                      onPressed: ocupado ? null : onCambiarEstatus,
                    ),
                    RisegButton(
                      label: 'Editar',
                      icon: Icons.edit_outlined,
                      size: RisegButtonSize.compact,
                      onPressed: ocupado ? null : onEditar,
                    ),
                  ],
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// La insignia de la ficha. **Un estatus desconocido se enseña tal cual**, igual que en
/// el listado: un `_ => activo` pintaría como activo a un cliente que no lo está.
class _InsigniaDeEstatusDeLaFicha extends StatelessWidget {
  const _InsigniaDeEstatusDeLaFicha({required this.cliente});

  final Cliente cliente;

  @override
  Widget build(BuildContext context) => switch (cliente.estado) {
    EstatusDeCliente.activo => const RisegStatusBadge(
      label: 'Activo',
      tone: RisegStatusTone.success,
      icon: Icons.check_circle_outline,
    ),
    EstatusDeCliente.suspendido => const RisegStatusBadge(
      label: 'Suspendido',
      tone: RisegStatusTone.warning,
      icon: Icons.pause_circle_outline,
    ),
    EstatusDeCliente.terminado => const RisegStatusBadge(
      label: 'Terminado',
      tone: RisegStatusTone.neutral,
      icon: Icons.do_not_disturb_on_outlined,
    ),
    null => RisegStatusBadge(
      label: cliente.estatus,
      tone: RisegStatusTone.neutral,
      icon: Icons.help_outline,
    ),
  };
}

// ===========================================================================
// Los indicadores
// ===========================================================================

/// Servicios activos e importe mensual contratado.
///
/// **Personal asignado NO está** y llega con la cobertura operativa. No sale en cero:
/// **ausencia nunca es cero**, y un cero diría que el cliente no tiene gente.
class _Indicadores extends StatelessWidget {
  const _Indicadores({required this.indicadores});

  final IndicadoresDeCliente? indicadores;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final i = indicadores;

    // SI NO SE PUDIERON LEER, SE DICE. Un «0 servicios» inventado aquí sería un dato
    // falso con la forma de un dato.
    if (i == null) {
      return RisegCard(
        child: Row(
          children: [
            Icon(Icons.info_outline, size: 18, color: colors.textMuted),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                'No se pudieron leer los indicadores de este cliente.',
                style: AppTypography.body.copyWith(color: colors.textMuted),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: RisegStatCard(
                label: 'Servicios activos',
                value: '${i.serviciosActivos}',
                icon: Icons.design_services_outlined,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: RisegStatCard(
                label: 'Importe mensual contratado',
                // VACÍO NO ES CERO: sin condiciones vigentes no hay importe, y un
                // `$0.00` diría que se contrató algo por cero pesos.
                value: i.importeMensual.isEmpty
                    ? 'Sin condiciones vigentes'
                    : i.importeMensual.map((m) => m.enPantalla).join(' · '),
                icon: Icons.payments_outlined,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Importe mensual contratado, sin IVA, de los servicios no terminados.',
          style: AppTypography.caption.copyWith(color: colors.textMuted),
        ),
      ],
    );
  }
}

// ===========================================================================
// Lo que llega después, y por qué el hueco se explica
// ===========================================================================

/// Una sección que todavía no existe, **dicha con su nombre y su motivo**.
///
/// El hueco explica más que la ausencia: quien viene del escritorio busca sus contactos
/// y sus portales, y una pantalla que no los menciona parece una pantalla a la que le
/// falta algo sin que nadie sepa qué.
class _LlegaDespues extends StatelessWidget {
  const _LlegaDespues({
    required this.titulo,
    required this.mensaje,
    required this.icono,
  });

  final String titulo;
  final String mensaje;
  final IconData icono;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return RisegCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, size: 20, color: colors.textMuted),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titulo, style: AppTypography.bodyStrong),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  mensaje,
                  style: AppTypography.caption.copyWith(color: colors.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// Guardar y cancelar
// ===========================================================================

class _Acciones extends StatelessWidget {
  const _Acciones({
    required this.guardando,
    required this.onCancelar,
    required this.onGuardar,
  });

  final bool guardando;
  final VoidCallback onCancelar;
  final VoidCallback onGuardar;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.end,
    children: [
      RisegButton(
        label: 'Cancelar',
        variant: RisegButtonVariant.secondary,
        // CANCELAR NO PREGUNTA AQUÍ: cambiar de dirección pasa por el `onExit` de la
        // ruta, que es quien tiene la pregunta (D-56). Con las dos, cancelar
        // preguntaría dos veces por la misma salida.
        onPressed: guardando ? null : onCancelar,
      ),
      const SizedBox(width: AppSpacing.md),
      RisegButton(
        label: 'Guardar',
        loading: guardando,
        onPressed: guardando ? null : onGuardar,
      ),
    ],
  );
}

// ===========================================================================
// El diálogo del estatus
// ===========================================================================

/// Elegir el estatus nuevo. **Los tres, y el actual marcado.**
///
/// Elegir el que ya está no hace nada —se cierra sin devolver nada—, porque un cambio de
/// estatus a sí mismo sería un evento en la bitácora que no cambió nada.
class _DialogoDeEstatus extends StatelessWidget {
  const _DialogoDeEstatus({required this.actual});

  final EstatusDeCliente? actual;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return AlertDialog(
      title: const Text('Cambiar el estatus'),
      content: SizedBox(
        width: 380,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'El estatus del cliente **no** cambia el de sus servicios: no hay '
                  'cascada.'
                  .replaceAll('**', ''),
              style: AppTypography.caption.copyWith(color: colors.textMuted),
            ),
            const SizedBox(height: AppSpacing.md),
            for (final e in EstatusDeCliente.values)
              ListTile(
                leading: Icon(
                  e == actual
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: e == actual ? colors.accent : colors.textMuted,
                ),
                title: Text(e.nombre),
                subtitle: Text(_queSignifica(e), style: AppTypography.caption),
                // EL ACTUAL NO SE PUEDE ELEGIR: cambiarlo a sí mismo escribiría un
                // evento que no cambió nada.
                enabled: e != actual,
                onTap: () => Navigator.of(context).pop(e),
              ),
          ],
        ),
      ),
      actions: [
        RisegButton(
          label: 'Cancelar',
          variant: RisegButtonVariant.secondary,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  String _queSignifica(EstatusDeCliente e) => switch (e) {
    EstatusDeCliente.activo => 'Se le pueden crear y editar servicios.',
    EstatusDeCliente.suspendido =>
      'La relación sigue, pero no admite servicios nuevos.',
    EstatusDeCliente.terminado =>
      'La relación terminó. No se borra nada ni se archiva el cliente.',
  };
}
