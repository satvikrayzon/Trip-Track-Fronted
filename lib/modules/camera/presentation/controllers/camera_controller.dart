import 'dart:io';



import 'package:flutter/foundation.dart';

import 'package:image/image.dart' as img;



import '../../../../core/di/service_locator.dart';

import '../../../../core/network/models/api_result.dart';

import '../../../travel/data/datasources/travel_request_remote_datasource.dart';



/// Camera / meter image upload via REST API.

class CameraControllerX {

  CameraControllerX({TravelRequestRemoteDataSource? travelApi})

      : _travelApi = travelApi ?? ServiceLocator.I.get();



  final TravelRequestRemoteDataSource _travelApi;



  double currentLatitude = 0.0;

  double currentLongitude = 0.0;

  String currentAddress = '';



  Future<void> uploadMeterImage({

    required String requestId,

    required File imageFile,

    required String captureType,

    required double latitude,

    required double longitude,

    required String address,

  }) async {

    final compressedFile = await _compressImage(imageFile);



    final upload = await _travelApi.uploadMeterImage(

      requestId: requestId,

      filePath: compressedFile.path,

      captureType: captureType,

      latitude: latitude,

      longitude: longitude,

      address: address,

    );



    try {

      compressedFile.delete();

    } catch (_) {}



    switch (upload) {

      case ApiSuccess(:final data):

        final patch = <String, dynamic>{

          'updatedAt': DateTime.now().toIso8601String(),

        };

        if (data['startImageUrl'] != null) {

          patch['startImageUrl'] = data['startImageUrl'];

        }

        if (data['endImageUrl'] != null) {

          patch['endImageUrl'] = data['endImageUrl'];

        }

        if (captureType == 'start') {

          patch['startCoordinates'] = {

            'latitude': latitude,

            'longitude': longitude,

          };

          patch['startAddress'] = address;

          patch['startTime'] = DateTime.now().toIso8601String();

          patch['status'] = 'End Missing';

        } else {

          patch['endCoordinates'] = {

            'latitude': latitude,

            'longitude': longitude,

          };

          patch['endAddress'] = address;

          patch['endTime'] = DateTime.now().toIso8601String();

          patch['status'] = 'Completed';

        }



        if (patch.length > 1) {

          final up = await _travelApi.update(requestId, patch);

          switch (up) {

            case ApiFailure(:final failure):

              throw Exception(failure.message);

            case ApiSuccess():

              break;

          }

        }

      case ApiFailure(:final failure):

        throw Exception(failure.message);

    }

  }



  Future<File> _compressImage(File imageFile) async {

    try {

      final imageBytes = await imageFile.readAsBytes();

      final image = img.decodeImage(imageBytes);



      if (image == null) {

        return imageFile;

      }



      final compressedBytes = img.encodeJpg(image, quality: 82);

      final compressedFile = File('${imageFile.path}_compressed.jpg');

      await compressedFile.writeAsBytes(compressedBytes);



      return compressedFile;

    } catch (e) {


      return imageFile;

    }

  }

}


