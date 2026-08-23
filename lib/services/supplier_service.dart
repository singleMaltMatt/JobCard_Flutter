import 'dart:convert';
import '../config/api_config.dart';
import '../models/supplier.dart';
import 'pocketbase_client.dart';

class SupplierService {
  final PocketBaseClient _client;

  SupplierService(this._client);

  /// Get all suppliers, fetching every page until exhausted.
  Future<List<Supplier>> getSuppliers() async {
    try {
      final all = <Supplier>[];
      int page = 1;
      const perPage = 200;

      while (true) {
        final response = await _client.get(
          ApiConfig.suppliersEndpoint,
          queryParams: {
            'sort': 'name',
            'page': '$page',
            'perPage': '$perPage',
          },
        );

        if (response.statusCode != 200) {
          throw Exception('Failed to load suppliers');
        }

        final data = jsonDecode(response.body);
        final items = data['items'] as List<dynamic>;
        all.addAll(
            items.map((item) => Supplier.fromJson(item as Map<String, dynamic>)));

        final totalPages = (data['totalPages'] as int? ?? 1);
        if (page >= totalPages) break;
        page++;
      }

      return all;
    } catch (e) {
      throw Exception('Failed to load suppliers: $e');
    }
  }

  /// Create a new supplier (used by the inline add-supplier flow).
  Future<Supplier> createSupplier({
    required String name,
    String email = '',
    String phone = '',
    String address = '',
  }) async {
    try {
      final response = await _client.post(
        ApiConfig.suppliersEndpoint,
        body: {
          'name': name,
          'email': email,
          'phone': phone,
          'address': address,
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return Supplier.fromJson(data);
      } else {
        throw Exception('Failed to create supplier: ${response.body}');
      }
    } catch (e) {
      throw Exception('Failed to create supplier: $e');
    }
  }
}
