<script lang="ts">
	// Small labelled tag: "Ceramic", "Powder" or "Ceramic + Powder", with an icon so it never relies on colour alone.
	import ActionIcon from './ActionIcon.svelte';
	import { serviceTypeLabel } from './records-ui';

	let { services }: { services: readonly (string | undefined | null)[] | null | undefined } = $props();
	const label = $derived(serviceTypeLabel(services));
</script>

{#if label}
	<span class="tag">
		{#if label !== 'Powder'}<ActionIcon name="drop" />{/if}{#if label !== 'Ceramic'}<ActionIcon name="wheel" />{/if}{label}
	</span>
{/if}

<style>
	.tag { display: inline-flex; align-items: center; gap: .3rem; width: fit-content; max-width: 100%; padding: .15rem .55rem; border: 1px solid var(--line); border-radius: 999px; background: var(--panel-2); color: var(--text); font-size: .75rem; font-weight: 700; white-space: nowrap; }
</style>
