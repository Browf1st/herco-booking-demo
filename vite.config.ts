import adapter from '@sveltejs/adapter-static';
import { sveltekit } from '@sveltejs/kit/vite';
import { defineConfig, loadEnv } from 'vite';

export default defineConfig(({ mode }) => ({
	plugins: [
		sveltekit({
			compilerOptions: {
				// Force runes mode for the project, except for libraries. Can be removed in svelte 6.
				runes: ({ filename }) =>
					filename.split(/[/\\]/).includes('node_modules') ? undefined : true
			},

			// Static output for the UI-only demo; switch to adapter-cloudflare when the backend is added.
			adapter: adapter(),

			// GitHub Pages serves the site under /<repo-name>, set through BASE_PATH in the deploy workflow.
			paths: { base: (loadEnv(mode, '.', 'BASE_PATH').BASE_PATH ?? '') as `/${string}` | '' }
		})
	]
}));
