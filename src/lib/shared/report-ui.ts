// Helpers for the Booking Reports screens (demo and live): rows, price column, sorting and popup text.
import type { RecordStatus } from './records-ui';

/** One row of the Reports list, already turned into text by the screen. `price` is "—" when it is unknown or not allowed. */
export type ReportRow = {
	id: string; ref: string; name: string; bike: string; walkIn: boolean; phone?: string;
	date: string; time: string; services: string; status: RecordStatus;
	price?: string; priceKind?: 'final' | 'estimate' | 'none'; priceValue?: number;
};

/** Up to two capital letters for the round avatar ("TEST UI Rider" -> "TU"). */
export function initials(name: string): string {
	const letters = name.trim().split(/\s+/u).filter(Boolean).slice(0, 2).map((word) => Array.from(word)[0]);
	return letters.join('').toUpperCase() || '?';
}

/** The Price column: done shows the final price, pending and booked show the original estimate, anything else "—". */
export function reportPrice(status: RecordStatus, final?: string | null, estimate?: string | null): { text: string; kind: 'final' | 'estimate' | 'none' } {
	if (status === 'done' && final) return { text: final, kind: 'final' };
	if ((status === 'pending' || status === 'confirmed') && estimate) return { text: estimate, kind: 'estimate' };
	return { text: '—', kind: 'none' };
}

export type ReportSort = 'date' | 'price' | 'status';
export const sortOptions: { value: ReportSort; label: string }[] = [{ value: 'date', label: 'Date (newest)' }, { value: 'price', label: 'Price (high to low)' }, { value: 'status', label: 'Status' }];
const statusOrder: RecordStatus[] = ['pending', 'confirmed', 'done', 'cancelled'];

/** A sorted copy. "date" keeps the order the list already has (newest first). Rows without a price go last. */
export function sortReportRows(rows: ReportRow[], sort: ReportSort): ReportRow[] {
	if (sort === 'price') return rows.toSorted((a, b) => (b.priceValue ?? -1) - (a.priceValue ?? -1));
	if (sort === 'status') return rows.toSorted((a, b) => statusOrder.indexOf(a.status) - statusOrder.indexOf(b.status));
	return rows.slice();
}

/** "Nov 20, 2026, 4:38 PM" in Philippine time, or "Not recorded" when the time is missing or not a date. */
export function manilaStamp(value?: string | null): string {
	const time = value ? new Date(value) : undefined;
	if (!time || Number.isNaN(time.getTime())) return 'Not recorded';
	return time.toLocaleString('en-PH', { timeZone: 'Asia/Manila', dateStyle: 'medium', timeStyle: 'short' });
}

/** "Showing 1 to 9 of 9 entries" numbers. `count` is how many rows this page holds; only the last page can be short. */
export function entryRange(page: number, pages: number, total: number, count: number): { from: number; to: number } {
	if (count <= 0 || total <= 0) return { from: 0, to: 0 };
	const from = page >= pages ? total - count + 1 : (page - 1) * count + 1;
	return { from, to: from + count - 1 };
}

/** "HG-11, HG-15" when there are only a few references, otherwise nothing (the list would be too long to be useful). */
export function refsText(refs: string[] | undefined, limit = 3): string {
	return refs && refs.length > 0 && refs.length <= limit ? refs.join(', ') : '';
}
