import 'package:flutter_test/flutter_test.dart';
import 'package:riseg_one/app/shell/apartados_web.dart' as apartados;
import 'package:riseg_one/features/usuarios/web/modelos/evento_de_auditoria.dart';
import 'package:riseg_one/features/usuarios/web/presentation/auditoria_legible.dart';

/// La auditoría dicha en español.
///
/// ## La prueba que de verdad protege esto es la ÚLTIMA
///
/// «El vocabulario cubre todas las entidades auditadas» recorre el inventario de
/// claves que el servidor escribe hoy y exige que **cada una tenga etiqueta propia**.
/// Si alguien añade un campo a un registro y no lo traduce, esa prueba falla con el
/// nombre del campo. Las demás comprueban que la traducción dice lo correcto; ésa
/// comprueba que no falta ninguna.
///
/// Su gemela vive en el backend —`AuditPayloadVocabularyTests`— y mide las claves
/// **reales** ejecutando las operaciones contra una base de verdad. Las dos juntas
/// cierran el círculo: el backend descubre una clave nueva, y aquí se exige su
/// etiqueta.
void main() {
  // Sin nombres ni catálogo: así se ve lo que la clase puede decir sola.
  const pelado = AuditoriaLegible(nombrePorIdentidad: {}, nombrePorPermiso: {});

  const conDatos = AuditoriaLegible(
    nombrePorIdentidad: {'01a15071-0001-7000-8000-000000000001': 'Juan Pérez'},
    nombrePorPermiso: {'personal.sueldo.ver': 'Ver sueldo'},
  );

  EventoDeAuditoria evento({
    required String entidad,
    required String accion,
    String? antes,
    String? despues,
    String? motivo,
    String tipoDeActor = 'identity',
    String? actor = '01a15071-0001-7000-8000-000000000001',
  }) => EventoDeAuditoria(
    id: 'ev-1',
    tipoDeActor: tipoDeActor,
    identidadDelActor: actor,
    tipoDeEntidad: entidad,
    entidadId: 'ent-1',
    accion: accion,
    antes: antes,
    despues: despues,
    motivo: motivo,
    cuando: DateTime.utc(2026, 10, 18, 19, 45),
  );

  group('El título nombra el objeto', () {
    test('«Creó el área Monitoreo», no «Creó · un área»', () {
      final e = evento(
        entidad: 'area',
        accion: 'created',
        despues: '{"code":"MON","name":"Monitoreo","status":"activa"}',
      );

      expect(pelado.titulo(e), 'Creó el área Monitoreo');
    });

    test('con el género correcto de cada objeto', () {
      // «el sucursal» es justo el detalle que hace que una pantalla parezca
      // traducida a máquina.
      final sucursal = evento(
        entidad: 'branch',
        accion: 'created',
        despues: '{"name":"Centro"}',
      );
      final puesto = evento(
        entidad: 'position',
        accion: 'updated',
        antes: '{"name":"Supervisor"}',
        despues: '{"name":"Supervisor general"}',
      );

      expect(pelado.titulo(sucursal), 'Creó la sucursal Centro');
      expect(pelado.titulo(puesto), 'Cambió el puesto Supervisor general');
    });

    test('un cambio de estado se dice «Desactivó», no «Cambió el estado»', () {
      // Quien lo lee quiere saber qué pasó, no qué columna se tocó.
      final apagada = evento(
        entidad: 'area',
        accion: 'status_changed',
        antes: '{"status":"activa"}',
        despues: '{"name":"Monitoreo","status":"inactiva"}',
      );

      expect(pelado.titulo(apagada), 'Desactivó el área Monitoreo');

      final encendida = evento(
        entidad: 'area',
        accion: 'status_changed',
        antes: '{"status":"inactiva"}',
        despues: '{"name":"Monitoreo","status":"activa"}',
      );

      expect(pelado.titulo(encendida), 'Activó el área Monitoreo');
    });

    test('un acceso se cuenta en PERSONAS y usa su nombre', () {
      final dado = evento(
        entidad: 'company_access',
        accion: 'granted',
        despues:
            '{"role":"user","subjectIdentityId":"01a15071-0001-7000-8000-000000000001"}',
      );

      expect(conDatos.titulo(dado), 'Dio acceso a Juan Pérez');

      final quitado = evento(
        entidad: 'company_access',
        accion: 'revoked',
        antes:
            '{"role":"user","status":"activa","subjectIdentityId":"01a15071-0001-7000-8000-000000000001"}',
        despues: '{"status":"revocada"}',
      );

      expect(conDatos.titulo(quitado), 'Quitó el acceso a Juan Pérez');
    });

    test('un permiso se nombra con el nombre del CATÁLOGO', () {
      final e = evento(
        entidad: 'company_access_permission',
        accion: 'granted',
        despues: '{"permission":"personal.sueldo.ver"}',
      );

      expect(conDatos.titulo(e), 'Concedió el permiso Ver sueldo');
    });

    test('un módulo se nombra con lo que manda el catálogo', () {
      // ⚠️ ANTES ESTA PRUEBA USABA `pelado`, porque el nombre salía de un mapa de
      // siete etiquetas escrito en la web. Desde el 19 de octubre de 2026 lo manda el
      // servidor, así que un traductor SIN catálogo ya no puede decir «Nómina» — y no
      // debe: inventarlo es lo que había que quitar.
      final e = evento(
        entidad: 'company_module',
        accion: 'enabled',
        despues: '{"module":"payroll","enabled":true}',
      );

      const conCatalogo = AuditoriaLegible(
        nombrePorIdentidad: {},
        nombrePorPermiso: {},
        nombrePorModulo: {'payroll': 'Nómina'},
      );

      expect(conCatalogo.titulo(e), 'Activó el módulo Nómina');

      // Y sin catálogo, el código humanizado: feo y honesto. El grupo del final
      // comprueba que en ese caso NO se cuela el nombre del apartado.
      expect(pelado.titulo(e), 'Activó el módulo Payroll');
    });

    test('sin nombre en el registro se dice «un área», que es la verdad', () {
      final e = evento(entidad: 'area', accion: 'deleted');

      expect(pelado.titulo(e), 'Borró un área');
    });

    test('una entidad SIN frase propia se dice legible, NUNCA con su código', () {
      // Es fea a propósito: es la señal visible de que falta traducirla. Lo que no
      // puede pasar es que salga `subscription_extra` crudo ni que se esconda la fila.
      final e = evento(
        entidad: 'subscription_extra',
        accion: 'created',
        despues: '{"name":"Empleados adicionales"}',
      );

      final titulo = pelado.titulo(e);

      expect(titulo, contains('Subscription extra'));
      expect(titulo, isNot(contains('subscription_extra')));
    });

    test('una ACCIÓN desconocida se dice legible, nunca cruda', () {
      final e = evento(entidad: 'area', accion: 'super_frobnicated');

      expect(pelado.titulo(e), isNot(contains('super_frobnicated')));
      expect(pelado.titulo(e), contains('Super frobnicated'));
    });
  });

  group('Quién lo hizo', () {
    test('con nombre cuando se conoce', () {
      expect(
        conDatos.actor(evento(entidad: 'area', accion: 'created')),
        'Juan Pérez',
      );
    });

    test('por su identidad abreviada cuando ya no tiene acceso', () {
      // NO se oculta la fila: una auditoría que esconde lo que no sabe nombrar deja
      // de servir justo para lo que existe.
      final texto = pelado.actor(evento(entidad: 'area', accion: 'created'));

      expect(texto, contains('01a15071'));
      expect(texto, contains('identidad'));
    });

    test('un hecho sin persona detrás lo dice con palabras', () {
      final e = evento(
        entidad: 'area',
        accion: 'created',
        tipoDeActor: 'system',
        actor: null,
      );

      expect(pelado.actor(e), 'El sistema');
    });
  });

  group('El detalle', () {
    test('sólo los campos que CAMBIARON', () {
      // El código sigue igual y no aparece: repetir los que no se movieron esconde
      // el único que sí.
      final e = evento(
        entidad: 'area',
        accion: 'updated',
        antes: '{"code":"MON","name":"Monitoreo","status":"activa"}',
        despues: '{"code":"MON","name":"Monitoreo central","status":"activa"}',
      );

      final campos = pelado.campos(e);

      expect(campos.map((c) => c.etiqueta), ['Nombre']);
      expect(campos.single.esCambio, isTrue);
      expect(campos.single.antes!.texto, 'Monitoreo');
      expect(campos.single.despues!.texto, 'Monitoreo central');
    });

    test('un alta no tiene «antes», así que lista lo que trae', () {
      final e = evento(
        entidad: 'area',
        accion: 'created',
        despues: '{"code":"MON","name":"Monitoreo","status":"activa"}',
      );

      final campos = pelado.campos(e);

      expect(campos.map((c) => c.etiqueta), ['Código', 'Nombre', 'Estado']);
      expect(campos.every((c) => !c.esCambio), isTrue);
    });

    test('los campos TÉCNICOS no se muestran', () {
      final e = evento(
        entidad: 'company',
        accion: 'created',
        despues:
            '{"name":"Demo","firstMaestroIdentityId":"01a15071-0001-7000-8000-000000000001","protectedPermissionsGranted":6}',
      );

      final etiquetas = pelado.campos(e).map((c) => c.etiqueta).toList();

      expect(etiquetas, contains('Nombre'));
      expect(etiquetas, contains('Permisos protegidos concedidos'));
      // El identificador del Maestro no le dice nada a nadie y empuja fuera lo que sí.
      expect(etiquetas.join(' '), isNot(contains('Identity')));
      expect(etiquetas.join(' '), isNot(contains('identity')));
    });

    test('«area_code» NO es un identificador y sí se muestra', () {
      // Es el código que el cliente escribió y reconoce. Un filtro que se comiera
      // todo lo que acaba en «code» perdería justamente eso.
      final e = evento(
        entidad: 'position',
        accion: 'created',
        despues: '{"code":"SUP","name":"Supervisor","area_code":"MON"}',
      );

      final campos = pelado.campos(e);

      expect(campos.map((c) => c.etiqueta), contains('Área'));
      expect(
        campos.firstWhere((c) => c.etiqueta == 'Área').despues!.texto,
        'MON',
      );
    });

    test('lo que ya está en el TÍTULO no se repite abajo', () {
      final e = evento(
        entidad: 'company_access_permission',
        accion: 'granted',
        despues: '{"permission":"personal.sueldo.ver"}',
      );

      expect(conDatos.titulo(e), contains('Ver sueldo'));
      expect(conDatos.campos(e), isEmpty);
    });

    test('el MOTIVO va primero, porque lo escribió una persona', () {
      final e = evento(
        entidad: 'area',
        accion: 'updated',
        antes: '{"status":"activa"}',
        despues: '{"status":"inactiva"}',
        motivo: 'cerró la sede',
      );

      final campos = pelado.campos(e);

      expect(campos.first.etiqueta, 'Motivo');
      expect(campos.first.despues!.texto, 'cerró la sede');
    });
  });

  group('Los valores se dicen en español', () {
    test('true y false son Sí y No', () {
      final e = evento(
        entidad: 'company_module',
        accion: 'enabled',
        antes: '{"enabled":false}',
        despues: '{"enabled":true}',
      );

      final campo = pelado.campos(e).single;

      expect(campo.etiqueta, 'Habilitado');
      expect(campo.antes!.texto, 'No');
      expect(campo.despues!.texto, 'Sí');
    });

    test('un estado es un chip, y conserva su código para el color', () {
      final e = evento(
        entidad: 'area',
        accion: 'created',
        despues: '{"status":"activa"}',
      );

      final valor = pelado.campos(e).single.despues!;

      expect(valor.forma, FormaDeValor.estado);
      expect(valor.texto, 'Activa');
      // El color y el ícono se eligen por el código, no por la traducción.
      expect(valor.estadoCrudo, 'activa');
    });

    test('un rol se dice Maestro o Usuario', () {
      final e = evento(
        entidad: 'company_access',
        accion: 'role_changed',
        antes: '{"role":"user"}',
        despues: '{"role":"maestro"}',
      );

      final campo = pelado.campos(e).single;

      expect(campo.antes!.texto, 'Usuario');
      expect(campo.despues!.texto, 'Maestro');
    });

    test('una fecha se dice dd/mmm/aaaa, con el mes en letras', () {
      // `18/10/2026` y `10/18/2026` se confunden; `18/oct/2026` no se confunde con
      // nada. Aplica a los campos de fecha de los módulos que vengan después.
      final e = evento(
        entidad: 'employment_period',
        accion: 'created',
        despues: '{"started_on":"2026-10-18"}',
      );

      final valor = pelado.campos(e).single.despues!;

      expect(valor.forma, FormaDeValor.fecha);
      expect(valor.texto, '18/oct/2026');
    });

    test('un campo de fecha con un valor raro NO se interpreta', () {
      // Se detecta por la clave Y por la forma del valor. Sólo por la clave, esto
      // habría reventado al convertirlo.
      final e = evento(
        entidad: 'employment_period',
        accion: 'created',
        despues: '{"started_on":"pendiente"}',
      );

      final valor = pelado.campos(e).single.despues!;

      expect(valor.forma, FormaDeValor.texto);
      expect(valor.texto, 'pendiente');
    });

    test('una lista se cuenta, no se vuelca', () {
      final e = evento(
        entidad: 'service',
        accion: 'created',
        despues: '{"schedule_blocks":[1,2,3]}',
      );

      expect(pelado.campos(e).single.despues!.texto, '3 elementos');
    });
  });

  group('NUNCA sale JSON', () {
    test('un detalle ilegible se dice con palabras, y no se vuelca', () {
      const basura = 'esto no es json {{{';

      final e = evento(entidad: 'area', accion: 'created', despues: basura);

      final aviso = pelado.avisoDeFormato(e);

      expect(aviso, isNotNull);
      expect(aviso, isNot(contains(basura)));
      expect(aviso, contains('formato'));

      // Y no inventa campos a partir de lo que no entendió.
      expect(pelado.campos(e), isEmpty);
    });

    test('un detalle normal no levanta ningún aviso', () {
      final e = evento(
        entidad: 'area',
        accion: 'created',
        despues: '{"name":"Monitoreo"}',
      );

      expect(pelado.avisoDeFormato(e), isNull);
    });

    test('ninguna etiqueta ni ningún valor sale con llaves o corchetes', () {
      // Una guarda de forma: si algún camino volcara el mapa, esto lo caza.
      final e = evento(
        entidad: 'area',
        accion: 'created',
        despues: '{"code":"MON","name":"Monitoreo","status":"activa"}',
      );

      final todo = [
        pelado.titulo(e),
        for (final c in pelado.campos(e))
          '${c.etiqueta} ${c.antes?.texto ?? ''} ${c.despues?.texto ?? ''}',
      ].join(' ');

      expect(todo, isNot(contains('{')));
      expect(todo, isNot(contains('"')));
    });
  });

  // =========================================================================
  // La prueba que protege todo lo anterior
  // =========================================================================

  group('El vocabulario cubre todas las entidades auditadas', () {
    /// Las claves que el servidor escribe **hoy** en los registros de empresa, por
    /// entidad.
    ///
    /// SALE DE LEER EL BACKEND, no de suponer: `TenancyRepository`,
    /// `AuthorizationRepository` y `StructureRepository` son los únicos que auditan lo
    /// que esta etapa produce. Su gemela —`AuditPayloadVocabularyTests`— mide las
    /// claves reales ejecutando las operaciones, así que si alguien añade una, allí
    /// falla con su nombre y aquí se le exige la etiqueta.
    ///
    /// **Se amplía cuando un módulo se muda**, igual que `modulos_mudados.dart`: no se
    /// inventa el texto oficial de un campo cuya pantalla no existe.
    const inventario = <String, List<String>>{
      // ⚠️ LAS SIETE DEL EXPEDIENTE SE COLARON A PANTALLA, y «Contact summary» salió
      // en inglés humanizado en una pantalla en español.
      //
      // Este par de pruebas existe justamente para impedirlo y NO LO CAZÓ. La razón
      // estaba en el backend: su escenario no ejercitaba las rutas del expediente que
      // añadió el esquema 50, así que estas claves nunca se escribían durante la
      // prueba y nunca se medían — y el círculo sólo se cierra para lo que el
      // escenario toca. Ya está corregido allí: el escenario guarda los dos
      // expedientes, y una mutación lo confirma diciendo
      // «company.contact_summary».
      'company': [
        'name',
        'firstMaestroIdentityId',
        'protectedPermissionsGranted',
        'legal_name',
        'tax_id',
        'legal_rep',
        'slogan',
        'fiscal_regime_code',
        'address_summary',
        'contact_summary',
      ],
      'company_access': ['role', 'subjectIdentityId', 'status'],
      'company_access_permission': ['permission'],
      'company_module': ['module', 'enabled'],
      'area': ['code', 'name', 'status'],
      'position': ['code', 'name', 'kind', 'area_code', 'status'],
      // `operational_status` LO ESTRENÓ M3, con cerrar y reabrir. Y el borrado físico
      // escribe las mismas claves en `before`, así que no añade ninguna nueva.
      'branch': [
        'code',
        'name',
        'status',
        'operational_status',
        // ESQUEMA 50: el expediente de la sucursal. El domicilio va como UNA LÍNEA
        // —la auditoría «guarda qué cambió, no documentos»— y el horario como una
        // CUENTA, porque «ningún evento lleva una colección».
        'address_summary',
        'schedule_blocks',
      ],
      'branch_type': ['code', 'name', 'status', 'recommended', 'created_count'],
    };

    /// Los verbos que el servidor escribe **hoy** para estas entidades.
    ///
    /// ⚠️ **ESTA LISTA NO EXISTÍA, y por eso se colaron dos.** Había prueba para cada
    /// CLAVE y ninguna para cada VERBO, así que `closed` y `reopened` —los de M3—
    /// llegaron a pantalla como «Closed» y «Reopened». Un verbo sin traducir no rompe
    /// nada visible: sale humanizado, parece intencional y nadie lo reporta.
    const verbos = <String>[
      'created',
      'updated',
      'status_changed',
      'granted',
      'revoked',
      'role_changed',
      'enabled',
      'disabled',
      // M3: la eliminación física y las dos transiciones de la sucursal.
      'deleted',
      'closed',
      'reopened',
    ];

    test('cada verbo se dice en español, o se dice cuál falta', () {
      final sinTraducir = verbos.where((v) => !AuditoriaLegible.tieneVerbo(v)).toList();

      expect(
        sinTraducir,
        isEmpty,
        reason:
            'Estos verbos saldrían en inglés humanizado en vez de en español. '
            'Añádelos a _verbos, en auditoria_legible.dart: ${sinTraducir.join(', ')}',
      );
    });

    test('cerrar y reabrir una sucursal se dicen sin confundirse con desactivar', () {
      // LAS DOS PREGUNTAS NO SE COLAPSAN, y el texto es donde se nota: si `closed`
      // dijera «Desactivó», la traza contaría que la sucursal se dio de baja cuando
      // sólo se cerró por obra, y quien audite un mes después no podría distinguirlo.
      final cerro = pelado.titulo(
        evento(
          entidad: 'branch',
          accion: 'closed',
          antes: '{"operational_status":"operando"}',
          despues: '{"operational_status":"cerrada_temporalmente"}',
        ),
      );

      expect(cerro, contains('Cerró temporalmente'));
      expect(cerro, isNot(contains('Desactivó')));

      final reabrio = pelado.titulo(
        evento(
          entidad: 'branch',
          accion: 'reopened',
          antes: '{"operational_status":"cerrada_temporalmente"}',
          despues: '{"operational_status":"operando"}',
        ),
      );

      expect(reabrio, contains('Reabrió'));
    });

    test('el estado operativo se dice en español y NO como chip de estado', () {
      // Un chip verde o gris lo haría parecer lo mismo que `status`, que es justo la
      // confusión que las dos columnas existen para evitar.
      final campos = pelado.campos(
        evento(
          entidad: 'branch',
          accion: 'closed',
          antes: '{"operational_status":"operando"}',
          despues: '{"operational_status":"cerrada_temporalmente"}',
        ),
      );

      final renglon = campos.single;

      expect(renglon.etiqueta, 'Estado operativo');
      expect(renglon.antes?.texto, 'Operando');
      expect(renglon.despues?.texto, 'Cerrada temporalmente');
    });

    test('el borrado físico dice qué desapareció y con qué motivo', () {
      // EL EVENTO ES LO ÚNICO QUE QUEDA DE LA FILA, así que tiene que leerse solo.
      const motivo = 'Se capturó por error, nunca se usó.';

      final e = evento(
        entidad: 'area',
        accion: 'deleted',
        antes: '{"code":"RH","name":"Recursos Humanos","status":"activa"}',
        motivo: motivo,
      );

      expect(pelado.titulo(e), contains('Borró'));
      expect(pelado.titulo(e), contains('Recursos Humanos'));

      // EL MOTIVO VA PRIMERO, porque lo escribió una persona.
      final campos = pelado.campos(e);
      expect(campos.first.etiqueta, 'Motivo');
      expect(campos.first.despues?.texto, motivo);
    });

    test('cada clave tiene etiqueta propia, o se dice cuál falta', () {
      final sinEtiqueta = <String>[];

      for (final entrada in inventario.entries) {
        for (final clave in entrada.value) {
          // Los técnicos no se muestran, así que no necesitan etiqueta.
          if (clave == 'id' ||
              clave.endsWith('_id') ||
              clave.endsWith('Id') ||
              clave.endsWith('IdentityId')) {
            continue;
          }

          if (!AuditoriaLegible.tieneEtiqueta(clave)) {
            sinEtiqueta.add('${entrada.key}.$clave');
          }
        }
      }

      expect(
        sinEtiqueta,
        isEmpty,
        reason:
            'Estos campos de la auditoría saldrían con un nombre inventado a partir '
            'de su clave en vez de en español. Añádeles su etiqueta en '
            '_etiquetas, en auditoria_legible.dart: ${sinEtiqueta.join(', ')}',
      );
    });

    test('cada entidad SE NOMBRA cuando el registro trae nombre', () {
      // ⚠️ LA PRUEBA QUE FALTABA, y se vio en pantalla: al desactivar una sucursal la
      // auditoría decía «Desactivó UNA sucursal». No era que a `branch` le faltara su
      // frase —la tenía— sino que el registro de un cambio de estado sólo llevaba
      // `status`, así que no había con qué nombrar la fila.
      //
      // El arreglo está en el servidor: `AuditarCambioAsync` manda el nombre SIEMPRE,
      // porque ahí no es un cambio sino la identificación del sujeto. Esta prueba fija
      // la mitad de acá: que con el nombre delante, NINGUNA entidad se quede en «un» o
      // «una».
      final sinNombrar = <String>[];

      for (final entidad in inventario.keys) {
        // Un registro realista de cambio de estado, con el nombre en los dos lados
        // como lo escribe el servidor.
        final e = evento(
          entidad: entidad,
          accion: 'status_changed',
          antes: '{"name":"Algo","status":"activa"}',
          despues: '{"name":"Algo","status":"inactiva"}',
        );

        if (!pelado.titulo(e).contains('Algo')) sinNombrar.add(entidad);
      }

      // `company_access`, `company_access_permission` y `company_module` se nombran por
      // OTRA clave —la identidad, el permiso, el módulo—, así que no usan `name` y es
      // correcto que no aparezcan aquí. Se nombran igual, con su propio dato.
      const porOtraClave = {
        'company_access',
        'company_access_permission',
        'company_module',
      };

      expect(
        sinNombrar.where((x) => !porOtraClave.contains(x)),
        isEmpty,
        reason:
            'Estas entidades saldrían como «un/una …» aunque el registro traiga el '
            'nombre: ${sinNombrar.join(', ')}',
      );
    });

    test('las tres que se nombran por otra clave TAMBIÉN se nombran', () {
      // No basta con exceptuarlas arriba: hay que comprobar que sí dicen de qué
      // hablan, cada una con su dato.
      final acceso = conDatos.titulo(
        evento(
          entidad: 'company_access',
          accion: 'status_changed',
          despues:
              '{"subjectIdentityId":"01a15071-0001-7000-8000-000000000001",'
              '"status":"inactiva"}',
        ),
      );

      expect(acceso, contains('Juan Pérez'));

      final permiso = conDatos.titulo(
        evento(
          entidad: 'company_access_permission',
          accion: 'granted',
          despues: '{"permission":"personal.sueldo.ver"}',
        ),
      );

      expect(permiso, contains('Ver sueldo'));

      final modulo = pelado.titulo(
        evento(
          entidad: 'company_module',
          accion: 'enabled',
          despues: '{"module":"personal","enabled":true}',
        ),
      );

      expect(modulo, contains('Personal'));
    });

    test('el nombre va al TÍTULO y no se repite en el detalle', () {
      // La otra mitad del arreglo del servidor: ahora el nombre viaja en los dos lados
      // de TODO cambio de estado. Si el detalle lo listara, cada desactivación tendría
      // un renglón «Nombre: Algo → Algo» que no dice nada.
      //
      // No hace falta tocar la pantalla para eso —«sólo lo que cambió» ya lo filtra—,
      // y esta prueba es la que lo garantiza al añadir el nombre al registro.
      final e = evento(
        entidad: 'branch',
        accion: 'status_changed',
        antes: '{"name":"AAA","status":"activa"}',
        despues: '{"name":"AAA","status":"inactiva"}',
      );

      expect(pelado.titulo(e), contains('AAA'));

      final etiquetas = pelado.campos(e).map((c) => c.etiqueta).toList();

      expect(etiquetas, ['Estado']);
      expect(etiquetas, isNot(contains('Nombre')));
    });

    test('cada entidad del inventario tiene su frase, con artículo', () {
      // Sin esto, una entidad auditada saldría como «el registro de tipo Company
      // access» — legible, pero no es español de verdad.
      for (final entidad in inventario.keys) {
        final e = evento(
          entidad: entidad,
          accion: 'created',
          despues: '{"name":"Algo"}',
        );

        final titulo = pelado.titulo(e);

        expect(
          titulo,
          isNot(contains('registro de tipo')),
          reason:
              'La entidad «$entidad» no tiene frase propia en _ObjetoDeAuditoria ni '
              'en _fraseEspecifica, así que sale con el respaldo genérico.',
        );
      }
    });

    test('y ninguna clave del inventario se muestra en crudo', () {
      // La guarda final: aunque faltara una etiqueta, lo que se pinta nunca es la
      // clave tal cual.
      for (final entrada in inventario.entries) {
        for (final clave in entrada.value) {
          expect(
            AuditoriaLegible.etiquetaDe(clave),
            isNot(equals(clave)),
            reason: 'La clave «$clave» se mostraría cruda.',
          );
        }
      }
    });
  });

  // =========================================================================
  // EL NOMBRE DEL MÓDULO, que lo manda el servidor y NO es el del apartado
  // =========================================================================

  group('El nombre del MÓDULO no es el del apartado', () {
    // ⚠️ ESTE GRUPO SE MUDÓ DESDE `apartados_web_test.dart` el 19 de octubre de 2026,
    // cuando el catálogo del servidor empezó a mandar `moduleName` y las siete
    // etiquetas que la web tenía a mano se retiraron.
    //
    // POR QUÉ VIVE AQUÍ AHORA: la propiedad a vigilar cruza la frontera —el nombre
    // del módulo lo manda el SERVIDOR, el del apartado lo decide la WEB—, y este es
    // el único sitio donde las dos se encuentran, porque es donde se inyecta.
    //
    // Y POR QUÉ IMPORTA: al unificar los nombres en un solo archivo, la auditoría
    // empezó a decir «Activó el módulo Personal» cuando el hecho registrado era
    // `module: payroll`. Eso es FALSO: lo que se encendió fue Nómina.

    /// Los nombres tal como los manda `app.platform_module`. Es un FIXTURE, no una
    /// fuente: existe para poder comparar contra los apartados, y su exactitud la
    /// vigila `El_catalogo_manda_el_NOMBRE_del_modulo_y_no_sólo_su_codigo` en el
    /// backend, que los compara contra la tabla.
    const delServidor = {
      'personal': 'Personal',
      'payroll': 'Nómina',
      'finance': 'Finanzas',
      'collections': 'Cobranza',
      'purchases_inventory': 'Compras e Inventario',
      'assets': 'Activos',
      'clients_services': 'Clientes y Servicios',
    };

    const conModulos = AuditoriaLegible(
      nombrePorIdentidad: {},
      nombrePorPermiso: {},
      nombrePorModulo: delServidor,
    );

    EventoDeAuditoria eventoDeModulo(String codigo) => evento(
      entidad: 'company_module',
      accion: 'company.module.enabled',
      despues: '{"module":"$codigo","enabled":true}',
    );

    test('la auditoría nombra el MÓDULO, no su apartado', () {
      expect(conModulos.titulo(eventoDeModulo('payroll')), contains('Nómina'));
      expect(conModulos.titulo(eventoDeModulo('collections')), contains('Cobranza'));

      // Y NO dice el apartado, que es el fallo que se vio.
      expect(
        conModulos.titulo(eventoDeModulo('payroll')),
        isNot(contains('Personal')),
        reason: 'Diría «activó Personal» cuando lo que se encendió fue Nómina.',
      );
    });

    test('y los dos DISCREPAN en los módulos que comparten apartado', () {
      // Si alguna vez coincidieran, sería la señal de que alguien volvió a unificarlos
      // y la auditoría volvió a mentir.
      for (final codigo in ['payroll', 'collections', 'clients_services']) {
        expect(
          delServidor[codigo],
          isNot(equals(apartados.nombreDelGrupoDePermisos(codigo))),
          reason:
              'El módulo «$codigo» y su apartado tendrían el mismo nombre, así que '
              'la auditoría diría el del apartado y no el del módulo.',
        );
      }
    });

    test('SIN catálogo humaniza el código, y NO inventa el apartado', () {
      // Es el camino cuando el catálogo no cargó. «Payroll» se ve claramente sin
      // curar —y por eso es honesto—, pero lo que importa es que no diga «Personal».
      const sinCatalogo = AuditoriaLegible(
        nombrePorIdentidad: {},
        nombrePorPermiso: {},
      );

      final titulo = sinCatalogo.titulo(eventoDeModulo('payroll'));

      expect(titulo, contains('Payroll'));
      expect(
        titulo,
        isNot(contains('Personal')),
        reason:
            'Sin catálogo preferimos un nombre feo a uno falso: «Personal» sería '
            'una afirmación que los datos no sostienen.',
      );
    });
  });
}
