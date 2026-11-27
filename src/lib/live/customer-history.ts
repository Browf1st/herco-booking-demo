// Turns the customer-safe change log (GET /api/bookings/history) into plain lines.
// It reads only the fields the customer may see (when, kind, you/shop, amounts, service name).
// Anything else the server might send (names, reasons, notes) is ignored on purpose. No imports, so Node tests can load it.

export type HistoryEntry = {
	at: string; kind: string; actor: string; from_centavos?: number | null; to_centavos?: number | null; service_label?: string | null;
};
export type HistoryLine = { key: string; when: string; actor: 'You' | 'Shop'; text: string };

/** The longest log shown (the server also caps it). */
export const historyCap = 200;
const peso = new Intl.NumberFormat('en-PH', { style: 'currency', currency: 'PHP' });
const stamp = new Intl.DateTimeFormat('en-PH', { dateStyle: 'medium', timeStyle: 'short', timeZone: 'Asia/Manila' });
const money = (centavos?: number | null) => typeof centavos === 'number' ? peso.format(centavos / 100) : '';
const plain: Record<string, string> = {
	booked: 'Booking made', approved: 'Booking confirmed', completed: 'Booking completed', cancelled: 'Booking cancelled', rescheduled: 'Booking rescheduled'
};

function describe(entry: HistoryEntry): string {
	const name = typeof entry.service_label === 'string' && entry.service_label.trim() ? entry.service_label.trim() : 'Service';
	const from = money(entry.from_centavos), to = money(entry.to_centavos);
	switch (entry.kind) {
		case 'price_changed':
		case 'price_corrected':
			return from && to ? `${name} price changed from ${from} to ${to}` : to ? `${name} price set to ${to}` : `${name} price changed`;
		case 'service_added': return to ? `Added ${name} (${to})` : `Added ${name}`;
		case 'service_removed': return from ? `Removed ${name} (${from})` : `Removed ${name}`;
		default: return plain[entry.kind] ?? 'Booking updated';
	}
}

/** Newest first, at most `historyCap` lines. */
export function historyLines(entries: readonly HistoryEntry[]): HistoryLine[] {
	return entries
		.filter((entry) => !Number.isNaN(Date.parse(entry.at)))
		.sort((a, b) => Date.parse(b.at) - Date.parse(a.at))
		.slice(0, historyCap)
		.map((entry, index) => ({
			key: entry.at + '-' + index, when: stamp.format(new Date(entry.at)),
			actor: entry.actor === 'you' ? 'You' : 'Shop', text: describe(entry)
		}));
}
