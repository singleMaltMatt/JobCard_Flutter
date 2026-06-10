import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../config/api_config.dart';
import '../config/theme.dart';
import '../models/job.dart';
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
  bool _getSignature = false;
  bool _sendEmail = false;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
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
    );

    if (mounted) {
      setState(() => _isSubmitting = false);

      if (success) {
        // Close the dialog immediately
        Navigator.of(context).pop();

        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Job completed successfully!'),
            backgroundColor: Colors.green,
          ),
        );

        // Fire email in the background (non-blocking) if requested
        if (_sendEmail) {
          _sendCompletionEmail(context);
        }
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

  void _sendCompletionEmail(BuildContext context) {
    _generateAndSendEmail().catchError((e) {
      debugPrint('Email send error: $e');
    });
  }

  Future<void> _generateAndSendEmail() async {
    // Step 1: generate PDF and base64-encode the bytes
    String? pdfBase64;
    try {
      final pdfResponse = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/pdf/generate-pdf'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'clientName': widget.job.clientName,
          'clientAddress': widget.job.clientAddress,
          'jobDate': widget.job.calendarDate ?? DateTime.now().toIso8601String(),
          'description': _descriptionController.text.trim(),
          'status': 'completed',
        }),
      );
      if (pdfResponse.statusCode == 200) {
        pdfBase64 = base64Encode(pdfResponse.bodyBytes);
      } else {
        debugPrint('PDF generation failed: ${pdfResponse.body}');
      }
    } catch (e) {
      debugPrint('PDF generation error: $e');
    }

    // Step 2: send email, attaching PDF if generated successfully
    final emailResponse = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/email/send-email'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'to': widget.job.clientEmail,
        'subject': 'Job Completed - JobCard Tracker',
        'clientName': widget.job.clientName,
        'clientAddress': widget.job.clientAddress,
        'jobDate': widget.job.calendarDate ?? DateTime.now().toIso8601String(),
        'description': _descriptionController.text.trim(),
        if (pdfBase64 != null) 'pdfBase64': pdfBase64,
      }),
    );

    if (emailResponse.statusCode == 200) {
      debugPrint('Email sent successfully');
    } else {
      debugPrint('Failed to send email: ${emailResponse.body}');
    }
  }

  @override
  Widget build(BuildContext context) {
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
          // Only use the provided scrollController for the DraggableScrollableSheet,
          // but DON'T wrap everything in SingleChildScrollView to avoid scroll conflicts with signature pad
          return NotificationListener<ScrollNotification>(
            onNotification: (notification) => false,
            child: Column(
              children: [
                // Handle bar
                Padding(
                  padding: const EdgeInsets.only(top: 12),
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
                // Scrollable content area
                Expanded(
                  child: SingleChildScrollView(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Title
                        const Text(
                          'Complete Job',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primaryBlack,
                          ),
                        ),
                        const SizedBox(height: 8),

                        // Job info
                        Text(
                          '${widget.job.clientName} - ${widget.job.clientAddress}',
                          style: const TextStyle(
                            fontSize: 14,
                            color: AppTheme.primaryGrey,
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Description text box
                        const Text(
                          'Work Description *',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
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

                        // Get Signature checkbox
                        CheckboxListTile(
                          title: const Text('Get Signature'),
                          subtitle: const Text('Client signs digitally on screen'),
                          value: _getSignature,
                          onChanged: (v) {
                            setState(() => _getSignature = v ?? false);
                          },
                          controlAffinity: ListTileControlAffinity.trailing,
                          activeColor: AppTheme.primaryBlue,
                        ),

                        // Signature pad (shown when checkbox is checked)
                        // NOT wrapped in scrollable - it gets its own fixed area
                        if (_getSignature) ...[
                          SizedBox(
                            height: 260,
                            child: SignaturePad(
                              onSign: (data) {
                                // Signature captured - data can be used for PDF
                              },
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],

                        // Send Email checkbox
                        CheckboxListTile(
                          title: const Text('Send Email'),
                          subtitle: Text('Send job card to ${widget.job.clientName}'),
                          value: _sendEmail,
                          onChanged: (v) {
                            setState(() => _sendEmail = v ?? false);
                          },
                          controlAffinity: ListTileControlAffinity.trailing,
                          activeColor: AppTheme.primaryBlue,
                        ),
                        const SizedBox(height: 24),

                        // Complete Job button
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
                            label: Text(_isSubmitting ? 'Completing...' : 'Complete Job'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
