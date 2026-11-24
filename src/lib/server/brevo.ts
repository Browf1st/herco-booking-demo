type Address = {
	email: string;
	name?: string;
};

export type BrevoConfig =
	| { mode: 'disabled' }
	| ({
			apiKey: string;
			from: Address;
			replyTo?: Address;
	  } & (
			| { mode: 'allowlist'; allowedRecipients: readonly string[] }
			| { mode: 'live' }
	  ));

export type TransactionalEmail = {
	to: Address;
	subject: string;
	text: string;
	/** Extra mail headers, for example List-Unsubscribe. Sent in Brevo's `headers` field. */
	headers?: Record<string, string>;
};

export type BrevoSendResult =
	| { status: 'accepted'; messageId: string }
	| { status: 'skipped'; reason: 'disabled' | 'recipient-not-allowed' }
	| { status: 'rejected'; reason: 'invalid-configuration' | 'invalid-message' }
	| { status: 'rejected'; reason: 'provider'; httpStatus: number }
	| { status: 'retry'; reason: 'rate-limited'; retryAfterSeconds?: number }
	| { status: 'unknown'; reason: 'connection' | 'invalid-response' }
	| { status: 'unknown'; reason: 'provider'; httpStatus: number };

const endpoint = 'https://api.brevo.com/v3/smtp/email';
const normalizeEmail = (email: string) => email.trim().toLowerCase();
const isEmail = (email: string) => /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email.trim());

function retryAfter(value: string | null): number | undefined {
	if (!value) return;
	if (/^\d+$/.test(value)) {
		const seconds = Number(value);
		return Number.isSafeInteger(seconds) ? seconds : undefined;
	}
	const when = Date.parse(value);
	return Number.isFinite(when) ? Math.max(0, Math.ceil((when - Date.now()) / 1000)) : undefined;
}

/**
 * Makes one delivery attempt. The caller owns retries and reconciliation.
 * An unknown result can still mean Brevo accepted the message.
 */
export async function sendBrevoEmail(
	config: BrevoConfig,
	message: TransactionalEmail,
	request: typeof fetch = fetch
): Promise<BrevoSendResult> {
	if (config.mode === 'disabled') return { status: 'skipped', reason: 'disabled' };
	if (!isEmail(message.to.email) || !message.subject.trim() || !message.text.trim()) {
		return { status: 'rejected', reason: 'invalid-message' };
	}
	if (
		config.mode === 'allowlist' &&
		!config.allowedRecipients.some((email) => normalizeEmail(email) === normalizeEmail(message.to.email))
	) {
		return { status: 'skipped', reason: 'recipient-not-allowed' };
	}
	if (!config.apiKey.trim() || !isEmail(config.from.email) || (config.replyTo && !isEmail(config.replyTo.email))) {
		return { status: 'rejected', reason: 'invalid-configuration' };
	}

	let response: Response;
	try {
		response = await request(endpoint, {
			method: 'POST',
			headers: {
				'api-key': config.apiKey.trim(),
				'content-type': 'application/json',
				accept: 'application/json'
			},
			redirect: 'error',
			signal: AbortSignal.timeout(10_000),
			body: JSON.stringify({
				sender: { ...config.from, email: config.from.email.trim() },
				replyTo: config.replyTo && { ...config.replyTo, email: config.replyTo.email.trim() },
				to: [{ ...message.to, email: message.to.email.trim() }],
				subject: message.subject,
				textContent: message.text,
				headers: message.headers
			})
		});
	} catch {
		return { status: 'unknown', reason: 'connection' };
	}

	if (response.status === 429) {
		return { status: 'retry', reason: 'rate-limited', retryAfterSeconds: retryAfter(response.headers.get('retry-after')) };
	}
	if (response.status >= 500 || response.status === 408) {
		return { status: 'unknown', reason: 'provider', httpStatus: response.status };
	}
	if (!response.ok) {
		return { status: 'rejected', reason: 'provider', httpStatus: response.status };
	}
	try {
		const result: { messageId?: unknown } | null = await response.json();
		if (typeof result?.messageId === 'string' && result.messageId.trim()) {
			return { status: 'accepted', messageId: result.messageId };
		}
	} catch {
		// A successful HTTP response may still have committed the send.
	}
	return { status: 'unknown', reason: 'invalid-response' };
}
