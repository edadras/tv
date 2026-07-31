import 'package:flutter/widgets.dart';

import 'receiver_controller.dart';
import 'sender_controller.dart';

/// Dependency-free state plumbing: an [InheritedNotifier] per role means any
/// widget can read the controller and rebuild when it changes, without
/// pulling in a state-management package.
class SenderScope extends InheritedNotifier<SenderController> {
  const SenderScope({super.key, required SenderController controller, required super.child})
      : super(notifier: controller);

  static SenderController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<SenderScope>();
    assert(scope?.notifier != null, 'No SenderScope above this widget');
    return scope!.notifier!;
  }

  /// Reads the controller without subscribing — for event handlers.
  static SenderController read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<SenderScope>();
    assert(scope?.notifier != null, 'No SenderScope above this widget');
    return scope!.notifier!;
  }
}

class ReceiverScope extends InheritedNotifier<ReceiverController> {
  const ReceiverScope({super.key, required ReceiverController controller, required super.child})
      : super(notifier: controller);

  static ReceiverController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<ReceiverScope>();
    assert(scope?.notifier != null, 'No ReceiverScope above this widget');
    return scope!.notifier!;
  }

  static ReceiverController read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<ReceiverScope>();
    assert(scope?.notifier != null, 'No ReceiverScope above this widget');
    return scope!.notifier!;
  }
}
