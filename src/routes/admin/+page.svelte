<script lang="ts">
	import { page } from '$app/state';
	import AdminBooking from '#lib/AdminBooking.svelte';
	import AdminPricing from '#lib/AdminPricing.svelte';
	import { resolve } from '$app/paths';
	import OperationsAdmin from '#lib/OperationsAdmin.svelte';
	import AdminCalendar from '#lib/AdminCalendar.svelte';
	import SlotPicker from '#lib/SlotPicker.svelte';
	import { shop, sizes } from '#lib/config.ts';
	import { fmtDate, fmtSlot, isOpenDay, slots, today, upcoming } from '#lib/dates.ts';
	import { bookingsOn, db, dayStatus, isSlotBlocked, reschedule, setDateAvailability, slotsFor, toggleSlotBlock } from '#lib/store.svelte.ts';

	const tabs = ['Overview', 'Bookings', 'Booking history', 'Customers', 'HERCO Points', 'Inventory', 'Reports', 'Pricing', 'Change requests', 'Activity log'];
	const requestedTab = $derived(page.url.searchParams.get('tab') === 'Customers & points' ? 'HERCO Points' : page.url.searchParams.get('tab') ?? 'Overview');
	const tab = $derived(tabs.includes(requestedTab) ? requestedTab : 'Overview');
	let date = $state(upcoming().find(isOpenDay)!);
	let moving = $state<{ id: string; date: string; slot: string }>();
	let error = $state('');

	const queue = $derived(bookingsOn(date));
	const availability = $derived(dayStatus(date));
	const closed = $derived(availability === 'closed' || availability === 'blocked');
	const override = $derived(db.blocked.includes(date) ? 'Closed by admin' : db.opened.includes(date) ? 'Opened by admin' : 'Regular hours');
	const count = (status: string) => queue.filter((b) => b.status === status).length;

	function move() {
		try {
			reschedule(moving!.id, moving!.date, moving!.slot);
			date = moving!.date;
			moving = undefined;
		} catch (e) {
			error = (e as Error).message;
		}
	}
</script>

<svelte:head><title>Shop admin | HERCO Detailing Garage</title></svelte:head>

<section class="section wrap stack">
	<p class="eyebrow">HERCO / Shop admin</p>
	<div class="row between">
		<h2>Garage dashboard</h2><a class="btn sm" href={resolve('/book?walk-in=1')}>Walk-in intake</a>
	</div>
	{#if tab === 'Pricing'}
		<AdminPricing />
	{:else if tab === 'Change requests'}
		<h3>Requests awaiting review</h3>
		{#each db.bookings.filter(b => b.requests?.some(r => r.state === 'Pending')) as booking (booking.id)}
			<article class="card stack"><p><strong>{booking.name}</strong> · {booking.id} · {fmtDate(booking.date)} at {fmtSlot(booking.slot)}</p><AdminBooking {booking} /></article>
		{:else}<p class="card">No requests awaiting review.</p>{/each}
	{:else if tab === 'Activity log'}
		<h3>Admin activity</h3>
		<p class="muted">All timestamps use Philippine time.</p>
		{#each db.events.filter(event => event.actor === 'Demo admin').toReversed() as event (event.id)}
			<p class="card"><strong>{event.action}</strong>{event.bookingId ? ' · ' + event.bookingId : ''}<br /><span class="muted small">{new Date(event.at).toLocaleString('en-PH', {timeZone:'Asia/Manila', dateStyle:'medium', timeStyle:'medium', hour12:true})} · {event.actor}</span></p>
		{:else}<p class="card">No admin activity yet.</p>{/each}
	{:else if tab !== 'Bookings'}
		<OperationsAdmin {tab} />
	{:else}
		<p class="eyebrow">Shop admin / {date === today() ? 'Today' : 'Upcoming'}</p>
		<h2>{fmtDate(date)}</h2>
		<AdminCalendar value={date} onpick={(d) => { date = d; moving = undefined; error = ''; }} />

		<div class="tiles">
			<div class="card"><b class="display">{queue.length}/{shop.dailyLimit}</b><span class="muted small">Booked</span></div>
			<div class="card"><b class="display">{count('pending')}</b><span class="muted small">Awaiting confirmation</span></div>
			<div class="card"><b class="display">{count('confirmed')}</b><span class="muted small">Confirmed</span></div>
		</div>

		<p class="muted small">Confirm a pending booking after reviewing its details. Mark it as done once the service is finished.</p>

		<section class="card stack" aria-label="Date availability">
			<h3>Date availability</h3>
			<p><strong>{fmtDate(date)}</strong> · {override} · {availability === 'open' ? 'Available' : availability === 'full' ? 'Full' : 'Closed to new bookings'}</p>
			{#if date >= today()}
				<div class="row">

					{#if closed}
						<button class="btn sm confirm-action" onclick={() => setDateAvailability(date, 'open')}>Open this date</button>
					{:else}
						<button class="btn sm danger" onclick={() => setDateAvailability(date, 'closed')}>Close this date</button>
					{/if}
					{#if db.opened.includes(date) || db.blocked.includes(date)}
						<button class="btn sm ghost" onclick={() => setDateAvailability(date, 'regular')}>Restore regular hours</button>
					{/if}
				</div>
				<p class="small muted">Closing the date stops new bookings. Existing appointments stay scheduled.</p>
			{/if}
		</section>

		{#each db.bookings.filter(b => b.date === date && b.walkIn?.immediate && b.status !== 'cancelled') as booking (booking.id)}
			<article class="card stack">
				<p><strong>Walk-in · {booking.name}</strong> · {fmtSlot(booking.slot)} · <span class="badge" data-status={booking.status}>{booking.status}</span></p>
				<AdminBooking {booking} />
			</article>
		{/each}
		<h3>Time slots · Philippine time</h3>
		<p class="small muted">Blocked times are hidden from booking. Existing appointments stay scheduled.</p>
		<ol class="stack">
			{#each slotsFor(date) as { time, free } (time)}
				{@const b = queue.find((x) => x.slot === time)}
				<li>
					<div class="stack">
						<b class="display time">{fmtSlot(time)}</b>
						{#if date >= today()}
							<button class="btn sm ghost" aria-label={(isSlotBlocked(date, time) ? 'Unblock ' : 'Block ') + fmtSlot(time)} onclick={() => toggleSlotBlock(date, time)}>{isSlotBlocked(date, time) ? 'Unblock time' : 'Block time'}</button>
						{/if}
					</div>
					{#if !b}
						<p class="muted open">{isSlotBlocked(date, time) ? 'Blocked' : closed ? 'Closed' : free && availability === 'open' ? 'Open' : 'Unavailable'}</p>
					{:else}
						<div class="card stack">
							<div class="row between">
								<h3>{b.name}</h3>
								{#if isSlotBlocked(date, time)}<span class="badge" data-status="cancelled">Time blocked</span>{/if}
								<span class="badge" data-status={b.status}>{b.status}</span>
							</div>
							<p class="muted small">
								{b.bike}{#if b.finish} · Finish: {b.finish}{/if}{#if b.size} ({sizes[b.size]}){/if}<br />
								{#if b.plateNumber}Plate number {b.plateNumber}<br />{/if}
								<a href="tel:{b.phone}">{b.phone}</a>{b.email ? `, ${b.email}` : ''}<br />
								{b.notes}
							</p>
							<AdminBooking booking={b} />
							{#if moving && moving.id === b.id}
								<SlotPicker bind:date={moving.date} bind:slot={moving.slot} />
								{#if error}<p class="error">{error}</p>{/if}
								<div class="row">
									<button class="btn sm" disabled={!moving.slot} onclick={move}>Save new slot</button>
									<button class="btn sm ghost" onclick={() => (moving = undefined)}>Close</button>
								</div>
							{:else if (b.status === 'pending' || b.status === 'confirmed') && !b.requests?.some(r => r.state === 'Pending')}
								<div><button class="btn sm ghost" onclick={() => (moving = { id: b.id, date: '', slot: '' })}>Reschedule as admin</button></div>
							{/if}
						</div>
					{/if}
				</li>
			{/each}
		</ol>

	{/if}
</section>

<style>
	.tiles {
		display: grid;
		grid-template-columns: repeat(3, 1fr);
		gap: 8px;
	}

	.tiles .card {
		display: grid;
		padding: 12px;
	}

	.tiles b {
		font-size: 2rem;
	}

	ol {
		margin: 0;
		padding: 0;
		list-style: none;
	}

	li {
		display: grid;
		grid-template-columns: 78px 1fr;
		gap: 10px;
		align-items: start;
	}

	.time {
		padding-top: 14px;
		color: var(--accent);
		font-size: 1.25rem;
	}

	.open {
		padding: 12px 16px;
		border: 1px dashed var(--line);
		border-radius: 6px;
	}

	.between {
		justify-content: space-between;
	}
</style>
