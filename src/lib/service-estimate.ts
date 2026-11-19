export type PricedService = { price_centavos: number; max_centavos?: number | null; quote_required?: boolean };
const currency = new Intl.NumberFormat('en-PH', { style: 'currency', currency: 'PHP' });
const pesos = (centavos: number) => currency.format(centavos / 100);

export function displayServicePrice(line: PricedService) {
	if (line.quote_required) return 'Shop quote required';
	const minimum = pesos(line.price_centavos);
	return line.max_centavos == null || line.max_centavos === line.price_centavos
		? minimum : minimum + '–' + pesos(line.max_centavos);
}

export function displayEstimate(lines: readonly PricedService[], minimum: number) {
	const maximum = minimum + lines.reduce((sum, line) =>
		sum + (line.quote_required ? 0 : (line.max_centavos ?? line.price_centavos) - line.price_centavos), 0);
	const priced = maximum === minimum ? pesos(minimum) : pesos(minimum) + '–' + pesos(maximum);
	if (lines.some(line => line.quote_required)) return minimum ? priced + ' plus shop quote' : 'Shop quote required';
	return priced;
}
