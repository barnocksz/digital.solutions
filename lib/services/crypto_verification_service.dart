import 'dart:convert';
import 'package:http/http.dart' as http;

class CryptoTxVerification {
  final bool isConfirmed;
  final int confirmations;
  final bool isValidRecipient;
  final bool isAmountSufficient;
  final String? errorMessage;

  CryptoTxVerification({
    required this.isConfirmed,
    required this.confirmations,
    required this.isValidRecipient,
    required this.isAmountSufficient,
    this.errorMessage,
  });

  bool get isFullyVerified =>
      isConfirmed && isValidRecipient && isAmountSufficient;
}

class CryptoVerificationService {
  /// Verifies a Bitcoin transaction using the public Blockstream Esplora API (no API key required).
  static Future<CryptoTxVerification> verifyBtcTransaction({
    required String txId,
    required String expectedAddress,
    required double expectedBtcAmount,
    int requiredConfirmations = 1,
    http.Client? client,
  }) async {
    final httpClient = client ?? http.Client();
    try {
      final txUri = Uri.parse('https://blockstream.info/api/tx/$txId');
      final txRes = await httpClient.get(txUri);
      if (txRes.statusCode != 200) {
        return CryptoTxVerification(
          isConfirmed: false,
          confirmations: 0,
          isValidRecipient: false,
          isAmountSufficient: false,
          errorMessage: 'Transaction not found on Bitcoin network.',
        );
      }

      final txData = jsonDecode(txRes.body) as Map<String, dynamic>;
      final status = txData['status'] as Map<String, dynamic>? ?? {};
      final isConfirmed = status['confirmed'] as bool? ?? false;
      final txBlockHeight = (status['block_height'] as num?)?.toInt();

      int confirmations = 0;
      if (isConfirmed && txBlockHeight != null) {
        final tipRes = await httpClient.get(Uri.parse('https://blockstream.info/api/blocks/tip/height'));
        if (tipRes.statusCode == 200) {
          final tipHeight = int.tryParse(tipRes.body) ?? txBlockHeight;
          confirmations = (tipHeight - txBlockHeight) + 1;
        }
      }

      // Check outputs for payment to expectedAddress
      final vout = txData['vout'] as List<dynamic>? ?? [];
      final expectedSats = (expectedBtcAmount * 1e8).round();
      int receivedSats = 0;
      bool recipientFound = false;

      for (final out in vout) {
        final scriptPubKeyAddress = out['scriptpubkey_address'] as String?;
        if (scriptPubKeyAddress == expectedAddress) {
          recipientFound = true;
          receivedSats += (out['value'] as num?)?.toInt() ?? 0;
        }
      }

      return CryptoTxVerification(
        isConfirmed: confirmations >= requiredConfirmations,
        confirmations: confirmations,
        isValidRecipient: recipientFound,
        isAmountSufficient: receivedSats >= expectedSats,
      );
    } catch (e) {
      return CryptoTxVerification(
        isConfirmed: false,
        confirmations: 0,
        isValidRecipient: false,
        isAmountSufficient: false,
        errorMessage: 'Verification failed: $e',
      );
    }
  }

  /// Verifies an Ethereum transaction using Etherscan or Blockscout JSON-RPC API.
  static Future<CryptoTxVerification> verifyEthTransaction({
    required String txHash,
    required String expectedAddress,
    required BigInt expectedWeiAmount,
    required String etherscanApiKey,
    int requiredConfirmations = 12,
    http.Client? client,
  }) async {
    final httpClient = client ?? http.Client();
    try {
      // 1. Fetch transaction receipt to check execution status
      final receiptUri = Uri.parse(
        'https://api.etherscan.io/api?module=proxy&action=eth_getTransactionReceipt&txhash=$txHash&apikey=$etherscanApiKey',
      );
      final receiptRes = await httpClient.get(receiptUri);
      final receiptJson = jsonDecode(receiptRes.body);
      final receipt = receiptJson['result'] as Map<String, dynamic>?;

      if (receipt == null || receipt['status'] != '0x1') {
        return CryptoTxVerification(
          isConfirmed: false,
          confirmations: 0,
          isValidRecipient: false,
          isAmountSufficient: false,
          errorMessage: 'Transaction has failed, reverted, or is still pending.',
        );
      }

      final txBlockNumber = int.parse(receipt['blockNumber'].toString().substring(2), radix: 16);

      // 2. Fetch transaction details to verify recipient and value
      final txUri = Uri.parse(
        'https://api.etherscan.io/api?module=proxy&action=eth_getTransactionByHash&txhash=$txHash&apikey=$etherscanApiKey',
      );
      final txRes = await httpClient.get(txUri);
      final txData = jsonDecode(txRes.body)['result'] as Map<String, dynamic>?;

      if (txData == null) {
        return CryptoTxVerification(
          isConfirmed: false,
          confirmations: 0,
          isValidRecipient: false,
          isAmountSufficient: false,
          errorMessage: 'Could not load transaction payload.',
        );
      }

      final toAddress = (txData['to'] as String? ?? '').toLowerCase();
      final hexValue = txData['value'] as String? ?? '0x0';
      final receivedWei = BigInt.parse(
        hexValue.startsWith('0x') ? hexValue.substring(2) : hexValue,
        radix: 16,
      );

      // 3. Fetch latest block number to calculate confirmations
      final blockUri = Uri.parse(
        'https://api.etherscan.io/api?module=proxy&action=eth_blockNumber&apikey=$etherscanApiKey',
      );
      final blockRes = await httpClient.get(blockUri);
      final latestHex = jsonDecode(blockRes.body)['result'] as String;
      final currentBlock = int.parse(latestHex.substring(2), radix: 16);
      final confirmations = (currentBlock - txBlockNumber) + 1;

      return CryptoTxVerification(
        isConfirmed: confirmations >= requiredConfirmations,
        confirmations: confirmations,
        isValidRecipient: toAddress == expectedAddress.toLowerCase(),
        isAmountSufficient: receivedWei >= expectedWeiAmount,
      );
    } catch (e) {
      return CryptoTxVerification(
        isConfirmed: false,
        confirmations: 0,
        isValidRecipient: false,
        isAmountSufficient: false,
        errorMessage: 'Ethereum verification error: $e',
      );
    }
  }
}