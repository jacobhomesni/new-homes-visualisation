# New Homes Visualisation

GitHub Pages site: https://jacobhomesni.github.io/new-homes-visualisation/

Dashboard for the Northern Ireland new-developments audit export.

- Map of Northern Ireland with county outlines (OSNI Open Data, OGL)
- Pinpoints for each development (town / postcode geocoding from audit addresses)
- Search, status filter, agent & developer tallies

## Local preview

Serve the folder over HTTP (required for `fetch` of JSON):

```bash
npx --yes serve .
```

Then open the printed local URL.

## Update data

1. Export a fresh Excel from the new-homes audit userscript.
2. Convert with the helpers in `scripts/` (or replace `data/developments.json`).
3. Commit and push to `main` — Pages updates automatically.

## Licence notes

County boundaries: © Ordnance Survey of Northern Ireland, Open Government Licence.
