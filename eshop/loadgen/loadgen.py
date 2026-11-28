"""eShop order load generator (standard library only).

Places orders through Ordering.API as a seeded eShop user. Each order starts the RabbitMQ
integration-event saga: OrderStarted -> GracePeriodConfirmed -> AwaitingValidation ->
StockConfirmed/Rejected -> PaymentSucceeded/Failed -> Paid, across basket, catalog, ordering,
order-processor, payment-processor and webhooks.

Environment:
  IDENTITY_URL          public Identity.API URL (token issuer must match the APIs' Identity:Url)
  CATALOG_URL           default http://catalog-api
  ORDERING_URL          default http://ordering-api
  LOADGEN_CLIENT_SECRET secret of the "loadgen" OIDC client (lab patch to Identity.API)
  LOADGEN_USERNAME      seeded eShop user, e.g. alice
  LOADGEN_PASSWORD      that user's password
  ORDERS_PER_MINUTE     order rate; 0 pauses ordering (default 6)
  CHECK_USERNAME/CHECK_PASSWORD  seeded user for --check (must differ from LOADGEN_USERNAME)
"""

import base64
import json
import os
import random
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid

IDENTITY_URL = os.environ["IDENTITY_URL"].rstrip("/")
CATALOG_URL = os.environ.get("CATALOG_URL", "http://catalog-api").rstrip("/")
ORDERING_URL = os.environ.get("ORDERING_URL", "http://ordering-api").rstrip("/")
CLIENT_SECRET = os.environ["LOADGEN_CLIENT_SECRET"]
USERNAME = os.environ["LOADGEN_USERNAME"]
PASSWORD = os.environ["LOADGEN_PASSWORD"]
TIMEOUT = 15

_token = {"value": None, "expires": 0.0, "sub": None}


def log(event, **fields):
    print(json.dumps({"ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "event": event, **fields}), flush=True)


def http(method, url, body=None, headers=None, form=False):
    data = None
    headers = dict(headers or {})
    if body is not None:
        if form:
            data = urllib.parse.urlencode(body).encode()
            headers["Content-Type"] = "application/x-www-form-urlencoded"
        else:
            data = json.dumps(body).encode()
            headers["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
        raw = resp.read()
        return resp.status, (json.loads(raw) if raw else None)


def token():
    if _token["value"] and time.time() < _token["expires"] - 60:
        return _token["value"], _token["sub"]
    _, payload = http("POST", f"{IDENTITY_URL}/connect/token", form=True, body={
        "grant_type": "password",
        "client_id": "loadgen",
        "client_secret": CLIENT_SECRET,
        "username": USERNAME,
        "password": PASSWORD,
        "scope": "openid profile orders basket",
    })
    access = payload["access_token"]
    claims_b64 = access.split(".")[1]
    claims = json.loads(base64.urlsafe_b64decode(claims_b64 + "=" * (-len(claims_b64) % 4)))
    _token.update(value=access, expires=time.time() + payload.get("expires_in", 3600), sub=claims["sub"])
    log("token_issued", sub=claims["sub"], expires_in=payload.get("expires_in"))
    return access, claims["sub"]


def place_order():
    access, sub = token()
    _, page = http("GET", f"{CATALOG_URL}/api/catalog/items?api-version=1.0&pageSize=100")
    picks = random.sample(page["data"], k=random.randint(1, 3))
    items = [{
        "id": str(uuid.uuid4()),
        "productId": p["id"],
        "productName": p["name"],
        "unitPrice": p["price"],
        "oldUnitPrice": p["price"],
        "quantity": random.randint(1, 2),
        "pictureUrl": "",
    } for p in picks]
    request_id = str(uuid.uuid4())
    status, _ = http("POST", f"{ORDERING_URL}/api/orders?api-version=1.0", headers={
        "Authorization": f"Bearer {access}",
        "x-requestid": request_id,
    }, body={
        "userId": sub,
        "userName": USERNAME,
        "city": "Montreal",
        "street": "1 Lab Street",
        "state": "QC",
        "country": "Canada",
        "zipCode": "H2X 1Y4",
        # eShop is pinned to its last .NET 10 commit, whose order contract still takes card fields
        # (.NET 11 replaced them with paymentToken). Same test card the eShop WebApp sends.
        "cardNumber": "1111222233334444",
        "cardHolderName": "TESTUSER",
        "cardExpiration": f"{time.gmtime().tm_year + 1}-12-31T00:00:00Z",
        "cardSecurityNumber": "111",
        "cardTypeId": 1,
        "buyer": USERNAME,
        "items": items,
    })
    log("order_placed", status=status, request_id=request_id, products=[p["id"] for p in picks])


def order_numbers():
    access, _ = token()
    _, orders = http("GET", f"{ORDERING_URL}/api/orders?api-version=1.0",
                     headers={"Authorization": f"Bearer {access}"})
    return {o["orderNumber"]: o["status"] for o in orders}


def check(timeout_s=300):
    """Place one order and wait for it to reach Paid via the queue saga. Exit 0 on success."""
    before = set(order_numbers())
    place_order()
    deadline = time.time() + timeout_s
    seen = []
    while time.time() < deadline:
        new = {n: s for n, s in order_numbers().items() if n not in before}
        for number, status in new.items():
            if not seen or seen[-1] != status:
                seen.append(status)
                log("check_status", order=number, status=status)
            if status == "Paid":
                log("check_passed", order=number, statuses=seen)
                return 0
            if status == "Cancelled":
                log("check_failed", order=number, statuses=seen)
                return 1
        time.sleep(5)
    log("check_failed", statuses=seen, timeout_s=timeout_s)
    return 1


def main():
    if "--check" in sys.argv:
        # Order as a different user than the running generator, so the only new orders this
        # user has are the check's own.
        global USERNAME, PASSWORD
        USERNAME = os.environ["CHECK_USERNAME"]
        PASSWORD = os.environ["CHECK_PASSWORD"]
        return check()
    log("loadgen_started", identity=IDENTITY_URL, catalog=CATALOG_URL, ordering=ORDERING_URL)
    while True:
        rate = float(os.environ.get("ORDERS_PER_MINUTE", "6"))
        if rate <= 0:
            time.sleep(30)
            continue
        try:
            place_order()
        except urllib.error.HTTPError as e:
            log("order_failed", status=e.code, reason=str(e.reason), body=e.read()[:300].decode(errors="replace"))
            if e.code == 401:
                _token["value"] = None
        except Exception as e:  # keep generating load through transient outages
            log("order_failed", error=f"{type(e).__name__}: {e}")
        time.sleep(random.uniform(0.5, 1.5) * 60.0 / rate)


if __name__ == "__main__":
    sys.exit(main())
