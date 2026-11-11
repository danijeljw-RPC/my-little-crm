abstract interface class Clock { DateTime now(); }
class SystemClock implements Clock { const SystemClock(); @override DateTime now() => DateTime.now().toUtc(); }
class FixedClock implements Clock { const FixedClock(this.value); final DateTime value; @override DateTime now() => value; }
