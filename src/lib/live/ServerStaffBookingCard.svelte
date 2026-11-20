<script lang="ts">
	import type { Snippet } from 'svelte';
	import { resolve } from '$app/paths';
	import ActionIcon from '../shared/ActionIcon.svelte';
	import BookingServiceEditor from './BookingServiceEditor.svelte';
	import ServerCustomerChangeForm from './ServerCustomerChangeForm.svelte';
	import ServerCompletionForm from './ServerCompletionForm.svelte';
	import type { StaffBooking, StaffBookingPermissions } from './server-booking-types';
	import { fmtDate, fmtSlot, today } from '../shared/dates';
	let { booking, permissions = {}, heading, onSaved = () => {} }: { booking: StaffBooking; permissions?: StaffBookingPermissions; heading?: Snippet; onSaved?: () => void } = $props();
	let dialog = $state<HTMLDialogElement>();
	let action = $state<'confirm' | 'cancel' | 'reschedule' | 'complete' | 'services' | 'share'>('confirm');
	let more = $state<HTMLDetailsElement>();
	let busy = $state(false);
	let issue = $state('');
	let note = $state('');
	let sharePhotos = $state(false);
	const active = $derived(booking.status === 'pending' || booking.status === 'confirmed');
	const past = $derived(booking.visit_date < today());
	const canChange = $derived(active && !past && !booking.request_pending);
	const labels = { pending: 'Pending', confirmed: 'Booked', done: 'Completed', cancelled: 'Cancelled' };
	const stamp = (value?: string | null) => value ? new Date(value).toLocaleString('en-PH', { timeZone: 'Asia/Manila', dateStyle: 'medium', timeStyle: 'short' }) : 'Not recorded';
	const money = (value?: number | null) => value === undefined || value === null ? '—' : new Intl.NumberFormat('en-PH', { style: 'currency', currency: 'PHP' }).format(value / 100);
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
<div class="booking-header">
	<div class="booking-heading">{#if heading}{@render heading()}{:else}<strong>{booking.customer_name}</strong><p class="small muted">{booking.services.join(' · ')} · {booking.bike}</p><span class="badge" data-status={booking.status === 'confirmed' ? 'booked' : booking.status}>{labels[booking.status]}</span>{/if}</div>
	<div class="row booking-actions">
		{#if booking.request_pending && Object.values(permissions).some(Boolean)}<a class="btn sm ghost" href={resolve('/admin') + '?view=requests'}><ActionIcon name="edit" />Review request</a>
		{:else if canChange && booking.status === 'pending' && permissions.can_confirm}<button class="btn sm confirm-action" onclick={() => open('confirm')}><ActionIcon name="check" />Confirm booking</button>
		{:else if booking.status === 'confirmed' && permissions.canComplete}<button class="btn sm complete-action" onclick={() => open('complete')}><ActionIcon name="finish" />Complete service</button>{/if}
		{#if permissions.can_edit_services || permissions.can_cancel || permissions.can_reschedule || permissions.canComplete || permissions.canRequestIntake || permissions.canAdjustPrices}
			<details class="more" bind:this={more}><summary class="btn sm ghost">More actions <span aria-hidden="true">▾</span></summary><div class="more-options">
				{#if permissions.can_edit_services}<button class="btn sm ghost" onclick={() => open('services')}><ActionIcon name="edit" />{active ? 'Edit services' : 'Service history'}</button>{/if}
				{#if permissions.canAdjustPrices}<a class="btn sm ghost" href={resolve('/booking-prices') + '?booking=' + booking.id}>Adjust prices</a>{/if}
				{#if canChange && booking.visit_hour !== null && permissions.can_reschedule}<button class="btn sm ghost" onclick={() => open('reschedule')}><ActionIcon name="calendar" />Reschedule booking</button>{/if}
				{#if canChange && permissions.can_cancel}<button class="btn sm danger" onclick={() => open('cancel')}><ActionIcon name="block" />Cancel booking</button>{/if}
				{#if permissions.canRequestIntake && booking.status !== 'done'}<a class="btn sm ghost" href={resolve('/walk-in-intake') + '?booking=' + booking.id}>Walk-in intake</a>{/if}
				{#if permissions.canComplete && booking.status === 'done'}<button class="btn sm ghost" onclick={() => open('complete')}>Completion photos</button>{/if}
				{#if permissions.can_edit_services || permissions.canComplete}<button class="btn sm ghost" onclick={() => open('share')}>Share customer note/photos</button>{/if}
			</div></details>
		{/if}
	</div>
</div>
<details class="slot-details"><summary><span class="closed-label">Tap to view more</span><span class="open-label">Show less</span></summary><div class="stack slot-detail-body">
	<p><ActionIcon name="box" /><strong>{booking.reference ?? booking.id}</strong> · {booking.bike}</p>
	<div class="cols"><p><ActionIcon name="calendar" /><strong>Visit</strong><br />{fmtDate(booking.visit_date)} · {booking.visit_hour === null ? 'Walk-in' : fmtSlot(booking.visit_hour + ':00')}</p><p><ActionIcon name="clock" /><strong>Booked on</strong><br />{stamp(booking.created_at)}</p><p><ActionIcon name="check" /><strong>Approved</strong><br />{stamp(booking.approved_at)}</p><p><ActionIcon name="finish" /><strong>Completed</strong><br />{stamp(booking.completed_at)}</p></div>
	<div><h3>Customer &amp; motorcycle</h3><p>{booking.customer_name} · {booking.customer_phone}</p>{#if booking.customer_email}<p>{booking.customer_email}</p>{/if}{#if booking.plate}<p>Plate {booking.plate}</p>{/if}</div>
	<p>Estimated service value <strong>{money(booking.total_centavos)}</strong></p>
	{#if booking.current_services}<ul>{#each booking.current_services as line}<li>{line.label} · {money(line.price_centavos)}{#if line.details}<ul>{#each line.details as detail}<li>{detail.label} · {money(detail.price_centavos)}</li>{/each}</ul>{/if}</li>{/each}</ul>{/if}
	{#if booking.approval_note}<p><strong>Private approval note</strong>: {booking.approval_note}</p>{/if}
	{#if booking.private_completion_note}<p><strong>Private completion note</strong>: {booking.private_completion_note}</p>{/if}
	{#if booking.shared_note}<p><strong>Note shared with customer</strong>: {booking.shared_note}</p>{/if}
	{#if booking.shared_photos}<p>{booking.shared_photos} completion photos explicitly shared with customer.</p>{/if}
	{#if booking.request_pending}<p class="small muted">The current appointment stays reserved while the customer's request is reviewed.</p>{/if}
</div></details>
<dialog bind:this={dialog} class="booking-dialog" aria-label={action === 'share' ? 'Share customer note and photos' : action + ' booking'}>
	{#if action === 'confirm' || action === 'share'}
		<form class="stack" onsubmit={submit}><h3>{action === 'share' ? 'Share with customer' : 'Confirm booking'}</h3>
			{#if action === 'share'}<p>Only this message and selected completion photos appear in the customer's booking details. Private notes remain private.</p><label>Customer-facing note<textarea bind:value={note} rows="4" maxlength="1000" disabled={busy}></textarea></label><label class="check"><input type="checkbox" bind:checked={sharePhotos} disabled={busy || !booking.photo_count} /> Share this booking's saved completion photos</label><p class="small muted">Clear the message and photo choice to stop sharing.</p>
			{:else}<label>Private approval note (optional)<textarea bind:value={note} rows="3" maxlength="500" disabled={busy}></textarea></label><p class="small muted">Use Share customer note/photos for a separate message the customer can see.</p>{/if}
			{#if issue}<p role="alert">{issue}</p>{/if}<div class="row"><button class="btn sm" disabled={busy}>{busy ? 'Saving…' : action === 'share' ? 'Save sharing choices' : 'Confirm booking'}</button><button type="button" class="btn sm ghost" disabled={busy} onclick={() => dialog?.close()}>Go back</button></div>
		</form>
	{:else if action === 'cancel' || action === 'reschedule'}<ServerCustomerChangeForm bookingId={booking.id} kind={action} staffVisit={{ date: booking.visit_date, hour: booking.visit_hour }} onSaved={saved} onClose={() => dialog?.close()} />
	{:else if action === 'complete'}{#key booking.id}<ServerCompletionForm bookingId={booking.id} initialPrice={(booking.total_centavos ?? 0) / 100} onSaved={saved} onClose={() => dialog?.close()} />{/key}
	{:else if action === 'services'}<BookingServiceEditor bookingId={booking.id} fromStaff={true} />{/if}
</dialog>
<style>
.booking-header{display:flex;flex-wrap:wrap;gap:.55rem 1rem;align-items:flex-start}.booking-heading{flex:1 1 14rem;min-width:0}.booking-actions{flex:none;max-width:100%;gap:.4rem}.more{position:relative}.more summary{list-style:none;cursor:pointer}.more summary::-webkit-details-marker{display:none}.more-options{position:absolute;z-index:4;inset:calc(100% + .25rem) 0 auto auto;width:max-content;max-width:min(18rem,calc(100vw - 3rem));display:grid;gap:.25rem;padding:.35rem;border:1px solid var(--line);border-radius:8px;background:var(--panel);box-shadow:0 4px 12px var(--card-shadow)}.more-options :global(.btn){justify-content:flex-start;width:100%;border-radius:4px;clip-path:none;font-style:normal}.slot-details>summary{cursor:pointer;color:var(--muted);font-size:.8rem;font-weight:700;margin-top:.55rem}.slot-details:not([open]) .open-label,.slot-details[open] .closed-label{display:none}.slot-detail-body{margin-top:.8rem;overflow-wrap:anywhere}.booking-dialog{width:min(650px,calc(100% - 24px));max-height:90dvh;padding:1rem;border:1px solid var(--line);border-radius:12px;background:var(--panel);color:var(--text)}.booking-dialog::backdrop{background:#0009}.check{display:flex;gap:.5rem;align-items:start}.check input{width:auto}ul{padding-left:1.3rem}@media(max-width:520px){.more-options{position:static;margin-top:.25rem}.booking-header{flex-direction:column}.booking-heading{flex:none;max-width:100%}}
</style>
