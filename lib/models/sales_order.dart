/// Extract the first non-empty string from a PocketBase file field.
/// File fields return a plain String (single) or List (multi); empty = null.
String? _pbFile(dynamic value) {
  if (value is String && value.isNotEmpty) return value;
  if (value is List && value.isNotEmpty) return value.first as String?;
  return null;
}

class SalesOrder {
  final String id;
  final String orderNumber;

  /// 'delivery' or 'collection' (lowercase, matching the PB select values).
  final String type;

  final String clientId;
  final String supplierId;

  /// Resolved from expand.client / expand.supplier depending on [type].
  final String partyName;
  final String partyAddress;
  final String partyEmail;

  final String assignedToId;

  /// Resolved from expand.assigned_to (name, falling back to email).
  final String assignedToName;

  /// Raw PocketBase date string; null/empty means unscheduled.
  final String? scheduledDate;

  final String reference;
  final String description;

  /// 'pending' / 'assigned' / 'completed'.
  final String status;

  final String? attachedPdfName;
  final String? generatedPdfName;
  final String? signatureName;
  final DateTime? signedAt;
  final bool emailSent;
  final String? relatedJobId;

  final DateTime created;
  final DateTime updated;

  SalesOrder({
    required this.id,
    required this.orderNumber,
    required this.type,
    required this.clientId,
    required this.supplierId,
    required this.partyName,
    required this.partyAddress,
    required this.partyEmail,
    required this.assignedToId,
    required this.assignedToName,
    this.scheduledDate,
    required this.reference,
    required this.description,
    required this.status,
    this.attachedPdfName,
    this.generatedPdfName,
    this.signatureName,
    this.signedAt,
    this.emailSent = false,
    this.relatedJobId,
    required this.created,
    required this.updated,
  });

  factory SalesOrder.fromJson(Map<String, dynamic> json) {
    final expand = json['expand'] as Map<String, dynamic>?;
    final type = (json['type'] as String?) ?? 'delivery';

    // The relevant party depends on the order type.
    Map<String, dynamic>? partyData;
    if (expand != null) {
      final partyKey = type == 'collection' ? 'supplier' : 'client';
      partyData = expand[partyKey] as Map<String, dynamic>?;
    }

    final techData = expand?['assigned_to'] as Map<String, dynamic>?;
    String techName = '';
    if (techData != null) {
      final name = techData['name'] as String?;
      techName = (name != null && name.isNotEmpty)
          ? name
          : (techData['email'] ?? '');
    }

    final scheduled = json['scheduled_date'] as String?;

    return SalesOrder(
      id: json['id'] ?? '',
      orderNumber: json['order_number'] ?? '',
      type: type,
      clientId: json['client'] ?? '',
      supplierId: json['supplier'] ?? '',
      partyName: partyData?['name'] ?? '',
      partyAddress: partyData?['address'] ?? '',
      partyEmail: partyData?['email'] ?? '',
      assignedToId: json['assigned_to'] ?? '',
      assignedToName: techName,
      scheduledDate: (scheduled != null && scheduled.isNotEmpty) ? scheduled : null,
      reference: json['reference'] ?? '',
      description: json['description'] ?? '',
      status: json['status'] ?? 'pending',
      attachedPdfName: _pbFile(json['attached_pdf']),
      generatedPdfName: _pbFile(json['generated_pdf']),
      signatureName: json['signature_name'],
      signedAt: DateTime.tryParse(json['signed_at'] ?? ''),
      emailSent: json['email_sent'] ?? false,
      relatedJobId: (json['related_job'] as String?)?.isNotEmpty == true
          ? json['related_job'] as String
          : null,
      created: DateTime.tryParse(json['created'] ?? '') ?? DateTime.now(),
      updated: DateTime.tryParse(json['updated'] ?? '') ?? DateTime.now(),
    );
  }

  bool get isCollection => type == 'collection';
  bool get isCompleted => status == 'completed';

  String get typeLabel => isCollection ? 'Collection' : 'Delivery';

  /// Calendar day of the scheduled date, or null when unscheduled.
  DateTime? get scheduledDay {
    if (scheduledDate == null) return null;
    final parsed = DateTime.tryParse(scheduledDate!);
    if (parsed == null) return null;
    return DateTime(parsed.year, parsed.month, parsed.day);
  }
}
