import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import '../models/audio_sample.dart';

class SampleProvider with ChangeNotifier {
  Map<String, List<AudioSample>> _pageSamples = {}; // Each page has its own list
  List<AudioSample> _filteredSamples = [];
  String _currentCategory = 'All';
  String _searchQuery = '';
  int _currentPage = 0;
  final int _samplesPerPage = 24; // 6x4 grid layout
  List<String> _availablePages = ['A']; // Start with only page A
  Map<String, String> _pageLabels = {}; // Custom labels for pages
  
  // Clear all samples and reset to a single empty page (A)
  void clearAllSamples() {
    _pageSamples = {'A': []};
    _filteredSamples = [];
    _currentCategory = 'All';
    _searchQuery = '';
    _currentPage = 0;
    _availablePages = ['A'];
    _pageLabels = {};
    notifyListeners();
  }
  
  // Setter to track page changes
  set currentPage(int page) {
    _currentPage = page;
  }
  
  List<AudioSample> get samples {
    // Flatten all page samples for backward compatibility
    List<AudioSample> allSamples = [];
    for (String page in _availablePages) {
      allSamples.addAll(_pageSamples[page] ?? []);
    }
    return allSamples;
  }
  
  List<AudioSample> get filteredSamples => _filteredSamples;
  String get currentCategory => _currentCategory;
  String get searchQuery => _searchQuery;
  int get currentPage => _currentPage;
  int get samplesPerPage => _samplesPerPage;
  int get totalPages => _availablePages.length;
  List<String> get availablePages => _availablePages;
  int get totalAvailablePages => _availablePages.length;
  Map<String, String> get pageLabels => _pageLabels;
  
  List<String> get categories {
    final categories = samples.map((s) => s.category).toSet().toList();
    categories.sort();
    return ['All', ...categories];
  }
  
  List<AudioSample> get currentPageSamples {
    final currentPageLetter = _availablePages[_currentPage];
    final pageSamples = _pageSamples[currentPageLetter] ?? [];
    
    return pageSamples;
  }

  // Get a sample by its ID
  AudioSample? getSampleById(String id) {
    try {
      for (String page in _availablePages) {
        final pageSamples = _pageSamples[page] ?? [];
        final sample = pageSamples.firstWhere((sample) => sample.id == id);
        if (sample != null) return sample;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  SampleProvider() {
    // clearAllSamples(); // Always start with a single empty page
    _initializeProvider();
  }

  // Initialize the provider asynchronously
  Future<void> _initializeProvider() async {
    // await _clearSavedSamples(); // Remove saved samples from persistent storage
    await _loadSamples();
  }

  // Clear saved samples from SharedPreferences
  Future<void> _clearSavedSamples() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('audio_samples');
  }

  // Get the label for a page, or empty string if not set
  String getLabelForPage(String letter) {
    return _pageLabels[letter] ?? '';
  }

  // Set the label for a page
  void setLabelForPage(String letter, String label) {
    _pageLabels[letter] = label;
    notifyListeners();
  }

  // Add a new page dynamically
  void addNewPage() {
    if (_availablePages.length < 26) { // Limit to A-Z
      final nextPageLetter = String.fromCharCode(65 + _availablePages.length); // A=65, B=66, etc.
      _availablePages.add(nextPageLetter);
      _pageLabels[nextPageLetter] = '';
      _pageSamples[nextPageLetter] = []; // Initialize empty list for new page
      notifyListeners();
    }
  }

  // Add a blank sample that can be filled with audio later
  Future<void> addBlankSample() async {
    final blankSample = AudioSample(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: 'New Sample',
      category: 'General',
      filePath: '', // Empty path for blank sample
      duration: Duration.zero,
      isBlank: true, // Mark as blank
      createdAt: DateTime.now(),
      lastModified: DateTime.now(),
    );
    
    final currentPageLetter = _availablePages[_currentPage];
    
    // Initialize page if it doesnt exist
    if (!_pageSamples.containsKey(currentPageLetter)) {
      _pageSamples[currentPageLetter] = [];
    }
    
    // Add to the current pages list
    _pageSamples[currentPageLetter]!.add(blankSample);
    
    // Apply filters and save
    _applyFilters();
    await _saveSamples();
    notifyListeners();
    
  }

  // Update a blank sample with actual audio data
  Future<void> updateBlankSample(String sampleId, String filePath, String name, Duration duration, {List<double>? waveformData}) async {
    for (String page in _availablePages) {
      final pageSamples = _pageSamples[page] ?? [];
      final index = pageSamples.indexWhere((s) => s.id == sampleId);
      if (index != -1) {
        pageSamples[index] = pageSamples[index].copyWith(
          name: name,
          filePath: filePath,
          duration: duration,
          isBlank: false, // No longer blank
          lastModified: DateTime.now(),
          waveformData: waveformData,
        );
        await _saveSamples();
        _applyFilters();
        notifyListeners();
        return;
      }
    }
  }

  // Get page index by letter
  int getPageIndexByLetter(String letter) {
    return _availablePages.indexOf(letter);
  }

  // Set current page by letter
  void setPageByLetter(String letter) {
    final pageIndex = getPageIndexByLetter(letter);
    if (pageIndex != -1) {
      _currentPage = pageIndex;
      notifyListeners();
    }
  }

  // Check if a page is the current page
  bool isCurrentPage(String letter) {
    return _availablePages[_currentPage] == letter;
  }

  // Get current page letter
  String getCurrentPageLetter() {
    return _availablePages[_currentPage];
  }

  // Delete a page by letter
  void deletePage(String letter) {
    // Don't allow deleting the last remaining page
    if (_availablePages.length <= 1) {
      return;
    }
    
    final pageIndex = getPageIndexByLetter(letter);
    if (pageIndex != -1) {
      // Remove the page
      _availablePages.removeAt(pageIndex);
      _pageSamples.remove(letter);
      _pageLabels.remove(letter);
      
      // Adjust current page if necessary
      if (_currentPage >= _availablePages.length) {
        _currentPage = _availablePages.length - 1;
      }
      
      notifyListeners();
    }
  }

  // Check if a page can be deleted (not the last remaining page)
  bool canDeletePage(String letter) {
    return _availablePages.length > 1;
  }

  Future<void> _loadSamples() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final samplesJson = prefs.getStringList('audio_samples') ?? [];
      
      // Convert from old format to new page-based format
      final allSamples = samplesJson
          .map((json) => AudioSample.fromJson(jsonDecode(json)))
          .toList();
      
      // Initialize page A with all existing samples (for backward compatibility)
      _pageSamples['A'] = allSamples;
      
      _applyFilters();
      notifyListeners();
    } catch (e) {
      // Initialize empty page A if loading fails
      _pageSamples['A'] = [];
    }
  }

  Future<void> _saveSamples() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final samplesJson = samples
          .map((sample) => jsonEncode(sample.toJson()))
          .toList();
      
      await prefs.setStringList('audio_samples', samplesJson);
    } catch (e) {
    }
  }

  void _applyFilters() {
    
    // Get all samples from all pages that match the filters
    _filteredSamples = samples.where((sample) {
      final matchesCategory = _currentCategory == 'All' || sample.category == _currentCategory;
      final matchesSearch = _searchQuery.isEmpty || 
          sample.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          (sample.notes?.toLowerCase().contains(_searchQuery.toLowerCase()) ?? false);
      
      return matchesCategory && matchesSearch;
    }).toList();
    
  }

  Future<AudioSample> addSampleShell({
    required String name,
    required String category,
    required String filePath,
    required Duration duration,
    String? notes,
  }) async {
    final now = DateTime.now();
    final sample = AudioSample(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      filePath: filePath,
      duration: duration,
      category: category,
      notes: notes,
      createdAt: now,
      lastModified: now,
      isBlank: false,
      waveformData: null,
      isWaveformLoading: true,
    );
    await addSample(sample);
    return sample;
  }

  Future<void> setSampleWaveform(String sampleId, List<double> waveformData) async {
    for (final page in _availablePages) {
      final pageSamples = _pageSamples[page] ?? [];
      final index = pageSamples.indexWhere((s) => s.id == sampleId);
      if (index != -1) {
        pageSamples[index] = pageSamples[index].copyWith(
          waveformData: waveformData,
          isWaveformLoading: false,
          lastModified: DateTime.now(),
        );
        await _saveSamples();
        _applyFilters();
        notifyListeners();
        return;
      }
    }
  }

  Future<void> addSample(AudioSample sample) async {
    final currentPageLetter = _availablePages[_currentPage];
    if (!_pageSamples.containsKey(currentPageLetter)) {
      _pageSamples[currentPageLetter] = [];
    }
    _pageSamples[currentPageLetter]!.add(sample);
    await _saveSamples();
    _applyFilters();
    notifyListeners();
  }

  Future<void> updateSample(AudioSample updatedSample) async {
    for (String page in _availablePages) {
      final pageSamples = _pageSamples[page] ?? [];
      final index = pageSamples.indexWhere((s) => s.id == updatedSample.id);
      if (index != -1) {
        pageSamples[index] = updatedSample.copyWith(
          lastModified: DateTime.now(),
        );
        await _saveSamples();
        _applyFilters();
        notifyListeners();
        return;
      }
    }
  }

  Future<void> deleteSample(String sampleId) async {
    for (String page in _availablePages) {
      final pageSamples = _pageSamples[page] ?? [];
      final initialLength = pageSamples.length;
      pageSamples.removeWhere((s) => s.id == sampleId);
      if (pageSamples.length < initialLength) {
        await _saveSamples();
        _applyFilters();
        notifyListeners();
        return;
      }
    }
  }

  void setCategory(String category) {
    _currentCategory = category;
    _applyFilters();
    notifyListeners();
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    _applyFilters();
    notifyListeners();
  }

  void setPage(int page) {
    if (page >= 0 && page < totalPages) {
      _currentPage = page;
      notifyListeners();
    }
  }

  void nextPage() {
    if (_currentPage < totalPages - 1) {
      _currentPage++;
      notifyListeners();
    }
  }

  void previousPage() {
    if (_currentPage > 0) {
      _currentPage--;
      notifyListeners();
    }
  }

  List<AudioSample> getFavorites() {
    return samples.where((s) => s.isFavorite).toList();
  }

  List<AudioSample> getSamplesByCategory(String category) {
    return samples.where((s) => s.category == category).toList();
  }

  Future<void> toggleFavorite(String sampleId) async {
    for (String page in _availablePages) {
      final pageSamples = _pageSamples[page] ?? [];
      final index = pageSamples.indexWhere((s) => s.id == sampleId);
      if (index != -1) {
        pageSamples[index] = pageSamples[index].copyWith(
          isFavorite: !pageSamples[index].isFavorite,
          lastModified: DateTime.now(),
        );
        await _saveSamples();
        _applyFilters();
        notifyListeners();
        return;
      }
    }
  }

  Future<void> duplicateSample(String sampleId) async {
    for (String page in _availablePages) {
      final pageSamples = _pageSamples[page] ?? [];
      final original = pageSamples.firstWhere((s) => s.id == sampleId);
      if (original != null) {
        final duplicated = original.copyWith(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          name: '${original.name} (Copy)',
          createdAt: DateTime.now(),
          lastModified: DateTime.now(),
        );
        
        await addSample(duplicated);
        return;
      }
    }
  }

  // Update the custom color of a sample
  Future<void> updateSampleColor(String sampleId, int color) async {
    for (String page in _availablePages) {
      final pageSamples = _pageSamples[page] ?? [];
      final index = pageSamples.indexWhere((s) => s.id == sampleId);
      if (index != -1) {
        pageSamples[index] = pageSamples[index].copyWith(
          customColor: color,
          lastModified: DateTime.now(),
        );
        await _saveSamples();
        _applyFilters();
        notifyListeners();
        return;
      }
    }
  }

  // Reorder samples within the current page
  Future<void> reorderSamples(int oldIndex, int newIndex) async {
    final currentPageLetter = _availablePages[_currentPage];
    final pageSamples = _pageSamples[currentPageLetter] ?? [];
    
    if (oldIndex >= 0 && oldIndex < pageSamples.length &&
        newIndex >= 0 && newIndex < pageSamples.length) {
      
      // Get the sample to move
      final sampleToMove = pageSamples[oldIndex];
      
      // Remove from old position and insert at new position
      pageSamples.removeAt(oldIndex);
      pageSamples.insert(newIndex, sampleToMove);
      
      await _saveSamples();
      notifyListeners();
    }
  }

  Future<void> exportSamples() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/samples_export.json');
      final samplesJson = samples.map((s) => s.toJson()).toList();
      await file.writeAsString(jsonEncode(samplesJson));
    } catch (e) {
    }
  }

  Future<void> importSamples(String jsonData) async {
    try {
      final List<dynamic> samplesJson = jsonDecode(jsonData);
      final importedSamples = samplesJson
          .map((json) => AudioSample.fromJson(json))
          .toList();
      
      for (final sample in importedSamples) {
        // Generate new ID to avoid conflicts
        final newSample = sample.copyWith(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          createdAt: DateTime.now(),
          lastModified: DateTime.now(),
        );
        await addSample(newSample);
      }
    } catch (e) {
    }
  }

  /// Regenerate waveform data for all samples to fix mirroring issues
  Future<void> regenerateAllWaveformData() async {
    try {
      // Import AudioProvider to access waveform generation
      // Note: This creates a circular dependency, so we'll need to handle this differently
      // For now, we'll just mark samples as needing waveform regeneration
      for (String page in _availablePages) {
        final pageSamples = _pageSamples[page] ?? [];
        for (int i = 0; i < pageSamples.length; i++) {
          final sample = pageSamples[i];
          if (!sample.isBlank && sample.waveformData != null) {
            // Clear existing waveform data to force regeneration
            pageSamples[i] = sample.copyWith(
              waveformData: null,
              lastModified: DateTime.now(),
            );
          }
        }
      }
      await _saveSamples();
      notifyListeners();
    } catch (e) {
      // Handle error silently
    }
  }
}

