class IncidentReport {
  final String id;
  final String category;
  final String description;
  final String locationAddress;
  final double latitude;
  final double longitude;
  final List<String> evidenceUrls;
  final DateTime createdAt;

  const IncidentReport({
    required this.id,
    required this.category,
    required this.description,
    required this.locationAddress,
    required this.latitude,
    required this.longitude,
    required this.evidenceUrls,
    required this.createdAt,
  });

  IncidentReport copyWith({
    String? id,
    String? category,
    String? description,
    String? locationAddress,
    double? latitude,
    double? longitude,
    List<String>? evidenceUrls,
    DateTime? createdAt,
  }) {
    return IncidentReport(
      id: id ?? this.id,
      category: category ?? this.category,
      description: description ?? this.description,
      locationAddress: locationAddress ?? this.locationAddress,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      evidenceUrls: evidenceUrls ?? this.evidenceUrls,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
