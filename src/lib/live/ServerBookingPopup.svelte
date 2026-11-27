<script lang="ts">
	// The Bookings tab "More details" popup: the Reports popup design plus the actions this staff member may use
	// (approve, reschedule, cancel, complete, per-service price edits, add/remove services) and the Changes history.
	// Loaded only when a popup opens, so the admin page stays small. The server checks every action again.
	// "grants" are the staff member's action grants and "pages" the pages they may open (GET /api/staff/workspace).
	import ReportDetails from '../shared/ReportDetails.svelte';
	import { editRights } from '../shared/edit-rights';
	import { expectedCentavos } from '../shared/booking-changes';
	import ActionIcon from '../shared/ActionIcon.svelte';
	import { detailOf } from './booking-detail';
	import ServerBookingChanges from './ServerBookingChanges.svelte';
	import ServerCompletionForm from './ServerCompletionForm.svelte';
	import ServerReportActions from './ServerReportActions.svelte';
	import ServerServiceEdits from './ServerServiceEdits.svelte';
	import type { StaffBooking, StaffLine } from './server-booking-types';

	// `withActions` false (Booking history) leaves out approve / cancel / reschedule / complete and keeps the price and service editors.
	let { booking, grants, pages, canComplete = false, withActions = true, onclose, onsaved, onreload }: {
		booking: StaffBooking; grants: string[]; pages: string[]; canComplete?: boolean; withActions?: boolean;
		onclose: () => void; onsaved: () => void; onreload: () => Promise<void>;
	} = $props();

	const showMoney = $derived(grants.includes('viewIncome'));
	// Lines and total after a save in this popup; they only count while the same booking object is open.
	let patch = $state.raw<{ for: StaffBooking; lines: StaffLine[]; total: number }>();
	const current = $derived(patch?.for === booking ? { ...booking, current_services: patch.lines, total_centavos: patch.total } : booking);
	const detail = $derived(detailOf(current, showMoney));
	const rights = $derived(editRights(booking.status, grants, pages));
	const canEditLines = $derived(Boolean(current.current_services?.length && (rights.price || rights.services)));
	// Show a top-right button only when it has something to act on (no dead buttons). The server still checks every grant.
	const canEditPrice = $derived(canEditLines && rights.price && showMoney && Boolean(current.current_services?.some(line => expectedCentavos(line) !== undefined)));
	let servicesEditable = $state(false);
	let changeVersion = $state(0);
	// The top-right Edit price / Edit service buttons only scroll to the editor and open it. The server checks every grant.
	let edits = $state<{ reveal: (mode: 'price' | 'service') => void }>();
	let completing = $state<HTMLDialogElement>();
	let completeOpen = $state(false);
	function openComplete() { completeOpen = true; completing?.showModal(); }

	function updated(lines: StaffLine[], total: number) { patch = { for: booking, lines, total }; changeVersion++; onsaved(); }
	async function reload() { patch = undefined; await onreload(); changeVersion++; }
	function completed() { completing?.close(); onsaved(); onclose(); }</script>

<ReportDetails {detail} {onclose} services={canEditLines ? lineEditor : undefined} changes={changeList} actions={bookingActions}
	onEditPrice={canEditPrice ? () => edits?.reveal('price') : undefined} onEditService={canEditLines && servicesEditable ? () => edits?.reveal('service') : undefined} />

<!-- The form is created only when Complete service is clicked, so it starts from the latest price (after any edits). -->
<dialog class="complete" bind:this={completing} aria-label="Complete service" onclose={() => completeOpen = false}>
	{#if completeOpen}<ServerCompletionForm bookingId={booking.id} initialPrice={(current.total_centavos ?? 0) / 100} hasCustomerAccount={booking.customer_id !== null} onSaved={completed} onClose={() => completing?.close()} />{/if}
</dialog>

{#snippet bookingActions()}
	{#if booking.approval_note || booking.private_completion_note || booking.shared_note || booking.shared_photos}
		<section class="notes" aria-label="Notes">
			<h4>Notes</h4>
			{#if booking.approval_note}<p><strong>Private approval note</strong>{booking.approval_note}</p>{/if}
			{#if booking.private_completion_note}<p><strong>Private completion note</strong>{booking.private_completion_note}</p>{/if}
			{#if booking.shared_note}<p><strong>Note shared with customer</strong>{booking.shared_note}</p>{/if}
			{#if booking.shared_photos}<p>{booking.shared_photos} completion photos explicitly shared with customer.</p>{/if}
		</section>
	{/if}
	{#if withActions}<ServerReportActions {booking} actions={grants} onsaved={() => { onsaved(); onclose(); }} />{/if}
	{#if withActions && booking.request_pending}<p class="small muted">The current appointment stays reserved until the change request is reviewed.</p>{/if}
	{#if withActions && booking.status === 'confirmed' && canComplete}
		<button type="button" class="act" onclick={openComplete}><ActionIcon name="finish" />Complete service</button>
	{/if}
{/snippet}
{#snippet lineEditor()}<ServerServiceEdits bind:this={edits} bind:servicesEditable bookingId={booking.id} status={booking.status} lines={current.current_services ?? []} actions={grants} {pages} {showMoney} onupdated={updated} onreload={reload} />{/snippet}
{#snippet changeList()}<ServerBookingChanges bookingId={booking.id} version={changeVersion} />{/snippet}

<style>
	.act { display: inline-flex; align-items: center; justify-content: center; gap: .4rem; min-height: 2.75rem; padding: 0 1rem; border: 1px solid var(--line); border-radius: 10px; background: var(--panel); color: var(--text); font: 700 .9rem var(--body); cursor: pointer; }
	.act:hover { border-color: var(--accent); }
	.notes { display: grid; gap: .35rem; padding: .75rem; border: 1px solid var(--line); border-radius: 10px; }
	.notes h4 { margin: 0; font-size: .85rem; text-transform: uppercase; letter-spacing: .06em; }
	.notes p { margin: 0; font-size: .9rem; overflow-wrap: anywhere; }
	.notes strong { display: block; color: var(--muted); font-size: .72rem; letter-spacing: .05em; text-transform: uppercase; }
	.complete { width: min(650px, calc(100% - 24px)); max-height: 90dvh; padding: 1rem; border: 1px solid var(--line); border-radius: 12px; background: var(--panel); color: var(--text); }
	.complete::backdrop { background: #0009; }
</style>
