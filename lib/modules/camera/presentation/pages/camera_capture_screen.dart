import 'dart:io';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geocoding/geocoding.dart';
import 'package:location/location.dart' as loc;
import 'package:path_provider/path_provider.dart';

import '../../../../core/app_messenger.dart';
import '../../../../core/routes/app_routes.dart';
import '../../../../core/utils/asset_utils.dart';
import '../controllers/camera_controller.dart';

/// Camera Capture Screen with GPS Overlay
/// Captures meter readings with embedded GPS coordinates and location data
class CameraCaptureScreen extends StatefulWidget {
  const CameraCaptureScreen({super.key});

  @override
  State<CameraCaptureScreen> createState() => _CameraCaptureScreenState();
}

class _CameraCaptureScreenState extends State<CameraCaptureScreen> {
  // Constants
  static const double _overlayPanelHeight = 150.0;
  static const double _overlayPadding = 10.0;
  static const double _overlayTextSize = 18.0;
  static const double _captureButtonSize = 80.0;
  static const double _captureButtonBorderWidth = 4.0;
  static const Color _primaryDarkColor = Color(0xFF111827);

  // Controllers and state
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  late final CameraControllerX _cameraController;
  String? _requestId;
  String? _captureType;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _cameraController = CameraControllerX();
    _extractArguments();
    _initializeCamera();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  // Extract route arguments
  void _extractArguments() {
    final args = AppNavigation.arguments as Map<String, dynamic>?;
    _requestId = args?['requestId'];
    _captureType = args?['type'];
  }

  // Initialize camera
  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) {
        throw Exception('No cameras available');
      }

      _controller = CameraController(
        _cameras![0],
        ResolutionPreset.high,
        enableAudio: false,
      );

      await _controller!.initialize();

      if (mounted) {
        setState(() => _isInitialized = true);
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackbar('Failed to initialize camera: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _isInitialized ? _buildCameraView() : _buildLoadingView(),
    );
  }

  // Build camera view with overlays
  Widget _buildCameraView() {
    return Stack(
      children: [
        Positioned.fill(child: CameraPreview(_controller!)),
        _buildTopBar(),
        _buildBottomControls(),
      ],
    );
  }

  // Build loading view
  Widget _buildLoadingView() {
    return const Center(
      child: CircularProgressIndicator(color: Colors.white),
    );
  }

  // Build top bar with back button and title
  Widget _buildTopBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top + 10,
          left: 16,
          right: 16,
          bottom: 16,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black.withOpacity(0.7), Colors.transparent],
          ),
        ),
        child: Row(
          children: [
            IconButton(
              onPressed: () => AppNavigation.back(),
              icon: const Icon(Icons.arrow_back, color: Colors.white),
            ),
            const SizedBox(width: 8),
            Text(
              'Capture ${_getCaptureTypeLabel()} Meter',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Build bottom controls with GPS indicator and capture button
  Widget _buildBottomControls() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 40),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              Colors.black.withOpacity(0.8),
              Colors.transparent,
            ],
          ),
        ),
        child: Column(
          children: [
            _buildGpsIndicator(),
            const SizedBox(height: 24),
            _buildCaptureButton(),
            const SizedBox(height: 16),
            const Text(
              'Tap to capture',
              style: TextStyle(color: Colors.white, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  // Build GPS active indicator
  Widget _buildGpsIndicator() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 40),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.3)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.gps_fixed, color: Colors.greenAccent, size: 16),
          SizedBox(width: 8),
          Text(
            'GPS Active',
            style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  // Build capture button
  Widget _buildCaptureButton() {
    return GestureDetector(
      onTap: _captureAndProcessImage,
      child: Container(
        width: _captureButtonSize,
        height: _captureButtonSize,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.white,
            width: _captureButtonBorderWidth,
          ),
        ),
        child: Container(
          margin: const EdgeInsets.all(8),
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }

  // Get capture type label
  String _getCaptureTypeLabel() {
    return _captureType == 'start' ? 'Start' : 'End';
  }

  // === IMAGE CAPTURE AND PROCESSING ===

  /// Main method to capture and process image with GPS overlay
  Future<void> _captureAndProcessImage() async {
    try {
      _showLoader('Capturing...');

      // Get GPS data and overlay text
      final overlayText = await _fetchLocationData();
      final overlayLines = overlayText.split('\n');

      // Capture image from camera
      final xFile = await _controller!.takePicture();
      final imageBytes = await xFile.readAsBytes();

      // Process and add overlay
      final processedImageFile = await _addOverlayToImage(
        imageBytes,
        overlayLines,
      );

      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      // Show preview dialog
      _showPreviewDialog(processedImageFile);
    } catch (e) {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      _showErrorSnackbar('Failed to capture image: $e');
    }
  }

  /// Add GPS overlay to captured image
  Future<File> _addOverlayToImage(
    Uint8List imageBytes,
    List<String> overlayLines,
  ) async {
    // Decode image
    final codec = await ui.instantiateImageCodec(imageBytes);
    final frame = await codec.getNextFrame();
    final originalImage = frame.image;

    // Create canvas for drawing
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // Draw original image
    canvas.drawImage(originalImage, Offset.zero, Paint());

    final width = originalImage.width.toDouble();
    final height = originalImage.height.toDouble();

    // Draw overlay panel
    await _drawOverlayPanel(canvas, width, height, overlayLines);

    // Finalize and convert to image
    final picture = recorder.endRecording();
    final finalImage = await picture.toImage(
      originalImage.width,
      originalImage.height,
    );

    // Convert to PNG bytes
    final byteData = await finalImage.toByteData(format: ui.ImageByteFormat.png);
    final pngBytes = byteData!.buffer.asUint8List();

    // Save to temporary file
    return await _saveToTemporaryFile(pngBytes);
  }

  /// Draw overlay panel with map thumbnail and text
  Future<void> _drawOverlayPanel(
    Canvas canvas,
    double width,
    double height,
    List<String> overlayLines,
  ) async {
    // Draw semi-transparent background panel
    final panelRect = Rect.fromLTWH(
      0,
      height - _overlayPanelHeight,
      width,
      _overlayPanelHeight,
    );
    canvas.drawRect(
      panelRect,
      Paint()..color = Colors.black.withOpacity(0.7),
    );

    // Load and draw map thumbnail
    final mapImage = await _loadMapThumbnail();
    const mapSize = _overlayPanelHeight - (2 * _overlayPadding);
    final mapRect = Rect.fromLTWH(
      _overlayPadding,
      height - _overlayPanelHeight + _overlayPadding,
      mapSize,
      mapSize,
    );
    paintImage(
      canvas: canvas,
      rect: mapRect,
      image: mapImage,
      fit: BoxFit.cover,
    );

    // Draw overlay text
    _drawOverlayText(
      canvas,
      overlayLines,
      mapRect.right + _overlayPadding,
      height - _overlayPanelHeight + _overlayPadding,
      width,
    );
  }

  /// Load map thumbnail image
  Future<ui.Image> _loadMapThumbnail() async {
    final mapBytes = await rootBundle.load(AssetUtilities.dummyLocationImage);
    final codec = await ui.instantiateImageCodec(mapBytes.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  /// Draw overlay text on canvas
  void _drawOverlayText(
    Canvas canvas,
    List<String> lines,
    double startX,
    double startY,
    double canvasWidth,
  ) {
    final textStyle = ui.TextStyle(color: Colors.white, fontSize: _overlayTextSize, fontFamily: 'Poppins');

    final paragraphStyle = ui.ParagraphStyle(
      textDirection: TextDirection.ltr,
      maxLines: lines.length,
    );

    double currentY = startY;

    for (final line in lines) {
      final builder = ui.ParagraphBuilder(paragraphStyle)
        ..pushStyle(textStyle)
        ..addText(line);

      final paragraph = builder.build()
        ..layout(ui.ParagraphConstraints(
          width: canvasWidth - startX - _overlayPadding,
        ));

      canvas.drawParagraph(paragraph, Offset(startX, currentY));
      currentY += paragraph.height + 4;
    }
  }

  /// Save processed image to temporary file
  Future<File> _saveToTemporaryFile(Uint8List imageBytes) async {
    final directory = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final filePath = '${directory.path}/$timestamp.png';
    final file = File(filePath);
    await file.writeAsBytes(imageBytes);
    return file;
  }

  // === LOCATION AND GPS METHODS ===

  /// Fetch location data and format overlay text
  Future<String> _fetchLocationData() async {
    final location = loc.Location();
    // Check and request location permissions
    final isLocationEnabled = await _ensureLocationEnabled(location);
    if (!isLocationEnabled) {
      return _getDefaultLocationText('Location service disabled');
    }
    final hasPermission = await _ensureLocationPermission(location);
    if (!hasPermission) {
      return _getDefaultLocationText('Location permission denied');
    }
    try {
      // Get current location
      final locationData = await location.getLocation();
      final latitude = locationData.latitude ?? 0.0;
      final longitude = locationData.longitude ?? 0.0;

      // Store coordinates in controller
      _cameraController.currentLatitude = latitude;
      _cameraController.currentLongitude = longitude;

      // Get address from coordinates
      final address = await _getAddressFromCoordinates(latitude, longitude);
      _cameraController.currentAddress = address;

      // Format overlay text
      return _formatOverlayText(address, latitude, longitude);
    } catch (e) {
      return _getDefaultLocationText('Location unavailable');
    }
  }

  /// Ensure location service is enabled
  Future<bool> _ensureLocationEnabled(loc.Location location) async {
    bool serviceEnabled = await location.serviceEnabled();
    if (!serviceEnabled) {
      serviceEnabled = await location.requestService();
    }
    return serviceEnabled;
  }

  /// Ensure location permission is granted
  Future<bool> _ensureLocationPermission(loc.Location location) async {
    loc.PermissionStatus permission = await location.hasPermission();
    if (permission == loc.PermissionStatus.denied) {
      permission = await location.requestPermission();
    }
    return permission == loc.PermissionStatus.granted;
  }

  /// Get address from coordinates using geocoding
  Future<String> _getAddressFromCoordinates(
    double latitude,
    double longitude,
  ) async {
    try {
      final placemarks = await placemarkFromCoordinates(latitude, longitude);
      if (placemarks.isEmpty) return 'Address not found';

      final place = placemarks.first;
      final addressComponents = [
        place.street,
        place.subLocality,
        place.locality,
        place.subAdministrativeArea,
        place.administrativeArea,
        place.postalCode
      ];

      return addressComponents.where((component) => component != null && component.trim().isNotEmpty).join(', ');
    } catch (e) {
      return 'Address not available';
    }
  }

  /// Format overlay text with address, coordinates, and timestamp
  String _formatOverlayText(String address, double latitude, double longitude) {
    final coordinates = 'Lat: ${latitude.toStringAsFixed(6)}, '
        'Lng: ${longitude.toStringAsFixed(6)}';
    final dateTime = _formatDateTime(DateTime.now());
    return '$address\n$coordinates\n$dateTime';
  }

  /// Get default location text for error cases
  String _getDefaultLocationText(String reason) {
    return '$reason\nLat: 0.0, Lng: 0.0\n${_formatDateTime(DateTime.now())}';
  }

  /// Format date and time
  String _formatDateTime(DateTime dateTime) {
    final day = dateTime.day;
    final month = _getMonthName(dateTime.month);
    final year = dateTime.year;
    final time = _formatTime(dateTime);
    return '$day $month $year $time';
  }

  /// Get month name from month number
  String _getMonthName(int month) {
    const monthNames = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December'
    ];
    return monthNames[month - 1];
  }

  /// Format time in 12-hour format
  String _formatTime(DateTime dateTime) {
    final hour = dateTime.hour % 12 == 0 ? 12 : dateTime.hour % 12;
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final period = dateTime.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }

  // === DIALOG AND UI METHODS ===

  /// Show image preview dialog with retake and upload options
  void _showPreviewDialog(File imageFile) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildPreviewImage(imageFile),
            _buildPreviewContent(imageFile),
          ],
        ),
      ),
    );
  }

  /// Build preview image section
  Widget _buildPreviewImage(File imageFile) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: Image.file(imageFile, height: 300, width: double.infinity, fit: BoxFit.cover),
    );
  }

  /// Build preview dialog content
  Widget _buildPreviewContent(File imageFile) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const Text(
            'Image Captured!',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Image captured with GPS coordinates',
            style: TextStyle(
              color: Colors.grey,
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          _buildPreviewActions(imageFile),
        ],
      ),
    );
  }

  /// Build preview action buttons
  Widget _buildPreviewActions(File imageFile) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () => _handleRetake(imageFile),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Retake'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton(
            onPressed: () => _handleUpload(imageFile),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              backgroundColor: _primaryDarkColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Upload',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }

  /// Handle retake action
  void _handleRetake(File imageFile) {
    Navigator.of(context).pop();
    imageFile.delete();
  }

  /// Handle upload action
  Future<void> _handleUpload(File imageFile) async {
    try {
      Navigator.of(context).pop();
      _showLoader('Uploading...');

      await _cameraController.uploadMeterImage(
          requestId: _requestId!,
          imageFile: imageFile,
          captureType: _captureType!,
          latitude: _cameraController.currentLatitude,
          longitude: _cameraController.currentLongitude,
          address: _cameraController.currentAddress);

      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      AppNavigation.back();

      _showSuccessSnackbar(
        '${_getCaptureTypeLabel()} meter reading uploaded successfully',
      );
    } catch (e) {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      _showErrorSnackbar('Failed to upload image: $e');
    } finally {
      imageFile.delete();
    }
  }

  /// Show loading dialog
  void _showLoader(String message) {
    showDialog<void>(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black.withOpacity(0.5),
        builder: (_) => PopScope(
          canPop: false,
          child: Center(
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 40,
                    height: 40,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      valueColor: AlwaysStoppedAnimation<Color>(_primaryDarkColor),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    message,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF1F2937)),
                  ),
                ],
              ),
            ),
          ),
        ));
  }

  /// Show success snackbar
  void _showSuccessSnackbar(String message) {
    showAppSnackBar(
      title: 'Success',
      message: message,
      backgroundColor: Colors.green,
      textColor: Colors.white,
    );
  }

  /// Show error snackbar
  void _showErrorSnackbar(String message) {
    showAppSnackBar(
      title: 'Error',
      message: message,
      backgroundColor: Colors.red,
      textColor: Colors.white,
    );
  }
}
