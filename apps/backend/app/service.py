"""Request logic. No database or network imports."""

MAX_NAME = 200


def create_item(store, publisher, payload):
    if not isinstance(payload, dict):
        return 400, {"error": "expected an object"}
    name = payload.get("name")
    if not isinstance(name, str) or not name.strip():
        return 400, {"error": "name is required"}
    name = name.strip()
    if len(name) > MAX_NAME:
        return 400, {"error": "name is too long"}
    item = store.insert(name)
    try:
        publisher.publish(item)
    except Exception:
        return 502, {"error": "queue did not accept the item", "item": item}
    return 201, item


def list_items(store):
    return 200, {"items": store.list()}


def health(store, publisher):
    try:
        store.ping()
        publisher.ping()
    except Exception:
        return 503, {"status": "unavailable"}
    return 200, {"status": "ok"}


def live():
    return 200, {"status": "ok"}
