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
        else
          for (final linea in lineas) ...[
            _TarjetaDeLinea(
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
            ),
            const SizedBox(height: AppSpacing.md),
          ],
      ],
    );
  }

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

  Future<void> _retirar(LineaComercial linea) async {
    // ⚠️ EL AVISO DICE LO QUE RETIRAR **NO** HACE, y es lo importante: sin esta frase,
    // «retirar» se lee como «deja de cobrar» y alguien dejaría una línea facturando meses.
    final seguro = await RisegDialog.showConfirmation(
      context: context,
      title: 'Retirar «${linea.nombre}»',
      message:
          'Retirar impide ponerle condiciones nuevas, pero NO deja de cobrar: '
          'su condición vigente sigue abierta y sigue facturando.\n\n'
          'Para que deje de cobrar, cierra su condición vigente.',
      confirmLabel: 'Retirar',
      cancelLabel: 'Cancelar',
    );

    if (seguro != true || !mounted) return;

    await _conGuardado(() async {
      final r = await widget.repositorio.retirarLinea(
        empresaId: widget.empresaId,
        servicioId: widget.servicioId,
        lineaId: linea.id,
      );

      return r.when(ok: _reemplazarLinea, failure: (f) => throw _Rechazo(f));
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
          await _cargarCondiciones(linea.id);

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
          await _cargarCondiciones(linea.id);

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
          await _cargarCondiciones(linea.id);

          return 'La línea deja de cobrar después del '
              '${fechaDeNegocioCorta(cierre.termino)}.';
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
                      const Text(
                        'Retirada: no admite condiciones nuevas.',
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
                : '${_precio(condicion.importeMenores, condicion.moneda)} al mes '
                      '· ${condicion.plazas} '
                      '${condicion.plazas == 1 ? 'elemento' : 'elementos'}',
            style: AppTypography.bodyStrong,
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            // ⚠️ EL IMPORTE SE DICE SIN IVA, y se dice que es sin IVA: el servidor suma así
            // en los indicadores, y una pantalla que lo sumara con impuesto daría dos
            // cifras distintas para la misma pregunta.
            'Importe sin IVA · ${iva?.nombre ?? condicion.iva}',
            style: AppTypography.caption,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text('$_puesto · $_turno', style: AppTypography.body),
          if (condicion.descripcion case final d? when d.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xxs),
            Text(d, style: AppTypography.caption),
          ],
          const SizedBox(height: AppSpacing.sm),
          if (condicion.horarios.isEmpty)
            const Text(
              // Cero bloques es VÁLIDO y significa algo: un servicio por disponibilidad o
              // bolsa de horas no tiene rejilla. Decir «sin horario» sin más se leería como
              // un dato que falta.
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
        if (tieneVigente)
          RisegMenuAction(
            label: 'Dejar de cobrar (cerrar)',
            icon: Icons.block_outlined,
            onTap: pulsar(_AccionDeLinea.cerrarVigente),
          ),
      ],
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
        if (linea.estaActiva)
          RisegMenuAction(
            label: 'Retirar la línea',
            icon: Icons.archive_outlined,
            onTap: pulsar(_AccionDeLinea.retirar),
          )
        else
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
