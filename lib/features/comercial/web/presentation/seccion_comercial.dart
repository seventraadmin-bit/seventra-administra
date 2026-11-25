import 'package:flutter/material.dart';

import '../../../../core/design_system/design_system_web.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/error/mensajes_humanos.dart';
import '../../../../core/fechas/dia_de_negocio.dart';
import '../../../../core/fechas/fecha_en_pantalla.dart';
import '../../../../core/trabajo_sin_guardar/declara_su_trabajo_sin_guardar.dart';
import '../../../../core/trabajo_sin_guardar/guardia_de_salida.dart';
import '../../../organizacion/web/datos/areas_repositorio_http.dart';
import '../../../organizacion/web/datos/puestos_repositorio_http.dart';
import '../../../organizacion/web/modelos/puesto.dart';
import '../../../organizacion/web/presentation/dialogo_de_puesto_rapido.dart';
import '../datos/condiciones_repositorio_http.dart';
import '../modelos/condicion_comercial.dart';
import 'dialogo_de_condicion.dart';
import 'seccion_de_sueldo_de_referencia.dart';

/// **La configuración comercial de un servicio**: sus líneas, lo que cobra cada una hoy y
/// lo que cobrará cuando entre la condición programada.
///
/// ## La forma que esto tiene que dejar clara
///
/// Un servicio cobra por **líneas**, y cada línea tiene **a lo sumo una condición vigente**
/// y **a lo sumo una programada**. La pantalla enseña esas dos y el resto es historial.
/// Mostrarlas todas en una lista plana haría imposible contestar la única pregunta que
/// importa de un vistazo: **¿cuánto cobra esto hoy?**
///
/// ## Las cinco acciones, y cuál pide motivo
///
/// | Acción | Motivo | Por qué |
/// |---|---|---|
/// | **Primera condición** | no | el motivo es para corregir, no para crear |
/// | **Programar la siguiente** | no | no reescribe nada: abre una vigencia nueva |
/// | **Corregir la programada** | no | todavía no fue realidad |
/// | **Corregir la vigente** | **sí** | es la que está cobrando, y sólo se puede si es la única de la línea |
/// | **Cerrar la vigente** | **sí** | la línea deja de cobrar, y en seis meses alguien preguntará por qué |
///
/// ## ⚠️ «Retirar» y «Cerrar» NO son lo mismo, y la pantalla lo dice
///
/// **Retirar la línea** impide abrirle condiciones nuevas y **deja su condición abierta**:
/// para la facturación sigue valiendo dinero. **Cerrar la condición vigente** es lo que hace
/// que deje de cobrar. Suenan igual y son opuestas en lo que importa, así que el menú las
/// separa y cada una explica su efecto antes de hacerlo.
///
/// ## 🚫 EL AUMENTO DE TARIFAS ES MANUAL, LÍNEA POR LÍNEA
///
/// No hay subida masiva y **esta pantalla no sugiere ninguna fecha**. Cada cliente sube
/// distinto según su negociación; que RISEG las suba en enero es **una costumbre de RISEG**,
/// no una regla del producto, y un botón que la impusiera convertiría la costumbre en ley
/// para todas las empresas.
class SeccionComercial extends StatefulWidget {
  const SeccionComercial({
    required this.repositorio,
    required this.empresaId,
    required this.servicioId,
    required this.puestos,
    required this.areas,
    required this.puedeAdministrar,
    required this.puedeTocarPrecios,
    required this.puedeVerSueldos,
    required this.hoy,
    required this.guardia,
    this.alCambiarLoQueCobra,
    super.key,
  });

  final CondicionesRepositorioHttp repositorio;
  final String empresaId;
  final String servicioId;

  /// El repositorio de **puestos**, para el selector de la condición.
  ///
  /// ⚠️ **Entra el repositorio y no la lista ya cargada**, y es a propósito: el expediente
  /// no necesita los puestos para nada más, así que precargarlos sería una lectura que paga
  /// todo el mundo para una pestaña que casi nadie abre. Se piden **al abrir esta pestaña**.
  final PuestosRepositorioHttp puestos;

  /// El repositorio de **áreas**, y está aquí por una sola razón: **crear un puesto sin
  /// salir del formulario** necesita su área.
  ///
  /// 🚫 **El dueño lo encontró probando el ensayo:** sin puestos operativos, el formulario
  /// sólo decía dónde se daban de alta, y seguir ese consejo significaba **salir, crear área
  /// y puesto, y volver a capturar todo**.
  final AreasRepositorioHttp areas;

  /// Se llama **después de cada cambio que mueve lo que el servicio cobra**.
  ///
  /// 🚫 **EXISTE PORQUE EL ENCABEZADO SE QUEDABA VIEJO.** El importe mensual vive en el
  /// expediente —esta pestaña es sólo una de sus pestañas— y no había forma de avisar hacia
  /// arriba: se guardaba una condición, la tarjeta decía «Cobra hoy $30,000» y el encabezado
  /// seguía diciendo «Sin condiciones vigentes» hasta recargar. Es **la duda número uno del
  /// inventario de RISEG ONE**, repetida aquí con otro dato.
  final VoidCallback? alCambiarLoQueCobra;

  /// `clients_services.manage`. Da de alta, renombra, retira y reactiva **líneas**.
  final bool puedeAdministrar;

  /// `clients_services.pricing.manage` (migración 0062). **Sin él no se abre ni se cambia
  /// una sola condición**, aunque se tenga `manage`: ver un precio no es cambiarlo, y dar de
  /// alta un cliente no es ponerle precio.
  final bool puedeTocarPrecios;

  /// `personal.sueldo.ver`, que es de **otro módulo**. Quien administra precios no ve
  /// sueldos por eso.
  final bool puedeVerSueldos;

  /// El día del negocio, del shell. **No se lee el reloj aquí**: el navegador tiene otra
  /// zona y la vigencia de una condición es dinero.
  final DiaDeNegocio Function() hoy;

  /// D-56 · el formulario de condición tiene campos y un «Guardar», así que **se registra**.
  /// Es la regla permanente del dueño, y vale también dentro de un diálogo: cerrarlo con la
  /// X perdería un formulario entero de precios y horarios.
  final GuardiaDeSalida guardia;

  @override
  State<SeccionComercial> createState() => _SeccionComercialState();
}

class _SeccionComercialState extends State<SeccionComercial> {
  List<LineaComercial>? _lineas;
  List<ModalidadDeTurno> _modalidades = const [];
  List<Puesto> _puestos = const [];

  /// El historial por línea, **cargado sólo cuando se abre**: un servicio con ocho líneas
  /// pediría ocho historiales al abrir la pestaña para enseñar dos filas de cada uno.
  final Map<String, List<CondicionComercial>> _condiciones = {};

  final Set<String> _abiertas = {};

  /// ¿Está desplegada la sección «Retiradas (N)»? **Cerrada por omisión**, decisión del dueño
  /// del 19-nov-2026: están ahí y se sabe cuántas son, pero no compiten con las vivas.
  bool _retiradasAbiertas = false;

  Failure? _fallo;
  bool _cargando = true;
  bool _guardando = false;

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

    // LAS TRES LECTURAS DE ARRANQUE, EN UNA SOLA TANDA. Antes eran tres viajes
    // encadenados —líneas, luego modalidades, luego puestos— y ninguno dependía del
    // anterior: era esperar tres veces para pintar una vez.
    final (lineas, modalidades, puestos) = await (
      widget.repositorio.lineas(
        empresaId: widget.empresaId,
        servicioId: widget.servicioId,
      ),
      widget.repositorio.modalidades(widget.empresaId),
      widget.puestos.listar(widget.empresaId),
    ).wait;

    if (!mounted) return;

    // ⚠️ `leyendo(...)` DEJA EL FALLO EN LA RAMA DE FALLO, no lanza: si esto lanzara dentro
    // de la rama `ok:` la pantalla se quedaría CARGANDO PARA SIEMPRE, sin error visible.
    final porAhora = lineas.when(
      ok: (l) => l,
      failure: (f) {
        setState(() {
          _fallo = f;
          _cargando = false;
        });

        return null;
      },
    );

    if (porAhora == null) return;

    // ⚠️ LOS DOS CATÁLOGOS SON DE LA EMPRESA Y NO DE ESTE SERVICIO, así que un fallo suyo
    // NO tumba la pestaña: las tarjetas siguen siendo útiles y el formulario lo dirá cuando
    // se abra. Lo que sí tumbaría la pestaña es que fallen las líneas, que es lo de arriba.

    setState(() {
      _lineas = porAhora;
      _modalidades = modalidades.when(ok: (m) => m, failure: (_) => const []);
      _puestos = puestos.when(ok: (p) => p, failure: (_) => const []);
      _cargando = false;
    });

    // LAS CONDICIONES DE CADA LÍNEA, Y AHORA SÍ EN PARALELO.
    //
    // 🚫 **ESTE COMENTARIO DECÍA «en paralelo» Y EL CÓDIGO ERA UN `for` CON `await`
    // DENTRO**: ocho líneas eran ocho viajes uno tras otro, y el dueño lo vio como «se
    // queda un buen rato». Un comentario que miente es peor que ninguno.
    await Future.wait([for (final linea in porAhora) _cargarCondiciones(linea.id)]);
  }

  Future<void> _cargarCondiciones(String lineaId) async {
    final historial = await widget.repositorio.historial(
      empresaId: widget.empresaId,
      servicioId: widget.servicioId,
      lineaId: lineaId,
    );

    if (!mounted) return;

    historial.when(
      ok: (c) => setState(() => _condiciones[lineaId] = c),
      // Un historial que falla deja la tarjeta sin su resumen y **no** tumba la pestaña:
      // las otras líneas siguen siendo útiles.
      failure: (_) {},
    );
  }

  /// Relee las condiciones de una línea **y avisa al encabezado**, después de cualquier
  /// mutación.
  ///
  /// 🚫 **EXISTE PORQUE TRES MUTACIONES QUE MUEVEN DINERO NO AVISABAN** (19-nov-2026):
  /// cerrar la condición vigente, cancelar la programada y guardar una condición releían la
  /// tarjeta y dejaban el encabezado con la cifra de antes. El dueño vio una de las dos
  /// mitades —«el encabezado no se refresca al retirar»— y las otras tres estaban igual.
  ///
  /// ⚠️ **Y NO VA DENTRO DE `_cargarCondiciones`**, que también corre al abrir la pestaña:
  /// ahí serían ocho avisos para una sola cifra. Lo que distingue a este camino no es leer
  /// las condiciones, es que **acaba de cambiar algo**.
  Future<void> _releerYAvisar(String lineaId) async {
    await _cargarCondiciones(lineaId);

    widget.alCambiarLoQueCobra?.call();
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) {
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.xl),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_fallo case final fallo?) {
      return RisegCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              MensajesHumanos.deMutacion(fallo),
              style: AppTypography.body,
            ),
            const SizedBox(height: AppSpacing.md),
            RisegButton(
              label: 'Reintentar',
              onPressed: _cargar,
              variant: RisegButtonVariant.secondary,
            ),
          ],
        ),
      );
    }

    final lineas = _lineas ?? const <LineaComercial>[];

    // 🚫 **LAS RETIRADAS AL FINAL Y PLEGADAS** (decisión del dueño, 19-nov-2026). Una línea
    // retirada **no desaparece** —sigue cobrando hasta que se cierre su condición, y su
    // historia es la de este servicio— pero tampoco compite por la vista con las vivas: en su
    // prueba en pantalla las retiradas se mezclaban con las activas y la pestaña se leía como
    // si todo estuviera igual de vigente.
    //
    // ⚠️ **Cerrada por omisión, y con su cuenta en el título:** así se sabe que están sin
    // tener que abrirlas, que es la diferencia entre plegar y esconder.
    final activas = [for (final l in lineas) if (l.estaActiva) l];
    final retiradas = [for (final l in lineas) if (!l.estaActiva) l];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RisegSectionHeader(
          title: 'Configuración comercial',
          description: lineas.isEmpty
              ? null
              : 'Lo que este servicio cobra hoy, línea por línea.',
          primaryAction: widget.puedeAdministrar
              ? RisegButton(
                  label: 'Nueva línea',
                  icon: Icons.add,
                  size: RisegButtonSize.compact,
                  onPressed: _guardando ? null : _nuevaLinea,
                )
              : null,
        ),
        const SizedBox(height: AppSpacing.md),
        if (lineas.isEmpty)
          RisegEmptyState(
            icon: Icons.receipt_long_outlined,
            title: 'Este servicio no cobra nada todavía',
            message:
                'Una línea comercial es cada cosa que se le cobra al cliente: '
                '«12 guardias 24×24» es una línea y «1 supervisor» es otra. '
                'Cada una lleva su precio, sus plazas y su horario.',
            primaryAction: widget.puedeAdministrar
                ? RisegButton(label: 'Nueva línea', onPressed: _nuevaLinea)
                : null,
          )
        else ...[
          for (final linea in activas) ...[
            _tarjeta(linea),
            const SizedBox(height: AppSpacing.md),
          ],
          if (retiradas.isNotEmpty) ...[
            TextButton.icon(
              onPressed: () =>
                  setState(() => _retiradasAbiertas = !_retiradasAbiertas),
              icon: Icon(
                _retiradasAbiertas ? Icons.expand_less : Icons.expand_more,
              ),
              label: Text('Retiradas (${retiradas.length})'),
            ),
            if (_retiradasAbiertas)
              for (final linea in retiradas) ...[
                const SizedBox(height: AppSpacing.sm),
                _tarjeta(linea),
              ],
          ],
        ],
      ],
    );
  }

  /// La tarjeta de una línea, igual para las activas y para las retiradas.
  ///
  /// Se saca a un método para que plegar las retiradas no duplique sus trece argumentos: dos
  /// copias de esta lista divergirían la primera vez que alguien añada un permiso.
  Widget _tarjeta(LineaComercial linea) => _TarjetaDeLinea(
    linea: linea,
    condiciones: _condiciones[linea.id],
    modalidades: _modalidades,
    puestos: _puestos,
    hoy: widget.hoy,
    abierta: _abiertas.contains(linea.id),
    puedeAdministrar: widget.puedeAdministrar,
    puedeTocarPrecios: widget.puedeTocarPrecios,
    puedeVerSueldos: widget.puedeVerSueldos,
    ocupado: _guardando,
    alAbrirCerrar: () => setState(() {
      _abiertas.contains(linea.id)
          ? _abiertas.remove(linea.id)
          : _abiertas.add(linea.id);
    }),
    alActuar: (accion) => _actuar(linea, accion),
  );

  // =========================================================================
  // Las acciones
  // =========================================================================

  /// El alta de una línea: **un solo formulario** con su primera condición.
  ///
  /// 🚫 **ANTES ERAN DOS PASOS** —pedir el nombre y luego «Poner su condición»— y entre los
  /// dos quedaba una línea que **no cobra nada**. En RISEG ONE «Agregar línea» siempre creó
  /// la línea con su primera vigencia; aquí se había partido sin que nadie lo decidiera, y
  /// el dueño lo encontró en su prueba del 18-nov-2026.
  Future<void> _nuevaLinea() async {
    final plan = await mostrarDialogoDeCondicion(
      context,
      titulo: 'Nueva línea comercial',
      modalidades: _modalidades,
      puestos: _puestos,
      hoy: widget.hoy(),
      guardia: widget.guardia,
      pideSueldoDeReferencia: true,
      pideMotivo: false,
      pideNombre: true,
      alCrearPuesto: _crearPuestoDesdeElFormulario,
      alAgregarModalidades: _agregarModalidadesRecomendadas,
    );

    if (plan == null || !mounted) return;

    await _conGuardado(() async {
      final r = await widget.repositorio.crearLinea(
        empresaId: widget.empresaId,
        servicioId: widget.servicioId,
        nombre: plan.nombre!,
        tipo: plan.tipo,
        condicion: plan.condicion,
        sueldoDeReferenciaMenores: plan.sueldoDeReferenciaMenores,
        bonoDeReferenciaMenores: plan.bonoDeReferenciaMenores,
      );

      return r.when(
        ok: (creada) {
          setState(() {
            _lineas = [...?_lineas, creada.linea];
            _abiertas.add(creada.linea.id);

            // ⚠️ LA CONDICIÓN SE GUARDA EN EL MAPA AQUÍ MISMO, y por eso la tarjeta nace
            // completa en lugar de decir «Leyendo sus condiciones…» hasta que algo
            // recargue. Una lista vacía es «no cobra»; **ausente** es «no cargado», y
            // antes una línea recién creada se quedaba ausente para siempre.
            _condiciones[creada.linea.id] = [
              if (creada.condicion != null) creada.condicion!,
            ];
          });

          // Lo que el servicio cobra acaba de cambiar: el encabezado tiene que saberlo.
          widget.alCambiarLoQueCobra?.call();

          return 'Línea «${creada.linea.nombre}» creada con su primera condición.';
        },
        failure: (f) => throw _Rechazo(f),
      );
    });
  }

  /// Crea un puesto operativo **sin cerrar el formulario de la condición**, y su área si
  /// hace falta.
  Future<Puesto?> _crearPuestoDesdeElFormulario() async {
    final puesto = await mostrarPuestoRapido(
      context,
      empresaId: widget.empresaId,
      areas: widget.areas,
      puestos: widget.puestos,
      guardia: widget.guardia,
    );

    if (puesto == null) return null;

    // La lista de la pestaña también se queda al día: el siguiente formulario que se abra
    // ya lo tiene sin pedirlo otra vez.
    setState(() => _puestos = [..._puestos, puesto]);

    return puesto;
  }

  /// Agrega las modalidades recomendadas **desde el formulario**, cuando el catálogo está
  /// vacío. Devuelve el catálogo resultante.
  Future<List<ModalidadDeTurno>?> _agregarModalidadesRecomendadas() async {
    final r = await widget.repositorio.agregarModalidadesRecomendadas(widget.empresaId);

    return r.when(
      ok: (catalogo) {
        setState(() => _modalidades = catalogo);

        return catalogo;
      },
      failure: (f) {
        if (mounted) RisegFeedback.showError(context, MensajesHumanos.deMutacion(f));

        return null;
      },
    );
  }

  Future<void> _actuar(LineaComercial linea, _AccionDeLinea accion) async {
    switch (accion) {
      case _AccionDeLinea.renombrar:
        await _renombrar(linea);
      case _AccionDeLinea.retirar:
        await _retirar(linea);
      case _AccionDeLinea.reactivar:
        await _reactivar(linea);
      case _AccionDeLinea.primeraCondicion:
        await _condicion(linea, _ActoDeCondicion.primera, null);
      case _AccionDeLinea.programarSiguiente:
        await _condicion(linea, _ActoDeCondicion.programar, null);
      case _AccionDeLinea.corregirProgramada:
        await _condicion(
          linea,
          _ActoDeCondicion.corregir,
          _deLinea(linea.id, TemporalidadDeCondicion.futura),
        );
      case _AccionDeLinea.corregirVigente:
        await _condicion(
          linea,
          _ActoDeCondicion.corregir,
          _deLinea(linea.id, TemporalidadDeCondicion.vigente),
        );
      case _AccionDeLinea.cancelarProgramada:
        await _cancelar(linea);
      case _AccionDeLinea.cerrarVigente:
        await _cerrar(linea);
      case _AccionDeLinea.cambiarTermino:
        await _cambiarTermino(linea);
      case _AccionDeLinea.sueldoDeReferencia:
        await _sueldo(linea);
    }
  }

  Future<void> _renombrar(LineaComercial linea) async {
    final nombre = await _pedirNombre(
      titulo: 'Renombrar la línea',
      inicial: linea.nombre,
      ayuda:
          'Sólo el nombre. Su identidad y su historial de precios no cambian.',
    );

    if (nombre == null || nombre == linea.nombre || !mounted) return;

    await _conGuardado(() async {
      final r = await widget.repositorio.renombrarLinea(
        empresaId: widget.empresaId,
        servicioId: widget.servicioId,
        lineaId: linea.id,
        nombre: nombre,
      );

      return r.when(
        ok: _reemplazarLinea,
        failure: (f) => throw _Rechazo(f),
      );
    });
  }

  /// Retirar: **el último día que cobra y por qué**, y el servidor hace las dos cosas.
  ///
  /// 🚫 **ERA UNA CONFIRMACIÓN Y AHORA ES UN FORMULARIO**, por decisión del dueño del
  /// 19-nov-2026. El diálogo viejo **advertía** que retirar no dejaba de cobrar —la frase era
  /// cierta y aun así él se confundió en su prueba en pantalla—, porque lo que estaba partido
  /// era el acto, no la explicación.
  Future<void> _retirar(LineaComercial linea) async {
    final vigente = _deLinea(linea.id, TemporalidadDeCondicion.vigente);

    final retiro = await mostrarDialogoDeRetiro(
      context,
      nombreDeLaLinea: linea.nombre,
      hoy: widget.hoy(),
      inicioDeLaVigente: vigente?.inicio,
      // ⚠️ **LO QUE DECIDE SI SE PIDE LA FECHA ES SI HAY CONDICIÓN VIGENTE**, no si la línea
      // está activa: mandar una fecha sin nada que cerrar responde 422.
      cobraAlgo: vigente != null,
    );

    if (retiro == null || !mounted) return;

    await _conGuardado(() async {
      final r = await widget.repositorio.retirarLinea(
        empresaId: widget.empresaId,
        servicioId: widget.servicioId,
        lineaId: linea.id,
        motivo: retiro.motivo,
        ultimoDiaQueCobra: retiro.ultimoDiaQueCobra,
      );

      return r.when(
        ok: (retirada) async {
          // LA CONDICIÓN CERRADA LLEGA EN LA MISMA RESPUESTA, así que la tarjeta queda al día
          // sin volver a preguntar — y el historial, releído, enseña su fecha de término.
          await _cargarCondiciones(linea.id);

          _reemplazarLinea(retirada.linea);

          return retiro.ultimoDiaQueCobra == null
              ? 'Línea «${linea.nombre}» retirada.'
              : 'Línea «${linea.nombre}» retirada: cobra hasta el '
                    '${fechaDeNegocioCorta(retiro.ultimoDiaQueCobra!)}.';
        },
        failure: (f) => throw _Rechazo(f),
      );
    });
  }

  Future<void> _reactivar(LineaComercial linea) async {
    await _conGuardado(() async {
      final r = await widget.repositorio.reactivarLinea(
        empresaId: widget.empresaId,
        servicioId: widget.servicioId,
        lineaId: linea.id,
      );

      return r.when(ok: _reemplazarLinea, failure: (f) => throw _Rechazo(f));
    });
  }

  Future<void> _condicion(
    LineaComercial linea,
    _ActoDeCondicion acto,
    CondicionComercial? existente,
  ) async {
    if (acto == _ActoDeCondicion.corregir && existente == null) return;

    final resultado = await mostrarDialogoDeCondicion(
      context,
      titulo: switch (acto) {
        _ActoDeCondicion.primera => 'Primera condición de «${linea.nombre}»',
        _ActoDeCondicion.programar => 'Programar la siguiente condición',
        _ActoDeCondicion.corregir =>
          existente!.estado == TemporalidadDeCondicion.vigente
              ? 'Corregir la condición vigente'
              : 'Corregir la condición programada',
      },
      modalidades: _modalidades,
      puestos: _puestos,
      hoy: widget.hoy(),
      guardia: widget.guardia,
      existente: existente,
      // EL SUELDO DE REFERENCIA SÓLO SE PIDE EN LA PRIMERA. En las otras dos el servidor
      // lo rechaza con 422, y pedirlo para tirarlo sería hacer teclear un dato que no se
      // guarda.
      pideSueldoDeReferencia: acto == _ActoDeCondicion.primera,
      // Y EL MOTIVO sólo al corregir la VIGENTE, que es la que está cobrando.
      pideMotivo:
          acto == _ActoDeCondicion.corregir &&
          existente!.estado == TemporalidadDeCondicion.vigente,
    );

    if (resultado == null || !mounted) return;

    await _conGuardado(() async {
      final r = switch (acto) {
        _ActoDeCondicion.primera => await widget.repositorio.crearPrimera(
          empresaId: widget.empresaId,
          servicioId: widget.servicioId,
          lineaId: linea.id,
          condicion: resultado.condicion,
          sueldoDeReferenciaMenores: resultado.sueldoDeReferenciaMenores,
          bonoDeReferenciaMenores: resultado.bonoDeReferenciaMenores,
        ),
        _ActoDeCondicion.programar => await widget.repositorio.programarSiguiente(
          empresaId: widget.empresaId,
          servicioId: widget.servicioId,
          lineaId: linea.id,
          condicion: resultado.condicion,
        ),
        _ActoDeCondicion.corregir => await widget.repositorio.corregir(
          empresaId: widget.empresaId,
          servicioId: widget.servicioId,
          lineaId: linea.id,
          condicionId: existente!.id,
          condicion: resultado.condicion,
          version: existente.version,
          motivo: resultado.motivo,
        ),
      };

      return r.when(
        ok: (condicion) async {
          await _releerYAvisar(linea.id);

          // EL AVISO DE CUPO SE ENSEÑA APARTE Y DESPUÉS DEL ÉXITO. 🚫 No es un error: la
          // condición se guardó, y el servidor no movió a nadie.
          if (condicion.aviso case final aviso? when mounted) {
            await RisegDialog.showInformational(
              context: context,
              title: 'Se guardó, con un aviso',
              message:
                  '${aviso.enPantalla}\n\n'
                  'Si alguien tiene que dejar la línea, hay que moverlo en Personal: '
                  'el sistema no desasigna a nadie por un cambio de precio.',
              dismissLabel: 'Entendido',
            );
          }

          return 'Condición guardada.';
        },
        failure: (f) => throw _Rechazo(f),
      );
    });
  }

  Future<void> _cancelar(LineaComercial linea) async {
    final programada = _deLinea(linea.id, TemporalidadDeCondicion.futura);
    if (programada == null) return;

    final seguro = await RisegDialog.showConfirmation(
      context: context,
      title: 'Cancelar la condición programada',
      message:
          'Nunca entró en vigor, así que se elimina y no deja historia.\n\n'
          'Lo que está cobrando hoy no cambia: si su término se movió al '
          'programar ésta, vuelve a quedar abierto.',
      confirmLabel: 'Cancelar la condición',
      cancelLabel: 'Dejarla',
      destructive: true,
    );

    if (seguro != true || !mounted) return;

    await _conGuardado(() async {
      final r = await widget.repositorio.cancelarProgramada(
        empresaId: widget.empresaId,
        servicioId: widget.servicioId,
        lineaId: linea.id,
        condicionId: programada.id,
      );

      return r.when(
        ok: (_) async {
          await _releerYAvisar(linea.id);

          return 'Condición programada cancelada.';
        },
        failure: (f) => throw _Rechazo(f),
      );
    });
  }

  Future<void> _cerrar(LineaComercial linea) async {
    final vigente = _deLinea(linea.id, TemporalidadDeCondicion.vigente);
    if (vigente == null) return;

    final cierre = await mostrarDialogoDeCierre(
      context,
      nombreDeLaLinea: linea.nombre,
      hoy: widget.hoy(),
      inicioDeLaVigente: vigente.inicio,
    );

    if (cierre == null || !mounted) return;

    await _conGuardado(() async {
      final r = await widget.repositorio.cerrarVigente(
        empresaId: widget.empresaId,
        servicioId: widget.servicioId,
        lineaId: linea.id,
        termino: cierre.termino,
        motivo: cierre.motivo,
      );

      return r.when(
        ok: (_) async {
          await _releerYAvisar(linea.id);

          return 'La línea deja de cobrar después del '
              '${fechaDeNegocioCorta(cierre.termino)}.';
        },
        failure: (f) => throw _Rechazo(f),
      );
    });
  }

  /// **Cambia** el último día de cobro de una condición que ya lo tiene.
  ///
  /// 🚫 **Es otro acto, y por eso es otro método y otra ruta** (19-nov-2026). Lo que los
  /// separa en pantalla es la fecha precargada: aquí se abre con **la que ya está**, porque
  /// quien entra viene a corregirla y no a elegirla de cero.
  Future<void> _cambiarTermino(LineaComercial linea) async {
    final vigente = _deLinea(linea.id, TemporalidadDeCondicion.vigente);

    // Sin condición vigente, o sin término que cambiar, no hay acto: el menú no lo ofrece,
    // y esto es el cinturón para el caso en que la lista se haya quedado vieja.
    if (vigente?.termino == null) return;

    final cambio = await mostrarDialogoDeCierre(
      context,
      nombreDeLaLinea: linea.nombre,
      hoy: widget.hoy(),
      inicioDeLaVigente: vigente!.inicio,
      terminoActual: vigente.termino,
    );

    if (cambio == null || !mounted) return;

    await _conGuardado(() async {
      final r = await widget.repositorio.cambiarTerminoVigente(
        empresaId: widget.empresaId,
        servicioId: widget.servicioId,
        lineaId: linea.id,
        termino: cambio.termino,
        motivo: cambio.motivo,
      );

      return r.when(
        ok: (_) async {
          await _releerYAvisar(linea.id);

          return 'La línea cobra hasta el '
              '${fechaDeNegocioCorta(cambio.termino)}.';
        },
        failure: (f) => throw _Rechazo(f),
      );
    });
  }

  Future<void> _sueldo(LineaComercial linea) async {
    final cambio = await mostrarSueldoDeReferencia(
      context,
      repositorio: widget.repositorio,
      empresaId: widget.empresaId,
      servicioId: widget.servicioId,
      linea: linea,
      hoy: widget.hoy(),
      puedeCambiar: widget.puedeTocarPrecios,
      guardia: widget.guardia,
    );

    // ⚠️ NO SE RECARGAN LAS CONDICIONES: mover el sueldo de referencia **no toca el
    // precio**, y recargarlas daría a entender que sí. Es la mitad útil de la 0065.
    if (cambio == true && mounted) {
      RisegFeedback.showSuccess(context, 'Sueldo de referencia actualizado.');
    }
  }

  // =========================================================================
  // Apoyo
  // =========================================================================

  /// La condición de una línea con esa temporalidad, o nula.
  ///
  /// El servidor garantiza **a lo sumo una** vigente y **a lo sumo una** futura por línea,
  /// así que buscar la primera es exacto y no una aproximación.
  CondicionComercial? _deLinea(String lineaId, TemporalidadDeCondicion cual) {
    for (final c in _condiciones[lineaId] ?? const <CondicionComercial>[]) {
      if (c.estado == cual) return c;
    }

    return null;
  }

  String _reemplazarLinea(LineaComercial nueva) {
    setState(() {
      _lineas = [
        for (final l in _lineas ?? const <LineaComercial>[])
          if (l.id == nueva.id) nueva else l,
      ];
    });

    // 🚫 **EL ENCABEZADO SE RELEE AUNQUE ESTO NO MUEVA DINERO**, y es deliberado (prueba en
    // pantalla del dueño, 19-nov-2026: «el encabezado no se refresca al retirar»).
    //
    // Retirar **no** deja de cobrar, así que el importe no cambia y en teoría no habría que
    // releerlo. Pero esa es exactamente la clase de razonamiento que falla: la pantalla
    // acabaría dependiendo de que alguien recuerde **qué mutación mueve el dinero**, y el
    // día que una lo mueva sin que nadie lo note, el encabezado miente sin fallar. Cuesta un
    // `GET` y hace que la tarjeta y el encabezado no puedan discrepar nunca.
    widget.alCambiarLoQueCobra?.call();

    return 'Línea actualizada.';
  }

  Future<String?> _pedirNombre({
    required String titulo,
    required String inicial,
    required String ayuda,
  }) => showDialog<String>(
    context: context,
    builder: (_) => _DialogoDeNombre(
      titulo: titulo,
      inicial: inicial,
      ayuda: ayuda,
      guardia: widget.guardia,
    ),
  );

  /// Corre una mutación con el candado de «ya estoy guardando» y traduce su rechazo.
  ///
  /// ⚠️ **El candado existe porque dos clics seguidos son dos peticiones**, y la segunda
  /// llegaría con la versión vieja: el 409 saldría por un doble clic y no por un conflicto
  /// real.
  Future<void> _conGuardado(Future<String> Function() accion) async {
    setState(() => _guardando = true);

    try {
      final mensaje = await accion();

      if (mounted) RisegFeedback.showSuccess(context, mensaje);
    } on _Rechazo catch (rechazo) {
      if (!mounted) return;

      await _mostrarRechazo(rechazo.fallo);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  /// Enseña el rechazo, y **el del candado de versión con lo que el servidor tiene ahora**.
  ///
  /// 🚫 Sin `current`, un conflicto sólo puede decir «recarga» y la persona pierde lo que
  /// escribió. Con él se puede decir qué cambió y qué precio hay hoy.
  Future<void> _mostrarRechazo(Failure fallo) async {
    final codigo = fallo is ApiHttpFailure ? fallo.codigo : null;

    if (codigo == CondicionesRepositorioHttp.codigoDesactualizada) {
      final actual = CondicionesRepositorioHttp.actualDe(fallo);

      await RisegDialog.showInformational(
        context: context,
        title: 'Alguien más cambió esta condición',
        // 🚫 AQUÍ NO SE DICE «EL SERVIDOR», y lo cazó el candado de textos. A quien captura
        // no le dice nada: lo que necesita saber es **qué dice la condición ahora** y que
        // su trabajo no se perdió.
        message: actual == null
            ? 'No se guardó. Vuelve a abrirla para ver cómo está ahora.'
            : 'No se guardó, y lo que escribiste sigue aquí.\n\n'
                  'La condición cobra ahora '
                  '${_precio(actual.importeMenores, actual.moneda)} al mes.\n\n'
                  'Ciérralo, mira cómo quedó y decide qué conservar.',
        dismissLabel: 'Entendido',
      );

      if (mounted) await _cargar();

      return;
    }

    if (!mounted) return;

    RisegFeedback.showError(context, MensajesHumanos.deMutacion(fallo));
  }
}

/// El nombre de una línea, al darla de alta o al renombrarla.
///
/// ## Por qué es un widget con estado y no un `showForm` con un controlador
///
/// D-56 · **toda pantalla con «Guardar» se registra en el `GuardiaDeSalida`**, y eso incluye
/// un diálogo de un solo campo. Un `showForm` con el controlador en una variable local no
/// puede registrarse —no tiene `State`—, así que lo escrito se perdería al pulsar «atrás»,
/// al recargar o al cambiar de empresa **sin preguntar**.
///
/// ⚠️ **Y no es un caso menor por ser un campo.** La regla es permanente y tiene candado
/// precisamente porque cada excepción parece pequeña por separado; el formulario número
/// siete es el que cuesta media hora de captura.
class _DialogoDeNombre extends StatefulWidget {
  const _DialogoDeNombre({
    required this.titulo,
    required this.inicial,
    required this.ayuda,
    required this.guardia,
  });

  final String titulo;
  final String inicial;
  final String ayuda;
  final GuardiaDeSalida guardia;

  @override
  State<_DialogoDeNombre> createState() => _DialogoDeNombreState();
}

class _DialogoDeNombreState extends State<_DialogoDeNombre>
    with DeclaraSuTrabajoSinGuardar<_DialogoDeNombre> {
  @override
  GuardiaDeSalida get guardia => widget.guardia;

  /// Contra **lo cargado**, no contra «se tocó algo»: quien escribe y deja el nombre como
  /// estaba no tiene trabajo sin guardar.
  @override
  bool get hayCambiosSinGuardar => _nombre.text.trim() != widget.inicial.trim();

  @override
  String get queSePierde => widget.inicial.isEmpty
      ? 'la línea comercial que estás dando de alta'
      : 'el nombre nuevo de ${widget.inicial}';

  late final TextEditingController _nombre = TextEditingController(
    text: widget.inicial,
  );

  String? _error;

  @override
  void dispose() {
    _nombre.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.titulo),
    content: SizedBox(
      width: 480,
      child: RisegTextField(
        label: 'Nombre de la línea',
        controller: _nombre,
        helperText: widget.ayuda,
        helperMaxLines: 3,
        errorText: _error,
        autofocus: true,
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: () {
          final nombre = _nombre.text.trim();

          if (nombre.isEmpty) {
            setState(() => _error = 'El nombre no puede quedar vacío.');

            return;
          }

          Navigator.of(context).pop(nombre);
        },
        child: const Text('Guardar'),
      ),
    ],
  );
}

/// Un día del negocio para la pantalla, o `sin fecha` cuando no hay.
///
/// **Nulo no se pinta como un hueco en blanco**: una condición sin término es lo normal —
/// cobra hasta que se cierre o se programe la siguiente—, y dejar el espacio vacío se leería
/// como un dato que falta.
String _dia(DiaDeNegocio? dia) =>
    dia == null ? 'sin fecha' : fechaDeNegocioCorta(dia);

/// `$15,000.00 MXN` a partir de las unidades menores.
///
/// ⚠️ **SE DIVIDE ENTRE 100 Y ESO ES UNA SUPOSICIÓN DICHA EN VOZ ALTA**, igual que en
/// `Monto`: no todas las monedas tienen dos decimales. Hoy el catálogo del servidor sólo
/// admite monedas que sí.
String _precio(int menores, String moneda) {
  final pesos = (menores ~/ 100).toString();
  final centavos = (menores % 100).toString().padLeft(2, '0');

  final conSeparadores = StringBuffer();

  for (var i = 0; i < pesos.length; i++) {
    if (i > 0 && (pesos.length - i) % 3 == 0) conSeparadores.write(',');
    conSeparadores.write(pesos[i]);
  }

  return '\$$conSeparadores.$centavos $moneda';
}

/// Las acciones del menú de una línea. **Enumeración cerrada**: el `switch` que las resuelve
/// no lleva comodín, así que añadir una **rompe la compilación** en vez de caer en silencio
/// en la rama de otra.
enum _AccionDeLinea {
  renombrar,
  retirar,
  reactivar,
  primeraCondicion,
  programarSiguiente,
  corregirProgramada,
  corregirVigente,
  cancelarProgramada,
  cerrarVigente,

  /// **Cambiar** el último día de cobro de una condición que ya lo tiene. 🚫 Es un acto
  /// distinto de [cerrarVigente] —otra ruta, otro código de error y otro motivo—, y no se
  /// colapsan: dos actos con el mismo nombre dejan la bitácora sin decir cuándo se decidió
  /// qué.
  cambiarTermino,
  sueldoDeReferencia,
}

/// Cuál de los tres actos sobre una condición se está haciendo. **No es un CRUD**: los tres
/// tienen reglas distintas y el servidor los separa en tres rutas.
enum _ActoDeCondicion { primera, programar, corregir }

/// El fallo de una mutación, para sacarlo de la rama `ok:` sin perderlo.
///
/// ⚠️ Existe porque **lanzar dentro de la rama `ok:` de un `Result` deja la pantalla
/// cargando para siempre** y sin error visible. Esto se lanza y se atrapa en un solo sitio.
class _Rechazo implements Exception {
  _Rechazo(this.fallo);

  final Failure fallo;
}

/// Una línea con su condición vigente, su programada y su menú.
class _TarjetaDeLinea extends StatelessWidget {
  const _TarjetaDeLinea({
    required this.linea,
    required this.condiciones,
    required this.modalidades,
    required this.puestos,
    required this.hoy,
    required this.abierta,
    required this.puedeAdministrar,
    required this.puedeTocarPrecios,
    required this.puedeVerSueldos,
    required this.ocupado,
    required this.alAbrirCerrar,
    required this.alActuar,
  });

  final LineaComercial linea;

  /// Nulo mientras no se ha leído el historial; vacío cuando la línea no cobra nada.
  /// **Son dos cosas distintas** y la tarjeta las dice distinto.
  final List<CondicionComercial>? condiciones;

  final List<ModalidadDeTurno> modalidades;
  final List<Puesto> puestos;
  final DiaDeNegocio Function() hoy;
  final bool abierta;
  final bool puedeAdministrar;
  final bool puedeTocarPrecios;
  final bool puedeVerSueldos;
  final bool ocupado;
  final VoidCallback alAbrirCerrar;
  final void Function(_AccionDeLinea) alActuar;

  CondicionComercial? _con(TemporalidadDeCondicion cual) {
    for (final c in condiciones ?? const <CondicionComercial>[]) {
      if (c.estado == cual) return c;
    }

    return null;
  }

  /// Lo que dice una línea **retirada**: hasta cuándo cobra, o que ya no cobra.
  ///
  /// 🚫 **SE LEE DE LA CONDICIÓN, NUNCA DEL ESTADO DE LA LÍNEA** (19-nov-2026). Desde que
  /// retirar cierra la condición, lo normal es que una retirada tenga una fecha de término
  /// —hoy o la que se eligió— y hasta ese día **se factura**.
  ///
  /// ⚠️ **Y HAY UN TERCER CASO QUE EXISTE EN DATOS REALES:** una línea retirada **antes** de
  /// esta decisión quedó con su condición **abierta**, así que sigue cobrando sin fecha. Eso
  /// se dice tal cual en lugar de enseñar «ya no cobra», que sería falso — y es lo que hay en
  /// el ensayo ahora mismo.
  String get _loQueDiceUnaRetirada {
    final vigente = _con(TemporalidadDeCondicion.vigente);

    if (vigente != null && vigente.termino == null) {
      return 'Retirada · SIGUE COBRANDO: su condición no tiene fecha de término';
    }

    if (vigente?.termino case final hasta?) {
      return 'Retirada · cobra hasta el ${_dia(hasta)}';
    }

    return 'Retirada · ya no cobra';
  }

  @override
  Widget build(BuildContext context) {
    final vigente = _con(TemporalidadDeCondicion.vigente);
    final programada = _con(TemporalidadDeCondicion.futura);
    final historicas = [
      for (final c in condiciones ?? const <CondicionComercial>[])
        if (c.estado == TemporalidadDeCondicion.historica) c,
    ];

    return RisegCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(linea.nombre, style: AppTypography.bodyStrong),
                    if (!linea.estaActiva) ...[
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        // 🚫 **LA TARJETA DICE HASTA CUÁNDO COBRA**, no «sigue cobrando»
                        // (19-nov-2026). Durante unas horas dijo «Retirada, pero SIGUE
                        // COBRANDO», que era cierto con la regla vieja y era justo la
                        // confusión: el dueño cambió el acto —retirar cierra la condición— y
                        // entonces lo único que hay que decir es la fecha.
                        //
                        // ⚠️ Se lee de la CONDICIÓN, no del estado de la línea: una retirada
                        // con término futuro todavía cobra, y una con término pasado ya no.
                        _loQueDiceUnaRetirada,
                        style: AppTypography.caption,
                      ),
                    ],
                  ],
                ),
              ),
              if (!linea.estaActiva)
                const Padding(
                  padding: EdgeInsets.only(right: AppSpacing.sm),
                  child: RisegStatusBadge(
                    label: 'Retirada',
                    tone: RisegStatusTone.neutral,
                  ),
                ),
              _Menu(
                linea: linea,
                tieneVigente: vigente != null,
                vigenteTieneTermino: vigente?.termino != null,
                tieneProgramada: programada != null,
                esLaUnica: (condiciones?.length ?? 0) == 1,
                puedeAdministrar: puedeAdministrar,
                puedeTocarPrecios: puedeTocarPrecios,
                puedeVerSueldos: puedeVerSueldos,
                ocupado: ocupado,
                alActuar: alActuar,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (condiciones == null)
            const Text('Leyendo sus condiciones…', style: AppTypography.caption)
          else if (condiciones!.isEmpty)
            _SinCondiciones(
              puedeTocarPrecios: puedeTocarPrecios && linea.estaActiva,
              alPonerPrecio: () => alActuar(_AccionDeLinea.primeraCondicion),
            )
          else ...[
            if (vigente != null)
              _ResumenDeCondicion(
                condicion: vigente,
                modalidades: modalidades,
                puestos: puestos,
                etiqueta: 'Cobra hoy',
                tono: RisegStatusTone.success,
              )
            else
              const Text(
                'No cobra hoy: su condición terminó o todavía no empieza.',
                style: AppTypography.caption,
              ),
            if (programada != null) ...[
              const SizedBox(height: AppSpacing.md),
              _ResumenDeCondicion(
                condicion: programada,
                modalidades: modalidades,
                puestos: puestos,
                etiqueta: 'Programada desde el ${_dia(programada.inicio)}',
                tono: RisegStatusTone.info,
              ),
            ],
            if (historicas.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              TextButton(
                onPressed: alAbrirCerrar,
                child: Text(
                  abierta
                      ? 'Ocultar el historial'
                      : 'Ver el historial (${historicas.length})',
                ),
              ),
              if (abierta)
                for (final h in historicas) ...[
                  const SizedBox(height: AppSpacing.sm),
                  _ResumenDeCondicion(
                    condicion: h,
                    modalidades: modalidades,
                    puestos: puestos,
                    etiqueta: 'Del ${_dia(h.inicio)} al ${_dia(h.termino)}',
                    tono: RisegStatusTone.neutral,
                  ),
                ],
            ],
          ],
        ],
      ),
    );
  }
}

class _SinCondiciones extends StatelessWidget {
  const _SinCondiciones({
    required this.puedeTocarPrecios,
    required this.alPonerPrecio,
  });

  final bool puedeTocarPrecios;
  final VoidCallback alPonerPrecio;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'Esta línea no cobra nada: no tiene condición.',
        style: AppTypography.body,
      ),
      if (puedeTocarPrecios) ...[
        const SizedBox(height: AppSpacing.sm),
        RisegButton(
          label: 'Poner su condición',
          size: RisegButtonSize.compact,
          onPressed: alPonerPrecio,
        ),
      ],
    ],
  );
}

/// El resumen de una condición: precio, plazas, importe, turno y horario.
class _ResumenDeCondicion extends StatelessWidget {
  const _ResumenDeCondicion({
    required this.condicion,
    required this.modalidades,
    required this.puestos,
    required this.etiqueta,
    required this.tono,
  });

  final CondicionComercial condicion;
  final List<ModalidadDeTurno> modalidades;
  final List<Puesto> puestos;
  final String etiqueta;
  final RisegStatusTone tono;

  String get _turno {
    final modalidad = modalidades.where((m) => m.id == condicion.modalidadId).firstOrNull;
    final periodo = condicion.periodoDelTurno;

    if (modalidad == null) return 'Sin modalidad de turno';
    if (periodo == null) return modalidad.nombre;

    return '${modalidad.nombre} · ${periodo.nombre}';
  }

  String get _puesto =>
      puestos.where((p) => p.id == condicion.puestoId).firstOrNull?.nombre ??
      'Puesto no encontrado';

  /// El horario DERIVADO de una modalidad que se captura por hora de cambio, o nulo.
  ///
  /// 🚫 **La tarjeta decía «Sin horario semanal fijo» en un 24×24**, y el dueño lo marcó en
  /// su prueba del 19-nov-2026: era falso. Un turno rotativo **sí** tiene horario —entra a
  /// una hora y dura lo que dura—; lo que no tiene es **rejilla semanal**, porque su ciclo
  /// no es periódico en siete días. El dato estaba guardado y la frase lo negaba.
  ///
  /// ⚠️ **Y el periodo cambia la ventana, no la hora:** con Nocturno la plaza entra cuando
  /// acaba la diurna, y la misma hora de cambio describe las dos — eso ya lo deriva
  /// `ModalidadDeTurno.horarioDerivado`, en un solo sitio.
  String? get _horarioDerivado {
    final modalidad = modalidades
        .where((m) => m.id == condicion.modalidadId)
        .firstOrNull;

    return modalidad?.horarioDerivado(
      condicion.horaDeCambioMinuto,
      nocturno: condicion.periodoDelTurno == PeriodoDeTurno.nocturno,
    );
  }

  @override
  Widget build(BuildContext context) {
    final iva = condicion.tratamientoDeIva;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: context.colors.surfaceSunken,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RisegStatusBadge(label: etiqueta, tone: tono),
          const SizedBox(height: AppSpacing.sm),
          // LA CUENTA SE LEE SEGÚN EL MODO (0066): con un precio por persona se enseña la
          // multiplicación —que es lo que alguien quiere comprobar— y con un total pactado
          // se enseña el total y la cantidad al lado, porque ahí la cantidad NO multiplica.
          Text(
            condicion.modo.esPorPersona
                ? '${_precio(condicion.precioUnitarioMenores ?? 0, condicion.moneda)} '
                      '× ${condicion.plazas} '
                      '= ${_precio(condicion.importeMenores, condicion.moneda)}'
                : '${_precio(condicion.importeMenores, condicion.moneda)} al mes'
                      // LA CANTIDAD SÓLO AQUÍ EN PERSONAL: en una línea de concepto la dice
                      // la línea de abajo —«Concepto · Cantidad: N»— y decirla dos veces
                      // obligaría a leer dos números para comprobar uno.
                      '${condicion.tipo.esPersonal ? ' · ${condicion.plazas} ${condicion.plazas == 1 ? 'elemento' : 'elementos'}' : ''}',
            style: AppTypography.bodyStrong,
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            // 🚫 **«TARIFA MENSUAL» Y NO «IMPORTE»** (dueño, 19-nov-2026). Es el precio
            // pactado del MES COMPLETO, y así se rotula para que nadie lo confunda con lo
            // que se va a facturar: el prorrateo por los días que se prestaron —
            // `precio × días × cantidad ÷ 30`— es de la AGENDA, en la etapa de cobranza,
            // que es la única que sabe qué días del periodo hubo servicio.
            //
            // ⚠️ Y SE DICE QUE ES SIN IVA: el servidor suma así en los indicadores, y una
            // pantalla que lo sumara con impuesto daría dos cifras distintas para la misma
            // pregunta.
            'Tarifa mensual, sin IVA · ${iva?.nombre ?? condicion.iva}',
            style: AppTypography.caption,
          ),
          const SizedBox(height: AppSpacing.sm),
          // 🚫 **UNA LÍNEA DE CONCEPTO NO TIENE PUESTO, NI TURNO, NI HORARIO**, y la tarjeta
          // los inventaba: decía «Puesto no encontrado · Sin modalidad de turno · Sin horario
          // semanal fijo», tres frases que suenan a datos que faltan sobre una línea que está
          // completa. Lo marcó el dueño el 19-nov-2026. Material, equipo o un concepto se
          // cobra sin nada de eso — así lo impone la 0066 con una FK compuesta— y lo que hay
          // que decir es qué es y cuánto.
          Text(
            condicion.tipo.esPersonal
                ? '$_puesto · $_turno'
                : 'Concepto · Cantidad: ${condicion.plazas}',
            style: AppTypography.body,
          ),
          if (condicion.descripcion case final d? when d.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xxs),
            Text(d, style: AppTypography.caption),
          ],
          // 🚫 **EL HORARIO ES SÓLO DE PERSONAL**: una línea de concepto no tiene turno del
          // que derivarlo ni rejilla que llenar, así que su tarjeta se acaba arriba.
          if (condicion.tipo.esPersonal) ...[
            const SizedBox(height: AppSpacing.sm),
            if (_horarioDerivado case final derivado?)
              // LA MODALIDAD SE CAPTURA POR HORA DE CAMBIO: el horario se dice derivado, y
              // no hay rejilla que enseñar porque el ciclo no cabe en una semana.
              Text(derivado, style: AppTypography.caption)
            else if (condicion.horarios.isEmpty)
              const Text(
                // Cero bloques es VÁLIDO y significa algo: un servicio por disponibilidad o
                // bolsa de horas no tiene rejilla. Decir «sin horario» sin más se leería
                // como un dato que falta.
                'Sin horario semanal fijo.',
                style: AppTypography.caption,
              )
            else
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xxs,
                children: [
                  for (final h in condicion.horarios)
                    Text(
                      '${h.nombreDelDia} ${h.enPantalla} (${h.duracionEnPantalla})',
                      style: AppTypography.caption,
                    ),
                ],
              ),
          ],
        ],
      ),
    );
  }
}

/// El menú de una línea. **Lo que no se puede hacer no se muestra**, y lo que no se puede
/// hacer *todavía* se muestra deshabilitado con su razón.
class _Menu extends StatelessWidget {
  const _Menu({
    required this.linea,
    required this.tieneVigente,
    required this.vigenteTieneTermino,
    required this.tieneProgramada,
    required this.esLaUnica,
    required this.puedeAdministrar,
    required this.puedeTocarPrecios,
    required this.puedeVerSueldos,
    required this.ocupado,
    required this.alActuar,
  });

  final LineaComercial linea;
  final bool tieneVigente;

  /// ¿La condición vigente **ya tiene** último día de cobro? Es lo que separa **poner** de
  /// **cambiar**, los dos actos que el dueño mandó no confundir el 19-nov-2026.
  final bool vigenteTieneTermino;

  final bool tieneProgramada;

  /// ¿La vigente es la ÚNICA condición de la línea? Es la frontera exacta de «corregir la
  /// vigente»: con historia detrás el servidor responde 409, así que la opción no se ofrece.
  final bool esLaUnica;

  final bool puedeAdministrar;
  final bool puedeTocarPrecios;
  final bool puedeVerSueldos;
  final bool ocupado;
  final void Function(_AccionDeLinea) alActuar;

  @override
  Widget build(BuildContext context) {
    // `onTap` nulo deshabilita la fila: mientras una mutación está en vuelo, el menú se ve
    // y no actúa. Dos clics seguidos son dos peticiones, y la segunda llegaría con la
    // versión vieja — el 409 saldría por un doble clic y no por un conflicto real.
    VoidCallback? pulsar(_AccionDeLinea accion) =>
        ocupado ? null : () => alActuar(accion);

    final opciones = <RisegMenuAction>[
      if (puedeTocarPrecios && linea.estaActiva) ...[
        if (!tieneVigente && !tieneProgramada)
          RisegMenuAction(
            label: 'Poner su condición',
            icon: Icons.price_change_outlined,
            onTap: pulsar(_AccionDeLinea.primeraCondicion),
          ),
        if (tieneVigente && !tieneProgramada)
          RisegMenuAction(
            label: 'Programar la siguiente',
            icon: Icons.event_outlined,
            onTap: pulsar(_AccionDeLinea.programarSiguiente),
          ),
        if (tieneVigente && esLaUnica)
          RisegMenuAction(
            label: 'Corregir la vigente',
            icon: Icons.edit_outlined,
            onTap: pulsar(_AccionDeLinea.corregirVigente),
          ),
        if (tieneProgramada) ...[
          RisegMenuAction(
            label: 'Corregir la programada',
            icon: Icons.edit_calendar_outlined,
            onTap: pulsar(_AccionDeLinea.corregirProgramada),
          ),
          RisegMenuAction(
            label: 'Cancelar la programada',
            icon: Icons.event_busy_outlined,
            destructive: true,
            onTap: pulsar(_AccionDeLinea.cancelarProgramada),
          ),
        ],
      ],
      // =====================================================================
      // 🔑 UNA SOLA ACCIÓN DE DINERO POR ESTADO — decisión del dueño, 19 y 24-nov-2026
      // =====================================================================
      //
      // De su prueba de cierre de C3. El menú ofrecía «Dejar de cobrar» Y «Retirar la línea»
      // en una línea activa —dos caminos para la misma intención, con resultados distintos—
      // y además ofrecía «Dejar de cobrar» otra vez en una condición que YA tenía fecha, que
      // el servidor aceptaba moviéndola en silencio. Su decisión no fue arreglar el diálogo:
      // fue dejar UNA acción por estado.
      //
      //   activa                         → «Dar de baja» (pide fecha y motivo, hace las dos)
      //   retirada SIN fecha de término  → «Poner último día de cobro»
      //   retirada CON fecha futura      → «Cambiar último día de cobro»
      //   retirada con la fecha pasada   → ninguna: ya no cobra y su condición es historia
      //
      // ⚠️ **EL ÚLTIMO CASO NO SE PROGRAMA, SE DERIVA:** una condición cuyo último día ya
      // pasó deja de ser la VIGENTE, así que `tieneVigente` es falso y las dos opciones
      // desaparecen solas. Un `if` sobre la fecha diría lo mismo y podría dejar de decirlo.
      if (!linea.estaActiva && puedeTocarPrecios && tieneVigente)
        if (!vigenteTieneTermino)
          RisegMenuAction(
            label: 'Poner último día de cobro',
            icon: Icons.event_busy_outlined,
            onTap: pulsar(_AccionDeLinea.cerrarVigente),
          )
        else
          RisegMenuAction(
            label: 'Cambiar último día de cobro',
            icon: Icons.edit_calendar_outlined,
            onTap: pulsar(_AccionDeLinea.cambiarTermino),
          ),
      if (puedeVerSueldos)
        RisegMenuAction(
          label: 'Sueldo de referencia',
          icon: Icons.badge_outlined,
          onTap: pulsar(_AccionDeLinea.sueldoDeReferencia),
        ),
      if (puedeAdministrar) ...[
        RisegMenuAction(
          label: 'Renombrar',
          icon: Icons.drive_file_rename_outline,
          onTap: pulsar(_AccionDeLinea.renombrar),
        ),
        // 🔑 «DAR DE BAJA» EXIGE LOS DOS PERMISOS, igual que la ruta: desde el 19-nov-2026
        // `/retire` cierra la condición vigente, o sea mueve dinero, y pide `manage` Y
        // `pricing.manage`. Ofrecerlo con uno solo sería un botón que contesta 403.
        if (linea.estaActiva && puedeTocarPrecios)
          RisegMenuAction(
            label: 'Dar de baja',
            icon: Icons.archive_outlined,
            destructive: true,
            onTap: pulsar(_AccionDeLinea.retirar),
          )
        else if (!linea.estaActiva)
          RisegMenuAction(
            label: 'Reactivar la línea',
            icon: Icons.unarchive_outlined,
            onTap: pulsar(_AccionDeLinea.reactivar),
          ),
      ],
    ];

    if (opciones.isEmpty) return const SizedBox.shrink();

    return RisegActionsMenu(actions: opciones);
  }
}
