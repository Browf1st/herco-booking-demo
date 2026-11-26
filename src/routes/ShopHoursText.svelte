<script lang="ts">
	// The shop's open days and hours as text ("Wed to Sun, 9 AM to 5 PM"). The footer loads this after the page
	// is shown, so every page's first download stays small.
	import { onMount } from 'svelte';

	import { liveShopHours, loadShopHours } from '#lib/live/shop-hours.svelte.ts';
	import { defaultSettings } from '#lib/shared/schedule-hours.ts';
	import { formatShopHours } from '#lib/shared/shop-hours-text.ts';
	// Until the live hours arrive (or if they fail), show the starting hours.
	const text = $derived(formatShopHours(liveShopHours.value ?? defaultSettings()).text);
	onMount(() => { void loadShopHours(); });
</script>

{text}
