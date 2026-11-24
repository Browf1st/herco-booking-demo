<!-- Styles load together with this screen (not in the page's first stylesheet). -->
<svelte:options css="injected" />
<script lang="ts">
	// Icons used only by the Reports screens and the Account menu, kept apart from ActionIcon so every page does not download them.
	const paths = {
		down: 'm6 9 6 6 6-6',
		gear: 'M12 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6ZM12 2v3m0 14v3M2 12h3m14 0h3M5 5l2 2m10 10 2 2M19 5l-2 2M7 17l-2 2',
		phone: 'M5 4h4l2 5-2.5 1.5a11 11 0 0 0 5 5L15 13l5 2v4a2 2 0 0 1-2 2A16 16 0 0 1 3 6a2 2 0 0 1 2-2Z',
		up: 'm6 15 6-6 6 6'
	};
	let { name }: { name: keyof typeof paths } = $props();
</script>

<svg class="icon" aria-hidden="true" focusable="false" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d={paths[name]} /></svg>

<style>
	.icon { width: 1em; height: 1em; flex: none; vertical-align: -.14em; }
</style>