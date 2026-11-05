<script lang="ts">
	import { page } from '$app/state';
	import OperationsAdmin from '#lib/OperationsAdmin.svelte';
	import AdminCalendar from '#lib/AdminCalendar.svelte';
	import SlotPicker from '#lib/SlotPicker.svelte';
	import { peso, priceOf, serviceOf, shop, sizes } from '#lib/config.ts';
	import { fmtDate, fmtSlot, isOpenDay, slots, today, upcoming } from '#lib/dates.ts';
	import { bookingsOn, db, features, reschedule, setStatus, toggleBlock } from '#lib/store.svelte.ts';

	const tabs = ['Overview', 'Bookings', 'Booking history', 'Customers', 'HERCO Points', 'Inventory', 'Reports & payments'];
	const requestedTab = $derived(page.url.searchParams.get('tab') === 'Customers & points' ? 'HERCO Points' : page.url.searchParams.get('tab') ?? 'Overview');
	const tab = $derived(tabs.includes(requestedTab) ? requestedTab : 'Overview');
	let date = $state(upcoming().find(isOpenDay)!);
	let moving = $state<{ id: string; date: string; slot: string }>();
	let error = $state('');

	const queue = $derived(bookingsOn(date));
	const blocked = $derived(db.blocked.includes(date));
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
		<h2>Garage dashboard</h2>
	</div>
	{#if tab !== 'Bookings'}
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

		<p class="muted small">Confirm a pending booking after reviewing its details and payment. Mark it as done once the service is finished.</p>

		<div class="row">
			<button class="btn sm" class:ghost={!blocked} onclick={() => toggleBlock(date)}>
				{blocked ? 'Unblock this date' : 'Block this date'}
			</button>
			<span class="muted small">
				{blocked ? 'Customers cannot book this date.' : 'Blocking stops new bookings and keeps the ones below.'}
			</span>
		</div>

		<ol class="stack">
			{#each slots as time (time)}
				{@const b = queue.find((x) => x.slot === time)}
				<li>
					<b class="display time">{fmtSlot(time)}</b>
					{#if !b}
						<p class="muted open">{blocked ? 'Blocked' : 'Open'}</p>
					{:else}
						<div class="card stack">
							<div class="row between">
								<h3>{b.name}</h3>
								<span class="badge" data-status={b.status}>{b.status}</span>
							</div>
							<p>{serviceOf(b.serviceId).name}, {peso(priceOf(b))}</p>
							<p class="muted small">
								{b.bike} ({sizes[b.size]})<br />
								{#if b.plateNumber}Plate number {b.plateNumber}<br />{/if}
								<a href="tel:{b.phone}">{b.phone}</a>{b.email ? `, ${b.email}` : ''}<br />
								{#if features().payment}Downpayment {peso(shop.downpayment)}, GCash ref {b.gcashRef || 'none'}<br />{/if}
								{b.notes}
							</p>
							{#if moving && moving.id === b.id}
								<SlotPicker bind:date={moving.date} bind:slot={moving.slot} />
								{#if error}<p class="error">{error}</p>{/if}
								<div class="row">
									<button class="btn sm" disabled={!moving.slot} onclick={move}>Save new slot</button>
									<button class="btn sm ghost" onclick={() => (moving = undefined)}>Close</button>
								</div>
							{:else if b.status !== 'done'}
								<div class="row">
									{#if b.status === 'pending'}
										<button class="btn sm confirm-action" onclick={() => setStatus(b.id, 'confirmed')}>
											Confirm booking
										</button>
									{:else if b.status === 'confirmed'}
										<button class="btn sm complete-action" onclick={() => setStatus(b.id, 'done')}>Mark as done</button>
									{/if}
									<button class="btn sm ghost" onclick={() => (moving = { id: b.id, date: '', slot: '' })}>Reschedule</button>
									<button class="btn sm danger" onclick={() => confirm('Cancel this booking?') && setStatus(b.id, 'cancelled')}>
										Cancel
									</button>
								</div>
							{/if}
						</div>
					{/if}
				</li>
			{/each}
		</ol>

		{#if db.blocked.length}
			<p class="eyebrow">Blocked dates</p>
			<div class="row">
				{#each db.blocked as d (d)}
					<button class="btn sm ghost" onclick={() => toggleBlock(d)}>{fmtDate(d, { month: 'short', day: 'numeric' })}, unblock</button>
				{/each}
			</div>
		{/if}
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
