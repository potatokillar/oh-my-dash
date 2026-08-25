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
      builder: (dctx) {
        final scheme = Theme.of(dctx).colorScheme;
        return AlertDialog(
          title: const Text('工具调用审批'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Agent 请求调用工具：',
                style: Theme.of(dctx)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: scheme.outline),
              ),
              const SizedBox(height: 10),
              // Tool name in an accent-tinted icon block.
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: scheme.outlineVariant.withValues(alpha: 0.35),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.build_outlined,
                        size: 18, color: scheme.primary),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        req.toolName,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontFamily: 'monospace',
                          color: scheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (req.reason != null && req.reason!.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  req.reason!,
                  style: Theme.of(dctx)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: scheme.outline),
                ),
              ],
            ],
          ),
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.pop(dctx, false),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.redAccent,
                side: const BorderSide(color: Colors.redAccent),
              ),
              child: const Text('拒绝'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dctx, true),
              child: const Text('允许一次'),
            ),
          ],
        );
      },
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
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF7C6CF0), // deep blue-violet
      brightness: Brightness.dark,
    );
    return MaterialApp(
      title: 'DSH',
      navigatorKey: _navigatorKey,
      theme: ThemeData(
        colorScheme: scheme,
        useMaterial3: true,
        // Near-black backdrop: cards/dialogs keep the violet-tinted surfaces
        // for layering, the page ground drops to almost pure black.
        scaffoldBackgroundColor: const Color(0xFF0A0A0F),
        appBarTheme: AppBarTheme(
          backgroundColor: scheme.surfaceContainer,
          scrolledUnderElevation: 0,
        ),
        cardTheme: CardThemeData(
          color: scheme.surfaceContainer,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(
              color: scheme.outlineVariant.withValues(alpha: 0.35),
            ),
          ),
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: scheme.surfaceContainerHigh,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(
              color: scheme.outlineVariant.withValues(alpha: 0.35),
            ),
          ),
        ),
        bottomSheetTheme: BottomSheetThemeData(
          backgroundColor: scheme.surfaceContainer,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        dividerTheme: DividerThemeData(
          color: scheme.outlineVariant.withValues(alpha: 0.4),
          thickness: 0.5,
          space: 0.5,
        ),
      ),
      themeMode: ThemeMode.dark,
      home: DeviceListPage(state: widget.state),
    );
  }
}
