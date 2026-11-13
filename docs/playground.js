// The playground calls the library, not a copy of it: `engine/number.js` is
// `src/examples/browser` built for JavaScript by the docs workflow. If the file
// is missing (a local checkout before a build), the page says so instead of
// pretending to compute.
const state = document.getElementById("engine-state");

let engine = null;
try {
  engine = await import("./engine/number.js");
} catch (err) {
  state.classList.add("bad");
  state.textContent =
    "the engine is not built in this copy of the site: run `moon build --target js --release` and copy the browser artifact to docs/engine/number.js";
}

const number = (value, fallback) => {
  const parsed = Number.parseInt(value, 10);
  return Number.isFinite(parsed) ? parsed : fallback;
};

// Each panel is a input list, an output element and one engine call. Results are
// printed as the engine returned them, including its refusals.
const panels = [
  {
    out: "expand-out",
    inputs: ["expand-n", "expand-d", "expand-p"],
    run: () =>
      engine.expand(
        number(document.getElementById("expand-n").value, 1),
        number(document.getElementById("expand-d").value, 7),
        number(document.getElementById("expand-p").value, 60),
      ),
  },
  {
    out: "pi-out",
    inputs: ["pi-p"],
    run: () => engine.pi(number(document.getElementById("pi-p").value, 100)),
  },
  {
    out: "format-out",
    inputs: ["format-value", "format-spec"],
    run: () =>
      engine.format(
        document.getElementById("format-value").value,
        document.getElementById("format-spec").value,
      ),
  },
  {
    out: "dissect-out",
    inputs: ["dissect-value"],
    run: () => engine.dissect(document.getElementById("dissect-value").value),
  },
];

const draw = (panel) => {
  if (!engine) return;
  const target = document.getElementById(panel.out);
  const started = performance.now();
  try {
    target.textContent = panel.run();
  } catch (err) {
    target.textContent = String(err);
  }
  const took = performance.now() - started;
  // The time is the browser's measurement of the call, not a library claim.
  const stamp = document.getElementById(panel.out + "-took");
  if (stamp) stamp.textContent = took.toFixed(1) + " ms in the browser";
};

let pending = 0;
const redraw = (panel) => {
  clearTimeout(pending);
  pending = setTimeout(() => draw(panel), 90);
};

for (const panel of panels) {
  for (const id of panel.inputs) {
    const input = document.getElementById(id);
    input.addEventListener("input", () => redraw(panel));
  }
}

if (engine) {
  state.textContent = "engine loaded from this library's JavaScript build";
  for (const panel of panels) draw(panel);
}
