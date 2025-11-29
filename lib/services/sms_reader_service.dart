import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

/// Model representing an SMS message
class SmsMessage {
  final String address;
  final String body;
  final DateTime? date;
  final int? type;

  SmsMessage({required this.address, required this.body, this.date, this.type});

  factory SmsMessage.fromMap(Map<String, dynamic> map) {
    return SmsMessage(
      address: map['address']?.toString() ?? 'Unknown',
      body: map['body']?.toString() ?? '',
      date: map['date'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['date'] as int)
          : null,
      type: map['type'] as int?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'address': address,
      'body': body,
      'date': date?.millisecondsSinceEpoch,
      'type': type,
    };
  }

  /// Returns a formatted string representation suitable for RAG storage
  String toRagDocument() {
    final dateStr = date != null ? date!.toLocal().toString() : 'Unknown date';
    return '''
From: $address
Date: $dateStr
Message: $body
''';
  }

  @override
  String toString() {
    return 'SmsMessage(address: $address, body: ${body.substring(0, body.length > 50 ? 50 : body.length)}..., date: $date)';
  }
}

/// Service to handle SMS reading from Android device
class SmsReaderService {
  static const platform = MethodChannel('sms_reader/native');

  /// Request SMS permission from the user
  Future<PermissionStatus> requestPermission() async {
    final status = await Permission.sms.request();
    return status;
  }

  /// Check if SMS permission is granted
  Future<bool> hasPermission() async {
    final status = await Permission.sms.status;
    return status.isGranted;
  }

  /// Open app settings if permission is permanently denied
  Future<bool> openAppSettings() async {
    return await Permission.sms.isPermanentlyDenied
        ? await openAppSettings()
        : false;
  }

  /// Load all SMS messages from the device inbox
  /// Throws [PlatformException] if there's an error reading from native side
  /// Returns empty list if no messages found
  Future<List<SmsMessage>> getAllSms() async {
    try {
      final result = await platform.invokeMethod<List<dynamic>>('getAllSms');

      if (result == null) {
        return [];
      }

      final messages = result
          .map((e) => SmsMessage.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();

      return messages;
    } on PlatformException catch (e) {
      throw Exception('Failed to load SMS: ${e.message}');
    }
  }

  /// Load SMS messages and convert them to RAG-ready documents
  /// Each message is formatted as a document string
  Future<List<String>> getSmsAsDocuments() async {
    final messages = await getAllSms();
    return messages.map((msg) => msg.toRagDocument()).toList();
  }

  /// Get SMS messages grouped by sender
  Future<Map<String, List<SmsMessage>>> getSmsGroupedBySender() async {
    final messages = await getAllSms();
    final Map<String, List<SmsMessage>> grouped = {};

    for (final msg in messages) {
      grouped.putIfAbsent(msg.address, () => []).add(msg);
    }

    return grouped;
  }

  /// Get SMS conversation with a specific sender/address
  Future<List<SmsMessage>> getConversationWith(String address) async {
    final messages = await getAllSms();
    return messages.where((msg) => msg.address == address).toList();
  }

  /// Get SMS messages within a date range
  Future<List<SmsMessage>> getSmsInDateRange(
    DateTime start,
    DateTime end,
  ) async {
    final messages = await getAllSms();
    return messages.where((msg) {
      if (msg.date == null) return false;
      return msg.date!.isAfter(start) && msg.date!.isBefore(end);
    }).toList();
  }

  /// Search SMS messages by body content
  Future<List<SmsMessage>> searchSms(String query) async {
    final messages = await getAllSms();
    final lowerQuery = query.toLowerCase();
    return messages
        .where((msg) => msg.body.toLowerCase().contains(lowerQuery))
        .toList();
  }
}
