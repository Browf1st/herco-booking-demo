// Signed, single-purpose token for the "Unsubscribe from reminders" link (F-017).
// Format: v1.<customer id>.<expiry, unix seconds>.<signature>. It never contains an email address.
// The signature is HMAC-SHA256 over the purpose, customer id and expiry, so a token for another purpose
// (or another customer, or a later expiry) does not verify. Uses Web Crypto, available in Workers and Node.

const PURPOSE = 'maintenance-reminder-unsubscribe';
const VERSION = 'v1';
export const TOKEN_LIFETIME_SECONDS = 365 * 24 * 60 * 60;
export const MIN_SECRET_LENGTH = 32;
const uuidPattern = /^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/;
const signaturePattern = /^[A-Za-z0-9_-]{43}$/;
const encoder = new TextEncoder();

function base64url(bytes: Uint8Array): string {
	let text = '';
	for (const byte of bytes) text += String.fromCharCode(byte);
	return btoa(text).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function fromBase64url(value: string): Uint8Array<ArrayBuffer> | undefined {
	try {
		const text = atob(value.replace(/-/g, '+').replace(/_/g, '/'));
		return Uint8Array.from(text, character => character.charCodeAt(0));
	} catch {
		return undefined;
	}
}

function signingKey(secret: string, usage: 'sign' | 'verify') {
	if (secret.length < MIN_SECRET_LENGTH) throw new Error('The reminder token secret is too short.');
	return crypto.subtle.importKey('raw', encoder.encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, [usage]);
}

function signedText(customerId: string, expires: number) {
	return [PURPOSE, customerId, expires].join('|');
}

export async function signUnsubscribeToken(customerId: string, secret: string, nowMs: number = Date.now()): Promise<string> {
	if (!uuidPattern.test(customerId)) throw new Error('Invalid customer id for a reminder token.');
	const expires = Math.floor(nowMs / 1000) + TOKEN_LIFETIME_SECONDS;
	const signature = await crypto.subtle.sign('HMAC', await signingKey(secret, 'sign'), encoder.encode(signedText(customerId, expires)));
	return [VERSION, customerId, expires, base64url(new Uint8Array(signature))].join('.');
}

/** Returns the customer id for a genuine, unexpired token, otherwise undefined. Never throws on bad input. */
export async function verifyUnsubscribeToken(token: unknown, secret: string, nowMs: number = Date.now()): Promise<string | undefined> {
	if (typeof token !== 'string' || token.length > 200) return;
	const [version, customerId, expiry, signature, ...extra] = token.split('.');
	if (version !== VERSION || extra.length || !uuidPattern.test(customerId ?? '') || !/^\d{1,12}$/.test(expiry ?? '') ||
		!signaturePattern.test(signature ?? '')) return;
	const expires = Number(expiry);
	if (expires <= Math.floor(nowMs / 1000)) return;
	const given = fromBase64url(signature);
	if (!given) return;
	const valid = await crypto.subtle.verify('HMAC', await signingKey(secret, 'verify'), given, encoder.encode(signedText(customerId, expires)));
	return valid ? customerId : undefined;
}
