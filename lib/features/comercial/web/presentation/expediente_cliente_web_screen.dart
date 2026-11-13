import 'dart:async';
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
import '../../../../core/fechas/dia_de_negocio.dart';
import '../../../../core/fechas/fecha_en_pantalla.dart';
import '../../../../core/trabajo_sin_guardar/declara_su_trabajo_sin_guardar.dart';
import '../../../../core/trabajo_sin_guardar/guardia_de_salida.dart';
import '../datos/clientes_repositorio_http.dart';
import '../datos/servicios_repositorio_http.dart';
import '../modelos/cliente.dart';
import '../modelos/entidad_fiscal.dart';
import '../modelos/servicio.dart';
import 'insignia_temporal.dart';
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
    this.alAbrirServicio,
    this.alVerSusServicios,
    this.hoy = DiaDeNegocio.hoy,
    this.repositorioDeServicios,
    super.key,
  });

  /// Para leer **los servicios de este cliente**. Nulo en las pruebas que no los miden.
  ///
  /// ⚠️ **ES EL REPOSITORIO DE SERVICIOS Y NO EL DE CLIENTES**, aunque la pantalla sea de
  /// un cliente: la ruta es `GET /services?clientId=…`, del módulo de Servicios, y
  /// meterla en el repositorio de Clientes mezclaría dos contratos en una clase.
  final ServiciosRepositorioHttp? repositorioDeServicios;

  /// Abrir uno de sus servicios. Nulo cuando quien monta no sabe navegar ahí.
  final void Function(String servicioId)? alAbrirServicio;

  /// Ver **todos** sus servicios, en Servicios y ya filtrados por él.
  final VoidCallback? alVerSusServicios;

  /// Qué día es hoy, para la insignia «Termina el…» de sus servicios. Entra por el
  /// constructor por lo mismo que en las otras dos pantallas: con el reloj leído adentro,
  /// una prueba se rompe sola al pasar los días.
  final DiaDeNegocio Function() hoy;

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
  final _creado = TextEditingController();
  final _actualizado = TextEditingController();

  /// D-58 · el inicio de la relación, **como fecha y no como texto**.
  ///
  /// `DateTime` y no `DiaDeNegocio` porque es lo que pide el campo del sistema de diseño.
  /// Al mandarlo se convierte con `DiaDeNegocio.deFechaLocal`, **nunca con
  /// `DiaDeNegocio.de`**: lo que la persona eligió es un día del calendario, y aplicarle
  /// el desplazamiento de zona lo correría un día.
  DateTime? _inicioElegido;

  /// Lo que falta por capturar, **por clave del servidor**, para señalarlo en su cuadro.
  ///
  /// Era un `String? _errorDeNombre`, y con eso los seis campos obligatorios del
  /// domicilio no se podían marcar: se descubrían de uno en uno en el aviso del servidor,
  /// que contesta **el primero que falta y para**.
  Map<String, String> _faltantes = const {};

  /// Cuántos servicios se enseñan dentro del expediente del cliente.
  ///
  /// Cinco, y se piden **seis**: así se sabe si hay más sin contar. El listado pagina por
  /// cursor y **no devuelve totales** a propósito (D-67), así que «cuántos son» costaría
  /// traerlos todos.
  static const _cuantosServiciosSeEnsenan = 5;

  /// Los servicios de este cliente. **Nulo es «todavía no llegaron»** y vacío «no tiene».
  List<ServicioEnLista>? _servicios;

  /// La pestaña abierta: **General · Domicilio · Contactos · Razones sociales**.
  ///
  /// Se mueve sola cuando un error cae en otra: ver [_pestanaDeLosErrores].
  int _pestana = 0;

  /// Los nodos de foco, en el orden de la pantalla.
  final _focos = RisegFocosDeFormulario(const [
    'name',
    'startedOn',
    'address.street',
    'address.exteriorNumber',
    'address.interiorNumber',
    'address.neighborhood',
    'address.municipality',
    'address.city',
    'address.state',
    'address.postalCode',
    'address.country',
    'address.landmarks',
  ]);

  @override
  void initState() {
    super.initState();
    // D-56 · el registro en el guardia lo pone el mixin, en el `super.initState()`.
    _cargar();
  }

  @override
  void dispose() {
    for (final c in [_nombre, _observaciones, _folio, _creado, _actualizado]) {
      c.dispose();
    }

    // Los diez del domicilio los libera su juego, que es su dueño.
    _domicilio.dispose();
    // NO ES OPCIONAL: un `FocusNode` sin liberar deja al `FocusManager` con una
    // referencia a un widget desmontado.
    _focos.dispose();
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

    // LOS SERVICIOS VAN APARTE porque su repositorio es OPCIONAL: quien monta esta
    // pantalla sin él —una prueba que mide otra cosa— no tiene por qué fabricarlo.
    // Y no bloquean la ficha: llegan cuando llegan, y mientras tanto su tarjeta espera.
    unawaited(_cargarSusServicios(id));

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

    // UN VOLCADO ESTRENA FORMULARIO: lo que se vuelque es «lo cargado», así que lo que
    // hubiera guardado antes deja de ser relevante.
    _yaSeGuardo = false;

    _nombre.text = c?.nombreComercial ?? '';
    _observaciones.text = c?.observaciones ?? '';
    _domicilio.volcar(_domicilioCargado);

    _folio.text = c?.codigo ?? '';

    // D-58 · EL SELECTOR SE CARGA CON LO QUE HAY, y nulo es nulo: el campo dice «Elegir
    // fecha» en vez de un texto inventado. No puede pasar con un servidor sano —la
    // exige al crear—, pero un valor fabricado aquí sería peor que un hueco.
    _inicioElegido = c?.inicioDeLaRelacion?.comoFechaLocal;

    _creado.text = c == null ? '' : fechaYHora(c.creadoEn);
    _actualizado.text = c == null ? '' : fechaYHora(c.actualizadoEn);

    _faltantes = const {};
  }

  // =========================================================================
  // D-56 · qué se perdería
  // =========================================================================

  /// **Sólo en edición hay algo que perder**: en consulta los campos no se pueden tocar,
  /// así que una diferencia sólo podría venir de un volcado a medias — y preguntar por
  /// eso sería preguntar por nada.
  /// Si lo de este formulario **ya se guardó**.
  ///
  /// 🚫 **ES LA FALLA DEL 12 DE NOVIEMBRE DE 2026, Y LA PAGÓ EL DUEÑO EN PANTALLA:**
  /// guardaba, leía «Se guardó el expediente del cliente», la pantalla **se quedaba en
  /// `/editar`** y al salir le preguntaban si quería tirar lo que acababa de guardar.
  ///
  /// La causa: guardar navega, navegar pasa por el `onExit` de la ruta, y el `onExit`
  /// pregunta comparando el formulario **contra la respuesta del servidor**. Basta que
  /// una sola comparación no coincida —un texto que el servidor recorta, una fecha que
  /// vuelve con otra forma, un campo que su respuesta no trae— para que la pantalla crea
  /// que hay trabajo sin guardar **justo después de guardarlo**, y entonces la pregunta
  /// bloquea la navegación: se queda en la edición.
  ///
  /// ⚠️ **NO SE ARREGLA AFINANDO LAS COMPARACIONES**, y ésa es la lección: cada una que
  /// se afine deja la siguiente. Lo que se guardó **no es trabajo sin guardar**, lo diga
  /// la respuesta como lo diga. Es el mismo candado que el alta ya tenía.
  ///
  /// Se apaga al volcar —un volcado estrena formulario— así que volver a editar vuelve a
  /// preguntar lo que debe.
  bool _yaSeGuardo = false;

  @override
  bool get hayCambiosSinGuardar {
    if (!widget.editando) return false;
    if (_yaSeGuardo) return false;

    final c = _cliente;
    if (c == null) return false;

    if (_nombre.text.trim() != c.nombreComercial) return true;
    if (_observacionesEscritas != c.observaciones) return true;
    if (_cambioElInicio(c)) return true;

    return !_domicilio.igualA(_domicilioCargado);
  }

  /// D-58 · ¿se movió el inicio de la relación?
  ///
  /// **Se compara por DÍA DE NEGOCIO y no por `DateTime`**, y no es lo mismo: dos
  /// `DateTime` del mismo día con distinta hora son distintos, y el selector devuelve la
  /// medianoche local. Comparar los `DateTime` haría que abrir la edición y no tocar nada
  /// contara como un cambio en cuanto la hora cargada no fuera exactamente 00:00.
  bool _cambioElInicio(Cliente c) {
    final elegido = _inicioElegido;

    if (elegido == null) return c.inicioDeLaRelacion != null;

    return DiaDeNegocio.deFechaLocal(elegido) != c.inicioDeLaRelacion;
  }

  /// Lo escrito en observaciones, **con el vacío como ausencia**: unas observaciones de
  /// cero caracteres no son unas observaciones, y el servidor guarda nulo.
  String? get _observacionesEscritas {
    final texto = _observaciones.text.trim();

    return texto.isEmpty ? null : texto;
  }

  /// **El nombre GUARDADO y no el del campo**: a quien está renombrando, la pregunta le
  /// hablaría de algo que todavía no existe con ese nombre.
  ///
  /// **Y NOMBRA LO QUE SE DESCARTA, no «el expediente».** El expediente tiene partes que
  /// **ya están guardadas** —los contactos y las razones sociales se escriben al momento,
  /// cada uno por su ruta— y decir «el expediente» hacía pensar que también se perdían.
  /// No hay ninguna transacción que abarque la pantalla: lo que «Cancelar» descarta son
  /// los datos del cliente y su domicilio de referencia, que es exactamente lo que
  /// compara [hayCambiosSinGuardar].
  @override
  String get queSePierde {
    final nombre = _cliente?.nombreComercial ?? '';
    final cliente = 'los datos del cliente $nombre'.trimRight();

    return '$cliente: sus contactos y razones sociales ya están guardados';
  }

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

    // ===================================================================
    // ESTILO B · PESTAÑAS, elegido por el dueño el 11 de noviembre de 2026
    // ===================================================================
    //
    // Cabecera y pestañas fijas, y sólo rueda el contenido. Esta ficha era **el caso más
    // claro de «página larga sin jerarquía»**: ocho secciones apiladas —ficha,
    // indicadores, generales, domicilio, contactos, entidades fiscales y dos avisos de lo
    // que llega después—, así que para llegar a las razones sociales había que pasar por
    // todo lo demás.
    //
    // **«Guardar» vive en la cabecera**: con pestañas, un botón al pie sólo existiría en
    // la pestaña abierta.
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Volver(onPressed: widget.alVolver),
          const SizedBox(height: AppSpacing.sm),
          _cabecera(cliente),
          const SizedBox(height: AppSpacing.md),
          RisegTabs(
            tabs: const [
              RisegTabItem(label: 'General'),
              RisegTabItem(label: 'Domicilio'),
              RisegTabItem(label: 'Contactos'),
              RisegTabItem(label: 'Razones sociales'),
            ],
            selectedIndex: _pestana,
            onChanged: (i) => setState(() => _pestana = i),
          ),
          const SizedBox(height: AppSpacing.md),
          if (widget.editando) ...[
            // **EL ALCANCE, DICHO DONDE SE VE EN TODA PESTAÑA.** «Guardar» no guarda el
            // expediente entero: los contactos y las razones sociales ya se escribieron
            // solos, cada uno por su ruta. Sin esta línea, el botón promete un acto que
            // abarca la pantalla y no existe ninguna transacción así.
            //
            // Antes vivía junto a los botones del pie; con el estilo B los botones están
            // en la cabecera, y esto va bajo las pestañas para que se lea en las cuatro.
            Text(
              // UNA LÍNEA (12-nov-2026): lo que «Guardar» abarca se dice nombrando las
              // dos pestañas que espera, no enumerando las que no.
              '«Guardar» aplica a General y Domicilio.',
              style: AppTypography.caption.copyWith(
                color: context.colors.textMuted,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          Expanded(
            child: SingleChildScrollView(
              child: switch (_pestana) {
                0 => _pestanaGeneral(cliente),
                1 => _pestanaDomicilio(),
                2 => SeccionDeContactos(
                  repositorio: widget.repositorio,
                  empresaId: widget.empresaId,
                  clienteId: widget.clienteId,
                  puedeAdministrar: widget.capacidades.puedeModificar,
                  guardia: widget.guardia,
                ),
                _ => SeccionDeEntidadesFiscales(
                  repositorio: widget.repositorio,
                  empresaId: widget.empresaId,
                  clienteId: widget.clienteId,
                  puedeAdministrar: widget.capacidades.puedeModificar,
                  guardia: widget.guardia,
                  // LA CABECERA SE ENTERA, y hace falta: la razón social y el RFC de
                  // arriba sólo se muestran con **una** entidad activa, así que añadir,
                  // archivar o reactivar una puede hacerlos aparecer o desaparecer.
                  alCambiar: _recargarLasEntidades,
                ),
              },
            ),
          ),
        ],
      ),
    );
  }

  /// La cabecera: quién es, cómo está, qué se puede hacer y cuánto.
  Widget _cabecera(Cliente cliente) {
    final e = _unicaEntidadActiva;
    final i = _indicadores;

    return RisegExpedienteHeader(
      titulo: cliente.nombreComercial,
      subtitulo: cliente.codigo,
      identidad: _LogotipoOIniciales(cliente: cliente, logotipo: _logotipo),
      insignias: [_InsigniaDeEstatusDeLaFicha(cliente: cliente)],
      acciones: [
        if (widget.editando) ...[
          RisegButton(
            label: 'Cancelar',
            variant: RisegButtonVariant.secondary,
            onPressed: _guardando ? null : () => widget.alIrADentro(null),
          ),
          RisegButton(
            label: 'Guardar',
            loading: _guardando,
            onPressed: _guardando ? null : _guardar,
          ),
        ] else if (widget.capacidades.puedeModificar) ...[
          RisegButton(
            label: 'Editar logotipo',
            icon: Icons.image_outlined,
            variant: RisegButtonVariant.secondary,
            onPressed: _guardando ? null : _editarLogotipo,
          ),
          RisegButton(
            label: 'Cambiar estatus',
            icon: Icons.swap_horiz,
            variant: RisegButtonVariant.secondary,
            onPressed: _guardando ? null : _cambiarEstatus,
          ),
          RisegButton(
            label: 'Editar',
            icon: Icons.edit_outlined,
            onPressed: _guardando ? null : () => widget.alIrADentro('editar'),
          ),
        ],
      ],
      cifras: [
        // LA RAZÓN SOCIAL Y EL RFC SÓLO CON **UNA** ENTIDAD FISCAL ACTIVA: con 0 o 2+
        // sería ambiguo, y es la regla del escritorio. La ficha no elige una, y enseñar
        // «la primera» sería inventar con qué razón social se factura.
        if (e != null)
          RisegCifra(
            'Razón social',
            e.razonSocial,
            // SIN RFC SE DICE, porque es opcional al dar de alta la entidad y
            // **obligatorio para facturar**: un hueco en blanco no avisaría.
            nota: e.rfc ?? 'Sin RFC registrado',
            // LA LLAVE ES PARA LAS PRUEBAS, y hace falta de verdad: la razón social sale
            // aquí y otra vez en la lista de razones sociales, así que una prueba que
            // buscara el texto a secas no podría distinguir «la ficha la muestra» de «la
            // lista la lista».
            clave: claveDeLaEntidadDeLaFicha,
          ),
        // SI NO SE PUDIERON LEER, SE DICE. Un «0 servicios» inventado aquí sería un dato
        // falso con la forma de un dato.
        if (i == null)
          const RisegCifra('Indicadores', 'No se pudieron leer')
        else ...[
          RisegCifra('Servicios activos', '${i.serviciosActivos}'),
          RisegCifra(
            'Importe mensual contratado',
            // VACÍO NO ES CERO: sin condiciones vigentes no hay importe, y un `$0.00`
            // diría que se contrató algo por cero pesos.
            i.importeMensual.isEmpty
                ? 'Sin condiciones vigentes'
                : i.importeMensual.map((m) => m.enPantalla).join(' · '),
            nota: 'Sin IVA, de los servicios no terminados.',
          ),
        ],
      ],
    );
  }

  /// En qué pestaña cae el primer error, para abrirla antes de pintarlo.
  int _pestanaDeLosErrores(Map<String, String> faltantes) =>
      faltantes.keys.any((k) => k.startsWith('address.')) ? 1 : 0;

  /// **General:** lo que se corrige, lo que sólo se lee, y lo que llega después.
  Widget _pestanaGeneral(Cliente cliente) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _datosGenerales(cliente),
      const SizedBox(height: AppSpacing.md),
      _loQueNoSeEdita(),
      const SizedBox(height: AppSpacing.md),
      // ⚠️ **SIN REPOSITORIO NO HAY TARJETA, y no es un detalle de pruebas:** una tarjeta
      // que no puede cargar nada se quedaría con el indicador puesto **para siempre**, y
      // un indicador que no se apaga parece lentitud y no ausencia. Es la misma lección
      // de D-74, aplicada antes de que la pague nadie.
      if (widget.repositorioDeServicios != null) ...[
        _serviciosDelCliente(),
        const SizedBox(height: AppSpacing.md),
      ],
      const _LlegaDespues(
        titulo: 'Portales',
        mensaje:
            'Los portales del cliente llegan con su propia subetapa, y exigen un '
            'permiso aparte que el Maestro no hereda.',
        icono: Icons.vpn_key_outlined,
      ),
    ],
  );

  /// **Los servicios de este cliente**, con acceso a cada uno.
  ///
  /// ## Por qué la lista y no sólo un botón
  ///
  /// Aquí había un hueco que decía «los servicios se ven en Servicios, filtrando por él;
  /// verlos aquí dentro **llega con la cobertura del módulo**» — jerga, y un pendiente
  /// sin número. El dueño lo marcó el 12 de noviembre de 2026 y pidió elegir entre la
  /// lista o un botón.
  ///
  /// **Es la lista**, y la razón es la pregunta que trae a alguien a esta pantalla: «¿qué
  /// le estamos prestando a este cliente?». Un botón la contesta **mandándote a otro
  /// sitio**, y al volver has perdido dónde estabas. La lista la contesta aquí, y el
  /// botón se queda para cuando hay más de las que caben.
  ///
  /// ⚠️ **SE PIDEN SEIS PARA ENSEÑAR CINCO**, que es cómo se sabe si hay más sin contar:
  /// el listado pagina por cursor y **no devuelve totales** —decisión de D-67—, así que
  /// preguntar «cuántos son» costaría traerlos todos.
  Widget _serviciosDelCliente() {
    final servicios = _servicios;

    return RisegTarjeta(
      titulo: 'Servicios del cliente',
      alDerecha: widget.alVerSusServicios == null
          ? null
          : RisegButton(
              label: 'Ver en Servicios',
              variant: RisegButtonVariant.secondary,
              size: RisegButtonSize.compact,
              icon: Icons.open_in_new,
              onPressed: widget.alVerSusServicios,
            ),
      hijo: switch (servicios) {
        // NULO ES «TODAVÍA NO LLEGARON» Y VACÍO ES «NO TIENE», y se dicen distinto.
        null => const Padding(
          padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: Center(child: CircularProgressIndicator()),
        ),
        [] => const RisegDatoEnLinea(
          etiqueta: 'Servicios',
          valor: null,
          vacioDice: 'Este cliente todavía no tiene servicios',
        ),
        _ => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final s in servicios.take(_cuantosServiciosSeEnsenan))
              RisegDatoEnLinea(
                etiqueta: s.codigo,
                valor: s.nombre,
                alFinal: Wrap(
                  spacing: AppSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (s.estado case final e?)
                      RisegStatusBadge(
                        label: e.nombre,
                        tone: switch (e) {
                          EstatusDeServicio.activo => RisegStatusTone.success,
                          EstatusDeServicio.suspendido =>
                            RisegStatusTone.warning,
                          EstatusDeServicio.terminado => RisegStatusTone.neutral,
                        },
                      ),
                    // LA MISMA INSIGNIA TEMPORAL QUE EL LISTADO Y EL EXPEDIENTE, del
                    // mismo sitio: «Termina el…» a treinta días, y en un terminado
                    // cuándo terminó.
                    if (insigniaTemporalDe(
                      hoy: widget.hoy(),
                      estatus: s.estatus,
                      condicionTemporal: s.condicionTemporal,
                      termino: s.termino,
                    )
                        case final t?)
                      t.pintar(),
                    if (widget.alAbrirServicio case final abrir?)
                      RisegButton(
                        label: 'Abrir',
                        variant: RisegButtonVariant.secondary,
                        size: RisegButtonSize.compact,
                        onPressed: () => abrir(s.id),
                      ),
                  ],
                ),
              ),
            if (servicios.length > _cuantosServiciosSeEnsenan) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Y más. Ábrelos en Servicios.',
                style: AppTypography.caption.copyWith(
                  color: context.colors.textMuted,
                ),
              ),
            ],
          ],
        ),
      },
    );
  }

  /// **Domicilio de referencia:** en consulta como texto, en edición los diez campos.
  Widget _pestanaDomicilio() => RisegTarjeta(
    titulo: 'Domicilio de referencia',
    // LA LETRA CHICA DICE LAS DOS REGLAS, y la segunda es de esta pantalla: el servidor
    // no tiene forma de borrar un domicilio, así que una vez registrado sólo se corrige.
    // Callarlo dejaría que se descubriera con un «Falta la calle.».
    nota: !widget.editando
        ? 'De referencia: no es donde se presta un servicio.'
        : _domicilioCargado == null
        ? 'Opcional: si lo dejas todo vacío, no se guarda domicilio.'
        : 'Una vez registrado, el domicilio se corrige: no se puede quitar desde aquí.',
    hijo: widget.editando
        ? SeccionDeDomicilio(
            campos: _domicilio,
            habilitado: _sePuedeEscribir,
            // ⚠️ **LOS FALTANTES LOS CALCULA LA PANTALLA**, y hasta el 11 de noviembre de
            // 2026 esto iba vacío con esta razón escrita: la respuesta del domicilio de un
            // cliente trae **un mensaje** —«Falta la colonia.»— y no una lista de campos
            // señalados, al contrario que la del expediente de una sucursal.
            //
            // Eso sigue siendo verdad, y la conclusión era la mala: con un solo mensaje
            // por intento, tres campos vacíos son **tres guardados** y tres avisos que se
            // van solos.
            erroresPorCampo: _faltantes,
            focos: _focos,
            // SIN TÍTULO: ya lo pone la tarjeta, y repetirlo lo diría dos veces.
            titulo: '',
            descripcion: '',
          )
        : DomicilioEnTexto(direccion: _domicilioCargado),
  );

  /// Lee **los servicios de este cliente**, si quien montó la pantalla dio el repositorio.
  ///
  /// Pide **uno más de los que se enseñan** para saber si hay más sin contar: el listado
  /// pagina por cursor y no devuelve totales (D-67).
  ///
  /// ⚠️ **UN FALLO AQUÍ NO ROMPE LA FICHA**, y por eso se queda en lista vacía: los
  /// servicios son una sección del expediente, no el expediente. La ficha de un cliente
  /// que no se puede consultar porque su listado de servicios falló sería una pantalla
  /// inútil por una tarjeta.
  Future<void> _cargarSusServicios(String id) async {
    final repositorio = widget.repositorioDeServicios;
    if (repositorio == null) return;

    final resultado = await repositorio.listar(
      widget.empresaId,
      clienteId: id,
      limite: _cuantosServiciosSeEnsenan + 1,
    );

    // LA RESPUESTA DE OTRO CLIENTE SE DESCARTA: entre que se pidió y que llegó, la
    // dirección puede haber cambiado.
    if (!mounted || widget.clienteId != id) return;

    setState(() {
      _servicios = resultado.when(
        ok: (p) => p.servicios,
        failure: (_) => const [],
      );
    });
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

  /// Los datos del cliente: **texto en consulta, campos en edición.**
  ///
  /// 🚫 **ERA EL CUARTO PROBLEMA DEL DUEÑO** —«la vista se ve casi igual que la
  /// edición»—, y aquí era el caso más claro: seis cuadros grises deshabilitados en tres
  /// columnas, cada uno con su letra chica debajo. Un cuadro apagado con el dato dentro
  /// **parece un campo que no te dejan tocar**, no un dato.
  Widget _datosGenerales(Cliente cliente) => RisegTarjeta(
    hijo: widget.editando
        ? RisegCuadricula(
            celdas: [
              RisegCelda.media(
                RisegTextField(
                  label: 'Nombre comercial',
                  controller: _nombre,
                  focusNode: _focos['name'],
                  enabled: _sePuedeEscribir,
                  errorText: _faltantes['name'],
                  // LA ÚNICA AYUDA DE LA TARJETA, y dice lo que no se adivina: quien
                  // llega del escritorio espera escribir aquí la razón social.
                  helperText: 'La marca, no la razón social.',
                ),
              ),
              // ✅ D-58 · YA SE EDITA. El servidor aceptaba `startedOn` en el `PATCH`
              // desde siempre; lo que faltaba era el selector, y mientras tanto el campo
              // decía el dato sin dejar corregirlo.
              RisegCelda.media(
                RisegDateField(
                  label: 'Inicio de la relación',
                  value: _inicioElegido,
                  enabled: _sePuedeEscribir,
                  errorText: _faltantes['startedOn'],
                  onChanged: (v) => setState(() => _inicioElegido = v),
                ),
              ),
              RisegCelda.ancha(
                RisegTextField(
                  label: 'Observaciones',
                  controller: _observaciones,
                  enabled: _sePuedeEscribir,
                  maxLines: 3,
                  helperText: 'El buscador del listado también mira aquí.',
                ),
              ),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RisegDatoEnLinea(
                etiqueta: 'Inicio de la relación',
                valor: _inicioElegido == null
                    ? null
                    : fechaDeNegocioCorta(
                        DiaDeNegocio.deFechaLocal(_inicioElegido!),
                      ),
              ),
              RisegDatoEnLinea(
                etiqueta: 'Observaciones',
                valor: cliente.observaciones,
                vacioDice: 'Sin observaciones',
              ),
            ],
          ),
  );

  /// Lo que **no se edita nunca**, en los dos modos y como texto.
  ///
  /// El folio lo asigna el servidor y **no viaja en ningún cuerpo**; las dos fechas las
  /// escribe él. Pintarlos como cuadros deshabilitados sólo invitaba a intentar escribir
  /// en ellos.
  ///
  /// ⚠️ **«ALTA EN EL SISTEMA» E «INICIO DE LA RELACIÓN» ESTÁN LAS DOS A PROPÓSITO**
  /// (D-58): una dice cuándo se capturó la fila y la otra cuándo empezó el negocio. Usar
  /// una por la otra falsea la antigüedad de la relación o la historia de la captura.
  Widget _loQueNoSeEdita() => RisegTarjeta(
    titulo: 'Registro',
    hijo: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RisegDatoEnLinea(etiqueta: 'Folio', valor: _folio.text),
        RisegDatoEnLinea(
          etiqueta: 'Alta en el sistema',
          valor: _creado.text,
        ),
        RisegDatoEnLinea(
          etiqueta: 'Última actualización',
          valor: _actualizado.text,
        ),
      ],
    ),
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

    final cambioElNombre = nombre != cliente.nombreComercial;
    final cambiaronLasObservaciones =
        _observacionesEscritas != cliente.observaciones;
    final cambioElInicio = _cambioElInicio(cliente);
    final cambioElCliente =
        cambioElNombre || cambiaronLasObservaciones || cambioElInicio;
    final cambioElDomicilio = !_domicilio.igualA(_domicilioCargado);

    // ⚠️ **LO QUE FALTA, COMPLETO Y EN SU CAMPO** (11 de noviembre de 2026). Antes eran
    // tres puertas en fila —el nombre, la fecha en un aviso abajo, y el domicilio al
    // servidor—, así que tres campos vacíos eran tres intentos.
    //
    // ⚠️ **EL DOMICILIO SE MIRA SÓLO SI CAMBIÓ:** el que vino del servidor ya pasó por
    // sus reglas, y una fila vieja que no las cumpliera bloquearía corregir el nombre.
    final faltantes = <String, String>{
      // EL NOMBRE VACÍO SE PARA AQUÍ: el servidor también lo rechaza, pero con el campo
      // en blanco no hace falta ir a preguntarlo.
      if (nombre.isEmpty) 'name': 'Falta el nombre comercial.',
      // D-58 · VACIARLO NO SE MANDA. El servidor **exige** la fecha de inicio, así que un
      // `PATCH` sin ella respondería «Falta el inicio de la relación», que es cierto y no
      // explica qué pasa. Se dice aquí, en el campo — antes salía en un aviso abajo, que
      // obliga a buscar cuál de los campos es.
      //
      // ⚠️ **ES UNA RED Y NO UN CAMINO**, y conviene dejarlo escrito para que nadie lo
      // busque en una prueba de pantalla: `RisegDateField` no tiene con qué **quitar** la
      // fecha —su `onChanged` entrega un `DateTime` que no puede ser nulo—, así que hoy
      // esto no se puede provocar desde la pantalla. Se queda porque el día que el campo
      // tenga un aspa, el aviso ya está en su sitio.
      if (cambioElInicio && _inicioElegido == null) 'startedOn':
        'No se puede quitar: elige una fecha.',
      if (cambioElDomicilio) ..._domicilio.faltantes,
    };

    if (faltantes.isNotEmpty) {
      setState(() {
        _faltantes = faltantes;
        // ⚠️ **LA PESTAÑA SE MUEVE AL ERROR:** con el domicilio en su pestaña, señalar la
        // colonia vacía mientras se mira «General» pintaría el error donde nadie está
        // mirando, y «Guardar» parecería no hacer nada.
        _pestana = _pestanaDeLosErrores(faltantes);
      });
      _focos.llevarLaVistaAlPrimerError(faltantes);

      return;
    }

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
      _faltantes = const {};
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
        // D-58 · `deFechaLocal` y NO `DiaDeNegocio.de`: lo que la persona eligió es un día
        // del calendario, y aplicarle el desplazamiento de zona lo correría un día.
        inicio: cambioElInicio
            ? DiaDeNegocio.deFechaLocal(_inicioElegido!)
            : null,
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

    // ⚠️ **LA GUARDIA SE APAGA ANTES DE NAVEGAR**, y el orden es la mitad del arreglo:
    // `alIrADentro` pasa por el `onExit` de la ruta, así que si se apagara después, la
    // pregunta saldría con el formulario ya guardado y dejaría la pantalla en la edición.
    setState(() {
      _guardando = false;
      _yaSeGuardo = true;
    });

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
  /// ⚠️ **TERMINAR LA RELACIÓN NO BORRA NADA Y TIENE UNA CONSECUENCIA, UNA SOLA**: un
  /// cliente que no está activo **no admite servicios nuevos**. El diálogo lo dice antes
  /// de confirmar, no después.
  ///
  /// <b>LO QUE NO BLOQUEA, y el aviso lo decía mal hasta el 27 de octubre de 2026:</b>
  /// los servicios que ya tiene **se siguen pudiendo editar**. El texto decía «ni editar
  /// los que tiene», que contradice la decisión del dueño —se bloquea crear, no editar— y
  /// además describía una restricción que el servidor no aplica. Un aviso que promete
  /// más de lo que pasa es peor que no avisar: enseña a desconfiar de los avisos.
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
                'nuevos. Los que ya tiene se siguen pudiendo editar.',
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

/// El logotipo del cliente, **con las iniciales como respaldo**.
///
/// ⚠️ **`Image.network` NO SIRVE** (IF-5): el token no viaja en un `<img>` y la ruta
/// responde `attachment`, así que los bytes los pide el repositorio con el cliente
/// autenticado y esto los pinta con `Image.memory`.
class _LogotipoOIniciales extends StatelessWidget {
  const _LogotipoOIniciales({required this.cliente, required this.logotipo});

  final Cliente cliente;
  final Uint8List? logotipo;

  @override
  Widget build(BuildContext context) {
    final bytes = logotipo;

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: SizedBox(
        width: 48,
        height: 48,
        child: bytes == null
            ? RisegIniciales(
                id: cliente.id,
                nombre: cliente.nombreComercial,
                lado: 48,
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
                      lado: 48,
                    ),
                  ),
                ),
              ),
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
/// ⚠️ **YA NO SE PINTA AQUÍ: son las CIFRAS DE LA CABECERA** desde el estilo B. Dos
/// tarjetas grandes entre la ficha y los datos eran justo lo que empujaba el resto de la
/// pantalla hacia abajo, y lo que dicen —dos números y un importe— se lee mejor al lado
/// del nombre, que es donde se mira primero.
///
/// **Personal asignado NO está** y llega con la cobertura operativa. No sale en cero:
/// **ausencia nunca es cero**, y un cero diría que el cliente no tiene gente.
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
