import { error } from '@sveltejs/kit';

// The largest HERCO JSON form is far smaller than 32 KiB. Photo uploads use
// their own stream limit and must not be passed through this JSON reader.
export const MAX_JSON_BYTES = 32 * 1024;

export async function readJsonBody(request: Request) {
	if (Number(request.headers.get('content-length')) > MAX_JSON_BYTES) {
		error(413, 'This request is too large.');
	}

	const body = request.body;
	if (!body || body.locked || request.bodyUsed) return null;
	const reader = body.getReader();
	const decoder = new TextDecoder('utf-8', { fatal: true });
	let bytes = 0;
	let text = '';

	try {
		while (true) {
			let chunk: ReadableStreamReadResult<Uint8Array>;
			try {
				chunk = await reader.read();
			} catch {
				// Preserve each endpoint's existing validation for unreadable JSON.
				return null;
			}
			if (chunk.done) break;
			bytes += chunk.value.byteLength;
			if (bytes > MAX_JSON_BYTES) {
				await reader.cancel().catch(() => {});
				error(413, 'This request is too large.');
			}
			try {
				text += decoder.decode(chunk.value, { stream: true });
			} catch {
				await reader.cancel().catch(() => {});
				return null;
			}
		}
		try {
			return JSON.parse(text + decoder.decode());
		} catch {
			return null;
		}
	} finally {
		reader.releaseLock();
	}
}
