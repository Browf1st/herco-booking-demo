<script lang="ts">
	import { asset } from '$app/paths';
	import CompareSlider from './CompareSlider.svelte';
	import { ceramicPairs, ceramicPhotos } from './ceramic-showcase.ts';

	const src = (slug: string, width: 480 | 960) => asset(`photos/ceramic/${slug}-${width}.webp` as Parameters<typeof asset>[0]);
</script>

<div class="stack">
	<div class="stack">
		<h2>Before and after ceramic coating</h2>
		<p class="muted">Move the slider to compare each finish.</p>
	</div>

	<div class="gallery">
		{#each ceramicPairs as pair, index (pair.title)}
			<figure>
				<CompareSlider before={pair.before} after={pair.after} alt={pair.title} loading={index === 0 ? 'eager' : 'lazy'} />
			</figure>
		{/each}
	</div>

	{#if ceramicPhotos.length}
		<h2>Finished ceramic coatings</h2>
		<div class="gallery">
			{#each ceramicPhotos as photo (photo.slug)}
				<figure>
					<img src={src(photo.slug, 480)} srcset={`${src(photo.slug, 480)} 480w, ${src(photo.slug, 960)} 960w`}
						sizes="(min-width: 1100px) 360px, (min-width: 900px) 32vw, (min-width: 600px) 48vw, 94vw"
						alt={photo.alt} width={photo.w} height={photo.h} loading="lazy" decoding="async" />
				</figure>
			{/each}
		</div>
	{/if}
</div>

<style>
	.gallery { display: grid; gap: 16px; }
	figure { position: relative; align-self: start; min-width: 0; margin: 0; }
	img { display: block; width: 100%; height: auto; border-radius: 6px; background: var(--panel-2); }

	@media (min-width: 600px) { .gallery { grid-template-columns: repeat(2, minmax(0, 1fr)); } }
	@media (min-width: 900px) { .gallery { grid-template-columns: repeat(3, minmax(0, 1fr)); } }
</style>
