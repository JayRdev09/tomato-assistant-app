import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:typed_data';
import 'dart:ui' as ui;
import '../services/api_service.dart';
import 'dart:math'; // Add this import
class DiseaseDetectionScreen extends StatefulWidget {
  final VoidCallback? onProceed;
  
  const DiseaseDetectionScreen({super.key, this.onProceed});

  @override
  State<DiseaseDetectionScreen> createState() => _DiseaseDetectionScreenState();
}

class _DiseaseDetectionScreenState extends State<DiseaseDetectionScreen> {
  Uint8List? _selectedImageBytes;
  Uint8List? _originalImageBytes;
  List<Uint8List> _batchImages = [];
  List<Map<String, dynamic>> _batchImageData = []; // Stores image data with adjustments
  bool _isProcessing = false;
  bool _isStoringBatch = false;
  String? _errorMessage;
  bool _showAdjustmentPanel = false;
  bool _imageStored = false;
  int _currentImageIndex = -1;
  bool _batchMode = false;
  bool _isCapturing = false;

  // Image adjustment parameters
  double _brightness = 75.0;
  double _contrast = 75.0;
  double _saturation = 75.0;

  final ImagePicker _picker = ImagePicker();

  Future<void> _pickBatchImages() async {
    try {
      setState(() {
        _errorMessage = null;
        _showAdjustmentPanel = false;
        _isProcessing = true;
      });

      if (!mounted) return;

      final List<XFile>? images = await _picker.pickMultiImage(
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 90,
      );

      if (images != null && images.isNotEmpty && mounted) {
        await _addImagesToBatch(images);
      } else {
        setState(() {
          _isProcessing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to pick images: $e';
          _isProcessing = false;
        });
      }
    }
  }

  Future<void> _captureSingleImage() async {
    try {
      setState(() {
        _errorMessage = null;
        _isCapturing = true;
      });

      if (!mounted) return;

      final XFile? image = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 90,
      );

      if (image != null && mounted) {
        final imageBytes = await image.readAsBytes();
        
        // Add to batch
        final newImageData = {
          'imageBytes': imageBytes,
          'originalBytes': imageBytes,
          'brightness': 75.0,
          'contrast': 75.0,
          'saturation': 75.0,
          'fileName': 'camera_${DateTime.now().millisecondsSinceEpoch}.jpg',
        };

        setState(() {
          _batchImageData.add(newImageData);
          _batchMode = true;
          
          // Load the newly captured image for editing
          _loadImageForEditing(_batchImageData.length - 1);
          _isCapturing = false;
        });

        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Image captured! Total: ${_batchImageData.length}'),
            duration: const Duration(seconds: 2),
          ),
        );
      } else {
        setState(() {
          _isCapturing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to capture image: $e';
          _isCapturing = false;
        });
      }
    }
  }

  Future<void> _captureMultipleImages() async {
    // Show dialog for capturing multiple images
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Capture Multiple Images'),
        content: const Text(
          'You can capture multiple images one by one.\n'
          'Each captured image will be added to the batch.\n'
          'Press "Done" when finished.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _startContinuousCapture();
            },
            child: const Text('Start Capturing'),
          ),
        ],
      ),
    );
  }

  Future<void> _startContinuousCapture() async {
    bool continueCapturing = true;
    
    while (continueCapturing && mounted) {
      final shouldContinue = await _showCaptureDialog();
      if (shouldContinue == true) {
        await _captureSingleImage();
        // Small delay to prevent rapid successive captures
        await Future.delayed(const Duration(milliseconds: 500));
      } else {
        continueCapturing = false;
      }
    }
  }

 Future<bool?> _showCaptureDialog() async {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: Text('Capture Image ${_batchImageData.length + 1}'),
      content: SingleChildScrollView(  // Add this wrapper
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Current batch: ${_batchImageData.length} images'),
            const SizedBox(height: 16),
            if (_batchImageData.isNotEmpty)
              SizedBox(
                height: 100,
                width: 300,  // Add a fixed width
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _batchImageData.length,
                  itemBuilder: (context, index) {
                    return Container(
                      margin: const EdgeInsets.all(4),
                      child: Image.memory(
                        _batchImageData[index]['imageBytes'],
                        width: 80,
                        height: 80,
                        fit: BoxFit.cover,
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Done'),
        ),
        ElevatedButton.icon(
          icon: const Icon(Icons.camera_alt),
          label: const Text('Capture Next'),
          onPressed: () => Navigator.pop(context, true),
        ),
      ],
    ),
  );
}

  Future<void> _addImagesToBatch(List<XFile> images) async {
    try {
      final List<Map<String, dynamic>> newImageDataList = [];

      for (var i = 0; i < images.length; i++) {
        final imageBytes = await images[i].readAsBytes();
        
        newImageDataList.add({
          'imageBytes': imageBytes,
          'originalBytes': imageBytes,
          'brightness': 75.0,
          'contrast': 75.0,
          'saturation': 75.0,
          'fileName': images[i].name,
        });
      }

      setState(() {
        // Add new images to existing batch
        _batchImageData.addAll(newImageDataList);
        _batchMode = true;
        
        // Load first new image for editing if no image is currently selected
        if (_currentImageIndex == -1 && _batchImageData.isNotEmpty) {
          _loadImageForEditing(0);
        }
        
        _isProcessing = false;
      });

      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Added ${newImageDataList.length} images to batch. Total: ${_batchImageData.length}'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to add images to batch: $e';
          _isProcessing = false;
        });
      }
    }
  }

  void _loadImageForEditing(int index) {
    if (index >= 0 && index < _batchImageData.length) {
      final imageData = _batchImageData[index];
      setState(() {
        _selectedImageBytes = imageData['imageBytes'];
        _originalImageBytes = imageData['originalBytes'];
        _brightness = imageData['brightness'];
        _contrast = imageData['contrast'];
        _saturation = imageData['saturation'];
        _currentImageIndex = index;
        _showAdjustmentPanel = true;
      });
    }
  }

  void _saveCurrentImageAdjustments() {
    if (_currentImageIndex >= 0 && _currentImageIndex < _batchImageData.length) {
      setState(() {
        _batchImageData[_currentImageIndex] = {
          ..._batchImageData[_currentImageIndex],
          'imageBytes': _selectedImageBytes,
          'brightness': _brightness,
          'contrast': _contrast,
          'saturation': _saturation,
        };
      });
    }
  }

  void _resetAdjustments() {
    setState(() {
      _brightness = 75.0;
      _contrast = 75.0;
      _saturation = 75.0;
    });
    _resetToOriginal();
  }

  void _resetToOriginal() {
    if (_originalImageBytes != null) {
      setState(() {
        _selectedImageBytes = _originalImageBytes;
      });
    }
  }

  Future<void> _applyAdjustments() async {
    if (_originalImageBytes == null) return;

    try {
      setState(() {
        _isProcessing = true;
      });

      final adjustedImage = await _adjustImage(
        _originalImageBytes!,
        brightness: _brightness,
        contrast: _contrast,
        saturation: _saturation,
      );

      setState(() {
        _selectedImageBytes = adjustedImage;
        _isProcessing = false;
      });

      // Save adjustments if in batch mode
      if (_batchMode && _currentImageIndex >= 0) {
        _saveCurrentImageAdjustments();
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to adjust image: $e';
        _isProcessing = false;
      });
    }
  }

  Future<Uint8List> _adjustImage(
    Uint8List imageBytes, {
    required double brightness,
    required double contrast,
    required double saturation,
  }) async {
    try {
      final codec = await ui.instantiateImageCodec(imageBytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final paint = Paint();

      final colorFilter = ui.ColorFilter.matrix(_getColorFilterMatrix(
        brightness: brightness,
        contrast: contrast,
        saturation: saturation,
      ));

      paint.colorFilter = colorFilter;
      canvas.drawImage(image, Offset.zero, paint);

      final picture = recorder.endRecording();
      final adjustedImage = await picture.toImage(image.width, image.height);
      final byteData =
          await adjustedImage.toByteData(format: ui.ImageByteFormat.png);

      return byteData!.buffer.asUint8List();
    } catch (e) {
      throw Exception('Image adjustment failed: $e');
    }
  }

  List<double> _getColorFilterMatrix({
    required double brightness,
    required double contrast,
    required double saturation,
  }) {
    final b = (brightness - 75.0) / 25.0;
    final c = contrast / 75.0;
    final s = saturation / 75.0;

    const rWeight = 0.299;
    const gWeight = 0.587;
    const bWeight = 0.114;

    return [
      c * ((1.0 - s) * rWeight + s),
      c * ((1.0 - s) * gWeight),
      c * ((1.0 - s) * bWeight),
      0,
      b,
      c * ((1.0 - s) * rWeight),
      c * ((1.0 - s) * gWeight + s),
      c * ((1.0 - s) * bWeight),
      0,
      b,
      c * ((1.0 - s) * rWeight),
      c * ((1.0 - s) * gWeight),
      c * ((1.0 - s) * bWeight + s),
      0,
      b,
      0,
      0,
      0,
      1,
      0,
    ];
  }

  Future<void> _storeBatchImages() async {
    if (_batchImageData.isEmpty) return;

    setState(() {
      _isStoringBatch = true;
      _errorMessage = null;
    });

    try {
      // Convert batch data to format expected by API
      final List<Map<String, dynamic>> imagesToStore = [];
      
      for (var imageData in _batchImageData) {
        imagesToStore.add({
          'imageBytes': imageData['imageBytes'],
          'brightness': imageData['brightness'],
          'contrast': imageData['contrast'],
          'saturation': imageData['saturation'],
          'fileName': imageData['fileName'],
        });
      }

      // Call batch API endpoint
      final result = await ApiService.storeBatchImages(
        images: imagesToStore,
      );

      if (mounted) {
        setState(() {
          _imageStored = true;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result['message'] ?? '${_batchImageData.length} images stored successfully!'
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to store batch images: ${e.message}';
          _imageStored = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Unexpected error: $e';
          _imageStored = false;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isStoringBatch = false;
        });
      }
    }
  }

  void _clearResults() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear All Images'),
        content: const Text('Are you sure you want to clear all images from the batch?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                _selectedImageBytes = null;
                _originalImageBytes = null;
                _batchImages.clear();
                _batchImageData.clear();
                _errorMessage = null;
                _showAdjustmentPanel = false;
                _imageStored = false;
                _batchMode = false;
                _currentImageIndex = -1;
                _resetAdjustments();
              });
            },
            child: const Text('Clear All', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _toggleAdjustmentPanel() {
    setState(() {
      _showAdjustmentPanel = !_showAdjustmentPanel;
    });
  }

  void _proceedToSoilAnalysis() {
    if (widget.onProceed != null) {
      widget.onProceed!();
    }
  }

  void _removeImageAtIndex(int index) {
    if (index >= 0 && index < _batchImageData.length) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Remove Image'),
          content: const Text('Are you sure you want to remove this image from the batch?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                setState(() {
                  _batchImageData.removeAt(index);
                  
                  // Adjust current index if needed
                  if (_batchImageData.isEmpty) {
                    _currentImageIndex = -1;
                    _selectedImageBytes = null;
                    _originalImageBytes = null;
                    _batchMode = false;
                  } else {
                    if (_currentImageIndex >= index) {
                      _currentImageIndex = max(0, _currentImageIndex - 1);
                    }
                    if (_currentImageIndex >= 0) {
                      _loadImageForEditing(_currentImageIndex);
                    }
                  }
                });
                
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Image removed from batch'),
                    duration: Duration(seconds: 2),
                  ),
                );
              },
              child: const Text('Remove', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Plant Image Enhancement',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Capture and enhance plant images for storage',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
              const SizedBox(height: 24),

              // Batch mode indicator
              if (_batchMode && _batchImageData.isNotEmpty)
                Card(
                  color: Colors.blue[50],
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Row(
                      children: [
                        const Icon(Icons.collections, color: Colors.blue),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Batch Mode: ${_batchImageData.length} image${_batchImageData.length > 1 ? 's' : ''} selected',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.blue,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 20),
                          onPressed: _clearResults,
                        ),
                      ],
                    ),
                  ),
                ),

              // Image Thumbnails (Batch Mode)
              if (_batchMode && _batchImageData.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(bottom: 8.0),
                        child: Text(
                          'Batch Images',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      SizedBox(
                        height: 100,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: _batchImageData.length,
                          itemBuilder: (context, index) {
                            final isSelected = index == _currentImageIndex;
                            return Container(
                              margin: const EdgeInsets.only(right: 8),
                              child: Stack(
                                children: [
                                  GestureDetector(
                                    onTap: () => _loadImageForEditing(index),
                                    child: Container(
                                      padding: const EdgeInsets.all(2),
                                      decoration: BoxDecoration(
                                        border: Border.all(
                                          color: isSelected ? Colors.blue : Colors.grey.shade300,
                                          width: isSelected ? 2 : 1,
                                        ),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Image.memory(
                                        _batchImageData[index]['imageBytes'],
                                        width: 80,
                                        height: 80,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    top: 0,
                                    right: 0,
                                    child: GestureDetector(
                                      onTap: () => _removeImageAtIndex(index),
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: Colors.red,
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        padding: const EdgeInsets.all(4),
                                        child: const Icon(
                                          Icons.close,
                                          color: Colors.white,
                                          size: 12,
                                        ),
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    bottom: 4,
                                    left: 4,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 4, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.black54,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        '${index + 1}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                      if (_batchImageData.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(
                            'Tap an image to edit it. Tap the red X to remove.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

              // Error Message
              if (_errorMessage != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red[50],
                    border: Border.all(color: Colors.red),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error, color: Colors.red),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 16),
                        onPressed: () => setState(() => _errorMessage = null),
                      ),
                    ],
                  ),
                ),

              if (_errorMessage != null) const SizedBox(height: 16),

              // Main Card
              Card(
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      // Image Preview
                      Container(
                        height: 200,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(8),
                          color: Colors.grey.shade50,
                        ),
                        child: _selectedImageBytes == null
                            ? const Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.photo_library,
                                      size: 50, color: Colors.grey),
                                  SizedBox(height: 8),
                                  Text('No images selected'),
                                  SizedBox(height: 4),
                                  Text(
                                    'Select or capture images to begin',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ],
                              )
                            : Stack(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.memory(
                                      _selectedImageBytes!,
                                      fit: BoxFit.cover,
                                      width: double.infinity,
                                      height: double.infinity,
                                      errorBuilder:
                                          (context, error, stackTrace) {
                                        return const Center(
                                          child: Icon(Icons.error,
                                              color: Colors.red),
                                        );
                                      },
                                    ),
                                  ),
                                  Positioned(
                                    top: 8,
                                    right: 8,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: Colors.black54,
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: IconButton(
                                        icon: const Icon(Icons.close,
                                            color: Colors.white, size: 20),
                                        onPressed: _clearResults,
                                      ),
                                    ),
                                  ),
                                  if (_isProcessing || _isCapturing)
                                    Container(
                                      color: Colors.black54,
                                      child: const Center(
                                        child: CircularProgressIndicator(
                                            color: Colors.white),
                                      ),
                                    ),
                                  // Image counter in batch mode
                                  if (_batchMode && _currentImageIndex >= 0)
                                    Positioned(
                                      bottom: 8,
                                      left: 8,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.black54,
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                        child: Text(
                                          'Image ${_currentImageIndex + 1} of ${_batchImageData.length}',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                      ),
                      const SizedBox(height: 16),

                      // Enhancement Toggle Button
                      if (_selectedImageBytes != null)
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                icon: Icon(_showAdjustmentPanel
                                    ? Icons.tune
                                    : Icons.auto_awesome),
                                label: Text(_showAdjustmentPanel
                                    ? 'Hide Adjustments'
                                    : 'Enhance Image'),
                                onPressed: _toggleAdjustmentPanel,
                              ),
                            ),
                          ],
                        ),

                      // Adjustment Panel
                      if (_showAdjustmentPanel && _selectedImageBytes != null)
                        _buildAdjustmentPanel(),

                      const SizedBox(height: 8),

                      // Capture and Gallery Buttons (when no images selected)
                      if (_batchImageData.isEmpty)
                        Column(
                          children: [
                            ElevatedButton.icon(
                              icon: _isCapturing
                                  ? const CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2)
                                  : const Icon(Icons.camera_alt),
                              label: const Text('Capture Images'),
                              onPressed: _isCapturing ? null : _captureMultipleImages,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue,
                                foregroundColor: Colors.white,
                                minimumSize: const Size(double.infinity, 50),
                              ),
                            ),
                            const SizedBox(height: 8),
                            ElevatedButton.icon(
                              icon: const Icon(Icons.collections),
                              label: const Text('Select from Gallery'),
                              onPressed: _isProcessing ? null : _pickBatchImages,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.deepOrange,
                                foregroundColor: Colors.white,
                                minimumSize: const Size(double.infinity, 50),
                              ),
                            ),
                          ],
                        ),

                      // Add more images buttons (when batch already has images)
                      if (_batchMode && _batchImageData.isNotEmpty)
                        Column(
                          children: [
                            const SizedBox(height: 8),
                            const Text(
                              'Add more images to batch',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton.icon(
                                    icon: const Icon(Icons.add_a_photo),
                                    label: const Text('Capture'),
                                    onPressed: _isCapturing ? null : _captureSingleImage,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.blue,
                                      foregroundColor: Colors.white,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: ElevatedButton.icon(
                                    icon: const Icon(Icons.add_photo_alternate),
                                    label: const Text('Add from Gallery'),
                                    onPressed: _isProcessing ? null : _pickBatchImages,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.deepOrange,
                                      foregroundColor: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),

                      // Navigation buttons for batch mode
                      if (_batchMode && _batchImageData.length > 1)
                        Padding(
                          padding: const EdgeInsets.only(top: 16.0),
                          child: Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  icon: const Icon(Icons.arrow_back),
                                  label: const Text('Previous'),
                                  onPressed: _currentImageIndex > 0
                                      ? () => _loadImageForEditing(
                                          _currentImageIndex - 1)
                                      : null,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.grey[700],
                                    foregroundColor: Colors.white,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: ElevatedButton.icon(
                                  icon: const Icon(Icons.arrow_forward),
                                  label: const Text('Next'),
                                  onPressed: _currentImageIndex <
                                          _batchImageData.length - 1
                                      ? () => _loadImageForEditing(
                                          _currentImageIndex + 1)
                                      : null,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.grey[700],
                                    foregroundColor: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                      // Store Button and Proceed Button
                      if (_selectedImageBytes != null && !_showAdjustmentPanel)
                        const SizedBox(height: 16),

                      if (_selectedImageBytes != null && !_showAdjustmentPanel)
                        Column(
                          children: [
                            ElevatedButton.icon(
                              icon: _isStoringBatch
                                  ? const CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2)
                                  : const Icon(Icons.save_alt),
                              label: Text(_isStoringBatch
                                  ? 'Storing ${_batchImageData.length} images...'
                                  : 'Save All Images'),
                              onPressed: _isStoringBatch
                                  ? null
                                  : _storeBatchImages,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.purple,
                                foregroundColor: Colors.white,
                                minimumSize: const Size(double.infinity, 50),
                              ),
                            ),
                            
                            const SizedBox(height: 8),
                            
                            // PROCEED BUTTON - Only enabled when image is stored
                            ElevatedButton.icon(
                              icon: const Icon(Icons.arrow_forward),
                              label: const Text('Proceed to Soil Analysis'),
                              onPressed: _imageStored
                                  ? _proceedToSoilAnalysis
                                  : null,
                              style: ElevatedButton.styleFrom(
                                backgroundColor:
                                    _imageStored ? Colors.orange : Colors.grey,
                                foregroundColor: Colors.white,
                                minimumSize: const Size(double.infinity, 50),
                              ),
                            ),
                            
                            if (!_imageStored)
                              Padding(
                                padding: const EdgeInsets.only(top: 8.0),
                                child: Text(
                                  'Save all ${_batchImageData.length} images first to proceed',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                              ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Storage Progress
              if (_isStoringBatch)
                Card(
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 16),
                        Text(
                          'Saving ${_batchImageData.length} images...',
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Preserving image quality and enhancement parameters for all images',
                          style: TextStyle(
                              fontSize: 14, color: Colors.grey.shade600),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),

              // Information Card
              if (_batchImageData.isEmpty)
                Card(
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.info, color: Colors.blue),
                            SizedBox(width: 8),
                            Text(
                              'How it works',
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        const Text('• Capture plant leaf images using camera'),
                        const Text('• Select multiple images from gallery'),
                        const Text('• Review and enhance each image individually'),
                        const Text('• Apply brightness, contrast, and saturation adjustments'),
                        const Text('• Save all enhanced images with adjustment parameters'),
                        const SizedBox(height: 8),
                        Text(
                          'You can capture multiple images one by one and they will all be added to the same batch.',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                ),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAdjustmentPanel() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Image Enhancement',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Adjusting Image ${_currentImageIndex + 1} of ${_batchImageData.length}',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 16),
          _buildAdjustmentSlider(
            label: 'Brightness',
            value: _brightness,
            min: 50,
            max: 100,
            icon: Icons.brightness_6,
            onChanged: (value) {
              setState(() => _brightness = value);
              _applyAdjustments();
            },
          ),
          _buildAdjustmentSlider(
            label: 'Contrast',
            value: _contrast,
            min: 50,
            max: 100,
            icon: Icons.contrast,
            onChanged: (value) {
              setState(() => _contrast = value);
              _applyAdjustments();
            },
          ),
          _buildAdjustmentSlider(
            label: 'Saturation',
            value: _saturation,
            min: 50,
            max: 100,
            icon: Icons.invert_colors,
            onChanged: (value) {
              setState(() => _saturation = value);
              _applyAdjustments();
            },
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reset All'),
                  onPressed: _resetAdjustments,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.grey,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.save),
                  label: const Text('Save This'),
                  onPressed: () {
                    _saveCurrentImageAdjustments();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Image adjustments saved'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.blue,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.save_alt),
                  label: const Text('Save All'),
                  onPressed: _isStoringBatch ? null : _storeBatchImages,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.purple,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAdjustmentSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    required IconData icon,
    required ValueChanged<double> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: Colors.grey),
              const SizedBox(width: 8),
              Text(
                label,
                style:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
              const Spacer(),
              Text(
                value.toStringAsFixed(1),
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Slider(
            value: value,
            min: min,
            max: max,
            divisions: 20,
            onChanged: onChanged,
            activeColor: Colors.purple,
            inactiveColor: Colors.grey.shade300,
          ),
        ],
      ),
    );
  }
}