<script lang="ts">
	import ActionIcon from '#lib/shared/ActionIcon.svelte';
	import PageHeader from '#lib/shared/PageHeader.svelte';
	import { page } from '$app/state';
	import { resolve } from '$app/paths';
	import { adminNavigation, adminPath } from '#lib/demo/adminNavigation.ts';
	import { canPerform, staffAccess } from '#lib/demo/staffAccess.svelte.ts';
	import DemoBookingSheet from '#lib/demo/DemoBookingSheet.svelte';
	import StaffAccess from '#lib/demo/StaffAccess.svelte';
	import AdminBooking from '#lib/demo/AdminBooking.svelte';
	import AdminActivity from '#lib/demo/AdminActivity.svelte';
	import AdminPricing from '#lib/demo/AdminPricing.svelte';
	import OperationsAdmin from '#lib/demo/OperationsAdmin.svelte';
	import AdminCalendar from '#lib/demo/AdminCalendar.svelte';

		import { addDays, fmtDate, fmtSlot, nowHour, today, upcoming } from '#lib/shared/dates.ts';
		import { bookingsOn, db, dayHours, dayStatus, isSlotBlocked, slotsFor, type Booking } from '#lib/demo/store.svelte.ts';

	// One page header style on every staff tab, like the Reports tab (owner item 12, 2026-11-23).
	const tabHeaders: Record<string, string> = {
		'Change requests': 'Cancel and reschedule requests waiting for review.',
		'Booking history': 'Track bookings by appointment date.',
		Customers: 'Find a customer and see their past visits.',
		'HERCO Points': 'Fan ranking, rewards and redemptions.',
		Inventory: 'Stock on hand, usage and low-stock alerts.',
		Pricing: 'Service prices and booking promotions.',
		'Activity log': 'Who changed what in the staff workspace, newest first.',
		'Staff Access': 'Choose who can use each staff page and action.'
	};
	const navigation = $derived(adminNavigation(page.url.searchParams));
	const tab = $derived(navigation.tab === 'Booking' ? navigation.section : navigation.tab);
	const pendingRequests = $derived(db.bookings.reduce((total, booking) =>
		total + (booking.requests?.filter(request => request.state === 'Pending').length ?? 0), 0));
	const pendingBookings = $derived(db.bookings.filter(booking => booking.status === 'pending').length);
	let date = $state(upcoming().find(day => !dayHours(day).closed) ?? today());
	let availabilityDialog = $state<HTMLDialogElement>();
	// The opening-hours screens load only when someone opens Manage availability.
	let manage = $state.raw<{ Panel: typeof import('#lib/shared/AvailabilityPanel.svelte').default; schedule: typeof import('#lib/demo/schedule.ts') }>();

	let detail = $state<Booking>();
	let source = $state('all');
	const matchesSource = (booking: { walkIn?: unknown }) => source === 'all' || Boolean(booking.walkIn) === (source === 'walk-in');
	let slotFilter = $state<'all' | 'pending' | 'confirmed' | 'done' | 'open'>('all');
	let slotFilterMenu = $state<HTMLDetailsElement>();
	let slotFilterTrigger = $state<HTMLElement>();

	const queue = $derived(bookingsOn(date));
	const availability = $derived(dayStatus(date));
	const pastDate = $derived(date < today());
	const closed = $derived(availability === 'closed' || availability === 'blocked');
	const override = $derived(db.blocked.includes(date) ? 'Closed by admin' : db.opened.includes(date) ? 'Opened by admin' : 'Regular hours');
	const availabilityLabel = $derived(pastDate ? 'Past date' : closed ? 'Closed to new bookings' : availability === 'full' ? 'Full' : 'Available');
	const count = (status: string) => db.bookings.filter(booking => booking.date === date && booking.status === status).length;
	// Any number of bookings can share an hour. Bookings outside the date's hours stay visible with a label.
	const daySlots = $derived(slotsFor(date).map(({ time, free }) => ({
		time, bookings: queue.filter(booking => booking.slot === time), blocked: isSlotBlocked(date, time),
		past: pastDate || (date === today() && Number.parseInt(time, 10) <= nowHour()),
		open: date >= today() && free && availability === 'open'
	})));
	const outsideHours = $derived(queue.filter(booking => !dayHours(date).hours.includes(Number.parseInt(booking.slot, 10)) && matchesSource(booking)));
	const hasStatus = (slot: { bookings: Booking[] }, status: string) => slot.bookings.some(booking => booking.status === status);
	const slotFilters = $derived([
		{ id: 'all', label: 'All slots', count: daySlots.length },
		{ id: 'pending', label: 'Pending', count: daySlots.filter(slot => hasStatus(slot, 'pending')).length },
		{ id: 'confirmed', label: 'Booked', count: daySlots.filter(slot => hasStatus(slot, 'confirmed')).length },
		{ id: 'done', label: 'Completed', count: daySlots.filter(slot => hasStatus(slot, 'done')).length },
		{ id: 'open', label: 'Open', count: daySlots.filter(slot => slot.open).length }
	] as const);
	const selectedSlotFilter = $derived(slotFilters.find(filter => filter.id === slotFilter)!);
	const visibleSlots = $derived(daySlots.filter(slot => (source === 'all' || slot.bookings.some(matchesSource)) && (slotFilter === 'all' || (slotFilter === 'open' ? slot.open : hasStatus(slot, slotFilter)))));

	function pickDate(day: string) {
		date = day;
	}

	async function openAvailability() {
		manage ??= { Panel: (await import('#lib/shared/AvailabilityPanel.svelte')).default, schedule: await import('#lib/demo/schedule.ts') };
		availabilityDialog?.showModal();
	}
</script>

<svelte:head><title>Shop admin | HERCO Detailing Garage</title></svelte:head>

<svelte:window onclick={(event) => {
	if (slotFilterMenu?.open && event.target instanceof Node && !slotFilterMenu.contains(event.target)) slotFilterMenu.open = false;
}} onkeydown={(event) => {
	if (event.key === 'Escape' && slotFilterMenu?.open) {
		slotFilterMenu.open = false;
		slotFilterTrigger?.focus();
	}
}} />

<section class="section wrap stack admin-content" class:booking-workspace={tab === 'Bookings'}>
	{#key staffAccess.sessionId}
	{#if staffAccess.current}
		<p class="small muted" role="status">Previewing {staffAccess.current.name}’s access. Select Owner view to return.</p>
	{/if}
	{#if !navigation.allowed}
		<div class="card stack" role="status">
			<h2>Page unavailable</h2>
			<p>{staffAccess.sessionId ? 'This view does not have access to this page.' : 'This staff preview is no longer active. Select Admin view or Owner view above.'}</p>
			{#if navigation.tabs.length}<div><a class="btn sm" href={resolve('/admin')}>Back to available pages</a></div>{/if}
		</div>
	{:else}
	{#if navigation.tab === 'Booking'}
		<nav class="row booking-sections" aria-label="Booking sections">
			{#each navigation.sections as section (section)}
				<a class="btn sm" class:ghost={navigation.section !== section} href={resolve(adminPath('Booking', section))} aria-current={navigation.section === section ? 'page' : undefined}><ActionIcon name={section === "Bookings" ? "calendar" : section === "Change requests" ? "edit" : "history"} />
					{section === 'Bookings' ? 'Booking' : section}
					{#if section === 'Change requests'}
						<span class="tab-count" aria-label={pendingRequests + ' awaiting review'}>{pendingRequests}</span>
					{:else if section === 'Bookings'}
						<span class="tab-count" aria-label={pendingBookings + ' pending bookings'}>{pendingBookings}</span>
					{/if}
				</a>
			{/each}
			{#if tab === 'Bookings' && date >= today() && canPerform('createBooking')}
				<details class="manual-menu">
					<summary class="btn sm"><ActionIcon name="add" />Manual booking <span aria-hidden="true">▾</span></summary>
					<div class="manual-options">
						<a data-sveltekit-reload href={resolve(`/book?manual=1&date=${date}`)}>Online</a>
						<a data-sveltekit-reload href={resolve(`/book?manual=1&walk-in=1&date=${date}`)}>Walk-in</a>
					</div>
				</details>
			{/if}
		</nav>
	{/if}
	{#if tabHeaders[tab] && tab !== 'Reports'}<PageHeader title={tab} subtitle={tabHeaders[tab]} timezone={tab === 'Booking history' || tab === 'Activity log'} />{/if}
	{#if tab === 'Pricing'}
		<AdminPricing />
	{:else if tab === 'Change requests'}
		<p class="muted">Customers submit cancellation and reschedule requests from Bookings. Their current appointment stays reserved until you approve the request.</p>
		{#each db.bookings.filter(b => b.requests?.some(r => r.state === 'Pending')) as booking (booking.id)}
			<article class="card stack">
				<AdminBooking {booking} when={fmtDate(booking.date) + ' · ' + fmtSlot(booking.slot)} onDetails={() => detail = booking} />
			</article>
		{:else}<p class="card">No requests awaiting review.</p>{/each}
	{:else if tab === 'Staff Access' && navigation.owner}
		<StaffAccess />
	{:else if tab === 'Activity log' && navigation.owner}
		<AdminActivity />
	{:else if tab !== 'Bookings'}
		<OperationsAdmin {tab} />
	{:else}
		<div class="row between day-heading">
			<div>
				<p class="eyebrow">Booking schedule</p><h2>{fmtDate(date)}</h2>
				<div class="row day-status"><span class="badge" data-status={pastDate ? undefined : closed ? 'cancelled' : availability === 'full' ? 'pending' : 'done'}>{availabilityLabel}</span><span class="small muted">{override}</span></div>
			</div>
			<div class="row day-controls">
				<button type="button" class="btn sm ghost" onclick={openAvailability}><ActionIcon name="calendar" />Manage availability</button>
				<div class="row" role="group" aria-label="Select booking day">
					<button type="button" class="btn sm ghost" aria-label="Previous day" onclick={() => pickDate(addDays(date, -1))}><ActionIcon name="left" /></button>
					<button type="button" class="btn sm ghost" aria-label="Next day" onclick={() => pickDate(addDays(date, 1))}><ActionIcon name="right" /></button>
				</div>
			</div>
		</div>
		<div class="tiles">
			<div class="card pending-tile"><b class="display">{count('pending')}</b><span class="small">Pending</span></div>
			<div class="card booked-tile"><b class="display">{count('confirmed')}</b><span class="small">Booked</span></div>
			<div class="card completed-tile"><b class="display">{count('done')}</b><span class="small">Completed</span></div>
		</div>
		<dialog class="availability-dialog" bind:this={availabilityDialog} aria-labelledby="availability-title">
			<header class="availability-header">
				<span class="availability-icon"><ActionIcon name="calendar" /></span>
				<div><h3 id="availability-title">Manage availability</h3><p class="small muted">{fmtDate(date)} · Philippine time</p></div>
				<button type="button" class="availability-button" onclick={() => availabilityDialog?.close()}>Close</button>
			</header>
			<div class="availability-body">
				{#if manage}
					{@const { Panel, schedule } = manage}
					<Panel {date} day={schedule.dayInfo(date)} loadSettings={schedule.loadSettings} saveSettings={schedule.saveSettings} act={(action, confirmOutside) => schedule.changeDate(date, action, confirmOutside)} />
				{/if}
			</div>
		</dialog>

		<div class="booking-layout">
		<div class="stack booking-column">
			{#key date.slice(0, 7)}
				<AdminCalendar value={date} onpick={pickDate} />
			{/key}
		</div>
		<section class="stack booking-column" aria-labelledby="time-slots-heading">
		<div class="card row between schedule-heading">
			<div><h3 id="time-slots-heading">Time slots</h3><p class="small muted">Philippine time</p></div>
			<details class="slot-filter" bind:this={slotFilterMenu}>
				<summary bind:this={slotFilterTrigger} aria-label={'Filter slots, ' + selectedSlotFilter.label + ', ' + selectedSlotFilter.count}>
					<ActionIcon name="adjust" />
					<span>{selectedSlotFilter.label}</span><span class="slot-filter-count">{selectedSlotFilter.count}</span>
					<span class="slot-filter-chevron" aria-hidden="true"></span>
				</summary>
				<div class="slot-filter-options" role="group" aria-label="Filter time slots">
					{#each slotFilters as filter (filter.id)}
						<button type="button" aria-pressed={slotFilter === filter.id} onclick={() => {
							slotFilter = filter.id;
							if (slotFilterMenu) slotFilterMenu.open = false;
							slotFilterTrigger?.focus();
						}}>
							<span class="slot-filter-check">{#if slotFilter === filter.id}<ActionIcon name="check" />{/if}</span>
							<span>{filter.label}</span><span class="slot-filter-count">{filter.count}</span>
						</button>
					{/each}
				</div>
			</details>
		</div>
		<label>Booking source<select bind:value={source}><option value="all">All sources</option><option value="online">Online</option><option value="walk-in">Walk-in</option></select></label>
		{#each db.bookings.filter(b => b.date === date && b.walkIn?.immediate && b.status !== 'cancelled' && matchesSource(b)) as booking (booking.id)}
			<article class="card stack">
				<AdminBooking {booking} when={'Walk-in · ' + fmtSlot(booking.slot)} onDetails={() => detail = booking} />
			</article>
		{/each}
		{#each outsideHours as booking (booking.id)}
			<article class="card stack" data-slot-status={booking.status}>
				<span class="badge">Outside hours</span>
				<AdminBooking {booking} when={fmtSlot(booking.slot)} onDetails={() => detail = booking} />
			</article>
		{/each}
		<ol class="stack">
			{#each visibleSlots as { time, open, blocked, past, bookings } (date + time)}
				<li class="card slot-card stack" data-slot-status={bookings[0]?.status ?? (blocked ? 'blocked' : open ? 'open' : 'unavailable')}>
					{#each bookings as b (b.id)}
						<AdminBooking booking={b} when={fmtSlot(time) + (bookings.length > 1 ? ' · ' + bookings.length + ' booked' : '')} onDetails={() => detail = b} />
					{:else}
						<div class="slot-summary"><time class="display time" datetime={time}>{fmtSlot(time)}</time><b>{past ? 'Past slot' : blocked ? 'Blocked' : closed ? 'Closed' : open ? 'Open slot' : 'Unavailable'}</b></div>
					{/each}
				</li>
			{:else}
				<li class="card muted">No time slots match this filter.</li>
			{/each}
		</ol>
		</section>
		</div>
	{/if}
	{/if}
	{/key}
		<DemoBookingSheet bind:booking={detail} />
</section>

<style>
	.manual-menu { position: relative; margin-inline-start: auto; }
	.manual-menu summary { list-style: none; cursor: pointer; }
	.manual-menu summary::-webkit-details-marker { display: none; }
	.manual-options { position: absolute; inset: calc(100% + .3rem) 0 auto auto; min-width: 9rem; padding: .25rem; background: var(--panel); border: 1px solid var(--line); border-radius: 6px; box-shadow: 0 4px 12px var(--card-shadow); z-index: 5; }
	.manual-options a { display: block; padding: .55rem .7rem; border-radius: 4px; text-decoration: none; }
	.manual-options a:hover { background: var(--panel-2); }
	.admin-content { grid-template-columns: minmax(0, 1fr); }
	.booking-workspace { max-width: 1420px; }
	.booking-workspace :is(.booking-sections, .day-controls, .schedule-heading) :global(.btn) {
		clip-path: none;
		border-radius: 6px;
		font-style: normal;
	}
	.day-heading h2 { font-size: clamp(2rem, 4vw, 3.5rem); margin-top: .35rem; }
	.day-status { margin-block-start: .35rem; }
	.day-controls { gap: .6rem; }
	.day-controls > .row { gap: .3rem; }
	.day-controls button { min-width: 40px; padding-inline: .65rem; }
	.tiles {
		display: grid;
		grid-template-columns: repeat(3, minmax(0, 1fr));
		gap: .65rem;
	}

	.tiles .card {
		display: grid;
		gap: .22rem;
		padding: .7rem .85rem;
	}

	.tiles b {
		font-size: 2rem;
	}
	.pending-tile { color: var(--warn); border-color: var(--warn-line); background: color-mix(in srgb, var(--warn-bg) 45%, var(--panel)); }
	.booked-tile { color: var(--accent); border-color: var(--bad-line); background: color-mix(in srgb, var(--bad-bg) 45%, var(--panel)); }
	.completed-tile { color: var(--ok); border-color: var(--ok-line); background: color-mix(in srgb, var(--ok-bg) 45%, var(--panel)); }
	.availability-dialog { --dialog-gutter: clamp(.75rem, 3vw, 1.2rem); width: min(540px, calc(100% - 24px)); max-height: 90dvh; margin: auto; padding: 0; border: 1px solid var(--line); border-radius: 12px; background: var(--panel); color: var(--text); }
	.availability-dialog::backdrop { background: #0009; }
	.availability-header { position: sticky; top: 0; z-index: 1; display: grid; grid-template-columns: auto minmax(0, 1fr) auto; align-items: center; gap: .65rem; padding: var(--dialog-gutter); background: var(--panel); border-bottom: 1px solid var(--line); }
	.availability-icon { display: grid; place-items: center; width: 2.15rem; aspect-ratio: 1; border-radius: 8px; background: var(--panel-2); color: var(--accent); }
	.availability-body { padding: var(--dialog-gutter); }
	.availability-button { display: inline-flex; align-items: center; justify-content: center; gap: .4rem; min-height: 36px; padding: .3rem .55rem; border: 1px solid var(--line); border-radius: 6px; background: var(--panel); color: var(--text); font: 650 .8rem var(--body); cursor: pointer; }
	.availability-button:hover { border-color: var(--accent); }
	.availability-dialog h3, .schedule-heading h3 { font-size: 1.35rem; }
	.booking-layout { display: grid; align-items: start; gap: .9rem; }
	.booking-column { min-width: 0; }
	.slot-filter { position: relative; min-width: 10rem; font-size: .85rem; }
	.slot-filter summary { display: flex; align-items: center; gap: .5rem; min-height: 40px; padding: .32rem .6rem; list-style: none; border: 1px solid var(--line); border-radius: 6px; background: var(--panel); font-weight: 700; cursor: pointer; }
	.slot-filter summary::-webkit-details-marker { display: none; }
	.slot-filter[open] summary, .slot-filter summary:hover { border-color: var(--accent); }
	.slot-filter-chevron { width: .44rem; height: .44rem; margin-inline: .1rem; border: solid currentColor; border-width: 0 1.5px 1.5px 0; transform: translateY(-2px) rotate(45deg); }
	.slot-filter summary .slot-filter-count { margin-inline-start: auto; }
	.slot-filter[open] .slot-filter-chevron { transform: translateY(2px) rotate(225deg); }
	.slot-filter-options { display: grid; position: absolute; inset: calc(100% + .3rem) auto auto 0; z-index: 2; min-width: max(100%, 9rem); gap: .15rem; padding: .25rem; border: 1px solid var(--line); border-radius: 7px; background: var(--panel); box-shadow: 0 4px 14px var(--card-shadow); }
	.slot-filter-options button { display: grid; grid-template-columns: 1em minmax(0, 1fr) auto; align-items: center; gap: .4rem; border: 0; border-radius: 4px; background: transparent; padding: .35rem .45rem; color: var(--text); font: inherit; text-align: start; cursor: pointer; }
	.slot-filter-options button:hover, .slot-filter-options button[aria-pressed='true'] { background: var(--panel-2); }
	.slot-filter-check { color: var(--accent); }
	.slot-filter-count { min-width: 1.3rem; padding-inline: .2rem; border-radius: .25rem; background: var(--bg); color: var(--muted); text-align: center; font-variant-numeric: tabular-nums; }
	.schedule-heading { padding: .75rem .85rem; }

	ol {
		margin: 0;
		padding: 0;
		list-style: none;
		gap: .55rem;
	}

	.slot-card { padding: .6rem .8rem; border-inline-start: 4px solid var(--line); }
	.slot-card[data-slot-status='pending'] { border-inline-start-color: var(--warn); }
	.slot-card[data-slot-status='confirmed'] { border-inline-start-color: var(--accent); }
	.slot-card[data-slot-status='done'] { border-inline-start-color: var(--ok); }
	.slot-card[data-slot-status='blocked'] { background: var(--panel-2); }
	.slot-card[data-slot-status='open'] { border-style: dashed; border-inline-start: 4px solid var(--ok-line); }
	.slot-summary { display: grid; grid-template-columns: minmax(4rem, max-content) minmax(0, 1fr); gap: .7rem; align-items: start; flex: 1 1 14rem; min-width: 0; }
	.time {
		color: var(--accent);
		font-size: 1.2rem;
		line-height: 1.2;
		white-space: nowrap;
	}

	.between {
		justify-content: space-between;
	}

	@media (min-width: 1000px) {
		.booking-layout { grid-template-columns: minmax(345px, 2fr) minmax(0, 4fr); }
	}
</style>
