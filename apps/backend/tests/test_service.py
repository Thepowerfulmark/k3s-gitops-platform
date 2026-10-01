import unittest

from app.service import create_item, health, list_items, live


class FakeStore:
    def __init__(self):
        self.rows = []
        self.down = False

    def insert(self, name):
        item = {
            "id": len(self.rows) + 1,
            "name": name,
            "created_at": "2026-01-01T00:00:00+00:00",
        }
        self.rows.append(item)
        return item

    def list(self):
        return list(self.rows)

    def ping(self):
        if self.down:
            raise RuntimeError("down")


class FakeQueue:
    def __init__(self):
        self.sent = []
        self.down = False

    def publish(self, item):
        if self.down:
            raise RuntimeError("queue")
        self.sent.append(item)

    def ping(self):
        if self.down:
            raise RuntimeError("queue")


class ServiceTest(unittest.TestCase):
    def test_create_item(self):
        store, queue = FakeStore(), FakeQueue()
        status, body = create_item(store, queue, {"name": "  notebook  "})
        self.assertEqual(status, 201)
        self.assertEqual(body["name"], "notebook")
        self.assertEqual(queue.sent, [body])

    def test_rejects_empty_name(self):
        store, queue = FakeStore(), FakeQueue()
        status, _body = create_item(store, queue, {"name": "   "})
        self.assertEqual(status, 400)
        self.assertEqual(queue.sent, [])

    def test_rejects_long_name(self):
        store, queue = FakeStore(), FakeQueue()
        status, _body = create_item(store, queue, {"name": "a" * 201})
        self.assertEqual(status, 400)

    def test_rejects_non_object(self):
        status, _body = create_item(FakeStore(), FakeQueue(), ["x"])
        self.assertEqual(status, 400)

    def test_queue_failure_keeps_the_row(self):
        store, queue = FakeStore(), FakeQueue()
        queue.down = True
        status, body = create_item(store, queue, {"name": "pen"})
        self.assertEqual(status, 502)
        self.assertEqual(body["item"]["name"], "pen")
        self.assertEqual(len(store.rows), 1)

    def test_list(self):
        store = FakeStore()
        store.insert("pen")
        status, body = list_items(store)
        self.assertEqual(status, 200)
        self.assertEqual(body["items"][0]["name"], "pen")

    def test_health(self):
        store, queue = FakeStore(), FakeQueue()
        self.assertEqual(health(store, queue)[0], 200)
        store.down = True
        self.assertEqual(health(store, queue)[0], 503)
        self.assertEqual(live()[0], 200)


if __name__ == "__main__":
    unittest.main()
