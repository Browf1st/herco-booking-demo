import cloudflare from '@sveltejs/adapter-cloudflare';
import { sveltekit } from '@sveltejs/kit/vite';
import { defineConfig } from 'vite';

export default defineConfig(({ mode }) => ({
	plugins: [
		sveltekit({
			compilerOptions: {
				// Force runes mode for the project, except for libraries. Can be removed in svelte 6.
				runes: ({ filename }) =>
					filename.split(/[/\\]/).includes('node_modules') ? undefined : true
			},

			// The live app uses Cloudflare Worker endpoints in every environment.
			adapter: cloudflare(),

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

			// The live app is served from the site root.
			paths: { base: '' }
		})
	]
}));
