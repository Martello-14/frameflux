# FrameFlux — multi-creator AI video platform starter

This version has a responsive streaming-style storefront, viewer/creator signup choice, public creator channels, creator-set monthly pricing, a creator channel editor, creator-owned uploads, and Paystack checkout/verification endpoints that record a 10% platform commission and 90% creator share before fees. It is a development starter, not a production-ready streaming business yet.

## 1. Create and configure Supabase
1. Create a project at https://supabase.com/.
2. Open **SQL Editor** and run `supabase-schema.sql` in a fresh project.
3. In **Storage**, create a **private** bucket named `videos` and a **public** bucket named `posters`.
4. In **Project Settings → API**, copy the Project URL and anon/public key.
5. If you previously ran an older version of the schema, do not blindly rerun the full SQL. Back up first, then run the payments-column migration at the end of this guide and review other schema changes.

## 2. Add the browser configuration
1. Copy `config.example.js` and name the copy `config.js`.
2. Put your Supabase project URL, anon/public key, and Paystack **public** test key into `config.js`.
3. Do not put the Supabase service-role key or Paystack secret key in `config.js`.

## 3. Deploy to Vercel
1. Create a private GitHub repository and upload all project files, including the `api` folder, `package.json`, and `vercel.json`.
2. Import the repository at https://vercel.com/.
3. In Vercel project **Settings → Environment Variables**, add:
   - `SUPABASE_URL` — your project URL
   - `SUPABASE_SERVICE_ROLE_KEY` — Supabase service-role key (server-side only)
   - `PAYSTACK_SECRET_KEY` — Paystack test secret key
4. Redeploy after adding environment variables. GitHub Pages alone cannot run the server-side payment endpoints.

## 4. Create your owner/admin account
1. Open the deployed website and sign up with the email address you control. Select **Creator** if you want to upload to your own channel too.
2. In Supabase SQL Editor, promote only your own account to admin (replace the email):
   `update public.profiles set role='admin' where email='YOUR-EMAIL@example.com';`
3. Sign out and sign back in. The database trigger prevents normal users from changing their own role. Keep the service-role key private.

## 5. How creator subscriptions work
- A user selects Viewer or Creator at signup.
- A creator opens **Creator Studio**, edits their channel name/bio/price, and publishes the channel.
- Creator uploads are stored in the private `videos` bucket in a folder named with that creator's user ID. Creators cannot upload into another creator's folder.
- A viewer chooses a creator and clicks **Subscribe to channel**.
- The server reads the creator's price from Supabase, initializes Paystack, then verifies the transaction before activating that viewer's 30-day subscription.
- The ledger records 10% of the gross amount as platform commission and 90% as creator earnings before payment processing fees/taxes. For example, on ₦2,500 gross, the ledger records ₦250 commission and ₦2,250 creator earnings.

## 6. Important limitations before launch
- The current checkout is a one-time payment granting 30 days of access; it does not automatically renew.
- Creator earnings are only recorded in the database. This does not automatically transfer money to creators. Design payouts, payment fees, refunds, chargebacks, taxes, and payout timing before making payment promises.
- Likes/dislikes, comments, saved videos are in the database schema but their interface/actions are not yet connected.
- This starter uses signed URLs and storage policies, but must be security-tested using separate viewer, creator, and admin accounts before real launch.
- Video uploads are limited to 200 MB in the browser. For larger video files or adaptive streaming, consider a specialist video host such as Mux, Cloudflare Stream, or Bunny Stream.
- Add terms, privacy policy, refund/cancellation policy, support contact, and rights-cleared content before launch.

## 7. Existing database migration
If you created the database from the earlier starter and the payment columns are missing, run:
```sql
alter table public.payments
  add column if not exists platform_commission_kobo integer,
  add column if not exists creator_earning_kobo integer;
```
Review the updated `supabase-schema.sql` before running any additional migration on an existing database.

## API endpoints
- `POST /api/creator-subscribe-initialize` expects `{ "creator_id": "CREATOR_UUID" }` and returns the Paystack reference and amount in kobo.
- `POST /api/creator-subscribe-verify` expects `{ "reference": "PAYSTACK_REFERENCE" }` and verifies with Paystack server-side.

Use Paystack test keys and test failed payments, cancelled checkout, duplicate callbacks, expired subscriptions, unauthorized uploads, and access attempts across creator accounts before taking real payments. Add signed Paystack webhook handling and idempotency before production use.
