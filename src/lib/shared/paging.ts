/** Number of pages for `total` items (always at least 1, so "Page 1 of 1" never becomes "of 0"). */
export function pageCount(total: number, perPage: number): number {
	if (!Number.isFinite(total) || total <= 0 || !Number.isInteger(perPage) || perPage <= 0) return 1;
	return Math.ceil(total / perPage);
}
