<script lang="ts" module>
	import type { ComponentProps } from 'svelte';
	import ActionIcon from './ActionIcon.svelte';
	/** One labelled segment on the card, for example { icon: 'clock', label: 'Time', value: '9:00 AM' }. */
	export type CardFact = { icon: ComponentProps<typeof ActionIcon>['name']; label: string; value: string };
</script>

<script lang="ts">
	// The one booking card used by customer My Bookings, staff Bookings and staff Booking history:
	// when and status, optional name, labelled icon segments, the service-type tag, then the actions.
	// Tapping the face opens the details. Staff cards keep a visible Details button; the customer card has "View details" in its Actions menu.
	import type { Snippet } from 'svelte';
	import ServiceTypeTag from './ServiceTypeTag.svelte';
	import StatusBadge from './StatusBadge.svelte';
	import type { RecordStatus } from './records-ui';

	let { when, status, name, facts = [], services, onDetails, detailsButton = true, actionsTop = false, actions }: {
		when: string; status: RecordStatus; name?: string; facts?: CardFact[];
		/** Service codes or labels, used for the Ceramic / Powder tag. */
		services?: readonly string[]; onDetails: () => void; detailsButton?: boolean;
		/** Put the Actions menu on the top row (beside the status) instead of the bottom bar. */
		actionsTop?: boolean; actions?: Snippet;
	} = $props();
	let opener = $state<HTMLButtonElement>();

	// Tapping the card works like the Details button, and focus goes back to that button when the sheet closes.
	function openFromCard() {
		opener?.focus();
		onDetails();
	}
</script>

<div class="booking-card">
	<!-- svelte-ignore a11y_click_events_have_key_events, a11y_no_static_element_interactions (The Details button, or the Actions menu, is the keyboard way in.) -->
	<div class="face" onclick={openFromCard}>
		<div class="top"><strong class="when">{when}</strong>
			<div class="top-end">
				<StatusBadge {status} />
				<!-- svelte-ignore a11y_click_events_have_key_events, a11y_no_static_element_interactions (The menu's own button is the control; this only stops the card from opening.) -->
				{#if actionsTop && actions}<div class="top-actions" onclick={(event) => event.stopPropagation()}>{@render actions()}</div>{/if}
			</div>
		</div>
		{#if name}<strong class="who">{name}</strong>{/if}
		{#if facts.length}
			<dl class="facts">{#each facts as fact (fact.label)}
				<div><dt><ActionIcon name={fact.icon} />{fact.label}</dt><dd>{fact.value}</dd></div>
			{/each}</dl>
		{/if}
		{#if services}<ServiceTypeTag {services} />{/if}
	</div>
	<div class="bar">
		{#if !actionsTop}<div class="actions">{@render actions?.()}</div>{/if}
		{#if detailsButton}<button type="button" class="details-button" bind:this={opener} aria-label={'Details for ' + (name ?? when)} onclick={onDetails}>Details</button>{/if}
	</div>
</div>

<style>
	.booking-card { display: grid; gap: .55rem; min-width: 0; }
	.face { display: grid; gap: .35rem; min-width: 0; cursor: pointer; }
	.top { display: flex; flex-wrap: wrap; align-items: center; justify-content: space-between; gap: .4rem; }
	.top-end { display: flex; flex-wrap: wrap; align-items: center; justify-content: flex-end; gap: .5rem; }
	.top-actions { display: flex; align-items: center; }
	.when { font-size: 1.1rem; }
	.who { font-size: 1rem; overflow-wrap: anywhere; }
	.facts { display: grid; grid-template-columns: repeat(auto-fit, minmax(7.5rem, 1fr)); gap: .4rem; margin: 0; }
	.facts div { display: grid; gap: .1rem; min-width: 0; padding: .4rem .55rem; border: 1px solid var(--line); border-radius: 10px; background: var(--panel-2); }
	.facts dt { display: flex; align-items: center; gap: .3rem; color: var(--muted); font-size: .68rem; font-weight: 800; letter-spacing: .05em; text-transform: uppercase; }
	.facts dd { margin: 0; font-size: .9rem; font-weight: 700; overflow-wrap: anywhere; }
	.bar { display: flex; flex-wrap: wrap; align-items: center; justify-content: space-between; gap: .5rem; }
	.actions { display: flex; flex-wrap: wrap; align-items: center; gap: .4rem; min-width: 0; }
	.actions :global(.btn) { min-height: 2.75rem; }
	.details-button { min-height: 2.75rem; margin-inline-start: auto; padding: 0 .5rem; border: 0; background: transparent; color: var(--accent); font: 700 .9rem var(--body); cursor: pointer; }
	.details-button:hover { text-decoration: underline; }
	.details-button:focus-visible { outline: 2px solid var(--accent); outline-offset: 2px; }
</style>
