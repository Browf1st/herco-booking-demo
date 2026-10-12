<script lang="ts">
	import { resolve } from '$app/paths';
	import CompareSlider from '#lib/CompareSlider.svelte';
	import { peso, photos, serviceOf, sizes, wheelColours, type Size } from '#lib/config.ts';
	import { features } from '#lib/store.svelte.ts';

	const finishes = [serviceOf('ceramic-glossy'), serviceOf('ceramic-matte')];
	const wheels = serviceOf('wheel-colour');

	let size = $state<Size>('medium');
	let finish = $state.raw(finishes[0]);
	let colour = $state.raw(wheelColours[0]);
</script>

<section class="section wrap stack">
	<p class="eyebrow">Preview</p>
	<h2>See it before you book</h2>
	{#if features().preview}
		<p class="eyebrow">Your bike</p>
		<div class="row">
			{#each Object.entries(sizes) as [id, label]}
				<button class="opt third" class:on={size === id} onclick={() => (size = id as Size)}><b>{label}</b></button>
			{/each}
		</div>

		<div class="layout">
			<CompareSlider before={photos.before} after={photos.after} alt="Scooter coated by the shop" />
			<div class="stack">
				<h3>Ceramic coating</h3>
				<p class="muted">Drag the slider to compare a bike before and after the shop worked on it. Both sides are real photos.</p>
				<p class="eyebrow">Finish</p>
				<div class="row">
					{#each finishes as f}
						<button class="opt half" class:on={finish === f} onclick={() => (finish = f)}>
							<b>{f.name.replace(' Coating', '')}</b>
						</button>
					{/each}
				</div>
				{@render total(finish, '')}
			</div>
		</div>

		<div class="layout">
			<div class="stack">
				<img class="photo" src={colour.photo} alt="Wheel coated in {colour.name}" />
				<p class="muted small">Real photo from the shop.</p>
			</div>
			<div class="stack">
				<h3>Wheel colour</h3>
				<p class="muted">Pick a colour to see a wheel the shop coated in it.</p>
				<p class="eyebrow">Colour: <span class="muted">{colour.name}</span></p>
				<div class="row">
					{#each wheelColours as c}
						<button class="swatch" class:on={colour === c} style:background={c.hex} aria-label={c.name} onclick={() => (colour = c)}></button>
					{/each}
				</div>
				{@render total(wheels, `Wheel colour: ${colour.name}`)}
				<img class="photo" src={photos.wheelSet} alt="Wheels coated in red, purple, pink and blue by the shop" />
				<p class="muted small">All four colours, fresh off the shop floor.</p>
			</div>
		</div>
	{:else}
		<p class="muted">The preview is part of the Pro package. Switch the demo to Pro in the footer to see it.</p>
	{/if}
</section>

{#snippet total(service: typeof wheels, notes: string)}
	<div class="card total row">
		<div>
			<p class="muted small">{service.name}</p>
			<p class="display price">{peso(service.prices[size])}</p>
		</div>
		<a class="btn" href={resolve(`/book?service=${service.id}&size=${size}&notes=${encodeURIComponent(notes)}`)}>Book this</a>
	</div>
{/snippet}

<style>
	.layout {
		display: grid;
		gap: 24px;
		padding-top: 24px;
		border-top: 1px solid var(--line);
	}

	.photo {
		width: 100%;
		border: 1px solid var(--line);
		border-radius: 6px;
	}

	.swatch {
		width: 48px;
		height: 48px;
		border: 2px solid var(--line);
		border-radius: 50%;
		cursor: pointer;
	}

	.swatch.on {
		border-color: var(--text);
		box-shadow: 0 0 0 3px var(--accent);
	}

	.third {
		flex: 1 1 200px;
	}

	.half {
		flex: 1 1 140px;
	}

	.total {
		justify-content: space-between;
	}

	.price {
		font-size: 2.6rem;
	}

	@media (min-width: 800px) {
		.layout {
			grid-template-columns: 1fr 1fr;
			align-items: start;
		}
	}
</style>
