import 'package:flutter/material.dart';

import '../../../../app/shell/se_cierra_al_cambiar_la_direccion.dart';
import '../../../../core/design_system/design_system_web.dart';
import '../../../../core/direcciones/campos_de_domicilio.dart';
import '../../../../core/direcciones/direccion.dart';
import '../../../../core/direcciones/seccion_de_domicilio.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/error/rechazo_del_servidor.dart';
import '../../../../core/fiscal/regimen_fiscal.dart';
import '../../../../core/trabajo_sin_guardar/declara_su_trabajo_sin_guardar.dart';
import '../../../../core/trabajo_sin_guardar/guardia_de_salida.dart';
import '../datos/clientes_repositorio_http.dart';
import '../modelos/entidad_fiscal.dart';

/// **Las razones sociales con las que se factura a este cliente**, incluidas las
/// archivadas.
///
/// ## Por qué las archivadas se enseñan
///
/// Con una entidad fiscal **se emitieron facturas**, así que no se borra: se archiva. Y
/// esconder las archivadas haría pensar que desaparecieron — lo que de verdad hace falta
/// saber es que existió y que ya no se usa. El servidor no las filtra, y la pantalla las
/// pinta con su insignia y sus acciones de edición **deshabilitadas, con el porqué**.
///
/// ## El aviso de RFC repetido
///
/// El RFC es **único por cliente**, así que el mismo RFC en otro cliente es legal —dos
/// marcas de la misma empresa legal— y también es el síntoma de un cliente capturado dos
/// veces. **Sólo quien está capturando puede distinguirlo**, así que el servidor **guarda y
/// avisa**, y el panel se queda abierto con el aviso **junto al campo del RFC**, nombrando
/// los otros clientes con su folio.
class SeccionDeEntidadesFiscales extends StatefulWidget {
  const SeccionDeEntidadesFiscales({
    required this.repositorio,
    required this.empresaId,
    required this.clienteId,
    required this.puedeAdministrar,
    required this.guardia,
    required this.alCambiar,
    super.key,
  });

  final ClientesRepositorioHttp repositorio;
  final String empresaId;
  final String clienteId;
  final bool puedeAdministrar;
  final GuardiaDeSalida guardia;

  /// Avisa de que la lista cambió, **para que la cabecera se entere**: la razón social y
  /// el RFC de arriba sólo se muestran con **una** entidad activa, así que añadir,
  /// archivar o reactivar una puede hacerlos aparecer o desaparecer.
  final VoidCallback alCambiar;

  @override
  State<SeccionDeEntidadesFiscales> createState() =>
      _SeccionDeEntidadesFiscalesState();
}

class _SeccionDeEntidadesFiscalesState
    extends State<SeccionDeEntidadesFiscales> {
  List<EntidadFiscal>? _entidades;
  Failure? _fallo;
  bool _cargando = true;

  /// El catálogo del SAT, **pedido una vez**.
  ///
  /// Se lee aquí y se pasa a los paneles para no pedirlo en cada apertura. Vacío significa
  /// que no se pudo leer; el panel lo dice en lugar de ofrecer un selector vacío.
  List<RegimenFiscal> _regimenes = const [];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void didUpdateWidget(SeccionDeEntidadesFiscales anterior) {
    super.didUpdateWidget(anterior);

    if (anterior.clienteId != widget.clienteId) _cargar();
  }

  Future<void> _cargar() async {
    final id = widget.clienteId;

    setState(() {
      _cargando = true;
      _fallo = null;
    });

    final (entidades, regimenes) = await (
      widget.repositorio.listarEntidadesFiscales(
        empresaId: widget.empresaId,
        clienteId: id,
      ),
      widget.repositorio.listarRegimenes(empresaId: widget.empresaId),
    ).wait;

    if (!mounted || widget.clienteId != id) return;

    entidades.when(
      ok: (lista) => setState(() {
        _entidades = lista;
        // EL CATÁLOGO NO PUEDE IMPEDIR PINTAR LA LISTA: si no bajó, las entidades se
        // ven igual y lo que falta se dice en el panel.
        _regimenes = regimenes.when(ok: (r) => r, failure: (_) => const []);
        _cargando = false;
      }),
      failure: (f) => setState(() {
        _fallo = f;
        _cargando = false;
      }),
    );
  }

  Future<void> _recargarYAvisar() async {
    await _cargar();
    widget.alCambiar();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return RisegFormSection(
      title: 'Entidades fiscales',
      description:
          'Las razones sociales con las que se factura a este cliente. Puede tener '
          'varias, y las archivadas se siguen viendo: con ellas se emitieron facturas.',
      children: [
        if (_cargando)
          const Padding(
            padding: EdgeInsets.all(AppSpacing.md),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_fallo case final f?)
          _Aviso(
            icono: Icons.cloud_off_outlined,
            mensaje: 'No se pudieron cargar las entidades fiscales: ${f.message}',
            accion: RisegButton(
              label: 'Intentar de nuevo',
              variant: RisegButtonVariant.secondary,
              size: RisegButtonSize.compact,
              onPressed: _cargar,
            ),
          )
        else if ((_entidades ?? const []).isEmpty)
          const _Aviso(
            icono: Icons.receipt_long_outlined,
            mensaje:
                'Este cliente todavía no tiene razones sociales. Sin una no se le '
                'puede facturar.',
          )
        else
          for (final e in _entidades!)
            _Fila(
              entidad: e,
              puedeAdministrar: widget.puedeAdministrar,
              nombreDelRegimen: _nombreDelRegimen(e.regimenFiscal),
              onEditar: () => _abrirPanel(e),
              onDomicilio: () => _abrirDomicilio(e),
              onCicloDeVida: () => _cambiarCicloDeVida(e),
            ),

        if (widget.puedeAdministrar) ...[
          const SizedBox(height: AppSpacing.xs),
          Align(
            alignment: Alignment.centerLeft,
            child: RisegButton(
              label: 'Añadir razón social',
              icon: Icons.add,
              variant: RisegButtonVariant.secondary,
              size: RisegButtonSize.compact,
              onPressed: _cargando ? null : () => _abrirPanel(null),
            ),
          ),
        ],

        if (_regimenes.isEmpty && !_cargando && widget.puedeAdministrar)
          Text(
            'El catálogo de regímenes del SAT no se pudo leer. Vuelve a intentarlo: sin '
            'él no se puede elegir el régimen fiscal.',
            style: AppTypography.caption.copyWith(color: colors.warning),
          ),
      ],
    );
  }

  /// `601 · General de Ley Personas Morales`, o el código solo si el catálogo no bajó.
  ///
  /// **Nunca una cadena vacía**: enseñar el código pelado es menos que el nombre y más
  /// que nada, y es lo que permite reconocer el régimen aunque el catálogo falle.
  String? _nombreDelRegimen(String? codigo) {
    if (codigo == null) return null;

    for (final r in _regimenes) {
      if (r.codigo == codigo) return r.etiqueta;
    }

    return codigo;
  }

  Future<void> _abrirPanel(EntidadFiscal? entidad) async {
    final guardado = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PanelDeEntidadFiscal(
        entidad: entidad,
        empresaId: widget.empresaId,
        clienteId: widget.clienteId,
        repositorio: widget.repositorio,
        regimenes: _regimenes,
        guardia: widget.guardia,
      ),
    );

    if ((guardado ?? false) && mounted) await _recargarYAvisar();
  }

  Future<void> _abrirDomicilio(EntidadFiscal entidad) async {
    final guardado = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PanelDeDomicilioFiscal(
        entidad: entidad,
        empresaId: widget.empresaId,
        clienteId: widget.clienteId,
        repositorio: widget.repositorio,
        guardia: widget.guardia,
      ),
    );

    if ((guardado ?? false) && mounted) await _cargar();
  }

  /// Archiva o reactiva, **con motivo**.
  Future<void> _cambiarCicloDeVida(EntidadFiscal entidad) async {
    final archivar = entidad.estaActiva;

    final motivo = await mostrarDialogoMotivo(
      context,
      titulo: archivar ? 'Archivar la razón social' : 'Reactivar la razón social',
      etiquetaMotivo: 'Motivo',
      confirmarLabel: archivar ? 'Archivar' : 'Reactivar',
      cancelarLabel: 'Cancelar',
      errorMotivoRequerido:
          'Falta el motivo. Queda en la bitácora: una razón social afecta a la '
          'facturación.',
      advertencia: archivar
          ? '${entidad.razonSocial}\n\n'
                'Archivar NO la borra —con ella se emitieron facturas— y sigue '
                'apareciendo en esta lista. Lo que no se puede es editarla ni '
                'facturar con ella mientras esté archivada.'
          : '${entidad.razonSocial}\n\nVuelve a estar disponible para facturar.',
    );

    if (motivo == null || !mounted) return;

    if (motivo.length > motivoMaximo) {
      RisegFeedback.showError(
        context,
        'El motivo admite hasta $motivoMaximo caracteres; escribiste ${motivo.length}.',
      );

      return;
    }

    final resultado = await widget.repositorio.modificarEntidadFiscal(
      empresaId: widget.empresaId,
      clienteId: widget.clienteId,
      entidadId: entidad.id,
      motivo: motivo,
      estatus: archivar ? 'archived' : 'active',
    );

    if (!mounted) return;

    await resultado.when(
      ok: (_) async {
        RisegFeedback.showSuccess(
          context,
          archivar
              ? 'Se archivó ${entidad.razonSocial}.'
              : 'Se reactivó ${entidad.razonSocial}.',
        );

        await _recargarYAvisar();
      },
      failure: (f) async => mostrarRechazoDelServidor(context, f),
    );
  }
}

// ===========================================================================
// Una fila
// ===========================================================================

class _Fila extends StatelessWidget {
  const _Fila({
    required this.entidad,
    required this.puedeAdministrar,
    required this.nombreDelRegimen,
    required this.onEditar,
    required this.onDomicilio,
    required this.onCicloDeVida,
  });

  final EntidadFiscal entidad;
  final bool puedeAdministrar;
  final String? nombreDelRegimen;
  final VoidCallback onEditar;
  final VoidCallback onDomicilio;
  final VoidCallback onCicloDeVida;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    // ⚠️ UNA ARCHIVADA NO SE EDITA, y el servidor responde 409 a quien lo intente. Las
    // acciones salen apagadas **con su porqué en el tooltip**, no escondidas: escondidas
    // harían pensar que falta un permiso.
    final sePuedeEditar = puedeAdministrar && entidad.estaActiva;

    final porQueNo = entidad.estaActiva
        ? null
        : 'Está archivada: reactívala para poder editarla.';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        entidad.razonSocial,
                        style: AppTypography.bodyStrong,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    RisegStatusBadge(
                      label: entidad.estaActiva ? 'Activa' : 'Archivada',
                      tone: entidad.estaActiva
                          ? RisegStatusTone.success
                          : RisegStatusTone.neutral,
                      icon: entidad.estaActiva
                          ? Icons.check_circle_outline
                          : Icons.inventory_2_outlined,
                    ),
                    // LO QUE FALTA PARA FACTURAR SE DICE AQUÍ, no al intentar emitir:
                    // el RFC y el régimen son opcionales al capturar y obligatorios para
                    // emitir (CP-13).
                    if (entidad.leFaltanDatosFiscales) ...[
                      const SizedBox(width: AppSpacing.xs),
                      const RisegStatusBadge(
                        label: 'Datos incompletos',
                        tone: RisegStatusTone.warning,
                        icon: Icons.warning_amber_outlined,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  [
                    entidad.rfc ?? 'Sin RFC',
                    nombreDelRegimen ?? 'Sin régimen fiscal',
                  ].join(' · '),
                  style: AppTypography.caption.copyWith(color: colors.textMuted),
                ),
              ],
            ),
          ),

          if (puedeAdministrar) ...[
            IconButton(
              tooltip: porQueNo ?? 'Domicilio fiscal',
              icon: const Icon(Icons.home_outlined),
              onPressed: sePuedeEditar ? onDomicilio : null,
            ),
            IconButton(
              tooltip: porQueNo ?? 'Corregir',
              icon: const Icon(Icons.edit_outlined),
              onPressed: sePuedeEditar ? onEditar : null,
            ),
            IconButton(
              // ARCHIVAR Y REACTIVAR SIEMPRE SE PUEDEN: es la salida de una archivada.
              tooltip: entidad.estaActiva ? 'Archivar' : 'Reactivar',
              icon: Icon(
                entidad.estaActiva
                    ? Icons.inventory_2_outlined
                    : Icons.unarchive_outlined,
              ),
              onPressed: onCicloDeVida,
            ),
          ],
        ],
      ),
    );
  }
}

class _Aviso extends StatelessWidget {
  const _Aviso({required this.icono, required this.mensaje, this.accion});

  final IconData icono;
  final String mensaje;
  final Widget? accion;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icono, size: 18, color: colors.textMuted),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            mensaje,
            style: AppTypography.caption.copyWith(color: colors.textMuted),
          ),
        ),
        if (accion case final a?) ...[const SizedBox(width: AppSpacing.sm), a],
      ],
    );
  }
}

// ===========================================================================
// El panel de la razón social
// ===========================================================================

/// Alta y corrección de una razón social. **El domicilio fiscal va aparte**, igual que en
/// el escritorio y por su razón: tenerlo en el mismo formulario lo haría borrable por
/// accidente al guardar otra cosa.
class _PanelDeEntidadFiscal extends StatefulWidget {
  const _PanelDeEntidadFiscal({
    required this.entidad,
    required this.empresaId,
    required this.clienteId,
    required this.repositorio,
    required this.regimenes,
    required this.guardia,
  });

  final EntidadFiscal? entidad;
  final String empresaId;
  final String clienteId;
  final ClientesRepositorioHttp repositorio;
  final List<RegimenFiscal> regimenes;
  final GuardiaDeSalida guardia;

  bool get esNueva => entidad == null;

  @override
  State<_PanelDeEntidadFiscal> createState() => _PanelDeEntidadFiscalState();
}

class _PanelDeEntidadFiscalState extends State<_PanelDeEntidadFiscal>
    with
        DeclaraSuTrabajoSinGuardar<_PanelDeEntidadFiscal>,
        SeCierraAlCambiarLaDireccion<_PanelDeEntidadFiscal> {
  @override
  GuardiaDeSalida get guardia => widget.guardia;

  late final String _razonInicial = widget.entidad?.razonSocial ?? '';
  late final String _rfcInicial = widget.entidad?.rfc ?? '';
  late final String? _regimenInicial = widget.entidad?.regimenFiscal;

  @override
  bool get hayCambiosSinGuardar =>
      _razon.text.trim() != _razonInicial.trim() ||
      _rfc.text.trim().toUpperCase() != _rfcInicial.trim().toUpperCase() ||
      _regimen != _regimenInicial;

  @override
  String get queSePierde => switch (widget.entidad) {
    final e? => 'la razón social ${e.razonSocial}',
    null => 'la razón social que estás dando de alta',
  };

  final _razon = TextEditingController();
  final _rfc = TextEditingController();

  String? _regimen;

  bool _guardando = false;
  String? _errorDeRazon;

  /// El aviso de RFC repetido, **después de guardar**.
  ///
  /// Cuando llega, el panel **no se cierra**: enseña el aviso junto al campo del RFC y un
  /// solo botón. Así se lee donde se escribió el RFC, que es donde se puede decidir si es
  /// correcto —dos marcas de la misma empresa legal— o un cliente capturado dos veces.
  AvisoDeRfc? _aviso;

  @override
  void initState() {
    super.initState();

    _razon.text = widget.entidad?.razonSocial ?? '';
    _rfc.text = widget.entidad?.rfc ?? '';
    _regimen = widget.entidad?.regimenFiscal;
  }

  @override
  void dispose() {
    _razon.dispose();
    _rfc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final guardado = _aviso != null;

    return Align(
      alignment: Alignment.centerRight,
      child: Material(
        color: colors.surfaceSunken,
        child: SizedBox(
          width: 460,
          height: double.infinity,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.esNueva
                      ? 'Nueva razón social'
                      : 'Corregir la razón social',
                  style: AppTypography.heading2,
                ),
                const SizedBox(height: AppSpacing.lg),

                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        RisegTextField(
                          label: 'Razón social',
                          controller: _razon,
                          enabled: !_guardando && !guardado,
                          errorText: _errorDeRazon,
                          autofocus: true,
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: AppSpacing.md),

                        RisegTextField(
                          label: 'RFC',
                          controller: _rfc,
                          enabled: !_guardando && !guardado,
                          // LAS DOS REGLAS QUE CAMBIARON RESPECTO AL ESCRITORIO, dichas
                          // donde se escribe: opcional, y único por ESTE cliente.
                          helperText:
                              'Opcional al capturar y obligatorio para facturar. Doce '
                              'caracteres para persona moral, trece para física.',
                          onChanged: (v) => setState(() {
                            // SE FILTRA EL CATÁLOGO CON LO ESCRITO: con doce caracteres
                            // se ofrecen los de persona moral y con trece los de física.
                            // El filtro es del servidor y **avisa, no bloquea**.
                            _regimen = _regimen;
                          }),
                        ),

                        if (_aviso case final a?) ...[
                          const SizedBox(height: AppSpacing.sm),
                          _AvisoDeRfcRepetido(aviso: a),
                        ],

                        const SizedBox(height: AppSpacing.md),

                        RisegSelect<String>(
                          label: 'Régimen fiscal',
                          value: _regimen,
                          hint: widget.regimenes.isEmpty
                              ? 'El catálogo del SAT no se pudo leer'
                              : 'Elige el régimen del SAT',
                          helperText:
                              'Opcional al capturar y obligatorio para facturar. Los '
                              'retirados por el SAT salen marcados.',
                          items: [
                            for (final r in _ofrecibles)
                              RisegSelectItem(
                                value: r.codigo,
                                // EL RETIRADO SE DICE Y NO SE ESCONDE: quien ya lo tenía
                                // lo conserva, y su tarjeta fiscal sigue diciendo la
                                // verdad.
                                label: r.seleccionable
                                    ? r.etiqueta
                                    : '${r.etiqueta} (retirado)',
                              ),
                          ],
                          onChanged: _guardando || guardado || widget.regimenes.isEmpty
                              ? null
                              : (v) => setState(() => _regimen = v),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: AppSpacing.md),

                // CON EL AVISO PUESTO, YA ESTÁ GUARDADO: un solo botón, porque no hay
                // nada que cancelar ni que volver a guardar.
                if (guardado)
                  Align(
                    alignment: Alignment.centerRight,
                    child: RisegButton(
                      label: 'Entendido',
                      onPressed: () => Navigator.of(context).pop(true),
                    ),
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        child: RisegButton(
                          label: 'Cancelar',
                          variant: RisegButtonVariant.secondary,
                          onPressed: _guardando
                              ? null
                              : () => Navigator.of(context).pop(false),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: RisegButton(
                          label: 'Guardar',
                          loading: _guardando,
                          onPressed: _guardando ? null : _guardar,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Los regímenes que se ofrecen: **los seleccionables, más el que ya está puesto**.
  ///
  /// ⚠️ **EL QUE YA ESTÁ PUESTO SE OFRECE AUNQUE ESTÉ RETIRADO**, y sin esto el selector
  /// no podría mostrar el valor actual —`RisegSelect` necesita que su `value` esté entre
  /// los `items`— así que una entidad con un régimen retirado abriría el panel con el
  /// campo en blanco y lo **borraría al guardar**.
  List<RegimenFiscal> get _ofrecibles => [
    for (final r in widget.regimenes)
      if (r.seleccionable || r.codigo == _regimenInicial) r,
  ];

  Future<void> _guardar() async {
    final razon = _razon.text.trim();

    setState(() => _errorDeRazon = razon.isEmpty ? 'Falta la razón social.' : null);

    if (_errorDeRazon != null) return;

    // EL RFC SE MANDA EN MAYÚSCULAS: el servidor comprueba la forma y el escritorio ya lo
    // normalizaba así. Enviarlo como se escribió haría que el mismo RFC en minúsculas
    // pareciera otro.
    final rfc = _rfc.text.trim().toUpperCase();

    final motivo = widget.esNueva ? null : await _pedirElMotivo();
    if (!widget.esNueva && (motivo == null || !mounted)) return;

    setState(() => _guardando = true);

    final resultado = widget.esNueva
        ? await widget.repositorio.crearEntidadFiscal(
            empresaId: widget.empresaId,
            clienteId: widget.clienteId,
            razonSocial: razon,
            rfc: rfc.isEmpty ? null : rfc,
            regimenFiscal: _regimen,
          )
        : await widget.repositorio.modificarEntidadFiscal(
            empresaId: widget.empresaId,
            clienteId: widget.clienteId,
            entidadId: widget.entidad!.id,
            motivo: motivo!,
            razonSocial: razon == _razonInicial.trim() ? null : razon,
            // VACIAR UN OPCIONAL SE MANDA COMO CADENA VACÍA: en este `PATCH` `null`
            // significa «no lo toques».
            rfc: rfc == _rfcInicial.trim().toUpperCase() ? null : rfc,
            regimenFiscal: _regimen == _regimenInicial ? null : (_regimen ?? ''),
          );

    if (!mounted) return;

    resultado.when(
      ok: (guardada) {
        // SIN AVISO SE CIERRA; CON AVISO SE QUEDA ABIERTO para que se lea junto al RFC.
        if (guardada.aviso == null) {
          Navigator.of(context).pop(true);

          return;
        }

        setState(() {
          _guardando = false;
          _aviso = guardada.aviso;
        });
      },
      failure: (f) {
        setState(() => _guardando = false);

        // LOS TRES RECHAZOS SALEN TAL CUAL, y cada uno dice qué hacer: `rfc_duplicado`
        // —este cliente ya tiene ese RFC—, `regimen_fiscal_no_disponible` —no está en el
        // catálogo— y `entidad_fiscal_archivada` —reactívala primero—.
        mostrarRechazoDelServidor(context, f);
      },
    );
  }

  Future<String?> _pedirElMotivo() => mostrarDialogoMotivo(
    context,
    titulo: 'Corregir la razón social',
    etiquetaMotivo: 'Motivo de la corrección',
    confirmarLabel: 'Guardar',
    cancelarLabel: 'Seguir editando',
    errorMotivoRequerido:
        'Falta el motivo. El RFC y la razón social son datos fiscales: el cambio '
        'afecta a la facturación y queda en la bitácora.',
  );
}

/// El aviso ámbar de RFC repetido, **con el folio y el nombre de los otros clientes**.
///
/// «Ese RFC ya existe» sin decir dónde obliga a buscarlo a mano en toda la cartera.
class _AvisoDeRfcRepetido extends StatelessWidget {
  const _AvisoDeRfcRepetido({required this.aviso});

  final AvisoDeRfc aviso;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: colors.warningBg,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: colors.warning),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_outlined, size: 18, color: colors.warning),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // SE GUARDÓ, Y SE DICE PRIMERO: lo contrario haría pensar que no.
                const Text(
                  'Se guardó, con un aviso',
                  style: AppTypography.bodyStrong,
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(aviso.mensaje, style: AppTypography.caption),
                const SizedBox(height: AppSpacing.xs),
                for (final c in aviso.clientes)
                  Text(c.etiqueta, style: AppTypography.caption.copyWith(
                    fontWeight: FontWeight.w600,
                  )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// El panel del domicilio fiscal
// ===========================================================================

/// El domicilio fiscal de una razón social: **los mismos diez campos y las mismas reglas**
/// que el de referencia, con el mismo widget.
///
/// Va **en su propio panel** y no dentro del formulario de la razón social, igual que en el
/// escritorio: tenerlo junto lo haría borrable por accidente al guardar otra cosa.
///
/// Y por lo mismo que el de referencia (D-59): **una vez capturado se corrige, no se
/// borra**. El servidor no tiene `DELETE` y su `PUT` exige los seis obligatorios.
class _PanelDeDomicilioFiscal extends StatefulWidget {
  const _PanelDeDomicilioFiscal({
    required this.entidad,
    required this.empresaId,
    required this.clienteId,
    required this.repositorio,
    required this.guardia,
  });

  final EntidadFiscal entidad;
  final String empresaId;
  final String clienteId;
  final ClientesRepositorioHttp repositorio;
  final GuardiaDeSalida guardia;

  @override
  State<_PanelDeDomicilioFiscal> createState() => _PanelDeDomicilioFiscalState();
}

class _PanelDeDomicilioFiscalState extends State<_PanelDeDomicilioFiscal>
    with
        DeclaraSuTrabajoSinGuardar<_PanelDeDomicilioFiscal>,
        SeCierraAlCambiarLaDireccion<_PanelDeDomicilioFiscal> {
  @override
  GuardiaDeSalida get guardia => widget.guardia;

  final _domicilio = CamposDeDomicilio();

  Direccion? _cargado;
  bool _cargando = true;
  bool _guardando = false;
  Failure? _fallo;

  @override
  bool get hayCambiosSinGuardar =>
      !_cargando && !_domicilio.igualA(_cargado);

  @override
  String get queSePierde =>
      'el domicilio fiscal de ${widget.entidad.razonSocial}';

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _domicilio.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    final resultado = await widget.repositorio.verDomicilioFiscal(
      empresaId: widget.empresaId,
      clienteId: widget.clienteId,
      entidadId: widget.entidad.id,
    );

    if (!mounted) return;

    resultado.when(
      ok: (d) => setState(() {
        _cargado = d;
        _domicilio.volcar(d);
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

    return Align(
      alignment: Alignment.centerRight,
      child: Material(
        color: colors.surfaceSunken,
        child: SizedBox(
          width: 560,
          height: double.infinity,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Domicilio fiscal', style: AppTypography.heading2),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  widget.entidad.razonSocial,
                  style: AppTypography.caption.copyWith(color: colors.textMuted),
                ),
                const SizedBox(height: AppSpacing.lg),

                Expanded(
                  child: _cargando
                      ? const Center(child: CircularProgressIndicator())
                      : SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (_fallo case final f?) ...[
                                Text(
                                  'No se pudo cargar el domicilio: ${f.message}',
                                  style: AppTypography.caption.copyWith(
                                    color: colors.error,
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.md),
                              ],
                              SeccionDeDomicilio(
                                campos: _domicilio,
                                habilitado: !_guardando,
                                erroresPorCampo: const {},
                                titulo: 'Domicilio fiscal',
                                descripcion: _cargado == null
                                    ? 'Hacen falta calle, número exterior, colonia, '
                                          'municipio, estado y código postal. El '
                                          'código postal fiscal es obligatorio para '
                                          'emitir una factura.'
                                    : 'Una vez registrado, el domicilio fiscal se '
                                          'corrige: no se puede quitar desde aquí.',
                              ),
                            ],
                          ),
                        ),
                ),

                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: RisegButton(
                        label: 'Cancelar',
                        variant: RisegButtonVariant.secondary,
                        onPressed: _guardando
                            ? null
                            : () => Navigator.of(context).pop(false),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: RisegButton(
                        label: 'Guardar',
                        loading: _guardando,
                        onPressed: _guardando || _cargando ? null : _guardar,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _guardar() async {
    final direccion = _domicilio.direccion;

    // VACIARLO NO SE MANDA (D-59): el servidor no puede borrarlo y contestaría «Falta la
    // calle.», que es cierto y no explica qué pasa.
    if (direccion == null) {
      RisegFeedback.showError(
        context,
        _cargado == null
            ? 'Escribe el domicilio fiscal o cierra sin guardar.'
            : 'El domicilio fiscal no se puede quitar desde aquí: corrígelo o vuelve '
                  'a escribirlo como estaba.',
      );

      return;
    }

    setState(() => _guardando = true);

    final resultado = await widget.repositorio.guardarDomicilioFiscal(
      empresaId: widget.empresaId,
      clienteId: widget.clienteId,
      entidadId: widget.entidad.id,
      direccion: direccion,
    );

    if (!mounted) return;

    resultado.when(
      ok: (_) => Navigator.of(context).pop(true),
      failure: (f) {
        setState(() => _guardando = false);
        mostrarRechazoDelServidor(context, f);
      },
    );
  }
}
