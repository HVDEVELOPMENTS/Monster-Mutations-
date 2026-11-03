// Shared SVG drawing helpers for the Monster Mutations icon and thumbnail.
const INK = "#2a0f45";

function rad(cx, cy, r, stops, id) {
	return `<radialGradient id="${id}" cx="${cx}" cy="${cy}" r="${r}">${stops
		.map(([o, c, a]) => `<stop offset="${o}" stop-color="${c}" stop-opacity="${a ?? 1}"/>`)
		.join("")}</radialGradient>`;
}
function lin(x1, y1, x2, y2, stops, id) {
	return `<linearGradient id="${id}" x1="${x1}" y1="${y1}" x2="${x2}" y2="${y2}">${stops
		.map(([o, c, a]) => `<stop offset="${o}" stop-color="${c}" stop-opacity="${a ?? 1}"/>`)
		.join("")}</linearGradient>`;
}

function rays(cx, cy, n, len, color, opacity, rot = 0) {
	let s = "";
	for (let i = 0; i < n; i++) {
		const a0 = ((i / n) * 2 * Math.PI) + rot;
		const a1 = a0 + Math.PI / n;
		s += `<polygon points="${cx},${cy} ${cx + Math.cos(a0) * len},${cy + Math.sin(a0) * len} ${cx + Math.cos(a1) * len},${cy + Math.sin(a1) * len}" fill="${color}" opacity="${opacity}"/>`;
	}
	return s;
}

function sparkle(x, y, r, color = "#fff", opacity = 1) {
	const k = r * 0.22;
	return `<path d="M${x},${y - r} Q${x + k},${y - k} ${x + r},${y} Q${x + k},${y + k} ${x},${y + r} Q${x - k},${y + k} ${x - r},${y} Q${x - k},${y - k} ${x},${y - r}Z" fill="${color}" opacity="${opacity}"/>`;
}

function bubble(x, y, r, tint = "#ffffff") {
	return `<g opacity="0.85"><circle cx="${x}" cy="${y}" r="${r}" fill="${tint}" fill-opacity="0.18" stroke="#fff" stroke-opacity="0.8" stroke-width="${Math.max(2, r * 0.08)}"/>
	<ellipse cx="${x - r * 0.35}" cy="${y - r * 0.4}" rx="${r * 0.32}" ry="${r * 0.18}" transform="rotate(-35 ${x - r * 0.35} ${y - r * 0.4})" fill="#fff" opacity="0.9"/></g>`;
}

function flame(x, y, w, h, fills) {
	let s = "";
	fills.forEach((f, i) => {
		const k = 1 - i * 0.28;
		const ww = w * k, hh = h * k, yy = y - i * 2;
		s += `<path d="M${x - ww / 2},${yy} C${x - ww * 0.7},${yy - hh * 0.45} ${x - ww * 0.1},${yy - hh * 0.55} ${x - ww * 0.05},${yy - hh}
			C${x + ww * 0.25},${yy - hh * 0.62} ${x + ww * 0.75},${yy - hh * 0.5} ${x + ww / 2},${yy} C${x + ww * 0.35},${yy + ww * 0.32} ${x - ww * 0.35},${yy + ww * 0.32} ${x - ww / 2},${yy}Z"
			fill="${f}" ${i === 0 ? `stroke="${INK}" stroke-width="5" stroke-linejoin="round"` : ""}/>`;
	});
	return s;
}

function crystal(bx, by, angle, len, w, id) {
	return `<g transform="rotate(${angle} ${bx} ${by})">
		<polygon points="${bx - w},${by + 10} ${bx - w * 1.15},${by - len * 0.6} ${bx},${by - len} ${bx + w * 1.15},${by - len * 0.6} ${bx + w},${by + 10}"
			fill="url(#${id})" stroke="${INK}" stroke-width="5" stroke-linejoin="round"/>
		<polygon points="${bx},${by + 10} ${bx},${by - len} ${bx + w * 1.15},${by - len * 0.6} ${bx + w},${by + 10}" fill="#ffffff" opacity="0.28"/>
		<polygon points="${bx - w * 0.75},${by - len * 0.15} ${bx - w * 0.85},${by - len * 0.55} ${bx - w * 0.35},${by - len * 0.75}" fill="#ffffff" opacity="0.75"/>
	</g>`;
}

function bolt(x, y, s, angle) {
	return `<g transform="translate(${x} ${y}) rotate(${angle}) scale(${s})">
		<polygon points="0,0 -14,-34 -2,-34 -12,-70 16,-26 4,-26 14,0" fill="#ffe94a" stroke="${INK}" stroke-width="${5 / s}" stroke-linejoin="round"/>
		<polygon points="-12,-70 16,-26 4,-26" fill="#fff" opacity="0.6"/>
	</g>`;
}

// A bubbly monster in a 240x240 box, body centred on (120,140).
// o: { id, body:[light,mid,dark], belly, iris, horns, mutation:'crystal'|'flame'|'storm'|'toxic'|'both', crystal:[c1,c2], aura }
function monster(o) {
	const id = o.id;
	const [bl, bm, bd] = o.body;
	const defs = `<defs>
		${rad("35%", "28%", "80%", [[0, bl], [0.55, bm], [1, bd]], id + "body")}
		${rad("50%", "40%", "60%", [[0, "#ffffff"], [1, o.belly]], id + "belly")}
		${rad("40%", "35%", "70%", [[0, "#fff8c2"], [0.5, o.iris], [1, o.irisDark ?? o.iris]], id + "iris")}
		${lin(0, 0, 0, 1, [[0, "#ffffff"], [0.35, (o.crystal ?? ["#7ff6ff"])[0]], [1, (o.crystal ?? ["#7ff6ff", "#2a7dff"])[1] ?? "#2a7dff"]], id + "cry")}
		${lin(0, 0, 0, 1, [[0, "#fffbe6"], [1, o.hornColor ?? "#ffcf6b"]], id + "horn")}
		${rad("50%", "50%", "50%", [[0, o.aura ?? "#ffffff", 0.95], [0.45, o.aura ?? "#ffffff", 0.5], [1, o.aura ?? "#ffffff", 0]], id + "aura")}
	</defs>`;
	const m = o.mutation;
	let back = "", front = "";

	if (o.aura) back += `<circle cx="120" cy="135" r="135" fill="url(#${id}aura)"/>`;

	if (m === "crystal" || m === "both") {
		const base = [[-78, 66, 13], [-50, 82, 16], [-22, 66, 13], [50, 78, 15], [78, 60, 12]];
		for (const [a, l, w] of base) {
			const r = 72, ar = (a - 90) * Math.PI / 180;
			back += crystal(120 + Math.cos(ar) * r, 142 + Math.sin(ar) * r, a, l, w, id + "cry");
		}
	}
	if (m === "flame") {
		back += `<g transform="rotate(62 200 175)">${flame(200, 175, 46, 95, ["#ff5a1f", "#ffb021", "#fff3a0"])}</g>`;
	}
	if (m === "toxic") {
		back += `<g>${[[-60, 40], [-20, 55], [25, 48], [62, 38]].map(([a, l]) => {
			const ar = (a - 90) * Math.PI / 180, bx = 120 + Math.cos(ar) * 72, by = 142 + Math.sin(ar) * 72;
			return `<g transform="rotate(${a} ${bx} ${by})"><rect x="${bx - 7}" y="${by - l}" width="14" height="${l + 10}" rx="7" fill="#c9ff5a" stroke="${INK}" stroke-width="5"/><circle cx="${bx}" cy="${by - l}" r="13" fill="#7cff3a" stroke="${INK}" stroke-width="5"/><circle cx="${bx - 4}" cy="${by - l - 4}" r="4" fill="#fff"/></g>`;
		}).join("")}</g>`;
	}

	// feet + arms
	back += `<ellipse cx="82" cy="218" rx="25" ry="15" fill="${bd}" stroke="${INK}" stroke-width="6"/>
		<ellipse cx="158" cy="218" rx="25" ry="15" fill="${bd}" stroke="${INK}" stroke-width="6"/>
		<ellipse cx="38" cy="165" rx="16" ry="25" transform="rotate(30 38 165)" fill="${bm}" stroke="${INK}" stroke-width="6"/>
		<ellipse cx="202" cy="165" rx="16" ry="25" transform="rotate(-30 202 165)" fill="${bm}" stroke="${INK}" stroke-width="6"/>`;

	if (o.horns) {
		back += `<path d="M72,88 C58,70 50,46 58,22 C72,40 88,56 98,72Z" fill="url(#${id}horn)" stroke="${INK}" stroke-width="6" stroke-linejoin="round"/>
			<path d="M168,88 C182,70 190,46 182,22 C168,40 152,56 142,72Z" fill="url(#${id}horn)" stroke="${INK}" stroke-width="6" stroke-linejoin="round"/>`;
	}
	if (m === "storm") {
		back += bolt(84, 78, 1.0, -28) + bolt(156, 78, 1.0, 28);
	}

	const body = `<path d="M120,52 C178,52 210,96 210,146 C210,196 172,222 120,222 C68,222 30,196 30,146 C30,96 62,52 120,52Z"
		fill="url(#${id}body)" stroke="${INK}" stroke-width="7"/>
		<ellipse cx="120" cy="178" rx="56" ry="38" fill="url(#${id}belly)" opacity="0.9"/>`;

	let spots = "";
	if (o.spots) {
		spots = o.spots.map(([x, y, r]) => `<circle cx="${x}" cy="${y}" r="${r}" fill="${o.spotColor}" opacity="0.85"/>`).join("");
	}

	const eye = (x) => `<ellipse cx="${x}" cy="124" rx="25" ry="29" fill="#fff" stroke="${INK}" stroke-width="6"/>
		<ellipse cx="${x + 3}" cy="128" rx="17" ry="21" fill="url(#${id}iris)"/>
		<ellipse cx="${x + 4}" cy="130" rx="9" ry="12" fill="${INK}"/>
		<circle cx="${x - 4}" cy="118" r="7" fill="#fff"/>
		<circle cx="${x + 9}" cy="139" r="3.5" fill="#fff"/>`;

	const face = eye(92) + eye(148) + `
		<path d="M94,166 Q120,206 146,166 Q120,174 94,166Z" fill="#5a0b2e" stroke="${INK}" stroke-width="6" stroke-linejoin="round"/>
		<ellipse cx="122" cy="183" rx="13" ry="7" fill="#ff7aa8"/>
		<polygon points="101,168 108,168 104.5,178" fill="#fff"/>
		<polygon points="132,168 139,168 135.5,178" fill="#fff"/>
		<ellipse cx="62" cy="160" rx="13" ry="8" fill="#ff6fae" opacity="0.6"/>
		<ellipse cx="178" cy="160" rx="13" ry="8" fill="#ff6fae" opacity="0.6"/>`;

	const gloss = `<ellipse cx="82" cy="82" rx="30" ry="13" transform="rotate(-32 82 82)" fill="#fff" opacity="0.6"/>
		<circle cx="118" cy="66" r="6" fill="#fff" opacity="0.6"/>`;

	if (m === "flame" || m === "both") {
		front += flame(120, 62, 60, 92, ["#ff4d1f", "#ffa31a", "#fff27a"]);
	}
	if (m === "crystal") {
		front += crystal(120, 60, 0, 48, 12, id + "cry");
	}
	if (m === "toxic") {
		front += `<path d="M60,92 Q72,70 120,66 Q168,70 180,92 Q170,98 166,116 Q160,98 150,104 Q146,124 138,104 Q126,96 116,110 Q110,96 100,102 Q94,120 86,100 Q78,96 72,112 Q68,96 60,92Z" fill="#8dff3c" stroke="${INK}" stroke-width="5" stroke-linejoin="round" opacity="0.95"/>
			<ellipse cx="96" cy="80" rx="16" ry="6" fill="#fff" opacity="0.6" transform="rotate(-12 96 80)"/>`;
	}

	return `<g>${defs}${back}${body}${spots}${gloss}${face}${front}</g>`;
}

function trainer() {
	return `<g stroke="${INK}" stroke-width="8" stroke-linejoin="round">
		<defs>
			${lin(0, 0, 0, 1, [[0, "#ff6a3d"], [1, "#d8204f"]], "shirt")}
			${lin(0, 0, 0, 1, [[0, "#4aa8ff"], [1, "#1b4fd6"]], "jeans")}
			${lin(0, 0, 0, 1, [[0, "#ffe7c2"], [1, "#f5bf86"]], "skin")}
			${lin(0, 0, 0, 1, [[0, "#3fd2ff"], [1, "#1270e0"]], "cap")}
			${rad("40%", "35%", "70%", [[0, "#ffffff"], [0.5, "#fff2a6"], [1, "#ffb21e"]], "egg")}
			${rad("50%", "50%", "50%", [[0, "#fff6a0", 0.95], [1, "#ffcc33", 0]], "eggglow")}
		</defs>
		<!-- legs -->
		<rect x="88" y="400" width="60" height="190" rx="10" fill="url(#jeans)"/>
		<rect x="152" y="400" width="60" height="190" rx="10" fill="url(#jeans)"/>
		<rect x="78" y="570" width="76" height="34" rx="14" fill="#fff"/>
		<rect x="146" y="570" width="76" height="34" rx="14" fill="#fff"/>
		<!-- raised pointing arm -->
		<g transform="rotate(-128 252 262)">
			<rect x="228" y="240" width="54" height="120" rx="12" fill="url(#shirt)"/>
			<rect x="230" y="350" width="50" height="80" rx="12" fill="url(#skin)"/>
		</g>
		<!-- torso -->
		<rect x="74" y="232" width="152" height="184" rx="18" fill="url(#shirt)"/>
		<path d="M120,262 L150,262 L162,300 L135,326 L108,300Z" fill="#ffd93b" stroke-width="6"/>
		<circle cx="128" cy="292" r="6" fill="${INK}" stroke="none"/>
		<circle cx="144" cy="292" r="6" fill="${INK}" stroke="none"/>
		<!-- arm holding egg -->
		<rect x="22" y="240" width="54" height="120" rx="12" fill="url(#shirt)"/>
		<rect x="24" y="350" width="50" height="70" rx="12" fill="url(#skin)"/>
		<circle cx="60" cy="430" r="92" fill="url(#eggglow)" stroke="none"/>
		<path d="M60,368 C96,368 112,420 112,446 C112,476 90,494 60,494 C30,494 8,476 8,446 C8,420 24,368 60,368Z" fill="url(#egg)"/>
		<circle cx="42" cy="430" r="11" fill="#ff5fb0" stroke-width="5"/>
		<circle cx="80" cy="410" r="8" fill="#5fd8ff" stroke-width="5"/>
		<circle cx="76" cy="462" r="10" fill="#9b6bff" stroke-width="5"/>
		<ellipse cx="38" cy="396" rx="12" ry="7" transform="rotate(-40 38 396)" fill="#fff" stroke="none" opacity="0.9"/>
		<!-- head -->
		<rect x="132" y="200" width="40" height="40" fill="url(#skin)"/>
		<rect x="78" y="88" width="144" height="134" rx="34" fill="url(#skin)"/>
		<ellipse cx="124" cy="152" rx="9" ry="14" fill="${INK}" stroke="none"/>
		<ellipse cx="176" cy="152" rx="9" ry="14" fill="${INK}" stroke="none"/>
		<circle cx="127" cy="146" r="3.5" fill="#fff" stroke="none"/>
		<circle cx="179" cy="146" r="3.5" fill="#fff" stroke="none"/>
		<path d="M122,182 Q150,212 180,182Z" fill="#fff" stroke-width="6"/>
		<ellipse cx="104" cy="182" rx="11" ry="6" fill="#ff8fb5" stroke="none" opacity="0.7"/>
		<ellipse cx="198" cy="182" rx="11" ry="6" fill="#ff8fb5" stroke="none" opacity="0.7"/>
		<!-- cap -->
		<path d="M74,124 C74,64 226,64 226,124Z" fill="url(#cap)"/>
		<path d="M150,118 L258,112 C266,124 256,134 240,134 L150,132Z" fill="#1270e0"/>
		<circle cx="150" cy="96" r="14" fill="#ffd93b" stroke-width="6"/>
		<ellipse cx="112" cy="90" rx="18" ry="7" transform="rotate(-20 112 90)" fill="#fff" stroke="none" opacity="0.6"/>
	</g>`;
}
