// Checks the JSON body of POST /api/staff/line-price. Returns the database arguments, or null when the body is not valid.
const uuid = /^[\da-f]{8}(?:-[\da-f]{4}){3}-[\da-f]{12}$/i;

export const maxLinePricePesos = 1_000_000;
export const maxLinePriceReason = 200;

export type LinePriceRequest = {
	booking: string; requestId: string; service: string;
	/** The line's stored price_centavos as the staff member saw it. For a quote-only line (no price) send 0 or null; both match. */
	expectedCentavos: number | null;
	/** New price in centavos (whole pesos only). */
	centavos: number;
	reason: string;
};

export function parseLinePriceRequest(body: any): LinePriceRequest | null {
	if (typeof body?.booking !== 'string' || !uuid.test(body.booking)) return null;
	if (typeof body.requestId !== 'string' || !uuid.test(body.requestId)) return null;
	if (typeof body.service !== 'string' || !body.service || body.service.length > 100) return null;
	if (body.expectedCentavos !== null && !(Number.isSafeInteger(body.expectedCentavos) && body.expectedCentavos >= 0)) return null;
	if (!Number.isSafeInteger(body.pesos) || body.pesos < 0 || body.pesos > maxLinePricePesos) return null;
	if (typeof body.reason !== 'string') return null;
	const reason = body.reason.trim();
	if (!reason || reason.length > maxLinePriceReason) return null;
	return {
		booking: body.booking, requestId: body.requestId, service: body.service,
		expectedCentavos: body.expectedCentavos, centavos: body.pesos * 100, reason
	};
}

/** Maps a database error code from herco_staff_set_line_price to the API answer. */
export function linePriceFailure(code: string):
	{ status: 400 | 403 | 404 | 409 | 503; code?: 'booking_locked' | 'line_changed'; message: string } {
	switch (code) {
		case '42501': return { status: 403, message: 'You do not have permission to change prices.' };
		case 'P0002': return { status: 404, message: 'Booking not found.' };
		case 'P0423': return { status: 409, code: 'booking_locked', message: 'This booking can no longer be changed.' };
		case 'P0412': return { status: 409, code: 'line_changed', message: 'This service was changed by someone else. Reload to see the latest.' };
		case 'P0400': return { status: 400, message: 'That is already the price.' };
		case '22023': return { status: 400, message: 'Enter a whole-peso price from 0 to 1,000,000 and a reason of up to 200 characters.' };
		default: return { status: 503, message: 'Price changes are temporarily unavailable. Retry using the same details.' };
	}
}

/** For the 409 of POST /api/booking-services: can the booking still be edited (then the revision was stale) or not. */
export function serviceConflict(canEdit: unknown): { code: 'booking_locked' | 'line_changed'; message: string } {
	return canEdit === false
		? { code: 'booking_locked', message: 'This booking can no longer be changed.' }
		: { code: 'line_changed', message: 'The booking changed. Reload to see the latest.' };
}
