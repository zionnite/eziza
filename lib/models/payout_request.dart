class PayoutRequest {
  final String  id;
  final double  amount;
  final String  status; // pending | paid | rejected
  final String? bankName;
  final String? accountNumber;
  final String? accountName;
  final DateTime  createdAt;
  final DateTime? paidAt;

  const PayoutRequest({
    required this.id,
    required this.amount,
    required this.status,
    this.bankName,
    this.accountNumber,
    this.accountName,
    required this.createdAt,
    this.paidAt,
  });

  factory PayoutRequest.fromJson(Map<String, dynamic> j) => PayoutRequest(
        id:            j['id'] as String,
        amount:        (j['amount'] as num).toDouble(),
        status:        j['status'] as String,
        bankName:      j['bank_name'] as String?,
        accountNumber: j['account_number'] as String?,
        accountName:   j['account_name'] as String?,
        createdAt:     DateTime.parse(j['created_at'] as String),
        paidAt: j['paid_at'] != null
            ? DateTime.parse(j['paid_at'] as String)
            : null,
      );

  bool get isPending  => status == 'pending';
  bool get isPaid     => status == 'paid';
  bool get isRejected => status == 'rejected';
}
