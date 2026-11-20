<script lang="ts">
	import ActionIcon from '#lib/shared/ActionIcon.svelte';
	import { asset, resolve } from '$app/paths';

	import CompareSlider from '#lib/shared/CompareSlider.svelte';
	import { photos } from '#lib/shared/config.ts';
	import { powderConcept, powderShowcase } from '#lib/shared/powder-showcase.ts';
	import { features } from '#lib/demo/store.svelte.ts';
</script>

<section class="section wrap stack">
	<p class="eyebrow">Showcase / Finished work</p>
	<h2>Coating results</h2>
	{#if import.meta.env.MODE === 'worker' || features().preview}
		<div class="layout">
			<CompareSlider before={photos.before} after={photos.after} alt="Scooter coated by the shop" loading="eager" />
			<div class="stack">
				<h3>Ceramic coating</h3>
				<p class="muted">Drag the slider to explore the before-and-after photos of a glossy black finish.</p>
				<p class="eyebrow">Finish shown</p>
				<h3>Glossy black</h3>
				<div><a class="btn ghost" href={resolve('/book?service=ceramic')}><ActionIcon name="calendar" />Book ceramic coating</a></div>
			</div>
		</div>

		<div class="powder stack">
			<div class="powder-intro">
				<div class="stack">
					<h3>Powder coating results</h3>
					<p class="muted">Wheels, CVT covers, brackets and springs finished in the shop. Tap a finish to book it.</p>
				</div>
				<div><a class="btn ghost" href={resolve('/book?service=wheel-colour')}><ActionIcon name="calendar" />Book powder coating</a></div>
			</div>
			<ul class="gallery">
				{#each powderShowcase as item, index (item.slug)}
					<li>
						<figure>
							<img src={asset(`photos/powder/${item.slug}-480.webp` as Parameters<typeof asset>[0])}
								srcset={`${asset(`photos/powder/${item.slug}-480.webp` as Parameters<typeof asset>[0])} 480w, ${asset(`photos/powder/${item.slug}-800.webp` as Parameters<typeof asset>[0])} 800w`}
								sizes="(min-width: 1100px) 340px, (min-width: 700px) 31vw, 46vw"
								alt={item.alt} width="480" height="640" loading={index < 2 ? 'eager' : 'lazy'} decoding="async" />
							<figcaption>
								{#if item.finish}<a href={resolve(`/book?service=wheel-colour&finish=${encodeURIComponent(item.finish)}`)}>{item.title}</a>{:else}{item.title}{/if}
							</figcaption>
						</figure>
					</li>
				{/each}
			</ul>
			<img class="photo" src={asset(powderConcept.photo)} srcset={`${asset(powderConcept.small)} 480w, ${asset(powderConcept.photo)} 800w`}
				sizes="(min-width: 1100px) 1060px, calc(100vw - 32px)" alt={powderConcept.alt} width="800" height="671" loading="lazy" decoding="async" />
			<p class="muted small">Real photos from the shop.</p>
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
		height: auto;
		border: 1px solid var(--line);
		border-radius: 6px;
	}

	.powder {
		padding-top: 24px;
		border-top: 1px solid var(--line);
	}

	.powder-intro {
		display: flex;
		flex-wrap: wrap;
		align-items: end;
		justify-content: space-between;
		gap: 12px;
	}

	.gallery {
		display: grid;
		grid-template-columns: repeat(2, minmax(0, 1fr));
		gap: 12px;
		margin: 0;
		padding: 0;
		list-style: none;
	}

	figure {
		margin: 0;
	}

	.gallery img {
		display: block;
		width: 100%;
		height: auto;
		aspect-ratio: 3 / 4;
		object-fit: cover;
		border: 1px solid var(--line);
		border-radius: 6px;
		background: var(--panel);
	}

	figcaption {
		margin-top: 6px;
		font-size: .9rem;
		font-weight: 650;
	}

	figcaption a {
		color: inherit;
		text-decoration-color: var(--accent);
		text-underline-offset: 3px;
	}

	@media (min-width: 700px) {
		.gallery {
			grid-template-columns: repeat(3, minmax(0, 1fr));
			gap: 16px;
		}
	}





	@media (min-width: 800px) {
		.layout {
			grid-template-columns: 1fr 1fr;
			align-items: start;
		}
	}
</style>
