import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cashi_flow/presentation/core/theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cashi_flow/domain/models/transaction_model.dart';
import 'package:cashi_flow/domain/providers/transaction_providers.dart';
import 'package:go_router/go_router.dart';

/// MethodChannel to talk to our native Kotlin UPI handler
const _upiChannel = MethodChannel('com.weberq.cashiflow/upi');

class PayHubScreen extends ConsumerStatefulWidget {
  const PayHubScreen({super.key});

  @override
  ConsumerState<PayHubScreen> createState() => _PayHubScreenState();
}

class _PayHubScreenState extends ConsumerState<PayHubScreen> {
  final TextEditingController _upiController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();

  @override
  void dispose() {
    _upiController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  void _onKeypadTap(String value) {
    HapticFeedback.lightImpact();
    setState(() {
      if (value == '<') {
        if (_amountController.text.isNotEmpty) {
          _amountController.text = _amountController.text.substring(0, _amountController.text.length - 1);
        }
      } else {
        _amountController.text += value;
      }
    });
  }

  /// Launch internal scanners of Vendor apps directly
  Future<void> _launchAppScanner(String appName) async {
    HapticFeedback.selectionClick();
    try {
      if (appName == 'Paytm') {
        await _upiChannel.invokeMethod('launchUpi', {
          'uri': 'paytmmp://paytm.com/scan',
          'package': 'net.one97.paytm',
        });
      } else if (appName == 'GPay') {
         await _upiChannel.invokeMethod('launchUpi', {
          'uri': 'gpay://qr',
          'package': 'com.google.android.apps.nbu.paisa.user',
        });
      } else if (appName == 'PhonePe') {
         await _upiChannel.invokeMethod('launchApp', {
          'package': 'com.phonepe.app',
        });
      }
    } on PlatformException catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not launch $appName')),
        );
      }
    }
    
    // Auto-pop the PayHub screen when launching an external scanner 
    // because the payment will be tracked via Notification Service instead
    if (mounted) {
      context.pop();
    }
  }

  /// Build the full standard `upi://pay?...` URI string for manual inputs
  String _buildUpiUri(String upiId, String amount) {
    final encodedPa = Uri.encodeComponent(upiId).replaceAll('%40', '@');
    return 'upi://pay?pa=$encodedPa&pn=Payee&am=$amount&cu=INR';
  }

  Future<void> _launchManualUpiApp(String androidPackage) async {
    HapticFeedback.selectionClick();
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
      title: 'Routed to $androidPackage',
      type: 'Expense',
      accountId: 'pending_acc', // Will be mapped later when confirmed or reviewed
      description: 'UPI ID: $upiId',
      status: 'pending',
    );
    
    await ref.read(transactionRepositoryProvider).addTransaction(newTx);

    final upiUri = _buildUpiUri(upiId, amount);

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
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.darkBackground,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('New Payment'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            HapticFeedback.selectionClick();
            if (mounted) context.pop();
          },
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Direct Scanner Options Array
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.electricMint.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppTheme.electricMint.withOpacity(0.3)),
              ),
              child: Column(
                children: [
                  const Icon(Icons.qr_code_scanner, size: 40, color: AppTheme.electricMint),
                  const SizedBox(height: 12),
                  const Text(
                    'Direct Scan & Auto-Track',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.electricMint),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Launch your favorite app to scan directly. Receipts are tracked automatically.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _AppRouteButton(
                        label: 'GPay',
                        iconPath: Icons.g_mobiledata,
                        color: Colors.blueAccent,
                        onTap: () => _launchAppScanner('GPay'),
                      ),
                      _AppRouteButton(
                        label: 'PhonePe',
                        iconPath: Icons.phone_android,
                        color: Colors.purpleAccent,
                        onTap: () => _launchAppScanner('PhonePe'),
                      ),
                      _AppRouteButton(
                        label: 'Paytm',
                        iconPath: Icons.payment,
                        color: Colors.lightBlue,
                        onTap: () => _launchAppScanner('Paytm'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 40),
            Text(
              'Or Manual Entry',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
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
            const SizedBox(height: 24),
            
            // Amount Display Custom Keypad
            Container(
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
              decoration: BoxDecoration(
                color: AppTheme.surfaceColor,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.currency_rupee, color: AppTheme.electricMint, size: 36),
                  const SizedBox(width: 8),
                  Text(
                    _amountController.text.isEmpty ? '0.00' : _amountController.text,
                    style: const TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.onSurfaceColor,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _buildNumericKeypad(),
            
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _launchManualUpiApp('com.google.android.apps.nbu.paisa.user'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.surfaceColor,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: const Text('GPay'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _launchManualUpiApp('com.phonepe.app'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.surfaceColor,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: const Text('PhonePe'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _launchManualUpiApp('net.one97.paytm'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.surfaceColor,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: const Text('Paytm'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildNumericKeypad() {
    return GridView.count(
      shrinkWrap: true,
      crossAxisCount: 3,
      childAspectRatio: 2,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        '1', '2', '3',
        '4', '5', '6',
        '7', '8', '9',
        '.', '0', '<'
      ].map((key) {
        return InkWell(
          onTap: () => _onKeypadTap(key),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            decoration: BoxDecoration(
              color: AppTheme.surfaceColor.withOpacity(0.5),
              borderRadius: BorderRadius.circular(16),
            ),
            alignment: Alignment.center,
            child: key == '<'
                ? const Icon(Icons.backspace_outlined)
                : Text(
                    key,
                    style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                  ),
          ),
        );
      }).toList(),
    );
  }
}

class _AppRouteButton extends StatelessWidget {
  final String label;
  final IconData iconPath;
  final Color color;
  final VoidCallback onTap;

  const _AppRouteButton({
    required this.label,
    required this.iconPath,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 85,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.4)),
        ),
        child: Column(
          children: [
            Icon(iconPath, size: 32, color: color),
            const SizedBox(height: 8),
            Text(label, style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}
