---
name: web-security
description: >-
  Use when building security-sensitive web code — authentication,
  authorization, sessions, cookies, file uploads, redirects, outbound HTTP,
  security headers, CORS, password hashing, token generation. Trigger: "add
  login", "set up auth", "configure CORS", "JWT", "rate limit", or work
  touching auth/, session, csrf. Do NOT use for scanning a repo for committed
  secrets (security-review).

---

# Web Security

Extends `CLAUDE.md §7` (Security Foundations). The universal rules (no committed secrets, validate input, parameterized queries, supply chain, env var handling) live there. This skill covers web-specific threats and mitigations.

## Authentication

### Passwords
- **Hash with Argon2id** (preferred) or bcrypt (cost ≥12). Never MD5, SHA-*, or PBKDF2-SHA1.
- Argon2id parameters (2026 recommended starting points): memory 64 MB, iterations 3, parallelism 4. Tune to ~250ms on your hardware.
- Minimum length depends on factor context (state your threat model): per NIST SP 800-63B rev 4 (2024), require **≥15 chars** for a password used as a single/primary factor, and **≥8** is acceptable only when it is one factor inside enforced MFA. Check against breach lists (`HaveIBeenPwned` k-anonymity API) regardless.
- Never enforce composition rules ("must contain symbol") — they reduce entropy. Check breach lists instead.
- Do not impose a maximum length below 64. Allow 100+ characters.
- Never email passwords. Never log passwords, even on error.

### Tokens & sessions
- **Session tokens:** 256 bits of entropy from a CSPRNG. `crypto.randomBytes(32)` / `secrets.token_urlsafe(32)`.
- **JWTs:**
  - Use only when stateless validation is genuinely needed; otherwise use opaque session tokens.
  - Algorithm `EdDSA` or `RS256`. Never `none`. Never `HS256` with a secret you can't keep server-side.
  - Validate `iss`, `aud`, `exp`, `nbf` on every request.
  - Short lifetime (≤15 min for access tokens). Refresh tokens with rotation and reuse detection.
  - Never store JWTs in `localStorage` — XSS exfiltrates them. Use httpOnly cookies.
- **OAuth / OIDC:** use a vetted library (Auth0, Clerk, Authlib, oauthlib). Do not implement the protocol yourself.
- **MFA:** TOTP via standard libraries; WebAuthn for passwordless. Avoid SMS as a primary factor.

### Brute force & enumeration
- **Rate-limit** login, signup, password reset, MFA, and any auth-adjacent endpoint.
- **Lockout** after N failures, with exponential backoff. Notify the user.
- **Generic error messages.** "Invalid email or password" — never disclose which.
- **Constant-time comparison** for tokens, password hashes, HMACs (`crypto.timingSafeEqual`, `hmac.compare_digest`).

## Authorization

- **Authorize on every request,** not just at login. The session being valid says nothing about whether *this* user can perform *this* action on *this* resource.
- **Check ownership/membership** before returning any resource. `GET /orders/{id}` must verify the caller can see this order.
- **Default deny.** Whitelist allowed actions; never blacklist.
- **Centralize authorization logic.** Sprinkled `if user.role == ...` everywhere is unauditable. Use a policy engine (Casbin, OSO, Cedar) or a single helper.
- **IDOR is the most common production bug.** Test with a second account that should *not* have access.

## Cookies & sessions

```
Set-Cookie: session=<token>;
  HttpOnly;
  Secure;
  SameSite=Lax;
  Path=/;
  Max-Age=3600
```

- `HttpOnly`: blocks JavaScript access (mitigates XSS exfiltration).
- `Secure`: HTTPS only.
- `SameSite=Lax` minimum; `Strict` for high-value sessions; `None` requires `Secure` and a CSRF strategy.
- **No sensitive data in non-HttpOnly cookies.**
- **Rotate session ID** on login and on privilege change to prevent fixation.

## CSRF

State-changing endpoints need CSRF protection. Pick one (or both):

1. **SameSite cookies** (`Lax` minimum) — sufficient for most modern flows.
2. **CSRF tokens** — synchronizer-token pattern: server issues token, client sends in custom header (`X-CSRF-Token`), server verifies. Required for `SameSite=None` cookies and for strict legacy compatibility.

GraphQL: enforce `Content-Type: application/json` and reject simple-request types (preflight is then mandatory and CSRF is mostly mitigated).

## CORS

- **Default deny.** Reflect origins from a whitelist; never `Access-Control-Allow-Origin: *` for authenticated endpoints.
- `Access-Control-Allow-Credentials: true` requires an explicit origin (not `*`).
- Preflight: cache with `Access-Control-Max-Age` (e.g., 600) to reduce overhead.
- Never echo the request `Origin` header without validation — defeats the purpose.

## Security headers (every HTML response)

```
Content-Security-Policy: default-src 'self'; script-src 'self' 'sha256-...'; ...
Strict-Transport-Security: max-age=63072000; includeSubDomains; preload
X-Content-Type-Options: nosniff
Referrer-Policy: strict-origin-when-cross-origin
Permissions-Policy: camera=(), microphone=(), geolocation=()
X-Frame-Options: DENY              # legacy; CSP frame-ancestors is preferred
Cross-Origin-Opener-Policy: same-origin
Cross-Origin-Embedder-Policy: require-corp     # only if cross-origin isolation needed
```

- **CSP:** start with `default-src 'self'` and a strict script-src. Avoid `unsafe-inline` and `unsafe-eval`. Use nonces or hashes for inline scripts you genuinely need.
- **HSTS:** at least `max-age=31536000`; include `preload` only when fully committed.

## Input handling (web specifics)

- **Validate at the boundary** with a schema library: Zod, Valibot, Pydantic, marshmallow.
- **Reject unknown fields** by default (`strip` is safer than `passthrough`).
- **Type coercion is dangerous** — explicit schemas, not `parseInt(req.query.id)` ad hoc.
- **File size limits at the proxy** (nginx, ALB) AND at the app. Don't trust just one layer.
- **Deny dangerous content types** in upload endpoints unless explicitly needed.

## File uploads

- **Validate by content (magic bytes)**, not by extension or client-supplied MIME. Use `file-type` (JS) or `python-magic`.
- **Generate new filenames.** Never trust user input for storage paths. UUID + extension from validated content type.
- **Store outside the web root.** Serve via a controller that re-checks authorization.
- **Image uploads:** re-encode through a safe library (`sharp`, `Pillow`). Strip EXIF unless needed (privacy + ImageTragick-class bugs).
- **Scan for malware** where the threat model warrants (ClamAV, vendor APIs).
- **Cap upload size** at the proxy: e.g., nginx `client_max_body_size 10M`.

## SSRF (Server-Side Request Forgery)

When the server fetches a URL on the user's behalf:

- **Whitelist allowed hosts/protocols.** Default deny.
- **Resolve DNS first**, then **block private/loopback/metadata IPs** before connecting:
  - 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 127.0.0.0/8, 169.254.0.0/16, ::1/128, fc00::/7, fe80::/10
  - Block `169.254.169.254` (cloud metadata) explicitly.
- **Re-resolve at connect time** — DNS rebinding attacks change resolution between check and use. Use libraries like `safe-curl`, `httpx` with custom transport, or pin connection IP.
- **Disable redirects** or follow only to whitelisted hosts.
- **Set timeouts** (connect + read).
- **Limit response size** to prevent DoS via large file fetches.

## Open redirects

Any endpoint that redirects to a URL from user input is a phishing weapon.

- **Whitelist relative paths only**, or a list of approved absolute URLs.
- Never blindly `redirect(req.query.next)`.
- For OAuth / login flows: validate the `redirect_uri` against pre-registered values exactly (no prefix matching).

## TLS

- **TLS 1.2 minimum**, prefer 1.3.
- **Never disable certificate verification.** No `verify=False`, no `rejectUnauthorized: false`. Even in tests, use a real CA via testcontainers or stub at a higher layer.
- **HSTS** as above.
- **Pin only when you control the deployment** (mobile apps, IoT). Bad pinning bricks production.

## Secrets in transit and at rest

- **In transit:** TLS everywhere, including internal service-to-service.
- **At rest:** rely on storage encryption (AWS KMS, GCP CMEK). Encrypt application-side only when the threat model justifies it.
- **No secrets in URLs** — they end up in logs, browser history, referer headers.

## Logging (security-sensitive paths)

- Never log any part of a session token, bearer token, API key, refresh token, or `Authorization` header — not the full value, not a prefix, not a suffix, not a hash derived from the raw value. CLAUDE.md §7 is absolute here; a "prefix only" carve-out was a real defect that let partial credentials leak into logs.
- To correlate log lines to a session without leaking the token: use a **server-side correlation identifier** — a random session record ID, request ID, or `sub`-hash from the ID token — that has no value to an attacker who steals the log.
- Never log: passwords, full credit card numbers, full SSNs, full request/response bodies for auth/payment endpoints.
- **Mask user PII where a truncated form is useful and non-authenticating**, e.g. show last-4 of a payment card or the local-part of an email in an operator UI — never the same treatment for authenticating secrets.
- **Audit log** sensitive actions (login, password change, role change, money movement). Audit logs are append-only.

## Common patterns (secure starting points — set your own hosts, origins, CSP)

These compile and enforce as written, but you MUST substitute your hosts,
origins, and CSP. They are a correct baseline, not a drop-in for every app.

### Express (Node)
```js
import helmet from 'helmet';
import rateLimit from 'express-rate-limit';

app.use(helmet({
  contentSecurityPolicy: { /* configured per app */ },
  // `preload: true` opts the domain into browser HSTS preload lists — a
  // long-term, hard-to-reverse commitment (every subdomain HTTPS-only forever).
  // Enable it deliberately, only once you are certain. Default OFF:
  hsts: { maxAge: 31536000, includeSubDomains: true /* , preload: true */ },
}));
app.use('/auth', rateLimit({ windowMs: 60_000, max: 10 }));
```

### FastAPI (Python)
```python
from fastapi import FastAPI, Request
from fastapi.middleware.trustedhost import TrustedHostMiddleware
from fastapi.middleware.cors import CORSMiddleware
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded
from slowapi.util import get_remote_address

limiter = Limiter(key_func=get_remote_address)
app = FastAPI()
app.state.limiter = limiter
# REQUIRED: without this handler a limited route raises an unhandled error.
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

app.add_middleware(TrustedHostMiddleware, allowed_hosts=["api.example.com"])
app.add_middleware(CORSMiddleware,
    allow_origins=["https://app.example.com"],
    allow_credentials=True, allow_methods=["GET", "POST"], allow_headers=["*"])

# The Limiter enforces NOTHING until a route opts in with @limiter.limit AND
# takes a `request: Request` parameter (SlowAPI reads the client key from it).
@app.post("/auth/login")
@limiter.limit("10/minute")
async def login(request: Request):
    ...
```

## Done criteria (in addition to CLAUDE.md §14)

- [ ] Authentication uses standard library; passwords hashed with Argon2id/bcrypt.
- [ ] Authorization checked on every request, not just at login.
- [ ] Cookies set with `HttpOnly`, `Secure`, `SameSite`.
- [ ] CSRF protection on state-changing endpoints (SameSite or token).
- [ ] CORS whitelist explicit; no wildcard with credentials.
- [ ] Security headers set (CSP, HSTS, X-Content-Type-Options, etc.).
- [ ] Input validated with a schema library; unknown fields rejected.
- [ ] File uploads: type-by-content, new filenames, outside web root, size limits.
- [ ] Outbound HTTP: SSRF protections in place; no follow-redirects to internal IPs.
- [ ] Redirects: whitelist only; no open redirects.
- [ ] No secrets in URLs, logs, error messages.
- [ ] TLS verification never disabled.
- [ ] Rate limiting on auth/expensive endpoints.
