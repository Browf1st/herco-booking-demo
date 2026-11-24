<!-- Styles load together with this screen (not in the page's first stylesheet). -->
<svelte:options css="injected" />
<script lang="ts">
	// The red "Book" button with a Walk-in / Online menu. The screen only renders it for staff who may create bookings.
	import ActionIcon from './ActionIcon.svelte';
	import MoreIcons from './MoreIcons.svelte';

	let { links }: { links: { label: string; href: string }[] } = $props();
	let menu = $state<HTMLDetailsElement>();
</script>

<svelte:window onclick={(event) => { if (menu?.open && event.target instanceof Node && !menu.contains(event.target)) menu.open = false; }}
	onkeydown={(event) => { if (event.key === 'Escape' && menu?.open) { menu.open = false; menu.querySelector('summary')?.focus(); } }} />

<details class="book" bind:this={menu}>
	<summary><ActionIcon name="add" />Book <MoreIcons name="down" /></summary>
	<div class="options">{#each links as link (link.label)}<a href={link.href} data-sveltekit-reload>{link.label}</a>{/each}</div>
</details>

<style>
	.book { position: relative; }
	summary { display: inline-flex; align-items: center; gap: .45rem; min-height: 2.75rem; padding: 0 1.1rem; border-radius: 8px; background: var(--accent-fill); color: var(--accent-ink); font: 800 .95rem var(--body); list-style: none; cursor: pointer; }
	summary::-webkit-details-marker { display: none; }
	summary:focus-visible { outline: 2px solid var(--accent); outline-offset: 2px; }
	.options { position: absolute; inset: calc(100% + .3rem) 0 auto auto; z-index: 5; min-width: 10rem; padding: .25rem; border: 1px solid var(--line); border-radius: 10px; background: var(--panel); box-shadow: 0 8px 24px var(--card-shadow); }
	.options a { display: block; padding: .65rem .8rem; border-radius: 6px; font-weight: 650; text-decoration: none; }
	.options a:hover, .options a:focus-visible { background: var(--panel-2); }
</style>
