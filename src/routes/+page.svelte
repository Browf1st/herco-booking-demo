<script lang="ts">
	import ActionIcon from '#lib/shared/ActionIcon.svelte';
	import { onMount } from 'svelte';
	import { asset, resolve } from '$app/paths';
	import AvailabilityCalendar from '#lib/shared/AvailabilityCalendar.svelte';
	import { photos, shop } from '#lib/shared/config.ts';
	import { showcaseHome } from '#lib/shared/showcase-home.ts';
	import { addDays, fmtDate, today, upcoming } from '#lib/shared/dates.ts';
	import { defaultSettings } from '#lib/shared/schedule-hours.ts';
	import { formatClosedDays, formatShopHours } from '#lib/shared/shop-hours-text.ts';
	import { liveShopHours, loadShopHours } from '#lib/live/shop-hours.svelte.ts';

	// Until the live hours arrive (or if they fail), show the starting hours.
	const shopHours = $derived(liveShopHours.value ?? defaultSettings());
	const openHours = $derived(formatShopHours(shopHours));
	const closedDays = $derived(formatClosedDays(shopHours.openWeekdays));
	const directions = `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(shop.address)}`;
	const statusLabels = { open: 'Available', closed: 'Closed', blocked: 'Closed', full: 'Full' };
	let calendarOpen = $state(false);
	const days = upcoming().slice(0, 7);
	type ServerSlot = { visit_date: string; status: 'past' | 'closed' | 'blocked' | 'open' };
	let serverSlots = $state<ServerSlot[]>();
	let scheduleError = $state(false);
	let calendarSlots = $state<ServerSlot[]>([]);
	let calendarIssue = $state('');
	let calendarLoading = $state(false);
	let calendarRequest = 0;

	async function loadCalendar(from: string, through: string) {

		const request = ++calendarRequest;
		calendarIssue = '';
		calendarSlots = [];
		const horizon = addDays(today(), 365);
		if (from > horizon) { calendarIssue = 'Bookings open up to one year ahead.'; return; }
		calendarLoading = true;
		try {
			const response = await fetch(resolve('/api/availability') + '?' + new URLSearchParams({ from, to: through > horizon ? horizon : through }));
			if (!response.ok) throw new Error();
			const slots = await response.json();
			if (request === calendarRequest) calendarSlots = slots;
		} catch { if (request === calendarRequest) calendarIssue = 'Availability is temporarily unavailable. Select another month to retry.'; }
		finally { if (request === calendarRequest) calendarLoading = false; }
	}

	function calendarStatus(date: string) {

		const slots = calendarSlots.filter(slot => slot.visit_date === date);
		return slots.some(slot => slot.status === 'open') ? 'open' : 'closed';
	}

	onMount(() => {

		void loadShopHours();
		const controller = new AbortController();
		const query = new URLSearchParams({ from: days[0], to: days[days.length - 1] });
		void fetch(resolve('/api/availability') + '?' + query, { signal: controller.signal })
			.then(async response => {
				if (!response.ok) throw new Error();
				serverSlots = await response.json();
			})
			.catch(() => { if (!controller.signal.aborted) scheduleError = true; });
		return () => controller.abort();
	});

	function scheduleStatus(date: string): keyof typeof statusLabels {

		const slots = serverSlots?.filter(slot => slot.visit_date === date) ?? [];
		return slots.some(slot => slot.status === 'open') ? 'open' : 'closed';
	}

	const steps = [
		['Choose your service', 'Select ceramic coating or powder coating.'],
		['Tell us about your bike', 'Add your contact details, motorcycle model, and the parts you want coated.'],
		['Request a visit', 'Choose an available date and time. The shop needs to confirm your request.']
	];
</script>

<section class="hero" id="home">
	<div class="wrap hero-content">
		<div class="stack">
			<p class="hero-address">4494 G Bamboo Street<br />Valenzuela, 1442</p>
			<p class="eyebrow">{openHours.text}</p>
			<h1>Cleaner bikes.<br /><span class="accent">Bigger dreams.</span></h1>
			<p class="lead">
				Motorcycle detailing, ceramic coating and powder coating in Valenzuela. Find a service and choose a drop-off time.
			</p>
			<div class="row">
				<a class="btn" href={resolve('/book')}><ActionIcon name="calendar" />Book a slot</a>
				<a class="btn ghost" href="#schedule"><ActionIcon name="clock" />Check availability</a>
			</div>
		</div>
		<img class="hero-photo" src={asset(photos.hero)} srcset={`${asset('photos/herco-cruiser-480.webp')} 480w, ${asset(photos.hero)} 720w`} sizes="(min-width: 1100px) 506px, (min-width: 800px) 46vw, calc(100vw - 32px)" alt="" width="720" height="960" fetchpriority="high" />
	</div>
	<div class="stripe"></div>
</section>

<section class="section wrap stack" id="services">
	<p class="eyebrow">01 / Services</p>
	<h2>Motorcycle coating services</h2>
	<div class="teaser">
		<article class="work-photo card stack">
			<img src={asset(photos.ceramic)} alt="Ceramic coating application" loading="lazy" />
			<h3>Ceramic coating</h3>
			<p class="muted">For suitable painted surfaces and body panels. Share your motorcycle model and the panels you want coated so the garage can assess the job.</p>
			<div><a class="btn sm ghost" href={resolve('/book?service=ceramic')}><ActionIcon name="calendar" />Book ceramic coating</a></div>
		</article>
		<article class="work-photo card stack">
			<img src={asset(photos.powder)} srcset={`${asset(photos.powderSmall)} 480w, ${asset(photos.powder)} 960w`}
				sizes="(min-width: 1100px) 490px, (min-width: 800px) calc(50vw - 60px), calc(100vw - 64px)"
				alt="Scooter with Fire Red powder-coated wheels" width="960" height="540" loading="lazy" decoding="async" />
			<h3>Powder coating</h3>
			<p class="muted">For wheels and other suitable metal components. Tell the garage which parts you want coated and your preferred colour or finish.</p>
			<div><a class="btn sm ghost" href={resolve('/book?service=wheel-colour')}><ActionIcon name="calendar" />Book powder coating</a></div>
		</article>
	</div>
</section>

<section class="section band" id="schedule">
	<div class="wrap stack">
		<div class="schedule-heading">
			<h2>Shop schedule</h2>
			<p class="muted">{openHours.text} Philippine time.{#if closedDays} <strong>Closed {closedDays}.</strong>{/if}</p>
		</div>
		<div class="schedule card stack">
			<div class="schedule-heading">
				<h3>Next 7 days</h3>
				<p class="muted small">Select an available date to start your booking.</p>
			</div>
			{#if scheduleError}
				<p role="alert">Availability is temporarily unavailable.</p>
			{:else if !serverSlots}
				<p role="status">Loading availability…</p>
			{:else}
			<ul class="schedule-days">
				{#each days as date (date)}
					{@const status = scheduleStatus(date)}
					<li data-status={status}>
						{#snippet day()}
							<time datetime={date}>
								<span>{fmtDate(date, { weekday: 'short' })}</span>
								<strong>{fmtDate(date, { month: 'short', day: 'numeric' })}</strong>
							</time>
							<span class="availability">{statusLabels[status]}</span>
						{/snippet}
						{#if status === 'open'}
							<a class="schedule-day" href={resolve('/book') + '?date=' + date} aria-label={'Book a visit on ' + fmtDate(date)}>{@render day()}</a>
						{:else}
							<div class="schedule-day">{@render day()}</div>
						{/if}
					</li>
				{/each}
			</ul>
			{/if}
			<div><button type="button" class="btn sm ghost" aria-expanded={calendarOpen} onclick={() => calendarOpen = !calendarOpen}><ActionIcon name="calendar" />{calendarOpen ? 'Hide calendar' : 'See more dates'}</button></div>
			{#if calendarOpen}
				{#if calendarLoading}<p role="status">Loading calendar…</p>{/if}
				{#if calendarIssue}<p role="alert">{calendarIssue}</p>{/if}
				<AvailabilityCalendar statusFor={calendarStatus} onmonth={loadCalendar} allows={date => date <= addDays(today(),365)} />
			{/if}
		</div>
	</div>
</section>

<section class="section band">
	<div class="wrap stack">
		<p class="eyebrow">02 / Simple steps</p>
		<h2>How booking works</h2>
		<ol class="cols">
			{#each steps as [title, text], i}
				<li class="stack">
					<b class="display num">{String(i + 1).padStart(2, '0')}</b>
					<h3>{title}</h3>
					<p class="muted">{text}</p>
				</li>
			{/each}
		</ol>
	</div>
</section>

<section class="section wrap stack" id="inventory">
	<p class="eyebrow">Showcase</p>
	<h2>Finished in our shop</h2>
	<p class="muted">A few recent jobs. Ask the garage about current colours and whether a finish suits your parts.</p>
	<div class="finish-groups">
		{#each showcaseHome as group (group.folder)}
			<div class="finish-group stack">
				<h3>{group.title}</h3>
				<ul class="finish-grid">
					{#each group.photos as item (item.slug)}
						<li>
							<figure class="stack">
								<img src={asset(`photos/${group.folder}/${item.slug}-480.webp` as Parameters<typeof asset>[0])}
									alt={item.alt} width="480" height="480" loading="lazy" decoding="async" />
								{#if 'title' in item}<figcaption class="small">{item.title}</figcaption>{/if}
							</figure>
						</li>
					{/each}
				</ul>

					<div class="finish-link"><a class="btn ghost" href={resolve(group.href)}><ActionIcon name="view" />View {group.title}</a></div>

			</div>
		{/each}
	</div>
</section>

<section class="section band" id="visit">
	<div class="wrap cta">
		<div class="visit-contact">
			<img class="visit-logo" src={asset(photos.logo)} alt="" width="960" height="915" loading="lazy" />
			<div class="stack">
				<h2>Visit HERCO</h2>
				<div class="row contact-links">
					<a href={directions} target="_blank" rel="noopener noreferrer" aria-label="Get directions to HERCO (opens in a new tab)" title="Get directions">
						<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
							<path d="M20 10c0 5-8 11-8 11S4 15 4 10a8 8 0 1 1 16 0Z" />
							<circle cx="12" cy="10" r="2.5" />
						</svg>
					</a>
					<details class="phone-contact">
						<summary aria-label="HERCO phone number" aria-describedby="herco-phone-number">
						<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round" aria-hidden="true">
							<path d="M6 3h4l1 5-3 2a13 13 0 0 0 6 6l2-3 5 1v4a3 3 0 0 1-3 3A16 16 0 0 1 3 6a3 3 0 0 1 3-3Z" />
						</svg>
						</summary>
						<span id="herco-phone-number" class="phone-tooltip">{shop.phoneLabel}</span>
					</details>
					<a href={`mailto:${shop.contactEmail}`} aria-label={`Email HERCO at ${shop.contactEmail}`} title={shop.contactEmail}>
						<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round" aria-hidden="true">
							<rect x="3" y="5" width="18" height="14" rx="3" />
							<path d="m4 7 8 6 8-6" />
						</svg>
					</a>
					<a href={shop.messenger} target="_blank" rel="noopener noreferrer" aria-label="Message HERCO on Messenger (opens in a new tab)" title="Message HERCO">
						<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
							<path d="M12 3a9 9 0 0 0-8 13l-1 5 5-1a9 9 0 1 0 4-17Z" />
							<path d="m7 14 4-4 3 3 3-3" />
						</svg>
					</a>
					<a href={shop.facebook} target="_blank" rel="noopener noreferrer" aria-label="HERCO on Facebook (opens in a new tab)" title="HERCO on Facebook">
						<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
							<path d="M14 22v-9h3l.5-4H14V7c0-1 .4-2 2-2h2V2.4A17 17 0 0 0 15 2c-3 0-5 2-5 5v2H7v4h3v9z" />
						</svg>
					</a>
				</div>
			</div>
		</div>
		<a class="btn" href={resolve('/book')}><ActionIcon name="calendar" />Book a slot</a>
	</div>
</section>

<style>
	.visit-contact {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: 16px 24px;
	}

	.visit-logo {
		display: block;
		width: clamp(88px, 12vw, 140px);
		height: auto;
		mix-blend-mode: screen;
	}

	#visit .cta > .btn {
		justify-self: start;
	}

	.contact-links a,
	.phone-contact summary {
		display: grid;
		place-items: center;
		width: 48px;
		height: 48px;
		border: 1px solid var(--line);
		border-radius: 6px;
		color: var(--text);
		background: var(--panel-2);
	}

	.contact-links a:hover,
	.phone-contact summary:hover {
		border-color: var(--accent);
		color: var(--accent);
	}

	.contact-links svg {
		width: 22px;
		height: 22px;
	}

	.phone-contact {
		position: relative;
	}

	.phone-contact summary::-webkit-details-marker {
		display: none;
	}

	.phone-tooltip {
		position: absolute;
		z-index: 1;
		bottom: calc(100% + 4px);
		left: 50%;
		transform: translateX(-50%);
		padding: 6px 10px;
		border: 1px solid var(--line);
		border-radius: 6px;
		background: var(--panel-2);
		white-space: nowrap;
	}

	.phone-contact::details-content {
		content-visibility: visible;
	}

	.phone-contact:not([open]):not(:hover):not(:focus-within) .phone-tooltip {
		visibility: hidden;
	}

	.hero {
		background: linear-gradient(120deg, var(--panel), var(--bg));
		color: var(--text);
	}

	.hero-content {
		display: grid;
		align-items: center;
		gap: clamp(24px, 4vw, 56px);
		padding-block: clamp(32px, 6vw, 72px);
	}

	.hero h1 {
		font-size: clamp(2.5rem, 5vw, 5.1rem);
	}

	.hero-content > .stack {
		max-width: 660px;
	}

	.hero-address {
		color: var(--muted);
		font-size: 0.95rem;
		line-height: 1.5;
	}

	.lead {
		max-width: 46ch;
		color: var(--muted);
		font-size: 1.1rem;
	}

	.hero-photo {
		width: 100%;
		height: auto;
		max-height: 480px;
		object-fit: contain;
	}

	@media (min-width: 800px) {
		.hero-content { grid-template-columns: minmax(0, 1fr) minmax(0, 1fr); }
	}

	section[id] {
		scroll-margin-top: 72px;
	}

	summary {
		cursor: pointer;
		color: var(--accent);
	}

	.finish-groups { display: grid; gap: 24px; }
	.finish-group { grid-template-rows: auto auto 1fr; }
	.finish-group h3, .finish-grid figure { margin: 0; }
	.finish-link { margin-top: auto; }
	.finish-grid { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 12px; margin: 0; padding: 0; list-style: none; }
	.finish-grid figcaption { font-weight: 650; overflow-wrap: anywhere; }

	@media (min-width: 800px) {
		.finish-groups { grid-template-columns: repeat(2, minmax(0, 1fr)); }
		.finish-grid { gap: 16px; }
	}

	.finish-grid img,
	.work-photo img {
		width: 100%;
		height: auto;
		aspect-ratio: 1;
		object-fit: cover;
		border-radius: 4px;
	}

	.work-photo img {
		aspect-ratio: 16 / 9;
	}

	.band {
		background: var(--panel);
		border-block: 1px solid var(--line);
	}

	ol {
		margin: 0;
		padding: 0;
		list-style: none;
	}

	.num {
		color: var(--accent);
		font-size: 3rem;
	}

	figure {
		margin: 0;
	}

	.teaser,
	.cta {
		display: grid;
		gap: 24px;
		align-items: center;
	}

	.schedule { padding: clamp(12px, 3vw, 28px); }
	.schedule-heading { display: grid; gap: 8px; }
	.schedule-days { display: grid; gap: 8px; list-style: none; margin: 0; padding: 0; }
	.schedule-day {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 8px;
		height: 100%;
		padding: 10px;
		border: 1px solid var(--line);
		border-radius: 8px;
		background: var(--bg);
		text-decoration: none;
	}
	.schedule-day time { display: flex; align-items: baseline; flex-wrap: wrap; gap: 6px; }
	.schedule-day time span { color: var(--muted); font-size: 0.85rem; }
	.schedule-day time strong { white-space: nowrap; }
	a.schedule-day { border-color: var(--ok-line); background: color-mix(in srgb, var(--ok-bg) 55%, var(--panel)); }
	a.schedule-day:hover { background: var(--ok-bg); border-color: var(--ok); }
	.availability { font-size: 0.8rem; font-weight: 700; color: var(--muted); }
	[data-status='open'] .availability { color: var(--ok); }
	[data-status='full'] .availability { color: var(--warn); }
	@media (min-width: 820px) {
		.schedule-days { grid-template-columns: repeat(7, minmax(0, 1fr)); }
		.schedule-day, .schedule-day time { flex-direction: column; align-items: start; }
	}

	@media (min-width: 800px) {
		.teaser {
			grid-template-columns: 1fr 1fr;
		}

		.cta {
			grid-template-columns: 1fr auto;
		}
	}
</style>
