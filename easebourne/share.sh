#!/usr/bin/env bash
# Give another leader access to an organiser's sign-up sheets.
#
#   sudo ./easebourne/share.sh OWNER_EMAIL LEADER_EMAIL [viewer|editor]
#   sudo ./easebourne/share.sh --remove OWNER_EMAIL LEADER_EMAIL
#
# viewer (default): sees the sheets, responses and CSV export; cannot change anything.
# editor: can also edit sheets and slots.
#
# The leader must be in ORGANISER_EMAILS and must have signed in once first.
# Their dashboard then shows the owner's sheets instead of their own.
set -euo pipefail
cd "$(dirname "$0")/.."

PSQL="${PSQL:-docker compose -f docker-compose.prod.yml exec -T db psql -U signup -d signup}"
q() { $PSQL -v ON_ERROR_STOP=1 -qtA "$@"; }

remove=0
if [ "${1:-}" = "--remove" ]; then remove=1; shift; fi
OWNER="${1:?owner email}"; LEADER="${2:?leader email}"; ROLE="${3:-viewer}"
case "$ROLE" in viewer|editor) ;; *) echo "Role must be viewer or editor"; exit 1 ;; esac
OWNER=$(printf '%s' "$OWNER" | tr '[:upper:]' '[:lower:]'); LEADER=$(printf '%s' "$LEADER" | tr '[:upper:]' '[:lower:]')

WS=$(q -v e="$OWNER" <<'SQL'
select m.workspace_id from organizers o
join workspace_members m on m.organizer_id = o.id and m.role = 'owner' and m.status = 'active'
where lower(o.email) = :'e' limit 1;
SQL
)
[ -n "$WS" ] || { echo "No organiser found for $OWNER."; exit 1; }

LID=$(q -v e="$LEADER" <<'SQL'
select id from organizers where lower(email) = :'e';
SQL
)
[ -n "$LID" ] || { echo "$LEADER has not signed in yet. Ask them to sign in once, then run this again."; exit 1; }

if [ "$remove" = 1 ]; then
  q -v ws="$WS" -v lid="$LID" <<'SQL'
delete from workspace_members where workspace_id = :'ws' and organizer_id = :'lid' and role <> 'owner';
update organizers o set default_workspace_id = (
  select m.workspace_id from workspace_members m
  where m.organizer_id = o.id and m.role = 'owner' limit 1)
where o.id = :'lid';
SQL
  echo "Removed $LEADER from $OWNER's sheets. They need to sign out and back in."
  exit 0
fi

q -v ws="$WS" -v lid="$LID" -v role="$ROLE" <<'SQL'
insert into workspace_members (id, workspace_id, organizer_id, role, status)
values ('mem_' || replace(gen_random_uuid()::text, '-', ''), :'ws', :'lid', :'role', 'active')
on conflict (workspace_id, organizer_id) do update set role = excluded.role, status = 'active';
update organizers set default_workspace_id = :'ws' where id = :'lid';
SQL
echo "$LEADER is now $ROLE on $OWNER's sheets. They need to sign out and back in."
