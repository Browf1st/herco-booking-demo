<script lang="ts">
	import { onMount } from 'svelte';
	import { resolve } from '$app/paths';
	import CoatingRuleEditor from '#lib/live/CoatingRuleEditor.svelte';
	import PageHeader from '#lib/shared/PageHeader.svelte';
 import ServerCatalogPricing from '#lib/live/ServerCatalogPricing.svelte';

	type Setting = { code: string; label: string; enabled: boolean; revision: number };
	type Service = Setting & { price_centavos: number; appointment_days: number[]; max_centavos?: number | null; quote_required?: boolean };
	type Promotion = Setting & { discount_basis_points: number };
	type Pricing = { canEditServices: boolean; canEditPromotion: boolean; services: Service[]; promotion: Promotion };
	type ServiceDraft = Setting & { pesos?: number; maximum?: number; quoteRequired?: boolean; days: number[] };
	type PromotionDraft = Setting & { percent?: number };
	const days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
	const money = new Intl.NumberFormat('en-PH', { style: 'currency', currency: 'PHP' });
	const attempts = new Map<string, string>();
	let pricing = $state<Pricing>();
	let draft = $state<ServiceDraft>();
	let promotionDraft = $state<PromotionDraft>();
	let loading = $state(true);
	let busy = $state(false);
	let failure = $state('');
	let notice = $state('');
	let stale = $state(false);

	function loadPromotion(promotion: Promotion) {
		const { discount_basis_points, ...setting } = promotion;
		promotionDraft = { ...setting, percent: discount_basis_points / 100 };
	}

	function edit(service?: Service) {
		draft = service ? {
			code: service.code, label: service.label, enabled: service.enabled, revision: service.revision,
			pesos: service.price_centavos / 100, days: [...service.appointment_days],
			maximum: service.max_centavos == null ? undefined : service.max_centavos / 100, quoteRequired: service.quote_required
		} : { code: '', label: '', enabled: false, revision: 0, days: [0, 1, 2, 3, 4, 5, 6] };
		failure = notice = '';
	}

	async function load() {
		loading = true;
		failure = '';
		try {
			const response = await fetch(resolve('/api/pricing'));
			if (response.status === 403) throw new Error('Pricing requires staff permission.');
			if (!response.ok) throw new Error('Pricing is temporarily unavailable.');
			pricing = await response.json() as Pricing;
			loadPromotion(pricing.promotion);
			draft = undefined;
			stale = false;
		} catch (err) {
			pricing = undefined;
			promotionDraft = undefined;
			draft = undefined;
			failure = err instanceof Error ? err.message : 'Pricing is temporarily unavailable.';
		} finally {
			loading = false;
		}
	}

	async function write(input: { operation: 'service' | 'promotion' } & Setting & Record<string, unknown>) {
		if (busy || stale) return;
		busy = true;
		failure = notice = '';
		const fingerprint = JSON.stringify(input);
		const requestId = attempts.get(fingerprint) ?? crypto.randomUUID();
		attempts.set(fingerprint, requestId);
		try {
			const response = await fetch(resolve('/api/pricing'), {
				method: 'POST',
				headers: { 'content-type': 'application/json', accept: 'application/json' },
				body: JSON.stringify({ requestId, ...input })
			});
			if (!response.ok) {
				stale = response.status === 409;
				const detail = await response.json().catch(() => null);
				throw new Error(detail?.message ?? 'The save could not be confirmed. Retry the same change.');
			}
			attempts.delete(fingerprint);
			if (input.operation === 'service') draft = undefined;
			await load();
			notice = failure ? 'Pricing was saved. Reload to see the latest settings.' : 'Pricing settings saved.';
		} catch (err) {
			failure = err instanceof Error ? err.message : 'The save could not be confirmed. Retry the same change.';
		} finally {
			busy = false;
		}
	}

	function saveService(event: SubmitEvent) {
		event.preventDefault();
		if (!draft || (!draft.quoteRequired && draft.pesos === undefined) || !draft.days.length) return;
		const { pesos, days, maximum, quoteRequired, ...setting } = draft;
		void write({ ...setting, days: [...days].sort(), operation: 'service', quoteRequired: !!quoteRequired,
			priceCentavos: quoteRequired ? 0 : Math.round((pesos ?? 0) * 100),
			maxCentavos: quoteRequired || maximum === undefined ? null : Math.round(maximum * 100) });
	}

	function savePromotion(event: SubmitEvent) {
		event.preventDefault();
		if (!promotionDraft || promotionDraft.percent === undefined) return;
		const { percent, ...setting } = promotionDraft;
		void write({ ...setting, enabled: percent > 0, operation: 'promotion', discountBps: Math.round(percent * 100) });
	}

	onMount(() => { void load(); });
</script>

<svelte:head><title>Staff pricing | HERCO</title></svelte:head>
<section class="section wrap stack">
	<PageHeader title="Pricing" subtitle="Service prices, coating price rules and booking promotions." />
	{#if loading}
		<p role="status">Loading pricing…</p>
	{:else if pricing}
		<p>Changes apply to new bookings. Saved bookings keep their original prices.</p>
		<ServerCatalogPricing />
<details class="card stack"><summary>Service availability and advanced catalog settings</summary><section class="stack" aria-labelledby="catalog-heading">
			<div class="row between">
				<h2 id="catalog-heading">Services</h2>
				{#if pricing.canEditServices}<button type="button" class="btn sm" onclick={() => edit()}>Add service</button>{/if}
			</div>
			{#if draft}
				<form class="card stack" onsubmit={saveService}>
					<h3>{draft.revision ? 'Edit service' : 'Add service'}</h3>
					<fieldset class="stack" disabled={busy || stale}>
						<label>Service code <input bind:value={draft.code} pattern="[a-z0-9][a-z0-9\-]*" maxlength="64" readonly={draft.revision > 0} required /></label>
						<label>Customer-facing label <input bind:value={draft.label} maxlength="120" required /></label>
						<label><input type="checkbox" bind:checked={draft.quoteRequired} /> Shop quote required</label>
						{#if !draft.quoteRequired}
							<label>Base or minimum price (₱) <input type="number" bind:value={draft.pesos} min="0" max="21474836.47" step="0.01" required /></label>
							<label>Maximum price (₱, optional) <input type="number" bind:value={draft.maximum} min="0" max="21474836.47" step="0.01" /></label>
						{/if}
						<fieldset class="row checks">
							<legend>Appointment days</legend>
							{#each days as day, value (day)}
								<label><input type="checkbox" value={value} bind:group={draft.days} /> {day}</label>
							{/each}
						</fieldset>
						<label class="check"><input type="checkbox" bind:checked={draft.enabled} /> Available for new bookings</label>
					</fieldset>
					<div class="row">
						<button class="btn sm" type="submit" disabled={busy || stale || !draft.days.length}>Save service</button>
						<button class="btn sm ghost" type="button" disabled={busy} onclick={() => draft = undefined}>Cancel</button>
					</div>
				</form>
			{/if}
			{#each pricing.services as service (service.code)}
				<article class="service row between">
					<div>
						<strong>{service.label}</strong>
						<p>{service.quote_required ? 'Shop quote required' : money.format(service.price_centavos / 100) +
							(service.max_centavos == null ? '' : '–' + money.format(service.max_centavos / 100))} ·
							{service.enabled ? 'Available' : 'Disabled'} · {service.appointment_days.map(day => days[day]).join(', ')}</p>
					</div>
					{#if pricing.canEditServices}
						<button class="btn sm ghost" type="button" aria-label={'Edit ' + service.label} disabled={busy} onclick={() => edit(service)}>Edit</button>
					{/if}
				</article>
			{:else}
				<p>No services are configured.</p>
			{/each}
		</section>
		</details><details class="card"><summary>Advanced coating matching rules</summary><CoatingRuleEditor /></details>

		{#if promotionDraft}
			<section class="card stack" aria-labelledby="promotion-heading">
				<h2 id="promotion-heading">Booking promotion</h2>
				<p class="muted">Applies to ceramic and powder coating estimates. Set to 0% to turn it off.</p>
				<form class="stack" onsubmit={savePromotion}>
					<fieldset class="stack" disabled={!pricing.canEditPromotion || busy || stale}>
						<details><summary>Promotion identification</summary><label>Promotion code <input bind:value={promotionDraft.code} pattern="[a-z0-9][a-z0-9\-]*" maxlength="64" required /></label>
						<label>Customer-facing label <input bind:value={promotionDraft.label} maxlength="120" required /></label>
						</details><label>Discount (%) <input type="number" bind:value={promotionDraft.percent} min="0" max="100" step="0.01" required /></label>
					</fieldset>
					{#if pricing.canEditPromotion}
						<div><button class="btn sm" type="submit" disabled={busy || stale}>Save promotion</button></div>
					{/if}
				</form>
			</section>
		{/if}
	{/if}
	{#if failure}
		<p class="error" role="alert">{failure}</p>
		{#if stale || !pricing}
			<div class="row"><button class="btn sm ghost" type="button" onclick={load}>Reload pricing</button><a href={resolve('/account')}>Account</a></div>
		{/if}
	{/if}
	{#if notice}<p role="status">{notice}</p>{/if}
</section>

<style>
	h2 { font-size: 1.8rem; }
	.service { padding-block: .5rem; border-block-start: 1px solid var(--line); }
	.check, .checks label { display: flex; align-items: center; gap: .45rem; }
	.check input, .checks input { width: auto; }
</style>
