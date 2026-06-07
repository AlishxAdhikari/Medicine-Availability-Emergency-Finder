class EmergencyContact {
  final String id;
  final String label;
  final String phoneNumber;
  final String icon; // Icon name matching Flutter Icons

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
      icon: json['icon'] as String? ?? 'phone',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'label': label,
      'phone_number': phoneNumber,
      'icon': icon,
    };
  }
}
