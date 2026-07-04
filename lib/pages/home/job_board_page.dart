import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import '../../constants/colors.dart';
import '../../controllers/auth_controller.dart';
import '../../controllers/delivery_controller.dart';
import '../../models/delivery.dart';
import 'active_delivery_page.dart';

class JobBoardPage extends StatefulWidget {
  const JobBoardPage({super.key});

  @override
  State<JobBoardPage> createState() => _JobBoardPageState();
}

class _JobBoardPageState extends State<JobBoardPage> {
  final _auth     = Get.find<AuthController>();
  final _delivery = Get.find<DeliveryController>();

  @override
  void initState() {
    super.initState();
    final rider = _auth.rider.value;
    if (rider != null) _delivery.init(rider);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Job Board'),
        actions: [
          Obx(() {
            final active = _delivery.activeDelivery.value;
            if (active == null) return const SizedBox.shrink();
            return TextButton.icon(
              onPressed: () => Get.to(() => const ActiveDeliveryPage()),
              icon: const Icon(Icons.local_shipping,
                  color: EzizaColors.kPurple, size: 18),
              label: const Text('Active',
                  style: TextStyle(color: EzizaColors.kPurple)),
            );
          }),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _delivery.refresh,
          ),
        ],
      ),
      body: Obx(() {
        // If there's an active delivery, show a banner at the top
        final active = _delivery.activeDelivery.value;
        final open   = _delivery.openDeliveries;

        return RefreshIndicator(
          onRefresh: _delivery.refresh,
          child: CustomScrollView(
            slivers: [
              if (active != null)
                SliverToBoxAdapter(child: _ActiveBanner(delivery: active)),
              if (_delivery.loading.value && open.isEmpty)
                const SliverFillRemaining(
                    child: Center(child: CircularProgressIndicator())),
              if (!_delivery.loading.value && open.isEmpty)
                const SliverFillRemaining(child: _EmptyState()),
              SliverPadding(
                padding: const EdgeInsets.all(16),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) => _DeliveryCard(delivery: open[i]),
                    childCount: open.length,
                  ),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}

// ── Active delivery banner ────────────────────────────────────
class _ActiveBanner extends StatelessWidget {
  final Delivery delivery;
  const _ActiveBanner({required this.delivery});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Get.to(() => const ActiveDeliveryPage()),
      child: Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              colors: [EzizaColors.kPurpleD, EzizaColors.kPurple]),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(children: [
          const Icon(Icons.local_shipping, color: EzizaColors.kWhite),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Active Delivery',
                  style: TextStyle(
                      color: EzizaColors.kWhite, fontWeight: FontWeight.bold)),
              Text(_statusLabel(delivery.status),
                  style: const TextStyle(
                      color: EzizaColors.kSurface, fontSize: 12)),
            ]),
          ),
          const Icon(Icons.chevron_right, color: EzizaColors.kWhite),
        ]),
      ),
    );
  }

  String _statusLabel(String status) => switch (status) {
        'assigned'               => 'Head to pickup location',
        'awaiting_pickup_confirm' => 'Awaiting merchant handoff',
        'picked_up'              => 'En route to customer',
        'delivered'              => 'Waiting for customer confirmation',
        _                        => status,
      };
}

// ── Open delivery card ────────────────────────────────────────
class _DeliveryCard extends StatelessWidget {
  final Delivery delivery;
  const _DeliveryCard({required this.delivery});

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat.currency(symbol: '₦', decimalDigits: 0);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: EzizaColors.kBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Addresses
          _AddressRow(
            icon: Icons.radio_button_checked,
            color: EzizaColors.kPurple,
            label: 'Pickup',
            address: delivery.pickupAddress,
          ),
          const SizedBox(height: 8),
          _AddressRow(
            icon: Icons.location_on,
            color: EzizaColors.kGold,
            label: 'Drop-off',
            address: delivery.deliveryAddress,
          ),
          if (delivery.packageDescription != null) ...[
            const SizedBox(height: 8),
            Text(delivery.packageDescription!,
                style: const TextStyle(
                    color: EzizaColors.kMuted, fontSize: 12)),
          ],
          const Divider(height: 20),
          Row(children: [
            if (delivery.packageValue != null)
              Text('Value: ${fmt.format(delivery.packageValue)}',
                  style: const TextStyle(
                      color: EzizaColors.kMuted, fontSize: 12)),
            const Spacer(),
            ElevatedButton(
              onPressed: () => _showBidSheet(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: EzizaColors.kPurple,
                foregroundColor: EzizaColors.kWhite,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              ),
              child: const Text('Place Bid'),
            ),
          ]),
        ]),
      ),
    );
  }

  void _showBidSheet(BuildContext context) {
    final ctrl  = TextEditingController();
    final note  = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Place a Bid',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: EzizaColors.kText)),
          const SizedBox(height: 16),
          TextField(
            controller: ctrl,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Your price (₦)',
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: note,
            decoration: InputDecoration(
              labelText: 'Note (optional)',
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: EzizaColors.kPurple,
                foregroundColor: EzizaColors.kWhite,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () async {
                final amount = double.tryParse(ctrl.text.trim());
                if (amount == null) return;
                Navigator.pop(ctx);
                final result = await Get.find<DeliveryController>()
                    .placeBid(delivery.id, amount, note: note.text.trim());
                if (result == 'true') {
                  Get.snackbar('Bid placed', 'Your bid has been submitted.',
                      backgroundColor: EzizaColors.kSuccess,
                      colorText: EzizaColors.kWhite,
                      snackPosition: SnackPosition.BOTTOM);
                } else {
                  Get.snackbar('Error', result,
                      backgroundColor: EzizaColors.kError,
                      colorText: EzizaColors.kWhite,
                      snackPosition: SnackPosition.BOTTOM);
                }
              },
              child: const Text('Submit Bid'),
            ),
          ),
        ]),
      ),
    );
  }
}

class _AddressRow extends StatelessWidget {
  final IconData icon;
  final Color    color;
  final String   label;
  final String   address;
  const _AddressRow({
    required this.icon,
    required this.color,
    required this.label,
    required this.address,
  });

  @override
  Widget build(BuildContext context) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, color: color, size: 18),
      const SizedBox(width: 8),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: EzizaColors.kMuted)),
          Text(address,
              style: const TextStyle(
                  fontSize: 13, color: EzizaColors.kText)),
        ]),
      ),
    ]);
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) => const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox_outlined, size: 64, color: EzizaColors.kBorder),
            SizedBox(height: 12),
            Text('No open deliveries right now',
                style: TextStyle(color: EzizaColors.kMuted)),
          ],
        ),
      );
}
