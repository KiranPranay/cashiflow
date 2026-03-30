import 'package:hive_flutter/hive_flutter.dart';
import 'package:cashi_flow/domain/models/category_model.dart';
import 'package:cashi_flow/domain/repositories/category_repository.dart';

class HiveCategoryRepository implements CategoryRepository {
  final Box<CategoryModel> _box;

  HiveCategoryRepository(this._box);

  @override
  Stream<List<CategoryModel>> watchCategories() async* {
    yield _box.values.toList();
    yield* _box.watch().map((event) => _box.values.toList());
  }

  @override
  Future<void> addCategory(CategoryModel category) async {
    await _box.put(category.id, category);
  }

  @override
  Future<void> updateCategory(CategoryModel category) async {
    await _box.put(category.id, category);
  }

  @override
  Future<void> deleteCategory(String id) async {
    await _box.delete(id);
  }

  @override
  Future<CategoryModel?> getCategoryById(String id) async {
    return _box.get(id);
  }
}
