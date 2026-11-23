<script lang="ts">
	// Centred sign-in card shared by the live and demo account screens: logo or mail icon, heading,
	// short subtext, optional Log in / Sign up tabs, then the screen's own buttons and form.
	import type { Snippet } from 'svelte';
	import { asset } from '$app/paths';
	import ActionIcon from './ActionIcon.svelte';
	import { photos } from './config.ts';
	import { nextTabIndex } from './auth-tabs.ts';

	type Tab = 'login' | 'signup';
	let {
		heading,
		subtext,
		icon = 'logo',
		tab,
		ontab,
		disabled = false,
		children
	}: {
		heading: string;
		subtext: string;
		icon?: 'logo' | 'mail';
		tab?: Tab;
		ontab?: (tab: Tab) => void;
		disabled?: boolean;
		children: Snippet;
	} = $props();

	const tabs: { id: Tab; label: string }[] = [{ id: 'login', label: 'Log in' }, { id: 'signup', label: 'Sign up' }];
	let tabButtons = $state<HTMLButtonElement[]>([]);

	function moveFocus(event: KeyboardEvent, index: number) {
		const next = nextTabIndex(event.key, index, tabs.length);
		if (next === null) return;
		event.preventDefault();
		ontab?.(tabs[next].id);
		tabButtons[next]?.focus();
	}
</script>

<div class="auth-card">
	{#if icon === 'mail'}
		<span class="auth-icon" aria-hidden="true"><ActionIcon name="mail" /></span>
	{:else}
		<img class="auth-logo" src={asset(photos.logo)} alt="" width="56" height="56" />
	{/if}
	<h1>{heading}</h1>
	<p class="muted auth-subtext">{subtext}</p>
	{#if tab && ontab}
		<div class="auth-tabs" role="tablist" aria-label="Log in or sign up">
			{#each tabs as item, index (item.id)}
				<button
					bind:this={tabButtons[index]}
					type="button"
					role="tab"
					id={'auth-tab-' + item.id}
					aria-selected={tab === item.id}
					aria-controls="auth-panel"
					tabindex={tab === item.id ? 0 : -1}
					{disabled}
					onclick={() => ontab(item.id)}
					onkeydown={(event) => moveFocus(event, index)}>{item.label}</button>
			{/each}
		</div>
		<div class="auth-body" id="auth-panel" role="tabpanel" aria-labelledby={'auth-tab-' + tab}>{@render children()}</div>
	{:else}
		<div class="auth-body">{@render children()}</div>
	{/if}
</div>

<style>
	.auth-card {
		width: min(100%, 440px);
		margin-inline: auto;
		padding: clamp(24px, 6vw, 40px) clamp(16px, 5vw, 36px);
		border: 1px solid var(--line);
		border-radius: 16px;
		background: var(--panel);
		box-shadow: 0 10px 30px var(--card-shadow);
		text-align: center;
	}
	.auth-logo { display: block; width: 56px; height: 56px; margin: 0 auto 16px; border-radius: 12px; }
	.auth-icon { display: grid; place-items: center; width: 56px; height: 56px; margin: 0 auto 16px; border-radius: 50%; background: color-mix(in srgb, var(--accent) 16%, transparent); color: var(--accent); }
	.auth-icon :global(svg) { width: 26px; height: 26px; }
	h1 { margin: 0; font: 800 clamp(1.6rem, 6vw, 2rem)/1.15 var(--body); font-style: normal; text-transform: none; letter-spacing: 0; }
	.auth-subtext { max-width: 34ch; margin: 8px auto 0; overflow-wrap: anywhere; }
	.auth-tabs { display: grid; grid-template-columns: 1fr 1fr; gap: 4px; margin-top: 24px; padding: 4px; border-radius: 12px; background: var(--panel-2); }
	.auth-tabs button { min-height: 44px; border: 0; border-radius: 9px; background: transparent; color: var(--muted); font: 700 1rem var(--body); cursor: pointer; }
	.auth-tabs button[aria-selected='true'] { background: var(--panel); color: var(--text); box-shadow: 0 1px 4px var(--card-shadow); }
	.auth-tabs button:focus-visible { outline: 2px solid var(--accent); outline-offset: 2px; }
	.auth-tabs button:disabled { cursor: not-allowed; }
	.auth-body { display: grid; gap: 16px; margin-top: 24px; text-align: left; }

	/* Shared form look for both account screens. */
	.auth-body :global(form) { display: grid; gap: 16px; }
	.auth-body :global(label) { display: grid; gap: 6px; font-weight: 650; font-size: .95rem; }
	/* Only labelled text fields and the password box; the code-step digit boxes keep their own size. */
	.auth-body :global(label > input), .auth-body :global(.password-input > input) { min-height: 48px; padding: 10px 14px; border-radius: 10px; font-size: 1rem; }
	.auth-body :global(.auth-primary) {
		display: inline-flex; align-items: center; justify-content: center; gap: 8px;
		width: 100%; min-height: 52px; padding: 10px 16px;
		border: 1px solid var(--accent-fill); border-radius: 10px;
		background: var(--accent-fill); color: var(--accent-ink); font: 750 1rem var(--body); cursor: pointer;
	}
	.auth-body :global(.auth-primary:hover:not(:disabled)) { filter: brightness(1.08); }
	.auth-body :global(.auth-primary:disabled) { cursor: not-allowed; opacity: .6; }
	.auth-body :global(.auth-primary:focus-visible) { outline: 2px solid var(--text); outline-offset: 2px; }
	.auth-body :global(.auth-link) { display: inline-flex; align-items: center; border: 0; padding: 0; min-height: 44px; color: var(--accent); background: transparent; font: inherit; font-weight: 650; cursor: pointer; }
	.auth-body :global(.auth-link:hover:not(:disabled)) { text-decoration: underline; }
	.auth-body :global(.auth-divider) { display: flex; align-items: center; gap: 14px; margin: 0; color: var(--muted); font-size: .9rem; }
	.auth-body :global(.auth-divider)::before, .auth-body :global(.auth-divider)::after { content: ''; flex: 1; border-top: 1px solid var(--line); }
</style>
