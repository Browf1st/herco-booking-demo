<script lang="ts">
	import { resolve } from '$app/paths';
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import { notifyAccountChanged } from '#lib/workspace-navigation.ts';
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
	let name = $state('');
	let showForm = $state(false);
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

	async function enterAccount(response: Response) {
		const body = await response.json();
		const target = typeof body?.redirectTo === 'string' ? body.redirectTo : '';
		if (!target.startsWith('/') || target.startsWith('//')) throw new Error('Invalid account destination.');
		notifyAccountChanged();
		await goto(target, { invalidateAll: true });
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
				if (response.status === 403) {
					const body = await response.json().catch(() => null);
					if (emailEnabled && body?.code === 'email_confirmation_required') {
						setMode('confirm');
						notice = 'Confirm your email using the code sent when you created your account.';
						return;
					}
					message = typeof body?.message === 'string' ? body.message : 'Could not sign in. Try again.';
					return;
				}
				message = await responseMessage(response, 'Could not sign in. Try again.');
				return;
			}
			await enterAccount(response);
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
			notifyAccountChanged();
			setMode('login');
		} catch {
			message = 'Could not reach the account service. Try again.';
		} finally {
			busy = false;
		}
	}

	function setMode(next: typeof mode) {
		mode = next;
		showForm = next === 'confirm' || next === 'recover' || next === 'reset-password';
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
			const response = await sendAccountAction({ action, email: email.trim(), name: name.trim(), password, token });
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
				await enterAccount(response);
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
		const refresh = () => { void loadSession(); };
		window.addEventListener('herco-account-changed', refresh);
		void loadOptions();
		void loadSession().then(() => {
			if (checked && !session && new URL(window.location.href).searchParams.get('auth') === 'retry') {
				message = 'Social sign-in could not be completed. Please try again.';
			}
		});
		return () => window.removeEventListener('herco-account-changed', refresh);
	});
</script>

<svelte:head><title>Account | HERCO</title></svelte:head>
<section class="section wrap stack account">
 {#if message}<p role="alert">{message}</p>{/if}
 {#if notice}<p role="status">{notice}</p>{/if}
 {#if !checked}
  <p role="status">Checking your session…</p>
  {#if !busy && message}<button class="btn ghost" onclick={loadSession}>Try again</button>{/if}
 {:else if session}
  <div class="account-heading"><button class="btn sm ghost" onclick={signOut} disabled={busy}><ActionIcon name="logout" />Sign out</button></div>
  {#key session.id}<ServerContactProfile /><StaffSecurity bind:busy />{/key}
 {:else}
  <div class="login stack">
   <h1>{mode === 'login' ? 'Log In' : mode === 'signup' ? 'Sign Up' : headings[mode]}</h1>
   {#if mode === 'login' || mode === 'signup'}
    {#if emailEnabled}<p>{mode === 'login' ? 'New to HERCO?' : 'Already have an account?'} <button type="button" class="mode" disabled={busy} onclick={() => setMode(mode === 'login' ? 'signup' : 'login')}><ActionIcon name={mode === 'login' ? 'add' : 'login'} />{mode === 'login' ? 'Sign Up' : 'Log In'}</button></p>{/if}
   {/if}
   {#if !showForm && (mode === 'login' || mode === 'signup')}
    <div class="providers stack">
     {#each providers as provider (provider)}
      <button type="button" class="provider" class:facebook={provider === 'facebook'} disabled={busy} onclick={() => signInWith(provider)}>
       <span class="logo" aria-hidden="true">{#if provider === 'facebook'}<svg viewBox="0 0 24 24"><path fill="#395793" d="M14 24V13h4l.6-4H14V6.5C14 5.3 14.4 5 16 5h3V1.4C18 1.1 16.8 1 15.5 1 12 1 10 3 10 6.7V9H7v4h3v11z"/></svg>{:else}<svg viewBox="0 0 48 48"><path fill="#4285f4" d="M43.6 24.5c0-1.4-.1-2.8-.4-4.1H24v7.8h11a9.4 9.4 0 0 1-4.1 6.2v5h6.7c3.8-3.5 6-8.7 6-14.9z"/><path fill="#34a853" d="M24 44c5.5 0 10.1-1.8 13.5-4.9l-6.6-5.1a12.3 12.3 0 0 1-18.3-6.5H5.8v5.2A20.4 20.4 0 0 0 24 44z"/><path fill="#fbbc05" d="M12.6 27.5a12 12 0 0 1 0-7V15H5.8a20.2 20.2 0 0 0 0 18z"/><path fill="#ea4335" d="M24 12c3 0 5.7 1 7.8 3l5.8-5.8A19.7 19.7 0 0 0 24 4 20.4 20.4 0 0 0 5.8 15l6.8 5.5A12 12 0 0 1 24 12z"/></svg>{/if}</span>
       {mode === 'signup' ? 'Sign up' : 'Log in'} with {provider === 'facebook' ? 'Facebook' : 'Google'}
      </button>
     {/each}
     {#if providers.length}<p class="divider">or</p>{/if}
     <button type="button" class="provider email" disabled={busy} onclick={() => showForm = true}><ActionIcon name="mail" />{mode === 'signup' ? 'Sign up' : 'Log in'} with Email</button>
    </div>
   {:else}
    <form class="stack demo-form" onsubmit={submitAccount}>
     {#if mode === 'signup'}<label>Name<input bind:value={name} autocomplete="name" maxlength="120" required /></label>{/if}
     <label>Email<input type="email" bind:value={email} autocomplete="username" maxlength="254" required /></label>
     {#if mode === 'confirm' || mode === 'reset-password'}<label>Email verification code<input bind:value={token} autocomplete="one-time-code" inputmode="numeric" minlength="6" maxlength="10" pattern={'[0-9]{6,10}'} required /></label>{/if}
     {#if mode === 'login' || mode === 'signup' || mode === 'reset-password'}<label>{mode === 'reset-password' ? 'New password' : 'Password'}<input type="password" bind:value={password} autocomplete={mode === 'login' ? 'current-password' : 'new-password'} minlength={mode === 'login' ? undefined : 8} maxlength="1024" required /></label>{/if}
     <button class="provider email" type="submit" disabled={busy}><ActionIcon name="login" />{busy ? 'Please wait…' : buttonLabels[mode]}</button>
     {#if mode === 'login' && emailEnabled}<button class="mode" type="button" disabled={busy} onclick={() => setMode('recover')}>Forgot password?</button>{/if}
     {#if mode === 'reset-password'}<button class="mode" type="button" disabled={busy} onclick={() => setMode('recover')}>Request a new code</button>{/if}
     <button class="mode" type="button" disabled={busy} onclick={() => { setMode(mode === 'signup' ? 'signup' : 'login'); showForm = false; }}><ActionIcon name="back" />Back to sign-in options</button>
    </form>
   {/if}
  </div>
 {/if}
</section>
<style>
 .account { max-width: 680px; }
 .account-heading { display: flex; flex-wrap: wrap; align-items: center; justify-content: space-between; gap: .6rem; }

 .login { background: var(--panel); text-align: center; padding: clamp(20px, 5vw, 54px) 16px; border-radius: 8px; }
 .login h1 { font: 750 clamp(2.6rem, 7vw, 4.4rem)/1.1 var(--body); text-transform: none; }
 .providers, .demo-form { width: min(100%, 440px); margin: 24px auto 0; }
 .demo-form label { text-align: left; }
 .mode { border: 0; padding: 0; color: var(--accent); background: transparent; font: inherit; font-weight: 650; cursor: pointer; }
 .mode:hover { text-decoration: underline; }
 .provider { position: relative; min-height: 56px; padding: 10px 42px; border: 1px solid transparent; border-radius: 3px; background: #2465ca; color: #fff; font: 650 1rem var(--body); cursor: pointer; }
 .provider.facebook { background: #395793; }
 .provider.email { background: var(--panel); color: var(--text); border-color: var(--line); }
 .provider:hover { filter: brightness(.94); }
 .logo { position: absolute; inset-inline-start: 10px; top: 50%; translate: 0 -50%; display: grid; place-items: center; width: 30px; height: 30px; background: #fff; border-radius: 2px; }
 .logo svg { width: 23px; height: 23px; }
 .divider { display: flex; align-items: center; gap: 14px; margin-block: 8px; color: var(--muted); }
 .divider::before, .divider::after { content: ''; flex: 1; border-top: 1px solid var(--line); }
</style>
