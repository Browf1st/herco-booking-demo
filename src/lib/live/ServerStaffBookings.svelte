<script lang="ts">
	import { onMount } from 'svelte';
import ActionIcon from '../shared/ActionIcon.svelte';
import ServerAdminCalendar from './ServerAdminCalendar.svelte';
import ServerStaffBookingCard from './ServerStaffBookingCard.svelte';
import ServerBookingDetails from './ServerBookingDetails.svelte';
import DetailsSheet from '../shared/DetailsSheet.svelte';
import type { StaffBooking } from './server-booking-types';
	import { resolve } from '$app/paths';
	import { addDays, fmtDate, fmtSlot, today } from '#lib/shared/dates.ts';
	import ServerCustomerChangeForm from '#lib/live/ServerCustomerChangeForm.svelte';
	import CoatingOptionSummary from './CoatingOptionSummary.svelte';
	import type { CoatingOptions } from './booking-coating';
	let { canComplete = false, canRequestIntake = false, canAdjustPrices = false }: {
		canComplete?: boolean; canRequestIntake?: boolean; canAdjustPrices?: boolean;
	} = $props();

	type Booking = StaffBooking;
	type Slot = { hour: number; status: 'past' | 'open' | 'closed' | 'blocked' | 'booked'; blocked: boolean };
	type Day = {
		bookings: Booking[];
		slots: Slot[];
		override: boolean | null;
		can_confirm: boolean;
		can_cancel: boolean;
		can_reschedule: boolean;
		can_edit_services: boolean;
		can_manage_schedule: boolean;
		past_date: boolean;
	};
	type DateAction = 'open_date' | 'close_date' | 'restore_date';
	type ScheduleAction = DateAction | 'block_slot' | 'unblock_slot';
	type Action = { action: 'confirm'; bookingId: string; note: string } |
		{ action: ScheduleAction; date: string; hour?: number };
	const slotLabels = { past: 'Past slot', open: 'Open', closed: 'Closed', blocked: 'Blocked', booked: 'Booked' };
	const hourLabel = (hour: number) => fmtSlot(hour + ':00');

	let source = $state('all');
 let filter = $state('all');
 let availabilityDialog = $state<HTMLDialogElement>();
 let filterMenu = $state<HTMLDetailsElement>();
 let date = $state(today());
 const dayCount = (status: string) => day?.bookings.filter(booking=>booking.status===status).length ?? 0;
 let day = $state<Day>();
	const closed = $derived(day?.override === false || day?.slots.every(slot=>slot.status==='closed'));
 const slots = $derived(day?.slots.filter(slot=>{
  const booking=day?.bookings.find(item=>item.visit_hour===slot.hour);
  return (source==='all'|| (booking && (source==='walk-in')===(booking.source==='walk-in'))) &&
   (filter==='all'||filter==='open'&&slot.status==='open'||booking?.status===filter);
 })??[]);
 const filters = $derived([{id:'all',label:'All slots',count:day?.slots.length??0},{id:'pending',label:'Pending',count:dayCount('pending')},
  {id:'confirmed',label:'Booked',count:dayCount('confirmed')},{id:'done',label:'Completed',count:dayCount('done')},
  {id:'open',label:'Open',count:day?.slots.filter(slot=>slot.status==='open').length??0}]);
	
	let detail = $state<Booking>();
	let access = $state<'loading' | 'ready' | 'signedOut' | 'denied' | 'unavailable'>('loading');
	let directChange = $state<{ id: string; kind: 'cancel' | 'reschedule' }>();
	let busy = $state(false);
	let message = $state('');
	let notice = $state('');

	async function describeFailure(response: Response) {
		const body = await response.json().catch(() => null);
		return typeof body?.message === 'string' ? body.message : 'The request could not be completed. Try again.';
	}

	async function load() {
		access = 'loading';
		day = undefined;
		directChange = undefined;
		message = '';
		try {
			const response = await fetch(resolve('/api/staff/bookings') + '?' + new URLSearchParams({ date }));
			if (response.status === 401) {
				access = 'signedOut';
			} else if (response.status === 403) {
				access = 'denied';
			} else if (!response.ok) {
				throw new Error(await describeFailure(response));
			} else {
				day = await response.json();
				access = 'ready';
			}
		} catch (failure) {
			message = failure instanceof Error ? failure.message : 'Could not load the workspace.';
			access = 'unavailable';
		}
	}

	async function changeSaved(kind: 'cancel' | 'reschedule') {
		await load();
		if (access === 'ready') notice = kind === 'cancel' ? 'Booking cancelled.' : 'Booking rescheduled.';
	}

	function pickDate(value: string) {
		if (!value || busy) return;
		date = value;
		notice = '';
		void load();
	}

	async function submit(path: '/api/staff/bookings', body: Action, success: string) {
		if (busy) return;
		busy = true;
		message = notice = '';
		try {
			const response = await fetch(resolve(path), {
				method: 'POST',
				headers: { 'content-type': 'application/json', accept: 'application/json' },
				body: JSON.stringify(body)
			});
			if (response.status === 401) {
				await load();
				return;
			}
			if (!response.ok) throw new Error(await describeFailure(response));
			await load();
			if (access === 'ready') notice = success;
		} catch (failure) {
			message = failure instanceof Error ? failure.message : 'The request could not be completed.';
		} finally {
			busy = false;
		}
	}

	function changeSchedule(action: ScheduleAction, hour?: number) {
		void submit('/api/staff/bookings', { action, date, hour }, 'Availability updated.');
	}

	function confirm(event: SubmitEvent, bookingId: string) {
		event.preventDefault();
		if (!(event.currentTarget instanceof HTMLFormElement)) return;
		const note = String(new FormData(event.currentTarget).get('note') ?? '');
		void submit('/api/staff/bookings', { action: 'confirm', bookingId, note }, 'Booking confirmed.');
	}

	onMount(() => { void load(); });
</script>

<svelte:head><title>Shop admin | HERCO Detailing Garage</title></svelte:head>
<section class="section wrap stack booking-workspace staff-parity">
	{#if access === 'loading'}<p role="status">Loading the booking schedule…</p>
	{:else if access === 'signedOut'}<p>Sign in with your staff account.</p><a class="btn" href={resolve('/account')}>Sign in</a>
	{:else if access === 'denied'}<p role="alert">Your account does not have access to this booking workspace.</p>
	{:else if access === 'unavailable'}<p role="alert">{message}</p><button class="btn sm ghost" onclick={load}>Try again</button>
	{:else if day}
		<div class="row between day-heading"><div><p class="eyebrow">Booking schedule</p><h2>{fmtDate(date)}</h2><div class="row day-status"><span class="badge" data-status={day.past_date ? undefined : closed ? 'cancelled' : 'done'}>{day.past_date ? 'Past date' : closed ? 'Closed to new bookings' : 'Available'}</span><span class="small muted">{day.override === null ? 'Regular hours' : day.override ? 'Opened by admin' : 'Closed by admin'}</span></div></div>
			<div class="row day-controls">{#if day.can_manage_schedule && !day.past_date}<button class="btn sm ghost" onclick={() => availabilityDialog?.showModal()}><ActionIcon name="calendar" />Manage availability</button>{/if}<div class="row" role="group" aria-label="Select booking day"><button class="btn sm ghost" aria-label="Previous day" disabled={busy} onclick={() => pickDate(addDays(date, -1))}><ActionIcon name="left" /></button><button class="btn sm ghost" aria-label="Next day" disabled={busy} onclick={() => pickDate(addDays(date, 1))}><ActionIcon name="right" /></button></div></div></div>
		<div class="tiles"><div class="card pending-tile"><b class="display">{dayCount('pending')}</b><span class="small">Pending</span></div><div class="card booked-tile"><b class="display">{dayCount('confirmed')}</b><span class="small">Booked</span></div><div class="card completed-tile"><b class="display">{dayCount('done')}</b><span class="small">Completed</span></div></div>
		<div class="booking-layout"><div class="stack booking-column"><ServerAdminCalendar value={date} onpick={pickDate} /></div><section class="stack booking-column" aria-labelledby="time-slots-heading">
			<div class="card row between schedule-heading"><div><h3 id="time-slots-heading">Time slots</h3><p class="small muted">Philippine time</p></div><details class="slot-filter" bind:this={filterMenu}><summary><ActionIcon name="adjust" />{filters.find(item => item.id === filter)?.label}<span class="slot-filter-count">{filters.find(item => item.id === filter)?.count}</span><span aria-hidden="true">▾</span></summary><div class="filter-options">{#each filters as item}<button type="button" aria-pressed={filter === item.id} onclick={() => { filter = item.id; if (filterMenu) filterMenu.open = false; }}>{item.label}<span>{item.count}</span></button>{/each}</div></details></div>
			<label>Booking source<select bind:value={source}><option value="all">All sources</option><option value="online">Online</option><option value="walk-in">Walk-in</option></select></label>
			{#if source !== 'online'}{#each day.bookings.filter(booking => booking.visit_hour === null && (filter === 'all' || booking.status === filter)) as booking (booking.id)}<article class="card slot-card"><ServerStaffBookingCard {booking} permissions={{ ...day, canComplete, canRequestIntake, canAdjustPrices }} onSaved={load} onDetails={() => detail = booking} /></article>{/each}{/if}
			<ol class="stack slot-list">{#each slots as slot (date + slot.hour)}{@const booking = day.bookings.find(item => item.visit_hour === slot.hour)}<li class="card slot-card" data-slot-status={booking?.status ?? slot.status}>
				{#if booking}<ServerStaffBookingCard {booking} permissions={{ ...day, canComplete, canRequestIntake, canAdjustPrices }} onSaved={load} onDetails={() => detail = booking} />
				{:else}<div class="slot-summary"><time>{hourLabel(slot.hour)}</time><strong>{slotLabels[slot.status]}</strong></div>{/if}
			</li>{:else}<li class="card">No time slots match these filters.</li>{/each}</ol>
		</section></div>
		<DetailsSheet title={detail ? 'Details for ' + detail.customer_name : 'Booking details'} open={Boolean(detail)} onclose={() => detail = undefined}>{#if detail}<ServerBookingDetails booking={detail} />{/if}</DetailsSheet>
		{#if day.can_manage_schedule}<dialog class="availability-dialog" bind:this={availabilityDialog} aria-labelledby="availability-title"><header class="availability-header"><span class="availability-icon"><ActionIcon name="calendar" /></span><div><h3 id="availability-title">Manage availability</h3><p class="small muted">{fmtDate(date)} · Philippine time</p></div><button class="availability-button" onclick={() => availabilityDialog?.close()}>Close</button></header><div class="stack availability-body"><p class="small muted">Changes apply to new bookings. Existing appointments stay scheduled.</p><section class="stack availability-day"><div class="row between"><h4>Date availability</h4><span class="badge">{closed ? 'Closed' : 'Available'}</span></div><div class="row availability-actions"><button class="availability-button" disabled={busy || day.past_date} onclick={() => changeSchedule(closed ? 'open_date' : 'close_date')}><ActionIcon name={closed ? 'check' : 'block'} />{closed ? 'Open this date' : 'Close this date'}</button>{#if day.override !== null}<button class="availability-button" disabled={busy || day.past_date} onclick={() => changeSchedule('restore_date')}><ActionIcon name="reset" />Restore regular hours</button>{/if}</div></section><section class="stack availability-times"><h4>Time slot restrictions</h4><ul>{#each day.slots as slot}<li class="row between"><div><strong>{hourLabel(slot.hour)}</strong><p class="small slot-restriction" class:restricted={slot.blocked}>{slot.status === 'past' ? 'Past slot' : slot.blocked ? 'Blocked for new bookings' : 'No slot restriction'}</p></div>{#if !day.past_date && (slot.status !== 'past' || slot.blocked)}<button class="availability-button slot-button" disabled={busy} onclick={() => changeSchedule(slot.blocked ? 'unblock_slot' : 'block_slot', slot.hour)}><ActionIcon name={slot.blocked ? 'check' : 'block'} />{slot.blocked ? 'Unblock' : 'Block slot'}</button>{/if}</li>{/each}</ul></section>{#if message}<p role="alert">{message}</p>{/if}{#if notice}<p role="status">{notice}</p>{/if}</div></dialog>{/if}
	{/if}
	{#if message && access !== 'unavailable'}<p role="alert">{message}</p>{/if}{#if notice}<p role="status">{notice}</p>{/if}
</section>

<style>

	:global(.staff-parity .manual-menu) { position: relative; margin-inline-start: auto; }
	:global(.staff-parity .manual-menu summary) { list-style: none; cursor: pointer; }
	:global(.staff-parity .manual-menu summary::-webkit-details-marker) { display: none; }
	:global(.staff-parity .manual-options) { position: absolute; inset: calc(100% + .3rem) 0 auto auto; min-width: 9rem; padding: .25rem; background: var(--panel); border: 1px solid var(--line); border-radius: 6px; box-shadow: 0 4px 12px var(--card-shadow); z-index: 5; }
	:global(.staff-parity .manual-options a) { display: block; padding: .55rem .7rem; border-radius: 4px; text-decoration: none; }
	:global(.staff-parity .manual-options a:hover) { background: var(--panel-2); }
	:global(.staff-parity .admin-content) { grid-template-columns: minmax(0, 1fr); }
	:global(.staff-parity .booking-workspace) { max-width: 1420px; }
	:global(.staff-parity .booking-workspace :is(.booking-sections, .day-controls, .schedule-heading) :global(.btn)) {
		clip-path: none;
		border-radius: 6px;
		font-style: normal;
	}
	:global(.staff-parity .day-heading h2) { font-size: clamp(2rem, 4vw, 3.5rem); margin-top: .35rem; }
	:global(.staff-parity .day-status) { margin-block-start: .35rem; }
	:global(.staff-parity .day-controls) { gap: .6rem; }
	:global(.staff-parity .day-controls > .row) { gap: .3rem; }
	:global(.staff-parity .day-controls button) { min-width: 40px; padding-inline: .65rem; }
	:global(.staff-parity .tiles) {
		display: grid;
		grid-template-columns: repeat(3, minmax(0, 1fr));
		gap: .65rem;
	}

	:global(.staff-parity .tiles .card) {
		display: grid;
		gap: .22rem;
		padding: .7rem .85rem;
	}

	:global(.staff-parity .tiles b) {
		font-size: 2rem;
	}
	:global(.staff-parity .pending-tile) { color: var(--warn); border-color: var(--warn-line); background: color-mix(in srgb, var(--warn-bg) 45%, var(--panel)); }
	:global(.staff-parity .booked-tile) { color: var(--accent); border-color: var(--bad-line); background: color-mix(in srgb, var(--bad-bg) 45%, var(--panel)); }
	:global(.staff-parity .completed-tile) { color: var(--ok); border-color: var(--ok-line); background: color-mix(in srgb, var(--ok-bg) 45%, var(--panel)); }
	:global(.staff-parity .availability-dialog) { --dialog-gutter: clamp(.75rem, 3vw, 1.2rem); width: min(540px, calc(100% - 24px)); max-height: 90dvh; margin: auto; padding: 0; border: 1px solid var(--line); border-radius: 12px; background: var(--panel); color: var(--text); }
	:global(.staff-parity .availability-dialog::backdrop) { background: #0009; }
	:global(.staff-parity .availability-header) { position: sticky; top: 0; z-index: 1; display: grid; grid-template-columns: auto minmax(0, 1fr) auto; align-items: center; gap: .65rem; padding: var(--dialog-gutter); background: var(--panel); border-bottom: 1px solid var(--line); }
	:global(.staff-parity .availability-icon) { display: grid; place-items: center; width: 2.15rem; aspect-ratio: 1; border-radius: 8px; background: var(--panel-2); color: var(--accent); }
	:global(.staff-parity .availability-body) { padding: var(--dialog-gutter); }
	:global(.staff-parity .availability-day) { gap: .45rem; padding: .7rem; border: 1px solid var(--line); border-radius: 8px; background: var(--panel-2); }
	:global(.staff-parity .availability-actions) { gap: .4rem; }
	:global(.staff-parity .availability-button) { display: inline-flex; align-items: center; justify-content: center; gap: .4rem; min-height: 36px; padding: .3rem .55rem; border: 1px solid var(--line); border-radius: 6px; background: var(--panel); color: var(--text); font: 650 .8rem var(--body); cursor: pointer; }
	:global(.staff-parity .availability-button:hover) { border-color: var(--accent); }
	:global(.staff-parity .date-danger) { color: var(--bad); }
	:global(.staff-parity .slot-button) { min-width: 6.25rem; }
	:global(.staff-parity .slot-restriction) { color: var(--muted); }
	:global(.staff-parity .slot-restriction.restricted) { color: var(--bad); }
	:global(.staff-parity .availability-dialog h4) { margin: 0; font-size: .95rem; }
	:global(.staff-parity .availability-times) { gap: .5rem; }
	:global(.staff-parity .availability-times ul) { margin: 0; padding: 0 .65rem; list-style: none; border: 1px solid var(--line); border-radius: 8px; }
	:global(.staff-parity .availability-times li) { padding: .45rem 0; }
	:global(.staff-parity .availability-times li + li) { border-top: 1px solid var(--line); }
	:global(.staff-parity .availability-dialog h3), :global(.staff-parity .schedule-heading h3) { font-size: 1.35rem; }
	:global(.staff-parity .booking-layout) { display: grid; align-items: start; gap: .9rem; }
	:global(.staff-parity .booking-column) { min-width: 0; }
	:global(.staff-parity .slot-filter) { position: relative; min-width: 10rem; font-size: .85rem; }
	:global(.staff-parity .slot-filter summary) { display: flex; align-items: center; gap: .5rem; min-height: 40px; padding: .32rem .6rem; list-style: none; border: 1px solid var(--line); border-radius: 6px; background: var(--panel); font-weight: 700; cursor: pointer; }
	:global(.staff-parity .slot-filter summary::-webkit-details-marker) { display: none; }
	:global(.staff-parity .slot-filter[open] summary), :global(.staff-parity .slot-filter summary:hover) { border-color: var(--accent); }
	:global(.staff-parity .slot-filter-chevron) { width: .44rem; height: .44rem; margin-inline: .1rem; border: solid currentColor; border-width: 0 1.5px 1.5px 0; transform: translateY(-2px) rotate(45deg); }
	:global(.staff-parity .slot-filter summary .slot-filter-count) { margin-inline-start: auto; }
	:global(.staff-parity .slot-filter[open] .slot-filter-chevron) { transform: translateY(2px) rotate(225deg); }
	:global(.staff-parity .slot-filter-options) { display: grid; position: absolute; inset: calc(100% + .3rem) auto auto 0; z-index: 2; min-width: max(100%, 9rem); gap: .15rem; padding: .25rem; border: 1px solid var(--line); border-radius: 7px; background: var(--panel); box-shadow: 0 4px 14px var(--card-shadow); }
	:global(.staff-parity .slot-filter-options button) { display: grid; grid-template-columns: 1em minmax(0, 1fr) auto; align-items: center; gap: .4rem; border: 0; border-radius: 4px; background: transparent; padding: .35rem .45rem; color: var(--text); font: inherit; text-align: start; cursor: pointer; }
	:global(.staff-parity .slot-filter-options button:hover), :global(.staff-parity .slot-filter-options button[aria-pressed='true']) { background: var(--panel-2); }
	:global(.staff-parity .slot-filter-check) { color: var(--accent); }
	:global(.staff-parity .slot-filter-count) { min-width: 1.3rem; padding-inline: .2rem; border-radius: .25rem; background: var(--bg); color: var(--muted); text-align: center; font-variant-numeric: tabular-nums; }
	:global(.staff-parity .schedule-heading) { padding: .75rem .85rem; }

	:global(.staff-parity ol) {
		margin: 0;
		padding: 0;
		list-style: none;
		gap: .55rem;
	}

	:global(.staff-parity .slot-card) { padding: .6rem .8rem; border-inline-start: 4px solid var(--line); }
	:global(.staff-parity .slot-card[data-slot-status='pending']) { border-inline-start-color: var(--warn); }
	:global(.staff-parity .slot-card[data-slot-status='confirmed']) { border-inline-start-color: var(--accent); }
	:global(.staff-parity .slot-card[data-slot-status='done']) { border-inline-start-color: var(--ok); }
	:global(.staff-parity .slot-card[data-slot-status='blocked']) { background: var(--panel-2); }
	:global(.staff-parity .slot-card[data-slot-status='open']) { border-style: dashed; border-inline-start: 4px solid var(--ok-line); }
	:global(.staff-parity .slot-summary) { display: grid; grid-template-columns: minmax(4rem, max-content) minmax(0, 1fr); gap: .7rem; align-items: start; flex: 1 1 14rem; min-width: 0; }
	:global(.staff-parity .time) {
		color: var(--accent);
		font-size: 1.2rem;
		line-height: 1.2;
		white-space: nowrap;
	}

	:global(.staff-parity .between) {
		justify-content: space-between;
	}

	@media (min-width: 1000px) {
		:global(.staff-parity .booking-layout) { grid-template-columns: minmax(345px, 2fr) minmax(0, 4fr); }
	}

.slot-list{list-style:none;padding:0;margin:0}.filter-options{position:absolute;z-index:5;right:0;min-width:100%;background:var(--panel);border:1px solid var(--line);border-radius:6px;padding:.3rem;display:grid}.filter-options button{display:flex;justify-content:space-between;gap:1rem;padding:.5rem;border:0;background:transparent;color:var(--text);cursor:pointer}.filter-options button[aria-pressed=true]{color:var(--accent);background:var(--panel-2)}
</style>
