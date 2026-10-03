--  What a scenario and the parity test share: the fixture file the
--  options_bot library dumped, and how one of its lines splits.

package Graecus_World is

   --  The 36-row parity fixture, relative to the crate root.
   Fixture_Path : constant String := "tests/data/options_bot_greeks.csv";

   --  The Nth comma-separated field of a fixture line; "" past the last.
   function Field (Line : String; N : Positive) return String;

end Graecus_World;
