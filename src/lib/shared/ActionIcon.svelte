<script lang="ts">
	const paths = {
		add: 'M12 5v14M5 12h14',
		adjust: 'M4 7h16M4 17h16M9 4v6m6 4v6',
		back: 'm12 5-7 7 7 7M5 12h14',
		block: 'M6 6l12 12M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0Z',
		box: 'm12 3 8 4v10l-8 4-8-4V7l8-4Zm-8 4 8 4 8-4m-8 4v10',
		calendar: 'M8 3v4m8-4v4M4 10h16M5 5h14a1 1 0 0 1 1 1v14a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V6a1 1 0 0 1 1-1Z',
		check: 'm5 12 4 4L19 6',
		clock: 'M12 7v5l3 2m6-2a9 9 0 1 1-18 0 9 9 0 0 1 18 0Z',
		close: 'm6 6 12 12M18 6 6 18',
		download: 'M12 3v12m-5-5 5 5 5-5M4 16v4h16v-4',
		edit: 'm15 5 4 4M4 20l4-.8L20 7l-4-4L4.8 15.8 4 20Z',
		finish: 'M5 21V4m0 1c5-4 9 4 14 0v10c-5 4-9-4-14 0',
		gift: 'M3 9h18v4H3zm2 4v8h14v-8m-7-4v12m0-12H8a2.5 2.5 0 1 1 2.5-2.5L12 9Zm0 0h4a2.5 2.5 0 1 0-2.5-2.5L12 9Z',
		hide: 'm3 3 18 18M10.6 5.1A9.8 9.8 0 0 1 12 5c6 0 10 7 10 7a17.6 17.6 0 0 1-3.1 3.8M6.6 6.6C3.9 8.4 2 12 2 12s4 7 10 7a9.6 9.6 0 0 0 5.4-1.6M9.9 9.9a3 3 0 0 0 4.2 4.2',
		history: 'M3 12a9 9 0 1 1 2 5.7M3 5v7h7m2-5v5l3 2',
		in: 'M12 3v11m-4-4 4 4 4-4M4 14v6h16v-6',
		left: 'm15 5-7 7 7 7',
		login: 'M14 4h6v16h-6M3 12h12m-4-4 4 4-4 4',
		logout: 'M10 4H4v16h6m1-8h10m-4-4 4 4-4 4',
		mail: 'M3 5h18v14H3zM3 6l9 7 9-7',
		menu: 'M4 6h16M4 12h16M4 18h16',
		moon: 'M20.9 13.2a9 9 0 1 1-10.1-10.1 7 7 0 0 0 10.1 10.1Z',
		out: 'M12 15V4m-4 4 4-4 4 4M4 14v6h16v-6',
		pause: 'M9 5v14m6-14v14',
		play: 'm8 5 12 7-12 7V5Z',
		ranking: 'M3 13h6v7H3zm6-9h6v16H9zm6 6h6v10h-6z',
		reset: 'M3 11a9 9 0 1 1 2 7M3 4v7h7',
		right: 'm9 5 7 7-7 7',
		search: 'm20 20-4.2-4.2M17 10.5a6.5 6.5 0 1 1-13 0 6.5 6.5 0 0 1 13 0Z',
		save:'M4 4h14l2 2v14H4zM8 4v6h8V4M8 20v-6h8v6',
		send: 'm3 11 18-8-7 18-3-8-8-2Zm8 2 10-10',
		sun: 'M12 2v2m0 16v2M2 12h2m16 0h2M5 5l1.4 1.4m11.2 11.2L19 19M5 19l1.4-1.4M17.6 6.4 19 5m-3 7a4 4 0 1 1-8 0 4 4 0 0 1 8 0Z',
		system: 'M3 4h18v13H3zm9 13v4m-4 0h8',
		user: 'M4 21v-2a5 5 0 0 1 5-5h6a5 5 0 0 1 5 5v2M16 7a4 4 0 1 1-8 0 4 4 0 0 1 8 0Z',
		view: 'M2 12s4-7 10-7 10 7 10 7-4 7-10 7S2 12 2 12Zm13 0a3 3 0 1 1-6 0 3 3 0 0 1 6 0Z'
	};
	let { name }: { name: keyof typeof paths } = $props();
</script>

<svg class="action-icon" aria-hidden="true" focusable="false" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
	<path d={paths[name]} />
</svg>

<style>
	.action-icon { width: 1em; height: 1em; flex: none; vertical-align: -.14em; }
</style>
