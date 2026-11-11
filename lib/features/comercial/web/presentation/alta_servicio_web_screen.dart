import 'package:flutter/material.dart';

import '../../../../core/design_system/design_system_web.dart';
import '../../../../core/direcciones/campos_de_domicilio.dart';
import '../../../../core/direcciones/seccion_de_domicilio.dart';
import '../../../../core/error/rechazo_del_servidor.dart';
import '../../../../core/fechas/dia_de_negocio.dart';
import '../../../../core/trabajo_sin_guardar/declara_su_trabajo_sin_guardar.dart';
import '../../../../core/trabajo_sin_guardar/guardia_de_salida.dart';
import '../datos/clientes_repositorio_http.dart';
import '../datos/servicios_repositorio_http.dart';
import '../modelos/cliente.dart';
import '../modelos/servicio.dart';

/// El alta de un servicio — `/comercial/servicios/nuevo`.
///
/// ## Por qué es una PÁGINA y no un diálogo, al contrario que el alta de un cliente
///
/// Decisión del dueño del 9 de noviembre de 2026. El alta de un cliente son **tres
/// campos** y cabe en un panel; la de un servicio son **quince**: cinco propios más los
/// **diez del domicilio operativo**, que el servidor exige en la misma transacción desde
/// la 0059. A quince campos, un diálogo en un teléfono no se puede usar.
///
/// Y una página se registra en el `GuardiaDeSalida` igual que un panel, así que no se
/// pierde nada por el camino.
///
/// ## Es UNA sola petición, y eso manda en el diseño del formulario
///
/// El servidor no admite un servicio sin domicilio —lo impone un disparador diferido al
/// cerrar la transacción—, así que **no hay «guardar el servicio y luego el domicilio»**:
/// un formulario a medias no deja un servicio a medias, deja un 400. Por eso el domicilio
/// no es una sección opcional que se pueda saltar.
///
/// ## El cliente se elige aquí y después es inmutable
///
/// `service.client_id` no viaja en ningún `PATCH` y el servidor no ofrece ruta para
/// cambiarlo: un servicio que cambiara de cliente reescribiría a quién se le cobró. Y el
/// selector ofrece **sólo clientes ACTIVOS**, porque un cliente que no lo está no admite
/// servicios nuevos (D-64) — ofrecer otros sería enseñar una puerta que responde 409.
class AltaServicioWebScreen extends StatefulWidget {
  const AltaServicioWebScreen({
    required this.repositorio,
    required this.clientes,
    required this.empresaId,
    required this.guardia,
    required this.alTerminar,
    required this.alCancelar,
    this.alIrAClientes,
    this.alIrATipos,
    this.clienteIdInicial,
    super.key,
  });

  final ServiciosRepositorioHttp repositorio;

  /// El repositorio de clientes, **para el selector**: ofrece los activos.
  final ClientesRepositorioHttp clientes;

  final String empresaId;

  /// Dónde se registra que hay trabajo sin guardar (D-56). **Esta pantalla SÍ lo usa**:
  /// es un formulario de quince campos, y es justo el caso que la regla protege.
  final GuardiaDeSalida guardia;

  /// Qué hacer con el servicio recién creado. **La pantalla pide, no navega.**
  final void Function(Servicio creado) alTerminar;

  final VoidCallback alCancelar;

  /// Lleva a Clientes, para cuando no hay ninguno activo. Opcional: sin él, el aviso lo
  /// dice y no ofrece el atajo — un botón que no lleva a ningún sitio es peor que su
  /// ausencia.
  final VoidCallback? alIrAClientes;

  /// Lleva al catálogo de tipos, para cuando la empresa todavía no tiene ninguno.
  ///
  /// ⚠️ **Es la salida de un callejón, no un adorno.** El catálogo nace vacío a propósito
  /// —SEVENTRA se vende también a empresas que no son de seguridad—, así que «no hay
  /// tipos» es el estado normal del primer día y el alta tiene que saber adónde mandar.
  /// Opcional por lo mismo que [alIrAClientes]: un botón que no lleva a ningún sitio es
  /// peor que su ausencia.
  final VoidCallback? alIrATipos;

  /// Con qué cliente llega preseleccionado, si se entró desde su expediente.
  ///
  /// Hoy nadie lo pasa —el alta se abre desde el listado—, y existe porque el expediente
  /// de un cliente va a tener su «Nuevo servicio»: dejar el hueco cuesta una línea y
  /// evita que esa pantalla tenga que duplicar el formulario.
  final String? clienteIdInicial;

  @override
  State<AltaServicioWebScreen> createState() => _AltaServicioWebScreenState();
}

class _AltaServicioWebScreenState extends State<AltaServicioWebScreen>
    with DeclaraSuTrabajoSinGuardar<AltaServicioWebScreen> {
  final _nombre = TextEditingController();
  final _observaciones = TextEditingController();

  /// Los diez campos del domicilio, con sus controladores. **Los posee y los libera él**,
  /// así que aquí se llama a `dispose` una vez y no diez.
  final _domicilio = CamposDeDomicilio();

  String? _clienteId;
  String? _tipoId;

  /// La fecha de inicio. `DateTime` y no [DiaDeNegocio] porque es lo que pide el campo del
  /// sistema de diseño; se convierte **al mandar**, y la conversión va por
  /// [DiaDeNegocio.deFechaLocal] porque lo que la persona eligió es un día del calendario,
  /// no un instante.
  DateTime? _inicio;

  /// Las dos listas de los selectores. **Nulo es «todavía no llegaron»** y vacío es «no
  /// hay ninguno», que son dos cosas distintas y se dicen distinto.
  List<ClienteEnLista>? _clientesActivos;
  List<TipoDeServicio>? _tiposActivos;

  bool _guardando = false;

  /// Si ya se guardó. **Apaga el guardia**: lo guardado no es trabajo sin guardar, y
  /// preguntar «¿seguro que sales?» después de un alta correcta sería absurdo —y enseñaría
  /// a contestar el diálogo sin leerlo—.
  bool _guardado = false;

  /// Lo que falta por elegir, **por clave**, para señalar el cuadro en lugar de un aviso
  /// general arriba: con quince campos, «revisa los datos» no sirve.
  Map<String, String> _faltantes = const {};

  @override
  GuardiaDeSalida get guardia => widget.guardia;

  /// ⚠️ **SE COMPARA CONTRA EL FORMULARIO VACÍO, que es «lo cargado» de un alta.**
  ///
  /// No contra «se tocó algo»: escribir una letra y borrarla no es un cambio, y una
  /// pregunta que sale por eso enseña a contestar el diálogo sin leerlo — y entonces el
  /// día que haya quince campos de verdad que perder, también se contestará sin leer.
  ///
  /// **La fecha propuesta no cuenta**: la pone la pantalla, no la persona. Y el cliente
  /// preseleccionado tampoco, por lo mismo.
  @override
  bool get hayCambiosSinGuardar =>
      !_guardado &&
      (_nombre.text.trim().isNotEmpty ||
          _observaciones.text.trim().isNotEmpty ||
          _domicilio.hayAlgo ||
          _tipoId != null ||
          _clienteId != widget.clienteIdInicial);

  @override
  String get queSePierde => 'el nuevo servicio';

  @override
  void initState() {
    super.initState();

    _clienteId = widget.clienteIdInicial;

    // LA FECHA SE PROPONE CON EL DÍA DE NEGOCIO, no con `DateTime.now()`: el día del
    // negocio va por UTC-6, así que a las 19:00 locales un `now()` en UTC ya es mañana.
    // Es el error que se copió mal ocho veces en el servidor y aquí no se repite.
    _inicio = DiaDeNegocio.hoy().comoFechaLocal;

    _cargarSelectores();
  }

  @override
  void dispose() {
    _nombre.dispose();
    _observaciones.dispose();
    // UNA LLAMADA Y NO DIEZ: `CamposDeDomicilio` posee sus controladores.
    _domicilio.dispose();
    super.dispose();
  }

  // =========================================================================
  // Los selectores
  // =========================================================================

  /// Los clientes **activos** y los tipos **activos**.
  ///
  /// ⚠️ **NINGUNA DE LAS DOS ES LA LISTA DEL FILTRO DEL LISTADO**, y la diferencia es el
  /// sentido de la pregunta:
  ///
  /// | | el filtro del listado ofrece | el alta ofrece |
  /// |---|---|---|
  /// | clientes | los que **ya tienen** servicios | los **activos** |
  /// | tipos | los **usados** | los **activos** |
  ///
  /// Filtrar mira hacia atrás —qué hay— y dar de alta mira hacia adelante —qué se puede
  /// elegir—. Un cliente terminado con cuatro servicios sale en el filtro y **no** aquí;
  /// un tipo recién creado, al revés.
  Future<void> _cargarSelectores() async {
    final clientes = await widget.clientes.listar(
      widget.empresaId,
      estatus: EstatusDeCliente.activo,
      // El techo del servidor: un selector es una lista completa o no sirve para elegir.
      limite: 200,
    );

    final tipos = await widget.repositorio.tipos(
      widget.empresaId,
      // TODOS Y NO `usados: true`: un tipo recién creado tiene que poder elegirse para el
      // PRIMER servicio que lo use, que es justo para lo que se creó.
      usados: null,
    );

    if (!mounted) return;

    setState(() {
      clientes.when(
        ok: (p) => _clientesActivos = p.clientes,
        // VACÍO Y NO NULO AL FALLAR: nulo significaría «todavía no llegaron» y la pantalla
        // se quedaría cargando para siempre. Vacío enseña el aviso, que ofrece la salida.
        failure: (_) => _clientesActivos = const [],
      );

      tipos.when(
        // SÓLO LOS ACTIVOS: un tipo retirado de circulación no se puede elegir para algo
        // nuevo —el servidor lo rechaza—, así que no se ofrece.
        ok: (t) => _tiposActivos = t.where((x) => x.estaActivo).toList(),
        failure: (_) => _tiposActivos = const [],
      );
    });
  }

  // =========================================================================
  // Guardar
  // =========================================================================

  Future<void> _guardar() async {
    final clienteId = _clienteId;
    final tipoId = _tipoId;
    final inicio = _inicio;

    // LOS TRES SELECTORES SE COMPRUEBAN AQUÍ y el nombre no, y la asimetría es a
    // propósito: un selector sin elegir **no tiene nada que mandar** —no hay cuerpo que
    // armar—, mientras que un nombre vacío SÍ viaja y el servidor contesta cuál falta con
    // su mensaje. Lo que no se hace es duplicar las reglas del servidor en el formulario.
    if (clienteId == null || tipoId == null || inicio == null) {
      setState(() {
        _faltantes = {
          if (clienteId == null) 'clientId': 'Elige el cliente.',
          if (tipoId == null) 'serviceTypeId': 'Elige el tipo de servicio.',
          if (inicio == null) 'startedOn': 'Elige la fecha de inicio.',
        };
      });

      return;
    }

    final domicilio = _domicilio.direccion;

    if (domicilio == null) {
      // EL DOMICILIO VACÍO SE ATAJA, y es lo único en que esta pantalla se adelanta al
      // servidor: mandarlo sin `address` daría «Falta la calle», que es cierto y no dice
      // que el domicilio sea OBLIGATORIO en un servicio. Con un domicilio A MEDIAS no se
      // ataja: ahí el servidor nombra el campo que falta, que es lo que hace falta leer.
      setState(() {
        _faltantes = {
          'address.street':
              'Un servicio no existe sin domicilio operativo: es donde se presta.',
        };
      });

      return;
    }

    setState(() {
      _guardando = true;
      _faltantes = const {};
    });

    final resultado = await widget.repositorio.crear(
      empresaId: widget.empresaId,
      clienteId: clienteId,
      nombre: _nombre.text.trim(),
      tipoId: tipoId,
      // LO QUE LA PERSONA ELIGIÓ ES UN DÍA DEL CALENDARIO, no un instante: por eso
      // `deFechaLocal` y no `DiaDeNegocio.de`, que aplicaría el desplazamiento de zona a
      // una fecha que no lo necesita y podría dejarla en el día anterior.
      inicio: DiaDeNegocio.deFechaLocal(inicio),
      domicilio: domicilio,
      observaciones: _observaciones.text.trim().isEmpty
          ? null
          : _observaciones.text.trim(),
    );

    if (!mounted) return;

    resultado.when(
      ok: (servicio) {
        // EL GUARDIA SE APAGA ANTES DE NAVEGAR: el mixin lo suelta en `dispose`, pero la
        // navegación ocurre antes y la pregunta saldría con el formulario ya guardado.
        setState(() => _guardado = true);

        widget.alTerminar(servicio);
      },
      failure: (f) {
        setState(() => _guardando = false);

        // UN SOLO SITIO DECIDE CÓMO SE DICE UN RECHAZO, y recibe el FALLO y no un texto:
        // hay rechazos que el servidor no explica bien —un módulo apagado, un permiso que
        // falta— y la traducción vive ahí, no repartida por cada pantalla.
        mostrarRechazoDelServidor(context, f);
      },
    );
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
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const RisegSectionHeader(
                title: 'Nuevo servicio',
                description:
                    'Lo que se le presta a un cliente en un lugar concreto. '
                    'El domicilio operativo va en la misma captura.',
              ),
              const SizedBox(height: AppSpacing.md),
              Expanded(child: _cuerpo()),
            ],
          ),
        ),
      ),
    );
  }

  /// El formulario, **o la razón por la que todavía no se puede capturar**.
  ///
  /// ⚠️ **Un formulario que no se puede enviar no se enseña.** Sin clientes activos o sin
  /// tipos, guardar respondería 409 o 400 con seguridad: pintar quince campos para que el
  /// último paso falle es peor que decirlo antes y ofrecer la salida.
  Widget _cuerpo() {
    final clientes = _clientesActivos;
    final tipos = _tiposActivos;

    // TODAVÍA NO LLEGARON. Nulo y vacío se distinguen a propósito: con vacío ya se sabe
    // que no hay ninguno, y con nulo todavía no se sabe nada.
    if (clientes == null || tipos == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (clientes.isEmpty) {
      return RisegEmptyState(
        icon: Icons.handshake_outlined,
        title: 'Primero hace falta un cliente activo',
        message:
            'Un servicio se le presta a un cliente, y un cliente que no está activo '
            'no admite servicios nuevos: una relación pausada o cerrada no debe '
            'generar compromisos. Da de alta uno, o reactiva al que corresponda.',
        primaryAction: widget.alIrAClientes == null
            ? null
            : RisegButton(
                label: 'Ver clientes',
                onPressed: widget.alIrAClientes,
              ),
      );
    }

    if (tipos.isEmpty) {
      // Y AQUÍ SE SALE DEL CALLEJÓN. El catálogo nace vacío a propósito —SEVENTRA se
      // vende también a empresas que no son de seguridad—, así que esta pantalla no es un
      // error: es el primer día de una empresa nueva, y lo único que le falta es un
      // minuto en el catálogo.
      return RisegEmptyState(
        icon: Icons.category_outlined,
        title: 'Primero hace falta un tipo de servicio',
        message:
            'El catálogo de tipos —«Vigilancia fija», «Rondín», «Escolta»— es de cada '
            'empresa y empieza vacío, porque no a todas les corresponden los mismos. '
            'Créalo en un minuto: hay un botón que agrega los recomendados de una vez.',
        primaryAction: widget.alIrATipos == null
            ? null
            : RisegButton(
                label: 'Ir a tipos de servicio',
                onPressed: widget.alIrATipos,
              ),
      );
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RisegFormSection(
            title: 'Datos generales',
            description:
                'El cliente no se puede cambiar después: un servicio que cambiara de '
                'cliente reescribiría a quién se le cobró.',
            grid: true,
            children: [
              RisegTextField(
                label: 'Nombre del servicio',
                controller: _nombre,
                enabled: !_guardando,
                helperText:
                    'Como lo reconoce la operación: «Sportium Satélite».',
              ),
              RisegSelect<String?>(
                label: 'Cliente',
                value: _clienteId,
                enabled: !_guardando,
                errorText: _faltantes['clientId'],
                helperText: 'Sólo clientes activos.',
                items: [
                  for (final c in clientes)
                    RisegSelectItem(
                      value: c.cliente.id,
                      label: c.cliente.nombreComercial,
                    ),
                ],
                onChanged: (v) => setState(() => _clienteId = v),
              ),
              RisegSelect<String?>(
                label: 'Tipo de servicio',
                value: _tipoId,
                enabled: !_guardando,
                errorText: _faltantes['serviceTypeId'],
                items: [
                  for (final t in tipos)
                    RisegSelectItem(value: t.id, label: t.nombre),
                ],
                onChanged: (v) => setState(() => _tipoId = v),
              ),
              RisegDateField(
                label: 'Fecha de inicio',
                value: _inicio,
                enabled: !_guardando,
                errorText: _faltantes['startedOn'],
                helperText:
                    'Desde cuándo opera. Se propone hoy y se puede cambiar.',
                onChanged: (v) => setState(() => _inicio = v),
              ),
              RisegTextField(
                label: 'Observaciones',
                controller: _observaciones,
                enabled: !_guardando,
                maxLines: 3,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          SeccionDeDomicilio(
            titulo: 'Domicilio operativo',
            campos: _domicilio,
            habilitado: !_guardando,
            erroresPorCampo: _faltantes,
            // LA LETRA CHICA DICE LA REGLA, y aquí es distinta de la de una sucursal:
            // allá el domicilio se puede dejar vacío entero y aquí NO. Es el parámetro
            // que existe justo para esto.
            descripcion:
                'Dónde se presta el servicio. Es obligatorio: un servicio sin '
                'domicilio no se puede cubrir ni supervisar, y el servidor no lo '
                'admite.',
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              RisegButton(
                label: 'Cancelar',
                variant: RisegButtonVariant.ghost,
                onPressed: _guardando ? null : widget.alCancelar,
              ),
              const SizedBox(width: AppSpacing.sm),
              RisegButton(
                label: _guardando ? 'Guardando…' : 'Guardar',
                icon: Icons.save_outlined,
                onPressed: _guardando ? null : _guardar,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
