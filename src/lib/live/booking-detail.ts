// Turns a staff booking into what the "More details" popup shows (Reports and the Bookings tab use the same design).
// Money is left out when the viewer may not see income.
import { fmtDate, fmtSlot } from '../shared/dates.ts';
import type { Detail } from '../shared/ReportDetails.svelte';
import { manilaStamp, popupTotalCentavos } from '../shared/report-ui.ts';
import type { StaffBooking } from './server-booking-types.ts';

const money = (cents?: number | null) => cents == null ? '—' : new Intl.NumberFormat('en-PH', { style: 'currency', currency: 'PHP' }).format(cents / 100);
const optionalMoney = (cents?: number) => cents === undefined ? undefined : money(cents);

export function detailOf(booking: StaffBooking, showMoney: boolean): Detail {
	return {
		name: booking.customer_name, ref: booking.reference ?? booking.id, status: booking.status,
		walkIn: booking.source === 'walk-in' || booking.visit_hour === null,
		bike: booking.plate ? booking.bike + ' · Plate ' + booking.plate : booking.bike,
		lines: booking.current_services?.length
			? booking.current_services.map((line) => ({ label: line.label, price: showMoney ? money(line.price_centavos) : undefined, parts: line.details?.map((part) => ({ label: part.label, price: showMoney ? money(part.price_centavos) : undefined })) }))
			: booking.services.map((label) => ({ label })),
		// Completed work shows its final price (what completed income counts); open bookings show the current total.
		total: showMoney ? optionalMoney(popupTotalCentavos(booking.status, booking.final_price_centavos, booking.total_centavos)) : undefined,
		phone: booking.customer_phone || undefined, email: booking.customer_email,
		visit: fmtDate(booking.visit_date) + ' · ' + (booking.visit_hour === null ? 'Walk-in' : fmtSlot(booking.visit_hour + ':00')),
		booked: manilaStamp(booking.created_at), approved: manilaStamp(booking.approved_at), completed: manilaStamp(booking.completed_at)
	};
}
