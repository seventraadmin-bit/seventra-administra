import 'package:flutter/material.dart';

// LAS CAPACIDADES VIENEN DEL SHELL, no del catálogo de permisos: esta feature no puede
// importar `PermisoCompany` —hay un guardia que lo impide— y no le hace falta.
import '../../../../app/shell/apartados_web.dart' show CapacidadesDeModulo;
import '../../../../core/design_system/design_system_web.dart';
import '../../../../core/direcciones/campos_de_domicilio.dart';
import '../../../../core/direcciones/direccion.dart';
import '../../../../core/direcciones/seccion_de_domicilio.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/error/mensajes_humanos.dart';
import '../../../../core/error/rechazo_del_servidor.dart';
import '../../../../core/error/result.dart';
import '../../../../core/fechas/dia_de_negocio.dart';
import '../../../../core/fechas/fecha_en_pantalla.dart';
import '../../../../core/trabajo_sin_guardar/declara_su_trabajo_sin_guardar.dart';
import '../../../../core/trabajo_sin_guardar/guardia_de_salida.dart';
import '../../../personal/web/datos/empleados_repositorio_http.dart';
import '../../../personal/web/modelos/empleado_elegible.dart';
import '../../../organizacion/web/datos/sucursales_repositorio_http.dart';
import '../../../organizacion/web/modelos/sucursal.dart';
import '../datos/clientes_repositorio_http.dart';
import '../datos/servicios_repositorio_http.dart';
import '../modelos/contacto.dart';
import '../modelos/entidad_fiscal.dart';
import '../modelos/servicio.dart';
import 'insignia_temporal.dart';

/// **Cuanto hay de un servicio, en un solo sitio**: su ficha, sus indicadores, sus datos
/// generales, su domicilio operativo, su supervisor y sus tres vínculos.
///
/// ## Consultar y editar son DOS DIRECCIONES
///
/// `/comercial/servicios/<id>` y `/comercial/servicios/<id>/editar`, igual que el
/// expediente de un cliente y por la misma razón: **consultar no es cambiar**. Así
/// «atrás» devuelve de la edición a la consulta, el enlace de un servicio se puede pegar
/// sin abrir un formulario, y el `onExit` de la ruta de edición es el que pregunta por el
/// trabajo sin guardar (D-56).
///
/// ## Qué entra en «Guardar» y qué NO, que es la decisión de diseño de esta pantalla
///
/// En el formulario viven **sólo los campos que `PATCH /services/{id}` corrige con un
/// motivo**: nombre, tipo y observaciones, más el domicilio operativo por su `PUT`. Todo
/// lo demás —el estatus, el término, el supervisor y los tres vínculos— tiene **su propia
/// ruta y sus propias reglas**, así que son acciones y no campos.
///
/// 🚫 **Y no es una preferencia estética.** Meter el supervisor en el formulario obligaría
/// a pedir un motivo que su ruta no pide, y meter la entidad fiscal obligaría a lo
/// contrario: pedirlo siempre cuando el servidor sólo lo exige al **cambiarla** (R9). Un
/// formulario que junta reglas distintas acaba mintiendo sobre una de ellas.
///
/// ## Guardar son hasta DOS peticiones, y el servidor no las junta
///
/// El servicio va por `PATCH /services/{id}` **con motivo** y el domicilio por
/// `PUT /services/{id}/address` **sin él**. De ahí tres reglas, las mismas que el
/// expediente de un cliente:
///
///  1. **sólo viaja lo que cambió** —el servidor rechaza un `PATCH` que no cambia nada—;
///  2. **si la segunda falla, la primera ya ocurrió**, y se dice qué quedó guardado. No se
///     intenta deshacer: deshacer una corrección es otra corrección, con su motivo;
///  3. **el domicilio operativo se CORRIGE y no se quita**: desde la 0059 no existe
///     servicio sin domicilio, y el servidor no publica un `DELETE`.
///
/// <b>Importa `design_system_web.dart`, NUNCA el barrel completo.</b> El completo exporta
/// un componente que lee del disco con `dart:io` y rompería la build web.
class ExpedienteServicioWebScreen extends StatefulWidget {
  const ExpedienteServicioWebScreen({
    required this.repositorio,
    required this.clientes,
    required this.sucursales,
    required this.empleados,
    required this.empresaId,
    required this.servicioId,
    required this.capacidades,
    required this.puedeElegirSupervisor,
    required this.guardia,
    required this.editando,
    required this.alIrADentro,
    required this.alVolver,
    required this.alConocerElNombre,
    super.key,
  });

  final ServiciosRepositorioHttp repositorio;

  /// El repositorio de **clientes**, por dos cosas que son del cliente y no del servicio:
  /// sus **contactos** y sus **entidades fiscales**, que son lo que los dos selectores de
  /// vínculo ofrecen.
  final ClientesRepositorioHttp clientes;

  /// Las sucursales **propias**, para el vínculo administrativo.
  ///
  /// 🚫 **No es dónde se presta el servicio** —eso es el domicilio operativo—: `Branch` es
  /// destino administrativo y `Service` el operativo, que es la regla fundamental de
  /// Personal vista desde el otro lado.
  final SucursalesRepositorioHttp sucursales;

  /// Los empleados, **sólo para el selector del supervisor**.
  final EmpleadosRepositorioHttp empleados;

  final String empresaId;

  /// **El id de la URL**, y de la URL sale sólo esto: dónde estás. Lo que se puede hacer
  /// sigue saliendo del contexto que confirmó el servidor.
  final String servicioId;

  final CapacidadesDeModulo capacidades;

  /// Si a quien mira se le puede **ofrecer el selector** de supervisor.
  ///
  /// ⚠️ **Se resuelve en el SHELL y llega resuelto**, por decisión del dueño, y la razón
  /// es que son **dos módulos**: ver el supervisor es `clients_services.read` —la ruta es
  /// del servicio—, pero **elegirlo** obliga a listar empleados, y eso es
  /// `personal.read`. Quien tenga Comercial y no Personal **ve** quién responde por el
  /// servicio y no se le ofrece cambiarlo: enseñar el selector sería enseñar una puerta
  /// que responde 403.
  ///
  /// Y **no sustituye a `capacidades`**: para cambiarlo hacen falta las dos cosas,
  /// `clients_services.manage` para escribir el vínculo y esto para poder elegir a quién.
  final bool puedeElegirSupervisor;

  /// D-56 · dónde se registra que hay trabajo sin guardar. **Esta pantalla SÍ lo usa**.
  final GuardiaDeSalida guardia;

  /// Si la dirección dice que se está editando. **No es estado de la pantalla** (D-39).
  final bool editando;

  /// Pide cambiar de modo. `null` vuelve a la consulta, `'editar'` abre la edición.
  ///
  /// **La pantalla pide, no navega:** quien conoce la ruta del apartado es el portón.
  final void Function(String? aDonde) alIrADentro;

  /// Vuelve al listado.
  final VoidCallback alVolver;

  /// Publica cómo se llama el servicio, **para el rastro**. Sale de la fila cargada y
  /// **nunca de la URL**, donde quedaría viejo en cuanto alguien lo renombrara.
  final void Function(String id, String nombre) alConocerElNombre;

  @override
  State<ExpedienteServicioWebScreen> createState() =>
      _ExpedienteServicioWebScreenState();
}

class _ExpedienteServicioWebScreenState
    extends State<ExpedienteServicioWebScreen>
    with DeclaraSuTrabajoSinGuardar<ExpedienteServicioWebScreen> {
  @override
  GuardiaDeSalida get guardia => widget.guardia;

  /// Lo que el servidor devolvió la última vez que esta pantalla y él coincidieron.
  /// **Es la base de la comparación de cambios**, no una copia de cortesía.
  Servicio? _servicio;
  IndicadoresDeServicio? _indicadores;
  Direccion? _domicilioCargado;
  SupervisorDelServicio? _supervisor;

  List<TipoDeServicio> _tipos = const [];
  List<ContactoDeCliente> _contactos = const [];
  List<EntidadFiscal> _entidades = const [];
  List<Sucursal> _sucursales = const [];

  Failure? _fallo;
  bool _cargando = true;
  bool _guardando = false;

  final _nombre = TextEditingController();
  final _observaciones = TextEditingController();
  final _domicilio = CamposDeDomicilio();

  /// Los de **sólo lectura**.
  ///
  /// ⚠️ **SON CAMPOS DEL ESTADO Y NO SE CREAN EN EL `build`**: un `TextEditingController`
  /// nuevo en cada repintado se queda sin liberar, y aquí hay un repintado por tecla.
  final _folio = TextEditingController();
  final _inicio = TextEditingController();
  final _creado = TextEditingController();
  final _actualizado = TextEditingController();

  String? _tipoId;

  /// Lo que falta por capturar, **por clave del servidor**, para señalarlo en su cuadro.
  ///
  /// Era un `String? _errorDeNombre` hasta el 11 de noviembre de 2026, y con eso los
  /// campos del domicilio no se podían marcar: el único que podía ponerse en rojo era el
  /// nombre, y los demás se descubrían de uno en uno en el aviso del servidor.
  Map<String, String> _faltantes = const {};

  /// Los nodos de foco, en el orden de la pantalla: con el botón al final, un error
  /// arriba se pintaba donde nadie estaba mirando.
  final _focos = RisegFocosDeFormulario(const [
    'name',
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
    _cargar();
  }

  @override
  void dispose() {
    for (final c in [
      _nombre,
      _observaciones,
      _folio,
      _inicio,
      _creado,
      _actualizado,
    ]) {
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
  void didUpdateWidget(ExpedienteServicioWebScreen anterior) {
    super.didUpdateWidget(anterior);

    // ⚠️ **CAMBIAR DE SERVICIO SIN DESMONTAR LA PANTALLA PASA DE VERDAD**: las dos
    // direcciones son la misma ruta con otro `<id>`, así que go_router reutiliza este
    // `State`. Sin esto, el expediente seguiría enseñando el servicio anterior con la URL
    // del nuevo.
    if (anterior.servicioId != widget.servicioId) _cargar();

    // SALIR DE LA EDICIÓN SIN GUARDAR DEVUELVE LO CARGADO. La pregunta la hizo ya el
    // `onExit` de la ruta; si llegó aquí, es que se eligió salir.
    if (anterior.editando && !widget.editando) _volcar();
  }

  // =========================================================================
  // Cargar
  // =========================================================================

  /// Las lecturas de la ficha, **en paralelo**.
  ///
  /// ⚠️ **SÓLO EL SERVICIO PUEDE IMPEDIR PINTAR.** Si fallan los indicadores, los tipos o
  /// cualquiera de las tres listas de los selectores, la ficha sale con lo que hay: un
  /// servicio que no se puede consultar porque su lista de sucursales no bajó sería una
  /// pantalla inútil por un selector.
  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _fallo = null;
    });

    final servicio = await widget.repositorio.ver(
      empresaId: widget.empresaId,
      servicioId: widget.servicioId,
    );

    if (!mounted) return;

    final ficha = servicio.when<Servicio?>(ok: (s) => s, failure: (_) => null);

    if (ficha == null) {
      setState(() {
        _fallo = servicio.when(ok: (_) => null, failure: (f) => f);
        _cargando = false;
      });

      return;
    }

    // EL NOMBRE PARA EL RASTRO, en cuanto se conoce y de los datos.
    widget.alConocerElNombre(ficha.id, ficha.nombre);

    final resto = await Future.wait([
      widget.repositorio.indicadores(
        empresaId: widget.empresaId,
        servicioId: widget.servicioId,
      ),
      widget.repositorio.domicilio(
        empresaId: widget.empresaId,
        servicioId: widget.servicioId,
      ),
      widget.repositorio.tipos(widget.empresaId, usados: null),
      widget.clientes.listarContactos(
        empresaId: widget.empresaId,
        clienteId: ficha.clienteId,
      ),
      widget.clientes.listarEntidadesFiscales(
        empresaId: widget.empresaId,
        clienteId: ficha.clienteId,
      ),
      widget.sucursales.listar(widget.empresaId),
      // EL SUPERVISOR SE PIDE SÓLO SI LA FICHA DICE QUE HAY UNO: su ruta responde 404
      // cuando no, y pedirlo igual sería pagar una consulta para que conteste «no hay»
      // algo que la ficha ya dijo.
      if (ficha.supervisorEmpleadoId != null)
        widget.repositorio.supervisor(
          empresaId: widget.empresaId,
          servicioId: widget.servicioId,
        ),
    ]);

    if (!mounted) return;

    setState(() {
      _servicio = ficha;
      _indicadores = resto[0].when<IndicadoresDeServicio?>(
        ok: (v) => v as IndicadoresDeServicio?,
        failure: (_) => null,
      );
      _domicilioCargado = resto[1].when<Direccion?>(
        ok: (v) => v as Direccion?,
        failure: (_) => null,
      );
      _tipos = resto[2].when<List<TipoDeServicio>>(
        ok: (v) => v as List<TipoDeServicio>,
        failure: (_) => const [],
      );
      _contactos = resto[3].when<List<ContactoDeCliente>>(
        ok: (v) => v as List<ContactoDeCliente>,
        failure: (_) => const [],
      );
      _entidades = resto[4].when<List<EntidadFiscal>>(
        ok: (v) => v as List<EntidadFiscal>,
        failure: (_) => const [],
      );
      _sucursales = resto[5].when<List<Sucursal>>(
        ok: (v) => v as List<Sucursal>,
        failure: (_) => const [],
      );
      _supervisor = resto.length > 6
          ? resto[6].when<SupervisorDelServicio?>(
              ok: (v) => v as SupervisorDelServicio?,
              failure: (_) => null,
            )
          : null;
      _cargando = false;
    });

    _volcar();
  }

  /// Vuelca lo cargado en los campos. **Es la base de la comparación**, así que se llama
  /// al cargar y al salir de la edición sin guardar.
  void _volcar() {
    final s = _servicio;
    if (s == null) return;

    _nombre.text = s.nombre;
    _observaciones.text = s.observaciones ?? '';
    _folio.text = s.codigo;
    _inicio.text = switch (s.inicio) {
      final d? => fechaDeNegocioCorta(d),
      null => '—',
    };
    _creado.text = fechaYHora(s.creadoEn);
    _actualizado.text = fechaYHora(s.actualizadoEn);
    _tipoId = s.tipoId;
    _domicilio.volcar(_domicilioCargado);

    setState(() => _faltantes = const {});
  }

  /// Las observaciones escritas, o nulo si quedaron vacías.
  String? get _observacionesEscritas {
    final texto = _observaciones.text.trim();

    return texto.isEmpty ? null : texto;
  }

  // =========================================================================
  // D-56 · lo que se perdería
  // =========================================================================

  /// ⚠️ **SÓLO EDITANDO.** En consulta no hay nada escrito que perder, y preguntar al
  /// salir de una ficha que nadie tocó enseña a ignorar la pregunta.
  @override
  bool get hayCambiosSinGuardar {
    if (!widget.editando) return false;

    final s = _servicio;
    if (s == null) return false;

    return _nombre.text.trim() != s.nombre ||
        _observacionesEscritas != s.observaciones ||
        _tipoId != s.tipoId ||
        !_domicilio.igualA(_domicilioCargado);
  }

  /// **El nombre sale del servicio CARGADO, no del campo**: a quien está renombrando, la
  /// pregunta le hablaría de algo que todavía no existe con ese nombre.
  @override
  String get queSePierde => switch (_servicio) {
    final s? => 'el servicio ${s.codigo} ${s.nombre}',
    null => 'este servicio',
  };

  // =========================================================================
  // Pintar
  // =========================================================================

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Scaffold(
      backgroundColor: colors.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: _cuerpo(),
        ),
      ),
    );
  }

  Widget _cuerpo() {
    if (_cargando) return const Center(child: CircularProgressIndicator());

    if (_fallo case final f?) {
      return RisegEmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'No se pudo cargar el servicio',
        message: f.message,
        primaryAction: RisegButton(
          label: 'Intentar de nuevo',
          onPressed: _cargar,
        ),
        secondaryAction: RisegButton(
          label: 'Volver a Servicios',
          variant: RisegButtonVariant.secondary,
          onPressed: widget.alVolver,
        ),
      );
    }

    final s = _servicio;
    if (s == null) return const SizedBox.shrink();

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Volver(onVolver: widget.alVolver),
          const SizedBox(height: AppSpacing.sm),
          _Cabecera(
            servicio: s,
            editando: widget.editando,
            puedeEditar: widget.capacidades.puedeModificar,
            guardando: _guardando,
            onEditar: () => widget.alIrADentro('editar'),
            onEstatus: _cambiarEstatus,
          ),
          const SizedBox(height: AppSpacing.md),
          if (_indicadores case final i?) ...[
            _Indicadores(
              indicadores: i,
              terminado: s.estado?.esFinalizado ?? false,
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          _datosGenerales(s),
          const SizedBox(height: AppSpacing.md),
          SeccionDeDomicilio(
            titulo: 'Domicilio operativo',
            campos: _domicilio,
            habilitado: widget.editando && !_guardando,
            erroresPorCampo: _faltantes,
            focos: _focos,
            // 🚫 **NINGÚN NÚMERO DE MIGRACIÓN EN LA PANTALLA.** Esto decía «desde la 0059
            // no existe un servicio sin domicilio operativo», y el dueño lo leyó en el
            // ensayo: a quien captura no le dice nada y lo vigila ahora
            // `textos_sin_jerga_interna_test.dart`.
            descripcion:
                'Dónde se presta el servicio. Se corrige, pero no se puede dejar '
                'vacío.',
          ),
          const SizedBox(height: AppSpacing.md),
          _SeccionDelTermino(
            servicio: s,
            puedeCambiar: widget.capacidades.puedeModificar && !_guardando,
            onProgramar: _programarTermino,
            onRetirar: _retirarTermino,
          ),
          const SizedBox(height: AppSpacing.md),
          _SeccionDelSupervisor(
            supervisor: _supervisor,
            puedeEscribir: widget.capacidades.puedeModificar && !_guardando,
            puedeElegir: widget.puedeElegirSupervisor,
            onElegir: _elegirSupervisor,
            onQuitar: _quitarSupervisor,
          ),
          const SizedBox(height: AppSpacing.md),
          _vinculos(s),
          if (widget.editando) ...[
            const SizedBox(height: AppSpacing.md),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                RisegButton(
                  label: 'Cancelar',
                  variant: RisegButtonVariant.secondary,
                  onPressed: _guardando
                      ? null
                      : () => widget.alIrADentro(null),
                ),
                const SizedBox(width: AppSpacing.sm),
                RisegButton(
                  label: 'Guardar',
                  loading: _guardando,
                  onPressed: _guardando ? null : _guardar,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _datosGenerales(Servicio s) => RisegFormSection(
    title: 'Datos generales',
    description: 'El cliente queda fijo: no se puede cambiar.',
    grid: true,
    children: [
      RisegTextField(
        label: 'Folio',
        controller: _folio,
        enabled: false,
        helperText: 'Lo asigna el sistema y no cambia.',
      ),
      RisegTextField(
        label: 'Nombre del servicio',
        controller: _nombre,
        focusNode: _focos['name'],
        enabled: widget.editando && !_guardando,
        errorText: _faltantes['name'],
      ),
      RisegSelect<String?>(
        label: 'Tipo de servicio',
        value: _tipoId,
        enabled: widget.editando && !_guardando,
        items: [
          // ⚠️ **EL TIPO ACTUAL SE OFRECE AUNQUE ESTÉ RETIRADO.** Si no, un servicio con
          // un tipo que la empresa desactivó abriría el expediente con el selector en
          // blanco, y guardar cualquier otra corrección le cambiaría el tipo sin que
          // nadie lo pidiera. Un retirado no se puede ELEGIR; el que ya está, se conserva.
          for (final t in _tipos)
            if (t.estaActivo || t.id == s.tipoId)
              RisegSelectItem(
                value: t.id,
                label: t.estaActivo ? t.nombre : '${t.nombre} (retirado)',
              ),
        ],
        onChanged: (v) => setState(() => _tipoId = v),
      ),
      RisegTextField(
        label: 'Fecha de inicio',
        controller: _inicio,
        enabled: false,
        helperText:
            'Desde cuándo opera. Se fija al dar de alta y no se corrige aquí.',
      ),
      RisegTextField(
        label: 'Alta en el sistema',
        controller: _creado,
        enabled: false,
        // D-58 · ES OTRA COSA QUE EL INICIO, y por eso están los dos: una es cuándo
        // empezó a operar el servicio y otra cuándo se capturó la fila.
        helperText: 'Cuándo se capturó. No es la fecha de inicio.',
      ),
      RisegTextField(
        label: 'Última actualización',
        controller: _actualizado,
        enabled: false,
      ),
      RisegTextField(
        label: 'Observaciones',
        controller: _observaciones,
        enabled: widget.editando && !_guardando,
        maxLines: 3,
      ),
    ],
  );

  Widget _vinculos(Servicio s) => RisegFormSection(
    title: 'Vínculos',
    description:
        'A quién se le factura, quién responde por parte del cliente y qué '
        'sucursal propia lo administra.',
    children: [
      _Vinculo(
        etiqueta: 'Entidad fiscal',
        ayuda:
            'A la que se le factura este servicio. Cambiarla o quitarla pide '
            'motivo; la primera asignación no.',
        valor: switch (s.entidadFiscalId) {
          final id? =>
            _entidades
                .where((e) => e.id == id)
                .map((e) => e.razonSocial)
                .firstOrNull ??
                'Asignada',
          null => null,
        },
        puedeCambiar: widget.capacidades.puedeModificar && !_guardando,
        hayDeDonde: _entidades.isNotEmpty,
        vacioDice: 'Este cliente todavía no tiene entidades fiscales.',
        onCambiar: _cambiarEntidadFiscal,
        onQuitar: s.entidadFiscalId == null ? null : _quitarEntidadFiscal,
      ),
      _Vinculo(
        etiqueta: 'Contacto responsable',
        ayuda: 'Del cliente. No decide a quién se le factura, así que no pide motivo.',
        valor: switch (s.contactoResponsableId) {
          final id? =>
            _contactos
                .where((c) => c.id == id)
                .map((c) => c.nombre)
                .firstOrNull ??
                'Asignado',
          null => null,
        },
        puedeCambiar: widget.capacidades.puedeModificar && !_guardando,
        hayDeDonde: _contactos.isNotEmpty,
        vacioDice: 'Este cliente todavía no tiene contactos.',
        onCambiar: _cambiarContacto,
        onQuitar: s.contactoResponsableId == null ? null : _quitarContacto,
      ),
      _Vinculo(
        etiqueta: 'Sucursal administrativa',
        // 🚫 LA FRONTERA, DICHA EN LA PANTALLA: `Branch` es destino administrativo y
        // `Service` el operativo. Dónde se presta es el domicilio de arriba.
        ayuda:
            'La sucursal PROPIA que lo administra. No es dónde se presta el '
            'servicio: eso es el domicilio operativo.',
        valor: switch (s.sucursalAdministrativaId) {
          final id? =>
            _sucursales
                .where((b) => b.id == id)
                .map((b) => b.nombre)
                .firstOrNull ??
                'Asignada',
          null => null,
        },
        puedeCambiar: widget.capacidades.puedeModificar && !_guardando,
        hayDeDonde: _sucursales.isNotEmpty,
        vacioDice: 'La empresa todavía no tiene sucursales.',
        onCambiar: _cambiarSucursal,
        onQuitar: s.sucursalAdministrativaId == null ? null : _quitarSucursal,
      ),
    ],
  );

  // =========================================================================
  // Guardar
  // =========================================================================

  /// Guarda lo que cambió, **y nada más**.
  ///
  /// El motivo se pide **antes** de mandar nada, por lo mismo que el servidor lo valida
  /// primero: no es un campo del formulario, es la condición para corregir.
  Future<void> _guardar() async {
    final s = _servicio;
    if (s == null) return;

    final nombre = _nombre.text.trim();

    final cambioElNombre = nombre != s.nombre;
    final cambioElTipo = _tipoId != null && _tipoId != s.tipoId;
    final cambiaronLasObservaciones = _observacionesEscritas != s.observaciones;

    final cambioElServicio =
        cambioElNombre || cambioElTipo || cambiaronLasObservaciones;
    final cambioElDomicilio = !_domicilio.igualA(_domicilioCargado);

    // ⚠️ **LO QUE FALTA, COMPLETO Y EN SU CAMPO** (11 de noviembre de 2026). Antes sólo
    // se podía señalar el nombre, y los seis campos del domicilio se descubrían de uno en
    // uno: el servidor contesta **el primero que falta y para**.
    //
    // ⚠️ **EL DOMICILIO SE MIRA SÓLO SI CAMBIÓ**, y no es pereza: el que vino del
    // servidor ya pasó por sus reglas, pero una fila vieja —traída del escritorio— podría
    // no cumplirlas, y entonces corregir el NOMBRE se quedaría bloqueado por un código
    // postal que nadie tocó. Lo que se valida es lo que se va a mandar.
    final faltantes = <String, String>{
      if (nombre.isEmpty) 'name': 'Falta el nombre del servicio.',
      if (cambioElDomicilio) ..._domicilio.faltantesSiendoObligatorio,
    };

    if (faltantes.isNotEmpty) {
      setState(() => _faltantes = faltantes);
      _focos.llevarLaVistaAlPrimerError(faltantes);

      return;
    }

    // NADA QUE GUARDAR NO ES UN ERROR: se vuelve a la consulta, que es lo que esa
    // persona quería. Mandar el `PATCH` igual respondería «No hay nada que modificar».
    if (!cambioElServicio && !cambioElDomicilio) {
      widget.alIrADentro(null);

      return;
    }

    final motivo = await mostrarDialogoMotivo(
      context,
      titulo: 'Corregir el servicio',
      etiquetaMotivo: 'Motivo de la corrección',
      confirmarLabel: 'Guardar',
      cancelarLabel: 'Seguir editando',
      errorMotivoRequerido:
          'Falta el motivo. Queda en la bitácora y es lo que explica por qué '
          'cambió este dato.',
    );

    if (motivo == null || !mounted) return;

    setState(() {
      _guardando = true;
      _faltantes = const {};
    });

    // ⚠️ **EL SERVICIO PRIMERO Y EL DOMICILIO DESPUÉS**, y el orden importa: si falla el
    // primero no se ha tocado nada, y si falla el segundo lo que quedó guardado es una
    // corrección con su motivo en la auditoría — algo que se puede leer y rehacer.
    var guardadoElServicio = false;

    if (cambioElServicio) {
      final resultado = await widget.repositorio.corregir(
        empresaId: widget.empresaId,
        servicioId: s.id,
        motivo: motivo,
        // CADA CAMPO VIAJA SÓLO SI CAMBIÓ: mandando los tres «porque están ahí», un
        // cambio de nombre arrastraría unas observaciones que nadie tocó — y el evento
        // de la auditoría diría que también cambiaron.
        nombre: cambioElNombre ? nombre : null,
        tipoId: cambioElTipo ? _tipoId : null,
        observaciones: cambiaronLasObservaciones ? _observacionesEscritas : null,
      );

      if (!mounted) return;

      final fallo = resultado.when<Failure?>(
        ok: (actualizado) {
          _servicio = actualizado;
          guardadoElServicio = true;

          return null;
        },
        failure: (f) => f,
      );

      if (fallo != null) {
        setState(() => _guardando = false);
        mostrarRechazoDelServidor(context, fallo);

        return;
      }
    }

    if (cambioElDomicilio) {
      final direccion = _domicilio.direccion;

      // VACIARLO NO SE MANDA: el servidor no puede borrarlo —no hay `DELETE` y su `PUT`
      // exige los seis obligatorios— y contestaría «Falta la calle.», que es cierto y no
      // explica qué pasa. Se dice aquí.
      if (direccion == null) {
        setState(() => _guardando = false);

        RisegFeedback.showError(
          context,
          guardadoElServicio
              ? 'Se guardaron los datos del servicio. El domicilio operativo no se '
                    'puede quitar: corrígelo o vuelve a escribirlo como estaba.'
              : 'El domicilio operativo no se puede quitar: corrígelo o vuelve a '
                    'escribirlo como estaba.',
        );

        return;
      }

      final resultado = await widget.repositorio.guardarDomicilio(
        empresaId: widget.empresaId,
        servicioId: s.id,
        domicilio: direccion,
      );

      if (!mounted) return;

      final fallo = resultado.when<Failure?>(
        ok: (d) {
          _domicilioCargado = d;

          return null;
        },
        failure: (f) => f,
      );

      if (fallo != null) {
        setState(() => _guardando = false);

        // SE DICE QUÉ SÍ QUEDÓ GUARDADO. Sin eso, quien lea «Falta la colonia.» pensaría
        // que no se guardó nada y volvería a escribir el nombre. Y no se intenta
        // deshacer: deshacer una corrección es otra corrección, con su motivo.
        RisegFeedback.showError(
          context,
          guardadoElServicio
              ? 'Se guardaron los datos del servicio, pero el domicilio no: '
                    '${MensajesHumanos.deMutacion(fallo)}'
              : MensajesHumanos.deMutacion(fallo),
        );

        return;
      }
    }

    if (!mounted) return;

    setState(() => _guardando = false);

    RisegFeedback.showSuccess(context, 'Se guardó el expediente del servicio.');
    widget.alIrADentro(null);
  }

  // =========================================================================
  // El estatus y el término
  // =========================================================================

  Future<void> _cambiarEstatus() async {
    final s = _servicio;
    if (s == null) return;

    final elegido = await showDialog<EstatusDeServicio>(
      context: context,
      builder: (_) => _DialogoDeEstatus(actual: s.estado),
    );

    if (elegido == null || !mounted) return;

    // ⚠️ **TERMINAR EXIGE DECIDIR LA FECHA**, y reactivar un terminado también: el
    // servidor responde `fecha_de_termino_requerida` si no llega. Se pregunta aquí en
    // lugar de dejar que el guardado falle.
    DiaDeNegocio? termino;
    var retirar = false;

    if (elegido == EstatusDeServicio.terminado) {
      final elegida = await _pedirLaFechaDeTermino(
        titulo: 'Terminar el servicio',
        ayuda:
            'Desde cuándo deja de operar. Puede ser hoy o una fecha pasada: lo que '
            'no se admite es programar un término en el futuro desde aquí.',
        propuesta: DiaDeNegocio.hoy().comoFechaLocal,
      );

      if (elegida == null || !mounted) return;
      termino = DiaDeNegocio.deFechaLocal(elegida);
    } else if (s.estado?.esFinalizado ?? false) {
      // REACTIVAR UN TERMINADO DEJA UNA FECHA DE TÉRMINO QUE YA NO APLICA, así que hay
      // que decidir qué pasa con ella. Se retira, que es lo que significa reactivar.
      retirar = s.termino != null;
    }

    final motivo = await mostrarDialogoMotivo(
      context,
      titulo: 'Cambiar el estatus a ${elegido.nombre}',
      etiquetaMotivo: 'Motivo del cambio',
      confirmarLabel: 'Cambiar el estatus',
      cancelarLabel: 'Cancelar',
      errorMotivoRequerido:
          'Falta el motivo. Queda en la bitácora con el estatus anterior y el nuevo.',
      advertencia: elegido == EstatusDeServicio.terminado
          ? 'Un servicio terminado no se puede suspender después. Para volver a '
                'operarlo hay que reactivarlo.'
          : null,
    );

    if (motivo == null || !mounted) return;

    setState(() => _guardando = true);

    final resultado = await widget.repositorio.cambiarEstado(
      empresaId: widget.empresaId,
      servicioId: s.id,
      estatus: elegido,
      motivo: motivo,
      termino: termino,
      retirarTermino: retirar,
    );

    if (!mounted) return;

    resultado.when(
      ok: (actualizado) {
        setState(() {
          _servicio = actualizado;
          _guardando = false;
        });

        RisegFeedback.showSuccess(
          context,
          'El servicio quedó en ${elegido.nombre.toLowerCase()}.',
        );
      },
      failure: (f) {
        setState(() => _guardando = false);
        mostrarRechazoDelServidor(context, f);
      },
    );
  }

  Future<void> _programarTermino() async {
    final s = _servicio;
    if (s == null) return;

    final elegida = await _pedirLaFechaDeTermino(
      titulo: 'Programar el término',
      // ⚠️ LA REGLA, DICHA ANTES DE QUE EL SERVIDOR LA APLIQUE: una fecha pasada se
      // rechaza SIEMPRE aquí, esté el servicio activo o suspendido. Para registrar un
      // término que ya ocurrió está «Terminar», con su fecha.
      ayuda:
          'Hoy o después. Para registrar un término que YA ocurrió, usa «Terminar» '
          'con su fecha: programar es comprometerse a futuro.',
      propuesta: s.termino?.comoFechaLocal ?? DiaDeNegocio.hoy().comoFechaLocal,
      desde: DiaDeNegocio.hoy().comoFechaLocal,
    );

    if (elegida == null || !mounted) return;

    setState(() => _guardando = true);

    final resultado = await widget.repositorio.programarTermino(
      empresaId: widget.empresaId,
      servicioId: s.id,
      termino: DiaDeNegocio.deFechaLocal(elegida),
    );

    if (!mounted) return;

    resultado.when(
      ok: (actualizado) {
        setState(() {
          _servicio = actualizado;
          _guardando = false;
        });

        RisegFeedback.showSuccess(context, 'Se programó el término.');
      },
      failure: (f) {
        setState(() => _guardando = false);
        mostrarRechazoDelServidor(context, f);
      },
    );
  }

  Future<void> _retirarTermino() async {
    final s = _servicio;
    if (s == null) return;

    setState(() => _guardando = true);

    final resultado = await widget.repositorio.retirarTerminoProgramado(
      empresaId: widget.empresaId,
      servicioId: s.id,
    );

    if (!mounted) return;

    resultado.when(
      ok: (actualizado) {
        setState(() {
          _servicio = actualizado;
          _guardando = false;
        });

        RisegFeedback.showSuccess(
          context,
          'Se retiró el término. El servicio queda sin fecha de fin.',
        );
      },
      failure: (f) {
        setState(() => _guardando = false);
        mostrarRechazoDelServidor(context, f);
      },
    );
  }

  Future<DateTime?> _pedirLaFechaDeTermino({
    required String titulo,
    required String ayuda,
    required DateTime propuesta,
    DateTime? desde,
  }) => showDialog<DateTime>(
    context: context,
    builder: (_) => _DialogoDeFecha(
      titulo: titulo,
      ayuda: ayuda,
      propuesta: propuesta,
      desde: desde,
    ),
  );

  // =========================================================================
  // El supervisor
  // =========================================================================

  Future<void> _elegirSupervisor() async {
    final s = _servicio;
    if (s == null) return;

    final elegido = await showDialog<EmpleadoElegible>(
      context: context,
      builder: (_) => _DialogoDeSupervisor(
        empleados: widget.empleados,
        empresaId: widget.empresaId,
      ),
    );

    if (elegido == null || !mounted) return;

    setState(() => _guardando = true);

    final resultado = await widget.repositorio.asignarSupervisor(
      empresaId: widget.empresaId,
      servicioId: s.id,
      empleadoId: elegido.id,
    );

    if (!mounted) return;

    resultado.when(
      ok: (actualizado) {
        setState(() {
          _servicio = actualizado;
          // SE PINTA LO ELEGIDO SIN VOLVER A PREGUNTAR: el empleado venía de una lista
          // de ACTIVOS, así que su insignia es la que acaba de verse en el selector.
          _supervisor = SupervisorDelServicio(
            empleadoId: elegido.id,
            numeroDeEmpleado: elegido.numero,
            nombreCompleto: elegido.nombreCompleto,
            estaActivo: elegido.estaActivo,
          );
          _guardando = false;
        });

        RisegFeedback.showSuccess(
          context,
          '${elegido.nombreCompleto} responde por este servicio.',
        );
      },
      failure: (f) {
        setState(() => _guardando = false);
        mostrarRechazoDelServidor(context, f);
      },
    );
  }

  Future<void> _quitarSupervisor() async {
    final s = _servicio;
    if (s == null) return;

    setState(() => _guardando = true);

    final resultado = await widget.repositorio.quitarSupervisor(
      empresaId: widget.empresaId,
      servicioId: s.id,
    );

    if (!mounted) return;

    resultado.when(
      ok: (actualizado) {
        setState(() {
          _servicio = actualizado;
          _supervisor = null;
          _guardando = false;
        });

        RisegFeedback.showSuccess(context, 'El servicio quedó sin supervisor.');
      },
      failure: (f) {
        setState(() => _guardando = false);
        mostrarRechazoDelServidor(context, f);
      },
    );
  }

  // =========================================================================
  // Los tres vínculos
  // =========================================================================

  Future<void> _cambiarEntidadFiscal() async {
    final s = _servicio;
    if (s == null) return;

    final elegida = await _elegirDeUnaLista(
      titulo: 'Entidad fiscal',
      opciones: [
        for (final e in _entidades)
          (valor: e.id, etiqueta: '${e.razonSocial} · ${e.rfc ?? 'sin RFC'}'),
      ],
      actual: s.entidadFiscalId,
    );

    if (elegida == null || !mounted) return;

    // ⚠️ **EL MOTIVO ES CONDICIONAL Y LO DECIDE LA MISMA REGLA QUE EL SERVIDOR (R9):**
    // la PRIMERA asignación no lo pide y cambiarla sí. Preguntarlo siempre pediría algo
    // que el servidor no exige; no preguntarlo nunca fallaría al cambiar.
    String? motivo;

    if (s.entidadFiscalId != null) {
      motivo = await mostrarDialogoMotivo(
        context,
        titulo: 'Cambiar la entidad fiscal',
        etiquetaMotivo: 'Motivo del cambio',
        confirmarLabel: 'Cambiar',
        cancelarLabel: 'Cancelar',
        errorMotivoRequerido:
            'Falta el motivo. Cambia a quién se le factura este servicio.',
      );

      if (motivo == null || !mounted) return;
    }

    await _aplicar(
      widget.repositorio.asignarEntidadFiscal(
        empresaId: widget.empresaId,
        servicioId: s.id,
        entidadFiscalId: elegida,
        motivo: motivo,
      ),
      exito: 'Se asignó la entidad fiscal.',
    );
  }

  Future<void> _quitarEntidadFiscal() async {
    final s = _servicio;
    if (s == null) return;

    final motivo = await mostrarDialogoMotivo(
      context,
      titulo: 'Quitar la entidad fiscal',
      etiquetaMotivo: 'Motivo',
      confirmarLabel: 'Quitar',
      cancelarLabel: 'Cancelar',
      errorMotivoRequerido:
          'Falta el motivo. Quita a quién se le factura este servicio.',
    );

    if (motivo == null || !mounted) return;

    await _aplicar(
      widget.repositorio.quitarEntidadFiscal(
        empresaId: widget.empresaId,
        servicioId: s.id,
        motivo: motivo,
      ),
      exito: 'Se quitó la entidad fiscal.',
    );
  }

  Future<void> _cambiarContacto() async {
    final s = _servicio;
    if (s == null) return;

    final elegido = await _elegirDeUnaLista(
      titulo: 'Contacto responsable',
      opciones: [
        for (final c in _contactos) (valor: c.id, etiqueta: c.nombre),
      ],
      actual: s.contactoResponsableId,
    );

    if (elegido == null || !mounted) return;

    await _aplicar(
      widget.repositorio.asignarContactoResponsable(
        empresaId: widget.empresaId,
        servicioId: s.id,
        contactoId: elegido,
      ),
      exito: 'Se asignó el contacto responsable.',
    );
  }

  Future<void> _quitarContacto() async {
    final s = _servicio;
    if (s == null) return;

    await _aplicar(
      widget.repositorio.quitarContactoResponsable(
        empresaId: widget.empresaId,
        servicioId: s.id,
      ),
      exito: 'Se quitó el contacto responsable.',
    );
  }

  Future<void> _cambiarSucursal() async {
    final s = _servicio;
    if (s == null) return;

    final elegida = await _elegirDeUnaLista(
      titulo: 'Sucursal administrativa',
      opciones: [
        // SÓLO LAS ACTIVAS SE OFRECEN, y la que ya está se conserva aunque no lo esté:
        // la misma regla que el tipo de servicio retirado.
        for (final b in _sucursales)
          if (b.activa || b.id == s.sucursalAdministrativaId)
            (
              valor: b.id,
              etiqueta: b.activa ? b.nombre : '${b.nombre} (inactiva)',
            ),
      ],
      actual: s.sucursalAdministrativaId,
    );

    if (elegida == null || !mounted) return;

    await _aplicar(
      widget.repositorio.asignarSucursalAdministrativa(
        empresaId: widget.empresaId,
        servicioId: s.id,
        sucursalId: elegida,
      ),
      exito: 'Se asignó la sucursal administrativa.',
    );
  }

  Future<void> _quitarSucursal() async {
    final s = _servicio;
    if (s == null) return;

    await _aplicar(
      widget.repositorio.quitarSucursalAdministrativa(
        empresaId: widget.empresaId,
        servicioId: s.id,
      ),
      exito: 'Se quitó la sucursal administrativa.',
    );
  }

  /// Un diálogo que elige **uno** de una lista, o nulo si se cancela.
  Future<String?> _elegirDeUnaLista({
    required String titulo,
    required List<({String valor, String etiqueta})> opciones,
    required String? actual,
  }) => showDialog<String>(
    context: context,
    builder: (_) =>
        _DialogoDeLista(titulo: titulo, opciones: opciones, actual: actual),
  );

  /// Manda una mutación del servicio y refleja lo que devolvió. **Las seis rutas de
  /// vínculo devuelven el servicio entero**, así que su lectura también es una.
  Future<void> _aplicar(
    Future<Result<Servicio>> peticion, {
    required String exito,
  }) async {
    setState(() => _guardando = true);

    final resultado = await peticion;

    if (!mounted) return;

    resultado.when(
      ok: (actualizado) {
        setState(() {
          _servicio = actualizado;
          _guardando = false;
        });

        RisegFeedback.showSuccess(context, exito);
      },
      failure: (f) {
        setState(() => _guardando = false);
        mostrarRechazoDelServidor(context, f);
      },
    );
  }
}

// ===========================================================================
// Las piezas de la ficha
// ===========================================================================

class _Volver extends StatelessWidget {
  const _Volver({required this.onVolver});

  final VoidCallback onVolver;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return InkWell(
      onTap: onVolver,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.arrow_back, size: 18, color: colors.textMuted),
            const SizedBox(width: AppSpacing.xs),
            Text(
              'Servicios',
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
    required this.servicio,
    required this.editando,
    required this.puedeEditar,
    required this.guardando,
    required this.onEditar,
    required this.onEstatus,
  });

  final Servicio servicio;
  final bool editando;
  final bool puedeEditar;
  final bool guardando;
  final VoidCallback onEditar;
  final VoidCallback onEstatus;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final estado = servicio.estado;

    // ⚠️ **LA DECISIÓN NO SE TOMA AQUÍ**, y es el arreglo del 11 de noviembre de 2026: un
    // servicio Terminado enseñaba «Vigente» al lado, porque los dos ejes se pintaban como
    // si fueran comparables. Quién habla y qué dice está en `insignia_temporal.dart`, que
    // es también de donde lo saca la fila del listado.
    final temporal = insigniaTemporalDe(
      estatus: servicio.estatus,
      condicionTemporal: servicio.condicionTemporal,
      termino: servicio.termino,
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(servicio.nombre, style: AppTypography.heading1),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                servicio.codigo,
                style: AppTypography.caption.copyWith(color: colors.textMuted),
              ),
              const SizedBox(height: AppSpacing.xs),
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xxs,
                children: [
                  if (estado != null)
                    RisegStatusBadge(
                      label: estado.nombre,
                      tone: switch (estado) {
                        EstatusDeServicio.activo => RisegStatusTone.success,
                        EstatusDeServicio.suspendido => RisegStatusTone.warning,
                        EstatusDeServicio.terminado => RisegStatusTone.neutral,
                      },
                      icon: switch (estado) {
                        EstatusDeServicio.activo => Icons.check_circle_outline,
                        EstatusDeServicio.suspendido => Icons.pause_circle_outline,
                        EstatusDeServicio.terminado => Icons.flag_outlined,
                      },
                    ),
                  if (temporal != null) temporal.pintar(),
                ],
              ),
            ],
          ),
        ),
        if (!editando && puedeEditar) ...[
          RisegButton(
            label: 'Cambiar estatus',
            variant: RisegButtonVariant.secondary,
            icon: Icons.swap_horiz,
            onPressed: guardando ? null : onEstatus,
          ),
          const SizedBox(width: AppSpacing.sm),
          RisegButton(
            label: 'Editar',
            icon: Icons.edit_outlined,
            onPressed: guardando ? null : onEditar,
          ),
        ],
      ],
    );
  }
}

class _Indicadores extends StatelessWidget {
  const _Indicadores({required this.indicadores, required this.terminado});

  final IndicadoresDeServicio indicadores;
  final bool terminado;

  @override
  Widget build(BuildContext context) => Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.sm,
      children: [
        _Dato(
          etiqueta: 'Importe mensual',
          // ⚠️ **AUSENCIA NUNCA ES CERO.** Una lista vacía significa que no hay
          // condiciones comerciales vigentes, y «$0.00» diría que el servicio no vale
          // nada. Son dos cosas distintas y se dicen distinto.
          valor: indicadores.importeMensual.isEmpty
              ? 'Sin condiciones vigentes'
              : indicadores.importeMensual.map((m) => m.enPantalla).join(' · '),
        ),
        _Dato(
          etiqueta: terminado ? 'Duró' : 'Antigüedad',
          valor: indicadores.antiguedadEnPantalla,
          ayuda: terminado
              // EN UN TERMINADO DEJA DE CRECER: se mide hasta su término, porque lo que
              // dice es cuánto duró.
              ? 'Hasta su término.'
              : null,
        ),
      ],
    );
}

class _Dato extends StatelessWidget {
  const _Dato({required this.etiqueta, required this.valor, this.ayuda});

  final String etiqueta;
  final String valor;
  final String? ayuda;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          etiqueta.toUpperCase(),
          style: AppTypography.caption.copyWith(
            color: colors.textMuted,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(valor, style: AppTypography.heading2),
        if (ayuda case final a?) ...[
          const SizedBox(height: AppSpacing.xxs),
          Text(
            a,
            style: AppTypography.caption.copyWith(color: colors.textMuted),
          ),
        ],
      ],
    );
  }
}

/// El término programado: cuándo deja de operar, y cómo se cambia.
class _SeccionDelTermino extends StatelessWidget {
  const _SeccionDelTermino({
    required this.servicio,
    required this.puedeCambiar,
    required this.onProgramar,
    required this.onRetirar,
  });

  final Servicio servicio;
  final bool puedeCambiar;
  final VoidCallback onProgramar;
  final VoidCallback onRetirar;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final termino = servicio.termino;
    final terminado = servicio.estado?.esFinalizado ?? false;

    return RisegFormSection(
      title: 'Término',
      description: terminado
          // EN UN TERMINADO LA FECHA ES UN HECHO, no un plan: no se «programa» algo que
          // ya pasó, así que aquí no se ofrece cambiarla desde esta sección.
          ? 'El servicio ya terminó. Para volver a operarlo, reactívalo desde '
                '«Cambiar estatus».'
          : 'Cuándo deja de operar. Programar acepta hoy o después: para registrar '
                'un término que YA ocurrió se usa «Cambiar estatus» → Terminado.',
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                switch (termino) {
                  final d? => 'Termina el ${fechaDeNegocioCorta(d)}',
                  null => 'Sin fecha de término',
                },
                style: AppTypography.body.copyWith(
                  color: termino == null ? colors.textMuted : colors.textPrimary,
                ),
              ),
            ),
            if (puedeCambiar && !terminado) ...[
              if (termino != null) ...[
                RisegButton(
                  label: 'Retirar',
                  variant: RisegButtonVariant.secondary,
                  size: RisegButtonSize.compact,
                  onPressed: onRetirar,
                ),
                const SizedBox(width: AppSpacing.xs),
              ],
              RisegButton(
                label: termino == null ? 'Programar' : 'Cambiar',
                variant: RisegButtonVariant.secondary,
                size: RisegButtonSize.compact,
                onPressed: onProgramar,
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// Quién RESPONDE por el servicio.
///
/// 🚫 **No es personal asignado al servicio.** La asignación de personal lleva ZONA —lo
/// dice la 0046—, así que esto nombra a quien responde, no a quien trabaja ahí.
class _SeccionDelSupervisor extends StatelessWidget {
  const _SeccionDelSupervisor({
    required this.supervisor,
    required this.puedeEscribir,
    required this.puedeElegir,
    required this.onElegir,
    required this.onQuitar,
  });

  final SupervisorDelServicio? supervisor;

  /// `clients_services.manage`: escribir el vínculo.
  final bool puedeEscribir;

  /// `personal.read`: poder **listar empleados** para elegir a quién.
  final bool puedeElegir;

  final VoidCallback onElegir;
  final VoidCallback onQuitar;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final s = supervisor;

    // HACEN FALTA LAS DOS COSAS, y son de dos módulos: escribir el vínculo es de
    // Comercial y elegir a quién obliga a leer Personal.
    final seOfreceElegir = puedeEscribir && puedeElegir;

    return RisegFormSection(
      title: 'Supervisor responsable',
      description:
          'Quién responde por este servicio. Puede ser cualquier empleado activo '
          'de la empresa, sin filtrar por puesto.',
      children: [
        if (s == null)
          Row(
            children: [
              Expanded(
                child: Text(
                  'Sin supervisor asignado',
                  style: AppTypography.body.copyWith(color: colors.textMuted),
                ),
              ),
              if (seOfreceElegir)
                RisegButton(
                  label: 'Asignar',
                  variant: RisegButtonVariant.secondary,
                  size: RisegButtonSize.compact,
                  icon: Icons.person_add_alt,
                  onPressed: onElegir,
                ),
            ],
          )
        else ...[
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.nombreCompleto, style: AppTypography.bodyStrong),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      'Empleado ${s.numeroDeEmpleado}',
                      style: AppTypography.caption.copyWith(
                        color: colors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              // ⚠️ **LA INSIGNIA «BAJA», que es la razón de que esta ruta devuelva
              // `isActive`.** Un supervisor que deja de estar activo NO se desvincula
              // solo —decisión del dueño—, así que la ficha tiene que poder decir que
              // esa persona ya no está en vez de enseñar un nombre que parece vigente.
              if (!s.estaActivo)
                const RisegStatusBadge(
                  label: 'Baja',
                  tone: RisegStatusTone.warning,
                  icon: Icons.person_off_outlined,
                ),
              if (seOfreceElegir) ...[
                const SizedBox(width: AppSpacing.xs),
                RisegButton(
                  label: 'Cambiar',
                  variant: RisegButtonVariant.secondary,
                  size: RisegButtonSize.compact,
                  onPressed: onElegir,
                ),
              ],
              if (puedeEscribir) ...[
                const SizedBox(width: AppSpacing.xs),
                RisegButton(
                  label: 'Quitar',
                  variant: RisegButtonVariant.secondary,
                  size: RisegButtonSize.compact,
                  onPressed: onQuitar,
                ),
              ],
            ],
          ),
          if (!s.estaActivo) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Esta persona ya no está activa en la empresa. El servicio conserva '
              'la referencia —no se borra sola— pero conviene nombrar a otra.',
              style: AppTypography.caption.copyWith(color: colors.textMuted),
            ),
          ],
        ],

        // SE DICE POR QUÉ NO SE OFRECE, en vez de enseñar un hueco sin explicación.
        if (puedeEscribir && !puedeElegir) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Para elegir un supervisor hace falta permiso de lectura en Personal: '
            'la lista de empleados es de ese módulo.',
            style: AppTypography.caption.copyWith(color: colors.textMuted),
          ),
        ],
      ],
    );
  }
}

/// Una fila de vínculo: qué está asignado y los dos botones.
class _Vinculo extends StatelessWidget {
  const _Vinculo({
    required this.etiqueta,
    required this.ayuda,
    required this.valor,
    required this.puedeCambiar,
    required this.hayDeDonde,
    required this.vacioDice,
    required this.onCambiar,
    required this.onQuitar,
  });

  final String etiqueta;
  final String ayuda;

  /// Lo asignado, o nulo si no hay nada.
  final String? valor;

  final bool puedeCambiar;

  /// Si hay de dónde elegir. **Sin opciones no se ofrece el botón**: abriría una lista
  /// vacía, que parece un error del producto y no la consecuencia de que el cliente
  /// todavía no tenga contactos.
  final bool hayDeDonde;

  final String vacioDice;
  final VoidCallback onCambiar;
  final VoidCallback? onQuitar;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      etiqueta.toUpperCase(),
                      style: AppTypography.caption.copyWith(
                        color: colors.textMuted,
                        letterSpacing: 0.6,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      valor ?? 'Sin asignar',
                      style: valor == null
                          ? AppTypography.body.copyWith(color: colors.textMuted)
                          : AppTypography.bodyStrong,
                    ),
                  ],
                ),
              ),
              if (puedeCambiar && hayDeDonde)
                RisegButton(
                  label: valor == null ? 'Asignar' : 'Cambiar',
                  variant: RisegButtonVariant.secondary,
                  size: RisegButtonSize.compact,
                  onPressed: onCambiar,
                ),
              if (puedeCambiar && onQuitar != null) ...[
                const SizedBox(width: AppSpacing.xs),
                RisegButton(
                  label: 'Quitar',
                  variant: RisegButtonVariant.secondary,
                  size: RisegButtonSize.compact,
                  onPressed: onQuitar,
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            hayDeDonde ? ayuda : vacioDice,
            style: AppTypography.caption.copyWith(color: colors.textMuted),
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// Los diálogos
// ===========================================================================

class _DialogoDeEstatus extends StatelessWidget {
  const _DialogoDeEstatus({required this.actual});

  final EstatusDeServicio? actual;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final terminado = actual?.esFinalizado ?? false;

    return AlertDialog(
      backgroundColor: colors.surfaceSunken,
      title: const Text('Cambiar el estatus', style: AppTypography.heading2),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final e in EstatusDeServicio.values)
            // 🚫 **TERMINADO → SUSPENDIDO ESTÁ PROHIBIDO** y el servidor responde 409.
            // La celda prohibida no se ofrece: un botón que siempre falla es peor que
            // su ausencia, y aquí además confundiría «suspender» con «reactivar».
            if (e != actual && !(terminado && e == EstatusDeServicio.suspendido))
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  terminado && e == EstatusDeServicio.activo
                      ? 'Reactivar'
                      : e.nombre,
                ),
                subtitle: Text(
                  switch (e) {
                    EstatusDeServicio.activo when terminado =>
                      'Vuelve a operar y se retira su fecha de término.',
                    EstatusDeServicio.activo => 'Vuelve a operar.',
                    EstatusDeServicio.suspendido =>
                      'Deja de operar temporalmente. Se puede reactivar.',
                    EstatusDeServicio.terminado =>
                      'Deja de operar. Pide la fecha desde cuándo.',
                  },
                  style: AppTypography.caption.copyWith(color: colors.textMuted),
                ),
                onTap: () => Navigator.of(context).pop(e),
              ),
        ],
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
}

class _DialogoDeFecha extends StatefulWidget {
  const _DialogoDeFecha({
    required this.titulo,
    required this.ayuda,
    required this.propuesta,
    this.desde,
  });

  final String titulo;
  final String ayuda;
  final DateTime propuesta;

  /// La primera fecha admitida. **Programar un término no acepta el pasado**, y el
  /// selector lo impone en lugar de dejar que el servidor conteste 422.
  final DateTime? desde;

  @override
  State<_DialogoDeFecha> createState() => _DialogoDeFechaState();
}

class _DialogoDeFechaState extends State<_DialogoDeFecha> {
  late DateTime? _fecha = widget.propuesta;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return AlertDialog(
      backgroundColor: colors.surfaceSunken,
      title: Text(widget.titulo, style: AppTypography.heading2),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RisegDateField(
              label: 'Fecha',
              value: _fecha,
              firstDate: widget.desde,
              helperText: widget.ayuda,
              onChanged: (v) => setState(() => _fecha = v),
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
        RisegButton(
          label: 'Confirmar',
          onPressed: _fecha == null
              ? null
              : () => Navigator.of(context).pop(_fecha),
        ),
      ],
    );
  }
}

/// Elige **uno** de una lista corta.
class _DialogoDeLista extends StatelessWidget {
  const _DialogoDeLista({
    required this.titulo,
    required this.opciones,
    required this.actual,
  });

  final String titulo;
  final List<({String valor, String etiqueta})> opciones;
  final String? actual;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return AlertDialog(
      backgroundColor: colors.surfaceSunken,
      title: Text(titulo, style: AppTypography.heading2),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final o in opciones)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(o.etiqueta),
                trailing: o.valor == actual
                    ? Icon(Icons.check, color: colors.accent)
                    : null,
                onTap: () => Navigator.of(context).pop(o.valor),
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
}

/// Elige al supervisor **buscando en el servidor**.
///
/// ⚠️ **No se filtra en la pantalla.** `GET /employees` pagina por cursor, así que filtrar
/// una página no es filtrar la plantilla: una empresa con trescientos empleados traería
/// los primeros cincuenta y «buscar» entre ellos encontraría a quien cupo, no a quien se
/// busca. El texto va al servidor.
class _DialogoDeSupervisor extends StatefulWidget {
  const _DialogoDeSupervisor({
    required this.empleados,
    required this.empresaId,
  });

  final EmpleadosRepositorioHttp empleados;
  final String empresaId;

  @override
  State<_DialogoDeSupervisor> createState() => _DialogoDeSupervisorState();
}

class _DialogoDeSupervisorState extends State<_DialogoDeSupervisor> {
  final _buscador = TextEditingController();

  List<EmpleadoElegible>? _empleados;
  Failure? _fallo;
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _buscar();
  }

  @override
  void dispose() {
    _buscador.dispose();
    super.dispose();
  }

  Future<void> _buscar() async {
    setState(() {
      _cargando = true;
      _fallo = null;
    });

    final resultado = await widget.empleados.activos(
      widget.empresaId,
      texto: _buscador.text,
    );

    if (!mounted) return;

    resultado.when(
      ok: (e) => setState(() {
        _empleados = e;
        _cargando = false;
      }),
      failure: (f) => setState(() {
        _fallo = f;
        _cargando = false;
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return AlertDialog(
      backgroundColor: colors.surfaceSunken,
      title: const Text('Elegir supervisor', style: AppTypography.heading2),
      content: SizedBox(
        width: 460,
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: RisegTextField(
                    label: 'Buscar',
                    controller: _buscador,
                    helperText: 'Por nombre o número de empleado.',
                    onSubmitted: (_) => _buscar(),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                RisegButton(
                  label: 'Buscar',
                  variant: RisegButtonVariant.secondary,
                  size: RisegButtonSize.compact,
                  onPressed: _cargando ? null : _buscar,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Expanded(child: _cuerpo()),
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

  Widget _cuerpo() {
    if (_cargando) return const Center(child: CircularProgressIndicator());

    if (_fallo case final f?) {
      return RisegEmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'No se pudieron cargar los empleados',
        message: f.message,
        primaryAction: RisegButton(
          label: 'Intentar de nuevo',
          onPressed: _buscar,
        ),
      );
    }

    final empleados = _empleados ?? const <EmpleadoElegible>[];

    if (empleados.isEmpty) {
      // SE DISTINGUE «NO HAY NINGUNO» DE «LA BÚSQUEDA NO ENCONTRÓ», porque son dos
      // problemas distintos y se arreglan distinto.
      return RisegEmptyState(
        icon: Icons.people_outline,
        title: _buscador.text.trim().isEmpty
            ? 'No hay empleados activos'
            : 'Nadie coincide con esa búsqueda',
        message: _buscador.text.trim().isEmpty
            ? 'Sólo un empleado activo puede responder por un servicio, y «activo» '
                  'se deriva de un periodo laboral abierto.'
            : 'Prueba con otra parte del nombre o con el número de empleado.',
      );
    }

    return ListView.separated(
      itemCount: empleados.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (_, i) => ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(empleados[i].nombreCompleto),
        subtitle: Text('Empleado ${empleados[i].numero}'),
        onTap: () => Navigator.of(context).pop(empleados[i]),
      ),
    );
  }
}
