import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/theme.dart';

class ThemeCubit extends Cubit<ThemeData> {
  ThemeCubit() : super(AppTheme.darkTheme) {
    _loadTheme();
  }

  bool _isDark = true;
  bool get isDark => _isDark;

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    _isDark = prefs.getBool('is_dark_theme') ?? true;
    emit(_isDark ? AppTheme.darkTheme : AppTheme.lightTheme);
  }

  Future<void> toggleTheme() async {
    _isDark = !_isDark;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_dark_theme', _isDark);
    emit(_isDark ? AppTheme.darkTheme : AppTheme.lightTheme);
  }
}
