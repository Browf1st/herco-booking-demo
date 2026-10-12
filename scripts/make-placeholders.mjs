// Generates original placeholder bike images into static/bikes; run with: node scripts/make-placeholders.mjs
import { mkdirSync, writeFileSync } from 'node:fs';
import { bikes, colours } from '../src/lib/config.ts';

const out = new URL('../static/bikes/', import.meta.url);

const mix = (a, b, t) =>
	'#' +
	[1, 3, 5]
		.map((i) => Math.round(parseInt(a.slice(i, i + 2), 16) * (1 - t) + parseInt(b.slice(i, i + 2), 16) * t))
		.map((n) => n.toString(16).padStart(2, '0'))
		.join('');

// Each shape list is a set of SVG path strings drawn on an 800 by 500 canvas with the floor at y 420.
const shapes = {
	scooter: {
		wheels: [[185, 365, 55], [610, 365, 55]],
		metal: ['M560 250L610 365', 'M548 150L520 128'],
		exhaust: 'M120 335L290 350L290 372L125 362Z',
		dark: ['M320 330L530 330L545 365L305 365Z', 'M215 320L320 320L310 372L200 372Z'],
		body: [
			'M528 150L572 150L588 255L548 335L500 335L520 250Z',
			'M130 250Q150 222 240 228L350 238L325 325L215 325L140 290Z',
			'M558 325Q610 280 662 325L650 335Q610 300 570 335Z'
		],
		seat: 'M165 200L340 208Q358 222 350 238L240 228L150 232Z',
		lamp: 'M560 165L576 165L580 195L564 195Z',
		shine: ['M160 246Q200 236 330 246L328 253Q200 244 162 254Z', 'M536 160L548 160L562 250L550 252Z']
	},
	sport: {
		wheels: [[185, 345, 75], [615, 345, 75]],
		metal: ['M548 215L615 345', 'M345 330L185 345', 'M535 200L505 172'],
		exhaust: 'M330 352L200 300L150 285L148 268L345 325Z',
		dark: ['M300 345L325 250L500 245L520 320L455 370L320 370Z'],
		body: [
			'M330 222Q410 160 505 205L515 250L335 252Z',
			'M135 195L275 215L262 250L205 246Z',
			'M500 200L560 190L590 228L560 280L515 250Z',
			'M548 300Q615 238 682 300L668 310Q615 262 562 310Z',
			'M325 372L455 372L432 398L345 398Z'
		],
		seat: 'M250 222L338 220L336 252L262 250Z',
		lamp: 'M572 205L588 228L576 240L566 215Z',
		shine: [
			'M350 215Q415 178 490 208L485 215Q415 190 355 222Z',
			'M160 205L260 220L258 226L165 211Z',
			'M515 208L555 200L558 206L518 215Z'
		]
	},
	adventure: {
		wheels: [[180, 342, 78], [620, 338, 82]],
		metal: ['M540 190L620 338', 'M340 330L180 342', 'M525 178L492 150'],
		exhaust: 'M300 335L150 250L120 250L115 232L160 228L320 315Z',
		dark: [
			'M295 350L320 245L505 240L525 325L460 378L315 378Z',
			'M100 200L215 205L215 215L100 212Z',
			'M320 380L460 380L440 402L340 402Z'
		],
		body: [
			'M325 215Q420 130 520 185L530 245L330 250Z',
			'M515 180L580 175L660 205L655 218L575 225L530 245Z',
			'M150 200L280 212L268 248L215 244Z',
			'M262 250L335 252L320 300L275 290Z'
		],
		seat: 'M240 208L335 212L332 250L265 248Z',
		lamp: 'M572 182L600 190L598 204L574 208Z',
		screen: 'M548 110L580 175L552 190L532 130Z',
		shine: ['M345 208Q420 150 505 190L500 198Q420 164 350 216Z', 'M585 185L645 206L643 211L584 192Z']
	}
};

const paths = (list, attrs) => list.map((d) => `<path d="${d}" ${attrs}/>`).join('');

function wheel([cx, cy, r], dirty) {
	const spokes = [0, 72, 144, 216, 288]
		.map((a) => `<path d="M${cx} ${cy}L${cx} ${cy - r * 0.66}" transform="rotate(${a} ${cx} ${cy})"/>`)
		.join('');
	return `<circle cx="${cx}" cy="${cy}" r="${r}" fill="#0c0d0f"/>
<g fill="none" stroke="${dirty ? '#6f6a61' : '#aab1bb'}" stroke-width="5">
<circle cx="${cx}" cy="${cy}" r="${r * 0.68}"/><circle cx="${cx}" cy="${cy}" r="${r * 0.38}" stroke-width="3"/>${spokes}</g>
<circle cx="${cx}" cy="${cy}" r="${r * 0.14}" fill="#2a2d33"/>`;
}

function image(bike, colour, finish) {
	const s = shapes[bike.id];
	const fill = { stock: mix(colour.hex, '#6b6258', 0.45), glossy: 'url(#gloss)', matte: mix(colour.hex, '#3a3d42', 0.16) }[finish];
	const shine = { stock: 0, glossy: 0.75, matte: 0.1 }[finish];
	return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 800 500">
<defs>
<radialGradient id="bg" cx=".5" cy=".42" r=".8"><stop offset="0" stop-color="#3a4049"/><stop offset="1" stop-color="#121418"/></radialGradient>
<linearGradient id="gloss" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${mix(colour.hex, '#ffffff', 0.35)}"/><stop offset=".45" stop-color="${colour.hex}"/><stop offset="1" stop-color="${mix(colour.hex, '#000000', 0.4)}"/></linearGradient>
<pattern id="dust" width="67" height="53" patternUnits="userSpaceOnUse"><rect width="67" height="53" fill="#7a6a52" opacity=".28"/><g fill="#c9b899" opacity=".4"><circle cx="8" cy="9" r="1.8"/><circle cx="31" cy="5" r="1.1"/><circle cx="52" cy="17" r="2.3"/><circle cx="19" cy="30" r="1.3"/><circle cx="41" cy="39" r="1.7"/><circle cx="61" cy="46" r="1"/><circle cx="6" cy="47" r="2"/></g></pattern>
</defs>
<rect width="800" height="500" fill="url(#bg)"/>
<rect y="420" width="800" height="80" fill="#0f1114"/>
<ellipse cx="400" cy="422" rx="310" ry="13" fill="${finish === 'glossy' ? mix(colour.hex, '#000000', 0.55) : '#000000'}" opacity=".6"/>
${paths(s.metal, 'fill="none" stroke="#8b929c" stroke-width="11" stroke-linecap="round"')}
${s.wheels.map((w) => wheel(w, finish === 'stock')).join('')}
<path d="${s.exhaust}" fill="${finish === 'stock' ? '#5d5a55' : '#878e98'}"/>
${paths(s.dark, 'fill="#22252b"')}
${paths(s.body, `fill="${fill}"`)}
${finish === 'stock' ? paths([...s.body, ...s.dark], 'fill="url(#dust)"') : ''}
<path d="${s.seat}" fill="#0e0f11"/>
${s.screen ? `<path d="${s.screen}" fill="#a9c0d6" opacity=".45"/>` : ''}
<path d="${s.lamp}" fill="#fff6cf"/>
${paths(s.shine, `fill="#ffffff" opacity="${shine}"`)}
<g font-family="Arial, sans-serif" font-size="14" fill="#7d8590"><text x="20" y="480">PLACEHOLDER IMAGE</text><text x="780" y="480" text-anchor="end">${bike.name} / ${colour.name} / ${finish}</text></g>
</svg>
`;
}

mkdirSync(out, { recursive: true });
for (const bike of bikes)
	for (const colour of colours)
		for (const finish of ['stock', 'glossy', 'matte'])
			writeFileSync(new URL(`${bike.id}-${colour.id}-${finish}.svg`, out), image(bike, colour, finish));
