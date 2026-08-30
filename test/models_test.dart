import 'package:flutter_test/flutter_test.dart';
import 'package:jobcard_tracker/models/job.dart';
import 'package:jobcard_tracker/models/sales_order.dart';

void main() {
  group('Job.jobTypeLabel', () {
    Job jobWithType(String type) => Job.fromJson({
          'id': 'abc',
          'status': 'completed',
          'job_type': type,
        });

    test('maps known job types to display labels', () {
      expect(jobWithType('site_visit').jobTypeLabel, 'Site Visit');
      expect(jobWithType('maintenance').jobTypeLabel, 'Maintenance');
      expect(jobWithType('call_out').jobTypeLabel, 'Call Out');
      expect(jobWithType('cctv_access_control').jobTypeLabel,
          'CCTV / Access Control');
    });

    test('falls back to Site Visit for unknown types', () {
      // Note: this fallback means a job_type added in PocketBase but not
      // here will silently display as "Site Visit" everywhere, including
      // on the PDF. Add new types to the switch as well as to PocketBase.
      expect(jobWithType('something_new').jobTypeLabel, 'Site Visit');
    });
  });

  group('Job file fields', () {
    test('reads job_card_pdf from a multi-file (array) field', () {
      final job = Job.fromJson({
        'id': 'abc',
        'job_card_pdf': ['gs_0238_dcdy5iadqe.pdf'],
      });
      expect(job.jobCardPdfName, 'gs_0238_dcdy5iadqe.pdf');
    });

    test('reads a single-value file field', () {
      final job = Job.fromJson({'id': 'abc', 'job_card_pdf': 'one.pdf'});
      expect(job.jobCardPdfName, 'one.pdf');
    });

    test('empty file field is null', () {
      final job = Job.fromJson({'id': 'abc', 'job_card_pdf': []});
      expect(job.jobCardPdfName, isNull);
    });
  });

  group('SalesOrder', () {
    test('resolves the client for a delivery', () {
      final order = SalesOrder.fromJson({
        'id': 'o1',
        'type': 'delivery',
        'client': 'c1',
        'expand': {
          'client': {'name': 'Lemay Construction', 'address': 'Fourways'},
        },
      });
      expect(order.partyName, 'Lemay Construction');
      expect(order.typeLabel, 'Delivery');
      expect(order.isCollection, isFalse);
    });

    test('resolves the supplier for a collection', () {
      final order = SalesOrder.fromJson({
        'id': 'o2',
        'type': 'collection',
        'supplier': 's1',
        'expand': {
          'supplier': {'name': 'SPL', 'address': 'Midrand'},
        },
      });
      expect(order.partyName, 'SPL');
      expect(order.typeLabel, 'Collection');
      expect(order.isCollection, isTrue);
    });

    test('blank related_job is treated as unattached', () {
      final order = SalesOrder.fromJson({
        'id': 'o3',
        'type': 'delivery',
        'related_job': '',
      });
      expect(order.relatedJobId, isNull);
    });
  });
}
