Feature: A premium's vol, or why there is none

  The vol a premium implies is found by inverting the price.  Trust it
  only when it is computed: a premium with no time value is clamped, and
  one deep in the money near expiry is faint -- any vol prices it, so the
  number means nothing -- while the delta at that vol still holds.

  Background:
    Given an SPX at 7500
    And a rate of 0.045

  Scenario Outline: The vol that priced a premium is the vol it implies
    Given a <right> struck at 7480
    And 4 days to expiry
    And a vol of 0.18
    Then the implied vol recovers the vol that priced it within 0.00000001

    Examples:
      | right |
      | call  |
      | put   |

  Scenario: A premium with time value implies its vol
    Given a call struck at 7500
    And 4 days to expiry
    And a premium of 58.2131620126
    When the vol it implies is sought
    Then the implied vol is computed
    And the implied vol is 0.18 within 0.0001

  Scenario: A premium at intrinsic is clamped, and its delta still holds
    Given a call struck at 7300
    And 0.27 days to expiry
    And a premium of 200
    When the vol it implies is sought
    Then the implied vol is clamped
    And the delta is 1 within 0.005

  Scenario: A worthless premium is clamped, and its delta is nothing
    Given a call struck at 7550
    And 0.27 days to expiry
    And a premium of 0
    When the vol it implies is sought
    Then the implied vol is clamped
    And the delta is 0 within 0.005

  Scenario: Deep in the money near expiry the vol is faint, and the delta holds
    Given a call struck at 7300
    And 0.27 days to expiry
    And a premium of 200.2428296367
    When the vol it implies is sought
    Then the implied vol is faint
    And the delta is 1 within 0.005
