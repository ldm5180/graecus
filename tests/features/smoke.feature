Feature: The feature runner runs

  Scenario: Dollars are summed
    Given nothing has been priced
    When 3 dollars are added
    And 4 dollars are added
    Then the total is 7 dollars
