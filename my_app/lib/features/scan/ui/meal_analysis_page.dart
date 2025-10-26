// lib/features/scan/ui/meal_analysis_page.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../data/meal_analysis_service.dart';
import '../data/simple_meal_analysis_service.dart';
import '../../analytics/data/analytics_service.dart';
import '../../services/image_service.dart';

class MealAnalysisPage extends StatefulWidget {
  final File photo;
  const MealAnalysisPage({super.key, required this.photo});

  @override
  State<MealAnalysisPage> createState() => _MealAnalysisPageState();
}

class _MealAnalysisPageState extends State<MealAnalysisPage> {
  late File _photo;
  bool _loading = false;
  String? _error;
  MealAnalysis? _mealAnalysis;

  @override
  void initState() {
    super.initState();
    _photo = widget.photo;
    _analyzeMeal();
  }

  Future<void> _analyzeMeal() async {
    setState(() {
      _loading = true;
      _error = null;
      _mealAnalysis = null;
    });

    try {
      print('Starting meal analysis...');
      // Use simple service for now to test basic functionality
      final analysis = await SimpleMealAnalysisService.instance.analyzeMeal(_photo);
      print('Meal analysis completed successfully');
      
      if (!mounted) return;
      
      setState(() {
        _mealAnalysis = analysis;
        _loading = false;
      });
    } catch (e) {
      print('Meal analysis failed: $e');
      if (!mounted) return;
      
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _retakePhoto() async {
    if (!mounted) return;
    Navigator.of(context).pop('retake');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Meal Analysis'),
        actions: [
          IconButton(
            icon: const Icon(Icons.camera_alt),
            onPressed: _loading ? null : _retakePhoto,
            tooltip: 'Retake Photo',
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Analyzing meal...'),
                  SizedBox(height: 8),
                  Text('This may take a few seconds', style: TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            )
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
                        const SizedBox(height: 16),
                        Text('Analysis Failed', style: theme.textTheme.headlineSmall),
                        const SizedBox(height: 8),
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: _retakePhoto,
                          icon: const Icon(Icons.camera_alt),
                          label: const Text('Take New Photo'),
                        ),
                      ],
                    ),
                  ),
                )
              : _mealAnalysis != null
                  ? _buildMealAnalysis(theme)
                  : const Center(child: Text('No analysis available')),
      floatingActionButton: _mealAnalysis != null 
          ? FloatingActionButton.extended(
              onPressed: _saveMealToFoodLog,
              icon: const Icon(Icons.save),
              label: const Text('Save Meal'),
              backgroundColor: Colors.green,
            )
          : null,
    );
  }

  Future<void> _saveMealToFoodLog() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _mealAnalysis == null) return;

    try {
      // Show loading state
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 16),
              Text('Saving meal and uploading image...'),
            ],
          ),
          duration: Duration(seconds: 5),
        ),
      );

      // Upload image first
      String? imageUrl;
      try {
        imageUrl = await ImageService.instance.uploadMealImage(_photo);
      } catch (e) {
        print('Image upload failed: $e');
        // Continue without image if upload fails
      }

      // Add image URL to meal data
      final mealData = _mealAnalysis!.toJson();
      if (imageUrl != null) {
        mealData['image_url'] = imageUrl;
      }

      await AnalyticsService.instance.saveMealToFoodLog(mealData, user.uid);
      
      if (!mounted) return;
      
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(imageUrl != null 
              ? 'Meal and image saved successfully!' 
              : 'Meal saved successfully! (Image upload failed)'),
          backgroundColor: Colors.green,
        ),
      );
      
      // Navigate back to home
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      if (!mounted) return;
      
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save meal: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildMealAnalysis(ThemeData theme) {
    final analysis = _mealAnalysis!;
    
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100), // Extra bottom padding for FAB
      children: [
        // Photo
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxHeight: 300,
            ),
            child: Image.file(
              _photo,
              width: double.infinity,
              fit: BoxFit.contain,
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Total Nutrition Summary
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Total Nutrition', style: theme.textTheme.titleLarge),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _NutritionTile(
                        label: 'Calories',
                        value: analysis.totalCalories,
                        unit: 'kcal',
                        color: Colors.orange,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _NutritionTile(
                        label: 'Protein',
                        value: analysis.totalProtein,
                        unit: 'g',
                        color: Colors.blue,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _NutritionTile(
                        label: 'Carbs',
                        value: analysis.totalCarbs,
                        unit: 'g',
                        color: Colors.green,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _NutritionTile(
                        label: 'Fat',
                        value: analysis.totalFat,
                        unit: 'g',
                        color: Colors.red,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Ingredients Breakdown
        Text('Ingredients', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        ...analysis.ingredients.map((ingredient) => _buildIngredientCard(ingredient, theme)),
      ],
    );
  }

  Widget _buildIngredientCard(IngredientNutrition ingredient, ThemeData theme) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.brightness == Brightness.dark
            ? Colors.grey[850]
            : Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  ingredient.name,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
              ),
              Text(
                '${ingredient.portionGrams.toStringAsFixed(0)}g',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                '${ingredient.calories.toStringAsFixed(0)} kcal',
                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange, fontSize: 13),
              ),
              const SizedBox(width: 8),
              Text('P: ${ingredient.protein.toStringAsFixed(0)}g',
                  style: const TextStyle(fontSize: 13, color: Colors.blue)),
              const SizedBox(width: 8),
              Text('C: ${ingredient.carbs.toStringAsFixed(0)}g',
                  style: const TextStyle(fontSize: 13, color: Colors.green)),
              const SizedBox(width: 8),
              Text('F: ${ingredient.fat.toStringAsFixed(0)}g',
                  style: const TextStyle(fontSize: 13, color: Colors.red)),
            ],
          ),
          if (ingredient.usdaName != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.green[200]!),
              ),
              child: Text(
                'USDA: ${ingredient.usdaName}',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.green[700],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _NutritionTile extends StatelessWidget {
  final String label;
  final double value;
  final String unit;
  final Color color;

  const _NutritionTile({
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${value.toStringAsFixed(0)} $unit',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

