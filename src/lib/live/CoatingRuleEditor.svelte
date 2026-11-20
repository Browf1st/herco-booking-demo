<script lang="ts">
	import { onMount } from 'svelte';
	import { resolve } from '$app/paths';
	import { finishes } from '#lib/shared/coating.ts';
	import { wheels } from '#lib/shared/bookingCatalog.ts';
	import {
		appointmentPowderParts, appointmentWheelSizes, coatingSnapshot, type CoatingDraft, type CoatingOptions
	} from '#lib/live/booking-coating.ts';

	type Service = 'ceramic' | 'wheel-colour';
	type Rule = {
		id: string; revision: number; service_code: Service; bike_key: string; option_match: CoatingOptions;
		minimum_centavos: number; maximum_centavos: number | null; quote_required: boolean; enabled: boolean;
	};
	type Draft = {
		id: string | null; revision: number; service: Service; bike: string; options: CoatingDraft;
		minimum?: number; maximum?: number; quote: boolean; enabled: boolean;
	};
	const serviceLabel = { ceramic: 'Ceramic coating', 'wheel-colour': 'Powder coating' };
	const money = new Intl.NumberFormat('en-PH', { currency: 'PHP', style: 'currency' });
	let canEdit = $state(false);
	let rules = $state<Rule[]>([]);
	let draft = $state<Draft>();
	let loading = $state(true);
	let busy = $state(false);
	let stale = $state(false);
	let issue = $state('');
	let notice = $state('');
	let retry: { fingerprint: string; requestId: string } | undefined;

	function newOptions(option?: CoatingOptions): CoatingDraft {
		return {
			ceramic: option?.ceramic_finish ?? '', red: option?.red_body === true,
			powder: [...(option?.powder_parts ?? [])], front: option?.wheel_front ?? '', rear: option?.wheel_rear ?? ''
		};
	}

	function edit(rule?: Rule) {
		issue = notice = '';
		stale = false;
		draft = rule ? {
			id: rule.id, revision: rule.revision, service: rule.service_code, bike: rule.bike_key,
			options: newOptions(rule.option_match), minimum: rule.minimum_centavos / 100,
			maximum: rule.maximum_centavos == null ? undefined : rule.maximum_centavos / 100,
			quote: rule.quote_required, enabled: rule.enabled
		} : {
			id: null, revision: 0, service: 'ceramic', bike: '', options: newOptions(), quote: false, enabled: false
		};
	}

	async function load() {
		loading = true;
		issue = '';
		try {
			const response = await fetch(resolve('/api/pricing/coating-rules'));
			if (!response.ok) throw new Error('Coating rules are temporarily unavailable.');
			const data = await response.json();
			canEdit = data.canEdit;
			rules = data.rules;
			draft = undefined;
			stale = false;
		} catch (failure) {
			issue = failure instanceof Error ? failure.message : 'Could not load coating rules.';
		} finally {
			loading = false;
		}
	}

	async function save(event: SubmitEvent) {
		event.preventDefault();
		if (!draft || busy || stale || (!draft.quote && draft.minimum === undefined)) return;
		issue = notice = '';
		const options = coatingSnapshot(draft.options, [draft.service]);
		if (!Object.keys(options).length) {
			issue = 'Choose the finish or parts this rule applies to.';
			return;
		}
		const payload = {
			id: draft.id, revision: draft.revision, service: draft.service, bike: draft.bike.trim(), options,
			minimumCentavos: draft.quote ? 0 : Math.round((draft.minimum ?? 0) * 100),
			maximumCentavos: draft.quote || draft.maximum == null ? null : Math.round(draft.maximum * 100),
			quoteRequired: draft.quote, enabled: draft.enabled
		};
		const fingerprint = JSON.stringify(payload);
		if (retry?.fingerprint !== fingerprint) retry = { fingerprint, requestId: crypto.randomUUID() };
		busy = true;
		try {
			const response = await fetch(resolve('/api/pricing/coating-rules'), {
				method: 'POST', headers: { 'content-type': 'application/json', accept: 'application/json' },
				body: JSON.stringify({ ...payload, requestId: retry.requestId })
			});
			if (!response.ok) {
				const failure = await response.json().catch(() => null);
				stale = response.status === 409;
				throw new Error(typeof failure?.message === 'string' ? failure.message : 'Could not save this rule.');
			}
			retry = undefined;
			await load();
			notice = issue ? 'Rule saved. Reload to see the latest list.' : 'Coating rule saved.';
		} catch (failure) {
			issue = failure instanceof Error ? failure.message : 'The save could not be confirmed. Retry the same change.';
		} finally {
			busy = false;
		}
	}

	onMount(() => { void load(); });
</script>

<section class="card stack" aria-labelledby="coating-rules-heading">
	<div class="row between">
		<h2 id="coating-rules-heading">Coating price rules</h2>
		{#if canEdit}<button type="button" class="btn sm" disabled={busy} onclick={() => edit()}>Add rule</button>{/if}
	</div>
	<p>Rules match the exact finish or set of parts and wheel sizes. A rule for a specific bike takes priority over a matching rule for any eligible bike.</p>
	{#if loading}
		<p role="status">Loading coating rules…</p>
	{:else}
		{#if draft && canEdit}
			<form class="card stack" onsubmit={save}>
				<h3>{draft.id ? 'Edit coating rule' : 'Add coating rule'}</h3>
				<fieldset class="stack" disabled={busy || stale}>
					<legend>Match a configuration</legend>
					<label>Service<select bind:value={draft.service} onchange={() => { if (draft) draft.options = newOptions(); }}>
						<option value="ceramic">Ceramic coating</option>
						<option value="wheel-colour">Powder coating</option>
					</select></label>
					<label>Exact bike name (optional)<input bind:value={draft.bike} maxlength="120" placeholder="Any eligible bike" /></label>
					{#if draft.service === 'ceramic'}
						<label>Ceramic finish<select bind:value={draft.options.ceramic} required>
							<option value="">Choose finish</option>
							{#each finishes as finish}<option value={finish}>{finish}</option>{/each}
						</select></label>
						{#if draft.options.ceramic === 'Enhance'}
							<label class="check"><input type="checkbox" bind:checked={draft.options.red} required />
								Red Honda ADV or PCX 150/160</label>
						{/if}
					{:else}
						<fieldset class="cols">
							<legend>Powder coating parts</legend>
							{#each appointmentPowderParts as part (part)}
								<label class="check"><input type="checkbox" bind:group={draft.options.powder} value={part} /> {part}</label>
							{/each}
						</fieldset>
						{#if draft.options.powder.includes(wheels)}
							<div class="cols">
								<label>Front mag diameter<select bind:value={draft.options.front}>
									<option value="">No front mag</option>
									{#each appointmentWheelSizes as size (size)}<option value={size}>{size}</option>{/each}
								</select></label>
								<label>Rear mag diameter<select bind:value={draft.options.rear}>
									<option value="">No rear mag</option>
									{#each appointmentWheelSizes as size (size)}<option value={size}>{size}</option>{/each}
								</select></label>
							</div>
						{/if}
					{/if}
					<label class="check"><input type="checkbox" bind:checked={draft.quote} /> Shop quote required</label>
					{#if !draft.quote}
						<label>Fixed or minimum price (₱)<input type="number" bind:value={draft.minimum}
							min="0" max="21474836.47" step="0.01" required /></label>
						<label>Maximum price (₱, optional)<input type="number" bind:value={draft.maximum}
							min="0" max="21474836.47" step="0.01" /></label>
					{/if}
					<label class="check"><input type="checkbox" bind:checked={draft.enabled} /> Use for new matching bookings</label>
				</fieldset>
				<div class="row">
					<button class="btn sm" type="submit" disabled={busy || stale}>Save rule</button>
					<button class="btn sm ghost" type="button" disabled={busy} onclick={() => { draft = undefined; issue = ''; }}>Cancel</button>
				</div>
			</form>
		{/if}
		{#each rules as rule (rule.id)}
			<article class="row between rule">
				<div>
					<strong>{serviceLabel[rule.service_code]} · {rule.bike_key || 'Any eligible bike'}</strong>
					<p>{rule.option_match.ceramic_finish || rule.option_match.powder_parts?.join(', ')}
						{#if rule.option_match.wheel_front} · Front {rule.option_match.wheel_front}{/if}
						{#if rule.option_match.wheel_rear} · Rear {rule.option_match.wheel_rear}{/if}
					</p>
					<p>{rule.quote_required ? 'Shop quote' : money.format(rule.minimum_centavos / 100) +
						(rule.maximum_centavos === null ? '' : '–' + money.format(rule.maximum_centavos / 100))}
						· {rule.enabled ? 'Enabled' : 'Disabled'}</p>
				</div>
				{#if canEdit}<button class="btn sm ghost" type="button" disabled={busy} onclick={() => edit(rule)}>Edit rule</button>{/if}
			</article>
		{:else}
			{#if !issue}<p>No coating price rules are configured.</p>{/if}
		{/each}
	{/if}
	{#if issue}
		<p role="alert">{issue}</p>
		{#if stale || !draft}<div><button class="btn sm ghost" type="button" onclick={load}>Reload coating rules</button></div>{/if}
	{/if}
	{#if notice}<p role="status">{notice}</p>{/if}
</section>

<style>
	h2 { font-size: 1.8rem; }
	.rule { padding-block: .5rem; border-block-start: 1px solid var(--line); }
	.check { display: flex; align-items: center; gap: .5rem; }
	.check input { width: auto; }
</style>
