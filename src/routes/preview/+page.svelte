<script lang="ts">
	import { resolve } from '$app/paths';
	import CompareSlider from '#lib/CompareSlider.svelte';
	import { bikeImage, bikes, colours, finishes, peso, serviceOf, sizes } from '#lib/config.ts';
	import { features } from '#lib/store.svelte.ts';

	let bike = $state.raw(bikes[1]);
	let colour = $state.raw(colours[0]);
	let finish = $state.raw(finishes[0]);

	const service = $derived(serviceOf(finish.serviceId));
</script>

<section class="section wrap stack">
	<p class="eyebrow">Bike preview</p>
	<h2>Build your finish</h2>
	{#if features().preview}
		<div class="layout">
			<div class="stack">
				<CompareSlider
					before={bikeImage(bike.id, colour.id, 'stock')}
					after={bikeImage(bike.id, colour.id, finish.id)}
					alt="{bike.name} in {colour.name}"
				/>
				<p class="muted small">Placeholder artwork. Real photos of each model, colour and finish drop in file for file.</p>
			</div>
			<div class="stack">
				<p class="eyebrow">Model</p>
				<div class="stack tight">
					{#each bikes as b}
						<button class="opt" class:on={bike === b} onclick={() => (bike = b)}>
							<b>{b.name}</b><span class="small muted">{sizes[b.size]}</span>
						</button>
					{/each}
				</div>
				<p class="eyebrow">Colour: <span class="muted">{colour.name}</span></p>
				<div class="row">
					{#each colours as c}
						<button
							class="swatch"
							class:on={colour === c}
							style:background={c.hex}
							aria-label={c.name}
							onclick={() => (colour = c)}
						></button>
					{/each}
				</div>
				<p class="eyebrow">Finish</p>
				<div class="row">
					{#each finishes as f}
						<button class="opt half" class:on={finish === f} onclick={() => (finish = f)}><b>{f.name}</b></button>
					{/each}
				</div>
				<div class="card total row">
					<div>
						<p class="muted small">{service.name}, {bike.name}</p>
						<p class="display price">{peso(service.prices[bike.size])}</p>
					</div>
					<a class="btn" href={resolve(`/book?service=${service.id}&bike=${bike.id}&colour=${colour.id}`)}>Book this</a>
				</div>
			</div>
		</div>
	{:else}
		<p class="muted">The bike preview is part of the Pro package. Switch the demo to Pro in the footer to see it.</p>
	{/if}
</section>

<style>
	.layout {
		display: grid;
		gap: 24px;
	}

	.tight {
		gap: 8px;
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
			grid-template-columns: 3fr 2fr;
			align-items: start;
		}
	}
</style>
