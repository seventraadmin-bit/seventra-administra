import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../../core/company/autoridad_de_organizacion.dart';
import '../../../../core/company/gestor_de_company.dart';
import '../../../../core/company/guardia_de_salida.dart';
import '../../../../core/company/logotipos_de_empresa.dart';
import '../../../../core/design_system/design_system_web.dart';
import '../../../../core/error/failure.dart';
import '../datos/empresas_repositorio_http.dart';
import '../datos/expedientes_repositorio_http.dart';
import '../datos/logotipo_repositorio_http.dart';
import '../modelos/expediente.dart';
import 'empresa_ficha.dart';
import 'empresas_administracion_screen.dart';
import 'empresa_web_screen.dart';

/// La pestaña **Empresa**: la ficha de **la empresa activa**, y su edición.
///
/// ## Por qué dos pasos y no un formulario siempre abierto
///
/// Hasta el 21 de octubre de 2026 esta pestaña **era** un formulario: se entraba
/// directamente a dieciséis campos editables. Y lo que se hace a diario es mirar el RFC
/// para dárselo a alguien, no cambiarlo; además los datos fiscales no se veían con la
/// forma en que se entregan, que es la de la tarjeta fiscal.
///
/// Así que el recorrido es **ficha → editar**, y editar **cierra al guardar**.
///
/// ## 🚫 AQUÍ NO HAY LISTA DE EMPRESAS, y la hubo durante tres días
///
/// E1 hizo de la lista la entrada: con varias empresas se veía la lista, y **tocar una
/// fila abría su expediente Y cambiaba la empresa activa**. Se programó así, funcionó
/// así, y en cuanto hubo una segunda empresa apareció el problema de verdad:
/// **consultar no es cambiar.** Mirar la ficha de otra empresa movía el contexto de
/// trabajo entero —menú, permisos, barra inferior— sin que nadie lo hubiera pedido, y
/// el siguiente guardado habría ido a la empresa que se estaba *mirando*.
///
/// No era un defecto de implementación: la decisión juntaba dos verbos con expectativas
/// opuestas —consultar espera que no cambie nada; cambiar espera que cambie todo— en un
/// solo gesto. Así que se separaron (E1-B):
///
///  · **cambiar de empresa** se hace **sólo desde la barra inferior**, con un menú que
///    dice en voz alta lo que hace y avisa después: «Ahora trabajas en X»;
///  · **consultar la ficha de otra empresa sin activarla** será parte de **E2**, la
///    administración de empresas. Hoy no existe ningún camino que lo haga, y no se
///    finge que exista.
///
/// Esta pantalla enseña **siempre la activa**, así que su título ya no puede mentir.
///
/// ## El guardia de salida
///
/// La pregunta «hay cambios sin guardar» sigue existiendo, pero ya no la hace esta
/// pantalla al cambiar de empresa —no puede, porque ya no cambia de empresa—: se
/// registra en el [GuardiaDeSalida] del marco, y la hace **la barra** antes de cambiar.
/// Al cancelar la edición la pregunta sí es de aquí, porque la salida es de aquí.
class EmpresasWebScreen extends StatefulWidget {
  const EmpresasWebScreen({
    required this.repositorio,
    required this.logotipos,
    required this.gestorDeCompany,
    required this.empresaActivaId,
    required this.puedeEditar,
    required this.guardia,
    required this.organizationId,
    required this.repositorioDeEmpresas,
    required this.cacheDeLogotipos,
    required this.editando,
    required this.administrando,
    required this.alIrADentro,
    this.autoridad,
    this.alCambiarLasEmpresas,
    super.key,
  });

  final ExpedientesRepositorioHttp repositorio;

  /// El logotipo no va por el repositorio de expedientes: son rutas de archivos, con
  /// su propio contrato y sus propios errores.
  ///
  /// **Llega construido, como los otros seis repositorios.** Recibir el cliente HTTP y
  /// armarlo aquí habría hecho que una pantalla hablara HTTP, que es justo lo que el
  /// guardia de arquitectura vigila — y con razón: la composición vive en el arranque.
  ///
  /// (Y el guardia **no ignora los comentarios**, así que ni este texto puede nombrar
  /// la carpeta prohibida. Es deliberado por su parte: una lista de excepciones que se
  /// pudiera sortear con un comentario no sería una lista.)
  final LogotipoRepositorioHttp logotipos;

  /// Quien cambia la empresa activa. **No se simula con un `setState`**: el marco
  /// entero depende del contexto que este gestor publica.
  ///
  /// ⚠️ **ESTA PANTALLA NO RESUELVE LA EMPRESA, y la diferencia es la que vigila el
  /// guardia de arquitectura:** «no es quién menciona Company, es quién decide cuál
  /// es». Aquí se recibe la lista ya resuelta y se llama a `cambiarA` — exactamente la
  /// forma del selector de empresa, que es la que ese guardia ya admite. El
  /// descubrimiento —`GET /companies`, la preferencia recordada, el contexto— sigue
  /// ocurriendo en un solo sitio.
  final GestorDeCompany gestorDeCompany;

  final String empresaActivaId;

  /// Dónde se registra que hay trabajo sin guardar, para que **la barra** pueda
  /// preguntar antes de cambiar de empresa.
  ///
  /// Se recibe y no se crea: el guardia es uno por sesión y lo reparte el portón. Uno
  /// por pantalla no serviría de nada — nadie de arriba sabría a quién preguntar.
  final GuardiaDeSalida guardia;

  /// `company.settings.manage`. Gobierna **el botón «Editar»** y, dentro, los campos.
  final bool puedeEditar;

  // --- E2 · la pestaña de administración -----------------------------------

  final String organizationId;
  final EmpresasRepositorioHttp repositorioDeEmpresas;

  /// La caché de logotipos del portón. **Se comparte, no se crea aquí**: la usan también
  /// el selector y el menú de la barra, y una caché por pantalla volvería a descargar lo
  /// que otra acababa de traer.
  final LogotiposDeEmpresa cacheDeLogotipos;

  /// Qué puede hacer esta persona **sobre la Organization**.
  ///
  /// ⚠️ **NULA ES EL CASO DE LA MAYORÍA**, y no un error: un Maestro que no es miembro de
  /// la Organization administra *su* empresa y no da de alta empresas. Con nula, la
  /// pestaña de administración **no existe** — ni vacía ni deshabilitada: no está.
  ///
  /// También llega nula los primeros milisegundos, mientras la respuesta viaja. El efecto
  /// es el mismo y es el correcto: la pestaña aparece cuando se sabe que debe.
  final AutoridadDeOrganizacion? autoridad;

  /// Para avisar al marco de que su menú de empresas cambió: una desactivada o descartada
  /// desaparece de él, y una nueva aparece.
  ///
  /// Lleva **la empresa afectada, o nulo al crear**: con ella, el marco relee la lista y
  /// se queda donde está; sin ella tendría que volver a resolver, y resolver con varias
  /// empresas devuelve a «Elige una empresa».
  final ValueChanged<String?>? alCambiarLasEmpresas;

  // --- D-39 · dónde estás, que lo dice la dirección ------------------------

  /// ¿Está abierto el formulario del expediente? **Lo dice la dirección**:
  /// `/organizacion/empresa/editar`.
  ///
  /// ✅ **ERA UN `_Paso` DE ESTADO LOCAL, Y CON ÉL UN CALLBACK HACIA ARRIBA.** El portón
  /// dibuja el rastro y no se enteraba de que aquí dentro se había abierto un
  /// formulario, así que esta pantalla tenía que **anunciarlo** — y el anuncio se quedó
  /// pegado una vez, diciendo «Editar» estando en la administración. Eso era D-39: quien
  /// sabe dónde estás es la dirección, no un aviso que alguien tiene que acordarse de
  /// mandar.
  final bool editando;

  /// ¿Está abierta la administración de empresas?
  /// **Lo dice la dirección**: `/organizacion/empresa/administracion`.
  ///
  /// ⚠️ **NO CONCEDE NADA.** Pide autoridad de Organization, y eso el guardia del router
  /// no lo sabe —sólo entiende permisos de Company—, así que una dirección escrita a mano
  /// llega hasta aquí. Sin [autoridad] no se abre: se ve la ficha, igual que antes.
  final bool administrando;

  /// Pide abrir algo de dentro, o volver a la ficha con nulo.
  ///
  /// Recibe `'editar'` o `'administracion'`. **Es un nombre y no una dirección**: quien
  /// conoce la ruta del apartado es el portón, y así esta pantalla sigue sin saber que
  /// existe un router.
  final ValueChanged<String?> alIrADentro;

  @override
  State<EmpresasWebScreen> createState() => _EmpresasWebScreenState();
}

/// En qué paso está la pantalla. **La lista ya no es un paso** (E1-B): se fue a E2.
enum _Paso { ficha, editando }

class _EmpresasWebScreenState extends State<EmpresasWebScreen> {
  /// En qué paso está la pantalla, **derivado de la dirección** (D-39).
  ///
  /// **SIEMPRE SE ENTRA POR LA FICHA**, con una empresa o con veinte: una dirección sin
  /// nada dentro es la ficha, y antes, con varias, se entraba por una lista en la que
  /// tocar una fila cambiaba la empresa activa. Lo explica la cabecera de la pantalla.
  ///
  /// **Y DERIVARLO ARREGLA UNA SEGUNDA COSA DE PASO:** al pasar a la administración
  /// había que acordarse de cerrar el formulario a mano —`_paso = _Paso.ficha`—, o
  /// volver a la ficha reabría un formulario vacío dando a entender que lo escrito
  /// seguía ahí. Ahora la dirección no puede decir las dos cosas a la vez.
  _Paso get _paso => widget.editando ? _Paso.editando : _Paso.ficha;

  /// Qué vista se está mirando, **derivada de la dirección**. La ficha es lo que se
  /// consulta a diario; la administración es lo que se abre de vez en cuando.
  _Vista get _vista => widget.administrando ? _Vista.administracion : _Vista.ficha;

  Failure? _fallo;
  bool _cargando = true;

  /// El expediente de la empresa activa, para la ficha.
  ExpedienteDeEmpresa? _expediente;
  Uint8List? _logotipo;

  /// El catálogo del SAT, **para que la ficha diga el régimen con su descripción**.
  ///
  /// El expediente sólo trae el código, y un «601» a secas no le sirve a quien recibe
  /// la tarjeta fiscal. Se pide aquí y no en la ficha porque la ficha es un widget sin
  /// estado: pedirlo allí la convertiría en una pantalla con carga propia.
  ///
  /// **Si no llega, no se bloquea nada**: la ficha enseña el código solo, que es lo
  /// único que se sabe.
  List<RegimenFiscal> _regimenes = const [];

  /// Si el logotipo no se pudo traer. **Distinto de no tener logotipo**: confundirlos
  /// haría pensar que se perdió.
  bool _logotipoFallo = false;

  /// Lo pregunta el formulario cuando se intenta salir con cambios.
  bool Function()? _hayCambiosSinGuardar;

  @override
  void initState() {
    super.initState();

    // SE REGISTRA AL MONTARSE Y SE LIBERA AL DESMONTARSE, como un controller. Lo que se
    // registra es un método de este estado, no el `_hayCambiosSinGuardar` de dentro:
    // ése lo pone el formulario más tarde, y pasar la referencia ahora registraría un
    // nulo para siempre.
    widget.guardia.registrar(_hayTrabajoSinGuardar);

    _cargar();
  }

  @override
  void dispose() {
    widget.guardia.liberar(_hayTrabajoSinGuardar);
    super.dispose();
  }

  /// Lo que el guardia del marco pregunta antes de cambiar de empresa.
  ///
  /// Sólo hay algo que perder **con el formulario abierto**: la ficha es de sólo
  /// lectura, y responder «sí» desde ella haría preguntar por nada en cada cambio.
  bool _hayTrabajoSinGuardar() =>
      _paso == _Paso.editando && (_hayCambiosSinGuardar?.call() ?? false);

  @override
  void didUpdateWidget(EmpresasWebScreen anterior) {
    super.didUpdateWidget(anterior);

    // LA EMPRESA ACTIVA CAMBIÓ POR FUERA —desde el selector del marco— así que lo que
    // esta pantalla tiene cargado ya no es de esa empresa.
    if (anterior.empresaActivaId != widget.empresaActivaId) _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _fallo = null;
      _logotipoFallo = false;
    });

    // LAS TRES PETICIONES A LA VEZ: son independientes y encadenarlas triplicaría la
    // espera de abrir la pestaña. **La lista no se pide**: llega del marco.
    //
    // EL CATÁLOGO DEL SAT SIN FILTRAR POR RFC, a propósito: aquí no se elige un
    // régimen, se NOMBRA el que ya está guardado, y un catálogo filtrado podría no
    // traer el de esta empresa —si su RFC cambió de longitud, o si el régimen se
    // retiró— y la ficha enseñaría el código pelado teniendo la descripción a mano.
    final (expediente, logotipo, regimenes) = await (
      widget.repositorio.leerDeEmpresa(widget.empresaActivaId),
      widget.logotipos.leer(widget.empresaActivaId),
      widget.repositorio.listarRegimenes(empresaId: widget.empresaActivaId),
    ).wait;

    if (!mounted) return;

    setState(() {
      _cargando = false;

      expediente.when(
        ok: (e) => _expediente = e,
        failure: (f) => _fallo = f,
      );

      logotipo.when(
        ok: (bytes) => _logotipo = bytes,
        failure: (_) {
          _logotipo = null;
          _logotipoFallo = true;
        },
      );

      regimenes.when(
        ok: (lista) => _regimenes = lista,
        // EL CATÁLOGO QUE NO SE PUDO LEER NO BLOQUEA LA FICHA: se enseña el código
        // del régimen sin su descripción, que es lo único que se sabe. Negar la ficha
        // entera por no poder adornar un campo sería desproporcionado.
        failure: (_) => _regimenes = const [],
      );
    });
  }

  /// Pide abrir o cerrar el formulario del expediente.
  ///
  /// ✅ **ERA UN `setState` Y AHORA ES UNA NAVEGACIÓN** (D-39), así que abrir el
  /// formulario deja una entrada en el historial del navegador: «atrás» devuelve a la
  /// ficha, que es lo que cualquiera espera.
  void _ir(_Paso paso) =>
      widget.alIrADentro(paso == _Paso.editando ? 'editar' : null);

  /// Cambia de vista, **preguntando antes de tirar trabajo**.
  ///
  /// ⚠️ **PREGUNTA ANTES DE TIRAR TRABAJO.** Encontrado el 22 de octubre de 2026 al
  /// arreglar el rastro: el selector de vista llamaba a `setState` directo, así que
  /// pasar a Administración con el expediente a medio escribir **perdía lo escrito en
  /// silencio** —la vista nueva reemplaza el subárbol y el formulario se construye de
  /// cero—.
  ///
  /// Es la misma regla que E1-B puso para cambiar de empresa y la que M3 puso para el
  /// 409: **el trabajo de una persona no se tira sin preguntárselo.** Y se usa el mismo
  /// diálogo, no uno parecido.
  ///
  /// ⏳(D-56) **La pregunta la hace quien sale por aquí, no quien sale con «atrás».** El
  /// botón del navegador, recargar y cerrar la pestaña siguen tirando lo escrito sin
  /// preguntar, y los tres se cierran dentro de C1 — `GoRoute.onExit` y `beforeunload`.
  ///
  /// ✅ **Y LO QUE AQUÍ SOBRABA ERA ANUNCIAR EL RASTRO.** Antes sólo `_ir` lo anunciaba,
  /// así que cambiar de vista no lo tocaba y arriba seguía leyéndose «Empresa › Editar»
  /// estando en la administración. Ahora el rastro sale de la dirección, y una dirección
  /// no puede quedarse diciendo dónde estabas.
  Future<void> _irALaVista(_Vista vista) async {
    if (vista == _vista) return;

    if (vista == _Vista.administracion &&
        !await _seguroDeSalir('administrar las empresas')) {
      return;
    }

    if (!mounted) return;

    widget.alIrADentro(vista == _Vista.administracion ? 'administracion' : null);
  }

  /// ¿Se puede salir sin perder trabajo?
  ///
  /// Con el formulario cerrado, siempre. Con cambios sin guardar, lo decide la persona
  /// — y el escritorio ya confirma al cancelar el expediente de empresa, así que el
  /// recorrido se copia en vez de inventarse.
  Future<bool> _seguroDeSalir(String queSeVaAHacer) async {
    if (_paso != _Paso.editando) return true;
    if (!(_hayCambiosSinGuardar?.call() ?? false)) return true;

    final confirmado = await RisegDialog.showConfirmation(
      context: context,
      title: 'Hay cambios sin guardar',
      message:
          'Si eliges $queSeVaAHacer se perderá lo que escribiste en el expediente.',
      confirmLabel: 'Descartar los cambios',
      cancelLabel: 'Seguir editando',
    );

    return confirmado ?? false;
  }

  // =========================================================================
  // El logotipo
  // =========================================================================

  Future<void> _logotipoCambio(Uint8List? bytes) async {
    if (!mounted) return;

    setState(() {
      // LA INSTANCIA ES NUEVA, y de eso depende que la imagen se repinte:
      // `MemoryImage` compara por identidad de la lista, así que reusar la misma
      // dejaría la imagen vieja en pantalla y parecería que no se guardó.
      _logotipo = bytes;
      _logotipoFallo = false;
    });
  }

  // =========================================================================
  // Pintar
  // =========================================================================

  @override
  Widget build(BuildContext context) {
    if (_cargando) {
      return const Center(child: CircularProgressIndicator());
    }

    final expediente = _expediente;

    if (expediente == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _fallo?.message ?? 'No se pudo cargar el expediente.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.md),
              RisegButton(label: 'Volver a intentar', onPressed: _cargar),
            ],
          ),
        ),
      );
    }

    // LA PESTAÑA DE ADMINISTRACIÓN SE ENVUELVE ALREDEDOR DE LA FICHA, y no es un apartado
    // del menú: el registro de apartados sólo entiende permisos de COMPANY, y esta
    // pestaña pide autoridad de ORGANIZATION. Enseñarla desde allí habría exigido
    // enseñarle al registro un segundo sistema de autoridad.
    //
    // Y SÓLO EXISTE CON AUTORIDAD: sin ella no se pinta ni el selector de pestañas, así
    // que quien no administra la organización ve exactamente lo que veía antes.
    final conAdministracion = widget.autoridad?.puedeAdministrarEmpresas ?? false;

    if (conAdministracion && _vista == _Vista.administracion) {
      return Column(
        children: [
          _SelectorDeVista(vista: _vista, alElegir: _irALaVista),
          Expanded(
            child: EmpresasAdministracionScreen(
              repositorio: widget.repositorioDeEmpresas,
              logotipos: widget.cacheDeLogotipos,
              organizationId: widget.organizationId,
              autoridad: widget.autoridad!,
              empresaActivaId: widget.empresaActivaId,
              alCambiarLaLista: widget.alCambiarLasEmpresas,
            ),
          ),
        ],
      );
    }

    final contenido = switch (_paso) {
      _Paso.ficha => EmpresaFicha(
        expediente: expediente,
        regimenes: _regimenes,
        logotipo: _logotipo,
        logotipoFallo: _logotipoFallo,
        puedeEditar: widget.puedeEditar,
        // YA NO HAY A DÓNDE VOLVER: la ficha es la entrada. El «‹ Empresas» llevaba a
        // la lista que se fue a E2.
        onVolverALaLista: null,
        onEditar: () => _ir(_Paso.editando),
        onReintentarLogotipo: _cargar,
      ),
      _Paso.editando => EmpresaWebScreen(
        repositorio: widget.repositorio,
        logotipos: widget.logotipos,
        empresaId: widget.empresaActivaId,
        puedeEditar: widget.puedeEditar,
        logotipo: _logotipo,
        alCambiarElLogotipo: _logotipoCambio,
        // GUARDAR CIERRA, y la ficha se pinta con lo que el `PUT` devolvió: pedirlo
        // otra vez sería una petición que no puede traer nada nuevo.
        alGuardar: (e) {
          setState(() {
            _expediente = e;

          });

          _ir(_Paso.ficha);

          // EL MENÚ DE LA BARRA DICE EL NOMBRE NUEVO. La lista se obtuvo al entrar y
          // `revalidar()` sólo recarga el contexto, no la lista: sin esto, la barra
          // diría el nombre nuevo y su propio menú el viejo, a un clic de distancia.
          //
          // **Se anota en el gestor y no en una copia local**, que es lo que hacía
          // antes esta pantalla: la lista tiene un dueño, y ahora la leen dos sitios
          // —el menú y el selector—, así que una copia parcheada aquí dejaría al menú
          // con el nombre viejo de todas formas.
          widget.gestorDeCompany.anotarRenombrado(
            widget.empresaActivaId,
            nombre: e.nombre,
            razonSocial: e.razonSocial,
          );

          // ⚠️ **Y LA BARRA INFERIOR TAMBIÉN**, que es lo que no se ve desde aquí: el
          // pie del marco y el rastro pintan `contexto.companyName`, que viene del
          // contexto que el servidor confirmó. Sin revalidar, el nombre nuevo saldría
          // en la ficha y el viejo abajo, en la misma pantalla.
          //
          // **Lo pide el gestor, no esta pantalla**: revalidar es resolver, y la
          // resolución vive en un solo sitio.
          widget.gestorDeCompany.revalidar();
        },
        alCancelar: () async {
          if (await _seguroDeSalir('salir')) _ir(_Paso.ficha);
        },
        alVigilarCambios: (hayCambios) => _hayCambiosSinGuardar = hayCambios,
      ),
    };

    // SIN AUTORIDAD, LA FICHA SE DEVUELVE SOLA: ni un selector de pestañas de una
    // pestaña, ni un hueco donde iría. Quien no administra la organización ve
    // exactamente lo que veía antes de E2.
    if (!conAdministracion) return contenido;

    return Column(
      children: [
        _SelectorDeVista(vista: _vista, alElegir: _irALaVista),
        Expanded(child: contenido),
      ],
    );
  }
}

/// Qué se está viendo de Empresa: su ficha, o la administración de todas.
enum _Vista { ficha, administracion }

/// El selector de las dos vistas.
///
/// **Segmentado y no pestañas de Material**: las pestañas de verdad las pinta la barra
/// superior del marco —«Organización › Empresa»— y meter unas segundas, idénticas, a dos
/// centímetros haría que nadie supiera cuáles manda.
class _SelectorDeVista extends StatelessWidget {
  const _SelectorDeVista({required this.vista, required this.alElegir});

  final _Vista vista;
  final ValueChanged<_Vista> alElegir;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.borderSubtle)),
      ),
      child: Row(
        children: [
          SegmentedButton<_Vista>(
            key: const Key('empresa_selector_de_vista'),
            segments: const [
              ButtonSegment<_Vista>(
                value: _Vista.ficha,
                label: Text('Ficha'),
                icon: Icon(Icons.badge_outlined, size: 18),
              ),
              ButtonSegment<_Vista>(
                value: _Vista.administracion,
                label: Text('Administración'),
                icon: Icon(Icons.apartment_outlined, size: 18),
              ),
            ],
            selected: {vista},
            showSelectedIcon: false,
            onSelectionChanged: (elegido) => alElegir(elegido.first),
          ),
        ],
      ),
    );
  }
}
