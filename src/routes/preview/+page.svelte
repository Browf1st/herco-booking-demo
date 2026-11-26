<script lang="ts">
	import { onMount, tick } from 'svelte';
	import ActionIcon from '#lib/shared/ActionIcon.svelte';
	import { asset, resolve } from '$app/paths';
	import { goto } from '$app/navigation';
	import { page } from '$app/state';

	import CeramicShowcase from '#lib/shared/CeramicShowcase.svelte';
	import { ceramicPairs, ceramicPhotos } from '#lib/shared/ceramic-showcase.ts';
	import ShowcaseLightbox from '#lib/shared/ShowcaseLightbox.svelte';
	import { powderShowcase, showcaseCategories } from '#lib/shared/powder-showcase.ts';
	import { countByCategory, distributeColumns, filterPhotos, shownCount } from '#lib/shared/showcase-gallery.ts';

	const counts = countByCategory(powderShowcase);
	const filters = [{ id: 'all', label: 'All' }, ...showcaseCategories];
	const tabs = [
		{ id: 'powder', label: 'Powder Coating', count: powderShowcase.length },
		{ id: 'ceramic', label: 'Ceramic Coating & Polish', count: ceramicPairs.length + ceramicPhotos.length }
	] as const;
	type ShowcaseTab = (typeof tabs)[number]['id'];
	const activeTab = $derived((page.shallow?.url ?? page.url).searchParams.get('tab') === 'ceramic' ? 'ceramic' : 'powder');
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

	function selectTab(id: ShowcaseTab) {
		if (id === activeTab) return;
		return goto(resolve(id === 'ceramic' ? '/preview?tab=ceramic' : '/preview'), { shallow: true, replace: true });
	}

	function handleTabKey(event: KeyboardEvent, id: ShowcaseTab) {
		let target: ShowcaseTab;
		switch (event.key) {
			case 'Home': target = 'powder'; break;
			case 'End': target = 'ceramic'; break;
			case 'ArrowLeft':
			case 'ArrowRight': target = id === 'ceramic' ? 'powder' : 'ceramic'; break;
			default: return;
		}
		event.preventDefault();
		selectTab(target);
		document.getElementById(`showcase-tab-${target}`)?.focus();
	}

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
	<div class="showcase-header">
		<div class="stack">
			<p class="eyebrow">Showcase <span>Crafted in-house</span></p>
			<h1>Real work from<br />the HERCO shop</h1>
			<p class="muted description">High-durability powder coating, mirror-finish ceramic paint restoration, and precision surface detailing built to conquer street, track, and weather.</p>
		</div>

			<a class="btn showcase-book" href={resolve(activeTab === 'ceramic' ? '/book?service=ceramic' : '/book?service=wheel-colour')}>
				<ActionIcon name="calendar" />
				{activeTab === 'ceramic' ? 'Book ceramic coating' : 'Book powder coating'}
			</a>

	</div>

		<div class="tabs" role="tablist" aria-label="Coating showcases">
			{#each tabs as tab (tab.id)}
				<button type="button" role="tab" id="showcase-tab-{tab.id}" aria-controls="showcase-{tab.id}"
					aria-selected={activeTab === tab.id} tabindex={activeTab === tab.id ? 0 : -1}
					onclick={() => selectTab(tab.id)} onkeydown={(event) => handleTabKey(event, tab.id)}>
					{tab.label}<span class="tab-count">{tab.count}</span>
				</button>
			{/each}
		</div>
		<div id="showcase-ceramic" role="tabpanel" aria-labelledby="showcase-tab-ceramic" hidden={activeTab !== 'ceramic'}>
			{#if activeTab === 'ceramic'}<CeramicShowcase />{/if}
		</div>

		<div id="showcase-powder" role="tabpanel" aria-labelledby="showcase-tab-powder" hidden={activeTab !== 'powder'}>
			{#if activeTab === 'powder'}
				<div class="stack">
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
				</div>
			{/if}
		</div>

</section>

<style>
	.showcase-header { display: flex; flex-wrap: wrap; align-items: end; justify-content: space-between; gap: 16px; }
	.showcase-header .eyebrow { display: flex; align-items: center; gap: 10px; margin: 0; }
	.eyebrow::before { content: ''; width: 8px; height: 8px; border-radius: 50%; background: var(--accent-fill); }
	.eyebrow span { padding-inline-start: 10px; border-inline-start: 1px solid var(--line); color: var(--muted); letter-spacing: .05em; }
	.showcase h1 { margin: 0; font-size: clamp(2rem, 5vw, 3.75rem); font-style: italic; line-height: 1; text-transform: uppercase; }
	.description { max-width: 66ch; margin: 0; }
	.showcase-book { min-height: 44px; font-family: var(--display); font-style: italic; text-transform: uppercase; }

	.tabs { display: flex; flex-wrap: wrap; column-gap: 12px; border-bottom: 1px solid var(--line); }
	.tabs button {
		display: inline-flex;
		align-items: center;
		gap: 8px;
		min-height: 44px;
		padding: 8px clamp(5px, 1.2vw, 16px);
		border: 0;
		border-bottom: 2px solid transparent;
		background: transparent;
		color: var(--muted);
		font: 700 clamp(.75rem, 2.4vw, 1.05rem) var(--display);
		text-transform: uppercase;
		cursor: pointer;
	}
	.tabs button::before { content: ''; width: 7px; height: 7px; border-radius: 50%; }
	.tabs button[aria-selected='true'] { border-bottom-color: var(--accent-fill); color: var(--text); }
	.tabs button[aria-selected='true']::before { background: var(--accent-fill); }
	.tab-count { padding: 2px 7px; border: 1px solid var(--line); border-radius: 999px; font-size: .72rem; }
	.tabs button[aria-selected='true'] .tab-count { border-color: var(--accent-fill); }
	.tabs button:focus-visible { outline: 2px solid var(--accent); outline-offset: 2px; }

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
