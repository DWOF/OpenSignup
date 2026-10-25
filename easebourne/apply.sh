#!/usr/bin/env bash
# Apply Easebourne branding to this OpenSignup checkout.
#
# Safe to run any number of times: it first restores the upstream versions of
# every file it changes, then rebrands them. Run it after every `git pull`,
# before `docker compose build`.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
# shellcheck disable=SC1091
source easebourne/brand.env

FILES=(
  tailwind.config.ts
  src/app/icon.svg
  src/app/apple-icon.png
  src/app/opengraph-image.png
  src/app/twitter-image.png
  src/app/opengraph-image.alt.txt
  src/app/twitter-image.alt.txt
  src/app/login/page.tsx
  src/app/login/confirm/page.tsx
  "src/app/app/(chrome)/layout.tsx"
  "src/app/app/(chrome)/page.tsx"
  "src/app/app/(chrome)/signups/[id]/layout.tsx"
  src/auth/config.ts
  src/email/templates/layout.tsx
  src/email/templates/magic-link.tsx
  src/email/templates/commitment-confirmation.tsx
  src/email/templates/reminder.tsx
  src/oauth/provider.ts
  src/components/build-wysiwyg/Editable.tsx
  src/app/login/confirm/sign-in-link.tsx
  "src/app/oauth/consent/[uid]/consent-form.tsx"
  src/email/templates/slot-changed.tsx
  src/lib/seo.ts
)

# 1. Back to upstream.
git checkout -- "${FILES[@]}"

# 2. Images.
for f in icon.svg apple-icon.png opengraph-image.png twitter-image.png \
         opengraph-image.alt.txt twitter-image.alt.txt; do
  cp "easebourne/assets/$f" "src/app/$f"
done

# 3. Colours. Upstream blue -> brand colours.
for f in "${FILES[@]}"; do
  case "$f" in *.png|*.txt|*.svg) continue ;; esac
  sed -i \
    -e "s/#1f6feb/${BRAND_COLOR}/gI" \
    -e "s/#1658c4/${BRAND_COLOR_DARK}/gI" \
    -e "s/#dbe7ff/${BRAND_COLOR_SOFT}/gI" \
    "$f"
done

# 4. Product name -> our name, where parents and leaders see it.
#    (The legal pages keep "OpenSignup": they credit the project, as the
#    licence expects.) Escape & and / for sed.
NAME_SED=$(printf '%s' "$BRAND_NAME" | sed -e 's/[&/\]/\\&/g')
sed -i "s/Sign in to OpenSignup/Sign in to ${NAME_SED}/g" \
  src/app/login/page.tsx src/app/login/confirm/page.tsx \
  src/auth/config.ts src/email/templates/magic-link.tsx
sed -i "s/>OpenSignup</>${NAME_SED}</" src/email/templates/layout.tsx
sed -i "s/^\(\s*\)OpenSignup$/\1${NAME_SED}/" "src/app/app/(chrome)/layout.tsx"
sed -i "s/Welcome to OpenSignup/Welcome to ${NAME_SED}/" "src/app/app/(chrome)/page.tsx"
sed -i "s/title: 'OpenSignup'/title: '${NAME_SED}'/g" "src/app/app/(chrome)/signups/[id]/layout.tsx"

# 4b. Link-preview alt text, kept in step with the image (upstream tests this).
ALT_SED=$(sed -e 's/[&/\\]/\\&/g' easebourne/assets/opengraph-image.alt.txt | tr -d '\n')
sed -i "s/^  alt: '.*',$/  alt: '${ALT_SED}',/" src/lib/seo.ts
grep -q "alt: '${ALT_SED}'" src/lib/seo.ts || { echo "Alt-text patch did not apply" >&2; exit 1; }

# 5. Organiser allowlist (ORGANISER_EMAILS in .env).
sed -i '/^    callbacks: {$/r easebourne/patches/organiser-allowlist.snippet' src/auth/config.ts
grep -q 'ORGANISER_EMAILS' src/auth/config.ts || { echo "Allowlist patch did not apply" >&2; exit 1; }

# 6. Show line breaks in the builder's description text (the public page
#    already does). Upstream collapses them in the read-only view.
sed -i 's/className={`${className} cursor-text rounded/className={`${className} whitespace-pre-line cursor-text rounded/' \
  src/components/build-wysiwyg/Editable.tsx
grep -q 'whitespace-pre-line cursor-text' src/components/build-wysiwyg/Editable.tsx || { echo "Line-break patch did not apply" >&2; exit 1; }

# 7. Check nothing was missed in the files we own.
left=$(grep -l "#1f6feb\|>OpenSignup<\|Sign in to OpenSignup" \
  "${FILES[@]/%/}" 2>/dev/null || true)
if [ -n "$left" ]; then
  echo "Branding incomplete in: $left" >&2
  exit 1
fi
echo "Branding applied: ${BRAND_NAME} (${BRAND_COLOR})"
