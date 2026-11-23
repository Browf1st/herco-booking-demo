<script lang="ts" module>
	let fieldCount = 0;
</script>

<script lang="ts">
	// Password input with a show/hide button and an optional link (e.g. "Forgot password?") beside the label.
	import type { Snippet } from 'svelte';
	import ActionIcon from './ActionIcon.svelte';

	let {
		value = $bindable(''),
		label = 'Password',
		autocomplete = 'current-password',
		minlength,
		disabled = false,
		aside
	}: {
		value?: string;
		label?: string;
		autocomplete?: 'current-password' | 'new-password';
		minlength?: number;
		disabled?: boolean;
		aside?: Snippet;
	} = $props();

	// A plain counter keeps label ids unique without pulling extra Svelte runtime into every page.
	const id = 'password-' + ++fieldCount;
	let visible = $state(false);
</script>

<div class="password-field">
	<div class="password-label">
		<label for={id}>{label}</label>
		{#if aside}{@render aside()}{/if}
	</div>
	<div class="password-input">
		<input {id} type={visible ? 'text' : 'password'} bind:value {autocomplete} {minlength} maxlength="1024" required {disabled} aria-describedby={minlength ? id + '-hint' : undefined} />
		<button type="button" class="toggle" aria-label={visible ? 'Hide password' : 'Show password'} aria-pressed={visible} aria-controls={id} onclick={() => (visible = !visible)}>
			<ActionIcon name={visible ? 'hide' : 'view'} />
		</button>
	</div>
	{#if minlength}<p class="small muted" id={id + '-hint'}>At least {minlength} characters.</p>{/if}
</div>

<style>
	.password-field { display: grid; gap: 6px; }
	.password-label { display: flex; flex-wrap: wrap; align-items: baseline; justify-content: space-between; gap: 4px 12px; }
	.password-label label { font-weight: 650; font-size: .95rem; }
	.password-input { position: relative; }
	.password-input input { width: 100%; padding-inline-end: 52px; }
	.toggle {
		position: absolute; inset-block: 0; inset-inline-end: 2px; margin-block: auto;
		display: grid; place-items: center; width: 44px; height: 44px;
		border: 0; border-radius: 8px; background: transparent; color: var(--muted); cursor: pointer;
	}
	.toggle:hover { color: var(--text); }
	.toggle:focus-visible { outline: 2px solid var(--accent); outline-offset: -2px; }
	.toggle :global(svg) { width: 20px; height: 20px; }
	.small { margin: 0; }
</style>
