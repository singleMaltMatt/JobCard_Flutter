import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/api_config.dart';
import '../config/theme.dart';
import '../models/sales_order.dart';
import '../providers/auth_provider.dart';
import '../providers/tech_sales_provider.dart';
import '../services/pocketbase_client.dart';
import '../services/sales_order_service.dart';
import '../services/sales_pdf_service.dart';
import 'signature_pad.dart';

/// Sign-off sheet for a delivery or collection.
///
/// IMPORTANT: this writes only to the sales_orders record. It never calls
/// updateJobStatus and never touches on_site_started_at / on_site_ended_at,
/// so a technician can sign for a delivery in the middle of a job without
/// disturbing the running timer.
class SalesOrderSheet extends StatefulWidget {
  final SalesOrder order;

  const SalesOrderSheet({super.key, required this.order});

  @override
  State<SalesOrderSheet> createState() => _SalesOrderSheetState();
}

class _SalesOrderSheetState extends State<SalesOrderSheet> {
  final _signatureNameController = TextEditingController();
  String? _capturedSignature;
  bool _sendEmail = false;
  bool _isSubmitting = false;
  String _progressLabel = '';

  late final SalesOrderService _service;

  /// Attached deliveries are merged into the job card when the job is
  /// completed, so they must not be emailed separately here. Collections
  /// aren't emailed at all — the portal status change is the record.
  bool get _canEmail =>
      widget.order.relatedJobId == null &&
      !widget.order.isCollection &&
      widget.order.partyEmail.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _service = SalesOrderService(context.read<PocketBaseClient>());
  }

  @override
  void dispose() {
    _signatureNameController.dispose();
    super.dispose();
  }

  Future<void> _openSignatureDialog() async {
    final result = await showDialog<String?>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const _SalesSignatureDialog(),
    );
    if (result != null && mounted) {
      setState(() => _capturedSignature = result);
    }
  }

  Future<void> _openAttachedPdf() async {
    final name = widget.order.attachedPdfName;
    if (name == null) return;
    final uri = Uri.parse(
        ApiConfig.fileUrl('sales_orders', widget.order.id, name));
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open the attached PDF')),
        );
      }
    }
  }

  Future<void> _submit() async {
    if (_capturedSignature == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please capture a signature before completing'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    if (_signatureNameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter the name of the person signing'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
      _progressLabel = 'Fetching attachment...';
    });

    final order = widget.order;
    final signedAt = DateTime.now();
    final user = context.read<AuthProvider>().user;
    final technicianName =
        (user?.name?.isNotEmpty == true) ? user!.name! : (user?.username ?? '');

    try {
      // 1. Pull the SAGE PDF (if any) so it can be merged as pages 2+.
      final attached = await _service.fetchAttachedPdf(order);

      if (!mounted) return;
      setState(() => _progressLabel = 'Generating document...');

      // 2. Render the branded cover and merge.
      final payload = <String, dynamic>{
        'type': order.type,
        'orderNumber': order.orderNumber,
        'partyName': order.partyName,
        'partyAddress': order.partyAddress,
        'reference': order.reference,
        'description': order.description,
        'signatureName': _signatureNameController.text.trim(),
        'signature': _capturedSignature,
        'signedDate': DateFormat('d MMM yyyy HH:mm').format(signedAt),
        'technicianName': technicianName,
      };

      final pdfBytes = await SalesPdfService.generateSalesPdf(
        payload,
        attachedPdfBytes: attached,
      );

      if (pdfBytes == null) {
        throw Exception('PDF generation failed');
      }

      if (!mounted) return;
      setState(() => _progressLabel = 'Uploading...');

      // 3. Store the merged PDF on the record.
      final fileName = '${order.orderNumber}.pdf';
      await _service.uploadGeneratedPdf(
        orderId: order.id,
        pdfBytes: pdfBytes,
        fileName: fileName,
      );

      // 4. Store the raw signature (best effort — never blocks completion).
      await _service.uploadSignature(
        orderId: order.id,
        pngBytes: base64Decode(_capturedSignature!.split(',').last),
        fileName: '${order.id}_sig.png',
      );

      // 5. Email the signed note (optional, standalone deliveries only).
      // Done before the status write so email_sent reflects reality.
      var emailed = false;
      if (_sendEmail && _canEmail) {
        if (!mounted) return;
        setState(() => _progressLabel = 'Sending email...');
        emailed = await SalesPdfService.sendSalesEmail(
          {
            'to': order.partyEmail,
            'subject': '${order.typeLabel} Note - ${order.orderNumber}',
            'type': order.type,
            'orderNumber': order.orderNumber,
            'partyName': order.partyName,
            'partyAddress': order.partyAddress,
            'reference': order.reference,
            'description': order.description,
            'signedDate': DateFormat('d MMM yyyy').format(signedAt),
          },
          pdfBytes,
        );
      }

      // 6. Mark it done.
      final ok = await _service.markCompleted(
        orderId: order.id,
        signatureName: _signatureNameController.text.trim(),
        signedAt: signedAt,
        emailSent: emailed,
      );

      if (!ok) throw Exception('Could not update the order status');

      if (!mounted) return;
      context.read<TechSalesProvider>().removeLocally(order.id);
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_sendEmail && _canEmail && !emailed
              ? '${order.orderNumber} completed, but the email failed to send'
              : '${order.orderNumber} signed and completed'),
          backgroundColor:
              (_sendEmail && _canEmail && !emailed) ? Colors.orange : Colors.green,
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _progressLabel = '';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final dateFmt = DateFormat('d MMM yyyy');

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) {
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
                child: Row(
                  children: [
                    const SizedBox(width: 48),
                    Expanded(
                      child: Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      color: AppTheme.primaryGrey,
                      onPressed: _isSubmitting
                          ? null
                          : () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        order.isCollection
                            ? 'Collection'
                            : 'Delivery',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primaryBlack,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        order.orderNumber,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppTheme.primaryBlue,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 16),

                      _detailRow(
                        order.isCollection
                            ? Icons.factory_outlined
                            : Icons.business_outlined,
                        order.isCollection ? 'Supplier' : 'Client',
                        order.partyName,
                      ),
                      if (order.partyAddress.isNotEmpty)
                        _detailRow(Icons.place_outlined, 'Address',
                            order.partyAddress),
                      if (order.scheduledDay != null)
                        _detailRow(Icons.calendar_today, 'Scheduled',
                            dateFmt.format(order.scheduledDay!)),
                      if (order.reference.isNotEmpty)
                        _detailRow(Icons.tag, 'Reference', order.reference),

                      const SizedBox(height: 16),
                      Text(
                        order.isCollection
                            ? 'Goods to collect'
                            : 'Goods to deliver',
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey[300]!),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          order.description.isEmpty
                              ? '—'
                              : order.description,
                          style: const TextStyle(
                              fontSize: 14, color: AppTheme.darkGrey),
                        ),
                      ),

                      if (order.attachedPdfName != null) ...[
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed:
                                _isSubmitting ? null : _openAttachedPdf,
                            icon: const Icon(Icons.picture_as_pdf_outlined,
                                size: 18),
                            label: const Text('View attached PDF'),
                          ),
                        ),
                      ],

                      if (order.relatedJobId != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryBlue
                                .withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.link,
                                  size: 16, color: AppTheme.primaryBlue),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Attached to a job — this note will be sent '
                                  'with the job card when that job is completed.',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: AppTheme.primaryBlue),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      const Divider(height: 32),

                      const Text(
                        'Received in good order',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 12),

                      TextFormField(
                        controller: _signatureNameController,
                        enabled: !_isSubmitting,
                        decoration: InputDecoration(
                          labelText: 'Signature Name *',
                          hintText: 'Full name of person signing',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      if (_capturedSignature != null) ...[
                        Container(
                          height: 90,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            border:
                                Border.all(color: Colors.green, width: 2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Image.memory(
                              base64Decode(
                                  _capturedSignature!.split(',').last),
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Icon(Icons.check_circle,
                                color: Colors.green, size: 16),
                            const SizedBox(width: 6),
                            const Text('Signature captured',
                                style: TextStyle(color: Colors.green)),
                            const Spacer(),
                            TextButton(
                              onPressed: _isSubmitting
                                  ? null
                                  : _openSignatureDialog,
                              child: const Text('Re-sign'),
                            ),
                          ],
                        ),
                      ] else
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _isSubmitting
                                ? null
                                : _openSignatureDialog,
                            icon: const Icon(Icons.draw_outlined),
                            label: const Text('Tap to Sign'),
                            style: OutlinedButton.styleFrom(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 20),
                              textStyle: const TextStyle(fontSize: 16),
                            ),
                          ),
                        ),

                      if (_canEmail) ...[
                        const SizedBox(height: 8),
                        CheckboxListTile(
                          title: const Text('Send Email'),
                          subtitle:
                              Text('Send the note to ${order.partyName}'),
                          value: _sendEmail,
                          onChanged: _isSubmitting
                              ? null
                              : (v) =>
                                  setState(() => _sendEmail = v ?? false),
                          controlAffinity:
                              ListTileControlAffinity.trailing,
                          activeColor: AppTheme.primaryBlue,
                        ),
                      ],

                      const SizedBox(height: 20),

                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _isSubmitting ? null : _submit,
                          icon: _isSubmitting
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.check_circle),
                          label: Text(_isSubmitting
                              ? (_progressLabel.isEmpty
                                  ? 'Working...'
                                  : _progressLabel)
                              : 'Complete ${order.typeLabel}'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            padding:
                                const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Signing this does not affect any job you have running.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 12, color: AppTheme.primaryGrey),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: AppTheme.primaryGrey),
          const SizedBox(width: 8),
          Text('$label: ',
              style: const TextStyle(
                  fontSize: 13, color: AppTheme.primaryGrey)),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                  fontSize: 13, color: AppTheme.darkGrey),
            ),
          ),
        ],
      ),
    );
  }
}

/// Fullscreen signature dialog — mirrors the job-card one so the
/// technician gets the same signing experience.
class _SalesSignatureDialog extends StatelessWidget {
  const _SalesSignatureDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Cancel',
                    onPressed: () => Navigator.of(context).pop(null),
                  ),
                  const Expanded(
                    child: Text(
                      'Signature — Received in good order',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
              const Divider(),
              const SizedBox(height: 4),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey[300]!),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: SignaturePad(
                        onSign: (base64) =>
                            Navigator.of(context).pop(base64),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
