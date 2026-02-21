import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/emergency_contact.dart';

class EmergencyContactsStore {
  static const _key = 'emergency_contacts_v1';

  static Future<List<EmergencyContact>> load() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_key);
    if (raw == null || raw.trim().isEmpty) return [];
    final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    return list.map(EmergencyContact.fromJson).toList();
  }

  static Future<void> save(List<EmergencyContact> contacts) async {
    final sp = await SharedPreferences.getInstance();
    final raw = jsonEncode(contacts.map((c) => c.toJson()).toList());
    await sp.setString(_key, raw);
  }
}
