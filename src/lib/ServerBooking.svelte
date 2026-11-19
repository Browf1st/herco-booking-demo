<script lang="ts">
	import { onMount } from 'svelte';
	import { resolve } from '$app/paths';
	import { page } from '$app/state';
	import { addDays, fmtDate, fmtSlot, today } from './dates';
	import { trackShopEvent } from './analytics';
	import { canEnhance } from './coating';
	import { wheels } from './bookingCatalog';
	import { coatingSnapshot, type CoatingDraft } from './booking-coating';
	import AppointmentCoatingFields from './AppointmentCoatingFields.svelte';
	import { displayEstimate, displayServicePrice, type PricedService } from './service-estimate';

	type Service = {
		code: string;
		label: string;
		price_centavos: number;
		max_centavos?: number | null;
		quote_required?: boolean;
		appointment_days: number[];
		promotion?: { label: string; base_price_centavos: number } | null;
	};
	type Slot = { visit_date: string; visit_hour: number; status: string };
	type Booking = { id: string; status: string; totalCentavos: number; estimateOpen?: boolean };
	type Intake = { version: string; title: string; body: string; method: 'typed_name'; date: string };
	type EstimateLine = PricedService & { code: string; label: string; promotion?: { label: string } | null };
	type Estimate = { lines: EstimateLine[]; totalCentavos: number; fingerprint: string };
	let { walkIn = false }: { walkIn?: boolean } = $props();

	let services = $state<Service[]>([]);
	let slots = $state<Slot[]>([]);
	let selected = $state<string[]>([]);
	let visitDate = $state('');
	let visitHour = $state('');
	let name = $state('');
	let phone = $state('');
	let bike = $state('');
	let plate = $state('');
	let coating = $state<CoatingDraft>({ ceramic: '', red: false, powder: [], front: '', rear: '' });
	let email = $state('');
	let intake = $state<Intake | null>(null);
	let signerName = $state('');
	let acknowledged = $state(false);
	let loading = $state(true);
	let signedOut = $state(false);
	let loadError = $state('');
	let submitting = $state(false);
	let submitError = $state('');
	let booked = $state<Booking>();
	let preview = $state<{ estimate: Estimate; selection: string; revision: number }>();
	let previewIssue = $state('');
	let previewRevision = $state(0);
	let started = false;

	const attempts = new Map<string, string>();
	const prices = new Intl.NumberFormat('en-PH', { style: 'currency', currency: 'PHP' });
	const selectedServices = $derived(services.filter((service) => selected.includes(service.code)));
	const openSlots = $derived(slots.filter((slot) => slot.status === 'open' &&
		selectedServices.every((service) => service.appointment_days.includes(
			new Date(slot.visit_date + 'T00:00:00Z').getUTCDay()
		))
	));
	const availableDates = $derived([...new Set(openSlots.map((slot) => slot.visit_date))]);
	const availableHours = $derived(openSlots.filter((slot) => slot.visit_date === visitDate));
	const intakeWeekday = $derived(intake ? new Date(intake.date + 'T00:00:00Z').getUTCDay() : null);
	const visibleServices = $derived(walkIn && intakeWeekday !== null
		? services.filter(service => service.appointment_days.some(day => day === intakeWeekday))
		: services);
	const openEstimate = $derived(selectedServices.some(service => service.quote_required ||
		(service.max_centavos != null && service.max_centavos > service.price_centavos)));
	const configured = $derived(coatingSnapshot(coating, selected));
	const configurationIssue = $derived.by(() => {
		if (configured.ceramic_finish === 'Enhance' && (!configured.red_body || !canEnhance(bike))) {
			return 'Enhance is for red Honda ADV or PCX 150/160 units.';
		}
		if (configured.powder_parts?.includes(wheels) && !configured.wheel_front && !configured.wheel_rear) {
			return 'Enter a wheel size or choose Not sure.';
		}
		return '';
	});
	const previewInput = $derived(bike.trim() && selected.length && !configurationIssue
		? JSON.stringify({ bike: bike.trim(), services: [...selected].sort(), coating: configured })
		: '');
	const currentEstimate = $derived(preview?.selection === previewInput && preview.revision === previewRevision
		? preview.estimate : undefined);

	$effect(() => {
		const selection = previewInput;
		const revision = previewRevision;
		preview = undefined;
		previewIssue = '';
		if (!selection || signedOut || booked) return;
		const controller = new AbortController();
		const timer = setTimeout(() => { void loadEstimate(selection, revision, controller.signal); }, 250);
		return () => {
			clearTimeout(timer);
			controller.abort();
		};
	});

	async function loadEstimate(selection: string, revision: number, signal: AbortSignal) {
		try {
			const response = await fetch(resolve('/api/coating-estimate'), {
				method: 'POST', signal,
				headers: { 'content-type': 'application/json', accept: 'application/json' },
				body: selection
			});
			const data = await response.json().catch(() => null);
			if (!response.ok || !Array.isArray(data?.lines) || !Number.isSafeInteger(data.totalCentavos) ||
				typeof data.fingerprint !== 'string' || !/^[a-f0-9]{32}$/.test(data.fingerprint)) {
				throw Error(typeof data?.message === 'string' ? data.message : 'Could not load the estimate. Try again.');
			}
			if (!signal.aborted) preview = { estimate: data, selection, revision };
		} catch (error) {
			if (!signal.aborted) previewIssue = error instanceof Error ? error.message : 'Could not load the estimate. Try again.';
		}
	}

	function servicePrice(service: Service) {
		if (service.quote_required) return 'Shop quote';
		const minimum = prices.format(service.price_centavos / 100);
		return service.max_centavos != null && service.max_centavos > service.price_centavos
			? minimum + '–' + prices.format(service.max_centavos / 100)
			: minimum;
	}

	async function fetchIntake(): Promise<Intake | null> {
		const response = await fetch(resolve('/api/walk-in-bookings'), { headers: { accept: 'application/json' } });
		if (!response.ok) {
			const failure = await response.json().catch(() => null);
			throw new Error(typeof failure?.message === 'string' ? failure.message : 'Could not load the walk-in form.');
		}
		return response.json();
	}

	async function availability(): Promise<Slot[]> {
		const from = today();
		const query = new URLSearchParams({ from, to: addDays(from, 20) });
		const response = await fetch(resolve('/api/availability') + '?' + query);
		if (!response.ok) throw new Error('Could not load available visits. Try again.');
		return response.json();
	}

	async function load() {
		loading = true;
		signedOut = false;
		loadError = '';
		try {
			const session = await fetch(resolve('/api/auth/session'));
			if (session.status === 401) {
				signedOut = true;
				return;
			}
			if (!session.ok) throw new Error('Could not check your sign-in. Try again.');

			const [catalog, freshSlots, approvedForm] = await Promise.all([
				fetch(resolve('/api/catalog')),
				walkIn ? Promise.resolve([]) : availability(),
				walkIn ? fetchIntake() : Promise.resolve(null)
			]);
			if (!catalog.ok) throw new Error('Could not load services. Try again.');
			email = (await session.json()).email ?? '';
			services = await catalog.json();
			slots = freshSlots;
			intake = approvedForm;
			void fetch(resolve('/api/auth/contact')).then(async response => {
				if (!response.ok) return;
				const contact = await response.json();
				if (!name) name = contact.name;
				if (!phone) phone = contact.mobile;
			}).catch(() => {});
			if (!started && visibleServices.length && (!walkIn || intake)) {
				started = true;
				trackShopEvent('booking_started');
			}
			const suggestedDate = page.url.searchParams.get('date');
			if (!visitDate && suggestedDate && availableDates.includes(suggestedDate)) visitDate = suggestedDate;
		} catch (failure) {
			loadError = failure instanceof Error ? failure.message : 'Could not load booking.';
		} finally {
			loading = false;
		}
	}

	function chooseService(code: string, checked: boolean) {
		selected = checked ? [...selected, code] : selected.filter((item) => item !== code);
		if (checked) trackShopEvent('service_selected');
		if (!availableDates.includes(visitDate)) visitDate = '';
		if (!availableHours.some((slot) => String(slot.visit_hour) === visitHour)) visitHour = '';
	}

	async function submit(event: SubmitEvent) {
		event.preventDefault();
		if (submitting || !selected.length || (walkIn ? !intake || !acknowledged : !visitDate || !visitHour)) return;
		const estimate = currentEstimate;
		if (!estimate) return;
		submitting = true;
		submitError = '';
		try {
			const payload = {
				...(walkIn && intake ? { date: intake.date, formVersion: intake.version, signerName: signerName.trim(), acknowledged }
					: { date: visitDate, hour: Number(visitHour) }),
				services: [...selected].sort(),
				bike: bike.trim(), name: name.trim(), phone: phone.trim(), plate: plate.trim(),
				coating: configured
			};
			const fingerprint = JSON.stringify(payload);
			const requestId = attempts.get(fingerprint) ?? crypto.randomUUID();
			attempts.set(fingerprint, requestId);

			const response = await fetch(resolve(walkIn ? '/api/walk-in-bookings' : '/api/bookings'), {
				method: 'POST',
				headers: { 'content-type': 'application/json', accept: 'application/json' },
				body: JSON.stringify({ ...payload, requestId, priceFingerprint: estimate.fingerprint })
			});
			if (response.ok) {
				booked = await response.json();
				trackShopEvent('booking_submitted');
				return;
			}
			if (response.status === 401) signedOut = true;
			const errorBody = await response.json().catch(() => null);
			submitError = errorBody?.message ?? 'Could not submit your booking. Try again with the same details.';
			if (response.status === 409 && errorBody?.code === 'price_changed') {
				previewRevision += 1;
				return;
			}
			if (response.status === 409) {
				if (walkIn) {
					intake = await fetchIntake().catch(() => intake);
					signerName = '';
					acknowledged = false;
					selected = selected.filter(code => visibleServices.some(service => service.code === code));
				} else {
					slots = await availability().catch(() => slots);
					visitHour = '';
					if (!availableDates.includes(visitDate)) visitDate = '';
				}
			}
		} catch {
			submitError = 'Could not confirm your booking. Retry with the same details or check My Bookings.';
		} finally {
			submitting = false;
		}
	}

	onMount(() => { void load(); });
</script>

<svelte:head><title>{walkIn ? 'Walk in today' : 'Book a visit'} | HERCO</title></svelte:head>
<section class="section wrap stack">
	<h1>{walkIn ? 'Walk in today' : 'Book a visit'}</h1>
	{#if !booked}
		<div><a class="btn sm ghost" href={resolve(walkIn ? '/book' : '/walk-in')}>{walkIn ? 'Schedule a visit' : 'Already at the shop? Walk in today'}</a></div>
	{/if}
	{#if loading}
		<p role="status">Loading booking options…</p>
	{:else if signedOut}
		<p>Sign in to submit a booking and view it on any device.</p>
		<div><a class="btn" href={resolve('/account')}>Sign in</a></div>
	{:else if loadError}
		<p role="alert">{loadError}</p>
		<div><button class="btn ghost" type="button" onclick={load}>Try again</button></div>
	{:else if booked}
		<div class="card stack" role="status">
			<h2>{walkIn ? 'Walk-in submitted' : 'Booking submitted'}</h2>
			<p>The shop will review your request. Booking reference: <strong>{booked.id}</strong></p>
			{#if booked.estimateOpen ?? openEstimate}
				<p>The shop will confirm the final service price.</p>
			{:else}
				<p>Service total: {prices.format(booked.totalCentavos / 100)}</p>
			{/if}
			<div><a class="btn" href={resolve('/my-bookings')}>View My Bookings</a></div>
		</div>
	{:else if walkIn && !intake}
		<p>Walk-in booking is unavailable while the shop sets up its intake form.</p>
	{:else if !visibleServices.length}
		<p>{walkIn ? 'No services are listed for walk-in booking today.' : 'Online booking is unavailable while the shop sets up its services.'}</p>
	{:else}
		<form class="card stack" onsubmit={submit}>
			<fieldset disabled={submitting}>
				<legend>Choose your services</legend>
				<p class="small muted">These are catalog prices. Your estimate appears below after you enter your bike and coating details.</p>
				{#each visibleServices as service (service.code)}
					<label class="service-option">
						<input type="checkbox" checked={selected.includes(service.code)}
							onchange={(event) => chooseService(service.code, event.currentTarget.checked)} />
						<span>
							{service.label}
							{#if service.promotion}<small class="muted">{service.promotion.label}</small>{/if}
						</span>
						<span class="service-price">
							<strong>{servicePrice(service)}</strong>
							{#if service.promotion && !service.quote_required}
								<small class="muted">Regular {prices.format(service.promotion.base_price_centavos / 100)}</small>
							{/if}
						</span>
					</label>
				{/each}
			</fieldset>
			{#if selected.includes('ceramic') || selected.includes('wheel-colour')}
				<AppointmentCoatingFields bind:options={coating} ceramic={selected.includes('ceramic')}
					powder={selected.includes('wheel-colour')} disabled={submitting} />
			{/if}
			{#if walkIn && intake}
				<p><strong>Walk-in for {fmtDate(intake.date)}.</strong> Use this form when you’re at the shop. Staff will review your intake before service starts.</p>
			{:else}
			<fieldset disabled={submitting}>
				<legend>Choose a visit</legend>
				<p class="small muted">Times are shown in Philippine time.</p>
				<div class="cols">
					<label>Visit date
						<select bind:value={visitDate} required disabled={!selected.length}
							onchange={() => { visitHour = ''; }}>
							<option value="">Select a date</option>
							{#each availableDates as date (date)}
								<option value={date}>{fmtDate(date)}</option>
							{/each}
						</select>
					</label>
					<label>Visit time
						<select bind:value={visitHour} required disabled={!visitDate}>
							<option value="">Select a time</option>
							{#each availableHours as slot (slot.visit_hour)}
								<option value={String(slot.visit_hour)}>{fmtSlot(slot.visit_hour + ':00')}</option>
							{/each}
						</select>
					</label>
				</div>
				{#if selected.length && !availableDates.length}
					<p>No available visits for this selection in the next 21 days.</p>
				{/if}
			</fieldset>
			{/if}
			<fieldset disabled={submitting}>
				<legend>Your details</legend>
				{#if email}<p class="small muted">Booking email: {email}</p>{/if}
				<div class="cols">
					<label>Full name<input bind:value={name} autocomplete="name" maxlength="120" required /></label>
					<label>Mobile number<input bind:value={phone} type="tel" autocomplete="tel" minlength="3" maxlength="40" required /></label>
					<label>Bike model<input bind:value={bike} maxlength="120" required /></label>
					<label>Plate number (optional)<input bind:value={plate} maxlength="30" /></label>
				</div>
			</fieldset>
			{#if walkIn && intake}
				<fieldset class="stack" disabled={submitting}>
					<legend>{intake.title}</legend>
					<p class="small muted">Form version {intake.version}</p>
					<p class="intake-text">{intake.body}</p>
					<label class="service-option"><input type="checkbox" bind:checked={acknowledged} required />
						<span>I read and agree to the form above.</span></label>
					<label>Type your full name to sign<input bind:value={signerName} maxlength="120" autocomplete="off" required /></label>
				</fieldset>
			{/if}
			<section class="card stack estimate-panel" aria-labelledby="estimate-heading">
				<h2 id="estimate-heading">Booking estimate</h2>
				{#if configurationIssue && bike.trim()}
					<p class="error">{configurationIssue}</p>
				{:else if currentEstimate}
					<p role="status">Estimated total · <strong>{displayEstimate(currentEstimate.lines, currentEstimate.totalCentavos)}</strong></p>
					<ul>
						{#each currentEstimate.lines as line (line.code)}
							<li>{line.label} · {displayServicePrice(line)}
								{#if line.promotion}<small class="muted">({line.promotion.label})</small>{/if}
							</li>
						{/each}
					</ul>
				{:else if previewIssue}
					<p role="alert">{previewIssue}</p>
					<div><button class="btn sm ghost" type="button" onclick={() => { previewRevision += 1; }}>Retry estimate</button></div>
				{:else if previewInput}
					<p role="status">Updating your estimate…</p>
				{:else}
					<p class="muted">Choose a service and enter your bike model to see the estimate.</p>
				{/if}
			</section>
			{#if submitError}<p role="alert">{submitError}</p>{/if}
			<div class="row">
				<button class="btn" type="submit"
					disabled={submitting || !currentEstimate || (walkIn ? !acknowledged || !signerName.trim() : !visitHour)}>
					{submitting ? 'Submitting…' : walkIn ? 'Sign and submit walk-in' : 'Submit booking'}
				</button>
				<a href={resolve('/my-bookings')}>My Bookings</a>
			</div>
		</form>
	{/if}
</section>

<style>
	fieldset { border: 1px solid var(--line); border-radius: 8px; min-width: 0; }
	legend { font-weight: 700; }
	.service-option { display: grid; grid-template-columns: auto 1fr auto; align-items: center; gap: .6rem; padding: .45rem 0; }
	.service-option small { display: block; }
	.service-price { text-align: end; }
	.intake-text { white-space: pre-wrap; overflow-wrap: anywhere; }
	.estimate-panel h2 { font-size: 1.55rem; }
</style>
