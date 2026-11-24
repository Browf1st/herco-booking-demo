<script lang="ts">
	// The "Changes" list in the demo booking popups.
	import BookingChangesList from '../shared/BookingChangesList.svelte';
	import { historyLine } from '../shared/booking-changes';
	import { demoHistory } from './booking-history';
	import type { Booking } from './store.svelte';

	let { booking, showMoney }: { booking: Booking; showMoney: boolean } = $props();
	const lines = $derived(demoHistory(booking, showMoney).map(historyLine));
</script>

<BookingChangesList status="ready" {lines} onretry={() => {}} />
