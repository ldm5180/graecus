Feature: A premium is a price, never a debt

  The greeks price European index options -- SPX, SPXW, XSP -- by
  Black-Scholes.  A contract is a spot, a strike and its right, the
  time to expiry, a vol and a rate; every check prices it as it stands.

  Background:
    Given an SPX at 7500
    And a rate of 0.045

  Scenario Outline: Four days out, an option is worth at least its intrinsic value
    Given a <right> struck at <strike>
    And 4 days to expiry
    And a vol of 0.18
    Then the price is at least <intrinsic>

    Examples:
      | right | strike | intrinsic |
      | call  | 7300   | 200       |
      | call  | 7700   | 0         |
      | put   | 7700   | 200       |
      | put   | 7300   | 0         |

  Scenario: Far out of the money and about to expire, a call is worth nothing
    Given a call struck at 8000
    And 0.27 days to expiry
    And a vol of 0.12
    Then the price is 0 within 0.0001

  Scenario: Deep in the money and about to expire, a put is worth a little under intrinsic
    Its strike is paid at expiry, so the money is worth its discount.

    Given a put struck at 7700
    And 0.27 days to expiry
    And a vol of 0.12
    Then the price is 199.74 within 0.01

  Scenario: A vol outside the envelope is refused, not clamped
    Then a vol of 7 is refused
    And a vol of 0.0001 is refused
