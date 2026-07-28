// Shared helper for the "look up a delivery by client-supplied id" pattern
// repeated across cancel-delivery/accept-bid/confirm-pickup/confirm-receipt/
// get-delivery. Those all previously did `if (!delivery) return
// json({ error: 'Delivery not found' }, 404)` without ever checking the
// query's own `error` -- a malformed delivery_id (e.g. a stray character
// from a copy-paste) fails as a Postgres "invalid input syntax for type
// uuid" error, not a real zero-row lookup, but got reported back to the
// caller as the same misleading "Delivery not found", pointing them at the
// wrong thing to check (a stale/wrong ID) instead of the real problem
// (a malformed one).
export function deliveryLookupFailure(
  error: { code?: string; message?: string } | null,
  notFoundMessage = 'Delivery not found',
  invalidFormatMessage = 'Invalid delivery_id format',
): { message: string; status: number } {
  // .single() itself errors on zero rows (PGRST116) -- that IS the normal
  // "genuinely doesn't exist" case, not an unexpected failure. Must be
  // checked before the catch-all error branch below, or a real not-found
  // would wrongly surface as a raw 500 with PostgREST's internal wording.
  if (error?.code === 'PGRST116' || !error) {
    return { message: notFoundMessage, status: 404 }
  }
  if (error.code === '22P02') {
    return { message: invalidFormatMessage, status: 400 }
  }
  return { message: error.message ?? 'Lookup failed', status: 500 }
}
