// Vulnerable Next.js API route: state-changing operations without
// authentication.
//
// Trust boundary: any anonymous client can POST to /api/posts to create a
// post, DELETE /api/posts/:id to delete one, or PUT /api/admin/promote to
// elevate themselves. No getServerSession, no middleware.ts gate, no
// auth helper. The route handler runs unauth'd.
//
// Expected finding: authentication (high), CWE-306, A07:2021.

import type { NextApiRequest, NextApiResponse } from 'next';
import { prisma } from '../../lib/prisma';

// Vulnerable: pages/api/posts.ts — POST creates a post; no auth check.
export default async function handler(req: NextApiRequest, res: NextApiResponse) {
  if (req.method === 'POST') {
    // No getSession() / getServerSession() / requireUser() here.
    // No corresponding middleware.ts matcher in this fixture.
    const post = await prisma.post.create({
      data: {
        title: req.body.title,
        body: req.body.body,
        authorId: req.body.authorId, // also vulnerable to mass-assignment
      },
    });
    return res.status(201).json(post);
  }

  if (req.method === 'DELETE') {
    // Anonymous DELETE — wipes any post by id.
    await prisma.post.delete({ where: { id: Number(req.query.id) } });
    return res.status(204).end();
  }

  if (req.method === 'PUT') {
    // Anonymous self-promotion to admin.
    const user = await prisma.user.update({
      where: { id: req.body.userId },
      data: { role: 'admin' },
    });
    return res.json(user);
  }

  res.status(405).end();
}
