type Account = { id: string; name: string; email: string; provider: string };
const key = 'herco-demo-account';
export const account = $state<{ current?: Account }>({
 current: typeof localStorage === 'undefined' ? undefined : JSON.parse(localStorage.getItem(key) ?? 'null') ?? undefined
});
export function signIn(name: string, email: string, provider: string) {
 const id = email.trim().toLowerCase();
 account.current = { id, name: name.trim() || id.split('@')[0], email: id, provider };
 localStorage.setItem(key, JSON.stringify(account.current));
}
export function signOut() {
 account.current = undefined;
 localStorage.removeItem(key);
}
export function browserBookingIds() {
 return JSON.parse(localStorage.getItem('herco-my-bookings') ?? '[]') as string[];
}
export function rememberBooking(id: string) {
 localStorage.setItem('herco-my-bookings', JSON.stringify([...browserBookingIds(), id]));
}
