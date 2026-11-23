<script lang="ts">
	// The calm booking card used by every staff booking list: time and status, name, "Bike · N services",
	// one main button, the rest under "More actions", and a visible Details button.
	import type { Snippet } from 'svelte';
	import StatusBadge from './StatusBadge.svelte';
	import type { RecordStatus } from './records-ui';

	let { when, status, name, meta, onDetails, actions }: {
		when: string; status: RecordStatus; name: string; meta: string; onDetails: () => void; actions?: Snippet;
	} = $props();
	let opener = $state<HTMLButtonElement>();

	// Tapping the card works like the Details button, and focus goes back to that button when the sheet closes.
	function openFromCard() {
		opener?.focus();
		onDetails();
	}
</script>

<div class="booking-card">
	<!-- svelte-ignore a11y_click_events_have_key_events, a11y_no_static_element_interactions (The Details button below is the keyboard way in.) -->
	<div class="face" onclick={openFromCard}>
		<div class="top"><strong class="when">{when}</strong><StatusBadge {status} /></div>
		<strong class="who">{name}</strong>
		<p class="small muted meta">{meta}</p>
	</div>
	<div class="bar">
		<div class="actions">{@render actions?.()}</div>
		<button type="button" class="details-button" bind:this={opener} aria-label={'Details for ' + name} onclick={onDetails}>Details</button>
	</div>
</div>

<style>
	.booking-card { display: grid; gap: .55rem; min-width: 0; }
	.face { display: grid; gap: .25rem; min-width: 0; cursor: pointer; }
	.top { display: flex; flex-wrap: wrap; align-items: center; justify-content: space-between; gap: .4rem; }
	.when { font-size: 1.1rem; }
	.who { font-size: 1rem; overflow-wrap: anywhere; }
	.meta { margin: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
	.bar { display: flex; flex-wrap: wrap; align-items: center; justify-content: space-between; gap: .5rem; }
	.actions { display: flex; flex-wrap: wrap; align-items: center; gap: .4rem; min-width: 0; }
	.actions :global(.btn) { min-height: 2.75rem; }
	.details-button { min-height: 2.75rem; margin-inline-start: auto; padding: 0 .5rem; border: 0; background: transparent; color: var(--accent); font: 700 .9rem var(--body); cursor: pointer; }
	.details-button:hover { text-decoration: underline; }
	.details-button:focus-visible { outline: 2px solid var(--accent); outline-offset: 2px; }
</style>
