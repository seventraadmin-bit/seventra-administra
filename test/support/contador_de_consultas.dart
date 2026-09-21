import 'package:drift/backends.dart';
import 'package:drift/drift.dart';

/// `QueryExecutor` que cuenta las consultas que realmente llegan a
/// SQLite.
///
/// Existe porque medir tiempo no sirve para demostrar una propiedad
/// arquitectónica: el tiempo es ruidoso y depende de la máquina. Lo que
/// prueba que un N+1 desapareció es que el NÚMERO de consultas deje de
/// crecer con el número de filas.
///
/// Envuelve un ejecutor real (normalmente `NativeDatabase.memory()`) y
/// delega todo; lo único que agrega es el conteo. La apertura de la base
/// —crear el esquema, sembrar catálogos— ejecuta muchísimas sentencias,
/// así que el conteo se arranca a mano con [reiniciar] justo antes de lo
/// que se quiere medir.
class ContadorDeConsultas implements QueryExecutor {
  ContadorDeConsultas(this._interno);

  final QueryExecutor _interno;

  /// Sentencias `SELECT` ejecutadas desde el último [reiniciar].
  int selects = 0;

  /// Texto de cada `SELECT` contado — útil para saber QUÉ se consultó de
  /// más cuando una prueba de complejidad falla.
  final List<String> sentencias = [];

  void reiniciar() {
    selects = 0;
    sentencias.clear();
  }

  @override
  Future<List<Map<String, Object?>>> runSelect(String statement, List<Object?> args) {
    selects++;
    sentencias.add(statement);
    return _interno.runSelect(statement, args);
  }

  @override
  SqlDialect get dialect => _interno.dialect;

  @override
  Future<bool> ensureOpen(QueryExecutorUser user) => _interno.ensureOpen(user);

  @override
  Future<int> runInsert(String statement, List<Object?> args) => _interno.runInsert(statement, args);

  @override
  Future<int> runUpdate(String statement, List<Object?> args) => _interno.runUpdate(statement, args);

  @override
  Future<int> runDelete(String statement, List<Object?> args) => _interno.runDelete(statement, args);

  @override
  Future<void> runCustom(String statement, [List<Object?>? args]) => _interno.runCustom(statement, args);

  @override
  Future<void> runBatched(BatchedStatements statements) => _interno.runBatched(statements);

  // Las transacciones delegan al ejecutor real. El camino de LECTURA que
  // se mide aquí no abre ninguna, así que no hace falta propagar el
  // conteo hacia dentro; si algún día lo hiciera, el conteo quedaría
  // por debajo del real y nunca por encima — el sentido seguro para una
  // prueba que exige "no más de N".
  @override
  TransactionExecutor beginTransaction() => _interno.beginTransaction();

  @override
  QueryExecutor beginExclusive() => _interno.beginExclusive();

  @override
  Future<void> close() => _interno.close();
}
