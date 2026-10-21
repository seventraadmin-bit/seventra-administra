import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../../core/company/company_remota.dart';
import '../../../../core/company/gestor_de_company.dart';
import '../../../../core/design_system/design_system_web.dart';
import '../../../../core/error/failure.dart';
import '../datos/expedientes_repositorio_http.dart';
import '../datos/logotipo_repositorio_http.dart';
import '../modelos/expediente.dart';
import 'empresa_ficha.dart';
import 'empresa_web_screen.dart';

/// La pestaña **Empresa**: la lista de empresas, la ficha de una, y su edición.
///
/// ## Por qué tres pasos y no un formulario siempre abierto
///
/// Hasta el 21 de octubre de 2026 esta pestaña **era** un formulario: se entraba
/// directamente a dieciséis campos editables. Eso tiene tres problemas que el
/// escritorio no tiene:
///
///  · **con varias empresas, no había dónde elegir** — la pestaña enseñaba la activa y
///    nada más, aunque la persona tuviera acceso a tres;
///  · **consultar y editar se confundían**: lo que se hace a diario es mirar el RFC
///    para dárselo a alguien, no cambiarlo;
///  · y los datos fiscales **no se veían con la forma en que se entregan**, que es la
///    de la tarjeta fiscal.
///
/// Así que el recorrido es: **lista → ficha → editar**, y editar **cierra al guardar**.
///
/// **Con una sola empresa la lista no se pinta** y se abre su ficha. Es la misma regla
/// que la barra de pestañas —«un rótulo que no lleva a ninguna parte ocupa espacio y no
/// dice nada»— y es el caso frecuente.
///
/// ## ⚠️ Tocar una fila CAMBIA LA EMPRESA ACTIVA
///
/// No es sólo navegar, y por eso se avisa. El marco entero —el menú, los permisos, el
/// rastro, el pie— se construye desde la **empresa activa**. Si la ficha de la empresa
/// B se abriera dejando activa la A, la regla «lo que no puedes hacer no se muestra» se
/// calcularía **contra la empresa equivocada**: el botón «Editar» aparecería según los
/// permisos en A mientras el `PUT` iría contra B, y el servidor contestaría 403 con
/// razón después de que la pantalla hubiera prometido lo contrario.
///
/// Y si hay cambios sin guardar, **se pregunta antes de cambiar**: cambiar de empresa
/// recarga el expediente, así que es la misma pérdida que cancelar.
class EmpresasWebScreen extends StatefulWidget {
  const EmpresasWebScreen({
    required this.repositorio,
    required this.logotipos,
    required this.gestorDeCompany,
    required this.empresas,
    required this.empresaActivaId,
    required this.puedeEditar,
    this.alCambiarElRastro,
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

  /// Las empresas a enseñar, **tal como el marco las recibió del gestor**.
  ///
  /// Se reciben en vez de pedirlas aquí por la misma razón que en el selector: lo que
  /// se pinta tiene que ser exactamente lo que el estado dijo. Pedirlas por su cuenta
  /// sería una segunda resolución, y dos pantallas podrían acabar mirando listas
  /// distintas en la misma sesión.
  final List<CompanyDisponible> empresas;

  final String empresaActivaId;

  /// `company.settings.manage`. Gobierna **el botón «Editar»** y, dentro, los campos.
  final bool puedeEditar;

  /// El tercer segmento del rastro: «Organización › Empresa › Editar».
  final ValueChanged<String?>? alCambiarElRastro;

  @override
  State<EmpresasWebScreen> createState() => _EmpresasWebScreenState();
}

/// En qué paso está la pantalla.
enum _Paso { lista, ficha, editando }

class _EmpresasWebScreenState extends State<EmpresasWebScreen> {
  /// **CON VARIAS EMPRESAS SE ENTRA POR LA LISTA; con una, por su ficha.**
  ///
  /// Es la misma forma que Sucursales —la lista es la entrada y la fila abre el
  /// expediente— y la razón de la excepción es la de la barra de pestañas: una lista de
  /// uno no decide nada y el paso de más se paga en cada visita.
  late _Paso _paso = widget.empresas.length > 1 ? _Paso.lista : _Paso.ficha;

  /// La lista que se está enseñando: **la que llegó del marco, con los renombrados
  /// de esta sesión ya puestos**.
  ///
  /// Se guarda una copia propia por una razón concreta: el marco la obtuvo cuando se
  /// resolvió la sesión, así que después de renombrar una empresa seguiría diciendo el
  /// nombre viejo hasta la siguiente resolución. Parchear la fila es lo mismo que hace
  /// la lista de sucursales al guardar — no es resolver nada, es actualizar lo que se
  /// recibió.
  late List<CompanyDisponible> _empresas = widget.empresas;
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
    _cargar();
  }

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

      // CON UNA SOLA EMPRESA NO HAY LISTA QUE ENSEÑAR.
      if (_paso == _Paso.lista && _empresas.length <= 1) {
        _paso = _Paso.ficha;
      }
    });
  }

  void _ir(_Paso paso) {
    setState(() => _paso = paso);

    widget.alCambiarElRastro?.call(switch (paso) {
      _Paso.lista => null,
      _Paso.ficha => null,
      _Paso.editando => 'Editar',
    });
  }

  /// Cambia la empresa activa y abre su ficha.
  ///
  /// **Pregunta primero si hay algo sin guardar**, porque cambiar de empresa recarga
  /// el expediente y lo escrito se perdería.
  Future<void> _abrir(CompanyDisponible empresa) async {
    if (empresa.companyId == widget.empresaActivaId) {
      _ir(_Paso.ficha);

      return;
    }

    if (!await _seguroDeSalir('cambiar de empresa')) return;

    final resultado = await widget.gestorDeCompany.cambiarA(empresa.companyId);

    if (!mounted) return;

    resultado.when(
      // NO SE RECARGA AQUÍ: al publicarse el contexto nuevo, el marco reconstruye esta
      // pantalla con otro `empresaActivaId` y `didUpdateWidget` lo hace. Recargar
      // también sería pedir el expediente dos veces.
      ok: (_) => _ir(_Paso.ficha),
      failure: (f) => RisegFeedback.showError(
        context,
        'No se pudo abrir ${empresa.companyName}: ${f.message}',
      ),
    );
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

    return switch (_paso) {
      _Paso.lista => _Lista(
        empresas: _empresas,
        activaId: widget.empresaActivaId,
        onAbrir: _abrir,
      ),
      _Paso.ficha => EmpresaFicha(
        expediente: expediente,
        regimenes: _regimenes,
        logotipo: _logotipo,
        logotipoFallo: _logotipoFallo,
        puedeEditar: widget.puedeEditar,
        // EL REGRESO A LA LISTA SÓLO SI HAY LISTA. Con una empresa, un «‹ Empresas»
        // que lleva a una lista de uno sería un paso que no decide nada.
        onVolverALaLista: _empresas.length > 1
            ? () => _ir(_Paso.lista)
            : null,
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

            // LA LISTA DICE EL NOMBRE NUEVO. La que llegó del marco se resolvió al
            // entrar, así que sin esto seguiría diciendo el viejo.
            _empresas = [
              for (final empresa in _empresas)
                if (empresa.companyId == widget.empresaActivaId)
                  empresa.conNombre(e.nombre)
                else
                  empresa,
            ];
          });

          _ir(_Paso.ficha);

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
  }
}

/// La lista de empresas que esta persona puede abrir.
class _Lista extends StatelessWidget {
  const _Lista({
    required this.empresas,
    required this.activaId,
    required this.onAbrir,
  });

  final List<CompanyDisponible> empresas;
  final String activaId;
  final ValueChanged<CompanyDisponible> onAbrir;

  /// ¿Hay más de una organización en la lista?
  ///
  /// **Si no, el nombre de la organización no se repite en cada fila:** cinco filas
  /// diciendo «Organización RISEG» es ruido que empuja fuera lo que distingue.
  bool get _variasOrganizaciones =>
      empresas.map((e) => e.organizationName).toSet().length > 1;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: context.colors.surface,
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const RisegSectionHeader(
              title: 'Empresas',
              description: 'Las empresas que puedes abrir. Toca una para ver su ficha.',
            ),
            const SizedBox(height: AppSpacing.md),
            Expanded(
              child: ListView.separated(
                itemCount: empresas.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (_, i) => _Fila(
                  empresa: empresas[i],
                  esLaActiva: empresas[i].companyId == activaId,
                  conOrganizacion: _variasOrganizaciones,
                  onTocar: () => onAbrir(empresas[i]),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _Fila extends StatelessWidget {
  const _Fila({
    required this.empresa,
    required this.esLaActiva,
    required this.conOrganizacion,
    required this.onTocar,
  });

  final CompanyDisponible empresa;
  final bool esLaActiva;
  final bool conOrganizacion;
  final VoidCallback onTocar;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return InkWell(
      onTap: onTocar,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.md,
          horizontal: AppSpacing.sm,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(empresa.companyName, style: AppTypography.bodyStrong),
                  if (conOrganizacion) ...[
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      empresa.organizationName,
                      style: AppTypography.caption.copyWith(
                        color: colors.textMuted,
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // CUÁL ESTÁ ABIERTA, dicho en la lista: tocar otra fila cambia la empresa
            // activa, así que saber en cuál se está es parte de la decisión.
            if (esLaActiva) ...[
              const RisegStatusBadge(
                label: 'Abierta',
                tone: RisegStatusTone.success,
                icon: Icons.check_circle_outline,
              ),
              const SizedBox(width: AppSpacing.xs),
            ],

            // EL ROL, que con varias empresas no es obvio: alguien puede ser Maestro
            // en una y Usuario en otra.
            RisegStatusBadge(
              label: empresa.role == 'maestro' ? 'Maestro' : 'Usuario',
              tone: RisegStatusTone.neutral,
              icon: Icons.badge_outlined,
            ),
            Icon(Icons.chevron_right, color: colors.textMuted),
          ],
        ),
      ),
    );
  }
}
