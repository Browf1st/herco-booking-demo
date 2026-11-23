<script lang="ts">
	// One details popup for a whole list: a bottom sheet on phones, a side panel on desktop.
	// The browser returns focus to the button that opened it when the dialog closes.
	import type { Snippet } from 'svelte';

	let { title, open, onclose, children }: { title: string; open: boolean; onclose: () => void; children: Snippet } = $props();
	let dialog = $state<HTMLDialogElement>();

	$effect(() => {
		if (open) dialog?.showModal(); else dialog?.close();
	});
</script>

<dialog bind:this={dialog} aria-label={title} {onclose} onclick={(event) => { if (event.target === dialog) dialog.close(); }}>
	{#if open}
		<header><h3>{title}</h3><button type="button" class="btn sm ghost" onclick={() => dialog?.close()}>Close</button></header>
		<div class="body">{@render children()}</div>
	{/if}
</dialog>

<style>
	dialog { box-sizing: border-box; display: none; width: 100%; max-width: none; height: auto; max-height: 90dvh; margin: auto 0 0; padding: 0; border: 1px solid var(--line); border-radius: 16px 16px 0 0; background: var(--panel); color: var(--text); overflow: hidden; }
	dialog[open] { display: flex; flex-direction: column; }
	dialog::backdrop { background: #0009; }
	header { display: flex; align-items: center; justify-content: space-between; gap: .75rem; padding: .75rem 1rem; border-bottom: 1px solid var(--line); }
	h3 { font-size: 1.25rem; overflow-wrap: anywhere; }
	.body { padding: 1rem; overflow-y: auto; overflow-wrap: anywhere; }
	@media (min-width: 700px) {
		dialog { width: 36rem; max-width: 100%; height: 100dvh; max-height: 100dvh; margin: 0 0 0 auto; border-radius: 0; }
	}
</style>
