// Vulnerable Next.js middleware: open-redirect via user-controlled URL.
//
// Trust boundary: ?next=... query parameter flows directly into
// NextResponse.redirect. An attacker constructs
// /login?next=https://evil.com/phish and after auth the user is redirected
// to the attacker's site.
//
// Expected finding: input_validation (high), CWE-601, A01:2021.

import { NextResponse, type NextRequest } from 'next/server';

export function middleware(req: NextRequest) {
  // Vulnerable: middleware redirects to whatever ?next= the client supplies.
  // No allow-list. No same-origin check.
  const next = req.nextUrl.searchParams.get('next');
  if (next) {
    return NextResponse.redirect(new URL(next));
  }

  // Also vulnerable: rewrite shape with user-controlled destination.
  const dest = req.nextUrl.searchParams.get('rewrite_to');
  if (dest) {
    return NextResponse.rewrite(new URL(dest, req.url));
  }

  return NextResponse.next();
}

export const config = {
  matcher: ['/login', '/logout', '/oauth/callback'],
};
