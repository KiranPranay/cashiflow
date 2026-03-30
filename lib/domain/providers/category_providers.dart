import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:cashi_flow/domain/models/category_model.dart';
import 'package:cashi_flow/data/repositories/hive_category_repository.dart';

final categoryRepositoryProvider = Provider((ref) {
  final box = Hive.box<CategoryModel>('categories');
  return HiveCategoryRepository(box);
});

final categoriesStreamProvider = StreamProvider<List<CategoryModel>>((ref) {
  final repo = ref.watch(categoryRepositoryProvider);
  return repo.watchCategories();
});
