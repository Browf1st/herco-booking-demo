<script lang="ts">
	import { resolve } from '$app/paths';
	let { bookingId }: { bookingId: string } = $props();
	type BookingEvent = { id: number; kind: string; to_status: string; created_at: string };
	let events = $state<BookingEvent[]>();
	let busy = $state(false);
	let failed = $state(false);
	const time = new Intl.DateTimeFormat('en-PH', { dateStyle: 'medium', timeStyle: 'short', timeZone: 'Asia/Manila' });
	const labels: Record<string, string> = {
		booking_submitted: 'Booking submitted', booking_created_by_staff: 'Booking created by the shop',
		booking_confirmed: 'Shop confirmed your booking', booking_services_updated: 'Services updated',
		booking_price_corrected: 'Shop updated a service price',
		booking_cancel_requested: 'Cancellation requested', booking_reschedule_requested: 'Reschedule requested',
		booking_cancel_approved: 'Cancellation approved', booking_cancel_declined: 'Cancellation declined',
		booking_reschedule_approved: 'Reschedule approved', booking_reschedule_declined: 'Reschedule declined',
		booking_cancel_withdrawn: 'Cancellation request withdrawn', booking_reschedule_withdrawn: 'Reschedule request withdrawn',
		booking_cancelled_by_staff: 'Shop cancelled your booking', booking_rescheduled_by_staff: 'Shop rescheduled your booking',
		walk_in_submitted: 'Walk-in submitted', walk_in_intake_requested: 'Walk-in form requested', walk_in_intake_signed: 'Walk-in form signed',
		completed: 'Booking completed'
	};

	async function load() {
		busy = true;
		failed = false;
		try {
			const response = await fetch(resolve('/api/bookings/activity') + '?booking=' + encodeURIComponent(bookingId));
			if (!response.ok) throw new Error();
			events = (await response.json()).events;
		} catch { failed = true; }
		finally { busy = false; }
	}
</script>

<details ontoggle={(event) => {
	if (event.currentTarget.open && !events && !busy && !failed) void load();
}}>
	<summary>Booking activity</summary>
	{#if busy}
		<p role="status">Loading activity…</p>
	{:else if failed}
		<p role="alert">Could not load booking activity.</p>
		<button class="btn sm ghost" onclick={load}>Try again</button>
	{:else if events}
		<ol>
			{#each events as item (item.id)}
				<li>
					<strong>{labels[item.kind] ?? 'Booking updated'}</strong> · {time.format(new Date(item.created_at))}
					{#if item.kind === 'walk_in_intake_requested'}
						<div><a href={resolve('/walk-in-intake') + '?booking=' + encodeURIComponent(bookingId)}>View walk-in form</a></div>
					{/if}
				</li>
			{:else}
				<li>No activity yet.</li>
			{/each}
		</ol>
	{/if}
</details>
