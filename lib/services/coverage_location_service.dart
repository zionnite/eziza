import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/location.dart';

/// Fetches admin-managed State → City → Area hierarchy from the `locations` table.
class CoverageLocationService {
  static final _db = Supabase.instance.client;

  static List<String>?              _statesCache;
  static final _citiesCache = <String, List<String>>{};
  static final _areasCache  = <String, List<Location>>{};

  static Future<List<String>> fetchStates() async {
    if (_statesCache != null) return _statesCache!;
    final data = await _db
        .from('locations')
        .select('state')
        .eq('active', true)
        .order('state');
    final states = (data as List)
        .map((e) => e['state'] as String)
        .toSet()
        .toList()
      ..sort();
    return _statesCache = states;
  }

  static Future<List<String>> fetchCities(String state) async {
    if (_citiesCache.containsKey(state)) return _citiesCache[state]!;
    final data = await _db
        .from('locations')
        .select('city')
        .eq('state', state)
        .eq('active', true)
        .order('city');
    final cities = (data as List)
        .map((e) => e['city'] as String)
        .toSet()
        .toList()
      ..sort();
    return _citiesCache[state] = cities;
  }

  static Future<List<Location>> fetchAreas(String state, String city) async {
    final key = '$state|$city';
    if (_areasCache.containsKey(key)) return _areasCache[key]!;
    final data = await _db
        .from('locations')
        .select()
        .eq('state', state)
        .eq('city', city)
        .eq('active', true)
        .order('area');
    final areas = (data as List).map((e) => Location.fromJson(e)).toList();
    return _areasCache[key] = areas;
  }

  static Future<List<Location>> fetchByIds(List<int> ids) async {
    if (ids.isEmpty) return [];
    final data = await _db
        .from('locations')
        .select()
        .inFilter('id', ids);
    return (data as List).map((e) => Location.fromJson(e)).toList();
  }

  static void clearCache() {
    _statesCache = null;
    _citiesCache.clear();
    _areasCache.clear();
  }
}
