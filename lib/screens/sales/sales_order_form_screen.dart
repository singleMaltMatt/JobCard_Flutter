import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../models/client.dart';
import '../../models/sales_order.dart';
import '../../models/supplier.dart';
import '../../models/user.dart';
import '../../models/week_job.dart';
import '../../services/client_service.dart';
import '../../services/pocketbase_client.dart';
import '../../services/sales_order_service.dart';
import '../../services/supplier_service.dart';

/// Create / edit form for a sales order. Pass [order] to edit; null creates.
/// Pops with `true` when something was saved so the caller can reload.
class SalesOrderFormScreen extends StatefulWidget {
  final SalesOrder? order;

  const SalesOrderFormScreen({super.key, this.order});

  @override
  State<SalesOrderFormScreen> createState() => _SalesOrderFormScreenState();
}

class _SalesOrderFormScreenState extends State<SalesOrderFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _referenceController = TextEditingController();
  final _descriptionController = TextEditingController();

  late final SalesOrderService _orderService;
  late final ClientService _clientService;
  late final SupplierService _supplierService;

  bool _loadingLists = true;
  String? _listError;

  List<Client> _clients = [];
  List<Supplier> _suppliers = [];
  List<AppUser> _techs = [];

  String _type = 'delivery';
  String? _partyId; // client id or supplier id depending on _type
  String? _techId;
  DateTime? _scheduledDate;

  // Attach-to-job (deliveries only). When set, the delivery note is merged
  // into that job's job card at completion instead of being emailed on its
  // own at signing time.
  String? _relatedJobId;
  List<WeekJob> _attachableJobs = [];
  bool _loadingJobs = false;

  PlatformFile? _pickedPdf;
  bool _saving = false;

  bool get _isEdit => widget.order != null;

  @override
  void initState() {
    super.initState();
    final client = context.read<PocketBaseClient>();
    _orderService = SalesOrderService(client);
    _clientService = ClientService(client);
    _supplierService = SupplierService(client);

    final order = widget.order;
    if (order != null) {
      _type = order.type;
      _partyId = order.isCollection
          ? (order.supplierId.isEmpty ? null : order.supplierId)
          : (order.clientId.isEmpty ? null : order.clientId);
      _techId = order.assignedToId.isEmpty ? null : order.assignedToId;
      _scheduledDate = order.scheduledDay;
      _relatedJobId = order.relatedJobId;
      _referenceController.text = order.reference;
      _descriptionController.text = order.description;
    }

    _loadLists();
  }

  @override
  void dispose() {
    _referenceController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _loadLists() async {
    setState(() {
      _loadingLists = true;
      _listError = null;
    });
    try {
      final results = await Future.wait([
        _clientService.getClients(),
        _supplierService.getSuppliers(),
        _orderService.getInternalTechs(),
      ]);
      setState(() {
        _clients = results[0] as List<Client>;
        _suppliers = results[1] as List<Supplier>;
        _techs = results[2] as List<AppUser>;
        _loadingLists = false;
      });
      await _refreshAttachableJobs();
    } catch (e) {
      setState(() {
        _listError = e.toString();
        _loadingLists = false;
      });
    }
  }

  /// Reload the attachable-job list whenever client or date changes.
  /// Only meaningful for deliveries with both a client and a date set.
  Future<void> _refreshAttachableJobs() async {
    if (_type != 'delivery' || _partyId == null || _scheduledDate == null) {
      if (mounted) {
        setState(() {
          _attachableJobs = [];
          _relatedJobId = null;
        });
      }
      return;
    }

    setState(() => _loadingJobs = true);
    try {
      final jobs = await _orderService.getAttachableJobs(
        clientId: _partyId!,
        aroundDate: _scheduledDate!,
      );
      if (!mounted) return;
      setState(() {
        _attachableJobs = jobs;
        // Drop a stale selection if that job is no longer a candidate.
        if (_relatedJobId != null &&
            !jobs.any((j) => j.id == _relatedJobId)) {
          _relatedJobId = null;
        }
        _loadingJobs = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _attachableJobs = [];
          _loadingJobs = false;
        });
      }
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _scheduledDate ?? now,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() => _scheduledDate = picked);
      await _refreshAttachableJobs();
    }
  }

  Future<void> _pickPdf() async {
    // NOTE: file_picker is pinned to ^10.3.10 (11.x has a broken Android
    // gradle config). 10.x uses the instance accessor; 11.x switched to a
    // static call. Don't "fix" this to FilePicker.pickFiles without also
    // moving the pubspec constraint.
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      withData: true,
    );
    if (result != null && result.files.isNotEmpty) {
      final file = result.files.single;
      if (file.bytes == null) return;
      setState(() => _pickedPdf = file);
    }
  }

  Future<void> _addSupplier() async {
    final created = await showDialog<Supplier>(
      context: context,
      builder: (_) => _AddSupplierDialog(service: _supplierService),
    );
    if (created != null) {
      setState(() {
        _suppliers = [..._suppliers, created]
          ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        _partyId = created.id;
      });
    }
  }

  Future<void> _addClient() async {
    final created = await showDialog<Client>(
      context: context,
      builder: (_) => _AddClientDialog(service: _clientService),
    );
    if (created != null) {
      setState(() {
        _clients = [..._clients, created]
          ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        _partyId = created.id;
      });
      // A brand-new client can't have jobs yet, but keep the attach list
      // in step with the new selection.
      await _refreshAttachableJobs();
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_partyId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_type == 'collection'
              ? 'Please select a supplier'
              : 'Please select a client'),
        ),
      );
      return;
    }

    setState(() => _saving = true);

    // Status is derived: completed stays completed (that transition
    // belongs to the technician in the app); otherwise assignment
    // decides pending vs assigned.
    final existingStatus = widget.order?.status;
    final status = existingStatus == 'completed'
        ? 'completed'
        : (_techId != null ? 'assigned' : 'pending');

    final scheduled = _scheduledDate == null
        ? ''
        : '${_scheduledDate!.year}-${_scheduledDate!.month.toString().padLeft(2, '0')}-${_scheduledDate!.day.toString().padLeft(2, '0')}';

    try {
      String orderId;
      if (_isEdit) {
        orderId = widget.order!.id;
        await _orderService.updateOrder(
          orderId,
          type: _type,
          clientId: _type == 'delivery' ? _partyId! : '',
          supplierId: _type == 'collection' ? _partyId! : '',
          assignedToId: _techId ?? '',
          scheduledDate: scheduled,
          reference: _referenceController.text.trim(),
          description: _descriptionController.text.trim(),
          status: status,
          relatedJobId: _type == 'delivery' ? (_relatedJobId ?? '') : '',
        );
      } else {
        final created = await _orderService.createOrder(
          type: _type,
          clientId: _type == 'delivery' ? _partyId! : '',
          supplierId: _type == 'collection' ? _partyId! : '',
          assignedToId: _techId ?? '',
          scheduledDate: scheduled,
          reference: _referenceController.text.trim(),
          description: _descriptionController.text.trim(),
          status: status,
          relatedJobId: _type == 'delivery' ? (_relatedJobId ?? '') : '',
        );
        orderId = created.id;
      }

      if (_pickedPdf != null) {
        await _orderService.uploadAttachedPdf(
          orderId: orderId,
          pdfBytes: _pickedPdf!.bytes!,
          fileName: _pickedPdf!.name,
        );
      }

      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit
            ? 'Edit ${widget.order!.orderNumber}'
            : 'New Sales Order'),
      ),
      body: _loadingLists
          ? const Center(child: CircularProgressIndicator())
          : _listError != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(_listError!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.red)),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: _loadLists,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : _buildForm(),
    );
  }

  Widget _buildForm() {
    final isCollection = _type == 'collection';
    final dateFmt = DateFormat('EEE d MMM yyyy');

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Type
                DropdownButtonFormField<String>(
                  key: const ValueKey('type'),
                  initialValue: _type,
                  decoration: const InputDecoration(labelText: 'Order type'),
                  items: const [
                    DropdownMenuItem(
                        value: 'delivery', child: Text('Delivery (to client)')),
                    DropdownMenuItem(
                        value: 'collection',
                        child: Text('Collection (from supplier)')),
                  ],
                  onChanged: _saving
                      ? null
                      : (v) {
                          if (v == null || v == _type) return;
                          setState(() {
                            _type = v;
                            _partyId = null; // party list source changed
                          });
                          _refreshAttachableJobs();
                        },
                ),
                const SizedBox(height: 16),

                // Party (clients for delivery, suppliers for collection).
                // Keyed on type so switching rebuilds with a clean value.
                DropdownButtonFormField<String>(
                  key: ValueKey('party-$_type'),
                  initialValue: _partyId,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: isCollection ? 'Supplier' : 'Client',
                  ),
                  items: isCollection
                      ? _suppliers
                          .map((s) => DropdownMenuItem(
                              value: s.id, child: Text(s.name)))
                          .toList()
                      : _clients
                          .map((c) => DropdownMenuItem(
                              value: c.id, child: Text(c.name)))
                          .toList(),
                  onChanged: _saving
                      ? null
                      : (v) {
                          setState(() => _partyId = v);
                          _refreshAttachableJobs();
                        },
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: _saving
                        ? null
                        : (isCollection ? _addSupplier : _addClient),
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(isCollection
                        ? 'Add new supplier'
                        : 'Add new client'),
                  ),
                ),
                const SizedBox(height: 16),

                // Technician
                DropdownButtonFormField<String?>(
                  key: const ValueKey('tech'),
                  initialValue: _techId,
                  isExpanded: true,
                  decoration:
                      const InputDecoration(labelText: 'Assigned technician'),
                  items: [
                    const DropdownMenuItem<String?>(
                        value: null, child: Text('Unassigned')),
                    ..._techs.map((t) => DropdownMenuItem<String?>(
                          value: t.id,
                          child: Text(
                              (t.name != null && t.name!.isNotEmpty)
                                  ? t.name!
                                  : t.email),
                        )),
                  ],
                  onChanged:
                      _saving ? null : (v) => setState(() => _techId = v),
                ),
                const SizedBox(height: 16),

                // Scheduled date
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _saving ? null : _pickDate,
                        icon: const Icon(Icons.calendar_today, size: 18),
                        label: Text(
                          _scheduledDate == null
                              ? 'Pick a date (optional)'
                              : dateFmt.format(_scheduledDate!),
                        ),
                      ),
                    ),
                    if (_scheduledDate != null)
                      IconButton(
                        tooltip: 'Clear date',
                        icon: const Icon(Icons.clear),
                        onPressed: _saving
                            ? null
                            : () {
                                setState(() => _scheduledDate = null);
                                _refreshAttachableJobs();
                              },
                      ),
                  ],
                ),
                const SizedBox(height: 16),

                // Attach to an existing job (deliveries only). When attached,
                // the tech still signs the delivery separately in the app;
                // the signed note is merged into the job card at completion
                // rather than emailed on its own.
                if (_type == 'delivery') ...[
                  if (_loadingJobs)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: LinearProgressIndicator(minHeight: 2),
                    )
                  else if (_partyId == null || _scheduledDate == null)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: Text(
                        'Pick a client and date to attach this delivery to a scheduled job.',
                        style: TextStyle(
                            fontSize: 12, color: AppTheme.primaryGrey),
                      ),
                    )
                  else if (_attachableJobs.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: Text(
                        'No open jobs for this client around that date \u2014 this will be a standalone delivery.',
                        style: TextStyle(
                            fontSize: 12, color: AppTheme.primaryGrey),
                      ),
                    )
                  else
                    DropdownButtonFormField<String?>(
                      key: ValueKey('job-$_partyId-$_scheduledDate'),
                      initialValue: _relatedJobId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Attach to job (optional)',
                        helperText:
                            'Attached: merged into the job card. Standalone: emailed on signing.',
                      ),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('Standalone delivery'),
                        ),
                        ..._attachableJobs.map((j) => DropdownMenuItem<String?>(
                              value: j.id,
                              child: Text(
                                '${j.jobNumber} \u00b7 ${j.jobTypeLabel}'
                                '${j.techName.isEmpty ? '' : ' \u00b7 ${j.techName}'}'
                                '${j.calendarDate == null ? '' : ' \u00b7 ${j.calendarDate}'}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            )),
                      ],
                      onChanged: _saving
                          ? null
                          : (v) => setState(() => _relatedJobId = v),
                    ),
                  const SizedBox(height: 16),
                ],

                // Reference
                TextFormField(
                  controller: _referenceController,
                  enabled: !_saving,
                  decoration: const InputDecoration(
                    labelText: 'Reference',
                    hintText: 'e.g. LC28072026 & LCPO38017',
                  ),
                ),
                const SizedBox(height: 16),

                // Description
                TextFormField(
                  controller: _descriptionController,
                  enabled: !_saving,
                  maxLines: 4,
                  decoration: InputDecoration(
                    labelText: isCollection
                        ? 'What to collect'
                        : 'What to deliver',
                    alignLabelWithHint: true,
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 16),

                // SAGE PDF
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'SAGE document (PDF)',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        if (_isEdit &&
                            widget.order!.attachedPdfName != null &&
                            _pickedPdf == null)
                          Text(
                            'Attached: ${widget.order!.attachedPdfName}',
                            style: const TextStyle(
                                fontSize: 13, color: AppTheme.darkGrey),
                          ),
                        if (_pickedPdf != null)
                          Text(
                            'Selected: ${_pickedPdf!.name}',
                            style: const TextStyle(
                                fontSize: 13, color: AppTheme.primaryBlue),
                          ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton.icon(
                            onPressed: _saving ? null : _pickPdf,
                            icon: const Icon(Icons.upload_file, size: 18),
                            label: Text(
                              (_isEdit &&
                                          widget.order!.attachedPdfName !=
                                              null) ||
                                      _pickedPdf != null
                                  ? 'Replace PDF'
                                  : 'Choose PDF',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : Text(_isEdit ? 'Save Changes' : 'Create Order'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AddSupplierDialog extends StatefulWidget {
  final SupplierService service;

  const _AddSupplierDialog({required this.service});

  @override
  State<_AddSupplierDialog> createState() => _AddSupplierDialogState();
}

class _AddSupplierDialogState extends State<_AddSupplierDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final supplier = await widget.service.createSupplier(
        name: _nameController.text.trim(),
        email: _emailController.text.trim(),
        phone: _phoneController.text.trim(),
        address: _addressController.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(supplier);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to add supplier: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Supplier'),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameController,
                enabled: !_saving,
                decoration: const InputDecoration(labelText: 'Name'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _emailController,
                enabled: !_saving,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  hintText: 'Separate multiples with ;',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phoneController,
                enabled: !_saving,
                decoration: const InputDecoration(labelText: 'Phone'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _addressController,
                enabled: !_saving,
                decoration: const InputDecoration(labelText: 'Address'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Text('Add'),
        ),
      ],
    );
  }
}

/// Inline client creation, mirroring _AddSupplierDialog. Kelly occasionally
/// gets a delivery for a client who has no job on the system yet.
class _AddClientDialog extends StatefulWidget {
  final ClientService service;

  const _AddClientDialog({required this.service});

  @override
  State<_AddClientDialog> createState() => _AddClientDialogState();
}

class _AddClientDialogState extends State<_AddClientDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final client = await widget.service.createClient(
        name: _nameController.text.trim(),
        email: _emailController.text.trim(),
        phone: _phoneController.text.trim(),
        address: _addressController.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(client);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to add client: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Client'),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameController,
                enabled: !_saving,
                decoration: const InputDecoration(labelText: 'Name'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _emailController,
                enabled: !_saving,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  hintText: 'Separate multiples with ;',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phoneController,
                enabled: !_saving,
                decoration: const InputDecoration(labelText: 'Phone'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _addressController,
                enabled: !_saving,
                decoration: const InputDecoration(labelText: 'Address'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Text('Add'),
        ),
      ],
    );
  }
}
