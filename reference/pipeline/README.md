# Asset pipeline

Builds `../game-assets/` from the source packs: copies the picked models, splits multi-object
files, renames them, normalizes scale/pivot/facing, simplifies the trees, generates the three-lane road tiles (`roads.mjs`), the power-ups, bus and roadworks
(`props.mjs`; both also run on their own: `node roads.mjs`, `node props.mjs`), the sidewalk and grass tiles, and
compresses them without glTF extensions (weld/dedup, tree textures resized to 256–512 px, JPEG
where there is no alpha), so any glTF loader can read the output.

```bash
npm install
npm run build
```

The list of assets and their settings is at the top of `build.mjs`. New source models go in
`../Extras-glb/`. Everything in the output folder
except `README.md` is replaced on every run, so don't hand-edit files in `game-assets/`.
