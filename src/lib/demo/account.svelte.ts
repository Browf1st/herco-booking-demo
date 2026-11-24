import { saveFanProfile } from './operations.svelte';

type Account = { id: string; name: string; email: string; provider: string; phone?: string };
const key = 'herco-demo-account';
const phoneKey = (id: string) => `herco-demo-profile-phone:${id}`;
// These records simulate identity only. Replace with verified Supabase sessions;
// browser booking IDs must never grant production access to a customer's records.
function read(key: string) {
 try { return localStorage.getItem(key); } catch { return null; }
}
function restoreAccount(): Account | undefined {
 try {
  const value = JSON.parse(read(key) ?? 'null');
  if (!value || !['id', 'name', 'email', 'provider'].every(field => typeof value[field] === 'string')) return;
  return { id: value.id, name: value.name, email: value.email, provider: value.provider,
   phone: typeof value.phone === 'string' ? value.phone : '' };
 } catch { return undefined; }
}
export const account = $state<{ current?: Account }>({
 current: import.meta.env.MODE === 'worker' ? undefined : restoreAccount()
});
export function signIn(name: string, email: string, provider: string) {
 const id = email.trim().toLowerCase();
 const next = { id, name: name.trim() || id.split('@')[0], email: id, provider, phone: read(phoneKey(id)) ?? '' };
 localStorage.setItem(key, JSON.stringify(next));
 saveFanProfile(next);
 account.current = next;
}
export function saveProfilePhone(phone: string) {
 const current = account.current;
 if (!current) return;
 localStorage.setItem(phoneKey(current.id), phone);
 current.phone = phone;
 localStorage.setItem(key, JSON.stringify(current));
 saveFanProfile(current);
}
// Demo "Maintenance reminders" switch (F-017). On unless the visitor turned it off on this browser.
const remindersKey = (id: string) => `herco-demo-maintenance-reminders:${id}`;
export function maintenanceRemindersOn(id: string) {
 return read(remindersKey(id)) !== 'off';
}
export function setMaintenanceReminders(on: boolean) {
 const current = account.current;
 if (!current) return;
 try { localStorage.setItem(remindersKey(current.id), on ? 'on' : 'off'); } catch { /* keeps the choice for this visit only */ }
}
export function signOut() {
 account.current = undefined;
 localStorage.removeItem(key);
}
export function browserBookingIds() {
 try {
  const ids: unknown = JSON.parse(read('herco-my-bookings') ?? '[]');
  return Array.isArray(ids) ? ids.filter((id): id is string => typeof id === 'string') : [];
 } catch { return []; }
}
export function rememberBooking(id: string) {
 localStorage.setItem('herco-my-bookings', JSON.stringify([...new Set([...browserBookingIds(), id])]));
}
