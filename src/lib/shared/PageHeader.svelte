<script lang="ts">
	// One title style for every staff tab (owner item 12, 2026-11-23), matching the Reports tab:
	// a modest title, a one-line description, an optional "Philippine time" note and the page's main button.
	import type { Snippet } from 'svelte';
	import ActionIcon from './ActionIcon.svelte';

	let { title, subtitle = '', badge = '', timezone = false, children }: {
		title: string; subtitle?: string; badge?: string; timezone?: boolean; children?: Snippet;
	} = $props();
</script>

<div class="page-head">
	<div class="page-head-text">
		<h1>{title}{#if badge}<span class="page-head-badge">{badge}</span>{/if}</h1>
		{#if subtitle}<p class="muted">{subtitle}</p>{/if}
	</div>
	{#if timezone || children}
		<div class="page-head-side">
			{#if timezone}<span class="page-head-zone"><ActionIcon name="clock" />Philippine time</span>{/if}
			{#if children}{@render children()}{/if}
		</div>
	{/if}
</div>

<style>
	.page-head { display: flex; flex-wrap: wrap; align-items: center; justify-content: space-between; gap: .65rem 1rem; padding-block: .4rem; }
	.page-head-text { min-width: min(100%, 16rem); }
	h1 { font-size: clamp(2rem, 4vw, 2.6rem); line-height: 1.05; overflow-wrap: anywhere; }
	.page-head-badge { margin-inline-start: .75rem; padding: .2rem .6rem; border-radius: 6px; background: var(--panel-2); color: var(--muted); font: 700 .75rem var(--body); font-style: normal; letter-spacing: 0; text-transform: none; vertical-align: middle; white-space: nowrap; display: inline-block; margin-block-start: .3rem; }
	p { margin: .45rem 0 0; font-size: .85rem; }
	.page-head-side { display: flex; flex-wrap: wrap; align-items: center; gap: .65rem; }
	.page-head-zone { display: inline-flex; align-items: center; gap: .35rem; color: var(--muted); font-size: .85rem; }
</style>
