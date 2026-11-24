// Small helpers for price changes, added services and the "Changes" list. No imports, so tests can run it directly.

export type HistoryEntry = {
	at: string; kind: string; actor?: string; service_code?: string; service_label?: string; reason?: string;
	from_centavos?: number | null; to_centavos?: number | null;
};
export type Checked<T> = ({ ok: true } & T) | { ok: false; message: string };

const peso = new Intl.NumberFormat('en-PH', { style: 'currency', currency: 'PHP', minimumFractionDigits: 0, maximumFractionDigits: 2 });
const when = new Intl.DateTimeFormat('en-US', { timeZone: 'Asia/Manila', month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit', hour12: true });
const statusWords: Record<string, string> = { booked: 'Booked', approved: 'Approved', completed: 'Completed', cancelled: 'Cancelled', rescheduled: 'Rescheduled' };
const isMoney = (value: unknown): value is number => typeof value === 'number' && Number.isFinite(value);

export const formatCentavos = (centavos: number) => peso.format(centavos / 100);

// Philippine time, like "Nov 24, 3:10 PM".
export function manilaWhen(iso: string) {
	const date = new Date(iso);
	return Number.isNaN(date.getTime()) ? 'Unknown time' : when.format(date).replace(/[  ]/g, ' ');
}

// One line of the Changes list. Amounts are left out when the server did not send them (no income permission).
export function historyLine(entry: HistoryEntry): string {
	const label = entry.service_label || entry.service_code || 'Service';
	let what = statusWords[entry.kind] ?? 'Changed';
	if (entry.kind === 'price_changed' || entry.kind === 'price_corrected') {
		const corrected = entry.kind === 'price_corrected';
		if (isMoney(entry.to_centavos) && isMoney(entry.from_centavos)) what = `${label} ${formatCentavos(entry.from_centavos)} → ${formatCentavos(entry.to_centavos)}`;
		else if (isMoney(entry.to_centavos)) what = `${label} set to ${formatCentavos(entry.to_centavos)}`;
		else what = `${label} price ${corrected ? 'corrected' : 'changed'}`;
	} else if (entry.kind === 'service_added') {
		what = `Added ${label}` + (isMoney(entry.to_centavos) ? ' ' + formatCentavos(entry.to_centavos) : '');
	} else if (entry.kind === 'service_removed') {
		what = `Removed ${label}` + (isMoney(entry.from_centavos) ? ' ' + formatCentavos(entry.from_centavos) : '');
	}
	return [manilaWhen(entry.at), entry.actor || 'HERCO staff', what, entry.reason?.trim()].filter(Boolean).join(' · ');
}

// The new price as typed by staff: whole pesos from 0 to 1,000,000. "₱2,300" and "2300" both work.
export function parsePesos(text: string): Checked<{ pesos: number }> {
	const cleaned = text.replace(/[₱\s,]/g, '');
	if (!cleaned) return { ok: false, message: 'Enter the new price.' };
	if (!/^-?\d+(\.\d+)?$/.test(cleaned)) return { ok: false, message: 'Enter the price as a number, like 2300.' };
	if (cleaned.startsWith('-')) return { ok: false, message: 'The price cannot be below ₱0.' };
	if (!/^\d+(\.0+)?$/.test(cleaned)) return { ok: false, message: 'Use whole pesos, like 2300.' };
	const pesos = Number(cleaned.split('.')[0]);
	if (pesos > 1_000_000) return { ok: false, message: 'The price cannot be more than ₱1,000,000.' };
	return { ok: true, pesos };
}

export function parseReason(text: string): Checked<{ reason: string }> {
	const reason = text.trim();
	if (!reason) return { ok: false, message: 'Enter a short reason for the change.' };
	if (reason.length > 200) return { ok: false, message: 'Keep the reason to 200 characters or fewer.' };
	return { ok: true, reason };
}

export { editRights } from './edit-rights.ts';

// The price a staff member saw for a line, sent back so the server can spot a newer change.
// Quote-only lines send the stored value (0 when it is 0 or missing), never null. undefined = the price is hidden, so it cannot be edited.
export function expectedCentavos(line: { price_centavos?: number | null; quote_required?: boolean }): number | undefined {
	if (isMoney(line.price_centavos)) return line.price_centavos;
	return line.quote_required ? 0 : undefined;
}

// True when the shop changed the services or the total after the booking was made (shown to the customer).
export function bookingWasUpdated(input: { originalTotal?: number | null; currentTotal?: number | null; originalCodes: readonly string[]; currentCodes?: readonly string[] | null }): boolean {
	const { originalTotal, currentTotal, originalCodes, currentCodes } = input;
	if (isMoney(originalTotal) && isMoney(currentTotal) && originalTotal !== currentTotal) return true;
	if (!currentCodes) return false;
	return originalCodes.length !== currentCodes.length || currentCodes.some((code) => !originalCodes.includes(code));
}
