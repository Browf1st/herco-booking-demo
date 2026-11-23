// Keyboard rules for the Log in / Sign up tabs: arrows wrap around, Home and End jump to the ends.
// Returns the index of the tab to select, or null when the key does nothing.
export function nextTabIndex(key: string, index: number, count: number): number | null {
	if (count < 1) return null;
	if (key === 'Home') return 0;
	if (key === 'End') return count - 1;
	if (key === 'ArrowRight') return (index + 1) % count;
	if (key === 'ArrowLeft') return (index - 1 + count) % count;
	return null;
}
