import 'package:flutter/material.dart';
import '../services/api_service.dart';

class SoilStatusScreen extends StatefulWidget {
  final VoidCallback? onProceed;

  const SoilStatusScreen({super.key, this.onProceed});

  @override
  State<SoilStatusScreen> createState() => _SoilStatusScreenState();
}

class _SoilStatusScreenState extends State<SoilStatusScreen> {
  bool _isLoading = false;
  Map<String, dynamic>? _soilStatus;
  String? _errorMessage;

  Future<void> _loadSoilStatus() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await ApiService.getSoilStatus();

      setState(() {
        _soilStatus = result;
      });
    } on ApiException catch (e) {
      setState(() {
        _errorMessage = 'Failed to load soil status: ${e.message}';
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Unexpected error: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _proceedToResults() {
    if (widget.onProceed != null) {
      widget.onProceed!();
    }
  }

  @override
  void initState() {
    super.initState();
    _loadSoilStatus();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Soil Status'),
        backgroundColor: const Color.fromARGB(255, 187, 137, 119),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _loadSoilStatus();
            },
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? _buildErrorState()
              : _soilStatus != null
                  ? _buildSoilStatus()
                  : _buildEmptyState(),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 64, color: Colors.red),
          const SizedBox(height: 16),
          Text(
            _errorMessage!,
            style: const TextStyle(fontSize: 16, color: Colors.red),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            icon: const Icon(Icons.refresh),
            label: const Text('Try Again'),
            onPressed: () {
              _loadSoilStatus();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.brown,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.terrain, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          const Text(
            'No soil data available',
            style: TextStyle(fontSize: 16, color: Colors.grey),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            icon: const Icon(Icons.refresh),
            label: const Text('Check for Soil Data'),
            onPressed: () {
              _loadSoilStatus();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.brown,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSoilStatus() {
    final dataStatus = _soilStatus!['data_status'] ?? 'no_data';
    final isDataFresh = dataStatus == 'fresh';
    final dataAgeHours = _soilStatus!['data_age_hours'] ?? 0;
    final hasData = dataStatus != 'no_data';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with data status
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Soil Parameters',
                      style: TextStyle(
                          fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    if (_soilStatus!['last_updated'] != null)
                      Text(
                        'Last updated: ${_soilStatus!['last_updated']}',
                        style: const TextStyle(color: Colors.grey),
                      ),
                  ],
                ),
              ),
              if (hasData)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: isDataFresh ? Colors.green[50] : Colors.orange[50],
                    border: Border.all(
                        color: isDataFresh ? Colors.green : Colors.orange),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isDataFresh ? Icons.check_circle : Icons.warning,
                        size: 16,
                        color: isDataFresh ? Colors.green : Colors.orange,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isDataFresh ? 'Current' : '${dataAgeHours}h old',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isDataFresh ? Colors.green : Colors.orange,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (_soilStatus!['message'] != null)
            Text(
              _soilStatus!['message'],
              style: TextStyle(
                color: isDataFresh ? Colors.green : Colors.orange,
                fontStyle: FontStyle.italic,
              ),
            ),
          const SizedBox(height: 24),

          // Combined Soil Data in Containers
          Column(
            children: [
              // NPK Levels Container
              if (_soilStatus!['npk_levels'] != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16.0),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.withOpacity(0.2),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                    border: Border.all(color: Colors.grey.withOpacity(0.2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // NPK items
                      ...(_soilStatus!['npk_levels'] as Map<String, dynamic>)
                          .entries
                          .map((entry) {
                        return _buildStatusItem(
                          entry.key,
                          entry.value.toString(),
                          Icons.grass,
                          Colors.green,
                        );
                      }).toList(),

                      // Soil parameter items
                      ...(_soilStatus!['other_parameters']
                              as Map<String, dynamic>)
                          .entries
                          .map((entry) {
                        IconData icon;
                        Color color;

                        switch (entry.key) {
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
                          default:
                            icon = Icons.terrain;
                            color = Colors.brown;
                        }

                        return _buildStatusItem(
                          entry.key,
                          entry.value.toString(),
                          icon,
                          color,
                        );
                      }).toList(),
                    ],
                  ),
                ),

              const SizedBox(height: 16),
            ],
          ),

          const SizedBox(height: 16),

          // Proceed Button Section
          Column(
            children: [
              if (!isDataFresh && hasData)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange[50],
                    border: Border.all(color: Colors.orange),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning, size: 16, color: Colors.orange),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Soil data is ${dataAgeHours}h old.',
                          style: TextStyle(fontSize: 12, color: Colors.orange),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 12),

              // Proceed Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.arrow_forward),
                  label: const Text('Proceed to Results'),
                  onPressed: hasData ? _proceedToResults : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: hasData ? Colors.orange : Colors.grey,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),

              // Helper text for proceed button
              if (!hasData)
                const Padding(
                  padding: EdgeInsets.only(top: 8.0),
                  child: Text(
                    'Soil data is required to proceed to results',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusItem(
      String title, String value, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _capitalizeFirst(title),
                  style: const TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
                  ),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 16,
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

  String _capitalizeFirst(String text) {
    if (text.isEmpty) return text;
    return text[0].toUpperCase() + text.substring(1);
  }
}