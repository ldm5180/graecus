Feature: A delta is signed and bounded

  The delta says how much a contract moves with the index, and its sign
  says which way: a call's is positive and a put's negative.  A stop
  logic reads it, so deep in the money it nears 1 (or -1 for a put),
  far out of the money it nears 0, and at the money a call and a put
  hedge each other.

  Background:
    Given an SPX at 7500
    And a rate of 0.045

  Scenario Outline: A call's delta is positive and a put's negative
    Given a <right> struck at <strike>
    And 4 days to expiry
    And a vol of 0.18
    Then the delta is <sign>

    Examples:
      | right | strike | sign     |
      | call  | 7300   | positive |
      | call  | 7700   | positive |
      | put   | 7300   | negative |
      | put   | 7700   | negative |

  Scenario Outline: Deep in the money and about to expire, a delta is all or nothing
    Given a <right> struck at <strike>
    And 0.27 days to expiry
    And a vol of 0.12
    Then the delta is <delta> within 0.005

    Examples:
      | right | strike | delta |
      | call  | 7300   | 1     |
      | put   | 7700   | -1    |
      | call  | 8000   | 0     |
      | put   | 7000   | 0     |

  Scenario: At the money, a call and a put hedge each other
    Given a call struck at 7500
    And 0.27 days to expiry
    And a vol of 0.12
    Then the call and put deltas sum to 0 within 0.02
