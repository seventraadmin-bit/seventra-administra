import 'package:flutter/material.dart';

import '../../../../core/company/autoridad_de_organizacion.dart';
import '../../../../core/company/logotipos_de_empresa.dart';
import '../../../../core/design_system/design_system_web.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/error/result.dart';
import '../../../../core/fechas/fecha_en_pantalla.dart';
import '../../../usuarios/web/tarjeta_de_empresa.dart';
import '../datos/empresas_repositorio_http.dart';
import '../modelos/empresa_administrada.dart';
import 'campos_de_alta_de_empresa.dart';

/// E2 · **Administración de empresas** de la Organization.
///
/// ## Para quién es, y por qué no es una pestaña del menú
///
/// Esta pantalla pide la autoridad de **Organization** —Owner, o Admin con
/// `companies.manage`—, que es otro plano que los permisos de Company con los que se
/// gobiernan las demás pestañas. El registro de apartados sólo entiende permisos de
/// Company, así que enseñarla desde ahí habría exigido enseñarle un segundo sistema de
/// autoridad. Vive **dentro** de Organización › Empresa, junto a la ficha.
///
/// **Un Maestro que no sea miembro de la Organization no la ve.** Administra *su*
/// empresa; no da de alta empresas nuevas.
///
/// ## Los cuatro verbos, y uno no es un borrado
///
/// Crear · Desactivar · Reactivar · **Descartar**. El borrado físico **no existe**: una
/// empresa descartada se queda en la base con su estado y desaparece de todas las
/// listas, porque su propia traza de auditoría la retiene — y conservarla es el punto.
///
/// 🚫 **Descartar no se revierte desde aquí**, y el diálogo lo dice antes de pedir el
/// nombre escrito. Recuperarla será cosa de SEVENTRA.
class EmpresasAdministracionScreen extends StatefulWidget {
  const EmpresasAdministracionScreen({
    required this.repositorio,
    required this.logotipos,
    required this.organizationId,
    required this.autoridad,
    required this.empresaActivaId,
    this.alCambiarLaLista,
    super.key,
  });

  final EmpresasRepositorioHttp repositorio;
  final LogotiposDeEmpresa logotipos;
  final String organizationId;

  /// Qué puede hacer esta persona. **Se recibe ya resuelta**: quien monta esta pantalla
  /// ya decidió que debe existir, y preguntarlo otra vez aquí daría dos respuestas.
  final AutoridadDeOrganizacion autoridad;

  /// La empresa en la que se está trabajando, para marcarla y para **no ofrecer
  /// desactivarla**: dejarse fuera a uno mismo de un clic no es una decisión, es un
  /// accidente.
  final String empresaActivaId;

  /// ¿Lo que se escribió para confirmar es el nombre de la empresa?
  ///
  /// ⚠️ **IGNORA LAS COMILLAS DE LOS EXTREMOS, y es un arreglo de algo que pasó.** La
  /// primera versión pintaba «Escribe «X» para confirmar» en la etiqueta del campo, y
  /// copiar ese texto con el ratón se lleva las angulares dentro: el nombre se rechazaba
  /// por unas comillas que eran **de la pantalla y no del nombre**.
  ///
  /// La vista ya no las pinta —el nombre va en negritas y sin comillas— y aun así se
  /// perdonan aquí: quien las escriba de memoria está acertando, no equivocándose.
  ///
  /// **Lo que NO se afloja** es el resto: la defensa es que la persona LEA el nombre y lo
  /// copie, así que un parecido no vale. Y **sólo los extremos**: una empresa que se
  /// llame `RISEG "Norte"` conserva las suyas, porque están dentro.
  ///
  /// Es pública y estática **para poder probarla sin montar la pantalla**: las comillas
  /// sólo se ven copiando con el ratón, y una prueba que escriba el nombre a mano
  /// acierta siempre.
  static bool confirmacionCoincide(String escrito, String nombre) =>
      _sinComillas(escrito).isNotEmpty &&
      _sinComillas(escrito) == _sinComillas(nombre);

  /// El texto sin las comillas de los extremos ni los espacios de alrededor.
  static String _sinComillas(String texto) {
    var limpio = texto.trim();

    // Las angulares —que eran las que ponía la pantalla—, las rectas y las tipográficas.
    const comillas = '«»"“”';

    while (limpio.isNotEmpty && comillas.contains(limpio[0])) {
      limpio = limpio.substring(1);
    }

    while (limpio.isNotEmpty && comillas.contains(limpio[limpio.length - 1])) {
      limpio = limpio.substring(0, limpio.length - 1);
    }

    return limpio.trim();
  }

  /// Para que el marco refresque su menú de empresas cuando esta pantalla cambia alguna.
  /// **No se recarga desde aquí**: la lista del marco tiene un dueño.
  ///
  /// **Recibe la empresa afectada, o nulo al crear**, y hace falta: si la afectada es la
  /// que está abierta, lo que toca es volver a resolver —el contexto entero cambió—;
  /// si es otra, basta releer la lista. Sin ese dato, el marco tendría que elegir
  /// siempre lo más caro, y lo más caro **devuelve a «Elige una empresa»**.
  final ValueChanged<String?>? alCambiarLaLista;

  @override
  State<EmpresasAdministracionScreen> createState() =>
      _EmpresasAdministracionScreenState();
}

class _EmpresasAdministracionScreenState
    extends State<EmpresasAdministracionScreen> {
  List<EmpresaAdministrada> _empresas = const [];
  Failure? _fallo;
  bool _cargando = true;

  /// Cuál está en medio de una operación. Es el id y no un `bool` porque hay que señalar
  /// **esa** fila mientras las demás se apagan.
  String? _ocupada;

  /// Si se enseñan las inactivas. **Ocultas por omisión**: en el caso normal son ruido.
  bool _conInactivas = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _fallo = null;
    });

    final leida = await widget.repositorio.listar(widget.organizationId);

    if (!mounted) return;

    setState(() {
      _cargando = false;

      leida.when(
        ok: (lista) => _empresas = lista,
        failure: (f) => _fallo = f,
      );
    });
  }

  List<EmpresaAdministrada> get _visibles => [
    for (final e in _empresas)
      if (_conInactivas || e.estaActiva) e,
  ];

  int get _activas => _empresas.where((e) => e.estaActiva).length;

  /// Ejecuta una operación y refresca. **Un solo sitio** para el patrón, porque los
  /// cuatro verbos comparten exactamente el mismo: apagar la fila, pedir, decir qué
  /// pasó, recargar y avisar al marco.
  Future<void> _operar({
    required String? companyId,
    required Future<Result<void>> Function() operacion,
    required String exito,
  }) async {
    setState(() => _ocupada = companyId ?? '—');

    final resultado = await operacion();

    if (!mounted) return;

    setState(() => _ocupada = null);

    await resultado.when(
      ok: (_) async {
        RisegFeedback.showSuccess(context, exito);

        await _cargar();

        // EL MENÚ DE LA BARRA TAMBIÉN CAMBIA: una empresa desactivada o descartada
        // desaparece de él, y una nueva aparece. Sin este aviso, la barra seguiría
        // ofreciendo entrar a una empresa que ya no admite a nadie.
        //
        // SE LE DICE CUÁL: con el id, el marco relee la lista y se queda donde está.
        // Sin él tendría que volver a resolver, y resolver con varias empresas devuelve
        // a «Elige una empresa» — que es exactamente el defecto que esto arregla.
        widget.alCambiarLaLista?.call(companyId);
      },
      failure: (f) async => RisegFeedback.showError(context, _humano(f)),
    );
  }

  /// El fallo, en palabras. **Los códigos se distinguen aquí y no en el mensaje del
  /// servidor**: cada uno tiene un arreglo distinto, y el de capacidad llega con cifras
  /// que conviene no reescribir.
  String _humano(Failure fallo) {
    if (fallo is! ApiHttpFailure) return fallo.message;

    return switch (fallo.codigo) {
      EmpresasRepositorioHttp.codigoUltimaActiva =>
        'Es la única empresa activa: activa o crea otra antes.',

      EmpresasRepositorioHttp.codigoSinCambio =>
        'Esa empresa ya estaba así. Vuelve a cargar la lista.',

      EmpresasRepositorioHttp.codigoConDatos =>
        'Esa empresa ya tiene datos registrados, así que no se puede descartar. '
            'Desactívala si ya no opera.',

      EmpresasRepositorioHttp.codigoDescartada =>
        'Esa empresa está descartada y desde aquí no se puede recuperar.',

      EmpresasRepositorioHttp.codigoSinAutoridad =>
        'No tienes autoridad para esta operación.',

      // LA DE CAPACIDAD SE PASA TAL CUAL: el servidor manda las dos cifras —«tu plan
      // permite 5 empresas y quedarían 6»— y reescribirla las perdería.
      _ => fallo.message,
    };
  }

  // =========================================================================
  // Los cuatro verbos
  // =========================================================================

  Future<void> _crear() async {
    final datos = await _pedirAlta(context);
    if (datos == null || !mounted) return;

    final nombre = datos.nombre.trim();

    // SIN NOMBRE NO SE MANDA NADA. El servidor lo rechazaría con un 422, y gastar un
    // viaje para que conteste lo que la pantalla ya sabe es ruido.
    if (nombre.isEmpty) {
      RisegFeedback.showError(context, 'Hace falta el nombre comercial.');
      return;
    }

    await _operar(
      companyId: null,
      operacion: () => widget.repositorio.crear(
        organizationId: widget.organizationId,
        nombre: nombre,
        razonSocial: datos.razonSocial,
      ),
      exito: 'Empresa «$nombre» creada. Ya puedes entrar en ella.',
    );
  }

  Future<void> _desactivar(EmpresaAdministrada empresa) async {
    final escrito = await _pedirMotivo(
      context,
      titulo: 'Desactivar ${empresa.nombre}',
      cuerpo:
          'Deja de operar y desaparece de «Elige una empresa» y del menú de la barra. '
          '${_quienQuedaFuera(empresa)}\n\n'
          'Se puede reactivar después, y conserva su equipo y sus datos.',
      accion: 'Desactivar',
    );

    if (escrito == null || !mounted) return;

    final motivo = escrito.motivo.trim();

    if (motivo.isEmpty) {
      RisegFeedback.showError(
        context,
        'Hace falta el motivo: no se desactivó nada.',
      );
      return;
    }

    await _operar(
      companyId: empresa.companyId,
      operacion: () => widget.repositorio.desactivar(
        organizationId: widget.organizationId,
        companyId: empresa.companyId,
        motivo: motivo,
      ),
      exito: '${empresa.nombre} quedó desactivada.',
    );
  }

  Future<void> _reactivar(EmpresaAdministrada empresa) => _operar(
    companyId: empresa.companyId,
    operacion: () => widget.repositorio.reactivar(
      organizationId: widget.organizationId,
      companyId: empresa.companyId,
    ),
    exito: '${empresa.nombre} vuelve a operar.',
  );

  Future<void> _descartar(EmpresaAdministrada empresa) async {
    final escrito = await _pedirMotivo(
      context,
      titulo: 'Descartar ${empresa.nombre}',
      cuerpo:
          'Para las empresas creadas por error. Desaparece de TODAS las listas, '
          'incluida ésta, y libera su lugar en el plan.\n\n'
          '⚠️ Desde Administra esto NO se puede deshacer: recuperarla tendría que '
          'hacerlo SEVENTRA.\n\n'
          'Sólo funciona si la empresa no tiene ningún dato registrado.',
      accion: 'Descartar',
      // LA CONFIRMACIÓN ESCRIBIENDO EL NOMBRE, y sólo aquí: es la defensa contra el
      // clic equivocado en lo único que no se deshace desde Administra.
      nombreAEscribir: empresa.nombre,
    );

    if (escrito == null || !mounted) return;

    final motivo = escrito.motivo.trim();

    if (motivo.isEmpty) {
      RisegFeedback.showError(context, 'Hace falta el motivo: no se descartó nada.');
      return;
    }

    // EL NOMBRE SE COMPARA EXACTO, pero **sin las comillas que son de la pantalla y no
    // del nombre**: alguien copió el texto con las angulares dentro y se rechazó. La
    // vista ya no las pinta, y aun así se ignoran aquí — porque el que las escriba de
    // memoria está acertando, no equivocándose.
    //
    // Lo que NO se afloja es el resto: se busca que la persona LO LEA y lo copie. Y si
    // no coincide **no se descarta nada y se dice**, en vez de cerrarse en silencio: un
    // diálogo que se cierra sin hacer nada parece que hizo algo.
    if (!EmpresasAdministracionScreen.confirmacionCoincide(
      escrito.confirmacion,
      empresa.nombre,
    )) {
      RisegFeedback.showError(
        context,
        'El nombre no coincide: no se descartó nada.',
      );
      return;
    }

    await _operar(
      companyId: empresa.companyId,
      operacion: () => widget.repositorio.descartar(
        organizationId: widget.organizationId,
        companyId: empresa.companyId,
        motivo: motivo,
      ),
      exito: '${empresa.nombre} quedó descartada.',
    );
  }

  String _quienQuedaFuera(EmpresaAdministrada empresa) => switch (empresa.accesos) {
    0 => 'Nadie tiene acceso a ella ahora mismo.',
    1 => 'Una persona con acceso dejará de poder entrar.',
    final n => '$n personas con acceso dejarán de poder entrar.',
  };

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
              Text(_humano(fallo), textAlign: TextAlign.center),
              const SizedBox(height: AppSpacing.md),
              RisegButton(label: 'Volver a intentar', onPressed: _cargar),
            ],
          ),
        ),
      );
    }

    final colors = context.colors;
    final inactivas = _empresas.length - _activas;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: RisegSectionHeader(
                  title: 'Empresas',
                  description:
                      '$_activas ${_activas == 1 ? 'activa' : 'activas'}'
                      '${inactivas == 0 ? '' : ' · $inactivas inactiva${inactivas == 1 ? '' : 's'}'}',
                ),
              ),
              RisegButton(
                key: const Key('admin_empresas_nueva'),
                label: 'Nueva empresa',
                onPressed: _ocupada == null ? _crear : null,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),

          // LA CASILLA SÓLO SI HAY ALGO QUE ENSEÑAR: con cero inactivas, una casilla
          // que no cambia nada ocupa espacio y no dice nada.
          if (inactivas > 0)
            Align(
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Checkbox(
                    key: const Key('admin_empresas_ver_inactivas'),
                    value: _conInactivas,
                    onChanged: (v) => setState(() => _conInactivas = v ?? false),
                  ),
                  Text(
                    'Mostrar las inactivas',
                    style: AppTypography.caption.copyWith(color: colors.textMuted),
                  ),
                ],
              ),
            ),

          const SizedBox(height: AppSpacing.sm),
          Expanded(
            child: ListView.separated(
              itemCount: _visibles.length,
              separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
              itemBuilder: (_, i) {
                final empresa = _visibles[i];

                return _Fila(
                  key: Key('admin_empresa_${empresa.companyId}'),
                  empresa: empresa,
                  logotipos: widget.logotipos,
                  esLaActiva: empresa.companyId == widget.empresaActivaId,
                  puedeDescartar: widget.autoridad.puedeEliminarEmpresas,
                  ocupada: _ocupada == empresa.companyId,
                  apagada: _ocupada != null && _ocupada != empresa.companyId,
                  alDesactivar: () => _desactivar(empresa),
                  alReactivar: () => _reactivar(empresa),
                  alDescartar: () => _descartar(empresa),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Una empresa en la lista de administración.
class _Fila extends StatelessWidget {
  const _Fila({
    required this.empresa,
    required this.logotipos,
    required this.esLaActiva,
    required this.puedeDescartar,
    required this.ocupada,
    required this.apagada,
    required this.alDesactivar,
    required this.alReactivar,
    required this.alDescartar,
    super.key,
  });

  final EmpresaAdministrada empresa;
  final LogotiposDeEmpresa logotipos;
  final bool esLaActiva;
  final bool puedeDescartar;
  final bool ocupada;
  final bool apagada;
  final VoidCallback alDesactivar;
  final VoidCallback alReactivar;
  final VoidCallback alDescartar;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Opacity(
      opacity: apagada ? 0.5 : 1,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: esLaActiva ? colors.accent : colors.borderSubtle,
            width: esLaActiva ? 1.6 : 1,
          ),
        ),
        child: Row(
          children: [
            RecuadroDeLogotipo(
              companyId: empresa.companyId,
              nombre: empresa.nombre,
              logotipos: logotipos,
              lado: 40,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    empresa.nombre,
                    style: AppTypography.bodyStrong,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  // LA RAZÓN SOCIAL SE OMITE CUANDO NO HAY, igual que en la tarjeta de
                  // «Elige una empresa»: ausencia nunca es cero.
                  if (empresa.razonSocial != null)
                    Text(
                      empresa.razonSocial!,
                      style: AppTypography.caption.copyWith(color: colors.textMuted),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  // LA FECHA DE ALTA VA JUNTO A LOS ACCESOS, y no es decoración: esta
                  // lista es la única que ofrece «Descartar», que existe **para las
                  // empresas creadas por error**. Saber cuándo nació cada una es lo que
                  // permite reconocer a esa, sobre todo entre dos con nombres parecidos.
                  //
                  // El servidor ya la mandaba y el modelo ya la exigía —una fecha mal
                  // formada rompía la lista entera— para un dato que no se enseñaba en
                  // ninguna parte. O se muestra o se quita; se muestra.
                  Text(
                    '${empresa.accesos == 1 ? '1 persona con acceso' : '${empresa.accesos} personas con acceso'}'
                    ' · creada el ${fechaCorta(empresa.creada)}',
                    style: AppTypography.caption.copyWith(color: colors.textMuted),
                  ),
                ],
              ),
            ),

            if (esLaActiva) ...[
              const RisegStatusBadge(
                label: 'Abierta',
                tone: RisegStatusTone.success,
                icon: Icons.check_circle_outline,
              ),
              const SizedBox(width: AppSpacing.xs),
            ],

            if (!empresa.estaActiva) ...[
              const RisegStatusBadge(
                label: 'Inactiva',
                tone: RisegStatusTone.neutral,
                icon: Icons.pause_circle_outline,
              ),
              const SizedBox(width: AppSpacing.xs),
            ],

            if (ocupada)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2.2),
              )
            else
              _Menu(
                empresa: empresa,
                esLaActiva: esLaActiva,
                puedeDescartar: puedeDescartar,
                habilitado: !apagada,
                alDesactivar: alDesactivar,
                alReactivar: alReactivar,
                alDescartar: alDescartar,
              ),
          ],
        ),
      ),
    );
  }
}

/// El menú de la fila: **sólo lo que aplica**, y cuando algo no aplica se dice por qué.
///
/// Un elemento deshabilitado sin explicación obliga a adivinar; uno ausente obliga a
/// buscarlo. Con el motivo escrito, ni una cosa ni la otra.
class _Menu extends StatelessWidget {
  const _Menu({
    required this.empresa,
    required this.esLaActiva,
    required this.puedeDescartar,
    required this.habilitado,
    required this.alDesactivar,
    required this.alReactivar,
    required this.alDescartar,
  });

  final EmpresaAdministrada empresa;
  final bool esLaActiva;
  final bool puedeDescartar;
  final bool habilitado;
  final VoidCallback alDesactivar;
  final VoidCallback alReactivar;
  final VoidCallback alDescartar;

  @override
  Widget build(BuildContext context) => PopupMenuButton<VoidCallback>(
    key: Key('admin_menu_${empresa.companyId}'),
    enabled: habilitado,
    tooltip: 'Más acciones',
    icon: const Icon(Icons.more_vert),
    onSelected: (accion) => accion(),
    itemBuilder: (_) => [
      if (empresa.estaActiva)
        PopupMenuItem<VoidCallback>(
          value: alDesactivar,
          // LA EMPRESA EN LA QUE SE ESTÁ TRABAJANDO NO SE OFRECE DESACTIVAR: dejarse
          // fuera a uno mismo de un clic no es una decisión, es un accidente. Y el
          // servidor tampoco lo impide, así que la defensa es ésta.
          enabled: !esLaActiva,
          child: Text(
            esLaActiva
                ? 'Desactivar — cambia de empresa primero'
                : 'Desactivar',
          ),
        )
      else
        PopupMenuItem<VoidCallback>(
          value: alReactivar,
          child: const Text('Reactivar'),
        ),

      // DESCARTAR SÓLO PARA EL OWNER. Si no puede, no aparece: un elemento que siempre
      // responde «no tienes autoridad» es ruido.
      if (puedeDescartar)
        PopupMenuItem<VoidCallback>(
          value: alDescartar,
          enabled: !esLaActiva,
          child: Text(
            esLaActiva
                ? 'Descartar — cambia de empresa primero'
                : 'Descartar…',
          ),
        ),
    ],
  );
}

/// Lo que se escribe en un diálogo, **mutable y compartido** con `onConfirm`.
///
/// Es la forma que ya usa `dialogo_de_choque.dart`: `RisegDialog.showForm` construye el
/// marco —título, botones, foco atrapado y el cierre completo de la ruta— y el contenido
/// escribe aquí. Montar un `AlertDialog` propio habría dejado esta pantalla fuera de
/// todo eso, que es justo lo que `RisegDialog` existe para no repetir.
class _LoEscrito {
  String nombre = '';
  String razonSocial = '';
  String motivo = '';
  String confirmacion = '';
}

/// El alta: nombre comercial y, si se quiere, razón social.
Future<_LoEscrito?> _pedirAlta(BuildContext context) {
  final escrito = _LoEscrito();

  return RisegDialog.showForm<_LoEscrito>(
    context: context,
    title: 'Nueva empresa',
    confirmLabel: 'Crear',
    cancelLabel: 'Cancelar',
    contentBuilder: (_) => _FormularioDeAlta(escrito: escrito),
    onConfirm: () async => escrito,
  );
}

/// El contenido del diálogo de alta.
///
/// Los campos son los de [CamposDeAltaDeEmpresa], **compartidos con la pantalla de la
/// primera empresa (E3)**: lo único que este envoltorio añade es el ancho del diálogo,
/// que es una decisión del diálogo y no de los campos.
class _FormularioDeAlta extends StatelessWidget {
  const _FormularioDeAlta({required this.escrito});

  final _LoEscrito escrito;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 420,
    child: CamposDeAltaDeEmpresa(
      alEscribirNombre: (v) => escrito.nombre = v,
      alEscribirRazonSocial: (v) => escrito.razonSocial = v,
    ),
  );
}

/// El motivo, y para descartar también el nombre escrito.
Future<_LoEscrito?> _pedirMotivo(
  BuildContext context, {
  required String titulo,
  required String cuerpo,
  required String accion,
  String? nombreAEscribir,
}) {
  final escrito = _LoEscrito();

  return RisegDialog.showForm<_LoEscrito>(
    context: context,
    title: titulo,
    confirmLabel: accion,
    cancelLabel: 'Cancelar',
    // DESTRUCTIVO SÓLO CUANDO PIDE EL NOMBRE, o sea al descartar: desactivar se
    // deshace, y pintarlo en rojo igualaría dos cosas que no son iguales.
    destructive: nombreAEscribir != null,
    contentBuilder: (_) => _FormularioDeMotivo(
      escrito: escrito,
      cuerpo: cuerpo,
      nombreAEscribir: nombreAEscribir,
    ),
    onConfirm: () async => escrito,
  );
}

class _FormularioDeMotivo extends StatefulWidget {
  const _FormularioDeMotivo({
    required this.escrito,
    required this.cuerpo,
    this.nombreAEscribir,
  });

  final _LoEscrito escrito;
  final String cuerpo;
  final String? nombreAEscribir;

  @override
  State<_FormularioDeMotivo> createState() => _FormularioDeMotivoState();
}

class _FormularioDeMotivoState extends State<_FormularioDeMotivo> {
  final _motivo = TextEditingController();
  final _confirmacion = TextEditingController();

  @override
  void dispose() {
    _motivo.dispose();
    _confirmacion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return SizedBox(
      width: 460,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.cuerpo, style: AppTypography.body),
          const SizedBox(height: AppSpacing.md),
          RisegTextField(
            key: const Key('motivo'),
            label: 'Motivo',
            controller: _motivo,
            autofocus: true,
            onChanged: (v) => widget.escrito.motivo = v,
          ),
          Text(
            'Queda en la auditoría, con tu nombre y la fecha.',
            style: AppTypography.caption.copyWith(color: colors.textMuted),
          ),
          if (widget.nombreAEscribir != null) ...[
            const SizedBox(height: AppSpacing.md),

            // ⚠️ EL NOMBRE VA EN NEGRITAS Y SIN COMILLAS, y no es estética. La primera
            // versión ponía «Escribe «X» para confirmar» en la etiqueta del campo, y
            // alguien copió el texto **con las comillas angulares dentro** — que es lo
            // natural si lo que se ve es el nombre entrecomillado— y se rechazó.
            //
            // Las comillas eran mías, no del nombre de la empresa. Así que se quitan de
            // la vista y el nombre se destaca por el peso de la letra.
            Text.rich(
              TextSpan(
                style: AppTypography.body.copyWith(color: colors.textPrimary),
                children: [
                  const TextSpan(text: 'Escribe el nombre de la empresa, '),
                  TextSpan(
                    text: widget.nombreAEscribir,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const TextSpan(text: ', para confirmar:'),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            RisegTextField(
              key: const Key('nombre_a_escribir'),
              label: 'Nombre de la empresa',
              controller: _confirmacion,
              onChanged: (v) => widget.escrito.confirmacion = v,
            ),
          ],
        ],
      ),
    );
  }
}
