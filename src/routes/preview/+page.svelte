<script lang="ts">
	import { onMount, tick } from 'svelte';
	import ActionIcon from '#lib/shared/ActionIcon.svelte';
	import { asset, resolve } from '$app/paths';

	import CompareSlider from '#lib/shared/CompareSlider.svelte';
	import ShowcaseLightbox from '#lib/shared/ShowcaseLightbox.svelte';
	import { photos } from '#lib/shared/config.ts';
	import { powderShowcase, showcaseCategories } from '#lib/shared/powder-showcase.ts';
	import { countByCategory, distributeColumns, filterPhotos, shownCount } from '#lib/shared/showcase-gallery.ts';
	import { features } from '#lib/demo/store.svelte.ts';

	const counts = countByCategory(powderShowcase);
	const filters = [{ id: 'all', label: 'All' }, ...showcaseCategories];
	let filter = $state('all');
	let pages = $state(1);
	let open = $state(-1);
	const matching = $derived(filterPhotos(powderShowcase, filter));
	const shown = $derived(shownCount(matching.length, pages));
	const src = (slug: string, width: 480 | 960) => asset(`photos/showcase/${slug}-${width}.webp` as Parameters<typeof asset>[0]);

	// Fixed columns (2, 3 or 4 by screen width) so "Show more" only adds photos at the bottom and nothing moves.
	// The wall is drawn only after the real column count is known (the page is built without a screen), so it never re-flows on load.
	let columnCount = $state(2);
	let ready = $state(false);
	const columns = $derived(distributeColumns(matching.slice(0, shown), columnCount));
	onMount(() => {
		const wide = matchMedia('(min-width: 900px)');
		const medium = matchMedia('(min-width: 600px)');
		const update = () => { columnCount = wide.matches ? 4 : medium.matches ? 3 : 2; };
		update();
		ready = true;
		wide.addEventListener('change', update);
		medium.addEventListener('change', update);
		return () => { wide.removeEventListener('change', update); medium.removeEventListener('change', update); };
	});

	function choose(id: string) { filter = id; pages = 1; }

	// Keyboard and screen-reader users continue from the first new photo (the button may disappear).
	// The page stays where it is: the new photos are below the "Show more" button.
	async function showMore() {
		const first = shown;
		pages++;
		await tick();
		document.querySelector<HTMLButtonElement>(`.masonry .tile[data-index="${first}"]`)?.focus({ preventScroll: true });
	}
</script>

<svelte:head><title>Showcase | HERCO</title></svelte:head>

<section class="section wrap stack showcase">
	<div class="intro">
		<div class="stack">
			<p class="eyebrow">Showcase</p>
			<h1>Real work from the HERCO shop</h1>
			<p class="muted">{powderShowcase.length} photos of wheels, bikes and parts coated in the shop. Tap any photo to see it full size.</p>
		</div>
		<div><a class="btn" href={resolve('/book?service=wheel-colour')}><ActionIcon name="calendar" />Book powder coating</a></div>
	</div>

	{#if import.meta.env.MODE === 'worker' || features().preview}
		<div class="card ceramic">
			<CompareSlider before={photos.before} after={photos.after} alt="Scooter coated by the shop" loading="eager" />
			<div class="stack">
				<p class="eyebrow">Ceramic coating</p>
				<h2>Before and after</h2>
				<p class="muted">Drag the slider to compare a glossy black ceramic finish.</p>
				<div><a class="btn sm ghost" href={resolve('/book?service=ceramic')}><ActionIcon name="calendar" />Book ceramic coating</a></div>
			</div>
		</div>

		<div class="chips" role="group" aria-label="Filter photos">
			{#each filters as option (option.id)}
				<button type="button" class="chip" aria-pressed={filter === option.id} onclick={() => choose(option.id)}>
					{option.label}<span class="count">{counts[option.id] ?? 0}</span>
				</button>
			{/each}
		</div>

		<div class="masonry" role="list" aria-label="Powder coating photos" aria-busy={!ready}>
			{#if ready}{#each columns as column, columnIndex (columnIndex)}
				<div class="column" role="presentation">
					{#each column as { photo, index } (photo.slug)}
						<figure role="listitem">
							<button type="button" class="tile" data-index={index} onclick={() => (open = index)} aria-label={`View larger: ${photo.title}`}>
								<img src={src(photo.slug, 480)} srcset={`${src(photo.slug, 480)} 480w, ${src(photo.slug, 960)} 960w`}
									sizes="(min-width: 1100px) 260px, (min-width: 900px) 24vw, (min-width: 600px) 32vw, 48vw"
									alt={photo.alt} width={photo.w} height={photo.h} loading={index < 4 ? 'eager' : 'lazy'} decoding="async" />
								<span class="label">{photo.finish ?? photo.title}</span>
							</button>
						</figure>
					{/each}
				</div>
			{/each}{/if}
		</div>

		<div class="more">
			<p class="muted small" aria-live="polite">Showing {shown} of {matching.length} photos</p>
			{#if shown < matching.length}
				<button type="button" class="btn ghost" onclick={showMore}><ActionIcon name="add" />Show {Math.min(24, matching.length - shown)} more</button>
			{/if}
		</div>

		<ShowcaseLightbox photos={matching} bind:index={open} />
	{:else}
		<p class="muted">The showcase is part of the Pro package. Switch the demo to Pro in the footer to see it.</p>
	{/if}
</section>

<style>
	.showcase h1 { font-size: clamp(2rem, 7vw, 3.2rem); }
	.intro { display: flex; flex-wrap: wrap; align-items: end; justify-content: space-between; gap: 16px; }
	.intro p { margin: 0; }

	/* Compact card so the photo wall starts near the top, even on phones. */
	.ceramic { display: grid; grid-template-columns: minmax(0, 42%) 1fr; gap: 12px; padding: 10px; align-items: center; }
	.ceramic h2 { font-size: clamp(1.2rem, 4vw, 1.8rem); }
	.ceramic p { margin: 0; }
	.ceramic .muted { font-size: .9rem; }
	@media (min-width: 760px) {
		.ceramic { grid-template-columns: minmax(0, 220px) 1fr; padding: 16px; gap: 24px; }
	}

	.chips { display: flex; gap: 8px; overflow-x: auto; padding: 2px 2px 6px; scrollbar-width: thin; }
	.chip {
		display: inline-flex;
		align-items: center;
		gap: 6px;
		flex: none;
		min-height: 40px;
		padding: 6px 14px;
		border: 1px solid var(--line);
		border-radius: 999px;
		background: var(--panel);
		color: var(--text);
		font: inherit;
		font-weight: 650;
		cursor: pointer;
	}
	.chip[aria-pressed='true'] { border-color: var(--accent-fill); background: var(--accent-fill); color: var(--accent-ink); }
	.count { font-size: .8rem; opacity: .8; font-variant-numeric: tabular-nums; }

	/* Masonry with fixed columns (the page code splits the photos), so adding photos never moves the ones already shown. */
	.masonry { display: flex; align-items: flex-start; gap: 8px; }
	.masonry[aria-busy='true'] { min-height: 80vh; }
	.column { display: grid; flex: 1 1 0; min-width: 0; gap: 8px; }
	@media (min-width: 600px) { .masonry, .column { gap: 12px; } }
	figure { margin: 0; }

	.tile {
		position: relative;
		display: block;
		width: 100%;
		padding: 0;
		border: 0;
		border-radius: 6px;
		overflow: hidden;
		background: var(--panel-2);
		cursor: zoom-in;
	}
	.tile img { display: block; width: 100%; height: auto; transition: transform .25s ease; }
	.tile:hover img, .tile:focus-visible img { transform: scale(1.03); }
	.tile:focus-visible { outline: 3px solid var(--accent); outline-offset: 2px; }
	.label {
		position: absolute;
		left: 6px;
		bottom: 6px;
		max-width: calc(100% - 12px);
		padding: 3px 8px;
		border-radius: 4px;
		background: #000b;
		color: #fff;
		font-size: .78rem;
		font-weight: 700;
		text-align: start;
		overflow-wrap: anywhere;
	}

	.more { display: grid; justify-items: center; gap: 8px; }
	.more p { margin: 0; }
</style>
