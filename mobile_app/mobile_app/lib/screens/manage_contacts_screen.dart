import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import '../models/emergency_contact.dart';
import '../storage/emergency_contacts_store.dart';

class ManageContactsScreen extends StatefulWidget {
  const ManageContactsScreen({super.key});

  @override
  State<ManageContactsScreen> createState() => _ManageContactsScreenState();
}

class _ManageContactsScreenState extends State<ManageContactsScreen> {
  List<EmergencyContact> _contacts = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await EmergencyContactsStore.load();
    if (!mounted) return;
    setState(() => _contacts = list);
  }

  Future<void> _pickContact() async {
    // Request permission to read contacts
    if (await FlutterContacts.requestPermission(readonly: true)) {
      // Open the native contact picker
      final contact = await FlutterContacts.openExternalPick();
      
      if (contact != null) {
        // Fetch full contact details to get the phone numbers
        final fullContact = await FlutterContacts.getContact(contact.id);
        
        if (fullContact != null && fullContact.phones.isNotEmpty) {
          final name = fullContact.displayName;
          final phone = fullContact.phones.first.number;

          final newContact = EmergencyContact(name: name, phone: phone);
          final updated = [..._contacts, newContact];
          
          await EmergencyContactsStore.save(updated);
          
          if (!mounted) return;
          setState(() => _contacts = updated);
        } else {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Selected contact has no phone number.')),
          );
        }
      }
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Contacts permission denied.')),
      );
    }
  }

  Future<void> _deleteAt(int i) async {
    final updated = [..._contacts]..removeAt(i);
    await EmergencyContactsStore.save(updated);
    if (!mounted) return;
    setState(() => _contacts = updated);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Emergency Contacts'),
        backgroundColor: Colors.transparent,
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _contacts.length + 1,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (ctx, idx) {
          if (idx == _contacts.length) {
            return OutlinedButton.icon(
              onPressed: _pickContact,
              icon: const Icon(Icons.add),
              label: const Text('Add contact'),
            );
          }

          final c = _contacts[idx];
          return Card(
            child: ListTile(
              leading: const Icon(Icons.person),
              title: Text(c.name),
              subtitle: Text(c.phone),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _deleteAt(idx),
              ),
            ),
          );
        },
      ),
    );
  }
}