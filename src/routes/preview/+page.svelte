<script lang="ts">
	import { asset, resolve } from '$app/paths';

	import CompareSlider from '#lib/CompareSlider.svelte';
	import { photos, wheelColours } from '#lib/config.ts';
	import { features } from '#lib/store.svelte.ts';

	let colour = $state.raw(wheelColours[0]);
</script>

<section class="section wrap stack">
	<p class="eyebrow">Preview / Finished work</p>
	<h2>Coating results</h2>
	{#if features().preview}
		<div class="layout">
			<CompareSlider before={photos.before} after={photos.after} alt="Scooter coated by the shop" />
			<div class="stack">
				<h3>Ceramic coating</h3>
				<p class="muted">Drag the slider to explore the before-and-after photos of a glossy black finish.</p>
				<p class="eyebrow">Finish shown</p>
				<h3>Glossy black</h3>
				<div><a class="btn ghost" href={resolve('/book?service=ceramic-glossy')}>Book ceramic coating</a></div>
			</div>
		</div>

		<div class="layout">
			<div class="stack">
				<img class="photo" src={asset(colour.photo as Parameters<typeof asset>[0])} alt="Wheel coated in {colour.name}" />
				<p class="muted small">Real photo from the shop.</p>
			</div>
			<div class="stack">
				<h3>Powder coating results</h3>
				<p class="muted">Browse the finished wheels in each colour.</p>
			<p class="eyebrow">Wheel colour <span class="muted">{colour.name}</span></p>
			<div class="row" role="group" aria-label="Wheel colour">
				{#each wheelColours as c (c.id)}
					<button class="swatch" class:on={colour === c} style:background={c.hex} aria-label={c.name} aria-pressed={colour === c} title={c.name} onclick={() => (colour = c)}></button>
				{/each}
			</div>
				<div><a class="btn ghost" href={resolve(`/book?service=wheel-colour&notes=${encodeURIComponent("Wheel colour: " + colour.name)}`)}>Book powder coating</a></div>
				<img class="photo" src={asset(photos.wheelSet)} alt="Wheels coated in red, purple, pink and blue by the shop" />
				<p class="muted small">All four colours, fresh off the shop floor.</p>
			</div>
		</div>
	{:else}
		<p class="muted">The preview is part of the Pro package. Switch the demo to Pro in the footer to see it.</p>
	{/if}
</section>


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





	@media (min-width: 800px) {
		.layout {
			grid-template-columns: 1fr 1fr;
			align-items: start;
		}
	}
</style>
