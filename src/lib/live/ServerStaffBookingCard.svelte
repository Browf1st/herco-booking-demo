<script lang="ts">
	import { resolve } from '$app/paths';
	import ActionIcon from '../shared/ActionIcon.svelte';
	import BookingCard, { type CardFact } from '../shared/BookingCard.svelte';
	import ServerCustomerChangeForm from './ServerCustomerChangeForm.svelte';
	import type { StaffBooking, StaffBookingPermissions } from './server-booking-types';
	import { fmtSlot, today } from '../shared/dates';
	let { booking, permissions = {}, when, onDetails, onSaved = () => {} }: { booking: StaffBooking; permissions?: StaffBookingPermissions; when?: string; onDetails: () => void; onSaved?: () => void } = $props();
	let dialog = $state<HTMLDialogElement>();
	let action = $state<'confirm' | 'cancel' | 'reschedule' | 'complete' | 'services' | 'share'>('confirm');
	let more = $state<HTMLDetailsElement>();
	let busy = $state(false);
	let issue = $state('');
	let note = $state('');
	let sharePhotos = $state(false);
	// Labelled segments: bike, how many services and, only when the server sent amounts (viewIncome), the estimate.
	const peso = new Intl.NumberFormat('en-PH', { style: 'currency', currency: 'PHP' });
	const facts = $derived<CardFact[]>([
		{ icon: 'finish', label: 'Bike', value: booking.bike || 'Not provided' },
		{ icon: 'menu', label: 'Services', value: booking.services.length + (booking.services.length === 1 ? ' service' : ' services') },
		...(typeof booking.total_centavos === 'number' ? [{ icon: 'adjust', label: 'Estimate', value: peso.format(booking.total_centavos / 100) } as CardFact] : [])
	]);
	const serviceNames = $derived(booking.current_services?.length ? booking.current_services.map((line) => line.code) : booking.services);
	const active = $derived(booking.status === 'pending' || booking.status === 'confirmed');
	const past = $derived(booking.visit_date < today());
	const canChange = $derived(active && !past && !booking.request_pending);
	const hasCustomerAccount = $derived(booking.customer_id !== null);
	const canOpenIntake = $derived(hasCustomerAccount && permissions.canRequestIntake && booking.status !== 'done');
	function open(next: typeof action) { action = next; issue = ''; note = next === 'share' ? booking.shared_note ?? '' : ''; sharePhotos = Boolean(booking.shared_photos); if (more) more.open = false; dialog?.showModal(); }
	function saved() { dialog?.close(); onSaved(); }
	async function submit(event: SubmitEvent) {
		event.preventDefault(); if (busy) return; busy = true; issue = '';
		try {
			const response = await fetch(resolve('/api/staff/bookings'), { method: 'POST', headers: { 'content-type': 'application/json' },
				body: JSON.stringify(action === 'share' ? { action: 'share', bookingId: booking.id, note, photos: sharePhotos } : { action: 'confirm', bookingId: booking.id, note }) });
			if (!response.ok) { const result = await response.json(); throw new Error(result.message ?? 'Could not save the update.'); }
			saved();
		} catch (failure) { issue = failure instanceof Error ? failure.message : 'Could not save the update.'; }
		finally { busy = false; }
	}
</script>
<BookingCard when={when ?? (booking.visit_hour === null ? 'Walk-in' : fmtSlot(booking.visit_hour + ':00'))} status={booking.status} name={booking.customer_name} {facts} services={serviceNames} {onDetails}>
	{#snippet actions()}
		{#if booking.request_pending && Object.values(permissions).some(Boolean)}<a class="btn sm ghost" href={resolve('/admin') + '?view=requests'}><ActionIcon name="edit" />Review request</a>
		{:else if canChange && booking.status === 'pending' && permissions.can_confirm}<button class="btn sm confirm-action" onclick={() => open('confirm')}><ActionIcon name="check" />Confirm booking</button>
		{:else if booking.status === 'confirmed' && permissions.canComplete}<button class="btn sm complete-action" onclick={() => open('complete')}><ActionIcon name="finish" />Complete service</button>{/if}
		{#if permissions.can_edit_services || permissions.can_cancel || permissions.can_reschedule || permissions.canComplete || canOpenIntake || permissions.canAdjustPrices}
			<details class="more" bind:this={more}><summary class="btn sm ghost" aria-label="More actions"><span aria-hidden="true">⋯</span></summary><div class="more-options">
				{#if permissions.can_edit_services}<button class="btn sm ghost" onclick={() => open('services')}><ActionIcon name="edit" />{active ? 'Edit services' : 'Service history'}</button>{/if}
				{#if permissions.canAdjustPrices}<a class="btn sm ghost" href={resolve('/booking-prices') + '?booking=' + booking.id}>Adjust prices</a>{/if}
				{#if canChange && booking.visit_hour !== null && permissions.can_reschedule}<button class="btn sm ghost" onclick={() => open('reschedule')}><ActionIcon name="calendar" />Reschedule booking</button>{/if}
				{#if canOpenIntake}<a class="btn sm ghost" href={resolve('/walk-in-intake') + '?booking=' + booking.id}>Walk-in intake</a>{/if}
				{#if permissions.canComplete && booking.status === 'done'}<button class="btn sm ghost" onclick={() => open('complete')}>Completion photos</button>{/if}
				{#if hasCustomerAccount && (permissions.can_edit_services || permissions.canComplete)}<button class="btn sm ghost" onclick={() => open('share')}>Share customer note/photos</button>{/if}
				{#if canChange && permissions.can_cancel}<button class="btn sm danger cancel-option" onclick={() => open('cancel')}><ActionIcon name="block" />Cancel booking</button>{/if}
			</div></details>
		{/if}
	{/snippet}
</BookingCard>
<dialog bind:this={dialog} class="booking-dialog" aria-label={action === 'share' ? 'Share customer note and photos' : action + ' booking'}>
	{#if action === 'confirm' || action === 'share'}
		<form class="stack" onsubmit={submit}><h3>{action === 'share' ? 'Share with customer' : 'Confirm booking'}</h3>
			{#if action === 'share'}<p>Only this message and selected completion photos appear in the customer's booking details. Private notes remain private.</p><label>Customer-facing note<textarea bind:value={note} rows="4" maxlength="1000" disabled={busy}></textarea></label><label class="check"><input type="checkbox" bind:checked={sharePhotos} disabled={busy || !booking.photo_count} /> Share this booking's saved completion photos</label><p class="small muted">Clear the message and photo choice to stop sharing.</p>
			{:else}<label>Private approval note (optional)<textarea bind:value={note} rows="3" maxlength="500" disabled={busy}></textarea></label>{#if hasCustomerAccount}<p class="small muted">Use Share customer note/photos for a separate message the customer can see.</p>{/if}{/if}
			{#if issue}<p role="alert">{issue}</p>{/if}<div class="row"><button class="btn sm" disabled={busy}>{busy ? 'Saving…' : action === 'share' ? 'Save sharing choices' : 'Confirm booking'}</button><button type="button" class="btn sm ghost" disabled={busy} onclick={() => dialog?.close()}>Go back</button></div>
		</form>
	{:else if action === 'cancel' || action === 'reschedule'}<ServerCustomerChangeForm bookingId={booking.id} kind={action} staffVisit={{ date: booking.visit_date, hour: booking.visit_hour }} onSaved={saved} onClose={() => dialog?.close()} />
	<!-- These two forms load only when their dialog opens (keeps the staff page's first download small). -->
	{:else if action === 'complete'}{#key booking.id}{#await import('./ServerCompletionForm.svelte') then { default: ServerCompletionForm }}<ServerCompletionForm bookingId={booking.id} initialPrice={(booking.total_centavos ?? 0) / 100} {hasCustomerAccount} onSaved={saved} onClose={() => dialog?.close()} />{/await}{/key}
	{:else if action === 'services'}{#await import('./BookingServiceEditor.svelte') then { default: BookingServiceEditor }}<BookingServiceEditor bookingId={booking.id} fromStaff={true} />{/await}{/if}
</dialog>
<style>
.more{position:relative}.more summary{list-style:none;cursor:pointer}.more summary::-webkit-details-marker{display:none}.more-options{position:absolute;z-index:4;inset:calc(100% + .25rem) 0 auto auto;width:max-content;max-width:min(18rem,calc(100vw - 3rem));display:grid;gap:.25rem;padding:.35rem;border:1px solid var(--line);border-radius:8px;background:var(--panel);box-shadow:0 4px 12px var(--card-shadow)}.more-options :global(.btn){justify-content:flex-start;width:100%;border-radius:4px;clip-path:none;font-style:normal}.cancel-option{margin-top:.5rem}.booking-dialog{width:min(650px,calc(100% - 24px));max-height:90dvh;padding:1rem;border:1px solid var(--line);border-radius:12px;background:var(--panel);color:var(--text)}.booking-dialog::backdrop{background:#0009}.check{display:flex;gap:.5rem;align-items:start}.check input{width:auto}@media(max-width:520px){.more-options{position:static;margin-top:.25rem}}
</style>
