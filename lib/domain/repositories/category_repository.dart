import 'package:cashi_flow/domain/models/category_model.dart';

abstract class CategoryRepository {
  Stream<List<CategoryModel>> watchCategories();
  Future<void> addCategory(CategoryModel category);
  Future<void> updateCategory(CategoryModel category);
  Future<void> deleteCategory(String id);
  Future<CategoryModel?> getCategoryById(String id);
}
