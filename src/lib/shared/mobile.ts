// One mobile-number rule for screens and server: digits with optional +, spaces, () and -, 7-15 digits in total.
// No imports, so Node tests and server code can both load it.
export function isValidMobile(value: string): boolean {
	const mobile = value.trim();
	return /^\+?[0-9 ()-]{7,20}$/.test(mobile) && /^\d{7,15}$/.test(mobile.replace(/\D/g, ''));
}
