<script lang="ts">
	import { resolve } from '$app/paths';
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import { notifyAccountChanged } from '#lib/shared/workspace-navigation.ts';
	import ActionIcon from '#lib/shared/ActionIcon.svelte';
	import StaffSecurity from '#lib/live/StaffSecurity.svelte';
	import ServerContactProfile from '#lib/live/ServerContactProfile.svelte';
	import CodeInput from '#lib/live/CodeInput.svelte';
	import AuthShell from '#lib/shared/AuthShell.svelte';
	import PasswordField from '#lib/shared/PasswordField.svelte';
	import { codeLength, maskEmail, DEFAULT_CODE_LENGTH } from '#lib/live/code-digits.ts';
	import { currentTheme, setTheme, themeOptions, THEME_EVENT, type ThemeChoice } from '#lib/shared/theme.ts';

	type Session = { id: string; email: string | null };
	type AccountAction = 'signup' | 'confirm' | 'recover' | 'reset-password';
	type Provider = 'google' | 'facebook';

	let session = $state<Session | null>(null);
	let checked = $state(false);
	let busy = $state(false);
	let email = $state('');
	let name = $state('');
	let password = $state('');
	let token = $state('');
	let message = $state('');
	let notice = $state('');
	let mode = $state<'login' | AccountAction>('login');
	let emailEnabled = $state(false);
	let providers = $state<Provider[]>([]);
	let otpLength = $state(DEFAULT_CODE_LENGTH);
	let theme = $state<ThemeChoice>('system');
	let editEmail = $state(false);
	// Bumped to clear the code boxes (new code requested or email changed).
	let codeResets = $state(0);
	const codeStep = $derived(mode === 'confirm' || mode === 'reset-password');
	const showEmailField = $derived(!codeStep || editEmail || !email.trim());

	const sessionUrl = resolve('/api/auth/session');
	const accountUrl = resolve('/api/auth/account');
	const headings = {
		login: 'Sign in', signup: 'Create account', confirm: 'Confirm your email',
		recover: 'Reset your password', 'reset-password': 'Choose a new password'
	} as const;
	const buttonLabels = {
		login: 'Log in', signup: 'Create account', confirm: 'Confirm email',
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
		token = password = message = notice = '';
		editEmail = false;
	}

	async function resendCode() {
		if (busy) return;
		if (!email.trim()) { message = 'Enter your email address first.'; return; }
		busy = true;
		message = notice = '';
		try {
			const response = await sendAccountAction({ action: mode === 'confirm' ? 'resend' : 'recover', email: email.trim() });
			if (!response.ok) {
				message = await responseMessage(response, 'Could not send a new code. Try again.');
				return;
			}
			token = '';
			codeResets++;
			editEmail = false;
			notice = 'If an account uses this address, a new code will arrive by email.';
		} catch {
			message = 'Could not reach the account service. Try again.';
		} finally {
			busy = false;
		}
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
			otpLength = codeLength(options.otpLength);
			const supported: Provider[] = ['google', 'facebook'];
			providers = supported.filter(provider => options.providers?.[provider] === true);
		} catch {
			// Password sign-in stays available if the optional sign-in settings cannot be loaded.
		}
	}

	onMount(() => {
		const refresh = () => { void loadSession(); };
		const syncTheme = () => { theme = currentTheme(); };
		syncTheme();
		// Another tab changed the theme: read the new value from the event, since the layout may not have applied it yet.
		const syncStoredTheme = (event: StorageEvent) => {
			if (event.key === 'herco-theme' || event.key === null) theme = event.newValue === 'light' || event.newValue === 'dark' ? event.newValue : 'system';
		};
		window.addEventListener(THEME_EVENT, syncTheme);
		window.addEventListener('storage', syncStoredTheme);
		window.addEventListener('herco-account-changed', refresh);
		void loadOptions();
		void loadSession().then(() => {
			if (checked && !session && new URL(window.location.href).searchParams.get('auth') === 'retry') {
				message = 'Social sign-in could not be completed. Please try again.';
			}
		});
		return () => {
			window.removeEventListener('herco-account-changed', refresh);
			window.removeEventListener(THEME_EVENT, syncTheme);
			window.removeEventListener('storage', syncStoredTheme);
		};
	});
</script>

<svelte:head><title>Account | HERCO</title></svelte:head>
<section class="section wrap stack account">
 <!-- When signed out, these alerts show inside the sign-in card instead (accountForm). -->
 {#if !checked || session}
  {#if message}<p role="alert">{message}</p>{/if}
  {#if notice}<p role="status">{notice}</p>{/if}
 {/if}
 {#if !checked}
  <p role="status">Checking your session…</p>
  {#if !busy && message}<button class="btn ghost" onclick={loadSession}>Try again</button>{/if}
 {:else if session}
  <header class="account-header">
   <span class="avatar" aria-hidden="true">{(session.email ?? '?').slice(0, 1).toUpperCase()}</span>
   <div class="account-title"><h1>Account</h1>{#if session.email}<p class="muted small">{session.email}</p>{/if}</div>
  </header>
  {#key session.id}<ServerContactProfile /><StaffSecurity bind:busy />{/key}
  <section class="card stack" aria-labelledby="appearance-heading">
   <h2 id="appearance-heading" class="section-title"><ActionIcon name="sun" /> Appearance</h2>
   <p class="small muted">Choose how HERCO looks on this device.</p>
   <div class="theme-options" role="radiogroup" aria-labelledby="appearance-heading">
    {#each themeOptions as option (option.value)}
     <label class="theme-option" class:active={theme === option.value}>
      <input type="radio" name="account-theme" value={option.value} checked={theme === option.value} onchange={() => setTheme(option.value)} />
      {option.label}
     </label>
    {/each}
   </div>
  </section>
  <section class="card signout-row" aria-labelledby="signout-heading">
   <div><h2 id="signout-heading" class="section-title">Sign out</h2><p class="small muted">Sign out of HERCO on this device.</p></div>
   <button class="btn sm ghost signout" onclick={signOut} disabled={busy}><ActionIcon name="logout" />Sign out</button>
  </section>
 {:else if codeStep}
  <AuthShell icon="mail" heading={mode === 'confirm' ? 'Check your email' : headings[mode]}
   subtext={showEmailField ? 'Enter your email and the ' + otpLength + '-digit code we sent you.' : 'We sent a ' + otpLength + '-digit code to ' + maskEmail(email) + '.'}>
   {@render accountForm()}
  </AuthShell>
 {:else if mode === 'recover'}
  <AuthShell heading={headings.recover} subtext="Enter your account email and we'll send you a code to reset your password.">
   {@render accountForm()}
  </AuthShell>
 {:else}
  <AuthShell heading={mode === 'signup' ? 'Create your account' : 'Welcome back'}
   subtext={mode === 'signup' ? 'Sign up to book faster, track your bookings and earn HERCO Points.' : 'Log in to book visits, see your bookings and use HERCO Points.'}
   tab={emailEnabled ? (mode === 'signup' ? 'signup' : 'login') : undefined} ontab={(next) => { if (!busy && next !== mode) setMode(next); }}>
   {#if providers.length}
    <div class="providers stack">
     {#each providers as provider (provider)}
      <button type="button" class="provider" class:facebook={provider === 'facebook'} disabled={busy} onclick={() => signInWith(provider)}>
       <span class="logo" aria-hidden="true">{#if provider === 'facebook'}<svg viewBox="0 0 24 24"><path fill="#395793" d="M14 24V13h4l.6-4H14V6.5C14 5.3 14.4 5 16 5h3V1.4C18 1.1 16.8 1 15.5 1 12 1 10 3 10 6.7V9H7v4h3v11z"/></svg>{:else}<svg viewBox="0 0 48 48"><path fill="#4285f4" d="M43.6 24.5c0-1.4-.1-2.8-.4-4.1H24v7.8h11a9.4 9.4 0 0 1-4.1 6.2v5h6.7c3.8-3.5 6-8.7 6-14.9z"/><path fill="#34a853" d="M24 44c5.5 0 10.1-1.8 13.5-4.9l-6.6-5.1a12.3 12.3 0 0 1-18.3-6.5H5.8v5.2A20.4 20.4 0 0 0 24 44z"/><path fill="#fbbc05" d="M12.6 27.5a12 12 0 0 1 0-7V15H5.8a20.2 20.2 0 0 0 0 18z"/><path fill="#ea4335" d="M24 12c3 0 5.7 1 7.8 3l5.8-5.8A19.7 19.7 0 0 0 24 4 20.4 20.4 0 0 0 5.8 15l6.8 5.5A12 12 0 0 1 24 12z"/></svg>{/if}</span>
       {mode === 'signup' ? 'Sign up' : 'Log in'} with {provider === 'facebook' ? 'Facebook' : 'Google'}
      </button>
     {/each}
    </div>
    <p class="auth-divider">or use your email</p>
   {/if}
   {@render accountForm()}
  </AuthShell>
 {/if}
</section>

{#snippet accountForm()}
 {#if message}<p class="auth-alert" role="alert">{message}</p>{/if}
 {#if notice}<p class="auth-notice" role="status">{notice}</p>{/if}
 <form onsubmit={submitAccount}>
  {#if mode === 'signup'}<label>Name<input bind:value={name} autocomplete="name" maxlength="120" required /></label>{/if}
  {#if showEmailField}<label>Email<input type="email" bind:value={email} autocomplete="username" maxlength="254" required /></label>{/if}
  {#if codeStep}{#key mode + ':' + otpLength + ':' + codeResets}<CodeInput bind:value={token} length={otpLength} disabled={busy} label="Email verification code" />{/key}{/if}
  {#if mode === 'login'}
   <PasswordField bind:value={password}>
    {#snippet aside()}{#if emailEnabled}<button class="auth-link small" type="button" disabled={busy} onclick={() => setMode('recover')}>Forgot password?</button>{/if}{/snippet}
   </PasswordField>
  {:else if mode === 'signup' || mode === 'reset-password'}
   <PasswordField bind:value={password} label={mode === 'reset-password' ? 'New password' : 'Password'} autocomplete="new-password" minlength={8} />
  {/if}
  <button class="auth-primary" type="submit" disabled={busy || (codeStep && token.length !== otpLength)}><ActionIcon name={codeStep ? 'check' : mode === 'signup' ? 'add' : mode === 'recover' ? 'send' : 'login'} />{busy ? 'Please wait…' : buttonLabels[mode]}</button>
  {#if codeStep}
   <p class="code-links small">
    <span>Didn't get it? <button class="auth-link" type="button" disabled={busy} onclick={resendCode}>Resend code</button></span>
    {#if !showEmailField}<button class="auth-link" type="button" disabled={busy} onclick={() => { editEmail = true; token = ''; codeResets++; }}>Use a different email</button>{/if}
   </p>
  {/if}
  {#if mode !== 'login' && mode !== 'signup'}<button class="auth-link back" type="button" disabled={busy} onclick={() => setMode('login')}><ActionIcon name="back" />Back to log in</button>{/if}
 </form>
{/snippet}
<style>
 .account { max-width: 680px; }
 .account-header { display: flex; align-items: center; gap: 14px; }
 .account-title { min-width: 0; }
 .account-title h1 { font: 800 clamp(1.8rem, 5vw, 2.4rem)/1.1 var(--body); font-style: normal; text-transform: none; }
 .account-title p { overflow-wrap: anywhere; }
 .avatar { flex: none; display: grid; place-items: center; width: 52px; height: 52px; border-radius: 50%; background: var(--accent); color: #fff; font: 800 1.4rem var(--body); }
 .section-title { font: 750 1.25rem/1.2 var(--body); font-style: normal; text-transform: none; }
 .theme-options { display: flex; flex-wrap: wrap; gap: 8px; }
 .theme-option { display: inline-flex; align-items: center; gap: .45rem; min-height: 44px; padding: 8px 14px; border: 1px solid var(--line); border-radius: 999px; cursor: pointer; }
 .theme-option input { width: auto; margin: 0; }
 .theme-option.active { border-color: var(--accent); outline: 1px solid var(--accent); }
 .signout-row { display: flex; flex-wrap: wrap; align-items: center; justify-content: space-between; gap: 12px; }
 .signout:hover:not(:disabled) { color: #c62828; border-color: #c62828; }

 .code-links { display: flex; flex-wrap: wrap; justify-content: space-between; gap: 8px; margin: 0; }
 .back { display: inline-flex; align-items: center; gap: 6px; justify-self: center; min-height: 44px; }
 .auth-alert, .auth-notice { margin: 0; padding: 10px 14px; border-radius: 10px; border: 1px solid var(--line); background: var(--panel-2); }
 .auth-alert { border-color: color-mix(in srgb, var(--accent) 55%, var(--line)); }

 .provider { position: relative; min-height: 56px; padding: 10px 42px; border: 1px solid transparent; border-radius: 3px; background: #2465ca; color: #fff; font: 650 1rem var(--body); cursor: pointer; }
 .provider.facebook { background: #395793; }
 .provider:hover { filter: brightness(.94); }
 .logo { position: absolute; inset-inline-start: 10px; top: 50%; translate: 0 -50%; display: grid; place-items: center; width: 30px; height: 30px; background: #fff; border-radius: 2px; }
 .logo svg { width: 23px; height: 23px; }
</style>
