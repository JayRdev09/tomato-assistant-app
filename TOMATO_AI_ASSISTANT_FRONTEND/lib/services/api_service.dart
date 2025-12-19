import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

class ApiService {
  static const String baseUrl = 'http://localhost:8000/api';

  // Supabase Auth Token
  static String? _authToken;
  static String? _userId;

  // Set the authentication token
  static void setAuthToken(String? token, String? userId) {
    _authToken = token;
    _userId = userId;
    if (token != null) {
      print('🔐 Authentication token set for API calls');
      print('👤 User ID: $userId');
    } else {
      print('🔓 Authentication token cleared');
    }
  }

  // Get authentication headers
  static Map<String, String> _getAuthHeaders({bool includeAuth = true}) {
    final headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    if (includeAuth && _authToken != null) {
      headers['Authorization'] = 'Bearer $_authToken';
    }
    return headers;
  }

  // Test backend connection
  static Future<Map<String, dynamic>> testBackendConnection() async {
    try {
      print('🔗 Testing backend connection...');

      final response = await http.get(
        Uri.parse('$baseUrl/health'),
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      print('📡 Backend response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return {
          'connected': true,
          'status': 'healthy',
          'message': data['message'] ?? 'Backend is running',
          'details': data
        };
      } else {
        return {
          'connected': false,
          'status': 'unreachable',
          'message': 'Backend responded with ${response.statusCode}',
          'details': 'Make sure your backend is running on port 8000'
        };
      }
    } catch (e) {
      print('❌ Backend connection failed: $e');
      return {
        'connected': false,
        'status': 'error',
        'message': 'Cannot connect to backend',
        'details':
            'Error: $e\nPlease check:\n1. Backend server is running\n2. Correct IP address: 192.168.1.195\n3. Port 8000 is accessible'
      };
    }
  }

  // ============ AUTHENTICATION METHODS ============

  // User Registration
  static Future<Map<String, dynamic>> signUp({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    String? phoneNumber,
    String? address,
  }) async {
    try {
      // First test connection
      final connection = await testBackendConnection();
      if (!connection['connected']) {
        throw ApiException(
            'Cannot connect to backend: ${connection['message']}');
      }

      print('👤 User registration attempt: $email');

      final response = await http
          .post(
            Uri.parse('$baseUrl/auth/signup'),
            headers: _getAuthHeaders(includeAuth: false),
            body: json.encode({
              'email': email,
              'password': password,
              'firstName': firstName,
              'lastName': lastName,
              'phoneNumber': phoneNumber,
              'address': address,
            }),
          )
          .timeout(const Duration(seconds: 15));

      print('📡 Signup response: ${response.statusCode}');
      print('📡 Signup response body: ${response.body}');

      if (response.statusCode == 201) {
        final data = json.decode(response.body);
        print('✅ User created successfully');
        return data;
      } else {
        final errorData = json.decode(response.body);
        throw ApiException(errorData['message'] ??
            'Registration failed with status ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Signup error: $e');
      if (e is http.ClientException) {
        throw ApiException(
            'Network error: Cannot connect to server. Check your internet connection and ensure backend is running.');
      } else if (e is ApiException) {
        rethrow;
      } else {
        throw ApiException('Registration failed: $e');
      }
    }
  }

  // User Login
  static Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    try {
      // First test connection
      final connection = await testBackendConnection();
      if (!connection['connected']) {
        throw ApiException(
            'Cannot connect to backend: ${connection['message']}');
      }

      print('🔐 User login attempt: $email');

      final response = await http
          .post(
            Uri.parse('$baseUrl/auth/login'),
            headers: _getAuthHeaders(includeAuth: false),
            body: json.encode({
              'email': email,
              'password': password,
            }),
          )
          .timeout(const Duration(seconds: 15));

      print('📡 Login response: ${response.statusCode}');
      print('📡 Login response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        // Store the authentication token and user info
        final session = data['session'];
        final user = data['user'];

        if (session != null && session['access_token'] != null) {
          setAuthToken(session['access_token'], user['id']);
        }

        print('✅ Login successful');
        return data;
      } else {
        final errorData = json.decode(response.body);
        throw ApiException(errorData['message'] ??
            'Login failed with status ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Login error: $e');
      if (e is http.ClientException) {
        throw ApiException(
            'Network error: Cannot connect to server. Check your internet connection and ensure backend is running.');
      } else if (e is ApiException) {
        rethrow;
      } else {
        throw ApiException('Login failed: $e');
      }
    }
  }

  // Verify Token
  static Future<Map<String, dynamic>> verifyToken(String token) async {
    try {
      print('🔍 Verifying authentication token...');

      final response = await http
          .post(
            Uri.parse('$baseUrl/auth/verify-token'),
            headers: _getAuthHeaders(includeAuth: false),
            body: json.encode({
              'access_token': token,
            }),
          )
          .timeout(const Duration(seconds: 10));

      print('📡 Token verification response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        // Update the stored token and user info
        final user = data['user'];
        setAuthToken(token, user['id']);

        print('✅ Token verified successfully');
        return data;
      } else {
        throw ApiException(
            'Token verification failed with status ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Token verification error: $e');
      throw ApiException('Token verification failed: $e');
    }
  }

  // Get User Profile
  static Future<Map<String, dynamic>> getUserProfile() async {
    try {
      if (!isAuthenticated) {
        throw ApiException('Not authenticated');
      }

      final response = await http
          .get(
            Uri.parse('$baseUrl/auth/profile'),
            headers: _getAuthHeaders(),
          )
          .timeout(const Duration(seconds: 10));

      print('📡 Profile response: ${response.statusCode}');

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else if (response.statusCode == 401) {
        throw ApiException('Authentication required. Please login again.');
      } else {
        throw ApiException(
            'Failed to load profile: Server returned ${response.statusCode}');
      }
    } catch (e) {
      if (e is http.ClientException) {
        throw ApiException(
            'Network error: Please check your internet connection');
      } else if (e is ApiException) {
        rethrow;
      } else {
        throw ApiException('Unexpected error: $e');
      }
    }
  }

  // Update User Profile
  static Future<Map<String, dynamic>> updateProfile({
    String? firstName,
    String? lastName,
    String? phoneNumber,
    String? address,
  }) async {
    try {
      final response = await http
          .put(
            Uri.parse('$baseUrl/auth/profile'),
            headers: _getAuthHeaders(),
            body: json.encode({
              'firstName': firstName,
              'lastName': lastName,
              'phoneNumber': phoneNumber,
              'address': address,
            }),
          )
          .timeout(const Duration(seconds: 10));

      print('📡 Profile update response: ${response.statusCode}');

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else if (response.statusCode == 401) {
        throw ApiException('Authentication required');
      } else {
        throw ApiException(
            'Failed to update profile: Server returned ${response.statusCode}');
      }
    } catch (e) {
      if (e is http.ClientException) {
        throw ApiException(
            'Network error: Please check your internet connection');
      } else if (e is ApiException) {
        rethrow;
      } else {
        throw ApiException('Unexpected error: $e');
      }
    }
  }

  // ============ SOIL DATA METHODS ============

  // Store soil data with validation (REQUIRES AUTH)
  static Future<Map<String, dynamic>> storeSoilData(
      Map<String, dynamic> soilData) async {
    try {
      // Check if user is authenticated and has userId
      if (!isAuthenticated || _userId == null) {
        throw ApiException('Authentication required. Please sign in again.');
      }

      print('💾 Storing soil data for user: $_userId - $soilData');

      // Validate required fields
      final requiredFields = [
        'humidity',
        'ph',
        'nitrogen',
        'phosphorus',
        'potassium',
        'temperature'
      ];
      final missingFields =
          requiredFields.where((field) => soilData[field] == null).toList();

      if (missingFields.isNotEmpty) {
        throw ApiException(
            'Missing required fields: ${missingFields.join(', ')}');
      }

      final response = await http
          .post(
            Uri.parse('$baseUrl/soil/store'),
            headers: _getAuthHeaders(),
            body: json.encode({
              'userId': _userId, // ✅ Add userId to request body
              'soilData': soilData,
            }),
          )
          .timeout(const Duration(seconds: 10));

      print('📡 Soil data storage response: ${response.statusCode}');
      print(
          '📡 Soil data storage response body: ${response.body}'); // Add for debugging

      if (response.statusCode == 200) {
        final result = json.decode(response.body);
        print('✅ Soil data stored successfully');
        return result;
      } else if (response.statusCode == 400) {
        final errorData = json.decode(response.body);
        throw ApiException(errorData['message'] ?? 'User ID is required');
      } else if (response.statusCode == 401) {
        throw ApiException('Authentication required. Please sign in again.');
      } else {
        final errorData = json.decode(response.body);
        throw ApiException(errorData['message'] ?? 'Failed to store soil data');
      }
    } catch (e) {
      print('❌ Soil data storage error: $e');
      if (e is http.ClientException) {
        throw ApiException(
            'Network error: Please check your internet connection');
      } else if (e is ApiException) {
        rethrow;
      } else {
        throw ApiException('Unexpected error: $e');
      }
    }
  }

  // Get soil status (REQUIRES AUTH)
  static Future<Map<String, dynamic>> getSoilStatus() async {
    try {
      // Check if user is authenticated and has userId
      if (!isAuthenticated || _userId == null) {
        throw ApiException('Authentication required. Please sign in again.');
      }

      print('🌱 Fetching soil status for user: $_userId');

      final response = await http
          .get(
            Uri.parse(
                '$baseUrl/soil/status?userId=$_userId'), // ✅ Add userId parameter
            headers: _getAuthHeaders(),
          )
          .timeout(const Duration(seconds: 10));

      print('📡 Soil status response: ${response.statusCode}');
      print(
          '📡 Soil status response body: ${response.body}'); // Add this for debugging

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('✅ Soil data received');
        return data;
      } else if (response.statusCode == 400) {
        final errorData = json.decode(response.body);
        throw ApiException(errorData['message'] ?? 'User ID is required');
      } else if (response.statusCode == 401) {
        throw ApiException('Authentication required. Please sign in again.');
      } else {
        throw ApiException(
            'Failed to get soil status: Server returned ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Soil status error: $e');
      if (e is http.ClientException) {
        throw ApiException('Network error: Cannot connect to backend');
      } else if (e is ApiException) {
        rethrow;
      } else {
        throw ApiException('Unexpected error: $e');
      }
    }
  }

  // NEW METHOD: Get soil data around a specific date for analysis
  static Future<Map<String, dynamic>> getSoilDataAroundDate(String date) async {
    try {
      // Check if user is authenticated and has userId
      if (!isAuthenticated || _userId == null) {
        throw ApiException('Authentication required. Please sign in again.');
      }

      print('🌱 Fetching soil data around date: $date for user: $_userId');

      final response = await http
          .get(
            Uri.parse(
                '$baseUrl/soil/data-around-date?userId=$_userId&analysisDate=$date'),
            headers: _getAuthHeaders(),
          )
          .timeout(const Duration(seconds: 10));

      print('📡 Soil data around date response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('✅ Soil data around date received');
        return data['soil_data'] ?? {};
      } else if (response.statusCode == 404) {
        print('⚠️  No soil data found for this analysis date');
        return {};
      } else if (response.statusCode == 401) {
        throw ApiException('Authentication required. Please sign in again.');
      } else {
        print(
            '⚠️  Failed to get soil data around date: ${response.statusCode}');
        return {};
      }
    } catch (e) {
      print('❌ Soil data around date error: $e');
      return {};
    }
  }

  // Get latest soil analysis from Flask API
  static Future<Map<String, dynamic>> getSoilAnalysis() async {
    try {
      final url = Uri.parse('$baseUrl/soil_analysis');
      final response = await http.get(url).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data;
      } else {
        final errorData = json.decode(response.body);
        throw ApiException(
            errorData['error'] ?? 'Failed to fetch soil analysis');
      }
    } catch (e) {
      throw ApiException('Error fetching soil analysis: $e');
    }
  }

  // ============ IMAGE METHODS (BATCH ONLY) ============

  // Store BATCH enhanced images (REQUIRES AUTH) - ONLY BATCH METHOD
  static Future<Map<String, dynamic>> storeBatchImages({
    required List<Map<String, dynamic>> images,
  }) async {
    try {
      // Check if user is authenticated and has userId
      if (!isAuthenticated || _userId == null) {
        throw ApiException('Authentication required. Please sign in again.');
      }

      print('🖼️ Storing BATCH of ${images.length} images for user: $_userId');

      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/images/upload-batch'),
      );

      // Add auth header
      if (_authToken != null) {
        request.headers['Authorization'] = 'Bearer $_authToken';
      }

      // Add userId field
      request.fields['userId'] = _userId!;

       // Generate batch timestamp IN UTC
  final batchTimestamp = DateTime.now().toUtc().toIso8601String(); // Use UTC
  request.fields['batch_timestamp'] = batchTimestamp;

      // Add each image as a separate file with its adjustments and batch index
      for (var i = 0; i < images.length; i++) {
        final imageData = images[i];
        final imageBytes = imageData['imageBytes'] as Uint8List;

        // Add the image file
        request.files.add(http.MultipartFile.fromBytes(
          'images',
          imageBytes,
          filename: imageData['fileName'] ??
              'batch_image_${DateTime.now().millisecondsSinceEpoch}_$i.jpg',
        ));

        // Add adjustment data for this image
        request.fields['brightness_$i'] = imageData['brightness'].toString();
        request.fields['contrast_$i'] = imageData['contrast'].toString();
        request.fields['saturation_$i'] = imageData['saturation'].toString();
        request.fields['batch_index_$i'] = i.toString();
      }

      // Add metadata about the batch
      request.fields['image_count'] = images.length.toString();
      request.fields['batch_timestamp'] = batchTimestamp;

      print('📤 Sending batch upload request:');
      print('   - userId: $_userId');
      print('   - batch_timestamp: $batchTimestamp');
      print('   - total images: ${images.length}');

      var response = await request.send();
      final responseString = await response.stream.bytesToString();

      print('📡 Batch upload response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final result = json.decode(responseString);
        print('✅ Batch image upload successful');
        
        // Add batch timestamp to result for later reference
        result['batch_timestamp'] = batchTimestamp;
        
        return result;
      } else if (response.statusCode == 400) {
        final errorData = json.decode(responseString);
        throw ApiException(errorData['message'] ?? 'Invalid batch data');
      } else if (response.statusCode == 401) {
        throw ApiException('Authentication required. Please sign in again.');
      } else {
        final errorData = json.decode(responseString);
        throw ApiException(errorData['message'] ??
            'Failed to store batch images: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Batch image upload error: $e');
      if (e is http.ClientException) {
        throw ApiException(
            'Network error: Please check your internet connection');
      } else if (e is ApiException) {
        rethrow;
      } else {
        throw ApiException('Unexpected error: $e');
      }
    }
  }

  // Get user images
  static Future<List<Map<String, dynamic>>> getUserImages(
      {int limit = 10}) async {
    try {
      // Check if user is authenticated and has userId
      if (!isAuthenticated || _userId == null) {
        throw ApiException('Authentication required. Please sign in again.');
      }

      final response = await http
          .get(
            Uri.parse('$baseUrl/images/user-images?userId=$_userId&limit=$limit'),
            headers: _getAuthHeaders(),
          )
          .timeout(const Duration(seconds: 10));

      print('📡 User images response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return List<Map<String, dynamic>>.from(data['images'] ?? []);
      } else if (response.statusCode == 401) {
        throw ApiException('Authentication required. Please sign in again.');
      } else {
        throw ApiException(
            'Failed to load user images: Server returned ${response.statusCode}');
      }
    } catch (e) {
      if (e is http.ClientException) {
        throw ApiException(
            'Network error: Please check your internet connection');
      } else if (e is ApiException) {
        rethrow;
      } else {
        throw ApiException('Unexpected error: $e');
      }
    }
  }

  // NEW METHOD: Get images around a specific date for analysis
  static Future<List<Map<String, dynamic>>> getImagesAroundDate(String date,
      {int limit = 10}) async {
    try {
      // Check if user is authenticated and has userId
      if (!isAuthenticated || _userId == null) {
        throw ApiException('Authentication required. Please sign in again.');
      }

      print('🖼️ Fetching images around date: $date for user: $_userId');

      final response = await http
          .get(
            Uri.parse(
                '$baseUrl/images/images-around-date?userId=$_userId&analysisDate=$date&limit=$limit'),
            headers: _getAuthHeaders(),
          )
          .timeout(const Duration(seconds: 10));

      print('📡 Images around date response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('✅ Images around date received: ${data['images']?.length ?? 0}');
        return List<Map<String, dynamic>>.from(data['images'] ?? []);
      } else if (response.statusCode == 404) {
        print('⚠️  No images found for this analysis date');
        return [];
      } else if (response.statusCode == 401) {
        throw ApiException('Authentication required. Please sign in again.');
      } else {
        print('⚠️  Failed to get images around date: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      print('❌ Images around date error: $e');
      return [];
    }
  }

  // Get latest analysis result
  static Future<Map<String, dynamic>?> getLatestAnalysis() async {
    try {
      if (!isAuthenticated || _userId == null) {
        throw ApiException('Authentication required. Please sign in again.');
      }

      final response = await http
          .get(
            Uri.parse('$baseUrl/analysis/results/latest?userId=$_userId'),
            headers: _getAuthHeaders(),
          )
          .timeout(const Duration(seconds: 10));

      print('📡 Latest analysis response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['analysis'];
      } else if (response.statusCode == 404) {
        return null; // No analysis found
      } else if (response.statusCode == 401) {
        throw ApiException('Authentication required. Please sign in again.');
      } else {
        throw ApiException(
            'Failed to load latest analysis: Server returned ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error fetching latest analysis: $e');
      return null; // Return null instead of throwing to avoid breaking the UI
    }
  }

  // Get latest image for user
  static Future<Map<String, dynamic>?> getLatestImage() async {
    try {
      if (!isAuthenticated || _userId == null) {
        throw ApiException('Authentication required. Please sign in again.');
      }

      final response = await http
          .get(
            Uri.parse('$baseUrl/images/latest?userId=$_userId'),
            headers: _getAuthHeaders(),
          )
          .timeout(const Duration(seconds: 10));

      print('📡 Latest image response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['image'];
      } else if (response.statusCode == 404) {
        return null; // No images found
      } else if (response.statusCode == 401) {
        throw ApiException('Authentication required. Please sign in again.');
      } else {
        throw ApiException(
            'Failed to load latest image: Server returned ${response.statusCode}');
      }
    } catch (e) {
      if (e is http.ClientException) {
        throw ApiException(
            'Network error: Please check your internet connection');
      } else if (e is ApiException) {
        rethrow;
      } else {
        throw ApiException('Unexpected error: $e');
      }
    }
  }

  // ============ ANALYSIS METHODS ============

  // Check data status for analysis (REQUIRES AUTH) - UPDATED FOR BATCH
  static Future<Map<String, dynamic>> checkDataStatus() async {
    try {
      // Check if user is authenticated and has userId
      if (!isAuthenticated || _userId == null) {
        throw ApiException('Authentication required. Please sign in again.');
      }

      print('📊 Checking real-time data status for user: $_userId');

      final response = await http
          .get(
            Uri.parse('$baseUrl/analysis/data-status?userId=$_userId'),
            headers: _getAuthHeaders(),
          )
          .timeout(const Duration(seconds: 10));

      print('📡 Data status response: ${response.statusCode}');
      print('📡 Data status response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        // Handle new response structure with can_analyze_batch
        bool canAnalyze;
        bool canAnalyzeOptimal;
        
        if (data['can_analyze_batch'] != null) {
          canAnalyze = data['can_analyze_batch'] as bool;
          canAnalyzeOptimal = data['can_analyze_batch'] as bool; // Use same for batch
        } else if (data['can_analyze'] != null && data['can_analyze'] is bool) {
          canAnalyze = data['can_analyze'];
          canAnalyzeOptimal = data['can_analyze_optimal'] as bool? ?? false;
        } else {
          // If no explicit flag, check if we have both soil and images
          final soilExists = data['soil_data']?['exists'] ?? false;
          final imageExists = (data['available_images']?['count'] ?? 0) > 0;
          canAnalyze = soilExists && imageExists;
          canAnalyzeOptimal = false;
        }
        
        // Create a corrected response
        final correctedData = Map<String, dynamic>.from(data);
        correctedData['can_analyze'] = canAnalyze;
        correctedData['can_analyze_optimal'] = canAnalyzeOptimal;

        print('✅ Data status received - can_analyze: $canAnalyze, can_analyze_batch: ${data['can_analyze_batch']}');
        return correctedData;
      } else if (response.statusCode == 400) {
        final errorData = json.decode(response.body);
        throw ApiException(errorData['message'] ?? 'User ID is required');
      } else if (response.statusCode == 401) {
        throw ApiException('Authentication required. Please login again.');
      } else {
        throw ApiException(
            'Failed to check data status: Server returned ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Data status check error: $e');
      if (e is http.ClientException) {
        throw ApiException('Network error: Cannot connect to backend');
      } else if (e is ApiException) {
        rethrow;
      } else {
        throw ApiException('Unexpected error: $e');
      }
    }
  }

  // Perform REAL-TIME analysis with validation (REQUIRES AUTH)
  static Future<Map<String, dynamic>> performRealTimeAnalysis({
    String? batchTimestamp,
    Map<String, dynamic>? imageData,
  }) async {
    try {
      // Check if user is authenticated and has userId
      if (!isAuthenticated || _userId == null) {
        throw ApiException('Authentication required. Please sign in again.');
      }

      print('🔍 Starting REAL-TIME analysis for user: $_userId');
      
      // Log analysis type
      if (batchTimestamp != null) {
        print('📦 Batch analysis requested for batch: $batchTimestamp');
      } else if (imageData != null) {
        print('🖼️ Single image analysis requested');
      } else {
        print('🔍 Default analysis (latest image) requested');
      }

      // First check data status
      final status = await checkDataStatus();

      if (!status['can_analyze']) {
        final soilStatus = status['soil_data']['status'];
        final imageStatus = status['image_data']['status'];

        String errorMessage = '❌ Cannot perform real-time analysis:\n\n';

        if (soilStatus == 'missing') {
          errorMessage += '• 📊 No soil data available\n';
        } else if (soilStatus == 'stale') {
          errorMessage +=
              '• ⏰ Soil data is outdated (${status['soil_data']['age_hours']} hours old)\n';
        }

        if (imageStatus == 'missing') {
          errorMessage += '• 🖼️ No plant image available\n';
        } else if (imageStatus == 'stale') {
          errorMessage +=
              '• ⏰ Plant image is outdated (${status['image_data']['age_hours']} hours old)\n';
        }

        errorMessage +=
            '\n💡 Please add current soil measurements and plant images (max 24 hours old).';
        throw ApiException(errorMessage);
      }

      print('✅ Data is fresh, proceeding with analysis...');

      // Prepare request body based on analysis type
      final Map<String, dynamic> requestBody = {
        'userId': _userId,
      };

      // Add batch timestamp if provided
      if (batchTimestamp != null) {
        requestBody['batchTimestamp'] = batchTimestamp;
        print('📤 Sending batch analysis request for timestamp: $batchTimestamp');
      }
      
      // Add image data if provided
      if (imageData != null) {
        requestBody['imageData'] = imageData;
        print('📤 Sending custom image analysis request');
      }

      // Proceed with analysis
      final response = await http
          .post(
            Uri.parse('$baseUrl/analysis/integrated'),
            headers: _getAuthHeaders(),
            body: json.encode(requestBody),
          )
          .timeout(const Duration(seconds: 90)); // Increased timeout for batch analysis

      print('📡 Analysis response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('✅ Real-time analysis completed successfully');
        
        // Log analysis type in result
        if (batchTimestamp != null) {
          print('📊 Batch analysis completed for ${data['total_images'] ?? 'multiple'} images');
        }
        
        return data;
      } else if (response.statusCode == 401) {
        throw ApiException('Authentication required. Please sign in again.');
      } else {
        final errorData = json.decode(response.body);
        throw ApiException(errorData['message'] ??
            'Analysis failed with status ${response.statusCode}');
      }
    } catch (e) {
      rethrow;
    }
  }

  // NEW: Batch analysis method
// In ApiService.performBatchAnalysis(), after getting response:
static Future<Map<String, dynamic>> performBatchAnalysis() async {
  try {
    if (!isAuthenticated || _userId == null) {
      throw ApiException('Authentication required. Please sign in again.');
    }

    print('📦 Starting BATCH analysis for user: $_userId');

    // Prepare request
    final Map<String, dynamic> requestBody = {
      'userId': _userId,
      'useLatestSoil': true,
      'batchSize': 20,
      'analysisMode': 'both'
    };

    final response = await http
        .post(
          Uri.parse('$baseUrl/analysis/analyze-batch'),
          headers: _getAuthHeaders(),
          body: json.encode(requestBody),
        )
        .timeout(const Duration(seconds: 120));

    print('📡 Batch analysis response: ${response.statusCode}');

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      print('✅ Batch analysis completed successfully');
      
      // ⚠️ CRITICAL FIX: Get batch timestamp from batch_info
      final batchInfo = data['batch_info'];
      final batchId = batchInfo?['batch_timestamp'] as String?;
      
      // If no batch timestamp in batch_info, try to get it from the first stored result
      if (batchId == null && data['storage'] != null) {
        final storage = data['storage'] as Map<String, dynamic>;
        final storedBatchId = storage['batch_timestamp'] as String?;
        if (storedBatchId != null) {
          print('🔄 Using batch timestamp from storage: $storedBatchId');
          data['batch_info']['batch_timestamp'] = storedBatchId;
        }
      }
      
      print('📊 Processed ${data['batch_info']?['analyzed_images'] ?? '?'} images');
      return data;
    } else if (response.statusCode == 401) {
      throw ApiException('Authentication required. Please sign in again.');
    } else {
      final errorData = json.decode(response.body);
      throw ApiException(errorData['message'] ??
          'Batch analysis failed with status ${response.statusCode}');
    }
  } catch (e) {
    rethrow;
  }
}
  // NEW: Run batch analysis for specific timestamp
  static Future<Map<String, dynamic>> performBatchAnalysisForTimestamp(String batchTimestamp) async {
    try {
      if (!isAuthenticated || _userId == null) {
        throw ApiException('Authentication required. Please sign in again.');
      }

      print('📦 Running batch analysis for timestamp: $batchTimestamp');

      final response = await http
          .post(
            Uri.parse('$baseUrl/analysis/analyze-batch'),
            headers: _getAuthHeaders(),
            body: json.encode({
              'userId': _userId,
              'batchTimestamp': batchTimestamp,
              'useLatestSoil': true,
              'analysisMode': 'both'
            }),
          )
          .timeout(const Duration(seconds: 120));

      print('📡 Batch analysis response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('✅ Batch analysis completed successfully');
        return data;
      } else if (response.statusCode == 401) {
        throw ApiException('Authentication required. Please sign in again.');
      } else {
        final errorData = json.decode(response.body);
        throw ApiException(errorData['message'] ??
            'Batch analysis failed with status ${response.statusCode}');
      }
    } catch (e) {
      rethrow;
    }
  }



  // Get analysis history with enhanced data
  static Future<List<Map<String, dynamic>>> getAnalysisHistory(
      {int limit = 20}) async {
    try {
      if (!isAuthenticated || _userId == null) {
        throw ApiException('Authentication required. Please sign in again.');
      }

      final response = await http
          .get(
            Uri.parse('$baseUrl/analysis/history?userId=$_userId&limit=$limit'),
            headers: _getAuthHeaders(),
          )
          .timeout(const Duration(seconds: 10));

      print('📡 Analysis history response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return List<Map<String, dynamic>>.from(data['history'] ?? []);
      } else if (response.statusCode == 401) {
        throw ApiException('Authentication required. Please sign in again.');
      } else {
        throw ApiException(
            'Failed to load analysis history: Server returned ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error fetching analysis history: $e');
      throw ApiException('Failed to load analysis history: $e');
    }
  }

  // Get specific analysis with associated data
  static Future<Map<String, dynamic>> getAnalysisWithData(
      String analysisId) async {
    try {
      if (!isAuthenticated || _userId == null) {
        throw ApiException('Authentication required. Please sign in again.');
      }

      print('🔍 Fetching analysis with data for ID: $analysisId');

      final response = await http
          .get(
            Uri.parse(
                '$baseUrl/analysis/with-data?userId=$_userId&analysisId=$analysisId'),
            headers: _getAuthHeaders(),
          )
          .timeout(const Duration(seconds: 10));

      print('📡 Analysis with data response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data;
      } else if (response.statusCode == 404) {
        throw ApiException('Analysis not found');
      } else if (response.statusCode == 401) {
        throw ApiException('Authentication required. Please sign in again.');
      } else {
        throw ApiException(
            'Failed to load analysis data: Server returned ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error fetching analysis with data: $e');
      throw ApiException('Failed to load analysis data: $e');
    }
  }

  // ============ BATCH ANALYSIS METHODS ============

  // Get batch analysis history
  static Future<List<Map<String, dynamic>>> getBatchHistory() async {
    try {
      if (!isAuthenticated || _userId == null) {
        throw ApiException('Authentication required. Please sign in again.');
      }

      final response = await http
          .get(
            Uri.parse('$baseUrl/analysis/batch-history?userId=$_userId'),
            headers: _getAuthHeaders(),
          )
          .timeout(const Duration(seconds: 10));

      print('📡 Batch history response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return List<Map<String, dynamic>>.from(data['batches'] ?? []);
      } else if (response.statusCode == 401) {
        throw ApiException('Authentication required. Please sign in again.');
      } else {
        throw ApiException(
            'Failed to load batch history: Server returned ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error fetching batch history: $e');
      throw ApiException('Failed to load batch history: $e');
    }
  }

  // Get specific batch details
// Get specific batch details - UPDATED WITH TIMESTAMP FIX
static Future<Map<String, dynamic>> getBatchDetails(String batchId) async {
  try {
    if (!isAuthenticated || _userId == null) {
      throw ApiException('Authentication required. Please sign in again.');
    }

    print('🔍 [API] Fetching batch details for ID: $batchId');
    
    // Convert Z to +00:00 format for database matching
    String normalizedBatchId = batchId;
    if (batchId.endsWith('Z')) {
      normalizedBatchId = batchId.replaceFirst('Z', '+00:00');
      print('🔄 [API] Normalized batch ID: $normalizedBatchId (original: $batchId)');
    }

    // Try with normalized ID first
    final url = '$baseUrl/analysis/batch/$normalizedBatchId?userId=$_userId&details=true';
    print('🌐 [API] Calling URL: $url');

    final response = await http
        .get(
          Uri.parse(url),
          headers: _getAuthHeaders(),
        )
        .timeout(const Duration(seconds: 10));

    print('📡 [API] Batch details response: ${response.statusCode}');

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      print('✅ [API] Batch details received successfully');
      return data;
    } 
    
    // If normalized fails, try original
    if (response.statusCode == 404 && batchId != normalizedBatchId) {
      print('🔄 [API] Trying with original batch ID...');
      final originalUrl = '$baseUrl/analysis/batch/$batchId?userId=$_userId&details=true';
      
      final originalResponse = await http
          .get(
            Uri.parse(originalUrl),
            headers: _getAuthHeaders(),
          )
          .timeout(const Duration(seconds: 5));

      if (originalResponse.statusCode == 200) {
        final data = json.decode(originalResponse.body);
        print('✅ [API] Batch details received with original ID');
        return data;
      }
    }
    
    // Handle errors
    final errorData = json.decode(response.body);
    throw ApiException(
      errorData['message'] ??
      'Failed to load batch details: Server returned ${response.statusCode}'
    );
    
  } catch (e) {
    print('❌ [API] Error fetching batch details: $e');
    throw ApiException('Failed to load batch details: $e');
  }
}

  // Get user batches
  static Future<List<Map<String, dynamic>>> getUserBatches() async {
    try {
      if (!isAuthenticated || _userId == null) {
        throw ApiException('Authentication required. Please sign in again.');
      }

      final response = await http
          .get(
            Uri.parse('$baseUrl/images/user-batches?userId=$_userId'),
            headers: _getAuthHeaders(),
          )
          .timeout(const Duration(seconds: 10));

      print('📡 User batches response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return List<Map<String, dynamic>>.from(data['batches'] ?? []);
      } else if (response.statusCode == 401) {
        throw ApiException('Authentication required. Please sign in again.');
      } else {
        throw ApiException(
            'Failed to load user batches: Server returned ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error fetching user batches: $e');
      throw ApiException('Failed to load user batches: $e');
    }
  }

  // ============ UTILITY METHODS ============

  // Enhanced connection test with detailed diagnostics
  static Future<Map<String, dynamic>> diagnoseConnection() async {
    final results = <String, dynamic>{};

    try {
      // Test basic connectivity
      print('🔍 Running connection diagnostics...');

      // Test 1: Basic HTTP connectivity
      final healthResponse = await http.get(
        Uri.parse('$baseUrl/health'),
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      results['basic_connectivity'] = healthResponse.statusCode == 200;
      results['health_status'] = healthResponse.statusCode;

      if (healthResponse.statusCode == 200) {
        final healthData = json.decode(healthResponse.body);
        results['backend_details'] = healthData;
      }

      // Test 2: Database connectivity (via auth status)
      if (isAuthenticated) {
        try {
          final profileResponse = await http
              .get(
                Uri.parse('$baseUrl/auth/profile'),
                headers: _getAuthHeaders(),
              )
              .timeout(const Duration(seconds: 5));

          results['database_connectivity'] = profileResponse.statusCode == 200;
          results['auth_status'] = profileResponse.statusCode;
        } catch (e) {
          results['database_connectivity'] = false;
          results['database_error'] = e.toString();
        }
      }

      // Test 3: Storage connectivity (via images endpoint)
      try {
        final imagesResponse = await http
            .get(
              Uri.parse('$baseUrl/images/health'),
              headers: _getAuthHeaders(),
            )
            .timeout(const Duration(seconds: 5));

        results['storage_connectivity'] = imagesResponse.statusCode == 200;
      } catch (e) {
        results['storage_connectivity'] = false;
      }

      results['diagnosis_complete'] = true;
      results['overall_status'] =
          results['basic_connectivity'] ? 'healthy' : 'unhealthy';
    } catch (e) {
      results['diagnosis_complete'] = false;
      results['error'] = e.toString();
      results['overall_status'] = 'failed';
    }

    print('📊 Connection diagnostics: $results');
    return results;
  }

  // Validate soil data before sending
  static void validateSoilData(Map<String, dynamic> soilData) {
    final errors = <String>[];

    // Check required fields
    final requiredFields = [
      'moisture',
      'ph',
      'nitrogen',
      'phosphorus',
      'potassium',
      'temperature'
    ];
    for (final field in requiredFields) {
      if (soilData[field] == null) {
        errors.add('$field is required');
      }
    }

    // Validate ranges
    if (soilData['moisture'] != null &&
        (soilData['moisture'] < 0 || soilData['moisture'] > 100)) {
      errors.add('Moisture must be between 0-100%');
    }

    if (soilData['ph'] != null && (soilData['ph'] < 0 || soilData['ph'] > 14)) {
      errors.add('pH must be between 0-14');
    }

    if (soilData['temperature'] != null &&
        (soilData['temperature'] < -10 || soilData['temperature'] > 60)) {
      errors.add('Temperature must be between -10°C and 60°C');
    }

    if (errors.isNotEmpty) {
      throw ApiException('Invalid soil data:\n${errors.join('\n')}');
    }
  }

  // Utility method to format soil data for display
  static Map<String, dynamic> formatSoilDataForDisplay(
      Map<String, dynamic> soilData) {
    return {
      'npk_levels': {
        'nitrogen': '${soilData['nitrogen']?.toStringAsFixed(1)}%',
        'phosphorus': '${soilData['phosphorus']?.toStringAsFixed(1)}%',
        'potassium': '${soilData['potassium']?.toStringAsFixed(1)}%',
      },
      'other_parameters': {
        'ph': soilData['ph']?.toStringAsFixed(1),
        'moisture': '${soilData['moisture']?.toStringAsFixed(1)}%',
        'temperature': '${soilData['temperature']?.toStringAsFixed(1)}°C',
        'conductivity': soilData['conductivity']?.toStringAsFixed(2),
      }
    };
  }

  // Debug method to check current user state
  static void debugUserState() {
    print('🔍 Debug User State:');
    print('   - Current User ID: $_userId');
    print('   - Is Authenticated: $isAuthenticated');
    print('   - Auth Token: ${_authToken != null ? "Present" : "Missing"}');
  }

  // Call this before making soil requests to debug
  static Future<void> debugSoilStatusRequest() async {
    debugUserState();

    if (_userId == null) {
      print('❌ No user ID set!');
      return;
    }

    try {
      final url = '$baseUrl/soil/status?userId=$_userId';
      print('🌱 Testing URL: $url');

      final response = await http.get(
        Uri.parse(url),
        headers: _getAuthHeaders(),
      );

      print('📡 Response status: ${response.statusCode}');
      print('📡 Response body: ${response.body}');
    } catch (e) {
      print('❌ Debug request failed: $e');
    }
  }

  

  // ============ PROPERTIES ============

  // Check if user is authenticated
  static bool get isAuthenticated => _authToken != null;

  // Get current user ID
  static String? get currentUserId => _userId;

  // Get current auth token
  static String? get currentToken => _authToken;

  // Logout
  static void logout() {
    _authToken = null;
    _userId = null;
    print('🔓 User logged out');
  }

  // Clear authentication (alias for logout)
  static void clearAuth() {
    logout();
  }
}

class ApiException implements Exception {
  final String message;
  ApiException(this.message);

  @override
  String toString() => message;
}


