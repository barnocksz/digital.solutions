import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../services/cart_service.dart';
import '../services/currency_service.dart';

class CartDrawer extends StatefulWidget {
  final ValueChanged<String>? onProceedToQuote;

  const CartDrawer({super.key, this.onProceedToQuote});

  @override
  State<CartDrawer> createState() => _CartDrawerState();
}

class _CartDrawerState extends State<CartDrawer> {
  late final TextEditingController _promoController;
  String? _promoError;
  bool _isValidatingPromo = false;

  @override
  void initState() {
    super.initState();
    _promoController = TextEditingController();
  }

  @override
  void dispose() {
    _promoController.dispose();
    super.dispose();
  }

  Future<void> _confirmDeleteItem(
    BuildContext context,
    CartService cart,
    String itemId,
    String itemTitle,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Item'),
        content: Text('Are you sure you want to remove "$itemTitle" from your cart?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final removedItem = cart.removeItem(itemId);
      if (removedItem != null) {
        final messenger = ScaffoldMessenger.of(context);
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text('Removed "$itemTitle" from cart'),
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'Undo',
              textColor: const Color(0xFFD4AF37),
              onPressed: () => cart.restoreItem(removedItem),
            ),
          ),
        );
      }
    }
  }

  void _showPaymentSelectionModal(
    BuildContext context,
    CartService cart,
    CurrencyService currencyService,
    List cartItems,
  ) {
    var selectedPaymentCurrency = currencyService.currentCurrency;
    bool isCopied = false;
    final Map<AppCurrency, String> assignedAddresses = {};
    final Map<AppCurrency, int> assignedIndices = {};
    bool isLoadingAddress = false;
    String? addressError;
    bool isInitialized = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          Future<void> fetchAddressIfNeeded(AppCurrency currency) async {
            if (!currency.isCrypto || assignedAddresses.containsKey(currency)) return;

            setDialogState(() {
              isLoadingAddress = true;
              addressError = null;
            });

            try {
              final callable = FirebaseFunctions.instance.httpsCallable('assignDepositAddress');
              final response = await callable.call<Map<String, dynamic>>({
                'currency': currency.code,
              });

              final data = Map<String, dynamic>.from(response.data);
              final addr = data['depositAddress'] as String?;
              final idx = (data['addressIndex'] as num?)?.toInt();

              if (ctx.mounted) {
                setDialogState(() {
                  if (addr != null && addr.isNotEmpty) {
                    assignedAddresses[currency] = addr;
                    if (idx != null) assignedIndices[currency] = idx;
                  }
                  isLoadingAddress = false;
                });
              }
            } catch (e) {
              if (ctx.mounted) {
                setDialogState(() {
                  isLoadingAddress = false;
                  addressError = 'Failed to generate unique deposit address: $e';
                });
              }
            }
          }

          if (!isInitialized) {
            isInitialized = true;
            if (selectedPaymentCurrency.isCrypto) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                fetchAddressIfNeeded(selectedPaymentCurrency);
              });
            }
          }

          final payableStr = currencyService.format(cart.total, selectedPaymentCurrency);
          final details = currencyService.getPaymentDetails(selectedPaymentCurrency);
          final fallbackAddress = details['account']!;
          final address = (selectedPaymentCurrency.isCrypto && assignedAddresses.containsKey(selectedPaymentCurrency))
              ? assignedAddresses[selectedPaymentCurrency]!
              : fallbackAddress;
          final assignedIndex = assignedIndices[selectedPaymentCurrency];

          String qrData = address;
          if (selectedPaymentCurrency == AppCurrency.btc) {
            final btcAmount = (cart.total * currencyService.getRate(AppCurrency.btc)).toStringAsFixed(AppCurrency.btc.decimals);
            qrData = 'bitcoin:$address?amount=$btcAmount&label=Barnock';
          } else if (selectedPaymentCurrency == AppCurrency.eth) {
            final ethVal = cart.total * currencyService.getRate(AppCurrency.eth);
            final parts = ethVal.toStringAsFixed(18).split('.');
            final whole = BigInt.parse(parts[0]) * BigInt.from(10).pow(18);
            final frac = BigInt.parse(parts[1].padRight(18, '0').substring(0, 18));
            final wei = whole + frac;
            qrData = 'ethereum:$address?value=${wei.toString()}';
          }

          return AlertDialog(
            title: const Text('Checkout & Payment Details'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Choose Settlement Currency / Crypto:',
                      style: TextStyle(fontSize: 13, color: Colors.black54)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    children: AppCurrency.values.map((c) {
                      return ChoiceChip(
                        label: Text('${c.code} (${c.symbol})'),
                        selected: selectedPaymentCurrency == c,
                        onSelected: (_) =>
                            setDialogState(() {
                              selectedPaymentCurrency = c;
                              isCopied = false;
                              if (c.isCrypto) {
                                fetchAddressIfNeeded(c);
                              }
                            }),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF574325).withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Total Payable: $payableStr',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: Color(0xFF574325))),
                        const SizedBox(height: 6),
                        Text(details['method']!,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 13)),
                        const SizedBox(height: 4),
                        if (isLoadingAddress)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8.0),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'Generating unique BIP-44 deposit address...',
                                  style: TextStyle(fontSize: 12, color: Colors.black54),
                                ),
                              ],
                            ),
                          )
                        else
                        Row(
                          children: [
                            Expanded(
                              child: SelectableText(
                                address,
                                style: const TextStyle(fontSize: 12, color: Colors.black87),
                              ),
                            ),
                            if (selectedPaymentCurrency.isCrypto) ...[
                              const SizedBox(width: 8),
                              IconButton(
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                tooltip: isCopied ? 'Copied!' : 'Copy address',
                                icon: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 200),
                                  child: Icon(
                                    isCopied ? Icons.check_circle : Icons.copy_rounded,
                                    key: ValueKey<bool>(isCopied),
                                    size: 18,
                                    color: isCopied ? Colors.green.shade600 : const Color(0xFF574325),
                                  ),
                                ),
                                onPressed: () async {
                                  await Clipboard.setData(ClipboardData(text: address));
                                  setDialogState(() => isCopied = true);
                                  Future.delayed(const Duration(seconds: 2), () {
                                    if (ctx.mounted) {
                                      setDialogState(() => isCopied = false);
                                    }
                                  });
                                },
                              ),
                            ],
                          ],
                        ),
                        if (assignedIndex != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            'HD Derivation Index #$assignedIndex (BIP-44)',
                            style: const TextStyle(fontSize: 10, color: Colors.black45),
                          ),
                        ],
                        if (isCopied) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Address copied to clipboard!',
                            style: TextStyle(color: Colors.green.shade700, fontSize: 11, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (selectedPaymentCurrency.isCrypto) ...[
                    const SizedBox(height: 14),
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.grey.shade300),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: isLoadingAddress
                            ? const SizedBox(
                                width: 140,
                                height: 140,
                                child: Center(child: CircularProgressIndicator()),
                              )
                            : QrImageView(
                          data: qrData,
                          version: QrVersions.auto,
                          size: 140.0,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    if (addressError != null) ...[
                      Text(
                        addressError!,
                        style: TextStyle(color: Colors.red.shade700, fontSize: 11),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 4),
                    ],
                    Center(
                      child: Text(
                        selectedPaymentCurrency == AppCurrency.btc
                            ? 'Scan with Bitcoin wallet (Amount & address prefilled via BIP-21)'
                            : selectedPaymentCurrency == AppCurrency.eth
                                ? 'Scan with Ethereum wallet (Amount in Wei prefilled via EIP-681)'
                                : 'Scan QR code with your ${selectedPaymentCurrency.code} wallet',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 11, color: Colors.black54),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Back')),
              ElevatedButton(
                onPressed: isLoadingAddress ? null : () {
                  Navigator.pop(ctx);
                  Navigator.of(context).pop();
                  final summary = cartItems.map((i) => '• ${i.item.title} (x${i.quantity}) - ${currencyService.format(i.totalPrice, selectedPaymentCurrency)}').join('\n');
                  widget.onProceedToQuote?.call(
                    'Cart Items:\n$summary\nSettlement Currency: ${selectedPaymentCurrency.code}\nTotal: $payableStr\nPayment Method: ${details['method']}\nDeposit Address: $address${assignedIndex != null ? '\nAddress Index: #$assignedIndex' : ''}',
                  );
                },
                child: const Text('Confirm Payment & Submit Quote'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    CartService? cart;
    try {
      cart = context.watch<CartService>();
    } catch (_) {
      cart = null;
    }
    final currencyService = context.watch<CurrencyService>();
    final totalCount = cart?.totalCount ?? 0;
    final cartItems = cart?.items ?? [];
    final isCartEmpty = cart?.isEmpty ?? true;
    final subtotal = cart?.subtotal ?? 0.0;
    final discountAmount = cart?.discountAmount ?? 0.0;
    final finalTotal = cart?.total ?? subtotal;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final drawerWidth = screenWidth < 500 ? screenWidth * 0.90 : 420.0;

    return Drawer(
      width: drawerWidth,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      child: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 16),
              child: Row(
                children: [
                  const Icon(Icons.shopping_bag_outlined, color: Color(0xFF574325)),
                  const SizedBox(width: 10),
                  Text(
                    'Shopping Cart ($totalCount)',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Close Cart',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // Items List / Empty State
            Expanded(
              child: isCartEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.remove_shopping_cart_outlined,
                                size: 64, color: Colors.grey.shade400),
                            const SizedBox(height: 16),
                            const Text(
                              'Your cart is empty',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Browse our catalog to add programming hardware products or tailor-made software services.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.black54, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: cartItems.length,
                      separatorBuilder: (_, __) => const Divider(height: 24),
                      itemBuilder: (context, index) {
                        final cartItem = cartItems[index];
                        final item = cartItem.item;

                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 60,
                              height: 60,
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.grey.shade200),
                              ),
                              child: const Icon(Icons.precision_manufacturing,
                                  color: Color(0xFF574325), size: 28),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          item.title,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.bold, fontSize: 14),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      IconButton(
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                        icon: Icon(Icons.delete_outline,
                                            size: 18, color: Colors.grey.shade500),
                                        tooltip: 'Remove item',
                                        onPressed: cart == null
                                            ? null
                                            : () => _confirmDeleteItem(
                                                context, cart!, item.id, item.title),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${currencyService.format(item.basePrice)} each',
                                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                                  ),
                                  const SizedBox(height: 10),
                                  // Quantity Selector
                                  Row(
                                    children: [
                                      Container(
                                        decoration: BoxDecoration(
                                          border: Border.all(color: Colors.grey.shade300),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            InkWell(
                                              onTap: () {
                                                if (cart == null) return;
                                                if (cartItem.quantity > 1) {
                                                  cart.decrementQuantity(item.id);
                                                } else {
                                                  _confirmDeleteItem(
                                                      context, cart, item.id, item.title);
                                                }
                                              },
                                              child: const Padding(
                                                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                child: Icon(Icons.remove, size: 16),
                                              ),
                                            ),
                                            Padding(
                                              padding: const EdgeInsets.symmetric(horizontal: 8),
                                              child: Text(
                                                '${cartItem.quantity}',
                                                style: const TextStyle(fontWeight: FontWeight.bold),
                                              ),
                                            ),
                                            InkWell(
                                              onTap: () => cart?.incrementQuantity(item.id),
                                              child: const Padding(
                                                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                child: Icon(Icons.add, size: 16),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const Spacer(),
                                      Text(
                                        currencyService.format(cartItem.totalPrice),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF574325),
                                          fontSize: 14,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    ),
            ),

            // Footer
            if (!isCartEmpty) ...[
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    if (cart != null) ...[
                      _buildPromoSection(cart),
                      const SizedBox(height: 14),
                    ],
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Estimated Subtotal',
                            style: TextStyle(fontSize: 15, color: Colors.black54)),
                        Text(
                          currencyService.format(subtotal),
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                      ],
                    ),
                    if (discountAmount > 0) ...[
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Promo Discount (${((cart?.discountPercentage ?? 0) * 100).toInt()}%)',
                            style: const TextStyle(fontSize: 14, color: Colors.green, fontWeight: FontWeight.w600),
                          ),
                          Text(
                            '-${currencyService.format(discountAmount)}',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Total',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
                        ),
                        Text(
                          currencyService.format(finalTotal),
                          style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF574325),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 46,
                      child: ElevatedButton.icon(
                        onPressed: cart == null
                            ? null
                            : () => _showPaymentSelectionModal(
                                  context,
                                  cart!,
                                  currencyService,
                                  cartItems,
                                ),
                        icon: const Icon(Icons.payment),
                        label: const Text('Proceed to Formal Quote / Payment'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPromoSection(CartService cart) {
    if (cart.appliedPromoCode != null) {
      final discountPercent = (cart.discountPercentage * 100).toInt();
      final isMinMet = cart.isMinOrderMet;

      if (!isMinMet) {
        final diff = (cart.minOrderValue - cart.subtotal).toStringAsFixed(2);
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.amber.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.amber.shade300),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline, size: 18, color: Colors.amber.shade900),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${cart.appliedPromoCode}: Add \$$diff more to activate $discountPercent% off',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.amber.shade900,
                  ),
                ),
              ),
              InkWell(
                onTap: () => cart.removePromoCode(),
                child: const Icon(Icons.close, size: 18, color: Colors.black54),
              ),
            ],
          ),
        );
      }

      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF574325).withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF574325).withOpacity(0.2)),
        ),
        child: Row(
          children: [
            const Icon(Icons.discount_outlined, size: 18, color: Color(0xFF574325)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${cart.appliedPromoCode} ($discountPercent% OFF)',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: Color(0xFF574325),
                ),
              ),
            ),
            InkWell(
              onTap: () {
                cart.removePromoCode();
                setState(() => _promoError = null);
              },
              child: const Icon(Icons.close, size: 18, color: Colors.black54),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 38,
                child: TextField(
                  controller: _promoController,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    hintText: 'Promo Code (e.g. BARNOCK10)',
                    hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: const BorderSide(color: Color(0xFF574325)),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 38,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF574325),
                  side: const BorderSide(color: Color(0xFF574325)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                ),
                onPressed: _isValidatingPromo
                    ? null
                    : () async {
                  final code = _promoController.text.trim();
                  if (code.isEmpty) return;
                        setState(() {
                          _isValidatingPromo = true;
                          _promoError = null;
                        });
                        final error = await cart.applyPromoCode(code);
                        if (mounted) {
                          setState(() {
                            _isValidatingPromo = false;
                            if (error == null) {
                              _promoController.clear();
                              _promoError = null;
                            } else {
                              _promoError = error;
                            }
                          });
                  }
                },
                child: _isValidatingPromo
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Apply', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
        if (_promoError != null)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 4),
            child: Text(
              _promoError!,
              style: TextStyle(color: Colors.red.shade700, fontSize: 11),
            ),
          ),
      ],
    );
  }
}