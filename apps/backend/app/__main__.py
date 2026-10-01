import sys

from app.server import migrate, serve


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "serve"
    if mode == "migrate":
        raise SystemExit(migrate())
    if mode == "serve":
        raise SystemExit(serve())
    print("usage: python -m app serve|migrate", file=sys.stderr)
    raise SystemExit(2)


if __name__ == "__main__":
    main()
