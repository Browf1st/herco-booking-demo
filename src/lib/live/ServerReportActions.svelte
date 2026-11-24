<script lang="ts">
	// The Approve / Reschedule / Cancel buttons inside the Reports "More details" popup.
	// They use the same endpoints and forms as the booking cards. The server still decides who may do what.
	import { resolve } from '$app/paths';
	import ActionIcon from '../shared/ActionIcon.svelte';
	import { today } from '../shared/dates';
	import ServerCustomerChangeForm from './ServerCustomerChangeForm.svelte';
	import type { StaffBooking } from './server-booking-types';

	let { booking, actions, onsaved }: { booking: StaffBooking; actions: string[]; onsaved: () => void } = $props();
	let dialog = $state<HTMLDialogElement>();
	let kind = $state<'confirm' | 'cancel' | 'reschedule'>('confirm');
	let note = $state('');
	let busy = $state(false);
	let issue = $state('');
	const active = $derived(booking.status === 'pending' || booking.status === 'confirmed');
	const canChange = $derived(active && booking.visit_date >= today() && !booking.request_pending);
	const canApprove = $derived(canChange && booking.status === 'pending' && actions.includes('confirmBooking'));
	const canMove = $derived(canChange && booking.visit_hour !== null && actions.includes('rescheduleBooking'));
	const canCancel = $derived(canChange && actions.includes('cancelBooking'));

	function open(next: typeof kind) { kind = next; note = issue = ''; dialog?.showModal(); }
	function saved() { dialog?.close(); onsaved(); }
	async function approve(event: SubmitEvent) {
		event.preventDefault();
		if (busy) return;
		busy = true; issue = '';
		try {
			const response = await fetch(resolve('/api/staff/bookings'), { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ action: 'confirm', bookingId: booking.id, note }) });
			if (!response.ok) { const result = await response.json(); throw new Error(result.message ?? 'Could not save the update.'); }
			saved();
		} catch (failure) { issue = failure instanceof Error ? failure.message : 'Could not save the update.'; }
		finally { busy = false; }
	}
</script>

{#if canApprove}<button type="button" class="act approve" onclick={() => open('confirm')}><ActionIcon name="check" />Approve booking</button>{/if}
{#if canMove || canCancel}
	<div class="pair">
		{#if canMove}<button type="button" class="act" onclick={() => open('reschedule')}>Reschedule</button>{/if}
		{#if canCancel}<button type="button" class="act danger" onclick={() => open('cancel')}>Cancel booking</button>{/if}
	</div>
{/if}
{#if booking.request_pending}<p class="small muted">A change request is waiting for review in Change requests.</p>{/if}

<dialog bind:this={dialog} aria-label={kind === 'confirm' ? 'Approve booking' : kind + ' booking'}>
	{#if kind === 'confirm'}
		<form class="stack" onsubmit={approve}>
			<h3>Approve booking</h3>
			<label>Private approval note (optional)<textarea bind:value={note} rows="3" maxlength="500" disabled={busy}></textarea></label>
			{#if issue}<p class="error" role="alert">{issue}</p>{/if}
			<div class="row"><button type="button" class="act" disabled={busy} onclick={() => dialog?.close()}>Go back</button><button class="act approve" disabled={busy}>{busy ? 'Saving…' : 'Approve booking'}</button></div>
		</form>
	{:else}
		<ServerCustomerChangeForm bookingId={booking.id} {kind} staffVisit={{ date: booking.visit_date, hour: booking.visit_hour }} onSaved={saved} onClose={() => dialog?.close()} />
	{/if}
</dialog>

<style>
	.act { display: inline-flex; align-items: center; justify-content: center; gap: .4rem; min-height: 2.75rem; padding: 0 1rem; border: 1px solid var(--line); border-radius: 10px; background: var(--panel); color: var(--text); font: 700 .9rem var(--body); cursor: pointer; }
	.act:hover:not(:disabled) { border-color: var(--accent); }
	.act:disabled { opacity: .4; cursor: not-allowed; }
	.approve { min-height: 3rem; border-color: transparent; background: light-dark(#0f8a4f, #2a8a5c); color: #fff; font-size: 1rem; }
	.pair { display: grid; grid-template-columns: repeat(auto-fit, minmax(8rem, 1fr)); gap: .5rem; }
	.danger { color: var(--bad); border-color: var(--bad-line); }
	dialog { width: min(650px, calc(100% - 24px)); max-height: 90dvh; padding: 1rem; border: 1px solid var(--line); border-radius: 12px; background: var(--panel); color: var(--text); }
	dialog::backdrop { background: #0009; }
</style>
