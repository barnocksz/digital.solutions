import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import '../../../models/catalog_item.dart';
import '../../../models/quote.dart';
import '../services/admin_carousel_management_screen.dart';
import '../services/crypto_verification_service.dart';
import '../services/currency_service.dart';
import '../services/invoice_pdf_service.dart';
import '../../../services/auth_service.dart';

class AdminPortalView extends StatefulWidget {
  const AdminPortalView({super.key});

  @override
  State<AdminPortalView> createState() => _AdminPortalViewState();
}

class _AdminPortalViewState extends State<AdminPortalView> {
  int _currentTabIndex = 0;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();

    if (auth.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (!auth.isAdmin) {
      return const _AdminLoginGate();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Operations & Catalog Control Center'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => auth.signOut(),
          ),
        ],
      ),
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _currentTabIndex,
            onDestinationSelected: (idx) => setState(() => _currentTabIndex = idx),
            labelType: NavigationRailLabelType.all,
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.inventory_2),
                label: Text('Catalog'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.request_quote_outlined),
                label: Text('Quotes & Invoices'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.view_carousel_outlined),
                label: Text('Carousel Banners'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.account_balance_outlined),
                label: Text('Financials'),
              ),
            ],
          ),
          const VerticalDivider(thickness: 1, width: 1),
          Expanded(
            child: _currentTabIndex == 0
                ? const _AdminCatalogManager()
                : _currentTabIndex == 1
                    ? const _AdminQuoteAndInvoiceManager()
                    : _currentTabIndex == 2
                        ? const AdminCarouselManagementScreen()
                        : const _AdminFinancialsManager(),
          ),
        ],
      ),
    );
  }
}

class _AdminCatalogManager extends StatelessWidget {
  const _AdminCatalogManager();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showItemEditor(context),
        child: const Icon(Icons.add),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('catalog').snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final items = snapshot.data!.docs
              .map((doc) => CatalogItem.fromFirestore(doc.data() as Map<String, dynamic>, doc.id))
              .toList();

          return ListView.builder(
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return ListTile(
                title: Text(item.title),
                subtitle: Text('${item.type.name} - \$${item.basePrice.toStringAsFixed(2)}'),
                trailing: IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () => FirebaseFirestore.instance.collection('catalog').doc(item.id).delete(),
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _showItemEditor(BuildContext context) {
    final titleController = TextEditingController();
    final priceController = TextEditingController();
    final costController = TextEditingController();
    final stockController = TextEditingController();
    final descController = TextEditingController();
    final protocolsController = TextEditingController();
    final mcusController = TextEditingController();
    CatalogType selectedType = CatalogType.hardware;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          title: const Text('Add Catalog Entry'),
          content: SingleChildScrollView(
            child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: titleController, decoration: const InputDecoration(labelText: 'Title')),
              TextField(
                controller: priceController,
                decoration: const InputDecoration(labelText: 'Base Price (USD)'),
                keyboardType: TextInputType.number,
              ),
              TextField(
                controller: costController,
                decoration: const InputDecoration(
                  labelText: 'Unit Cost / COGS (USD)',
                  hintText: 'Direct manufacturing or procurement cost',
                ),
                keyboardType: TextInputType.number,
              ),
              TextField(
                controller: stockController,
                decoration: const InputDecoration(labelText: 'Stock Quantity on Hand'),
                keyboardType: TextInputType.number,
              ),
              DropdownButton<CatalogType>(
                value: selectedType,
                isExpanded: true,
                items: CatalogType.values.map((t) => DropdownMenuItem(value: t, child: Text(t.name))).toList(),
                onChanged: (val) => setModalState(() => selectedType = val!),
              ),
              TextField(controller: descController, decoration: const InputDecoration(labelText: 'Description')),
              if (selectedType == CatalogType.hardware) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: protocolsController,
                  decoration: const InputDecoration(
                    labelText: 'Protocols (comma-separated)',
                    hintText: 'e.g. SWD, JTAG, UART, SPI, I2C',
                  ),
                ),
                TextField(
                  controller: mcusController,
                  decoration: const InputDecoration(
                    labelText: 'Target MCUs (comma-separated)',
                    hintText: 'e.g. STM32, ESP32, nRF52, RP2040',
                  ),
                ),
              ],
            ],
          ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                final specs = <String, dynamic>{};
                if (protocolsController.text.trim().isNotEmpty) {
                  specs['protocols'] = protocolsController.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
                }
                if (mcusController.text.trim().isNotEmpty) {
                  specs['target_mcus'] = mcusController.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
                }
                final item = CatalogItem(
                  id: '',
                  title: titleController.text,
                  description: descController.text,
                  basePrice: double.tryParse(priceController.text) ?? 0.0,
                  costPrice: double.tryParse(costController.text) ?? 0.0,
                  stockQuantity: int.tryParse(stockController.text) ?? 0,
                  type: selectedType,
                  specifications: specs,
                );
                await FirebaseFirestore.instance.collection('catalog').add(item.toFirestore());
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Save Item'),
            )
          ],
        ),
      ),
    ).then((_) {
      titleController.dispose();
      priceController.dispose();
      costController.dispose();
      stockController.dispose();
      descController.dispose();
      protocolsController.dispose();
      mcusController.dispose();
    });
  }
}

class _AdminQuoteAndInvoiceManager extends StatefulWidget {
  const _AdminQuoteAndInvoiceManager();

  @override
  State<_AdminQuoteAndInvoiceManager> createState() => _AdminQuoteAndInvoiceManagerState();
}

class _AdminQuoteAndInvoiceManagerState extends State<_AdminQuoteAndInvoiceManager> {
  final Map<String, bool> _isVerifying = {};

  void _showTxHashEditor(BuildContext context, Quote quote) {
    final txHashController = TextEditingController(text: quote.paymentTxHash);
    String? selectedCurrencyCode = quote.paymentCurrency;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          return AlertDialog(
            title: const Text('Set Payment Transaction Hash'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: txHashController,
                  decoration: const InputDecoration(labelText: 'Transaction Hash (TxID)'),
                ),
                const SizedBox(height: 16),
                DropdownButton<String>(
                  value: selectedCurrencyCode,
                  isExpanded: true,
                  hint: const Text('Select Payment Currency'),
                  items: AppCurrency.values
                      .where((c) => c.isCrypto)
                      .map((c) => DropdownMenuItem(value: c.code, child: Text(c.code)))
                      .toList(),
                  onChanged: (val) => setDialogState(() => selectedCurrencyCode = val),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              ElevatedButton(
                onPressed: () {
                  FirebaseFirestore.instance.collection('quotes').doc(quote.id).update({
                    'paymentTxHash': txHashController.text.trim(),
                    'paymentCurrency': selectedCurrencyCode,
                    'verificationStatus': 'pending_verification',
                  });
                  Navigator.pop(ctx);
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _decrementStockForQuote(Quote quote) async {
    final itemRegex = RegExp(r'•\s*(.+?)\s*\(x(\d+)\)');
    final matches = itemRegex.allMatches(quote.projectScope);
    final firestore = FirebaseFirestore.instance;

    for (final match in matches) {
      final itemTitle = match.group(1)?.trim();
      final quantity = int.tryParse(match.group(2) ?? '1') ?? 1;

      if (itemTitle != null && itemTitle.isNotEmpty) {
        final query = await firestore
            .collection('catalog')
            .where('title', isEqualTo: itemTitle)
            .limit(1)
            .get();

        if (query.docs.isNotEmpty) {
          final doc = query.docs.first;
          final currentStock = (doc.data()['stockQuantity'] as num?)?.toInt() ?? 0;
          final updatedStock = (currentStock - quantity).clamp(0, 999999);

          await firestore.collection('catalog').doc(doc.id).update({
            'stockQuantity': updatedStock,
          });
        }
      }
    }
  }

  Future<void> _restockForQuote(Quote quote) async {
    final itemRegex = RegExp(r'•\s*(.+?)\s*\(x(\d+)\)');
    final matches = itemRegex.allMatches(quote.projectScope);
    final firestore = FirebaseFirestore.instance;

    for (final match in matches) {
      final itemTitle = match.group(1)?.trim();
      final quantity = int.tryParse(match.group(2) ?? '1') ?? 1;

      if (itemTitle != null && itemTitle.isNotEmpty) {
        final query = await firestore
            .collection('catalog')
            .where('title', isEqualTo: itemTitle)
            .limit(1)
            .get();

        if (query.docs.isNotEmpty) {
          final doc = query.docs.first;
          final currentStock = (doc.data()['stockQuantity'] as num?)?.toInt() ?? 0;
          await firestore.collection('catalog').doc(doc.id).update({
            'stockQuantity': currentStock + quantity,
          });
        }
      }
    }
  }

  Future<void> _updateQuoteStatus(BuildContext context, Quote quote, String newStatus, {String? verificationStatus}) async {
    final updateData = <String, dynamic>{
      'status': newStatus,
    };
    if (verificationStatus != null) {
      updateData['verificationStatus'] = verificationStatus;
    }
    if (newStatus == 'quoted') {
      updateData['quoteIssuedAt'] = FieldValue.serverTimestamp();
      updateData['emailStatus'] = 'pending';
    }
    if (newStatus == 'paid' && !quote.stockDecremented) {
      await _decrementStockForQuote(quote);
      updateData['stockDecremented'] = true;
      updateData['reconciledAt'] = FieldValue.serverTimestamp();
    } else if ((newStatus == 'refunded' || newStatus == 'canceled') && quote.stockDecremented) {
      await _restockForQuote(quote);
      updateData['stockDecremented'] = false;
      updateData['restockedAt'] = FieldValue.serverTimestamp();
    }

    await FirebaseFirestore.instance.collection('quotes').doc(quote.id).update(updateData);

    if (context.mounted) {
      if (newStatus == 'paid' && !quote.stockDecremented) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Payment recorded & inventory stock decremented.'), backgroundColor: Colors.green),
        );
      } else if ((newStatus == 'refunded' || newStatus == 'canceled') && quote.stockDecremented) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Order marked as ${newStatus.toUpperCase()} & inventory restocked.'), backgroundColor: Colors.orange.shade800),
        );
      }
    }
  }

  Future<void> _verifyPayment(Quote quote) async {
    if (quote.paymentTxHash == null || quote.paymentTxHash!.isEmpty || quote.paymentCurrency == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Transaction hash or currency not set.'), backgroundColor: Colors.orange),
      );
      return;
    }

    setState(() => _isVerifying[quote.id] = true);

    final currency = AppCurrency.values.firstWhere((c) => c.code == quote.paymentCurrency);
    final currencyService = context.read<CurrencyService>();
    final paymentDetails = currencyService.getPaymentDetails(currency);
    final expectedAddress = paymentDetails['account']!;

    CryptoTxVerification result;

    if (currency == AppCurrency.btc) {
      // Note: expectedBtcAmount should ideally be stored with the quote.
      // This is a placeholder calculation.
      final expectedBtcAmount = quote.estimatedCost * currencyService.getRate(AppCurrency.btc);
      result = await CryptoVerificationService.verifyBtcTransaction(
        txId: quote.paymentTxHash!,
        expectedAddress: expectedAddress,
        expectedBtcAmount: expectedBtcAmount,
      );
    } else if (currency == AppCurrency.eth) {
      // Note: expectedWeiAmount should ideally be stored with the quote.
      final ethVal = quote.estimatedCost * currencyService.getRate(AppCurrency.eth);
      final parts = ethVal.toStringAsFixed(18).split('.');
      final whole = BigInt.parse(parts[0]) * BigInt.from(10).pow(18);
      final frac = BigInt.parse(parts[1].padRight(18, '0').substring(0, 18));
      final expectedWeiAmount = whole + frac;

      result = await CryptoVerificationService.verifyEthTransaction(
        txHash: quote.paymentTxHash!,
        expectedAddress: expectedAddress,
        expectedWeiAmount: expectedWeiAmount,
        etherscanApiKey: 'YOUR_ETHERSCAN_API_KEY', // Replace with your key
      );
    } else {
      result = CryptoTxVerification(isConfirmed: false, confirmations: 0, isValidRecipient: false, isAmountSufficient: false, errorMessage: 'Unsupported currency for verification.');
    }

    String finalStatus = quote.status;
    String verificationMessage;

    if (result.isFullyVerified) {
      finalStatus = 'paid';
      verificationMessage = 'Payment Confirmed! ${result.confirmations} confirmations.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(verificationMessage), backgroundColor: Colors.green),
      );
    } else {
      verificationMessage = result.errorMessage ?? 'Verification failed. Check recipient, amount, and confirmations.';
       ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(verificationMessage), backgroundColor: Colors.red),
      );
    }

    await _updateQuoteStatus(context, quote, finalStatus, verificationStatus: verificationMessage);

    if (mounted) {
      setState(() => _isVerifying.remove(quote.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('quotes').orderBy('createdAt', descending: true).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final quotes = snapshot.data!.docs
            .map((d) => Quote.fromFirestore(d.data() as Map<String, dynamic>, d.id))
            .toList();

        return ListView.builder(
          itemCount: quotes.length,
          itemBuilder: (context, idx) {
            final quote = quotes[idx];
            final isLoading = _isVerifying[quote.id] ?? false;

            return ExpansionTile(
              title: Text('Customer: ${quote.customerEmail}'),
              subtitle: Text('Status: ${quote.status.toUpperCase()}'),
              trailing: PopupMenuButton<String>(
                  onSelected: (newStatus) => _updateQuoteStatus(context, quote, newStatus),
                  itemBuilder: (context) => [
                        const PopupMenuItem(value: 'pending', child: Text('Mark as Pending')),
                        const PopupMenuItem(value: 'quoted', child: Text('Issue Quote')),
                        const PopupMenuItem(value: 'invoiced', child: Text('Convert to Invoice')),
                        const PopupMenuItem(value: 'paid', child: Text('Mark Paid')),
                        const PopupMenuItem(value: 'refunded', child: Text('Refund Order (Restock)')),
                        const PopupMenuItem(value: 'canceled', child: Text('Cancel Order (Restock)')),
                      ]),
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Scope: ${quote.projectScope}'),
                      const Divider(height: 24),
                      Text('TX Hash: ${quote.paymentTxHash ?? 'Not set'}'),
                      Text('Payment Currency: ${quote.paymentCurrency ?? 'Not set'}'),
                      const SizedBox(height: 8),
                      if (quote.verificationStatus != null)
                        Chip(
                          label: Text(quote.verificationStatus!),
                          backgroundColor: quote.status == 'paid' ? Colors.green.shade100 : Colors.orange.shade100,
                        ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () => quote.status == 'refunded'
                                ? InvoicePdfService.downloadCreditNote(quote: quote)
                                : InvoicePdfService.downloadInvoice(quote: quote),
                            icon: Icon(
                              quote.status == 'refunded' ? Icons.assignment_return_outlined : Icons.picture_as_pdf,
                              size: 18,
                            ),
                            label: Text(quote.status == 'refunded' ? 'Credit Note' : 'Download PDF'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: quote.status == 'refunded' ? Colors.red.shade800 : const Color(0xFF574325),
                              side: BorderSide(color: quote.status == 'refunded' ? Colors.red.shade800 : const Color(0xFF574325)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: () => _showTxHashEditor(context, quote),
                            child: const Text('Set TX Hash'),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            onPressed: isLoading ? null : () => _verifyPayment(quote),
                            icon: isLoading
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.verified_user_outlined, size: 18),
                            label: const Text('Verify Payment'),
                          ),
                        ],
                      ),
                    ],
                  ),
                )
              ],
            );
          },
        );
      },
    );
  }
}

class _AdminFinancialsManager extends StatefulWidget {
  const _AdminFinancialsManager();

  @override
  State<_AdminFinancialsManager> createState() => _AdminFinancialsManagerState();
}

class _AdminFinancialsManagerState extends State<_AdminFinancialsManager> {
  DateTimeRange? _dateRange;
  final TextEditingController _customerController = TextEditingController();
  String _customerFilter = '';
  bool _isQuarterlyView = false;

  Future<void> _showAdminStatementMonthDialog(
    BuildContext context,
    String customerEmail,
    List<Quote> quotes,
  ) async {
    final now = DateTime.now();
    int selectedMonth = now.month;
    int selectedYear = now.year;
    bool allTime = false;

    const monthNames = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];

    final quoteYears = quotes.map((q) => q.createdAt.year).toSet().toList()..sort();
    final startYear = quoteYears.isNotEmpty ? quoteYears.first : now.year - 2;
    final endYear = now.year + 1;
    final availableYears = List<int>.generate(endYear - startYear + 1, (i) => startYear + i).reversed.toList();

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) {
          return AlertDialog(
            title: Text('Statement Period: $customerEmail'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('All Time (All Transactions)'),
                  value: allTime,
                  onChanged: (val) => setDialogState(() => allTime = val ?? false),
                ),
                if (!allTime) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: DropdownButtonFormField<int>(
                          value: selectedMonth,
                          decoration: const InputDecoration(labelText: 'Month', border: OutlineInputBorder()),
                          items: List.generate(12, (index) {
                            return DropdownMenuItem<int>(
                              value: index + 1,
                              child: Text(monthNames[index]),
                            );
                          }),
                          onChanged: (val) {
                            if (val != null) setDialogState(() => selectedMonth = val);
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: DropdownButtonFormField<int>(
                          value: selectedYear,
                          decoration: const InputDecoration(labelText: 'Year', border: OutlineInputBorder()),
                          items: availableYears.map((year) {
                            return DropdownMenuItem<int>(value: year, child: Text(year.toString()));
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) setDialogState(() => selectedYear = val);
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              ElevatedButton.icon(
                icon: const Icon(Icons.picture_as_pdf, size: 16),
                label: const Text('Generate Statement'),
                onPressed: () async {
                  Navigator.pop(ctx);
                  final start = allTime ? null : DateTime(selectedYear, selectedMonth, 1);
                  final end = allTime ? null : DateTime(selectedYear, selectedMonth + 1, 0, 23, 59, 59, 999);
                  await InvoicePdfService.downloadStatement(
                    customerEmail: customerEmail,
                    quotes: quotes,
                    startDate: start,
                    endDate: end,
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _customerController.dispose();
    super.dispose();
  }

  String _escapeCsv(dynamic val) {
    final str = (val ?? '').toString();
    return '"${str.replaceAll('"', '""')}"';
  }

  void _exportFinancialCsv(
    BuildContext context,
    List<Quote> quotes,
    List<CatalogItem> catalog,
    double totalRevenue,
    double estimatedCogs,
    double grossProfit,
    double grossMarginPercent,
    double inventoryAssetValue,
    double pipelineValue,
  ) {
    final dateRangeStr = _dateRange == null
        ? 'All Time'
        : '${_dateRange!.start.toIso8601String().substring(0, 10)} to ${_dateRange!.end.toIso8601String().substring(0, 10)}';
    final customerStr = _customerFilter.isEmpty ? 'All Customers' : _customerFilter;
    final buf = StringBuffer();

    // 1. Executive Summary
    buf.writeln('"BARNOCK DIGITAL SOLUTIONS - EXECUTIVE FINANCIAL & ACCOUNTING REPORT"');
    buf.writeln('"Generated At",${_escapeCsv(DateTime.now().toIso8601String())}');
    buf.writeln('"Date Range Filter",${_escapeCsv(dateRangeStr)}');
    buf.writeln('"Customer Filter",${_escapeCsv(customerStr)}');
    buf.writeln('"Settled Revenue (USD)",${totalRevenue.toStringAsFixed(2)}');
    buf.writeln('"Cost of Goods Sold - COGS (USD)",${estimatedCogs.toStringAsFixed(2)}');
    buf.writeln('"Realized Gross Profit (USD)",${grossProfit.toStringAsFixed(2)}');
    buf.writeln('"Gross Margin (%)","${grossMarginPercent.toStringAsFixed(1)}%"');
    buf.writeln('"Inventory Asset Valuation (USD)",${inventoryAssetValue.toStringAsFixed(2)}');
    buf.writeln('"Unsettled Pipeline Value (USD)",${pipelineValue.toStringAsFixed(2)}');
    buf.writeln();

    // 2. Transactions Ledger
    buf.writeln('"RECONCILED TRANSACTIONS & QUOTES LEDGER"');
    buf.writeln('"Quote ID","Customer Email","Created Date","Status","Currency","Payment TxID","Stock Reconciled","Revenue (USD)","Scope Details"');
    for (final q in quotes) {
      buf.writeln([
        _escapeCsv(q.id),
        _escapeCsv(q.customerEmail),
        _escapeCsv(q.createdAt.toIso8601String().substring(0, 10)),
        _escapeCsv(q.status.toUpperCase()),
        _escapeCsv(q.paymentCurrency ?? 'USD'),
        _escapeCsv(q.paymentTxHash ?? 'N/A'),
        _escapeCsv(q.stockDecremented ? 'YES' : 'NO'),
        q.estimatedCost.toStringAsFixed(2),
        _escapeCsv(q.projectScope.replaceAll('\n', ' | ')),
      ].join(','));
    }
    buf.writeln();

    // 3. Hardware Inventory Stock Ledger
    buf.writeln('"HARDWARE INVENTORY & ASSET VALUATION LEDGER"');
    buf.writeln('"Item ID","Title","Category","Base Price (USD)","Unit Cost (USD)","Unit Margin (USD)","Margin (%)","Stock On Hand","Total Asset Value (USD)","Status"');
    for (final item in catalog) {
      final unitMargin = item.basePrice - item.costPrice;
      final marginPct = item.basePrice > 0 ? (unitMargin / item.basePrice) * 100 : 0.0;
      final assetVal = item.costPrice * item.stockQuantity;
      final status = item.stockQuantity <= 5 ? 'LOW STOCK' : 'IN STOCK';
      buf.writeln([
        _escapeCsv(item.id),
        _escapeCsv(item.title),
        _escapeCsv(item.type.name),
        item.basePrice.toStringAsFixed(2),
        item.costPrice.toStringAsFixed(2),
        unitMargin.toStringAsFixed(2),
        '"${marginPct.toStringAsFixed(1)}%"',
        item.stockQuantity.toString(),
        assetVal.toStringAsFixed(2),
        _escapeCsv(status),
      ].join(','));
    }

    final csvData = buf.toString();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Export Accounting & Profit Report'),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('The report has been generated with transaction ledger, COGS, and inventory asset valuation.'),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  csvData.split('\n').take(8).join('\n'),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
          OutlinedButton.icon(
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Copy CSV'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: csvData));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('CSV copied to clipboard.')));
            },
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.download, size: 16),
            label: const Text('Download CSV File'),
            onPressed: () async {
              final filename = 'barnock_financials_${DateTime.now().toIso8601String().substring(0, 10)}.csv';
              await Printing.sharePdf(bytes: Uint8List.fromList(utf8.encode(csvData)), filename: filename);
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('quotes').snapshots(),
        builder: (context, quoteSnap) {
          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('catalog').snapshots(),
            builder: (context, catSnap) {
              if (!quoteSnap.hasData || !catSnap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final quotes = quoteSnap.data!.docs
                  .map((d) => Quote.fromFirestore(d.data() as Map<String, dynamic>, d.id))
                  .toList();

              final catalog = catSnap.data!.docs
                  .map((d) => CatalogItem.fromFirestore(d.data() as Map<String, dynamic>, d.id))
                  .toList();

              // Filter quotes by date range and customer email
              final filteredQuotes = quotes.where((q) {
                if (_customerFilter.isNotEmpty &&
                    !q.customerEmail.toLowerCase().contains(_customerFilter.toLowerCase())) {
                  return false;
                }
                if (_dateRange != null) {
                  final start = DateTime(_dateRange!.start.year, _dateRange!.start.month, _dateRange!.start.day);
                  final end = DateTime(_dateRange!.end.year, _dateRange!.end.month, _dateRange!.end.day, 23, 59, 59, 999);
                  if (q.createdAt.isBefore(start) || q.createdAt.isAfter(end)) return false;
                }
                return true;
              }).toList();

              final paidQuotes = filteredQuotes.where((q) => q.status == 'paid').toList();
              final pendingQuotes = quotes.where((q) => q.status != 'paid').toList();

              final totalRevenue = paidQuotes.fold(0.0, (sum, q) => sum + q.estimatedCost);
              final pipelineValue = pendingQuotes.fold(0.0, (sum, q) => sum + q.estimatedCost);

              // Average Gross Margin calculation from catalog offerings
              double totalCatalogRevenue = 0.0;
              double totalCatalogCost = 0.0;
              for (final item in catalog) {
                totalCatalogRevenue += item.basePrice;
                totalCatalogCost += item.costPrice;
              }
              final estimatedMarginRate = totalCatalogRevenue > 0
                  ? ((totalCatalogRevenue - totalCatalogCost) / totalCatalogRevenue).clamp(0.0, 1.0)
                  : 0.65; // fallback standard 65% gross margin

              final estimatedCogs = totalRevenue * (1.0 - estimatedMarginRate);
              final grossProfit = totalRevenue - estimatedCogs;
              final grossMarginPercent = totalRevenue > 0 ? (grossProfit / totalRevenue) * 100 : 0.0;

              // Inventory Valuation & Low Stock
              final inventoryAssetValue = catalog.fold(0.0, (sum, i) => sum + (i.costPrice * i.stockQuantity));
              final lowStockItems = catalog.where((i) => i.type == CatalogType.hardware && i.stockQuantity <= 5).toList();

              return SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            'Executive Financial Standing & Reconciliation',
                            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF574325),
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () => _exportFinancialCsv(
                            context,
                            filteredQuotes,
                            catalog,
                            totalRevenue,
                            estimatedCogs,
                            grossProfit,
                            grossMarginPercent,
                            inventoryAssetValue,
                            pipelineValue,
                          ),
                          icon: const Icon(Icons.table_chart_outlined, size: 18),
                          label: const Text('Export Ledger / CSV'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text('Live reconciliation of settled payments, realized gross profit, and inventory assets.',
                        style: TextStyle(color: Colors.black54)),
                    const SizedBox(height: 18),

                    // Filter Toolbar
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          SizedBox(
                            width: 260,
                            height: 40,
                            child: TextField(
                              controller: _customerController,
                              decoration: InputDecoration(
                                hintText: 'Filter by customer email...',
                                hintStyle: const TextStyle(fontSize: 12),
                                prefixIcon: const Icon(Icons.search, size: 18),
                                suffixIcon: _customerFilter.isNotEmpty
                                    ? IconButton(
                                        icon: const Icon(Icons.clear, size: 16),
                                        onPressed: () {
                                          _customerController.clear();
                                          setState(() => _customerFilter = '');
                                        },
                                      )
                                    : null,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                              ),
                              onChanged: (val) => setState(() => _customerFilter = val.trim()),
                            ),
                          ),
                          OutlinedButton.icon(
                            icon: const Icon(Icons.date_range, size: 18),
                            label: Text(
                              _dateRange == null
                                  ? 'All Dates'
                                  : '${_dateRange!.start.toIso8601String().substring(0, 10)} - ${_dateRange!.end.toIso8601String().substring(0, 10)}',
                              style: const TextStyle(fontSize: 12),
                            ),
                            onPressed: () async {
                              final picked = await showDateRangePicker(
                                context: context,
                                firstDate: DateTime(2020),
                                lastDate: DateTime(2035),
                                initialDateRange: _dateRange,
                              );
                              if (picked != null) setState(() => _dateRange = picked);
                            },
                          ),
                          if (_dateRange != null || _customerFilter.isNotEmpty)
                            TextButton.icon(
                              icon: const Icon(Icons.filter_alt_off, size: 16),
                              label: const Text('Reset Filters'),
                              onPressed: () {
                                _customerController.clear();
                                setState(() {
                                  _customerFilter = '';
                                  _dateRange = null;
                                });
                              },
                            ),
                          if (_customerFilter.isNotEmpty && filteredQuotes.isNotEmpty)
                            OutlinedButton.icon(
                              icon: const Icon(Icons.receipt_long, size: 16),
                              label: Text('Statement for "$_customerFilter"'),
                              style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF574325)),
                              onPressed: () => _showAdminStatementMonthDialog(
                                context,
                                _customerFilter,
                                filteredQuotes,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Key Metrics Cards
                    Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children: [
                        _buildKpiCard('Settled Revenue', '\$${totalRevenue.toStringAsFixed(2)}',
                            '${paidQuotes.length} reconciled orders', Colors.green.shade800),
                        _buildKpiCard('Realized COGS', '\$${estimatedCogs.toStringAsFixed(2)}',
                            'Cost of goods sold', Colors.blueGrey.shade800),
                        _buildKpiCard('Gross Profit', '\$${grossProfit.toStringAsFixed(2)}',
                            'Margin: ${grossMarginPercent.toStringAsFixed(1)}%', const Color(0xFF574325)),
                        _buildKpiCard('Inventory Asset Value', '\$${inventoryAssetValue.toStringAsFixed(2)}',
                            '${catalog.length} catalog items', Colors.indigo.shade800),
                        _buildKpiCard('Pipeline Value', '\$${pipelineValue.toStringAsFixed(2)}',
                            '${pendingQuotes.length} quotes pending', Colors.orange.shade800),
                      ],
                    ),
                    const SizedBox(height: 32),

                    // Profit Trends Bar Chart (Monthly / Quarterly)
                    _buildTrendsChart(filteredQuotes, estimatedMarginRate),
                    const SizedBox(height: 32),

                    // Inventory Stock Alerts Table
                    Text('Hardware Inventory & Reorder Monitoring',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    Card(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      child: ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: catalog.where((i) => i.type == CatalogType.hardware).length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, idx) {
                          final item = catalog.where((i) => i.type == CatalogType.hardware).toList()[idx];
                          final isLow = item.stockQuantity <= 5;
                          return ListTile(
                            title: Text(item.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text('Unit Price: \$${item.basePrice.toStringAsFixed(2)} | Cost: \$${item.costPrice.toStringAsFixed(2)}'),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Chip(
                                  label: Text('${item.stockQuantity} in stock',
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: isLow ? Colors.red.shade800 : Colors.green.shade800)),
                                  backgroundColor: isLow ? Colors.red.shade50 : Colors.green.shade50,
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    if (lowStockItems.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.warning_amber_rounded, color: Colors.red.shade700),
                            const SizedBox(width: 8),
                            Text(
                              'Low Stock Alert: ${lowStockItems.length} hardware product(s) have 5 or fewer units remaining.',
                              style: TextStyle(color: Colors.red.shade900, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildTrendsChart(List<Quote> quotes, double marginRate) {
    final referenceDate = _dateRange?.end ?? DateTime.now();
    const monthNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

    final List<Map<String, dynamic>> periodData = [];
    double maxVal = 0.0;

    if (_isQuarterlyView) {
      final currentQuarter = ((referenceDate.month - 1) ~/ 3) + 1;
      final baseQuarterStartMonth = (currentQuarter - 1) * 3 + 1;

      for (int i = 5; i >= 0; i--) {
        final qStart = DateTime(referenceDate.year, baseQuarterStartMonth - (i * 3), 1);
        final qEnd = DateTime(qStart.year, qStart.month + 3, 1);
        final qNum = ((qStart.month - 1) ~/ 3) + 1;

        final qPaidQuotes = quotes.where((q) {
          return q.status == 'paid' &&
              q.createdAt.isAfter(qStart.subtract(const Duration(milliseconds: 1))) &&
              q.createdAt.isBefore(qEnd);
        }).toList();

        final revenue = qPaidQuotes.fold(0.0, (sum, q) => sum + q.estimatedCost);
        final grossProfit = revenue * marginRate;
        maxVal = math.max(maxVal, math.max(revenue, grossProfit));

        final label = "Q$qNum '${qStart.year.toString().substring(2)}";
        periodData.add({
          'label': label,
          'revenue': revenue,
          'grossProfit': grossProfit,
        });
      }
    } else {
      for (int i = 5; i >= 0; i--) {
        final targetYear = referenceDate.year;
        final targetMonth = referenceDate.month - i;
        final monthStart = DateTime(targetYear, targetMonth, 1);
        final monthEnd = DateTime(targetYear, targetMonth + 1, 1);

        final monthPaidQuotes = quotes.where((q) {
          return q.status == 'paid' &&
              q.createdAt.isAfter(monthStart.subtract(const Duration(milliseconds: 1))) &&
              q.createdAt.isBefore(monthEnd);
        }).toList();

        final revenue = monthPaidQuotes.fold(0.0, (sum, q) => sum + q.estimatedCost);
        final grossProfit = revenue * marginRate;

        maxVal = math.max(maxVal, math.max(revenue, grossProfit));

        final label = "${monthNames[monthStart.month - 1]} '${monthStart.year.toString().substring(2)}";
        periodData.add({
          'label': label,
          'revenue': revenue,
          'grossProfit': grossProfit,
        });
      }
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 16,
            runSpacing: 12,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _isQuarterlyView
                        ? 'Quarterly Financial Performance & Profit Trends'
                        : 'Monthly Financial Performance & Profit Trends',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _isQuarterlyView
                        ? 'Comparative billed revenue versus realized gross profit over trailing 6 quarters'
                        : 'Comparative billed revenue versus realized gross profit over trailing 6 months',
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('Monthly', style: TextStyle(fontSize: 12))),
                      ButtonSegment(value: true, label: Text('Quarterly', style: TextStyle(fontSize: 12))),
                    ],
                    selected: {_isQuarterlyView},
                    onSelectionChanged: (set) => setState(() => _isQuarterlyView = set.first),
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                  const SizedBox(width: 16),
                  _buildLegendItem('Revenue', const Color(0xFF574325)),
                  const SizedBox(width: 16),
                  _buildLegendItem('Gross Profit', Colors.green.shade700),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (maxVal == 0.0)
            Container(
              height: 180,
              alignment: Alignment.center,
              child: const Text('No settled revenue recorded in this period.', style: TextStyle(color: Colors.black45)),
            )
          else
            SizedBox(
              height: 200,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: periodData.map((data) {
                  final double rev = data['revenue'] as double;
                  final double profit = data['grossProfit'] as double;
                  final String label = data['label'] as String;

                  final double revHeight = maxVal > 0 ? (rev / maxVal) * 140.0 : 0.0;
                  final double profitHeight = maxVal > 0 ? (profit / maxVal) * 140.0 : 0.0;

                  return Expanded(
                    child: Tooltip(
                      message: '$label\nRevenue: \$${rev.toStringAsFixed(2)}\nGross Profit: \$${profit.toStringAsFixed(2)}',
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              // Revenue Bar
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 400),
                                width: 14,
                                height: revHeight.clamp(4.0, 140.0),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF574325),
                                  borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                                ),
                              ),
                              const SizedBox(width: 4),
                              // Gross Profit Bar
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 400),
                                width: 14,
                                height: profitHeight.clamp(4.0, 140.0),
                                decoration: BoxDecoration(
                                  color: Colors.green.shade700,
                                  borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          Text(
                            '\$${profit.toStringAsFixed(0)}',
                            style: TextStyle(fontSize: 10, color: Colors.green.shade800, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black87)),
      ],
    );
  }

  Widget _buildKpiCard(String title, String value, String subtitle, Color color) {
    return Container(
      width: 220,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 6, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 12, color: Colors.black54, fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(fontSize: 11, color: Colors.black45)),
        ],
      ),
    );
  }
}

class _AdminLoginGate extends StatefulWidget {
  const _AdminLoginGate();

  @override
  State<_AdminLoginGate> createState() => _AdminLoginGateState();
}

class _AdminLoginGateState extends State<_AdminLoginGate> {
  late final TextEditingController _emailController;
  late final TextEditingController _passController;
  String? _errorMessage;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController();
    _passController = TextEditingController();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passController.dispose();
    super.dispose();
  }

  Future<void> _handleSignIn() async {
    final email = _emailController.text.trim();
    final password = _passController.text.trim();

    if (email.isEmpty) {
      setState(() => _errorMessage = 'Please enter your admin email address.');
      return;
    }

    final emailRegex = RegExp(r'^[^@]+@[^@]+\.[^@]+');
    if (!emailRegex.hasMatch(email)) {
      setState(() => _errorMessage = 'Please enter a valid email address (e.g. admin@barnock.com).');
      return;
    }

    if (password.isEmpty) {
      setState(() => _errorMessage = 'Please enter your password.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await context.read<AuthService>().signIn(email, password);
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = switch (e.code) {
            'invalid-email' => 'The email address is badly formatted.',
            'user-not-found' => 'No account found with this email.',
            'wrong-password' => 'Incorrect password.',
            'invalid-credential' => 'Invalid email or password.',
            _ => e.message ?? 'Authentication failed. Please check your credentials.',
          };
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = 'An unexpected error occurred. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Admin Console Sign-in', style: Theme.of(context).textTheme.headlineSmall),
              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, size: 20, color: Colors.red.shade700),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(color: Colors.red.shade800, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Admin Email',
                  hintText: 'e.g. barnocksz@gmail.com',
                ),
                onSubmitted: (_) => _handleSignIn(),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passController,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Password'),
                onSubmitted: (_) => _handleSignIn(),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _handleSignIn,
                  child: _isLoading
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Authenticate'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}