// Vulnerable React component: <a href={user_url}> without scheme allow-list.
//
// Trust boundary: user.website / link.url are stored attacker-controlled
// strings. An attacker stores "javascript:alert(document.cookie)" as their
// profile website; clicking it executes the script in the victim's session.
// React 16.9+ warns on javascript: URLs but does not block them; in earlier
// versions there's no warning at all.
//
// Expected finding: xss_or_code_exec (high), CWE-79, A03:2021.

import React from 'react';

export function ProfileLink({ user }) {
  // Vulnerable: user.website may be "javascript:..." or "data:text/html,..."
  return (
    <a href={user.website} target="_blank" rel="noopener">
      {user.name}'s site
    </a>
  );
}

export function LinkList({ links }) {
  return (
    <ul>
      {links.map((link) => (
        <li key={link.id}>
          {/* Vulnerable: link.url is user-supplied; no scheme check. */}
          <a href={link.url}>{link.label}</a>
        </li>
      ))}
    </ul>
  );
}

export function ImgLink({ avatar }) {
  // Vulnerable: img src can also carry data: URIs that bypass CSP under
  // permissive img-src directives.
  return <img src={avatar.url} alt={avatar.alt} />;
}
