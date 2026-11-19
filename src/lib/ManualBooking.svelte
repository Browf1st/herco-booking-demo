<script lang="ts">
	import { resolve } from '$app/paths';
	import { addDays, fmtDate, fmtSlot, today } from '#lib/dates.ts';

	type Customer = { id: string; email: string };
	type Service = {
		code: string; label: string; price_centavos: number; appointment_days: number[];
		promotion?: { label: string; base_price_centavos: number } | null;
	};
	type Slot = { visit_date: string; visit_hour: number; status: string };
	type Booking = { id: string; status: string; totalCentavos: number };
	const price = new Intl.NumberFormat('en-PH', { style: 'currency', currency: 'PHP' });
	const attempts = new Map<string, string>();
	let email = $state('');
	let customer = $state<Customer>();
	let catalog = $state<Service[]>([]);
	let slots = $state<Slot[]>([]);
	let selected = $state<string[]>([]);
	let date = $state('');
	let hour = $state('');
	let name = $state('');
	let phone = $state('');
	let bike = $state('');
	let plate = $state('');
	let booking = $state<Booking>();
	let busy = $state(false);
	let needsAccount = $state(false);
	let message = $state('');

	const selectedServices = $derived(catalog.filter(service => selected.includes(service.code)));
	const openSlots = $derived(slots.filter(slot => slot.status === 'open' && selectedServices.every(service =>
		service.appointment_days.includes(new Date(slot.visit_date + 'T00:00:00Z').getUTCDay()))));
	const availableDates = $derived([...new Set(openSlots.map(slot => slot.visit_date))]);
	const availableHours = $derived(openSlots.filter(slot => slot.visit_date === date));

	async function loadAvailability() {
		const from = today();
		const query = new URLSearchParams({ from, to: addDays(from, 20) });
		const response = await fetch(resolve('/api/availability') + '?' + query);
		if (!response.ok) throw new Error('Could not load available visits.');
		slots = await response.json();
	}

	async function send(body: Record<string, unknown>) {
		const response = await fetch(resolve('/api/staff/manual-booking'), {
			method: 'POST',
			headers: { 'content-type': 'application/json', accept: 'application/json' },
			body: JSON.stringify(body)
		});
		if (response.status === 401 || response.status === 428) needsAccount = true;
		return response;
	}

	async function failureMessage(response: Response) {
		const failure = await response.json().catch(() => null);
		return typeof failure?.message === 'string' ? failure.message : 'Could not complete the request. Try again.';
	}

	async function lookup(event: SubmitEvent) {
		event.preventDefault();
		if (busy) return;
		busy = true;
		message = '';
		needsAccount = false;
		try {
			const response = await send({ action: 'lookup', email: email.trim() });
			if (!response.ok) throw new Error(await failureMessage(response));
			const [matched, services] = await Promise.all([
				response.json(), fetch(resolve('/api/catalog')), loadAvailability()
			]);
			if (!services.ok) throw new Error('Could not load services.');
			catalog = await services.json();
			customer = matched;
		} catch (failure) {
			message = failure instanceof Error ? failure.message : 'Could not check the customer’s account.';
		} finally {
			busy = false;
		}
	}

	function changeCustomer() {
		customer = booking = undefined;
		email = date = hour = name = phone = bike = plate = message = '';
		selected = [];
	}

	function selectService(code: string, checked: boolean) {
		selected = checked ? [...selected, code] : selected.filter(item => item !== code);
		if (!availableDates.includes(date)) date = '';
		if (!availableHours.some(slot => String(slot.visit_hour) === hour)) hour = '';
	}

	async function submit(event: SubmitEvent) {
		event.preventDefault();
		if (busy || !customer || !selected.length || !date || !hour) return;
		busy = true;
		message = '';
		needsAccount = false;
		try {
			const payload = {
				action: 'book', customerId: customer.id, email: customer.email,
				date, hour: Number(hour), services: [...selected].sort(), name: name.trim(),
				phone: phone.trim(), bike: bike.trim(), plate: plate.trim()
			};
			const fingerprint = JSON.stringify(payload);
			const requestId = attempts.get(fingerprint) ?? crypto.randomUUID();
			attempts.set(fingerprint, requestId);
			const response = await send({ ...payload, requestId });
			if (response.status === 409) {
				hour = '';
				await loadAvailability().catch(() => {});
				if (!availableDates.includes(date)) date = '';
			}
			if (response.status === 404) changeCustomer();
			if (!response.ok) throw new Error(await failureMessage(response));
			booking = await response.json();
		} catch (failure) {
			message = failure instanceof Error ? failure.message : 'Could not save the booking. Try again with the same details.';
		} finally {
			busy = false;
		}
	}
</script>

<svelte:head><title>Manual booking | HERCO</title></svelte:head>
<section class="section wrap stack">
	<div><a class="btn sm ghost" href={resolve('/admin')}>Back to staff bookings</a></div>
	<h1>Book for a customer</h1>
	{#if booking}
		<article class="card stack" role="status">
			<h2>Booking submitted</h2>
			<p>Reference <strong>{booking.id}</strong></p>
			<p>Service total {price.format(booking.totalCentavos / 100)}. This booking is pending confirmation.</p>
			<div><button class="btn sm ghost" onclick={changeCustomer}>Book for another customer</button></div>
		</article>
	{:else if !customer}
		<form class="card stack" onsubmit={lookup}>
			<p>Enter the exact email the customer verified with HERCO.</p>
			<label>Customer email<input required type="email" bind:value={email} maxlength="254" disabled={busy} /></label>
			<div><button class="btn sm" disabled={busy}>{busy ? 'Checking…' : 'Find verified account'}</button></div>
		</form>
	{:else}
		<div class="row">
			<p>Verified account <strong>{customer.email}</strong></p>
			<button class="btn sm ghost" disabled={busy} onclick={changeCustomer}>Change customer</button>
		</div>
		{#if !catalog.length}
			<p>Manual booking is unavailable until the shop enables a service.</p>
		{:else}
			<form class="card stack" onsubmit={submit}>
				<fieldset class="stack" disabled={busy}>
					<legend>Services</legend>
					{#each catalog as service (service.code)}
						<label class="option"><input type="checkbox" checked={selected.includes(service.code)}
							onchange={(event) => selectService(service.code, event.currentTarget.checked)} />
							<span>{service.label} · {price.format(service.price_centavos / 100)}
								{#if service.promotion}
									<small>{service.promotion.label} · was {price.format(service.promotion.base_price_centavos / 100)}</small>
								{/if}
							</span>
						</label>
					{/each}
				</fieldset>
				<div class="cols">
					<label>Visit date<select bind:value={date} required disabled={busy} onchange={() => { hour = ''; }}>
						<option value="">Choose date</option>
						{#each availableDates as day}<option value={day}>{fmtDate(day)}</option>{/each}
					</select></label>
					<label>Visit time<select bind:value={hour} disabled={!date || busy} required>
						<option value="">Choose time</option>
						{#each availableHours as slot (slot.visit_hour)}<option value={String(slot.visit_hour)}>{fmtSlot(slot.visit_hour + ':00')}</option>{/each}
					</select></label>
				</div>
				<p class="small muted">Visit times are in Philippine time.</p>
				<div class="cols">
					<label>Customer name<input bind:value={name} maxlength="120" disabled={busy} required /></label>
					<label>Customer mobile number<input type="tel" bind:value={phone} minlength="3" maxlength="40" disabled={busy} required /></label>
					<label>Bike model<input bind:value={bike} maxlength="120" disabled={busy} required /></label>
					<label>Plate number (optional)<input bind:value={plate} maxlength="30" disabled={busy} /></label>
				</div>
				<div><button class="btn sm" disabled={busy || !selected.length || !date || !hour}>{busy ? 'Submitting…' : 'Submit booking'}</button></div>
			</form>
		{/if}
	{/if}
	<p class="small muted">Walk-in intake requires the approved shop form. Use this page for scheduled visits.</p>
	{#if message}<p role="alert">{message}</p>{/if}
	{#if needsAccount}<div><a class="btn sm" href={resolve('/account')}>Go to Account</a></div>{/if}
</section>

<style>
	.option { display: flex; align-items: center; gap: .5rem; }
	.option input { width: auto; }
</style>
