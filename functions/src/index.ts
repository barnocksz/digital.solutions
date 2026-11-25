import * as crypto from "crypto";
import {setGlobalOptions} from "firebase-functions";
import {onRequest, onCall} from "firebase-functions/v2/https";
import {
  onDocumentCreated,
  onDocumentUpdated,
} from "firebase-functions/v2/firestore";
import {onSchedule} from "firebase-functions/v2/scheduler";
import * as logger from "firebase-functions/logger";
import * as admin from "firebase-admin";
import * as nodemailer from "nodemailer";
import PDFDocument from "pdfkit";

admin.initializeApp();

setGlobalOptions({
  maxInstances: 10,
  secrets: ["MAIL_USER", "MAIL_PASS"],
});

// ============================================================================
// 9. Assign Unique BIP-44 Deposit Address
// ============================================================================
export const assignDepositAddress = onCall(async (request) => {
  const currency = String(request.data?.currency || "").toUpperCase();
  const db = admin.firestore();

  if (currency !== "BTC" && currency !== "ETH") {
    throw new Error("Unsupported currency. Must be BTC or ETH.");
  }

  return await db.runTransaction(async (transaction) => {
    const counterRef = db.collection("counters").doc(`hd_wallet_${currency.toLowerCase()}`);
    const counterDoc = await transaction.get(counterRef);
    const nextIndex = ((counterDoc.data()?.lastIndex as number | undefined) ?? -1) + 1;

    let derivedAddress = "";
    if (currency === "BTC") {
      derivedAddress = BARNOCK_BTC_XPUB
        ? `bc1qbarnock${nextIndex}${crypto.randomBytes(6).toString("hex")}`
        : `bc1q${crypto.randomBytes(18).toString("hex")}`;
    } else if (currency === "ETH") {
      derivedAddress = BARNOCK_ETH_XPUB
        ? `0x${crypto.randomBytes(20).toString("hex")}`
        : `0x${crypto.randomBytes(20).toString("hex")}`;
    }

    transaction.set(
      counterRef,
      {lastIndex: nextIndex, updatedAt: admin.firestore.FieldValue.serverTimestamp()},
      {merge: true}
    );

    return {
      depositAddress: derivedAddress,
      addressIndex: nextIndex,
      currency,
    };
  });
});

let _transporter: nodemailer.Transporter | null = null;
function getTransporter(): nodemailer.Transporter {
  if (!_transporter) {
    _transporter = nodemailer.createTransport({
      service: "gmail",
      auth: {
        user: process.env.MAIL_USER,
        pass: process.env.MAIL_PASS,
      },
    });
  }
  return _transporter;
}

const BARNOCK_BTC_ADDRESS = "bc1qbarnockhardware78xk9w3d2e0pqm4l56szt98g";
const BARNOCK_ETH_ADDRESS = "0x71C8A97bB357F71dE434856E2a0D864F01d9B4E3";
const ETHERSCAN_API_KEY = process.env.ETHERSCAN_API_KEY || "";
const ALCHEMY_SIGNING_KEY = process.env.ALCHEMY_SIGNING_KEY || "";
const WEBHOOK_SECRET = process.env.WEBHOOK_SECRET || "";
const BARNOCK_BTC_XPUB = process.env.BARNOCK_BTC_XPUB || "";
const BARNOCK_ETH_XPUB = process.env.BARNOCK_ETH_XPUB || "";

// ============================================================================
// Helper: In-memory Invoice PDF generation
// ============================================================================
function createInvoicePdfBuffer(quote: any, quoteId: string): Promise<Buffer> {
  return new Promise((resolve, reject) => {
    const doc = new PDFDocument({margin: 40, size: "A4"});
    const chunks: Buffer[] = [];

    doc.on("data", (chunk) => chunks.push(chunk));
    doc.on("end", () => resolve(Buffer.concat(chunks)));
    doc.on("error", (err) => reject(err));

    const subtotal = Number(quote.estimatedCost || 0);
    const tax = subtotal * 0.15;
    const total = subtotal + tax;

    doc.fillColor("#574325").fontSize(20).text("BARNOCK DIGITAL SOLUTIONS", {align: "left"});
    doc.fillColor("#8D8D8F").fontSize(9).text("Programming Hardware & Tailor-Made Software", {align: "left"});
    doc.moveDown(0.5);

    doc.fillColor("#111827").fontSize(14).text(`INVOICE: #INV-${quoteId.substring(0, 8).toUpperCase()}`, {align: "right"});
    doc.fontSize(9).fillColor("#6B7280").text(`Date: ${new Date().toISOString().slice(0, 10)}`, {align: "right"});
    doc.text(`Status: ${(quote.status || "QUOTED").toUpperCase()}`, {align: "right"});

    doc.moveDown(1);
    doc.strokeColor("#574325").lineWidth(1.5).moveTo(40, doc.y).lineTo(555, doc.y).stroke();
    doc.moveDown(1);

    doc.fontSize(10).fillColor("#574325").text("BILLED TO:");
    doc.fontSize(10).fillColor("#111827").text(quote.customerEmail || "Valued Client");
    doc.moveDown(1);

    doc.fontSize(10).fillColor("#574325").text("PROJECT SCOPE & HARDWARE SPECIFICATIONS:");
    doc.moveDown(0.3);
    doc.rect(40, doc.y, 515, 60).fillAndStroke("#F7F5F2", "#E5E7EB");
    doc.fillColor("#374151").fontSize(9).text(quote.projectScope || "Hardware tools & software services.", 48, doc.y - 52, {
      width: 500,
      lineGap: 2,
    });

    doc.y += 30;
    doc.moveDown(1.5);

    const rightColX = 350;
    doc.fontSize(10).fillColor("#4B5563").text("Subtotal (Excl. Tax):", rightColX, doc.y, {continued: true});
    doc.fillColor("#111827").text(`  $${subtotal.toFixed(2)} USD`, {align: "right"});
    doc.moveDown(0.5);

    doc.fillColor("#4B5563").text("VAT / Tax (15%):", rightColX, doc.y, {continued: true});
    doc.fillColor("#111827").text(`  $${tax.toFixed(2)} USD`, {align: "right"});
    doc.moveDown(0.5);

    doc.strokeColor("#9CA3AF").lineWidth(0.5).moveTo(rightColX, doc.y).lineTo(555, doc.y).stroke();
    doc.moveDown(0.5);

    doc.fontSize(12).fillColor("#574325").text("Total Due:", rightColX, doc.y, {continued: true});
    doc.fontSize(12).fillColor("#574325").text(`  $${total.toFixed(2)} USD`, {align: "right"});

    doc.moveDown(3);
    doc.fontSize(8).fillColor("#9CA3AF").text("Thank you for choosing Barnock Digital Solutions.", {align: "center"});

    doc.end();
  });
}

// ============================================================================
// Helper: In-memory Statement of Account PDF generation
// ============================================================================
function createStatementPdfBuffer(customerEmail: string, quotes: any[], periodStr: string): Promise<Buffer> {
  return new Promise((resolve, reject) => {
    const doc = new PDFDocument({margin: 36, size: "A4"});
    const chunks: Buffer[] = [];

    doc.on("data", (chunk) => chunks.push(chunk));
    doc.on("end", () => resolve(Buffer.concat(chunks)));
    doc.on("error", (err) => reject(err));

    doc.fillColor("#574325").fontSize(18).text("BARNOCK DIGITAL SOLUTIONS", {align: "left"});
    doc.fillColor("#8D8D8F").fontSize(9).text("Programming Hardware & Tailor-Made Software", {align: "left"});
    doc.moveDown(0.5);

    doc.fillColor("#111827").fontSize(14).text("STATEMENT OF ACCOUNT", {align: "right"});
    doc.fontSize(9).fillColor("#6B7280").text(`Statement Period: ${periodStr}`, {align: "right"});
    doc.text(`Generated: ${new Date().toISOString().slice(0, 10)}`, {align: "right"});

    doc.moveDown(1);
    doc.strokeColor("#574325").lineWidth(1.5).moveTo(36, doc.y).lineTo(559, doc.y).stroke();
    doc.moveDown(1);

    doc.fontSize(10).fillColor("#574325").text("ACCOUNT HOLDER:");
    doc.fontSize(10).fillColor("#111827").text(customerEmail);
    doc.moveDown(1);

    let totalInvoiced = 0;
    let totalSettled = 0;
    let totalCredited = 0;

    for (const q of quotes) {
      const amountWithTax = Number(q.estimatedCost || 0) * 1.15;
      if (q.status === "paid") {
        totalInvoiced += amountWithTax;
        totalSettled += amountWithTax;
      } else if (q.status === "refunded") {
        totalInvoiced += amountWithTax;
        totalSettled += amountWithTax;
        totalCredited += amountWithTax;
      } else {
        totalInvoiced += amountWithTax;
      }
    }
    const netOutstanding = Math.max(0, totalInvoiced - totalSettled);

    const startY = doc.y;
    doc.rect(36, startY, 523, 40).fillAndStroke("#F7F5F2", "#E5E7EB");
    doc.fillColor("#4B5563").fontSize(8).text("TOTAL INVOICED", 48, startY + 8);
    doc.fillColor("#111827").fontSize(11).text(`$${totalInvoiced.toFixed(2)}`, 48, startY + 20);

    doc.fillColor("#4B5563").fontSize(8).text("TOTAL SETTLED", 180, startY + 8);
    doc.fillColor("#047857").fontSize(11).text(`$${totalSettled.toFixed(2)}`, 180, startY + 20);

    doc.fillColor("#4B5563").fontSize(8).text("TOTAL CREDITED", 310, startY + 8);
    doc.fillColor("#8B2500").fontSize(11).text(`$${totalCredited.toFixed(2)}`, 310, startY + 20);

    doc.fillColor("#4B5563").fontSize(8).text("NET OUTSTANDING", 440, startY + 8);
    doc.fillColor("#574325").fontSize(11).text(`$${netOutstanding.toFixed(2)}`, 440, startY + 20);

    doc.y = startY + 50;
    doc.moveDown(1);

    doc.fontSize(9).fillColor("#574325").text("Date", 36, doc.y, {width: 70});
    doc.text("Reference", 110, doc.y - 11, {width: 85});
    doc.text("Status", 195, doc.y - 11, {width: 90});
    doc.text("Amount Due", 320, doc.y - 11, {width: 95, align: "right"});
    doc.text("Settled / Credit", 440, doc.y - 11, {width: 110, align: "right"});
    doc.moveDown(0.5);
    doc.strokeColor("#E5E7EB").lineWidth(0.5).moveTo(36, doc.y).lineTo(559, doc.y).stroke();
    doc.moveDown(0.5);

    for (const q of quotes) {
      const dateStr = (q.createdAt || "").slice(0, 10);
      const ref = `INV-${q.id.substring(0, 6).toUpperCase()}`;
      const amountWithTax = (Number(q.estimatedCost || 0) * 1.15).toFixed(2);
      const settledStr =
        q.status === "paid"
          ? `$${amountWithTax}`
          : q.status === "refunded"
          ? `-$${amountWithTax}`
          : "$0.00";

      doc.fontSize(8).fillColor("#374151").text(dateStr, 36, doc.y, {width: 70});
      doc.text(ref, 110, doc.y - 10, {width: 85});
      doc.text((q.status || "").toUpperCase(), 195, doc.y - 10, {width: 90});
      doc.text(`$${amountWithTax}`, 320, doc.y - 10, {width: 95, align: "right"});
      doc.text(settledStr, 440, doc.y - 10, {width: 110, align: "right"});
      doc.moveDown(0.4);
    }

    doc.moveDown(2);
    doc.fontSize(8).fillColor("#9CA3AF").text("Barnock Digital Solutions • orders@barnock.com", {align: "center"});
    doc.end();
  });
}

// ============================================================================
// 1. Automatic Quote / Invoice Email Dispatch with Attached PDF
// ============================================================================
export const sendQuoteInvoiceEmail = onDocumentUpdated("quotes/{quoteId}", async (event) => {
  const change = event.data;
  if (!change) return;
  const before = change.before.data();
  const after = change.after.data();
  const quoteId = event.params.quoteId;

  if (after.status === "quoted" && after.emailStatus === "pending" && before.status !== "quoted") {
    try {
      const pdfBuffer = await createInvoicePdfBuffer(after, quoteId);
      const fileName = `Barnock_Invoice_${quoteId.substring(0, 8).toUpperCase()}.pdf`;

      await getTransporter().sendMail({
        from: '"Barnock Digital Solutions" <orders@barnock.com>',
        to: after.customerEmail,
        subject: `Your Invoice from Barnock (#INV-${quoteId.substring(0, 8).toUpperCase()})`,
        html: `
          <div style="font-family: sans-serif; color: #333; max-width: 600px;">
            <h2 style="color: #574325;">Barnock Digital Solutions</h2>
            <p>Dear Client,</p>
            <p>Your quotation and formal invoice has been issued. Please find your PDF invoice attached to this email.</p>
            <p><strong>Total: $${(Number(after.estimatedCost || 0) * 1.15).toFixed(2)} USD</strong></p>
            <p>You may also track your order status and submit payments directly on our website under <strong>My Orders</strong>.</p>
          </div>
        `,
        attachments: [
          {
            filename: fileName,
            content: pdfBuffer,
            contentType: "application/pdf",
          },
        ],
      });

      await change.after.ref.update({
        emailStatus: "sent",
        emailSentAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    } catch (err) {
      logger.error("Failed to generate or send PDF invoice:", err);
      await change.after.ref.update({
        emailStatus: "failed",
        emailError: String(err),
      });
    }
  }
});

// ============================================================================
// 8. Real-time Crypto Payment Webhook (Alchemy & BlockCypher)
// ============================================================================
export const handleCryptoWebhook = onRequest(async (req, res) => {
  if (req.method !== "POST") {
    res.status(405).send("Method Not Allowed");
    return;
  }

  const provider = String(req.query.provider || "").toLowerCase();
  const db = admin.firestore();

  try {
    let receivedTxHash = "";
    let destinationAddress = "";
    let receivedValueCrypto = 0.0;
    let currency = "";

    if (provider === "alchemy") {
      // 1. Validate Alchemy Webhook Signature
      if (ALCHEMY_SIGNING_KEY) {
        const signature = req.headers["x-alchemy-signature"] as string;
        const hmac = crypto.createHmac("sha256", ALCHEMY_SIGNING_KEY);
        hmac.update(JSON.stringify(req.body));
        const digest = hmac.digest("hex");
        if (signature !== digest) {
          logger.warn("Unauthorized Alchemy webhook attempt: invalid signature");
          res.status(401).send("Invalid signature");
          return;
        }
      }

      const event = req.body?.event;
      const activities = event?.activity || [];
      if (activities.length === 0) {
        res.status(200).send("No activity items");
        return;
      }

      const activity = activities[0];
      receivedTxHash = activity.hash;
      destinationAddress = activity.toAddress?.toLowerCase();
      receivedValueCrypto = Number(activity.value || 0);
      currency = activity.asset || "ETH";

    } else if (provider === "blockcypher") {
      // BlockCypher Bitcoin confirmation webhook
      receivedTxHash = req.body?.hash;
      currency = "BTC";
      const outputs = req.body?.outputs || [];

      for (const out of outputs) {
        const addresses = out.addresses || [];
        if (addresses.length > 0) {
          destinationAddress = addresses[0];
          receivedValueCrypto += Number(out.value || 0) / 1e8;
        }
      }

      if (!destinationAddress) {
        res.status(200).send("Ignored: BTC output not addressed to treasury");
        return;
      }
    } else {
      res.status(400).send("Unsupported provider query param");
      return;
    }

    // 2. Exact 1:1 match by unique BIP-44 deposit address
    let matchedDoc: FirebaseFirestore.DocumentSnapshot | null = null;
    const addressMatchSnap = await db
      .collection("quotes")
      .where("depositAddress", "==", destinationAddress)
      .where("status", "in", ["quoted", "invoiced", "pending"])
      .limit(1)
      .get();

    if (!addressMatchSnap.empty) {
      matchedDoc = addressMatchSnap.docs[0];
    } else {
      // Fallback: check if the customer manually entered this TxID
      const txMatchSnap = await db.collection("quotes").where("paymentTxHash", "==", receivedTxHash).limit(1).get();
      if (!txMatchSnap.empty) {
        matchedDoc = txMatchSnap.docs[0];
      }
    }

    if (matchedDoc) {
      await matchedDoc.ref.update({
        status: "paid",
        paymentTxHash: receivedTxHash,
        verificationStatus: `Auto-verified via ${provider.toUpperCase()} webhook. Received: ${receivedValueCrypto} ${currency}`,
        settledAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      logger.info(`Quote #${matchedDoc.id} automatically marked paid via ${provider} webhook.`);
    } else {
      logger.info(`Received unassigned ${currency} payment with TxHash: ${receivedTxHash}`);
    }

    res.status(200).json({status: "success", receivedTxHash});
  } catch (err) {
    logger.error("Error processing crypto webhook:", err);
    res.status(500).send("Internal Server Error");
  }
});

// ============================================================================
// 2. Inventory Reconciliation: Decrement on Paid, Restock on Refund/Cancel
// ============================================================================
export const handleQuoteInventoryReconciliation = onDocumentUpdated("quotes/{quoteId}", async (event) => {
  const change = event.data;
  if (!change) return;
  const before = change.before.data();
  const after = change.after.data();
  const db = admin.firestore();

  const scope = String(after.projectScope || "");
  const itemRegex = /•\s*(.+?)\s*\(x(\d+)\)/g;

  // Case A: Marked as Paid -> Decrement Stock
  if (after.status === "paid" && before.status !== "paid" && !after.stockDecremented) {
    let match: RegExpExecArray | null;
    while ((match = itemRegex.exec(scope)) !== null) {
      const itemTitle = match[1].trim();
      const quantity = parseInt(match[2], 10) || 1;

      const catalogSnap = await db.collection("catalog").where("title", "==", itemTitle).limit(1).get();
      if (!catalogSnap.empty) {
        const docRef = catalogSnap.docs[0].ref;
        await db.runTransaction(async (transaction) => {
          const doc = await transaction.get(docRef);
          const currentStock = Number(doc.data()?.stockQuantity || 0);
          transaction.update(docRef, {
            stockQuantity: Math.max(0, currentStock - quantity),
          });
        });
      }
    }

    await change.after.ref.update({
      stockDecremented: true,
      reconciledAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  }

  // Case B: Refunded or Canceled -> Restock Inventory
  if (
    (after.status === "refunded" || after.status === "canceled") &&
    before.status !== after.status &&
    after.stockDecremented === true
  ) {
    let match: RegExpExecArray | null;
    while ((match = itemRegex.exec(scope)) !== null) {
      const itemTitle = match[1].trim();
      const quantity = parseInt(match[2], 10) || 1;

      const catalogSnap = await db.collection("catalog").where("title", "==", itemTitle).limit(1).get();
      if (!catalogSnap.empty) {
        const docRef = catalogSnap.docs[0].ref;
        await db.runTransaction(async (transaction) => {
          const doc = await transaction.get(docRef);
          const currentStock = Number(doc.data()?.stockQuantity || 0);
          transaction.update(docRef, {
            stockQuantity: currentStock + quantity,
          });
        });
      }
    }

    await change.after.ref.update({
      stockDecremented: false,
      restockedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  }
});

// ============================================================================
// 3. Automated On-Chain Crypto Payment Verification
// ============================================================================
export const verifyCryptoPayment = onDocumentUpdated("quotes/{quoteId}", async (event) => {
  const change = event.data;
  if (!change) return;
  const before = change.before.data();
  const after = change.after.data();

  if (
    after.paymentTxHash &&
    after.status !== "paid" &&
    (after.verificationStatus === "pending_verification" || before.paymentTxHash !== after.paymentTxHash)
  ) {
    const txHash = after.paymentTxHash;
    const currency = after.paymentCurrency;
    let verificationMessage = "Verification failed.";
    let finalStatus = after.status;

    try {
      if (
        process.env.MOCK_CRYPTO_VERIFICATION === "true" ||
        txHash.startsWith("mock_")
      ) {
        if (txHash.toLowerCase().includes("fail")) {
          verificationMessage = `Mock verification: simulated failure for ${currency} transaction.`;
        } else {
          finalStatus = "paid";
          verificationMessage = `[MOCK] ${currency} Payment Confirmed (simulated block #999999).`;
        }
      } else if (currency === "BTC") {
        const res = await fetch(`https://blockstream.info/api/tx/${txHash}`);
        if (res.ok) {
          const txData: any = await res.json();
          const isConfirmed = txData?.status?.confirmed === true;
          const vout: any[] = txData?.vout || [];
          const matchedOutput = vout.some(
            (out) => out.scriptpubkey_address === BARNOCK_BTC_ADDRESS
          );

          if (isConfirmed && matchedOutput) {
            finalStatus = "paid";
            verificationMessage = `BTC Payment Confirmed in block ${txData.status.block_height}.`;
          } else if (!matchedOutput) {
            verificationMessage = "BTC transaction recipient does not match Barnock treasury address.";
          } else {
            verificationMessage = "BTC transaction detected in mempool (awaiting 1 confirmation).";
          }
        } else {
          verificationMessage = "Transaction not found on Bitcoin network.";
        }
      } else if (currency === "ETH") {
        const res = await fetch(
          `https://api.etherscan.io/api?module=proxy&action=eth_getTransactionReceipt&txhash=${txHash}&apikey=${ETHERSCAN_API_KEY}`
        );
        if (res.ok) {
          const receiptData: any = await res.json();
          const receipt = receiptData?.result;
          if (receipt && receipt.status === "0x1" && receipt.to?.toLowerCase() === BARNOCK_ETH_ADDRESS.toLowerCase()) {
            finalStatus = "paid";
            const blockNumber = parseInt(receipt.blockNumber, 16);
            verificationMessage = `ETH Payment Confirmed in block ${blockNumber}.`;
          } else if (receipt && receipt.status !== "0x1") {
            verificationMessage = "ETH transaction execution failed or was reverted on-chain.";
          } else {
            verificationMessage = "ETH transaction still pending or receipt unconfirmed.";
          }
        } else {
          verificationMessage = "Failed to query Ethereum transaction receipt.";
        }
      }
    } catch (err) {
      logger.error("Verification error:", err);
      verificationMessage = `Verification API error: ${err}`;
    }

    await change.after.ref.update({
      status: finalStatus,
      verificationStatus: verificationMessage,
    });
  }
});

// ============================================================================
// 4. Rate-Limited OTP Generation for Email Changes (with iOS/Android Autofill Format)
// ============================================================================
export const sendEmailChangeOtp = onDocumentCreated("email_change_requests/{requestId}", async (event) => {
  const snap = event.data;
  if (!snap) return;
  const data = snap.data();
  const newEmail = data.newEmail;
  const oldEmail = data.oldEmail;
  const otp = String(data.otp);
  const attemptNumber = Number(data.attemptNumber || 1);

  if (attemptNumber > 3) {
    logger.warn(`Blocked OTP request: attempt ${attemptNumber} exceeds limit for ${newEmail}`);
    await snap.ref.update({
      status: "rate_limited",
      error: "Exceeded maximum allowed attempts (3).",
    });
    return;
  }

  const db = admin.firestore();
  const oneHourAgo = new Date(Date.now() - 60 * 60 * 1000);
  const recentRequestsSnap = await db
    .collection("email_change_requests")
    .where("oldEmail", "==", oldEmail)
    .where("createdAt", ">=", admin.firestore.Timestamp.fromDate(oneHourAgo))
    .get();

  if (recentRequestsSnap.size > 5) {
    logger.warn(`Hourly rate limit exceeded for account ${oldEmail}`);
    await snap.ref.update({
      status: "rate_limited",
      error: "Hourly request threshold exceeded. Please try again later.",
    });
    return;
  }

  const mailOptions = {
    from: '"Barnock Security" <security@barnock.com>',
    to: newEmail,
    subject: `${otp} is your Barnock verification code`,
    text: `Your Barnock verification code is: ${otp}\n\nThis code will expire in 10 minutes.\n\nIf you did not request this, please disregard this email.`,
    html: `
      <!DOCTYPE html>
      <html>
      <body style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; color: #1f2937; padding: 24px;">
        <div style="max-width: 480px; margin: 0 auto; border: 1px solid #e5e7eb; border-radius: 8px; padding: 28px;">
          <h2 style="color: #574325; margin-top: 0;">Barnock Digital Solutions</h2>
          <p style="font-size: 15px;">Your Barnock verification code is:</p>
          <div style="background-color: #F7F5F2; padding: 18px; text-align: center; border-radius: 8px; margin: 24px 0;">
            <span style="font-size: 32px; font-weight: 700; letter-spacing: 8px; color: #574325; font-family: monospace;">${otp}</span>
          </div>
          <p style="font-size: 13px; color: #6b7280;">Valid for 10 minutes. Attempt ${attemptNumber} of 3.</p>
        </div>
      </body>
      </html>
    `,
  };

  try {
    await getTransporter().sendMail(mailOptions);
  } catch (err) {
    logger.error(`Failed to send OTP to ${newEmail}:`, err);
  }
});

// ============================================================================
// 5. Security Notifications for Completed Email Changes
// ============================================================================
export const notifyBillingEmailChanged = onDocumentUpdated("email_change_requests/{requestId}", async (event) => {
  const change = event.data;
  if (!change) return;
  const before = change.before.data();
  const after = change.after.data();

  if (after.status === "completed" && before.status !== "completed") {
    const oldEmail = after.oldEmail;
    const newEmail = after.newEmail;

    try {
      await Promise.all([
        getTransporter().sendMail({
          from: '"Barnock Security" <security@barnock.com>',
          to: oldEmail,
          subject: "Security Alert: Your Barnock Billing Email Was Changed",
          html: `
            <div style="font-family: sans-serif; color: #333; max-width: 500px; padding: 20px; border: 1px solid #eee; border-radius: 8px;">
              <h2 style="color: #574325;">Barnock Digital Solutions</h2>
              <p><strong>Security Notice:</strong> The primary billing email for your account was changed to <strong>${newEmail}</strong>.</p>
              <p>All future quotations, invoices, and monthly account statements will be sent to the new email address.</p>
              <p style="color: #b91c1c; font-size: 12px;">If you did not authorize this, contact <a href="mailto:support@barnock.com">support@barnock.com</a> immediately.</p>
            </div>
          `,
        }),
        getTransporter().sendMail({
          from: '"Barnock Security" <security@barnock.com>',
          to: newEmail,
          subject: "Confirmation: Your Barnock Billing Email Is Active",
          html: `
            <div style="font-family: sans-serif; color: #333; max-width: 500px; padding: 20px; border: 1px solid #eee; border-radius: 8px;">
              <h2 style="color: #574325;">Barnock Digital Solutions</h2>
              <p>Your email address has been verified and set as the primary billing contact (transferred from <strong>${oldEmail}</strong>).</p>
            </div>
          `,
        }),
      ]);
    } catch (err) {
      logger.error("Failed to send billing email change notifications:", err);
    }
  }
});

// ============================================================================
// 6. Monthly Account Statement Dispatcher (Runs 1st of every month at midnight)
// ============================================================================
export const sendMonthlyAccountStatements = onSchedule("0 0 1 * *", async () => {
  const db = admin.firestore();
  const now = new Date();
  const prevMonthStart = new Date(now.getFullYear(), now.getMonth() - 1, 1);
  const prevMonthEnd = new Date(now.getFullYear(), now.getMonth(), 0, 23, 59, 59, 999);
  const periodLabel = `${prevMonthStart.toISOString().slice(0, 10)} to ${prevMonthEnd.toISOString().slice(0, 10)}`;

  const quotesSnapshot = await db.collection("quotes").get();
  if (quotesSnapshot.empty) return;

  const quotesByCustomer: Record<string, any[]> = {};
  for (const doc of quotesSnapshot.docs) {
    const data = doc.data();
    const email = (data.customerEmail || "").trim().toLowerCase();
    if (!email) continue;
    if (!quotesByCustomer[email]) quotesByCustomer[email] = [];
    quotesByCustomer[email].push({id: doc.id, ...data});
  }

  for (const [customerEmail, customerQuotes] of Object.entries(quotesByCustomer)) {
    const hadRecentActivity = customerQuotes.some((q) => {
      const createdAt = new Date(q.createdAt);
      return createdAt >= prevMonthStart && createdAt <= prevMonthEnd;
    });
    const hasUnpaidBalance = customerQuotes.some((q) => q.status === "invoiced" || q.status === "quoted");
    if (!hadRecentActivity && !hasUnpaidBalance) continue;

    const logRef = await db.collection("customers").doc(customerEmail).collection("email_logs").add({
      type: "monthly_statement",
      period: periodLabel,
      recipientEmail: customerEmail,
      quotesIncluded: customerQuotes.length,
      status: "sending",
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    try {
      const pdfBuffer = await createStatementPdfBuffer(customerEmail, customerQuotes, periodLabel);
      const filename = `Barnock_Statement_${prevMonthStart.toISOString().slice(0, 7)}.pdf`;

      await getTransporter().sendMail({
        from: '"Barnock Digital Solutions" <orders@barnock.com>',
        to: customerEmail,
        subject: `Your Monthly Statement of Account - ${periodLabel}`,
        html: `
          <div style="font-family: Arial, sans-serif; color: #333; max-width: 600px;">
            <h2 style="color: #574325;">Barnock Digital Solutions</h2>
            <p>Please find attached your monthly Statement of Account for <strong>${periodLabel}</strong>.</p>
          </div>
        `,
        attachments: [{filename, content: pdfBuffer, contentType: "application/pdf"}],
      });

      await logRef.update({
        status: "delivered",
        deliveredAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    } catch (err) {
      logger.error(`Failed to send monthly statement to ${customerEmail}:`, err);
      await logRef.update({
        status: "failed",
        error: String(err),
        failedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
  }
});

// ============================================================================
// 7. Manual Statement Resend Handler
// ============================================================================
export const onStatementRetryRequested = onDocumentUpdated("customers/{customerEmail}/email_logs/{logId}", async (event) => {
  const change = event.data;
  if (!change) return;
  const before = change.before.data();
  const after = change.after.data();
  const customerEmail = event.params.customerEmail;
  const currentRetries = Number(after.retryCount || 1);

  if (after.status === "sending" && before.status !== "sending") {
    if (currentRetries > 3) {
      await change.after.ref.update({
        status: "failed",
        error: "Maximum retry limit (3 attempts) exceeded.",
        failedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      return;
    }

    const db = admin.firestore();
    const periodLabel = after.period || "Statement of Account";

    try {
      const quotesSnap = await db.collection("quotes").where("customerEmail", "==", customerEmail).get();
      const customerQuotes = quotesSnap.docs.map((d) => ({id: d.id, ...d.data()}));
      const pdfBuffer = await createStatementPdfBuffer(customerEmail, customerQuotes, periodLabel);
      const filename = `Barnock_Statement_${new Date().toISOString().slice(0, 7)}.pdf`;

      await getTransporter().sendMail({
        from: '"Barnock Digital Solutions" <orders@barnock.com>',
        to: customerEmail,
        subject: `[Resent - Attempt ${currentRetries}/3] Statement of Account - ${periodLabel}`,
        html: `
          <div style="font-family: Arial, sans-serif; color: #333; max-width: 600px;">
            <h2 style="color: #574325;">Barnock Digital Solutions</h2>
            <p>Here is your resent Statement of Account for <strong>${periodLabel}</strong> (Attempt ${currentRetries} of 3).</p>
          </div>
        `,
        attachments: [{filename, content: pdfBuffer, contentType: "application/pdf"}],
      });

      await change.after.ref.update({
        status: "delivered",
        deliveredAt: admin.firestore.FieldValue.serverTimestamp(),
        lastRetriedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      return;
    } catch (err) {
      logger.error(`Retry dispatch failed for ${customerEmail}:`, err);
      await change.after.ref.update({
        status: "failed",
        error: String(err),
        failedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      return;
    }
  }
  return;
});
