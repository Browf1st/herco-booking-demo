// Small helpers for the header Account menu (both builds).
import type { ThemeChoice } from './theme';

/** The person shown in the header menu. `role` is shown on top of the menu (the menu capitalises it: owner, staff, Customer). */
export type MenuUser = { name: string; email: string; role: string };

/** What the sun/moon button switches to: the opposite of what is on screen now ("system" follows the device). */
export function oppositeTheme(choice: ThemeChoice, systemIsDark: boolean): 'light' | 'dark' {
	const showingDark = choice === 'dark' || (choice === 'system' && systemIsDark);
	return showingDark ? 'light' : 'dark';
}
