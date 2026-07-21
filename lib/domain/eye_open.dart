/// Pure decision logic for the eye-open ("prove you're really up") dismiss
/// mission. The camera + ML Kit widget classifies each front-camera frame into
/// left/right eye-open probabilities and feeds them here; keeping the "have the
/// eyes been open long enough?" rule pure makes it headlessly unit-testable
/// while the ML widget stays thin (device-verify).
library;

/// Probability above which an eye is treated as open. ML Kit's
/// `*EyeOpenProbability` is 0.0–1.0; ~0.6 is a confident-open bar that still
/// tolerates squinting into a bright screen at wake-up.
const double kEyeOpenThreshold = 0.6;

/// Required cumulative open-eyed time before the mission solves, scaled a little
/// by difficulty. Deliberately short — this proves wakefulness, it isn't an
/// endurance test — and the widget always offers a timeout escape, so even the
/// hard window can never trap.
Duration eyeOpenWindowFor(String diff) {
  switch (diff) {
    case 'hard':
      return const Duration(milliseconds: 3500);
    case 'medium':
      return const Duration(milliseconds: 2500);
    default:
      return const Duration(milliseconds: 2000);
  }
}

/// A single classified frame: the left/right eye-open probabilities (null when
/// ML Kit isn't confident, or no live face was found) and [dtMs], the elapsed
/// time attributed to this frame (since the previous sample).
typedef EyeFrame = ({double? left, double? right, int dtMs});

/// Whether BOTH eyes are open past [threshold] in frame [f]. A null probability
/// (no confident classification / no live face) counts as not-open — this is
/// also the live-face requirement that stops a closed-eye half-asleep swipe.
bool bothEyesOpen(EyeFrame f, {double threshold = kEyeOpenThreshold}) {
  final l = f.left;
  final r = f.right;
  return l != null && r != null && l > threshold && r > threshold;
}

/// Total open-eyed milliseconds across [frames]. Cumulative: a blink or a
/// momentarily-lost face simply contributes nothing rather than resetting
/// progress, so natural blinking never punishes the user. Pure.
int accumulateOpenMs(Iterable<EyeFrame> frames,
    {double threshold = kEyeOpenThreshold}) {
  var openMs = 0;
  for (final f in frames) {
    if (bothEyesOpen(f, threshold: threshold)) openMs += f.dtMs;
  }
  return openMs;
}

/// Whether the cumulative open-eyed time across [frames] reaches [required].
/// This is the pass/fail rule the widget mirrors with a running accumulator.
bool sustainedOpen(Iterable<EyeFrame> frames, Duration required,
    {double threshold = kEyeOpenThreshold}) {
  return accumulateOpenMs(frames, threshold: threshold) >=
      required.inMilliseconds;
}
