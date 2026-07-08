class Rider {
  final String id;
  final String? authUserId;
  final String fullName;
  final String phone;
  final String? email;
  final String vehicleType;
  final String? vehiclePlate;
  final List<String> coverageStates;
  final String? bankName;
  final String? accountNumber;
  final String? accountName;
  final bool isApproved;
  final bool isAvailable;
  final double ratingAvg;
  final int totalDeliveries;
  final double walletBalance;
  final String? fcmToken;
  final String status; // pending / approved / rejected / suspended
  final String? avatarUrl;

  const Rider({
    required this.id,
    this.authUserId,
    required this.fullName,
    required this.phone,
    this.email,
    required this.vehicleType,
    this.vehiclePlate,
    required this.coverageStates,
    this.bankName,
    this.accountNumber,
    this.accountName,
    required this.isApproved,
    required this.isAvailable,
    required this.ratingAvg,
    required this.totalDeliveries,
    required this.walletBalance,
    this.fcmToken,
    required this.status,
    this.avatarUrl,
  });

  factory Rider.fromJson(Map<String, dynamic> j) {
    final approved = j['is_approved'] as bool? ?? false;
    return Rider(
      id: j['id'] as String,
      authUserId: j['auth_user_id'] as String?,
      fullName: j['full_name'] as String,
      phone: j['phone'] as String,
      email: j['email'] as String?,
      vehicleType: j['vehicle_type'] as String,
      vehiclePlate: j['vehicle_plate'] as String?,
      coverageStates: List<String>.from(j['coverage_states'] ?? []),
      bankName: j['bank_name'] as String?,
      accountNumber: j['account_number'] as String?,
      accountName: j['account_name'] as String?,
      isApproved: approved,
      isAvailable: j['is_available'] as bool? ?? true,
      ratingAvg: (j['rating_avg'] as num?)?.toDouble() ?? 0,
      totalDeliveries: j['total_deliveries'] as int? ?? 0,
      walletBalance: (j['wallet_balance'] as num?)?.toDouble() ?? 0,
      fcmToken: j['fcm_token'] as String?,
      status: j['status'] as String? ?? (approved ? 'approved' : 'pending'),
      avatarUrl: j['avatar_url'] as String?,
    );
  }
}
