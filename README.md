# Kwnchwkcha Sung — Live Booking Site

This package turns the earlier browser-only demo into a real database-backed booking site.

## What it does
- Customer booking form
- ₹100 per ticket
- UPI payment reference capture
- Automatic atomic allocation of KWS-001 through KWS-500
- Persistent online bookings in Supabase Postgres
- Admin login with Supabase Auth
- Admin dashboard with pending/confirmed/cancelled bookings
- Approve/cancel controls
- CSV export
- Print-ready customer ticket

## Setup (about 10–15 minutes)

1. Create a Supabase project.
2. In **SQL Editor**, run all of `schema.sql`.
3. In Supabase **Authentication**, create the admin user using your own email and a strong password. You can use the password you want for your KWS admin account; do not publish it in this repository.
4. In SQL Editor, run this, replacing the email with the admin email you created:

```sql
insert into public.admin_users(user_id, username)
select id, 'KWSADMIN' from auth.users where email='YOUR_EMAIL'
on conflict (user_id) do update set username='KWSADMIN';
```

5. Copy `config.example.js` to `config.js`.
6. Put your Supabase project URL and **publishable/anon browser key** into `config.js`.
7. Publish the folder with GitHub Pages, Netlify, Cloudflare Pages, or another static host.

### Important security rule
Never put a Supabase `service_role`/secret key in `config.js` or in browser JavaScript. The website uses Supabase Auth + Row Level Security, and the public booking action is a restricted database function.

### Admin login
The dashboard displays the admin role as `KWSADMIN`, but the actual secure sign-in uses the email/password of the Supabase Auth account you created. This avoids putting a fixed password into public website code.

### Payment verification
The website records the UPI transaction/reference number. Approval is manual: the organizer checks the payment and then presses **Approve** in the admin dashboard. This version does not automatically verify bank/UPI payments.

### WhatsApp number
The ticket WhatsApp button currently uses the number from the earlier demo. Change it in `index.html` if the organizer wants a different confirmation number.
