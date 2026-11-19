<script lang="ts">
	import { resolve } from '$app/paths';
	import { onMount } from 'svelte';
	import ActionIcon from '#lib/ActionIcon.svelte';
	import StaffSecurity from '#lib/StaffSecurity.svelte';
	import ServerContactProfile from '#lib/ServerContactProfile.svelte';

	type Session = { id: string; email: string | null };
	type AccountAction = 'signup' | 'confirm' | 'recover' | 'reset-password';
	type Provider = 'google' | 'facebook';

	let session = $state<Session | null>(null);
	let checked = $state(false);
	let busy = $state(false);
	let email = $state('');
	let password = $state('');
	let token = $state('');
	let message = $state('');
	let notice = $state('');
	let mode = $state<'login' | AccountAction>('login');
	let emailEnabled = $state(false);
	let providers = $state<Provider[]>([]);

	const sessionUrl = resolve('/api/auth/session');
	const accountUrl = resolve('/api/auth/account');
	const headings = {
		login: 'Sign in', signup: 'Create account', confirm: 'Confirm your email',
		recover: 'Reset your password', 'reset-password': 'Choose a new password'
	} as const;
	const buttonLabels = {
		login: 'Sign in', signup: 'Create account', confirm: 'Confirm email',
		recover: 'Send reset code', 'reset-password': 'Save new password'
	} as const;

	function readSession(value: unknown): Session {
		if (
			!value || typeof value !== 'object' ||
			!('id' in value) || typeof value.id !== 'string' ||
			!('email' in value) || (value.email !== null && typeof value.email !== 'string')
		) throw new Error('The account service returned an unexpected response.');
		return { id: value.id, email: value.email };
	}

	async function responseMessage(response: Response, fallback: string) {
		const body = await response.json().catch(() => null);
		return typeof body?.message === 'string' ? body.message : fallback;
	}

	async function loadSession() {
		busy = true;
		message = '';
		try {
			const response = await fetch(sessionUrl, { headers: { accept: 'application/json' } });
			if (response.status === 401) {
				session = null;
			} else if (response.ok) {
				session = readSession(await response.json());
			} else {
				throw new Error(await responseMessage(response, 'Could not check your account. Try again.'));
			}
			checked = true;
		} catch (error) {
			message = error instanceof Error && error.name !== 'TypeError'
				? error.message
				: 'Could not reach the account service. Try again.';
		} finally {
			busy = false;
		}
	}

	async function signIn(event: SubmitEvent) {
		event.preventDefault();
		if (busy) return;
		busy = true;
		message = '';
		try {
			const response = await fetch(sessionUrl, {
				method: 'POST',
				headers: { accept: 'application/json', 'content-type': 'application/json' },
				body: JSON.stringify({ email: email.trim(), password })
			});
			if (!response.ok) {
				message = await responseMessage(response, 'Could not sign in. Try again.');
				return;
			}
			await loadSession();
		} catch {
			message = 'Could not reach the account service. Try again.';
		} finally {
			password = '';
			busy = false;
		}
	}

	async function signOut() {
		if (busy) return;
		busy = true;
		message = '';
		try {
			const response = await fetch(sessionUrl, {
				method: 'DELETE',
				headers: { accept: 'application/json' }
			});
			if (!response.ok) {
				message = await responseMessage(response, 'Could not sign out. Try again.');
				return;
			}
			session = null;
			setMode('login');
		} catch {
			message = 'Could not reach the account service. Try again.';
		} finally {
			busy = false;
		}
	}

	function setMode(next: typeof mode) {
		mode = next;
		token = password = message = notice = '';
	}

	function sendAccountAction(body: Record<string, string>) {
		return fetch(accountUrl, {
			method: 'POST',
			headers: { accept: 'application/json', 'content-type': 'application/json' },
			body: JSON.stringify(body)
		});
	}

	async function submitAccount(event: SubmitEvent) {
		if (mode === 'login') return signIn(event);
		event.preventDefault();
		if (busy) return;
		const action = mode;
		busy = true;
		message = notice = '';
		try {
			const response = await sendAccountAction({ action, email: email.trim(), password, token });
			if (!response.ok) {
				message = await responseMessage(response, 'Could not complete that step. Try again.');
				return;
			}
			if (action === 'signup') {
				setMode('confirm');
				notice = 'If signup is available for this address, a confirmation code will arrive by email.';
			} else if (action === 'recover') {
				setMode('reset-password');
				notice = 'If an account uses this address, a reset code will arrive by email.';
			} else {
				setMode('login');
				await loadSession();
				notice = action === 'confirm' ? 'Email confirmed.' : 'Your password was updated.';
			}
		} catch {
			message = 'Could not reach the account service. Try again.';
		} finally {
			busy = false;
		}
	}

	async function signInWith(provider: Provider) {
		if (busy) return;
		busy = true;
		message = '';
		try {
			const response = await sendAccountAction({ action: 'oauth', provider });
			if (!response.ok) {
				message = await responseMessage(response, 'Could not start social sign-in. Try again.');
				return;
			}
			const data = await response.json();
			const destination = typeof data.url === 'string' ? new URL(data.url) : null;
			if (!destination || destination.protocol !== 'https:') throw new Error();
			window.location.assign(destination);
		} catch {
			message = 'Could not start social sign-in. Try again.';
		} finally {
			busy = false;
		}
	}

	async function loadOptions() {
		try {
			const response = await fetch(accountUrl, { headers: { accept: 'application/json' } });
			if (!response.ok) return;
			const options = await response.json();
			emailEnabled = options.email === true;
			const supported: Provider[] = ['google', 'facebook'];
			providers = supported.filter(provider => options.providers?.[provider] === true);
		} catch {
			// Password sign-in stays available if the optional sign-in settings cannot be loaded.
		}
	}

	onMount(() => {
		void loadOptions();
		void loadSession().then(() => {
			if (checked && !session && new URL(window.location.href).searchParams.get('auth') === 'retry') {
				message = 'Social sign-in could not be completed. Please try again.';
			}
		});
	});
</script>

<svelte:head><title>Account | HERCO</title></svelte:head>

<section class="section wrap stack account">
	<h1>{session ? 'Your account' : headings[mode]}</h1>
	{#if message}<p role="alert">{message}</p>{/if}
	{#if notice}<p role="status">{notice}</p>{/if}
	{#if !checked}
		{#if busy || !message}
			<p class="muted" role="status">Checking your session…</p>
		{:else}
			<div class="row"><button type="button" class="btn ghost" onclick={loadSession}>Try again</button></div>
		{/if}
	{:else if session}
		<div class="card stack">
			<p>{#if session.email}Signed in as <strong>{session.email}</strong>{:else}You’re signed in.{/if}</p>
			<div class="row">
				<a class="btn" href={resolve('/my-bookings')}>My bookings</a>
				<button type="button" class="btn ghost" onclick={signOut} disabled={busy}>
					<ActionIcon name="logout" />{busy ? 'Signing out…' : 'Sign out'}
				</button>
			</div>
		</div>
		{#key session.id}<ServerContactProfile /><StaffSecurity bind:busy />{/key}
	{:else}
		<form class="card stack" onsubmit={submitAccount}>
			<label>Email <input type="email" bind:value={email} autocomplete="username" maxlength="254" required /></label>
			{#if mode === 'confirm' || mode === 'reset-password'}
				<label>Six-digit email code <input type="text" bind:value={token} autocomplete="one-time-code" inputmode="numeric" maxlength="6" pattern="[0-9]{6}" required /></label>
			{/if}
			{#if mode === 'login' || mode === 'signup' || mode === 'reset-password'}
				<label>{mode === 'reset-password' ? 'New password' : 'Password'}
					<input type="password" bind:value={password} autocomplete={mode === 'login' ? 'current-password' : 'new-password'} minlength={mode === 'login' ? undefined : 8} maxlength="1024" required />
				</label>
			{/if}
			<div class="row">
				<button type="submit" class="btn" disabled={busy}><ActionIcon name="login" />{busy ? 'Please wait…' : buttonLabels[mode]}</button>
				{#if mode !== 'login'}
					<button type="button" class="btn ghost" onclick={() => setMode('login')} disabled={busy}>Back to sign in</button>
				{/if}
				{#if mode === 'reset-password'}
					<button type="button" class="btn ghost" onclick={() => setMode('recover')} disabled={busy}>Request a new code</button>
				{/if}
			</div>
		</form>
		{#if mode === 'login' && emailEnabled}
			<div class="row">
				<button type="button" class="btn ghost" onclick={() => setMode('signup')} disabled={busy}>Create account</button>
				<button type="button" class="btn ghost" onclick={() => setMode('confirm')} disabled={busy}>Enter confirmation code</button>
				<button type="button" class="btn ghost" onclick={() => setMode('recover')} disabled={busy}>Forgot password?</button>
			</div>
		{/if}
		{#if mode === 'login' && providers.length}
			<div class="row">
				{#each providers as provider (provider)}
					<button type="button" class="btn ghost" onclick={() => signInWith(provider)} disabled={busy}>Continue with {provider === 'google' ? 'Google' : 'Facebook'}</button>
				{/each}
			</div>
		{/if}
	{/if}
</section>

<style>
	.account { max-width: 680px; }
</style>
