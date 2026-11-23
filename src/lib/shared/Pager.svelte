<script lang="ts">
	// Previous / Page n of m / Next, the same style as the staff Booking history pager.
	import ActionIcon from './ActionIcon.svelte';

	let { page, pages, label, onchange }: { page: number; pages: number; label: string; onchange: (page: number) => void } = $props();
</script>

{#if pages > 1}
	<nav class="row pager" aria-label={label + ' pagination'}>
		<button type="button" class="btn sm ghost" disabled={page <= 1} onclick={() => onchange(page - 1)}><ActionIcon name="left" />Previous</button>
		<span class="small muted" aria-live="polite">Page {page} of {pages}</span>
		<button type="button" class="btn sm ghost" disabled={page >= pages} onclick={() => onchange(page + 1)}><ActionIcon name="right" />Next</button>
	</nav>
{/if}

<style>
	.pager { justify-content: center; align-items: center; gap: .65rem; }
</style>
