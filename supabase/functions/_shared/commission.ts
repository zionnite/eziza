import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

// Eziza's platform commission on External Carrier (Shipbubble) bookings —
// previously pure pass-through in both directions (Eziza Direct customers
// and tenants alike paid exactly the carrier's raw quote). Reuses the same
// settings.platform_fee_pct already applied to internal-rider deliveries
// (credit_delivery_earnings()) rather than a second rate to separately
// configure — one unified "Eziza platform commission" concept across both
// fulfillment channels. Stored as a fraction (0.10 = 10%), not a percentage.
export async function getPlatformFeePct(client: ReturnType<typeof createClient>): Promise<number> {
  const { data } = await client
    .from('settings')
    .select('value')
    .eq('key', 'platform_fee_pct')
    .maybeSingle()
  return Number(data?.value ?? 0.10)
}

export function applyCommission(carrierCost: number, feePct: number): { total: number; commission: number } {
  const commission = Math.round(carrierCost * feePct * 100) / 100
  const total = Math.round((carrierCost + commission) * 100) / 100
  return { total, commission }
}
