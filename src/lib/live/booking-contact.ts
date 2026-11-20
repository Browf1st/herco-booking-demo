// Small booking-form rules. Imports use explicit .ts paths so the Node test runner can load them directly.
import { isValidMobile } from '../shared/mobile.ts';

/** Turns a picked visit hour ("11" or 11) into the "HH:00" slot that fmtSlot expects. */
export function slotFromHour(hour: string | number): string {
	return String(hour) + ':00';
}

/**
 * Checks the name and mobile number before the review step. Returns an error message, or '' when valid.
 * The mobile number is optional unless required (walk-ins and staff bookings), but if typed it must be valid:
 * 7-15 digits, with only +, spaces, () and - besides digits (same rule as the profile and the booking server).
 */
export function contactError(name: string, phone: string, phoneRequired: boolean): string {
	if (!name.trim()) return 'Enter your name.';
	const blank = phone.trim() === '';
	if (phoneRequired && !isValidMobile(phone)) return 'Enter a valid mobile number.';
	if (!phoneRequired && !blank && !isValidMobile(phone)) return 'Enter a valid mobile number, or leave it blank.';
	return '';
}
