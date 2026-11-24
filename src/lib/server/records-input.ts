// Checks the JSON body of POST /api/staff/records. Returns the database arguments, or null when the body is not valid.
export const recordSorts = ['date', 'date_asc', 'price', 'price_asc', 'status'] as const;
export type RecordSort = (typeof recordSorts)[number];

const dateText = /^\d{4}-\d{2}-\d{2}$/;

export type RecordsQuery = {
	from: string | null; through: string | null; search: string; status: string; source: string;
	page: number; report: boolean; sort: RecordSort;
};

export function parseRecordsRequest(body: any): RecordsQuery | null {
	if (typeof body?.from !== 'string' || typeof body.through !== 'string') return null;
	const noDates = body.from === '' && body.through === '';
	if (!noDates && !(dateText.test(body.from) && dateText.test(body.through))) return null;
	if (typeof body.search !== 'string' || body.search.length > 254) return null;
	if (!['all', 'pending', 'confirmed', 'done', 'cancelled'].includes(body.status)) return null;
	if (!['all', 'online', 'walk-in'].includes(body.source)) return null;
	if (!Number.isInteger(body.page) || body.page < 1 || body.page > 500) return null;
	if (typeof body.report !== 'boolean') return null;
	// "sort" is optional so older screens keep working; when sent it must be one of the known values.
	if (body.sort !== undefined && !recordSorts.includes(body.sort)) return null;
	return {
		from: body.from || null, through: body.through || null, search: body.search, status: body.status, source: body.source,
		page: body.page, report: body.report, sort: body.sort ?? 'date'
	};
}
