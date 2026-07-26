import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/app_snackbar.dart';
import '../../data/datasources/admin_remote_datasource.dart';
import '../../data/models/admin_models.dart';

/// "بدء تشغيلة جديدة" — mirrors the web's MaterialIssuancePage.tsx exactly:
/// pick a category → recipe, enter consumed material quantities (deducted
/// immediately), optionally add product re-entry lines, then submit to the
/// same POST /manufacturing the web page uses. No planned-quantity field on
/// outputs — that field/its downstream efficiency reporting was removed
/// backend-wide (see ManufacturingController).
class StartProductionPage extends StatefulWidget {
  const StartProductionPage({super.key});

  @override
  State<StartProductionPage> createState() => _StartProductionPageState();
}

class _InputRow {
  final RecipeInputModel recipeInput;
  final _qtyCtrl = TextEditingController();
  _InputRow(this.recipeInput) {
    if (recipeInput.defaultQuantity > 0) {
      _qtyCtrl.text = recipeInput.defaultQuantity.toString();
    }
  }
}

class _OutputRow {
  final RecipeOutputModel recipeOutput;
  int? warehouseId;
  _OutputRow(this.recipeOutput);
}

class _ReentryRow {
  int? productId;
  int? warehouseId;
  final qtyCtrl = TextEditingController();
}

class _StartProductionPageState extends State<StartProductionPage> {
  final _remote = sl<AdminRemoteDataSource>();

  List<IdNameModel> _categories = [];
  List<RecipeModel> _recipes = [];
  List<IdNameModel> _labs = [];
  List<SimpleWarehouseModel> _warehouses = [];
  List<SimpleProductModel> _allProducts = [];
  List<TreasuryModel> _treasuries = [];
  List<ProductionBatchSummaryModel> _recentBatches = [];

  int? _categoryId;
  RecipeModel? _selectedRecipe;
  int? _labId;
  final _notesCtrl = TextEditingController();
  final _expenseCtrl = TextEditingController();
  int? _expenseTreasuryId;

  List<_InputRow> _inputRows = [];
  List<_OutputRow> _outputRows = [];
  final List<_ReentryRow> _reentryRows = [];

  bool _loadingRefData = true;
  bool _loadingRecipes = false;
  bool _submitting = false;
  String? _lastBatchNumber;

  @override
  void initState() {
    super.initState();
    _loadRefData();
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    _expenseCtrl.dispose();
    for (final r in _inputRows) {
      r._qtyCtrl.dispose();
    }
    for (final r in _reentryRows) {
      r.qtyCtrl.dispose();
    }
    super.dispose();
  }

  Future<void> _loadRefData() async {
    setState(() => _loadingRefData = true);
    try {
      final results = await Future.wait([
        _remote.fetchProductCategories(),
        _remote.fetchLabs(),
        _remote.fetchWarehouses(),
        _remote.fetchProducts(),
        _remote.fetchTreasuries(),
        _remote.fetchInProgressBatches(),
      ]);
      setState(() {
        _categories = results[0] as List<IdNameModel>;
        _labs = results[1] as List<IdNameModel>;
        _warehouses = (results[2] as List<SimpleWarehouseModel>)
            .where((w) => w.type == 'manufacturing')
            .toList();
        _allProducts = results[3] as List<SimpleProductModel>;
        _treasuries = results[4] as List<TreasuryModel>;
        _recentBatches = results[5] as List<ProductionBatchSummaryModel>;
        _loadingRefData = false;
      });
    } catch (_) {
      setState(() => _loadingRefData = false);
      if (mounted) AppSnackbar.showError(context, 'فشل تحميل بيانات الشاشة.');
    }
  }

  Future<void> _onCategoryChanged(int? categoryId) async {
    setState(() {
      _categoryId = categoryId;
      _selectedRecipe = null;
      _recipes = [];
      _inputRows = [];
      _outputRows = [];
    });
    if (categoryId == null) return;
    setState(() => _loadingRecipes = true);
    try {
      final recipes = await _remote.fetchRecipes(categoryId: categoryId);
      setState(() {
        _recipes = recipes;
        _loadingRecipes = false;
      });
    } catch (_) {
      setState(() => _loadingRecipes = false);
      if (mounted) AppSnackbar.showError(context, 'فشل تحميل الوصفات.');
    }
  }

  void _onRecipeSelected(RecipeModel recipe) {
    setState(() {
      _selectedRecipe = recipe;
      _inputRows = recipe.inputs.map((i) => _InputRow(i)).toList();
      _outputRows = recipe.outputs
          .map((o) => _OutputRow(o)..warehouseId = recipe.outputWarehouseId)
          .toList();
    });
  }

  void _addReentryRow() => setState(() => _reentryRows.add(_ReentryRow()));

  void _removeReentryRow(int idx) => setState(() {
        _reentryRows[idx].qtyCtrl.dispose();
        _reentryRows.removeAt(idx);
      });

  Future<void> _submit() async {
    if (_selectedRecipe == null) {
      AppSnackbar.showError(context, 'اختر وصفة أولاً');
      return;
    }
    final activeInputs = _inputRows
        .where((r) => r._qtyCtrl.text.isNotEmpty && (double.tryParse(r._qtyCtrl.text) ?? 0) > 0)
        .toList();
    if (activeInputs.isEmpty) {
      AppSnackbar.showError(context, 'أدخل كمية واحدة على الأقل للمكونات');
      return;
    }
    final overStock = activeInputs.where((r) =>
        r.recipeInput.inputType == 'raw_material' &&
        r.recipeInput.currentStock != null &&
        (double.tryParse(r._qtyCtrl.text) ?? 0) > r.recipeInput.currentStock!);
    if (overStock.isNotEmpty) {
      AppSnackbar.showError(
          context, 'مخزون غير كافٍ: ${overStock.map((r) => r.recipeInput.name).join('، ')}');
      return;
    }

    final activeReentry = _reentryRows
        .where((r) => r.productId != null && r.warehouseId != null && (double.tryParse(r.qtyCtrl.text) ?? 0) > 0)
        .toList();

    setState(() => _submitting = true);
    try {
      final expenseAmount = double.tryParse(_expenseCtrl.text) ?? 0;
      final batchNumber = await _remote.startProductionBatch(
        recipeId: _selectedRecipe!.id,
        categoryId: _categoryId,
        labId: _labId,
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        materials: activeInputs
            .map((r) => {
                  'input_type': r.recipeInput.inputType,
                  if (r.recipeInput.inputType == 'raw_material')
                    'raw_material_id': r.recipeInput.rawMaterialId
                  else
                    'product_id': r.recipeInput.productId,
                  'quantity_used': r._qtyCtrl.text,
                })
            .toList(),
        outputs: _outputRows
            .map((r) => {
                  'product_id': r.recipeOutput.productId,
                  'is_byproduct': r.recipeOutput.isByproduct,
                  if (r.warehouseId != null) 'warehouse_id': r.warehouseId,
                })
            .toList(),
        reentryMaterials: activeReentry
            .map((r) => {
                  'product_id': r.productId,
                  'warehouse_id': r.warehouseId,
                  'quantity_used': r.qtyCtrl.text,
                })
            .toList(),
        additionalExpense: expenseAmount > 0 ? expenseAmount : null,
        expenseTreasuryId: expenseAmount > 0 ? _expenseTreasuryId : null,
      );

      if (!mounted) return;
      setState(() {
        _lastBatchNumber = batchNumber;
        _submitting = false;
        _categoryId = null;
        _selectedRecipe = null;
        _recipes = [];
        _inputRows = [];
        _outputRows = [];
        _reentryRows.clear();
        _notesCtrl.clear();
        _expenseCtrl.clear();
        _expenseTreasuryId = null;
      });
      AppSnackbar.showSuccess(context, 'تم فتح التشغيلة: ${batchNumber ?? ''}');
      final batches = await _remote.fetchInProgressBatches();
      if (mounted) setState(() => _recentBatches = batches);
    } on DioException catch (e) {
      setState(() => _submitting = false);
      AppSnackbar.showError(
          context, e.response?.data?['message'] as String? ?? 'فشل فتح التشغيلة');
    } catch (_) {
      setState(() => _submitting = false);
      AppSnackbar.showError(context, 'حدث خطأ غير متوقع');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('بدء تشغيلة جديدة')),
      body: _loadingRefData
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadRefData,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_lastBatchNumber != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppTheme.secondary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppTheme.secondary.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle, color: AppTheme.secondary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'تم فتح التشغيلة: $_lastBatchNumber — الخامات خُصمت من المخزون.',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  Text('١. اختيار الوصفة', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<int>(
                    initialValue: _categoryId,
                    decoration: const InputDecoration(labelText: 'التصنيف'),
                    items: _categories
                        .map((c) => DropdownMenuItem(value: c.id, child: Text(c.name)))
                        .toList(),
                    onChanged: _onCategoryChanged,
                  ),
                  const SizedBox(height: 12),
                  if (_loadingRecipes) const Center(child: CircularProgressIndicator()),
                  if (!_loadingRecipes && _categoryId != null && _recipes.isEmpty)
                    const Text('لا توجد وصفات نشطة لهذا التصنيف.',
                        style: TextStyle(color: AppTheme.danger)),
                  if (_recipes.isNotEmpty)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _recipes
                          .map((r) => ChoiceChip(
                                label: Text(r.name),
                                selected: _selectedRecipe?.id == r.id,
                                onSelected: (_) => _onRecipeSelected(r),
                              ))
                          .toList(),
                    ),
                  if (_selectedRecipe != null) ...[
                    const SizedBox(height: 16),
                    DropdownButtonFormField<int>(
                      initialValue: _labId,
                      decoration: const InputDecoration(labelText: 'المعمل (اختياري)'),
                      items: _labs
                          .map((l) => DropdownMenuItem(value: l.id, child: Text(l.name)))
                          .toList(),
                      onChanged: (v) => setState(() => _labId = v),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _notesCtrl,
                      decoration: const InputDecoration(labelText: 'ملاحظات'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _expenseCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                          labelText: 'مصروفات إضافية للتشغيلة (اختياري)', hintText: '0.00'),
                      onChanged: (_) => setState(() {}),
                    ),
                    if ((double.tryParse(_expenseCtrl.text) ?? 0) > 0 && _treasuries.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      DropdownButtonFormField<int>(
                        initialValue: _expenseTreasuryId,
                        decoration: const InputDecoration(labelText: 'الخزينة'),
                        items: _treasuries
                            .map((t) => DropdownMenuItem(value: t.id, child: Text(t.name)))
                            .toList(),
                        onChanged: (v) => setState(() => _expenseTreasuryId = v),
                      ),
                    ],
                    const SizedBox(height: 20),
                    Text('٢. الخامات — الكميات المصروفة',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    const Text('ستُخصم فوراً من المخزون. اترك فارغاً للمكوّنات غير المستخدمة.',
                        style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                    const SizedBox(height: 8),
                    ..._inputRows.map((row) {
                      final qty = double.tryParse(row._qtyCtrl.text) ?? 0;
                      final warn = row.recipeInput.currentStock != null &&
                          qty > row.recipeInput.currentStock!;
                      return Card(
                        color: warn ? AppTheme.danger.withValues(alpha: 0.06) : AppTheme.cardBg,
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(row.recipeInput.name,
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                    if (row.recipeInput.currentStock != null)
                                      Text('المتاح: ${row.recipeInput.currentStock!.toStringAsFixed(2)} ${row.recipeInput.unit}',
                                          style: TextStyle(
                                              fontSize: 11,
                                              color: warn ? AppTheme.danger : AppTheme.secondary)),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 90,
                                child: TextField(
                                  controller: row._qtyCtrl,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  textAlign: TextAlign.center,
                                  onChanged: (_) => setState(() {}),
                                  decoration: const InputDecoration(isDense: true),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                    if (_selectedRecipe!.allowProductReentry) ...[
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('إعادة تشغيل منتجات تامة (اختياري)',
                              style: Theme.of(context).textTheme.titleMedium),
                          TextButton.icon(
                            onPressed: _addReentryRow,
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('إضافة'),
                          ),
                        ],
                      ),
                      ..._reentryRows.asMap().entries.map((entry) {
                        final idx = entry.key;
                        final row = entry.value;
                        return Card(
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Column(
                              children: [
                                DropdownButtonFormField<int>(
                                  initialValue: row.productId,
                                  decoration: const InputDecoration(labelText: 'المنتج', isDense: true),
                                  items: _allProducts
                                      .map((p) => DropdownMenuItem(value: p.id, child: Text(p.name)))
                                      .toList(),
                                  onChanged: (v) => setState(() => row.productId = v),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(
                                      child: DropdownButtonFormField<int>(
                                        initialValue: row.warehouseId,
                                        decoration:
                                            const InputDecoration(labelText: 'المخزن', isDense: true),
                                        items: _warehouses
                                            .map((w) => DropdownMenuItem(value: w.id, child: Text(w.name)))
                                            .toList(),
                                        onChanged: (v) => setState(() => row.warehouseId = v),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    SizedBox(
                                      width: 80,
                                      child: TextField(
                                        controller: row.qtyCtrl,
                                        keyboardType:
                                            const TextInputType.numberWithOptions(decimal: true),
                                        textAlign: TextAlign.center,
                                        decoration: const InputDecoration(labelText: 'كمية', isDense: true),
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline, color: AppTheme.danger),
                                      onPressed: () => _removeReentryRow(idx),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                    ],
                    const SizedBox(height: 20),
                    Text('٣. النواتج — تحديد المخزن',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    const Text('الكميات الفعلية تُسجَّل لاحقاً في «استلام إنتاج تام»',
                        style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                    const SizedBox(height: 8),
                    ..._outputRows.map((row) => Card(
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(row.recipeOutput.name,
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                      if (row.recipeOutput.isByproduct)
                                        const Text('ثانوي',
                                            style: TextStyle(fontSize: 10, color: AppTheme.accent)),
                                    ],
                                  ),
                                ),
                                SizedBox(
                                  width: 160,
                                  child: DropdownButtonFormField<int>(
                                    initialValue: row.warehouseId,
                                    decoration: const InputDecoration(labelText: 'المخزن', isDense: true),
                                    items: _warehouses
                                        .map((w) => DropdownMenuItem(value: w.id, child: Text(w.name)))
                                        .toList(),
                                    onChanged: (v) => setState(() => row.warehouseId = v),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )),
                    const SizedBox(height: 24),
                    SizedBox(
                      height: 50,
                      child: ElevatedButton.icon(
                        onPressed: _submitting ? null : _submit,
                        icon: _submitting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.science_outlined),
                        label: Text(_submitting ? 'جارٍ فتح التشغيلة...' : 'فتح التشغيلة وصرف الخامات'),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  Text('التشغيلات الجارية', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  if (_recentBatches.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text('لا توجد تشغيلات جارية', style: TextStyle(color: AppTheme.textMuted)),
                    )
                  else
                    ..._recentBatches.map((b) => Card(
                          child: ListTile(
                            leading: const Icon(Icons.hourglass_top_outlined, color: AppTheme.accent),
                            title: Text(b.batchNumber ?? '#${b.id}',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            subtitle: Text(b.recipeName ?? '—', style: const TextStyle(fontSize: 11)),
                          ),
                        )),
                ],
              ),
            ),
    );
  }
}
