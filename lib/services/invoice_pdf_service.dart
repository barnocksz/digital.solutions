import 'package:flutter/services.dart' show rootBundle;
import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/quote.dart';

class InvoicePdfService {
  static const double defaultTaxRate = 0.15; // 15% VAT / Sales Tax

  /// Generates the raw PDF bytes with the Barnock logo, tax calculations, and payment details
  static Future<Uint8List> generateInvoicePdfBytes({
    required Quote quote,
    String companyName = 'Barnock Digital Solutions',
    double taxRate = defaultTaxRate,
  }) async {
    final pdf = pw.Document();

    final primaryColor = PdfColor.fromHex('574325');
    final secondaryColor = PdfColor.fromHex('8D8D8F');
    final lightBgColor = PdfColor.fromHex('F7F5F2');

    // Load the brand logo asset
    pw.MemoryImage? logoImage;
    try {
      final byteData = await rootBundle.load('assets/images/barnock_full_logo_brown.png');
      logoImage = pw.MemoryImage(byteData.buffer.asUint8List());
    } catch (_) {
      // Fallback if the asset is missing or failing to resolve
      logoImage = null;
    }

    final subtotal = quote.estimatedCost;
    final taxAmount = subtotal * taxRate;
    final grandTotal = subtotal + taxAmount;

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Top Header: Logo + Invoice Metadata
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  if (logoImage != null)
                    pw.Container(
                      height: 48,
                      child: pw.Image(logoImage, fit: pw.BoxFit.contain),
                    )
                  else
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          companyName,
                          style: pw.TextStyle(
                            fontSize: 22,
                            fontWeight: pw.FontWeight.bold,
                            color: primaryColor,
                          ),
                        ),
                        pw.Text(
                          'Programming Hardware & Tailor-Made Software',
                          style: pw.TextStyle(fontSize: 9, color: secondaryColor),
                        ),
                      ],
                    ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        'FORMAL INVOICE',
                        style: pw.TextStyle(
                          fontSize: 20,
                          fontWeight: pw.FontWeight.bold,
                          color: primaryColor,
                        ),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        'Invoice #: INV-${quote.id.substring(0, quote.id.length > 8 ? 8 : quote.id.length).toUpperCase()}',
                        style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
                      ),
                      pw.Text(
                        'Date: ${quote.createdAt.toIso8601String().substring(0, 10)}',
                        style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                      ),
                      pw.Text(
                        'Status: ${quote.status.toUpperCase()}',
                        style: pw.TextStyle(
                          fontSize: 10,
                          fontWeight: pw.FontWeight.bold,
                          color: quote.status == 'paid' ? PdfColors.green700 : primaryColor,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 18),
              pw.Divider(thickness: 1, color: primaryColor),
              pw.SizedBox(height: 14),

              // Client & Merchant Billing Info
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('BILLED TO:', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: secondaryColor)),
                      pw.SizedBox(height: 4),
                      pw.Text(quote.customerEmail, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
                      pw.Text('Customer Ref: ${quote.customerId.isEmpty ? "Standard Client" : quote.customerId}', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text('ISSUED BY:', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: secondaryColor)),
                      pw.SizedBox(height: 4),
                      pw.Text('Barnock Digital Solutions', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
                      pw.Text('support@barnock.com', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                      pw.Text('Tax / VAT Reg: SZ-44910284', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 20),

              // Project Scope & Deliverables Card
              pw.Text('PROJECT SCOPE & HARDWARE SPECIFICATIONS',
                  style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: secondaryColor)),
              pw.SizedBox(height: 6),
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  color: lightBgColor,
                  borderRadius: pw.BorderRadius.circular(6),
                  border: pw.Border.all(color: PdfColors.grey300),
                ),
                child: pw.Text(
                  quote.projectScope.isEmpty ? 'Programming hardware and custom software deliverables.' : quote.projectScope,
                  style: const pw.TextStyle(fontSize: 10, lineSpacing: 2),
                ),
              ),
              pw.SizedBox(height: 18),

              // Financial Summary & Tax Breakdown Table
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.end,
                children: [
                  pw.Container(
                    width: 240,
                    child: pw.Column(
                      children: [
                        _buildPriceRow('Subtotal (Excl. Tax):', '\$${subtotal.toStringAsFixed(2)}'),
                        pw.SizedBox(height: 4),
                        _buildPriceRow('VAT / Tax (${(taxRate * 100).toInt()}%):', '\$${taxAmount.toStringAsFixed(2)}'),
                        pw.Divider(thickness: 0.8, color: PdfColors.grey400),
                        _buildPriceRow(
                          'Total Due (USD):',
                          '\$${grandTotal.toStringAsFixed(2)}',
                          isTotal: true,
                          primaryColor: primaryColor,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              pw.Spacer(),

              // Payment Instructions & Footer
              pw.Container(
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey100,
                  borderRadius: pw.BorderRadius.circular(4),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('Settlement Instructions:',
                        style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: primaryColor)),
                    pw.SizedBox(height: 2),
                    pw.Text('Bank Transfer (SZL/ZAR): FNB Eswatini | Acc: 62894109823 | Branch: 280164 | Ref: INV-${quote.id.substring(0, 6)}',
                        style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey800)),
                    pw.Text('Crypto Settlement (BTC/ETH): Send payment to treasury address specified in order quote details.',
                        style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey800)),
                  ],
                ),
              ),
              pw.SizedBox(height: 8),
              pw.Center(
                child: pw.Text(
                  'Thank you for partnering with Barnock. For questions, contact support@barnock.com.',
                  style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
                ),
              ),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  /// Generates a formal Credit Note PDF for refunded orders
  static Future<Uint8List> generateCreditNotePdfBytes({
    required Quote quote,
    String companyName = 'Barnock Digital Solutions',
    double taxRate = defaultTaxRate,
  }) async {
    final pdf = pw.Document();

    final primaryColor = PdfColor.fromHex('8B2500'); // Rust/Crimson credit note tone
    final secondaryColor = PdfColor.fromHex('8D8D8F');
    final lightBgColor = PdfColor.fromHex('FFF5F5');

    pw.MemoryImage? logoImage;
    try {
      final byteData = await rootBundle.load('assets/images/barnock_full_logo_brown.png');
      logoImage = pw.MemoryImage(byteData.buffer.asUint8List());
    } catch (_) {
      logoImage = null;
    }

    final subtotal = quote.estimatedCost;
    final taxAmount = subtotal * taxRate;
    final grandTotal = subtotal + taxAmount;

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Top Header
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  if (logoImage != null)
                    pw.Container(
                      height: 48,
                      child: pw.Image(logoImage, fit: pw.BoxFit.contain),
                    )
                  else
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          companyName,
                          style: pw.TextStyle(
                            fontSize: 22,
                            fontWeight: pw.FontWeight.bold,
                            color: primaryColor,
                          ),
                        ),
                        pw.Text(
                          'Programming Hardware & Tailor-Made Software',
                          style: pw.TextStyle(fontSize: 9, color: secondaryColor),
                        ),
                      ],
                    ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        'CREDIT NOTE',
                        style: pw.TextStyle(
                          fontSize: 20,
                          fontWeight: pw.FontWeight.bold,
                          color: primaryColor,
                        ),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        'Credit Note #: CRN-${quote.id.substring(0, quote.id.length > 8 ? 8 : quote.id.length).toUpperCase()}',
                        style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
                      ),
                      pw.Text(
                        'Original Invoice Ref: INV-${quote.id.substring(0, quote.id.length > 8 ? 8 : quote.id.length).toUpperCase()}',
                        style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                      ),
                      pw.Text(
                        'Date: ${DateTime.now().toIso8601String().substring(0, 10)}',
                        style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                      ),
                      pw.Text(
                        'Status: REFUNDED',
                        style: pw.TextStyle(
                          fontSize: 10,
                          fontWeight: pw.FontWeight.bold,
                          color: primaryColor,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 18),
              pw.Divider(thickness: 1, color: primaryColor),
              pw.SizedBox(height: 14),

              // Refund Notice Card
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  color: lightBgColor,
                  borderRadius: pw.BorderRadius.circular(6),
                  border: pw.Border.all(color: PdfColors.red200),
                ),
                child: pw.Text(
                  'NOTICE: This credit note confirms that the transaction referenced below has been refunded. Associated hardware allocations have been restocked to inventory.',
                  style: pw.TextStyle(fontSize: 9, color: primaryColor, fontWeight: pw.FontWeight.bold),
                ),
              ),
              pw.SizedBox(height: 16),

              // Billing Info
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('CREDITED TO:', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: secondaryColor)),
                      pw.SizedBox(height: 4),
                      pw.Text(quote.customerEmail, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text('ISSUED BY:', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: secondaryColor)),
                      pw.SizedBox(height: 4),
                      pw.Text(companyName, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
                      pw.Text('Tax / VAT Reg: SZ-44910284', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 20),

              // Item scope
              pw.Text('ADJUSTED ITEMS & DELIVERABLES', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: secondaryColor)),
              pw.SizedBox(height: 6),
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  borderRadius: pw.BorderRadius.circular(6),
                  border: pw.Border.all(color: PdfColors.grey300),
                ),
                child: pw.Text(quote.projectScope, style: const pw.TextStyle(fontSize: 10, lineSpacing: 2)),
              ),
              pw.SizedBox(height: 18),

              // Refund totals
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.end,
                children: [
                  pw.Container(
                    width: 250,
                    child: pw.Column(
                      children: [
                        _buildPriceRow('Refunded Subtotal:', '-\$${subtotal.toStringAsFixed(2)}'),
                        pw.SizedBox(height: 4),
                        _buildPriceRow('Refunded VAT (${(taxRate * 100).toInt()}%):', '-\$${taxAmount.toStringAsFixed(2)}'),
                        pw.Divider(thickness: 0.8, color: PdfColors.grey400),
                        _buildPriceRow(
                          'Total Credited Amount:',
                          '-\$${grandTotal.toStringAsFixed(2)} USD',
                          isTotal: true,
                          primaryColor: primaryColor,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              pw.Spacer(),

              pw.Center(
                child: pw.Text(
                  'This document serves as an official accounting credit memorandum for your records.',
                  style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
                ),
              ),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  /// Generates a unified Account Statement PDF containing all customer invoices and credit notes
  static Future<Uint8List> generateStatementPdfBytes({
    required String customerEmail,
    required List<Quote> quotes,
    String companyName = 'Barnock Digital Solutions',
    double taxRate = defaultTaxRate,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final pdf = pw.Document();
    final primaryColor = PdfColor.fromHex('574325');
    final secondaryColor = PdfColor.fromHex('8D8D8F');

    pw.MemoryImage? logoImage;
    try {
      final byteData = await rootBundle.load('assets/images/barnock_full_logo_brown.png');
      logoImage = pw.MemoryImage(byteData.buffer.asUint8List());
    } catch (_) {
      logoImage = null;
    }

    final filteredQuotes = quotes.where((q) {
      if (startDate != null && q.createdAt.isBefore(startDate)) return false;
      if (endDate != null) {
        final endOfDay = DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59, 999);
        if (q.createdAt.isAfter(endOfDay)) return false;
      }
      return true;
    }).toList();

    final sortedQuotes = List<Quote>.from(filteredQuotes)
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    double totalBilled = 0.0;
    double totalPaid = 0.0;
    double totalRefunded = 0.0;

    final List<List<String>> tableData = [];

    for (final q in sortedQuotes) {
      final subtotal = q.estimatedCost;
      final totalWithTax = subtotal * (1 + taxRate);
      final dateStr = q.createdAt.toIso8601String().substring(0, 10);
      final refStr = 'INV-${q.id.substring(0, q.id.length > 6 ? 6 : q.id.length).toUpperCase()}';

      if (q.status == 'refunded') {
        totalBilled += totalWithTax;
        totalPaid += totalWithTax;
        totalRefunded += totalWithTax;
        tableData.add([
          dateStr,
          refStr,
          'Invoice (Billed)',
          '\$${totalWithTax.toStringAsFixed(2)}',
          '\$${totalWithTax.toStringAsFixed(2)}',
        ]);
        tableData.add([
          dateStr,
          'CRN-${q.id.substring(0, q.id.length > 6 ? 6 : q.id.length).toUpperCase()}',
          'Credit Note (Refunded)',
          '-\$${totalWithTax.toStringAsFixed(2)}',
          '-\$${totalWithTax.toStringAsFixed(2)}',
        ]);
      } else if (q.status == 'paid') {
        totalBilled += totalWithTax;
        totalPaid += totalWithTax;
        tableData.add([
          dateStr,
          refStr,
          'Invoice (Paid)',
          '\$${totalWithTax.toStringAsFixed(2)}',
          '\$${totalWithTax.toStringAsFixed(2)}',
        ]);
      } else {
        totalBilled += totalWithTax;
        tableData.add([
          dateStr,
          refStr,
          'Invoice (${q.status.toUpperCase()})',
          '\$${totalWithTax.toStringAsFixed(2)}',
          '\$0.00',
        ]);
      }
    }

    final netOutstanding = (totalBilled - totalPaid).clamp(0.0, double.infinity);

    final String periodLabel;
    if (startDate != null &&
        endDate != null &&
        startDate.year == endDate.year &&
        startDate.month == endDate.month) {
      const monthNames = [
        'January', 'February', 'March', 'April', 'May', 'June',
        'July', 'August', 'September', 'October', 'November', 'December'
      ];
      periodLabel = '${monthNames[startDate.month - 1]} ${startDate.year}';
    } else if (startDate != null || endDate != null) {
      periodLabel =
          '${startDate != null ? startDate.toIso8601String().substring(0, 10) : 'Start'} to ${endDate != null ? endDate.toIso8601String().substring(0, 10) : 'Present'}';
    } else {
      periodLabel = 'All Time';
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        build: (pw.Context context) => [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              if (logoImage != null)
                pw.Container(height: 44, child: pw.Image(logoImage, fit: pw.BoxFit.contain))
              else
                pw.Text(companyName, style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: primaryColor)),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text('STATEMENT OF ACCOUNT', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: primaryColor)),
                  pw.Text('Date: ${DateTime.now().toIso8601String().substring(0, 10)}', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                  pw.Text(
                    'Period: $periodLabel',
                    style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
                  ),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 12),
          pw.Divider(thickness: 1, color: primaryColor),
          pw.SizedBox(height: 10),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('ACCOUNT HOLDER:', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: secondaryColor)),
                  pw.Text(customerEmail, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text('MERCHANT:', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: secondaryColor)),
                  pw.Text(companyName, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                  pw.Text('orders@barnock.com', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 18),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              _buildStatBox('Total Invoiced', '\$${totalBilled.toStringAsFixed(2)}', primaryColor),
              _buildStatBox('Total Settled', '\$${totalPaid.toStringAsFixed(2)}', PdfColors.green700),
              _buildStatBox('Total Credited', '\$${totalRefunded.toStringAsFixed(2)}', PdfColor.fromHex('8B2500')),
              _buildStatBox('Net Outstanding', '\$${netOutstanding.toStringAsFixed(2)}', netOutstanding > 0 ? primaryColor : PdfColors.green700),
            ],
          ),
          pw.SizedBox(height: 20),
          pw.Text('TRANSACTIONS & ADJUSTMENTS LEDGER', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: secondaryColor)),
          pw.SizedBox(height: 6),
          pw.Table.fromTextArray(
            headers: ['Date', 'Reference', 'Type / Status', 'Amount Due', 'Settled / Credit'],
            data: tableData,
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 9),
            headerDecoration: pw.BoxDecoration(color: primaryColor),
            cellStyle: const pw.TextStyle(fontSize: 8.5),
            cellAlignment: pw.Alignment.centerLeft,
            cellAlignments: {
              3: pw.Alignment.centerRight,
              4: pw.Alignment.centerRight,
            },
            headerAlignments: {
              3: pw.Alignment.centerRight,
              4: pw.Alignment.centerRight,
            },
            border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
            headerHeight: 22,
            cellHeight: 20,
          ),
        ],
      ),
    );

    return pdf.save();
  }

  static Future<void> downloadStatement({
    required String customerEmail,
    required List<Quote> quotes,
    String companyName = 'Barnock Digital Solutions',
    double taxRate = defaultTaxRate,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final pdfBytes = await generateStatementPdfBytes(
      customerEmail: customerEmail,
      quotes: quotes,
      companyName: companyName,
      taxRate: taxRate,
      startDate: startDate,
      endDate: endDate,
    );
    await Printing.sharePdf(
      bytes: pdfBytes,
      filename: 'statement_${customerEmail.replaceAll('@', '_at_')}.pdf',
    );
  }

  static pw.Widget _buildStatBox(String title, String value, PdfColor color) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        borderRadius: pw.BorderRadius.circular(4),
        border: pw.Border.all(color: PdfColors.grey300),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(title, style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
          pw.SizedBox(height: 2),
          pw.Text(value, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  static Future<void> downloadCreditNote({
    required Quote quote,
    String companyName = 'Barnock Digital Solutions',
    double taxRate = defaultTaxRate,
  }) async {
    final pdfBytes = await generateCreditNotePdfBytes(
      quote: quote,
      companyName: companyName,
      taxRate: taxRate,
    );
    await Printing.sharePdf(
      bytes: pdfBytes,
      filename: 'credit_note_${quote.id}.pdf',
    );
  }

  static Future<void> downloadInvoice({
    required Quote quote,
    String companyName = 'Barnock Digital Solutions',
    double taxRate = defaultTaxRate,
  }) async {
    final pdfBytes = await generateInvoicePdfBytes(
      quote: quote,
      companyName: companyName,
      taxRate: taxRate,
    );
    await Printing.sharePdf(
      bytes: pdfBytes,
      filename: 'invoice_${quote.id}.pdf',
    );
  }

  static pw.Widget _buildPriceRow(String label, String value, {bool isTotal = false, PdfColor? primaryColor}) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          label,
          style: pw.TextStyle(
            fontSize: isTotal ? 11 : 10,
            fontWeight: isTotal ? pw.FontWeight.bold : pw.FontWeight.normal,
            color: isTotal ? (primaryColor ?? PdfColors.black) : PdfColors.grey800,
          ),
        ),
        pw.Text(
          value,
          style: pw.TextStyle(
            fontSize: isTotal ? 12 : 10,
            fontWeight: isTotal ? pw.FontWeight.bold : pw.FontWeight.normal,
            color: isTotal ? (primaryColor ?? PdfColors.black) : PdfColors.black,
          ),
        ),
      ],
    );
  }
}