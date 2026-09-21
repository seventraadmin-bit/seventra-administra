import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:riseg_one/core/auditoria/diff_evento.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/finanzas/data/tables/deuda_table.dart' show TipoMovimientoDeuda;
import 'package:riseg_one/features/finanzas/data/tables/egreso_table.dart';
import 'package:uuid/uuid.dart';

import '../../domain/fuente_egreso.dart';
import '../../domain/origen_financiero_gasto.dart';
import '../../domain/politica_saldo_cuenta.dart';
import '../../domain/repositories/deuda_repository.dart';
import '../../domain/repositories/egreso_repository.dart';
import '../../domain/usecases/eliminar_egreso_fisicamente_usecase.dart';
import '../saldos_cuenta_query.dart';
import 'deuda_repository_impl.dart';

class EgresoRepositoryImpl implements EgresoRepository {
  EgresoRepositoryImpl(this._db);

  final AppDatabase _db;

  /// `DeudaRepository` construido AQUÍ, sobre la misma `AppDatabase` y
  /// con este mismo repositorio como su `EgresoRepository` — nunca
  /// inyectado (Etapa "Origen financiero de Egresos manuales"; forma
  /// definitiva tras el bug real descrito abajo).
  ///
  /// Por qué se compone: un gasto manual financiado con TDC escribe su
  /// `Egreso` y el `MovimientoDeuda` del cargo en la MISMA transacción,
  /// y en este proyecto el orquestador de una escritura compuesta es
  /// siempre el repositorio que posee `_db` y compone a los demás
  /// (`CompraRepositoryImpl`, `TiempoExtraRepositoryImpl`,
  /// `DeudaRepositoryImpl`). La transacción se comparte porque lo que
  /// se comparte es `_db`, no la instancia del repositorio.
  ///
  /// **Por qué NO se inyecta (bug real, caso EGR-000035).** El primer
  /// intento recibía un `DeudaRepository Function()` y el provider le
  /// pasaba `() => ref.read(deudaRepositoryProvider)`, creyendo que
  /// diferir la lectura bastaba para romper el ciclo — porque
  /// `deudaRepositoryProvider` ya hace `ref.watch(egresoRepositoryProvider)`
  /// (necesita el Egreso que genera un pago de deuda). No basta: la
  /// arista del grafo de Riverpod se registra igual al leerla, y la
  /// primera corrección Cuenta → TDC lanzaba `CircularDependencyError`
  /// en tiempo de ejecución, que el caso de uso traducía al genérico
  /// "No se pudo corregir el Egreso". Ninguna prueba lo detectó porque
  /// todas arman los repositorios a mano, sin `ProviderContainer` — ver
  /// `egreso_origen_financiero_providers_test.dart`, que ahora cubre
  /// justamente esa vía.
  ///
  /// `DeudaRepositoryImpl` es un envoltorio sin estado sobre `_db`, así
  /// que construirlo aquí es equivalente a recibirlo y elimina el ciclo
  /// de raíz: `egresoRepositoryProvider` ya no depende de
  /// `deudaRepositoryProvider` en ninguna dirección.
  late final DeudaRepository _deudaRepository = DeudaRepositoryImpl(_db, this);

  @override
  Future<EgresoData?> obtenerPorId(String id) {
    return (_db.select(_db.egreso)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  @override
  Future<List<EgresoData>> listar({
    String? estatus,
    String? categoriaFinancieraId,
    String? servicioId,
    String? sucursalId,
    String? areaId,
    DateTime? rangoInicio,
    DateTime? rangoFin,
    bool soloSalidaDeEfectivo = false,
  }) {
    final query = _db.select(_db.egreso);
    if (soloSalidaDeEfectivo) query.where((t) => t.deudaId.isNull());
    if (estatus != null) query.where((t) => t.estatus.equals(estatus));
    if (categoriaFinancieraId != null) query.where((t) => t.categoriaFinancieraId.equals(categoriaFinancieraId));
    if (servicioId != null) query.where((t) => t.servicioId.equals(servicioId));
    if (sucursalId != null) query.where((t) => t.sucursalId.equals(sucursalId));
    if (areaId != null) query.where((t) => t.areaId.equals(areaId));
    if (rangoInicio != null) query.where((t) => t.fecha.isBiggerOrEqualValue(rangoInicio));
    if (rangoFin != null) query.where((t) => t.fecha.isSmallerOrEqualValue(rangoFin));
    query.orderBy([(t) => OrderingTerm.desc(t.fecha)]);
    return query.get();
  }

  @override
  Future<List<EgresoEventoData>> listarEventos(String egresoId) {
    return (_db.select(_db.egresoEvento)
          ..where((t) => t.egresoId.equals(egresoId))
          ..orderBy([(t) => OrderingTerm.asc(t.fechaHora)]))
        .get();
  }

  @override
  Future<EgresoData> crear({
    required String folioEgreso,
    required int monto,
    required DateTime fecha,
    String? categoriaFinancieraId,
    String? servicioId,
    String? sucursalId,
    String? areaId,
    String? cuentaCaja,
    String? cuentaFinancieraId,
    List<FuenteEgreso>? fuentes,
    String? deudaId,
    required String formaPago,
    String? beneficiario,
    required String concepto,
    String? observaciones,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      // Invariante de origen financiero (Etapa "Origen financiero de
      // Egresos manuales"): un gasto sale de una cuenta O se carga a
      // una tarjeta, nunca ambas — se valida aquí, en el único punto
      // de entrada de escritura, no vía `CHECK` de esquema.
      if (cuentaFinancieraId != null && deudaId != null) {
        throw StateError(
          'Egreso $folioEgreso: cuentaFinancieraId y deudaId son mutuamente '
          'excluyentes — un gasto no puede salir de una cuenta y cargarse a '
          'una tarjeta a la vez.',
        );
      }

      // Las fuentes son la verdad. Un llamador que sólo conoce una
      // cuenta (los nueve orígenes automáticos actuales) no tiene que
      // saber nada de esto: su cuenta única se convierte en una fuente
      // por el importe completo, y así TODO Egreso pagado desde cuenta
      // queda representado igual.
      final fuentesResueltas = _resolverFuentes(
        fuentes: fuentes,
        cuentaFinancieraId: cuentaFinancieraId,
        monto: monto,
      );
      final cuentaLegacy = _cuentaLegacyDe(fuentesResueltas, cuentaFinancieraId);

      final egreso = await _db.into(_db.egreso).insertReturning(
            EgresoCompanion.insert(
              folioEgreso: folioEgreso,
              monto: monto,
              fecha: fecha,
              categoriaFinancieraId: Value(categoriaFinancieraId),
              servicioId: Value(servicioId),
              sucursalId: Value(sucursalId),
              areaId: Value(areaId),
              cuentaCaja: Value(cuentaCaja),
              cuentaFinancieraId: Value(cuentaLegacy),
              deudaId: Value(deudaId),
              formaPago: formaPago,
              beneficiario: Value(beneficiario),
              concepto: concepto,
              observaciones: Value(observaciones),
            ),
          );

      await _sincronizarFuentes(egresoId: egreso.id, monto: monto, fecha: fecha, fuentes: fuentesResueltas);

      await _registrarEvento(
        egresoId: egreso.id,
        tipoEvento: TipoEventoEgreso.registrado,
        estadoAnterior: null,
        estadoNuevo: egreso.estatus,
        actorUsuarioId: actorUsuarioId,
        datosRelevantes: {
          'folioEgreso': folioEgreso,
          'monto': monto,
          if (fuentesResueltas.isNotEmpty)
            'fuentes': [
              for (final f in fuentesResueltas) {'cuentaFinancieraId': f.cuentaFinancieraId, 'importe': f.importe},
            ],
        },
      );

      return egreso;
    });
  }

  @override
  Future<EgresoData> corregir({
    required String egresoId,
    int? monto,
    DateTime? fecha,
    String? categoriaFinancieraId,
    String? servicioId,
    String? sucursalId,
    String? areaId,
    String? cuentaCaja,
    String? cuentaFinancieraId,
    List<FuenteEgreso>? fuentes,
    bool limpiarCuentaFinancieraId = false,
    String? deudaId,
    bool limpiarDeudaId = false,
    String? formaPago,
    String? beneficiario,
    String? concepto,
    String? observaciones,
    required String motivo,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final anterior = await (_db.select(_db.egreso)..where((t) => t.id.equals(egresoId))).getSingle();

      // Misma invariante que en `crear`, evaluada sobre el estado
      // RESULTANTE (no solo sobre los argumentos): corregir solo la
      // cuenta de un Egreso que hoy tiene tarjeta debe fallar salvo que
      // la misma llamada limpie la tarjeta — que es exactamente lo que
      // hace la transición TDC → Cuenta.
      final cuentaResultante = limpiarCuentaFinancieraId ? null : (cuentaFinancieraId ?? anterior.cuentaFinancieraId);
      final deudaResultante = limpiarDeudaId ? null : (deudaId ?? anterior.deudaId);
      if (cuentaResultante != null && deudaResultante != null) {
        throw StateError(
          'Egreso ${anterior.folioEgreso}: cuentaFinancieraId y deudaId son '
          'mutuamente excluyentes — la corrección dejaría el gasto con los '
          'dos orígenes financieros a la vez.',
        );
      }

      await (_db.update(_db.egreso)..where((t) => t.id.equals(egresoId))).write(
        EgresoCompanion(
          monto: monto == null ? const Value.absent() : Value(monto),
          fecha: fecha == null ? const Value.absent() : Value(fecha),
          categoriaFinancieraId: categoriaFinancieraId == null ? const Value.absent() : Value(categoriaFinancieraId),
          servicioId: servicioId == null ? const Value.absent() : Value(servicioId),
          sucursalId: sucursalId == null ? const Value.absent() : Value(sucursalId),
          areaId: areaId == null ? const Value.absent() : Value(areaId),
          cuentaCaja: cuentaCaja == null ? const Value.absent() : Value(cuentaCaja),
          cuentaFinancieraId:
              limpiarCuentaFinancieraId ? const Value(null) : (cuentaFinancieraId == null ? const Value.absent() : Value(cuentaFinancieraId)),
          deudaId: limpiarDeudaId ? const Value(null) : (deudaId == null ? const Value.absent() : Value(deudaId)),
          formaPago: formaPago == null ? const Value.absent() : Value(formaPago),
          beneficiario: beneficiario == null ? const Value.absent() : Value(beneficiario),
          concepto: concepto == null ? const Value.absent() : Value(concepto),
          observaciones: observaciones == null ? const Value.absent() : Value(observaciones),
          updatedAt: Value(DateTime.now()),
        ),
      );

      // Fuentes DESPUÉS de actualizar el Egreso, para que la
      // validación use el importe y la fecha ya corregidos.
      //
      // `_sincronizarFuentes` borra primero las fuentes anteriores y
      // sólo entonces lee el saldo: así el saldo contra el que se
      // valida ya no incluye el movimiento que esta misma corrección
      // sustituye, sin ninguna aritmética de compensación. Es la
      // respuesta al caso de "no contarse a sí mismo".
      final fuentesNuevas = _resolverFuentes(
        fuentes: fuentes,
        cuentaFinancieraId: cuentaResultante,
        monto: monto ?? anterior.monto,
      );
      if (fuentes != null || cuentaFinancieraId != null || limpiarCuentaFinancieraId || monto != null) {
        await _sincronizarFuentes(
          egresoId: egresoId,
          monto: monto ?? anterior.monto,
          fecha: fecha ?? anterior.fecha,
          fuentes: fuentesNuevas,
          validar: anterior.estatus == 'registrado',
        );
        if (fuentes != null) {
          await (_db.update(_db.egreso)..where((t) => t.id.equals(egresoId)))
              .write(EgresoCompanion(cuentaFinancieraId: Value(_cuentaLegacyDe(fuentesNuevas, cuentaResultante))));
        }
      }

      final diff = DiffEvento();
      if (monto != null) diff.anotar('monto', anterior.monto, monto);
      if (fecha != null) diff.anotar('fecha', anterior.fecha, fecha);
      if (categoriaFinancieraId != null) diff.anotar('categoriaFinancieraId', anterior.categoriaFinancieraId, categoriaFinancieraId);
      if (servicioId != null) diff.anotar('servicioId', anterior.servicioId, servicioId);
      if (sucursalId != null) diff.anotar('sucursalId', anterior.sucursalId, sucursalId);
      if (areaId != null) diff.anotar('areaId', anterior.areaId, areaId);
      if (cuentaCaja != null) diff.anotar('cuentaCaja', anterior.cuentaCaja, cuentaCaja);
      if (limpiarCuentaFinancieraId || cuentaFinancieraId != null) {
        diff.anotar('cuentaFinancieraId', anterior.cuentaFinancieraId, limpiarCuentaFinancieraId ? null : cuentaFinancieraId);
      }
      if (limpiarDeudaId || deudaId != null) {
        diff.anotar('deudaId', anterior.deudaId, limpiarDeudaId ? null : deudaId);
      }
      if (formaPago != null) diff.anotar('formaPago', anterior.formaPago, formaPago);
      if (beneficiario != null) diff.anotar('beneficiario', anterior.beneficiario, beneficiario);
      if (concepto != null) diff.anotar('concepto', anterior.concepto, concepto);
      if (observaciones != null) diff.anotar('observaciones', anterior.observaciones, observaciones);

      await _registrarEvento(
        egresoId: egresoId,
        tipoEvento: TipoEventoEgreso.corregido,
        estadoAnterior: diff.estadoAnteriorJson,
        estadoNuevo: diff.estadoNuevoJson,
        observacion: motivo,
        actorUsuarioId: actorUsuarioId,
      );

      return (_db.select(_db.egreso)..where((t) => t.id.equals(egresoId))).getSingle();
    });
  }

  /// Descompone un [OrigenFinancieroGasto] en el par de columnas
  /// mutuamente excluyentes que `Egreso` persiste. `null` en ambas
  /// cuando el origen es `null` — "sin especificar", nunca un tercer
  /// caso.
  /// La lista de fuentes con la que se va a trabajar: la explícita si
  /// el llamador la dio, o la única derivada de su cuenta.
  List<FuenteEgreso> _resolverFuentes({
    required List<FuenteEgreso>? fuentes,
    required String? cuentaFinancieraId,
    required int monto,
  }) {
    if (fuentes != null) return List.unmodifiable(fuentes);
    if (cuentaFinancieraId == null) return const [];
    return [FuenteEgreso(cuentaFinancieraId: cuentaFinancieraId, importe: monto)];
  }

  /// El valor de la columna *legacy* `Egreso.cuentaFinancieraId`.
  ///
  /// Se sigue escribiendo para no romper a sus consumidores actuales
  /// (clasificación por origen, diff de corrección de Compras,
  /// reportes), pero **ningún cálculo de saldo la lee**: con varias
  /// fuentes queda `null`, porque ninguna cuenta sola representa el
  /// Egreso, y eso mismo delata a cualquiera que intente volver a
  /// usarla como verdad.
  String? _cuentaLegacyDe(List<FuenteEgreso> fuentes, String? cuentaFinancieraId) {
    if (fuentes.isEmpty) return cuentaFinancieraId;
    if (fuentes.length == 1) return fuentes.single.cuentaFinancieraId;
    return null;
  }

  /// Sustituye las fuentes de un Egreso, validando la política de saldo
  /// **dentro de la transacción en curso**.
  ///
  /// El orden importa y es deliberado:
  ///
  /// 1. se borran las fuentes anteriores del mismo Egreso;
  /// 2. se lee el saldo — que por (1) ya no las incluye;
  /// 3. se valida contra ese saldo;
  /// 4. se insertan las nuevas.
  ///
  /// Así una corrección nunca se cuenta a sí misma, y la lectura que
  /// autoriza la salida no puede separarse de la escritura: si la
  /// política rechaza, la excepción aborta la transacción entera —
  /// incluido lo que el módulo de origen llevara escrito.
  Future<void> _sincronizarFuentes({
    required String egresoId,
    required int monto,
    required DateTime fecha,
    required List<FuenteEgreso> fuentes,
    bool validar = true,
  }) async {
    await (_db.delete(_db.egresoFuente)..where((t) => t.egresoId.equals(egresoId))).go();
    if (fuentes.isEmpty) return;

    final cuentasVistas = <String>{};
    var suma = 0;
    for (final f in fuentes) {
      if (f.importe <= 0) {
        throw DistribucionInvalidaException('Una fuente de pago debe ser mayor a cero (recibido: ${f.importe}).');
      }
      if (!cuentasVistas.add(f.cuentaFinancieraId)) {
        throw DistribucionInvalidaException('La cuenta ${f.cuentaFinancieraId} aparece dos veces en el mismo pago.');
      }
      suma += f.importe;
    }
    if (suma != monto) {
      throw DistribucionInvalidaException('Las fuentes suman $suma y el importe es $monto: deben coincidir exactamente.');
    }

    if (validar) {
      final cuentas = await (_db.select(_db.cuentaFinanciera)..where((t) => t.id.isIn(cuentasVistas))).get();
      final porId = {for (final c in cuentas) c.id: c};
      final saldos = await calcularSaldosCanonico(_db, cuentasVistas);
      const politica = PoliticaSaldoCuenta();
      for (final f in fuentes) {
        final veredicto = politica.verificar(
          cuenta: porId[f.cuentaFinancieraId],
          disponible: saldos[f.cuentaFinancieraId] ?? 0,
          requerido: f.importe,
          fechaMovimiento: fecha,
        );
        if (veredicto is! SaldoSuficiente) throw SaldoInsuficienteException(veredicto);
      }
    }

    for (final f in fuentes) {
      await _db.into(_db.egresoFuente).insert(
            EgresoFuenteCompanion.insert(
              egresoId: egresoId,
              cuentaFinancieraId: f.cuentaFinancieraId,
              importe: f.importe,
            ),
          );
    }
  }

  ({String? cuentaFinancieraId, String? deudaId}) _columnasDeOrigen(OrigenFinancieroGasto? origen) {
    return switch (origen) {
      OrigenFinancieroCuenta(:final cuentaFinancieraId) => (cuentaFinancieraId: cuentaFinancieraId, deudaId: null),
      OrigenFinancieroTarjeta(:final deudaId) => (cuentaFinancieraId: null, deudaId: deudaId),
      null => (cuentaFinancieraId: null, deudaId: null),
    };
  }

  @override
  Future<EgresoData> crearConOrigen({
    required String folioEgreso,
    required int monto,
    required DateTime fecha,
    String? categoriaFinancieraId,
    String? servicioId,
    String? sucursalId,
    String? areaId,
    String? cuentaCaja,
    OrigenFinancieroGasto? origen,
    required String formaPago,
    String? beneficiario,
    required String concepto,
    String? observaciones,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final columnas = _columnasDeOrigen(origen);

      final egreso = await crear(
        folioEgreso: folioEgreso,
        monto: monto,
        fecha: fecha,
        categoriaFinancieraId: categoriaFinancieraId,
        servicioId: servicioId,
        sucursalId: sucursalId,
        areaId: areaId,
        cuentaCaja: cuentaCaja,
        cuentaFinancieraId: columnas.cuentaFinancieraId,
        deudaId: columnas.deudaId,
        formaPago: formaPago,
        beneficiario: beneficiario,
        concepto: concepto,
        observaciones: observaciones,
        actorUsuarioId: actorUsuarioId,
      );

      if (columnas.deudaId != null) {
        await _deudaRepository.registrarCargoEgreso(
          deudaId: columnas.deudaId!,
          egresoId: egreso.id,
          monto: monto,
          fecha: fecha,
          observaciones: 'Gasto $folioEgreso · $concepto',
          actorUsuarioId: actorUsuarioId,
        );
      }

      return (_db.select(_db.egreso)..where((t) => t.id.equals(egreso.id))).getSingle();
    });
  }

  @override
  Future<EgresoData> corregirConOrigen({
    required String egresoId,
    int? monto,
    DateTime? fecha,
    String? categoriaFinancieraId,
    String? servicioId,
    String? sucursalId,
    String? areaId,
    String? cuentaCaja,
    OrigenFinancieroGasto? origen,
    bool limpiarOrigen = false,
    String? formaPago,
    String? beneficiario,
    String? concepto,
    String? observaciones,
    required String motivo,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final anterior = await (_db.select(_db.egreso)..where((t) => t.id.equals(egresoId))).getSingle();

      final deudaAnterior = anterior.deudaId;
      final montoFinal = monto ?? anterior.monto;

      // Origen resultante: explícito si se pasó uno (o si se pidió
      // limpiarlo); si no, se CONSERVA el actual — corregir solo el
      // monto de un gasto con TDC nunca debe borrar su tarjeta.
      final ({String? cuentaFinancieraId, String? deudaId}) destino;
      if (limpiarOrigen) {
        destino = (cuentaFinancieraId: null, deudaId: null);
      } else if (origen != null) {
        destino = _columnasDeOrigen(origen);
      } else {
        destino = (cuentaFinancieraId: anterior.cuentaFinancieraId, deudaId: deudaAnterior);
      }
      final deudaNueva = destino.deudaId;
      final cambiaOrigen = limpiarOrigen || origen != null;

      // 1. Revierte el cargo de la tarjeta ANTERIOR cuando el gasto
      //    deja de estar financiado por ella (se va a otra tarjeta, a
      //    una cuenta, o se queda sin origen). Nunca cuando sigue en la
      //    MISMA tarjeta — ese caso es un ajuste-delta (paso 3), jamás
      //    una reversión + cargo nuevo, que perdería el encadenamiento
      //    del ledger sin ninguna ganancia.
      if (deudaAnterior != null && deudaNueva != deudaAnterior) {
        await _deudaRepository.revertirCargoEgreso(
          deudaId: deudaAnterior,
          egresoId: egresoId,
          motivo: motivo,
          actorUsuarioId: actorUsuarioId,
        );
      }

      // 2. Escribe el Egreso ya con su origen final. `limpiar*` explícito
      //    en cada transición para que la invariante "cuenta XOR
      //    tarjeta" se cumpla sobre el estado RESULTANTE.
      final corregido = await corregir(
        egresoId: egresoId,
        monto: monto,
        fecha: fecha,
        categoriaFinancieraId: categoriaFinancieraId,
        servicioId: servicioId,
        sucursalId: sucursalId,
        areaId: areaId,
        cuentaCaja: cuentaCaja,
        cuentaFinancieraId: destino.cuentaFinancieraId,
        limpiarCuentaFinancieraId: cambiaOrigen && destino.cuentaFinancieraId == null,
        deudaId: destino.deudaId,
        limpiarDeudaId: cambiaOrigen && destino.deudaId == null,
        formaPago: formaPago,
        beneficiario: beneficiario,
        concepto: concepto,
        observaciones: observaciones,
        motivo: motivo,
        actorUsuarioId: actorUsuarioId,
      );

      if (deudaNueva != null) {
        if (deudaNueva == deudaAnterior) {
          // 3. MISMA tarjeta: ajuste-delta append-only — nunca reescribe
          //    el `cargoCompra` original (mismo criterio exacto que
          //    Compra/TiempoExtra sobre su propia tarjeta).
          await _deudaRepository.registrarAjusteCargoEgreso(
            deudaId: deudaNueva,
            egresoId: egresoId,
            deltaImporte: montoFinal - anterior.monto,
            motivo: motivo,
            actorUsuarioId: actorUsuarioId,
          );
        } else {
          // 4. Tarjeta distinta (o gasto que ANTES no estaba en ninguna):
          //    cargo completo nuevo por el monto final.
          await _deudaRepository.registrarCargoEgreso(
            deudaId: deudaNueva,
            egresoId: egresoId,
            monto: montoFinal,
            fecha: corregido.fecha,
            observaciones: 'Gasto ${corregido.folioEgreso} · ${corregido.concepto}',
            actorUsuarioId: actorUsuarioId,
          );
        }
      }

      return (_db.select(_db.egreso)..where((t) => t.id.equals(egresoId))).getSingle();
    });
  }

  @override
  Future<EgresoData> cancelarConOrigen({
    required String egresoId,
    required String motivo,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final anterior = await (_db.select(_db.egreso)..where((t) => t.id.equals(egresoId))).getSingle();

      final cancelado = await cancelar(egresoId: egresoId, motivo: motivo, actorUsuarioId: actorUsuarioId);

      // `deudaId` NO se limpia: el expediente conserva con qué tarjeta
      // se financió el gasto que se canceló. El efecto financiero sí
      // queda en cero, por el `ajusteNegativo` — y `revertirCargoEgreso`
      // es idempotente por construcción (si el neto ya es 0 no escribe
      // nada), así que una segunda cancelación nunca duplica reversión.
      if (anterior.deudaId != null) {
        await _deudaRepository.revertirCargoEgreso(
          deudaId: anterior.deudaId!,
          egresoId: egresoId,
          motivo: motivo,
          actorUsuarioId: actorUsuarioId,
        );
      }

      return cancelado;
    });
  }

  @override
  Future<EgresoData> corregirMonto({
    required String egresoId,
    required int nuevoMonto,
    required String motivo,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final anterior = await (_db.select(_db.egreso)..where((t) => t.id.equals(egresoId))).getSingle();

      await (_db.update(_db.egreso)..where((t) => t.id.equals(egresoId))).write(
        EgresoCompanion(monto: Value(nuevoMonto), updatedAt: Value(DateTime.now())),
      );

      // Las fuentes van con el importe: cambiar el monto sin
      // re-repartirlo dejaría la suma descuadrada y el saldo
      // mintiendo. Sólo se puede hacer automáticamente cuando hay
      // una sola cuenta; con varias, quién pone el delta es una
      // decisión de negocio que este método no puede tomar por nadie.
      final fuentesActuales =
          await (_db.select(_db.egresoFuente)..where((t) => t.egresoId.equals(egresoId))).get();
      if (fuentesActuales.length > 1) {
        throw DistribucionInvalidaException(
          'El Egreso ${anterior.folioEgreso} se pagó desde ${fuentesActuales.length} cuentas: '
          'corrige la distribución explícitamente en vez de sólo el importe.',
        );
      }
      if (fuentesActuales.length == 1) {
        await _sincronizarFuentes(
          egresoId: egresoId,
          monto: nuevoMonto,
          fecha: anterior.fecha,
          fuentes: [
            FuenteEgreso(cuentaFinancieraId: fuentesActuales.single.cuentaFinancieraId, importe: nuevoMonto),
          ],
          validar: anterior.estatus == 'registrado',
        );
      }

      await _registrarEvento(
        egresoId: egresoId,
        tipoEvento: TipoEventoEgreso.corregido,
        estadoAnterior: anterior.estatus,
        estadoNuevo: anterior.estatus,
        observacion: motivo,
        actorUsuarioId: actorUsuarioId,
        datosRelevantes: {'montoAnterior': anterior.monto, 'montoNuevo': nuevoMonto},
      );

      return (_db.select(_db.egreso)..where((t) => t.id.equals(egresoId))).getSingle();
    });
  }

  @override
  Future<EgresoData> cancelar({
    required String egresoId,
    required String motivo,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final anterior = await (_db.select(_db.egreso)..where((t) => t.id.equals(egresoId))).getSingle();

      await (_db.update(_db.egreso)..where((t) => t.id.equals(egresoId))).write(
        EgresoCompanion(
          estatus: Value(EstatusEgreso.cancelado.name),
          motivoCancelacion: Value(motivo),
          updatedAt: Value(DateTime.now()),
        ),
      );

      await _registrarEvento(
        egresoId: egresoId,
        tipoEvento: TipoEventoEgreso.cancelado,
        estadoAnterior: anterior.estatus,
        estadoNuevo: EstatusEgreso.cancelado.name,
        observacion: motivo,
        actorUsuarioId: actorUsuarioId,
      );

      return (_db.select(_db.egreso)..where((t) => t.id.equals(egresoId))).getSingle();
    });
  }

  @override
  Future<AttachmentData> adjuntarComprobante({
    required String egresoId,
    required String originalFileName,
    required String storedFileName,
    required String path,
    required String mimeType,
    required int sizeBytes,
    String? actorUsuarioId,
  }) {
    return _db.transaction(() async {
      final adjunto = await _db.into(_db.attachment).insertReturning(
            AttachmentCompanion.insert(
              id: const Uuid().v4(),
              categoria: const Value('comprobante'),
              originalFileName: originalFileName,
              storedFileName: storedFileName,
              path: path,
              mimeType: mimeType,
              sizeBytes: sizeBytes,
            ),
          );
      await _db.into(_db.egresoAttachment).insert(
            EgresoAttachmentCompanion.insert(attachmentId: adjunto.id, egresoId: egresoId),
          );

      await _registrarEvento(
        egresoId: egresoId,
        tipoEvento: TipoEventoEgreso.comprobanteAdjuntado,
        estadoAnterior: null,
        estadoNuevo: null,
        actorUsuarioId: actorUsuarioId,
        datosRelevantes: {'archivoNuevo': originalFileName, 'attachmentId': adjunto.id},
      );

      return adjunto;
    });
  }

  @override
  Future<int> totalEgresos({DateTime? rangoInicio, DateTime? rangoFin}) async {
    final query = _db.selectOnly(_db.egreso)
      ..addColumns([_db.egreso.monto.sum()])
      ..where(_db.egreso.estatus.equals(EstatusEgreso.registrado.name))
      // Etapa "Origen financiero de Egresos manuales": un gasto
      // financiado con TDC nunca es salida de efectivo — ver el doc
      // comment del método en la interfaz.
      ..where(_db.egreso.deudaId.isNull());
    if (rangoInicio != null) query.where(_db.egreso.fecha.isBiggerOrEqualValue(rangoInicio));
    if (rangoFin != null) query.where(_db.egreso.fecha.isSmallerOrEqualValue(rangoFin));
    final fila = await query.getSingle();
    return fila.read(_db.egreso.monto.sum()) ?? 0;
  }

  @override
  Future<Map<String?, int>> totalPorCategoria({DateTime? rangoInicio, DateTime? rangoFin}) async {
    // Mismo predicado que `totalEgresos`, incluida la exclusión de los
    // Egresos financiados con TDC: este desglose es exactamente esa
    // cifra abierta por categoría, y si no cuadrara con ella Reportes
    // mostraría un total y una tabla que no suman lo mismo.
    final query = _db.selectOnly(_db.egreso)
      ..addColumns([_db.egreso.categoriaFinancieraId, _db.egreso.monto.sum()])
      ..where(_db.egreso.estatus.equals(EstatusEgreso.registrado.name) & _db.egreso.deudaId.isNull())
      ..groupBy([_db.egreso.categoriaFinancieraId]);
    if (rangoInicio != null) query.where(_db.egreso.fecha.isBiggerOrEqualValue(rangoInicio));
    if (rangoFin != null) query.where(_db.egreso.fecha.isSmallerOrEqualValue(rangoFin));
    final filas = await query.get();
    return {
      for (final fila in filas)
        fila.read(_db.egreso.categoriaFinancieraId): fila.read(_db.egreso.monto.sum()) ?? 0,
    };
  }

  /// Cinco orígenes automáticos reales hoy (Etapa 15: `Compra`/
  /// `PagoNomina`; etapa "Ingresos y Egresos": `TiempoExtra`/
  /// `TiempoExtraCostoAdicional`/`MovimientoDeuda` — hueco real de
  /// auditoría, ninguno se verificaba antes: intentar eliminar un
  /// Egreso de Tiempo Extra o de un pago de Deuda fallaba con una
  /// excepción SQL cruda de FK en vez de este mensaje amigable con el
  /// folio real, exactamente igual que ya pasaba con Compra/Nómina
  /// antes de esta comprobación) — todas sus FK son `onDelete:
  /// restrict`, así que SQLite ya lo impediría de todas formas; se
  /// verifican aquí primero solo para dar el mensaje específico.
  /// `Egreso` no guarda su propio origen; se infiere siempre por
  /// relación inversa, la única fuente determinista real.
  @override
  Future<ResumenEliminacionEgreso> obtenerResumenEliminacionFisica(String egresoId) async {
    final egreso = await obtenerPorId(egresoId);
    if (egreso == null) return const ResumenEliminacionEgreso(existe: false);

    final compra = await (_db.select(_db.compra)..where((t) => t.egresoId.equals(egresoId))).getSingleOrNull();
    if (compra != null) {
      return ResumenEliminacionEgreso(
        existe: true,
        detalleBloqueo:
            'Este Egreso fue generado por la Compra ${compra.folioCompra}. Corrija o elimine la Compra desde su expediente.',
      );
    }

    final pagoNomina =
        await (_db.select(_db.pagoNomina)..where((t) => t.egresoId.equals(egresoId))).getSingleOrNull();
    if (pagoNomina != null) {
      return ResumenEliminacionEgreso(
        existe: true,
        detalleBloqueo:
            'Este Egreso pertenece al Pago de Nómina ${pagoNomina.folioPagoNomina} y no puede eliminarse de forma independiente.',
      );
    }

    final tiempoExtraBase =
        await (_db.select(_db.tiempoExtra)..where((t) => t.egresoId.equals(egresoId))).getSingleOrNull();
    if (tiempoExtraBase != null) {
      return ResumenEliminacionEgreso(
        existe: true,
        detalleBloqueo:
            'Este Egreso fue generado por el Tiempo extra ${tiempoExtraBase.folio}. Corrija o cancele el Tiempo extra desde su expediente.',
      );
    }

    final costoAdicional = await (_db.select(_db.tiempoExtraCostoAdicional)..where((t) => t.egresoId.equals(egresoId)))
        .getSingleOrNull();
    if (costoAdicional != null) {
      final tiempoExtraDelCosto =
          await (_db.select(_db.tiempoExtra)..where((t) => t.id.equals(costoAdicional.tiempoExtraId))).getSingleOrNull();
      return ResumenEliminacionEgreso(
        existe: true,
        detalleBloqueo: 'Este Egreso fue generado por un costo adicional del Tiempo extra '
            '${tiempoExtraDelCosto?.folio ?? costoAdicional.tiempoExtraId}. Corrija o cancele el Tiempo extra desde su expediente.',
      );
    }

    final movimientoDeuda = await (_db.select(_db.movimientoDeuda)
          ..where((t) => t.tipo.equals(TipoMovimientoDeuda.pago.name) & t.egresoId.equals(egresoId)))
        .getSingleOrNull();
    if (movimientoDeuda != null) {
      final deuda = await (_db.select(_db.deuda)..where((t) => t.id.equals(movimientoDeuda.deudaId))).getSingleOrNull();
      return ResumenEliminacionEgreso(
        existe: true,
        detalleBloqueo: 'Este Egreso fue generado por un pago de la Deuda ${deuda?.folio ?? movimientoDeuda.deudaId}. '
            'No puede eliminarse de forma independiente.',
      );
    }

    final descuentoProgramado =
        await (_db.select(_db.descuentoProgramadoEmpleado)..where((t) => t.egresoId.equals(egresoId))).getSingleOrNull();
    if (descuentoProgramado != null) {
      return ResumenEliminacionEgreso(
        existe: true,
        detalleBloqueo: 'Este Egreso fue generado por el desembolso del descuento ${descuentoProgramado.folio}. '
            'Cancele o elimine el descuento desde su expediente.',
      );
    }

    return const ResumenEliminacionEgreso(existe: true);
  }

  /// Eliminación física extraordinaria (Etapa 15; ampliada en la etapa
  /// "Ingresos y Egresos") — el único bloqueador real es que el Egreso
  /// haya sido generado automáticamente por una Compra/Pago de Nómina/
  /// Tiempo Extra (base o costo adicional)/pago de Deuda
  /// (`obtenerResumenEliminacionFisica`); el estatus (`registrado`/
  /// `cancelado`) nunca bloquea por sí solo — un Egreso manual cancelado
  /// (captura de prueba) es el caso elegible típico. Los comprobantes
  /// (`EgresoAttachment`) se limpian explícitamente en la misma
  /// transacción, nunca vía `CASCADE` indiscriminado: son solo soporte
  /// documental, no una dependencia financiera real como las anteriores.
  @override
  Future<EliminarEgresoFisicamenteResultado> eliminarFisicamente({
    required String egresoId,
    required String motivo,
    String? actorUsuarioId,
  }) async {
    final egresoInicial = await obtenerPorId(egresoId);
    if (egresoInicial == null) return EliminarEgresoFisicamenteNoExiste();

    final resumen = await obtenerResumenEliminacionFisica(egresoId);
    if (resumen.bloqueado) {
      return EliminarEgresoFisicamenteTieneDependencias(resumen.detalleBloqueo!);
    }

    final adjuntosQuery = _db.select(_db.attachment).join([
      innerJoin(_db.egresoAttachment, _db.egresoAttachment.attachmentId.equalsExp(_db.attachment.id)),
    ])
      ..where(_db.egresoAttachment.egresoId.equals(egresoId));
    final adjuntos = await adjuntosQuery.map((row) => row.readTable(_db.attachment)).get();
    final eventos = await listarEventos(egresoId);

    await _db.transaction(() async {
      final snapshot = <String, Object?>{
        'egreso': egresoInicial.toJson(),
        'eventos': [for (final e in eventos) e.toJson()],
        'adjuntos': [for (final a in adjuntos) a.toJson()],
      };

      await (_db.delete(_db.egresoAttachment)..where((t) => t.egresoId.equals(egresoId))).go();
      for (final adjunto in adjuntos) {
        await (_db.delete(_db.attachment)..where((t) => t.id.equals(adjunto.id))).go();
      }

      await _db.into(_db.eliminacionFisicaEvento).insert(
            EliminacionFisicaEventoCompanion.insert(
              tipoEntidad: 'egreso',
              entidadIdOriginal: egresoId,
              fechaHora: DateTime.now(),
              motivo: motivo,
              snapshotJson: jsonEncode(snapshot),
              actorUsuarioId: Value(actorUsuarioId),
            ),
          );
      await (_db.delete(_db.egreso)..where((t) => t.id.equals(egresoId))).go();
    });

    return EliminarEgresoFisicamenteExitoso();
  }

  Future<void> _registrarEvento({
    required String egresoId,
    required TipoEventoEgreso tipoEvento,
    required String? estadoAnterior,
    required String? estadoNuevo,
    String? observacion,
    String? actorUsuarioId,
    Map<String, Object?>? datosRelevantes,
  }) {
    return _db.into(_db.egresoEvento).insert(
          EgresoEventoCompanion.insert(
            egresoId: egresoId,
            fechaHora: DateTime.now(),
            tipoEvento: tipoEvento.name,
            estadoAnterior: Value(estadoAnterior),
            estadoNuevo: Value(estadoNuevo),
            observacion: Value(observacion),
            actorUsuarioId: Value(actorUsuarioId),
            datosRelevantes: Value(datosRelevantes == null ? null : jsonEncode(datosRelevantes)),
          ),
        );
  }
}
