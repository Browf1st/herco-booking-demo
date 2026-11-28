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
	<div class="head">
		<p class="visit"><span>Visit scheduled</span><b>{fmtDate(booking.visit_date)} · {booking.visit_hour === null ? 'Walk-in' : fmtSlot(booking.visit_hour + ':00')}</b></p>
		<div class="status-box">
			<p class="top"><StatusBadge status={booking.status} /><span class="ref">Ref: {booking.reference ?? booking.id}</span>{#if booking.source === 'walk-in'}<span class="walk">Walk-in</span>{/if}</p>
			<dl class="stamps" aria-label="Dates"><div><dt>Booked</dt><dd>{stamp(booking.created_at)}</dd></div><div><dt>Approved</dt><dd>{stamp(booking.approved_at)}</dd></div><div><dt>Completed</dt><dd>{stamp(booking.completed_at)}</dd></div></dl>
		</div>
	</div>
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
	{#if booking.approval_note || booking.private_completion_note || booking.shared_note || booking.shared_photos}
		<section class="stack" aria-label="Notes">
			<h4>Notes</h4>
			{#if booking.approval_note}<p><strong>Private approval note</strong>{booking.approval_note}</p>{/if}
			{#if booking.private_completion_note}<p><strong>Private completion note</strong>{booking.private_completion_note}</p>{/if}
			{#if booking.shared_note}<p><strong>Note shared with customer</strong>{booking.shared_note}</p>{/if}
			{#if booking.shared_photos}<p>{booking.shared_photos} completion photos explicitly shared with customer.</p>{/if}
		</section>
	{/if}
	{#if booking.request_pending}<p class="small muted">A change request is waiting for review. The current appointment stays reserved until it is reviewed.</p>{/if}
</div>

<style>
	h4 { margin: 0; font-size: 1rem; }
	p { margin: 0; }
	ul { margin: 0; padding-left: 1.3rem; }
	.head { display: flex; flex-wrap: wrap; align-items: flex-start; justify-content: space-between; gap: .75rem; }
	.visit { display: grid; gap: .1rem; padding: .55rem .75rem; border: 1px solid var(--line); border-radius: 10px; background: var(--panel-2); font-size: .9rem; }
	.visit span { color: var(--muted); font-size: .68rem; font-weight: 800; letter-spacing: .05em; text-transform: uppercase; }
	.status-box { display: grid; gap: .35rem; margin-inline-start: auto; justify-items: end; }
	.top { display: flex; flex-wrap: wrap; align-items: center; justify-content: flex-end; gap: .5rem; }
	.ref { padding: .1rem .55rem; border: 1px solid var(--line); border-radius: 6px; background: var(--panel-2); font-size: .8rem; font-weight: 700; }
	.walk { color: light-dark(#6b21a8, #d8b4fe); font-size: .8rem; font-weight: 700; }
	section[aria-label="Notes"] strong { display: block; color: var(--muted); font-size: .72rem; letter-spacing: .05em; text-transform: uppercase; }
	.stamps { display: grid; gap: .1rem; margin: 0; color: var(--muted); font-size: .72rem; text-align: end; }
	.stamps div { display: flex; flex-wrap: wrap; justify-content: flex-end; gap: .3rem; }
	.stamps dt::after { content: ':'; }
	.stamps dd { margin: 0; }
</style>
