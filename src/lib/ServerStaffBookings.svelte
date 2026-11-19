<script lang="ts">
	import { onMount } from 'svelte';
	import { resolve } from '$app/paths';
	import { addDays, fmtDate, fmtSlot, today } from '#lib/dates.ts';
	import ServerCustomerChangeForm from '#lib/ServerCustomerChangeForm.svelte';
	import CoatingOptionSummary from './CoatingOptionSummary.svelte';
	import type { CoatingOptions } from './booking-coating';
	let { onVerified, canComplete = false, canRequestIntake = false, canAdjustPrices = false }: {
		onVerified?: () => void; canComplete?: boolean; canRequestIntake?: boolean; canAdjustPrices?: boolean;
	} = $props();

	type Booking = {
		id: string;
		visit_hour: number | null;
		bike: string;
		customer_name: string;
		customer_phone: string;
		status: 'pending' | 'confirmed' | 'done';
		services: string[];
		coating_options?: CoatingOptions;
		approval_note: string | null;
		request_pending: boolean;
	};
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
	type Factor = { id: string; name?: string };
	type DateAction = 'open_date' | 'close_date' | 'restore_date';
	type ScheduleAction = DateAction | 'block_slot' | 'unblock_slot';
	type Action = { action: 'confirm'; bookingId: string; note: string } |
		{ action: ScheduleAction; date: string; hour?: number };
	const labels = { pending: 'Pending', confirmed: 'Booked', done: 'Completed' };
	const slotLabels = { past: 'Past slot', open: 'Open', closed: 'Closed', blocked: 'Blocked', booked: 'Booked' };
	const hourLabel = (hour: number) => fmtSlot(hour + ':00');

	let date = $state(today());
	let day = $state<Day>();
	let access = $state<'loading' | 'ready' | 'signedOut' | 'verify' | 'denied' | 'unavailable'>('loading');
	let factors = $state<Factor[]>([]);
	let directChange = $state<{ id: string; kind: 'cancel' | 'reschedule' }>();
	let factorId = $state('');
	let code = $state('');
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
			} else if (response.status === 428) {
				const result = await fetch(resolve('/api/staff/mfa'));
				if (!result.ok) throw new Error(await describeFailure(result));
				factors = await result.json();
				factorId = factors[0]?.id ?? '';
				access = 'verify';
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

	async function submit(path: '/api/staff/mfa' | '/api/staff/bookings', body: Action | { factorId: string; code: string }, success: string) {
		if (busy) return;
		busy = true;
		message = notice = '';
		try {
			const response = await fetch(resolve(path), {
				method: 'POST',
				headers: { 'content-type': 'application/json', accept: 'application/json' },
				body: JSON.stringify(body)
			});
			if (response.status === 401 || response.status === 428) {
				await load();
				return;
			}
			if (!response.ok) throw new Error(await describeFailure(response));
			if (path === '/api/staff/mfa') {
				code = '';
				onVerified?.();
			}
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

<svelte:head><title>Staff bookings | HERCO</title></svelte:head>
<section class="section wrap stack">
	<h1>Staff bookings</h1>
	{#if access === 'loading'}
		<p role="status">Loading the staff workspace…</p>
	{:else if access === 'signedOut'}
		<p>Sign in with your staff account.</p>
		<div><a class="btn" href={resolve('/account')}>Sign in</a></div>
	{:else if access === 'denied'}
		<p role="alert">Your account does not have access to this booking workspace.</p>
	{:else if access === 'verify'}
		{#if factors.length}
			<form class="card stack verification" onsubmit={(event) => {
				event.preventDefault();
				void submit('/api/staff/mfa', { factorId, code }, 'Session verified.');
			}}>
				<h2>Verify your staff session</h2>
				{#if factors.length > 1}
					<label>Authenticator<select bind:value={factorId}>
						{#each factors as factor, index (factor.id)}
							<option value={factor.id}>{factor.name || 'Authenticator ' + (index + 1)}</option>
						{/each}
					</select></label>
				{/if}
				<label>Six-digit code
					<input type="text" bind:value={code} inputmode="numeric" autocomplete="one-time-code" pattern="[0-9]{6}" maxlength="6" required />
				</label>
				<div><button class="btn sm" disabled={busy}>Verify</button></div>
			</form>
		{:else}
			<p>Set up an authenticator in <a href={resolve('/account')}>your account</a> before opening bookings.</p>
		{/if}
	{:else if access === 'unavailable'}
		<div><button class="btn sm ghost" onclick={load}>Try again</button></div>
	{:else if day}
		<div class="row">
			<button class="btn sm ghost" disabled={busy} onclick={() => pickDate(addDays(date, -1))}>Previous day</button>
			<label>Visit date<input type="date" value={date} disabled={busy} onchange={(event) => pickDate(event.currentTarget.value)} /></label>
			<button class="btn sm ghost" disabled={busy} onclick={() => pickDate(addDays(date, 1))}>Next day</button>
		</div>
		<h2>{fmtDate(date)}</h2>
		<p class="small muted">Visit times are in Philippine time.</p>
		{#if day.can_manage_schedule && !day.past_date}
			<section class="card stack">
				<h3>Manage availability</h3>
				<p>{day.override === null ? 'Regular hours' : day.override ? 'Opened manually' : 'Closed manually'}. Existing bookings stay on the schedule.</p>
				<div class="row">
					<button class="btn sm ghost" disabled={busy || day.override === true} onclick={() => changeSchedule('open_date')}>Open date</button>
					<button class="btn sm ghost" disabled={busy || day.override === false} onclick={() => changeSchedule('close_date')}>Close date</button>
					<button class="btn sm ghost" disabled={busy || day.override === null} onclick={() => changeSchedule('restore_date')}>Restore regular hours</button>
				</div>
			</section>
		{/if}
		{#if day.bookings.some(booking => booking.visit_hour === null)}
			<h3>Walk-ins</h3>
			{#each day.bookings.filter(booking => booking.visit_hour === null) as booking (booking.id)}
				<article class="card stack">
					<p class="small">Signed intake · Walk-in</p>
					{@render bookingDetails(booking, date !== today())}
				</article>
			{/each}
		{/if}
		{#each day.slots as slot (slot.hour)}
			{@const booking = day.bookings.find(item => item.visit_hour === slot.hour)}
			<article class="card stack">
				<div class="row between">
					<h3>{hourLabel(slot.hour)}</h3>
					{#if day.can_manage_schedule && !day.past_date && (slot.status !== 'past' || slot.blocked)}
						<button class="btn sm ghost" disabled={busy} aria-label={(slot.blocked ? 'Unblock ' : 'Block ') + hourLabel(slot.hour)}
							onclick={() => changeSchedule(slot.blocked ? 'unblock_slot' : 'block_slot', slot.hour)}>
							{slot.blocked ? 'Unblock' : 'Block slot'}
						</button>
					{/if}
				</div>
				{#if booking}
					{@render bookingDetails(booking, slot.status === 'past')}
				{:else}
					<p>{slotLabels[slot.status]}</p>
				{/if}
				{#if booking && slot.blocked}<p class="small muted">Blocked for new bookings</p>{/if}
			</article>
		{/each}
	{/if}
	{#if message}<p role="alert">{message}</p>{/if}
	{#if notice}<p role="status">{notice}</p>{/if}
</section>

{#snippet bookingDetails(booking: Booking, past: boolean)}
	<div class="row"><strong>{booking.customer_name}</strong><span class="badge" data-status={booking.status === 'confirmed' ? 'booked' : booking.status}>{labels[booking.status]}</span></div>
	<p>{booking.bike} · {booking.services.join(' · ')}</p>
	<details>
		<summary>View details</summary>
		<div class="stack detail">
			<p>{booking.customer_phone}</p>
			<p>Reference {booking.id}</p>
			<CoatingOptionSummary options={booking.coating_options} />
				{#if canAdjustPrices}
					<div><a class="btn sm ghost" href={resolve('/booking-prices') + '?booking=' + booking.id}>Booking prices</a></div>
				{/if}
			{#if canRequestIntake && booking.status !== 'done'}
				<div><a class="btn sm ghost" href={resolve('/walk-in-intake') + '?booking=' + booking.id}>Walk-in intake</a></div>
			{/if}
			{#if day?.can_edit_services}
				<div><a class="btn sm ghost" href={resolve('/booking-services') + '?from=staff&booking=' + booking.id}>
					{booking.status === 'done' || day?.past_date ? 'View service history' : 'Edit services'}
				</a></div>
			{/if}
			{#if canComplete && (booking.status === 'confirmed' || booking.status === 'done')}
				<div><a class="btn sm ghost" href={resolve('/complete-booking') + '?booking=' + booking.id}>
					{booking.status === 'done' ? 'View completion photos' : 'Complete booking'}
				</a></div>
			{/if}
			{#if booking.approval_note}<p><strong>Private approval note</strong> · {booking.approval_note}</p>{/if}
			{#if booking.status !== 'done' && !past && (day?.can_cancel || (booking.visit_hour !== null && day?.can_reschedule))}
				{#if booking.request_pending}
					<p>Review the customer's pending request before changing this visit directly.</p>
					<div><a class="btn sm ghost" href={resolve('/admin') + '?view=requests'}>View change requests</a></div>
				{:else}
					<div class="row">
						{#if day?.can_cancel}<button type="button" class="btn sm ghost" disabled={busy}
							onclick={() => { directChange = { id: booking.id, kind: 'cancel' }; }}>Cancel booking</button>{/if}
						{#if (booking.visit_hour !== null && day?.can_reschedule)}<button type="button" class="btn sm ghost" disabled={busy}
							onclick={() => { directChange = { id: booking.id, kind: 'reschedule' }; }}>Reschedule booking</button>{/if}
					</div>
					{#if directChange?.id === booking.id}
						{@const kind = directChange.kind}
						{#key kind}
							<ServerCustomerChangeForm bookingId={booking.id} {kind} staffVisit={{ date, hour: booking.visit_hour }}
								onSaved={() => { void changeSaved(kind); }} onClose={() => { directChange = undefined; }} />
						{/key}
					{/if}
				{/if}
			{/if}
			{#if day?.can_confirm && booking.status === 'pending' && (booking.visit_hour !== null || date === today())}
				<form class="stack" onsubmit={(event) => confirm(event, booking.id)}>
					<label>Private approval note (optional)<textarea name="note" maxlength="500" rows="2"></textarea></label>
					<div><button class="btn sm" disabled={busy}>Confirm booking</button></div>
				</form>
			{/if}
		</div>
	</details>
{/snippet}

<style>
	.verification { max-width: 32rem; }
	.detail { margin-top: .75rem; overflow-wrap: anywhere; }
</style>
