<script lang="ts">
	import { asset, resolve } from '$app/paths';
	import { onMount } from 'svelte';
	import CompareSlider from '#lib/CompareSlider.svelte';
	import { peso, photos, shop, wheelColours } from '#lib/config.ts';
	import { fmtDate, fmtSlot, upcoming } from '#lib/dates.ts';
	import { dayStatus, features, spotsLeft } from '#lib/store.svelte.ts';

	const hours = `${fmtSlot(String(shop.openHour))} – ${fmtSlot(String(shop.closeHour))}`;
	const directions = `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(shop.address)}`;
	const statusLabels = { closed: 'Closed', blocked: 'Unavailable', full: 'Full' };

	let heroVideo = $state<HTMLVideoElement>();
	let heroCanvas = $state<HTMLCanvasElement>();
	let heroPlaying = $state(false);

	function playHero() {
		if (!heroVideo) return;
		heroVideo.muted = true;
		void heroVideo.play().catch(() => {
			// Keep the poster visible if playback is unavailable.
		});
	}

	onMount(() => {
		const video = heroVideo;
		const canvas = heroCanvas;
		const context = canvas?.getContext('2d');
		if (!video || !canvas || !context) return;

		// Draw the reel as a background so the browser has no visible video surface for its overlays.
		let frame = 0;
		let lastTime = -1;
		function draw() {
			if (!video || !canvas || !context) return;
			if (video.readyState >= 2 && video.currentTime !== lastTime) {
				if (canvas.width !== video.videoWidth || canvas.height !== video.videoHeight) {
					canvas.width = video.videoWidth;
					canvas.height = video.videoHeight;
				}
				context.drawImage(video, 0, 0);
				lastTime = video.currentTime;
			}
			if (!video.paused) frame = requestAnimationFrame(draw);
		}
		function startDrawing() {
			cancelAnimationFrame(frame);
			draw();
		}
		video.addEventListener('playing', startDrawing);
		if (matchMedia('(prefers-reduced-motion: no-preference)').matches) playHero();
		return () => {
			video.removeEventListener('playing', startDrawing);
			cancelAnimationFrame(frame);
		};
	});
	const steps = $derived([
		['Pick your service', 'Choose ceramic coating or powder coating for your bike.'],
		['Pick a date and slot', 'Choose a drop-off time from the demo calendar.'],
		...(features().payment
			? [[`Send the ${peso(shop.downpayment)} downpayment`, 'Pay by GCash and type in the reference number. No screenshots.']]
			: []),
		['Review your request', 'Check your service, motorcycle details and preferred drop-off time.']
	]);
</script>

<section class="hero" id="home">
	<video
		bind:this={heroVideo}
		src={asset('photos/herco-reel.mp4')}
		hidden
		preload="metadata"
		playsinline
		muted
		loop
		disablepictureinpicture
		onplaying={() => (heroPlaying = true)}
		onpause={() => (heroPlaying = false)}
	></video>
	<canvas class="hero-video" bind:this={heroCanvas} aria-hidden="true"></canvas>
	<div class="hero-shade"></div>
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
				<a class="btn ghost" href="#schedule">See shop schedule</a>
			</div>
		</div>
		<button
			class="hero-motion"
			type="button"
			aria-label={heroPlaying ? 'Pause background video' : 'Play background video'}
			title={heroPlaying ? 'Pause background video' : 'Play background video'}
			onclick={() => heroPlaying ? heroVideo?.pause() : playHero()}
		>
			<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
				{#if heroPlaying}
					<path d="M8 5h3v14H8zm5 0h3v14h-3z" />
				{:else}
					<path d="M9 5v14l11-7z" />
				{/if}
			</svg>
		</button>
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
			<div><a class="btn sm ghost" href={resolve('/book?service=ceramic-glossy')}>Book ceramic coating</a></div>
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
		<p class="eyebrow">Plan your visit</p>
		<h2>Garage schedule</h2>
		<div class="card stack schedule">
			<dl class="shop-hours">
				<div><dt>Wednesday to Sunday</dt><dd class="display">{hours}</dd></div>
				<div><dt>Monday and Tuesday</dt><dd class="muted">Closed</dd></div>
			</dl>
			<div class="stack">
				<div class="schedule-heading row">
				<h3>Next 7 days</h3>
					<span class="small muted">Philippine time</span>
				</div>
				<ul class="schedule-days">
					{#each upcoming().slice(0, 7) as date (date)}
						{@const status = dayStatus(date)}
						{@const count = status === 'open' ? spotsLeft(date) : 0}
						<li data-status={status}>
							<time datetime={date}>
								<span class="small muted">{fmtDate(date, { weekday: 'short' })}</span>
								<b class="display">{fmtDate(date, { month: 'short', day: 'numeric' })}</b>
							</time>
							<span class="availability small">{status === 'open' ? `${count} ${count === 1 ? 'slot' : 'slots'}` : statusLabels[status]}</span>
						</li>
					{/each}
				</ul>
				<div class="schedule-footer row">
					<a class="btn sm" href={resolve('/book')}>Open booking calendar</a>
				</div>
			</div>
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
			<p class="eyebrow">03 / Preview</p>
			<h2>See the finish before you book</h2>
			<p class="muted">Drag to compare a real bike before and after, then browse wheel colours coated by the shop.</p>
			<div><a class="btn" href={resolve('/preview')}>Open preview</a></div>
		</div>
		<CompareSlider before={photos.before} after={photos.after} alt="Scooter coated by the shop" />
	</section>
{/if}

<section class="section wrap stack" id="inventory">
	<p class="eyebrow">Finish inventory</p>
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
		position: relative;
		isolation: isolate;
		background: var(--bg);
	}

	.hero-content {
		position: relative;
		display: grid;
		align-content: center;
		min-height: clamp(520px, 64vw, 680px);
		padding-block: 48px 64px;
	}

	.hero-content > .stack {
		max-width: 660px;
	}

	.hero-address {
		color: var(--text);
		font-size: 0.95rem;
		line-height: 1.5;
	}

	.hero-shade {
		position: absolute;
		inset: 0;
		z-index: -1;
		background: linear-gradient(90deg, rgb(10 11 13 / 94%), rgb(10 11 13 / 78%) 38%, rgb(10 11 13 / 28%));
	}

	.lead {
		max-width: 46ch;
		color: var(--text);
		font-size: 1.1rem;
	}

	.hero-video {
		position: absolute;
		inset: 0;
		z-index: -2;
		width: 100%;
		height: 100%;
		object-fit: cover;
		object-position: center 48%;
		pointer-events: none;
	}

	.hero-motion {
		position: absolute;
		right: 16px;
		bottom: 16px;
		display: grid;
		place-items: center;
		width: 44px;
		height: 44px;
		padding: 0;
		border: 1px solid rgb(255 255 255 / 32%);
		border-radius: 50%;
		background: rgb(10 11 13 / 70%);
		color: var(--text);
		cursor: pointer;
	}

	.hero-motion:hover {
		border-color: var(--accent);
		background: var(--bg);
	}

	.hero-motion svg {
		width: 20px;
		height: 20px;
	}

	@media (max-width: 640px) {
		.hero-shade {
			background: rgb(10 11 13 / 76%);
		}
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

	.shop-hours {
		display: flex;
		flex-wrap: wrap;
		gap: 14px 36px;
		margin: 0;
		padding-bottom: 18px;
		border-bottom: 1px solid var(--line);
	}

	.shop-hours dt {
		color: var(--muted);
		font-size: 0.85rem;
	}

	.shop-hours dd {
		margin: 2px 0 0;
		font-size: 1.35rem;
	}

	.schedule-heading,
	.schedule-footer {
		justify-content: space-between;
	}

	.schedule-days {
		display: grid;
		grid-template-columns: repeat(auto-fit, minmax(105px, 1fr));
		gap: 8px;
		margin: 0;
		padding: 0;
		list-style: none;
	}

	.schedule-days li {
		display: grid;
		gap: 8px;
		justify-items: start;
		padding: 10px;
		border: 1px solid var(--line);
		border-radius: 6px;
		background: var(--panel-2);
	}

	.schedule-days time {
		display: grid;
		line-height: 1.2;
	}

	.schedule-days b {
		font-size: 1.45rem;
	}

	.availability {
		padding: 2px 7px;
		border-radius: 4px;
		background: var(--bg);
		color: var(--muted);
	}

	[data-status='open'] .availability {
		color: var(--ok);
	}

	[data-status='full'] .availability {
		color: var(--warn);
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
