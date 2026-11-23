// Pure helpers for the Showcase gallery (filters, paging, lightbox steps). No Svelte, so tests can import them.
export const SHOWCASE_PAGE = 24;

export type ShowcaseFilter<C extends string> = 'all' | C;

export function filterPhotos<P extends { category: string }>(photos: readonly P[], filter: string): P[] {
	return filter === 'all' ? [...photos] : photos.filter((photo) => photo.category === filter);
}

export function countByCategory(photos: readonly { category: string }[]): Record<string, number> {
	const counts: Record<string, number> = { all: photos.length };
	for (const photo of photos) counts[photo.category] = (counts[photo.category] ?? 0) + 1;
	return counts;
}

/** How many tiles to show after `pages` clicks of "Show more" (never more than `total`). */
export function shownCount(total: number, pages: number): number {
	const safePages = Number.isInteger(pages) && pages > 0 ? pages : 1;
	return Math.max(0, Math.min(total, safePages * SHOWCASE_PAGE));
}

/** Next/previous photo in the lightbox, wrapping around at both ends. */
export function stepIndex(index: number, delta: number, total: number): number {
	if (total <= 0) return -1;
	return (((index + delta) % total) + total) % total;
}

/** Swipe direction from a horizontal finger move: -1 (previous), 1 (next) or 0 (too short or mostly vertical). */
export function swipeDelta(dx: number, dy: number, threshold = 50): -1 | 0 | 1 {
	if (Math.abs(dx) < threshold || Math.abs(dx) < Math.abs(dy) * 1.5) return 0;
	return dx < 0 ? 1 : -1;
}
