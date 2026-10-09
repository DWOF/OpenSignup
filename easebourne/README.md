# Easebourne Scouts & Guides sign-ups

Our branding and deployment files for a self-hosted copy of
[OpenSignup](https://github.com/richshaw/OpenSignup). Everything specific to
Easebourne lives in this folder, so pulling upstream updates never conflicts.

| File | What it is |
| --- | --- |
| `brand.env` | Name, strapline, colours. The one file to edit for branding. |
| `make-assets.py` | Regenerates the icon and link-preview image from `brand.env`. Run on a laptop, commit `assets/`. |
| `assets/` | Generated images. |
| `apply.sh` | Rebrands the checkout. Run after every `git pull`, before building. |
| `Caddyfile` | HTTPS, plus the leaders' password on everything except parent sign-up links. |
| `docker-compose.caddy.yml` | Adds Caddy to the upstream `docker-compose.prod.yml`. |
| `backup.sh` | Nightly database dump, 14 days kept. |

Build and start:

```bash
./easebourne/apply.sh
docker compose -f docker-compose.prod.yml -f easebourne/docker-compose.caddy.yml up -d --build
```

Source code for this instance, as the AGPL-3.0 licence requires, is this
repository: upstream OpenSignup plus this folder.
