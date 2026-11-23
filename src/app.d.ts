// See https://svelte.dev/docs/kit/types#app.d.ts
// for information about these interfaces
declare global {
	namespace App {
		// interface Error {}
		// interface Locals {}
		// interface PageData {}
		interface PageState {
			/** Set while the Showcase photo viewer is open, so the phone Back button closes it. */
			showcasePhoto?: boolean;
		}
		// interface Platform {}
	}
}

export {};
