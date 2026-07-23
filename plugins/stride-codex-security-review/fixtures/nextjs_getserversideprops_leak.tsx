// Vulnerable Next.js page: getServerSideProps leaks secrets into props.
//
// Trust boundary: anything returned in `props` from getServerSideProps is
// serialized into __NEXT_DATA__ JSON inside the rendered HTML. Anyone who
// loads the page can View Source and read the env vars and the
// password_digest field. Same for getStaticProps and App-Router
// generateMetadata.
//
// Expected finding: data_exposure (high), CWE-200, A04:2021.

import type { GetServerSideProps } from 'next';

type Props = {
  stripeKey: string;
  databaseUrl: string;
  apiToken: string;
  user: {
    id: number;
    email: string;
    passwordHash: string;
    apiToken: string;
    mfaSecret: string;
  };
};

export default function AccountPage({ stripeKey, user }: Props) {
  return (
    <div>
      <h1>Welcome, {user.email}</h1>
    </div>
  );
}

export const getServerSideProps: GetServerSideProps<Props> = async (ctx) => {
  // Vulnerable: server-side env vars passed into props -> client HTML.
  // process.env.STRIPE_SECRET_KEY is NOT prefixed NEXT_PUBLIC_, so the
  // developer believes it's server-only — but returning it in `props`
  // sends it to the browser anyway.
  const stripeKey = process.env.STRIPE_SECRET_KEY!;
  const databaseUrl = process.env.DATABASE_URL!;
  const apiToken = process.env.INTERNAL_API_TOKEN!;

  // Vulnerable: raw user object including passwordHash / mfaSecret.
  const user = await fetchUser(ctx.params!.id as string);

  return {
    props: {
      stripeKey,
      databaseUrl,
      apiToken,
      user, // <-- full object with passwordHash + apiToken + mfaSecret
    },
  };
};

async function fetchUser(id: string) {
  return {
    id: Number(id),
    email: 'user@example.com',
    passwordHash: '$2b$12$bcrypt...',
    apiToken: 'sk_live_REDACTED',
    mfaSecret: 'JBSWY3DPEHPK3PXP',
  };
}
