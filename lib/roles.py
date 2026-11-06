"""Shared interpretation of current and legacy seat roles."""

import re

ROLE_NAMES = {"looper", "pm", "gh", "docs", "architect", "helper"}

# Roles whose key is the seat. When nothing is an architect yet, the one custom
# seat with a descriptive role is that renamed architect. notes and reviewer
# (role equals the key) stay custom, as does any extra descriptive seat —
# claiming every unresolved seat would drop or overwrite them.
_STANDING_KEYS = {"looper", "pm", "gh", "docs", "helper"}


def seat_role(key, seat):
    # Shipped and init configs use descriptive roles, so the key decides then.
    if seat.get("role") in ROLE_NAMES:
        return seat["role"]
    if re.fullmatch(r"arch(_\d+)?", key):
        return "architect"
    if re.fullmatch(r"pm(_\d+)?", key):
        return "pm"
    return key


def seat_roles(existing_seats):
    roles = {key: seat_role(key, seat) for key, seat in existing_seats.items()}
    if any(role == "architect" for role in roles.values()):
        return roles
    renamed = [
        key for key, role in roles.items()
        if role == key and key not in _STANDING_KEYS and _descriptive_role(existing_seats[key], key)
    ]
    if len(renamed) == 1:
        roles[renamed[0]] = "architect"
    return roles


def _descriptive_role(seat, key):
    role = seat.get("role")
    return isinstance(role, str) and bool(role) and role != key
