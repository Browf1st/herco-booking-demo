import { json } from '@sveltejs/kit';
import { requireSameOrigin } from '#lib/server/supabase.ts';
import type { RequestHandler } from './$types';

// Retired in F-021: the per-bike rules now live in config.powderModel.exceptions
// (see /api/pricing/catalog). The route stays so callers get a clear 410, not a 404.
export const prerender = false;
const retired = () => json({ message: 'Coating rules moved into the pricing catalog.' }, { status: 410 });

export const GET: RequestHandler = async () => retired();

export const POST: RequestHandler = async (event) => {
	requireSameOrigin(event);
	return retired();
};
