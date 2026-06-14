import 'package:flutter/material.dart';

enum EmergencyContactIcon {
  phone(Icons.phone_outlined),
  localHospital(Icons.local_hospital_outlined),
  localPolice(Icons.local_police_outlined),
  fireTruck(Icons.fire_truck_outlined),
  bloodtype(Icons.bloodtype_outlined);

  final IconData iconData;

  const EmergencyContactIcon(this.iconData);

  static EmergencyContactIcon fromString(String value) {
    switch (value.toLowerCase().trim()) {
      case 'local_hospital':
      case 'hospital':
        return EmergencyContactIcon.localHospital;
      case 'local_police':
      case 'police':
        return EmergencyContactIcon.localPolice;
      case 'fire_truck':
      case 'fire':
        return EmergencyContactIcon.fireTruck;
      case 'bloodtype':
      case 'blood':
        return EmergencyContactIcon.bloodtype;
      case 'phone':
      default:
        return EmergencyContactIcon.phone;
    }
  }

  String toJsonValue() {
    switch (this) {
      case EmergencyContactIcon.localHospital:
        return 'local_hospital';
      case EmergencyContactIcon.localPolice:
        return 'local_police';
      case EmergencyContactIcon.fireTruck:
        return 'fire_truck';
      case EmergencyContactIcon.bloodtype:
        return 'bloodtype';
      case EmergencyContactIcon.phone:
        return 'phone';
    }
  }
}

class EmergencyContact {
  final String id;
  final String label;
  final String phoneNumber;
  final EmergencyContactIcon icon;

  EmergencyContact({
    required this.id,
    required this.label,
    required this.phoneNumber,
    required this.icon,
  });

  factory EmergencyContact.fromJson(Map<String, dynamic> json) {
    return EmergencyContact(
      id: json['id'] as String,
      label: json['label'] as String,
      phoneNumber: json['phone_number'] as String,
      icon: EmergencyContactIcon.fromString(json['icon'] as String? ?? 'phone'),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'label': label,
      'phone_number': phoneNumber,
      'icon': icon.toJsonValue(),
    };
  }
}
