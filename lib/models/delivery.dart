class Delivery {
  final String id;
  final String tenantId;
  final String externalOrderId;
  final String pickupAddress;
  final double? pickupLat;
  final double? pickupLng;
  final String? pickupContactName;
  final String? pickupContactPhone;
  final String deliveryAddress;
  final double? deliveryLat;
  final double? deliveryLng;
  final String? deliveryContactName;
  final String? deliveryContactPhone;
  final String? packageDescription;
  final double? packageValue;
  final String status;
  final String? riderId;
  final double? agreedPrice;
  final double? platformFee;
  final DateTime? bidClosesAt;
  final DateTime? confirmedAt;
  final DateTime createdAt;

  const Delivery({
    required this.id,
    required this.tenantId,
    required this.externalOrderId,
    required this.pickupAddress,
    this.pickupLat,
    this.pickupLng,
    this.pickupContactName,
    this.pickupContactPhone,
    required this.deliveryAddress,
    this.deliveryLat,
    this.deliveryLng,
    this.deliveryContactName,
    this.deliveryContactPhone,
    this.packageDescription,
    this.packageValue,
    required this.status,
    this.riderId,
    this.agreedPrice,
    this.platformFee,
    this.bidClosesAt,
    this.confirmedAt,
    required this.createdAt,
  });

  factory Delivery.fromJson(Map<String, dynamic> j) => Delivery(
        id: j['id'] as String,
        tenantId: j['tenant_id'] as String,
        externalOrderId: j['external_order_id'] as String,
        pickupAddress: j['pickup_address'] as String,
        pickupLat: (j['pickup_lat'] as num?)?.toDouble(),
        pickupLng: (j['pickup_lng'] as num?)?.toDouble(),
        pickupContactName: j['pickup_contact_name'] as String?,
        pickupContactPhone: j['pickup_contact_phone'] as String?,
        deliveryAddress: j['delivery_address'] as String,
        deliveryLat: (j['delivery_lat'] as num?)?.toDouble(),
        deliveryLng: (j['delivery_lng'] as num?)?.toDouble(),
        deliveryContactName: j['delivery_contact_name'] as String?,
        deliveryContactPhone: j['delivery_contact_phone'] as String?,
        packageDescription: j['package_description'] as String?,
        packageValue: (j['package_value'] as num?)?.toDouble(),
        status: j['status'] as String,
        riderId: j['rider_id'] as String?,
        agreedPrice: (j['agreed_price'] as num?)?.toDouble(),
        platformFee: (j['platform_fee'] as num?)?.toDouble(),
        bidClosesAt: j['bid_closes_at'] != null
            ? DateTime.parse(j['bid_closes_at'] as String)
            : null,
        confirmedAt: j['confirmed_at'] != null
            ? DateTime.parse(j['confirmed_at'] as String)
            : null,
        createdAt: DateTime.parse(j['created_at'] as String),
      );

  bool get isOpen => status == 'open';
  bool get isAssigned => status == 'assigned';
  bool get isPickedUp => status == 'picked_up';
  bool get isDelivered => status == 'delivered';
  bool get isConfirmed => status == 'confirmed';
  bool get isCancelled => status == 'cancelled';
}
