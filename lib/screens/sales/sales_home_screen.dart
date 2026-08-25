import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../models/sales_order.dart';
import '../../models/week_job.dart';
import '../../providers/sales_auth_provider.dart';
import '../../providers/sales_provider.dart';
import 'sales_login_screen.dart';
import 'sales_order_form_screen.dart';

class SalesHomeScreen extends StatefulWidget {
  const SalesHomeScreen({super.key});

  @override
  State<SalesHomeScreen> createState() => _SalesHomeScreenState();
}

class _SalesHomeScreenState extends State<SalesHomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SalesProvider>().loadWeek();
    });
  }

  Future<void> _logout() async {
    await context.read<SalesAuthProvider>().logout();
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const SalesLoginScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<SalesAuthProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sales Portal'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Center(child: Text(auth.displayName)),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: _logout,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('New Order'),
        onPressed: () async {
          final changed = await Navigator.of(context).push<bool>(
            MaterialPageRoute(
                builder: (_) => const SalesOrderFormScreen()),
          );
          if (changed == true && context.mounted) {
            context.read<SalesProvider>().loadWeek();
          }
        },
      ),
      body: Column(
        children: [
          const _WeekNavBar(),
          Expanded(
            child: Consumer<SalesProvider>(
              builder: (context, sales, _) {
                if (sales.isLoading) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (sales.error != null) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          sales.error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.red),
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          onPressed: sales.loadWeek,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  );
                }
                return const _WeekList();
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _WeekNavBar extends StatelessWidget {
  const _WeekNavBar();

  @override
  Widget build(BuildContext context) {
    final sales = context.watch<SalesProvider>();
    final fmt = DateFormat('d MMM');

    return Material(
      color: AppTheme.white,
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              tooltip: 'Previous week',
              onPressed: sales.isLoading ? null : sales.previousWeek,
            ),
            const SizedBox(width: 8),
            Text(
              '${fmt.format(sales.weekStart)} – ${fmt.format(sales.weekEnd)}',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppTheme.primaryBlue,
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              tooltip: 'Next week',
              onPressed: sales.isLoading ? null : sales.nextWeek,
            ),
            if (!sales.isCurrentWeek) ...[
              const SizedBox(width: 8),
              TextButton(
                onPressed: sales.isLoading ? null : sales.goToThisWeek,
                child: const Text('Today'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _WeekList extends StatelessWidget {
  const _WeekList();

  @override
  Widget build(BuildContext context) {
    final sales = context.watch<SalesProvider>();
    final today = DateTime.now();
    final todayDay = DateTime(today.year, today.month, today.day);
    final dayFmt = DateFormat('EEEE d MMMM');

    final unscheduled = sales.unscheduledOrders;

    return RefreshIndicator(
      onRefresh: sales.loadWeek,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
            children: [
              if (unscheduled.isNotEmpty) ...[
                const _DayHeader(label: 'Unscheduled', highlight: false),
                ...unscheduled.map((o) => _OrderCard(order: o)),
                const SizedBox(height: 16),
              ],
              for (int i = 0; i < 7; i++)
                _daySection(
                  context,
                  sales,
                  sales.weekStart.add(Duration(days: i)),
                  todayDay,
                  dayFmt,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _daySection(
    BuildContext context,
    SalesProvider sales,
    DateTime day,
    DateTime todayDay,
    DateFormat dayFmt,
  ) {
    final orders = sales.ordersForDay(day);
    final jobs = sales.jobsForDay(day);
    final isToday = day == todayDay;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DayHeader(label: dayFmt.format(day), highlight: isToday),
        if (orders.isEmpty && jobs.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            child: Text(
              'Nothing scheduled',
              style: TextStyle(color: AppTheme.primaryGrey, fontSize: 13),
            ),
          ),
        ...orders.map((o) => _OrderCard(order: o)),
        ...jobs.map((j) => _JobTile(job: j)),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _DayHeader extends StatelessWidget {
  final String label;
  final bool highlight;

  const _DayHeader({required this.label, required this.highlight});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: highlight ? AppTheme.primaryBlue : AppTheme.darkGrey,
            ),
          ),
          if (highlight) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.primaryBlue,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'Today',
                style: TextStyle(color: AppTheme.white, fontSize: 11),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;

  const _StatusChip({required this.status});

  Color get _color {
    switch (status) {
      case 'completed':
        return Colors.green;
      case 'assigned':
      case 'accepted':
      case 'on_route':
      case 'on_site':
        return AppTheme.primaryBlue;
      case 'pending':
      default:
        return Colors.orange;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        status.replaceAll('_', ' '),
        style: TextStyle(
          color: _color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  final SalesOrder order;

  const _OrderCard({required this.order});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppTheme.primaryBlue,
          child: Icon(
            order.isCollection ? Icons.archive : Icons.local_shipping,
            color: AppTheme.white,
            size: 20,
          ),
        ),
        title: Row(
          children: [
            Text(
              order.orderNumber,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 8),
            Text(
              order.typeLabel,
              style: const TextStyle(
                color: AppTheme.primaryGrey,
                fontSize: 13,
              ),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(order.partyName),
            Text(
              order.assignedToName.isEmpty
                  ? 'Unassigned'
                  : order.assignedToName,
              style: const TextStyle(fontSize: 12),
            ),
            if (order.reference.isNotEmpty)
              Text(
                'Ref: ${order.reference}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.primaryGrey,
                ),
              ),
            if (order.relatedJobId != null)
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.link, size: 13, color: AppTheme.primaryBlue),
                    SizedBox(width: 4),
                    Text(
                      'Merged into job card on completion',
                      style: TextStyle(
                          fontSize: 12, color: AppTheme.primaryBlue),
                    ),
                  ],
                ),
              ),
          ],
        ),
        trailing: _StatusChip(status: order.status),
        onTap: () async {
          final changed = await Navigator.of(context).push<bool>(
            MaterialPageRoute(
                builder: (_) => SalesOrderFormScreen(order: order)),
          );
          if (changed == true && context.mounted) {
            context.read<SalesProvider>().loadWeek();
          }
        },
      ),
    );
  }
}

/// Read-only job tile so the sales user can see which technician is
/// where on a given day. Visually lighter than the order cards.
class _JobTile extends StatelessWidget {
  final WeekJob job;

  const _JobTile({required this.job});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          const Icon(Icons.work_outline,
              size: 16, color: AppTheme.primaryGrey),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${job.jobNumber} · ${job.clientName} · ${job.techName.isEmpty ? 'Unassigned' : job.techName}',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                color: AppTheme.darkGrey,
              ),
            ),
          ),
          const SizedBox(width: 8),
          _StatusChip(status: job.status),
        ],
      ),
    );
  }
}
