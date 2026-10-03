--  The fixture, by name (parity.feature): a row's contract loaded, and
--  the vol and delta the Go library answered for it matched.
--  A region of the registry: Offer takes this feature's steps, Reset
--  starts a scenario, Phase names its state.

package Graecus_Steps.Parity is

   procedure Offer
     (Ctx : in out Step_Context; Evt : Step_Kind; Handled : out Boolean);

   procedure Reset;

   function Phase return String;

end Graecus_Steps.Parity;
