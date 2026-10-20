const { createClient } = require('@supabase/supabase-js');
const crypto = require('crypto');

module.exports = async (req, res) => {
  if (req.method !== 'POST') return res.status(405).json({ error: 'Method not allowed' });
  try {
    const auth = req.headers.authorization || '';
    if (!auth.startsWith('Bearer ')) return res.status(401).json({ error: 'Sign in required' });
    const sb = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY);
    const { data: { user }, error: authError } = await sb.auth.getUser(auth.slice(7));
    if (authError || !user) return res.status(401).json({ error: 'Invalid session' });
    const { creator_id } = req.body || {};
    if (!creator_id || creator_id === user.id) return res.status(400).json({ error: 'Choose a valid creator to subscribe to.' });
    const { data: page, error: pageError } = await sb.from('creator_pages')
      .select('creator_id,display_name,monthly_price_kobo,published')
      .eq('creator_id', creator_id).eq('published', true).single();
    if (pageError || !page) return res.status(404).json({ error: 'Creator page not found.' });
    const amount = Number(page.monthly_price_kobo);
    if (!Number.isInteger(amount) || amount < 10000) return res.status(400).json({ error: 'Creator price is invalid.' });
    const reference = 'ffc_' + crypto.randomBytes(12).toString('hex');
    const init = await fetch('https://api.paystack.co/transaction/initialize', {
      method: 'POST',
      headers: { Authorization: 'Bearer ' + process.env.PAYSTACK_SECRET_KEY, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        email: user.email, amount, currency: 'NGN', reference,
        metadata: { payment_type: 'creator_subscription', subscriber_id: user.id, creator_id: page.creator_id, platform_commission_percent: 10 }
      })
    });
    const payload = await init.json();
    if (!init.ok || !payload.status) return res.status(502).json({ error: payload.message || 'Could not initialize checkout.' });
    const { error: insertError } = await sb.from('payments').insert({
      reference, user_id: user.id, creator_id: page.creator_id, amount,
      currency: 'NGN', payment_type: 'creator_subscription', status: 'pending'
    });
    if (insertError) throw insertError;
    return res.status(200).json({ authorization_url: payload.data.authorization_url, reference, amount, creator_name: page.display_name });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ error: 'Could not start creator checkout.' });
  }
};
