// One theme setting for the whole site. The header menu and the Account page both use it.
export type ThemeChoice = 'system' | 'light' | 'dark';

/** Fired on window after the theme changes in this tab, so every theme control can update. */
export const THEME_EVENT = 'herco-theme-changed';
const STORAGE_KEY = 'herco-theme';

export const themeOptions: readonly { value: ThemeChoice; label: string }[] = [
	{ value: 'system', label: 'System' },
	{ value: 'light', label: 'Light' },
	{ value: 'dark', label: 'Dark' }
];

export function currentTheme(): ThemeChoice {
	const value = document.documentElement.dataset.theme;
	return value === 'light' || value === 'dark' ? value : 'system';
}

export function setTheme(value: ThemeChoice) {
	if (value === 'light' || value === 'dark') document.documentElement.dataset.theme = value;
	else delete document.documentElement.dataset.theme;
	try {
		if (value === 'system') localStorage.removeItem(STORAGE_KEY);
		else localStorage.setItem(STORAGE_KEY, value);
	} catch {
		// Private windows may block storage; the theme still applies for this visit.
	}
	window.dispatchEvent(new Event(THEME_EVENT));
}
