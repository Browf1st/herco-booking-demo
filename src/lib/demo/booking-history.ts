// Builds the demo "Changes" list from what the demo store keeps on a booking. Types only, so tests can run it directly.
import type { HistoryEntry } from '../shared/booking-changes';

type Line = { label: string; subtotal: number };
type Change = { at: string; actor: string; reason?: string; before: { estimate?: { lines?: Line[] } }; after: { estimate?: { lines?: Line[] } } };
export type HistorySource = {
	status: string; createdAt?: string; approvedAt?: string; completedAt?: string; cancelledAt?: string;
	walkIn?: { at: string }; bookedByStaff?: boolean; serviceChanges?: Change[];
};
const centavos = (pesos: number) => Math.round(pesos * 100);

// Newest first, like the live list. Amounts are left out when the viewer may not see income.
export function demoHistory(booking: HistorySource, showMoney: boolean): HistoryEntry[] {
	const entries: HistoryEntry[] = [];
	const when = (at: string | undefined, kind: string, actor: string) => { if (at) entries.push({ at, kind, actor }); };
	when(booking.createdAt ?? booking.walkIn?.at, 'booked', booking.bookedByStaff || booking.walkIn ? 'HERCO staff' : 'Customer');
	when(booking.approvedAt, 'approved', 'HERCO staff');
	if (booking.status === 'done') when(booking.completedAt, 'completed', 'HERCO staff');
	when(booking.cancelledAt, 'cancelled', 'HERCO staff');
	for (const change of booking.serviceChanges ?? []) {
		const before = change.before.estimate?.lines ?? [];
		const after = change.after.estimate?.lines ?? [];
		const base = { at: change.at, actor: change.actor };
		for (const line of after) {
			const old = before.find((item) => item.label === line.label);
			if (!old) entries.push({ ...base, kind: 'service_added', service_label: line.label, to_centavos: centavos(line.subtotal) });
			else if (old.subtotal !== line.subtotal) entries.push({ ...base, kind: 'price_changed', service_label: line.label, from_centavos: centavos(old.subtotal), to_centavos: centavos(line.subtotal), reason: change.reason });
		}
		for (const old of before) if (!after.some((line) => line.label === old.label)) entries.push({ ...base, kind: 'service_removed', service_label: old.label, from_centavos: centavos(old.subtotal) });
	}
	const stripped = showMoney ? entries : entries.map(({ from_centavos, to_centavos, ...rest }) => rest);
	return stripped.map((entry, index) => ({ entry, index })).sort((a, b) => Date.parse(b.entry.at) - Date.parse(a.entry.at) || a.index - b.index).map(({ entry }) => entry);
}
