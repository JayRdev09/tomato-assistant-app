import 'package:flutter/material.dart';
import '../services/api_service.dart';

class ConnectionTestScreen extends StatefulWidget {
  const ConnectionTestScreen({super.key});

  @override
  State<ConnectionTestScreen> createState() => _ConnectionTestScreenState();
}

class _ConnectionTestScreenState extends State<ConnectionTestScreen> {
  Map<String, dynamic> _connectionStatus = {};
  Map<String, dynamic> _diagnostics = {};
  bool _isTesting = false;
  bool _isRunningDiagnostics = false;
  final List<String> _testLog = [];

  void _addToLog(String message) {
    setState(() {
      _testLog.add('${DateTime.now().toString().split('.').first}: $message');
    });
  }

  Future<void> _testConnection() async {
    setState(() {
      _isTesting = true;
      _connectionStatus = {};
      _testLog.clear();
    });

    _addToLog('🔗 Starting connection test...');
    _addToLog('📡 Testing URL: ${ApiService.baseUrl}');

    try {
      final status = await ApiService.testBackendConnection();
      setState(() {
        _connectionStatus = status;
      });

      if (status['connected'] == true) {
        _addToLog('✅ Backend connection successful');
        _addToLog('📊 Status: ${status['status']}');
        _addToLog('💬 Message: ${status['message']}');
      } else {
        _addToLog('❌ Backend connection failed');
        _addToLog('📊 Status: ${status['status']}');
        _addToLog('💬 Message: ${status['message']}');
        _addToLog('🔍 Details: ${status['details']}');
      }
    } catch (e) {
      _addToLog('❌ Connection test error: $e');
      setState(() {
        _connectionStatus = {
          'connected': false,
          'status': 'error',
          'message': 'Test failed: $e'
        };
      });
    } finally {
      setState(() {
        _isTesting = false;
      });
    }
  }

  Future<void> _runDiagnostics() async {
    setState(() {
      _isRunningDiagnostics = true;
      _diagnostics = {};
      _testLog.clear();
    });

    _addToLog('🔍 Starting comprehensive diagnostics...');

    try {
      final results = await ApiService.diagnoseConnection();
      setState(() {
        _diagnostics = results;
      });

      _addToLog('📊 Diagnostics completed: ${results['overall_status']}');
      
      if (results['basic_connectivity'] == true) {
        _addToLog('✅ Basic connectivity: OK');
      } else {
        _addToLog('❌ Basic connectivity: FAILED');
      }

      if (results['database_connectivity'] == true) {
        _addToLog('✅ Database connectivity: OK');
      } else if (results['database_connectivity'] == false) {
        _addToLog('⚠️ Database connectivity: Issues detected');
      }

      if (results['storage_connectivity'] == true) {
        _addToLog('✅ Storage connectivity: OK');
      } else if (results['storage_connectivity'] == false) {
        _addToLog('⚠️ Storage connectivity: Issues detected');
      }

      // Test authentication if backend is connected
      if (results['basic_connectivity'] == true) {
        _addToLog('🔐 Testing authentication endpoints...');
        await _testAuthentication();
      }

    } catch (e) {
      _addToLog('❌ Diagnostics failed: $e');
      setState(() {
        _diagnostics = {
          'error': 'Diagnostics failed: $e'
        };
      });
    } finally {
      setState(() {
        _isRunningDiagnostics = false;
      });
    }
  }

  Future<void> _testAuthentication() async {
    try {
      _addToLog('👤 Testing auth endpoints...');
      
      // Test if we can access auth health
      final response = await ApiService.testBackendConnection();
      if (response['connected'] == true) {
        _addToLog('✅ Auth endpoints are accessible');
        
        // If user is authenticated, test profile access
        if (ApiService.isAuthenticated) {
          _addToLog('🔑 User is authenticated, testing profile access...');
          try {
            final profile = await ApiService.getUserProfile();
            _addToLog('✅ Profile access: OK - Welcome ${profile['user']['firstName']}');
          } catch (e) {
            _addToLog('❌ Profile access failed: $e');
          }
        } else {
          _addToLog('👤 No active authentication session');
        }
      }
    } catch (e) {
      _addToLog('❌ Auth test failed: $e');
    }
  }

  Future<void> _testSoilDataEndpoints() async {
    if (!ApiService.isAuthenticated) {
      _addToLog('⚠️ Skipping soil data test - not authenticated');
      return;
    }

    try {
      _addToLog('🌱 Testing soil data endpoints...');
      
      // Test soil status endpoint
      final soilStatus = await ApiService.getSoilStatus();
      _addToLog('✅ Soil status endpoint: OK');
      _addToLog('📊 Data status: ${soilStatus['data_status']}');
      
    } catch (e) {
      _addToLog('❌ Soil data test failed: $e');
    }
  }

  Future<void> _testImageEndpoints() async {
    if (!ApiService.isAuthenticated) {
      _addToLog('⚠️ Skipping image endpoints test - not authenticated');
      return;
    }

    try {
      _addToLog('🖼️ Testing image endpoints...');
      
      // Test getting user images
      final images = await ApiService.getUserImages(limit: 1);
      _addToLog('✅ Image endpoints: OK - Found ${images.length} images');
      
    } catch (e) {
      _addToLog('❌ Image endpoints test failed: $e');
    }
  }

  Future<void> _runFullTestSuite() async {
    await _testConnection();
    if (_connectionStatus['connected'] == true) {
      await _runDiagnostics();
      await _testAuthentication();
      await _testSoilDataEndpoints();
      await _testImageEndpoints();
    }
  }

  Widget _buildStatusCard() {
    final isConnected = _connectionStatus['connected'] == true;
    
    return Card(
      color: isConnected ? Colors.green[50] : Colors.red[50],
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isConnected ? Icons.check_circle : Icons.error,
                  color: isConnected ? Colors.green : Colors.red,
                  size: 32,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    isConnected ? 'Backend Connected' : 'Backend Disconnected',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: isConnected ? Colors.green : Colors.red,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_connectionStatus.isNotEmpty) ...[
              Text('Status: ${_connectionStatus['status']}'),
              const SizedBox(height: 4),
              Text('Message: ${_connectionStatus['message']}'),
              if (_connectionStatus['details'] != null) ...[
                const SizedBox(height: 4),
                Text('Details: ${_connectionStatus['details']}'),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDiagnosticsCard() {
    if (_diagnostics.isEmpty) return const SizedBox();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Detailed Diagnostics',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ..._diagnostics.entries.map((entry) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      margin: const EdgeInsets.only(top: 6, right: 8),
                      decoration: BoxDecoration(
                        color: _getStatusColor(entry.value),
                        shape: BoxShape.circle,
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${entry.key}:',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            entry.value.toString(),
                            style: TextStyle(
                              color: _getStatusColor(entry.value),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Color _getStatusColor(dynamic value) {
    if (value == true) return Colors.green;
    if (value == false) return Colors.red;
    if (value is String && value.contains('error')) return Colors.red;
    if (value is String && value.contains('healthy')) return Colors.green;
    return Colors.grey;
  }

  Widget _buildTestLog() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.list_alt),
                SizedBox(width: 8),
                Text(
                  'Test Log',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              height: 200,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: _testLog.isEmpty
                  ? const Center(
                      child: Text(
                        'No test logs yet...',
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _testLog.length,
                      itemBuilder: (context, index) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8.0,
                            vertical: 4.0,
                          ),
                          child: Text(
                            _testLog[index],
                            style: const TextStyle(
                              fontFamily: 'Monospace',
                              fontSize: 12,
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _testConnection();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Backend Connection Test'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Connection Info
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Backend Connection',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    const Text('URL: ${ApiService.baseUrl}'),
                    Text('Authenticated: ${ApiService.isAuthenticated}'),
                    if (ApiService.isAuthenticated)
                      Text('User ID: ${ApiService.currentUserId}'),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ElevatedButton(
                          onPressed: _isTesting ? null : _testConnection,
                          child: _isTesting
                              ? const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    CircularProgressIndicator(),
                                    SizedBox(width: 8),
                                    Text('Testing...'),
                                  ],
                                )
                              : const Text('Test Connection'),
                        ),
                        ElevatedButton(
                          onPressed: _isRunningDiagnostics ? null : _runDiagnostics,
                          child: _isRunningDiagnostics
                              ? const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    CircularProgressIndicator(),
                                    SizedBox(width: 8),
                                    Text('Diagnosing...'),
                                  ],
                                )
                              : const Text('Run Diagnostics'),
                        ),
                        ElevatedButton(
                          onPressed: _isTesting ? null : _runFullTestSuite,
                          child: const Text('Full Test Suite'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 16),

            // Status Card
            _buildStatusCard(),

            const SizedBox(height: 16),

            // Diagnostics Card
            _buildDiagnosticsCard(),

            const SizedBox(height: 16),

            // Test Log
            Expanded(child: _buildTestLog()),

            // Troubleshooting Guide
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Troubleshooting Guide',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 8),
                    Text('• Ensure backend server is running (npm run dev)'),
                    Text('• Check if port 8000 is accessible'),
                    Text('• Verify IP address matches your network'),
                    Text('• Check firewall settings'),
                    Text('• Ensure both devices are on same network'),
                    Text('• Restart backend server if issues persist'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}