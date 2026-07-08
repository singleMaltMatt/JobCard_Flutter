import 'dart:convert';
import '../config/api_config.dart';
import '../models/client.dart';
import 'pocketbase_client.dart';

class ClientService {
  final PocketBaseClient _client;

  ClientService(this._client);

  /// Get all clients, fetching every page until exhausted.
  Future<List<Client>> getClients() async {
    try {
      final all = <Client>[];
      int page = 1;
      const perPage = 200;

      while (true) {
        final response = await _client.get(
          ApiConfig.clientsEndpoint,
          queryParams: {
            'sort': 'name',
            'page': '$page',
            'perPage': '$perPage',
          },
        );

        if (response.statusCode != 200) {
          throw Exception('Failed to load clients');
        }

        final data = jsonDecode(response.body);
        final items = data['items'] as List<dynamic>;
        all.addAll(items.map((item) => Client.fromJson(item as Map<String, dynamic>)));

        final totalPages = (data['totalPages'] as int? ?? 1);
        if (page >= totalPages) break;
        page++;
      }

      return all;
    } catch (e) {
      throw Exception('Failed to load clients: $e');
    }
  }

  /// Create a new client
  Future<Client> createClient({
    required String name,
    required String email,
    required String phone,
    required String address,
  }) async {
    try {
      final response = await _client.post(
        ApiConfig.clientsEndpoint,
        body: {
          'name': name,
          'email': email,
          'phone': phone,
          'address': address,
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return Client.fromJson(data);
      } else {
        throw Exception('Failed to create client');
      }
    } catch (e) {
      throw Exception('Failed to create client: $e');
    }
  }

  /// Get a single client by ID
  Future<Client> getClient(String id) async {
    try {
      final response = await _client.get(ApiConfig.clientEndpoint(id));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return Client.fromJson(data);
      } else {
        throw Exception('Client not found');
      }
    } catch (e) {
      throw Exception('Failed to load client: $e');
    }
  }
}