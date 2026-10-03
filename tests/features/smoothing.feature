Feature: How fast a new sample takes over

  An IV-skew signal is smoothed: each new sample is blended in with a
  weight that grows with the time since the last one, counted in the
  signal's time constants.  A sample arriving at once changes nothing,
  one a time constant later weighs about 0.632, and one after a long
  silence replaces the signal outright.

  Scenario Outline: A sample's weight grows with the gap before it
    Then a sample <gap> time constants after the last weighs <weight> within <tolerance>

    Examples:
      | gap | weight | tolerance |
      | 0   | 0      | 0.000001  |
      | 0.5 | 0.393  | 0.001     |
      | 1   | 0.632  | 0.001     |
      | 3   | 0.950  | 0.001     |
      | 800 | 1      | 0.000001  |
