import adapter from '@sveltejs/adapter-static';
import cloudflare from '@sveltejs/adapter-cloudflare';
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

			// GitHub Pages publishes the demo. The Worker build includes the server endpoints.
			adapter: mode === 'worker' ? cloudflare() : adapter({ strict: false }),

			// Static pages receive a hashed CSP meta tag. The Worker adds HTTP-only
			// framing protection in _headers and hooks.server.ts.
			...(mode === 'production' || mode === 'worker' ? { csp: {
				mode: 'hash' as const,
				directives: {
					'default-src': ['self'],
					'script-src': ['self'],
					'style-src': ['self', 'unsafe-inline', 'https://fonts.googleapis.com'],
					'font-src': ['self', 'https://fonts.gstatic.com'],
					'img-src': ['self', 'data:', 'blob:'],
					'object-src': ['none'],
					'base-uri': ['self'],
					'form-action': ['self']
				}
			} } : {}),

			// GitHub Pages serves the site under /<repo-name>, set through BASE_PATH in the deploy workflow.
			paths: { base: (loadEnv(mode, '.', 'BASE_PATH').BASE_PATH ?? '') as `/${string}` | '' }
		})
	]
}));
