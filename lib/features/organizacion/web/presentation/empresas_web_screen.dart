import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../../core/company/gestor_de_company.dart';
import '../../../../core/company/guardia_de_salida.dart';
import '../../../../core/design_system/design_system_web.dart';
import '../../../../core/error/failure.dart';
import '../datos/expedientes_repositorio_http.dart';
import '../datos/logotipo_repositorio_http.dart';
import '../modelos/expediente.dart';
import 'empresa_ficha.dart';
import 'empresa_web_screen.dart';

/// La pestaÃ±a **Empresa**: la ficha de **la empresa activa**, y su ediciÃ³n.
///
/// ## Por quÃ© dos pasos y no un formulario siempre abierto
///
/// Hasta el 21 de octubre de 2026 esta pestaÃ±a **era** un formulario: se entraba
/// directamente a diecisÃ©is campos editables. Y lo que se hace a diario es mirar el RFC
/// para dÃ¡rselo a alguien, no cambiarlo; ademÃ¡s los datos fiscales no se veÃ­an con la
/// forma en que se entregan, que es la de la tarjeta fiscal.
///
/// AsÃ­ que el recorrido es **ficha â†’ editar**, y editar **cierra al guardar**.
///
/// ## ðŸš« AQUÃ NO HAY LISTA DE EMPRESAS, y la hubo durante tres dÃ­as
///
/// E1 hizo de la lista la entrada: con varias empresas se veÃ­a la lista, y **tocar una
/// fila abrÃ­a su expediente Y cambiaba la empresa activa**. Se programÃ³ asÃ­, funcionÃ³
/// asÃ­, y en cuanto hubo una segunda empresa apareciÃ³ el problema de verdad:
/// **consultar no es cambiar.** Mirar la ficha de otra empresa movÃ­a el contexto de
/// trabajo entero â€”menÃº, permisos, barra inferiorâ€” sin que nadie lo hubiera pedido, y
/// el siguiente guardado habrÃ­a ido a la empresa que se estaba *mirando*.
///
/// No era un defecto de implementaciÃ³n: la decisiÃ³n juntaba dos verbos con expectativas
/// opuestas â€”consultar espera que no cambie nada; cambiar espera que cambie todoâ€” en un
/// solo gesto. AsÃ­ que se separaron (E1-B):
///
///  Â· **cambiar de empresa** se hace **sÃ³lo desde la barra inferior**, con un menÃº que
///    dice en voz alta lo que hace y avisa despuÃ©s: Â«Ahora trabajas en XÂ»;
///  Â· **consultar la ficha de otra empresa sin activarla** serÃ¡ parte de **E2**, la
///    administraciÃ³n de empresas. Hoy no existe ningÃºn camino que lo haga, y no se
///    finge que exista.
///
/// Esta pantalla enseÃ±a **siempre la activa**, asÃ­ que su tÃ­tulo ya no puede mentir.
///
/// ## El guardia de salida
///
/// La pregunta Â«hay cambios sin guardarÂ» sigue existiendo, pero ya no la hace esta
/// pantalla al cambiar de empresa â€”no puede, porque ya no cambia de empresaâ€”: se
/// registra en el [GuardiaDeSalida] del marco, y la hace **la barra** antes de cambiar.
/// Al cancelar la ediciÃ³n la pregunta sÃ­ es de aquÃ­, porque la salida es de aquÃ­.
class EmpresasWebScreen extends StatefulWidget {
  const EmpresasWebScreen({
    required this.repositorio,
    required this.logotipos,
    required this.gestorDeCompany,
    required this.empresaActivaId,
    required this.puedeEditar,
    required this.guardia,
    this.alCambiarElRastro,
    super.key,
  });

  final ExpedientesRepositorioHttp repositorio;

  /// El logotipo no va por el repositorio de expedientes: son rutas de archivos, con
  /// su propio contrato y sus propios errores.
  ///
  /// **Llega construido, como los otros seis repositorios.** Recibir el cliente HTTP y
  /// armarlo aquÃ­ habrÃ­a hecho que una pantalla hablara HTTP, que es justo lo que el
  /// guardia de arquitectura vigila â€” y con razÃ³n: la composiciÃ³n vive en el arranque.
  ///
  /// (Y el guardia **no ignora los comentarios**, asÃ­ que ni este texto puede nombrar
  /// la carpeta prohibida. Es deliberado por su parte: una lista de excepciones que se
  /// pudiera sortear con un comentario no serÃ­a una lista.)
  final LogotipoRepositorioHttp logotipos;

  /// Quien cambia la empresa activa. **No se simula con un `setState`**: el marco
  /// entero depende del contexto que este gestor publica.
  ///
  /// âš ï¸ **ESTA PANTALLA NO RESUELVE LA EMPRESA, y la diferencia es la que vigila el
  /// guardia de arquitectura:** Â«no es quiÃ©n menciona Company, es quiÃ©n decide cuÃ¡l
  /// esÂ». AquÃ­ se recibe la lista ya resuelta y se llama a `cambiarA` â€” exactamente la
  /// forma del selector de empresa, que es la que ese guardia ya admite. El
  /// descubrimiento â€”`GET /companies`, la preferencia recordada, el contextoâ€” sigue
  /// ocurriendo en un solo sitio.
  final GestorDeCompany gestorDeCompany;

  final String empresaActivaId;

  /// DÃ³nde se registra que hay trabajo sin guardar, para que **la barra** pueda
  /// preguntar antes de cambiar de empresa.
  ///
  /// Se recibe y no se crea: el guardia es uno por sesiÃ³n y lo reparte el portÃ³n. Uno
  /// por pantalla no servirÃ­a de nada â€” nadie de arriba sabrÃ­a a quiÃ©n preguntar.
  final GuardiaDeSalida guardia;

  /// `company.settings.manage`. Gobierna **el botÃ³n Â«EditarÂ»** y, dentro, los campos.
  final bool puedeEditar;

  /// El tercer segmento del rastro: Â«OrganizaciÃ³n â€º Empresa â€º EditarÂ».
  final ValueChanged<String?>? alCambiarElRastro;

  @override
  State<EmpresasWebScreen> createState() => _EmpresasWebScreenState();
}

/// En quÃ© paso estÃ¡ la pantalla. **La lista ya no es un paso** (E1-B): se fue a E2.
enum _Paso { ficha, editando }

class _EmpresasWebScreenState extends State<EmpresasWebScreen> {
  /// **SIEMPRE SE ENTRA POR LA FICHA**, con una empresa o con veinte.
  ///
  /// Antes, con varias, se entraba por una lista en la que tocar una fila cambiaba la
  /// empresa activa. Lo explica la cabecera de la pantalla.
  _Paso _paso = _Paso.ficha;

  Failure? _fallo;
  bool _cargando = true;

  /// El expediente de la empresa activa, para la ficha.
  ExpedienteDeEmpresa? _expediente;
  Uint8List? _logotipo;

  /// El catÃ¡logo del SAT, **para que la ficha diga el rÃ©gimen con su descripciÃ³n**.
  ///
  /// El expediente sÃ³lo trae el cÃ³digo, y un Â«601Â» a secas no le sirve a quien recibe
  /// la tarjeta fiscal. Se pide aquÃ­ y no en la ficha porque la ficha es un widget sin
  /// estado: pedirlo allÃ­ la convertirÃ­a en una pantalla con carga propia.
  ///
  /// **Si no llega, no se bloquea nada**: la ficha enseÃ±a el cÃ³digo solo, que es lo
  /// Ãºnico que se sabe.
  List<RegimenFiscal> _regimenes = const [];

  /// Si el logotipo no se pudo traer. **Distinto de no tener logotipo**: confundirlos
  /// harÃ­a pensar que se perdiÃ³.
  bool _logotipoFallo = false;

  /// Lo pregunta el formulario cuando se intenta salir con cambios.
  bool Function()? _hayCambiosSinGuardar;

  @override
  void initState() {
    super.initState();

    // SE REGISTRA AL MONTARSE Y SE LIBERA AL DESMONTARSE, como un controller. Lo que se
    // registra es un mÃ©todo de este estado, no el `_hayCambiosSinGuardar` de dentro:
    // Ã©se lo pone el formulario mÃ¡s tarde, y pasar la referencia ahora registrarÃ­a un
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
  /// SÃ³lo hay algo que perder **con el formulario abierto**: la ficha es de sÃ³lo
  /// lectura, y responder Â«sÃ­Â» desde ella harÃ­a preguntar por nada en cada cambio.
  bool _hayTrabajoSinGuardar() =>
      _paso == _Paso.editando && (_hayCambiosSinGuardar?.call() ?? false);

  @override
  void didUpdateWidget(EmpresasWebScreen anterior) {
    super.didUpdateWidget(anterior);

    // LA EMPRESA ACTIVA CAMBIÃ“ POR FUERA â€”desde el selector del marcoâ€” asÃ­ que lo que
    // esta pantalla tiene cargado ya no es de esa empresa.
    if (anterior.empresaActivaId != widget.empresaActivaId) _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _fallo = null;
      _logotipoFallo = false;
    });

    // LAS TRES PETICIONES A LA VEZ: son independientes y encadenarlas triplicarÃ­a la
    // espera de abrir la pestaÃ±a. **La lista no se pide**: llega del marco.
    //
    // EL CATÃLOGO DEL SAT SIN FILTRAR POR RFC, a propÃ³sito: aquÃ­ no se elige un
    // rÃ©gimen, se NOMBRA el que ya estÃ¡ guardado, y un catÃ¡logo filtrado podrÃ­a no
    // traer el de esta empresa â€”si su RFC cambiÃ³ de longitud, o si el rÃ©gimen se
    // retirÃ³â€” y la ficha enseÃ±arÃ­a el cÃ³digo pelado teniendo la descripciÃ³n a mano.
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
        // EL CATÃLOGO QUE NO SE PUDO LEER NO BLOQUEA LA FICHA: se enseÃ±a el cÃ³digo
        // del rÃ©gimen sin su descripciÃ³n, que es lo Ãºnico que se sabe. Negar la ficha
        // entera por no poder adornar un campo serÃ­a desproporcionado.
        failure: (_) => _regimenes = const [],
      );
    });
  }

  void _ir(_Paso paso) {
    setState(() => _paso = paso);

    widget.alCambiarElRastro?.call(switch (paso) {
      _Paso.ficha => null,
      _Paso.editando => 'Editar',
    });
  }

  /// Â¿Se puede salir sin perder trabajo?
  ///
  /// Con el formulario cerrado, siempre. Con cambios sin guardar, lo decide la persona
  /// â€” y el escritorio ya confirma al cancelar el expediente de empresa, asÃ­ que el
  /// recorrido se copia en vez de inventarse.
  Future<bool> _seguroDeSalir(String queSeVaAHacer) async {
    if (_paso != _Paso.editando) return true;
    if (!(_hayCambiosSinGuardar?.call() ?? false)) return true;

    final confirmado = await RisegDialog.showConfirmation(
      context: context,
      title: 'Hay cambios sin guardar',
      message:
          'Si eliges $queSeVaAHacer se perderÃ¡ lo que escribiste en el expediente.',
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
      // `MemoryImage` compara por identidad de la lista, asÃ­ que reusar la misma
      // dejarÃ­a la imagen vieja en pantalla y parecerÃ­a que no se guardÃ³.
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

    return switch (_paso) {
      _Paso.ficha => EmpresaFicha(
        expediente: expediente,
        regimenes: _regimenes,
        logotipo: _logotipo,
        logotipoFallo: _logotipoFallo,
        puedeEditar: widget.puedeEditar,
        // YA NO HAY A DÃ“NDE VOLVER: la ficha es la entrada. El Â«â€¹ EmpresasÂ» llevaba a
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
        // GUARDAR CIERRA, y la ficha se pinta con lo que el `PUT` devolviÃ³: pedirlo
        // otra vez serÃ­a una peticiÃ³n que no puede traer nada nuevo.
        alGuardar: (e) {
          setState(() {
            _expediente = e;

          });

          _ir(_Paso.ficha);

          // EL MENÃš DE LA BARRA DICE EL NOMBRE NUEVO. La lista se obtuvo al entrar y
          // `revalidar()` sÃ³lo recarga el contexto, no la lista: sin esto, la barra
          // dirÃ­a el nombre nuevo y su propio menÃº el viejo, a un clic de distancia.
          //
          // **Se anota en el gestor y no en una copia local**, que es lo que hacÃ­a
          // antes esta pantalla: la lista tiene un dueÃ±o, y ahora la leen dos sitios
          // â€”el menÃº y el selectorâ€”, asÃ­ que una copia parcheada aquÃ­ dejarÃ­a al menÃº
          // con el nombre viejo de todas formas.
          widget.gestorDeCompany.anotarRenombrado(
            widget.empresaActivaId,
            nombre: e.nombre,
            razonSocial: e.razonSocial,
          );

          // âš ï¸ **Y LA BARRA INFERIOR TAMBIÃ‰N**, que es lo que no se ve desde aquÃ­: el
          // pie del marco y el rastro pintan `contexto.companyName`, que viene del
          // contexto que el servidor confirmÃ³. Sin revalidar, el nombre nuevo saldrÃ­a
          // en la ficha y el viejo abajo, en la misma pantalla.
          //
          // **Lo pide el gestor, no esta pantalla**: revalidar es resolver, y la
          // resoluciÃ³n vive en un solo sitio.
          widget.gestorDeCompany.revalidar();
        },
        alCancelar: () async {
          if (await _seguroDeSalir('salir')) _ir(_Paso.ficha);
        },
        alVigilarCambios: (hayCambios) => _hayCambiosSinGuardar = hayCambios,
      ),
    };
  }
}
