import 'package:flutter_test/flutter_test.dart';
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

    test('un módulo se nombra en español', () {
      final e = evento(
        entidad: 'company_module',
        accion: 'enabled',
        despues: '{"module":"payroll","enabled":true}',
      );

      expect(pelado.titulo(e), 'Activó el módulo Nómina');
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
      'company': ['name', 'firstMaestroIdentityId', 'protectedPermissionsGranted'],
      'company_access': ['role', 'subjectIdentityId', 'status'],
      'company_access_permission': ['permission'],
      'company_module': ['module', 'enabled'],
      'area': ['code', 'name', 'status'],
      'position': ['code', 'name', 'kind', 'area_code', 'status'],
      'branch': ['code', 'name', 'status'],
      'branch_type': ['code', 'name', 'status', 'recommended', 'created_count'],
    };

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
}
