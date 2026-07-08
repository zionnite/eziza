import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../constants/colors.dart';

const _kReturnUrlPrefix =
    'https://nvwpsccleewgirlwokys.supabase.co/functions/v1/paystack-return';

/// Hosts Paystack's checkout in an embedded WebView and watches its
/// navigation directly — this is what actually gives a payment flow the
/// "auto-close back into the app" feel (same technique the pay_with_paystack
/// package uses internally), without that package's real drawback: it
/// requires shipping the live Paystack secret key to the client to call
/// api.paystack.co directly. Here the secret key never leaves
/// paystack-initialize (server-side) — this page only ever loads the
/// authorization_url that function already returned.
class PaystackCheckoutPage extends StatefulWidget {
  const PaystackCheckoutPage({super.key, required this.authorizationUrl});
  final String authorizationUrl;

  @override
  State<PaystackCheckoutPage> createState() => _PaystackCheckoutPageState();
}

class _PaystackCheckoutPageState extends State<PaystackCheckoutPage> {
  late final WebViewController _controller;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) {
          if (mounted) setState(() => _loading = true);
        },
        onPageFinished: (_) {
          if (mounted) setState(() => _loading = false);
        },
        onNavigationRequest: (request) {
          if (request.url.startsWith(_kReturnUrlPrefix)) {
            Navigator.of(context).pop(true);
            return NavigationDecision.prevent;
          }
          return NavigationDecision.navigate;
        },
      ))
      ..loadRequest(Uri.parse(widget.authorizationUrl));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {},
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.of(context).pop(false),
          ),
          title: const Text('Complete Payment'),
          backgroundColor: EzizaColors.kWhite,
          foregroundColor: EzizaColors.kText,
          elevation: 0,
        ),
        body: Stack(children: [
          WebViewWidget(controller: _controller),
          if (_loading)
            const Center(child: CircularProgressIndicator(color: EzizaColors.kPurpleD)),
        ]),
      ),
    );
  }
}
