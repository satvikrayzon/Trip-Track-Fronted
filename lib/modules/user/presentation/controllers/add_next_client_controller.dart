import 'package:flutter/material.dart';

import '../../../../core/models/picked_location.dart';

class AddNextClientController {
  AddNextClientController({
    required PickedLocation initialFrom,
  }) {
    fromLocation.value = initialFrom;
  }

  final ValueNotifier<PickedLocation?> fromLocation =
      ValueNotifier<PickedLocation?>(null);
  final ValueNotifier<PickedLocation?> toLocation =
      ValueNotifier<PickedLocation?>(null);
  final ValueNotifier<bool> showLocationErrors = ValueNotifier<bool>(false);

  void selectToLocation(PickedLocation? location) {
    toLocation.value = location;
  }

  void dispose() {
    fromLocation.dispose();
    toLocation.dispose();
    showLocationErrors.dispose();
  }
}

class AddNextClientInput {
  const AddNextClientInput({
    required this.clientName,
    required this.destination,
    required this.purpose,
  });

  final String clientName;
  final String destination;
  final String purpose;
}
