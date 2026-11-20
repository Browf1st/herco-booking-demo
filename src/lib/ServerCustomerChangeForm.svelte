<script lang="ts">
	import { onMount } from 'svelte';
 import ServerVisitPicker from './ServerVisitPicker.svelte';
	import { resolve } from '$app/paths';
	import { addDays, fmtDate, fmtSlot, today } from '#lib/dates.ts';
	import { trackShopEvent } from '#lib/analytics.ts';

	type Slot = { visit_date: string; visit_hour: number; status: string };
	let { bookingId, kind, onSaved, onClose, staffVisit }: {
		bookingId: string; kind: 'cancel' | 'reschedule'; onSaved: () => void; onClose: () => void;
		staffVisit?: { date: string; hour: number | null };
	} = $props();
	let slots = $state<Slot[]>([]);
	let date = $state('');
	let hour = $state('');
	let reason = $state('');
	let loading = $state(true);
	let busy = $state(false);
	let message = $state('');
	const attempts = new Map<string, string>();
	const openSlots = $derived(slots.filter(slot => slot.status === 'open'));
	const days = $derived([...new Set(openSlots.map(slot => slot.visit_date))]);

	onMount(() => {
		if (kind !== 'reschedule') return;
		const controller = new AbortController();
		const from = today();
		void fetch(resolve('/api/availability') + '?' + new URLSearchParams({ from, to: addDays(from, 20) }), {
			signal: controller.signal
		}).then(async response => {
			if (!response.ok) throw new Error();
			slots = await response.json();
		}).catch(() => {
			if (!controller.signal.aborted) message = 'Could not load available visits. Close and try again.';
		}).finally(() => { loading = false; });
		return () => controller.abort();
	});

	async function submit(event: SubmitEvent) {
		event.preventDefault();
		if (busy || (kind === 'reschedule' && (!date || !hour))) return;
		message = '';
		busy = true;
		try {
			const body = {
				bookingId, kind, reason: reason.trim(),
				...(kind === 'reschedule' ? { date, hour: Number(hour) } : {})
			};
			const fingerprint = JSON.stringify(body);
			const submissionId = attempts.get(fingerprint) ?? crypto.randomUUID();
			attempts.set(fingerprint, submissionId);
			const endpoint = staffVisit ? '/api/staff/bookings' : '/api/bookings/requests';
			const action = staffVisit ? {
				action: 'change', requestId: submissionId, originalDate: staffVisit.date, originalHour: staffVisit.hour
			} : { submissionId };
			const response = await fetch(resolve(endpoint), {
				method: 'POST',
				headers: { 'content-type': 'application/json', accept: 'application/json' },
				body: JSON.stringify({ ...body, ...action })
			});
			if (!response.ok) {
				const failure = await response.json().catch(() => null);
				throw new Error(typeof failure?.message === 'string' ? failure.message : 'Could not send the request.');
			}
			if (!staffVisit) trackShopEvent('change_request_submitted');
			onSaved();
		} catch (failure) {
			message = failure instanceof Error ? failure.message : 'Could not send the request. Try again with the same details.';
		} finally {
			busy = false;
		}
	}
</script>

<form class="card stack" onsubmit={submit}>
	{#if staffVisit}
		<h3>{kind === 'cancel' ? 'Cancel booking' : 'Reschedule booking'}</h3>
		<p class="small">{staffVisit.hour === null ? 'This cancels the walk-in in My Bookings.'
			: 'This changes the appointment in My Bookings and releases the original slot.'}</p>
	{:else}
		<h3>{kind === 'cancel' ? 'Request cancellation' : 'Request rescheduling'}</h3>
		<p class="small">Your current slot stays booked while the shop reviews your request.</p>
	{/if}
	{#if kind === 'reschedule'}
		<ServerVisitPicker bind:date bind:hour disabled={busy}/>
	{/if}
	<label>{staffVisit ? 'Private reason (optional)' : 'Reason (optional)'}<textarea bind:value={reason} maxlength="500" rows="2"></textarea></label>
	{#if message}<p role="alert">{message}</p>{/if}
	<div class="row">
		<button class="btn sm" disabled={busy || (kind === 'reschedule' && (!date || !hour))}>
			{busy ? 'Saving…' : staffVisit ? (kind === 'cancel' ? 'Confirm cancellation' : 'Save new visit') : 'Send request'}
		</button>
		<button type="button" class="btn sm ghost" disabled={busy} onclick={onClose}>Close</button>
	</div>
</form>
