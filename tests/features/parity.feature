Feature: The greeks agree with the library a trading bot trades by

  tests/data/options_bot_greeks.csv holds 36 contracts priced and
  inverted by the Go library a production trading bot calls, at a rate
  of 0.045.  The suite walks every row; these tell the story of the
  regimes, each row named as the fixture names it.

  Scenario Outline: Where the library found the vol, the greeks find the same one
    Given the fixture row <case> <right>
    Then its implied vol matches the fixture's within 0.002
    And its delta matches the fixture's within 0.005

    Examples:
      | case             | right |
      | 0dte_calm_otm    | CALL  |
      | 0dte_calm_atm    | CALL  |
      | 0dte_calm_itm    | PUT   |
      | 4dte_otm         | CALL  |
      | 4dte_atm         | PUT   |
      | 4dte_deep        | PUT   |
      | 8dte_badseed_atm | CALL  |
      | xsp_atm          | PUT   |

  Scenario Outline: Where the vol cannot be found, the greeks say why and the delta still agrees
    Given the fixture row <case> <right>
    When the vol it implies is sought
    Then the implied vol is <quality>
    And its delta matches the fixture's within 0.005

    Examples:
      | case            | right | quality |
      | 0dte_calm_deep  | CALL  | faint   |
      | at_intrinsic    | CALL  | clamped |
      | below_intrinsic | PUT   | clamped |
      | zero_premium    | CALL  | clamped |
