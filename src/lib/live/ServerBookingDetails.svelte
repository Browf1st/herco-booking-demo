<script lang="ts">
	// Everything about one booking, shown inside the shared details sheet.
	import StatusBadge from '../shared/StatusBadge.svelte';
	import { fmtDate, fmtSlot } from '../shared/dates';
	import { editRights } from '../shared/edit-rights';
	// The editor and the Changes list load only when a popup opens that needs them (keeps the admin page small).
	import type { StaffBooking, StaffLine } from './server-booking-types';

	// "actions" (the staff member's grants) turns on price and service editing and the Changes list.
	// "onchanged" tells the screen behind to refresh; "onreload" asks it to load this booking again.
	let { booking, actions, pages, onchanged, onreload }: { booking: StaffBooking; actions?: string[]; pages?: string[]; onchanged?: () => void; onreload?: () => Promise<void> } = $props();
	// Lines and total after a save in this popup. They only count while the same booking object is open.
	let patch = $state.raw<{ for: StaffBooking; lines: StaffLine[]; total: number }>();
	const lines = $derived(patch?.for === booking ? patch.lines : booking.current_services);
	const total = $derived(patch?.for === booking ? patch.total : booking.total_centavos);
	let changeVersion = $state(0);
	const rights = $derived(editRights(booking.status, actions, pages ?? []));
	const editable = $derived(Boolean(onreload && lines?.length && (rights.price || rights.services)));
	function updated(next: StaffLine[], totalCentavos: number) { patch = { for: booking, lines: next, total: totalCentavos }; changeVersion++; onchanged?.(); }
	async function reload() { await onreload?.(); changeVersion++; }
	const stamp = (value?: string | null) => value ? new Date(value).toLocaleString('en-PH', { timeZone: 'Asia/Manila', dateStyle: 'medium', timeStyle: 'short' }) : 'Not recorded';
	const money = (value?: number | null) => value === undefined || value === null ? '—' : new Intl.NumberFormat('en-PH', { style: 'currency', currency: 'PHP' }).format(value / 100);
	const phone = $derived(booking.customer_phone?.replace(/[^\d+]/g, '') ?? '');
</script>

<div class="stack">
	<p class="row"><StatusBadge status={booking.status} /><span class="small muted">{booking.reference ?? booking.id}{booking.source === 'walk-in' ? ' · Walk-in' : ''}</span></p>
	<section class="stack" aria-label="Services">
		<h4>Services</h4>
		{#if editable && lines}
			{#await import('./ServerServiceEdits.svelte') then { default: ServiceEdits }}<ServiceEdits bookingId={booking.id} status={booking.status} lines={lines} actions={actions ?? []} pages={pages ?? []} showMoney={lines.some((line) => typeof line.price_centavos === 'number')} onupdated={updated} onreload={reload} />{/await}
		{:else if lines?.length}
			<ul>{#each lines as line}<li>{line.label} · {money(line.price_centavos)}{#if line.details}<ul>{#each line.details as detail}<li>{detail.label} · {money(detail.price_centavos)}</li>{/each}</ul>{/if}</li>{/each}</ul>
		{:else}<p>{booking.services.join(' · ')}</p>{/if}
		<p>Price <strong>{money(total)}</strong></p>
		{#if booking.status === 'done' && booking.final_price_centavos != null}<p>Final price <strong>{money(booking.final_price_centavos)}</strong></p>{/if}
	</section>
	{#if actions}{#await import('./ServerBookingChanges.svelte') then { default: Changes }}<Changes bookingId={booking.id} version={changeVersion} />{/await}{/if}
	<section class="stack" aria-label="Motorcycle and contact">
		<h4>Customer and motorcycle</h4>
		<p>{booking.plate ? booking.bike + ' · Plate ' + booking.plate : booking.bike}</p>
		<p>{booking.customer_name}{#if phone} · <a href={'tel:' + phone}>{booking.customer_phone}</a>{/if}</p>
		{#if booking.customer_email}<p><a href={'mailto:' + booking.customer_email}>{booking.customer_email}</a></p>{/if}
	</section>
	<section class="cols" aria-label="Dates in Philippine time">
		<p><strong>Visit</strong><br />{fmtDate(booking.visit_date)} · {booking.visit_hour === null ? 'Walk-in' : fmtSlot(booking.visit_hour + ':00')}</p>
		<p><strong>Booked on</strong><br />{stamp(booking.created_at)}</p>
		<p><strong>Approved</strong><br />{stamp(booking.approved_at)}</p>
		<p><strong>Completed</strong><br />{stamp(booking.completed_at)}</p>
	</section>
	{#if booking.approval_note || booking.private_completion_note || booking.shared_note || booking.shared_photos}
		<section class="stack" aria-label="Notes">
			<h4>Notes</h4>
			{#if booking.approval_note}<p><strong>Private approval note</strong>: {booking.approval_note}</p>{/if}
			{#if booking.private_completion_note}<p><strong>Private completion note</strong>: {booking.private_completion_note}</p>{/if}
			{#if booking.shared_note}<p><strong>Note shared with customer</strong>: {booking.shared_note}</p>{/if}
			{#if booking.shared_photos}<p>{booking.shared_photos} completion photos explicitly shared with customer.</p>{/if}
		</section>
	{/if}
	{#if booking.request_pending}<p class="small muted">A change request is waiting for review. The current appointment stays reserved until it is reviewed.</p>{/if}
</div>

<style>
	h4 { margin: 0; font-size: 1rem; }
	p { margin: 0; }
	ul { margin: 0; padding-left: 1.3rem; }
</style>
