// Rules for the one-box-per-digit verification code input. No imports, so Node tests can load it.
// Digits are kept as one entry per box ('' = empty), so an empty box in the middle never shifts later digits.

export const DEFAULT_CODE_LENGTH = 6;

/** Supabase email codes are 6-10 digits. Anything else falls back to 6. */
export function codeLength(value: unknown): number {
	return typeof value === 'number' && Number.isInteger(value) && value >= 6 && value <= 10 ? value : DEFAULT_CODE_LENGTH;
}

/** An empty set of boxes. */
export function emptyDigits(length: number): string[] {
	return Array.from({ length }, () => '');
}

/**
 * Applies what was typed or pasted into box `index`.
 * Non-digits are dropped. Several digits (paste or phone auto-fill) fill the following boxes.
 * Returns the new digits and which box should get focus next.
 */
export function fillDigits(current: readonly string[], index: number, raw: string, length: number) {
	const digits = Array.from({ length }, (_, i) => current[i] ?? '');
	const typed = raw.replace(/\D/g, '');
	if (!typed) {
		digits[index] = '';
		return { digits, focus: index };
	}
	// A full code pasted into any box replaces the whole code.
	const start = typed.length >= length ? 0 : index;
	let position = start;
	for (const digit of typed.slice(0, length - start)) digits[position++] = digit;
	return { digits, focus: Math.min(position, length - 1) };
}

/** Backspace: clears this box, or the box before it when this one is already empty. Other boxes stay put. */
export function backspaceDigits(current: readonly string[], index: number) {
	const digits = [...current];
	if (digits[index]) {
		digits[index] = '';
		return { digits, focus: index };
	}
	const previous = Math.max(0, index - 1);
	digits[previous] = '';
	return { digits, focus: previous };
}

/** The finished code, or '' while any box is still empty. */
export function codeValue(digits: readonly string[]): string {
	return digits.every(Boolean) ? digits.join('') : '';
}

/** Shows "ja***@example.com" so the screen confirms where the code went without printing the full address. */
export function maskEmail(email: string): string {
	const [name, domain] = email.trim().split('@');
	if (!name || !domain) return email.trim();
	return name.slice(0, Math.min(2, name.length)) + '***@' + domain;
}
