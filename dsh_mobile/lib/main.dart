import 'dart:async';

import 'package:flutter/material.dart';

import 'app_state.dart';
import 'ui/device_list_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final state = AppState();
  await state.init();
  runApp(DshApp(state: state));
}

class DshApp extends StatefulWidget {
  final AppState state;
  const DshApp({super.key, required this.state});

  @override
  State<DshApp> createState() => _DshAppState();
}

class _DshAppState extends State<DshApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  StreamSubscription<ApprovalRequest>? _approvalSub;

  /// approvalIds already being shown, to avoid stacking duplicate dialogs
  /// (the host replays pending approvals on every mux reconnect).
  final Set<String> _openApprovals = {};

  @override
  void initState() {
    super.initState();
    _approvalSub = widget.state.approvals.listen(_showApproval);
  }

  @override
  void dispose() {
    _approvalSub?.cancel();
    super.dispose();
  }

  Future<void> _showApproval(ApprovalRequest req) async {
    if (req.approvalId.isNotEmpty && !_openApprovals.add(req.approvalId)) {
      return;
    }
    final ctx = _navigatorKey.currentContext;
    if (ctx == null) {
      _openApprovals.remove(req.approvalId);
      return;
    }
    final allowed = await showDialog<bool>(
      context: ctx,
      barrierDismissible: false,
      builder: (dctx) => AlertDialog(
        title: const Text('工具调用审批'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Agent 请求调用工具：'),
            const SizedBox(height: 8),
            Text(
              req.toolName,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
              ),
            ),
            if (req.reason != null && req.reason!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(req.reason!, style: Theme.of(dctx).textTheme.bodySmall),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx, false),
            child: const Text('拒绝', style: TextStyle(color: Colors.redAccent)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dctx, true),
            child: const Text('允许一次'),
          ),
        ],
      ),
    );
    _openApprovals.remove(req.approvalId);
    if (allowed == null) return;
    try {
      await widget.state
          .answerApproval(req, allowed ? 'allowed-once' : 'rejected');
    } catch (e) {
      final ctx2 = _navigatorKey.currentContext;
      if (ctx2 != null && ctx2.mounted) {
        ScaffoldMessenger.maybeOf(ctx2)
            ?.showSnackBar(SnackBar(content: Text('审批应答失败: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DSH',
      navigatorKey: _navigatorKey,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.dark,
      home: DeviceListPage(state: widget.state),
    );
  }
}
