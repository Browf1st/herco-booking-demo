<!-- Styles load together with this screen (not in the page's first stylesheet). -->
<svelte:options css="injected" />
<script lang="ts">
	// The Approve / Reschedule / Cancel buttons inside the Reports "More details" popup (demo).
	// They call the same store actions as the booking cards and only appear for staff who may use them.
	import ActionIcon from '../shared/ActionIcon.svelte';
	import { canPerform } from './staffAccess.svelte.ts';
	import { approveBooking, reschedule, setStatus, type Booking } from './store.svelte';
	import VisitPicker from './VisitPicker.svelte';

	let { booking, ondone }: { booking: Booking; ondone: () => void } = $props();
	let dialog = $state<HTMLDialogElement>();
	let kind = $state<'approve' | 'cancel' | 'move'>('approve');
	let note = $state('');
	let moveDate = $state('');
	let moveSlot = $state('');
	let issue = $state('');
	const waiting = $derived(booking.requests?.some((request) => request.state === 'Pending') ?? false);
	const active = $derived(booking.status === 'pending' || booking.status === 'confirmed');
	const canApprove = $derived(booking.status === 'pending' && !waiting && canPerform('confirmBooking'));
	const canMove = $derived(active && !waiting && canPerform('rescheduleBooking'));
	const canCancel = $derived(active && !waiting && canPerform('cancelBooking'));

	function open(next: typeof kind) { kind = next; note = moveDate = moveSlot = issue = ''; dialog?.showModal(); }
	function save(event: SubmitEvent) {
		event.preventDefault();
		try {
			if (kind === 'approve') approveBooking(booking, note.trim());
			else if (kind === 'cancel') setStatus(booking.id, 'cancelled', note.trim());
			else reschedule(booking.id, moveDate, moveSlot);
			dialog?.close();
			ondone();
		} catch (failure) { issue = failure instanceof Error ? failure.message : 'Could not save the change.'; }
	}
</script>

{#if canApprove}<button type="button" class="act approve" onclick={() => open('approve')}><ActionIcon name="check" />Approve booking</button>{/if}
{#if canMove || canCancel}
	<div class="pair">
		{#if canMove}<button type="button" class="act" onclick={() => open('move')}>Reschedule</button>{/if}
		{#if canCancel}<button type="button" class="act danger" onclick={() => open('cancel')}>Cancel booking</button>{/if}
	</div>
{/if}
{#if waiting}<p class="small muted">A change request is waiting for review in Change requests.</p>{/if}

<dialog bind:this={dialog} aria-label={kind === 'approve' ? 'Approve booking' : kind === 'cancel' ? 'Cancel booking' : 'Reschedule booking'}>
	<form class="stack" onsubmit={save}>
		<h3>{kind === 'approve' ? 'Approve booking' : kind === 'cancel' ? 'Cancel booking' : 'Reschedule booking'}</h3>
		{#if kind === 'move'}
			<VisitPicker bind:date={moveDate} bind:slot={moveSlot} powder={!!(booking.selection?.catalog && booking.selection.powder)} />
		{:else}
			{#if kind === 'cancel'}<p>Cancel {booking.id} for {booking.name}? The appointment time will be released.</p>{/if}
			<label>{kind === 'approve' ? 'Approval note for the customer (optional)' : 'Note for the customer (optional)'}<textarea rows="3" maxlength="1000" bind:value={note}></textarea></label>
		{/if}
		{#if issue}<p class="error" role="alert">{issue}</p>{/if}
		<div class="row">
			<button type="button" class="act" onclick={() => dialog?.close()}>Go back</button>
			<button class="act approve" class:bad={kind === 'cancel'} disabled={kind === 'move' && (!moveDate || !moveSlot)}>{kind === 'approve' ? 'Approve booking' : kind === 'cancel' ? 'Cancel booking' : 'Save new visit'}</button>
		</div>
	</form>
</dialog>

<style>
	.act { display: inline-flex; align-items: center; justify-content: center; gap: .4rem; min-height: 2.75rem; padding: 0 1rem; border: 1px solid var(--line); border-radius: 10px; background: var(--panel); color: var(--text); font: 700 .9rem var(--body); cursor: pointer; }
	.act:hover:not(:disabled) { border-color: var(--accent); }
	.act:disabled { opacity: .4; cursor: not-allowed; }
	.approve { min-height: 3rem; border-color: transparent; background: light-dark(#0f8a4f, #2a8a5c); color: #fff; font-size: 1rem; }
	.approve.bad { background: var(--accent-fill); }
	.pair { display: grid; grid-template-columns: repeat(auto-fit, minmax(8rem, 1fr)); gap: .5rem; }
	.danger { color: var(--bad); border-color: var(--bad-line); }
	dialog { width: min(520px, calc(100% - 24px)); max-height: 90dvh; padding: 1rem; border: 1px solid var(--line); border-radius: 12px; background: var(--panel); color: var(--text); }
	dialog::backdrop { background: #0009; }
</style>