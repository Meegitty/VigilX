import 'package:flutter/material.dart';
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

  Future<void> _addContactDialog() async {
    final nameCtl = TextEditingController();
    final phoneCtl = TextEditingController();

    final result = await showDialog<EmergencyContact>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add emergency contact'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtl,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            TextField(
              controller: phoneCtl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone (with country code if possible)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final name = nameCtl.text.trim();
              final phone = phoneCtl.text.trim();
              if (name.isEmpty || phone.isEmpty) return;
              Navigator.pop(ctx, EmergencyContact(name: name, phone: phone));
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (result == null) return;
    final updated = [..._contacts, result];
    await EmergencyContactsStore.save(updated);
    if (!mounted) return;
    setState(() => _contacts = updated);
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
        title: const Text('Emergency contacts'),
        backgroundColor: Colors.transparent,
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _contacts.length + 1,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (ctx, idx) {
          if (idx == _contacts.length) {
            return OutlinedButton.icon(
              onPressed: _addContactDialog,
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