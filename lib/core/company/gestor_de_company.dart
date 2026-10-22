import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier;

import '../error/failure.dart';
import '../error/result.dart';
import '../logging/app_logger.dart';
import 'almacen_company_recordada.dart';
import 'company_api.dart';
import 'company_remota.dart';

/// El motor de la Company activa: descubre, resuelve, cambia y revalida.
///
/// QUÉ RESUELVE, en orden y sin adivinar nada:
///
/// ```
/// GET /companies  →  0 ─────────────► SinAccesoACompanies
///                    1 ─────────────► cargar su /context
///                    N ─────────────► SeleccionDeCompanyRequerida
///                                      + la recordada, para MARCARLA
/// ```
///
/// ⚠️ **CON VARIAS SE PREGUNTA SIEMPRE** (21 de octubre de 2026). Hasta entonces, una
/// preferencia válida abría su empresa sin preguntar y la pantalla de selección sólo
/// se veía la primera vez. Se cambió por dos motivos que apuntan al mismo sitio:
/// entrar a trabajar en una empresa sin haberlo pedido es la misma clase de sorpresa
/// que hizo retirar la lista de Organización › Empresa, y la insignia «Última vez» no
/// se podía ver nunca —cuando había memoria no había pantalla—.
///
/// DE DÓNDE SALE EL `companyId`: exclusivamente del array de `/companies`. **Nunca**
/// de Drift, ni de la `Empresa` local, ni de un nombre, ni de un correo, ni de
/// configuración, ni de un literal. La preferencia guardada no es una fuente: hoy ni
/// siquiera es una pista para entrar — sólo dice cuál **marcar** en la pantalla, y
/// aun eso sólo si el servidor la confirma en la lista.
///
/// LA GENERACIÓN, igual que en el motor de sesión y por el mismo motivo. Cambiar de
/// A a B y enseguida a C deja la respuesta de B viajando; si llegara después y se
/// publicara, el usuario acabaría en la empresa que ya había descartado, y
/// persistirla la reabriría mañana. Cada operación anota su generación y, si al
/// volver no coincide, su resultado **se tira sin publicar y sin persistir**.
///
/// EMPRESA LOCAL Y COMPANY NO SE TOCAN. Este archivo no conoce `Empresa`,
/// `EmpresaRepository`, `Usuario` ni `SesionUsuario`: la `Empresa` legacy sigue
/// siendo el emisor de los documentos locales y la Company es el inquilino
/// operativo remoto. No hay vínculo, y no se infiere ninguno por nombre, RFC ni
/// logotipo.
class GestorDeCompany {
  GestorDeCompany({
    required CompanyApi api,
    required AlmacenCompanyRecordada almacen,
    required AppLogger logger,
  }) : _api = api,
       _almacen = almacen,
       _logger = logger;

  final CompanyApi _api;
  final AlmacenCompanyRecordada _almacen;
  final AppLogger _logger;

  final ValueNotifier<EstadoCompany> _estado = ValueNotifier<EstadoCompany>(
    const CompanySinResolver(),
  );

  /// La última lista que devolvió el servidor.
  ///
  /// Se conserva fuera del estado porque hace falta en situaciones en las que el
  /// estado no la lleva: si el contexto de la candidata falla por una razón
  /// comercial, la capa de interfaz necesitará ofrecer las otras empresas sin
  /// volver a descubrir.
  List<CompanyDisponible> _disponibles = const [];

  int _generacion = 0;

  Future<EstadoCompany>? _resolucionEnVuelo;
  ({String companyId, int generacion, Future<Result<CompanyContext>> futuro})?
  _contextoEnVuelo;

  bool _desechado = false;

  /// El estado, para observarlo. `ValueListenable` y no `Stream` porque tiene valor
  /// actual: quien empieza a escuchar sabe en qué situación está sin esperar el
  /// siguiente evento, y no hay ventana en la que un cambio se pierda entre leer y
  /// suscribirse.
  ValueListenable<EstadoCompany> get estadoObservable => _estado;

  EstadoCompany get estado => _estado.value;

  /// El identificador de la Company activa, o `null`.
  ///
  /// **Es la dependencia que todo provider remoto debe observar.** Cuando cambia,
  /// Riverpod reconstruye lo que lo observa y el estado de la empresa anterior deja
  /// de existir, sin registro manual de invalidaciones que se quede obsoleto en
  /// cuanto nazca un módulo nuevo.
  String? get companyIdActiva => switch (_estado.value) {
    CompanyActiva(:final contexto) => contexto.companyId,
    _ => null,
  };

  CompanyContext? get contextoActivo => switch (_estado.value) {
    CompanyActiva(:final contexto) => contexto,
    _ => null,
  };

  /// Las Companies que el servidor entregó la última vez, en su orden.
  List<CompanyDisponible> get disponibles => List.unmodifiable(_disponibles);

  // -------------------------------------------------------------------------
  // Resolución inicial
  // -------------------------------------------------------------------------

  /// Descubre las Companies accesibles y deja resuelto el estado.
  ///
  /// **Es «single-flight»**: dos resoluciones simultáneas harían dos descubrimientos
  /// y dos contextos para lo mismo. La segunda espera el mismo `Future`.
  Future<EstadoCompany> resolver() {
    final enVuelo = _resolucionEnVuelo;
    if (enVuelo != null) return enVuelo;

    final generacion = ++_generacion;
    final futuro = _resolver(generacion, permitirReintento: true);
    _resolucionEnVuelo = futuro;

    // La limpieza se registra ANTES de devolver, así corre antes de que despierte
    // quien espera: nadie observa una resolución ya completada.
    futuro.whenComplete(() {
      if (identical(_resolucionEnVuelo, futuro)) _resolucionEnVuelo = null;
    });

    return futuro;
  }

  Future<EstadoCompany> _resolver(
    int generacion, {
    required bool permitirReintento,
  }) async {
    final lista = await _api.listarAccesibles();

    switch (lista) {
      case Err<List<CompanyDisponible>>(:final failure):
        // No se pudo preguntar. NO se toca la preferencia y NO se dice que no hay
        // empresas: son dos cosas distintas y confundirlas expulsaría a alguien por
        // un bache de red.
        return _noSePudoResolver(generacion, failure);

      case Ok<List<CompanyDisponible>>(:final value):
        if (generacion != _generacion) return estado;

        _disponibles = value;

        if (value.isEmpty) {
          // El servidor respondió: esta Identity no tiene acceso a ninguna empresa.
          // Es un hecho, no un fallo. La preferencia se limpia porque ya no puede
          // corresponder a nada.
          await _borrarPreferencia();
          return _publicarSiVigente(
            generacion,
            () => const SinAccesoACompanies(),
          );
        }

        if (value.length > 1) {
          // SE PREGUNTA SIEMPRE CON VARIAS, aunque haya una recordada. La preferencia
          // **ordena y marca**, ya no decide: lo explica `SeleccionDeCompanyRequerida`.
          final recordada = await _recordadaEnLaLista(value);

          return _publicarSiVigente(
            generacion,
            () => SeleccionDeCompanyRequerida(value, recordada: recordada),
          );
        }

        final contexto = await _cargarContexto(value.single.companyId, generacion);

        switch (contexto) {
          case Ok<CompanyContext>():
            return estado;

          case Err<CompanyContext>(:final failure):
            if (CompanyApi.esEmpresaNoDisponible(failure)) {
              // AUTORITATIVO: la candidata dejó de estar disponible entre la lista y
              // el contexto. Se limpia y se vuelve a descubrir **una sola vez**: un
              // reintento resuelve la carrera real, y repetir sin límite construiría
              // un bucle contra un servidor que ya contestó.
              _logger.info(
                'La empresa candidata dejó de estar disponible; se vuelve a descubrir.',
              );

              await _borrarPreferencia();

              if (!permitirReintento || generacion != _generacion) {
                return _publicarSiVigente(
                  generacion,
                  () => CompanyNoResuelta(failure),
                );
              }

              return _resolver(generacion, permitirReintento: false);
            }

            // 402 y todo lo demás: se representa el fallo y **no se borra nada**. Una
            // suscripción restringida no es una revocación, y la empresa sigue en la
            // lista y en la preferencia.
            return _noSePudoResolver(generacion, failure);
        }
    }
  }

  /// La última empresa usada, **si y sólo si aparece en la lista** que el servidor
  /// acaba de entregar.
  ///
  /// Esa comprobación es la que hace innecesario indexar la preferencia por Identity:
  /// un identificador dejado por otra persona en el mismo equipo no está en la lista de
  /// ésta y se descarta solo.
  ///
  /// ⚠️ **YA NO DECIDE A DÓNDE SE ENTRA.** Antes esto se llamaba `_elegirCandidata` y
  /// su resultado abría la empresa sin preguntar; hoy sólo sirve para que la pantalla
  /// de selección la marque «Última vez» y la ponga primera. Con **una sola** empresa
  /// no se consulta nada: hay una, se abre.
  ///
  /// **Y la preferencia obsoleta se borra aquí**, que es lo que esto conserva de la
  /// versión anterior: una pista que el servidor no confirma no es una pista, y dejarla
  /// escrita la volvería a ofrecer mañana.
  Future<String?> _recordadaEnLaLista(
    List<CompanyDisponible> disponibles,
  ) async {
    final recordada = await _leerPreferencia();
    if (recordada == null) return null;

    for (final company in disponibles) {
      if (company.companyId == recordada) return recordada;
    }

    _logger.info(
      'La empresa recordada ya no está entre las accesibles; se descarta.',
    );
    await _borrarPreferencia();

    return null;
  }

  // -------------------------------------------------------------------------
  // Cambio de Company
  // -------------------------------------------------------------------------

  /// Cambia a otra Company. **Todo o nada.**
  ///
  /// El contexto se confirma ANTES de publicar: si falla, la Company anterior sigue
  /// activa y no se publica ningún estado intermedio que haga parecer que la nueva
  /// ya lo está. La preferencia se escribe **después** de confirmar, nunca antes.
  ///
  /// Dos llamadas concurrentes a la MISMA empresa comparten la petición: son la
  /// misma intención. Una llamada a otra empresa sube la generación, así que la
  /// anterior queda huérfana y su resultado se descartará — un `Future` viejo no se
  /// reutiliza nunca para una generación nueva.
  Future<Result<CompanyContext>> cambiarA(String companyId) {
    final enVuelo = _contextoEnVuelo;

    if (enVuelo != null &&
        enVuelo.companyId == companyId &&
        enVuelo.generacion == _generacion) {
      return enVuelo.futuro;
    }

    final generacion = ++_generacion;
    final futuro = _cargarContexto(companyId, generacion);

    _contextoEnVuelo = (
      companyId: companyId,
      generacion: generacion,
      futuro: futuro,
    );

    futuro.whenComplete(() {
      if (identical(_contextoEnVuelo?.futuro, futuro)) _contextoEnVuelo = null;
    });

    return futuro;
  }

  /// Carga el contexto y, si sigue siendo la intención vigente, lo publica y
  /// persiste la elección.
  Future<Result<CompanyContext>> _cargarContexto(
    String companyId,
    int generacion,
  ) async {
    final resultado = await _api.contexto(companyId);

    if (generacion != _generacion) {
      // Otra selección la sustituyó mientras esto viajaba. El contexto que acaba de
      // llegar es válido pero pertenece a una intención que ya no existe: no se
      // publica y no se persiste.
      _logger.warning(
        'Contexto de empresa descartado: otra selección lo sustituyó.',
      );

      return const Result.failure(
        CompanySeleccionSuperadaFailure(
          'La selección de empresa se sustituyó por otra más reciente.',
        ),
      );
    }

    switch (resultado) {
      case Err<CompanyContext>(:final failure):
        return Result.failure(failure);

      case Ok<CompanyContext>(:final value):
        _publicar(CompanyActiva(value));

        // SE PERSISTE DESPUÉS DE PUBLICAR, y el orden es deliberado: el estado
        // remoto confirmado es la autoridad y la preferencia sólo acelera el
        // siguiente arranque. Esperar al sistema de archivos para publicar una
        // empresa ya confirmada dejaría la interfaz colgada de una preferencia.
        //
        // Se vuelve a comprobar la generación porque publicar no tiene `await` pero
        // guardar sí: entre medias podría haber empezado otro cambio, y escribir
        // entonces dejaría recordada una empresa que ya no es la activa.
        if (generacion == _generacion) await _guardarPreferencia(companyId);

        return Result.ok(value);
    }
  }

  // -------------------------------------------------------------------------
  // Revalidación
  // -------------------------------------------------------------------------

  /// Vuelve a pedir el contexto de la Company activa.
  ///
  /// PARA QUÉ SIRVE: un administrador puede revocar el acceso en cualquier momento,
  /// y entonces `/context` responde 404 `empresa_no_disponible`. Ante ese 404
  /// —**autoritativo**— se descarta la empresa, se vuelve a descubrir y se resuelve
  /// otra vez con lo que quede: una, varias o ninguna.
  ///
  /// **Nunca cierra la sesión de Identity.** Perder el acceso a una empresa no es
  /// dejar de ser quien eres, y confundirlo obligaría a volver a escribir la
  /// contraseña por un cambio administrativo ajeno.
  ///
  /// EN IF-3 SÓLO REACCIONA A SUS PROPIAS LLAMADAS. Que un endpoint de negocio
  /// pueda comunicar «este acceso cambió» es una decisión de IF-4/IF-6: un 404 de
  /// negocio puede significar simplemente que ese empleado no existe, y engancharlo
  /// aquí cerraría empresas por errores ajenos.
  Future<EstadoCompany> revalidar() async {
    final activa = companyIdActiva;

    if (activa == null) return resolver();

    final generacion = ++_generacion;
    final resultado = await _cargarContexto(activa, generacion);

    switch (resultado) {
      case Ok<CompanyContext>():
        return estado;

      case Err<CompanyContext>(:final failure):
        if (CompanyApi.esEmpresaNoDisponible(failure)) {
          _logger.info(
            'El acceso a la empresa activa dejó de estar disponible; se resuelve de nuevo.',
          );

          await _borrarPreferencia();
          _publicar(const CompanySinResolver());

          return resolver();
        }

        // Sin red, 5xx o una restricción comercial: la empresa activa SIGUE activa.
        // Cambiar de empresa en silencio por un timeout sería peor que no revalidar.
        _logger.warning(
          'No se pudo revalidar la empresa activa; se conserva la actual.',
        );

        return estado;
    }
  }

  /// Anota que una empresa de la lista se renombró, **sin volver a resolver nada**.
  ///
  /// POR QUÉ HACE FALTA: la lista se obtuvo al entrar, y `revalidar()` sólo recarga el
  /// **contexto** de la activa, no la lista. Así que después de cambiar el nombre
  /// comercial en el expediente, el menú de la barra seguiría diciendo el nombre viejo
  /// hasta el siguiente inicio de sesión — y lo diría justo al lado de la barra, que sí
  /// se actualiza. Dos nombres distintos de la misma empresa en la misma pantalla.
  ///
  /// **Esto NO es resolver.** No pregunta al servidor, no elige empresa y no publica un
  /// contexto: actualiza lo que ya se había recibido, igual que una lista de sucursales
  /// se parchea al guardar una. Quien renombró acaba de recibir del servidor los valores
  /// que pasa aquí, así que no se está inventando nada.
  ///
  /// **No publica estado**, y es a propósito: quien renombra llama después a
  /// [revalidar], que publica el contexto nuevo y provoca el repintado. Publicar aquí
  /// también daría dos repintados por un solo cambio.
  void anotarRenombrado(
    String companyId, {
    required String nombre,
    String? razonSocial,
  }) {
    _disponibles = [
      for (final empresa in _disponibles)
        if (empresa.companyId == companyId)
          empresa.conNombre(nombre, razonSocial: razonSocial)
        else
          empresa,
    ];
  }

  /// Olvida la Company activa sin tocar la sesión: vuelve al estado inicial y borra
  /// la preferencia. Pensado para el relevo del portón, no para reaccionar a errores.
  Future<void> olvidarSeleccion() async {
    _generacion++;
    _contextoEnVuelo = null;
    _resolucionEnVuelo = null;
    _disponibles = const [];

    _publicar(const CompanySinResolver());

    await _borrarPreferencia();
  }

  /// Suelta el estado observable. **Idempotente**: desechar dos veces un
  /// `ChangeNotifier` lanza.
  void dispose() {
    if (_desechado) return;

    _desechado = true;
    _estado.dispose();
  }

  // -------------------------------------------------------------------------

  /// Publica [CompanyNoResuelta] **sólo si no hay ya una empresa activa**.
  ///
  /// Si A está activa y una resolución posterior no se puede completar —sin red, un
  /// 5xx, una restricción comercial—, **A sigue activa**: un bache de red no cambia de
  /// empresa ni degrada una sesión que funciona, y quien lo observe vería un estado
  /// peor que la realidad. Es la misma regla que el motor de sesión aplica a
  /// `SesionRemotaSinConfirmar`, y la razón de que exista un estado separado de
  /// [SinAccesoACompanies].
  ///
  /// **No aplica al 404 autoritativo**: ahí el servidor sí dijo que esa empresa dejó
  /// de estar disponible, y conservarla sería ignorar la única fuente que manda.
  EstadoCompany _noSePudoResolver(int generacion, Failure failure) {
    if (generacion != _generacion) return estado;

    if (companyIdActiva != null) {
      _logger.warning(
        'No se pudo resolver la empresa; se conserva la que estaba activa.',
      );

      return estado;
    }

    _publicar(CompanyNoResuelta(failure));

    return estado;
  }

  /// Publica sólo si esta operación sigue siendo la vigente, y devuelve el estado
  /// resultante. El estado se construye con una función para no fabricarlo cuando va
  /// a descartarse.
  EstadoCompany _publicarSiVigente(
    int generacion,
    EstadoCompany Function() construir,
  ) {
    if (generacion != _generacion) return estado;

    _publicar(construir());
    return estado;
  }

  /// Publica el estado, salvo si ya se desechó el gestor.
  ///
  /// Una petición puede estar viajando cuando el contenedor que aloja el gestor se
  /// destruye. Escribir en un `ValueNotifier` desechado lanza, y hacerlo desde una
  /// continuación asíncrona produce un error sin relación visible con su causa.
  void _publicar(EstadoCompany nuevo) {
    if (_desechado) return;

    _estado.value = nuevo;
  }

  /// Las tres operaciones de la preferencia van envueltas porque son accesos al
  /// almacén del sistema, y ninguna debe poder tumbar la aplicación.
  ///
  /// **No poder GUARDAR no invalida la empresa que acaba de confirmarse**: sigue
  /// activa en esta ejecución, y lo único que se pierde es abrirla directamente en
  /// el siguiente arranque —donde la resolución normal volverá a preguntar—. Revertir
  /// a la empresa anterior por esto produciría más inconsistencia que aceptarlo: el
  /// usuario pidió B, el servidor confirmó B, y devolverlo a A por un fallo de disco
  /// sería contradecir las dos autoridades reales.
  Future<void> _guardarPreferencia(String companyId) async {
    try {
      await _almacen.escribir(companyId);
    } catch (e) {
      _logger.error(
        'No se pudo recordar la empresa activa. Sigue activa en esta sesión, '
        'pero el próximo arranque volverá a resolverla.',
        e,
      );
    }
  }

  Future<String?> _leerPreferencia() async {
    try {
      return await _almacen.leer();
    } catch (e) {
      _logger.error('No se pudo leer la empresa recordada.', e);
      return null;
    }
  }

  Future<void> _borrarPreferencia() async {
    try {
      await _almacen.borrar();
    } catch (e) {
      _logger.error('No se pudo borrar la empresa recordada.', e);
    }
  }
}
