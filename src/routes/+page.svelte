<script lang="ts">
	import { asset, resolve } from '$app/paths';
	import AvailabilityCalendar from '#lib/AvailabilityCalendar.svelte';
	import CompareSlider from '#lib/CompareSlider.svelte';
	import { photos, shop, wheelColours } from '#lib/config.ts';
	import { fmtDate, fmtSlot, upcoming } from '#lib/dates.ts';
	import { dayStatus, features } from '#lib/store.svelte.ts';

	const hours = `${fmtSlot(String(shop.openHour) + ':00')} – ${fmtSlot(String(shop.closeHour) + ':00')}`;
	const directions = `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(shop.address)}`;
	const statusLabels = { open: 'Available', closed: 'Closed', blocked: 'Closed', full: 'Full' };
	let calendarOpen = $state(false);

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
			<p class="eyebrow">Wed to Sun / {hours}</p>
			<h1>Cleaner bikes.<br /><span class="accent">Bigger dreams.</span></h1>
			<p class="lead">
				Motorcycle detailing, ceramic coating and powder coating in Valenzuela. Find a service and choose a drop-off time.
			</p>
			<div class="row">
				<a class="btn" href={resolve('/book')}>Book a slot</a>
				<a class="btn ghost" href="#schedule">Check availability</a>
			</div>
		</div>
		<img class="hero-photo" src={asset(photos.hero)} alt="" fetchpriority="high" />
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
			<div><a class="btn sm ghost" href={resolve('/book?service=ceramic')}>Book ceramic coating</a></div>
		</article>
		<article class="work-photo card stack">
			<img src={asset(photos.powder)} alt="Motorcycle fitted with red coated wheels" loading="lazy" />
			<h3>Powder coating</h3>
			<p class="muted">For wheels and other suitable metal components. Tell the garage which parts you want coated and your preferred colour or finish.</p>
			<div><a class="btn sm ghost" href={resolve('/book?service=wheel-colour')}>Book powder coating</a></div>
		</article>
	</div>
</section>

<section class="section band" id="schedule">
	<div class="wrap stack">
		<div class="schedule-heading">
			<h2>Shop schedule</h2>
			<p class="muted">Wednesday to Sunday, {hours} Philippine time. <strong>Closed Monday and Tuesday.</strong></p>
		</div>
		<div class="schedule card stack">
			<div class="schedule-heading">
				<h3>Next 7 days</h3>
				<p class="muted small">Select an available date to start your booking.</p>
			</div>
			<ul class="schedule-days">
				{#each upcoming().slice(0, 7) as date (date)}
					{@const status = dayStatus(date)}
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
			<div><button type="button" class="btn sm ghost" aria-expanded={calendarOpen} onclick={() => calendarOpen = !calendarOpen}>{calendarOpen ? 'Hide calendar' : 'See more dates'}</button></div>
			{#if calendarOpen}
				<AvailabilityCalendar />
			{/if}
		</div>
	</div>
</section>

<section class="section band">
	<div class="wrap stack">
		<p class="eyebrow">02 / How booking works</p>
		<h2>No chat. No waiting.</h2>
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

{#if features().preview}
	<section class="section wrap teaser">
		<div class="stack">
			<p class="eyebrow">Showcase</p>
			<h2>See the finish before you book</h2>
			<p class="muted">Drag to compare a real bike before and after, then browse wheel colours coated by the shop.</p>
			<div><a class="btn" href={resolve('/preview')}>Open showcase</a></div>
		</div>
		<CompareSlider before={photos.before} after={photos.after} alt="Scooter coated by the shop" />
	</section>
{/if}

<section class="section wrap stack" id="inventory">
	<h2>Wheel coating colours</h2>
	<p class="muted">Browse sample finishes from the gallery. Ask the garage about current stock and whether a finish suits your parts.</p>
	<div class="finish-grid">
		{#each wheelColours as colour (colour.id)}
			<figure class="card stack">
				<img src={colour.photo} alt={`${colour.name} coated wheel`} loading="lazy" />
				<figcaption><h3>{colour.name}</h3><p class="small muted">Check availability with the shop</p></figcaption>
			</figure>
		{/each}
	</div>
	<div class="row">
		{#if features().preview}<a class="btn ghost" href={resolve('/preview')}>Open preview</a>{/if}
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
		<a class="btn" href={resolve('/book')}>Book a slot</a>
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
		background: linear-gradient(120deg, #fff, var(--bg));
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

	.finish-grid {
		display: grid;
		grid-template-columns: repeat(auto-fit, minmax(min(100%, 190px), 1fr));
		gap: 16px;
	}

	.finish-grid img,
	.work-photo img {
		width: 100%;
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
	a.schedule-day { border-color: #91bea4; background: #f0f9f3; }
	a.schedule-day:hover { background: #d9f3e3; border-color: var(--ok); }
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
