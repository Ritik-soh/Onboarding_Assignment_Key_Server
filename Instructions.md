# API Key Server — README

Base URL - http://localhost:4567
Endpoints & curl examples-

# Table of contents

1. Project overview
2. Problem statement
3. High-level solution & design
4. File list (every file + role)
5. API endpoints (usage & exact behavior)
6. Data structures, complexity & concurrency notes
7. Environment / Requirements (Ruby, gems)
8. How to run the server (step-by-step)
9. How to run tests (RSpec)
10. Example commands (curl) and expected responses (JSON)
11. Troubleshooting & common gotchas
12. Next steps & suggestions

---

# 1 — Project overview

This is a small, single-process API key server written in Ruby (Sinatra) — **no Rails**. It:

* Generates API keys with time-based expiry.
* Serves available keys to clients and marks them as blocked while in use.
* Automatically releases blocked keys after a short interval.
* Allows manual unblock, keep-alive, and delete operations.
* Keeps keys alive only if clients call keep-alive periodically.
* Keeps internal state in memory and has a background thread for cleanup so endpoints do not need to iterate the whole key set.

It was built to be testable and configurable (expiry / block durations).

---

# 2 — Problem statement

You want a small service that can:

* Generate API keys that expire after 5 minutes (configurable).
* Provide a single endpoint to **get** an available key; when served it becomes blocked so it won’t be served again until unblocked or auto-released.
* Auto-release blocked keys after 60s if the client does not call “unblock”.
* Allow a client to explicitly unblock a key (and reset its expiry).
* Allow deletion of keys.
* Require clients to call a keep-alive endpoint every 5 minutes to keep a key alive; otherwise the key is purged.
* Ensure all endpoints avoid O(n) scans of the entire key set — operations should be O(1) or O(log n) where applicable.
* Be unit-tested with RSpec.

---

# 3 — Solution & design (high-level)

* API server implemented using **Sinatra** for minimal footprint.
* Core logic lives in `KeyStore` (`lib/key_store.rb`), responsible for:

  * Generating keys,
  * Serving available keys (FIFO behavior used by tests),
  * Blocking / unblocking,
  * Deleting keys,
  * Keep-alive logic,
  * Background cleanup thread that processes expiry and auto-release using min-heaps (expiry & block-release heaps).
* Background thread runs every `poll_interval` seconds to:

  * Delete expired keys (expiry heap).
  * Release blocked keys whose block period expired (block heap).
* Endpoints are thin wrappers calling methods on the `KeyStore`.
* The design keeps endpoint latency low and ensures no endpoint loops over every key.
* Expiry and block durations are configurable via ENV (good for fast tests).

---

# 4 — File list (what each file does)

Root:

* `Gemfile`

  * RubyGems metadata and dependencies (`sinatra`, `rspec`, `rack-test`, etc.)
  * Set the recommended Ruby version (use your installed Ruby — the project was tested with Ruby 3.4.5 in this environment).
* `Rakefile`

  * RSpec rake task: `rake` runs tests.
* `README.md`

  * This file (documentation, instructions, examples).

Server & library:

* `server.rb`

  * Sinatra app. Loads `lib/key_store.rb`, initializes a `KEY_STORE` instance using ENV overrides, and defines the HTTP endpoints:

    * `POST /keys` — generate key
    * `GET /keys/available` — get an available key (blocks it)
    * `POST /keys/:key/unblock` — unblock
    * `DELETE /keys/:key` — delete key
    * `POST /keys/:key/keep_alive` — keep alive
    * `GET /keys/:key` — debug/info (for tests)
* `lib/key_store.rb`

  * Core implementation of `KeyStore` and `MinHeap`.
  * `MinHeap` is used for expiry & block-release scheduling (O(log n) operations).
  * `KeyStore` manages key metadata, available queue, heaps, and runs a background cleanup thread.

Tests:

* `spec/spec_helper.rb`

  * RSpec and Rack::Test setup and ENV overrides used for faster tests.
* `spec/key_store_spec.rb`

  * Unit tests for `KeyStore` behavior (generate, block, unblock, expiry, keep\_alive).
* `spec/app_spec.rb`

  * Integration tests exercising the HTTP endpoints via Rack::Test.

---

# 5 — API endpoints (exact behavior)

All responses are JSON. Time values are returned in ISO8601 UTC format.

1. `POST /keys`

   * Generate a new key.
   * Response: `201 Created` with JSON `{ "key": "<hex32>", "expiry_at": "<ISO8601 UTC time>" }`

2. `GET /keys/available`

   * Get an available key (FIFO order for this project). The returned key becomes **blocked** and will not be returned again until unblocked or auto-released.
   * Response: `200 OK` with `{ "key": "<hex32>", "blocked_until": "<ISO8601 UTC time>" }`
   * If no eligible key is available: `404` with `{ "error":"no available key" }`.

3. `POST /keys/:key/unblock`

   * Unblock the key (reset expiry to now + expiry\_seconds).
   * Returns: `200` `{ "status":"unblocked" }` or `404` `{ "error":"not found" }`.

4. `DELETE /keys/:key`

   * Delete/purge a key.
   * Returns `200` `{ "status":"deleted" }` or `404` if not found.

5. `POST /keys/:key/keep_alive`

   * Extend expiry for a key to now + expiry\_seconds (client must call every expiry\_seconds to keep alive).
   * Returns `200` `{ "status":"kept_alive" }` or `404` if not found.

6. `GET /keys/:key`

   * Return debugging info `{ expiry: Float, blocked: Boolean, deleted: Boolean }` — primarily for tests.

---

# 6 — Data structures, complexity & concurrency

* `@keys` (Hash) — key → metadata (expiry timestamp, blocked flag, deleted flag). Access O(1).
* Available keys stored in an Array (`@available_keys`) with an index map (`@available_index`), used for O(1) add and O(1) remove in the random-selection version. For FIFO behavior tests we maintain order by using stable `delete_at` + reindexing.
* `MinHeap` (binary heap) used for expiry and block-release scheduling — provides O(log n) push/pop/update.
* Background cleanup thread:

  * Pops expired keys from expiry heap and deletes them (O(log n) per item).
  * Pops expired blocks from block heap and unblocks them (O(log n) per item).
* Concurrency:

  * A `Mutex` protects `KeyStore` internal state. The background thread synchronizes on the same mutex when manipulating shared state.

**Complexity summary:**

* Generate: O(log n) (heap push) + O(1) (array append).
* Get available: O(1) pick + O(log n) push to block heap.
* Unblock/delete/keep\_alive: O(log n) (heap update/remove) + O(1).
* No endpoint performs an O(n) scan (except `delete_at` reindexing used for preserving FIFO order; if you expect huge volumes, we can replace with a deque + map to maintain order at O(1)).

---

# 7 — Environment & requirements

* Ruby: **>= 3.2** (project was tested using Ruby **3.4.5** in this environment). Use a Ruby version manager (rbenv/rvm) if needed.
* Bundler (gem) — install with `gem install bundler`.
* Gems (from `Gemfile`) include:

  * `sinatra` (for server)
  * `rspec` (for tests)
  * `rack-test` (for endpoint tests)
  * `webrick` (if using default Ruby server)
* Optional: `jq` used in examples for pretty JSON (install via Homebrew on macOS: `brew install jq`).

---

# 8 — How to run the project (exact steps)

**Clone / cd into project root** (where `server.rb` and `Gemfile` live).

1. Install gems:


gem install bundler   # if not installed
bundle install


2. Run server (default durations: expiry 300s, block 60s, poll 1s):

ruby server.rb


Server will log something like:


== Sinatra (v3.x.x) has taken the stage on 4567 for development with backup from WEBrick


3. Run server with short timeouts for demo (recommended when trying it manually):


KEY_EXPIRY_SECONDS=20 KEY_BLOCK_SECONDS=5 KEY_POLL_INTERVAL=0.5 ruby server.rb


* `KEY_EXPIRY_SECONDS` — lifetime of keys (seconds)
* `KEY_BLOCK_SECONDS` — how long a key is blocked once served
* `KEY_POLL_INTERVAL` — how frequently the background cleaner runs

---

# 9 — How to run tests (RSpec) & what to expect

Run tests:


bundle exec rspec

You should see something like:

 
11 examples, 0 failures


You can run via rake:


bundle exec rake
# (or just `rake` if using system rake)
```

Notes:

* Tests set ENV overrides to make expiry and block times small so tests run quickly.
* Tests use `Rack::Test` so you do **not** need to start the server separately; they exercise the app in-process.
* If you have a manually running server (puma/rackup) on the same app, it won’t be used by RSpec (Rack::Test runs in-process). However, having a separate running server can be confusing when manually using curl, so stop it if necessary.

---

# 10 — Example commands and expected outputs

> **Important**: WEBrick (the default dev server) may reject a `POST` without a `Content-Length` header. Use `-d ''` or `-H 'Content-Length: 0'` with `curl` when POSTing without a body.

### 1) Generate (create) a key

```bash
curl -s -X POST http://localhost:4567/keys -d '' | jq .
```

**Expected response (201)**:

```json
{
  "key": "0348db30bc91692043d3699e091512c1",
  "expiry_at": "2025-08-12T12:34:56Z"
}
```

### 2) Get an available key (serve & block)

```bash
curl -s http://localhost:4567/keys/available | jq .
```

**Expected response (200)**:

```json
{ "key": "0348db30bc91692043d3699e091512c1", "blocked_until": "2025-08-12T12:35:16Z" }
```

If none are available:

```bash
curl -i http://localhost:4567/keys/available
# HTTP/1.1 404 and body: {"error":"no available key"}
```

### 3) Unblock a key (manual release)

```bash
curl -s -X POST http://localhost:4567/keys/0348db30bc91692043d3699e091512c1/unblock -d '' | jq .
# => {"status":"unblocked"}
```

### 4) Delete a key

```bash
curl -s -X DELETE http://localhost:4567/keys/0348db30bc91692043d3699e091512c1 | jq .
# => {"status":"deleted"}
```

### 5) Keep-alive (extend expiry)

```bash
curl -s -X POST http://localhost:4567/keys/0348db30bc91692043d3699e091512c1/keep_alive -d '' | jq .
# => {"status":"kept_alive"}
```

### 6) Debug/info for a key

```bash
curl -s http://localhost:4567/keys/0348db30bc91692043d3699e091512c1 | jq .
# => { "expiry": 1234567890.123, "blocked": false, "deleted": false }
```

---

# 11 — Troubleshooting & common gotchas

1. **411 Length Required on POST**

   * If you run `curl -X POST http://localhost:4567/keys` you may get `411 Length Required`. Fix: send an explicit empty body:

     ```bash
     curl -X POST http://localhost:4567/keys -d ''
     ```

     or add `-H 'Content-Length: 0'`.

2. **Tests showed different key (flaky)**

   * If an earlier server instance is running in the background and you run manual calls, the in-memory `KEY_STORE` state can differ from the fresh state RSpec expects. Ensure you kill any running puma/rackup/WEBrick process on that port:

     ```bash
     pkill -f puma
     pkill -f rackup
     # or find PID: lsof -i :4567
     ```
   * RSpec uses a fresh in-process app (no external server required).

3. **Order of served keys in tests**

   * Tests assume FIFO serving in the `GET /keys/available` test. The code has been adjusted to guarantee that behavior. If you change to random selection later, update tests accordingly.

4. **Race in cleanup thread vs tests**

   * The `KeyStore` uses a background thread. Tests and the cleanup thread manipulate internal state; the code uses `Mutex` to avoid races. If you implement shutdown/reset, ensure you handle the thread cleanly.

5. **Large scale performance**

   * Current FIFO implementation uses `Array#delete_at` and reindexing which is O(n). For very large key sets (100k+), replace with a double-ended queue + index map or a linked list + hash for O(1) removal while preserving order.


---
We can run the following in a terminal, but do two quick checks first:
--Server is running (in another terminal):
ruby server.rb should be active and listening on port 4567.
jq installed (optional, for pretty JSON):
If you don’t have jq, either install with brew install jq or drop the | jq . to see raw JSON.
Then run (in a different terminal tab so the server keeps running):
curl -s -X POST http://localhost:4567/keys -d '' | jq .

1) Generate a key (E1)
Create a new API key. Key will expire after KEY_EXPIRY_SECONDS unless kept alive.
curl -s -X POST http://localhost:4567/keys -d '' | jq .
# Example response:
# { "key":"eace172e6714fa120e6e8c4db486afa2", "expiry_at":"2025-08-20T00:38:47Z" }
expiry_at is the canonical expiry timestamp (UTC ISO8601).

2) Get an available random key (E2)
Get a random key that is not currently blocked. The server will mark that key blocked for KEY_BLOCK_SECONDS so it won’t be re-served until unblocked or automatically released.
curl -s http://localhost:4567/keys/available | jq .
# Example successful response:
# { "key":"eace172e6714fa120e6e8c4db486afa2", "blocked_until":"2025-08-20T00:32:47Z" }

# If none available:
# { "error":"no available key" }  (HTTP 404)
Notes:
The return includes blocked_until (canonical timestamp from the store).
After receiving a key you should call keep_alive periodically (see #5).

3) Unblock a key (E3)
If a client wants to manually release the blocked key, call unblock. Unblocking resets its expiry to now + KEY_EXPIRY_SECONDS so it’s usable again.
curl -s -X POST http://localhost:4567/keys/eace172e6714fa120e6e8c4db486afa2/unblock -d '' | jq .
# Example: { "status":"unblocked" }
If the key does not exist, a 404 response is returned.

4) Delete a key (purge)
Permanently remove a key.
curl -s -X DELETE http://localhost:4567/keys/eace172e6714fa120e6e8c4db486afa2 | jq .
# Example: { "status":"deleted" }
After deletion, the key is gone and cannot be used again.

5) Keep-alive (must be called every 5 minutes)
Clients must call this endpoint every KEY_EXPIRY_SECONDS (default 300s = 5 minutes) to keep their key alive. If a key does not receive a keep-alive within the expiry window it is permanently deleted.
curl -s -X POST http://localhost:4567/keys/eace172e6714fa120e6e8c4db486afa2/keep_alive -d '' | jq .
# Example: { "status":"kept_alive" }
This extends the key’s expiry to now + KEY_EXPIRY_SECONDS.

6) Per-key info (safe O(1) debug)
Get stored info for a single key (expiry, blocked, blocked_until, deleted). This does not iterate the full store.
curl -s http://localhost:4567/keys/eace172e6714fa120e6e8c4db486afa2 | jq .
# Example:
# {
#   "expiry_at":"2025-08-20T00:38:47Z",
#   "blocked":false,
#   "blocked_until":null,
#   "deleted":false
# }

7) Safe stats (O(1)) — counts only, not full list
Get O(1) counts (total keys, available, blocked):
curl -s http://localhost:4567/stats | jq .
# Example: { "total_keys": 2, "available": 1, "blocked": 1 }
Important: There is no GET /keys that returns the entire key list because that would be O(n) and violate the requirement. Use /stats and per-key GET /keys/:key for visibility.

Author - Ritik Sohane (Browserstack)