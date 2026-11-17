// Presentation preference only. Never store production credentials or roles here.
try {
	const theme = localStorage.getItem('herco-theme');
	if (theme === 'light' || theme === 'dark') document.documentElement.dataset.theme = theme;
} catch {}
const systemTheme = matchMedia('(prefers-color-scheme: dark)');
function updateThemeColor() {
	const theme = document.documentElement.dataset.theme;
	const dark = theme === 'dark' || (theme !== 'light' && systemTheme.matches);
	document.querySelector('meta[name="theme-color"]')?.setAttribute('content', dark ? '#11151c' : '#f6f7fa');
}
updateThemeColor();
systemTheme.addEventListener('change', updateThemeColor);
new MutationObserver(updateThemeColor).observe(document.documentElement, {
	attributes: true, attributeFilter: ['data-theme']
});
