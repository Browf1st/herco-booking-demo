<script lang="ts">
	import { tick } from 'svelte';
	import { backspaceDigits, codeValue, emptyDigits, fillDigits } from './code-digits';

	// `value` is the finished code, or '' while a box is empty. To clear the boxes, re-create this
	// component (the account screen wraps it in a {#key}).
	let { value = $bindable(''), length = 6, disabled = false, label = 'Verification code' }:
		{ value?: string; length?: number; disabled?: boolean; label?: string } = $props();

	let boxes = $state<HTMLInputElement[]>([]);
	// One entry per box, so an empty box in the middle keeps the later digits in place.
	// Reading `length` once is intended: the parent re-creates this component when the length changes.
	// svelte-ignore state_referenced_locally
	let digits = $state<string[]>(emptyDigits(length));

	function update(next: string[]) {
		digits = next;
		value = codeValue(next);
	}

	async function focusBox(index: number) {
		await tick();
		const box = boxes[Math.max(0, Math.min(index, length - 1))];
		box?.focus();
		box?.select();
	}

	function handleInput(index: number, event: Event) {
		const input = event.currentTarget as HTMLInputElement;
		const next = fillDigits(digits, index, input.value, length);
		update(next.digits);
		input.value = next.digits[index];
		if (input.value) void focusBox(next.focus);
	}

	function handlePaste(index: number, event: ClipboardEvent) {
		const text = event.clipboardData?.getData('text') ?? '';
		if (!text) return;
		event.preventDefault();
		const next = fillDigits(digits, index, text, length);
		update(next.digits);
		void focusBox(next.focus);
	}

	function handleKey(index: number, event: KeyboardEvent) {
		if (event.key === 'Backspace' || event.key === 'Delete') {
			event.preventDefault();
			const next = event.key === 'Delete' ? fillDigits(digits, index, '', length) : backspaceDigits(digits, index);
			update(next.digits);
			void focusBox(next.focus);
		} else if (event.key === 'ArrowLeft' && index > 0) {
			event.preventDefault();
			void focusBox(index - 1);
		} else if (event.key === 'ArrowRight' && index < length - 1) {
			event.preventDefault();
			void focusBox(index + 1);
		}
	}
</script>

<fieldset class="code-input" {disabled}>
	<legend>{label}</legend>
	<div class="boxes">
		{#each digits as digit, index (index)}
			<input
				bind:this={boxes[index]}
				value={digit}
				type="text"
				inputmode="numeric"
				pattern="[0-9]*"
				maxlength={index === 0 ? length : 1}
				autocomplete={index === 0 ? 'one-time-code' : 'off'}
				aria-label={'Digit ' + (index + 1) + ' of ' + length}
				oninput={(event) => handleInput(index, event)}
				onpaste={(event) => handlePaste(index, event)}
				onkeydown={(event) => handleKey(index, event)}
				onfocus={(event) => event.currentTarget.select()}
			/>
		{/each}
	</div>
</fieldset>

<style>
	.code-input { border: 0; margin: 0; padding: 0; min-width: 0; }
	legend { padding: 0; margin-bottom: .5rem; font-weight: 650; }
	.boxes { display: flex; justify-content: center; gap: clamp(4px, 1.6vw, 10px); }
	input {
		width: clamp(36px, 11vw, 52px); height: clamp(46px, 13vw, 60px); padding: 0;
		border: 1px solid var(--line); border-radius: 8px; background: var(--bg, transparent); color: var(--text);
		font: 750 clamp(1.25rem, 5vw, 1.6rem)/1 var(--body); text-align: center;
	}
	input:focus { outline: 2px solid var(--accent); outline-offset: 1px; border-color: var(--accent); }
	fieldset:disabled input { opacity: .6; }
</style>
