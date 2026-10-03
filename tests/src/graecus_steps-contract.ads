--  The contract a scenario composes (pricing.feature and every feature
--  that prices): a spot, a strike and its right, days to expiry, a vol
--  and a rate, each refused outside the crate's envelope for it.
--  A region of the registry: Offer takes this feature's steps, Reset
--  starts a scenario, Phase names its state.

package Graecus_Steps.Contract is

   procedure Offer
     (Ctx : in out Step_Context; Evt : Step_Kind; Handled : out Boolean);

   procedure Reset;

   function Phase return String;

end Graecus_Steps.Contract;
