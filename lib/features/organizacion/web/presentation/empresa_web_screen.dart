import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../../core/design_system/design_system_web.dart';
import '../../../../core/error/failure.dart';
import '../datos/expedientes_repositorio_http.dart';
import '../datos/logotipo_repositorio_http.dart';
import '../modelos/choque_de_expediente.dart';
import '../modelos/expediente.dart';
import 'dialogo_de_choque.dart';
import 'dialogo_de_logotipo.dart';
import 'eliminar_estructura.dart';

/// El expediente de la EMPRESA: la pestaña que Organización no tenía.
///
/// ## Qué es y qué no
///
/// Es la identidad **fiscal y de contacto** de la empresa: razón social, RFC,
/// representante legal, eslogan, régimen fiscal, domicilio y contacto. **El nombre
/// comercial no se edita aquí** —se muestra— porque ya existía antes del expediente y
/// tiene su propio camino; y **el código humano de la empresa NO se trae**, por
/// decisión del dueño: en la nube la empresa ya es el límite de aislamiento y su
/// identidad es su `companyId`.
///
/// ## Las tres cosas que esta pantalla NO decide
///
///  · **si la tarjeta fiscal está lista** —razón social + RFC + domicilio—: lo manda
///    el servidor en `fiscalCardReady`. La regla vive en un solo sitio, y si la
///    pantalla la calculara serían dos listas que pueden discrepar;
///  · **si un régimen se puede elegir**: llega en `selectable`. Un régimen retirado
///    por el SAT se sigue mostrando —marcado— porque la empresa que lo tenía lo
///    conserva, pero no se ofrece para algo nuevo;
///  · **si el cruce de medianoche de un tramo**… eso es de la sucursal, pero la razón
///    es la misma: lo derivado lo deriva quien manda.
///
/// ## El 409 no es un error, es otra persona
///
/// Si alguien más guardó mientras este formulario estaba abierto, el servidor contesta
/// **409 `expediente_desactualizado`** y aquí **se recarga y se avisa**, en vez de
/// mostrar un error que nadie puede arreglar. Lo que no se hace es guardar encima: eso
/// borraría el trabajo del otro sin que ninguno de los dos se enterara.
///
/// <b>Importa `design_system_web.dart`, NUNCA el barrel completo</b>, que arrastra
/// `dart:io` y rompe la build web.
class EmpresaWebScreen extends StatefulWidget {
  const EmpresaWebScreen({
    required this.repositorio,
    required this.logotipos,
    required this.empresaId,
    required this.puedeEditar,
    required this.alGuardar,
    required this.alCancelar,
    this.logotipo,
    this.alCambiarElLogotipo,
    this.alVigilarCambios,
    super.key,
  });

  final ExpedientesRepositorioHttp repositorio;

  /// El logotipo va por su propio repositorio: son rutas de archivos, con su propio
  /// contrato y sus propios errores.
  final LogotipoRepositorioHttp logotipos;

  final String empresaId;

  /// Si quien mira tiene `company.settings.manage`.
  ///
  /// **Sólo gobierna si los campos se OFRECEN**, nunca si se puede guardar: eso lo
  /// decide el servidor en cada petición. Filtrar no es autorizar.
  final bool puedeEditar;

  /// Qué hacer cuando se guardó: **cerrar y volver a la ficha**.
  ///
  /// Recibe el expediente que devolvió el `PUT`, así que la ficha se pinta con él sin
  /// volver a pedirlo — pedirlo otra vez sería una petición que no puede traer nada
  /// nuevo.
  final ValueChanged<ExpedienteDeEmpresa> alGuardar;

  /// Qué hacer al cancelar. **Quien pregunta por los cambios sin guardar es el
  /// llamador**, no este formulario: la misma pregunta hace falta al cambiar de
  /// empresa desde la lista, y tenerla en dos sitios sería dos textos que divergen.
  final VoidCallback alCancelar;

  /// Los bytes del logotipo que la ficha ya trajo, para no volver a pedirlo al entrar
  /// a editar.
  final Uint8List? logotipo;

  /// Avisa de que el logotipo cambió, **para que la ficha lo pinte al volver**.
  final ValueChanged<Uint8List?>? alCambiarElLogotipo;

  /// Le entrega al llamador una forma de preguntar «¿hay cambios sin guardar?».
  ///
  /// **Se publica en vez de devolverse** porque la pregunta la hace el llamador en un
  /// momento que este widget no controla: al cancelar, o al tocar otra empresa en la
  /// lista.
  final ValueChanged<bool Function()>? alVigilarCambios;

  @override
  State<EmpresaWebScreen> createState() => _EmpresaWebScreenState();
}

class _EmpresaWebScreenState extends State<EmpresaWebScreen> {
  ExpedienteDeEmpresa? _expediente;
  List<RegimenFiscal> _regimenes = const [];
  Failure? _fallo;
  bool _cargando = true;
  bool _guardando = false;

  /// Los campos que el servidor señaló, por nombre de campo del contrato.
  Map<String, String> _erroresDeCampo = const {};

  /// Los nodos de foco, **en el orden del formulario y con la clave del servidor**.
  ///
  /// Aquí pesa más que en ninguna otra pantalla: son **dieciséis** campos y el botón
  /// de guardar está al final, así que un error en la razón social se pintaba fuera de
  /// la vista y para la persona el botón no había hecho nada.
  ///
  /// El régimen fiscal no está: es un selector y no se enfoca, así que a él se llega
  /// por su sección.
  final _focos = RisegFocosDeFormulario(const [
    'name',
    'legalName',
    'taxId',
    'legalRep',
    'slogan',
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
    'contact.phone',
    'contact.email',
    'contact.website',
  ]);

  /// La sección de la identidad fiscal, **para llegar al selector de régimen**, que no
  /// se puede enfocar.
  final _claveDeIdentidad = GlobalKey();

  /// El nombre comercial, **editable desde el 21 de octubre de 2026**.
  ///
  /// Antes se mostraba y no se podía cambiar por ningún camino: era una función del
  /// escritorio perdida, donde sí es un campo del expediente.
  final _nombre = TextEditingController();

  final _razonSocial = TextEditingController();
  final _rfc = TextEditingController();
  final _representante = TextEditingController();
  final _eslogan = TextEditingController();

  final _calle = TextEditingController();
  final _exterior = TextEditingController();
  final _interior = TextEditingController();
  final _colonia = TextEditingController();
  final _municipio = TextEditingController();
  final _ciudad = TextEditingController();
  final _estado = TextEditingController();
  final _cp = TextEditingController();
  final _pais = TextEditingController();
  final _referencias = TextEditingController();

  final _telefono = TextEditingController();
  final _correo = TextEditingController();
  final _sitio = TextEditingController();

  String? _regimen;

  /// Los regímenes que **ya se han visto**, por código.
  ///
  /// El catálogo llega FILTRADO por la longitud del RFC, así que al cambiar un RFC de
  /// empresa por uno de persona física el régimen elegido **desaparece de la lista**.
  /// Lo que se vio una vez se recuerda, y hace dos cosas que sin esto no se podrían:
  /// seguir diciendo «General de Ley Personas Morales» en vez de un código suelto, y
  /// saber **a qué tipo de persona aplica** cuando ya no está en la lista vigente.
  final Map<String, RegimenFiscal> _regimenesVistos = {};

  /// Todos los controllers, para liberarlos en un solo sitio.
  ///
  /// **Liberar un controller no es opcional y en este proyecto ya costó una vez.**
  /// Diecisiete `dispose()` escritos a mano son diecisiete oportunidades de olvidar
  /// uno, y el que se olvida no falla: sólo gotea.
  List<TextEditingController> get _todos => [
    _nombre,
    _razonSocial, _rfc, _representante, _eslogan,
    _calle, _exterior, _interior, _colonia, _municipio,
    _ciudad, _estado, _cp, _pais, _referencias,
    _telefono, _correo, _sitio,
  ];

  @override
  void initState() {
    super.initState();

    // SE LE ENTREGA AL LLAMADOR LA PREGUNTA, no la respuesta: el momento de hacerla
    // —cancelar, o tocar otra empresa en la lista— lo decide él.
    widget.alVigilarCambios?.call(() => _hayCambiosSinGuardar);

    _logotipo = widget.logotipo;
    _cargar();
  }

  /// Los bytes del logotipo que se están enseñando.
  ///
  /// Entra con lo que la ficha ya trajo, así que **abrir editar no vuelve a pedirlo**.
  Uint8List? _logotipo;

  bool _subiendoLogotipo = false;

  /// ¿Hay algo escrito que se perdería al salir?
  ///
  /// Se compara el formulario **contra el expediente cargado**, no contra un «se tocó
  /// algo»: escribir una letra y borrarla no es un cambio, y preguntar por eso enseña
  /// a contestar el diálogo sin leerlo.
  ///
  /// **El logotipo no cuenta**: se aplica al momento, así que nunca está pendiente de
  /// guardar.
  bool get _hayCambiosSinGuardar {
    final e = _expediente;
    if (e == null) return false;

    String? texto(TextEditingController c) {
      final t = c.text.trim();

      return t.isEmpty ? null : t;
    }

    if (_nombre.text.trim() != e.nombre) return true;
    if (texto(_razonSocial) != e.razonSocial) return true;
    if (texto(_rfc)?.toUpperCase() != e.rfc) return true;
    if (texto(_representante) != e.representanteLegal) return true;
    if (texto(_eslogan) != e.eslogan) return true;
    if (_regimen != e.regimenFiscal) return true;

    // EL DOMICILIO Y EL CONTACTO SE COMPARAN POR SU FORMA FINAL, la misma que se
    // mandaría: comparar campo a campo contra el modelo repetiría aquí las reglas de
    // «vacío del todo es nulo» y las dos acabarían discrepando.
    final direccion = _direccionDelFormulario();
    if ((direccion?.aJson().toString()) != (e.direccion?.aJson().toString())) {
      return true;
    }

    final contacto = _contactoDelFormulario();

    return (contacto?.aJson().toString()) != (e.contacto?.aJson().toString());
  }

  @override
  void dispose() {
    for (final c in _todos) {
      c.dispose();
    }

    _focos.dispose();

    super.dispose();
  }

  /// Lleva la vista y el cursor al **primer** campo señalado.
  ///
  /// El orden es el de la pantalla, no el de la respuesta: el servidor «reúne todos
  /// los errores antes de fallar» y el orden en que los enumera no lo controlamos.
  void _llevarLaVistaAlPrimerError() {
    if (_focos.llevarLaVistaAlPrimerError(_erroresDeCampo)) return;

    // EL RÉGIMEN NO SE PUEDE ENFOCAR: se llega a su sección.
    if (_erroresDeCampo.containsKey('fiscalRegimeCode')) {
      if (_claveDeIdentidad.currentContext case final contexto?) {
        risegLlevarLaVistaA(contexto);
      }
    }
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _fallo = null;
    });

    final resultado = await widget.repositorio.leerDeEmpresa(widget.empresaId);

    if (!mounted) return;

    resultado.when(
      ok: (e) {
        _volcarEnElFormulario(e);
        setState(() {
          _expediente = e;
          _cargando = false;
        });
        _cargarRegimenes();
      },
      failure: (f) => setState(() {
        _fallo = f;
        _cargando = false;
      }),
    );
  }

  /// El catálogo, **filtrado por el RFC que haya**.
  ///
  /// Si falla, la lista queda vacía y el selector lo dice — **no se bloquea el resto
  /// del formulario**: el domicilio y el contacto no dependen del SAT, y no dejar
  /// guardar un teléfono porque un catálogo no cargó sería castigar a la persona por
  /// una avería que no es suya.
  Future<void> _cargarRegimenes() async {
    final resultado = await widget.repositorio.listarRegimenes(
      empresaId: widget.empresaId,
      rfc: _rfc.text,
    );

    if (!mounted) return;

    resultado.when(
      ok: (lista) => setState(() {
        _regimenes = lista;

        // Se recuerda cada uno ANTES de que un filtro lo quite: esta lista ya viene
        // acotada por el RFC, y la siguiente lo estará por otro.
        for (final r in lista) {
          _regimenesVistos[r.codigo] = r;
        }
      }),
      failure: (_) => setState(() => _regimenes = const []),
    );
  }

  void _volcarEnElFormulario(ExpedienteDeEmpresa e) {
    _nombre.text = e.nombre;
    _razonSocial.text = e.razonSocial ?? '';
    _rfc.text = e.rfc ?? '';
    _representante.text = e.representanteLegal ?? '';
    _eslogan.text = e.eslogan ?? '';
    _regimen = e.regimenFiscal;

    final d = e.direccion;
    _calle.text = d?.calle ?? '';
    _exterior.text = d?.numeroExterior ?? '';
    _interior.text = d?.numeroInterior ?? '';
    _colonia.text = d?.colonia ?? '';
    _municipio.text = d?.municipio ?? '';
    _ciudad.text = d?.ciudad ?? '';
    _estado.text = d?.estado ?? '';
    _cp.text = d?.codigoPostal ?? '';
    _pais.text = d?.pais ?? '';
    _referencias.text = d?.referencias ?? '';

    final c = e.contacto;
    _telefono.text = c?.telefono ?? '';
    _correo.text = c?.correo ?? '';
    _sitio.text = c?.sitio ?? '';
  }

  // =========================================================================
  // Guardar
  // =========================================================================

  /// ¿Hay algo escrito en el domicilio?
  ///
  /// **Importa porque un domicilio a medias lo rechaza el motor**, y la frontera entre
  /// «no hay domicilio» y «hay uno incompleto» la marca esto: todos vacíos se manda
  /// `null` —que borra el que hubiera—, y con algo escrito se manda completo y el
  /// servidor señala lo que falte.
  bool get _hayAlgoDeDomicilio => [
    _calle, _exterior, _interior, _colonia, _municipio,
    _ciudad, _estado, _cp, _pais, _referencias,
  ].any((c) => c.text.trim().isNotEmpty);

  Direccion? _direccionDelFormulario() {
    if (!_hayAlgoDeDomicilio) return null;

    String? opcional(TextEditingController c) {
      final t = c.text.trim();

      return t.isEmpty ? null : t;
    }

    return Direccion(
      calle: _calle.text.trim(),
      numeroExterior: _exterior.text.trim(),
      colonia: _colonia.text.trim(),
      municipio: _municipio.text.trim(),
      estado: _estado.text.trim(),
      codigoPostal: _cp.text.trim(),
      numeroInterior: opcional(_interior),
      ciudad: opcional(_ciudad),
      pais: opcional(_pais),
      referencias: opcional(_referencias),
    );
  }

  Contacto? _contactoDelFormulario() {
    String? opcional(TextEditingController c) {
      final t = c.text.trim();

      return t.isEmpty ? null : t;
    }

    final contacto = Contacto(
      telefono: opcional(_telefono),
      correo: opcional(_correo),
      sitio: opcional(_sitio),
    );

    // VACÍO SE MANDA COMO NULO, no como un contacto de tres nulos: el servidor no
    // guarda una fila sin nada, y mandarla haría parecer que hay contacto.
    return contacto.estaVacio ? null : contacto;
  }

  Future<void> _guardar() async {
    final expediente = _expediente;
    if (expediente == null) return;

    setState(() {
      _guardando = true;
      _erroresDeCampo = const {};
    });

    String? texto(TextEditingController c) {
      final t = c.text.trim();

      return t.isEmpty ? null : t;
    }

    final resultado = await widget.repositorio.guardarDeEmpresa(
      empresaId: widget.empresaId,
      // SÓLO SI SE PUEDE EDITAR: nulo es «no lo toques», así que quien no tiene el
      // permiso no lo manda y el servidor no tiene que exigírselo por un campo que no
      // quiso cambiar.
      nombre: widget.puedeEditar ? _nombre.text.trim() : null,
      // LA VERSIÓN ES LA QUE SE LEYÓ AL ABRIR. No se recalcula ni se pide de nuevo
      // antes de guardar: hacerlo convertiría el candado en un adorno, porque
      // volvería a leer justo el valor que acaba de cambiar otra persona.
      version: expediente.version,
      razonSocial: texto(_razonSocial),
      rfc: texto(_rfc)?.toUpperCase(),
      representanteLegal: texto(_representante),
      eslogan: texto(_eslogan),
      regimenFiscal: _regimen,
      direccion: _direccionDelFormulario(),
      contacto: _contactoDelFormulario(),
    );

    if (!mounted) return;

    resultado.when(
      ok: (e) {
        _volcarEnElFormulario(e);
        setState(() {
          _expediente = e;
          _guardando = false;
        });

        RisegFeedback.showSuccess(context, 'Expediente de la empresa guardado.');

        // GUARDAR CIERRA Y VUELVE A LA FICHA, con el expediente que el `PUT` devolvió.
        //
        // Y SÓLO SI SALIÓ BIEN: cerrar con un error pendiente dejaría a la persona en
        // la ficha sin saber que su cambio no entró. Los caminos de fallo de abajo se
        // quedan en el formulario, con el campo señalado y la vista llevada a él.
        widget.alGuardar(e);
      },
      failure: (f) {
        setState(() => _guardando = false);

        if (ExpedientesRepositorioHttp.esDesactualizado(f)) {
          _resolverElChoque(f);

          return;
        }

        // EL RÉGIMEN NO DISPONIBLE VA AL CAMPO, no a un aviso que se va. Es un 422 con
        // su propio código y no trae `fields` —el servidor no lo manda como error de
        // entrada—, así que se traduce aquí: es el único error de este formulario que
        // se arregla en un control concreto, y decirlo en un recuadro flotante haría
        // buscar cuál de los quince campos es.
        if (f case ApiHttpFailure(codigo: 'regimen_no_disponible')) {
          setState(() => _erroresDeCampo = {'fiscalRegimeCode': f.message});
          _llevarLaVistaAlPrimerError();

          return;
        }

        final campos = ExpedientesRepositorioHttp.camposDe(f);

        if (campos.isNotEmpty) {
          // TODOS LOS CAMPOS A LA VEZ. El servidor «reúne todos los errores antes de
          // fallar» a propósito; mostrarlos de uno en uno obligaría a descubrirlos con
          // un guardado por cada uno.
          setState(() => _erroresDeCampo = campos);
          // Y LA VISTA VA AL PRIMERO: con el botón al final de dieciséis campos, un
          // error arriba se pintaba donde nadie estaba mirando.
          _llevarLaVistaAlPrimerError();

          return;
        }

        mostrarRechazoDelServidor(context, f.message);
      },
    );
  }

  // =========================================================================
  // El choque: cuando otra persona guardó mientras yo editaba
  // =========================================================================

  /// Cuántas veces se ha reintentado **sin preguntar** en este guardado.
  ///
  /// Un choque que se resuelve solo se reintenta sin molestar a nadie, y eso abre la
  /// puerta a dar vueltas si alguien guarda sin parar. Tres y después el aviso de
  /// siempre: es un tope, no una regla de negocio.
  int _reintentos = 0;

  /// Qué hacer con el 409 del candado optimista.
  ///
  /// **La misma pieza que el expediente de una sucursal**, y aquí pesa más: este
  /// formulario tiene **dieciséis** campos, así que recargarlo —lo que se hacía antes—
  /// podía tirar dieciséis datos escritos por un choque en uno.
  ///
  /// Con el expediente que el 409 trae, el que se cargó al abrir y el del formulario:
  /// lo que cambió sólo uno se queda sin preguntar, y **sólo se pregunta lo que los
  /// dos cambiaron a cosas distintas**.
  Future<void> _resolverElChoque(Failure fallo) async {
    final suyo = ExpedientesRepositorioHttp.actualDe(
      fallo,
      ExpedienteDeEmpresa.deJson,
    );

    // SIN EL EXPEDIENTE DEL SERVIDOR NO SE PUEDE COMPARAR: se avisa y se recarga, que
    // es lo que se hacía antes. Pasa con un servidor viejo.
    if (suyo == null || _expediente == null || _reintentos >= 3) {
      await _avisarSinPoderComparar();

      return;
    }

    final choque = _compararCon(suyo);

    if (choque.seResuelveSolo) {
      _aplicar(suyo, choque, const {});
      _reintentos++;
      await _guardar();

      return;
    }

    final elegidos = await mostrarDialogoDeChoque(
      context: context,
      choque: choque,
    );

    // CERRÓ EL AVISO: no se guarda y **no se toca el formulario**.
    if (elegidos == null || !mounted) return;

    _aplicar(suyo, choque, elegidos);
    _reintentos++;
    await _guardar();
  }

  /// Las tres versiones de cada campo: lo que se cargó, lo que hay escrito y lo suyo.
  ChoqueDeExpediente _compararCon(ExpedienteDeEmpresa suyo) {
    final base = _expediente!;
    final mia = _direccionDelFormulario();
    final mio = _contactoDelFormulario();

    CampoComparado deLaDireccion(
      String campo,
      String etiqueta,
      String? Function(Direccion) cual,
    ) => CampoComparado(
      campo: 'address.$campo',
      etiqueta: etiqueta,
      base: base.direccion == null ? null : cual(base.direccion!),
      mio: mia == null ? null : cual(mia),
      suyo: suyo.direccion == null ? null : cual(suyo.direccion!),
    );

    CampoComparado delContacto(
      String campo,
      String etiqueta,
      String? Function(Contacto) cual,
    ) => CampoComparado(
      campo: 'contact.$campo',
      etiqueta: etiqueta,
      base: base.contacto == null ? null : cual(base.contacto!),
      mio: mio == null ? null : cual(mio),
      suyo: suyo.contacto == null ? null : cual(suyo.contacto!),
    );

    String? texto(TextEditingController c) {
      final t = c.text.trim();

      return t.isEmpty ? null : t;
    }

    return ChoqueDeExpediente([
      CampoComparado(
        campo: 'legalName',
        etiqueta: 'Razón social',
        base: base.razonSocial,
        mio: texto(_razonSocial),
        suyo: suyo.razonSocial,
      ),
      CampoComparado(
        campo: 'taxId',
        etiqueta: 'RFC',
        base: base.rfc,
        mio: texto(_rfc)?.toUpperCase(),
        suyo: suyo.rfc,
      ),
      CampoComparado(
        campo: 'legalRep',
        etiqueta: 'Representante legal',
        base: base.representanteLegal,
        mio: texto(_representante),
        suyo: suyo.representanteLegal,
      ),
      CampoComparado(
        campo: 'slogan',
        etiqueta: 'Eslogan',
        base: base.eslogan,
        mio: texto(_eslogan),
        suyo: suyo.eslogan,
      ),
      CampoComparado(
        campo: 'fiscalRegimeCode',
        etiqueta: 'Régimen fiscal',
        base: base.regimenFiscal,
        mio: _regimen,
        suyo: suyo.regimenFiscal,
        // SE COMPARA EL CÓDIGO DEL SAT Y SE LEE CON SU NOMBRE: un «626» pelado no le
        // dice a nadie cuál de los dos regímenes es.
        comoSeLee: _etiquetaDelRegimen,
      ),
      deLaDireccion('street', 'Calle', (d) => d.calle),
      deLaDireccion('exteriorNumber', 'Número exterior', (d) => d.numeroExterior),
      deLaDireccion('interiorNumber', 'Número interior', (d) => d.numeroInterior),
      deLaDireccion('neighborhood', 'Colonia', (d) => d.colonia),
      deLaDireccion('municipality', 'Municipio', (d) => d.municipio),
      deLaDireccion('city', 'Ciudad', (d) => d.ciudad),
      deLaDireccion('state', 'Estado', (d) => d.estado),
      deLaDireccion('postalCode', 'Código postal', (d) => d.codigoPostal),
      deLaDireccion('country', 'País', (d) => d.pais),
      deLaDireccion('landmarks', 'Referencias', (d) => d.referencias),
      delContacto('phone', 'Teléfono', (c) => c.telefono),
      delContacto('email', 'Correo', (c) => c.correo),
      delContacto('website', 'Sitio web', (c) => c.sitio),
    ]);
  }

  /// Deja en el formulario el resultado de las elecciones, **y la versión del servidor
  /// como nueva base**: el siguiente guardado va con su contador.
  void _aplicar(
    ExpedienteDeEmpresa suyo,
    ChoqueDeExpediente choque,
    Map<String, bool> elegidos,
  ) {
    final valores = choque.resolver(elegidos);

    setState(() {
      _expediente = suyo;

      _razonSocial.text = valores['legalName'] ?? '';
      _rfc.text = valores['taxId'] ?? '';
      _representante.text = valores['legalRep'] ?? '';
      _eslogan.text = valores['slogan'] ?? '';
      _regimen = valores['fiscalRegimeCode'];

      _calle.text = valores['address.street'] ?? '';
      _exterior.text = valores['address.exteriorNumber'] ?? '';
      _interior.text = valores['address.interiorNumber'] ?? '';
      _colonia.text = valores['address.neighborhood'] ?? '';
      _municipio.text = valores['address.municipality'] ?? '';
      _ciudad.text = valores['address.city'] ?? '';
      _estado.text = valores['address.state'] ?? '';
      _cp.text = valores['address.postalCode'] ?? '';
      _pais.text = valores['address.country'] ?? '';
      _referencias.text = valores['address.landmarks'] ?? '';

      _telefono.text = valores['contact.phone'] ?? '';
      _correo.text = valores['contact.email'] ?? '';
      _sitio.text = valores['contact.website'] ?? '';
    });
  }

  /// `626 · Régimen Simplificado de Confianza`, o el código a secas si el catálogo
  /// todavía no se ha leído. **Nunca un hueco**: el aviso tiene que decir entre qué se
  /// elige.
  ///
  /// Mira primero la lista vigente y después [_etiquetasVistas], que es lo que salva el
  /// caso en el que el régimen elegido **ya no está** en una lista filtrada por un RFC
  /// nuevo: ahí es justamente cuando hay que nombrarlo bien.
  String _etiquetaDelRegimen(String? codigo) {
    if (codigo == null) return 'Sin régimen';

    for (final r in _regimenes) {
      if (r.codigo == codigo) return r.etiqueta;
    }

    return _regimenesVistos[codigo]?.etiqueta ?? codigo;
  }

  /// ¿El régimen elegido **contradice** al RFC escrito?
  ///
  /// Se decide con los datos —el régimen dice a qué persona aplica, y la longitud del
  /// RFC dice cuál es— y **no** con «desapareció de la lista». Son dos preguntas
  /// distintas y conviene no confundirlas: la ausencia también la causaría un catálogo
  /// que no cargó, y de ahí saldría un aviso inventado.
  ///
  /// **Falso cuando no se sabe**: sin el régimen en la caché o sin una longitud de RFC
  /// que signifique algo, no hay nada que contradecir. *Ausencia nunca es cero.*
  bool get _elRegimenContradiceAlRfc {
    final elegido = _regimen;
    if (elegido == null) return false;

    final regimen = _regimenesVistos[elegido];
    if (regimen == null) return false;

    return switch (_rfc.text.trim().length) {
      12 => !regimen.personaMoral,
      13 => !regimen.personaFisica,
      _ => false,
    };
  }

  /// Alguien más guardó y no se puede comparar: se recarga y se dice **qué pasó y qué
  /// hacer**.
  ///
  /// No se guarda encima y no se ofrece «forzar»: el trabajo del otro no es un
  /// obstáculo que esta pantalla pueda apartar.
  Future<void> _avisarSinPoderComparar() => showDialog<void>(
      context: context,
      builder: (contexto) => AlertDialog(
        title: const Text('Alguien más guardó este expediente'),
        content: const Text(
          'Mientras tenías el formulario abierto, otra persona guardó cambios en el '
          'expediente de la empresa. Para no borrar su trabajo, no se guardó nada.\n\n'
          'Se van a cargar los datos más recientes. Revisa lo que haya cambiado y '
          'vuelve a escribir lo tuyo.',
        ),
        actions: [
          RisegButton(
            label: 'Cargar lo más reciente',
            onPressed: () {
              Navigator.of(contexto).pop();
              _reintentos = 0;
              _cargar();
            },
          ),
        ],
      ),
    );

  // =========================================================================
  // Pintar
  // =========================================================================

  @override
  Widget build(BuildContext context) =>
      // EL RECORRIDO DE FOCO ENVUELVE AL `Scrollable`, no al contrario: la política
      // necesita encontrarlo desde el contexto de lo enfocado. Sin esto, la vuelta de
      // `Tab` —del botón de guardar al primer campo— dejaba la vista abajo con el
      // foco invisible arriba.
      RisegRecorridoDeFoco(child: _cuerpo(context));

  Widget _cuerpo(BuildContext context) {
    if (_cargando) {
      return const Center(child: CircularProgressIndicator());
    }

    final fallo = _fallo;

    if (fallo != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(fallo.message, textAlign: TextAlign.center),
              const SizedBox(height: AppSpacing.md),
              RisegButton(label: 'Volver a intentar', onPressed: _cargar),
            ],
          ),
        ),
      );
    }

    final expediente = _expediente!;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ⚠️ EL SUBTÍTULO DECÍA «el nombre comercial se cambia en otro sitio», y
          // **ese sitio no existía en Administra**: el nombre venía de la Company, que
          // se da de alta desde Console. Así que un cliente no podía corregir su
          // propio nombre comercial, y es una función del escritorio que se perdió sin
          // que nadie lo decidiera. Se edita aquí desde el 21 de octubre de 2026.
          RisegSectionHeader(
            title: 'Editar ${expediente.nombre}',
            description:
                'La identidad fiscal y de contacto de la empresa. Al guardar se cierra '
                'y vuelves a la ficha.',
          ),
          const SizedBox(height: AppSpacing.lg),
          _seccionDelLogotipo(),
          const SizedBox(height: AppSpacing.lg),
          _avisoDeLaTarjetaFiscal(expediente),
          const SizedBox(height: AppSpacing.lg),
          RisegFormSection(
            key: _claveDeIdentidad,
            title: 'Identidad',
            grid: true,
            children: [
              _campo(
                'name',
                'Nombre comercial',
                _nombre,
                ayuda: 'Como se conoce a la empresa. Sale en sus documentos.',
              ),
              _campo(
                'legalName',
                'Razón social',
                _razonSocial,
                ayuda: 'Como aparece en la constancia de situación fiscal.',
              ),
              _campo(
                'taxId',
                'RFC',
                _rfc,
                ayuda:
                    '12 caracteres para persona moral, 13 para persona física.',
                // AL CAMBIAR EL RFC SE VUELVE A PEDIR EL CATÁLOGO, porque la longitud
                // decide qué regímenes aplican. Y el filtro AVISA, no bloquea: un RFC
                // a medio escribir deja la lista completa en vez de vaciarla.
                alCambiar: (_) => _cargarRegimenes(),
              ),
              _selectorDeRegimen(),
              _campo('legalRep', 'Representante legal', _representante),
              _campo('slogan', 'Eslogan', _eslogan),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          _seccionDeDomicilio(),
          const SizedBox(height: AppSpacing.lg),
          RisegFormSection(
            title: 'Contacto',
            description:
                'Los tres son opcionales. Si los dejas vacíos, no se guarda contacto.',
            grid: true,
            children: [
              _campo(
                'contact.phone',
                'Teléfono',
                _telefono,
                teclado: TextInputType.phone,
              ),
              _campo(
                'contact.email',
                'Correo',
                _correo,
                teclado: TextInputType.emailAddress,
              ),
              _campo('contact.website', 'Sitio web', _sitio),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          if (widget.puedeEditar)
            Row(
              children: [
                const Spacer(),
                // CANCELAR EXISTE DESDE QUE EDITAR ES UN MODO. Antes el formulario
                // estaba siempre abierto y no había de dónde salir; ahora salir puede
                // perder trabajo, así que hay por dónde y se pregunta si hace falta.
                RisegButton(
                  label: 'Cancelar',
                  variant: RisegButtonVariant.secondary,
                  onPressed: _guardando ? null : widget.alCancelar,
                ),
                const SizedBox(width: AppSpacing.sm),
                RisegButton(
                  label: 'Guardar expediente',
                  icon: Icons.save_outlined,
                  loading: _guardando,
                  onPressed: _guardando ? null : _guardar,
                ),
              ],
            )
          else
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Sólo puedes consultar este expediente. Editarlo necesita el '
                    'permiso de configuración de la empresa.',
                    style: AppTypography.caption.copyWith(
                      color: context.colors.textMuted,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                // SIN PERMISO TAMBIÉN HAY POR DÓNDE SALIR: quien llegó aquí sin poder
                // editar tiene que poder volver a la ficha.
                RisegButton(
                  label: 'Volver',
                  variant: RisegButtonVariant.secondary,
                  onPressed: widget.alCancelar,
                ),
              ],
            ),
        ],
      ),
    );
  }

  /// Dice si la tarjeta fiscal se puede generar **y qué falta si no**.
  ///
  /// La lista de indispensables la decide el servidor; aquí sólo se nombra lo que
  /// está vacío para que la persona no tenga que adivinar cuál de los tres es.
  Widget _avisoDeLaTarjetaFiscal(ExpedienteDeEmpresa e) {
    final colors = context.colors;

    if (e.tarjetaFiscalLista) {
      // ⚠️ «COMPLETOS» NO ES «CORRECTOS», y decirlo así era engañoso. Se encontró
      // probando el ensayo el 22 de octubre de 2026: con los tres datos puestos y un
      // régimen que contradice al RFC, la pantalla daba por bueno un expediente que
      // produciría una tarjeta fiscal contradictoria.
      //
      // El servidor dice `fiscalCardReady` sobre LOS TRES INDISPENSABLES —razón social,
      // RFC y domicilio— y eso sigue siendo verdad; no se le discute. Lo que se añade
      // es lo que esta pantalla sí sabe y el servidor no mira: que el régimen elegido
      // y el RFC hablen de la misma clase de persona.
      //
      // Y SE DICE «REVISA», NO «ESTÁ MAL»: guardarlo está permitido a propósito, así
      // que el aviso señala, no sentencia.
      if (_elRegimenContradiceAlRfc) {
        return RisegCard(
          child: Row(
            children: [
              Icon(Icons.info_outline, color: colors.warning),
              const SizedBox(width: AppSpacing.md),
              const Expanded(
                child: Text(
                  'Están los tres datos de la tarjeta fiscal —razón social, RFC y '
                  'domicilio—, pero hay algo que revisar: el régimen fiscal no '
                  'corresponde al tipo de persona del RFC.',
                ),
              ),
            ],
          ),
        );
      }

      return RisegCard(
        child: Row(
          children: [
            Icon(Icons.verified_outlined, color: colors.success),
            const SizedBox(width: AppSpacing.md),
            const Expanded(
              child: Text(
                'Los datos fiscales están completos: razón social, RFC y domicilio.',
              ),
            ),
          ],
        ),
      );
    }

    final faltan = [
      if ((e.razonSocial ?? '').isEmpty) 'la razón social',
      if ((e.rfc ?? '').isEmpty) 'el RFC',
      if (e.direccion == null) 'el domicilio',
    ];

    return RisegCard(
      child: Row(
        children: [
          Icon(Icons.info_outline, color: colors.warning),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              'Para los datos fiscales completos falta ${faltan.join(', ')}. '
              'Lo demás se puede guardar igual.',
            ),
          ),
        ],
      ),
    );
  }

  /// El selector de régimen.
  ///
  /// **Un régimen retirado que la empresa YA tiene se sigue ofreciendo**, marcado. Si
  /// se quitara de la lista, el selector aparecería vacío teniendo un valor guardado y
  /// el primer guardado lo borraría sin que nadie lo pidiera.
  ///
  /// ## ⚠️ Y lo mismo, por otro motivo, cuando cambia el RFC
  ///
  /// **Esto reventaba la pantalla**, y se encontró probando el ensayo el 22 de octubre
  /// de 2026: con `601` elegido —persona moral— y el RFC cambiado a uno de 13
  /// caracteres, el catálogo vuelve **filtrado a persona física** y `601` ya no está
  /// en él. El menú desplegable exige que su valor esté entre sus opciones, así que
  /// lanzaba y la pantalla entera se caía con «Algo salió mal».
  ///
  /// **Se avisa, no se limpia.** Borrar la elección de alguien en silencio porque
  /// escribió un RFC es perderle trabajo sin preguntar, y el servidor **permite**
  /// guardar esa combinación a propósito —el filtro es una ayuda, no una regla: «el
  /// servidor no es el SAT»—. Así que el régimen se sigue ofreciendo, marcado, y el
  /// aviso dice exactamente qué no cuadra.
  Widget _selectorDeRegimen() {
    final elegido = _regimen;

    final elegibles = [
      for (final r in _regimenes)
        if (r.seleccionable || r.codigo == elegido) r,
    ];

    // EL ELEGIDO QUE EL FILTRO SE LLEVÓ. Se vuelve a poner como opción para que el
    // desplegable tenga el valor que le estamos dando; sin esto, lanza.
    final desaparecido = elegido != null && !elegibles.any((r) => r.codigo == elegido);

    if (_regimenes.isEmpty) {
      return const RisegTextField(
        label: 'Régimen fiscal',
        enabled: false,
        readOnly: true,
        helperText:
            'No se pudo cargar el catálogo del SAT. Puedes guardar lo demás y '
            'elegirlo después.',
      );
    }

    return RisegSelect<String>(
      label: 'Régimen fiscal',
      value: elegido,
      hint: 'Elige el régimen',
      // EL DEL SERVIDOR MANDA SOBRE EL NUESTRO: si el `PUT` señaló este campo, eso es
      // lo que hay que arreglar primero.
      errorText: _erroresDeCampo['fiscalRegimeCode'] ?? _avisoDeRegimenQueNoCuadra(),
      enabled: widget.puedeEditar && !_guardando,
      helperText: _ayudaDelRegimen(),
      items: [
        for (final r in elegibles)
          RisegSelectItem(
            value: r.codigo,
            label: r.seleccionable
                ? r.etiqueta
                : '${r.etiqueta} (ya no se puede elegir)',
          ),

        // El que el filtro se llevó, al final y nombrado por lo que es.
        if (desaparecido)
          RisegSelectItem(
            value: elegido,
            label: '${_etiquetaDelRegimen(elegido)} (no corresponde a este RFC)',
          ),
      ],
      onChanged: (v) {
        // Igual que en los campos de texto: elegir otro régimen retira el error que el
        // servidor puso sobre el anterior. Aquí tiene su propio `onChanged` porque no
        // pasa por `_campo`, que es de `RisegTextField`.
        _limpiarErrorDe('fiscalRegimeCode');
        setState(() => _regimen = v);
      },
    );
  }

  /// «601 · General de Ley Personas Morales es de persona moral y el RFC que
  /// escribiste es de persona física.»
  ///
  /// Nulo cuando no hay nada que avisar. **Dice las dos mitades** —qué es el régimen y
  /// qué es el RFC— porque con una sola habría que adivinar cuál de las dos está mal, y
  /// cualquiera de las dos puede serlo: tan válido es corregir el RFC como cambiar el
  /// régimen.
  String? _avisoDeRegimenQueNoCuadra() {
    // ⚠️ SE DECIDE CON LOS DATOS, NO CON «DESAPARECIÓ DE LA LISTA». Lo primero que
    // escribí miraba la ausencia, y la ausencia tiene otra causa posible —un catálogo
    // que no cargó—: de ahí habría salido un aviso inventado sobre tipos de persona
    // que nadie comprobó.
    if (!_elRegimenContradiceAlRfc) return null;

    final elegido = _regimen;
    if (elegido == null) return null;

    final nombre = _etiquetaDelRegimen(elegido);

    return switch (_rfc.text.trim().length) {
      12 =>
        '$nombre es de persona física y el RFC que escribiste tiene 12 caracteres, '
            'que es de empresa. Cambia uno de los dos.',
      13 =>
        '$nombre es de persona moral y el RFC que escribiste tiene 13 caracteres, '
            'que es de persona física. Cambia uno de los dos.',

      // Sin una longitud que lo explique no se inventa el motivo: se dice lo único
      // que consta.
      _ => '$nombre no está entre los que aplican al RFC que escribiste.',
    };
  }

  /// La ayuda cambia con el RFC, **y nunca dice que la lista está filtrada cuando no
  /// lo está**: prometer un filtro que no se aplicó haría pensar que un régimen que
  /// falta no existe.
  String _ayudaDelRegimen() {
    final rfc = _rfc.text.trim();

    return switch (rfc.length) {
      12 => 'El RFC es de 12 caracteres, así que la lista muestra los de persona moral.',
      13 => 'El RFC es de 13 caracteres, así que la lista muestra los de persona física.',
      _ => 'Escribe el RFC y la lista se acota a los regímenes que le aplican.',
    };
  }

  // =========================================================================
  // El logotipo
  // =========================================================================

  /// El logotipo, **que se aplica al momento y no al guardar**.
  ///
  /// ## Por qué no espera a «Guardar»
  ///
  /// Porque es otra operación: tiene su propia ruta, su propio permiso de archivo y su
  /// propio evento. Mezclarla con el `PUT` del expediente obligaría a mandar los bytes
  /// en **cada** guardado —aunque nadie hubiera tocado el logotipo— y a inventar un
  /// «quitar pendiente» que no existe en el servidor.
  ///
  /// La pantalla lo dice en vez de dejarlo descubrir.
  Widget _seccionDelLogotipo() {
    final colors = context.colors;
    final logo = _logotipo;

    return RisegFormSection(
      title: 'Logotipo',
      description:
          'PNG o JPEG, hasta 5 MB. Se guarda al momento: no espera a «Guardar».',
      children: [
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Container(
              width: 96,
              height: 96,
              alignment: Alignment.center,
              padding: const EdgeInsets.all(AppSpacing.xs),
              decoration: BoxDecoration(
                color: logo == null ? colors.accentSoftBg : Colors.white,
                border: Border.all(color: colors.borderSubtle),
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: logo == null
                  ? Icon(Icons.image_outlined, color: colors.textMuted)
                  : Image.memory(logo, fit: BoxFit.contain),
            ),

            if (widget.puedeEditar) ...[
              RisegButton(
                label: logo == null ? 'Subir logotipo' : 'Cambiar logotipo',
                icon: Icons.upload_outlined,
                variant: RisegButtonVariant.secondary,
                size: RisegButtonSize.compact,
                loading: _subiendoLogotipo,
                onPressed: _subiendoLogotipo ? null : _elegirYSubirLogotipo,
              ),
              if (logo != null)
                RisegButton(
                  label: 'Quitar',
                  variant: RisegButtonVariant.danger,
                  size: RisegButtonSize.compact,
                  onPressed: _subiendoLogotipo ? null : _quitarLogotipo,
                ),
            ],
          ],
        ),

        if (!widget.puedeEditar)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.lock_outline, size: 14, color: colors.textMuted),
              const SizedBox(width: AppSpacing.xxs),
              Expanded(
                child: Text(
                  'Para cambiar el logotipo necesitas el permiso de configurar la '
                  'empresa.',
                  style: AppTypography.caption.copyWith(color: colors.textMuted),
                ),
              ),
            ],
          ),
      ],
    );
  }

  Future<void> _elegirYSubirLogotipo() async {
    final elegido = await elegirLogotipo(context);

    if (elegido == null || !mounted) return;

    setState(() => _subiendoLogotipo = true);

    final resultado = await widget.logotipos.subir(
      empresaId: widget.empresaId,
      nombreDeArchivo: elegido.nombre,
      bytes: elegido.bytes,
    );

    if (!mounted) return;

    resultado.when(
      ok: (bytes) {
        setState(() {
          _logotipo = bytes;
          _subiendoLogotipo = false;
        });

        widget.alCambiarElLogotipo?.call(bytes);
        RisegFeedback.showSuccess(context, 'Logotipo guardado.');
      },
      failure: (f) {
        setState(() => _subiendoLogotipo = false);

        // EL 409 DE CAPACIDAD LLEVA CIFRAS, y con ellas se puede actuar; sin ellas,
        // «no cabe» no dice qué hacer. ⚠️ Y SON DE LA ORGANIZACIÓN, no de la empresa.
        if (LogotipoRepositorioHttp.capacidadDe(f) case final cifras?) {
          mostrarRechazoDelServidor(
            context,
            'Tu organización se quedó sin espacio: usa '
            '${_enGb(cifras.usados)} de ${_enGb(cifras.capacidad)}. '
            'Habla con SEVENTRA para ampliarlo.',
          );

          return;
        }

        mostrarRechazoDelServidor(context, f.message);
      },
    );
  }

  Future<void> _quitarLogotipo() async {
    final confirmado = await RisegDialog.showConfirmation(
      context: context,
      title: 'Quitar el logotipo',
      message:
          'La empresa se presentará con sus iniciales, en texto. Se libera el espacio '
          'que ocupaba.',
      confirmLabel: 'Quitar',
      cancelLabel: 'Cancelar',
    );

    if (!(confirmado ?? false) || !mounted) return;

    setState(() => _subiendoLogotipo = true);

    final resultado = await widget.logotipos.quitar(widget.empresaId);

    if (!mounted) return;

    resultado.when(
      ok: (_) {
        setState(() {
          _logotipo = null;
          _subiendoLogotipo = false;
        });

        widget.alCambiarElLogotipo?.call(null);

        // SE DICE QUE SE LIBERÓ CAPACIDAD, no que se borró: el archivo sigue guardado
        // hasta la purga, y lo que queda libre en el acto es la capacidad contratada.
        RisegFeedback.showSuccess(
          context,
          'Se quitó el logotipo y se liberó su espacio.',
        );
      },
      failure: (f) {
        setState(() => _subiendoLogotipo = false);
        mostrarRechazoDelServidor(context, f.message);
      },
    );
  }

  /// Los bytes en GB con un decimal. **En GB y no en bytes** porque la capacidad del
  /// plan se contrata en GB, y comparar «104857600» con «1 GB» no se puede hacer de
  /// cabeza.
  static String _enGb(int bytes) =>
      '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';

  /// Un campo del formulario, **con su clave del servidor dicha una sola vez**.
  ///
  /// La misma clave da el nodo de foco y el error. Escribirlas por separado —como
  /// estaban, en diecisiete bloques iguales— es cómo el error se pinta en «Colonia» y
  /// la vista va a «Municipio» sin que nada falle.
  Widget _campo(
    String campo,
    String etiqueta,
    TextEditingController controlador, {
    String? ayuda,
    TextInputType? teclado,
    ValueChanged<String>? alCambiar,
  }) => RisegTextField(
    label: etiqueta,
    controller: controlador,
    focusNode: _focos[campo],
    enabled: widget.puedeEditar && !_guardando,
    errorText: _erroresDeCampo[campo],
    helperText: ayuda,
    keyboardType: teclado,
    onChanged: (valor) {
      // ⚠️ EL ERROR SE BORRA AL EDITAR, Y SE ENCONTRÓ PROBANDO EL ENSAYO el 22 de
      // octubre de 2026. El error de un campo sólo se limpiaba al volver a guardar,
      // así que después de un intento fallido se quedaba puesto mientras la persona
      // corregía: un RFC de 13 caracteres perfectamente válido seguía mostrando «debe
      // tener 12 o 13» hasta el siguiente guardado.
      //
      // Lo peor no es el texto de más: es que el mensaje deja de ser información y
      // pasa a ser ruido, y entonces se ignora el que SÍ importa.
      //
      // **Se limpia al editar y no se revalida aquí**: la validación es del servidor
      // —incluido el RFC, cuya regla es deliberadamente permisiva— y una segunda en la
      // pantalla sería otra fuente de verdad que discreparía el día que una cambie.
      // Esto no dice «ya está bien»; dice «ya no sé, vuelve a preguntar».
      _limpiarErrorDe(campo);

      alCambiar?.call(valor);
    },
  );

  /// Quita el error de un campo, si lo tenía.
  ///
  /// **Sólo repinta cuando de verdad había uno**: un `setState` por cada tecla en un
  /// formulario de diecisiete campos es trabajo para nada.
  void _limpiarErrorDe(String campo) {
    if (!_erroresDeCampo.containsKey(campo)) return;

    setState(() {
      _erroresDeCampo = {
        for (final e in _erroresDeCampo.entries)
          if (e.key != campo) e.key: e.value,
      };
    });
  }

  Widget _seccionDeDomicilio() => RisegFormSection(
    title: 'Domicilio fiscal',
    description:
        'Si escribes cualquier dato, hacen falta calle, número exterior, colonia, '
        'municipio, estado y código postal. Si los dejas todos vacíos, no se guarda '
        'domicilio.',
    grid: true,
    children: [
      _campo('address.street', 'Calle', _calle),
      _campo('address.exteriorNumber', 'Número exterior', _exterior),
      _campo(
        'address.interiorNumber',
        'Número interior',
        _interior,
        ayuda: 'Opcional.',
      ),
      _campo('address.neighborhood', 'Colonia', _colonia),
      _campo('address.municipality', 'Municipio', _municipio),
      _campo('address.city', 'Ciudad', _ciudad, ayuda: 'Opcional.'),
      _campo('address.state', 'Estado', _estado),
      _campo(
        'address.postalCode',
        'Código postal',
        _cp,
        ayuda: 'Cinco dígitos.',
        teclado: TextInputType.number,
      ),
      _campo('address.country', 'País', _pais, ayuda: 'Opcional.'),
      _campo(
        'address.landmarks',
        'Referencias',
        _referencias,
        ayuda: 'Opcional. Entre qué calles, frente a qué.',
      ),
    ],
  );
}
