<script lang="ts">
	import ActionIcon from '#lib/ActionIcon.svelte';
	import { page } from '$app/state';
	import { resolve } from '$app/paths';
	import { adminNavigation, adminPath } from '#lib/adminNavigation.ts';
	import { canPerform, staffAccess } from '#lib/staffAccess.svelte.ts';
	import BookingSummary from '#lib/BookingSummary.svelte';
	import StaffAccess from '#lib/StaffAccess.svelte';
	import AdminBooking from '#lib/AdminBooking.svelte';
	import AdminActivity from '#lib/AdminActivity.svelte';
	import AdminPricing from '#lib/AdminPricing.svelte';
	import OperationsAdmin from '#lib/OperationsAdmin.svelte';
	import AdminCalendar from '#lib/AdminCalendar.svelte';

	import { serviceOf, sizes } from '#lib/config.ts';
	import { addDays, fmtDate, fmtSlot, isOpenDay, today, upcoming } from '#lib/dates.ts';
	import { serviceLabel } from '#lib/coating.ts';
	import { bookingStatusLabels, bookingsOn, db, dayStatus, isSlotBlocked, setDateAvailability, slotsFor, toggleSlotBlock } from '#lib/store.svelte.ts';

	const navigation = $derived(adminNavigation(page.url.searchParams));
	const tab = $derived(navigation.tab === 'Booking' ? navigation.section : navigation.tab);
	const pendingRequests = $derived(db.bookings.reduce((total, booking) =>
		total + (booking.requests?.filter(request => request.state === 'Pending').length ?? 0), 0));
	const pendingBookings = $derived(db.bookings.filter(booking => booking.status === 'pending').length);
	let date = $state(upcoming().find(isOpenDay)!);
	let availabilityDialog = $state<HTMLDialogElement>();
	let availabilityError = $state('');
	let availabilityNotice = $state('');

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
	const daySlots = $derived(slotsFor(date).map(({ time, free }) => ({
		time, booking: queue.find(booking => booking.slot === time), blocked: isSlotBlocked(date, time),
		open: date >= today() && free && availability === 'open'
	})));
	const slotFilters = $derived([
		{ id: 'all', label: 'All slots', count: daySlots.length },
		{ id: 'pending', label: 'Pending', count: daySlots.filter(slot => slot.booking?.status === 'pending').length },
		{ id: 'confirmed', label: 'Booked', count: daySlots.filter(slot => slot.booking?.status === 'confirmed').length },
		{ id: 'done', label: 'Completed', count: daySlots.filter(slot => slot.booking?.status === 'done').length },
		{ id: 'open', label: 'Open', count: daySlots.filter(slot => slot.open).length }
	] as const);
	const selectedSlotFilter = $derived(slotFilters.find(filter => filter.id === slotFilter)!);
	const visibleSlots = $derived(daySlots.filter(slot => (source === 'all' || (slot.booking && matchesSource(slot.booking))) && (slotFilter === 'all' || (slotFilter === 'open' ? slot.open : slot.booking?.status === slotFilter))));

	function pickDate(day: string) {
		date = day;
	}

	function updateAvailability(update: () => void, notice: string) {
		availabilityError = availabilityNotice = '';
		try {
			update();
			availabilityNotice = notice;
		} catch (error) {
			availabilityError = (error as Error).message;
		}
	}

	function openAvailability() {
		availabilityError = availabilityNotice = '';
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
	{#if tab === 'Pricing'}
		<AdminPricing />
	{:else if tab === 'Change requests'}
		<h3>Requests awaiting review</h3>
		<p class="muted">Customers submit cancellation and reschedule requests from Bookings. Their current appointment stays reserved until you approve the request.</p>
		{#each db.bookings.filter(b => b.requests?.some(r => r.state === 'Pending')) as booking (booking.id)}
			<article class="card stack">
				<AdminBooking {booking}>
					{#snippet heading()}<p><strong>{booking.name}</strong> · {booking.id} · {fmtDate(booking.date)} at {fmtSlot(booking.slot)}</p>{/snippet}
					<details class="slot-details">
						<summary><span class="closed-label">Tap to view more</span><span class="open-label">Show less</span></summary>
						<div class="stack slot-detail-body"><BookingSummary {booking} staff /></div>
					</details>
				</AdminBooking>
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
				{#if !pastDate && canPerform('manageSchedule')}
					<button type="button" class="btn sm ghost" onclick={openAvailability}><ActionIcon name="calendar" />Manage availability</button>
				{/if}
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
		{#if !pastDate && canPerform('manageSchedule')}
			<dialog class="availability-dialog" bind:this={availabilityDialog} aria-labelledby="availability-title">
				<header class="availability-header">
					<span class="availability-icon"><ActionIcon name="calendar" /></span>
					<div><h3 id="availability-title">Manage availability</h3><p class="small muted">{fmtDate(date)} · Philippine time</p></div>
					<button type="button" class="availability-button" onclick={() => availabilityDialog?.close()}>Close</button>
				</header>
				<div class="stack availability-body">
					<p class="small muted">Changes apply to new bookings. Existing appointments stay scheduled.</p>
					<section class="stack availability-day" aria-label="Date availability">
						<div class="row between"><h4>Date availability</h4><span class="badge" data-status={closed ? 'cancelled' : availability === 'full' ? 'pending' : 'done'}>{availabilityLabel}</span></div>
						<div class="row between">
							<p class="small muted">{override}</p>
							<div class="row availability-actions">
							{#if closed}
								<button type="button" class="availability-button" onclick={() => updateAvailability(() => setDateAvailability(date, 'open'), 'Date opened for new bookings.')}><ActionIcon name="check" />Open this date</button>
							{:else}
								<button type="button" class="availability-button date-danger" onclick={() => updateAvailability(() => setDateAvailability(date, 'closed'), 'Date closed to new bookings.')}><ActionIcon name="block" />Close this date</button>
							{/if}
							{#if override !== 'Regular hours'}
								<button type="button" class="availability-button" onclick={() => updateAvailability(() => setDateAvailability(date, 'regular'), 'Regular hours restored.')}><ActionIcon name="reset" />Restore regular hours</button>
							{/if}
							</div>
						</div>
					</section>
					<section class="stack availability-times" aria-label="Time slot availability">
						<h4>Time slot restrictions</h4>
						<ul>
							{#each daySlots as { time, blocked } (time)}
								<li class="row between">
									<div><strong>{fmtSlot(time)}</strong><p class="small slot-restriction" class:restricted={blocked}>{blocked ? 'Blocked for new bookings' : 'No slot restriction'}</p></div>
									<button type="button" class="availability-button slot-button" aria-label={(blocked ? 'Unblock ' : 'Block ') + fmtSlot(time)} onclick={() => updateAvailability(() => toggleSlotBlock(date, time), (blocked ? 'Removed the restriction for ' : 'Blocked new bookings at ') + fmtSlot(time) + '.')}><ActionIcon name={blocked ? 'check' : 'block'} />{blocked ? 'Unblock' : 'Block slot'}</button>
								</li>
							{/each}
						</ul>
					</section>
					{#if availabilityError}<p class="error" role="alert">{availabilityError}</p>{/if}
					{#if availabilityNotice}<p class="small muted" role="status">{availabilityNotice}</p>{/if}
				</div>
			</dialog>
		{/if}

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
				<AdminBooking {booking}>
					{#snippet heading()}
						<p><strong>{booking.name}</strong></p>
						<p class="small muted">Walk-in · {fmtSlot(booking.slot)} <span class="badge" data-status={booking.status === 'confirmed' ? 'booked' : booking.status}>{bookingStatusLabels[booking.status]}</span></p>
					{/snippet}
					<details class="slot-details">
						<summary><span class="closed-label">Tap to view more</span><span class="open-label">Show less</span></summary>
						<div class="stack slot-detail-body"><BookingSummary {booking} staff /></div>
					</details>
				</AdminBooking>
			</article>
		{/each}
		<ol class="stack">
			{#each visibleSlots as { time, open, blocked, booking: b } (date + time)}
				<li class="card slot-card" data-slot-status={b?.status ?? (blocked ? 'blocked' : open ? 'open' : 'unavailable')}>
					{#snippet slotHeading()}
						<div class="slot-summary">
							<time class="display time" datetime={time}>{fmtSlot(time)}</time>
							<div class="slot-identity">
								{#if b}
									<b>{b.name}</b>
									<p class="small muted">{b.selection ? serviceLabel(b.selection) : serviceOf(b.serviceId).name} · {b.bike}</p>
									<span class="badge" data-status={b.status === 'confirmed' ? 'booked' : b.status}>{bookingStatusLabels[b.status]}</span>
								{:else}
									<b>{blocked ? 'Blocked' : closed ? 'Closed' : pastDate ? 'Past slot' : open ? 'Open slot' : 'Unavailable'}</b>
								{/if}
							</div>
						</div>
					{/snippet}
					{#if b}
						<AdminBooking booking={b} heading={slotHeading}>
						<details class="slot-details">
							<summary><span class="closed-label">Tap to view more</span><span class="open-label">Show less</span></summary>
							<div class="stack slot-detail-body">
								<BookingSummary booking={b} staff />
								<p class="muted small">
									{b.bike}{#if b.finish} · Finish: {b.finish}{/if}{#if b.size} ({sizes[b.size]}){/if}<br />
									{#if b.plateNumber}Plate number {b.plateNumber}<br />{/if}
									<a href="tel:{b.phone}">{b.phone}</a>{b.email ? `, ${b.email}` : ''}<br />
									{b.notes}
								</p>
							</div>
						</details>
						</AdminBooking>
					{:else}
						{@render slotHeading()}
					{/if}
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
	.booking-workspace :is(.booking-sections, .day-controls, .schedule-heading, .slot-detail-body) :global(.btn) {
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
	.availability-day { gap: .45rem; padding: .7rem; border: 1px solid var(--line); border-radius: 8px; background: var(--panel-2); }
	.availability-actions { gap: .4rem; }
	.availability-button { display: inline-flex; align-items: center; justify-content: center; gap: .4rem; min-height: 36px; padding: .3rem .55rem; border: 1px solid var(--line); border-radius: 6px; background: var(--panel); color: var(--text); font: 650 .8rem var(--body); cursor: pointer; }
	.availability-button:hover { border-color: var(--accent); }
	.date-danger { color: var(--bad); }
	.slot-button { min-width: 6.25rem; }
	.slot-restriction { color: var(--muted); }
	.slot-restriction.restricted { color: var(--bad); }
	.availability-dialog h4 { margin: 0; font-size: .95rem; }
	.availability-times { gap: .5rem; }
	.availability-times ul { margin: 0; padding: 0 .65rem; list-style: none; border: 1px solid var(--line); border-radius: 8px; }
	.availability-times li { padding: .45rem 0; }
	.availability-times li + li { border-top: 1px solid var(--line); }
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
	.slot-identity { overflow-wrap: anywhere; padding-inline-start: .7rem; border-inline-start: 1px solid var(--line); }
	.slot-identity .badge { display: inline-block; margin-block-start: .25rem; }
	.slot-details { border-top: 1px solid var(--line); margin-top: .55rem; }
	.slot-details summary { width: fit-content; padding: .35rem .35rem 0 0; color: var(--muted); font-size: .8rem; font-weight: 700; cursor: pointer; }
	.slot-details:not([open]) .open-label, .slot-details[open] .closed-label { display: none; }
	.slot-detail-body { padding-block: .6rem .25rem; overflow-wrap: anywhere; }
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
