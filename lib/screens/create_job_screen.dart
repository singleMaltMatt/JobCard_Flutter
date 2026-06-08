import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/job_provider.dart';

class CreateJobScreen extends StatefulWidget {
  const CreateJobScreen({super.key});

  @override
  State<CreateJobScreen> createState() => _CreateJobScreenState();
}

class _CreateJobScreenState extends State<CreateJobScreen> {
  final _formKey = GlobalKey<FormState>();
  String? _selectedClientId;
  DateTime _selectedDate = DateTime.now();
  bool _isCreatingClient = false;
  bool _isSubmitting = false;

  // New client fields
  final _clientNameController = TextEditingController();
  final _clientEmailController = TextEditingController();
  final _clientPhoneController = TextEditingController();
  final _clientAddressController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Refresh clients every time this screen opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<JobProvider>().loadClients();
    });
  }

  @override
  void dispose() {
    _clientNameController.dispose();
    _clientEmailController.dispose();
    _clientPhoneController.dispose();
    _clientAddressController.dispose();
    super.dispose();
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    final jobProvider = context.read<JobProvider>();
    String clientId = _selectedClientId ?? '';

    // Create new client first if needed
    if (_isCreatingClient) {
      final newClient = await jobProvider.createClient(
        name: _clientNameController.text.trim(),
        email: _clientEmailController.text.trim(),
        phone: _clientPhoneController.text.trim(),
        address: _clientAddressController.text.trim(),
      );

      if (newClient == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to create client: ${jobProvider.error}'),
              backgroundColor: Colors.red,
            ),
          );
        }
        setState(() => _isSubmitting = false);
        return;
      }

      clientId = newClient.id;
    }

    if (clientId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select or create a client')),
      );
      setState(() => _isSubmitting = false);
      return;
    }

    final success = await jobProvider.createJob(
      clientId: clientId,
      calendarDate: DateFormat('yyyy-MM-dd').format(_selectedDate),
    );

    if (mounted) {
      setState(() => _isSubmitting = false);
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Job created successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to create job: ${jobProvider.error}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create New Job')),
      body: Consumer<JobProvider>(
        builder: (context, jobProvider, _) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Toggle between select existing or create new client
                  Row(
                    children: [
                      Expanded(
                        child: ChoiceChip(
                          label: const Text('Select Client'),
                          selected: !_isCreatingClient,
                          onSelected: (v) => setState(() {
                            _isCreatingClient = false;
                            _selectedClientId = null;
                          }),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ChoiceChip(
                          label: const Text('New Client'),
                          selected: _isCreatingClient,
                          onSelected: (v) => setState(() {
                            _isCreatingClient = true;
                            _selectedClientId = null;
                          }),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  if (_isCreatingClient) ...[
                    TextFormField(
                      controller: _clientNameController,
                      decoration: const InputDecoration(labelText: 'Client Name *'),
                      validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _clientEmailController,
                      decoration: const InputDecoration(labelText: 'Client Email'),
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _clientPhoneController,
                      decoration: const InputDecoration(labelText: 'Phone'),
                      keyboardType: TextInputType.phone,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _clientAddressController,
                      decoration: const InputDecoration(labelText: 'Address'),
                      maxLines: 2,
                    ),
                  ] else ...[
                    if (jobProvider.isLoading)
                      const Center(child: CircularProgressIndicator())
                    else
                      DropdownButtonFormField<String>(
                        decoration: const InputDecoration(
                          labelText: 'Select Client *',
                          prefixIcon: Icon(Icons.business),
                        ),
                        value: _selectedClientId,
                        items: jobProvider.clients.map((client) {
                          return DropdownMenuItem(
                            value: client.id,
                            child: Text(client.name),
                          );
                        }).toList(),
                        onChanged: (v) => setState(() => _selectedClientId = v),
                        validator: (v) => (v == null || v.isEmpty) ? 'Select a client' : null,
                      ),
                  ],

                  const SizedBox(height: 24),

                  // Date picker
                  InkWell(
                    onTap: _selectDate,
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Job Date',
                        prefixIcon: Icon(Icons.calendar_today),
                      ),
                      child: Text(DateFormat('EEEE, MMMM d, yyyy').format(_selectedDate)),
                    ),
                  ),

                  const SizedBox(height: 32),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isSubmitting ? null : _submit,
                      child: _isSubmitting
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('Create Job'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}