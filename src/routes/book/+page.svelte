<script lang="ts">
	import { resolve } from '$app/paths';
	import { page } from '$app/state';
	import SlotPicker from '#lib/SlotPicker.svelte';
	import { peso, priceOf, serviceOf, services, shop, sizes, type Size } from '#lib/config.ts';
	import { fmtDate, fmtSlot } from '#lib/dates.ts';
	import { book, features, type Booking } from '#lib/store.svelte.ts';

	// A link from the home page or the preview can preselect the service, bike size and a note.
	const query = page.url.searchParams;
	const size = query.get('size') ?? '';

	let form = $state({
		serviceId: services.find((s) => s.id === query.get('service'))?.id ?? '',
		size: (size in sizes ? size : '') as Size,
		bike: '',
		date: '',
		slot: '',
		name: '',
		phone: '',
		email: '',
		notes: query.get('notes') ?? '',
		gcashRef: ''
	});
	let step = $state(0);
	let error = $state('');
	let done = $state<Booking>();

	const steps = $derived(['Service', 'Schedule', 'Details', ...(features().payment ? ['Downpayment'] : [])]);
	const price = $derived(form.serviceId && form.size ? priceOf(form) : 0);
	const ready = $derived(step === 0 ? price > 0 : step === 1 ? !!form.slot : true);

	function next(event: SubmitEvent) {
		event.preventDefault();
		scrollTo(0, 0);
		if (step < steps.length - 1) return void step++;
		try {
			done = book(form);
		} catch (e) {
			error = (e as Error).message;
			form.slot = '';
			step = 1;
		}
	}
</script>

<section class="section wrap stack">
	{#if done}
		<p class="eyebrow">Booking {done.id}</p>
		<h2>Slot requested</h2>
		<p class="muted">
			{features().payment
				? 'The shop will check your GCash reference number and confirm your slot.'
				: 'The shop will approve your slot shortly.'}
		</p>
		<div class="card stack">
			<p class="display big">{fmtDate(done.date)}, {fmtSlot(done.slot)}</p>
			<p>{serviceOf(done.serviceId).name} for {done.bike}</p>
			<p class="muted">
				Total {peso(priceOf(done))}{features().payment
					? `, less the ${peso(shop.downpayment)} downpayment (GCash ref ${done.gcashRef})`
					: ', paid at the shop'}
			</p>
		</div>
		{#if features().email}
			<div class="card mail stack">
				<p class="eyebrow">Email preview</p>
				<p class="small muted">To: {done.email}<br />Subject: We got your booking {done.id}</p>
				<p>
					Hi {done.name}, we received your booking for {serviceOf(done.serviceId).name} on {fmtDate(done.date)} at
					{fmtSlot(done.slot)}. We will email you again once the shop confirms it, and send a reminder the day before.
				</p>
				<p class="small muted">The shop also gets an alert at {shop.email} for every new booking.</p>
			</div>
		{/if}
		<div class="row">
			<a class="btn" href={resolve('/')}>Back to home</a>
			<a class="btn ghost" href={resolve('/admin')}>See it in the admin queue</a>
		</div>
	{:else}
		<p class="eyebrow">Step {step + 1} of {steps.length} / {steps[step]}</p>
		<h2>Book a slot</h2>
		<div class="progress" style:--done={(step + 1) / steps.length}></div>

		<form class="stack" onsubmit={next}>
			{#if step === 0}
				<p class="eyebrow">Your bike</p>
				<div class="cols">
					{#each Object.entries(sizes) as [id, label]}
						<button type="button" class="opt" class:on={form.size === id} onclick={() => (form.size = id as Size)}>
							<b>{label}</b>
						</button>
					{/each}
				</div>
				<p class="eyebrow">Service</p>
				<div class="stack tight">
					{#each services as service}
						<button type="button" class="opt service" class:on={form.serviceId === service.id} onclick={() => (form.serviceId = service.id)}>
							<b>{service.name}</b>
							<span class="display accent price">{form.size ? '' : 'from '}{peso(service.prices[form.size || 'small'])}</span>
							<span class="muted small">{service.blurb}</span>
						</button>
					{/each}
				</div>
			{:else if step === 1}
				{#if error}<p class="error">{error}</p>{/if}
				<SlotPicker bind:date={form.date} bind:slot={form.slot} />
			{:else if step === 2}
				<label>Full name <input bind:value={form.name} required autocomplete="name" /></label>
				<label>
					Mobile number
					<input bind:value={form.phone} required type="tel" inputmode="numeric" pattern="09\d{'{9}'}" placeholder="09XXXXXXXXX" title="11-digit mobile number starting with 09" />
				</label>
				<label>
					Email {features().email ? '(for your confirmation and reminder)' : '(optional)'}
					<input bind:value={form.email} required={features().email} type="email" autocomplete="email" />
				</label>
				<label>Bike make and model <input bind:value={form.bike} required placeholder="Example: Scooter 125, red" /></label>
				<label>Notes for the shop (optional) <textarea bind:value={form.notes} rows="3"></textarea></label>
			{:else}
				<div class="card stack">
					<p class="eyebrow">GCash downpayment</p>
					<p>
						Send <b class="accent">{peso(shop.downpayment)}</b> to GCash <b>{shop.gcash.number}</b>
						({shop.gcash.name}), then type the reference number from your GCash receipt below.
					</p>
					<p class="muted small">The balance of {peso(price - shop.downpayment)} is paid at the shop. Sample GCash details for this demo.</p>
				</div>
				<label>
					GCash reference number
					<input bind:value={form.gcashRef} required inputmode="numeric" pattern="\d{'{13}'}" placeholder="13 digits" title="13-digit GCash reference number" />
				</label>
			{/if}

			<div class="bar row">
				<p class="summary">
					{#if price}<b class="display accent">{peso(price)}</b>{/if}
					<span class="muted small">
						{form.serviceId ? serviceOf(form.serviceId).name : 'Pick a bike size and service'}{form.slot
							? `, ${fmtDate(form.date, { month: 'short', day: 'numeric' })} ${fmtSlot(form.slot)}`
							: ''}
					</span>
				</p>
				{#if step > 0}<button type="button" class="btn ghost sm" onclick={() => step--}>Back</button>{/if}
				<button class="btn" disabled={!ready}>{step < steps.length - 1 ? 'Next' : 'Confirm'}</button>
			</div>
		</form>
	{/if}
</section>

<style>
	.progress {
		height: 6px;
		background: linear-gradient(90deg, var(--accent) calc(var(--done) * 100%), var(--panel-2) 0);
		transform: skewX(-20deg);
	}

	.tight {
		gap: 8px;
	}

	.service {
		grid-template-columns: 1fr auto;
	}

	.service .small {
		grid-column: 1 / -1;
	}

	.price {
		font-size: 1.4rem;
	}

	.big {
		font-size: 2rem;
	}

	.mail {
		border-style: dashed;
	}

	.bar {
		flex-wrap: nowrap;
		position: sticky;
		bottom: 0;
		margin: 0 -16px;
		padding: 12px 16px;
		background: var(--panel);
		border-top: 1px solid var(--line);
	}

	.summary {
		display: grid;
		flex: 1;
	}

	.summary b {
		font-size: 1.6rem;
	}
</style>
