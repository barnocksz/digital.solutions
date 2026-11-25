import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pinput/pinput.dart';
import 'package:provider/provider.dart';
import '../models/quote.dart';
import '../services/currency_service.dart';
import '../services/invoice_pdf_service.dart';

class MyOrdersView extends StatefulWidget {
  const MyOrdersView({super.key});

  @override
  State<MyOrdersView> createState() => _MyOrdersViewState();
}

class _MyOrdersViewState extends State<MyOrdersView> {
  final _emailController = TextEditingController();
  String? _queriedEmail;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  void _searchQuotes() {
    final email = _emailController.text.trim();
    if (email.isNotEmpty) {
      setState(() => _queriedEmail = email);
    }
  }

  Future<void> _showUpdateBillingEmailDialog(BuildContext context, List<Quote> quotes) async {
    final newEmailController = TextEditingController();
    final otpController = TextEditingController();
    Timer? cooldownTimer;
    int resendCooldown = 0;
    const int maxOtpAttempts = 3;
    int otpAttempts = 1;
    int currentStep = 0; // 0: enter email, 1: enter OTP
    String targetNewEmail = '';
    String? requestId;
    String? validationError;
    bool isProcessing = false;

    Future<void> sendOtpRequest(String newEmail, void Function(void Function()) setModalState) async {
      final otp = (100000 + Random().nextInt(900000)).toString();
      final docRef = await FirebaseFirestore.instance.collection('email_change_requests').add({
        'oldEmail': _queriedEmail,
        'newEmail': newEmail,
        'otp': otp,
        'status': 'pending',
        'attemptNumber': otpAttempts,
        'createdAt': FieldValue.serverTimestamp(),
        'expiresAt': Timestamp.fromDate(DateTime.now().add(const Duration(minutes: 10))),
      });

      requestId = docRef.id;
      cooldownTimer?.cancel();
      setModalState(() => resendCooldown = 60);
      cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (resendCooldown > 1) {
          setModalState(() => resendCooldown--);
        } else {
          timer.cancel();
          setModalState(() => resendCooldown = 0);
        }
      });
    }

    Future<void> verifyAndSubmitOtp(
      BuildContext dialogCtx,
      void Function(void Function()) setModalState,
    ) async {
      final enteredOtp = otpController.text.trim();
      if (enteredOtp.length != 6) {
        setModalState(() => validationError = 'Please enter the 6-digit code.');
        return;
      }

      setModalState(() {
        isProcessing = true;
        validationError = null;
      });

      try {
        final firestore = FirebaseFirestore.instance;
        final requestDoc = await firestore.collection('email_change_requests').doc(requestId).get();

        if (!requestDoc.exists) {
          setModalState(() {
            isProcessing = false;
            validationError = 'Verification session expired. Please start over.';
          });
          return;
        }

        final data = requestDoc.data();
        final expiresAt = (data?['expiresAt'] as Timestamp?)?.toDate();

        if (expiresAt == null || DateTime.now().isAfter(expiresAt)) {
          setModalState(() {
            isProcessing = false;
            validationError = 'Verification code has expired. Please start over.';
          });
          return;
        }

        if (data?['otp'] != enteredOtp) {
          setModalState(() {
            isProcessing = false;
            validationError = 'Invalid verification code. Please check and try again.';
          });
          return;
        }

        final batch = firestore.batch();

        // 1. Update customer email across all linked quotes
        for (final quote in quotes) {
          final quoteRef = firestore.collection('quotes').doc(quote.id);
          batch.update(quoteRef, {'customerEmail': targetNewEmail});
        }

        // 2. Update new customer record
        final newCustomerRef = firestore.collection('customers').doc(targetNewEmail);
        batch.set(newCustomerRef, {
          'email': targetNewEmail,
          'previousEmail': _queriedEmail,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        // 3. Mark the email change request completed
        batch.update(firestore.collection('email_change_requests').doc(requestId), {
          'status': 'completed',
          'verifiedAt': FieldValue.serverTimestamp(),
        });

        // 4. Log notifications for both the old and new email addresses
        final oldEmailLogRef = firestore
            .collection('customers')
            .doc(_queriedEmail)
            .collection('email_logs')
            .doc();
        batch.set(oldEmailLogRef, {
          'type': 'billing_email_changed_security_alert',
          'period': 'Security Notice: Billing Email Transferred',
          'recipientEmail': _queriedEmail,
          'newEmail': targetNewEmail,
          'status': 'sending',
          'createdAt': FieldValue.serverTimestamp(),
        });

        final newEmailLogRef = firestore
            .collection('customers')
            .doc(targetNewEmail)
            .collection('email_logs')
            .doc();
        batch.set(newEmailLogRef, {
          'type': 'billing_email_changed_confirmation',
          'period': 'Confirmation: Primary Billing Email Activated',
          'recipientEmail': targetNewEmail,
          'oldEmail': _queriedEmail,
          'status': 'sending',
          'createdAt': FieldValue.serverTimestamp(),
        });

        await batch.commit();
        TextInput.finishAutofillContext();

        if (dialogCtx.mounted) Navigator.pop(dialogCtx);

        if (mounted) {
          setState(() {
            _queriedEmail = targetNewEmail;
            _emailController.text = targetNewEmail;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Billing email updated to $targetNewEmail. Notification sent to both addresses.'),
              backgroundColor: Colors.green.shade800,
            ),
          );
        }
      } catch (e) {
        setModalState(() {
          isProcessing = false;
          validationError = 'Failed to update email: $e';
        });
      }
    }

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setModalState) {
          final defaultPinTheme = PinTheme(
            width: 48,
            height: 52,
            textStyle: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF574325),
            ),
            decoration: BoxDecoration(
              color: const Color(0xFFF7F5F2),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade300),
            ),
          );

          final focusedPinTheme = defaultPinTheme.copyDecorationWith(
            border: Border.all(color: const Color(0xFF574325), width: 1.8),
            color: Colors.white,
          );

          final submittedPinTheme = defaultPinTheme.copyWith(
            decoration: defaultPinTheme.decoration?.copyWith(
              color: Colors.white,
              border: Border.all(color: const Color(0xFF574325)),
            ),
          );

          final errorPinTheme = defaultPinTheme.copyDecorationWith(
            border: Border.all(color: Colors.red.shade700, width: 1.5),
            color: Colors.red.shade50.withOpacity(0.5),
          );

          return AlertDialog(
            title: Text(currentStep == 0 ? 'Update Primary Billing Email' : 'Verify Email Change'),
            content: SizedBox(
              width: 440,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (currentStep == 0) ...[
                    Text(
                      'Current Email: $_queriedEmail',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'A 6-digit verification code will be sent to the new email address before existing quotes and invoices are transferred.',
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: newEmailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        labelText: 'New Billing Email',
                        hintText: 'e.g. client@example.com',
                        prefixIcon: const Icon(Icons.email_outlined),
                        errorText: validationError,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ] else ...[
                    AutofillGroup(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Enter the 6-digit code sent to $targetNewEmail:',
                            style: const TextStyle(fontSize: 13, color: Colors.black87),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'The verification code is valid for 10 minutes.',
                            style: TextStyle(fontSize: 11, color: Colors.black54),
                          ),
                          const SizedBox(height: 16),
                          Center(
                            child: Pinput(
                              length: 6,
                              controller: otpController,
                              autofocus: true,
                              keyboardType: TextInputType.number,
                              autofillHints: const [AutofillHints.oneTimeCode],
                              defaultPinTheme: defaultPinTheme,
                              focusedPinTheme: focusedPinTheme,
                              submittedPinTheme: submittedPinTheme,
                              errorPinTheme: errorPinTheme,
                              forceErrorState: validationError != null,
                              onCompleted: (pin) {
                                if (!isProcessing) {
                                  verifyAndSubmitOtp(dialogCtx, setModalState);
                                }
                              },
                              onChanged: (val) {
                                if (validationError != null) {
                                  setModalState(() => validationError = null);
                                }
                              },
                            ),
                          ),
                          if (validationError != null) ...[
                            const SizedBox(height: 8),
                            Center(
                              child: Text(
                                validationError!,
                                style: TextStyle(color: Colors.red.shade700, fontSize: 12),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                otpAttempts >= maxOtpAttempts
                                    ? 'Max attempts reached ($maxOtpAttempts/$maxOtpAttempts)'
                                    : resendCooldown > 0
                                        ? 'Resend code in ${resendCooldown}s'
                                        : "Didn't receive the code?",
                                style: TextStyle(
                                  fontSize: 12,
                                  color: otpAttempts >= maxOtpAttempts
                                      ? Colors.red.shade700
                                      : resendCooldown > 0
                                          ? const Color(0xFF574325)
                                          : Colors.black54,
                                  fontWeight: resendCooldown > 0 || otpAttempts >= maxOtpAttempts
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                ),
                              ),
                              TextButton(
                                onPressed: (resendCooldown > 0 || isProcessing || otpAttempts >= maxOtpAttempts)
                                    ? null
                                    : () async {
                                        if (otpAttempts >= maxOtpAttempts) return;
                                        setModalState(() {
                                          isProcessing = true;
                                          validationError = null;
                                        });
                                        try {
                                          otpAttempts++;
                                          await sendOtpRequest(targetNewEmail, setModalState);
                                          setModalState(() {
                                            isProcessing = false;
                                            otpController.clear();
                                          });
                                          if (context.mounted) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(
                                                content: Text('A new 6-digit code has been sent to $targetNewEmail (Attempt $otpAttempts of $maxOtpAttempts)'),
                                                backgroundColor: const Color(0xFF574325),
                                              ),
                                            );
                                          }
                                        } catch (e) {
                                          setModalState(() {
                                            otpAttempts--;
                                            isProcessing = false;
                                            validationError = 'Failed to resend code: $e';
                                          });
                                        }
                                      },
                                child: Text(
                                  otpAttempts >= maxOtpAttempts ? 'Limit Reached' : 'Resend Code',
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isProcessing
                    ? null
                    : () {
                        if (currentStep == 1) {
                          cooldownTimer?.cancel();
                          setModalState(() {
                            currentStep = 0;
                            resendCooldown = 0;
                            validationError = null;
                            otpController.clear();
                          });
                        } else {
                          cooldownTimer?.cancel();
                          Navigator.pop(ctx);
                        }
                      },
                child: Text(currentStep == 1 ? 'Back' : 'Cancel'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF574325),
                  foregroundColor: Colors.white,
                ),
                onPressed: isProcessing
                    ? null
                    : () async {
                        if (currentStep == 0) {
                        final newEmail = newEmailController.text.trim();
                        final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

                        if (newEmail.isEmpty) {
                          setModalState(() => validationError = 'Please enter an email address.');
                          return;
                        }
                        if (!emailRegex.hasMatch(newEmail)) {
                          setModalState(() => validationError = 'Please enter a valid email address.');
                          return;
                        }
                        if (newEmail.toLowerCase() == _queriedEmail!.toLowerCase()) {
                          setModalState(() => validationError = 'New email must be different from current email.');
                          return;
                        }

                        setModalState(() {
                            isProcessing = true;
                          validationError = null;
                        });

                        try {
                            final firestore = FirebaseFirestore.instance;
                            // Global rate limit: max 5 requests per hour for this account
                            final oneHourAgo = DateTime.now().subtract(const Duration(hours: 1));
                            final recentRequests = await firestore
                                .collection('email_change_requests')
                                .where('oldEmail', isEqualTo: _queriedEmail)
                                .where('createdAt', isGreaterThan: Timestamp.fromDate(oneHourAgo))
                                .get();

                            if (recentRequests.docs.length >= 5) {
                              setModalState(() {
                                isProcessing = false;
                                validationError = 'Too many requests. Please wait an hour before trying again.';
                              });
                              return;
                            }

                            await sendOtpRequest(newEmail, setModalState);

                            setModalState(() {
                              targetNewEmail = newEmail;
                              currentStep = 1;
                              isProcessing = false;
                              validationError = null;
                            });
                          } catch (e) {
                            setModalState(() {
                              isProcessing = false;
                              validationError = 'Failed to generate code: $e';
                            });
                          }
                          return;
                        }

                        // Step 1: Verify OTP & execute email change
                        await verifyAndSubmitOtp(dialogCtx, setModalState);
                      },
                child: isProcessing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : Text(currentStep == 0 ? 'Send Verification Code' : 'Verify & Update Email'),
              ),
            ],
          );
        },
      ),
    );
    cooldownTimer?.cancel();
    newEmailController.dispose();
    otpController.dispose();
  }

  Future<void> _showMonthYearStatementDialog(BuildContext context, List<Quote> quotes) async {
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
            title: const Text('Download Statement of Account'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Select a specific month and year or download all transactions.',
                  style: TextStyle(fontSize: 13, color: Colors.black54),
                ),
                const SizedBox(height: 12),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('All Time (All Transactions)'),
                  value: allTime,
                  onChanged: (val) {
                    setDialogState(() => allTime = val ?? false);
                  },
                ),
                if (!allTime) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: DropdownButtonFormField<int>(
                          value: selectedMonth,
                          decoration: const InputDecoration(
                            labelText: 'Month',
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            border: OutlineInputBorder(),
                          ),
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
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: DropdownButtonFormField<int>(
                          value: selectedYear,
                          decoration: const InputDecoration(
                            labelText: 'Year',
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            border: OutlineInputBorder(),
                          ),
                          items: availableYears.map((year) {
                            return DropdownMenuItem<int>(
                              value: year,
                              child: Text(year.toString()),
                            );
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
                label: const Text('Download PDF'),
                onPressed: () async {
                  Navigator.pop(ctx);
                  DateTime? start;
                  DateTime? end;
                  if (!allTime) {
                    start = DateTime(selectedYear, selectedMonth, 1);
                    end = DateTime(selectedYear, selectedMonth + 1, 0, 23, 59, 59, 999);
                  }
                  await InvoicePdfService.downloadStatement(
                    customerEmail: _queriedEmail!,
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

  void _showEmailDeliveryHistoryModal(BuildContext context) {
    bool isDescending = true;
    int currentPage = 0;
    const int pageSize = 4;
    const int maxRetryAttempts = 3;
    final searchController = TextEditingController();
    String searchQuery = '';
    final Set<String> resendingLogIds = {};

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: StatefulBuilder(
          builder: (titleCtx, setTitleState) => Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Text(
                  'Statement Delivery Logs',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
              ),
              TextButton.icon(
                onPressed: () {
                  setTitleState(() => isDescending = !isDescending);
                },
                icon: Icon(
                  isDescending ? Icons.arrow_downward : Icons.arrow_upward,
                  size: 16,
                ),
                label: Text(
                  isDescending ? 'Newest First' : 'Oldest First',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ),
        content: StatefulBuilder(
          builder: (dialogCtx, setModalState) {
            return SizedBox(
              width: 540,
              height: 460,
              child: Column(
                children: [
                  // Search filter bar
                  TextField(
                    controller: searchController,
                    decoration: InputDecoration(
                      hintText: 'Search by month (e.g. November), status, or error...',
                      hintStyle: const TextStyle(fontSize: 12),
                      prefixIcon: const Icon(Icons.search, size: 18),
                      suffixIcon: searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 16),
                              onPressed: () {
                                searchController.clear();
                                setModalState(() {
                                  searchQuery = '';
                                  currentPage = 0;
                                });
                              },
                            )
                          : null,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onChanged: (val) {
                      setModalState(() {
                        searchQuery = val.trim().toLowerCase();
                        currentPage = 0;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('customers')
                          .doc(_queriedEmail)
                          .collection('email_logs')
                          .orderBy('createdAt', descending: isDescending)
                          .snapshots(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                          return const Center(
                            child: Text('No statement email deliveries recorded yet.'),
                          );
                        }

                        // Filter by month or keyword
                        final filteredLogs = snapshot.data!.docs.where((doc) {
                          if (searchQuery.isEmpty) return true;
                          final data = doc.data() as Map<String, dynamic>;
                          final period = (data['period'] as String? ?? '').toLowerCase();
                          final status = (data['status'] as String? ?? '').toLowerCase();
                          final error = (data['error'] as String? ?? '').toLowerCase();
                          return period.contains(searchQuery) ||
                              status.contains(searchQuery) ||
                              error.contains(searchQuery);
                        }).toList();

                        if (filteredLogs.isEmpty) {
                          return Center(
                            child: Text(
                              'No logs matching "$searchQuery"',
                              style: const TextStyle(color: Colors.black54),
                            ),
                          );
                        }

                        // Pagination calculations
                        final totalCount = filteredLogs.length;
                        final totalPages = (totalCount / pageSize).ceil();
                        if (currentPage >= totalPages) {
                          currentPage = totalPages > 0 ? totalPages - 1 : 0;
                        }
                        final startIndex = currentPage * pageSize;
                        final endIndex = (startIndex + pageSize) > totalCount ? totalCount : (startIndex + pageSize);
                        final pageLogs = filteredLogs.sublist(startIndex, endIndex);

                        return Column(
                          children: [
                            Expanded(
                              child: ListView.separated(
                                itemCount: pageLogs.length,
                                separatorBuilder: (_, __) => const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  final doc = pageLogs[index];
                                  final data = doc.data() as Map<String, dynamic>;
                                  final status = (data['status'] as String? ?? 'sent').toLowerCase();
                                  final isDelivered = status == 'delivered';
                                  final isFailed = status == 'failed';
                                  final isSending = status == 'sending';
                                  final period = data['period'] ?? 'Monthly Statement';
                                  final retryCount = (data['retryCount'] as num?)?.toInt() ?? 0;
                                  final hasExceededLimit = retryCount >= maxRetryAttempts;
                                  final timestamp = (data['createdAt'] as Timestamp?)?.toDate();
                                  final dateStr = timestamp != null
                                      ? timestamp.toIso8601String().substring(0, 16).replaceAll('T', ' ')
                                      : 'Recently';
                                  final errorMsg = data['error'] as String?;
                                  final isResending = resendingLogIds.contains(doc.id) || isSending;

                                  return ListTile(
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                                    leading: Icon(
                                      isDelivered
                                          ? Icons.mark_email_read_outlined
                                          : isFailed
                                              ? Icons.error_outline
                                              : Icons.mail_outline,
                                      color: isDelivered
                                          ? Colors.green.shade700
                                          : isFailed
                                              ? Colors.red.shade700
                                              : Colors.orange.shade700,
                                    ),
                                    title: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            period,
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                          ),
                                        ),
                                        Chip(
                                          label: Text(
                                            status.toUpperCase(),
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: isDelivered
                                                  ? Colors.green.shade800
                                                  : isFailed
                                                      ? Colors.red.shade800
                                                      : Colors.orange.shade800,
                                            ),
                                          ),
                                          backgroundColor: isDelivered
                                              ? Colors.green.shade50
                                              : isFailed
                                                  ? Colors.red.shade50
                                                  : Colors.orange.shade50,
                                          visualDensity: VisualDensity.compact,
                                          padding: EdgeInsets.zero,
                                        ),
                                      ],
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const SizedBox(height: 2),
                                        Text(
                                          'Sent: $dateStr • Attempts: $retryCount/$maxRetryAttempts',
                                          style: const TextStyle(fontSize: 11),
                                        ),
                                        if (errorMsg != null && errorMsg.isNotEmpty)
                                          Padding(
                                            padding: const EdgeInsets.only(top: 2),
                                            child: Text(
                                              'Error: $errorMsg',
                                              style: TextStyle(fontSize: 11, color: Colors.red.shade700),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                      ],
                                    ),
                                    trailing: isFailed
                                        ? hasExceededLimit
                                            ? Tooltip(
                                                message: 'Maximum retry attempts ($maxRetryAttempts) reached. Contact support.',
                                                child: Chip(
                                                  label: const Text('Limit Reached', style: TextStyle(fontSize: 10)),
                                                  backgroundColor: Colors.grey.shade200,
                                                  visualDensity: VisualDensity.compact,
                                                ),
                                              )
                                            : OutlinedButton.icon(
                                                icon: isResending
                                                    ? const SizedBox(
                                                        width: 12,
                                                        height: 12,
                                                        child: CircularProgressIndicator(strokeWidth: 2),
                                                      )
                                                    : const Icon(Icons.refresh, size: 14),
                                                label: Text('Resend ($retryCount/$maxRetryAttempts)', style: const TextStyle(fontSize: 11)),
                                                style: OutlinedButton.styleFrom(
                                                  foregroundColor: Colors.red.shade800,
                                                  side: BorderSide(color: Colors.red.shade300),
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                  visualDensity: VisualDensity.compact,
                                                ),
                                                onPressed: isResending
                                                    ? null
                                                    : () async {
                                                        setModalState(() => resendingLogIds.add(doc.id));
                                                        try {
                                                          await FirebaseFirestore.instance
                                                              .collection('customers')
                                                              .doc(_queriedEmail)
                                                              .collection('email_logs')
                                                              .doc(doc.id)
                                                              .update({
                                                            'status': 'sending',
                                                            'retryCount': FieldValue.increment(1),
                                                            'retryRequestedAt': FieldValue.serverTimestamp(),
                                                            'error': FieldValue.delete(),
                                                          });
                                                          if (context.mounted) {
                                                            ScaffoldMessenger.of(context).showSnackBar(
                                                              SnackBar(
                                                                content: Text('Re-dispatch scheduled for $period (attempt ${retryCount + 1}/$maxRetryAttempts).'),
                                                                backgroundColor: Colors.green.shade800,
                                                              ),
                                                            );
                                                          }
                                                        } catch (e) {
                                                          if (context.mounted) {
                                                            ScaffoldMessenger.of(context).showSnackBar(
                                                              SnackBar(
                                                                content: Text('Failed to request retry: $e'),
                                                                backgroundColor: Colors.red.shade800,
                                                              ),
                                                            );
                                                          }
                                                        } finally {
                                                          setModalState(() => resendingLogIds.remove(doc.id));
                                                        }
                                                      },
                                              )
                                        : null,
                                  );
                                },
                              ),
                            ),
                            const Divider(height: 1),
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Showing ${startIndex + 1}-$endIndex of $totalCount',
                                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                                  ),
                                  Row(
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.chevron_left),
                                        iconSize: 20,
                                        tooltip: 'Previous page',
                                        onPressed: currentPage > 0
                                            ? () => setModalState(() => currentPage--)
                                            : null,
                                      ),
                                      Text(
                                        'Page ${currentPage + 1} of $totalPages',
                                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.chevron_right),
                                        iconSize: 20,
                                        tooltip: 'Next page',
                                        onPressed: currentPage < totalPages - 1
                                            ? () => setModalState(() => currentPage++)
                                            : null,
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
                ],
              ),
            );
          },
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    ).then((_) => searchController.dispose());
  }

  void _showSubmitTxHashModal(BuildContext context, Quote quote) {
    final txController = TextEditingController(text: quote.paymentTxHash);
    String selectedCurrency = quote.paymentCurrency ?? AppCurrency.btc.code;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogContext, setModalState) {
          return AlertDialog(
            title: const Text('Submit Crypto Payment Details'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Enter your transaction hash (TxID) to submit your payment for on-chain verification.',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
                const SizedBox(height: 12),
                DropdownButton<String>(
                  value: selectedCurrency,
                  isExpanded: true,
                  items: [AppCurrency.btc.code, AppCurrency.eth.code]
                      .map((code) => DropdownMenuItem(value: code, child: Text(code)))
                      .toList(),
                  onChanged: (val) => setModalState(() => selectedCurrency = val!),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: txController,
                  decoration: const InputDecoration(
                    labelText: 'Transaction Hash (TxID)',
                    hintText: 'e.g. 0x... or btc txid',
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              ElevatedButton(
                onPressed: () async {
                  final hash = txController.text.trim();
                  if (hash.isNotEmpty) {
                    await FirebaseFirestore.instance.collection('quotes').doc(quote.id).update({
                      'paymentTxHash': hash,
                      'paymentCurrency': selectedCurrency,
                      'verificationStatus': 'pending_verification',
                    });
                    if (ctx.mounted) Navigator.pop(ctx);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Payment TxID submitted successfully.')),
                      );
                    }
                  }
                },
                child: const Text('Submit'),
              ),
            ],
          );
        },
      ),
    ).then((_) => txController.dispose());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Quotes & Orders'),
      ),
      body: Column(
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Lookup by Customer Email',
                      hintText: 'e.g. client@example.com',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onSubmitted: (_) => _searchQuotes(),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _searchQuotes,
                  child: const Text('Search'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _queriedEmail == null
                ? const Center(
                    child: Text('Enter your email address above to view your quote and order history.'),
                  )
                : StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('quotes')
                        .where('customerEmail', isEqualTo: _queriedEmail)
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                        return Center(
                          child: Text('No orders or quotes found for "$_queriedEmail".'),
                        );
                      }

                      final quotes = snapshot.data!.docs
                          .map((d) => Quote.fromFirestore(d.data() as Map<String, dynamic>, d.id))
                          .toList();

                      return Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            color: Colors.grey.shade50,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Order History (${quotes.length})',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                ),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    OutlinedButton.icon(
                                      onPressed: () => _showUpdateBillingEmailDialog(context, quotes),
                                      icon: const Icon(Icons.edit_outlined, size: 16),
                                      label: const Text('Update Email'),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: const Color(0xFF574325),
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      ),
                                    ),
                                    OutlinedButton.icon(
                                      onPressed: () => _showEmailDeliveryHistoryModal(context),
                                      icon: const Icon(Icons.history, size: 16),
                                      label: const Text('Email Logs'),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: const Color(0xFF574325),
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    ElevatedButton.icon(
                                      onPressed: () => _showMonthYearStatementDialog(context, quotes),
                                      icon: const Icon(Icons.receipt_outlined, size: 16),
                                      label: const Text('Account Statement'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF574325),
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const Divider(height: 1),
                          Expanded(
                            child: ListView.separated(
                              padding: const EdgeInsets.all(16),
                              itemCount: quotes.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 12),
                              itemBuilder: (context, index) {
                          final quote = quotes[index];
                          return Card(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                              side: BorderSide(color: Colors.grey.shade200),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'Order #${quote.id.substring(0, quote.id.length > 6 ? 6 : quote.id.length)}',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                      ),
                                      Chip(
                                        label: Text(
                                          quote.status.toUpperCase(),
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                                        ),
                                        backgroundColor: quote.status == 'paid'
                                            ? Colors.green.shade100
                                            : const Color(0xFF574325).withOpacity(0.12),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text('Scope / Items:\n${quote.projectScope}', style: const TextStyle(fontSize: 13)),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Estimated: \$${quote.estimatedCost.toStringAsFixed(2)} USD',
                                    style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF574325)),
                                  ),
                                  if (quote.paymentTxHash != null) ...[
                                    const SizedBox(height: 6),
                                    Text('TxHash: ${quote.paymentTxHash}', style: const TextStyle(fontSize: 12, color: Colors.black54)),
                                  ],
                                  if (quote.verificationStatus != null) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      'Verification: ${quote.verificationStatus}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: quote.status == 'paid' ? Colors.green.shade800 : Colors.orange.shade800,
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 12),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      OutlinedButton.icon(
                                        onPressed: () => quote.status == 'refunded'
                                            ? InvoicePdfService.downloadCreditNote(quote: quote)
                                            : InvoicePdfService.downloadInvoice(quote: quote),
                                        icon: Icon(
                                          quote.status == 'refunded'
                                              ? Icons.assignment_return_outlined
                                              : Icons.picture_as_pdf,
                                          size: 16,
                                        ),
                                        label: Text(quote.status == 'refunded' ? 'Credit Note' : 'Download PDF'),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: quote.status == 'refunded' ? Colors.red.shade800 : const Color(0xFF574325),
                                        ),
                                      ),
                                      if (quote.status != 'paid') ...[
                                        const SizedBox(width: 8),
                                        ElevatedButton.icon(
                                          onPressed: () => _showSubmitTxHashModal(context, quote),
                                          icon: const Icon(Icons.payment, size: 16),
                                          label: Text(quote.paymentTxHash == null ? 'Submit TxID' : 'Update TxID'),
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                              },
                            ),
                          ),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}