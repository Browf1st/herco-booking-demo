import { createClient } from '@supabase/supabase-js';

type CleanupEnv = {
	HERCO_PHOTO_CLEANUP_MODE?: string;
	HERCO_PHOTO_CLEANUP_RETENTION_DAYS?: string;
	HERCO_PHOTO_CLEANUP_URL?: string;
	HERCO_PHOTO_CLEANUP_SECRET_KEY?: string;
};
type ClaimedPhoto = { object_path: string; claim_id: string | null; object_exists: boolean };

const bucket = 'herco-completion';
const uuid = '[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}';
const pathFormat = new RegExp('^' + uuid + '/' + uuid + '/' + uuid + '\\.(jpg|png|webp)$');
const claimFormat = new RegExp('^' + uuid + '$');
const batchSize = 25;

function projectOrigin(value: string | undefined) {
	if (!value) return null;
	try {
		const url = new URL(value);
		return url.protocol === 'https:' && !url.username && !url.password &&
			url.pathname === '/' && !url.search && !url.hash ? url.origin : null;
	} catch {
		return null;
	}
}

function validClaims(value: unknown, preview: boolean): value is ClaimedPhoto[] {
	if (!Array.isArray(value) || value.length > batchSize) return false;
	const batch = value[0]?.claim_id;
	return value.every(row => row && typeof row.object_path === 'string' && pathFormat.test(row.object_path) &&
		typeof row.object_exists === 'boolean' &&
		(preview ? row.claim_id === null : typeof batch === 'string' && claimFormat.test(batch) && row.claim_id === batch));
}

export async function runPhotoCleanup(env: CleanupEnv, fetchRequest: typeof fetch = fetch) {
	const mode = env.HERCO_PHOTO_CLEANUP_MODE ?? 'disabled';
	if (mode === 'disabled') return { state: 'disabled' };
	const retentionDays = Number(env.HERCO_PHOTO_CLEANUP_RETENTION_DAYS);
	const url = projectOrigin(env.HERCO_PHOTO_CLEANUP_URL);
	const key = env.HERCO_PHOTO_CLEANUP_SECRET_KEY?.trim();
	if ((mode !== 'report' && mode !== 'active') || !url || !key ||
		!Number.isInteger(retentionDays) || retentionDays < 7 || retentionDays > 3650) {
		return { state: 'configuration_error' };
	}

	const supabase = createClient(url, key, {
		auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
		global: { fetch: (input, init) => fetchRequest(input, { ...init, signal: AbortSignal.timeout(15000) }) }
	});
	const preview = mode === 'report';
	const { data, error: claimError } = await supabase.rpc('herco_claim_completion_photo_cleanup', {
		p_retention_days: retentionDays, p_limit: batchSize, p_preview: preview
	});
	if (claimError || !validClaims(data, preview)) return { state: 'claim_failed' };
	if (preview) return { state: 'report', candidates: data.length };
	if (!data.length) return { state: 'idle', removed: 0 };

	const paths = data.filter(photo => photo.object_exists).map(photo => photo.object_path);
	const { error: deletionError } = paths.length ? await supabase.storage.from(bucket).remove(paths) : { error: null };
	// A timeout may follow a successful deletion. Finalize only paths PostgreSQL confirms are already gone.
	const { data: removed, error: confirmationError } = await supabase.rpc('herco_confirm_completion_photo_cleanup', {
		p_claim_id: data[0].claim_id
	});
	if (confirmationError || !Number.isInteger(removed) || removed < 0 || removed > data.length) {
		return { state: 'confirmation_failed', claimed: data.length };
	}
	return { state: deletionError || removed !== data.length ? 'retry_pending' : 'removed', claimed: data.length, removed };
}

export default {
	async scheduled(_controller: unknown, env: CleanupEnv) {
		// Record counts and outcomes. The object paths and credentials stay private.
		try {
			const result = await runPhotoCleanup(env);
			if (result.state !== 'disabled') console.log('herco_completion_cleanup', result);
		} catch {
			console.error('herco_completion_cleanup', { state: 'unavailable' });
		}
	}
};
