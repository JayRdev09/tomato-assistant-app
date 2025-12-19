import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'dart:convert';

class ResultsScreen extends StatefulWidget {
  const ResultsScreen({super.key});

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  bool _isLoading = false;
  String? _errorMessage;
  
  // Store analyses
  Map<String, dynamic>? _newestAnalysis;
  List<Map<String, dynamic>> _previousAnalyses = [];
  List<Map<String, dynamic>> _newestBatchResults = [];
  
  // Soil data - now only used for analysis details
  Map<String, dynamic>? _soilData;
  
  // Track data hashes for change detection
  String? _previousAnalysesHash;
  String? _newestAnalysisHash;
  String? _soilDataHash;

  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  // Helper method to create a hash for data comparison
  String _createDataHash(List<Map<String, dynamic>> data) {
    try {
      final jsonString = json.encode(data);
      return _generateSimpleHash(jsonString);
    } catch (e) {
      return DateTime.now().millisecondsSinceEpoch.toString();
    }
  }

  String _generateSimpleHash(String input) {
    // Simple hash function for change detection
    var hash = 0;
    for (var i = 0; i < input.length; i++) {
      final char = input.codeUnitAt(i);
      hash = ((hash << 5) - hash) + char;
      hash = hash & hash; // Convert to 32bit integer
    }
    return hash.toString();
  }

  Future<void> _loadAllData({bool forceRefresh = false}) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Load soil data (now only for analysis details)
      await _loadSoilData(forceRefresh: forceRefresh);
      
      // Load analyses
      await _loadAnalyses(forceRefresh: forceRefresh);
      
      // Show success message if force refresh
      if (forceRefresh) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Data refreshed successfully'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
      
    } catch (e) {
      print('❌ Error loading all data: $e');
      setState(() {
        _errorMessage = 'Failed to load data: $e';
      });
      
      if (forceRefresh) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Refresh failed: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadSoilData({bool forceRefresh = false}) async {
    try {
      final soilStatus = await ApiService.getSoilStatus();
      
      if (soilStatus.isNotEmpty) {
        // Create hash for the soil data
        final currentHash = _createDataHash([soilStatus]);
        
        // Only update if hash changed or force refresh
        if (forceRefresh || _soilDataHash != currentHash) {
          setState(() {
            _soilData = soilStatus;
            _soilDataHash = currentHash;
          });
          print('✅ Soil data loaded for analysis details (${forceRefresh ? 'forced' : 'changed'})');
        }
      }
    } catch (e) {
      print('❌ Error loading soil data: $e');
      // Don't set error message for soil data failure - it's optional
    }
  }

  Future<void> _loadAnalyses({bool forceRefresh = false}) async {
    try {
      final batchHistory = await ApiService.getBatchHistory();
      
      if (batchHistory.isNotEmpty) {
        // Sort by date (newest first)
        batchHistory.sort((a, b) {
          final dateA = DateTime.parse(a['date']?.toString() ?? '1970-01-01');
          final dateB = DateTime.parse(b['date']?.toString() ?? '1970-01-01');
          return dateB.compareTo(dateA);
        });
        
        // Create hash for previous analyses
        final currentHash = _createDataHash(batchHistory);
        
        // Only update if hash changed or force refresh
        if (forceRefresh || _previousAnalysesHash != currentHash) {
          // Get newest batch
          final newestBatch = batchHistory.first;
          final newestBatchId = newestBatch['batch_id'] as String?;
          
          if (newestBatchId != null) {
            await _loadBatchResults(newestBatchId, forceRefresh: forceRefresh);
            
            // Set previous analyses (excluding newest)
            setState(() {
              _previousAnalyses = batchHistory.sublist(1).toList();
              _previousAnalysesHash = currentHash;
            });
            
            return;
          }
        } else {
          print('ℹ️ Analyses unchanged, skipping reload');
        }
      }
      
      await _tryAlternativeBatchLoading(forceRefresh: forceRefresh);
      
    } catch (e) {
      print('❌ Error loading analyses: $e');
      setState(() {
        _errorMessage = 'Failed to load analyses: $e';
      });
    }
  }

  Future<void> _tryAlternativeBatchLoading({bool forceRefresh = false}) async {
    try {
      final allHistory = await ApiService.getAnalysisHistory(limit: 100);
      
      final batchAnalyses = allHistory.where((item) => 
        item['batch_timestamp'] != null && 
        item['batch_timestamp'].toString().isNotEmpty
      ).toList();
      
      if (batchAnalyses.isEmpty) {
        print('⚠️ No batch analyses found');
        // Clear data if no analyses found (possible deletion case)
        if (_newestAnalysis != null || _previousAnalyses.isNotEmpty) {
          setState(() {
            _newestAnalysis = null;
            _newestBatchResults = [];
            _previousAnalyses = [];
            _newestAnalysisHash = null;
            _previousAnalysesHash = null;
          });
        }
        return;
      }
      
      final batchGroups = <String, Map<String, dynamic>>{};
      
      for (final analysis in batchAnalyses) {
        final batchId = analysis['batch_timestamp'] as String;
        if (!batchGroups.containsKey(batchId)) {
          batchGroups[batchId] = {
            'batch_id': batchId,
            'total': 0,
            'healthy_count': 0,
            'unhealthy_count': 0,
            'date': analysis['date_predicted'],
            'mode': analysis['mode'] ?? 'batch_image_only',
          };
        }
        
        batchGroups[batchId]!['total'] = (batchGroups[batchId]!['total'] as int) + 1;
        
        if (analysis['overall_health'] == 'Healthy' || 
            analysis['health_status'] == 'Healthy') {
          batchGroups[batchId]!['healthy_count'] = (batchGroups[batchId]!['healthy_count'] as int) + 1;
        } else {
          batchGroups[batchId]!['unhealthy_count'] = (batchGroups[batchId]!['unhealthy_count'] as int) + 1;
        }
      }
      
      final batchesList = batchGroups.values.toList()
        ..sort((a, b) => (b['date'] as String).compareTo(a['date'] as String));
      
      if (batchesList.isNotEmpty) {
        final newestBatch = batchesList.first;
        final newestBatchId = newestBatch['batch_id'] as String;
        await _loadBatchResults(newestBatchId, forceRefresh: forceRefresh);
        
        setState(() {
          _previousAnalyses = batchesList.sublist(1).toList();
        });
      } else if (_newestAnalysis != null) {
        // Clear data if batches disappeared
        setState(() {
          _newestAnalysis = null;
          _newestBatchResults = [];
          _previousAnalyses = [];
          _newestAnalysisHash = null;
          _previousAnalysesHash = null;
        });
      }
      
    } catch (e) {
      print('❌ Alternative batch loading failed: $e');
      throw Exception('Failed to find analyses');
    }
  }

  Future<void> _loadBatchResults(String batchId, {bool forceRefresh = false}) async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
      
      print('🔍 Loading batch results for ID: $batchId');
      
      final batchDetails = await ApiService.getBatchDetails(batchId);
      
      // DEBUG: Print the structure of batchDetails
      print('📦 Batch details structure:');
      print('Keys: ${batchDetails.keys}');
      
      if (batchDetails['analyses'] == null || batchDetails['analyses'].isEmpty) {
        print('⚠️ No analyses data found in batch');
        
        // Clear newest analysis if batch no longer exists
        if (_newestAnalysis != null && _newestAnalysis!['batch_id'] == batchId) {
          setState(() {
            _newestAnalysis = null;
            _newestBatchResults = [];
            _newestAnalysisHash = null;
          });
        }
        
        throw Exception('No analyses data in batch');
      }
      
      final analyses = List<Map<String, dynamic>>.from(batchDetails['analyses']);
      
      // Create hash for the analyses
      final currentHash = _createDataHash(analyses);
      
      // Check if data has changed
      if (forceRefresh || _newestAnalysisHash != currentHash) {
        
        // DEBUG: Print first analysis structure
        if (analyses.isNotEmpty) {
          print('🔍 First analysis structure:');
          print('Keys: ${analyses.first.keys}');
          print('Values: ${analyses.first}');
        }
        
        // Calculate statistics with better data extraction
        final healthyCount = analyses.where((a) {
          final overallHealth = a['overall_health'] as String? ?? '';
          final healthStatus = a['health_status'] as String? ?? '';
          return overallHealth.toLowerCase().contains('healthy') || 
                 healthStatus.toLowerCase().contains('healthy');
        }).length;
        
        final unhealthyCount = analyses.length - healthyCount;
        final healthRate = analyses.isNotEmpty ? (healthyCount / analyses.length * 100).round() : 0;
        
        // Create newest analysis with all available data
        final newestAnalysis = {
          'batch_id': batchId,
          'total': analyses.length,
          'healthy_count': healthyCount,
          'unhealthy_count': unhealthyCount,
          'health_rate': healthRate,
          'date': analyses.first['date_predicted'] ?? 
                  analyses.first['timestamp'] ?? 
                  DateTime.now().toIso8601String(),
          'mode': batchDetails['mode'] ?? 'batch_image_only',
          'timestamp': DateTime.now().toIso8601String(),
        };
        
        setState(() {
          _newestAnalysis = newestAnalysis;
          _newestBatchResults = analyses;
          _newestAnalysisHash = currentHash;
        });
        
        print('✅ Newest batch loaded: ${analyses.length} analyses (${forceRefresh ? 'forced' : 'changed'})');
        print('📊 Summary: $healthyCount healthy, $unhealthyCount unhealthy');
        
      } else {
        print('ℹ️ Batch results unchanged, skipping reload');
      }
      
    } catch (e) {
      print('❌ Error loading batch results: $e');
      setState(() {
        _errorMessage = 'Failed to load analysis results: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _runNewBatchAnalysis() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await ApiService.performBatchAnalysis();
      
      final batchInfo = result['batch_info'];
      var batchId = batchInfo?['batch_timestamp'] as String?;
      
      print('📊 New batch analysis completed, batch ID: $batchId');
      
      if (batchId != null) {
        await Future.delayed(const Duration(seconds: 2));
        
        // Force refresh all data
        await _loadAllData(forceRefresh: true);
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('New analysis completed! ${batchInfo['analyzed_images']} images processed'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        // Force refresh all data
        await _loadAllData(forceRefresh: true);
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Analysis completed! Latest results loaded.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('❌ Batch analysis error: $e');
      setState(() {
        _errorMessage = 'Analysis failed: $e';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Analysis failed: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _checkDataStatus() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      final status = await ApiService.checkDataStatus();

      final canAnalyzeBatch = status['can_analyze_batch'] as bool? ?? false;
      final soilData = status['soil_data'] as Map<String, dynamic>? ?? {};
      final availableImages = status['available_images'] as Map<String, dynamic>? ?? {};

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Data Status'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildStatusRow('Soil Data', soilData),
              const SizedBox(height: 8),
              _buildBatchStatusRow('Plant Images', availableImages),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: canAnalyzeBatch ? Colors.green[50] : Colors.red[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  status['requirements']?['message'] as String? ??
                      'Checking data availability...',
                  style: TextStyle(
                    color: canAnalyzeBatch ? Colors.green : Colors.red,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
            if (canAnalyzeBatch)
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  _runNewBatchAnalysis();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purple,
                ),
                child: const Text('Run Analysis'),
              ),
          ],
        ),
      );
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to check data status: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Widget _buildStatusRow(String title, Map<String, dynamic> data) {
    final exists = data['exists'] as bool? ?? false;
    final isFresh = data['is_fresh'] as bool? ?? false;
    final ageHours = data['age_hours'] as double?;

    IconData icon;
    Color color;

    if (!exists) {
      icon = Icons.error;
      color = Colors.red;
    } else if (!isFresh) {
      icon = Icons.warning;
      color = Colors.orange;
    } else {
      icon = Icons.check_circle;
      color = Colors.green;
    }

    String statusText;
    if (!exists) {
      statusText = 'Missing';
    } else if (!isFresh) {
      statusText = 'Available (${ageHours?.toStringAsFixed(1) ?? 'N/A'}h old)';
    } else {
      statusText = 'Fresh (${ageHours?.toStringAsFixed(1) ?? 'N/A'}h)';
    }

    return Row(
      children: [
        Icon(icon, color: color),
        const SizedBox(width: 8),
        Text(title),
        const Spacer(),
        Text(
          statusText,
          style: TextStyle(color: color),
        ),
      ],
    );
  }

  Widget _buildBatchStatusRow(String title, Map<String, dynamic> data) {
    final count = data['count'] as int? ?? 0;
    
    IconData icon;
    Color color;
    String statusText;

    if (count == 0) {
      icon = Icons.error;
      color = Colors.red;
      statusText = 'No images';
    } else if (count < 3) {
      icon = Icons.warning;
      color = Colors.orange;
      statusText = '$count images (minimum 3 recommended)';
    } else {
      icon = Icons.check_circle;
      color = Colors.green;
      statusText = '$count images available';
    }

    return Row(
      children: [
        Icon(icon, color: color),
        const SizedBox(width: 8),
        Text(title),
        const Spacer(),
        Text(
          statusText,
          style: TextStyle(color: color),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Plant Analysis Results'),
        backgroundColor: Colors.purple,
        foregroundColor: Colors.white,
        actions: [
          // Refresh button with force refresh
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : () => _loadAllData(forceRefresh: true),
            tooltip: 'Refresh All Data',
          ),
        ],
      ),
      body: _isLoading ? _buildLoadingState() : _buildContent(),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Colors.purple),
          ),
          const SizedBox(height: 16),
          const Text(
            'Loading data...',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_errorMessage != null) _buildErrorMessage(),

          const SizedBox(height: 16),

          _buildAnalysisControls(),

          const SizedBox(height: 24),

          // NEWEST ANALYSIS SECTION
          if (_newestAnalysis != null) 
            _buildNewestAnalysisSection(),

          const SizedBox(height: 32),

          // PREVIOUS ANALYSES SECTION
          if (_previousAnalyses.isNotEmpty)
            _buildPreviousAnalysesSection(),

          if (_newestAnalysis == null && _previousAnalyses.isEmpty && _errorMessage == null)
            _buildNoDataMessage(),
        ],
      ),
    );
  }

  Widget _buildErrorMessage() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red),
      ),
      child: Row(
        children: [
          const Icon(Icons.error, color: Colors.red),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _errorMessage!,
              style: const TextStyle(
                color: Colors.red,
                fontSize: 14,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () {
              setState(() {
                _errorMessage = null;
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildNoDataMessage() {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: Colors.grey[100],
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.analytics_outlined,
              size: 60,
              color: Colors.grey[400],
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'No Analysis Results Found',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 12),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 32.0),
            child: Text(
              'Run a new batch analysis to see results here. Your plant health insights will appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey,
              ),
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _runNewBatchAnalysis,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.purple,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 2,
            ),
            icon: const Icon(Icons.play_arrow),
            label: const Text(
              'Run First Analysis',
              style: TextStyle(fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnalysisControls() {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.analytics, color: Colors.purple, size: 28),
                SizedBox(width: 12),
                Text(
                  'Plant Analysis',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Get comprehensive health insights for your plants. Run analysis to detect diseases and get recommendations.',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _runNewBatchAnalysis,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purple,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 2,
                  shadowColor: Colors.purple.withOpacity(0.3),
                ),
                icon: const Icon(Icons.play_arrow, size: 24),
                label: const Text(
                  'Run New Analysis',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            
            const SizedBox(height: 12),
            
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _checkDataStatus,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.purple,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Colors.purple.withOpacity(0.3), width: 1.5),
                  ),
                  elevation: 0,
                ),
                icon: const Icon(Icons.health_and_safety, size: 24),
                label: const Text(
                  'Check Data Status',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNewestAnalysisSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Header
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.purple.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.new_releases, color: Colors.purple, size: 28),
            ),
            const SizedBox(width: 12),
            const Text(
              'Newest Plant Analysis',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                _formatRelativeTime(_newestAnalysis!['timestamp']),
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        
        const SizedBox(height: 20),
        
        // Analysis Summary Card
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.1),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildBatchSummary(_newestAnalysis!),
                const SizedBox(height: 20),
                Row(
                  children: [
                    const Icon(Icons.photo_library, color: Colors.grey, size: 18),
                    const SizedBox(width: 6),
                    Text(
                      '${_newestBatchResults.length} Analyzed Images',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 20),

        // Analyzed Images Grid
        if (_newestBatchResults.isNotEmpty)
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 0.85,
            ),
            itemCount: _newestBatchResults.length,
            itemBuilder: (context, index) {
              final result = _newestBatchResults[index];
              return _buildAnalyzedImageCard(result, index);
            },
          ),
      ],
    );
  }

  Widget _buildBatchSummary(Map<String, dynamic> batch) {
    final healthy = batch['healthy_count'] as int? ?? 0;
    final unhealthy = batch['unhealthy_count'] as int? ?? 0;
    final total = batch['total'] as int? ?? 0;
    final healthRate = batch['health_rate'] as int? ?? 0;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Stats Grid
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildSummaryMetric('Total', '$total', Icons.photo_library, Colors.blue),
            _buildSummaryMetric('Healthy', '$healthy', Icons.check_circle, Colors.green),
            _buildSummaryMetric('Issues', '$unhealthy', Icons.warning, Colors.orange),
            _buildSummaryMetric('Health', '$healthRate%', Icons.health_and_safety,
              healthRate >= 80 ? Colors.green : 
              healthRate >= 60 ? Colors.orangeAccent : Colors.red),
          ],
        ),
        
        const SizedBox(height: 16),
        
        // Health Progress Bar
        Container(
          height: 8,
          decoration: BoxDecoration(
            color: Colors.grey[200],
            borderRadius: BorderRadius.circular(4),
          ),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: healthRate / 100,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    healthRate >= 80 ? Colors.green : 
                    healthRate >= 60 ? Colors.orangeAccent : Colors.red,
                    healthRate >= 80 ? Colors.greenAccent : 
                    healthRate >= 60 ? Colors.orange : Colors.redAccent,
                  ],
                ),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ),
        
        const SizedBox(height: 12),
        
        // Meta Info
        Row(
          children: [
            Icon(Icons.calendar_today, size: 16, color: Colors.grey[600]),
            const SizedBox(width: 6),
            Text(
              'Analyzed: ${_formatDateTime(batch['date'])}',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(width: 16),
            if (batch['mode'] != null) ...[
              Icon(Icons.tune, size: 16, color: Colors.grey[600]),
              const SizedBox(width: 6),
              Text(
                '${batch['mode']}',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildSummaryMetric(String label, String value, IconData icon, Color color) {
    return Column(
      children: [
        Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 22),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: Colors.grey,
          ),
        ),
      ],
    );
  }

  Widget _buildAnalyzedImageCard(Map<String, dynamic> result, int index) {
    final diseaseType = result['disease_type'] as String? ?? 'Unknown';
    final healthStatus = result['health_status'] as String? ?? 'Unknown';
    final confidence = result['confidence'] as double? ?? 0.0;
    final overallHealth = result['overall_health'] as String? ?? 'Unknown';
    final plantHealthScore = result['plant_health_score'] as double?;
    final imageUrl = result['image_url'] as String?;
    final tomatoType = result['tomato_type'] as String? ?? 'Unknown';
    
    Color healthColor = _getHealthColor(overallHealth);
    
    // Format confidence as percentage
    final confidencePercent = (confidence * 100).toStringAsFixed(1);
    
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Material(
          color: Colors.white,
          child: InkWell(
            onTap: () => _showAnalysisDetails(result),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Image Preview with Index Badge
                  Stack(
                    children: [
                      // Image Container
                      Container(
                        height: 110,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: Colors.grey[100],
                        ),
                        child: imageUrl != null && imageUrl.isNotEmpty
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.network(
                                  imageUrl,
                                  fit: BoxFit.cover,
                                  loadingBuilder: (context, child, loadingProgress) {
                                    if (loadingProgress == null) return child;
                                    return Center(
                                      child: CircularProgressIndicator(
                                        value: loadingProgress.expectedTotalBytes != null
                                            ? loadingProgress.cumulativeBytesLoaded /
                                                loadingProgress.expectedTotalBytes!
                                            : null,
                                        strokeWidth: 2,
                                      ),
                                    );
                                  },
                                  errorBuilder: (context, error, stackTrace) {
                                    return Container(
                                      color: Colors.grey[200],
                                      child: Center(
                                        child: Icon(
                                          Icons.broken_image,
                                          color: Colors.grey[400],
                                          size: 40,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              )
                            : Center(
                                child: Icon(
                                  Icons.photo,
                                  color: Colors.grey[400],
                                  size: 40,
                                ),
                              ),
                      ),
                      
                      // Health Indicator
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: healthColor.withOpacity(0.9),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.1),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Text(
                            overallHealth,
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      
                      // Index Badge
                      Positioned(
                        top: 8,
                        left: 8,
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.6),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              '${index + 1}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 12),
                  
                  // Disease Type
                  Text(
                    diseaseType,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  
                  const SizedBox(height: 8),
                  
                  // Tomato Type and Confidence
                  Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Icon(Icons.category, size: 12, color: Colors.grey[600]),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                tomatoType,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey[700],
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.assessment, size: 10, color: Colors.blue),
                            const SizedBox(width: 4),
                            Text(
                              '$confidencePercent%',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.blue,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 8),
                  
                  // Plant Health Score
                  if (plantHealthScore != null) ...[
                    Row(
                      children: [
                        Icon(Icons.score, size: 12, color: Colors.green),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            'Plant Health: ${plantHealthScore.toStringAsFixed(1)}',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey[700],
                            ),
                          ),
                        ),
                        Container(
                          height: 4,
                          width: 40,
                          decoration: BoxDecoration(
                            color: Colors.grey[200],
                            borderRadius: BorderRadius.circular(2),
                          ),
                          child: FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: plantHealthScore / 100,
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    plantHealthScore >= 80 ? Colors.green : 
                                    plantHealthScore >= 60 ? Colors.orangeAccent : Colors.red,
                                    plantHealthScore >= 80 ? Colors.greenAccent : 
                                    plantHealthScore >= 60 ? Colors.orange : Colors.redAccent,
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                  
                  // View Details Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => _showAnalysisDetails(result),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey[50],
                        foregroundColor: Colors.purple,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: BorderSide(color: Colors.grey[300]!),
                        ),
                        elevation: 0,
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'View Details',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                          SizedBox(width: 4),
                          Icon(Icons.arrow_forward, size: 14),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPreviousAnalysesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Header
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.history, color: Colors.blue, size: 28),
            ),
            const SizedBox(width: 12),
            const Text(
              'Analysis History',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${_previousAnalyses.length} total',
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        
        const SizedBox(height: 20),
        
        // Previous Analyses List
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _previousAnalyses.length,
          itemBuilder: (context, index) {
            final analysis = _previousAnalyses[index];
            return _buildPreviousAnalysisCard(analysis, index);
          },
        ),
      ],
    );
  }

  Widget _buildPreviousAnalysisCard(Map<String, dynamic> analysis, int index) {
    final total = analysis['total'] as int? ?? 0;
    final healthy = analysis['healthy_count'] as int? ?? 0;
    final unhealthy = analysis['unhealthy_count'] as int? ?? 0;
    final date = analysis['date'] as String?;
    final batchId = analysis['batch_id'] as String?;
    
    final healthRate = total > 0 ? (healthy / total * 100).round() : 0;
    Color healthColor = _getHealthRateColor(healthRate);
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.08),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: batchId != null ? () => _loadPreviousBatch(batchId) : null,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                // Date Circle
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _getDayFromDate(date ?? ''),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue,
                        ),
                      ),
                      Text(
                        _getMonthFromDate(date ?? ''),
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.blue,
                        ),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(width: 16),
                
                // Analysis Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          _buildMiniMetric('${healthy}/${total}', 'Healthy', Colors.green),
                          const SizedBox(width: 12),
                          _buildMiniMetric('$unhealthy', 'Issues', Colors.red),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: LinearProgressIndicator(
                              value: healthRate / 100,
                              backgroundColor: Colors.grey[200],
                              color: healthColor,
                              minHeight: 4,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: healthColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.health_and_safety,
                                  size: 12,
                                  color: healthColor,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '$healthRate%',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: healthColor,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _formatTimeOnly(date ?? ''),
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                
                // View Button
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.purple.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.arrow_forward,
                    color: Colors.purple,
                    size: 18,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _loadPreviousBatch(String batchId) async {
    try {
      setState(() {
        _isLoading = true;
      });
      
      final batchDetails = await ApiService.getBatchDetails(batchId);
      
      if (batchDetails['analyses'] != null && batchDetails['analyses'].isNotEmpty) {
        final analyses = List<Map<String, dynamic>>.from(batchDetails['analyses']);
        
        // Show previous batch results in a dialog
        _showPreviousBatchResults(batchId, analyses);
      } else {
        // Batch no longer exists, refresh data
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Batch no longer exists. Refreshing data...'),
            backgroundColor: Colors.orange,
          ),
        );
        await _loadAllData(forceRefresh: true);
      }
      
    } catch (e) {
      print('❌ Error loading previous batch: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load batch: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showPreviousBatchResults(String batchId, List<Map<String, dynamic>> analyses) {
    final healthyCount = analyses.where((a) {
      final overallHealth = a['overall_health'] as String? ?? '';
      final healthStatus = a['health_status'] as String? ?? '';
      return overallHealth.toLowerCase().contains('healthy') || 
             healthStatus.toLowerCase().contains('healthy');
    }).length;
    
    final healthRate = analyses.isNotEmpty ? (healthyCount / analyses.length * 100).round() : 0;
    final healthColor = _getHealthRateColor(healthRate);
    
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.8,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: healthColor.withOpacity(0.1),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: healthColor.withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.history, color: healthColor),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Analysis from ${_formatDateOnly(batchId)}',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '${analyses.length} images analyzed',
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              
              // Stats Bar
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  border: Border(
                    bottom: BorderSide(color: Colors.grey[200]!),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildDialogStat('Total', '${analyses.length}', Colors.blue),
                    _buildDialogStat('Healthy', '$healthyCount', Colors.green),
                    _buildDialogStat('Issues', '${analyses.length - healthyCount}', Colors.orange),
                    _buildDialogStat('Health', '$healthRate%', healthColor),
                  ],
                ),
              ),
              
              // Results List
              Expanded(
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.all(20),
                  itemCount: analyses.length,
                  itemBuilder: (context, index) {
                    final result = analyses[index];
                    return _buildPreviousResultItem(result, index);
                  },
                ),
              ),
              
              // Close Button
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(color: Colors.grey[200]!),
                  ),
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.purple,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Close'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPreviousResultItem(Map<String, dynamic> result, int index) {
    final diseaseType = result['disease_type'] as String? ?? 'Unknown';
    final overallHealth = result['overall_health'] as String? ?? 'Unknown';
    final confidence = result['confidence'] as double? ?? 0.0;
    Color healthColor = _getHealthColor(overallHealth);
    
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: healthColor.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '${index + 1}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: healthColor,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  diseaseType,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: healthColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        overallHealth,
                        style: TextStyle(
                          fontSize: 10,
                          color: healthColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${(confidence * 100).toStringAsFixed(1)}%',
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.info_outline, size: 20, color: Colors.grey[600]),
            onPressed: () => _showAnalysisDetails(result),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniMetric(String value, String label, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: Colors.grey,
          ),
        ),
      ],
    );
  }

  Widget _buildDialogStat(String label, String value, Color color) {
    return Column(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            color: Colors.grey,
          ),
        ),
      ],
    );
  }

  void _showAnalysisDetails(Map<String, dynamic> result) {
    final diseaseType = result['disease_type'] as String? ?? 'Unknown';
    final healthStatus = result['health_status'] as String? ?? 'Unknown';
    final overallHealth = result['overall_health'] as String? ?? 'Unknown';
    final confidence = result['confidence'] as double? ?? 0.0;
    final plantHealthScore = result['plant_health_score'] as double?;
    final soilQualityScore = result['soil_quality_score'] as double?;
    final recommendations = result['recommendations'];
    final soilIssues = result['soil_issues'];
    final imageUrl = result['image_url'] as String?;
    final tomatoType = result['tomato_type'] as String? ?? 'Unknown';
    final date = result['date'] as String?;
    
    // Get soil data for this analysis
    final soilData = _soilData;
    
    List<String> plantRecList = [];
    List<String> soilRecList = [];
    
    // Process recommendations
    if (recommendations is List) {
      final allRecs = List<String>.from(recommendations);
      // Separate plant and soil recommendations (simple heuristic)
      plantRecList = allRecs.where((rec) => 
        !rec.toLowerCase().contains('soil') && 
        !rec.toLowerCase().contains('ph') &&
        !rec.toLowerCase().contains('nutrient')
      ).toList();
      soilRecList = allRecs.where((rec) => 
        rec.toLowerCase().contains('soil') || 
        rec.toLowerCase().contains('ph') ||
        rec.toLowerCase().contains('nutrient')
      ).toList();
    } else if (recommendations is String) {
      final allRecs = recommendations.split(',').map((e) => e.trim()).toList();
      plantRecList = allRecs.where((rec) => 
        !rec.toLowerCase().contains('soil') && 
        !rec.toLowerCase().contains('ph') &&
        !rec.toLowerCase().contains('nutrient')
      ).toList();
      soilRecList = allRecs.where((rec) => 
        rec.toLowerCase().contains('soil') || 
        rec.toLowerCase().contains('ph') ||
        rec.toLowerCase().contains('nutrient')
      ).toList();
    }
    
    // Process soil issues
    List<String> soilIssueList = [];
    if (soilIssues is List) {
      soilIssueList = List<String>.from(soilIssues);
    } else if (soilIssues is String) {
      soilIssueList = soilIssues.split(',').map((e) => e.trim()).toList();
    }
    
    Color healthColor = _getHealthColor(overallHealth);
    
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with health status
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: healthColor.withOpacity(0.1),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: healthColor,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _getHealthIcon(overallHealth),
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            overallHealth,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: healthColor,
                            ),
                          ),
                          Text(
                            diseaseType,
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              
              // Image
              if (imageUrl != null && imageUrl.isNotEmpty)
                Container(
                  height: 180,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                  ),
                  child: ClipRRect(
                    child: Image.network(
                      imageUrl,
                      fit: BoxFit.cover,
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return Center(
                          child: CircularProgressIndicator(
                            value: loadingProgress.expectedTotalBytes != null
                                ? loadingProgress.cumulativeBytesLoaded /
                                    loadingProgress.expectedTotalBytes!
                                : null,
                          ),
                        );
                      },
                      errorBuilder: (context, error, stackTrace) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.broken_image, color: Colors.grey[400], size: 40),
                              const SizedBox(height: 8),
                              const Text(
                                'Image not available',
                                style: TextStyle(color: Colors.grey),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Basic Info Grid
                    GridView.count(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisCount: 2,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 3,
                      children: [
                        _buildDetailCard('Tomato Type', tomatoType, Icons.category, Colors.blue),
                        _buildDetailCard('Confidence', '${(confidence * 100).toStringAsFixed(1)}%', Icons.assessment, Colors.purple),
                        if (plantHealthScore != null)
                          _buildDetailCard('Plant Health', plantHealthScore.toStringAsFixed(1), Icons.health_and_safety, Colors.green),
                        if (soilQualityScore != null)
                          _buildDetailCard('Soil Quality', soilQualityScore.toStringAsFixed(1), Icons.landscape, Colors.orange),
                      ],
                    ),
                    
                    const SizedBox(height: 24),
                    
                    // SOIL DATA SECTION (Only in analysis details)
                    if (soilData != null)
                      _buildSoilDataInDetails(soilData),
                    
                    // Plant Recommendations
                    if (plantRecList.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      const Text(
                        'Plant Recommendations',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.green.withOpacity(0.2)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: plantRecList.map((rec) => Padding(
                            padding: const EdgeInsets.only(bottom: 8.0),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(Icons.check_circle, size: 16, color: Colors.green),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    rec,
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                ),
                              ],
                            ),
                          )).toList(),
                        ),
                      ),
                    ],
                    
                    // Soil Recommendations
                    if (soilRecList.isNotEmpty || soilIssueList.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      const Text(
                        'Soil Management',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.orange.withOpacity(0.2)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Soil Issues
                            if (soilIssueList.isNotEmpty) ...[
                              const Text(
                                'Issues Identified:',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  color: Colors.orange,
                                ),
                              ),
                              const SizedBox(height: 8),
                              ...soilIssueList.map((issue) => Padding(
                                padding: const EdgeInsets.only(bottom: 6.0),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(Icons.warning, size: 16, color: Colors.orange),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        issue,
                                        style: const TextStyle(fontSize: 14),
                                      ),
                                    ),
                                  ],
                                ),
                              )).toList(),
                              const SizedBox(height: 12),
                            ],
                            
                            // Soil Recommendations
                            if (soilRecList.isNotEmpty) ...[
                              const Text(
                                'Recommendations:',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  color: Colors.orange,
                                ),
                              ),
                              const SizedBox(height: 8),
                              ...soilRecList.map((rec) => Padding(
                                padding: const EdgeInsets.only(bottom: 6.0),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(Icons.agriculture, size: 16, color: Colors.orange),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        rec,
                                        style: const TextStyle(fontSize: 14),
                                      ),
                                    ),
                                  ],
                                ),
                              )).toList(),
                            ],
                          ],
                        ),
                      ),
                    ],
                    
                    // Date Info
                    if (date != null) 
                      Container(
                        margin: const EdgeInsets.only(top: 20),
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.calendar_today, size: 16, color: Colors.grey[600]),
                            const SizedBox(width: 8),
                            Text(
                              'Analyzed: ${_formatDateTime(date)}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              
              // Close Button
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(color: Colors.grey[200]!),
                  ),
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.purple,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Close'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSoilDataInDetails(Map<String, dynamic> soilData) {
    // Extract NPK levels safely
    Map<String, dynamic> npkLevels = {};
    if (soilData['npk_levels'] is Map) {
      npkLevels = Map<String, dynamic>.from(soilData['npk_levels'] as Map);
    } else if (soilData['npk'] is Map) {
      npkLevels = Map<String, dynamic>.from(soilData['npk'] as Map);
    }
    
    // Extract other parameters safely
    Map<String, dynamic> otherParams = {};
    if (soilData['other_parameters'] is Map) {
      otherParams = Map<String, dynamic>.from(soilData['other_parameters'] as Map);
    }
    
    final lastUpdated = soilData['last_updated'] as String?;
    final dataStatus = soilData['data_status'] as String? ?? 'no_data';
    final isDataFresh = dataStatus == 'fresh';
    final dataAgeHours = soilData['data_age_hours'] as double? ?? 0;
    
    // Prepare all parameters in a single list
    final List<Map<String, dynamic>> allParameters = [];
    
    // Add NPK parameters
    if (npkLevels.isNotEmpty) {
      npkLevels.forEach((key, value) {
        if (value != null) {
          allParameters.add({
            'title': key.toUpperCase(),
            'value': value.toString(),
            'icon': Icons.grass,
            'color': Colors.green,
          });
        }
      });
    } else {
      // Add default NPK placeholders if no data
      allParameters.addAll([
        {'title': 'N', 'value': 'N/A', 'icon': Icons.grass, 'color': Colors.green},
        {'title': 'P', 'value': 'N/A', 'icon': Icons.grass, 'color': Colors.green},
        {'title': 'K', 'value': 'N/A', 'icon': Icons.grass, 'color': Colors.green},
      ]);
    }
    
    // Add other parameters
    if (otherParams.isNotEmpty) {
      otherParams.forEach((key, value) {
        if (value != null) {
          IconData icon;
          Color color;
          
          switch (key.toLowerCase()) {
            case 'ph':
              icon = Icons.water_drop;
              color = Colors.blue;
              break;
            case 'moisture':
              icon = Icons.opacity;
              color = Colors.lightBlue;
              break;
            case 'temperature':
              icon = Icons.thermostat;
              color = Colors.orange;
              break;
            case 'conductivity':
              icon = Icons.electric_bolt;
              color = Colors.purple;
              break;
            default:
              icon = Icons.terrain;
              color = Colors.brown;
          }
          
          allParameters.add({
            'title': _capitalizeFirst(key),
            'value': value.toString(),
            'icon': icon,
            'color': color,
          });
        }
      });
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Soil Parameters',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 8),
        
        // Data freshness indicator
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isDataFresh ? Colors.green[50] : Colors.orange[50],
            border: Border.all(
                color: isDataFresh ? Colors.green : Colors.orange),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isDataFresh ? Icons.check_circle : Icons.warning,
                size: 14,
                color: isDataFresh ? Colors.green : Colors.orange,
              ),
              const SizedBox(width: 6),
              Text(
                isDataFresh ? 'Fresh soil data' : 'Soil data: ${dataAgeHours.round()}h old',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: isDataFresh ? Colors.green : Colors.orange,
                ),
              ),
            ],
          ),
        ),
        
        if (lastUpdated != null) ...[
          const SizedBox(height: 4),
          Text(
            'Last updated: $lastUpdated',
            style: const TextStyle(
              fontSize: 11,
              color: Colors.grey,
            ),
          ),
        ],
        
        const SizedBox(height: 12),
        
        // Grid of soil parameters
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 1.0,
          ),
          itemCount: allParameters.length,
          itemBuilder: (context, index) {
            final param = allParameters[index];
            return _buildSoilParameterCard(
              param['title'] as String,
              param['value'] as String,
              param['icon'] as IconData,
              param['color'] as Color,
            );
          },
        ),
        
        // Data Status Message
        if (!isDataFresh)
          Container(
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange),
            ),
            child: Row(
              children: [
                Icon(Icons.warning, size: 16, color: Colors.orange),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Soil data is ${dataAgeHours.round()}h old. Consider updating for more accurate plant health analysis.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.orange,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildSoilParameterCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(height: 6),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Helper methods
  String _capitalizeFirst(String text) {
    if (text.isEmpty) return text;
    return text[0].toUpperCase() + text.substring(1);
  }

  String _formatDateTime(dynamic timestamp) {
    try {
      if (timestamp == null) return 'Unknown Date';
      final date = DateTime.parse(timestamp.toString());
      return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return 'Unknown Date';
    }
  }

  String _formatDateOnly(dynamic timestamp) {
    try {
      if (timestamp == null) return 'Unknown';
      final date = DateTime.parse(timestamp.toString());
      return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    } catch (e) {
      return 'Unknown';
    }
  }

  String _formatTimeOnly(dynamic timestamp) {
    try {
      if (timestamp == null) return 'Unknown';
      final date = DateTime.parse(timestamp.toString());
      return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return 'Unknown';
    }
  }

  String _formatRelativeTime(dynamic timestamp) {
    try {
      if (timestamp == null) return 'Just now';
      final date = DateTime.parse(timestamp.toString());
      final now = DateTime.now();
      final difference = now.difference(date);
      
      if (difference.inMinutes < 1) return 'Just now';
      if (difference.inMinutes < 60) return '${difference.inMinutes}m ago';
      if (difference.inHours < 24) return '${difference.inHours}h ago';
      if (difference.inDays < 7) return '${difference.inDays}d ago';
      return _formatDateTime(timestamp);
    } catch (e) {
      return 'Recently';
    }
  }

  String _getDayFromDate(String timestamp) {
    try {
      final date = DateTime.parse(timestamp);
      return date.day.toString();
    } catch (e) {
      return '--';
    }
  }

  String _getMonthFromDate(String timestamp) {
    try {
      final date = DateTime.parse(timestamp);
      const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      return months[date.month - 1];
    } catch (e) {
      return '---';
    }
  }

  Color _getHealthColor(String? status) {
    if (status == null) return Colors.grey;
    final lowerStatus = status.toLowerCase();

    if (lowerStatus.contains('healthy')) return Colors.green;
    if (lowerStatus.contains('unhealthy')) return Colors.red;
    if (lowerStatus.contains('moderate')) return Colors.orange;
    if (lowerStatus.contains('poor') || lowerStatus.contains('critical')) return Colors.red[800]!;

    return Colors.grey;
  }

  Color _getHealthRateColor(int rate) {
    if (rate >= 80) return Colors.green;
    if (rate >= 60) return Colors.orange;
    if (rate >= 40) return Colors.orangeAccent;
    return Colors.red;
  }

  IconData _getHealthIcon(String? status) {
    if (status == null) return Icons.help;
    final lowerStatus = status.toLowerCase();

    if (lowerStatus.contains('healthy')) return Icons.check_circle;
    if (lowerStatus.contains('unhealthy')) return Icons.warning;
    if (lowerStatus.contains('moderate')) return Icons.info;
    if (lowerStatus.contains('poor') || lowerStatus.contains('critical')) return Icons.error;

    return Icons.help;
  }
}