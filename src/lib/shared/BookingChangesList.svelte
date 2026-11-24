<!-- Styles load together with this screen (not in the page's first stylesheet). -->
<svelte:options css="injected" />
<script lang="ts">
	// The "Changes" list in a staff booking popup: newest first, already written out as plain lines (see booking-changes.ts).
	let { status, lines, message = '', onretry }: { status: 'loading' | 'ready' | 'error'; lines: string[]; message?: string; onretry: () => void } = $props();
	const titleId = $props.id();
</script>

<section aria-labelledby={titleId}>
	<h4 id={titleId}>Changes</h4>
	{#if status === 'loading'}
		<p class="muted small" role="status">Loading changes…</p>
	{:else if status === 'error'}
		<p class="error small" role="alert">{message || 'Could not load the changes.'}</p>
		<div><button type="button" class="btn sm ghost" onclick={onretry}>Try again</button></div>
	{:else if !lines.length}
		<p class="muted small">No changes yet</p>
	{:else}
		<ol>{#each lines as line, index (index)}<li>{line}</li>{/each}</ol>
	{/if}
</section>

<style>
	section { display: grid; gap: .5rem; padding: .85rem; border: 1px solid var(--line); border-radius: 12px; overflow-wrap: anywhere; }
	h4 { margin: 0; font-size: .75rem; letter-spacing: .05em; text-transform: uppercase; }
	p { margin: 0; }
	ol { display: grid; gap: .45rem; margin: 0; padding: 0; list-style: none; font-size: .9rem; }
	li { padding-bottom: .45rem; border-bottom: 1px solid var(--line); }
	li:last-child { padding-bottom: 0; border-bottom: 0; }
</style>
