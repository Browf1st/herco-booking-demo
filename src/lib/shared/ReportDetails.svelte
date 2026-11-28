<!-- Styles load together with this screen (not in the page's first stylesheet). -->
<svelte:options css="injected" />
<script module lang="ts">
	import type { RecordStatus } from './records-ui';
	export type Line = { label: string; price?: string; parts?: { label: string; price?: string }[] };
	export type Detail = {
		name: string; ref: string; status: RecordStatus; walkIn: boolean; lines: Line[]; total?: string;
		/** The booking-time total, shown struck through when the shop changed the price. */
		originalTotal?: string;
		bike: string; phone?: string; email?: string; visit: string; booked: string; approved: string; completed: string;
	};
</script>

<script lang="ts">
	// The "More details" popup for one booking: a centred dialog on desktop, a bottom sheet on phones.
	// The same popup serves staff Bookings, staff Booking history, Reports and the customer's My Bookings.
	// The browser handles Esc and keeps focus inside, then returns focus to the Details button that opened it.
	// Money fields are left out of `detail` by the screen when the viewer may not see income.
	import type { Snippet } from 'svelte';
	import ActionIcon from './ActionIcon.svelte';
	import MoreIcons from './MoreIcons.svelte';
	import StatusBadge from './StatusBadge.svelte';

	// `services` (optional) replaces the plain service list with one staff can edit; `changes` adds the Changes list.
	// `variant` is 'staff' (default) or 'customer': the customer popup never shows contact rows.
	// `onEditPrice` / `onEditService` (staff only) add the top-right buttons. They only scroll to the editors; the server checks every grant.
	let { detail, onclose, actions, services, changes, variant = 'staff', inclusions, onEditPrice, onEditService }: {
		detail: Detail; onclose: () => void; actions?: Snippet; services?: Snippet; changes?: Snippet;
		variant?: 'staff' | 'customer'; inclusions?: Snippet; onEditPrice?: () => void; onEditService?: () => void;
	} = $props();
	const customer = $derived(variant === 'customer');
	const changed = $derived(Boolean(detail.originalTotal && detail.total && detail.originalTotal !== detail.total));
	let dialog = $state<HTMLDialogElement>();
	$effect(() => { if (dialog && !dialog.open) dialog.showModal(); });
	const tel = (phone: string) => 'tel:' + phone.replace(/[^\d+]/g, '');
</script>

<dialog bind:this={dialog} aria-labelledby="more-details-title" onclose={onclose} onclick={(event) => { if (event.target === dialog) dialog?.close(); }}>
	<header>
		<div><p class="eyebrow">{customer ? 'Booking details' : 'More details'}</p><h3 id="more-details-title">{customer ? 'Your booking' : 'Details for ' + detail.name}</h3></div>
		<button type="button" class="close" aria-label="Close" onclick={() => dialog?.close()}>×</button>
	</header>
	<div class="body">
		<div class="head">
			<p class="visit"><span>Visit scheduled</span><b>{detail.visit}</b></p>
			<div class="status-box">
				<div class="top"><StatusBadge status={detail.status} /><span class="ref">Ref: {detail.ref}</span>{#if detail.walkIn}<span class="walk">Walk-in</span>{/if}</div>
				{#if !customer && (onEditPrice || onEditService)}
					<div class="edit-row">
						{#if onEditPrice}<button type="button" class="edit" onclick={onEditPrice}><ActionIcon name="edit" />Edit price</button>{/if}
						{#if onEditService}<button type="button" class="edit" onclick={onEditService}><ActionIcon name="adjust" />Edit service</button>{/if}
					</div>
				{/if}
				<dl class="stamps" aria-label="Dates">
					<div><dt>Booked</dt><dd>{detail.booked}</dd></div><div><dt>Approved</dt><dd>{detail.approved}</dd></div><div><dt>Completed</dt><dd>{detail.completed}</dd></div>
				</dl>
			</div>
		</div>

		<section aria-label="Services ordered">
			<h4>Services ordered{#if detail.total}<span class="total">Total: {#if changed}<s><span class="sr-only">Original total </span>{detail.originalTotal}</s> {/if}{detail.total}</span>{/if}</h4>
			{#if services}<div id="service-editor">{@render services()}</div>
			{:else if detail.lines.length}
				<ul>{#each detail.lines as line}
					<li><span class="line"><span>{line.label}</span>{#if line.price}<b>{line.price}</b>{/if}</span>
						{#if line.parts?.length}<ul class="parts">{#each line.parts as part}<li class="line"><span>{part.label}</span>{#if part.price}<span>{part.price}</span>{/if}</li>{/each}</ul>{/if}</li>
				{/each}</ul>
			{:else}<p class="muted small">No services listed.</p>{/if}
			{#if inclusions}{@render inclusions()}{/if}
			{#if detail.total}<p class="value"><span>Price</span><b>{#if changed}<s><span class="sr-only">Original total </span>{detail.originalTotal}</s> {/if}{detail.total}</b></p>{/if}
		</section>
		{#if changes}{@render changes()}{/if}

		<section aria-label={customer ? 'Motorcycle' : 'Customer and motorcycle'}>
			<h4>{customer ? 'Motorcycle' : 'Customer & motorcycle'}</h4>
			<p class="bike"><span class="bike-icon" aria-hidden="true"><ActionIcon name="finish" /></span><span><b>{detail.bike || 'Not provided'}</b>{#if !customer}<br /><span class="muted small">Customer: {detail.name}</span>{/if}</span></p>
			{#if !customer}
				<p class="contact"><span><MoreIcons name="phone" />{detail.phone || 'No mobile'}</span>{#if detail.phone}<a class="pill call" href={tel(detail.phone)}>Call</a>{/if}</p>
				{#if detail.email}<p class="contact"><span><ActionIcon name="mail" />{detail.email}</span><a class="pill email" href={'mailto:' + encodeURIComponent(detail.email)}>Email</a></p>{/if}
			{/if}
		</section>
		{#if actions}<div class="actions">{@render actions()}</div>{/if}
	</div>
</dialog>

<style>
	dialog { box-sizing: border-box; display: none; width: min(36rem, calc(100% - 2rem)); max-height: 90dvh; margin: auto; padding: 0; border: 1px solid var(--line); border-radius: 16px; background: var(--panel); color: var(--text); overflow: hidden; box-shadow: 0 20px 50px #0006; }
	dialog[open] { display: flex; flex-direction: column; }
	dialog::backdrop { background: #0009; }
	header { display: flex; align-items: center; justify-content: space-between; gap: .75rem; padding: .9rem 1.1rem; background: light-dark(#1b2230, #0d1218); color: #fff; }
	.eyebrow { color: #fda4af; font-size: .7rem; font-weight: 800; letter-spacing: .08em; text-transform: uppercase; }
	h3 { font-size: 1.25rem; overflow-wrap: anywhere; }
	.close { display: grid; place-items: center; width: 2.5rem; height: 2.5rem; padding: 0; border: 1px solid #ffffff44; border-radius: 8px; background: #ffffff1a; color: #fff; font: 400 1.6rem/1 var(--body); cursor: pointer; }
	.close:hover { background: #ffffff2e; }
	.close:focus-visible { outline: 2px solid #fff; outline-offset: 2px; }
	.body { display: grid; gap: .85rem; padding: 1rem 1.1rem 1.1rem; overflow-y: auto; overflow-wrap: anywhere; }
	.head { display: flex; flex-wrap: wrap; align-items: flex-start; justify-content: space-between; gap: .75rem; }
	.visit { display: grid; gap: .1rem; padding: .55rem .75rem; border: 1px solid var(--line); border-radius: 10px; background: var(--panel-2); font-size: .9rem; }
	.visit span { color: var(--muted); font-size: .68rem; font-weight: 800; letter-spacing: .05em; text-transform: uppercase; }
	.status-box { display: grid; gap: .45rem; margin-inline-start: auto; justify-items: end; min-width: 0; }
	.top { display: flex; flex-wrap: wrap; align-items: center; justify-content: flex-end; gap: .5rem; }
	.edit-row { display: flex; flex-wrap: wrap; justify-content: flex-end; gap: .4rem; }
	.edit { display: inline-flex; align-items: center; gap: .35rem; min-height: 2.75rem; padding: 0 .8rem; border: 1px solid var(--bad-line); border-radius: 8px; background: var(--bad-bg); color: var(--accent); font: 700 .85rem var(--body); cursor: pointer; }
	.edit:hover { border-color: var(--accent); }
	.edit:focus-visible { outline: 2px solid var(--accent); outline-offset: 2px; }
	.stamps { display: grid; gap: .1rem; margin: 0; color: var(--muted); font-size: .72rem; text-align: end; }
	.stamps div { display: flex; flex-wrap: wrap; justify-content: flex-end; gap: .3rem; }
	.stamps dt::after { content: ':'; }
	.stamps dd { margin: 0; }
	.ref { padding: .1rem .55rem; border: 1px solid var(--line); border-radius: 6px; background: var(--panel-2); font-size: .8rem; font-weight: 700; }
	.walk { color: light-dark(#6b21a8, #d8b4fe); font-size: .8rem; font-weight: 700; }
	section { display: grid; gap: .5rem; padding: .85rem; border: 1px solid var(--line); border-radius: 12px; }
	h4 { display: flex; justify-content: space-between; gap: .5rem; margin: 0; font-size: .75rem; letter-spacing: .05em; text-transform: uppercase; }
	.total { color: var(--ok); }
	s { color: var(--muted); }
	.sr-only { position: absolute; width: 1px; height: 1px; overflow: hidden; clip-path: inset(50%); white-space: nowrap; }
	ul { display: grid; gap: .35rem; margin: 0; padding: 0; list-style: none; }
	.line { display: flex; justify-content: space-between; gap: .75rem; }
	li > .line { font-weight: 700; }
	.parts { margin: .3rem 0 0 .6rem; padding-left: .8rem; border-left: 2px solid var(--line); color: var(--muted); font-size: .85rem; }
	.value { display: flex; justify-content: space-between; padding: .6rem .8rem; border-radius: 8px; background: var(--ok-bg); color: var(--ok); font-weight: 800; }
	p { margin: 0; }
	.bike { display: flex; align-items: center; gap: .75rem; padding: .6rem; border-radius: 10px; background: var(--panel-2); }
	.bike-icon { display: grid; place-items: center; width: 2.4rem; height: 2.4rem; border-radius: 10px; background: var(--bad-bg); color: var(--accent); }
	.contact { display: flex; align-items: center; justify-content: space-between; gap: .5rem; padding: .35rem .6rem; border-radius: 8px; background: var(--panel-2); font-size: .9rem; }
	.contact span { display: inline-flex; align-items: center; gap: .5rem; min-width: 0; }
	.pill { flex: none; padding: .35rem .7rem; border-radius: 6px; font-size: .72rem; font-weight: 800; text-decoration: none; text-transform: uppercase; }
	.call { color: var(--ok); background: var(--ok-bg); }
	.email { color: var(--bad); background: var(--bad-bg); }
	.actions { display: grid; gap: .5rem; }
	@media (max-width: 640px) {
		dialog { width: 100%; max-width: none; margin: auto 0 0; border-radius: 16px 16px 0 0; }
	}
</style>
