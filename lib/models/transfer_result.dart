/// The platform contract is decoded once, before it reaches gallery logic.
class TransferResult {
  const TransferResult({
    this.successfulIds = const [],
    this.skippedIds = const [],
    this.failures = const [],
    this.cancelled = false,
  });

  factory TransferResult.fromMap(Map<Object?, Object?> data) => TransferResult(
    successfulIds: List<String>.from(data['success'] as List? ?? const []),
    skippedIds: List<String>.from(data['skipped'] as List? ?? const []),
    failures: [
      for (final failure in data['failures'] as List? ?? const [])
        TransferFailure(
          photoId: (failure as Map)['id'] as String,
          reason: failure['reason'] as String? ?? 'unspecifiedReason',
        ),
    ],
    cancelled: data['cancelled'] == true,
  );

  final List<String> successfulIds;
  final List<String> skippedIds;
  final List<TransferFailure> failures;
  final bool cancelled;
}

class TransferFailure {
  const TransferFailure({required this.photoId, required this.reason});

  final String photoId;
  final String reason;
}
