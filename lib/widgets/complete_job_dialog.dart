import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../config/api_config.dart';
import '../config/theme.dart';
import '../models/job.dart';
import '../providers/auth_provider.dart';
import '../providers/job_provider.dart';
import 'signature_pad.dart';

class CompleteJobDialog extends StatefulWidget {
  final Job job;

  const CompleteJobDialog({super.key, required this.job});

  @override
  State<CompleteJobDialog> createState() => _CompleteJobDialogState();
}

class _CompleteJobDialogState extends State<CompleteJobDialog> {
  final _descriptionController = TextEditingController();
  final _signatureNameController = TextEditingController();
  bool _getSignature = false;
  bool _sendEmail = false;
  bool _isSubmitting = false;
  String? _capturedSignature;
  DateTime? _departedTime;

  @override
  void dispose() {
    _descriptionController.dispose();
    _signatureNameController.dispose();
    super.dispose();
  }

  Future<bool> _showCloseConfirmation() async {
    if (_isSubmitting) return false;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Close without completing?'),
        content: const Text(
          'The job card has not been generated yet. '
          'Closing now means no PDF will be created and no email will be sent.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Go Back'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Close Anyway',
                style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _openSignatureDialog() async {
    final result = await showDialog<String?>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const _SignatureDialog(),
    );
    if (result != null && mounted) {
      setState(() {
        _capturedSignature = result;
        _departedTime = DateTime.now();
      });
    }
  }

  Future<void> _completeJob() async {
    if (_descriptionController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please add a job description'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    final jobProvider = context.read<JobProvider>();
    final success = await jobProvider.completeJob(
      jobId: widget.job.id,
      description: _descriptionController.text.trim(),
      emailSent: _sendEmail,
      originalJob: widget.job,
    );

    if (mounted) {
      setState(() => _isSubmitting = false);

      if (success) {
        Navigator.of(context).pop();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.job.isRecurring
                ? 'Job completed! Next occurrence scheduled.'
                : 'Job completed successfully!'),
            backgroundColor: Colors.green,
          ),
        );

        // Always generate + store the job card PDF, email is a separate
        // optional step that reuses the same generated PDF bytes.
        _generateStoreAndMaybeEmail(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed: ${jobProvider.error ?? "Unknown error"}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _generateStoreAndMaybeEmail(BuildContext context) {
    final jobProvider = context.read<JobProvider>();
    _generatePdfStoreAndEmail(jobProvider).catchError((e) {
      debugPrint('PDF/email pipeline error: $e');
    });
  }

  Future<void> _generatePdfStoreAndEmail(JobProvider jobProvider) async {
    final user = context.mounted ? context.read<AuthProvider>().user : null;
    final technicianName = (user?.name?.isNotEmpty == true)
        ? user!.name!
        : (user?.username ?? '');

    final now = _departedTime ?? DateTime.now();
    final arrived = widget.job.onSiteStartedAt?.toLocal();
    final departed = now.toLocal();
    final timeFmt = DateFormat('HH:mm');
    final dateFmt = DateFormat('d MMM yyyy HH:mm');

    String timeSpent = '';
    if (arrived != null) {
      final diff = departed.difference(arrived);
      final h = diff.inHours;
      final m = diff.inMinutes % 60;
      timeSpent = h > 0 ? '${h}h ${m}m' : '${m}m';
    }

    // Step 1: generate the PDF
    List<int>? pdfBytes;
    try {
      final pdfResponse = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/pdf/generate-pdf'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'clientName': widget.job.clientName,
          'clientAddress': widget.job.clientAddress,
          'jobNumber': widget.job.jobNumber,
          'jobType': widget.job.jobTypeLabel,
          'appointmentDetails': widget.job.calendarDate != null
              ? DateFormat('d MMM yyyy')
                  .format(DateTime.parse(widget.job.calendarDate!))
              : '',
          'arrivedTime': arrived != null ? timeFmt.format(arrived) : '',
          'departedTime': timeFmt.format(departed),
          'timeSpent': timeSpent,
          'description': _descriptionController.text.trim(),
          'signatureName': _signatureNameController.text.trim(),
          'signature': _capturedSignature,
          'technicianName': technicianName,
          'completedDate': dateFmt.format(departed),
          'companyLogo': '${ApiConfig.baseUrl}/static/logo.png',
        }),
      );
      if (pdfResponse.statusCode == 200) {
        pdfBytes = pdfResponse.bodyBytes;
      } else {
        debugPrint('PDF generation failed: ${pdfResponse.body}');
      }
    } catch (e) {
      debugPrint('PDF generation error: $e');
    }

    if (pdfBytes == null) return;

    // Step 2: upload PDF to PocketBase, attached to this job record
    final fileName = '${widget.job.jobNumber.isNotEmpty ? widget.job.jobNumber : widget.job.id}.pdf';
    try {
      final uploadSuccess = await jobProvider.uploadJobCardPdf(
        jobId: widget.job.id,
        pdfBytes: pdfBytes,
        fileName: fileName,
      );
      if (!uploadSuccess) {
        debugPrint('Failed to upload job card PDF to PocketBase');
      }
    } catch (e) {
      debugPrint('Job card upload error: $e');
    }

    // Step 3: email (optional), reusing the same PDF bytes
    if (_sendEmail) {
      final pdfBase64 = base64Encode(pdfBytes);
      try {
        final emailResponse = await http.post(
          Uri.parse('${ApiConfig.baseUrl}/email/send-email'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'to': widget.job.clientEmail,
            'subject':
                'Job Completed - ${widget.job.jobTypeLabel} ${widget.job.jobNumber}',
            'clientName': widget.job.clientName,
            'clientAddress': widget.job.clientAddress,
            'jobDate':
                widget.job.calendarDate ?? DateTime.now().toIso8601String(),
            'description': _descriptionController.text.trim(),
            'pdfBase64': pdfBase64,
          }),
        );

        if (emailResponse.statusCode == 200) {
          debugPrint('Email sent successfully');
        } else {
          debugPrint('Failed to send email: ${emailResponse.body}');
        }
      } catch (e) {
        debugPrint('Email send error: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final shouldClose = await _showCloseConfirmation();
        if (shouldClose && context.mounted) Navigator.of(context).pop();
      },
      child: Container(
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
                        onPressed: () async {
                          final shouldClose = await _showCloseConfirmation();
                          if (shouldClose && context.mounted) Navigator.of(context).pop();
                        },
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Complete Job',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primaryBlack,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${widget.job.jobTypeLabel} · ${widget.job.jobNumber}',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppTheme.primaryBlue,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${widget.job.clientName} - ${widget.job.clientAddress}',
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppTheme.primaryGrey,
                        ),
                      ),
                      const SizedBox(height: 24),

                      const Text(
                        'Work Description *',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _descriptionController,
                        maxLines: 6,
                        decoration: InputDecoration(
                          hintText: 'Describe all work completed on site...',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      CheckboxListTile(
                        title: const Text('Get Signature'),
                        subtitle:
                            const Text('Client signs digitally on screen'),
                        value: _getSignature,
                        onChanged: (v) =>
                            setState(() => _getSignature = v ?? false),
                        controlAffinity: ListTileControlAffinity.trailing,
                        activeColor: AppTheme.primaryBlue,
                      ),

                      if (_getSignature) ...[
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _signatureNameController,
                          decoration: InputDecoration(
                            labelText: 'Signature Name',
                            hintText: 'Customer full name',
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
                                onPressed: _openSignatureDialog,
                                child: const Text('Re-sign'),
                              ),
                            ],
                          ),
                        ] else ...[
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: _openSignatureDialog,
                              icon: const Icon(Icons.draw_outlined),
                              label: const Text('Tap to Sign'),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                    vertical: 20),
                                textStyle: const TextStyle(fontSize: 16),
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                      ],

                      CheckboxListTile(
                        title: const Text('Send Email'),
                        subtitle: Text(
                            'Send job card to ${widget.job.clientName}'),
                        value: _sendEmail,
                        onChanged: (v) =>
                            setState(() => _sendEmail = v ?? false),
                        controlAffinity: ListTileControlAffinity.trailing,
                        activeColor: AppTheme.primaryBlue,
                      ),
                      const SizedBox(height: 24),

                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _isSubmitting ? null : _completeJob,
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
                              ? 'Completing...'
                              : 'Complete Job'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            padding:
                                const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
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
    ),
  );
  }
}

// Fullscreen signature dialog — covers entire screen so there's no scroll conflict
class _SignatureDialog extends StatelessWidget {
  const _SignatureDialog();

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
                      'Customer Signature',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold),
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