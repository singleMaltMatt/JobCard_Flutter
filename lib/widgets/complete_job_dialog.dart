import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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
  bool _signatureCaptured = false;
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
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Job completed successfully!'),
            backgroundColor: Colors.green,
          ),
        );
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

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return SingleChildScrollView(
          controller: scrollController,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Handle bar
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

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
                  validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
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
                if (_getSignature) ...[
                  SignaturePad(
                    onSign: (data) {
                      setState(() => _signatureCaptured = true);
                    },
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
        );
      },
    );
  }
}