<script lang="ts">
	import { resolve } from '$app/paths';
	import { onMount } from 'svelte';

	type Factor = { id: string; name: string };
	type StaffStatus =
		| { staff: false }
		| { staff: true; verified: boolean; needsExistingVerification: boolean; factors: Factor[] };
	type Enrollment = { factorId: string; qrCode: string; secret: string };
	let { busy = $bindable(false) }: { busy?: boolean } = $props();
	let status = $state<StaffStatus>();
	let enrollment = $state<Enrollment>();
	let factorId = $state('');
	let code = $state('');
	let message = $state('');
	const enrollmentUrl = resolve('/api/auth/mfa');
	const verificationUrl = resolve('/api/staff/mfa');

	async function fetchStatus() {
		const response = await fetch(enrollmentUrl, { headers: { accept: 'application/json' } });
		if (!response.ok) throw new Error('Could not check staff security. Try again.');
		const value: StaffStatus = await response.json();
		status = value;
		factorId = value.staff ? value.factors[0]?.id ?? '' : '';
	}

	async function run(action: () => Promise<void>) {
		if (busy) return;
		busy = true;
		message = '';
		try {
			await action();
		} catch (failure) {
			message = failure instanceof Error && failure.name !== 'TypeError'
				? failure.message : 'Could not reach the staff account service. Try again.';
		} finally {
			busy = false;
		}
	}

	async function post(url: string, input: Record<string, string>) {
		const response = await fetch(url, {
			method: 'POST',
			headers: { accept: 'application/json', 'content-type': 'application/json' },
			body: JSON.stringify(input)
		});
		if (response.ok) return response;
		const body = await response.json().catch(() => null);
		throw new Error(typeof body?.message === 'string' ? body.message : 'Could not verify your authenticator.');
	}

	function start() {
		return run(async () => {
			const response = await post(enrollmentUrl, { action: 'enroll' });
			enrollment = await response.json();
			code = '';
		});
	}

	function verify(event: SubmitEvent) {
		event.preventDefault();
		return run(async () => {
			if (enrollment) {
				await post(enrollmentUrl, { action: 'confirm-enrollment', factorId: enrollment.factorId, code });
				enrollment = undefined;
			} else {
				await post(verificationUrl, { factorId, code });
			}
			code = '';
			await fetchStatus();
		});
	}

	onMount(() => { void run(fetchStatus); });
</script>

{#if status?.staff || message}
	<section class="card stack" aria-labelledby="staff-security">
		<h2 id="staff-security">Staff security</h2>
		{#if message}<p role="alert">{message}</p>{/if}
		{#if !status}
			<div><button class="btn ghost" type="button" disabled={busy} onclick={() => run(fetchStatus)}>Try again</button></div>
		{:else if status.staff}
			{#if status.verified}
				<p>Your staff session is verified.</p>
				<div><a class="btn" href={resolve('/admin')}>Open staff workspace</a></div>
			{:else if enrollment || status.factors.length}
				{#if enrollment}
					<p>Scan this QR code in your authenticator app or enter the setup key manually.</p>
					<img class="enrollment-qr" width="192" height="192" src={enrollment.qrCode} alt="Authenticator setup QR code" />
					<details><summary>Show setup key</summary><code>{enrollment.secret}</code></details>
				{/if}
				<form class="stack" onsubmit={verify}>
					{#if !enrollment && status.factors.length > 1}
						<label>Authenticator
							<select bind:value={factorId} disabled={busy}>
								{#each status.factors as factor (factor.id)}<option value={factor.id}>{factor.name}</option>{/each}
							</select>
						</label>
					{/if}
					<label>Six-digit authenticator code
						<input bind:value={code} type="text" inputmode="numeric" pattern="[0-9]{6}" maxlength="6" autocomplete="one-time-code" disabled={busy} required />
					</label>
					<div class="row">
						<button class="btn" type="submit" disabled={busy}>{busy ? 'Verifying…' : 'Verify authenticator'}</button>
						{#if enrollment}
							<button class="btn ghost" type="button" disabled={busy} onclick={() => { enrollment = undefined; code = ''; message = ''; }}>Cancel setup</button>
						{/if}
					</div>
				</form>
			{:else if status.needsExistingVerification}
				<p>Your account uses an existing verification method. Ask the shop administrator for help setting up an authenticator app.</p>
			{:else}
				<p>Set up an authenticator app to verify your account before opening the staff workspace.</p>
				<div><button class="btn" type="button" disabled={busy} onclick={start}>{busy ? 'Starting setup…' : 'Set up authenticator'}</button></div>
			{/if}
		{/if}
	</section>
{/if}

<style>
	.enrollment-qr { max-width: 100%; background: white; padding: .5rem; }
	details code { display: block; overflow-wrap: anywhere; }
</style>
