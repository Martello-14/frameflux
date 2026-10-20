const { createClient } = require('@supabase/supabase-js');

module.exports = async (req, res) => {
  if (req.method !== 'POST') return res.status(405).json({ error: 'Method not allowed' });
  try {
    const auth = req.headers.authorization || '';
    if (!auth.startsWith('Bearer ')) return res.status(401).json({ error: 'Sign in required' });
    const sb = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY);
    const { data: { user }, error: authError } = await sb.auth.getUser(auth.slice(7));
    if (authError || !user) return res.status(401).json({ error: 'Invalid session' });
    const { reference } = req.body || {};
    if (!reference) return res.status(400).json({ error: 'Payment reference required.' });
    const { data: payment, error: paymentError } = await sb.from('payments').select('*').eq('reference', reference).single();
    if (paymentError || !payment) return res.status(404).json({ error: 'Payment record not found.' });
    if (payment.user_id !== user.id) return res.status(403).json({ error: 'This payment does not belong to your account.' });
    if (payment.status === 'success') return res.status(200).json({ success: true, message: 'Already verified.' });
    const response = await fetch('https://api.paystack.co/transaction/verify/' + encodeURIComponent(reference), {
      headers: { Authorization: 'Bearer ' + process.env.PAYSTACK_SECRET_KEY }
    });
    const result = await response.json();
    if (!response.ok || !result.status || result.data.status !== 'success') return res.status(402).json({ error: 'Payment is not confirmed as successful.' });
    const tx = result.data;
    if (tx.customer?.email?.toLowerCase() !== user.email?.toLowerCase() ||
        tx.currency !== 'NGN' || Number(tx.amount) !== Number(payment.amount)) {
      return res.status(400).json({ error: 'Payment details do not match the expected transaction.' });
    }
    if (payment.payment_type !== 'creator_subscription' || !payment.creator_id) {
      return res.status(400).json({ error: 'This endpoint only verifies creator subscriptions.' });
    }
    const now = new Date();
    const expires = new Date(now.getTime() + 30 * 24 * 60 * 60 * 1000).toISOString();
    const commission = Math.round(Number(tx.amount) * 0.10);
    const creatorNet = Number(tx.amount) - commission;
    const { error: subError } = await sb.from('creator_subscriptions').upsert({
      subscriber_id: user.id, creator_id: payment.creator_id, status: 'active',
      started_at: now.toISOString(), expires_at: expires,
      payment_reference: reference, amount_kobo: Number(tx.amount)
    }, { onConflict: 'subscriber_id,creator_id' });
    if (subError) throw subError;
    const { error: updateError } = await sb.from('payments').update({
      status: 'success', platform_commission_kobo: commission, creator_earning_kobo: creatorNet
    }).eq('reference', reference);
    if (updateError) throw updateError;
    return res.status(200).json({ success: true, expires_at: expires, platform_commission_kobo: commission, creator_earning_kobo: creatorNet });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ error: 'Could not verify creator subscription.' });
  }
};
