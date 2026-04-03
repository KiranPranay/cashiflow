import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:cashi_flow/presentation/core/theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cashi_flow/domain/models/transaction_model.dart';
import 'package:cashi_flow/domain/providers/transaction_providers.dart';

/// Same native MethodChannel as the full PayHubScreen
const _upiChannel = MethodChannel('com.weberq.cashiflow/upi');

class PayHubBottomSheet extends ConsumerStatefulWidget {
  const PayHubBottomSheet({super.key});

  @override
  ConsumerState<PayHubBottomSheet> createState() => _PayHubBottomSheetState();
}

class _PayHubBottomSheetState extends ConsumerState<PayHubBottomSheet> {
  final TextEditingController _upiController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();
  
  bool _isScanning = false;

  @override
  void dispose() {
    _upiController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (capture.barcodes.isNotEmpty) {
      final String? code = capture.barcodes.first.rawValue;
      if (code != null) {
        setState(() {
          _upiController.text = _extractUpiParams(code);
          _isScanning = false;
        });
      }
    }
  }

  String _extractUpiParams(String uri) {
    if (uri.startsWith('upi://pay')) {
      final uriObj = Uri.parse(uri);
      return uriObj.queryParameters['pa'] ?? uri;
    }
    return uri;
  }

  Future<void> _launchUpiApp(String androidPackage) async {
    final upiId = _upiController.text.trim();
    final amount = _amountController.text.trim();
    
    if (upiId.isEmpty || amount.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter UPI ID and amount')),
      );
      return;
    }

    final doubleAmt = double.tryParse(amount);
    if (doubleAmt == null) return;

    // Save transaction as PENDING — will be confirmed by notification listener
    final newTx = TransactionModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      amount: doubleAmt,
      timestamp: DateTime.now(),
      upiId: upiId,
      type: 'Sent',
      status: 'pending',
    );
    
    await ref.read(transactionRepositoryProvider).addTransaction(newTx);

    // Build NPCI-compliant upi:// URI and fire native intent
    final encodedPa = Uri.encodeComponent(upiId).replaceAll('%40', '@');
    final upiUri = 'upi://pay?pa=$encodedPa&pn=Payee&am=$amount&cu=INR';

    try {
      await _upiChannel.invokeMethod('launchUpi', {
        'uri': upiUri,
        'package': androidPackage,
      });
    } on PlatformException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message ?? 'Could not launch payment app')),
        );
      }
    }
    
    if (mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.darkBackground,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(32),
          topRight: Radius.circular(32),
        ),
      ),
      padding: EdgeInsets.only(
        top: 24,
        left: 24,
        right: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Handle bar
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Scan & Pay',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: AppTheme.electricMint,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          
          if (_isScanning) ...[
            SizedBox(
              height: 250,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: MobileScanner(
                  onDetect: _onDetect,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: () => setState(() => _isScanning = false),
              icon: const Icon(Icons.close),
              label: const Text('Cancel Scan'),
            )
          ] else ...[
            ElevatedButton.icon(
              onPressed: () => setState(() => _isScanning = true),
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Scan QR Code'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.surfaceColor,
                foregroundColor: AppTheme.electricMint,
              ),
            ),
          ],

          const SizedBox(height: 16),
          TextField(
            controller: _upiController,
            decoration: InputDecoration(
              labelText: 'UPI ID or Mobile Number',
              prefixIcon: const Icon(Icons.account_balance_wallet_outlined),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
              filled: true,
              fillColor: AppTheme.surfaceColor,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Amount (₹)',
              prefixIcon: const Icon(Icons.currency_rupee),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
              filled: true,
              fillColor: AppTheme.surfaceColor,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Route via:',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _AppRouteButton(
                label: 'GPay',
                iconPath: Icons.g_mobiledata,
                onTap: () => _launchUpiApp('com.google.android.apps.nbu.paisa.user'),
              ),
              _AppRouteButton(
                label: 'PhonePe',
                iconPath: Icons.phone_android,
                onTap: () => _launchUpiApp('com.phonepe.app'),
              ),
              _AppRouteButton(
                label: 'Paytm',
                iconPath: Icons.payment,
                onTap: () => _launchUpiApp('net.one97.paytm'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AppRouteButton extends StatelessWidget {
  final String label;
  final IconData iconPath;
  final VoidCallback onTap;

  const _AppRouteButton({
    required this.label,
    required this.iconPath,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
        decoration: BoxDecoration(
          color: AppTheme.surfaceColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.electricMint.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Icon(iconPath, size: 32, color: AppTheme.onSurfaceColor),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
