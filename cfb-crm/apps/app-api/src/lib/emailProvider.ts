/**
 * Email provider abstraction.
 * Set EMAIL_PROVIDER env var to: mock | ses | sendgrid | resend
 * Default: mock (logs to stdout, no real sends)
 */

export interface EmailMessage {
  messageId:        string;   // internal outreach_messages.id
  to:               string;
  firstName:        string;
  fromName:         string;
  fromAddress:      string;
  replyTo?:         string;
  subject:          string;
  htmlBody:         string;   // raw body — footer injected here
  unsubscribeToken: string;
  physicalAddress:  string;
}

export interface EmailResult {
  messageId: string;
  success:   boolean;
  error?:    string;
}

const WEB_BASE_URL = process.env.WEB_BASE_URL ?? 'http://localhost:3000';

function injectCanSpamFooter(html: string, unsubscribeToken: string, physicalAddress: string): string {
  const unsubUrl = `${WEB_BASE_URL}/unsubscribe?token=${unsubscribeToken}`;
  const footer = `
<div style="margin-top:32px;padding-top:16px;border-top:1px solid #e5e7eb;font-size:11px;color:#9ca3af;line-height:1.6">
  <p style="margin:0 0 4px 0">
    You are receiving this email because you are associated with this team portal.
    To unsubscribe from future emails,
    <a href="${unsubUrl}" style="color:#6b7280">click here</a>.
  </p>
  <p style="margin:0">${physicalAddress}</p>
</div>`;
  return html + footer;
}

async function sendViaMock(messages: EmailMessage[]): Promise<EmailResult[]> {
  return messages.map(m => {
    const body = injectCanSpamFooter(m.htmlBody, m.unsubscribeToken, m.physicalAddress);
    console.log(`[email:mock] To: ${m.to} | Subject: ${m.subject} | Body length: ${body.length}`);
    return { messageId: m.messageId, success: true };
  });
}

async function sendViaSendGrid(messages: EmailMessage[]): Promise<EmailResult[]> {
  // Dynamic import so the package is optional
  const sgMail = await import('@sendgrid/mail').catch(() => null);
  if (!sgMail) throw new Error('Install @sendgrid/mail to use sendgrid provider');
  sgMail.default.setApiKey(process.env.SENDGRID_API_KEY!);

  const results: EmailResult[] = [];
  for (const m of messages) {
    try {
      await sgMail.default.send({
        to:      m.to,
        from:    { name: m.fromName, email: m.fromAddress },
        replyTo: m.replyTo,
        subject: m.subject,
        html:    injectCanSpamFooter(m.htmlBody, m.unsubscribeToken, m.physicalAddress),
      });
      results.push({ messageId: m.messageId, success: true });
    } catch (err) {
      results.push({ messageId: m.messageId, success: false, error: String(err) });
    }
  }
  return results;
}

async function sendViaResend(messages: EmailMessage[]): Promise<EmailResult[]> {
  const { Resend } = await import('resend').catch(() => { throw new Error('Install resend to use resend provider'); });
  const resend = new Resend(process.env.RESEND_API_KEY!);

  const results: EmailResult[] = [];
  for (const m of messages) {
    try {
      await resend.emails.send({
        to:      [m.to],
        from:    `${m.fromName} <${m.fromAddress}>`,
        replyTo: m.replyTo,
        subject: m.subject,
        html:    injectCanSpamFooter(m.htmlBody, m.unsubscribeToken, m.physicalAddress),
      });
      results.push({ messageId: m.messageId, success: true });
    } catch (err) {
      results.push({ messageId: m.messageId, success: false, error: String(err) });
    }
  }
  return results;
}

export async function sendBulkEmail(messages: EmailMessage[]): Promise<EmailResult[]> {
  if (messages.length === 0) return [];
  const provider = (process.env.EMAIL_PROVIDER ?? 'mock').toLowerCase();
  switch (provider) {
    case 'sendgrid': return sendViaSendGrid(messages);
    case 'resend':   return sendViaResend(messages);
    case 'mock':
    default:         return sendViaMock(messages);
  }
}
