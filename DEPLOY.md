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

1. Go to <https://app.netlify.com> and sign up (free — you can log in with
   GitHub).
2. **Add new site → Deploy manually.**
3. Drag the whole **`web/` folder** onto the upload box.
4. It deploys and gives you a URL like `random-name-1234.netlify.app`.
5. **Site configuration → Change site name** → `packmule` → your link is now
   **`packmule.netlify.app`**.

Open it on your phone and desktop to confirm it runs.

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
