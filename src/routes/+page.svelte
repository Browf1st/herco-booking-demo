<script lang="ts">
	import { resolve } from '$app/paths';
	import CompareSlider from '#lib/CompareSlider.svelte';
	import { bikeImage, peso, reviews, services, shop } from '#lib/config.ts';
	import { features } from '#lib/store.svelte.ts';

	const steps = $derived([
		['Pick your service', 'Choose the wash, detail or ceramic coating that fits your bike.'],
		['Pick a date and slot', 'See the open drop-off times live. A day closes by itself once it is full.'],
		...(features().payment
			? [[`Send the ${peso(shop.downpayment)} downpayment`, 'Pay by GCash and type in the reference number. No screenshots.']]
			: []),
		['Ride in on time', 'Your slot is held for you. No waiting on chat, no guessing.']
	]);
</script>

<section class="hero">
	<div class="wrap hero-grid">
		<div class="stack">
			<p class="eyebrow">Valenzuela City / Wed to Sun / 9AM to 5PM</p>
			<h1>Ride in dirty.<br /><span class="accent">Ride out coated.</span></h1>
			<p class="lead">
				Motorcycle detailing and ceramic coating, strictly by schedule. Lock in your slot online in under a
				minute, with no account needed.
			</p>
			<div class="row">
				<a class="btn" href={resolve('/book')}>Book a slot</a>
				{#if features().preview}<a class="btn ghost" href={resolve('/preview')}>Preview your bike</a>{/if}
			</div>
		</div>
		<img class="hero-img" src={bikeImage('sport', 'red', 'glossy')} alt="Placeholder sport bike with a glossy coating" />
	</div>
	<div class="wrap stats">
		{#each shop.stats as stat}
			<div><b class="display">{stat.value}</b><span class="muted small">{stat.label}</span></div>
		{/each}
	</div>
	<div class="stripe"></div>
</section>

<section class="section wrap stack" id="services">
	<p class="eyebrow">01 / Services</p>
	<h2>Built for two wheels</h2>
	<div class="cols">
		{#each services as service}
			<a class="card service stack" href={resolve(`/book?service=${service.id}`)}>
				<h3>{service.name}</h3>
				<p class="muted">{service.blurb}</p>
				<p class="price">from <b class="display accent">{peso(service.prices.small)}</b></p>
				<span class="eyebrow">Book this</span>
			</a>
		{/each}
	</div>
	<p class="muted small">Sample services and prices for this demo. The final list comes from the shop.</p>
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
			<p class="eyebrow">03 / Bike preview</p>
			<h2>See the finish before you book</h2>
			<p class="muted">Pick your model, colour and finish, then drag to compare stock against coated.</p>
			<div><a class="btn" href={resolve('/preview')}>Open bike preview</a></div>
		</div>
		<CompareSlider
			before={bikeImage('adventure', 'blue', 'stock')}
			after={bikeImage('adventure', 'blue', 'glossy')}
			alt="Placeholder adventure bike"
		/>
	</section>
{/if}

<section class="section wrap stack">
	<p class="eyebrow">Riders say</p>
	<h2>100% recommend</h2>
	<div class="cols">
		{#each reviews as review}
			<blockquote class="card stack">
				<p>{review.text}</p>
				<footer class="eyebrow">{review.name}</footer>
			</blockquote>
		{/each}
	</div>
</section>

<section class="section band">
	<div class="wrap cta">
		<div class="stack">
			<h2>Slots fill fast.</h2>
			<p class="muted">
				Open Wednesday to Sunday, 9AM to 5PM in {shop.area}. Follow the shop on
				<a href={shop.facebook}>Facebook</a>.
			</p>
		</div>
		<a class="btn" href={resolve('/book')}>Book a slot</a>
	</div>
</section>

<style>
	.hero {
		background:
			linear-gradient(115deg, transparent 0 58%, color-mix(in srgb, var(--accent) 14%, transparent) 58% 62%, transparent 62%),
			radial-gradient(circle at 80% 20%, #1d2026, var(--bg) 60%);
	}

	.hero-grid {
		display: grid;
		gap: 28px;
		align-items: center;
		padding-top: 48px;
		padding-bottom: 32px;
	}

	.lead {
		max-width: 46ch;
		color: var(--muted);
		font-size: 1.1rem;
	}

	.hero-img {
		width: 100%;
		border-radius: 6px;
		clip-path: polygon(6% 0, 100% 0, 94% 100%, 0 100%);
	}

	.stats {
		display: grid;
		grid-template-columns: repeat(3, 1fr);
		gap: 12px;
		padding-bottom: 32px;
	}

	.stats div {
		display: grid;
		padding-left: 12px;
		border-left: 3px solid var(--accent);
	}

	.stats b {
		font-size: clamp(2rem, 8vw, 3.2rem);
	}

	.service {
		text-decoration: none;
		transition: border-color 0.15s;
	}

	.service:hover {
		border-color: var(--accent);
	}

	.price b {
		font-size: 2rem;
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

	blockquote {
		margin: 0;
	}

	.teaser,
	.cta {
		display: grid;
		gap: 24px;
		align-items: center;
	}

	@media (min-width: 800px) {
		.hero-grid,
		.teaser {
			grid-template-columns: 1fr 1fr;
		}

		.cta {
			grid-template-columns: 1fr auto;
		}
	}
</style>
