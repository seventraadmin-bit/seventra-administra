import 'package:flutter/material.dart';

import '../../../../core/design_system/design_system_web.dart';
import '../../../../core/error/failure.dart';
import '../datos/expedientes_repositorio_http.dart';
import '../modelos/expediente.dart';
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
    required this.empresaId,
    required this.puedeEditar,
    super.key,
  });

  final ExpedientesRepositorioHttp repositorio;
  final String empresaId;

  /// Si quien mira tiene `company.settings.manage`.
  ///
  /// **Sólo gobierna si los campos se OFRECEN**, nunca si se puede guardar: eso lo
  /// decide el servidor en cada petición. Filtrar no es autorizar.
  final bool puedeEditar;

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

  /// Todos los controllers, para liberarlos en un solo sitio.
  ///
  /// **Liberar un controller no es opcional y en este proyecto ya costó una vez.**
  /// Diecisiete `dispose()` escritos a mano son diecisiete oportunidades de olvidar
  /// uno, y el que se olvida no falla: sólo gotea.
  List<TextEditingController> get _todos => [
    _razonSocial, _rfc, _representante, _eslogan,
    _calle, _exterior, _interior, _colonia, _municipio,
    _ciudad, _estado, _cp, _pais, _referencias,
    _telefono, _correo, _sitio,
  ];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    for (final c in _todos) {
      c.dispose();
    }

    super.dispose();
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
      ok: (lista) => setState(() => _regimenes = lista),
      failure: (_) => setState(() => _regimenes = const []),
    );
  }

  void _volcarEnElFormulario(ExpedienteDeEmpresa e) {
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
        _cargarRegimenes();
      },
      failure: (f) {
        setState(() => _guardando = false);

        if (ExpedientesRepositorioHttp.esDesactualizado(f)) {
          _avisarDesactualizado();

          return;
        }

        // EL RÉGIMEN NO DISPONIBLE VA AL CAMPO, no a un aviso que se va. Es un 422 con
        // su propio código y no trae `fields` —el servidor no lo manda como error de
        // entrada—, así que se traduce aquí: es el único error de este formulario que
        // se arregla en un control concreto, y decirlo en un recuadro flotante haría
        // buscar cuál de los quince campos es.
        if (f case ApiHttpFailure(codigo: 'regimen_no_disponible')) {
          setState(() => _erroresDeCampo = {'fiscalRegimeCode': f.message});

          return;
        }

        final campos = ExpedientesRepositorioHttp.camposDe(f);

        if (campos.isNotEmpty) {
          // TODOS LOS CAMPOS A LA VEZ. El servidor «reúne todos los errores antes de
          // fallar» a propósito; mostrarlos de uno en uno obligaría a descubrirlos con
          // un guardado por cada uno.
          setState(() => _erroresDeCampo = campos);

          return;
        }

        mostrarRechazoDelServidor(context, f.message);
      },
    );
  }

  /// Alguien más guardó: se recarga y se dice **qué pasó y qué hacer**.
  ///
  /// No se guarda encima y no se ofrece «forzar»: el trabajo del otro no es un
  /// obstáculo que esta pantalla pueda apartar.
  void _avisarDesactualizado() {
    showDialog<void>(
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
              _cargar();
            },
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // Pintar
  // =========================================================================

  @override
  Widget build(BuildContext context) {
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
          RisegSectionHeader(
            title: expediente.nombre,
            description:
                'La identidad fiscal y de contacto de la empresa. El nombre comercial '
                'se cambia en otro sitio.',
          ),
          const SizedBox(height: AppSpacing.lg),
          _avisoDeLaTarjetaFiscal(expediente),
          const SizedBox(height: AppSpacing.lg),
          RisegFormSection(
            title: 'Identidad fiscal',
            grid: true,
            children: [
              RisegTextField(
                label: 'Razón social',
                controller: _razonSocial,
                enabled: widget.puedeEditar && !_guardando,
                errorText: _erroresDeCampo['legalName'],
                helperText: 'Como aparece en la constancia de situación fiscal.',
              ),
              RisegTextField(
                label: 'RFC',
                controller: _rfc,
                enabled: widget.puedeEditar && !_guardando,
                errorText: _erroresDeCampo['taxId'],
                helperText: '12 caracteres para persona moral, 13 para persona física.',
                // AL CAMBIAR EL RFC SE VUELVE A PEDIR EL CATÁLOGO, porque la longitud
                // decide qué regímenes aplican. Y el filtro AVISA, no bloquea: un RFC
                // a medio escribir deja la lista completa en vez de vaciarla.
                onChanged: (_) => _cargarRegimenes(),
              ),
              _selectorDeRegimen(),
              RisegTextField(
                label: 'Representante legal',
                controller: _representante,
                enabled: widget.puedeEditar && !_guardando,
                errorText: _erroresDeCampo['legalRep'],
              ),
              RisegTextField(
                label: 'Eslogan',
                controller: _eslogan,
                enabled: widget.puedeEditar && !_guardando,
                errorText: _erroresDeCampo['slogan'],
              ),
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
              RisegTextField(
                label: 'Teléfono',
                controller: _telefono,
                enabled: widget.puedeEditar && !_guardando,
                errorText: _erroresDeCampo['contact.phone'],
                keyboardType: TextInputType.phone,
              ),
              RisegTextField(
                label: 'Correo',
                controller: _correo,
                enabled: widget.puedeEditar && !_guardando,
                errorText: _erroresDeCampo['contact.email'],
                keyboardType: TextInputType.emailAddress,
              ),
              RisegTextField(
                label: 'Sitio web',
                controller: _sitio,
                enabled: widget.puedeEditar && !_guardando,
                errorText: _erroresDeCampo['contact.website'],
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          if (widget.puedeEditar)
            Align(
              alignment: Alignment.centerRight,
              child: RisegButton(
                label: 'Guardar expediente',
                icon: Icons.save_outlined,
                loading: _guardando,
                onPressed: _guardando ? null : _guardar,
              ),
            )
          else
            Text(
              'Sólo puedes consultar este expediente. Editarlo necesita el permiso '
              'de configuración de la empresa.',
              style: AppTypography.caption.copyWith(
                color: context.colors.textMuted,
              ),
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
  Widget _selectorDeRegimen() {
    final elegibles = [
      for (final r in _regimenes)
        if (r.seleccionable || r.codigo == _regimen) r,
    ];

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
      value: _regimen,
      hint: 'Elige el régimen',
      errorText: _erroresDeCampo['fiscalRegimeCode'],
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
      ],
      onChanged: (v) => setState(() => _regimen = v),
    );
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

  Widget _seccionDeDomicilio() => RisegFormSection(
    title: 'Domicilio fiscal',
    description:
        'Si escribes cualquier dato, hacen falta calle, número exterior, colonia, '
        'municipio, estado y código postal. Si los dejas todos vacíos, no se guarda '
        'domicilio.',
    grid: true,
    children: [
      RisegTextField(
        label: 'Calle',
        controller: _calle,
        enabled: widget.puedeEditar && !_guardando,
        errorText: _erroresDeCampo['address.street'],
      ),
      RisegTextField(
        label: 'Número exterior',
        controller: _exterior,
        enabled: widget.puedeEditar && !_guardando,
        errorText: _erroresDeCampo['address.exteriorNumber'],
      ),
      RisegTextField(
        label: 'Número interior',
        controller: _interior,
        enabled: widget.puedeEditar && !_guardando,
        errorText: _erroresDeCampo['address.interiorNumber'],
        helperText: 'Opcional.',
      ),
      RisegTextField(
        label: 'Colonia',
        controller: _colonia,
        enabled: widget.puedeEditar && !_guardando,
        errorText: _erroresDeCampo['address.neighborhood'],
      ),
      RisegTextField(
        label: 'Municipio',
        controller: _municipio,
        enabled: widget.puedeEditar && !_guardando,
        errorText: _erroresDeCampo['address.municipality'],
      ),
      RisegTextField(
        label: 'Ciudad',
        controller: _ciudad,
        enabled: widget.puedeEditar && !_guardando,
        errorText: _erroresDeCampo['address.city'],
        helperText: 'Opcional.',
      ),
      RisegTextField(
        label: 'Estado',
        controller: _estado,
        enabled: widget.puedeEditar && !_guardando,
        errorText: _erroresDeCampo['address.state'],
      ),
      RisegTextField(
        label: 'Código postal',
        controller: _cp,
        enabled: widget.puedeEditar && !_guardando,
        errorText: _erroresDeCampo['address.postalCode'],
        helperText: 'Cinco dígitos.',
        keyboardType: TextInputType.number,
      ),
      RisegTextField(
        label: 'País',
        controller: _pais,
        enabled: widget.puedeEditar && !_guardando,
        errorText: _erroresDeCampo['address.country'],
        helperText: 'Opcional.',
      ),
      RisegTextField(
        label: 'Referencias',
        controller: _referencias,
        enabled: widget.puedeEditar && !_guardando,
        errorText: _erroresDeCampo['address.landmarks'],
        helperText: 'Opcional. Entre qué calles, frente a qué.',
      ),
    ],
  );
}
