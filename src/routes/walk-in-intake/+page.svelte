<script lang="ts">
	import { onMount } from 'svelte';
	import { resolve } from '$app/paths';
	import { page } from '$app/state';
	import { fmtDate, fmtSlot } from '#lib/shared/dates.ts';

	type Intake = {
		bookingId: string; customerName: string; bike: string; date: string; hour: number | null;
		state: 'closed' | 'unavailable' | 'awaiting_request' | 'awaiting_signature' | 'signed';
		staff: boolean; canRequest: boolean; canSign: boolean; signedAt: string | null; signerName: string | null;
		form: { version: string; title: string; body: string; method: 'typed_name' } | null;
	};
	const api = resolve('/api/walk-in-intake');
	const dateAndTime = new Intl.DateTimeFormat('en-PH', {
		dateStyle: 'medium', timeStyle: 'short', timeZone: 'Asia/Manila'
	});
	let reference = $state('');
	let intake = $state<Intake>();
	let signerName = $state('');
	let accepted = $state(false);
	let busy = $state(false);
	let authRequired = $state(false);
	let message = $state('');
	let notice = $state('');

	async function responseMessage(response: Response) {
		const data = await response.json().catch(() => null);
		return typeof data?.message === 'string' ? data.message : 'Walk-in intake is temporarily unavailable. Try again.';
	}

	async function load() {
		authRequired = false;
		const query = new URLSearchParams({ booking: reference.trim() });
		const response = await fetch(api + '?' + query, { headers: { accept: 'application/json' } });
		if (!response.ok) {
			intake = undefined;
			authRequired = response.status === 401 || response.status === 403;
			throw new Error(await responseMessage(response));
		}
		intake = await response.json();
	}

	async function run(task: () => Promise<void>) {
		if (busy) return;
		busy = true;
		message = notice = '';
		try {
			await task();
		} catch (failure) {
			message = failure instanceof Error && failure.name !== 'TypeError'
				? failure.message : 'Could not reach the intake service. Try again.';
		} finally {
			busy = false;
		}
	}

	function openBooking(event: SubmitEvent) {
		event.preventDefault();
		signerName = '';
		accepted = false;
		void run(load);
	}

	function submit(action: 'request' | 'sign') {
		if (!intake?.form) return Promise.resolve();
		const payload = {
			action, bookingId: intake.bookingId, formVersion: intake.form.version,
			...(action === 'sign' ? { name: signerName.trim(), acknowledged: accepted } : {})
		};
		return run(async () => {
			const response = await fetch(api, {
				method: 'POST', headers: { accept: 'application/json', 'content-type': 'application/json' },
				body: JSON.stringify(payload)
			});
			if (!response.ok) {
				authRequired = response.status === 401 || response.status === 403;
				if (authRequired) intake = undefined;
				throw new Error(await responseMessage(response));
			}
			signerName = '';
			accepted = false;
			reference = payload.bookingId;
			await load();
			notice = action === 'request' ? 'Intake opened for this customer.' : 'Your signed intake was saved.';
		});
	}

	function customerLink(bookingId: string) {
		const url = new URL(resolve('/walk-in-intake'), page.url.href);
		url.searchParams.set('booking', bookingId);
		return url.href;
	}

	async function copyCustomerLink() {
		if (!intake) return;
		try {
			await navigator.clipboard.writeText(customerLink(intake.bookingId));
			notice = 'Customer link copied.';
		} catch {
			notice = 'Select and copy the customer link in the address field.';
		}
	}

	onMount(() => {

		reference = page.url.searchParams.get('booking') ?? '';
		if (reference) void run(load);
	});
</script>

<svelte:head><title>Walk-in intake | HERCO</title></svelte:head>
<section class="wrap section stack">
	<h1>Walk-in intake</h1>

		<form class="card stack" onsubmit={openBooking}>
			<label>Booking reference <input bind:value={reference} maxlength="36" required disabled={busy} /></label>
			<div><button class="btn ghost" type="submit" disabled={busy}>{busy ? 'Checking…' : 'Open intake'}</button></div>
		</form>
		{#if message}<p role="alert">{message}</p>{/if}
		{#if notice}<p role="status">{notice}</p>{/if}
		{#if authRequired}
			<div class="row">
				<a class="btn" href={resolve('/account')} target="_blank" rel="noopener">Sign in or verify your account in a new tab</a>
				<button class="btn ghost" type="button" onclick={() => run(load)} disabled={busy}>Try again</button>
			</div>
		{/if}
		{#if intake}
			<section class="card stack" aria-label="Booking intake">
				<h2>{intake.bike}</h2>
				<p>{intake.hour === null ? 'Walk-in' : 'Booking'} for <strong>{intake.customerName}</strong> on {fmtDate(intake.date)}{intake.hour === null ? '' : ' at ' + fmtSlot(intake.hour + ':00')}.</p>
				{#if intake.state === 'unavailable'}
					<p>The shop has no approved intake form configured.</p>
				{:else if intake.state === 'closed'}
					<p>This booking no longer accepts intake forms.</p>
				{:else if intake.state === 'awaiting_request' && !intake.canRequest}
					<p>The shop needs to open your intake before you can sign.</p>
				{:else if intake.form}
					<h3>{intake.form.title}</h3>
					<p class="muted small">Form version {intake.form.version}</p>
					<p class="form-copy">{intake.form.body}</p>
					{#if intake.canRequest}
						<div><button class="btn" type="button" disabled={busy} onclick={() => submit('request')}>Open intake for customer</button></div>
					{:else if intake.state === 'signed'}
						<p><strong>Signed</strong>{intake.signerName ? ' by ' + intake.signerName : ''} on {intake.signedAt ? dateAndTime.format(new Date(intake.signedAt)) : ''}.</p>
					{:else if intake.canSign}
						<form class="stack" onsubmit={event => { event.preventDefault(); void submit('sign'); }}>
							<label class="acknowledgement">
								<input type="checkbox" bind:checked={accepted} required disabled={busy} />
								I reviewed this intake form and acknowledge it by typing my name.
							</label>
							<label>Full name on your booking <input bind:value={signerName} maxlength="120" autocomplete="name" required disabled={busy} /></label>
							<div><button class="btn" type="submit" disabled={busy}>Sign intake form</button></div>
						</form>
					{:else if intake.staff}
						<p>Waiting for the customer to sign with their verified HERCO account.</p>
						<label>Customer intake link <input readonly value={customerLink(intake.bookingId)} /></label>
						<div><button class="btn ghost" type="button" onclick={copyCustomerLink}>Copy customer link</button></div>
					{/if}
				{/if}
			</section>
		{/if}

</section>

<style>
	h2 { font-size: 1.5rem; overflow-wrap: anywhere; }
	.form-copy { white-space: pre-wrap; overflow-wrap: anywhere; padding: 1rem; border: 1px solid var(--line); }
	.acknowledgement { display: flex; align-items: start; gap: .5rem; }
	.acknowledgement input { margin-block-start: .25rem; inline-size: auto; }
</style>
