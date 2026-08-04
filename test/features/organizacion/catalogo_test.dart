import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/organizacion/data/repositories/catalogo_repository_impl.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/listar_tipos_sucursal_usecase.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('ListarTiposSucursalUseCase devuelve los 3 tipos sembrados, ordenados', () async {
    final useCase = ListarTiposSucursalUseCase(CatalogoRepositoryImpl(db));

    final tipos = await useCase.ejecutar();

    expect(tipos.map((t) => t.codigo), containsAll(['OFICINA_ADMIN', 'BASE_OPERATIVA', 'BODEGA']));
    expect(tipos.every((t) => t.id.isNotEmpty && t.nombre.isNotEmpty), isTrue);
  });
}
