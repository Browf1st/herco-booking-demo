<script module lang="ts">
	import { canPerform } from './staffAccess.svelte.ts';
	// The grants (of the demo staff member now signed in) that matter for editing lines.
	export const editGrants = () => (['adjustPrices', 'editServices'] as const).filter((action) => canPerform(action));
</script>

<script lang="ts">
	// The service lines in the demo "More details" popup. "Edit price" saves through the same store function as the old price form.
	// Adding and removing services uses the existing "Edit services" window, which already has the demo service picker.
	import { editRights } from '../shared/booking-changes';
	import { linePrice } from '../shared/coating';
	import ServiceLinesEditor, { type EditableLine, type SaveResult } from '../shared/ServiceLinesEditor.svelte';
	import { coatingOf, editCoating, type Booking } from './store.svelte';

	let { booking, showMoney }: { booking: Booking; showMoney: boolean } = $props();
	const rights = $derived(editRights(booking.status, editGrants()));
	const lines = $derived<EditableLine[]>((booking.estimate?.lines ?? []).map((line) => ({
		code: line.label, label: line.label, price: showMoney ? linePrice(line) : undefined, canEditPrice: rights.price && showMoney
	})));

	async function savePrice(code: string, pesos: number, reason: string): Promise<SaveResult> {
		const line = booking.estimate?.lines?.find((item) => item.label === code);
		if (!line) return { ok: false, message: 'That service is no longer on this booking.' };
		if (!line.pending && line.maximum === undefined && line.subtotal === pesos) return { ok: false, message: 'The new price is the same as the current price.' };
		try {
			editCoating(booking, coatingOf(booking), 'Demo admin', { [code]: pesos }, reason);
			return { ok: true };
		} catch (problem) {
			const message = problem instanceof Error ? problem.message : 'Could not save the price.';
			return { ok: false, message: message.includes('already closed') ? 'This booking can no longer be changed.' : message };
		}
	}
</script>

<ServiceLinesEditor {lines} onsaveprice={savePrice} />
{#if rights.services}
	{#await import('./EditCoating.svelte') then { default: EditCoating }}<div><EditCoating {booking} staff /></div>{/await}
{/if}
