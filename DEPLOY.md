# Publishing Pack Mule to the web (Netlify)

A standalone, professional page — just the game at your own URL
(`packmule.netlify.app`, or a custom domain). No marketplace, no other games.

Free. The whole thing is: **export the web build → drag the folder onto
Netlify**. About 15 minutes the first time.

---

## 1. One-time: install the web export templates

In the Godot editor:

1. **Editor → Manage Export Templates…**
2. **Download and Install** (it grabs the templates for your exact version,
   ~600 MB, one time).

## 2. Export the web build

1. **Project → Export…**
2. **Add… → Web.**
3. At the bottom, set **Export Path** to the `web/` folder in this repo and
   name the file **`index.html`** (Netlify serves `index.html` automatically).
   - i.e. export to `…/PackMule/web/index.html`.
4. Make sure **Export With Debug is UNCHECKED**, then **Export Project**.

That writes `index.html`, `index.wasm`, `index.pck`, `index.js`, and a few
helper files into `web/`. The `web/_headers` file is already there — leave it.

> If a browser later shows a SharedArrayBuffer / cross-origin error, it means
> the headers in `web/_headers` didn't get applied — see step 4.

## 3. Put it on Netlify

### Option A — connect the GitHub repo (recommended)

This is the usual "connect repo and it deploys" flow. The catch with Godot:
**Netlify can't run the Godot export**, so there's no build step — you commit
the already‑exported files and Netlify just serves them. The included
`netlify.toml` already sets this up (`publish = "web"`, empty build command).

1. Commit the exported build: `git add web && git commit -m "web build" && git push`.
2. On <https://app.netlify.com>: **Add new site → Import an existing project →**
   pick the repo. It reads `netlify.toml`, so leave the build settings as‑is.
3. Deploy. Rename the site (**Site configuration → Change site name** →
   `packmule`) → **`packmule.netlify.app`**.
4. **To update:** re‑export into `web/`, commit, push — Netlify redeploys.

> Yes, this commits the `.wasm`/`.pck` (~tens of MB) to the repo. That's normal
> for this no‑build approach and well under GitHub's limits.

### Option B — drag and drop (no git)

1. <https://app.netlify.com> → **Add new site → Deploy manually.**
2. Drag the whole **`web/` folder** onto the upload box.
3. Rename the site as above. To update, drag the folder again.

Open the link on desktop and phone to confirm it runs.

## 4. (Optional) Custom domain — the most portfolio-friendly

If you own a domain, **Domain management → Add a domain** and follow the DNS
steps. Then your game lives at e.g. `play.yourname.com`.

## 5. Updating later

Re-export to `web/` (step 2) and drag the folder onto the site again
(**Deploys → Drag and drop**). Or connect the GitHub repo for auto-deploy:
set **build command = (blank)** and **publish directory = `web`**, commit the
exported files, and every push redeploys.

---

## Alternative: GitHub Pages (no new account, but single-threaded)

You're already on GitHub. GitHub Pages can't set the headers above, so you
must export **without threads**: in the Web preset, turn **Threads off**
(Project → Export → Web → uncheck the threads option), then commit the export
to a `/docs` folder and enable Pages on the `main` branch `/docs` in the repo
settings. Simpler, but physics may run a bit slower than the Netlify build.

## Why not Cloudflare Pages?

Same idea as Netlify, but it caps each file at 25 MB and Godot 4's `.wasm`
(and often the `.pck`) is larger, so uploads get rejected. Netlify has no such
cap.
